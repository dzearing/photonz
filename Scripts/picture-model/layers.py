"""Turn a flat picture into editable layers: a few colours, one filled path
per region with curves, specks dropped, the backdrop left out.

    layers.py <picture.png> [--colors 10] [--out drawing.svg]

Used by the picture-model try (server.py) and runnable by itself. The tracer
is vtracer (MIT). Nothing here knows what the picture is of: the palette comes
from the picture's own pixels and the names from the colours.
"""
from __future__ import annotations

import argparse
import colorsys
import io
import re
import sys

import numpy as np
import vtracer
from PIL import Image, ImageDraw, ImageFilter

MAX_PATHS = 300


def border_colour(pixels: np.ndarray) -> np.ndarray:
    """The colour most of the picture's edge is: its backdrop."""
    edge = np.concatenate([pixels[0], pixels[-1], pixels[:, 0], pixels[:, -1]]).astype(int)
    keys = (edge[:, 0] // 8) * 1024 + (edge[:, 1] // 8) * 32 + edge[:, 2] // 8
    common = np.bincount(keys).argmax()
    return edge[keys == common].mean(axis=0)


def nearest(fill: str, palette: np.ndarray) -> str:
    """The palette colour closest to `fill`, so the tracer's blends at region
    edges do not add colours of their own."""
    rgb = np.array([int(fill[i:i + 2], 16) for i in (1, 3, 5)])
    best = palette[np.abs(palette - rgb).sum(axis=1).argmin()]
    return "#" + "".join(f"{int(v):02X}" for v in best)


def backdrop_reached(near: np.ndarray) -> np.ndarray:
    """The pixels of `near` joined to the picture's edge through `near`."""
    # A copy: since Pillow 12 an image made from an array shares the array's
    # read-only memory, and floodfill on it changes nothing.
    mask = Image.fromarray(np.where(near, 255, 0).astype(np.uint8), "L").copy()
    height, width = near.shape
    edge = [(x, 0) for x in range(width)] + [(x, height - 1) for x in range(width)] \
        + [(0, y) for y in range(height)] + [(width - 1, y) for y in range(height)]
    for point in edge:
        if mask.getpixel(point) == 255:
            ImageDraw.floodfill(mask, point, 128)
    return np.asarray(mask) == 128


def kmeans_palette(pixels: np.ndarray, colors: int, seed: int = 0, starts: int = 4) -> np.ndarray:
    """Up to `colors` colours that stand for `pixels` (k-means, k-means++
    start, on a sample), with colours closer than a glance can tell merged.
    The best of `starts` runs is kept: one start can settle on a blend of
    two parts (a khaki between a brown can and a green leaf) and lose both."""
    if len(pixels) == 0:
        return np.zeros((1, 3))
    rng = np.random.default_rng(seed)
    sample = pixels[rng.choice(len(pixels), size=min(len(pixels), 40000), replace=False)].astype(float)
    best, best_error = None, np.inf
    for _ in range(starts):
        centres = [sample[rng.integers(len(sample))]]
        for _ in range(1, colors):
            d = np.min([((sample - c) ** 2).sum(axis=1) for c in centres], axis=0)
            if d.sum() == 0:
                break
            centres.append(sample[rng.choice(len(sample), p=d / d.sum())])
        centres = np.array(centres)
        for _ in range(20):
            nearest_centre = ((sample[:, None, :] - centres[None]) ** 2).sum(axis=2).argmin(axis=1)
            moved = np.array([sample[nearest_centre == i].mean(axis=0) if (nearest_centre == i).any() else centres[i]
                              for i in range(len(centres))])
            if np.allclose(moved, centres, atol=0.5):
                break
            centres = moved
        error = ((sample[:, None, :] - centres[None]) ** 2).sum(axis=2).min(axis=1).sum()
        if error < best_error:
            best, best_error = centres, error
    kept: list[np.ndarray] = []
    for c in best:
        if all(np.abs(c - k).sum() > 30 for k in kept):
            kept.append(c)
    return np.round(np.array(kept))


def assign(pixels: np.ndarray, palette: np.ndarray) -> np.ndarray:
    """Each pixel's nearest palette index, a row at a time to keep memory low."""
    flat = pixels.reshape(-1, 3).astype(np.int32)
    out = np.empty(len(flat), dtype=np.int32)
    step = 262144
    for i in range(0, len(flat), step):
        chunk = flat[i:i + step]
        out[i:i + step] = ((chunk[:, None, :] - palette[None].astype(np.int32)) ** 2).sum(axis=2).argmin(axis=1)
    return out.reshape(pixels.shape[:2])


LINE_CONTRAST = 24


def square_filter(values: np.ndarray, reach: int, keep) -> np.ndarray:
    """The min (`keep=np.minimum`) or max of each `reach` square, one axis at
    a time, edges padded with themselves: Pillow's rank filter is ten times
    slower at a scene's size."""
    half = reach // 2
    out = values
    for axis in (0, 1):
        padded = np.pad(out, [(half, half) if a == axis else (0, 0) for a in (0, 1)], mode="edge")
        length = out.shape[axis]
        out = padded.take(range(0, length), axis=axis)
        for shift in range(1, reach):
            out = keep(out, padded.take(range(shift, shift + length), axis=axis))
    return out


def thin_lines(image: Image.Image, reach: int) -> np.ndarray:
    """Pixels on a line narrower than `reach` that stands out from what is on
    both sides of it: a string, an eye, a mouth, a highlight. A top-hat per
    channel (the pixel against the picture opened or closed by a square of
    `reach`), so the step between two regions and a sky's grain are not lines.
    """
    reach = max(3, reach | 1)
    pixels = np.asarray(image.convert("RGB")).astype(np.int16)
    found = np.zeros(pixels.shape[:2], bool)
    for c in range(3):
        value = pixels[:, :, c]
        opened = square_filter(square_filter(value, reach, np.minimum), reach, np.maximum)
        closed = square_filter(square_filter(value, reach, np.maximum), reach, np.minimum)
        found |= (value - opened > LINE_CONTRAST) | (closed - value > LINE_CONTRAST)
    return found


def long_lines(found: np.ndarray, smallest: int) -> np.ndarray:
    """The lines in `found` that are long and sparse (a string, an outline):
    at least `smallest` pixels joined together, covering under a fifth of
    their own box. A dense patch of short lines (the gaps between lit
    windows) is left to the blur, which keeps it as a few solid shapes."""
    width = found.shape[1]
    left = set(np.flatnonzero(found).tolist())
    kept = np.zeros(found.size, bool)
    while left:
        seed = left.pop()
        stack, part = [seed], [seed]
        while stack:
            y, x = divmod(stack.pop(), width)
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    q = (y + dy) * width + x + dx
                    if 0 <= x + dx < width and q in left:
                        left.remove(q)
                        stack.append(q)
                        part.append(q)
        if len(part) < smallest:
            continue
        ys, xs = np.divmod(np.array(part), width)
        if len(part) < 0.2 * (np.ptp(ys) + 1) * (np.ptp(xs) + 1):
            kept[part] = True
    return kept.reshape(found.shape)


def with_line_colours(palette: np.ndarray, line: np.ndarray, around: np.ndarray) -> np.ndarray:
    """The palette plus up to two colours for thin lines that would otherwise
    take the colour of what is around them (a pale string across a pale sky):
    a line is too few pixels to win a palette slot of its own. `line` is the
    lines' own pixels, `around` the blurred picture at the same places."""
    if len(line) == 0:
        return palette
    stands_out = np.abs(line.astype(int) - around.astype(int)).sum(axis=1) > LINE_CONTRAST
    lost = stands_out & (assign(line[None], palette)[0] == assign(around[None], palette)[0])
    if not lost.any():
        return palette
    added = [c for c in kmeans_palette(line[lost], 2) if np.abs(palette - c).sum(axis=1).min() > 16]
    return np.vstack([palette, *added]) if added else palette


DETAIL_ERROR = 60


def detail_colours(palette: np.ndarray, pixels: np.ndarray, drawn: np.ndarray,
                   smallest: int) -> tuple[np.ndarray, np.ndarray]:
    """Up to two colours for small flat details no palette colour stands
    for, and where they go: a black eye on a dark navy stripe is too few
    pixels to win a k-means slot, so it takes the stripe's colour and the
    face goes blank. A detail is flat (the same colour as its neighbours, so
    not an anti-aliased edge), far from every palette colour, one colour
    (not a blend of two missed parts), and at least `smallest` pixels. Only
    the detail's own pixels take its colour, so nothing around it changes."""
    none = np.zeros((0, 3)), np.zeros(drawn.shape, bool)
    values = pixels.astype(np.int16)
    spread = np.max([square_filter(values[:, :, c], 5, np.maximum) - square_filter(values[:, :, c], 5, np.minimum)
                     for c in range(3)], axis=0)
    error = np.abs(values - palette[assign(pixels, palette)]).sum(axis=2)
    missed = drawn & (spread < 20) & (error > DETAIL_ERROR)
    if missed.sum() < smallest:
        return none
    found = pixels[missed].astype(int)
    centres = kmeans_palette(found, 4)
    owners = assign(found[None], centres)[0]
    tight = []
    for i, c in enumerate(centres):
        members = found[owners == i]
        if len(members) >= smallest and np.abs(members - c).sum(axis=1).mean() < 30 \
                and np.abs(palette - c).sum(axis=1).min() > 30:
            tight.append((len(members), i))
    keep = [i for _, i in sorted(tight, reverse=True)[:2]]
    if not keep:
        return none
    where = np.zeros(drawn.shape, bool)
    where[missed] = np.isin(owners, keep)
    return centres[keep], where


SMOOTH_SPREAD = 20
SMOOTH_SIGMA = 8


def smoothed(rgb: Image.Image) -> Image.Image:
    """A scene with its grain taken out and its edges kept sharp. A sky is
    often a soft gradient with grain in it, and its bands come out ragged
    unless it is blurred; but a blur over the whole picture turns every
    edge into a ramp, and the ramp comes back as rings of in-between colour
    round every shape (grey halos round black pines on white) that also take
    palette slots from the picture's own colours. So: a median filter
    everywhere (grain out, edges kept), and a wide blur only where nothing
    within the blur's reach differs by more than `SMOOTH_SPREAD`, which is
    a gradient, never an edge or a low-contrast detail."""
    sharp = rgb.filter(ImageFilter.MedianFilter(5))
    soft = np.asarray(sharp.filter(ImageFilter.GaussianBlur(SMOOTH_SIGMA)))
    values = np.asarray(sharp).astype(np.int16)
    reach = 4 * SMOOTH_SIGMA + 1
    spread = np.max([square_filter(values[:, :, c], reach, np.maximum) - square_filter(values[:, :, c], reach, np.minimum)
                     for c in range(3)], axis=0)
    flat = (spread < SMOOTH_SPREAD)[:, :, None]
    return Image.fromarray(np.where(flat, soft, values).astype(np.uint8), "RGB")


def reduce_colours(image: Image.Image, colors: int, mode_size: int = 5,
                   keep_backdrop: bool = False) -> tuple[Image.Image, np.ndarray]:
    """The picture in at most `colors` flat colours.

    Pixels near the backdrop colour become transparent so the drawing sits on
    whatever canvas it lands on; the rest are quantised (k-means through
    Pillow) to a palette taken from the picture itself.
    """
    rgb = image.convert("RGB")
    lines = np.zeros(rgb.size[::-1], bool)
    line_pixels = np.zeros((0, 3), np.uint8)
    if keep_backdrop:
        # A scene's thin lines (a kite's string, an eye) are found on the
        # sharp picture and kept out of the blur and the mode filter below,
        # which would otherwise wipe them out.
        # A line smaller than the tracer's speck size (trace) would be dropped
        # there anyway, so only longer ones are kept.
        speck = max(4, round(rgb.size[0] / 96))
        lines = long_lines(thin_lines(rgb, round(rgb.size[0] / 228)), speck * speck)
        line_pixels = np.asarray(rgb)[lines]
        rgb = smoothed(rgb)
    pixels = np.asarray(rgb)
    backdrop = border_colour(pixels)
    distance = np.abs(pixels.astype(int) - backdrop).sum(axis=2)
    drawn = np.ones(distance.shape, bool) if keep_backdrop else distance >= 36
    shadow = np.zeros(distance.shape, bool)
    if not keep_backdrop:
        # A soft grey shadow under a figure is a little darker than the
        # backdrop and has no colour of its own; it would come back as ragged
        # specks of the nearest pale colour (a cream belly's). Pale grey
        # pixels joined to the backdrop are the backdrop; a cream or a white
        # inside the drawing is not joined to it, or has colour, and stays.
        values = pixels.astype(int)
        grey = (values.max(axis=2) - values.min(axis=2)) < 12
        shadow = backdrop_reached((distance < 36) | (grey & (distance < 100))) & (distance >= 36)
        drawn &= ~shadow
    # A drawing's palette comes from its own pixels, so the backdrop (most of
    # the picture) takes no slots from a small dark detail (an eye); the
    # backdrop's colour then joins as one more, so a faint shadow and the
    # blends along the outline fold into the backdrop and leave with it
    # (trace drops the backdrop-coloured region reaching the edge), and a
    # white inside the drawing (a cheek) still has its colour.
    base = kmeans_palette(pixels[drawn], colors)
    if not keep_backdrop and np.abs(base - backdrop).sum(axis=1).min() > 30:
        base = np.vstack([base, np.round(backdrop)])
    speck = max(4, round(rgb.size[0] / 96))
    added, details = detail_colours(base, pixels, drawn, speck * speck)
    with_details = np.vstack([base, added])
    palette = with_line_colours(with_details, line_pixels, pixels[lines])
    # Only a line may take a line's colour, and only a detail a detail's, so
    # the colours added for them do not eat into the regions around them.
    labels = assign(pixels, base)
    labels[details] = assign(pixels[details][None], with_details)[0]
    if shadow.any():
        labels[shadow] = assign(np.round(backdrop)[None, None].astype(np.uint8), base)[0, 0]
    labels[lines] = assign(line_pixels[None], palette)[0]
    quantised = Image.fromarray(labels.astype(np.uint8), "P")
    quantised.putpalette([int(v) for v in palette.flatten()] + [0] * (768 - palette.size))
    # A small mode filter folds the blends along anti-aliased edges into
    # one side or the other, so they do not come back as slivers.
    quantised = quantised.filter(ImageFilter.ModeFilter(mode_size))
    indices = np.asarray(quantised).copy()
    indices[lines] = labels[lines]
    quantised = Image.fromarray(indices, "P")
    quantised.putpalette([int(v) for v in palette.flatten()] + [0] * (768 - palette.size))
    flat = np.asarray(quantised.convert("RGB")).copy()
    alpha = np.full(distance.shape, 255, np.uint8)
    if not keep_backdrop:
        # The backdrop is made clear, so the tracer leaves it out: given as a
        # colour, it came back as a region over a full-picture rectangle of
        # the drawing's own colour (the tracer's stack starts with one), and
        # dropping the backdrop left a grey square behind a grey rabbit.
        # Clear is the backdrop-coloured region joined to the edge; a white
        # inside the drawing (a cheek) is not joined to it and stays.
        own = np.abs(palette - backdrop).sum(axis=1).argmin()
        if np.abs(palette[own] - backdrop).sum() <= 30:
            alpha[backdrop_reached(indices == own)] = 0
    return Image.fromarray(np.dstack([flat, alpha]), "RGBA"), backdrop


def colour_name(hex_colour: str) -> str:
    """A person's word for a colour: "Dark brown", "Pale yellow", "Black"."""
    r, g, b = (int(hex_colour[i:i + 2], 16) / 255 for i in (1, 3, 5))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    if l < 0.12:
        return "Black"
    if l > 0.93:
        return "White"
    if s < 0.12:
        return "Dark grey" if l < 0.4 else ("Light grey" if l > 0.7 else "Grey")
    degrees = h * 360
    hues = [(15, "Red"), (38, "Orange"), (70, "Yellow"), (160, "Green"), (200, "Teal"),
            (250, "Blue"), (290, "Purple"), (335, "Pink"), (361, "Red")]
    name = next(word for limit, word in hues if degrees < limit)
    if name in ("Orange", "Red") and (l < 0.4 or (s < 0.5 and l < 0.62)):
        name = "Brown"
    if name == "Yellow" and l < 0.4:
        name = "Olive"
    if l < 0.3:
        return f"Dark {name.lower()}"
    if l > 0.78:
        return f"Pale {name.lower()}"
    return name


PATH = re.compile(r'<path d="([^"]*)" fill="(#[0-9A-Fa-f]{6})" transform="translate\(([-\d.]+),([-\d.]+)\)"\s*/>')


def path_box(d: str, dx: float = 0, dy: float = 0) -> tuple[float, float, float, float] | None:
    """A path's box from its points and curve handles (a little generous)."""
    numbers = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", d)]
    xs, ys = numbers[0::2], numbers[1::2]
    if not xs or not ys:
        return None
    return min(xs) + dx, min(ys) + dy, max(xs) + dx, max(ys) + dy


def path_area(d: str) -> float:
    """Rough area of a path from its points' bounding box."""
    box = path_box(d)
    return 0 if box is None else (box[2] - box[0]) * (box[3] - box[1])


SCENE_SPECKLE = 320
GATHER_AREA = 0.001


def shifted(d: str, dx: float, dy: float) -> str:
    """A path's commands moved by (dx, dy). The tracer writes only absolute
    M, L, C and Z, so its numbers are x, y pairs throughout."""
    out, index = [], 0
    for token in re.findall(r"[A-Za-z]|-?\d+(?:\.\d+)?", d):
        if token.isalpha():
            out.append(token)
            continue
        out.append(f"{float(token) + (dx if index % 2 == 0 else dy):.1f}".rstrip("0").rstrip("."))
        index += 1
    return " ".join(out)


def gathered(kept: list, small: float) -> list:
    """A scene's small shapes of one colour made one layer: a city's lit
    windows, a night's stars. One layer a window would be hundreds of layers
    nobody can work with, and the path cap would drop most of them. The
    gathered layer sits where the last of them did, so it stays on top of
    what it was drawn over."""
    groups: dict[str, list[int]] = {}
    for i, (d, fill, _, _) in enumerate(kept):
        if path_area(d) < small:
            groups.setdefault(fill, []).append(i)
    merged = {members[-1]: members for members in groups.values() if len(members) > 1}
    dropped = {i for members in merged.values() for i in members}
    out = []
    for i, path in enumerate(kept):
        if i in merged:
            d = " ".join(shifted(kept[j][0], kept[j][2], kept[j][3]) for j in merged[i])
            out.append((d, path[1], 0.0, 0.0))
        elif i not in dropped:
            out.append(path)
    return out


def trace(image: Image.Image, colors: int = 10, speckle: int | None = None, scale: int = 2,
          mode_size: int = 5, keep_backdrop: bool = False) -> dict:
    """The picture as an SVG of named, filled paths, and what was kept.

    The picture is traced at `scale` times its size, so region edges fall
    between pixels and the curves come out smooth rather than stepped; the
    SVG is drawn back at the picture's own size. A scene (`keep_backdrop`)
    keeps its sky and ground as layers instead of clearing the backdrop.
    """
    original = image.size
    if scale > 1:
        image = image.convert("RGB").resize((original[0] * scale, original[1] * scale), Image.Resampling.LANCZOS)
    width, height = image.size
    flat, backdrop = reduce_colours(image, colors, mode_size, keep_backdrop)
    opaque = np.asarray(flat)
    opaque = opaque[opaque[:, :, 3] > 0][:, :3].astype(int)
    palette = np.unique(opaque, axis=0) if len(opaque) else np.zeros((1, 3), int)
    buffer = io.BytesIO()
    flat.save(buffer, format="PNG")
    # A scene's small things (lit windows, stars, lamps) are what it is
    # made of, where a thing's specks are noise: a scene keeps patches a
    # quarter the size, and its small shapes are gathered by colour below.
    speckle = speckle or max(4, round(width / (SCENE_SPECKLE if keep_backdrop else 96)))
    svg = vtracer.convert_raw_image_to_svg(
        buffer.getvalue(), img_format="png", colormode="color", hierarchical="stacked", mode="spline",
        filter_speckle=speckle, color_precision=8, layer_difference=8, corner_threshold=60,
        length_threshold=4.0, max_iterations=10, splice_threshold=45, path_precision=1)
    found = [(m.group(1), nearest(m.group(2), palette), float(m.group(3)), float(m.group(4)))
             for m in PATH.finditer(svg)]
    smallest = speckle * speckle if keep_backdrop else (width * height) * 0.00015

    def is_backdrop(d: str, fill: str, dx: float, dy: float) -> bool:
        # The tracer does not read transparency, so the backdrop comes back
        # as a path of its own colour reaching the picture's edge.
        rgb = np.array([int(fill[i:i + 2], 16) for i in (1, 3, 5)])
        box = path_box(d, dx, dy)
        touches = box is not None and (box[0] <= 1 or box[1] <= 1 or box[2] >= width - 1 or box[3] >= height - 1)
        return not keep_backdrop and touches and np.abs(rgb - backdrop).sum() < 48

    kept = [p for p in found if path_area(p[0]) >= smallest and not is_backdrop(*p)]
    if keep_backdrop:
        kept = gathered(kept, width * height * GATHER_AREA)
    if len(kept) > MAX_PATHS:
        # Keep the biggest regions; the stacking order of the rest is kept.
        biggest = set(sorted(range(len(kept)), key=lambda i: -path_area(kept[i][0]))[:MAX_PATHS])
        kept = [p for i, p in enumerate(kept) if i in biggest]
    counts: dict[str, int] = {}
    lines = []
    for d, fill, dx, dy in kept:
        name = colour_name(fill)
        counts[name] = counts.get(name, 0) + 1
        label = name if counts[name] == 1 else f"{name} {counts[name]}"
        lines.append(f'<path id="{label}" d="{d}" fill="{fill}" transform="translate({dx:g},{dy:g})"/>')
    # The drawing's own bounds, so it fills the box it is placed in the way
    # any other drawing does rather than carrying the picture's empty margin.
    boxes = [b for b in (path_box(d, dx, dy) for d, _, dx, dy in kept) if b]
    if boxes:
        left = max(0, min(b[0] for b in boxes))
        top = max(0, min(b[1] for b in boxes))
        right = min(width, max(b[2] for b in boxes))
        bottom = min(height, max(b[3] for b in boxes))
    else:
        left, top, right, bottom = 0, 0, width, height
    w, h = right - left, bottom - top
    shrink = original[0] / width
    out = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{left:.1f} {top:.1f} {w:.1f} {h:.1f}" '
           f'width="{w * shrink:.1f}" height="{h * shrink:.1f}">\n' + "\n".join(lines) + "\n</svg>\n")
    return {"svg": out, "paths": len(kept), "found": len(found),
            "palette": sorted({p[1] for p in kept}), "clipped": clipped(image, backdrop, keep_backdrop)}


def clipped(image: Image.Image, backdrop: np.ndarray, keep_backdrop: bool) -> bool:
    """Whether the drawing runs off the picture: more than one part in a
    hundred of the picture's edge is not the backdrop's colour. A scene fills
    the frame on purpose, so it never counts."""
    if keep_backdrop:
        return False
    pixels = np.asarray(image.convert("RGB")).astype(int)
    edge = np.concatenate([pixels[0], pixels[-1], pixels[:, 0], pixels[:, -1]])
    return bool((np.abs(edge - backdrop).sum(axis=1) >= 36).mean() > 0.01)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("picture")
    parser.add_argument("--colors", type=int, default=10)
    parser.add_argument("--out")
    args = parser.parse_args()
    result = trace(Image.open(args.picture), colors=args.colors)
    if args.out:
        with open(args.out, "w") as f:
            f.write(result["svg"])
    else:
        sys.stdout.write(result["svg"])
    print(f"{result['paths']} paths kept of {result['found']}, {len(result['palette'])} colours", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
