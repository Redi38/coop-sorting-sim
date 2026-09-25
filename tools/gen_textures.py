"""Generates the tileable placeholder-art textures in assets/textures/.

Run:  python3 tools/gen_textures.py
Every texture tiles seamlessly (noise is built in frequency space, which is
periodic by construction). Each albedo gets a matching normal map derived
from its height field. Replace any PNG with hand-painted art of the same
name and the materials pick it up automatically.
"""
import numpy as np
from PIL import Image
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
N = 512
rng = np.random.default_rng(38)


def noise(shape, scale, rng=rng):
    """Tileable fractal-ish noise in [0,1]. Larger `scale` = bigger blobs."""
    h, w = shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    f = np.sqrt((fx * w / scale) ** 2 + (fy * h / scale) ** 2)
    spec = (rng.normal(size=shape) + 1j * rng.normal(size=shape)) / (1 + f ** 2.2)
    spec[0, 0] = 0
    n = np.real(np.fft.ifft2(spec))
    return (n - n.min()) / (n.max() - n.min())


def aniso_noise(shape, sx, sy, rng=rng):
    """Tileable noise stretched along x (for wood grain)."""
    h, w = shape
    fy = np.fft.fftfreq(h)[:, None] * h
    fx = np.fft.fftfreq(w)[None, :] * w
    f = np.sqrt((fx / sx) ** 2 + (fy / sy) ** 2)
    spec = (rng.normal(size=shape) + 1j * rng.normal(size=shape)) / (1 + f ** 2.4)
    spec[0, 0] = 0
    n = np.real(np.fft.ifft2(spec))
    return (n - n.min()) / (n.max() - n.min())


def lerp_colors(t, stops):
    """Map t in [0,1] through a list of (pos, (r,g,b)) stops."""
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,))
    pos = [p for p, _ in stops]
    cols = np.array([c for _, c in stops], dtype=float)
    for ch in range(3):
        out[..., ch] = np.interp(t, pos, cols[:, ch])
    return out


def normal_from_height(hgt, strength):
    dx = (np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)) * strength
    dy = (np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)) * strength
    nz = np.ones_like(hgt)
    n = np.stack([-dx, dy, nz], -1)   # OpenGL-style (Godot's default)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def save(name, rgb, hgt=None, strength=4.0):
    Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).save(os.path.join(OUT, f"{name}_albedo.png"))
    if hgt is not None:
        Image.fromarray(normal_from_height(hgt, strength)).save(os.path.join(OUT, f"{name}_normal.png"))
    print("wrote", name)


def wood(name, plank_rows, stops, seam_dark=0.55, grain_amt=0.35, stagger=True, strength=5.0):
    """Planks running along x: `plank_rows` planks per tile, staggered end joints."""
    grain = aniso_noise((N, N), 3, 40)
    fine = aniso_noise((N, N), 1.5, 90)
    blotch = noise((N, N), 6)
    y = np.arange(N)[:, None].repeat(N, 1)
    x = np.arange(N)[None, :].repeat(N, 0)
    ph = N // plank_rows
    row = y // ph
    # per-plank tone shift so boards don't look identical
    tone = rng.uniform(-0.12, 0.12, plank_rows)[row]
    t = 0.45 + grain_amt * (grain - 0.5) + 0.25 * (fine - 0.5) + 0.15 * (blotch - 0.5) + tone
    rgb = lerp_colors(t, stops)
    hgt = 0.6 * grain + 0.4 * fine
    # long seams between planks
    seam = (y % ph) < 2
    # end joints, staggered per row (tile-safe: offsets are multiples of N/4)
    if stagger:
        # random per-row offset (multiples of 16 px keep the tile seamless,
        # since the joint period N/2 divides the tile width)
        offsets = rng.integers(0, N // 32, plank_rows) * 16
        seam |= ((x + offsets[row]) % (N // 2)) < 2
    rgb[seam] *= seam_dark
    hgt = np.where(seam, 0.0, hgt)
    # soft darkening near seams (ambient-occlusion feel)
    edge = np.minimum(y % ph, ph - (y % ph)) / ph
    rgb *= (0.88 + 0.12 * np.clip(edge * 6, 0, 1))[..., None]
    save(name, rgb, hgt, strength)


os.makedirs(OUT, exist_ok=True)

# Floor: wide honey-oak boards
wood("floor_planks", 8, [(0.0, (70, 46, 30)), (0.45, (116, 80, 52)), (0.8, (142, 104, 70)), (1.0, (160, 122, 84))],
     seam_dark=0.72)

# Furniture: finer, darker walnut, no end joints (shelves are single boards)
wood("shelf_wood", 4, [(0.0, (58, 36, 22)), (0.5, (104, 68, 40)), (1.0, (148, 100, 60))],
     seam_dark=0.8, grain_amt=0.45, stagger=False, strength=3.0)

# Walls: warm dusty plaster with soft mottling and faint cracks
m1 = noise((N, N), 5); m2 = noise((N, N), 25); m3 = noise((N, N), 90)
t = 0.5 + 0.35 * (m1 - 0.5) + 0.25 * (m2 - 0.5) + 0.12 * (m3 - 0.5)
rgb = lerp_colors(t, [(0.0, (168, 142, 120)), (0.5, (206, 182, 156)), (1.0, (228, 210, 186))])
crack = np.abs(noise((N, N), 18) - 0.5) < 0.006
rgb[crack] *= 0.82
save("plaster_wall", rgb, 0.7 * m2 + 0.3 * m3 - crack * 0.3, 2.5)

# Parchment: signs and labels
p1 = noise((N, N), 4); p2 = noise((N, N), 30)
t = 0.55 + 0.3 * (p1 - 0.5) + 0.2 * (p2 - 0.5)
rgb = lerp_colors(t, [(0.0, (196, 168, 122)), (0.6, (234, 218, 184)), (1.0, (246, 236, 212))])
save("parchment", rgb, p2, 1.0)

# Rug: woven cozy runner (deep teal with warm border stripes)
y = np.arange(N)[:, None].repeat(N, 1)
x = np.arange(N)[None, :].repeat(N, 0)
weave = (np.sin(x * np.pi / 2) * np.sin(y * np.pi / 2)) * 0.5 + 0.5
fuzz = noise((N, N), 2)
base = lerp_colors(0.5 + 0.2 * (fuzz - 0.5), [(0, (28, 70, 74)), (1, (52, 104, 104))])
stripe = ((y // 16) % 8 == 0) | ((y // 16) % 8 == 1)
diamond = (np.abs(((x % 64) - 32)) + np.abs(((y % 64) - 32))) < 10
base[stripe] = lerp_colors(0.5 + 0.2 * (fuzz[stripe] - 0.5), [(0, (122, 62, 40)), (1, (150, 88, 54))])
base[diamond & ~stripe] = lerp_colors(0.5 + 0.2 * (fuzz[diamond & ~stripe] - 0.5), [(0, (200, 160, 90)), (1, (232, 196, 120))])
base *= (0.9 + 0.1 * weave)[..., None]
save("rug", base, weave * 0.5 + fuzz * 0.5, 1.5)

# Main-menu backdrop: dark warm vignette with soft candle-light bokeh.
W, H = 1920, 1080
yy, xx = np.mgrid[0:H, 0:W]
r = np.sqrt(((xx - W * 0.5) / W) ** 2 + ((yy - H * 0.55) / H) ** 2)
glow = np.clip(1.0 - r * 1.6, 0, 1) ** 1.6
img = np.zeros((H, W, 3))
img += np.array([22, 16, 12]) + glow[..., None] * np.array([70, 44, 24])
for _ in range(38):
    cx, cy = rng.uniform(0, W), rng.uniform(0, H)
    rad = rng.uniform(18, 90)
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / rad
    a = np.clip(1 - d, 0, 1) ** 0.7 * rng.uniform(0.05, 0.22)
    img += a[..., None] * np.array([255, 190, 110])
img += rng.normal(0, 2.0, img.shape)  # film grain, avoids banding
Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(os.path.join(OUT, "menu_backdrop.png"))
print("wrote menu_backdrop")
