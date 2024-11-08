#!/usr/bin/env python3
#
# add the range over rowids for each corpus into a new table


import argparse
import sys
import sqlite3

parser = argparse.ArgumentParser(prog='add_corpus_range.py',
                                 description='add the range of rowids over corpora in link databases')
parser.add_argument("-d", "--database", type=str, required=True, help="name of the link database file")
parser.add_argument("-c", "--corpus", type=str, help="name of the OPUS corpus")
parser.add_argument("-s", "--srclang", type=str, help="source language ID (OPUS)")
parser.add_argument("-t", "--trglang", type=str, help="target language ID (OPUS)")
parser.add_argument("-v", "--version", type=str, help="release of the corpus")

args = parser.parse_args()


# if len(sys.argv) != 2:
#     print("USAGE: add_corpus_range.py xx-yy.db")
#     exit()

# linksDB = sys.argv[1]

linksDB = args.database

linksDBcon = sqlite3.connect(linksDB, timeout=7200)
bitextDBcur = linksDBcon.cursor()
linksDBcur = linksDBcon.cursor()


## drop table first to make sure that we don't have incompatible tables from earlier versions:
# linksDBcur.execute("DROP TABLE IF EXISTS corpus_range")

linksDBcur.execute("CREATE TABLE IF NOT EXISTS corpus_range (corpus TEXT,version TEXT,srclang TEXT,trglang TEXT,srclang3 TEXT,trglang3 TEXT,start INTEGER,end INTEGER)")
linksDBcur.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_corpus ON corpus_range (corpus,version,srclang,trglang,srclang3,trglang3)")


def insert_range(corpus,version,srclang,trglang):
    global linksDBcur;
    
    print(f"Now processing {corpus}/{version}/{srclang}-{trglang}")
    for rowids in linksDBcur.execute(f"SELECT MIN(rowid),MAX(rowid) FROM links WHERE bitextID IN (SELECT rowid FROM bitexts WHERE corpus='{corpus}' AND version='{version}' AND fromDoc LIKE '{srclang}/%' AND toDoc LIKE '{trglang}/%')"):
        start = rowids[0]
        end = rowids[1]
        if (start and end):
            linksDBcur.execute(f"INSERT OR IGNORE INTO corpus_range VALUES ('{corpus}','{version}','{srclang}','{trglang}','{srclang3}','{trglang3}',{start},{end})")
            linksDBcur.execute(f"UPDATE corpus_range SET start={start},end={end} WHERE corpus='{corpus}' AND version='{version}' AND srclang='{srclang}' AND trglang='{trglang}' AND srclang3='{srclang3}' AND trglang3='{trglang3}'")


conditions = []
if (args.corpus):
    conditions.append(f"corpus='{args.corpus}'")
if (args.version):
    conditions.append(f"version='{args.version}'")
if (args.srclang):
    conditions.append(f"srclang='{args.srclang}'")
if (args.trglang):
    conditions.append(f"trglang='{args.trglang}'")

if conditions:
    condition = "WHERE " + " AND ".join(conditions)
else:
    condition = ''
    

# print(f"SELECT DISTINCT corpus,version,srclang,trglang,srclang3,trglang3 FROM corpora {condition}")
for bitext in bitextDBcur.execute(f"SELECT DISTINCT corpus,version,srclang,trglang,srclang3,trglang3 FROM corpora {condition}"):
    
    corpus = bitext[0]
    version = bitext[1]
    srclang = bitext[2]
    trglang = bitext[3]
    srclang3 = bitext[4]
    trglang3 = bitext[5]

    insert_range(corpus,version,srclang,trglang)
    

linksDBcon.commit()



##--------------------
## check overlaps
##--------------------

def overlap(x1,x2,y1,y2):
    if x2 < y1 or x1 > y2:
        return False
    return True


ranges = {}
for bitext in linksDBcur.execute(f"SELECT corpus,version,srclang,trglang,start,end FROM corpus_range"):
    ranges[f"{bitext[0]}/{bitext[1]}/{bitext[2]}-{bitext[3]}"] = tuple([bitext[4],bitext[5]]);

for x in ranges:
    for y in ranges:
        if x == y:
            continue
        if overlap(ranges[x][0],ranges[x][1],ranges[y][0],ranges[y][1]):
            print(f"{x} and {y} overlap! ({ranges[x][0]},{ranges[x][1]}) and ({ranges[y][0]},{ranges[y][1]})")
            
