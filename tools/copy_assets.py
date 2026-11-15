#!/usr/bin/env python3
"""Copy Flatland's assets out of the original FlatlandView Xcode asset catalog into this Godot project.

A one-off migration tool, run by hand (`python3 tools/copy_assets.py`); it takes no arguments and reads the paths
below. Maps and night masks are copied flat (loaded at run time by MapCatalog, and kept out of Godot's importer
with a .gdignore file). Icons, textures, suns and sounds are copied into res:// folders so Godot imports them.
It overwrites files that already exist in the destination.
"""
import os, re, shutil, sys, json
# The original FlatlandView (Swift) project: where the assets come from.
SRC = os.path.expanduser("~/Documents/GitHub/FlatlandView")
# Its Xcode asset catalog, which holds the images as folders named "<name>.imageset".
XC = SRC + "/FlatlandView/Assets.xcassets"
# This Godot project: where the assets go.
DST = os.path.expanduser("~/Developer/FlatlandU")
def imagesets(root):
    """Finds the images in an asset catalog folder.

    root: the folder to search (searched recursively).
    Returns: a dict of image-set name (the ".imageset" folder's name without the suffix) to the path of the first
    picture file in it (png, jpg, jpeg, gif, tiff or heic)."""
    out = {}
    for d, dirs, files in os.walk(root):
        if d.endswith(".imageset"):
            for f in files:
                if f.lower().endswith((".png", ".jpg", ".jpeg", ".gif", ".tiff", ".heic")) :
                    out.setdefault(os.path.basename(d)[:-9], os.path.join(d, f)); break
    return out
# All the map images in the catalog, by name.
sets = imagesets(XC + "/Maps")
# The names of the maps that MapList.swift actually uses (so unused pictures are not copied); this one is the
# sea pattern of a map, which the list does not name in quotes.
used = {"JapanesePattern4"}
for line in open(SRC + "/FlatlandView/Maps/Logical/MapList.swift"):
    if line.strip().startswith("//"): continue
    used.update(re.findall(r'"([A-Za-z0-9_]+)"', line))
os.makedirs(DST + "/Maps", exist_ok=True)
# How many map pictures were copied (the second value is unused).
copied, missing = 0, []
for n in sorted(used):
    if n in sets:
        shutil.copy2(sets[n], f"{DST}/Maps/{n}" + os.path.splitext(sets[n])[1].lower()); copied += 1
open(DST + "/Maps/.gdignore", "w").close()
print("maps copied", copied)
# Night masks: the old pre-rendered day/night pictures (the app now draws the night side with night.gdshader).
nm = DST + "/NightMasks"
for kind in ("North", "South", "Flat"):
    os.makedirs(f"{nm}/{kind}", exist_ok=True)
    for n, p in imagesets(XC + "/NightMasks/" + kind).items():
        shutil.copy2(p, f"{nm}/{kind}/{n}.png")
open(nm + "/.gdignore", "w").close()
# Small assets that Godot imports: (catalog folder, destination folder under Assets).
for sub, dst in (("Button Icons", "Icons"), ("Suns", "Suns"), ("Textures", "Textures"),
                 ("LocationTypeIcons", "LocationIcons"), ("PreferencePanelIcons", "PrefIcons"), ("SVG", "SVG")):
    os.makedirs(f"{DST}/Assets/{dst}", exist_ok=True)
    for n, p in imagesets(f"{XC}/{sub}").items():
        shutil.copy2(p, f"{DST}/Assets/{dst}/{n}{os.path.splitext(p)[1].lower()}")
os.makedirs(DST + "/Assets/Sounds", exist_ok=True)
for f in os.listdir(SRC):
    if f.endswith(".mp3"): shutil.copy2(f"{SRC}/{f}", f"{DST}/Assets/Sounds/{f}")
os.makedirs(DST + "/Assets/Docs", exist_ok=True)
for f in ("AboutFlatland.gif", "StaticFlatlandOverview.png"):
    shutil.copy2(f"{SRC}/Images/{f}", f"{DST}/Assets/Docs/{f}")
print("done")
