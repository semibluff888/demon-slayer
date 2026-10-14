"""Head ruler and body root measured from colour classes (offline, numpy/OpenCV).

Tanjiro's burgundy hair and peach skin are distinct from his costume, so the head
is the face-skin blob that touches the most hair plus the hair attached to it.
The ruler is sqrt(head area): it does not change when the head rotates, so it
measures drawing scale in flips and falls as well as upright poses. Upright
reference: approved idle candidate, hair top to chin 158 px.
"""
import cv2
import numpy as np


def _hsv(rgba):
    rgb = rgba[:, :, :3]
    return cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV).astype(np.int16)  # H 0-179, S/V 0-255


def masks(rgba):
    """Boolean masks for hair, skin and the dark-maroon uniform."""
    alpha = rgba[:, :, 3] > 160
    hsv = _hsv(rgba)
    h, s, v = hsv[:, :, 0], hsv[:, :, 1], hsv[:, :, 2]
    red_hue = (h >= 165) | (h <= 6)
    hair = alpha & red_hue & (s >= 120) & (v >= 70)
    skin = alpha & (h >= 5) & (h <= 22) & (s >= 35) & (s <= 120) & (v >= 190)
    uniform = alpha & red_hue & (s >= 50) & (s < 120) & (v >= 35) & (v < 140)
    return hair, skin, uniform


def head(rgba):
    """Returns dict(area, ruler, box) for the head, or None if no face is found."""
    hair, skin, _ = masks(rgba)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(skin.astype(np.uint8), 8)
    if count < 2:
        return None
    kernel = np.ones((9, 9), np.uint8)
    best, best_score = None, 0
    for index in range(1, count):
        if stats[index, cv2.CC_STAT_AREA] < 80:
            continue
        blob = (labels == index).astype(np.uint8)
        ring = cv2.dilate(blob, kernel) & ~blob.astype(bool)
        score = int(np.count_nonzero(ring & hair))
        if score > best_score:
            best, best_score = index, score
    if best is None or best_score < 30:
        return None
    face = labels == best
    hair_count, hair_labels, _, _ = cv2.connectedComponentsWithStats(hair.astype(np.uint8), 8)
    near = cv2.dilate(face.astype(np.uint8), np.ones((15, 15), np.uint8)).astype(bool)
    attached = np.zeros_like(hair)
    for index in np.unique(hair_labels[near & hair]):
        if index:
            attached |= hair_labels == index
    region = face | attached
    ys, xs = np.nonzero(region)
    return dict(area=int(region.sum()), ruler=float(np.sqrt(region.sum())),
                box=[int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1])


def root_x(rgba):
    """Horizontal body root: centroid of the uniform (jacket and trousers)."""
    _, _, uniform = masks(rgba)
    xs = np.nonzero(uniform)[1]
    if xs.size < 200:
        alpha = np.nonzero(rgba[:, :, 3] > 160)[1]
        return float(alpha.mean())
    return float(np.median(xs))


def root_y(rgba):
    """Vertical body centre: median row of the uniform (falls back to the silhouette)."""
    _, _, uniform = masks(rgba)
    ys = np.nonzero(uniform)[0]
    if ys.size < 200:
        ys = np.nonzero(rgba[:, :, 3] > 160)[0]
    return float(np.median(ys))


def sole_y(rgba):
    ys = np.nonzero(rgba[:, :, 3] > 150)[0]
    return int(ys.max()) + 1


def solid_body(rgba, kernel=25):
    """Silhouette without its thin parts: an opening wider than the katana removes the
    blade, fingers and loose sleeve tips but keeps the torso, legs and feet."""
    alpha = (rgba[:, :, 3] > 150).astype(np.uint8)
    shape = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel, kernel))
    opened = cv2.morphologyEx(alpha, cv2.MORPH_OPEN, shape).astype(bool)
    return opened if opened.any() else alpha.astype(bool)


def body_bottom(rgba, kernel=25):
    """Lowest row of the body itself; a dropped katana or a hand may reach lower."""
    return int(np.nonzero(solid_body(rgba, kernel))[0].max()) + 1


def body_axes(rgba, kernel=25):
    """Extents of the body (blade excluded) along its main axis and across it."""
    ys, xs = np.nonzero(solid_body(rgba, kernel))
    points = np.stack([xs, ys], 1).astype(float)
    points -= points.mean(0)
    _, vectors = np.linalg.eigh(np.cov(points.T))
    extent = []
    for axis in (vectors[:, -1], vectors[:, 0]):
        projected = points @ axis
        extent.append(float(np.percentile(projected, 99.5) - np.percentile(projected, 0.5)))
    return extent
