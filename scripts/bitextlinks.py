#!/usr/bin/env python3
#
# arguments: xx-yy.db xx.ids.db yy.ids.db xx-yy.linked.db corpus version
#

import sys
import sqlite3

if len(sys.argv) != 7:
    print("USAGE: corpuslinks.py xx-yy.db xx.ids.db yy.ids.db xx-yy.linked.db corpus version")
    exit()

algDB = sys.argv[1]
srcDB = sys.argv[2]
trgDB = sys.argv[3]
linkDB = sys.argv[4]
corpus = sys.argv[5]
version = sys.argv[6]

buffersize = 100000

##----------------------------------------------------------------
## connect to source and target language sentence index DBs
##----------------------------------------------------------------

srcDBcon = sqlite3.connect(f"file:{srcDB}?immutable=1",uri=True)
srcDBcur = srcDBcon.cursor()

trgDBcon = sqlite3.connect(f"file:{trgDB}?immutable=1",uri=True)
trgDBcur = trgDBcon.cursor()

##----------------------------------------------------------------
# create DB that shows what sentences are included in what kind of alignment units
##----------------------------------------------------------------

linksDBcon = sqlite3.connect(linkDB, timeout=7200)
linksDBcur = linksDBcon.cursor()

linksDBcur.execute("CREATE TABLE IF NOT EXISTS linkedsource ( sentID INTEGER, linkID INTEGER, bitextID INTEGER, PRIMARY KEY(linkID,sentID) )")
linksDBcur.execute("CREATE TABLE IF NOT EXISTS linkedtarget ( sentID INTEGER, linkID INTEGER, bitextID INTEGER, PRIMARY KEY(linkID,sentID) )")

linksDBcur.execute("CREATE INDEX IF NOT EXISTS idx_linkedsource_bitext ON linkedsource (bitextID,sentID)")
linksDBcur.execute("CREATE INDEX IF NOT EXISTS idx_linkedtarget_bitext ON linkedtarget (bitextID,sentID)")
linksDBcur.execute("CREATE INDEX IF NOT EXISTS idx_linkedsource_linkid ON linkedsource (linkID)")
linksDBcur.execute("CREATE INDEX IF NOT EXISTS idx_linkedtarget_linkid ON linkedtarget (linkID)")
linksDBcur.execute("CREATE INDEX IF NOT EXISTS idx_linkedsource_sentid ON linkedsource (sentID)")
linksDBcur.execute("CREATE INDEX IF NOT EXISTS idx_linkedtarget_sentid ON linkedtarget (sentID)")
linksDBcur.close()

##----------------------------------------------------------------
## connect to original sentence alignment DB
##----------------------------------------------------------------

algDBcon = sqlite3.connect(f"file:{algDB}?immutable=1",uri=True)
algDBcur = algDBcon.cursor()
bitextDBcur = algDBcon.cursor()


# insert links from buffer

srcbuffer = []
trgbuffer = []
linkbuffer = []

def insert_links():
    global linkDB, srcbuffer, trgbuffer, linkbuffer
    if len(srcbuffer) > 0 or len(trgbuffer) > 0:
        linksDBcon = sqlite3.connect(linkDB, timeout=7200)
        linksDBcur = linksDBcon.cursor()
        if len(srcbuffer) > 0:
            linksDBcur.executemany("""INSERT OR IGNORE INTO linkedsource VALUES(?,?,?)""", srcbuffer)
        if len(trgbuffer) > 0:
            linksDBcur.executemany("""INSERT OR IGNORE INTO linkedtarget VALUES(?,?,?)""", trgbuffer)
        linksDBcon.commit()
        linksDBcur.close()
        srcbuffer = []
        trgbuffer = []
        


#----------------------------------------------------------------
# run through all bitexts in this corpus (aligned document pairs)
# and store links that map internal sentence IDs to internal linkIDs
#----------------------------------------------------------------

bitextID = 0
fromDocID = 0
toDocID = 0
count = 0

for bitext in bitextDBcur.execute(f"SELECT rowid,fromDoc,toDoc FROM bitexts WHERE corpus='{corpus}' AND version='{version}'"):
    
    # find document IDs (fromDocID and toDocID)
    
    bitextID = bitext[0]
    fromDoc = bitext[1]
    toDoc = bitext[2]
    for doc in srcDBcur.execute(f"SELECT rowid FROM documents WHERE corpus='{corpus}' AND version='{version}' AND document='{fromDoc}'"):
        fromDocID = doc[0]
    for doc in trgDBcur.execute(f"SELECT rowid FROM documents WHERE corpus='{corpus}' AND version='{version}' AND document='{toDoc}'"):
        toDocID = doc[0]
    
    # run through alignments in this bitext

    # sys.stderr.write(f"links from bitext {bitextID} ({fromDoc} - {toDoc})\n")
    # sys.stderr.flush()

    for row in algDBcur.execute(f"SELECT rowid,srcIDs,trgIDs FROM links WHERE bitextID={bitextID}"):
        count+=1
        if not count % 5000:
            sys.stderr.write('.')
            if not count % 100000:
                sys.stderr.write(f" {count}\n")
            sys.stderr.flush()

        linkID = row[0]
        srcIDs = row[1].split(' ')
        trgIDs = row[2].split(' ')

        # get source and target sentence IDs from the sentence indeces
        # (search for the OPUS IDs in the sentence index DBs)

        for s in srcIDs:
            if (s):
                for sent in srcDBcur.execute(f"SELECT id FROM sentids WHERE docID={fromDocID} AND sentID='{s}'"):
                    sentID = sent[0]
                    srcbuffer.append(tuple([sentID,linkID,bitextID]))

        for t in trgIDs:
            if (t):
                for sent in trgDBcur.execute(f"SELECT id FROM sentids WHERE docID={toDocID} AND sentID='{t}'"):
                    sentID = sent[0]
                    trgbuffer.append(tuple([sentID,linkID,bitextID]))

        if len(srcbuffer) >= buffersize or len(trgbuffer) >= buffersize:
            insert_links()


# final insert if necessary
insert_links()


