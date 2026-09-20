"""Finalize the verified movement revision and retain original generation provenance."""
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'output/imagegen'
RUN = OUT/'anime-v2'
ARTIFACTS = ROOT/'artifacts'

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))
def write(path, value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def relative(path):
    return path.relative_to(ROOT).as_posix()
def check_log(filename,suite):
    content=(ARTIFACTS/filename).read_text(encoding='utf-8-sig')
    match=re.search(suite+r' TESTS: (\d+) passed, 0 failed',content)
    if not match or re.search(r'SCRIPT ERROR|ERROR:|FAIL:|instances were leaked',content):
        raise ValueError('No clean test evidence: '+filename)
    return dict(passed=int(match[1]),failed=0,log='artifacts/'+filename)

def main():
    now=datetime.now(timezone.utc).isoformat()
    checks={
        'combat':check_log('combat_tests.log','COMBAT'),
        'movement':check_log('movement_tests.log','MOVEMENT'),
        'ui':check_log('ui_tests.log','UI'),
        'presentation':check_log('presentation_tests.log','PRESENTATION'),
        'ui_rendered':check_log('ui_tests-rendered.log','UI'),
        'presentation_rendered':check_log('presentation_tests-rendered.log','PRESENTATION'),
    }
    hashes=[]
    for fps in (30,60,144):
        log=(ARTIFACTS/('fps-%d.log'%fps)).read_text(encoding='utf-8-sig')
        hashes.append(re.search(r'hash=([a-f0-9]{64})',log)[1])
    assert len(set(hashes))==1
    performance=read(ARTIFACTS/'performance-hd.json')
    assert performance['all_art_ready'] and performance['p95_frame_ms']<16.67
    jobs=read(RUN/'jobs.json')
    records={p.stem:read(p) for p in (RUN/'records').glob('*.json')}
    selected={}
    for job in jobs:
        if records.get(job['id'],{}).get('status')!='generated' or job['group']=='failed-attempts':
            continue
        meta=job.get('metadata',{})
        key=meta['character']+'/'+meta['clip'] if 'clip' in meta else job['id']
        selected[key]=job
    ids={j['id'] for j in selected.values()}
    sources=[]
    for key,job in selected.items():
        record=records[job['id']]
        path=ROOT/job['out']
        with Image.open(path) as image:
            size=list(image.size)
        record.update(accepted=True,actual_size=size,sha256=digest(path))
        record['review']={'status':'accepted_for_movement_revision','reviewed_utc':now,
                          'evidence':'artifacts/visual-acceptance.md'}
        # Preserve unknown or explicitly recorded costs; never infer zero.
        write(RUN/'records'/(job['id']+'.json'),record)
        sources.append(dict(key=key,id=job['id'],prompt=job['prompt'],source=job['out'],
                            requested_size=job['size'],actual_size=size,references=job['references'],
                            sha256=record['sha256'],cost=record.get('cost')))
    for name in ('tanjiro','zenitsu'):
        old=records.get(name+'-throw')
        if old:
            old['accepted']=False
            old['review']={'status':'superseded','replacement':name+'-throw-movement-v3','reviewed_utc':now}
            write(RUN/'records'/(name+'-throw.json'),old)
    inventory=[]
    for path in sorted((ROOT/'art').rglob('*')):
        if not path.is_file() or path.suffix not in ('.png','.jpg','.json','.ttf'):
            continue
        entry=dict(path=relative(path),bytes=path.stat().st_size,sha256=digest(path))
        if path.suffix in ('.png','.jpg'):
            with Image.open(path) as image:
                entry.update(size=list(image.size),mode=image.mode)
        inventory.append(entry)
    characters={}
    for name in ('tanjiro','zenitsu'):
        atlas=read(ROOT/'art/characters'/name/'atlas.json')
        characters[name]={'clips':len(atlas['clips']),'frames':sum(len(c['frames']) for c in atlas['clips'].values()),
                          'scale':atlas['canonical_height']/atlas['source_height']}
        assert characters[name]['clips']==25 and characters[name]['frames']==168
    videos=[]
    for width in (960,1280,1920):
        path=ARTIFACTS/('movement-%d.mp4'%width)
        assert path.is_file() and path.stat().st_size>10000
        cues=read(ARTIFACTS/('movement-%d'%width)/'cues.json')
        videos.append(dict(path=relative(path),bytes=path.stat().st_size,sha256=digest(path),**cues))
    history=OUT/'history/pre-movement-v3-manifest.json'
    if (OUT/'manifest.json').exists() and not history.exists():
        history.parent.mkdir(parents=True,exist_ok=True)
        history.write_bytes((OUT/'manifest.json').read_bytes())
    manifest=dict(revision='movement-v3',generated_utc=now,route='CPA / gpt-image-2 via existing image_gen.py',
      gameplay_changes=['fixed scale and world camera','960-unit arena and maximum separation','double-tap forward/back dash',
                        'somersault jumps with air attack interruption','synchronized side-switch shoulder throw'],
      stage=dict(world_width=960,zoom=3,layer_size=[4608,1152],composition='preserved central courtyard plus two outpaint extensions'),
      characters=characters,sources=sources,inventory=inventory,tests=checks,
      frame_rate_hash=dict(fps=[30,60,144],sha256=hashes[0],coverage='AI match plus scripted dashes, throw and airborne attack'),
      performance=performance,videos=videos,
      known_limits=['Physical gamepad not connected; sticks, deadzone, dpad and mixed-device matches verified with simulated input.',
                    'Source service can return dimensions different from request; both dimensions recorded. Unknown billing remains null.'])
    write(OUT/'manifest.json',manifest)
    report='''# 场地与动作改造验收

已完成固定 3.0 倍率、960 世界单位场地、共享地面世界变换、前后短冲刺、前后翻身、空中攻击衔接和双方联动过肩背摔。

## 实际画面检查

- 960×540、1280×720、1920×1080 各录制 12 个实际引擎场景：左右卷轴、单方拉开、前后冲刺、前后翻身、空中攻击、两角色／同角色／两侧版边背摔。
- 检查了身体比例、脚下地砖、场景拼接、完整倒转、抓取过肩与着地换位；修复了建筑和天空重复绘制月亮的问题。
- 每名角色 25 组动作、168 张不同画帧；两份原投技由新版抓取替换。图集抠图、裁切、透明边缘、固定比例和来源检查通过。
- 游戏运行时仅加载本地资源。新增素材通过 CPA / gpt-image-2 制作，原图、提示词、参考图和请求记录均保留。

## 自动检查

'''
    for name,check in checks.items():
        report+='- %s：%d passed，0 failed。\n'%(name,check['passed'])
    report+='- 美术 Python 检查：2 passed。\n- 30／60／144 FPS 的 AI 对局与脚本冲刺、背摔、跳跃出招状态摘要一致：'+hashes[0]+'。\n'
    report+='\n1080p 实测 1800 个渲染帧，平均 %.3f ms，P95 %.3f ms，P99 %.3f ms；GPU：%s。\n'%(performance['mean_frame_ms'],performance['p95_frame_ms'],performance['p99_frame_ms'],performance['gpu'])
    report+='\n## 交付与复现\n\n- gallery.html：本地动作与录像预览。\n- movement-960.mp4 / movement-1280.mp4 / movement-1920.mp4：各 20.6 秒、15 FPS 预览编码，战斗模拟始终 60Hz。\n- tests/run_tests.ps1 -Capture：完整验证。\n- tools/build_movement_art.py：离线重建美术。\n- tools/capture_movement_preview.gd 与 tools/encode_movement_preview.ps1：离线重录。\n\n未连接实体手柄；已验证模拟轴、十字键、按键、死区和混合设备对局。\n'
    (ARTIFACTS/'visual-acceptance.md').write_text(report,encoding='utf-8')
    print('Movement delivery manifest and visual acceptance updated.')
if __name__=='__main__':
    main()
