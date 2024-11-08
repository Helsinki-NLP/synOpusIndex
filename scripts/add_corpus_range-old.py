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
bitextDBcur = linksDBcon.cursor()
linksDBcur = linksDBcon.cursor()


linksDBcur.execute("CREATE TABLE IF NOT EXISTS corpus_range (corpus TEXT, version TEXT,start INTEGER,end INTEGER)")
linksDBcur.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_corpus ON corpus_range ( corpus, version )")

for bitext in bitextDBcur.execute(f"SELECT DISTINCT corpus,version FROM bitexts"):
    corpus = bitext[0]
    version = bitext[1]
    print(f"Now processing {corpus}/{version}")

    for rowids in linksDBcur.execute(f"SELECT MIN(rowid),MAX(rowid) FROM links WHERE bitextID IN (SELECT rowid FROM bitexts WHERE corpus='{corpus}' AND version='{version}')"):
        start = rowids[0]
        end = rowids[1]
        if (start and end):
            linksDBcur.execute(f"INSERT OR IGNORE INTO corpus_range VALUES ('{corpus}','{version}',{start},{end})")
            linksDBcur.execute(f"UPDATE corpus_range SET start={start},end={end} WHERE corpus='{corpus}' AND version='{version}'")

linksDBcon.commit()
