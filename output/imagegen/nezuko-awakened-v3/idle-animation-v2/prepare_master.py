"""Extract the user-selected white-background master without recoloring the art."""
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ANIM = Path(__file__).resolve().parent
OUT = ANIM.parent
SOURCE = OUT/'references/approved-idle-master.png'
ORIGIN = (55, 48)
CANVAS = (1120, 1664)


def main():
    image = Image.open(SOURCE).convert('RGB')
    rgb = np.asarray(image).astype(np.float32)
    low, high = rgb.min(axis=2), rgb.max(axis=2)
    candidate = ((low > 235) & (high-low < 15)).astype(np.uint8)
    count, labels, stats, centers = cv2.connectedComponentsWithStats(candidate, 8)
    chosen = []
    for index in range(1, count):
        x, y, w, h, area = stats[index]
        border = x == 0 or y == 0 or x+w == image.width or y+h == image.height
        if border:
            chosen.append(index)
            continue
        median = np.median(rgb[labels == index], axis=0)
        # White costume highlights have pink/cream chroma. The actual enclosed
        # backdrop holes are neutral; protect footwear and the horn explicitly.
        if median.min() > 247 and np.ptp(median) < 5 and y < 1320 and not (x < 725 and x+w > 650 and y < 125):
            chosen.append(index)
    background = np.isin(labels, chosen)
    foreground = ~background
    n, components, areas, _ = cv2.connectedComponentsWithStats(foreground.astype(np.uint8), 8)
    main_id = 1+int(np.argmax(areas[1:, cv2.CC_STAT_AREA]))
    near_main = cv2.dilate((components == main_id).astype(np.uint8), np.ones((9,9),np.uint8)) > 0
    for index in range(1, n):
        if areas[index, cv2.CC_STAT_AREA] < 10 and not near_main[components == index].any():
            foreground[components == index] = False

    core = cv2.erode(foreground.astype(np.uint8), np.ones((3,3),np.uint8)) > 0
    _, nearest = cv2.distanceTransformWithLabels((~core).astype(np.uint8), cv2.DIST_L2, 5,
                                                 labelType=cv2.DIST_LABEL_PIXEL)
    lookup = np.zeros((int(nearest.max())+1,3),np.float32)
    lookup[nearest[core]] = rgb[core]
    inner_rgb = lookup[nearest]
    backdrop = np.array([253.,253.,253.], np.float32)
    direction = inner_rgb-backdrop
    edge_alpha = np.sum((rgb-backdrop)*direction,axis=2)/np.maximum(np.sum(direction*direction,axis=2),1)
    alpha = foreground.astype(np.float32)
    edge = foreground & ~core
    alpha[edge] = np.clip(edge_alpha[edge],0,1)
    clean = rgb.copy()
    clean[edge] = np.clip((rgb[edge]-(1-alpha[edge,None])*backdrop)/np.maximum(alpha[edge,None],.01),0,255)
    rgba = np.dstack([clean,np.round(alpha*255)]).round().astype(np.uint8)
    rgba[alpha < .02] = 0
    cutout = Image.fromarray(rgba)
    cutout.save(ANIM/'approved-master-transparent.png')
    key = Image.new('RGBA',CANVAS)
    key.alpha_composite(cutout,ORIGIN)
    key.save(ANIM/'idle-key.png')
    bounds = Image.fromarray((np.asarray(key)[:,:,3]>32).astype(np.uint8)*255).getbbox()

    sheet = Image.new('RGB',(1320,1100),'#202533')
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',25)
    draw.text((30,20),'定稿抠像检查 · 深色背景 / 浅色背景',font=font,fill='#f2ece8')
    for i,bg in enumerate(['#202533','#e9e5df']):
        panel = Image.new('RGBA',(630,990),bg)
        display = cutout.resize((round(cutout.width*960/cutout.height),960),Image.Resampling.LANCZOS)
        panel.alpha_composite(display,((630-display.width)//2,15))
        sheet.paste(panel.convert('RGB'),(20+i*660,80))
    (OUT/'review').mkdir(exist_ok=True)
    sheet.save(OUT/'review/approved-idle-cutout-check.png')
    record = dict(source=SOURCE.relative_to(OUT).as_posix(),source_sha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                  source_size=list(image.size),canvas_size=list(CANVAS),source_origin=list(ORIGIN),foreground_bounds=list(bounds),
                  method='Connected neutral white backdrop plus visually checked interior holes; preserve tinted white garments. Edge pixels unmixed against white.',
                  removed_white_components=chosen,interior_colors_unchanged=bool(np.array_equal(rgba[core,:3],rgb[core].astype(np.uint8))),
                  key='idle-key.png',transparent='approved-master-transparent.png')
    (ANIM/'master.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in record.items() if k!='removed_white_components'},indent=2))


if __name__ == '__main__':
    main()
