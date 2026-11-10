#!/usr/bin/env python3
"""Export Flatland's SQLite data (cities, heritage sites, POI) to JSON for the Godot port."""
import json, sqlite3, sys
src = sys.argv[1]; out = sys.argv[2]
db = sqlite3.connect(src); db.row_factory = sqlite3.Row
def rows(q): return [dict(r) for r in db.execute(q)]
json.dump(rows("select Name,Country,IsCapital,Population,MetropolitanPopulation,Latitude,Longitude,Continent,CityColor,IsWorldCity from Cities"), open(out+"/cities.json","w"), separators=(",",":"))
json.dump(rows("select Name,Country,IsCapital,Population,MetropolitanPopulation,Latitude,Longitude,Continent,CityColor,IsWorldCity from AdditionalCities"), open(out+"/additional_cities.json","w"), separators=(",",":"))
json.dump(rows("select Name,Latitude,Longitude,Category,CategoryShort,Countries,DateInscribed from WorldHeritageSites"), open(out+"/heritage_sites.json","w"), separators=(",",":"))
json.dump(rows("select Name,Latitude,Longitude,Description,POIType,Color from POI"), open(out+"/poi.json","w"), separators=(",",":"))
