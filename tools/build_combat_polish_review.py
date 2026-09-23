"""Build combat-polish evidence, provenance and a local before/after gallery."""
import argparse,hashlib,html,json,re,shutil,subprocess
from datetime import datetime,timezone
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'artifacts/combat-polish'
RUN=ROOT/'output/imagegen/anime-v2'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def write(p,d):
 p.parent.mkdir(parents=True,exist_ok=True)
 p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def rel(p):return p.relative_to(ROOT).as_posix()
def encode(ffmpeg):
 flags=getattr(subprocess,'CREATE_NO_WINDOW',0)
 for label in ('before','after'):
  subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-framerate','30','-i',str(ART/label/'frame-%05d.jpg'),'-c:v','libx264','-preset','fast','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',str(ART/(label+'.mp4'))],check=True,creationflags=flags)
 subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-i',str(ART/'before.mp4'),'-i',str(ART/'after.mp4'),'-filter_complex','[0:v]scale=640:360[a];[1:v]scale=640:360[b];[a][b]hstack=inputs=2[out]','-map','[out]','-c:v','libx264','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',str(ART/'comparison.mp4')],check=True,creationflags=flags)
 if (ART/'previous/after.mp4').exists():
  subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-i',str(ART/'previous/after.mp4'),'-i',str(ART/'after.mp4'),'-filter_complex','[0:v]scale=640:360[a];[1:v]scale=640:360[b];[a][b]hstack=inputs=2[out]','-map','[out]','-c:v','libx264','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',str(ART/'revision-comparison.mp4')],check=True,creationflags=flags)

def acceptance():
 before=read(ART/'before/captures.json');after=read(ART/'after/captures.json')
 lookup={s['id']:s for s in before['scenarios']}
 cases=[s for s in after['scenarios'] if 'hashes' in s]
 assert len(cases)==56
 assert all(s['hashes']==lookup[s['id']]['hashes'] for s in cases),'Move simulation differs'
 unchanged=[]
 for p in sorted((ROOT/'moves').rglob('*.tres')):
  original=subprocess.check_output(['git','show','HEAD:'+rel(p)],cwd=ROOT)
  assert original.replace(b'\r\n',b'\n')==p.read_bytes().replace(b'\r\n',b'\n'),rel(p)
  unchanged.append(rel(p))
 log=(ROOT/'artifacts/combat-polish-regression.log').read_text(encoding='utf-8-sig')
 assert 'All checks passed.' in log and not re.search(r'SCRIPT ERROR|FAIL:',log)
 checks={name:int(count) for name,count in re.findall(r'([A-Z /]+): (\d+) passed, 0 failed',log)}
 focused=(ROOT/'artifacts/combat_polish_tests.log').read_text(encoding='utf-8-sig')
 latest=re.search(r'COMBAT POLISH TESTS: (\d+) passed, 0 failed',focused)
 assert latest and 'FAIL:' not in focused
 checks['COMBAT POLISH TESTS']=int(latest[1])
 hashes=re.findall(r'hash=([a-f0-9]{64})',log)
 assert len(hashes)==3 and len(set(hashes))==1
 jumps=[]
 for cid in ('tanjiro','zenitsu'):
  for width in (1280,1920):
   normal=next(s for s in after['scenarios'] if s['id']==f'{width}-{cid}-jump')['positions']
   dash=next(s for s in after['scenarios'] if s['id']==f'{width}-{cid}-dash-jump')['positions']
   assert all(abs(n[1]-d[1])<1e-5 for n,d in zip(normal,dash))
   nd=normal[-1][0]-normal[0][0];dd=dash[-1][0]-dash[0][0]
   jumps.append(dict(character=cid,width=width,normal_remaining_distance=nd,dash_remaining_distance=dd,ratio=dd/nd))
 result=dict(revision='combat-polish-v2',generated_utc=datetime.now(timezone.utc).isoformat(),checks=checks,move_resources_unchanged=len(unchanged),real_input_cases=len(cases),matching_simulation_ticks=sum(len(s['hashes']) for s in cases),screenshots=dict(before=len(before['captures']),after=len(after['captures']),resolutions=[[1280,720],[1920,1080]]),video=dict(fps=30,frames=after['video_frames'],seconds=after['video_frames']/30,audio=False),jumps=jumps,frame_rate_sha256=hashes[0],source_manifest='output/imagegen/combat-polish-manifest.json',limitations=['Input driven by deterministic held commands; physical gamepad feel not tested.'])
 write(ART/'acceptance.json',result)
 return result,after
def revision_gallery():
 labels = {'title': '本次反馈调整 · 上一版 / 当前版', 'intro': '撤销满气流光、MAX脉动与人物气焰；善逸雷光恢复原样。四种奥义残影寿命延长50%，改为保留服装明暗的蓝紫色轮廓。', 'labels': ['生生流转 · 青蓝残影', '碧罗之天 · 淡紫残影', '六连 · 靛蓝残影', '神速 · 冰蓝残影'], 'video': '左侧为上一版，右侧为本次调整；静音30 FPS。', 'baseline': '最初版本 / 当前版本', 'old': '上一版原图', 'new': '当前原图'}
 names=['1280-tanjiro-236236A-1-active-2.png','1280-tanjiro-236236AC-1-active-0.png','1280-zenitsu-236236A-1-active-3.png','1280-zenitsu-236236AC-1-active-1.png']
 if not all((ART/'previous'/n).exists() for n in names):return ''
 cards=[]
 for title,name in zip(labels['labels'],names):
  canvas=Image.new('RGB',(1280,300),'#101a2c');draw=ImageDraw.Draw(canvas)
  for x,label in [(0,'previous'),(640,'after')]:
   im=Image.open(ART/label/name).convert('RGB').crop((240,345,1110,675)).resize((640,243),Image.Resampling.LANCZOS)
   canvas.paste(im,(x,30));draw.text((x+12,9),label.upper(),fill='#e6c88a')
  target=ART/'comparisons'/('revision-'+Path(name).stem+'.jpg')
  canvas.save(target,quality=92)
  cards.append(f'<figure><img loading="lazy" src="comparisons/{target.name}" alt="{html.escape(title)}"><figcaption>{html.escape(title)} · <a href="previous/{name}">{labels["old"]}</a> / <a href="after/{name}">{labels["new"]}</a></figcaption></figure>')
 return f'<h2>{labels["title"]}</h2><p>{labels["intro"]}</p><video controls preload="metadata" src="revision-comparison.mp4"></video><p>{labels["video"]}</p>'+''.join(cards)+f'<h2>{labels["baseline"]}</h2>'

def gallery(result,after):
 selected=[
 ('水面斩 · 独立浪刃','1280-tanjiro-236A-1-projectile.png'),
 ('水车 · 后空翻','1280-tanjiro-623C-1-active-0.png'),
 ('呼吸槽 · 恢复原样','1280-tanjiro-meter-300.png'),
 ('满气MAX · 恢复静态','1280-zenitsu-meter-300.png'),
 ('霹雳一闪 · 恢复原有雷光','1280-zenitsu-236A-1-active-0.png'),
 ('上撩 · 斜向雷光','1280-zenitsu-623C-1-active-0.png'),
 ('回身斩 · 朝左','1280-zenitsu-214D--1-active-0.png'),
 ('生生流转 · 残影','1280-tanjiro-236236A-1-active-2.png'),
 ('碧罗之天 · MAX残影','1280-tanjiro-236236AC-1-active-0.png'),
 ('六连 · 移动残影','1280-zenitsu-236236A-1-active-3.png'),
 ('神速 · 冰蓝残影','1280-zenitsu-236236AC-1-active-1.png'),
 ('双方同时MAX','1280-dual-max-44.png'),
 ('冲刺起跳 · 增加距离','1280-tanjiro-dash-jump-28.png'),
 ('1080p · 朝左水面斩','1920-tanjiro-236C--1-projectile.png'),
 ('1080p · 朝左水车','1920-tanjiro-623A--1-active-0.png')]
 thumbs=ART/'comparisons';thumbs.mkdir(exist_ok=True);cards=[]
 for title,name in selected:
  if not all((ART/label/name).exists() for label in ('before','after')):continue
  canvas=Image.new('RGB',(1280,395),'#101a2c');draw=ImageDraw.Draw(canvas)
  for x,label in [(0,'before'),(640,'after')]:
   im=Image.open(ART/label/name).convert('RGB').resize((640,360),Image.Resampling.LANCZOS)
   canvas.paste(im,(x,30));draw.text((x+12,9),label.upper(),fill='#e6c88a')
  target=thumbs/(Path(name).stem+'.jpg');canvas.save(target,quality=90)
  cards.append(f'<figure><img loading="lazy" src="comparisons/{target.name}" alt="{html.escape(title)}"><figcaption>{html.escape(title)} · <a href="before/{name}">修改前原图</a> / <a href="after/{name}">修改后原图</a></figcaption></figure>')
 links=''.join(f'<li><a href="{c["path"].replace("res://artifacts/combat-polish/","")}">{html.escape(Path(c["path"]).name)}</a></li>' for c in after['captures'])
 doc=f"""<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>月下对决 · 跳跃与招式视觉优化</title>
<style>body{{margin:0;background:#0b1322;color:#e9edf1;font:16px/1.7 system-ui,"Microsoft YaHei",sans-serif}}main{{max-width:1280px;margin:auto;padding:36px 24px}}h1{{font-size:32px;margin:0;color:#f0d69d}}p{{color:#b6c9d4}}a{{color:#86dce9}}video,img{{display:block;width:100%;border-radius:8px}}figure{{margin:28px 0;background:#132035;padding:12px;border-radius:10px}}figcaption{{padding:9px 4px}}.facts{{padding:18px;border-left:3px solid #65cbd4;background:#112033}}details{{margin:24px 0}}ul{{columns:2;font-size:13px}}@media(max-width:700px){{ul{{columns:1}}}}</style>
<main><h1>跳跃与招式视觉优化</h1><p>前冲跳跃距离 ×1.5 · 四种奥义蓝紫残影延长 · 满气与雷光恢复原样 · 新水面斩与后空翻水车</p>
<div class="facts">招式资源 {result['move_resources_unchanged']} 份保持原值；{result['real_input_cases']} 个真实输入场景、{result['matching_simulation_ticks']} 个逻辑帧前后一致。30 / 60 / 144 FPS 战斗摘要一致。<br>720p / 1080p各方向截图共 {result['screenshots']['before']+result['screenshots']['after']} 张。视频为30 FPS静音实机对照，左侧修改前，右侧修改后。</div>
{revision_gallery()}
<h2>实机短片</h2><video controls preload="metadata" poster="comparisons/1280-tanjiro-236A-1-projectile.jpg" src="comparison.mp4"></video>
<p><a href="after.mp4">修改后完整画面</a> · <a href="before.mp4">修改前完整画面</a> · <a href="acceptance.json">检查记录</a></p>
{''.join(cards)}<details><summary>全部修改后截图</summary><ul>{links}</ul></details></main></html>"""
 (ART/'index.html').write_text(doc,encoding='utf-8')
def provenance(result):
 now=datetime.now(timezone.utc).isoformat();sources=[]
 for job in [j for j in read(RUN/'jobs.json') if j['group']=='combat-polish']:
  rp=RUN/'records'/(job['id']+'.json');record=read(rp);source=ROOT/job['out']
  with Image.open(source) as image:size=list(image.size)
  record.update(accepted=True,actual_size=size,sha256=sha(source),review=dict(status='accepted_for_combat_polish',reviewed_utc=now,evidence='artifacts/combat-polish/index.html'))
  write(rp,record);sources.append(record)
 master=ROOT/'output/imagegen/manifest.json';history=ROOT/'output/imagegen/history/pre-combat-polish-manifest.json'
 if not history.exists():shutil.copy2(master,history)
 data=read(master)
 data.update(revision='combat-polish-v2',generated_utc=now,previous_manifest=rel(history),gameplay_changes=['Forward dash jump inherits 1.5x ordinary jump horizontal speed; height and timing unchanged.'],combat_polish=dict(sources=sources,manifest='output/imagegen/combat-polish-manifest.json',acceptance='artifacts/combat-polish/acceptance.json',review='artifacts/combat-polish/index.html'))
 for cid in ('tanjiro','zenitsu'):
  atlas=read(ROOT/'art/characters'/cid/'atlas.json')
  data['characters'][cid]['frames']=sum(len(c['frames']) for c in atlas['clips'].values())
 inventory=[]
 for p in sorted((ROOT/'art').rglob('*')):
  if not p.is_file() or p.suffix not in ('.png','.jpg','.json','.ttf'):continue
  item=dict(path=rel(p),bytes=p.stat().st_size,sha256=sha(p))
  if p.suffix in ('.png','.jpg'):
   with Image.open(p) as image:item.update(size=list(image.size),mode=image.mode)
  inventory.append(item)
 data['inventory']=inventory;write(master,data)
 print('COMBAT POLISH ACCEPTANCE:',result['real_input_cases'],'unchanged move scenarios;',result['matching_simulation_ticks'],'matching ticks;',result['screenshots'])
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--encode',action='store_true')
 parser.add_argument('--ffmpeg',default=shutil.which('ffmpeg') or r'E:\Program Files\ffmpeg-7.1.1-essentials_build\bin\ffmpeg.exe')
 args=parser.parse_args();result,after=acceptance()
 if args.encode:encode(args.ffmpeg)
 gallery(result,after);provenance(result)
if __name__=='__main__':main()
