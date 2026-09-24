"""Review the actual production-engine KO captures, never synthesized animation."""
import json
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw
import review_round_selected as audio

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/round-polish'
TITLES = {'tanjiro_623C': '炭治郎 · 水车击败后完整收招', 'tanjiro_max': '炭治郎 · MAX 击败后完整收招', 'zenitsu_super': '善逸 · 第一斩 KO 后继续六连', 'zenitsu_max': '善逸 · 神速击败后完整收招'}
NAMES = {'tanjiro':'炭治郎','zenitsu':'善逸'}

def load(path):
    return json.loads(path.read_text(encoding='utf-8'))

def encode(info):
    name = info['name']
    audio.OUT = OUT
    audio.soundtrack(name, info)
    subprocess.run([str(audio.FFMPEG), '-hide_banner', '-loglevel', 'error', '-y', '-framerate', '60', '-i', str(OUT/'frames'/name/'frame-%05d.jpg'), '-i', str(OUT/(name+'.wav')), '-frames:v', str(info['frames']), '-c:v', 'libx264', '-preset', 'medium', '-crf', '19', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '128k', '-shortest', '-movflags', '+faststart', str(OUT/(name+'.mp4'))], check=True)
    at = min(info['frames']-1, info['moments']['ko']+45)
    im = Image.open(OUT/'frames'/name/('frame-%05d.jpg' % at))
    im.thumbnail((960,540)); im.save(OUT/(name+'.jpg'), quality=76)
    print('Encoded', name, info['frames'], 'frames', flush=True)

def contact_sheet(info, entries, path):
    cols = 3
    sheet = Image.new('RGB', (1200, ((len(entries)+cols-1)//cols)*250), '#111b2d')
    draw = ImageDraw.Draw(sheet)
    for n, (label, source) in enumerate(entries):
        im = Image.open(source); im.thumbnail((400,225))
        x,y=(n%cols)*400,(n//cols)*250
        sheet.paste(im,(x,y+25)); draw.text((x+8,y+7),label, fill='#efd0a0')
    sheet.save(path, quality=78)

def engine_sizes():
    base=ROOT/'artifacts/round-selected'
    entries={e['name']:e for e in load(base/'capture.json')['captures']}
    sheet=Image.new('RGB',(1200,580),'#101b2d');draw=ImageDraw.Draw(sheet)
    poses=[('OPENING 0','opening-000'),('OPENING LAST','opening-119'),('ROUND / IDLE','opening-120'),('DEFEAT HOLD','ground-11')]
    for row,cid in enumerate(['tanjiro','zenitsu']):
        for col,(label,suffix) in enumerate(poses):
            key='1280-'+cid+'-right-'+suffix;e=entries[key];x,y=e['root_screen']
            im=Image.open(base/'matrix'/(key+'.jpg')).crop((round(x-190),round(y-280),round(x+190),round(y+32))).resize((300,246),Image.Resampling.LANCZOS)
            sheet.paste(im,(col*300,row*290+30));draw.text((col*300+6,row*290+10),cid.upper()+' / '+label,fill='#efd0a0')
    sheet.save(OUT/'sizes-engine.jpg',quality=76)

def card(title, src, poster, description, ko=0, victory=0):
    return f'''<article><h2>{title}</h2><video controls playsinline preload="metadata" poster="{poster}" src="{src}"></video><p>{description}</p><nav><button data-time="0">重播</button><button data-time="{max(0,ko-.2):.3f}">KO 前后</button><button data-time="{victory:.3f}">胜利动作</button><button data-speed=".25">0.25 倍</button><button data-speed=".5">0.5 倍</button><button data-speed="1">原速</button></nav></article>'''

def main():
    data = load(OUT/'capture.json')
    assert not data['failures'], data['failures']
    for info in data['captures']:
        assert len(info['freeze_hashes']) == 9 and len(set(info['freeze_hashes'])) == 1
    for info in data['movies']: encode(info)
    engine_sizes()
    normal=[]
    for name in ['tanjiro-wins','zenitsu-wins']:
        info = load(ROOT/'artifacts/round-selected'/(name+'.json'))
        title = '炭治郎胜利 · 善逸落败' if name.startswith('tanjiro') else '善逸胜利 · 炭治郎落败'
        normal.append(card(title, '../round-selected/'+name+'.mp4', '../round-selected/'+name.removesuffix('-wins')+'-opening.jpg', '正式游戏普通对局输入。开场 2 秒 → ROUND → READY → GO!，查看开场与待机尺寸衔接、普通 KO 后飞和倒地。', info['moments']['ko']/60, (info['moments']['ko']+90)/60))
    skill=[]; throws=[]
    for info in data['movies']:
        name=info['name']; ko=info['moments']['ko']; victory=info['moments']['victory']
        if info['throw']:
            title=NAMES[info['loser']]+'落败 · '+('反投' if info['back'] else '正投')
            desc='摔落扣血时定格，慢放继续原受投收尾，保持同一朝向与最终躺卧，不再播放第二次落地。'
            throws.append(card(title,name+'.mp4',name+'.jpg',desc,ko/60,victory/60))
        else:
            desc='击败后保留正在施放的动作、位移、特效与后续斩击音效；不再判定伤害，完整收招后展示胜利 2 秒。'
            if name=='zenitsu_super': desc+=' 本段保留全部 6 次斩击。'
            skill.append(card(TITLES[name],name+'.mp4',name+'.jpg',desc,ko/60,victory/60))
            entries=[]
            for label, at in [('LETHAL HIT / FREEZE',ko), ('END OF QUARTER SPEED',ko+39), ('FINAL SKILL DRAWING',info['moments']['recovered']-1), ('VICTORY START',victory), ('VICTORY HOLD',min(info['frames']-1,victory+100))]:
                entries.append((label,OUT/'frames'/name/('frame-%05d.jpg'%at)))
            contact_sheet(info, entries, OUT/(name+'-engine.jpg'))
    # The impacted and settled frames are cropped from actual GPU captures.
    for winner in ['tanjiro','zenitsu']:
        entries=[]
        for direction in ['forward','back']:
            name=winner+'-throw-'+direction+'-right'
            for frame in [19,20,29,30]: entries.append((direction.upper()+' / THROW '+str(frame), OUT/'matrix'/(name+'-throw-%02d.jpg'%frame)))
            entries.append((direction.upper()+' / FINAL HOLD',OUT/'matrix'/(name+'-ko-190.jpg')))
        contact_sheet({},entries,OUT/(winner+'-throws-engine.jpg'))
    head='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>回合动作优化 · 实机验收</title><style>
    :root{color-scheme:dark}body{margin:0;background:#101827;color:#ede7db;font:16px "Microsoft YaHei",sans-serif}main{max-width:1320px;margin:auto;padding:32px 24px}h1{font-size:30px;color:#efd0a0}h2{font-size:20px}p{line-height:1.8;color:#c2cad5}.grid{display:grid;grid-template-columns:1fr 1fr;gap:24px}article{background:#19263a;border:1px solid #35465d;border-radius:12px;overflow:hidden}article h2,article p{margin:18px 20px}video{width:100%;display:block}nav{display:flex;gap:8px;flex-wrap:wrap;margin:16px 20px 20px}button{color:#eee0c8;background:#24354b;border:1px solid #647186;border-radius:4px;padding:8px 10px;cursor:pointer}details{margin-top:24px}summary{padding:14px 0;cursor:pointer;color:#efd0a0;font-size:20px}img{max-width:100%;border-radius:6px}a{color:#efd0a0}.timing{padding:15px 20px;border-left:3px solid #caaa72;background:#192335}@media(max-width:860px){.grid{grid-template-columns:1fr}main{padding:24px 12px}}</style><main>
    <h1>回合动作优化 · 正式游戏实机</h1><p>炭治郎开场与倒地比例、善逸开场前段已校准；正反投保持实际落地朝向；胜者先完成正在释放的招式，再接胜利动画。</p>
    <p class="timing">KO 定格 0.15 秒 → 0.25 倍速慢放 0.5 秒 → 正常收尾 → 胜利展示 2 秒。普通 KO 总计 3.5 秒；长招式会延后胜利开始，完整保留两秒展示。</p>
    <div class="grid">'''
    body=''.join(normal)+'</div><h2>必杀与超杀完整收招</h2><div class="grid">'+''.join(skill)+'</div><details open><summary>致命正投与反投</summary><div class="grid">'+''.join(throws)+'</div></details>'
    body+='''<details><summary>尺寸校准对照</summary><p>下图为相同引擎镜头比例下的开场首帧、末帧、ROUND 待机和倒地末帧。</p><img src="sizes-engine.jpg"><p>三列依次为正式待机、修改前、修改后。原画注册时修正体型，运行时始终使用同一人物标尺与 3 倍镜头。</p><img src="tanjiro-round_intro-compare.jpg"><img src="tanjiro-round_defeat-compare.jpg"><img src="zenitsu-round_intro-compare.jpg"></details>'''
    body+='''<details><summary>正反投连续实机截图</summary><p>含扣血前、扣血定格、原受投收尾与最终躺卧。左右镜像验证在 matrix 文件夹。</p><img src="tanjiro-throws-engine.jpg"><img src="zenitsu-throws-engine.jpg"></details><details><summary>六连完整收招与胜利衔接</summary><img src="zenitsu_super-engine.jpg"></details>'''
    footer='''<p>1280 × 720 · 60 FPS · 正式 Godot 场景 · 同次事件音效。开场完整对局使用普通输入；长技能与投技使用低血量测试布置，再由正式战斗逻辑完成。12 个场景的 9 张 KO 定格原始画面逐像素一致。完整回归通过；30／60／144 FPS 的确定性摘要一致。</p><p><a href="../round-selected/index.html">完整回合与多分辨率矩阵</a> · <a href="capture.json">实机验收记录</a></p></main><script>
    document.querySelectorAll('article').forEach(a=>{let v=a.querySelector('video');a.querySelectorAll('[data-time]').forEach(b=>b.onclick=()=>{v.currentTime=+b.dataset.time;v.play()});a.querySelectorAll('[data-speed]').forEach(b=>b.onclick=()=>{v.playbackRate=+b.dataset.speed;v.play()})});document.querySelectorAll('video').forEach(v=>v.onplay=()=>document.querySelectorAll('video').forEach(w=>{if(w!==v)w.pause()}));</script></html>'''
    (OUT/'index.html').write_text(head+body+footer,encoding='utf-8')
    print('Wrote',OUT/'index.html',flush=True)

if __name__=='__main__': main()