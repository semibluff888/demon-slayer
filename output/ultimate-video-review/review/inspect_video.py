import subprocess
from pathlib import Path
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'source/original.mp4'
FFMPEG = r'E:\Program Files\ffmpeg-7.1.1-essentials_build\bin\ffmpeg.exe'
SECTIONS = [('tanjiro_water',0,16),('tanjiro_hinokami',34,53),('tanjiro_district',53,71),('nezuko',90,110),('nezuko_awakened',110,128),('zenitsu_sixfold',204,222),('zenitsu_godspeed',222,240),('akaza',525,547)]
def sheet(name,times,width=320,columns=4):
    height=width*9//16
    canvas=Image.new('RGB',(width*columns,(height+24)*((len(times)+columns-1)//columns)),'#181818')
    draw=ImageDraw.Draw(canvas)
    for i,t in enumerate(times):
        result=subprocess.run([FFMPEG,'-v','error','-ss',str(t),'-i',str(SOURCE),'-frames:v','1','-vf',f'scale={width}:{height}','-f','rawvideo','-pix_fmt','rgb24','pipe:1'],capture_output=True,check=True)
        frame=Image.frombytes('RGB',(width,height),result.stdout)
        x,y=(i%columns)*width,(i//columns)*(height+24)
        canvas.paste(frame,(x,y))
        draw.text((x+6,y+height+4),f'{name}  {t:.3f}s',fill='white')
    target=ROOT/'review'/f'{name}.jpg'
    canvas.save(target,quality=88)
    print(target,flush=True)
if __name__=='__main__':
    for name,start,end in SECTIONS:
        sheet(name,list(range(start,end+1)))
