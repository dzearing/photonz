"""Two eval runs' drawings side by side, one request a row: today's way on the
left, painted on the right, each with its score.

    compare-sheet.py <out.png> <run-dir-a> <run-dir-b> [case ...]

Climb-set runs only (Scripts/ask-eval/README.md: held-out pictures are never
put where runners read).
"""
from __future__ import annotations

import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

TILE = (420, 300)


def tile(run: str, case: str) -> tuple[Image.Image, str]:
    folder = os.path.join(run, case)
    picture = Image.new("RGB", TILE, "white")
    try:
        made = Image.open(os.path.join(folder, "result.png")).convert("RGB")
        made.thumbnail(TILE)
        picture.paste(made, ((TILE[0] - made.width) // 2, (TILE[1] - made.height) // 2))
    except OSError:
        pass
    try:
        score = json.load(open(os.path.join(folder, "score.json")))
        lines = (score.get("judge") or {}).get("lines") or {}
        label = f"{score.get('score', '-')}  asked {lines.get('didWhatWasAsked', '-')} clean {lines.get('clean', '-')}"
    except OSError:
        label = "not run"
    return picture, label


def main() -> int:
    out, a, b, *cases = sys.argv[1:]
    if not cases:
        cases = sorted(c for c in os.listdir(b) if os.path.isfile(os.path.join(b, c, "result.png")))
    font = ImageFont.load_default(size=16)
    head = 28
    sheet = Image.new("RGB", (TILE[0] * 2 + 30, (TILE[1] + head) * len(cases) + 40), "white")
    draw = ImageDraw.Draw(sheet)
    draw.text((10, 10), f"left: {os.path.basename(a)}   right: {os.path.basename(b)}", fill="black", font=font)
    for row, case in enumerate(cases):
        y = 40 + row * (TILE[1] + head)
        for column, run in enumerate((a, b)):
            picture, label = tile(run, case)
            x = 10 + column * (TILE[0] + 10)
            sheet.paste(picture, (x, y + head))
            draw.text((x, y + 4), f"{case}: {label}", fill="black", font=font)
            draw.rectangle((x, y + head, x + TILE[0] - 1, y + head + TILE[1] - 1), outline=(200, 200, 200))
    sheet.save(out)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
