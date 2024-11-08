#!/usr/bin/env python3
#
# add the range over rowids for each corpus into a new table

import sys
import sqlite3


if len(sys.argv) != 2:
    print("USAGE: add_bitext_range.py xx-yy.db")
    exit()

linksDB = sys.argv[1]

linksDBcon = sqlite3.connect(linksDB, timeout=7200)
linksDBcur = linksDBcon.cursor()


def overlap(x1,x2,y1,y2):
    if x2 < y1 or x1 > y2:
        return False
    return True


ranges = {}
for bitext in linksDBcur.execute(f"SELECT corpus,version,srclang,trglang,start,end FROM corpus_range"):
    ranges[f"{bitext[0]},{bitext[1]},{bitext[2]},{bitext[3]}"] = tuple([bitext[4],bitext[5]]);

for x in ranges:
    for y in ranges:
        if x == y:
            continue
        if overlap(ranges[x][0],ranges[x][1],ranges[y][0],ranges[y][1]):
            print(f"{x} and {y} overlap! ({ranges[x][0]},{ranges[x][1]}) and ({ranges[y][0]},{ranges[y][1]})")
            
