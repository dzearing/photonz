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
    """The backdrop-coloured pixels joined to the picture's edge: white eyes
    and highlights inside the drawing stay part of it."""
    mask = Image.fromarray(np.where(near, 255, 0).astype(np.uint8), "L")
    height, width = near.shape
    edge = [(x, 0) for x in range(width)] + [(x, height - 1) for x in range(width)] \
        + [(0, y) for y in range(height)] + [(width - 1, y) for y in range(height)]
    for point in edge:
        if mask.getpixel(point) == 255:
            ImageDraw.floodfill(mask, point, 128)
    return np.asarray(mask) == 128


def kmeans_palette(pixels: np.ndarray, colors: int, seed: int = 0) -> np.ndarray:
    """Up to `colors` colours that stand for `pixels` (k-means, k-means++
    start, on a sample), with colours closer than a glance can tell merged."""
    if len(pixels) == 0:
        return np.zeros((1, 3))
    rng = np.random.default_rng(seed)
    sample = pixels[rng.choice(len(pixels), size=min(len(pixels), 40000), replace=False)].astype(float)
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
    kept: list[np.ndarray] = []
    for c in centres:
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


def reduce_colours(image: Image.Image, colors: int, mode_size: int = 5,
                   keep_backdrop: bool = False) -> tuple[Image.Image, np.ndarray]:
    """The picture in at most `colors` flat colours, the backdrop made clear.

    Pixels near the backdrop colour become transparent so the drawing sits on
    whatever canvas it lands on; the rest are quantised (k-means through
    Pillow) to a palette taken from the picture itself.
    """
    rgb = image.convert("RGB")
    if keep_backdrop:
        # A scene's sky is often a soft gradient with grain in it; a light
        # blur lets its bands come out as smooth curves instead of ragged ones.
        rgb = rgb.filter(ImageFilter.GaussianBlur(3))
    pixels = np.asarray(rgb)
    backdrop = border_colour(pixels)
    distance = np.abs(pixels.astype(int) - backdrop).sum(axis=2)
    clear = np.zeros(distance.shape, bool) if keep_backdrop else backdrop_reached(distance < 36)
    # The palette comes from the drawing's own pixels only, so the backdrop
    # takes no slots and a small dark detail (an eye) keeps its colour.
    palette = kmeans_palette(pixels[~clear], colors)
    labels = assign(pixels, palette)
    quantised = Image.fromarray(labels.astype(np.uint8), "P")
    quantised.putpalette([int(v) for v in palette.flatten()] + [0] * (768 - palette.size))
    # A small mode filter folds the blends along anti-aliased edges into
    # one side or the other, so they do not come back as slivers.
    quantised = quantised.filter(ImageFilter.ModeFilter(mode_size))
    flat = np.asarray(quantised.convert("RGB")).copy()
    alpha = np.where(clear, 0, 255).astype(np.uint8)
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
    speckle = speckle or max(4, round(width / 96))
    svg = vtracer.convert_raw_image_to_svg(
        buffer.getvalue(), img_format="png", colormode="color", hierarchical="stacked", mode="spline",
        filter_speckle=speckle, color_precision=8, layer_difference=8, corner_threshold=60,
        length_threshold=4.0, max_iterations=10, splice_threshold=45, path_precision=1)
    found = [(m.group(1), nearest(m.group(2), palette), float(m.group(3)), float(m.group(4)))
             for m in PATH.finditer(svg)]
    smallest = (width * height) * 0.00015

    def is_backdrop(d: str, fill: str, dx: float, dy: float) -> bool:
        # The tracer does not read transparency, so the backdrop comes back
        # as a path of its own colour reaching the picture's edge.
        rgb = np.array([int(fill[i:i + 2], 16) for i in (1, 3, 5)])
        box = path_box(d, dx, dy)
        touches = box is not None and (box[0] <= 1 or box[1] <= 1 or box[2] >= width - 1 or box[3] >= height - 1)
        return not keep_backdrop and touches and np.abs(rgb - backdrop).sum() < 48

    kept = [p for p in found if path_area(p[0]) >= smallest and not is_backdrop(*p)]
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
