# Draws the memory curve of a speed walk results file (its "memory" section) as a PNG:
#   python3 Scripts/perf/memory-chart.py <results.json> <out.png>
import json, sys
from PIL import Image, ImageDraw, ImageFont
r = json.load(open(sys.argv[1])); out = sys.argv[2]
m = r['memory']; fp = m['footprintMB']; rs = m['residentMB']; at = m.get('atSeconds') or list(range(1, len(fp) + 1))
W, H, L, B, T, R = 1200, 600, 90, 70, 60, 40
img = Image.new('RGB', (W, H), (250, 250, 250)); d = ImageDraw.Draw(img)
try:
    f = ImageFont.truetype('/System/Library/Fonts/SFNS.ttf', 20); fs = ImageFont.truetype('/System/Library/Fonts/SFNS.ttf', 16)
except Exception:
    f = fs = ImageFont.load_default()
top = max(max(fp), max(rs)) * 1.1; span = max(at[-1], 1)
def xy(t, v): return (L + (W - L - R) * t / span, H - B - (H - B - T) * v / top)
for k in range(0, 6):
    v = top * k / 5; y = xy(0, v)[1]
    d.line([(L, y), (W - R, y)], fill=(225, 225, 225)); d.text((10, y - 9), f'{v:,.0f} MB', fill=(90, 90, 90), font=fs)
for k in range(0, 11):
    t = span * k / 10; x = xy(t, 0)[0]
    d.text((x - 14, H - B + 8), f'{int(t//60)}:{int(t%60):02d}', fill=(90, 90, 90), font=fs)
for series, colour, name in [(fp, (40, 90, 200), 'footprint (what Activity Monitor shows)'), (rs, (220, 120, 30), 'resident')]:
    d.line([xy(t, v) for t, v in zip(at, series)], fill=colour, width=3)
d.text((L, 18), f"Memory while the {r.get('minutes')} minute reference edit plays and is scrubbed: peak footprint {m['peakFootprintMB']:,.0f} MB, resident {m['peakResidentMB']:,.0f} MB", fill=(20, 20, 20), font=f)
d.text((L, H - 30), 'blue: footprint   orange: resident   (one reading a second, taken off the main thread)', fill=(90, 90, 90), font=fs)
img.save(out); print(out, len(fp), 'readings')
