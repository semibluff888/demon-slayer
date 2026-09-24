"""Encode actual Godot round captures with their recorded in-game audio cues."""
import json,subprocess,wave
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/round-selected'
FFMPEG=Path('E:/Program Files/ffmpeg-7.1.1-essentials_build/bin/ffmpeg.exe')

def soundtrack(name,info):
    rate=22050;mix=np.zeros(round(info['frames']/info['fps']*rate)+1,dtype=np.float32)
    for event in info['events']:
        with wave.open(str(OUT/'audio'/(event['kind']+'.wav')),'rb') as w:
            assert w.getframerate()==rate and w.getsampwidth()==2
            samples=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(np.float32)/32768
            if w.getnchannels()>1:samples=samples.reshape(-1,w.getnchannels()).mean(axis=1)
        at=round(event['tick']/60*rate);end=min(len(mix),at+len(samples))
        if end>at:mix[at:end]+=samples[:end-at]*event.get('gain',1)*0.35
    with wave.open(str(OUT/(name+'.wav')),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate);w.writeframes((np.clip(mix,-1,1)*32767).astype('<i2').tobytes())

def main():
    data=json.loads((OUT/'capture.json').read_text(encoding='utf-8'))
    for name in ['tanjiro-wins','zenitsu-wins']:
        info=json.loads((OUT/(name+'.json')).read_text(encoding='utf-8'));soundtrack(name,info)
        subprocess.run([str(FFMPEG),'-hide_banner','-loglevel','error','-y','-framerate',str(info['fps']),'-i',str(OUT/'frames'/name/'frame-%05d.jpg'),'-i',str(OUT/(name+'.wav')),'-frames:v',str(info['frames']),'-c:v','libx264','-preset','medium','-crf','19','-pix_fmt','yuv420p','-c:a','aac','-b:a','128k','-shortest','-movflags','+faststart',str(OUT/(name+'.mp4'))],check=True)
        print('Encoded',name,info['frames'],'frames',flush=True)
    preview=OUT/'review';preview.mkdir(exist_ok=True)
    for source in list(OUT.glob('*.jpg'))+list((OUT/'matrix').glob('1280-*-corner-11.jpg')):
        im=Image.open(source);im.thumbnail((1000,600));im.save(preview/source.name,quality=70)
    for cid in ['tanjiro','zenitsu']:
        rows=[]
        for prefix in ['opening','ground','victory']:
            candidates=[e for e in data['captures'] if e['width']==1280 and e['character']==cid and ('-right-'+prefix+'-') in e['name']]
            for offset in range(0,len(candidates),4):rows.append(candidates[offset:offset+4])
        sheet=Image.new('RGB',(1200,len(rows)*235),'#152033');draw=ImageDraw.Draw(sheet)
        for row,entries in enumerate(rows):
            for col,e in enumerate(entries):
                im=Image.open(OUT/'matrix'/(e['name']+'.jpg'))
                x,y=e['root_screen'];im=im.crop((int(x-170),int(y-260),int(x+170),int(y+35)))
                im=im.resize((255,221),Image.Resampling.LANCZOS)
                sheet.paste(im,(col*300,row*235+14));draw.text((col*300+5,row*235),e['clip']+' '+str(e['drawing']),fill='white')
        sheet.save(preview/(cid+'-engine-poses.jpg'),quality=80)
    html='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>正式游戏 · 选定回合动作</title><style>
    :root{color-scheme:dark}body{margin:0;background:#101827;color:#ece5d8;font:16px "Microsoft YaHei",sans-serif}main{max-width:1300px;margin:auto;padding:36px 24px}h1{font-size:30px;color:#ecd1a0}p{color:#bec8d6;line-height:1.8}.grid{display:grid;grid-template-columns:1fr 1fr;gap:24px}article{background:#1a2638;border:1px solid #34465e;border-radius:12px;overflow:hidden}h2{font-size:20px;padding:0 20px}video{width:100%;display:block}article p{padding:0 20px}button{border:1px solid #667287;background:#213149;color:#e4dac8;border-radius:4px;padding:8px 12px;cursor:pointer}nav{display:flex;flex-wrap:wrap;gap:8px;padding:4px 20px 20px}a{color:#edd09a}details{margin-top:24px}summary{cursor:pointer;padding:12px 0}img{max-width:100%}@media(max-width:820px){.grid{grid-template-columns:1fr}main{padding:24px 12px}}</style><main>
    <h1>选定动作已接入正式游戏</h1><p>双方同时表演 2 秒，随后 ROUND → READY → GO!。以下两段录像使用正式游戏场景和普通对战输入，各展示一人的胜利与另一人的落败。</p><div class="grid">
    <article><h2>炭治郎胜利 · 善逸落败</h2><video controls playsinline preload="metadata" poster="tanjiro-wins.jpg" src="tanjiro-wins.mp4"></video><p>炭治郎 C 开场，无火弧；A 胜利。善逸 D 开场；修订 C 落败，痛苦表情与更远后飞。</p><nav><button data-time="0">开场</button><button data-time="4.45">KO 与胜利</button><button data-speed=".25">0.25 倍</button><button data-speed=".5">0.5 倍</button><button data-speed="1">原速</button></nav></article>
    <article><h2>善逸胜利 · 炭治郎落败</h2><video controls playsinline preload="metadata" poster="zenitsu-wins.jpg" src="zenitsu-wins.mp4"></video><p>善逸 D 开场与胜利。炭治郎后飞时单手握刀，背部触地后松手，伸展倒地，刀落在手边。</p><nav><button data-time="0">开场</button><button data-time="4.45">KO 与掉刀</button><button data-speed=".25">0.25 倍</button><button data-speed=".5">0.5 倍</button><button data-speed="1">原速</button></nav></article></div>
    <p>固定人物比例与正式待机一致；普通 KO 在有空间时向后飞约 122 个世界单位，镜头保持 3 倍比例。版边限制位移，镜头平移容纳倒地身体。致命投技保持原受投落地朝向与末帧，不重复落地。KO 定格 0.15 秒后进入慢放；长招式完成后再接胜利。</p>
    <details><summary>炭治郎 · 实际引擎逐帧</summary><img src="review/tanjiro-engine-poses.jpg"></details><details><summary>善逸 · 实际引擎逐帧</summary><img src="review/zenitsu-engine-poses.jpg"></details>
    <p>Godot 实际渲染 · 1280 × 720 · 60 FPS · 含同次运行的游戏音效。左右朝向、空中 KO、致命投技、版边及 960／1280／1920 宽度截图保存在 matrix 文件夹。</p></main><script>
    document.querySelectorAll('article').forEach(a=>{let v=a.querySelector('video');a.querySelectorAll('[data-time]').forEach(b=>b.onclick=()=>{v.currentTime=+b.dataset.time;v.play()});a.querySelectorAll('[data-speed]').forEach(b=>b.onclick=()=>{v.playbackRate=+b.dataset.speed;v.play()})});document.querySelectorAll('video').forEach(v=>v.onplay=()=>document.querySelectorAll('video').forEach(w=>{if(w!==v)w.pause()}));</script></html>'''
    (OUT/'index.html').write_text(html,encoding='utf-8')
    print('Wrote engine comparison page and pose sheets.')
if __name__=='__main__':main()