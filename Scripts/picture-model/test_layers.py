"""Checks for layers.py, on pictures made here (nothing stored).

    <picture-tools python> -I Scripts/picture-model/test_layers.py

Run with the Python Settings > Ask installs (it has numpy, Pillow, vtracer):
~/Library/Application Support/Photonz/Models/picture-tools/env/bin/python3
"""
from __future__ import annotations

import os
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


if __name__ == "__main__":
    unittest.main()
