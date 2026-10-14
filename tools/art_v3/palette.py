"""Per-material colour lock in Lab, applied once per generated sheet.

Materials are the anatomy colour classes (uniform, skin, hair) plus the character's
costume classes from spec/<id>.json "materials" (Tanjiro's haori green; Zenitsu's
haori in a yellow and an orange band, because a gradient's mean moves with how much
hem a pose shows). The mean Lab of each locked material is moved to the approved
idle's mean (chroma fully, lightness by half) so shading and line work survive while
clips stop drifting in hue.
"""
import cv2
import numpy as np

import anatomy

LIGHTNESS_SHARE = 0.5
# Only drift beyond this CIE76 distance is corrected; closer sheets stay untouched.
MIN_DELTA_E = 2.0


def materials():
    return anatomy.profile()['materials']


def locked():
    """Hair is measured for QA only: its saturated class also catches costume highlights."""
    return tuple(materials()['locked'])


def classes(rgba):
    hair, skin, uniform = anatomy.masks(rgba)
    measured = anatomy.head(rgba)
    if anatomy.profile()['anatomy'].get('hair_cut'):
        # Hair cut out of the shared costume colours by the head measurement itself.
        hair = measured['hair'] if measured else np.zeros_like(hair)
    else:
        # Hair only inside the measured head: trousers can share its saturated hue.
        head_only = np.zeros_like(hair)
        if measured:
            x0, y0, x1, y1 = measured['box']
            head_only[y0:y1, x0:x1] = True
        hair = hair & head_only
    hsv = cv2.cvtColor(rgba[:, :, :3], cv2.COLOR_RGB2HSV).astype(np.int16)
    alpha = rgba[:, :, 3] > 160
    head = None
    result = {}
    for name, rule in materials()['classes'].items():
        mask = anatomy.select(rgba, rule, hsv, alpha)
        if rule.get('exclude_head'):
            if head is None:
                head = np.zeros_like(mask)
                if measured:
                    head = cv2.dilate(measured['region'].astype(np.uint8), np.ones((7, 7), np.uint8)).astype(bool)
            mask = mask & ~head
        result[name] = mask
    result.update(uniform=uniform, skin=skin, hair=hair)
    return result


def lab(rgba):
    return cv2.cvtColor(rgba[:, :, :3], cv2.COLOR_RGB2LAB).astype(np.float32)


def stats(rgba):
    image = lab(rgba)
    result = {}
    for name, mask in classes(rgba).items():
        if mask.sum() >= 200:
            result[name] = image[mask].mean(axis=0).tolist()
    return result


def delta_e(first, second):
    """CIE76 distance between two OpenCV Lab triples (L scaled 0-255)."""
    a = np.array(first, np.float32)
    b = np.array(second, np.float32)
    a[0] *= 100.0 / 255.0
    b[0] *= 100.0 / 255.0
    return float(np.linalg.norm(a - b))


def lock(rgba, target, sheet_stats=None):
    """Shift each material's mean toward the target means; returns (image, shifts)."""
    sheet_stats = sheet_stats or stats(rgba)
    image = lab(rgba)
    touched = np.zeros(rgba.shape[:2], np.float32)
    shifts = {}
    for name, mask in classes(rgba).items():
        if name not in locked() or name not in target or name not in sheet_stats:
            continue
        if delta_e(sheet_stats[name], target[name]) < MIN_DELTA_E:
            continue
        shift = np.array(target[name], np.float32) - np.array(sheet_stats[name], np.float32)
        shift[0] *= LIGHTNESS_SHARE
        # Feathered weight keeps material borders and ink lines smooth.
        weight = cv2.GaussianBlur(mask.astype(np.float32), (0, 0), 1.2)[:, :, None]
        image += weight * shift[None, None, :]
        touched = np.maximum(touched, weight[:, :, 0])
        shifts[name] = [round(float(v), 2) for v in shift]
    out = rgba.copy()
    if shifts:
        # Only shifted pixels pass through Lab; the rest keep their exact values.
        rgb = cv2.cvtColor(np.clip(image + 0.5, 0, 255).astype(np.uint8), cv2.COLOR_LAB2RGB)
        changed = touched > 0.01
        out[changed, :3] = rgb[changed]
    return out, shifts
