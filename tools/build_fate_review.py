# coding: utf-8
"""Encode input-driven captures and publish a local visual review page."""
from pathlib import Path
import argparse,html,json,subprocess
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'artifacts/fate-revisions'
FFMPEG=Path(r'E:\Program Files\ffmpeg-7.1.1-essentials_build\bin\ffmpeg.exe')
def thumbnail(name):
 target=ART/'thumbnails'/(Path(name).stem+'.jpg')
 target.parent.mkdir(parents=True,exist_ok=True)
 with Image.open(ART/name) as im:
  im=im.convert('RGB');im.thumbnail((1280,800),Image.Resampling.LANCZOS);im.save(target,quality=92)
 return target.relative_to(ART).as_posix()
def picture(name,caption):
 return f'<figure><a href="{html.escape(name)}"><img loading="lazy" src="{thumbnail(name)}" alt="{html.escape(caption)}"></a><figcaption>{html.escape(caption)}</figcaption></figure>'
def main():
 p=argparse.ArgumentParser();p.add_argument('--encode',action='store_true');args=p.parse_args()
 if args.encode:
  for folder,filename in [('pain-video','pain-reactions.mp4'),('courtyard-video','corps-courtyard.mp4')]:
   subprocess.run([str(FFMPEG),'-hide_banner','-loglevel','error','-y','-framerate','30','-i',str(ART/folder/'frame-%05d.jpg'),'-c:v','libx264','-crf','20','-preset','medium','-pix_fmt','yuv420p','-movflags','+faststart',str(ART/filename)],check=True)
 capture=json.loads((ART/'capture.json').read_text(encoding='utf-8'))
 body='<h1>宿命对决 · 本次改进</h1><p>祢豆子整体缩小 15%；连续受击使用疼痛姿态；爆血朝向与踢击一致；新增鬼杀队庭院；主菜单换为含游戏名称的对峙海报。</p>'
 body+='<p><a href="../../docs/fate-revisions.md">实现与复现说明</a> · <a href="full-suite.log">完整测试记录</a> · <a href="../../output/imagegen/fate-v1/jobs.json">CPA 生图任务清单</a></p>'
 body+=picture('1280x720-title.png','正式游戏主菜单：标题已绘入海报，按钮使用原生控件')
 body+='<h2>人物比例与技能方向</h2><div class="pair">'+picture('size-before.png','同一场景：调整前的祢豆子比例')+picture('size-nezuko-tanjiro.png','缩小 15%：现在比炭治郎矮一档')+'</div>'
 body+='<div class="pair">'+picture('size-nezuko-zenitsu.png','与善逸对比')+picture('size-nezuko-akaza.png','与猗窝座对比')+'</div>'
 body+='<div class="pair">'+picture('effect-before.png','原贴图方向：亮焰主体偏后')+picture('effect-236C-right.png','修正方向：亮焰随前踢向对手伸展')+'</div>'
 body+='<div class="pair">'+picture('effect-623C-right.png','升空踢：焰弧向前上方扬起')+picture('effect-214D-left.png','回旋踢：反向站位保持正确镜像')+'</div>'
 body+='<h2>连续受击</h2><p>正式输入驱动，覆盖两名角色、左右朝向、超必杀和六段 MAX。静音，30 FPS；战斗逻辑 60 Hz。</p><video controls preload="metadata" poster="pain-nezuko-max-right.png" src="pain-reactions.mp4"></video>'
 body+='<div class="pair">'+picture('pain-nezuko-max-right.png','祢豆子：MAX 连击中闭眼承受冲击')+picture('pain-akaza-super-right.png','猗窝座：超必杀连击中的疼痛反应')+'</div>'
 body+='<h2>鬼杀队庭院</h2>'+picture('1280x720-stages.png','四张场景卡完整显示，可用鼠标、键盘或手柄选择')
 body+='<video controls preload="metadata" poster="courtyard-center.png" src="corps-courtyard.mp4"></video>'
 body+='<div class="pair">'+picture('courtyard-left.png','镜头左侧与角色落脚位置')+picture('courtyard-right.png','镜头右侧与角色落脚位置')+'</div>'
 body+='<h2>窗口尺寸检查</h2><div class="pair">'
 for size in ['960x540','1920x1080','3840x2160','1600x1000']:
  body+=picture(size+'-title.png',size+' · 主菜单')
  body+=picture(size+'-stages.png',size+' · 四地图')
 body+='</div><details><summary>全部 47 张实机截图</summary><div class="pair">'
 for name in capture['screenshots']:body+=picture(name,Path(name).stem)
 body+='</div></details><h2>生成资产与原始提示词</h2><p>使用项目既有 CPA API／CLI，gpt-image-2，high。以下为实际提交的提示词；原始输出与实际尺寸保存在来源记录中。</p>'
 for key,label,target in [('title-poster','主菜单海报','../../art/ui/title-poster.png'),('corps-courtyard','庭院全景','../../art/stages/corps_courtyard/panorama.png')]:
  prompt=(ROOT/'output/imagegen/fate-v1/prompts'/(key+'.txt')).read_text(encoding='utf-8')
  body+=f'<p><a href="{target}">{label}游戏资产</a> · <a href="../../output/imagegen/fate-v1/raw/{key}.png">原始输出</a> · <a href="../../output/imagegen/fate-v1/records/{key}.json">生成记录</a></p><details><summary>{label}提示词</summary><pre>{html.escape(prompt)}</pre></details>'
 style='*{box-sizing:border-box}body{max-width:1328px;margin:auto;padding:36px 24px;background:#101923;color:#eee6d4;font:16px/1.8 system-ui}h1{font-size:32px}h2{margin-top:40px;font-size:23px}p,figcaption{color:#c4cbd4}a{color:#f1c984}img,video{display:block;width:100%;height:auto}figure{margin:0 0 22px}figcaption{padding:8px 0}.pair{display:grid;grid-template-columns:1fr 1fr;gap:22px}details{border:1px solid #405468;padding:12px;margin:16px 0}summary{cursor:pointer}pre{white-space:pre-wrap;font-size:14px}@media(max-width:800px){.pair{grid-template-columns:1fr}}'
 (ART/'index.html').write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>鬼灭之刃：宿命对决 · 改进验收</title><style>'+style+'</style><body>'+body+'</body></html>',encoding='utf-8')
 print('Review:',ART/'index.html')
if __name__=='__main__':main()
