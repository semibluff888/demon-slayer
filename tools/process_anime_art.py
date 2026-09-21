"""Deterministic offline cutout, registered stage layers and trimmed sprite packing.

Source originals are immutable. A clip uses one calibration scale, never one scale
per pose. Measured anchors/crops are persisted for review and can be overridden in
anime-v2/calibration.json. No service calls or credentials are used here.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageMath, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/imagegen/anime-v2'
RAW = OUT / 'raw'
ART = ROOT / 'art'
REVIEW = OUT / 'review'
CANVAS = (1024, 640)
ANCHOR = (448, 568)
STANDING = 340
PAGE = 2048

def load_json(path, default=None):
    return json.loads(path.read_text(encoding='utf-8-sig')) if path.exists() else default

def save_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

def cutout(image):
    """Hue-selective matte; preserve dark outlines, pale fabric and violet flowers."""
    image = image.convert('RGBA')
    r, g, b, old_alpha = image.split()
    key = ImageChops.subtract(ImageChops.darker(r, b), g)
    alpha = key.point(lambda v: 255 if v <= 48 else max(0, round(255 - (v - 48) * 3.5)))
    alpha = ImageChops.multiply(alpha, old_alpha)
    # Unmatte only the transition pixels, using the actual source corner matte.
    matte = image.getpixel((0, 0))[:3]
    clean = []
    for channel, bg in zip((r, g, b), matte):
        clean.append(ImageMath.unsafe_eval('convert((c * 255 - bg * (255 - a)) / max(a, 1), "L")', c=channel, a=alpha, bg=bg))
    return Image.merge('RGBA', (*clean, alpha))

def mark_generated_dimensions():
    for path in RAW.glob('*.png'):
        record_path = OUT / 'records' / (path.stem + '.json')
        record = load_json(record_path, {})
        if record.get('status') != 'generated':
            continue
        with Image.open(path) as im:
            record['actual_size'] = list(im.size)
            record['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
        save_json(record_path, record)

def backdrop_preview(image, path):
    bounds = image.getbbox()
    if bounds:
        image = image.crop(bounds)
    image.thumbnail((420, 570), Image.Resampling.LANCZOS)
    preview = Image.new('RGB', (920, 620), '#f1e7d5')
    draw = ImageDraw.Draw(preview)
    draw.rectangle((460, 0, 919, 619), fill='#0c172e')
    for x in (0, 460):
        preview.paste(image, (x + (460 - image.width) // 2, 24), image)
    preview.save(path)

def portraits():
    for character in ('tanjiro', 'zenitsu'):
        path = RAW / (character + '-portrait.png')
        if not path.exists():
            continue
        image = cutout(Image.open(path))
        bounds = image.getbbox()
        if bounds is None:
            raise ValueError('Empty portrait ' + character)
        image = image.crop((max(0, bounds[0]-12), max(0, bounds[1]-12), min(image.width, bounds[2]+12), min(image.height, bounds[3]+12)))
        image.thumbnail((1100, 1600), Image.Resampling.LANCZOS)
        target = ART / 'characters' / character
        target.mkdir(parents=True, exist_ok=True)
        image.save(target / 'portrait.png')
        # Model-sheet front view provides a clean square HUD avatar, without mirroring costume.
        model = cutout(Image.open(RAW / (character + '-model.png')))
        front = model.crop((0, 0, model.width // 4, model.height))
        bbox = front.getbbox()
        face_width = int((bbox[2] - bbox[0]) * 0.61)
        cx = (bbox[0] + bbox[2]) / 2
        avatar = front.crop((int(cx-face_width/2), bbox[1], int(cx+face_width/2), bbox[1]+face_width))
        avatar = avatar.resize((192, 192), Image.Resampling.LANCZOS)
        bg = Image.new('RGBA', (192, 192), '#193745' if character == 'tanjiro' else '#433427')
        bg.alpha_composite(avatar)
        bg.save(target / 'avatar.png')
        backdrop_preview(image, REVIEW / (character + '-portrait-edges.jpg'))
        print('Portrait / avatar: ' + character)
    if (ROOT/'output/imagegen/battle-v5/raw/tanjiro-battle-portrait.png').exists():
        from build_battle_art import assets
        assets()

def vertical_mask(size, start, end, reverse=False):
    mask = Image.new('L', size)
    draw = ImageDraw.Draw(mask)
    for y in range(size[1]):
        amount = min(1, max(0, (y-start) / max(1, end-start)))
        draw.line((0, y, size[0], y), fill=round((1-amount if reverse else amount)*255))
    return mask

def stages():
    if (RAW / 'wisteria-continuous-v4.png').exists():
        from build_movement_art import extended_stage
        extended_stage()
        return
    required = ['wisteria-master', 'wisteria-sky', 'wisteria-canopy', 'wisteria-foreground']
    if not all((RAW / (name + '.png')).exists() for name in required):
        return
    target = ART / 'stages/wisteria'
    target.mkdir(parents=True, exist_ok=True)
    size = (2048, 1152)
    master = Image.open(RAW / 'wisteria-master.png').convert('RGBA').resize(size, Image.Resampling.LANCZOS)
    sky = Image.open(RAW / 'wisteria-sky.png').convert('RGB').resize(size, Image.Resampling.LANCZOS)
    sky.save(target / 'sky.png')
    # Opaque registered master beneath the optional silhouettes prevents parallax holes.
    # Sky is revealed only above the measured mountain/roof silhouette, with a soft seam.
    middle = master.copy()
    middle.putalpha(vertical_mask(size, 150, 470))
    middle.save(target / 'temple.png')
    floor = master.copy()
    floor.putalpha(vertical_mask(size, 831, 854))
    floor.save(target / 'floor.png')
    canopy = cutout(Image.open(RAW / 'wisteria-canopy.png')).resize(size, Image.Resampling.LANCZOS)
    canopy.save(target / 'wisteria.png')
    foreground = cutout(Image.open(RAW / 'wisteria-foreground.png')).resize(size, Image.Resampling.LANCZOS)
    foreground.save(target / 'foreground.png')
    master.convert('RGB').save(target / 'menu.jpg', quality=95)
    composed = sky.convert('RGBA')
    for layer in (middle, canopy, floor, foreground):
        composed.alpha_composite(layer)
    composed.resize((1280, 720), Image.Resampling.LANCZOS).save(REVIEW / 'stage-composite.png')
    print('Five registered stage layers')

def effects():
    target = ART / 'effects'
    target.mkdir(parents=True, exist_ok=True)
    for path in RAW.glob('fx-*.png'):
        image = Image.open(path).convert('RGB')
        image.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
        image.save(target / (path.stem[3:] + '.png'))
    print('Effect textures')

def foot_anchor(frame, bbox):
    """Measure contact from the bottom silhouette, excluding isolated single pixels."""
    alpha = frame.getchannel('A')
    y = bbox[3] - 1
    strip = alpha.crop((0, max(0, y-7), frame.width, y+1))
    occupied = []
    for x in range(frame.width):
        if max(strip.crop((x, 0, x+1, strip.height)).getdata()) > 150:
            occupied.append(x)
    return ((occupied[0] + occupied[-1]) / 2 if occupied else (bbox[0]+bbox[2])/2, bbox[3])

def sprite_components(source, count, columns):
    """Find the actual drawn figures, including swords extending beyond nominal cells.

    Components are measured at half resolution; a dilated ownership mask keeps
    neighboring limbs out of expanded crops, while retaining antialiasing.
    """
    small = source.getchannel('A').resize((source.width//2, source.height//2), Image.Resampling.BOX)
    w, h = small.size
    data = bytearray(small.point(lambda a: 1 if a > 110 else 0).tobytes())
    components = []
    for start in range(w*h):
        if data[start] != 1:
            continue
        data[start] = 0
        stack, pixels = [start], []
        x0 = x1 = start % w
        y0 = y1 = start // w
        while stack:
            at = stack.pop()
            pixels.append(at)
            x, y = at % w, at // w
            x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
            for nx, ny in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
                if 0 <= nx < w and 0 <= ny < h:
                    ni = ny*w+nx
                    if data[ni] == 1:
                        data[ni] = 0
                        stack.append(ni)
        if len(pixels) >= 4:
            components.append(dict(pixels=pixels, bbox=[x0,y0,x1+1,y1+1]))
    components.sort(key=lambda item: len(item['pixels']), reverse=True)
    if len(components) < count or len(components[count-1]['pixels']) < len(components[0]['pixels']) * 0.20:
        raise ValueError('Could not isolate {} complete sprites; check the source composition'.format(count))
    main = components[:count]
    # Reattach tiny separate details (earrings, blade glints) to the nearest body.
    for component in components[count:]:
        box = component['bbox']
        cx, cy = (box[0]+box[2])/2, (box[1]+box[3])/2
        nearest = min(main, key=lambda c: max(c['bbox'][0]-cx,0,cx-c['bbox'][2])**2 + max(c['bbox'][1]-cy,0,cy-c['bbox'][3])**2)
        b = nearest['bbox']
        if max(b[0]-cx,0,cx-b[2])**2 + max(b[1]-cy,0,cy-b[3])**2 < 26**2:
            nearest['pixels'].extend(component['pixels'])
            nearest['bbox'] = [min(b[0],box[0]),min(b[1],box[1]),max(b[2],box[2]),max(b[3],box[3])]
    main.sort(key=lambda c: (c['bbox'][1]+c['bbox'][3])/2)
    ordered = []
    for row in range(math.ceil(count/columns)):
        ordered.extend(sorted(main[row*columns:(row+1)*columns], key=lambda c: c['bbox'][0]))
    result = []
    for component in ordered:
        owner = bytearray(w*h)
        for at in component['pixels']:
            owner[at] = 255
        mask = Image.frombytes('L', (w,h), bytes(owner)).filter(ImageFilter.MaxFilter(5)).resize(source.size, Image.Resampling.NEAREST)
        isolated = source.copy()
        isolated.putalpha(ImageChops.multiply(source.getchannel('A'), mask))
        bounds = isolated.getbbox()
        result.append((bounds, isolated.crop(bounds)))
    return result

def process_clip(job, calibration):
    meta = job['metadata']
    source = cutout(Image.open(ROOT / job['out']))
    columns, rows, count = meta['columns'], meta['rows'], meta['count']
    cell_w, cell_h = source.width / columns, source.height / rows
    config = calibration.get(job['id'], {})
    # Idle source frames establish the calibration. Overrides use measured anatomy,
    # not bounding-box fitting: crouches and rotated poses keep their actual size.
    source_standing = config.get('standing_height', cell_h * 0.93)
    scale = STANDING / source_standing
    entries, frames = [], []
    components = sprite_components(source, count, columns)
    for i in range(count):
        x, y = i % columns, i // columns
        crop, frame = components[i]
        if str(i) in config.get('crops', {}):
            crop = config['crops'][str(i)]
            frame = source.crop(tuple(crop))
        alpha = frame.getchannel('A').point(lambda a: 255 if a > 60 else 0)
        bbox = alpha.getbbox()
        if bbox is None:
            raise ValueError('Empty frame {}:{}'.format(job['id'], i))
        measured_contact = foot_anchor(frame, bbox)
        # A planted-foot midpoint jumps whenever the trailing foot lifts. Keep the
        # horizontal root fixed to the source cell; only ground contact sets Y.
        root_x = (i % columns + config.get('root_fraction', meta.get('root_fraction', 0.42))) * cell_w - crop[0]
        anchor_mode = meta.get('anchor_mode', 'feet')
        if anchor_mode == 'pelvis':
            # Anatomical root, not the moving bottom of a rotating silhouette.
            pelvis = config.get('pelvis', {}).get(str(i), [0.5, 0.55])
            root_x = (i % columns + pelvis[0]) * cell_w - crop[0]
            root_y = (i // columns + pelvis[1]) * cell_h - crop[1]
            foot = (root_x, root_y + (34.0 / 70.0) * source_standing)
            # The final victim frames are grounded on their back.
            if (meta['clip'].startswith('thrown') and i >= 8) or i in config.get('ground_frames', []):
                foot = (root_x, measured_contact[1])
        else:
            foot = config.get('feet', {}).get(str(i), (root_x, measured_contact[1]))
        # Sheet margins stay outside the packed runtime texture. Same scale for ALL poses.
        frame = frame.crop(bbox)
        scaled = frame.resize((max(1, round(frame.width*scale)), max(1, round(frame.height*scale))), Image.Resampling.LANCZOS)
        at = (round(ANCHOR[0] - (foot[0]-bbox[0])*scale), round(ANCHOR[1] - (foot[1]-bbox[1])*scale))
        if min(at) < 0 or at[0]+scaled.width > CANVAS[0] or at[1]+scaled.height > CANVAS[1]:
            raise ValueError('Clipped artwork: {} frame {} at {} size {}'.format(job['id'], i, at, scaled.size))
        canvas = Image.new('RGBA', CANVAS)
        canvas.alpha_composite(scaled, at)
        if i in config.get('mirror_frames', []):
            # Register a turning thrower's leftward release to the shared back-throw path.
            from PIL import ImageOps
            mirrored = ImageOps.mirror(canvas)
            shifted = Image.new('RGBA', CANVAS)
            shifted.alpha_composite(mirrored, (2*ANCHOR[0]-CANVAS[0], 0))
            canvas = shifted
        frames.append(canvas)
        entries.append(dict(source=job['out'], crop=crop, measured_feet=foot, silhouette_contact=measured_contact, scale=scale,
                            normalized_bounds=list(canvas.getbbox()), source_cell_size=[cell_w, cell_h], anchor_mode=anchor_mode))
    order = meta.get('frame_order', list(range(count)))
    save_json(OUT / 'imports' / (job['id'] + '.json'), dict(standing_height=source_standing, canvas_size=CANVAS, feet_anchor=ANCHOR, frame_order=order, frames=entries))
    return [frames[i] for i in order]

def previews(character, clips):
    REVIEW.mkdir(parents=True, exist_ok=True)
    # Full motion preview and chronological contact sheets are separate QA surfaces.
    font = ImageFont.load_default()
    index_rows = []
    for clip, info in clips.items():
        frames = info['images']
        n = len(frames)
        columns = min(4, n)
        rows = math.ceil(n/columns)
        cell = (240, 185)
        sheet = Image.new('RGB', (columns*cell[0], rows*cell[1]), '#142038')
        draw = ImageDraw.Draw(sheet)
        animation = []
        for i, frame in enumerate(frames):
            thumb = frame.resize((240, 160), Image.Resampling.LANCZOS)
            x, y = (i%columns)*cell[0], (i//columns)*cell[1]
            sheet.paste(thumb, (x, y+20), thumb)
            draw.text((x+8, y+5), '{} {:02d}'.format(clip, i), fill='#e2ca9a', font=font)
            bg = Image.new('RGB', (480, 340), '#142038')
            moving = frame.resize((480, 320), Image.Resampling.LANCZOS)
            bg.paste(moving, (0, 10), moving)
            ImageDraw.Draw(bg).text((12, 12), character + ' / ' + clip, fill='#e2ca9a', font=font)
            animation.append(bg)
        sheet.save(REVIEW / (character + '-' + clip + '.jpg'), quality=93)
        animation[0].save(REVIEW / (character + '-' + clip + '.gif'), save_all=True, append_images=animation[1:], duration=83, loop=0, disposal=2)
        index_rows.append((clip, frames[min(len(frames)-1, len(frames)//2)]))
    overview = Image.new('RGB', (1000, math.ceil(len(index_rows)/4)*192), '#142038')
    draw = ImageDraw.Draw(overview)
    for i, (clip, frame) in enumerate(index_rows):
        thumb = frame.resize((250, 167), Image.Resampling.LANCZOS)
        x, y = i%4*250, i//4*192
        overview.paste(thumb, (x, y+21), thumb)
        draw.text((x+9, y+6), clip, fill='#e2ca9a', font=font)
    overview.save(REVIEW / (character+'-overview.jpg'), quality=94)

def save_atlas_page(image, path):
    # Write a complete PNG before replacing the previous build; a failed encode
    # must never leave an atlas truncated while the editor is watching it.
    temporary = path.with_suffix('.building.png')
    image.save(temporary, format='PNG')
    os.replace(str(temporary), str(path))

def pack(character, clips):
    target = ART / 'characters' / character
    target.mkdir(parents=True, exist_ok=True)
    atlas = dict(canvas_size=CANVAS, feet_anchor=ANCHOR, source_height=STANDING, canonical_height=70, clips={})
    sprites = []
    for clip, info in clips.items():
        count = len(info['images'])
        atlas['clips'][clip] = dict(loop=info['meta']['loop'], fps=info['meta']['fps'],
                                   phase_breaks=info['meta'].get('phase_breaks',[count//3, count*2//3]), frames=[None]*count,
                                   segment_sync=info['meta'].get('segment_sync',False),
                                   anchor_mode=info['meta'].get('anchor_mode','feet'),
                                   timeline=info['meta'].get('timeline', [0,3,5,8,10,13,15,18,20,23,26,29] if clip in ('throw_success','thrown') else []))
        for i, image in enumerate(info['images']):
            bbox = image.getbbox()
            sprites.append((clip, i, image.crop(bbox), bbox[:2]))
    sprites.sort(key=lambda item: item[2].height, reverse=True)
    page = Image.new('RGBA', (PAGE, PAGE))
    page_index = 0
    x = y = 2
    row_h = 0
    for clip, i, image, offset in sprites:
        if x+image.width+2 > PAGE:
            x, y, row_h = 2, y+row_h+4, 0
        if y+image.height+2 > PAGE:
            save_atlas_page(page, target / ('atlas-{}.png'.format(page_index)))
            page_index += 1
            page = Image.new('RGBA', (PAGE, PAGE))
            x = y = 2
            row_h = 0
        page.alpha_composite(image, (x, y))
        atlas['clips'][clip]['frames'][i] = dict(texture='atlas-{}.png'.format(page_index), region=[x, y, image.width, image.height], offset=list(offset))
        x += image.width+4
        row_h = max(row_h, image.height)
    save_atlas_page(page, target / ('atlas-{}.png'.format(page_index)))
    save_json(target / 'atlas.json', atlas)
    print('{}: {} clips, {} original frames, {} atlas pages'.format(character, len(clips), len(sprites), page_index+1))

def animations(only=None):
    jobs = load_json(OUT / 'jobs.json', [])
    calibration = load_json(OUT / 'calibration.json', {})
    for character in ('tanjiro', 'zenitsu'):
        if only and character != only:
            continue
        clips = {}
        latest = {}
        for job in jobs:
            if job['metadata'].get('character') != character or job['group'] == 'failed-attempts' or not (ROOT / job['out']).exists():
                continue
            record = load_json(OUT / 'records' / (job['id'] + '.json'), {})
            if record.get('status') == 'generated':
                latest[job['metadata']['clip']] = job
        for job in latest.values():
            frames = process_clip(job, calibration)
            clips[job['metadata']['clip']] = dict(images=frames, meta=job['metadata'])
        if clips:
            pack(character, clips)
            previews(character, clips)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--part', choices=['all', 'static', 'animation'], default='all')
    parser.add_argument('--character', choices=['tanjiro', 'zenitsu'])
    args = parser.parse_args()
    REVIEW.mkdir(parents=True, exist_ok=True)
    if args.part in ('all', 'static'):
        portraits()
        stages()
        effects()
    if args.part in ('all', 'animation'):
        animations(args.character)
    mark_generated_dimensions()

if __name__ == '__main__':
    main()
