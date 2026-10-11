#!/usr/bin/env python3
"""Render the checked-in SVG mark into iOS light, dark, and tinted app icons.

Requires Pillow and CairoSVG (plus the native Cairo library). Run from any folder.
"""
from pathlib import Path
import io
import xml.etree.ElementTree as ET

import cairosvg
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "design/app-icon/heart-arrows.svg"
DESTINATION = ROOT / "HealthSync/Assets.xcassets/AppIcon.appiconset"
SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)


def render(appearance):
    root = ET.fromstring(SOURCE.read_text())
    paths = root.findall(f".//{{{SVG}}}path")
    if len(paths) != 2:
        raise ValueError("The icon must contain the two sync-arrow paths")

    if appearance == "tinted":
        for path in paths:
            path.set("fill", "#FFFFFF")
    else:
        definitions = ET.Element(f"{{{SVG}}}defs")
        for index, colors in enumerate((("#FF5F5C", "#FA394D"),
                                        ("#FC829A", "#F02D61"))):
            gradient = ET.SubElement(definitions, f"{{{SVG}}}linearGradient", {
                "id": f"arrow-{index}", "x1": "0%", "y1": "0%",
                "x2": "100%" if index == 0 else "0%", "y2": "100%",
            })
            for offset, color in zip(("0%", "100%"), colors):
                ET.SubElement(gradient, f"{{{SVG}}}stop", {
                    "offset": offset, "stop-color": color,
                })
            paths[index].set("fill", f"url(#arrow-{index})")
        root.insert(0, definitions)

    if appearance != "dark":
        background = ET.Element(f"{{{SVG}}}rect", {
            "width": "1024", "height": "1024",
            "fill": "#000000" if appearance == "tinted" else "#FFFFFF",
        })
        root.insert(1 if appearance == "light" else 0, background)

    png = cairosvg.svg2png(bytestring=ET.tostring(root),
                          output_width=2048, output_height=2048)
    image = Image.open(io.BytesIO(png)).convert("RGBA").resize(
        (1024, 1024), Image.Resampling.LANCZOS)
    # The default App Store icon must have no alpha channel. The dark variant
    # deliberately keeps transparency for the system-provided background.
    if appearance != "dark":
        image = image.convert("RGB")
    name = {"light": "AppIcon.png", "dark": "AppIcon-Dark.png",
            "tinted": "AppIcon-Tinted.png"}[appearance]
    image.save(DESTINATION / name, optimize=True)
    print(f"Rendered {name}: {image.size}, {image.mode}")


if __name__ == "__main__":
    for appearance in ("light", "dark", "tinted"):
        render(appearance)
