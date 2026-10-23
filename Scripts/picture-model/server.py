"""A picture model on this Mac that Ask can draw with, behind a loopback port.

Photonz runs it (`AskPictureServer`, docs/design/ask.md "The picture model's
setup"): Settings > Ask installs its Python and weights, and Photonz starts it
with PHOTONZ_PICTURE_PORT and PHOTONZ_PICTURE_MODEL set, the first time Ask paints.

POST /draw {"subject": "...", "style": "...", "seed": 1, "size": 768}
  -> {"svg": "...", "paths": 27, "palette": [...], "seconds": 26.1, "picture": "/tmp/....png"}
GET /health -> {"model": "...", "ready": true}

The picture comes from Z-Image Turbo (Apache 2.0, through mflux, MIT) and is
traced into named, filled paths by trace.py (vtracer, MIT). The prompt is the
request's own words plus a general description of a flat, traceable look:
nothing in here knows about any particular subject.
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from layers import trace  # noqa: E402

MODEL = os.environ.get("PHOTONZ_PICTURE_MODEL", "mflux-community/z-image-turbo-mflux-q8")
PORT = int(os.environ.get("PHOTONZ_PICTURE_PORT", "8793"))

LOOK = ("flat vector illustration, simple bold shapes, a few flat colours, clean edges, "
        "no gradients, no texture, no shading, no text, no letters, no border, "
        "the whole picture centred with space around it and nothing cut off by the edge, "
        "on a plain white background")
STYLES = {
    "line art": "black line art drawing, uniform thick outlines, no fill colours, no text, plain white background",
    "silhouette": "solid single colour silhouette, no inner detail, no text, plain white background",
}

model = None


def load():
    global model
    from mflux.models.z_image.cli.z_image_turbo_generate import ZImageTurboCommand, build_parser
    saved, sys.argv = sys.argv, ["server", "--model", MODEL, "--prompt", "x"]
    try:
        args = build_parser().parse_args()
    finally:
        sys.argv = saved
    model = (ZImageTurboCommand, args, ZImageTurboCommand.load(args))


ICON = ("simple bold flat icon, minimal detail, a few flat colours, no gradients, no text, no letters, "
        "no border, no rounded square behind it, centred on a plain flat light grey background")


SCENE = ("flat vector illustration of the whole scene filling the frame edge to edge, with its own sky and "
         "ground, every figure and object whole inside the frame with room around it, none cut off by the edge, "
         "layered flat shapes for depth, a few flat colours, clean edges, no gradients, no texture, "
         "no text, no letters, no border")


def prompt_for(subject: str, style: str | None, icon: bool = False, scene: bool = False) -> str:
    style = (style or "").strip().lower()
    if icon:
        return f"{subject}. {ICON}"
    if scene:
        named = f"{style} style, " if style and style not in ("flat", "illustration", "flat illustration") else ""
        return f"{subject}. {named}{SCENE}"
    look = next((words for key, words in STYLES.items() if key in style), None)
    if look:
        return f"{subject}. {look}"
    named = f"{style} style, " if style and style not in ("flat", "illustration", "flat illustration") else ""
    return f"{subject}. {named}{LOOK}"


def draw(subject: str, style: str | None, seed: int, size: int, colors: int, icon: bool = False,
         scene: bool = False, retried: bool = False) -> dict:
    command, args, loaded = model
    # A scene is a landscape picture, the shape of a canvas; a thing is square.
    args.width, args.height = (size * 4 // 3 // 16 * 16, size) if scene else (size, size)
    prompt = prompt_for(subject, style, icon, scene)
    started = time.time()
    made = command.generate(loaded, args, seed, prompt)
    # MLX keeps every buffer it made for the next picture; between pictures
    # that is gigabytes the planning model beside it needs.
    import mlx.core as mx
    mx.clear_cache()
    painted = time.time() - started
    picture = made.image
    path = tempfile.NamedTemporaryFile(prefix="photonz-picture-", suffix=".png", delete=False).name
    picture.save(path)
    traced = trace(picture, colors=colors + 4 if scene else colors, mode_size=7 if scene else 5, keep_backdrop=scene)
    if traced["clipped"] and not retried:
        # Part of the drawing ran off the picture and would land cut off
        # straight along the edge: painted once more from another seed.
        print(f"{subject!r} ran off the edge; painting again", flush=True)
        return draw(subject, style, seed + 7919, size, colors, icon, scene, retried=True)
    return {**traced, "model": MODEL, "prompt": prompt, "picture": path, "seconds": round(time.time() - started, 1),
            "paintSeconds": round(painted, 1)}


class Handler(BaseHTTPRequestHandler):
    def reply(self, status: int, body: dict):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            self.reply(200, {"model": MODEL, "ready": model is not None})
        else:
            self.reply(404, {"error": "no such page"})

    def do_POST(self):
        if self.path != "/draw":
            return self.reply(404, {"error": "no such page"})
        try:
            asked = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
            subject = str(asked.get("subject", "")).strip()
            if not subject:
                return self.reply(400, {"error": "say what to draw"})
            result = draw(subject, asked.get("style"), int(asked.get("seed", 1)),
                          int(asked.get("size", 768)), int(asked.get("colors", 10)), bool(asked.get("icon", False)),
                          bool(asked.get("scene", False)))
            print(f"drew {subject!r} in {result['seconds']}s, {result['paths']} paths", flush=True)
            self.reply(200, result)
        except Exception as trouble:  # the app falls back to its own way
            self.reply(500, {"error": str(trouble)})

    def log_message(self, *_):
        pass


def main():
    import mlx.core as mx
    mx.set_cache_limit(1 << 30)
    load()
    print(f"picture model {MODEL} ready on 127.0.0.1:{PORT}", flush=True)
    # One thread: MLX keeps its streams per thread, so the model is used on
    # the thread that loaded it, one picture at a time.
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
