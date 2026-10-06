# coding: utf-8
"""Build a local review from actual Godot captures and passing checks. No network."""

from pathlib import Path

import argparse, html, json, re, shutil, subprocess

ROOT=Path(__file__).resolve().parents[1]

OUT=ROOT/'artifacts/menu-settings'

PAGE='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>鬼灭之刃：宿命对决 · 菜单与连段改进</title>
<style>
:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:#0b111d;color:#e7edf6;font:16px/1.7 "Microsoft YaHei",sans-serif}main{max-width:1280px;margin:auto;padding:36px 24px 72px}h1{font-size:34px;margin:6px 0 12px}h2{margin:38px 0 14px;font-size:24px}p{color:#b9c6d8}a{color:#9fd3ff}img,video{display:block;width:100%}figure{margin:0;overflow:hidden;background:#141f30;border:1px solid #334153;border-radius:10px}figcaption{padding:12px 16px;color:#bbc8da;font-size:14px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:18px}.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:24px 0}.stat{background:#172337;padding:16px;border-radius:8px}.stat b{display:block;font-size:23px;color:#f2d596}.stat span{font-size:13px;color:#afbed0}.tag{color:#dbb970;letter-spacing:3px;font-size:13px}button,select{padding:9px 14px;background:#17283f;color:#e5eef9;border:1px solid #486580;border-radius:5px;font:inherit;cursor:pointer}button.active{background:#943349;border-color:#e8919f}nav{display:flex;flex-wrap:wrap;gap:10px;margin:14px 0}table{width:100%;border-collapse:collapse;background:#142034}td,th{text-align:left;padding:10px 16px;border-bottom:1px solid #314159}code{color:#f3c3d2}footer{font-size:13px;margin-top:40px;color:#9aacbf}@media(max-width:760px){.grid,.stats{grid-template-columns:1fr 1fr}main{padding:24px 14px}h1{font-size:27px}}@media(max-width:520px){.grid{grid-template-columns:1fr}}
</style><main><div class="tag">鬼灭之刃：宿命对决</div><h1>新海报、游戏设置与更宽松的升龙取消</h1>
<p>已接入游戏的实际 Godot 画面。主菜单、选人流程与暂停菜单共用新键位。</p>
<div class="stats"><div class="stat"><b>UI / JK</b><span>P1 默认 ABCD</span></div><div class="stat"><b>Num56 / Num23</b><span>P2 默认 ABCD</span></div><div class="stat"><b>+12 帧</b><span>升龙命中后的收招取消余量</span></div><div class="stat"><b>512 / 512</b><span>慢速输入连段完整命中</span></div></div>
<h2>主菜单与游戏设置</h2><p>新增多位柱和上弦鬼的对峙海报。帮助、游戏设置作为一级菜单；设置支持静音、音量、双方方向和 ABCD 改键，自动保存。点击切换截图与分辨率。</p>
<nav aria-label="界面预览"><button class="screen active" data-screen="title">主菜单</button><button class="screen" data-screen="settings">游戏设置</button><select id="resolution" aria-label="预览分辨率"><option>1280x720</option><option>960x540</option><option>1920x1080</option><option>3840x2160</option><option>1600x1000</option></select></nav>
<figure><a id="full" href="title-1280x720.png"><img id="preview" src="title-1280x720.png" alt="游戏主菜单实机截图"></a><figcaption id="caption">1280×720 实机视口截图，点击查看原图。</figcaption></figure>
<h2>菜单操作与改键</h2><div class="grid">{{PANELS}}</div><p>方向键／WASD、Tab、确认键与手柄均可操作原生控件。选人页不再显示设备弹层；控制器选项集中在游戏设置。断线可在暂停设置中切回键盘。</p>
<h2>慢速升龙接奥义／MAX</h2><p><code>5A → 5C → 623A/C → 236236A/C 或 236236A+C</code><br>以下四段演示均在升龙命中后等待 6 帧，再以每个方向保持 3 帧输入双 236。对手在首击后持续按后，奥义／MAX 仍完整命中。</p>
<figure><video id="combo" controls preload="metadata" poster="combo-nezuko.png" src="slow-uppercut-combos.mp4"></video><figcaption>真实方向与 ABCD 输入驱动，60 Hz 逻辑；30 FPS 无声录制。</figcaption></figure><nav aria-label="连段章节">{{CHAPTERS}}</nav>
<table><thead><tr><th>项目</th><th>当前设置</th></tr></thead><tbody><tr><td>升龙取消</td><td>命中确认后，有效期及收招前 12 帧</td></tr><tr><td>双 236 方向识别</td><td>42 帧；最后方向后 12 帧内按攻击</td></tr><tr><td>奥义／MAX 执行缓冲</td><td>10 帧；普通动作仍为 6 帧</td></tr><tr><td>资源与伤害</td><td>1／3 格气；全段 280／445 伤害</td></tr></tbody></table>
<p>早期收招现在也能取消；仍需命中，挥空、被防和过期输入不能取消。过期请求会清除，避免落地后意外放出奥义。参数是本项目实测调优，并非对某部拳皇／街霸帧表的复刻。</p>
<footer>完整回归与美术检查通过，新增 {{SETTINGS}} 项设置检查、{{CANCEL}} 项取消检查。30／60／144 FPS 战斗状态一致。手柄采用模拟事件验证，未连接实体手柄。<br>海报按 imagegen 提示词规范经 CPA 生成；源图实际为 1672×941，4K 截图由游戏缩放渲染。1600×1000 窗口的截图仅包含 1600×900 有效视口，不含上下留边。<br><a href="../../docs/menu-settings.md">操作、参数与离线复现</a> · <a href="full-suite.log">完整回归</a> · <a href="settings-tests.log">设置补充验证</a> · <a href="verification.json">验收记录</a> · <a href="cancel-verification.json">512 组路线</a> · <a href="../../output/imagegen/menu-settings-v1/prompts/title-ensemble-v2.txt">海报提示词</a> · <a href="../../output/imagegen/menu-settings-v1/raw/title-ensemble-v2.png">原始生图</a></footer></main>
<script>
let screen='title';const selector=document.querySelector('#resolution');function update(){const size=selector.value;const file=screen+'-'+size+'.png';document.querySelector('#preview').src=file;document.querySelector('#full').href=file;document.querySelector('#preview').alt=(screen==='title'?'主菜单':'游戏设置')+'实机截图';document.querySelector('#caption').textContent=size==='1600x1000'?'1600×1000 窗口；截图为 1600×900 有效视口，上下留边未包含。':size.replace('x','×')+' 实机视口截图，点击查看原图。';document.querySelectorAll('.screen').forEach(b=>b.classList.toggle('active',b.dataset.screen===screen));}selector.onchange=update;document.querySelectorAll('.screen').forEach(b=>b.onclick=()=>{screen=b.dataset.screen;update();});document.querySelectorAll('.chapter').forEach(b=>b.onclick=()=>{const video=document.querySelector('#combo');video.currentTime=Number(b.dataset.time);video.play();});
</script></html>'''



def read(path):

    return json.loads(path.read_text(encoding='utf-8-sig'))



def encode(ffmpeg):

    if not ffmpeg: raise ValueError('Pass --ffmpeg with a local executable path.')

    subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-framerate','30',

        '-i',str(OUT/'combo-video/frame-%05d.jpg'),'-c:v','libx264','-threads','2',

        '-preset','medium','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',

        str(OUT/'slow-uppercut-combos.mp4')],check=True)



def main():

    full=(OUT/'full-suite.log').read_text(encoding='utf-8-sig')

    if 'All checks passed.' not in full: raise ValueError('Run the full regression suite first.')

    settings=(ROOT/'artifacts/settings_tests.log').read_text(encoding='utf-8-sig')

    match=re.search(r'SETTINGS TESTS: (\d+) passed, 0 failed',settings)

    if not match: raise ValueError('Settings regression did not pass.')

    (OUT/'settings-tests.log').write_text(settings,encoding='utf-8')

    results=read(OUT/'cancel-verification.json')

    capture=read(OUT/'combo-capture.json')

    menu=read(OUT/'menu-capture.json')

    if results['failures'] or capture['failures']: raise ValueError('Cancel regression/capture failed.')

    if len(results['routes'])!=512: raise ValueError('Incomplete matchup coverage.')

    for item in menu['captures']:

        if not (OUT/item['file']).is_file(): raise ValueError('Missing captured image: '+item['file'])

    if not (OUT/'slow-uppercut-combos.mp4').is_file(): raise ValueError('Encode the combo capture first.')

    hashes=re.findall(r'hash=([a-f0-9]{64})',full)

    if len(hashes)!=3 or len(set(hashes))!=1: raise ValueError('Missing matching FPS results.')

    verification=dict(settings_checks=int(match[1]),cancel_checks=results['passed'],routes=len(results['routes']),

        frame_rate_hash=hashes[0],screenshots=menu['captures'],poster=read(ROOT/'output/imagegen/menu-settings-v1/imports/title-poster.json'),

        controller_method='Synthetic Godot joypad events, no physical controller attached.',video_frames=capture['frames'])

    (OUT/'verification.json').write_text(json.dumps(verification,ensure_ascii=False,indent=2),encoding='utf-8')

    def picture(file,caption):

        return '<figure><a href="'+file+'"><img loading="lazy" src="'+file+'" alt="'+html.escape(caption)+'"></a><figcaption>'+html.escape(caption)+'</figcaption></figure>'

    panels=''.join(picture(file,caption) for file,caption in [

        ('selection.png','选人页：保留角色选择与简短提示，移除设备入口。'),

        ('pause.png','暂停菜单：新增游戏设置；退出设置后仍保持暂停。'),

        ('key-capture.png','点击键位后直接按新键；Esc 或手柄 B 取消。'),

        ('key-conflict.png','重复键位显示冲突，原绑定不被覆盖。')])

    labels={'nezuko':'祢豆子','zenitsu':'善逸','akaza':'猗窝座','tanjiro':'炭治郎'}

    chapters=''.join('<button class="chapter" data-time="'+str(ch['frame']/30)+'">'+labels[ch['character']]+' · 623'+ch['uppercut']+' → '+('MAX' if ch['max'] else '奥义')+'</button>' for ch in capture['chapters'])

    page=PAGE.replace('{{PANELS}}',panels).replace('{{CHAPTERS}}',chapters).replace('{{SETTINGS}}',str(verification['settings_checks'])).replace('{{CANCEL}}',str(verification['cancel_checks']))

    (OUT/'index.html').write_text(page,encoding='utf-8')

    print('Review ready:',OUT/'index.html')

    print('Verified:',verification['settings_checks'],'settings checks,',verification['cancel_checks'],'cancel checks,',len(menu['captures']),'screenshots')



if __name__=='__main__':

    parser=argparse.ArgumentParser()

    parser.add_argument('--encode',action='store_true')

    parser.add_argument('--ffmpeg',default=shutil.which('ffmpeg'))

    args=parser.parse_args()

    if args.encode: encode(args.ffmpeg)

    main()

