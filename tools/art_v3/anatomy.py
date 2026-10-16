"""Head ruler and body root measured from colour classes (offline, numpy/OpenCV).

The colour classes come from spec/<id>.json "anatomy" (configure() selects the
character; Tanjiro is the default). Each class is an inclusive HSV box: "h" in
OpenCV units (0-179, a range with low > high wraps through red), "s" and "v" 0-255.

The head is the face-skin blob that touches the most hair plus the hair attached to
it. Tanjiro's burgundy hair is distinct from his costume. Zenitsu's hair, haori and
leg wraps share one yellow-to-orange range, so his profile adds "hair_cut": only hair
on the far side of the chin (seen from the body centre) and within `radius` face sizes
of the face centre counts, after the gold is split at thin links. Akaza's pink hair
and magenta vest share hue and saturation but not brightness: his profile adds
"hair_lit", which keeps only the pink regions where at least `share` of the pixels are
as bright as the lit hair (`v`); the vest is never that bright, even where lit.

The ruler is sqrt(head area): it does not change when the head rotates, so it
measures drawing scale in flips and falls as well as upright poses.
"""
import cv2
import numpy as np

from common import spec

PROFILE = None


def configure(character):
    """Selects the character (spec/<id>.json) whose colour classes every measurement uses."""
    global PROFILE
    PROFILE = dict(spec(character), character=character)
    return PROFILE


def profile():
    return PROFILE if PROFILE is not None else configure('tanjiro')


def _hsv(rgba):
    rgb = rgba[:, :, :3]
    return cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV).astype(np.int16)  # H 0-179, S/V 0-255


def _within(channel, bounds):
    low, high = bounds
    if low <= high:
        return (channel >= low) & (channel <= high)
    return (channel >= low) | (channel <= high)


def select(rgba, rule, hsv=None, alpha=None):
    """Pixels of one colour class: an HSV box on the opaque drawing."""
    hsv = _hsv(rgba) if hsv is None else hsv
    alpha = rgba[:, :, 3] > 160 if alpha is None else alpha
    return alpha & _within(hsv[:, :, 0], rule['h']) & _within(hsv[:, :, 1], rule['s']) & _within(hsv[:, :, 2], rule['v'])


def masks(rgba):
    """Boolean masks for hair, skin and the uniform (jacket and trousers)."""
    alpha = rgba[:, :, 3] > 160
    hsv = _hsv(rgba)
    rules = profile()['anatomy']
    hair, skin, uniform = (select(rgba, rules[name], hsv, alpha) for name in ('hair', 'skin', 'uniform'))
    lit = rules.get('hair_lit')
    if lit:
        count, labels, stats, _ = cv2.connectedComponentsWithStats(hair.astype(np.uint8), 8)
        bright = np.bincount(labels[hair & (hsv[:, :, 2] >= lit['v'])], minlength=count)
        keep = bright >= lit['share'] * stats[:, cv2.CC_STAT_AREA]
        keep[0] = False
        hair = keep[labels]
    return hair, skin, uniform


def _face(hair, skin, toward=None):
    """Label image of the skin blobs and the face blob's label (or None). `toward` gives,
    per blob, the hair pixels that count (only those beyond the blob, seen from the body)."""
    count, labels, stats, _ = cv2.connectedComponentsWithStats(skin.astype(np.uint8), 8)
    if count < 2:
        return labels, None
    kernel = np.ones((9, 9), np.uint8)
    best, best_score = None, 0
    for index in range(1, count):
        if stats[index, cv2.CC_STAT_AREA] < 80:
            continue
        blob = (labels == index).astype(np.uint8)
        ring = cv2.dilate(blob, kernel) & ~blob.astype(bool)
        counted = hair if toward is None else toward(labels == index)
        score = int(np.count_nonzero(ring & counted))
        if score > best_score:
            best, best_score = index, score
    if best is None or best_score < 30:
        return labels, None
    return labels, best


def head(rgba):
    """Returns dict(area, ruler, box, region, hair) for the head, or None if no face is found."""
    hair, skin, uniform = masks(rgba)
    cut = profile()['anatomy'].get('hair_cut')
    if cut:
        return _cut_head(rgba, hair, skin, uniform, cut)
    labels, best = _face(hair, skin)
    if best is None:
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
                box=[int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1], region=region, hair=attached)


def _body_centre(uniform, alpha):
    ys, xs = np.nonzero(uniform)
    if xs.size < 200:
        ys, xs = np.nonzero(alpha)
    return np.array([np.median(xs), np.median(ys)], np.float64)


def _cut_head(rgba, hair, skin, uniform, cut):
    """Head of a character whose hair shares its colours with the costume (see module doc)."""
    body = _body_centre(uniform, rgba[:, :, 3] > 160)
    rows, cols = np.mgrid[0:rgba.shape[0], 0:rgba.shape[1]]

    def beyond(blob):
        # Hair lies on the far side of the face from the body; sleeve cuffs around a
        # hand lie on the near side, so a hand never outscores the face.
        ys, xs = np.nonzero(blob)
        centre = np.array([xs.mean(), ys.mean()])
        axis = centre - body
        axis /= max(1e-6, np.linalg.norm(axis))
        return hair & ((cols - centre[0]) * axis[0] + (rows - centre[1]) * axis[1] > 0)

    labels, best = _face(hair, skin, beyond)
    if best is None:
        return None
    face = labels == best
    ys, xs = np.nonzero(face)
    centre = np.array([xs.mean(), ys.mean()])
    axis = centre - body
    axis /= max(1e-6, np.linalg.norm(axis))
    along = (cols - centre[0]) * axis[0] + (rows - centre[1]) * axis[1]
    chin = float(((xs - centre[0]) * axis[0] + (ys - centre[1]) * axis[1]).min())
    size = float(np.sqrt(face.sum()))
    allowed = hair & (along >= chin) & (np.hypot(cols - centre[0], rows - centre[1]) <= cut['radius'] * size)
    link = int(cut.get('link', 1))
    split = cv2.erode(allowed.astype(np.uint8), np.ones((2 * link + 1, 2 * link + 1), np.uint8)) if link else allowed.astype(np.uint8)
    _, hair_labels = cv2.connectedComponents(split, connectivity=8)
    near = cv2.dilate(face.astype(np.uint8), np.ones((15, 15), np.uint8)).astype(bool)
    attached = np.zeros_like(hair)
    for index in np.unique(hair_labels[near & (split > 0)]):
        if index:
            attached |= hair_labels == index
    if link:
        attached = cv2.dilate(attached.astype(np.uint8), np.ones((2 * link + 1, 2 * link + 1), np.uint8)).astype(bool) & allowed
    region = face | attached
    ys, xs = np.nonzero(region)
    return dict(area=int(region.sum()), ruler=float(np.sqrt(region.sum())),
                box=[int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1], region=region, hair=attached)


def torso(rgba, belt, kernel=24):
    """Head centre to the middle of the sash band (spec colour class `belt`): the neck and
    trunk, which keep their length while the arms and legs move and the head turns. The
    band is what stays of the class after an opening `kernel` px wide and a quarter of that
    tall (thin tattoo lines, hanging sash ends and fists drop out). None when there is no
    head or no band below it."""
    measured = head(rgba)
    if not measured:
        return None
    band = select(rgba, belt).astype(np.uint8)
    band = cv2.morphologyEx(band, cv2.MORPH_OPEN, np.ones((max(3, kernel // 4), kernel), np.uint8))
    count, _, stats, centres = cv2.connectedComponentsWithStats(band, 8)
    if count < 2:
        return None
    largest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    ys, xs = np.nonzero(measured['region'])
    centre = np.array([xs.mean(), ys.mean()])
    if centres[largest][1] < centre[1]:
        return None
    return float(np.hypot(*(centres[largest] - centre)))


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
