"""Finalize provenance, exact combat audit, and local visual acceptance gallery."""
import json,hashlib,subprocess,shutil,html
from pathlib import Path
from datetime import datetime,timezone
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/battle-v5'
ART=ROOT/'artifacts/battle-v5'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def params(text):
 return {x.split('=',1)[0].strip():x.split('=',1)[1].strip() for x in text.splitlines() if '=' in x and not x.startswith(('[' ,'display_name'))}
def main():
 perf=read(ART/'performance.json')
 captures=read(ART/'matrix/captures.json')['captures']
 assert all(r['under_60fps_budget'] for r in perf['runs'])
 log=(ART/'regression.log').read_text(encoding='utf-8-sig')
 assert 'All checks passed.' in log and 'FAIL:' not in log and 'SCRIPT ERROR' not in log
 audit=[]
 for p in sorted((ROOT/'moves/core').glob('*.tres')):
  rel=p.relative_to(ROOT).as_posix()
  old=subprocess.check_output(['git','show','HEAD:'+rel],cwd=ROOT).decode('utf-8-sig')
  assert params(old)==params(p.read_text(encoding='utf-8-sig')),rel
  audit.append(rel)
 save(ART/'parameter-audit.json',dict(baseline='HEAD before battle-v5',moves=len(audit),excluded_fields=['display_name'],gameplay_parameter_changes=[]))
 for p in (OUT/'records').glob('*.json'):
  d=read(p);d.update(accepted=True,acceptance='artifacts/battle-v5/index.html; actual OpenGL captures and source review');save(p,d)
 save(OUT/'stage-accepted.json',dict(revision='battle-v5',panorama_sha256=sha(ROOT/'art/stages/wisteria/panorama.png'),size=[9600,2400],source_regions=21))
 previous=ROOT/'output/imagegen/history/pre-battle-v5-manifest.json'
 master=ROOT/'output/imagegen/manifest.json'
 if not previous.exists():shutil.copy2(master,previous)
 inventory=[]
 for p in sorted((ROOT/'art').rglob('*')):
  if not p.is_file() or p.suffix in ('.import','.md','.txt'):continue
  entry=dict(path=p.relative_to(ROOT).as_posix(),bytes=p.stat().st_size,sha256=sha(p))
  if p.suffix.lower() in ('.png','.jpg'):
   with Image.open(p) as im:entry.update(size=list(im.size),mode=im.mode)
  inventory.append(entry)
 save(master,dict(revision='battle-ui-v5',generated_utc=datetime.now(timezone.utc).isoformat(),route='CPA / gpt-image-2 via existing image_gen.py',
  previous_manifest=previous.relative_to(ROOT).as_posix(),gameplay_changes=[],characters=read(previous)['characters'],
  stage=read(ROOT/'art/stages/wisteria/stage.json'),artwork_records='output/imagegen/battle-v5/manifest.json',
  new_sources=[read(p) for p in sorted((OUT/'records').glob('*.json'))],inventory=inventory,performance=perf,
  rendered_matrix=dict(captures=len(captures),widths=[960,1280,1920,2560,3840],letterbox=[1600,1000],index='artifacts/battle-v5/matrix/captures.json'),
  authoring=dict(commands=['.venv/Scripts/python.exe tools/build_battle_art.py --part all','.venv/Scripts/python.exe tools/build_presentation_data.py','.venv/Scripts/python.exe tools/subset_fonts.py'])))
 from build_battle_art import manifest
 manifest()
 selected=[
 ('3840-tanjiro-idle-right-0-idle.png','4K 战斗 HUD 与连续背景'),
 ('3840-tanjiro-236236A-right-0-charge.png','水之呼吸 · 超必杀触发'),
 ('3840-tanjiro-236236A-right-0-combo.png','生生流转 · 水龙与连击'),
 ('3840-tanjiro-236236AC-right-0-charge.png','日之呼吸 · MAX 触发'),
 ('3840-tanjiro-236236AC-right-0-active.png','碧罗之天 · 火焰弧'),
 ('3840-zenitsu-236236A-right-0-combo.png','霹雳一闪 · 六连'),
 ('3840-zenitsu-236236AC-right-0-charge.png','雷之呼吸 · MAX 触发'),
 ('3840-zenitsu-236236AC-right-0-active.png','霹雳一闪 · 神速'),
 ('3840-tanjiro-both-right-0-charge.png','双方同时触发 MAX'),
 ('960-tanjiro-236236AC-left--1-active.png','960 宽度 · 同角色 · 左版边'),
 ('3840-zenitsu-details-right-0-details.png','练习详细输入指导'),
 ('1600-tanjiro-idle-right-0-idle.png','16:10 留边')]
 thumbs=ART/'thumbnails';thumbs.mkdir(exist_ok=True)
 cards=[]
 for name,title in selected:
  p=ART/'matrix'/name;assert p.exists(),p
  im=Image.open(p).convert('RGB');im.thumbnail((960,600),Image.Resampling.LANCZOS)
  target=thumbs/(p.stem+'.jpg');im.save(target,quality=91)
  cards.append(f'<figure><a href="matrix/{name}"><img loading="lazy" src="thumbnails/{target.name}"></a><figcaption>{html.escape(title)}</figcaption></figure>')
 before=Image.open(OUT/'references/stage-layout.png').resize((9600,2400),Image.Resampling.LANCZOS).crop((4032,688,5568,1712))
 after=Image.open(ROOT/'art/stages/wisteria/panorama.png').crop((4032,688,5568,1712))
 comparison=Image.new('RGB',(1536,560),'#0b1320');draw=ImageDraw.Draw(comparison)
 for x,im,label in [(0,before,'BEFORE / enlarged source'),(768,after,'AFTER / native detail repaint')]:
  comparison.paste(im.resize((768,512),Image.Resampling.LANCZOS),(x,0));draw.text((x+20,531),label,fill='#e6c77f')
 comparison.save(ART/'background-comparison.jpg',quality=94)
 # Preserve a true previous-engine screenshot when the historical capture is available.
 old=ROOT/'artifacts/phase2/matrix/1280-tanjiro-left-236236AC-active.png'
 new=ART/'matrix/1280-tanjiro-236236AC-left--1-active.png'
 if old.exists() and new.exists():
  pair=Image.new('RGB',(1280,770),'#0b1320');label=ImageDraw.Draw(pair)
  for x,path,title in [(0,old,'BEFORE'),(640,new,'AFTER')]:
   im=Image.open(path).convert('RGB').resize((640,360),Image.Resampling.LANCZOS)
   pair.paste(im,(x,30));label.text((x+16,10),title,fill='#e6c77f')
  bg=Image.open(ART/'background-comparison.jpg');bg.thumbnail((1280,370),Image.Resampling.LANCZOS)
  pair.paste(bg,((1280-bg.width)//2,400))
  pair.save(ART/'before-after.jpg',quality=93)
 summary='\n'.join(f"- {r['resolution'][0]}×{r['resolution'][1]}：平均 {r['mean_frame_ms']:.2f} ms，P95 {r['p95_frame_ms']:.2f} ms，P99 {r['p99_frame_ms']:.2f} ms。" for r in perf['runs'])
 review=f"""# 比赛 UI 与必杀技视觉升级

已交付 9600×2400 连续背景、两名角色的高清头像、金边水墨 HUD、底部三段呼吸槽、连击提示、分层水／雷／火特效及独立超杀触发演出。

四种超杀完整显示名称，字号统一 36px。超杀与 MAX 逻辑停顿保持 12／18 帧。{len(audit)} 份招式资源与改版前逐项对比，除显示名称外参数完全一致。

## 实测

{summary}

显卡：{perf['runs'][0]['gpu']}。每档 1800 帧实际 OpenGL 对战，统计包含显示调度，截图编码不计入采样。非 16:9 截图以实际引擎视口图像按 KEEP 布局补齐黑色窗口留边，记录中标注为合成。五档分辨率及 1600×1000 留边共 {len(captures)} 张引擎截图。完整自动回归通过，30／60／144 FPS 状态摘要一致。

## 来源与重建

CPA / gpt-image-2。21 块庭院图实际返回 1536×1024，经过几何对齐、低频光照匹配和重叠混合，没有把普通放大计作新增细节。角色特写保留服务返回的原生透明通道。未知生成费用保留 null。16 份背景、头像及特效派生文件已验证离线重建后字节一致。

安装 requirements-art.txt 后，以项目虚拟环境运行 tools/build_battle_art.py --part all 可离线重建。提示词、参考图、原图和请求记录位于 output/imagegen/battle-v5/。

[预览与完整截图](index.html) · [四种超杀录像](preview.mp4) · [性能原始数据](performance.json) · [参数对照](parameter-audit.json)
"""
 (ART/'review.md').write_text(review,encoding='utf-8')
 rows=''.join(f"<tr><td>{r['resolution'][0]} × {r['resolution'][1]}</td><td>{r['mean_frame_ms']:.2f} ms</td><td>{r['p95_frame_ms']:.2f} ms</td><td>{r['p99_frame_ms']:.2f} ms</td></tr>" for r in perf['runs'])
 page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>月下对决 · 比赛视觉升级</title>
<style>body{margin:0;background:#09111d;color:#f6edda;font:16px/1.65 system-ui,"Microsoft YaHei",sans-serif}main{max-width:1440px;margin:auto;padding:48px 32px}h1{font:42px Georgia,serif;color:#e6c77f}h2{font-size:24px;color:#e6c77f;margin-top:48px}p{color:#b7bfd0;max-width:960px}a{color:#81d6e7}video{width:100%;max-height:810px;background:#000;border:1px solid #655437}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}figure{margin:0;background:#111c2b;border:1px solid #344357}img{width:100%;display:block}figcaption{padding:12px 18px}table{border-collapse:collapse;width:100%;max-width:780px}th,td{text-align:left;padding:12px;border-bottom:1px solid #344357}small{color:#a3aec0}@media(max-width:800px){.grid{grid-template-columns:1fr}main{padding:24px 16px}}</style>
<main><small>MOONLIT DUEL / BATTLE V5</small><h1>月下对决 · 比赛视觉升级</h1><p>实际 Godot 引擎画面。高清连续庭院、金边水墨界面、元素呼吸槽与四种超杀；名称完整显示，战斗帧数与规则保持一致。</p>
<video controls preload="metadata" poster="thumbnails/3840-tanjiro-236236AC-right-0-active.jpg" src="preview.mp4"></video><h2>背景细节对比</h2><p>同一场景区域：旧源图放大与原生分区重绘，按相同比例显示。</p><img src="background-comparison.jpg">
<h2>实机截图</h2><p>点击图片查看原始分辨率。</p><div class="grid">'''+''.join(cards)+'''</div><h2>性能与验证</h2><table><tr><th>分辨率</th><th>平均</th><th>P95</th><th>P99</th></tr>'''+rows+f'''</table><p>{len(captures)} 张截图；五档分辨率、左右版边、同角色、同时触发、练习指导及 16:10 留边。完整回归与帧率一致性检查通过。</p><p><a href="review.md">验收说明</a> · <a href="performance.json">性能数据</a> · <a href="matrix/captures.json">全部截图索引</a> · <a href="parameter-audit.json">战斗参数对照</a></p></main></html>'''
 (ART/'index.html').write_text(page,encoding='utf-8')
 print('Published battle-v5 acceptance:',len(captures),'captures; ',len(audit),'unchanged gameplay parameter sets.')
if __name__=='__main__':main()

