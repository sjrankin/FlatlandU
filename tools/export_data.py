#!/usr/bin/env python3
"""Export Flatland's SQLite data (cities, heritage sites, points of interest) to JSON for the Godot port.

Usage: python3 tools/export_data.py <MappableS.db> <output folder>
Writes cities.json, additional_cities.json, heritage_sites.json and poi.json (compact JSON arrays of objects, one
per row, keyed by the column names) into the output folder, normally this project's data/ folder. CityDB loads them.
"""
import json, sqlite3, sys
# The SQLite database exported from the original FlatlandView app.
src = sys.argv[1]
# The folder to write the JSON files into.
out = sys.argv[2]
# The open database; rows are read as mappings so they can be turned into dicts.
db = sqlite3.connect(src); db.row_factory = sqlite3.Row
def rows(q):
    """Runs a query and returns its rows as a list of dicts (column name to value)."""
    return [dict(r) for r in db.execute(q)]
json.dump(rows("select Name,Country,IsCapital,Population,MetropolitanPopulation,Latitude,Longitude,Continent,CityColor,IsWorldCity from Cities"), open(out+"/cities.json","w"), separators=(",",":"))
json.dump(rows("select Name,Country,IsCapital,Population,MetropolitanPopulation,Latitude,Longitude,Continent,CityColor,IsWorldCity from AdditionalCities"), open(out+"/additional_cities.json","w"), separators=(",",":"))
json.dump(rows("select Name,Latitude,Longitude,Category,CategoryShort,Countries,DateInscribed from WorldHeritageSites"), open(out+"/heritage_sites.json","w"), separators=(",",":"))
json.dump(rows("select Name,Latitude,Longitude,Description,POIType,Color from POI"), open(out+"/poi.json","w"), separators=(",",":"))
