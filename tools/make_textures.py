"""Generates the gritty, low-res (PS2-era) textures in textures/.

Every texture tiles seamlessly: the noise is made periodic with FFTs.
Run from the project folder:  python3 tools/make_textures.py
Needs numpy and Pillow.
"""
import os

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "textures")
rng = np.random.default_rng(1993)


def noise(size, scale, seed=None):
    """Tileable smooth noise in [0, 1]. Larger `scale` = bigger blobs."""
    r = np.random.default_rng(seed) if seed is not None else rng
    white = r.standard_normal((size, size))
    f = np.fft.fftfreq(size)
    fx, fy = np.meshgrid(f, f)
    k = np.sqrt(fx * fx + fy * fy)
    falloff = np.exp(-((k * scale) ** 2))
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * falloff))
    out -= out.min()
    return out / max(out.max(), 1e-9)


def fbm(size, base, octaves=5):
    total = np.zeros((size, size))
    amp = 1.0
    norm = 0.0
    scale = base
    for _ in range(octaves):
        total += noise(size, scale) * amp
        norm += amp
        amp *= 0.5
        scale /= 2.0
    return total / norm


def save(name, rgb):
    rgb = np.clip(rgb, 0, 1)
    Image.fromarray((rgb * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, name + ".png"))
    print("wrote", name)


def tint(gray, dark, light):
    dark = np.array(dark, float) / 255
    light = np.array(light, float) / 255
    return dark + (light - dark) * gray[..., None]


def felt(size=256):
    fibers = noise(size, 0.6) * 0.5 + rng.random((size, size)) * 0.5
    mottle = fbm(size, 40)
    g = 0.35 + 0.35 * mottle + 0.25 * fibers
    # worn patches and old drink rings
    wear = np.clip(fbm(size, 70) - 0.55, 0, 1) * 1.6
    g += wear * 0.25
    img = tint(g, (10, 32, 20), (46, 92, 58))
    stains = np.clip(fbm(size, 25) - 0.62, 0, 1) * 2.5
    img *= (1 - stains[..., None] * 0.55)
    # a couple of cigarette burns
    yy, xx = np.mgrid[0:size, 0:size]
    for _ in range(3):
        cx, cy, r = rng.integers(0, size), rng.integers(0, size), rng.integers(3, 7)
        d = np.sqrt(((xx - cx + size / 2) % size - size / 2) ** 2 + ((yy - cy + size / 2) % size - size / 2) ** 2)
        burn = np.clip(1 - d / r, 0, 1)
        img *= (1 - burn[..., None] * 0.8)
    save("felt", img)


def wood(size=256, dark=(28, 16, 9), light=(92, 56, 30), name="wood"):
    yy, xx = np.mgrid[0:size, 0:size] / size
    # long, gently wavy grain running along x
    warp = fbm(size, 120) * 1.4 + noise(size, 6.0) * 0.25
    grain = 0.5 + 0.5 * np.sin((yy * 14 + warp) * np.pi * 2)
    fine = noise(size, 1.5)
    g = 0.55 * grain + 0.3 * fine + 0.15 * fbm(size, 30)
    img = tint(g, dark, light)
    # scratches and grime
    grime = np.clip(fbm(size, 20) - 0.5, 0, 1) * 1.4
    img *= (1 - grime[..., None] * 0.45)
    for _ in range(25):
        y = rng.integers(0, size)
        x0 = rng.integers(0, size)
        length = rng.integers(10, 60)
        for i in range(length):
            img[(y + i // 6) % size, (x0 + i) % size] *= 1.25
    save(name, img)


def concrete(size=256):
    g = 0.45 * fbm(size, 60) + 0.35 * fbm(size, 8) + 0.2 * rng.random((size, size))
    img = tint(g, (38, 37, 35), (98, 94, 88))
    stains = np.clip(fbm(size, 45) - 0.58, 0, 1) * 2.2
    img *= (1 - stains[..., None] * 0.6)
    save("concrete", img)


def plaster(size=256):
    g = 0.5 * fbm(size, 50) + 0.3 * fbm(size, 10) + 0.2 * rng.random((size, size))
    img = tint(g, (46, 48, 36), (110, 108, 82))
    # water stains running down
    yy = np.mgrid[0:size, 0:size][0] / size
    streaks = noise(size, 3.0)
    streak_mask = np.clip(streaks - 0.55, 0, 1) * 2.0 * (0.4 + 0.6 * yy)
    img *= (1 - streak_mask[..., None] * 0.5)
    damp = np.clip(fbm(size, 80) - 0.6, 0, 1) * 2.0
    img = img * (1 - damp[..., None] * 0.35) + damp[..., None] * np.array([0.02, 0.03, 0.0])
    save("plaster", img)


def metal(size=128):
    brushed = noise(size, 0.4)
    g = 0.5 + 0.3 * fbm(size, 20) + 0.2 * brushed
    img = tint(g, (24, 25, 27), (82, 84, 88))
    rust = np.clip(fbm(size, 18) - 0.55, 0, 1) * 2.4
    rust_col = tint(noise(size, 2.0), (60, 24, 10), (140, 70, 30))
    img = img * (1 - rust[..., None]) + rust_col * rust[..., None]
    save("metal", img)


def card_back(size=128):
    """A worn red card back with a diamond lattice."""
    yy, xx = np.mgrid[0:size, 0:size]
    lattice = ((xx + yy) // 8 + (xx - yy) // 8) % 2
    g = 0.6 + 0.25 * lattice + 0.15 * rng.random((size, size))
    img = tint(g, (55, 10, 8), (120, 26, 20))
    wear = np.clip(fbm(size, 30) - 0.55, 0, 1) * 1.5
    img = img * (1 - wear[..., None] * 0.5) + wear[..., None] * np.array([0.12, 0.1, 0.08])
    save("card_back", img)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    felt()
    wood()
    wood(128, (40, 16, 8), (120, 58, 26), "gun_wood")
    concrete()
    plaster()
    metal()
    card_back()
