#!/usr/bin/env python3
"""Extract the N brightest stars from the HYG database CSV into data/bright_stars.json.

Usage: tools/extract_bright_stars.py [hyg csv] [count]
Output rows: [right ascension (degrees), declination (degrees), apparent magnitude, B-V colour index,
proper name (or ""), spectral type (or "")].
HYG (astronexus/HYG-Database) is licensed CC BY-SA 4.0.
"""
import csv, json, sys

# The HYG database CSV to read (the first argument, or a default path).
src = sys.argv[1] if len(sys.argv) > 1 else "ExternalData/hygdata_v41.csv"
# How many stars to keep (the second argument, or 2000).
count = int(sys.argv[2]) if len(sys.argv) > 2 else 2000

# One (magnitude, right ascension, declination, color index, name, spectral type) tuple per usable star; sorted
# brightest first (lowest magnitude), then cut to [count].
rows = []
with open(src, newline="", encoding="utf-8") as f:
    for r in csv.DictReader(f):
        if r["id"] == "0" or r["proper"] == "Sol":   # skip the Sun
            continue
        try:
            mag = float(r["mag"])
            ra = float(r["ra"]) * 15.0
            dec = float(r["dec"])
        except ValueError:
            continue
        try:
            ci = float(r["ci"])
        except ValueError:
            ci = 0.6
        rows.append((mag, ra, dec, ci, r["proper"].strip(), r["spect"].strip()))

rows.sort()
rows = rows[:count]
# The output rows, as described in the module docstring (numbers rounded to keep the file small).
out = [[round(ra, 4), round(dec, 4), round(mag, 2), round(ci, 2), name, spect] for mag, ra, dec, ci, name, spect in rows]
with open("data/bright_stars.json", "w") as f:
    json.dump(out, f, separators=(",", ":"))
print(f"{len(out)} stars, magnitude {rows[0][0]} to {rows[-1][0]}")
