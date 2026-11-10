#!/usr/bin/env python3
"""Parse Flatland's MapList.swift + MapTypes enum into data/maps.json."""
import re, os, json
SRC = os.path.expanduser("~/Documents/GitHub/FlatlandView/FlatlandView")
enum = {}
txt = open(SRC + "/Maps/Logical/MapList.swift").read()
body = re.search(r"enum MapTypes: String, CaseIterable\s*\{(.*?)\n\}", txt, re.S).group(1)
for m in re.finditer(r'^\s*case (\w+) = "([^"]*)"', body, re.M): enum[m.group(1)] = m.group(2)
maps = []
files = set(os.listdir(os.path.expanduser("~/Developer/FlatlandU/Maps")))
def find(n):
    for e in (".png", ".jpg", ".jpeg"):
        if n + e in files: return n + e
    return ""
for line in open(SRC + "/Maps/Logical/MapList.swift"):
    if line.strip().startswith("//"): continue
    m = re.search(r'MapItem\(\.(\w+), false, "([^"]+)", "([^"]+)", "([^"]+)"', line)
    if not m: continue
    lm = re.search(r"LightMultiplier: ([\d.]+)", line)
    # LightMultiplier may be on the next line; handled below
    maps.append(dict(id=m.group(1), name=enum.get(m.group(1), m.group(1)), globe=find(m.group(2)),
                     north=find(m.group(3)), south=find(m.group(4)), light=float(lm.group(1)) if lm else 1.0, sea={"Standard":"SeaMask2.png","TectonicOverlay":"DitheredMap.png","StylizedSea1":"JapanesePattern4.png"}.get(m.group(1),"")))
lines = open(SRC + "/Maps/Logical/MapList.swift").read().split("\n")
for i, l in enumerate(lines):
    if l.strip().startswith("//"): continue
    m = re.search(r'MapItem\(\.(\w+),', l)
    if m and "LightMultiplier" not in l and i + 1 < len(lines) and "LightMultiplier" in lines[i + 1] and not lines[i+1].strip().startswith("MapItem"):
        v = float(re.search(r"LightMultiplier: ([\d.]+)", lines[i + 1]).group(1))
        for mm in maps:
            if mm["id"] == m.group(1): mm["light"] = v
json.dump(maps, open(os.path.expanduser("~/Developer/FlatlandU/data/maps.json"), "w"), indent=1)
print(len(maps), "maps;", sum(1 for m in maps if not m["globe"]), "missing globe;", sum(1 for m in maps if not m["north"]), "missing north")
