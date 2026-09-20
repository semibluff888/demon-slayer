"""Build a single registered panorama from the accepted continuous painting.

No API calls. The small local sky retouch keeps the moon visible below the HUD;
all architecture, reflections and paving share one texture and camera transform.
"""
import hashlib
import math
from pathlib import Path
from PIL import Image
import process_anime_art as pipeline

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/imagegen/anime-v2'
SOURCE = OUT / 'raw/wisteria-continuous-v4.png'
SIZE = (4608, 1152)


def soft_disk(size, inner, outer):
    center = (size - 1) / 2
    pixels = []
    for y in range(size):
        for x in range(size):
            t = min(1, max(0, (math.hypot(x-center, y-center)-inner)/(outer-inner)))
            pixels.append(round(255 * (1 - t*t*(3-2*t))))
    mask = Image.new('L', (size, size))
    mask.putdata(pixels)
    return mask


def build_stage():
    original = Image.open(SOURCE).convert('RGB')
    image = original.copy()
    w, h = image.size
    # Measured on the returned 2172 x 724 painting, stored proportionally.
    cx, cy = round(w * .604), round(h * .223)
    radius = round(h * .13)
    box = (cx-radius, cy-radius, cx+radius, cy+radius)
    clean_center = cx + round(w * .088)
    clouds = original.crop((clean_center-radius, cy-radius, clean_center+radius, cy+radius))
    image.paste(clouds, box[:2], soft_disk(radius*2, h*.068, h*.125))
    moon_radius = round(h * .088)
    moon = original.crop((cx-moon_radius, cy-moon_radius, cx+moon_radius, cy+moon_radius))
    moon_y = round(h * .342)
    image.paste(moon, (cx-moon_radius, moon_y-moon_radius),
                soft_disk(moon_radius*2, h*.052, h*.086))
    # Crop to 4:1 without stretching the moon or buildings horizontally. A small,
    # smooth correction in the lower landscape registers the terrace to game feet.
    crop_h = round(w / 4)
    top = round(h * .125)
    back_y = crop_h * .72
    bend_start = crop_h * .515
    measured_back = h * .700
    bend = (measured_back - top - back_y) / math.sin(math.pi*(back_y-bend_start)/(crop_h-bend_start))
    def source_y(y):
        t = min(1, max(0, (y-bend_start)/(crop_h-bend_start)))
        return top + y + bend * math.sin(math.pi*t)
    mesh = []
    for y in range(0, crop_h, 2):
        end = min(y+2, crop_h)
        sy0, sy1 = source_y(y), source_y(end)
        mesh.append(((0,y,w,end), (0,sy0,0,sy1,w,sy1,w,sy0)))
    panorama = image.transform((w,crop_h), Image.Transform.MESH, mesh, Image.Resampling.BICUBIC)
    panorama = panorama.resize(SIZE, Image.Resampling.LANCZOS)
    target = ROOT/'art/stages/wisteria'
    panorama.save(target/'panorama.png')
    # Menu artwork uses the same continuous courtyard.
    panorama.crop((1280,0,3328,1152)).save(target/'menu.jpg',quality=95)
    (OUT/'review').mkdir(parents=True, exist_ok=True)
    panorama.resize((1920,480),Image.Resampling.LANCZOS).save(OUT/'review/stage-continuous-v4.jpg',quality=94)
    pipeline.save_json(target/'stage.json',dict(
        revision='visual-polish-v4', size=list(SIZE), world_width=960,
        render_size=[3168,792], layers=['panorama'], parallax=[1.0],
        source=str(SOURCE.relative_to(ROOT)).replace('\\','/'),
        source_size=[w,h], source_sha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        composition='One continuous painting; one moon and aligned reflection; all surfaces share the world transform.',
        local_finish=dict(moon_from=[cx,cy],moon_to=[cx,moon_y],crop_top=top,crop_height=crop_h,
                          terrace_back_fraction=.72)))
    print('Continuous stage: one 4608 x 1152 world-registered panorama.')


if __name__ == '__main__':
    build_stage()
