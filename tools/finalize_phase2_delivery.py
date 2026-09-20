"""Finalize verified phase-two evidence, preserving generation and billing provenance."""
import copy,hashlib,html,json,re,subprocess
from datetime import datetime,timezone
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen';RUN=OUT/'anime-v2';ART=ROOT/'artifacts';PHASE=ART/'phase2'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def write(p,v):
 p.parent.mkdir(parents=True,exist_ok=True)
 p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def relative(p):return p.relative_to(ROOT).as_posix()
def log_check(name,label):
 p=ART/(name+'.log');s=p.read_text(encoding='utf-8-sig')
 assert not re.search(r'SCRIPT ERROR|ERROR:|FAIL:|instances were leaked|RIDs.*were leaked',s),name
 match=re.search(re.escape(label)+r': (\d+) passed, 0 failed',s);assert match,name
 return {'passed':int(match[1]),'failed':0,'log':relative(p)}
def main():
 now=datetime.now(timezone.utc).isoformat()
 checks={k:log_check(k,label) for k,label in [
 ('input_tests','INPUT TESTS'),('combat_tests','COMBAT TESTS'),('movement_tests','MOVEMENT TESTS'),
 ('combo_practice_tests','COMBO / PRACTICE TESTS'),('ui_tests','UI TESTS'),('presentation_tests','PRESENTATION TESTS'),
 ('phase2_basics_tests','PHASE TWO BASICS'),('phase2_feedback_tests','PHASE TWO FEEDBACK'),
 ('ui_tests-rendered','UI TESTS'),('presentation_tests-rendered','PRESENTATION TESTS')]}
 hashes=[]
 for fps in (30,60,144):
  s=(ART/f'fps-{fps}.log').read_text(encoding='utf-8-sig')
  assert 'physics=1800' in s
  hashes.append(re.search(r'hash=([a-f0-9]{64})',s)[1])
 assert len(set(hashes))==1
 matrix=read(PHASE/'matrix/captures.json');assert not matrix['failures'] and len(matrix['captures'])==192
 rebuild=read(PHASE/'rebuild-verification.json');assert not rebuild['changed'] and rebuild['offline']
 for name,sha in rebuild['hashes'].items():assert digest(ROOT/name)==sha,name
 audit=read(PHASE/'parameter-audit.json');assert not audit['gameplay_parameter_changes']
 before=read(PHASE/'performance-before.json');after=read(ART/'performance-hd.json')
 assert after['all_art_ready'] and after['p95_frame_ms']<16.67 and before['gpu']==after['gpu']
 performance={'before':before,'after':after,'difference_ms':{k:after[k]-before[k] for k in ['mean_frame_ms','p95_frame_ms','p99_frame_ms']},'method':'Same 1080p / OpenGL / GPU / 1800 rendered AI-versus-AI frame harness; no concurrent capture or encoding. Frame time includes scheduling and display pacing, not an isolated GPU timestamp.'}
 write(PHASE/'performance-comparison.json',performance)
 videos=[]
 for batch in ['basics','specials']:
  p=PHASE/(batch+'.mp4');cue=read(PHASE/batch/'cues.json');audio=read(PHASE/batch/'audio-report.json')
  assert p.stat().st_size>10000 and audio['peak']<1 and audio['pause_intervals']==2
  assert len(cue['cues'])==(26 if batch=='basics' else 24)
  assert cue['frames']==(1248 if batch=='basics' else 1872)
  capture_log=(PHASE/(batch+'-capture.log')).read_text(encoding='utf-8-sig')
  assert 'PHASE TWO CAPTURE COMPLETE' in capture_log and not re.search(r'ERROR:|SCRIPT ERROR',capture_log)
  probe=json.loads(subprocess.check_output(['E:/Program Files/ffmpeg-7.1.1-essentials_build/bin/ffprobe.exe','-v','error','-show_entries','format=duration,size','-show_entries','stream=codec_name,width,height,r_frame_rate,sample_rate','-of','json',str(p)],text=True))
  assert {s['codec_name'] for s in probe['streams']}=={'h264','aac'}
  assert abs(float(probe['format']['duration'])-cue['frames']/cue['fps'])<0.1
  videos.append({'path':relative(p),'bytes':p.stat().st_size,'sha256':digest(p),'fps':cue['fps'],'frames':cue['frames'],'seconds':cue['frames']/cue['fps'],'resolution':cue['resolution'],'cases':len(cue['cues']),'cues':relative(PHASE/batch/'cues.json'),'audio':audio,'probe':probe})
 history=OUT/'history/pre-phase2-manifest.json'
 if not history.exists():history.write_bytes((OUT/'manifest.json').read_bytes())
 manifest=read(history)
 manifest['revision']='phase2-actions-feedback-v1';manifest['generated_utc']=now
 manifest['previous_manifest']=relative(history)
 manifest['gameplay_changes']=[]
 manifest['visual_changes']=['28 dedicated chronological pose sources; 281 new selected drawings','Logic-stage and hit-segment animation synchronization','Dedicated water, lightning and fire silhouettes; restrained layered MAX effects','Hit/block/whiff/throw escape/meter feedback and deterministic local PCM','Freeze and reset handling for animation, trails, effects and audio','16 world-unit camera overscan inside the existing panorama; horizontal throw victims remain visible at true boundaries']
 for stale in ['previous_revision_performance','previous_revision_videos']:
  manifest.pop(stale,None)
 sources=[s for s in manifest['sources'] if '-phase2-' not in s['id']]
 jobs=read(RUN/'jobs.json');new_jobs=[j for j in jobs if j['group'].startswith('phase2-')]
 assert len(new_jobs)==28
 for job in new_jobs:
  record_path=RUN/'records'/(job['id']+'.json');record=read(record_path);p=ROOT/job['out']
  assert record['status']=='generated'
  with Image.open(p) as im:size=list(im.size)
  record.update(accepted=True,actual_size=size,sha256=digest(p))
  record['review']={'status':'accepted_for_phase2_actions_feedback','reviewed_utc':now,'evidence':'docs/phase2-acceptance.md','capture_gallery':'artifacts/phase2/index.html'}
  if 'frame_order' in job['metadata']:record['review']['frame_order']=job['metadata']['frame_order']
  write(record_path,record)
  meta=job['metadata']
  sources.append({'key':meta['character']+'/'+meta['clip'],'id':job['id'],'prompt':job['prompt'],'source':job['out'],'requested_size':job['size'],'actual_size':size,'references':job['references'],'sha256':record['sha256'],'cost':record.get('cost'),'source_drawings':meta['count'],'selected_drawings':len(meta.get('frame_order',range(meta['count']))),'import':relative(RUN/'imports'/(job['id']+'.json'))})
 manifest['sources']=sources
 chars={}
 for cid in ['tanjiro','zenitsu']:
  atlas=read(ROOT/'art/characters'/cid/'atlas.json')
  chars[cid]={'clips':len(atlas['clips']),'frames':sum(len(c['frames']) for c in atlas['clips'].values()),'pages':len({f['texture'] for c in atlas['clips'].values() for f in c['frames']}),'canvas_size':atlas['canvas_size'],'feet_anchor':atlas['feet_anchor'],'scale':atlas['canonical_height']/atlas['source_height']}
 assert chars['tanjiro']['frames']==306 and chars['zenitsu']['frames']==311
 manifest['characters']=chars
 inventory=[]
 for p in sorted((ROOT/'art').rglob('*')):
  if not p.is_file() or p.suffix not in ['.png','.jpg','.json','.ttf']:continue
  row={'path':relative(p),'bytes':p.stat().st_size,'sha256':digest(p)}
  if p.suffix in ['.png','.jpg']:
   with Image.open(p) as im:row.update(size=list(im.size),mode=im.mode)
  inventory.append(row)
 manifest.update(inventory=inventory,tests=checks,frame_rate_hash={'fps':[30,60,144],'logic_frames':1800,'sha256':hashes[0]},performance=performance,videos=videos,
  calibration={'path':relative(RUN/'calibration.json'),'sha256':digest(RUN/'calibration.json')},
  authoring={'jobs':relative(RUN/'jobs.json'),'jobs_sha256':digest(RUN/'jobs.json'),'rebuild_verification':relative(PHASE/'rebuild-verification.json'),'files_byte_identical':rebuild['files_compared'],'commands':['python tools/build_movement_art.py --part animation','python tools/build_presentation_data.py','python tools/build_combat_data.py','python tools/subset_fonts.py']},
  parameter_audit={'path':relative(PHASE/'parameter-audit.json'),**audit},
  rendered_matrix={'captures':192,'widths':[960,1280,1920],'index':relative(PHASE/'matrix/captures.json'),'method':matrix['method']},
  known_limits=['No physical gamepad connected. Local keyboard / virtual controller events and actual OpenGL rendering were tested; no physical-device playtest or acoustic playback review claimed.','Zenitsu upward and return iai cuts are game interpretations.','Generated source dimensions can differ from requested dimensions; both retained. Unknown CPA billing remains null.','Recordings use actual engine frames with exported Godot PCM mixed from the same 60Hz events, including pause intervals; not screen/microphone capture.'])
 write(OUT/'manifest.json',manifest)
 labels={'input_tests':'输入','combat_tests':'战斗与AI对局','movement_tests':'移动、翻滚与投技','combo_practice_tests':'连段／练习','ui_tests':'UI与模拟设备','presentation_tests':'表现与字体／图集','phase2_basics_tests':'第二阶段基础动作','phase2_feedback_tests':'第二阶段必杀与反馈','ui_tests-rendered':'UI实际渲染','presentation_tests-rendered':'表现实际渲染'}
 table='\n'.join(f'| {labels[k]} | {v["passed"]} | 0 |' for k,v in checks.items())
 report=f'''# 第二阶段：专属动作与打击反馈验收

2026-09-20，Godot 4.7.1，60Hz固定逻辑。两批已实现并启用，未改变招式帧数、伤害、位移、攻击范围、气量或取消规则。

## 完成内容

- 炭治郎：站立刀柄轻击／前踢、蹲下肘击／扫腿、空中膝击／下踢。善逸：站立短踢／侧踢、蹲下短踢／扫腿、空中短踢／剪式踢击。轻重与站蹲空各自使用连续姿态，保留刀剑架势。
- 两人各自前后滚、前投、前投受方和拆投；背摔双方沿用已接受的独立动作。翻滚卷身与无敌期、危险落脚与收招、投技落地与拆投硬直均按逻辑帧同步。
- 新增扭转漩涡、生生流转、碧罗之天、回身斩、六连、神速专属图集。独立水刃、纵向水车、低位漩涡、分段水流、火弧与雷光各有轮廓；六连六组动作对应六次实际命中，MAX以局部蓄力和多层特效加强表现。
- 命中、防御、挥空、拆投、耗气和气不足均有对应反馈。多段中间段降低声音、火花与震屏；动作取消／受击清理残影，停顿／暂停冻结表现，重置／回合结束清理瞬态。善逸上撩、回身斩继续标明游戏演绎。

新增28张源图、282张源姿态，选用281张。运行图集合计78组617帧：炭治郎39组306帧（7页），善逸39组311帧（6页）。原图、提示词、返回尺寸、摘要、选帧、标定、图集参数和映射均保留。

## 实际发现与修正

1. 蹲姿与横卧姿态按包围框比较会显得过大，改为每条动作固定解剖比例；不逐帧拉伸。善逸2D舍弃过高的原始首帧，以8张低位姿态完成动作，原图完整保留。
2. 翻滚和前投用显式时间表，避免卷身／落地画面错过逻辑阶段。六连等多段按每段独立分配画帧与出手声，避免整条有效期匀速播放造成不同步。
3. 真正版边的横卧受投姿态超出原28单位镜头边缘余量，脚尖出现少量裁切。镜头在现有全景画的48单位富余内使用16单位留白，维持固定3倍比例；双方战斗坐标与场地边界不变。新增80项完整受投轮廓检查及192张版边截图通过。
4. 连续多段的中间命中降低冲击表现，拆投兼容事件去重；实际混音峰值低于1，无削波。没有证据需要调整玩法参数，四条示例路线伤害保持第一阶段结果。

## 自动测试

| 套件 | 通过 | 失败 |
| --- | ---: | ---: |
{table}

美术与派生预览3项检查通过；离线作者工具重建{rebuild['files_compared']}份图集、标定、导入记录和运行资源，字节摘要全部相同。32组示例连段（每人4条×左右×中场／真实版边）均成立，首击后防用于识别断连，伤害仍为200／200、249／244、397／396、491／489。

30／60／144 FPS各推进1800逻辑帧，状态摘要一致：`{hashes[0]}`。见 `artifacts/combo-validation.json`、`artifacts/phase2/segment-validation.json`、各测试日志。

## 实际引擎渲染与录像

- `artifacts/phase2/index.html`：本地验收索引。
- `basics.mp4`：41.6秒、26场景；`specials.mp4`：62.4秒、24场景。均为实际Godot OpenGL帧，1280×720、30FPS视频；模拟逻辑保持60Hz。录像包含两角色、左右、近版边、同角色、取消、落地、拆投、暂停及资源反馈。
- `artifacts/phase2/matrix/`：60场景、192张截图。960×540／1280×720／1920×1080，两角色×左右真实场地边界×重体术、后滚、前投、1格及MAX的不同阶段，同角色对战。
- 通用渲染套件另覆盖三种尺寸的菜单、HUD、练习设置、完整招式表及全部42个招式。
- 音轨由Godot生成PCM，按同次运行的逻辑事件离线混音，保留暂停区间；不是麦克风／声卡录音。基础与必杀混音峰值为 {videos[0]['audio']['peak']:.3f}／{videos[1]['audio']['peak']:.3f}，视频为H.264/AAC。

## 1080p性能对比

同一RTX3080Ti、OpenGL兼容渲染、1800个AI对战渲染帧，不并行录制或编码。PNG编码不计入采样。

| 帧耗时 | 阶段前 | 阶段后 | 差值 |
| --- | ---: | ---: | ---: |
| 平均 | {before['mean_frame_ms']:.3f} ms | {after['mean_frame_ms']:.3f} ms | {0 if abs(after['mean_frame_ms']-before['mean_frame_ms'])<0.0005 else after['mean_frame_ms']-before['mean_frame_ms']:+.3f} ms |
| P95 | {before['p95_frame_ms']:.3f} ms | {after['p95_frame_ms']:.3f} ms | {after['p95_frame_ms']-before['p95_frame_ms']:+.3f} ms |
| P99 | {before['p99_frame_ms']:.3f} ms | {after['p99_frame_ms']:.3f} ms | {after['p99_frame_ms']-before['p99_frame_ms']:+.3f} ms |

P95低于60FPS的16.67ms预算。该指标包括渲染帧调度和显示节拍，并非独立GPU耗时；一次同机对比不代表其他硬件表现。原始数据见 `artifacts/phase2/performance-comparison.json`。

## 测试边界与剩余事项

自动测试包括模型输入、实际UI事件、AI和本地双人流程；手柄轴、死区、按键和混合设备使用模拟事件。引擎报告实体手柄列表为空，没有实体手柄或双人真人手感实测，也没有扬声器／耳机听感验收。已完成范围内未发现阻塞性逻辑或渲染问题。合成音色的主观听感、键盘同时按键冲突和实体手柄延迟仍需具体设备实测。

## 复现与体验

```powershell
# 完整自动检查 + 实际多分辨率截图 + 1080p性能
.\\tests\\run_tests.ps1 -Capture
# 离线重建并比较图集与作者资源
.\\.venv\\Scripts\\python.exe -X utf8 tools/verify_phase2_rebuild.py
# 连续录像与音轨，按顺序运行两批
& 'D:/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe' --path . --audio-driver Dummy --fixed-fps 60 --log-file artifacts/phase2/basics-capture.log --script res://tools/capture_phase2.gd
.\\.venv\\Scripts\\python.exe -X utf8 tools/mix_phase2_audio.py basics
.\\tools\\encode_phase2.ps1 -Batch basics
& 'D:/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe' --path . --audio-driver Dummy --fixed-fps 60 --log-file artifacts/phase2/specials-capture.log --script res://tools/capture_phase2.gd -- --specials
.\\.venv\\Scripts\\python.exe -X utf8 tools/mix_phase2_audio.py specials
.\\tools\\encode_phase2.ps1 -Batch specials
# 最后更新清单与本报告
.\\.venv\\Scripts\\python.exe -X utf8 tools/finalize_phase2_delivery.py
```

双击 `launch.cmd` →「自由练习」→选人。默认3格气；G／B为轻／重体术，F+G前滚，后+F+G后滚，近身方向+B投技。F3切换木桩与气量，Backspace重置，F1显示判定框。面朝右236236+F/V为1格奥义，236236+F+V为MAX，朝左镜像。
'''
 (ROOT/'docs/phase2-acceptance.md').write_text(report,encoding='utf-8')
 build_gallery(videos,after)
 print('PHASE TWO DELIVERY finalized: 28 accepted sources, 78 clips / 617 drawings, 192 corner screenshots, 2 audiovisual recordings.')
def build_gallery(videos,performance):
 content=['<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>月下对决 · 第二阶段验收</title><style>body{margin:0;background:#101725;color:#e7e5dc;font:16px/1.7 system-ui}main{max-width:1120px;margin:auto;padding:32px}h1{color:#edcf98}a{color:#9edbe4}video{width:100%;background:#080b13}section{margin:32px 0}.shots{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:16px}img{width:100%}figure{margin:0}figcaption{font-size:13px;color:#c1cbd5}.chapters{display:flex;flex-wrap:wrap;gap:8px}button{background:#22394d;color:#fff;border:1px solid #547487;border-radius:4px;padding:6px;cursor:pointer}</style><main><h1>鬼灭之刃 · 月下对决</h1><p>第二阶段：专属动作与打击反馈。实际Godot引擎画面，60Hz逻辑；音轨来自同次运行的事件。<a href="../../docs/phase2-acceptance.md">完整验收报告</a></p>']
 for batch,label in [('basics','基础动作 · 41.6秒'),('specials','必杀与奥义 · 62.4秒')]:
  content.append(f'<section><h2>{label}</h2><video id="{batch}" controls preload="metadata" src="{batch}.mp4"></video><div class="chapters">')
  for c in read(PHASE/batch/'cues.json')['cues']:
   label=('炭治郎' if c['character']=='tanjiro' else '善逸')+' '+c['scenario']
   content.append(f'<button onclick="seek(\'{batch}\',{c["start_frame"]/30})">{html.escape(label)}</button>')
  content.append('</div></section>')
 content.append('<section><h2>真实版边 · 同角色对战</h2><p>三种分辨率，启动／有效／收招原始截图：<a href="matrix/captures.json">192张截图索引</a>。<a href="matrix/">截图目录</a></p><div class="shots">')
 thumb=PHASE/'thumbnails';thumb.mkdir(exist_ok=True)
 for width in [960,1280,1920]:
  for cid,side,move,phase in [('tanjiro','left','236236AC','active'),('zenitsu','right','236236A','active'),('zenitsu','left','6D','slam'),('tanjiro','right','236236AC','recovery')]:
   name=f'{width}-{cid}-{side}-{move}-{phase}.png';p=PHASE/'matrix'/name
   with Image.open(p) as im:
    im.convert('RGB').resize((512,288)).save(thumb/(p.stem+'.jpg'),quality=88)
   content.append(f'<figure><a href="matrix/{name}"><img loading="lazy" src="thumbnails/{p.stem}.jpg"></a><figcaption>{width} · {cid} · {side} · {move} · {phase}</figcaption></figure>')
 content.append(f'</div></section><p>1080p平均 {performance["mean_frame_ms"]:.3f} ms，P95 {performance["p95_frame_ms"]:.3f} ms。实体手柄未连接；已验证模拟手柄和实际渲染。</p></main><script>function seek(id,t){{const v=document.getElementById(id);v.currentTime=t;v.play();}}</script></html>')
 (PHASE/'index.html').write_text('\n'.join(content),encoding='utf-8')
if __name__=='__main__':main()
