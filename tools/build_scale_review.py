# coding: utf-8
"""Build the engine review index and optional silent input-driven clips."""
import argparse, html, json, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/scale-fix/engine'

def main():
 p=argparse.ArgumentParser()
 p.add_argument('--encode',action='store_true')
 p.add_argument('--ffmpeg',default=r'E:\Program Files\ffmpeg-7.1.1-essentials_build\bin\ffmpeg.exe')
 args=p.parse_args()
 shots=json.loads((OUT/'gallery.json').read_text(encoding='utf-8'))
 seq=json.loads((OUT/'sequences.json').read_text(encoding='utf-8'))
 chars=list(dict.fromkeys(item['character'] for item in seq['sequences']))
 if args.encode:
  for cid in chars:
   start=next(item['first_frame'] for item in seq['sequences'] if item['character']==cid)
   following=[item['first_frame'] for item in seq['sequences'] if item['character']!=cid and item['first_frame']>start]
   end=min(following) if following else seq['frames']
   subprocess.run([args.ffmpeg,'-y','-hide_banner','-loglevel','error','-framerate',str(seq['fps']),'-start_number',str(start),'-i',str(OUT/'video/frame-%05d.jpg'),'-frames:v',str(end-start),'-c:v','libx264','-preset','medium','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart','-an',str(OUT/(cid+'.mp4'))],check=True)
 parts=[]
 for cid in chars:
  parts.append('<h2>'+cid+'</h2><video controls preload="metadata" src="'+cid+'.mp4"></video>')
  clips=list(dict.fromkeys(item['clip'] for item in shots if item['character']==cid))
  for clip in clips:
   images=''.join('<a href="'+s['file']+'"><img loading="lazy" src="'+s['file']+'"></a>' for s in shots if s['character']==cid and s['clip']==clip)
   parts.append('<details><summary>'+html.escape(clip)+'</summary><section>'+images+'</section></details>')
 header='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>体型一致性 · 引擎检查</title><style>body{max-width:1280px;margin:32px auto;padding:0 24px;background:#101c2c;color:#e8dfc8;font:16px/1.7 system-ui}img,video{width:100%}section{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}details{margin:12px 0;border:1px solid #3d6976}summary{padding:12px;cursor:pointer}a{color:#80d4df}</style><h1>体型一致性 · 引擎检查</h1><p>视频以真实输入驱动，包含蹲防、跳跃、翻滚、普通技、轻重必杀、奥义／MAX及前后受投。静音录制，20 FPS。</p><p>下方为图集在正式渲染器中的静态检查，右侧保持待机作为尺寸标尺。每个动作展示起始、中段、末帧。</p><a href="../index.html">返回修复前后对照</a>'
 (OUT/'index.html').write_text(header+''.join(parts),encoding='utf-8')
 print('Engine review ready:',OUT/'index.html')

if __name__=='__main__':main()
