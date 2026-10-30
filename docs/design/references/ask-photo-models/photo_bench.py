"""Times and weighs one picture model on the photo prompts: python photo_bench.py qwen|moss|zimage photos.json out/
One JSON line per event; memory is the process's physical footprint (what MLX's buffers count against)."""
import ctypes, json, os, sys, time
sys.path.insert(0, os.path.expanduser("~/Library/Caches/photonz-measure-qwen21"))
from bench import RusageV4, usage, Sampler
which, prompts, out = sys.argv[1], json.load(open(sys.argv[2])), sys.argv[3]
os.makedirs(out, exist_ok=True)
import mlx.core as mx
mx.set_cache_limit(1 << 30)
sampler = Sampler()
def say(event, **kw):
    u = usage()
    print(json.dumps({"event": event, "model": which, "footprintGB": round(u.phys_footprint / 1e9, 2),
                      "maxFootprintGB": round(u.lifetime_max_phys_footprint / 1e9, 2), **kw}), flush=True)
t = time.time()
if which == "qwen":
    from mflux.models.common.config import ModelConfig
    from mflux.models.qwen21.variants.edit.qwen_image_21_edit import QwenImage21Edit
    model = QwenImage21Edit(quantize=None, model_path=os.path.expanduser("~/Library/Caches/photonz-measure-qwen21/ckpt/turbo-q8"),
                            model_config=ModelConfig.from_name("qwen-image-2.1-turbo"))
    gen = lambda p: model.generate_image(seed=p["seed"], prompt=p["prompt"], width=p["width"], height=p["height"])
elif which == "moss":
    from mflux.models.moss_image import MOSSImage
    model = MOSSImage(quantize=8)
    gen = lambda p: model.generate_image(seed=p["seed"], prompt=p["prompt"], width=p["width"], height=p["height"],
                                         num_inference_steps=int(os.environ.get("STEPS", "50")), guidance=3.0)
elif which == "zimage":
    from mflux.models.z_image.cli.z_image_turbo_generate import ZImageTurboCommand, build_parser
    sys.argv = ["x", "--model", os.path.expanduser("~/Library/Application Support/Photonz/Models/z-image-turbo-q8"), "--prompt", "x"]
    args = build_parser().parse_args()
    model = ZImageTurboCommand.load(args)
    def gen(p):
        args.width, args.height = p["width"], p["height"]
        return ZImageTurboCommand.generate(model, args, p["seed"], p["prompt"])
if which != "zimage":
    mx.eval(model.parameters())
say("loaded", seconds=round(time.time() - t, 1), peakFootprintGB=sampler.take_foot())
for p in prompts:
    sampler.take_foot(); mx.reset_peak_memory()
    t = time.time()
    made = gen(p)
    s = time.time() - t
    path = os.path.join(out, f"{which}-{p['name']}.png")
    made.image.save(path)
    peak = mx.get_peak_memory() / 1e9
    mx.clear_cache()
    say("picture", name=p["name"], seconds=round(s, 1), peakFootprintGB=sampler.take_foot(), mlxPeakGB=round(peak, 2), path=path)
