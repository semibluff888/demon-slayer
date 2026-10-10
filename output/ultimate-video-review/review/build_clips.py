import concurrent.futures
import html
import json
import subprocess
from pathlib import Path
from inspect_video import FFMPEG, ROOT, SOURCE

FFPROBE = str(Path(FFMPEG).with_name('ffprobe.exe'))
items = [
 ('01_tanjiro_water','炭治郎｜水之呼吸奥义','炭治郎','生生流转：水系奥义候选，源视频未显示技能名',2.4,14.4,7),
 ('02_tanjiro_hinokami','炭治郎｜火之神神乐奥义','炭治郎','碧罗之天：火系奥义候选，源视频未显示技能名',36.4,49.7,41),
 ('03_tanjiro_district','炭治郎｜游郭篇·水火连斩','炭治郎','额外备选：水火组合演出，非已确认的碧罗之天',55.1,67.3,65),
 ('04_nezuko_blood','祢豆子｜爆血奥义','祢豆子','血鬼术·爆血：爆血演出',91.55,106.7,102),
 ('05_nezuko_awakened','祢豆子｜觉醒爆血连击','祢豆子','爆血·觉醒连击：觉醒形态候选演出',111.4,125.1,120),
 ('06_zenitsu_sixfold','善逸｜霹雳一闪·六连','善逸','霹雳一闪·六连：普通版奥义候选',206.1,218.7,210),
 ('07_zenitsu_godspeed','善逸｜霹雳一闪·神速','善逸','霹雳一闪·神速：游郭篇奥义候选',223.4,236.5,227),
 ('08_akaza_ultimate','猗窝座｜罗针·破坏杀奥义','猗窝座','破坏杀·灭式：候选演出；此源中未找到青银乱残光',526.4,543.5,531),
]

def build(item):
    stem,title,character,mapping,start,end,poster = item
    output=ROOT/'clips'/f'{stem}.mp4'
    cmd=[FFMPEG,'-hide_banner','-loglevel','error','-y','-ss',str(start),'-i',str(SOURCE),'-t',f'{end-start:.6f}','-map','0:v:0','-map','0:a:0','-c:v','libx264','-preset','medium','-crf','17','-threads','4','-pix_fmt','yuv420p','-c:a','aac','-b:a','192k','-af',f'afade=t=in:st=0:d=0.01,afade=t=out:st={end-start-0.04:.6f}:d=0.04','-movflags','+faststart','-map_metadata','-1',str(output)]
    subprocess.run(cmd,check=True)
    subprocess.run([FFMPEG,'-v','error','-y','-ss',str(poster),'-i',str(SOURCE),'-frames:v','1','-vf','scale=640:360',str(ROOT/'review'/f'{stem}.jpg')],check=True)
    probe=json.loads(subprocess.check_output([FFPROBE,'-v','error','-show_streams','-show_format','-of','json',str(output)]))
    video=next(s for s in probe['streams'] if s['codec_type']=='video')
    audio=next(s for s in probe['streams'] if s['codec_type']=='audio')
    assert (video['width'],video['height'],video['r_frame_rate'])==(1920,1080,'60/1')
    assert abs(float(probe['format']['duration'])-(end-start))<0.1
    check=subprocess.run([FFMPEG,'-v','error','-i',str(output),'-f','null','-'],capture_output=True,text=True)
    if check.returncode or check.stderr.strip():
        raise RuntimeError(f'{stem}: {check.stderr}')
    result=dict(id=stem,title=title,character=character,game_skill_mapping=mapping,file=f'clips/{stem}.mp4',source_start_seconds=start,source_end_seconds=end,duration_seconds=round(end-start,3),width=video['width'],height=video['height'],fps=60,video_codec=video['codec_name'],audio_codec=audio['codec_name'],bytes=int(probe['format']['size']),decode_verified=True)
    print(f'OK {stem}: {end-start:.2f}s, {result["bytes"]/1024/1024:.1f} MiB',flush=True)
    return result

with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    clips=list(pool.map(build,items))
manifest=dict(source_url='https://www.youtube.com/watch?v=-cnMjZ1v4fU',source_file='source/original.mp4',source_title='Demon Slayer - All Ultimates w. all DLC [The Hinokami Chronicles PC No HUD]',notes=['原始最高画质1080p60，未放大或补帧。','剪出命中瞬间至演出收尾，去除起手等待与站立恢复。','保留源视频原声、对手及场景；未接入游戏。','技能名主要按画面辨识；无HUD源没有招式字幕，具体对应以人工审片为准。'],clips=clips)
(ROOT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
search=json.loads((ROOT/'review/search.json').read_text(encoding='utf-8-sig'))
candidates=[e for e in search['entries'] if e['id'] in ['qQQBlBq-AwM','8hV0A42sZSw','99rjzXyIqtA']]
candidate_md='\n'.join(f'- [{e["title"]}]({e["url"]})' for e in candidates)
rows='\n'.join(f'| [{c["title"]}]({c["file"]}) | {c["duration_seconds"]:.2f}s | {c["source_start_seconds"]:.2f}–{c["source_end_seconds"]:.2f}s | {c["game_skill_mapping"]} |' for c in clips)
readme=f'''# 四角色必杀动画预览

打开 `preview.html` 可逐段播放；单独 MP4 在 `clips/`，完整原视频在 `source/original.mp4`。

- 来源：[用户提供的无 HUD 合集](https://www.youtube.com/watch?v=-cnMjZ1v4fU)
- 原视频：1920×1080、60FPS、约 11 分 27 秒；保留完整下载文件。
- 片段：H.264 / AAC、1080p60；逐帧精确重编码（CRF 17），无放大、无补帧、无裁画。
- 从命中瞬间起保留完整演出和短收尾，去掉发动前等待、对手起身和站立等待；音频首尾仅做 10ms / 40ms 淡入淡出以避免爆音。
- 画面检查未发现血条、HUD、广告叠层；原作场景、对手和原声仍在。
- 当前只下载、切割并提供预览，未修改游戏逻辑或接入视频。目录带 `.gdignore`。

| 视频 | 时长 | 原视频秒数 | 与当前游戏的关系 |
|---|---:|---|---|
{rows}

## 对应关系

原视频无技能字幕，文件名是便于预览的动作描述，非对所有官方招式名的认证。炭治郎额外提供游郭篇水火连斩作为备选。猗窝座仅发现一段普通形态奥义，包含罗针和冲击连击，未找到能确认是“终式·青银乱残光”的片段，未用别的招式冒充。

## 更高清候选（仅检索到，尚未验证画面是否无 HUD）

以下视频标题声称 4K / 60FPS，没有下载或替换本次源素材，可后续人工查看：

{candidate_md}

## 检查与复现

全部 8 个 MP4 已核验 1080p60、视频和音轨、持续时间，并通过全片解码检查。`manifest.json` 记录切割点；`review/` 内保留抽帧检查图和剪辑脚本。源文件最高分辨率即为 1080p，不是 4K。
'''
(ROOT/'README.md').write_text(readme,encoding='utf-8')
cards='\n'.join(f'''<article><h2>{html.escape(c['title'])}</h2><video controls preload="none" poster="review/{c['id']}.jpg" src="{c['file']}"></video><p>{c['duration_seconds']:.2f} 秒 · 1080p / 60FPS</p><p class="note">{html.escape(c['game_skill_mapping'])}</p><a href="{c['file']}" download>下载这一段 MP4</a></article>''' for c in clips)
page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>四角色 · 必杀动画预览</title><style>body{margin:0;background:#10131a;color:#edf0f5;font:16px/1.6 system-ui,"Microsoft YaHei",sans-serif}main{max-width:1320px;margin:auto;padding:32px}h1{font-size:30px;margin-bottom:6px}h2{font-size:19px}header{margin-bottom:28px}header p,.note{color:#aeb7c9}section{display:grid;grid-template-columns:repeat(auto-fit,minmax(360px,1fr));gap:22px}article{background:#1b202b;border:1px solid #30394b;border-radius:12px;padding:18px}video{width:100%;aspect-ratio:16/9;background:#000;border-radius:6px}a{color:#8ec5ff}.note{font-size:14px;min-height:44px}footer{margin-top:30px;color:#aeb7c9}@media(max-width:450px){main{padding:15px}section{grid-template-columns:1fr}}</style><main><header><h1>四角色 · 必杀动画预览</h1><p>8 段独立视频 · 1080p 60FPS · 保留原声 · 已去掉起手等待与站立恢复</p><p>来自原作无 HUD 合集。角色、对手和背景保留；技能对应见各片段备注。</p><a href="source/original.mp4">完整原视频</a> · <a href="README.md">素材说明与高清候选链接</a></header><section>'''+cards+'''</section><footer>猗窝座“青银乱残光”在此源中未找到。炭治郎游郭篇为额外备选。尚未接入游戏。</footer></main><script>document.querySelectorAll('video').forEach(v=>v.addEventListener('play',()=>document.querySelectorAll('video').forEach(o=>{if(o!==v)o.pause()})));</script></html>'''
(ROOT/'preview.html').write_text(page,encoding='utf-8')
print('COMPLETE: 8 clips, manifest, README, preview.html',flush=True)
