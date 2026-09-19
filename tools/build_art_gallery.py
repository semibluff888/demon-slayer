"""Build a fully local review page; originals, GIFs and engine captures stay local."""
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAMES = {'idle':'待机', 'walk':'前进', 'walk_back':'后退', 'crouch':'蹲下',
         'jump':'跳跃与落地', 'guard':'站防', 'guard_low':'低防', 'hit':'受击',
         'knockdown':'倒地', 'throw':'投技', 'victory':'胜利',
         'stand_light':'站立轻攻', 'stand_heavy':'站立重攻',
         'crouch_light':'蹲下轻攻', 'crouch_heavy':'蹲下重攻',
         'air_light':'空中轻攻', 'air_heavy':'空中重攻',
         'water_slash':'水面斩', 'water_wheel':'水车', 'iai':'居合斩', 'thunder':'霹雳一闪'}

def main():
    body = ['''<!doctype html><html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>月下对决 · 美术验收</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#0b1221;color:#f1e8d7;font:16px/1.7 system-ui,"Microsoft YaHei",sans-serif}
main{max-width:1320px;margin:auto;padding:48px 32px}h1{font:54px/1.2 Georgia,serif;margin:10px 0 24px}h2{font-weight:500;margin-top:56px}
p{color:#b4bdd0;max-width:850px}a{color:#d9ba80}nav{display:flex;gap:24px;flex-wrap:wrap;margin:30px 0}.eyebrow{color:#dab875;letter-spacing:.2em}
video{width:100%;background:#142038;border:1px solid #827047}.stills{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:22px}
figure{margin:0;background:#142038}figure img{display:block;width:100%;height:auto}figcaption{padding:12px 16px;color:#ceb98b;font-size:14px}
.motions{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px}.motions img{aspect-ratio:480/340;object-fit:contain}
small{color:#b4bdd0}details{margin:30px 0}summary{cursor:pointer;color:#d9ba80;font-size:24px}code{font-size:13px}
@media(max-width:800px){main{padding:24px 16px}h1{font-size:38px}.stills,.motions{grid-template-columns:1fr}}
</style><main><div class="eyebrow">MOONLIT DUEL / ART REVIEW</div><h1>月下对决 · 美术验收</h1>
<p>本地交付预览。下方视频由实际 Godot 对战渲染，包含水面斩、水车、居合斩、霹雳一闪。动作联系表与循环预览用于检查人物、刀身和画帧衔接；游戏中的攻击帧按原有起手／有效／收招阶段播放。</p>
<nav><a href="#combat">实际对战</a><a href="#screens">界面截图</a><a href="#tanjiro">炭治郎动作</a><a href="#zenitsu">善逸动作</a><a href="visual-acceptance.md">验收记录</a><a href="../output/imagegen/manifest.json">素材清单</a></nav>
<h2 id="combat">实际对战 · 四个专属技能</h2><video controls loop muted playsinline preload="metadata" poster="move-water_slash.png" src="combat-preview.mp4"></video>
<p><small>960×540 · 15 FPS 预览编码；对战按 60Hz 固定逻辑推进。预览编码帧率不代表游戏运行性能。</small></p>
<h2 id="screens">实际游戏截图</h2><div class="stills">''']
    for name, title in [('01-title','主菜单'),('03-select','角色选择'),('duel-neutral','战斗 HUD'),
                        ('move-water_wheel','水车'),('04-pause','暂停'),('02-controls','操作指南'),
                        ('07-results','结算'),('mirror-zenitsu','同角色对战')]:
        body.append('<figure><a href="{0}.png"><img loading="lazy" src="{0}.png" alt="{1}"></a><figcaption>{1}</figcaption></figure>'.format(name,title))
    body.append('</div>')
    for character, title in [('tanjiro','灶门炭治郎'),('zenitsu','我妻善逸')]:
        atlas = json.loads((ROOT/'art/characters'/character/'atlas.json').read_text(encoding='utf-8'))
        body.append('<h2 id="{}">{} · 19 组动作 / 112 帧</h2><div class="motions">'.format(character,title))
        for clip, data in atlas['clips'].items():
            stem = '../output/imagegen/anime-v2/review/' + character + '-' + clip
            body.append('<figure><a href="{0}.jpg"><img src="{0}.gif" alt="{1} {2} 连续动作"></a><figcaption>{2} · {3} 帧　<code>{4}</code></figcaption></figure>'.format(stem,title,NAMES[clip],len(data['frames']),html.escape(clip)))
        body.append('</div>')
    body.append('<p>点击动作可查看按时间排列的全部画帧。提示词、原始图、请求记录和实测切片保存在 output/imagegen/anime-v2/。全部预览无需联网。</p></main></html>')
    (ROOT/'artifacts/gallery.html').write_text(''.join(body),encoding='utf-8')
    print('Local art gallery: artifacts/gallery.html')

if __name__ == '__main__':
    main()
