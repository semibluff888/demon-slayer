"""Awakened variant of a canvas frame: identical geometry, derived per frame.

spec/<id>.json "awakening" picks the derivation:

mark  (Tanjiro) the base drawings already carry the forehead scar; in the awakened
      form it grows into the flame-shaped mark. The scar is found as dark red inside
      the face skin of the measured head, grown over the surrounding skin (never onto
      hair, eyes or background) and painted crimson. Frames without a visible scar
      (back views, turned heads) stay unchanged, exactly like the drawn character.
grade (Zenitsu) Thunder Breathing, Godspeed: the gold materials (haori, leg wraps,
      hair) turn brighter and more saturated, and an optional thin gold light runs
      along the silhouette's edge. Alpha is untouched, so every pixel stays where the
      base drawing put it.
"""
import cv2
import numpy as np

import anatomy

MARK = np.array([150, 18, 30], np.float32)
EDGE = np.array([196, 46, 40], np.float32)


def settings():
    return anatomy.profile().get('awakening', {'mode': 'mark'})


def scar_mask(rgba):
    """Dark red forehead pixels enclosed by face skin, or None."""
    measured = anatomy.head(rgba)
    if measured is None:
        return None, None
    x0, y0, x1, y1 = measured['box']
    region = np.zeros(rgba.shape[:2], bool)
    region[y0:y1, x0:x1] = True
    hair, skin, _ = anatomy.masks(rgba)
    hsv = cv2.cvtColor(rgba[:, :, :3], cv2.COLOR_RGB2HSV).astype(np.int16)
    reddish = (rgba[:, :, 3] > 200) & ((hsv[:, :, 0] >= 168) | (hsv[:, :, 0] <= 8)) & (hsv[:, :, 1] >= 90) & (hsv[:, :, 2] >= 60)
    skin_area = cv2.morphologyEx(skin.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)).astype(bool)
    # Scar = red pixels whose neighbourhood is mostly skin (hair is red but surrounded by hair).
    skin_ratio = cv2.blur(skin_area.astype(np.float32), (5, 5))
    scar = region & reddish & (skin_ratio > 0.45)
    # Keep the upper part of the face only (forehead).
    face_top = y0 + int((y1 - y0) * 0.15)
    face_mid = y0 + int((y1 - y0) * 0.62)
    scar[:face_top] = False
    scar[face_mid:] = False
    # Drawings face RIGHT: the scar sits on the front half of the head, never the temple behind.
    scar[:, :x0 + int((x1 - x0) * 0.45)] = False
    if scar.sum() < 2:
        return None, skin_area
    # The scar is one patch; stray red where hair meets the temple is dropped.
    count, labels, stats, _ = cv2.connectedComponentsWithStats(scar.astype(np.uint8), 8)
    largest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    return labels == largest, skin_area


def bake_mark(rgba, grow=2):
    """Returns (frame with the awakened mark, mark pixel count)."""
    scar, skin = scar_mask(rgba)
    if scar is None:
        return rgba.copy(), 0
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * grow + 1, 2 * grow + 1))
    mark = cv2.dilate(scar.astype(np.uint8), kernel).astype(bool) & (skin | scar)
    core = cv2.erode(mark.astype(np.uint8), np.ones((2, 2), np.uint8)).astype(bool)
    out = rgba.astype(np.float32)
    edge = mark & ~core
    out[core, :3] = out[core, :3] * 0.25 + MARK * 0.75
    out[edge, :3] = out[edge, :3] * 0.45 + EDGE * 0.55
    return np.clip(out + 0.5, 0, 255).astype(np.uint8), int(mark.sum())


def graded_area(rgba):
    """Pixels the grade may change: the gold materials (feathered) and the rim band."""
    rule = settings()
    alpha = rgba[:, :, 3] > 160
    gold = anatomy.select(rgba, rule['gold'], alpha=alpha)
    weight = cv2.GaussianBlur(gold.astype(np.float32), (0, 0), 0.8)
    rim = np.zeros(rgba.shape[:2], np.float32)
    width = int(rule.get('rim_px', 0))
    if width:
        solid = (rgba[:, :, 3] > 40).astype(np.uint8)
        inner = cv2.erode(solid, np.ones((2 * width + 1, 2 * width + 1), np.uint8))
        distance = cv2.distanceTransform(solid, cv2.DIST_L2, 3)
        band = (solid > 0) & (inner == 0)
        rim[band] = np.clip(1.0 - (distance[band] - 1.0) / width, 0.0, 1.0)
    return weight, rim


def bake_grade(rgba):
    """Returns (graded frame, changed pixel count)."""
    rule = settings()
    weight, rim = graded_area(rgba)
    image = cv2.cvtColor(rgba[:, :, :3], cv2.COLOR_RGB2LAB).astype(np.float32)
    graded = image.copy()
    graded[:, :, 0] = np.clip(graded[:, :, 0] + rule['lightness'] * 255.0 / 100.0, 0, 255)
    graded[:, :, 1:] = 128.0 + (graded[:, :, 1:] - 128.0) * rule['chroma']
    mixed = image + weight[:, :, None] * (graded - image)
    rgb = cv2.cvtColor(np.clip(mixed + 0.5, 0, 255).astype(np.uint8), cv2.COLOR_LAB2RGB).astype(np.float32)
    if rim.any():
        light = np.array(rule['rim_colour'], np.float32)
        strength = rim[:, :, None] * rule['rim_alpha']
        rgb = rgb * (1.0 - strength) + light * strength
    out = rgba.copy()
    touched = (weight > 0.01) | (rim > 0)
    out[touched, :3] = np.clip(rgb[touched] + 0.5, 0, 255).astype(np.uint8)
    return out, int(np.count_nonzero(np.any(out != rgba, axis=2)))


def bake(rgba):
    """The awakened frame and the number of pixels the derivation changed."""
    if settings()['mode'] == 'grade':
        return bake_grade(rgba)
    return bake_mark(rgba)
