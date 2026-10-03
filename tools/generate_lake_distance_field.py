"""Bake shoreline distance data, without changing the terrain artwork.

Red stores signed distance in source pixels (-64..64). Green limits lake
movement to the lake basin, leaving the off-screen river routes unchanged.
"""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
pixels = np.asarray(Image.open(ROOT / "assets/art/poyang-terrain-base.png").convert("RGB"))
water = (pixels[:, :, 2] > pixels[:, :, 1]) & (pixels[:, :, 1] > pixels[:, :, 0])
def pixel_distance(mask):
    """Eight-neighbor pixel distance, clipped at the shader's 64px range."""
    reached = mask.copy()
    result = np.full(mask.shape, 64, dtype=np.float32)
    result[mask] = 0
    for step in range(1, 65):
        padded = np.pad(reached, 1, constant_values=False)
        expanded = np.logical_or.reduce([
            padded[dy:dy + mask.shape[0], dx:dx + mask.shape[1]]
            for dy in range(3) for dx in range(3)
        ])
        result[expanded & ~reached] = step
        reached = expanded
    return result

distance = pixel_distance(water) - pixel_distance(~water)
y, x = np.mgrid[:water.shape[0], :water.shape[1]]
u, v = x / water.shape[1], y / water.shape[0]
influence = np.minimum.reduce([
    np.clip((v - .18) / .05, 0, 1), np.clip((.86 - v) / .05, 0, 1),
    np.clip((u - .24) / .04, 0, 1), np.clip((.83 - u) / .04, 0, 1),
])
data = np.zeros((*water.shape, 3), dtype=np.uint8)
data[:, :, 0] = np.rint(np.clip(.5 + distance / 128, 0, 1) * 255).astype(np.uint8)
data[:, :, 1] = np.rint(influence * 255).astype(np.uint8)
Image.fromarray(data).save(ROOT / "assets/art/lake-shore-distance.png")
print("Baked lake shoreline distance field")
