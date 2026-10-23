"""Checks for layers.py, on pictures made here (nothing stored).

    <picture-tools python> -I Scripts/picture-model/test_layers.py

Run with the Python Settings > Ask installs (it has numpy, Pillow, vtracer):
~/Library/Application Support/Photonz/Models/picture-tools/env/bin/python3
"""
from __future__ import annotations

import os
import re
import sys
import unittest

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import layers  # noqa: E402

SKY_TOP, SKY_LOW, GROUND, LINE = (175, 232, 244), (214, 243, 248), (240, 192, 136), (255, 255, 255)


def scene(width: int = 1024, height: int = 768, grain: int = 3, seed: int = 0) -> tuple[Image.Image, list]:
    """A scene the way the picture model paints one: a sky fading from one
    blue to a paler one, with grain, a ground, and a thin pale line running
    from high in the sky down into the paler part. Returns the picture and
    points along the line at its own size."""
    rng = np.random.default_rng(seed)
    t = np.linspace(0, 1, height)[:, None, None]
    sky = (np.array(SKY_TOP) * (1 - t) + np.array(SKY_LOW) * t) * np.ones((1, width, 1))
    sky += rng.normal(0, grain, sky.shape)
    ground_top = int(height * 0.88)
    sky[ground_top:] = GROUND
    picture = Image.fromarray(np.clip(sky, 0, 255).astype(np.uint8), "RGB")
    start, end = (width * 0.3, height * 0.15), (width * 0.6, height * 0.8)
    ImageDraw.Draw(picture).line([start, end], fill=LINE, width=2)
    points = [(start[0] + (end[0] - start[0]) * f, start[1] + (end[1] - start[1]) * f) for f in np.linspace(0.05, 0.95, 40)]
    return picture, points


def near_line(flat: np.ndarray, x: float, y: float) -> bool:
    """Whether a pixel within two of (x, y) still has the line's colour."""
    patch = flat[int(y) - 2:int(y) + 3, int(x) - 2:int(x) + 3, :3].astype(int)
    return bool((np.abs(patch - LINE).sum(axis=2) < 40).any())


class ScenesKeepThinLines(unittest.TestCase):
    def test_a_thin_pale_line_survives_the_whole_way(self):
        picture, points = scene()
        big = picture.resize((picture.size[0] * 2, picture.size[1] * 2), Image.Resampling.LANCZOS)
        flat, _ = layers.reduce_colours(big, 14, 7, keep_backdrop=True)
        flat = np.asarray(flat)
        kept = [near_line(flat, x * 2, y * 2) for x, y in points]
        self.assertEqual(sum(kept), len(kept), f"line lost at {[p for p, k in zip(points, kept) if not k]}")

    def test_the_sky_stays_in_smooth_bands(self):
        # Grain must not come back as specks: the sky away from the line is
        # only a few colours, each in big pieces.
        picture, _ = scene()
        big = picture.resize((picture.size[0] * 2, picture.size[1] * 2), Image.Resampling.LANCZOS)
        flat = np.asarray(layers.reduce_colours(big, 14, 7, keep_backdrop=True)[0])[:, 1400:, :3]
        sky = flat[: int(flat.shape[0] * 0.85)]
        keys = sky[:, :, 0].astype(int) * 65536 + sky[:, :, 1].astype(int) * 256 + sky[:, :, 2]
        _, counts = np.unique(keys, return_counts=True)
        self.assertLessEqual(len(counts), 8)
        self.assertGreater(counts.min(), sky.shape[1] * 4)

    def test_lines_finds_a_line_and_not_an_edge_or_grain(self):
        picture, points = scene()
        found = layers.thin_lines(picture, reach=5)
        on_line = [found[int(y) - 1:int(y) + 2, int(x) - 1:int(x) + 2].any() for x, y in points]
        self.assertEqual(sum(on_line), len(on_line))
        # The ground's top edge is a step, not a line, and the sky's grain is
        # not a line either: almost nothing away from the line is picked.
        away = found.copy()
        for x, y in points:
            away[int(y) - 6:int(y) + 7, int(x) - 6:int(x) + 7] = False
        self.assertLess(away.mean(), 0.001)

    def test_a_dense_grid_is_not_a_long_line(self):
        # Lit windows on a dark block: the dark gaps between them are thin and
        # stand out, but pulling them back sharp would cut the windows into
        # specks the tracer drops. Only a long, sparse line is kept.
        picture, points = scene()
        draw = ImageDraw.Draw(picture)
        draw.rectangle([700, 300, 860, 600], fill=(30, 40, 70))
        for y in range(306, 596, 10):
            for x in range(706, 856, 10):
                draw.rectangle([x, y, x + 6, y + 6], fill=(230, 210, 150))
        found = layers.long_lines(layers.thin_lines(picture, reach=5), smallest=100)
        self.assertFalse(found[300:600, 700:860].any(), "the window grid was kept as a line")
        on_line = [found[int(y) - 1:int(y) + 2, int(x) - 1:int(x) + 2].any() for x, y in points]
        self.assertEqual(sum(on_line), len(on_line))

    def test_the_traced_scene_has_a_layer_for_the_line(self):
        picture, points = scene()
        traced = layers.trace(picture, colors=14, mode_size=7, keep_backdrop=True)
        white = [line for line in traced["svg"].splitlines() if 'fill="#F' in line and 'id="White' in line]
        self.assertTrue(white, "no white layer in the traced scene")


def thing(size: int = 768) -> Image.Image:
    """A thing the way the picture model paints one: on white, a big blue
    body with a dark navy band across it, a small black eye sitting on the
    band, a cream patch inside a dark outline, and a soft grey shadow on
    the ground beneath."""
    picture = Image.new("RGB", (size, size), (255, 255, 255))
    pixels = np.asarray(picture).astype(float).copy()
    ys, xs = np.mgrid[0:size, 0:size]
    # The shadow: a soft grey ellipse fading out into the white.
    d = ((xs - size * 0.5) / (size * 0.3)) ** 2 + ((ys - size * 0.86) / (size * 0.05)) ** 2
    pixels -= (np.clip(1 - d, 0, 1) * 30)[:, :, None]
    picture = Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8), "RGB")
    draw = ImageDraw.Draw(picture)
    draw.ellipse([size * 0.2, size * 0.15, size * 0.8, size * 0.8], fill=(60, 120, 180))
    draw.rectangle([size * 0.25, size * 0.3, size * 0.75, size * 0.38], fill=(26, 37, 53))
    draw.ellipse([size * 0.4, size * 0.31, size * 0.43, size * 0.34], fill=(0, 0, 0))
    draw.ellipse([size * 0.35, size * 0.5, size * 0.65, size * 0.7], fill=(250, 242, 225), outline=(40, 30, 25), width=8)
    for shade in range(12):
        # a few greens, blues and browns elsewhere, so the palette is busy
        x = size * (0.27 + 0.04 * shade)
        draw.rectangle([x, size * 0.42, x + size * 0.03, size * 0.47],
                       fill=(40 + 15 * shade, 160 - 6 * shade, 60 + 9 * shade))
    return picture


def colour_at(flat: np.ndarray, x: float, y: float) -> np.ndarray:
    return flat[int(y), int(x), :3].astype(int)


class ScenesHaveNoHalos(unittest.TestCase):
    """A blur over a whole scene turned every edge into a ramp that came back
    as rings of grey round black pines on white (2026-10-23, the judge: 'grey
    halo fringes along every edge')."""

    def test_a_black_shape_on_white_has_no_ring_of_grey(self):
        picture = Image.new("RGB", (1024, 768), "white")
        ImageDraw.Draw(picture).polygon([(300, 650), (512, 120), (724, 650)], fill=(22, 20, 20))
        big = picture.resize((2048, 1536), Image.Resampling.LANCZOS)
        flat = np.asarray(layers.reduce_colours(big, 14, 7, keep_backdrop=True)[0])[:, :, :3].astype(int)
        between = (flat.min(axis=2) > 60) & (flat.max(axis=2) < 220)
        self.assertLess(between.sum(), 200, f"{between.sum()} pixels of in-between grey")

    def test_low_contrast_detail_is_not_smoothed_away(self):
        picture = Image.new("RGB", (1024, 768), (45, 42, 44))
        ImageDraw.Draw(picture).ellipse([480, 360, 540, 420], fill=(22, 20, 20))
        big = picture.resize((2048, 1536), Image.Resampling.LANCZOS)
        flat = np.asarray(layers.reduce_colours(big, 14, 7, keep_backdrop=True)[0])[:, :, :3].astype(int)
        self.assertLess(flat[780, 1020].sum(), 3 * 32)
        self.assertGreater(flat[100, 100].sum(), 3 * 38)


class ScenesKeepSmallThings(unittest.TestCase):
    """A city's lit windows were each under the tracer's speck size, and the
    night skyline came back as dark blocks (2026-10-23)."""

    def test_lit_windows_come_through_in_a_few_layers(self):
        picture = Image.new("RGB", (1024, 768), (14, 22, 32))
        draw = ImageDraw.Draw(picture)
        draw.rectangle([300, 250, 700, 768], fill=(10, 12, 16))
        windows = [(320 + 30 * i, 280 + 30 * j) for i in range(12) for j in range(14)]
        for x, y in windows:
            draw.rectangle([x, y, x + 6, y + 8], fill=(236, 214, 150))
        traced = layers.trace(picture, colors=14, mode_size=7, keep_backdrop=True)
        lit = [m for m in re.finditer(r'd="([^"]*)" fill="(#[0-9A-F]{6})"', traced["svg"])
               if int(m.group(2)[1:3], 16) > 180]
        shapes = sum(m.group(1).count("M") for m in lit)
        self.assertGreater(shapes, 0.9 * len(windows), f"{shapes} of {len(windows)} windows")
        self.assertLessEqual(len(lit), 3)


class ThingsKeepSmallDetails(unittest.TestCase):
    def test_a_black_eye_on_a_dark_band_keeps_its_colour(self):
        picture = thing()
        big = picture.resize((picture.size[0] * 2, picture.size[1] * 2), Image.Resampling.LANCZOS)
        flat = np.asarray(layers.reduce_colours(big, 10)[0])
        size = big.size[0]
        eye = colour_at(flat, size * 0.415, size * 0.325)
        band = colour_at(flat, size * 0.6, size * 0.34)
        self.assertLess(eye.sum(), 40, f"the eye came out {eye}")
        self.assertGreater(np.abs(eye - band).sum(), 60, "the eye merged into the band")

    def test_a_soft_shadow_leaves_with_the_backdrop_and_the_cream_stays(self):
        picture = thing()
        big = picture.resize((picture.size[0] * 2, picture.size[1] * 2), Image.Resampling.LANCZOS)
        flat = np.asarray(layers.reduce_colours(big, 10)[0])
        size = big.size[0]
        shadow = flat[int(size * 0.85):int(size * 0.87), int(size * 0.3):int(size * 0.7), :3].astype(int)
        self.assertTrue((shadow.min(axis=2) > 245).all(), "the shadow came back as a colour")
        cream = colour_at(flat, size * 0.5, size * 0.6)
        self.assertLess(np.abs(cream - (250, 242, 225)).sum(), 20, f"the cream patch came out {cream}")

    def test_the_traced_thing_has_no_backdrop_or_shadow_layer(self):
        traced = layers.trace(thing(), colors=10)
        self.assertNotIn('id="White', traced["svg"])
        self.assertIn("Black", traced["svg"])

    def test_a_grey_thing_on_white_has_no_square_behind_it(self):
        # The tracer's stack starts with a full-picture rectangle; with the
        # backdrop given as a colour, dropping it left the rectangle showing
        # in the drawing's own grey whenever that grey covered more of the
        # picture than the backdrop (a grey rabbit on a grey square).
        picture = Image.new("RGB", (512, 512), (254, 254, 253))
        draw = ImageDraw.Draw(picture)
        draw.ellipse([20, 60, 492, 500], fill=(147, 128, 120), outline=(3, 2, 2), width=10)
        draw.ellipse([300, 60, 360, 200], fill=(131, 101, 90), outline=(3, 2, 2), width=8)
        traced = layers.trace(picture, colors=10)
        boxes = [layers.path_box(m.group(2), float(m.group(4)), float(m.group(5))) for m in re.finditer(
            r'<path id="([^"]+)" d="([^"]*)" fill="(#\w+)" transform="translate\(([-\d.]+),([-\d.]+)\)"', traced["svg"])]
        self.assertTrue(boxes)
        for box in boxes:
            self.assertFalse(box[0] <= 1 and box[1] <= 1 and box[2] >= 1023 and box[3] >= 1023,
                             f"a path covers the whole picture: {box}")


class BackdropReached(unittest.TestCase):
    def test_it_fills_from_the_edge_and_not_an_enclosed_hole(self):
        near = np.ones((20, 20), bool)
        near[5:15, 5:15] = False
        near[8:12, 8:12] = True
        reached = layers.backdrop_reached(near)
        self.assertTrue(reached[0, 0] and reached[19, 19])
        self.assertFalse(reached[10, 10])


if __name__ == "__main__":
    unittest.main()
