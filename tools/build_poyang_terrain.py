"""Render the checked geographic source as a four-color, north-up pixel map.

Requires Pillow. Source coordinates are WGS84; both axes use the same local
distance scale. Shore bands and river widths are game art, not bathymetry.
"""
from pathlib import Path
import json
import math
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/geography/poyang-hydrography.geojson"
OUTPUT = ROOT / "assets/art/poyang-terrain-base.png"
LOGICAL_SIZE = 512
OUTPUT_SIZE = 1024
PALETTE = {
    "deep_water": "#176783",
    "shallow_water": "#63afcb",
    "shoreline": "#d8c68d",
    "land": "#829666",
}


def render():
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    view = source["map_view"]
    west, south, east, north = view["bounds_wgs84"]
    latitude_scale = math.cos(math.radians((south + north) / 2))
    assert abs((east - west) * latitude_scale - (north - south)) < 1e-6

    def point(coordinate):
        lon, lat = coordinate
        return ((lon - west) / (east - west) * LOGICAL_SIZE,
                (north - lat) / (north - south) * LOGICAL_SIZE)

    lake_mask = Image.new("L", (LOGICAL_SIZE, LOGICAL_SIZE), 0)
    lake_draw = ImageDraw.Draw(lake_mask)
    rivers = Image.new("L", lake_mask.size, 0)
    river_draw = ImageDraw.Draw(rivers)
    for feature in source["features"]:
        geometry = feature["geometry"]
        if geometry["type"] == "MultiPolygon":
            for polygon in geometry["coordinates"]:
                lake_draw.polygon([point(c) for c in polygon[0]], fill=255)
                for hole in polygon[1:]:
                    lake_draw.polygon([point(c) for c in hole], fill=0)
        elif geometry["type"] == "LineString":
            points = [point(c) for c in geometry["coordinates"]]
            if len(points) > 1:
                width = 6 if feature["properties"]["river"] == "Yangtze" else 3
                river_draw.line(points, fill=255, width=width, joint="curve")

    # Union all mapped water before adding bands: confluences have no land seams.
    from PIL import ImageChops
    water = ImageChops.lighter(lake_mask, rivers)
    shoreline = water.filter(ImageFilter.MaxFilter(5))
    deep = water.filter(ImageFilter.MinFilter(7))
    result = Image.new("RGB", water.size, PALETTE["land"])
    result.paste(PALETTE["shoreline"], mask=shoreline)
    result.paste(PALETTE["shallow_water"], mask=water)
    result.paste(PALETTE["deep_water"], mask=deep)
    # Keep narrow tributaries readable without changing their centerline positions.
    river_core = rivers.filter(ImageFilter.MinFilter(3))
    result.paste(PALETTE["deep_water"], mask=river_core)
    result = result.resize((OUTPUT_SIZE, OUTPUT_SIZE), Image.Resampling.NEAREST)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    result.save(OUTPUT)
    colors = result.getcolors(OUTPUT_SIZE * OUTPUT_SIZE)
    assert len(colors) == 4, colors
    assert result.size == (1024, 1024)
    water_count = sum(count for count, color in colors
                      if color in [(23, 103, 131), (99, 175, 203)])
    print(f"Saved {OUTPUT}; 1024x1024, four colors; water {water_count / 1048576:.1%}")


if __name__ == "__main__":
    render()
