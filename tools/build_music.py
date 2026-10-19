"""Game BGM: loudness-matched Vorbis files plus helpers for choosing cue points.

Sources and provenance live in output/music/ (sources.json, source/<id>.m4a). The game reads
art/music/<id>.ogg and the cue table in resources/music/library.json; see docs/music.md.

  .venv\\Scripts\\python.exe -X utf8 tools/build_music.py [--only homura_movie]
  .venv\\Scripts\\python.exe -X utf8 tools/build_music.py --profile rengoku_kyojuro
  .venv\\Scripts\\python.exe -X utf8 tools/build_music.py --suggest-loops rengoku_kyojuro [--scene battle]
  .venv\\Scripts\\python.exe -X utf8 tools/build_music.py --preview rengoku_kyojuro [--scene battle]

The default build measures each source (EBU R128), applies one static gain to reach
TARGET_LUFS, encodes Vorbis, re-measures the result and writes each duration back to the
library. Previews and loop suggestions go to artifacts/music/ and stdout.
"""
import argparse
import concurrent.futures
import json
import re
import shutil
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'output/music'
LIBRARY = ROOT / 'resources/music/library.json'
ASSETS = ROOT / 'art/music'
REVIEW = ROOT / 'artifacts/music'

TARGET_LUFS = -16.0       # integrated loudness of every game file
TRUE_PEAK_CEILING = -1.5  # dBTP; a static gain must not push past this
LOUDNESS_TOLERANCE = 0.5  # LU allowed between target and the encoded result
VORBIS_QUALITY = '5'      # same as the cinematic soundtracks
ANALYSIS_RATE = 22050     # mono rate for loop analysis
HOP = 512                 # analysis hop (~23 ms)
SEARCH = 6.0              # seconds either side of an authored loop point
LEVEL_PENALTY = 0.03      # similarity lost per dB between the two crossfaded windows
PREVIEW_LEAD = 8.0        # seconds of context around a previewed seam


def ffmpeg() -> str:
    path = shutil.which('ffmpeg')
    if not path or not shutil.which('ffprobe'):
        raise SystemExit('ffmpeg and ffprobe must be on PATH')
    return path


def loudness(path: Path) -> dict:
    """Integrated loudness, loudness range and true peak from ffmpeg's ebur128 summary."""
    result = subprocess.run([ffmpeg(), '-hide_banner', '-nostats', '-i', str(path), '-af', 'ebur128=peak=true', '-f', 'null', '-'],
                            capture_output=True, text=True, encoding='utf-8', errors='replace', check=True)
    summary = result.stderr[result.stderr.rfind('Summary:'):]
    def value(pattern: str) -> float:
        match = re.search(pattern, summary)
        if not match:
            raise SystemExit(f'cannot parse loudness of {path}')
        return float(match.group(1))
    return {'integrated': value(r'I:\s+(-?[\d.]+) LUFS'), 'range': value(r'LRA:\s+(-?[\d.]+) LU'), 'true_peak': value(r'Peak:\s+(-?[\d.]+) dBFS')}


def duration(path: Path) -> float:
    result = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(path)],
                            capture_output=True, text=True, check=True)
    return float(result.stdout.strip())


def decode(path: Path, rate: int, channels: int) -> np.ndarray:
    """Float32 samples shaped (frames, channels)."""
    result = subprocess.run([ffmpeg(), '-v', 'error', '-i', str(path), '-f', 'f32le', '-ac', str(channels), '-ar', str(rate), '-'],
                            capture_output=True, check=True)
    return np.frombuffer(result.stdout, dtype='<f4').reshape(-1, channels)


def load_sources() -> list:
    return json.loads((SOURCES / 'sources.json').read_text(encoding='utf-8'))['tracks']


def load_library() -> dict:
    return json.loads(LIBRARY.read_text(encoding='utf-8'))


def save_library(library: dict) -> None:
    LIBRARY.write_text(json.dumps(library, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def build(only: set) -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    tracks = [track for track in load_sources() if not only or track['id'] in only]
    def encode(track: dict) -> dict:
        source = SOURCES / track['file']
        target = ASSETS / f"{track['id']}.ogg"
        before = loudness(source)
        gain = TARGET_LUFS - before['integrated']
        if before['true_peak'] + gain > TRUE_PEAK_CEILING:
            gain = TRUE_PEAK_CEILING - before['true_peak']
        subprocess.run([ffmpeg(), '-v', 'error', '-y', '-i', str(source), '-map', '0:a:0', '-map_metadata', '-1',
                        '-af', f'volume={gain:.2f}dB', '-c:a', 'libvorbis', '-q:a', VORBIS_QUALITY, str(target)], check=True)
        after = loudness(target)
        print(f"{track['id']}: {before['integrated']:+.1f} -> {after['integrated']:+.1f} LUFS, peak {after['true_peak']:+.1f} dBTP, gain {gain:+.2f} dB", flush=True)
        return {'id': track['id'], 'source': before, 'output': after, 'gain_db': round(gain, 2), 'duration': round(duration(target), 3),
                'bytes': target.stat().st_size}
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        reports = list(pool.map(encode, tracks))
    library = load_library()
    failures = []
    for report in reports:
        library['tracks'][report['id']]['duration'] = report['duration']
        if abs(report['output']['integrated'] - TARGET_LUFS) > LOUDNESS_TOLERANCE:
            failures.append(f"{report['id']} integrated {report['output']['integrated']} LUFS")
        if report['output']['true_peak'] > TRUE_PEAK_CEILING + 0.3:
            failures.append(f"{report['id']} true peak {report['output']['true_peak']} dBTP")
    save_library(library)
    path = SOURCES / 'build-report.json'
    previous = json.loads(path.read_text(encoding='utf-8')) if path.is_file() else {}
    merged = {track['id']: track for track in previous.get('tracks', [])}
    merged.update({report['id']: report for report in reports})
    order = [track['id'] for track in load_sources()]
    path.write_text(json.dumps({'target_lufs': TARGET_LUFS, 'true_peak_ceiling_dbtp': TRUE_PEAK_CEILING, 'vorbis_quality': int(VORBIS_QUALITY),
                                'tracks': [merged[key] for key in order if key in merged]}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    if failures:
        raise SystemExit('MUSIC BUILD FAILED: ' + '; '.join(failures))
    print(f'MUSIC READY: {len(reports)} tracks', flush=True)


def asset(track_id: str) -> Path:
    path = ASSETS / f'{track_id}.ogg'
    if not path.is_file():
        raise SystemExit(f'{path} is missing; run the build first')
    return path


def clock(seconds: float) -> str:
    return f'{int(seconds // 60)}:{seconds % 60:05.2f}'


def profile(track_id: str) -> None:
    """Short-term loudness every two seconds, with a bar for quick reading."""
    result = subprocess.run([ffmpeg(), '-hide_banner', '-nostats', '-i', str(asset(track_id)), '-af', 'ebur128', '-f', 'null', '-'],
                            capture_output=True, text=True, encoding='utf-8', errors='replace', check=True)
    following = 0.0
    for line in result.stderr.splitlines():
        match = re.search(r't:\s*([\d.]+).*?S:\s*(-?[\d.]+)', line)
        if match and float(match.group(1)) >= following:
            seconds, level = float(match.group(1)), float(match.group(2))
            print(f'{clock(seconds):>8}  {level:6.1f}  ' + '#' * max(0, int((level + 40) * 1.5)))
            following += 2.0


def features(samples: np.ndarray, rate: int) -> np.ndarray:
    """Per-hop chroma (12) plus a weighted onset strength column."""
    mono = samples[:, 0]
    size = 4096
    frames = 1 + (len(mono) - size) // HOP
    window = np.hanning(size).astype(np.float32)
    index = np.arange(size)[None, :] + HOP * np.arange(frames)[:, None]
    spectrum = np.abs(np.fft.rfft(mono[index] * window, axis=1))
    frequencies = np.fft.rfftfreq(size, 1.0 / rate)
    usable = (frequencies > 55) & (frequencies < 5000)
    pitch = np.round(12 * np.log2(frequencies[usable] / 440.0)).astype(int) % 12
    chroma = np.zeros((frames, 12), dtype=np.float32)
    for bin_class in range(12):
        chroma[:, bin_class] = spectrum[:, usable][:, pitch == bin_class].sum(axis=1)
    chroma /= np.linalg.norm(chroma, axis=1, keepdims=True) + 1e-9
    energy = np.log1p(spectrum.sum(axis=1))
    onset = np.maximum(0, np.diff(energy, prepend=energy[0]))
    onset /= onset.max() + 1e-9
    level = 10 * np.log10((mono[index] ** 2).mean(axis=1) + 1e-10)
    return np.hstack([chroma, onset[:, None] * 2.0, level[:, None]]).astype(np.float32)


def scene_cue(library: dict, track_id: str, scene: str) -> tuple:
    cues = library['tracks'][track_id]['cues']
    if scene not in cues:
        scene = next(iter(cues))
    return scene, cues[scene]


def suggest(track_id: str, scene: str) -> None:
    """Rank loop seams near the authored points by how alike the crossfaded windows are."""
    library = load_library()
    scene, cue = scene_cue(library, track_id, scene)
    fade = float(cue.get('crossfade', library['mix']['fades']['loop']))
    samples = decode(asset(track_id), ANALYSIS_RATE, 1)
    table = features(samples, ANALYSIS_RATE)
    per_second = ANALYSIS_RATE / HOP
    length = int(fade * per_second)
    def candidates(centre: float, after: bool) -> np.ndarray:
        low = max(0 if after else length, int((centre - SEARCH) * per_second))
        high = min(len(table) - (length if after else 0), int((centre + SEARCH) * per_second))
        return np.arange(low, max(low + 1, high))
    starts = candidates(float(cue['loop_start']), True)
    ends = candidates(float(cue['loop_end']), False)
    # The fade overlaps [end - fade, end] with [start, start + fade]; those windows should
    # match in harmony and rhythm (cosine) and in level (penalty per dB of difference).
    shape, level = table[:, :-1], table[:, -1]
    head = np.stack([shape[s:s + length].ravel() for s in starts])
    tail = np.stack([shape[e - length:e].ravel() for e in ends])
    head /= np.linalg.norm(head, axis=1, keepdims=True) + 1e-9
    tail /= np.linalg.norm(tail, axis=1, keepdims=True) + 1e-9
    head_level = np.array([level[s:s + length].mean() for s in starts])
    tail_level = np.array([level[e - length:e].mean() for e in ends])
    score = tail @ head.T - LEVEL_PENALTY * np.abs(tail_level[:, None] - head_level[None, :])
    best = np.dstack(np.unravel_index(np.argsort(score, axis=None)[::-1], score.shape))[0]
    print(f'{track_id} [{scene}] authored loop {clock(cue["loop_start"])} -> {clock(cue["loop_end"])}, fade {fade:.1f}s')
    shown = []
    for end_index, start_index in best:
        start, end = starts[start_index] / per_second, ends[end_index] / per_second
        if any(abs(start - s) < 0.4 and abs(end - e) < 0.4 for s, e in shown):
            continue
        shown.append((start, end))
        print(f'  loop_start {start:8.2f} ({clock(start)})  loop_end {end:8.2f} ({clock(end)})  similarity {score[end_index, start_index]:.3f}')
        if len(shown) == 5:
            break
    if 'climax' in cue:
        # A jump target reads best on a phrase entry: the largest one-second rise in level.
        second = int(per_second)
        centre = int(float(cue['climax']) * per_second)
        span = np.arange(max(second, centre - int(4 * per_second)), min(len(level) - second, centre + int(4 * per_second)))
        rise = np.array([level[i:i + second].mean() - level[i - second:i].mean() for i in span])
        entry = span[int(np.argmax(rise))] / per_second
        print(f'  climax {entry:8.2f} ({clock(entry)})  rise {rise.max():+.1f} dB (authored {clock(float(cue["climax"]))})')


def equal_power(first: np.ndarray, second: np.ndarray) -> np.ndarray:
    progress = np.linspace(0.0, 1.0, len(first), dtype=np.float32)[:, None]
    return first * np.cos(progress * np.pi / 2) + second * np.sin(progress * np.pi / 2)


def splice(samples: np.ndarray, rate: int, leave: float, enter: float, fade: float) -> np.ndarray:
    """What the game plays when it leaves `leave` and crossfades into `enter`."""
    lead, span = int(PREVIEW_LEAD * rate), int(fade * rate)
    leave_at, enter_at = int(leave * rate), int(enter * rate)
    before = samples[max(0, leave_at - span - lead):leave_at - span]
    blend = equal_power(samples[leave_at - span:leave_at], samples[enter_at:enter_at + span])
    after = samples[enter_at + span:enter_at + span + lead]
    return np.vstack([before, blend, after])


def write_wav(path: Path, samples: np.ndarray, rate: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), 'wb') as output:
        output.setnchannels(samples.shape[1])
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes((np.clip(samples, -1, 1) * 32767).astype('<i2').tobytes())
    print(f'wrote {path.relative_to(ROOT)}')


def preview(track_id: str, scene: str) -> None:
    library = load_library()
    scene, cue = scene_cue(library, track_id, scene)
    fades = library['mix']['fades']
    rate = 44100
    samples = decode(asset(track_id), rate, 2)
    loop_fade = float(cue.get('crossfade', fades['loop']))
    write_wav(REVIEW / f'{track_id}-{scene}-loop.wav', splice(samples, rate, float(cue['loop_end']), float(cue['loop_start']), loop_fade), rate)
    if 'climax' in cue:
        # A final round can begin anywhere; preview the jump from a point a minute into the loop.
        leave = min(float(cue['loop_end']) - 1.0, float(cue['start']) + 60.0)
        write_wav(REVIEW / f'{track_id}-{scene}-climax.wav', splice(samples, rate, leave, float(cue['climax']), float(fades['climax'])), rate)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--only', action='append', default=[], help='build only this track id (repeatable)')
    parser.add_argument('--profile', metavar='ID', help='print the short-term loudness curve of a built track')
    parser.add_argument('--suggest-loops', metavar='ID', help='rank loop seams near the authored loop points')
    parser.add_argument('--preview', metavar='ID', help='render loop and climax seams to artifacts/music/')
    parser.add_argument('--scene', default='battle', help='cue set for --suggest-loops/--preview (title, select, battle)')
    args = parser.parse_args()
    if args.profile:
        profile(args.profile)
    elif args.suggest_loops:
        suggest(args.suggest_loops, args.scene)
    elif args.preview:
        preview(args.preview, args.scene)
    else:
        build(set(args.only))


if __name__ == '__main__':
    sys.exit(main())
