# -*- coding: utf-8 -*-
"""Encode actual engine captures and build the local review page (offline)."""
import argparse, json, subprocess, wave
from pathlib import Path
import numpy as np
HERE=Path(__file__).resolve().parent
OUT=HERE/'previews'
FFMPEG=Path('E:/Program Files/ffmpeg-7.1.1-essentials_build/bin/ffmpeg.exe')
NAMES={'tanjiro':'灶门炭治郎','zenitsu':'我妻善逸'}
def soundtrack(path,seconds,events):
 rate=22050
 mix=np.zeros(int(seconds*rate)+1,dtype=np.float32)
 for event in events:
  source=OUT/'audio'/(event['kind']+'.wav')
  with wave.open(str(source),'rb') as w:
   assert w.getframerate()==rate and w.getsampwidth()==2
   samples=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(np.float32)/32768
   if w.getnchannels()>1:samples=samples.reshape(-1,w.getnchannels()).mean(axis=1)
  at=round(event['tick']/60*rate);end=min(len(mix),at+len(samples))
  if end>at:mix[at:end]+=samples[:end-at]*event.get('gain',0.65)*0.35
 pcm=(np.clip(mix,-1,1)*32767).astype('<i2')
 with wave.open(str(path),'wb') as w:
  w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate);w.writeframes(pcm.tobytes())
def encode(only=None):
 cues=[dict(tick=t,kind=k) for t,k in [(120,'select'),(174,'select'),(216,'fight'),(312,'hit'),(318,'round_end'),(402,'select'),(552,'hit'),(558,'round_end'),(642,'select')]]
 soundtrack(OUT/'demo.wav',381/30,cues)
 dirs=[x for x in (OUT/'frames').iterdir() if x.is_dir()]
 for directory in dirs:
  if only and directory.name!=only:continue
  frames=len(list(directory.glob('frame-*.jpg')))
  sound=OUT/'demo.wav'
  if directory.name=='battle':
   info=json.loads((OUT/'battle-audio.json').read_text())
   sound=OUT/'battle.wav';soundtrack(sound,frames/30,info['events'])
  destination=OUT/(directory.name+'.mp4')
  subprocess.run([str(FFMPEG),'-hide_banner','-loglevel','error','-y','-framerate','30','-i',str(directory/'frame-%05d.jpg'),'-i',str(sound),'-frames:v',str(frames),'-c:v','libx264','-preset','medium','-crf','19','-pix_fmt','yuv420p','-c:a','aac','-b:a','128k','-shortest','-movflags','+faststart',str(destination)],check=True)
  print('Encoded',destination.name,frames,flush=True)
def page():
 variants=json.loads((HERE/'variants.json').read_text(encoding='utf-8'))
 cards=[]
 for v in variants:
  key=v['character']+'-'+v['id'].lower()
  cards.append(f"""<article data-character="{v['character']}"><div class="card-title"><span>{NAMES[v['character']]}</span><b>{v['id']} · {v['name']}</b></div><video controls playsinline preload="none" poster="previews/{key}.jpg" src="previews/{key}.mp4"></video><div class="chapters"><button data-time="0">开场</button><button data-time="5.2">终结与胜利</button><button data-time="9.2">落败</button><button data-speed=".5">半速</button><button data-speed="1">原速</button></div><p>18 帧开场 · 18 帧胜利 · 12 帧倒地</p><div class="links"><a href="review/{v['character']}-{v['id'].lower()}_intro.jpg">开场画帧</a><a href="review/{v['character']}-{v['id'].lower()}_victory.jpg">胜利画帧</a><a href="review/{v['character']}-{v['id'].lower()}_defeat.jpg">倒地画帧</a></div></article>""")
 html="""<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>月下对决 · 回合动作方案</title>
<style>
:root{color-scheme:dark;--gold:#e7c891;--ink:#0b1120;--paper:#f4ebd9}*{box-sizing:border-box}body{margin:0;background:radial-gradient(ellipse at top,#263244,#0b1120 60%);color:var(--paper);font-family:"Microsoft YaHei","Segoe UI",sans-serif}main{max-width:1420px;margin:auto;padding:48px 32px 72px}.eyebrow{letter-spacing:.3em;color:var(--gold);font-size:12px}h1{font-family:Georgia,"Microsoft YaHei",serif;font-size:38px;margin:12px 0 16px}header p{max-width:880px;line-height:1.9;color:#c0c5cc}nav,.chapters,.links{display:flex;gap:12px;flex-wrap:wrap}nav{margin:28px 0}button,a{font:inherit}button{border:1px solid #65708255;background:#1b2739;color:var(--paper);border-radius:6px;padding:9px 15px;cursor:pointer}button:hover,button.active{border-color:var(--gold);color:var(--gold)}a{color:var(--gold);text-decoration:none}a:hover{text-decoration:underline}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}article{overflow:hidden;border:1px solid #62738b44;background:#121c2cbb;border-radius:12px}.card-title{display:flex;justify-content:space-between;padding:20px 22px;font-size:15px}.card-title b{color:var(--gold);font-size:19px}video{width:100%;display:block;background:#080b11;aspect-ratio:16/9}.chapters{padding:16px 18px 0;gap:8px}.chapters button{font-size:13px;padding:7px 11px}article p{font-size:12px;color:#9ba8b8;padding:0 20px}.links{padding:0 20px 20px;font-size:13px}.battle{max-width:960px;margin:48px auto 0}.battle h2{font-size:23px}.battle p{color:#b5c0cc;line-height:1.8}footer{margin-top:32px;color:#99a8bd;font-size:13px;line-height:1.9}[hidden]{display:none!important}@media(max-width:820px){.grid{grid-template-columns:1fr}main{padding:30px 16px}h1{font-size:28px}}
</style><main><header><div class="eyebrow">MOONLIT DUEL / MOTION STUDIES</div><h1>回合之间，也有角色的性格。</h1><p>炭治郎与善逸，各四套开场、胜利和倒地方案。点击播放，在同一舞台、比例和节奏下比较。每段录像先展示双方开场与当前角色获胜，再展示当前角色落败。</p>
<p><a href="launch.cmd">独立 Godot demo</a> · 支持方案切换、镜像、慢速和时间轴；也可在文件夹中双击 launch.cmd。</p>
</header><nav><button class="active" data-filter="all">全部 8 套</button><button data-filter="tanjiro">炭治郎</button><button data-filter="zenitsu">善逸</button><button id="pause-all">全部暂停</button></nav><section class="grid">"""+''.join(cards)+"""</section><section class="battle"><h2>早期回合节奏录像</h2><video controls preload="none" poster="previews/battle-stages.jpg" src="previews/battle.mp4"></video><p>ROUND → READY → GO!；KO 定格 0.1 秒、0.25 倍速慢放 0.5 秒，结束演出共 3.5 秒。录像包含普通 KO、超时和双 KO。此处保留早期候选演示；当前正式游戏已接入选定动作，<a href="../../artifacts/round-polish/index.html">查看最新实机优化</a>。</p></section>
<footer>384 幅新动作画帧 · 24 段独立动画 · Godot 实际引擎录制 / 1280 × 720 / 30 FPS<br>逐帧联系表、来源记录及离线重建说明均保存在本文件夹。选择时可直接告诉我，例如“炭治郎 B、善逸 D”。</footer></main>
<script>
document.querySelectorAll('[data-filter]').forEach(b=>b.onclick=()=>{document.querySelectorAll('[data-filter]').forEach(x=>x.classList.toggle('active',x===b));document.querySelectorAll('article').forEach(c=>{c.hidden=b.dataset.filter!=='all'&&c.dataset.character!==b.dataset.filter;if(c.hidden)c.querySelector('video').pause()})});
document.querySelectorAll('article').forEach(c=>{let v=c.querySelector('video');c.querySelectorAll('[data-time]').forEach(b=>b.onclick=()=>{v.currentTime=Number(b.dataset.time);v.play()});c.querySelectorAll('[data-speed]').forEach(b=>b.onclick=()=>{v.playbackRate=Number(b.dataset.speed);v.play()})});
document.querySelectorAll('video').forEach(v=>v.addEventListener('play',()=>document.querySelectorAll('video').forEach(x=>{if(x!==v)x.pause()})));
document.getElementById('pause-all').onclick=()=>document.querySelectorAll('video').forEach(v=>v.pause());
</script></html>"""
 (HERE/'index.html').write_text(html,encoding='utf-8')
 print('Wrote index.html')
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--encode',action='store_true');ap.add_argument('--only');args=ap.parse_args()
 if args.encode:encode(args.only)
 page()
