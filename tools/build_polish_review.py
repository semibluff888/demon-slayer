# coding: utf-8
"""Build the local visual handoff from verified game captures and asset manifests."""
from pathlib import Path
import argparse,json,shutil,subprocess
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/uppercut-polish'
def encode_videos(ffmpeg):
 if not ffmpeg:raise ValueError('Install ffmpeg or pass --ffmpeg with its executable path.')
 for folder,name in [('uppercut-video','uppercuts.mp4'),('combo-video','uppercut-combos.mp4'),('courtyard-video','courtyard-hd.mp4')]:
  subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-framerate','30','-i',str(OUT/folder/'frame-%05d.jpg'),'-c:v','libx264','-threads','2','-preset','medium','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',str(OUT/name)],check=True)

def main():
 stage=json.loads((ROOT/'art/stages/corps_courtyard/stage.json').read_text(encoding='utf-8'))
 verification=json.loads((OUT/'verification.json').read_text(encoding='utf-8'))
 if stage['revision']!='courtyard-sr-v1' or verification['failures']:raise ValueError('Complete the verified HD stage before publishing the handoff')
 if 'All checks passed.' not in (OUT/'full-suite.log').read_text(encoding='utf-8-sig'):raise ValueError('Full regression suite has not completed.')
 for name in ['uppercuts.mp4','uppercut-combos.mp4','courtyard-hd.mp4','courtyard-3840x2160.png']:
  if not (OUT/name).is_file():raise ValueError('Missing handoff artifact: '+name)
 def picture(file,caption):return f'<figure><a href="{file}"><img loading="lazy" src="{file}" alt="{caption}"></a><figcaption>{caption}</figcaption></figure>'
 shots=''.join(picture(f'nezuko-{name}-before-after.png',label+'：左侧 P1 为修改前，右侧 P2 为修改后。') for name,label in [('idle','待机基准'),('B','站立轻踢 B'),('D','站立重踢 D'),('guard','蹲防')])
 arcs=picture('arc-nezuko-C-right.png','面向右：爆血圆弧朝对手一侧展开。')+picture('arc-nezuko-C-left.png','面向左：角色与特效同步镜像。')
 apex=''.join(picture('apex-'+cid+'.png',label+' · 重升龙顶点／转入下降') for cid,label in [('tanjiro','炭治郎'),('zenitsu','善逸'),('nezuko','祢豆子'),('akaza','猗窝座')])
 page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>鬼灭之刃：宿命对决 · 升龙与画面修正</title><style>
 :root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:#101522;color:#e7ebf4;font:16px/1.7 "Microsoft YaHei",sans-serif}main{max-width:1320px;margin:auto;padding:42px 28px 80px}small,.muted,figcaption{color:#a8b7c9}h1{font-size:38px;letter-spacing:2px;margin:6px 0 18px}h2{margin:45px 0 16px;border-left:4px solid #ff6393;padding-left:14px;font-size:24px}a{color:#8dd2ff}.tag{letter-spacing:3px;color:#ff8bac;font-size:13px}.stats,.grid{display:grid;grid-template-columns:1fr 1fr;gap:20px}.stats{grid-template-columns:repeat(4,1fr);margin:26px 0}.stat,figure,.video{background:#192132;border:1px solid #2d3b51;border-radius:10px;overflow:hidden;margin:0}.stat{padding:18px}.stat b{font-size:27px;display:block;color:#fff}.stat span{font-size:13px;color:#b6c3d4}figure img,video{display:block;width:100%}figcaption{padding:12px 16px;font-size:14px}table{width:100%;border-collapse:collapse;background:#192132}td,th{padding:12px;text-align:left;border-bottom:1px solid #2d3b51}code{color:#ffc1d4}.compare{position:relative;aspect-ratio:16/9;overflow:hidden;border-radius:10px}.compare img{position:absolute;width:100%;height:100%;object-fit:cover;inset:0}.compare #after{clip-path:inset(0 0 0 50%)}.compare #divider{position:absolute;inset:0 auto 0 50%;width:2px;background:white}.compare span{position:absolute;bottom:18px;background:#101522dc;padding:5px 13px;border-radius:5px}.compare .before{left:18px}.compare .after{right:18px}input[type=range]{width:100%;accent-color:#ff6c9c;margin:18px 0}footer{margin-top:40px;color:#98a8bf;font-size:13px}@media(max-width:800px){.grid,.stats{grid-template-columns:1fr}h1{font-size:28px}main{padding:24px 16px}}
 </style><main><div class="tag">鬼灭之刃：宿命对决</div><h1>升龙与画面修正</h1><p class="muted">实际 Godot 渲染画面与真实输入连段。人物保持原有身高关系。</p>
 <div class="stats"><div class="stat"><b>26 / 33 帧</b><span>轻／重升龙实际腾空 · 60 Hz</span></div><div class="stat"><b>37.18 / 58.14</b><span>轻／重升龙高度 · 游戏单位</span></div><div class="stat"><b>8688 × 2172</b><span>庭院全景 · 四倍神经网络超分</span></div><div class="stat"><b>1221 项</b><span>新增升龙检查全部通过</span></div></div>
 <h2>祢豆子：修正三组动作比例</h2><p>B、D 与待机的身体高度统一；蹲防以头部与躯干比例校准。整体 <code>0.85</code> 身高系数保留。</p><div class="grid">'''+shots+'''</div>
 <h2>升空踢：圆弧朝外</h2><div class="grid">'''+arcs+'''</div>
 <h2>四人的轻重升龙</h2><div class="video"><video controls preload="metadata" poster="apex-zenitsu.png" src="uppercuts.mp4"></video></div><p>轻版更紧凑，重版更高。善逸使用新生成的九帧上撩动作。腾空期间保持上升／下落姿势，落地后完成恢复。</p><div class="grid">'''+apex+'''</div>
 <h2>命中确认与连段</h2><p><code>5A → 5C → 623A/C → 236236A / 236236A+C</code></p><div class="video"><video controls preload="metadata" src="uppercut-combos.mp4" poster="combo-nezuko.png"></video></div><p>示范依次为祢豆子接奥义、善逸接 MAX、猗窝座接奥义。后续连段让对手持续按后防守，确认不存在可防御空隙；挥空、被防及过晚输入不能取消升龙。</p>
 <table><thead><tr><th>版本</th><th>腾空</th><th>高度</th><th>落地后恢复</th></tr></thead><tbody><tr><td>修改前 A／C</td><td>15 帧，约 0.25 秒</td><td>12.08</td><td>轻重轨迹相同</td></tr><tr><td>623A</td><td>26 帧，约 0.43 秒</td><td>37.18</td><td>11 帧</td></tr><tr><td>623C</td><td>33 帧，约 0.55 秒</td><td>58.14</td><td>13 帧</td></tr></tbody></table>
 <h2>鬼杀队庭院：清晰度对比</h2><p>使用本地 Real-ESRGAN 对原生图进行四倍超分，保留构图并改善屋瓦、木廊和植被边缘。滑动比较相同镜头；左侧修改前，右侧修改后。</p><div class="compare"><img src="before-courtyard-1280x720.png" alt="庭院修改前"><img id="after" src="courtyard-1280x720.png" alt="庭院高清版"><div id="divider"></div><span class="before">修改前</span><span class="after">高清版</span></div><input aria-label="庭院前后对比" id="slider" type="range" min="0" max="100" value="50"><p><a href="courtyard-1920x1080.png">查看 1080p 截图</a> · <a href="courtyard-3840x2160.png">查看 4K 截图</a></p><div class="video"><video controls preload="metadata" src="courtyard-hd.mp4" poster="courtyard-1280x720.png"></video></div>
 <footer>全部现有测试及新增检查通过。30／60／144 渲染帧率下战斗结果一致。录像为 30 FPS 无声实机捕获。善逸新动作用 imagegen 提示词规范及 CPA 流程生成；庭院使用原生图的本地神经网络超分。源图、实际尺寸、模型、裁切和锚点记录均保留。<br><a href="../../docs/uppercut-polish.md">技术与复现说明</a> · <a href="verification.json">升龙测量记录</a> · <a href="full-suite.log">完整测试日志</a></footer></main><script>slider.oninput=()=>{document.querySelector('#after').style.clipPath='inset(0 0 0 '+slider.value+'%)';document.querySelector('#divider').style.left=slider.value+'%'};</script></html>'''
 (OUT/'index.html').write_text(page,encoding='utf-8')
 print('Published local visual handoff.')
if __name__=='__main__':
 parser=argparse.ArgumentParser()
 parser.add_argument('--encode',action='store_true')
 parser.add_argument('--ffmpeg',default=shutil.which('ffmpeg'))
 args=parser.parse_args()
 if args.encode:encode_videos(args.ffmpeg)
 main()
