"""Bounded intermediate storage for Godot review captures (not game assets).

Called by capture_output.gd. Encode small PNG batches, verify every frame, then
remove only those intermediates. --keep-frames in Godot preserves lossless PNGs.
"""
import argparse
import ctypes
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FRAME = re.compile(r'(?:frame-\d+|t\d+)\.png$')
MARKER = '.capture-active.json'
PARTS = '.capture-parts'


def local(path):
    """Reject links, junctions and paths outside the disposable artifact tree."""
    path = Path(os.path.abspath(path))
    boundary = ROOT / 'artifacts'
    if path == boundary or boundary not in path.parents:
        raise ValueError(f'Not a capture path: {path}')
    for item in [path, *path.parents]:
        if item == ROOT:
            break
        if item.exists() or item.is_symlink():
            info = item.lstat()
            if item.is_symlink() or getattr(info, 'st_file_attributes', 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT:
                raise ValueError(f'Refusing linked path: {item}')
    if boundary.resolve() not in path.resolve().parents:
        raise ValueError(f'Capture path escaped artifacts: {path}')
    return path


def tracked_files():
    result = subprocess.run(['git', '-C', str(ROOT), 'ls-files', '-z'], check=True, capture_output=True)
    return {os.path.normcase(str(ROOT / name.decode('utf-8'))) for name in result.stdout.split(b'\0') if name}


def writable(path, tracked):
    path = local(path)
    if os.path.normcase(str(path)) in tracked:
        raise ValueError(f'Refusing tracked file: {path}')
    return path


def remove(paths, tracked):
    paths = [writable(p, tracked) for p in paths]
    for path in paths:
        path.unlink(missing_ok=True)


def frame_paths(folder):
    return sorted((p for p in folder.iterdir() if FRAME.fullmatch(p.name)),
                  key=lambda p: int(re.search(r'\d+', p.name).group()))


def codecs():
    result = [shutil.which(name) for name in ('ffmpeg', 'ffprobe')]
    if not all(result):
        raise RuntimeError('Install ffmpeg and ffprobe on PATH, or use --keep-frames for bounded PNG capture.')
    return result


def verify(video, expected, ffprobe):
    result = subprocess.run([ffprobe, '-v', 'error', '-select_streams', 'v:0', '-count_frames',
                             '-show_entries', 'stream=nb_read_frames', '-of', 'json', str(video)],
                            check=True, capture_output=True, text=True)
    streams = json.loads(result.stdout)['streams']
    if result.stderr.strip() or not video.is_file() or video.stat().st_size == 0 or len(streams) != 1 or int(streams[0]['nb_read_frames']) != expected:
        raise RuntimeError(f'Encoded frame verification failed: {video} (expected {expected})')


def save_state(folder, state, tracked):
    # Replace atomically: a capture killed mid-write must not leave a truncated
    # marker behind.
    pending = writable(folder / (MARKER + '.tmp'), tracked)
    pending.write_text(json.dumps(state, indent=2), encoding='utf-8')
    os.replace(pending, writable(folder / MARKER, tracked))


def process_started(pid):
    """Creation time (FILETIME) of a running process, or None.

    A marker stores it next to the PID, so a recycled PID is not mistaken for
    the capture. OpenProcess is read-only; os.kill(pid, 0) is unsafe on Windows.
    """
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.OpenProcess.restype = ctypes.c_void_p
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    kernel.GetExitCodeProcess.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong)]
    kernel.GetProcessTimes.argtypes = [ctypes.c_void_p] + [ctypes.POINTER(ctypes.c_ulonglong)] * 4
    handle = kernel.OpenProcess(0x1000, False, pid)
    if not handle:
        return None  # Exited, or a protected system process that cannot be a capture.
    try:
        code = ctypes.c_ulong()
        times = [ctypes.c_ulonglong() for _ in range(4)]
        if not kernel.GetExitCodeProcess(handle, ctypes.byref(code)) or code.value != 259:
            return None
        if not kernel.GetProcessTimes(handle, *(ctypes.byref(t) for t in times)):
            return None
        return times[0].value
    finally:
        kernel.CloseHandle(handle)


def read_marker(folder):
    """The marker's owner; None when it is absent, unreadable or incomplete."""
    path = local(folder / MARKER)
    try:
        marker = json.loads(path.read_text(encoding='utf-8'))
        return dict(pid=int(marker['pid']), started=int(marker['started']))
    except (OSError, ValueError, KeyError, TypeError):
        return None


def owner_alive(owner):
    return owner is not None and owner['pid'] > 0 and process_started(owner['pid']) == owner['started']


def maintain_artifacts():
    result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                             str(ROOT / 'tools/clean-local.ps1'), '-Apply', '-RetainRecent'], check=True,
                            capture_output=True, text=True, errors='replace')
    # Report evictions and budget warnings; the summary object stays quiet.
    for line in result.stdout.splitlines():
        if line.startswith(('Artifact retention', 'WARNING:')):
            print(line)


def prepare(folder, pid, fps, keep_frames=False, maintain=False):
    folder = local(folder)
    if fps <= 0 or fps > 60:
        raise ValueError('Capture FPS must be in (0, 60].')
    owner = read_marker(folder)
    if owner_alive(owner):
        raise RuntimeError(f"Capture directory is already active (PID {owner['pid']}): {folder}")
    started = process_started(pid)
    if started is None:
        raise RuntimeError(f'Capture owner process is not running (PID {pid}).')
    if not keep_frames:
        codecs()  # Fail before producing a large PNG batch.
    if maintain:
        maintain_artifacts()
    tracked = tracked_files()
    folder.mkdir(parents=True, exist_ok=True)
    stale = frame_paths(folder) + [folder / (MARKER + '.tmp')]
    parts = local(folder / PARTS)
    if parts.exists():
        # Only files produced by this encoder may be recycled.
        stale += [p for p in parts.iterdir() if re.fullmatch(r'part-\d+\.mp4|pending\.mp4|concat\.txt', p.name)]
    remove(stale, tracked)
    writable(folder / 'capture.mp4', tracked)  # Keep previous result until success.
    save_state(folder, dict(pid=pid, started=started, fps=fps, parts=[], frames=0, keep_frames=keep_frames), tracked)


def encode(folder):
    folder = local(folder)
    state = json.loads((folder / MARKER).read_text(encoding='utf-8'))
    frames = frame_paths(folder)
    if not frames:
        return
    tracked = tracked_files()
    for frame in frames:
        writable(frame, tracked)
    ffmpeg, ffprobe = codecs()
    parts = local(folder / PARTS)
    parts.mkdir(exist_ok=True)
    pending = writable(parts / 'pending.mp4', tracked)
    target = writable(parts / f"part-{len(state['parts']):05d}.mp4", tracked)
    try:
        # No second staging copy. The pipe accepts PNGs even when tick numbers
        # are sparse (--every=2); fps is 60/every, preserving real playback time.
        command = [ffmpeg, '-v', 'error', '-y', '-f', 'image2pipe', '-framerate', str(state['fps']),
                   '-i', 'pipe:0', '-an', '-c:v', 'libx264', '-preset', 'fast', '-crf', '18',
                   '-pix_fmt', 'yuv420p', str(pending)]
        with subprocess.Popen(command, stdin=subprocess.PIPE) as process:
            try:
                for frame in frames:
                    process.stdin.write(frame.read_bytes())
            finally:
                process.stdin.close()
            if process.wait() != 0:
                raise RuntimeError('ffmpeg failed; raw frames have been retained.')
        verify(pending, len(frames), ffprobe)
        encoded_bytes = pending.stat().st_size + sum(p.stat().st_size for p in parts.glob('part-*.mp4'))
        if encoded_bytes > 512 * 1024 * 1024:
            raise RuntimeError('Encoded capture exceeded 512 MiB; split the sequence. Raw frames retained.')
        pending.replace(target)
        state['parts'].append(target.name)
        state['frames'] += len(frames)
        save_state(folder, state, tracked)
        remove(frames, tracked)
    finally:
        remove([pending], tracked)


def finish(folder):
    folder = local(folder)
    state = json.loads((folder / MARKER).read_text(encoding='utf-8'))
    tracked = tracked_files()
    if state['keep_frames']:
        state['frames'] = len(frame_paths(folder))
        # These frames are now the result; an older capture.mp4 would be stale.
        remove([folder / 'capture.mp4'], tracked)
        write_report(folder, state, tracked)
        remove([folder / MARKER], tracked)
        print(f'Lossless frames retained: {folder}')
        return
    encode(folder)
    state = json.loads((folder / MARKER).read_text(encoding='utf-8'))
    if not state['parts']:
        raise RuntimeError('Capture produced no frames.')
    ffmpeg, ffprobe = codecs()
    parts = local(folder / PARTS)
    listing = writable(parts / 'concat.txt', tracked)
    pending = writable(parts / 'pending.mp4', tracked)
    target = writable(folder / 'capture.mp4', tracked)
    if any(not re.fullmatch(r'part-\d+\.mp4', name) for name in state['parts']):
        raise ValueError('Invalid capture part name')
    inputs = [local(parts / name) for name in state['parts']]
    listing.write_text(''.join(f"file '{p.name}'\n" for p in inputs), encoding='utf-8')
    try:
        subprocess.run([ffmpeg, '-v', 'error', '-y', '-f', 'concat', '-safe', '1', '-i', str(listing),
                        '-c', 'copy', '-movflags', '+faststart', str(pending)], check=True)
        verify(pending, state['frames'], ffprobe)
        pending.replace(target)
        write_report(folder, state, tracked)
        remove(inputs + [listing, folder / MARKER], tracked)
        print(f"CAPTURE VIDEO: {target} ({state['frames']} frames at {state['fps']} FPS)")
    finally:
        remove([pending], tracked)
    if not any(parts.iterdir()):
        parts.rmdir()


def write_report(folder, state, tracked):
    report = dict(fps=state['fps'], frames=state['frames'], keep_frames=state['keep_frames'],
                  generated_utc=datetime.now(timezone.utc).isoformat())
    writable(folder / 'capture.json', tracked).write_text(json.dumps(report, indent=2), encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['prepare', 'encode', 'finish'])
    parser.add_argument('folder', type=Path)
    parser.add_argument('--pid', type=int, default=os.getpid())
    parser.add_argument('--fps', type=float, default=60)
    parser.add_argument('--keep-frames', action='store_true')
    parser.add_argument('--maintain', action='store_true')
    args = parser.parse_args()
    if args.command == 'prepare':
        prepare(args.folder, args.pid, args.fps, args.keep_frames, args.maintain)
    elif args.command == 'encode':
        encode(args.folder)
    else:
        finish(args.folder)


if __name__ == '__main__':
    main()
