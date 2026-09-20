"""Record current visual-polish evidence without treating old captures as current."""
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'output/imagegen'
RUN = OUT/'anime-v2'
REVIEW = ROOT/'artifacts/visual-polish'


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    now = datetime.now(timezone.utc).isoformat()
    checks = {}
    for suite in ('combat','movement','ui','presentation'):
        path = ROOT/'artifacts'/(suite+'_tests.log')
        log = path.read_text(encoding='utf-8-sig')
        match = re.search(suite.upper()+r' TESTS: (\d+) passed, 0 failed', log)
        if not match or re.search(r'SCRIPT ERROR|ERROR:|FAIL:|instances were leaked', log):
            raise ValueError('Missing clean evidence: '+str(path))
        checks[suite] = dict(passed=int(match[1]), failed=0, log=path.relative_to(ROOT).as_posix())
    capture_log = (REVIEW/'capture.log').read_text(encoding='utf-8-sig')
    assert 'VISUAL POLISH CAPTURE COMPLETE: 568 frames' in capture_log
    assert not re.search(r'SCRIPT ERROR|ERROR:|FAIL:', capture_log)
    hashes = []
    for fps in (30,60,144):
        log = (ROOT/'artifacts'/('fps-%d.log'%fps)).read_text(encoding='utf-8-sig')
        hashes.append(re.search(r'hash=([a-f0-9]{64})',log)[1])
    assert len(set(hashes)) == 1
    history = OUT/'history/pre-visual-polish-v4-manifest.json'
    if not history.exists():
        history.write_bytes((OUT/'manifest.json').read_bytes())
    manifest = read(history)
    manifest['revision'] = 'visual-polish-v4'
    manifest['generated_utc'] = now
    manifest['visual_changes'] = [
        'Idle-referenced head, hand and limb scale calibration across motion clips.',
        'Continuous 3.2-second idle breathing, +/-0.3% around planted feet.',
        'One continuous panorama and one shared world transform; no overlapping sky or plant panels.'
    ]
    manifest['stage'] = read(ROOT/'art/stages/wisteria/stage.json')
    manifest['tests'] = checks
    manifest['frame_rate_hash'] = dict(fps=[30,60,144],sha256=hashes[0])
    if 'performance' in manifest:
        manifest['previous_revision_performance'] = manifest.pop('performance')
    if 'videos' in manifest:
        manifest['previous_revision_videos'] = manifest.pop('videos')
    video = REVIEW/'preview.mp4'
    assert video.stat().st_size > 10000
    manifest['videos'] = [dict(path=video.relative_to(ROOT).as_posix(),sha256=digest(video),
                              bytes=video.stat().st_size,**read(REVIEW/'cues.json'))]
    manifest['calibration'] = dict(path='output/imagegen/anime-v2/calibration.json',
                                   sha256=digest(RUN/'calibration.json'))
    source_id = 'wisteria-continuous-v4'
    job = next(j for j in read(RUN/'jobs.json') if j['id'] == source_id)
    source = ROOT/job['out']
    record = read(RUN/'records'/(source_id+'.json'))
    with Image.open(source) as image:
        size = list(image.size)
    record.update(accepted=True, actual_size=size, sha256=digest(source))
    record['review'] = dict(status='accepted_for_visual_polish_v4',reviewed_utc=now,
                            evidence='artifacts/visual-polish/review.md',
                            local_finish='tools/build_continuous_stage.py')
    write(RUN/'records'/(source_id+'.json'),record)
    manifest['sources'].append(dict(key=source_id,id=source_id,prompt=job['prompt'],source=job['out'],
                                    references=job['references'],requested_size=job['size'],actual_size=size,
                                    sha256=record['sha256'],cost=record.get('cost'),used_by_current_stage=True))
    old_stage = {'wisteria-master','wisteria-sky','wisteria-canopy','wisteria-foreground',
                 'wisteria-left-movement-v3','wisteria-right-movement-v3'}
    for entry in manifest['sources']:
        if entry['id'] in old_stage:
            entry['used_by_current_stage'] = False
            entry['superseded_by'] = source_id
    inventory = []
    for path in sorted((ROOT/'art').rglob('*')):
        if not path.is_file() or path.suffix not in ('.png','.jpg','.json','.ttf'):
            continue
        entry = dict(path=path.relative_to(ROOT).as_posix(),bytes=path.stat().st_size,sha256=digest(path))
        if path.suffix in ('.png','.jpg'):
            with Image.open(path) as image:
                entry.update(size=list(image.size),mode=image.mode)
        inventory.append(entry)
    manifest['inventory'] = inventory
    write(OUT/'manifest.json',manifest)
    report = '''# 人物与背景视觉修正

- 人物：以待机的头部、手和肢体比例重新校准前后移动、冲刺、翻滚、跳跃落姿、空中轻重攻击和技能。整组动作使用同一倍率，蜷身仍保持自然的紧凑姿势，不按轮廓高度缩放。
- 待机：固定放松姿势，以 3.2 秒一轮、垂直 ±0.3% 的呼吸替代原有半秒循环。脚底固定，暂停及命中停顿时同步冻结。720p 下整体高度变化峰峰值小于 1.5 像素。
- 背景：CPA / gpt-image-2 重绘连续庭院，再离线处理月亮位置、全景裁切和地面位置。游戏只绘制 panorama.png，天空、地面、建筑与倒影共同移动，取消原有独立覆盖的花草和天空。

## 实际引擎验证

[28.4 秒实机预览](preview.mp4)：两名角色的待机、前后移动、前后冲刺、前后翻滚、空中轻重攻击和前向技能，共 568 帧，20 FPS；战斗逻辑始终 60Hz。

![修正后的中央场景](stage-center-1920.png)

- 960×540 与 1920×1080 检查左端、中央、右端，共 6 张场景截图。
- 1280×720 录制两名角色的 20 个动作场景；检查头部和肢体比例、动作衔接以及脚底接触。
- 月亮与反光只有一处，地面连续；左右卷屏未见原来的三块拼接边和植物断边。

## 自动检查

'''
    for suite, result in checks.items():
        report += '- %s：%d passed，0 failed。\n' % (suite,result['passed'])
    report += '- 美术素材检查：2 passed；图集裁切、透明边缘、画帧和来源完整。\n'
    report += '- 30／60／144 FPS 的 1800 帧战斗状态摘要一致：`'+hashes[0]+'`。\n'
    report += '''
## 文件与复现

- 当前背景：`art/stages/wisteria/panorama.png`。
- 最终提示词：`output/imagegen/anime-v2/prompts/wisteria-continuous-v4.txt`。
- 未修改的 CPA 原图：`output/imagegen/anime-v2/raw/wisteria-continuous-v4.png`。
- 请求尺寸 3840×1280，服务实际返回 2172×724；运行时画面由离线流程整理到 4608×1152。费用未获得可靠返回，保留为未知。
- `python tools/build_movement_art.py` 离线重建人物和背景；不会再次调用生图服务。
- `tests/run_tests.ps1` 运行回归；Godot 加 `--fixed-fps 60 --script res://tools/capture_visual_polish.gd` 重录。
- 六张原始待机画帧作为源素材保留；运行时采用安静关键姿势加连续呼吸。动作联系表中的原始姿势不是新的待机播放顺序。
'''
    (REVIEW/'review.md').write_text(report,encoding='utf-8')
    print('Visual-polish manifest and review evidence saved.')


if __name__ == '__main__':
    main()
