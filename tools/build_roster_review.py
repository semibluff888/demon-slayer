# coding: utf-8
"""Build local delivery and provenance pages; optionally encode recorded Godot frames."""
import argparse,html,json,subprocess
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'artifacts/roster-v1'
OUT=ROOT/'output/imagegen/roster-v1'
STYLE="""body{background:#09111f;color:#f9edd1;font:16px/1.6 system-ui;margin:0 auto;max-width:1200px;padding:36px}h1{font-size:38px}h2{margin-top:48px}p,small{color:#bbc7d6}a{color:#8addde}img,video{width:100%;background:#111c2c;border-radius:8px}section{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:24px}figure{margin:0}figcaption{padding:10px 0}table{width:100%;border-collapse:collapse}td,th{padding:10px;text-align:left;border-bottom:1px solid #304056}code{color:#f298b8}"""
def write(path,title,body):
 path.write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'+title+'</title><style>'+STYLE+'</style><body><h1>'+title+'</h1>'+body+'</body></html>',encoding='utf-8')
def encode(ffmpeg):
 for folder in ['video','stage-video']:
  subprocess.run([str(ROOT/'.venv/Scripts/python.exe'),str(ROOT/'tools/mix_phase2_audio.py'),'battle-ui','--folder',str(ART/folder)],check=True)
  cue=json.loads((ART/folder/'cues.json').read_text(encoding='utf-8'));chapters=cue['chapters']
  for index,chapter in enumerate(chapters):
   start=chapter['start_seconds'];end=chapters[index+1]['start_seconds'] if index+1<len(chapters) else cue['frames']/30
   name=chapter.get('character',chapter.get('stage'))
   subprocess.run([ffmpeg,'-y','-hide_banner','-loglevel','error','-framerate','30','-start_number',str(round(start*30)),'-i',str(ART/folder/'frame-%05d.jpg'),'-ss',str(start),'-i',str(ART/folder/'soundtrack.wav'),'-frames:v',str(round((end-start)*30)),'-t',str(end-start),'-c:v','libx264','-preset','fast','-crf','20','-pix_fmt','yuv420p','-c:a','aac','-b:a','160k','-movflags','+faststart',str(ART/(name+'.mp4'))],check=True)
def main():
 p=argparse.ArgumentParser();p.add_argument('--encode',action='store_true');p.add_argument('--ffmpeg',default=r'E:\Program Files\ffmpeg-7.1.1-essentials_build\bin\ffmpeg.exe');args=p.parse_args()
 if args.encode:encode(args.ffmpeg)
 body='<p>四角色 · 三地图 · 街机菜单。全部画面来自 Godot 实机；视频包含游戏音效。</p><p><a href="../../docs/roster-expansion.md">接入、验证与复现说明</a> · <a href="../../output/imagegen/roster-v1/index.html">提示词与原始素材</a></p>'
 body+='<h2>菜单</h2><section>'
 for key,name in [('title','主菜单'),('select','选择角色'),('stages','选择场景')]:
  body+=f'<figure><a href="3840x2160-{key}.png"><img src="1280x720-{key}.png"></a><figcaption>{name} · 点击查看 4K 截图</figcaption></figure>'
 body+='</section><p>分辨率：'
 for size in ['960x540','1280x720','1920x1080','3840x2160','1600x1000']:
  body+=f'<a href="{size}-select.png">{size}</a> &nbsp; '
 body+='</p><h2>角色动作与奥义</h2><section>'
 for cid,name in [('nezuko','祢豆子'),('akaza','猗窝座')]:
  body+=f'<figure><video controls preload="metadata" src="{cid}.mp4"></video><figcaption>{name} · 12 普通技、投技、翻滚、6 必杀、奥义／MAX、开场与 KO</figcaption></figure>'
 body+='</section><h2>新地图卷动</h2><section>'
 for sid,name in [('infinity_castle','无限城'),('entertainment_district','游郭夜街')]:
  body+=f'<figure><video controls preload="metadata" poster="stage-{sid}.png" src="{sid}.mp4"></video><figcaption>{name} · <a href="stage-{sid}-left.png">左边界</a> / <a href="stage-{sid}-right.png">右边界</a></figcaption></figure>'
 body+='</section><p>角色视频约 66 秒／人，地图卷动 15 秒／张。模拟保持 60 Hz，录像输出为 1280×720、30 FPS。</p>'
 write(ART/'index.html','月下对决 · 四角色与三地图',body)
 body='<p>CPA API/CLI · gpt-image-2。原始输出、提示词、实际尺寸、裁切与拒绝记录均保留。离线重建不调用服务。</p><p><a href="../../../docs/roster-expansion.md">复现说明</a> · <a href="jobs.json">完整清单</a> · <a href="calibration.json">动画校准</a> · <a href="portrait-calibration.json">立绘／特写校准</a></p><table><tr><th>资产</th><th>类别</th><th>实际尺寸</th><th>记录</th></tr>'
 for job in json.loads((OUT/'jobs.json').read_text(encoding='utf-8')):
  record=json.loads((OUT/'records'/(job['id']+'.json')).read_text(encoding='utf-8-sig'))
  name=html.escape(job['id']);group=html.escape(job['group']);size=' × '.join(map(str,record.get('actual_size',[])))
  body+=f'<tr><td><a href="raw/{name}.png">{name}</a></td><td>{group}</td><td>{size}</td><td><a href="prompts/{name}.txt">提示词</a> / <a href="records/{name}.json">来源</a></td></tr>'
 write(OUT/'index.html','roster-v1 · 生图与资产记录',body+'</table>')
 print('Delivery and asset provenance pages ready.')
if __name__=='__main__':main()
