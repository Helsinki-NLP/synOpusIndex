#!/usr/bin/env python3
#
# arguments: xx-yy.db xx.ids.db yy.ids.db xx-yy.linked.db corpus version
#

import sys
import sqlite3
import os, traceback

if len(sys.argv) != 7:
    print("USAGE: links2sqlite.py xx-yy.db xx.ids.db yy.ids.db xx-yy.linked.db corpus version")
    print(sys.argv)
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

## tables that map sentences to links

linksDBcur.execute("CREATE TABLE IF NOT EXISTS linkedsource ( sentID INTEGER, linkID INTEGER, bitextID INTEGER, corpusID INTEGER, PRIMARY KEY(linkID,sentID) )")
linksDBcur.execute("CREATE TABLE IF NOT EXISTS linkedtarget ( sentID INTEGER, linkID INTEGER, bitextID INTEGER, corpusID INTEGER, PRIMARY KEY(linkID,sentID) )")

linksDBcur.execute("CREATE INDEX IF NOT EXISTS idx_linkedsource_bitext ON linkedsource (corpusID,bitextID,sentID)")
linksDBcur.execute("CREATE INDEX IF NOT EXISTS idx_linkedtarget_bitext ON linkedtarget (corpusID,bitextID,sentID)")
linksDBcur.execute("CREATE INDEX IF NOT EXISTS idx_linkedsource_linkid ON linkedsource (linkID)")
linksDBcur.execute("CREATE INDEX IF NOT EXISTS idx_linkedtarget_linkid ON linkedtarget (linkID)")
linksDBcur.execute("CREATE INDEX IF NOT EXISTS idx_linkedsource_sentid ON linkedsource (sentID)")
linksDBcur.execute("CREATE INDEX IF NOT EXISTS idx_linkedtarget_sentid ON linkedtarget (sentID)")

## the original alignment table, now also with internal sentence IDs

linksDBcur.execute("""CREATE TABLE IF NOT EXISTS links ( linkID INTEGER NOT NULL PRIMARY KEY, bitextID, 
                                                         srcIDs TEXT, trgIDs TEXT, srcSentIDs TEXT, trgSentIDs TEXT,
                                                         alignType TEXT, alignerScore REAL, cleanerScore REAL)""")
linksDBcur.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_links ON links ( bitextID, srcIDs, trgIDs )")
linksDBcur.execute("CREATE INDEX IF NOT EXISTS idx_aligntype ON links ( bitextID, alignType )")
linksDBcur.execute("CREATE INDEX IF NOT EXISTS idx_bitextid ON links ( bitextID )")
linksDBcur.execute("CREATE TABLE IF NOT EXISTS bitext_range (bitextID INTEGER NOT NULL PRIMARY KEY,start INTEGER,end INTEGER)")


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
        if len(linkbuffer) > 0:
            linksDBcur.executemany("""INSERT OR IGNORE INTO links VALUES(?,?,?,?,?,?,?,?,?)""", linkbuffer)
            # try:
            #     linksDBcur.executemany("""INSERT OR IGNORE INTO links VALUES(?,?,?,?,?,?,?,?,?)""", linkbuffer)
            # except:
            #     print(linkbuffer)
            #     print(sqlite3.Error.sqlite_errorcode)  # Prints 275
            #     print(sqlite3.Error.sqlite_errorname)  # Prints SQLITE_CONSTRAINT_CHECK
            #     quit()

        linksDBcon.commit()
        linksDBcur.close()
        srcbuffer = []
        trgbuffer = []
        linkbuffer = []



def insert_range(bitextID):
    global linkDB
    linksDBcon = sqlite3.connect(linkDB, timeout=7200)
    linksDBcur = linksDBcon.cursor()

    for rowids in linksDBcur.execute(f"SELECT MIN(rowid),MAX(rowid) FROM links WHERE bitextID={bitextID}"):
        start = rowids[0]
        end = rowids[1]
        if start and end:
            linksDBcur.execute(f"INSERT OR IGNORE INTO bitext_range VALUES ({bitextID},{start},{end})")
        
    linksDBcon.commit()
    linksDBcur.close()



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

    for row in algDBcur.execute(f"SELECT rowid,srcIDs,trgIDs,alignType,alignerScore,cleanerScore FROM links WHERE bitextID={bitextID}"):
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

        srcSentIDs = []
        trgSentIDs = []

        cleanSrcIDs = []
        cleanTrgIDs = []

        for s in srcIDs:
            if (s):
                cleanSrcIDs.append(s)
                for sent in srcDBcur.execute(f"SELECT id FROM sentids WHERE docID={fromDocID} AND sentID='{s}'"):
                    sentID = sent[0]
                    srcbuffer.append(tuple([sentID,linkID,bitextID]))
                    srcSentIDs.append(str(sentID))

        for t in trgIDs:
            if (t):
                cleanTrgIDs.append(t)
                for sent in trgDBcur.execute(f"SELECT id FROM sentids WHERE docID={toDocID} AND sentID='{t}'"):
                    sentID = sent[0]
                    trgbuffer.append(tuple([sentID,linkID,bitextID]))
                    trgSentIDs.append(str(sentID))

        srcID = ' '.join(cleanSrcIDs)
        trgID = ' '.join(cleanTrgIDs)
        srcSentID = ' '.join(srcSentIDs)
        trgSentID = ' '.join(trgSentIDs)

        linkbuffer.append([linkID,bitextID,srcID,trgID,srcSentID,trgSentID,row[3],row[4],row[5]])

        if len(srcbuffer) >= buffersize or len(trgbuffer) >= buffersize:
            insert_links()

    insert_links()
    insert_range(bitextID)


# final insert if necessary (should not be necessary)
insert_links()


