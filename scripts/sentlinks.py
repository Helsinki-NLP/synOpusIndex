#!/usr/bin/env python3
#
# arguments: xx-yy.db xx.ids.db yy.ids.db xx-yy.linked.db
#

import sys
import sqlite3


algDB = sys.argv[1]
srcDB = sys.argv[2]
trgDB = sys.argv[3]
linkDB = sys.argv[4]


## connect to source and target language sentence index DBs

srcDBcon = sqlite3.connect(srcDB)
srcDBcur = srcDBcon.cursor()

trgDBcon = sqlite3.connect(trgDB)
trgDBcur = trgDBcon.cursor()

# create DB that shows what sentences are included in what kind of alignment units

linksDBcon = sqlite3.connect(linkDB)
linksDBcur = linksDBcon.cursor()

linksDBcur.execute("CREATE TABLE IF NOT EXISTS linkedsource ( sentID INTEGER, linkID INTEGER, corpusID INTEGER)")
linksDBcur.execute("CREATE TABLE IF NOT EXISTS linkedtarget ( sentID INTEGER, linkID INTEGER, corpusID INTEGER)")
linksDBcur.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_sourcelinked ON linkedsource ( sentID, linkID, corpusID)")
linksDBcur.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_targetlinked ON linkedtarget ( sentID, linkID, corpusID)")


## create a new table of corpus names + versions
## --> this is to enable searching the sentence links for specific corpora without complicated table queries

linksDBcur.execute(f"ATTACH DATABASE '{algDB}' as alg")
linksDBcur.execute("CREATE TABLE IF NOT EXISTS corpora ( corpus TEXT, version TEXT)")
linksDBcur.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_corpus ON corpora ( corpus, version)")
linksDBcur.execute("INSERT OR IGNORE INTO corpora (corpus,version) SELECT DISTINCT corpus,version FROM alg.bitexts")
linksDBcon.commit()
linksDBcur.execute("DETACH DATABASE alg")


## connect to original sentence alignment DB

algDBcon = sqlite3.connect(algDB)
algDBcur = algDBcon.cursor()
bitextDBcur = algDBcon.cursor()


srcbuffer = []
trgbuffer = []
buffersize = 10000

bitextID = 0
corpusID = 0
fromDocID = 0
toDocID = 0

count = 0
for row in algDBcur.execute("SELECT rowid,bitextID,srcIDs,trgIDs FROM links ORDER BY bitextID"):
    
    count+=1
    if not count % 5000:
        sys.stderr.write('.')
        if not count % 100000:
            sys.stderr.write(f" {count}\n")
        sys.stderr.flush()

    if row[1] != bitextID:
        bitextID = row[1]
        for bitext in bitextDBcur.execute(f"SELECT * FROM bitexts WHERE rowid={bitextID}"):
            corpus = bitext[0]
            version = bitext[1]
            fromDoc = bitext[2]
            toDoc = bitext[3]
            for resource in linksDBcur.execute(f"SELECT rowid FROM corpora WHERE corpus='{corpus}' AND version='{version}'"):
                corpusID = resource[0]

            for doc in srcDBcur.execute(f"SELECT rowid FROM documents WHERE corpus='{corpus}' AND version='{version}' AND document='{fromDoc}'"):
                fromDocID = doc[0]
            for doc in trgDBcur.execute(f"SELECT rowid FROM documents WHERE corpus='{corpus}' AND version='{version}' AND document='{toDoc}'"):
                toDocID = doc[0]

    linkID = row[0]
    srcIDs = row[2].split(' ')
    trgIDs = row[3].split(' ')
    
    for s in srcIDs:
        if (s):
            # print(f"look for source sentence --{fromDocID}/{s}--")
            for sent in srcDBcur.execute(f"SELECT id FROM sentids WHERE docID={fromDocID} AND sentID='{s}'"):
                # print(f"found source sentence --{s}--")
                sentID = sent[0]
                srcbuffer.append(tuple([sentID,linkID,corpusID]))
            
    for t in trgIDs:
        if (t):
            # print(f"look for target sentence --{toDocID}/{t}--")
            for sent in trgDBcur.execute(f"SELECT id FROM sentids WHERE docID={toDocID} AND sentID='{t}'"):
                # print(f"found target sentence --{t}--")
                sentID = sent[0]
                trgbuffer.append(tuple([sentID,linkID,corpusID]))


    if len(srcbuffer) >= buffersize:
        linksDBcur.executemany("""INSERT OR IGNORE INTO linkedsource VALUES(?,?,?)""", srcbuffer)
        linksDBcon.commit()
        srcbuffer = []

    if len(trgbuffer) >= buffersize:
        linksDBcur.executemany("""INSERT OR IGNORE INTO linkedtarget VALUES(?,?,?)""", trgbuffer)
        linksDBcon.commit()
        trgbuffer = []



# final insert if necessary

if len(srcbuffer) > 0:
    linksDBcur.executemany("""INSERT OR IGNORE INTO linkedsource VALUES(?,?,?)""", srcbuffer)
    linksDBcon.commit()

if len(trgbuffer) > 0:
    linksDBcur.executemany("""INSERT OR IGNORE INTO linkedtarget VALUES(?,?,?)""", trgbuffer)
    linksDBcon.commit()
