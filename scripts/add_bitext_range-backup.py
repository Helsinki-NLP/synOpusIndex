#!/usr/bin/env python3
#
# add the range over rowids for each bitext into a new table


import sys
import sqlite3


if len(sys.argv) != 2:
    print("USAGE: add_bitext_range.py xx-yy.db")
    exit()

linksDB = sys.argv[1]

linksDBcon = sqlite3.connect(linksDB, timeout=7200)
bitextDBcur = linksDBcon.cursor()
linksDBcur = linksDBcon.cursor()


linksDBcur.execute("CREATE TABLE IF NOT EXISTS bitext_range (bitextID INTEGER NOT NULL PRIMARY KEY,start INTEGER,end INTEGER)")

for bitext in bitextDBcur.execute(f"SELECT DISTINCT bitextID FROM links"):
    bitextID = bitext[0]
    # print(f"now processing {bitextID}")
    for rowids in linksDBcur.execute(f"SELECT MIN(rowid),MAX(rowid) FROM links WHERE bitextID={bitextID}"):
        start = rowids[0]
        end = rowids[1]
        # print(f"INSERT OR IGNORE INTO bitext_range VALUES ({bitextID},{start},{end})")
        linksDBcur.execute(f"INSERT OR IGNORE INTO bitext_range VALUES ({bitextID},{start},{end})")
        linksDBcur.execute(f"UPDATE bitext_range SET start={start},end={end} WHERE bitextID={bitextID}")

linksDBcon.commit()
