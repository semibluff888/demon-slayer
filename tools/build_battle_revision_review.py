"""Build the review of the requested menu, anatomy and MAX fixes."""
import argparse, html, json, re, shutil
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import build_battle_ui_review as original
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/battle-revisions'

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def comparison(left,right,target):
    canvas=Image.new('RGB',(1600,484),'#101923')
    draw=ImageDraw.Draw(canvas)
    font=ImageFont.truetype(str(ROOT/'art/fonts/NotoSansSC-ui.ttf'),18)
    for column,(path,label) in enumerate([(left,'BEFORE'),(right,'AFTER')]):
        with Image.open(path) as source:
            canvas.paste(source.convert('RGB').resize((800,450),Image.Resampling.LANCZOS),(column*800,34))
        draw.text((column*800+16,5),label,font=font,fill='#d8c397')
    canvas.save(target,quality=94)

def report():
    suites={}
    for name in ['input_tests','combat_tests','damage_tests','movement_tests','combo_practice_tests',
                 'ui_tests','ui_tests-rendered','presentation_tests','phase2_basics_tests','phase2_feedback_tests','battle_visual_tests']:
        log=(ROOT/'artifacts'/(name+'.log')).read_text(encoding='utf-8-sig')
        matches=re.findall(r'(\d+) passed, (\d+) failed',log)
        assert matches and matches[-1][1]=='0' and not re.search(r'SCRIPT ERROR|ERROR:|FAIL:',log),name
        suites[name]=int(matches[-1][0])
    hashes=[re.search(r'hash=([a-f0-9]{64})',(ROOT/'artifacts'/('fps-%d.log'%fps)).read_text()).group(1) for fps in (30,60,144)]
    assert len(set(hashes))==1
    anatomy=read(OUT/'engine/captures.json'); rendered=read(OUT/'rendered/captures.json')
    assert not anatomy['failures']
    for item in anatomy['captures']:
        with Image.open(OUT/'engine'/item['path']) as im: assert im.size==(item['width'],item['width']*9//16)
    for item in rendered['captures']:
        with Image.open(ROOT/item['path'][6:]) as im: assert list(im.size)==item['size']
    result=dict(suites=suites,fps=[30,60,144],combat_hash=hashes[0],anatomy_captures=len(anatomy['captures']),
                layout_captures=len(rendered['captures']),art=read(OUT/'art-validation.json'),
                input_validation='Native keyboard/mouse and simulated gamepad UI events; no physical gamepad attached.')
    (OUT/'acceptance.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    return result

def gallery():
    result=report()
    # Historical UI captures are optional; never fabricate a before screenshot.
    comparisons=''
    for name,before,after,label in [
        ('max-before-after.jpg','matrix/1280-tanjiro-both-right-0-charge.png','1280-tanjiro-both-right-0-charge.png','MAX'),
        ('menus-before-after.jpg','hud/1280-pause.png','1280-pause.png','Pause')]:
        source=ROOT/'artifacts/battle-ui'/before
        if source.exists():
            comparison(source,OUT/'rendered'/after,OUT/name)
            comparisons+='<h2>'+label+' / Before - After</h2><img src="'+name+'">'
    samples=[
        ('rendered/1280-tanjiro-236236AC-right-1-charge.png','右侧施放：完整面部特写出现在右侧'),
        ('rendered/1280-zenitsu-236236AC-left--1-charge.png','左侧施放：完整面部特写出现在左侧'),
        ('rendered/1280-tanjiro-both-right-0-charge.png','双 MAX：书法图与脸部分行对齐'),
        ('rendered/1280-settings.png','练习设置恢复选人菜单风格'),
        ('engine/1280-tanjiro-right-hit6D-landing-11.png','炭治郎正投落地'),
        ('engine/1280-tanjiro-right-hit4D-landing-11.png','炭治郎背投落地'),
        ('engine/1280-zenitsu-right-hit6D-landing-11.png','善逸正投落地'),
        ('engine/1280-zenitsu-right-5D-active.png','善逸重体术：保留屈膝姿势，恢复身形')]
    cards=''.join('<figure><a href="'+p+'"><img loading="lazy" src="'+p+'"></a><figcaption>'+html.escape(t)+'</figcaption></figure>' for p,t in samples)
    poses=''.join('<details><summary>'+c+' / '+clip+'</summary><img loading="lazy" src="'+c+'-'+clip+'-compare.jpg"></details>' for c in ('tanjiro','zenitsu') for clip in ('roll_forward','roll_back','body_stand_heavy','thrown','thrown_forward'))
    videos=''.join('<figure><video controls preload="metadata" src="rendered/'+name+'.mp4"></video><figcaption>'+title+'</figcaption></figure>' for _,_,title,name in original.TITLES)
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>战斗界面与人物比例修正</title><style>*{box-sizing:border-box}body{background:#101923;color:#eee6d4;font:16px/1.8 "Microsoft YaHei",sans-serif;margin:0}main{max-width:1320px;margin:auto;padding:36px 24px}h1{font-size:32px}h2{margin-top:42px;font-size:23px}p,figcaption{color:#bfcbd4}a{color:#dec691}img,video{display:block;width:100%;height:auto}.grid{display:grid;grid-template-columns:1fr 1fr;gap:24px}figure{margin:0}figcaption{padding:8px 0}summary{cursor:pointer;padding:12px}details{border-bottom:1px solid #48505d}@media(max-width:760px){.grid{grid-template-columns:1fr}}</style>
<main><h1>战斗界面与人物比例修正</h1><p>暂停和练习设置恢复选人菜单风格。校准翻滚、重体术及受投落地的身形；MAX 完整脸部随施放时的屏幕侧定位，去除书法图上方的额外文字。</p>
'''+comparisons+'''
<h2>四种奥义短片</h2><p>实际 Godot 渲染，真实输入与事件音效，每段 2.5 秒。</p><div class="grid">'''+videos+'''</div><h2>实机画面</h2><div class="grid">'''+cards+'''</div>
<h2>动作对照</h2><p>每行依次为待机、修改前、修改后，所有素材采用相同显示比例。比较头部、躯干和四肢，屈膝和翻转保留原本姿势。</p>'''+poses+'''<p>验证：'''+str(result['anatomy_captures'])+''' 张动作截图、'''+str(result['layout_captures'])+''' 张布局截图，覆盖左右朝向、双奥义、960×540 至 4K 及 16:10 留边。回归通过，30／60／144 FPS 战斗状态一致。手柄焦点使用模拟事件验证。<a href="acceptance.json">完整验证记录</a></p></main></html>'''
    (OUT/'index.html').write_text(page,encoding='utf-8')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--encode',action='store_true');parser.add_argument('--ffmpeg',default=shutil.which('ffmpeg'));args=parser.parse_args()
    if args.encode:
        if not args.ffmpeg:parser.error('ffmpeg required')
        original.ART=OUT/'rendered';original.encode(args.ffmpeg)
    gallery()
    print('Battle revision review ready: '+str(OUT/'index.html'))
