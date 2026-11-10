#!/usr/bin/env python3
"""Copy Flatland's assets out of the Xcode asset catalog into the Godot project.
Maps, night masks: copied flat (loaded at runtime, kept out of the importer via .gdignore).
Icons/textures/suns: copied into res:// folders so Godot imports them."""
import os, re, shutil, sys, json
SRC = os.path.expanduser("~/Documents/GitHub/FlatlandView")
XC = SRC + "/FlatlandView/Assets.xcassets"
DST = os.path.expanduser("~/Developer/FlatlandU")
def imagesets(root):
    out = {}
    for d, dirs, files in os.walk(root):
        if d.endswith(".imageset"):
            for f in files:
                if f.lower().endswith((".png", ".jpg", ".jpeg", ".gif", ".tiff", ".heic")) :
                    out.setdefault(os.path.basename(d)[:-9], os.path.join(d, f)); break
    return out
sets = imagesets(XC + "/Maps")
used = {"JapanesePattern4"}
for line in open(SRC + "/FlatlandView/Maps/Logical/MapList.swift"):
    if line.strip().startswith("//"): continue
    used.update(re.findall(r'"([A-Za-z0-9_]+)"', line))
os.makedirs(DST + "/Maps", exist_ok=True)
copied, missing = 0, []
for n in sorted(used):
    if n in sets:
        shutil.copy2(sets[n], f"{DST}/Maps/{n}" + os.path.splitext(sets[n])[1].lower()); copied += 1
open(DST + "/Maps/.gdignore", "w").close()
print("maps copied", copied)
# night masks
nm = DST + "/NightMasks"
for kind in ("North", "South", "Flat"):
    os.makedirs(f"{nm}/{kind}", exist_ok=True)
    for n, p in imagesets(XC + "/NightMasks/" + kind).items():
        shutil.copy2(p, f"{nm}/{kind}/{n}.png")
open(nm + "/.gdignore", "w").close()
# imported small assets
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
