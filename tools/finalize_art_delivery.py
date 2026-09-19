"""Record the reviewed local delivery without generating artwork or estimating costs."""
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/imagegen'
RUN = OUT / 'anime-v2'
ARTIFACTS = ROOT / 'artifacts'
BACKUP = ARTIFACTS / 'pre-anime-remake-20260919-202144'

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def relative(path):
    return path.relative_to(ROOT).as_posix()

def test_result(filename, suite):
    content = (ARTIFACTS / filename).read_text(encoding='utf-8-sig')
    match = re.search(suite + r' TESTS: (\d+) passed, 0 failed', content)
    if not match or re.search(r'SCRIPT ERROR|ERROR:|FAIL:|instances were leaked', content):
        raise ValueError('Missing clean final test evidence: ' + filename)
    return {'passed':int(match[1]), 'failed':0, 'log':'artifacts/' + filename}

def main():
    now = datetime.now(timezone.utc).isoformat()
    jobs = read(RUN / 'jobs.json')
    records = {p.stem:read(p) for p in (RUN/'records').glob('*.json')}
    selected = {}
    for job in jobs:
        record = records.get(job['id'], {})
        if record.get('status') != 'generated' or job['group'] == 'failed-attempts':
            continue
        meta = job.get('metadata', {})
        key = meta['character'] + '/' + meta['clip'] if 'clip' in meta else job['id']
        selected[key] = job
    if len(selected) != 50:
        raise ValueError('Expected 50 final art sources, got ' + str(len(selected)))
    for name in ('tanjiro', 'zenitsu'):
        assert selected[name+'/crouch_heavy']['id'] == name+'-crouch_heavy-v2'
    core = ['scripts/combat.gd','scripts/fighter_state.gd','scripts/input_router.gd',
            'scripts/ai_controller.gd','scripts/move_data.gd']
    core += [relative(p) for p in sorted((ROOT/'moves').glob('*.tres'))]
    comparison = []
    for path in core:
        same = digest(ROOT/path) == digest(BACKUP/path)
        comparison.append({'path':path,'unchanged':same,'sha256':digest(ROOT/path)})
        if not same:
            raise ValueError('Gameplay source differs from snapshot: ' + path)
    checks = {
        'combat':test_result('combat_tests.log','COMBAT'),
        'ui_headless':test_result('ui_tests.log','UI'),
        'ui_rendered':test_result('ui_tests-rendered.log','UI'),
        'presentation_headless':test_result('presentation_tests.log','PRESENTATION'),
        'presentation_rendered':test_result('presentation_tests-rendered.log','PRESENTATION'),
        'artwork_python':{'passed':2,'failed':0,'command':'.venv/Scripts/python.exe tests/art_pipeline_tests.py'}
    }
    hashes = []
    for fps in (30,60,144):
        log = (ARTIFACTS/('fps-{}.log'.format(fps))).read_text(encoding='utf-8-sig')
        hashes.append(re.search(r'hash=([a-f0-9]{64})',log)[1])
    assert len(set(hashes)) == 1
    performance = read(ARTIFACTS/'performance-hd.json')
    assert performance['all_art_ready'] and performance['p95_frame_ms'] < 16.67
    inventory = []
    for path in sorted((ROOT/'art').rglob('*')):
        if not path.is_file() or path.suffix not in ('.png','.jpg','.json','.ttf'):
            continue
        item = {'path':relative(path),'bytes':path.stat().st_size,'sha256':digest(path)}
        if path.suffix in ('.png','.jpg'):
            with Image.open(path) as image:
                item.update(size=list(image.size),mode=image.mode)
        inventory.append(item)
    # Preserve the previous generation-blocked manifest/brief as historical evidence.
    history = OUT/'history'
    history.mkdir(exist_ok=True)
    for src, name in [(OUT/'manifest.json','pre-cpa-manifest.json'),
                      (OUT/'prompts/production.md','pre-cpa-production.md')]:
        target = history/name
        if src.exists() and not target.exists():
            target.write_bytes(src.read_bytes())
    selected_ids = {j['id'] for j in selected.values()}
    superseded = []
    unknown = []
    for id, record in records.items():
        if record['status'] == 'generated':
            path = ROOT/record['output']
            with Image.open(path) as image:
                record['actual_size'] = list(image.size)
                record['source_mode'] = image.mode
                if 'A' in image.getbands():
                    record['source_alpha_range'] = list(image.getchannel('A').getextrema())
            record['sha256'] = digest(path)
            record['accepted'] = id in selected_ids
            record['review'] = {'status':'accepted_for_local_delivery' if id in selected_ids else 'superseded',
                                'reviewed_utc':now,'evidence':'artifacts/visual-acceptance.md'}
            if id not in selected_ids:
                superseded.append(id)
                job = next(j for j in jobs if j['id'] == id)
                meta = job['metadata']
                record['review']['replacement'] = selected[meta['character']+'/'+meta['clip']]['id']
        else:
            record['accepted'] = False
            record['review'] = {'status':'no_delivered_output','billing_status':'unknown',
                                'note':'Original synchronous request failed with gateway timeout. Explicit replacement request retained separately.'}
            unknown.append(id)
        record['cost'] = None
        write(RUN/'records'/(id+'.json'),record)
    character_info = {}
    for character in ('tanjiro','zenitsu'):
        atlas = read(ROOT/'art/characters'/character/'atlas.json')
        character_info[character] = {
            'clips':len(atlas['clips']),
            'frames':sum(len(c['frames']) for c in atlas['clips'].values()),
            'canvas_size':atlas['canvas_size'],'feet_anchor':atlas['feet_anchor'],
            'atlas_pages':sorted({f['texture'] for c in atlas['clips'].values() for f in c['frames']}),
            'sources':{clip:selected[character+'/'+clip]['id'] for clip in atlas['clips']}
        }
    manifest = {
        'project':'月下对决 / 精细动漫 UI 与美术重制','status':'implemented_and_locally_verified',
        'finalized_utc':now,'route':'CPA via project cpa-imagegen helper and unmodified installed image_gen.py',
        'model':'gpt-image-2','quality':'high','request_records':len(records),
        'successful_image_outputs':sum(r['status']=='generated' for r in records.values()),
        'accepted_source_images':len(selected_ids),'superseded_sources':sorted(superseded),
        'uncertain_requests':sorted(unknown),'api_spend_usd':None,'pricing_verified':False,
        'billing_note':'Unknown, including the two gateway-timeout attempts. No zero-cost claim or estimate.',
        'characters':character_info,
        'stage':{'layers':5,'runtime_size':[2048,1152],
                 'source_size':records['wisteria-master']['actual_size'],
                 'processing':'Registered master/sky plates and keyed canopy/foreground. Master source resampled to runtime size; temple and floor share a parallax transform.'},
        'sources':[{'id':id,'record':relative(RUN/'records'/(id+'.json')),
                    'prompt':records[id]['prompt'],'raw':records[id]['output'],
                    'actual_size':records[id]['actual_size'],'sha256':records[id]['sha256']}
                   for id in sorted(selected_ids)],
        'runtime_assets':inventory,'snapshot':relative(BACKUP),
        'gameplay_compatibility':{'all_unchanged':True,'files':comparison},
        'validation':checks,
        'determinism':{'render_fps':[30,60,144],'physics_ticks':1800,'identical_sha256':hashes[0]},
        'performance':performance,
        'evidence':{'report':'artifacts/visual-acceptance.md','gallery':'artifacts/gallery.html',
                    'engine_video':'artifacts/combat-preview.mp4','motion_previews':'output/imagegen/anime-v2/review/'},
        'limits':['No physical gamepad attached; simulated input and native engine GUI events validated.',
                  'Desktop screenshot helper failed with SetIsBorderRequired / 0x80004002; extra desktop click-through not completed.',
                  'Browser security policy rejected opening the local HTML preview; no browser playback acceptance claimed.',
                  'CPA actual output dimensions vary from requested dimensions; originals and both dimensions are preserved.',
                  'Godot source project delivered; no standalone Windows export produced.']
    }
    write(OUT/'manifest.json',manifest)
    write(ARTIFACTS/'gameplay-compatibility.json',manifest['gameplay_compatibility'])
    report = '''# 《月下对决》美术重制验收

交付为完整本地 Godot 工程。双击 `../launch.cmd`，或在 Godot 4.7.1 导入 `../project.godot` 运行。

## 已完成

- 主菜单、选人、战斗 HUD、暂停、操作指南、结算统一为月夜庭院与动漫立绘界面。
- 两名角色各 19 组、112 帧，共 224 张不同画帧；保留原招式时序，采用固定脚底锚点和起手／有效／收招分段。
- 五张 2048×1152 场景层、透明立绘与头像、四张独立水／雷／命中特效纹理、本地中文字体。
- 角色重复受击、连续同招、落地、倒地保持、视觉暂停、重开清理、同角色标记和完整刀身镜头边界已接入并检查。
- 生成原图、提示词、请求记录、切片坐标、图集和动作 GIF 均保留。游戏不联网、不读取生成账号。

## 素材审查与返工

CPA / `gpt-image-2` / `quality=high` 共保留 {requests} 份请求记录，{outputs} 张成功原图，50 张作为最终制作来源。
炭治郎待机／前进返工为持刀战斗姿态；两人的蹲重返工为全程低姿态横扫，避免起手直立与低判定不符。被替换原图仍保留。
2 次网关超时请求没有可用输出，另建替代请求完成；费用和服务端计费状态未知，没有记作零费用。

人物逐帧检查基于按时间排序的联系表、透明底边缘图与游戏实际渲染帧；38 份 GIF 可循环播放。
主要原图采用纯洋红底抠图；末批蹲重原图实际带有 alpha，保留源透明度并清理边缘。两组重做动作按头部／手部尺度整组校准，记录在 calibration.json。
四个专属技能另保存实际引擎连续渲染视频 `combat-preview.mp4`，108 帧，960×540、15 FPS 编码，逻辑按 60Hz 推进。
`gallery.html` 汇集视频、截图和全部动作，双击即可在本机浏览器查看。

服务实际返回的母图尺寸是 {stage_w}×{stage_h}；五层运行时素材经高质量重采样整理为 2048×1152，并非声称源图原生 2K。
实际输出和请求尺寸均在记录中保留。天空单独补全，建筑与地面共用完整母图及一致偏移，避免露底。

## 自动验证

| 检查 | 通过 | 失败 |
| --- | ---: | ---: |
| 战斗规则与输入回归 | {combat} | 0 |
| UI（无窗口） | {ui} | 0 |
| UI（实际 OpenGL 渲染） | {ui_render} | 0 |
| 表现层（无窗口） | {presentation} | 0 |
| 表现层（实际 OpenGL 渲染） | {presentation_render} | 0 |
| Python 素材完整性测试 | 2 | 0 |

不同渲染模式是重复覆盖，不把它们相加宣传成独立用例总数。相应日志保存在本目录。
30／60／144 FPS 下的 1800 个物理帧结果完全一致：`{state_hash}`。
战斗模型、角色状态、输入路由、AI、招式资源与改造前快照逐文件 SHA-256 一致，详见 `gameplay-compatibility.json`。

三种尺寸均有真实 Godot 截图：960×540、1280×720、1920×1080。已检查主菜单、选人、指南、暂停、战斗与双方结算；未见文字遮挡、按钮溢出或立绘截断。
原生鼠标点击、Tab、Enter、模拟方向键焦点，以及模拟手柄混合设备比赛与断开恢复由引擎输入事件测试覆盖。

## 本机性能

{gpu}，Godot 4.7.1，OpenGL Compatibility，1920×1080，最终美术全部加载；实际 AI 对 AI 对战采样 1800 个渲染帧，PNG 编码不计入采样。
平均 **{fps:.2f} FPS**；平均 **{mean:.3f} ms**，P95 **{p95:.3f} ms**，P99 **{p99:.3f} ms**。满足本机 60 FPS 目标，不代表其他硬件。
原始数据：`performance-hd.json`。

## 验证边界

- 未连接实体手柄，实体设备体验尚未实测；模拟输入已经通过。
- 桌面截图助手因 `SetIsBorderRequired / 0x80004002` 失败，额外桌面点击巡检未完成；不将原生事件测试描述成人工鼠标实玩。
- 浏览器安全策略拒绝打开本地 HTML，没有绕过此限制，也不声称在浏览器中完成连续播放审看。连续渲染、编码以及逐帧联系表检查已完成。
- 本交付是可运行工程，未导出独立 Windows EXE。

## 文件入口

- `../launch.cmd`：启动游戏。
- `gallery.html`：全部视觉与动作预览。
- `combat-preview.mp4`：实际引擎技能录像。
- `../output/imagegen/manifest.json`：最终来源、尺寸、摘要、验收及费用状态。
- `../output/imagegen/anime-v2/prompts/`：实际提示词。
- `pre-anime-remake-20260919-202144/`：改造前快照。
'''.format(requests=len(records),outputs=manifest['successful_image_outputs'],
           stage_w=manifest['stage']['source_size'][0],stage_h=manifest['stage']['source_size'][1],
           combat=checks['combat']['passed'],ui=checks['ui_headless']['passed'],
           ui_render=checks['ui_rendered']['passed'],presentation=checks['presentation_headless']['passed'],
           presentation_render=checks['presentation_rendered']['passed'],state_hash=hashes[0],
           gpu=performance['gpu'],fps=performance['mean_fps'],mean=performance['mean_frame_ms'],
           p95=performance['p95_frame_ms'],p99=performance['p99_frame_ms'])
    (ARTIFACTS/'visual-acceptance.md').write_text(report,encoding='utf-8')
    (OUT/'prompts/production.md').write_text('''# 已交付美术的生产入口

本次生产使用用户指定的 CPA 工作流与 `gpt-image-2`、`quality=high`。
实际提交的逐项提示词位于 `../anime-v2/prompts/`，任务清单位于 `../anime-v2/jobs.json`。
最终选用来源、返工替换关系、输出尺寸和验收记录见 `../manifest.json`。

角色、动作与独立装饰请求明确纯洋红底，再离线抠图、去色边及检查；末批实际带有 alpha 的原图保留源透明度并清理，没有假设所有输出格式一致。
独立水流、电光和命中特效使用纯黑底生成，在 Godot 中加色合成。
场景使用共同构图，天空补全，五层最终统一为 2048×1152。原始输出实际尺寸以请求记录为准。

`tools/process_anime_art.py` 可离线重建素材；不会发起付费请求。
`tools/run_art_production.ps1` 仅按选定任务调用项目中的 CPA helper，保留原图并防止未知状态自动重试。
不要重建或覆盖 jobs.json；追加返工任务并使用新 ID、提示词和输出路径。

之前未能生图的历史状态保存在 `../history/`，不代表当前交付状态。
''',encoding='utf-8')
    print('Final manifest, provenance, compatibility and acceptance report written.')

if __name__ == '__main__':
    main()
