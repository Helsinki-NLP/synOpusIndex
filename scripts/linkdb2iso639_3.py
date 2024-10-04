#!/usr/bin/env python3
#
#  copy link tables and reverse link direction if necessary
#  this will merge several language pairs that correspond to the same
#  ISO-639-3 macro-language codes of
#
# USAGE: linkdb2iso639_3.py dir xx yy xxx yyy
#
#  dir = directory where the DBs are located
#
#  xx = source language code (original OPUS code)
#  yy = target language code (original OPUS code)
#
#  xxx = three-letter source language code (macro-language if available)
#  yyy = three-letter target language code (macro-language if available)
#

import sys
import sqlite3
import os, traceback
import os.path

if len(sys.argv) != 6:
    print("USAGE: linkdb2iso639_3.py dir xx yy xxx yyy")
    exit()

dbDir = sys.argv[1]

srcLangOld = sys.argv[2]
trgLangOld = sys.argv[3]

srcLangNew = sys.argv[4]
trgLangNew = sys.argv[5]


oldLinkDB = f"{dbDir}/{srcLangOld}-{trgLangOld}.db"

if srcLangNew > trgLangNew:
    reverse = True;
    linkDB = f"{dbDir}/{trgLangNew}-{srcLangNew}.db"
else:
    reverse = False;
    linkDB = f"{dbDir}/{srcLangNew}-{trgLangNew}.db"

if oldLinkDB == linkDB:
    print(f"{oldLinkDB} and {linkDB} are the same. Nothing needs to be done")
    exit()

if not os.path.isfile(oldLinkDB):
    print(f"{oldLinkDB} does not exist")
    exit()

    
buffersize = 100000
srcbuffer = []
trgbuffer = []
linkbuffer = []


##----------------------------------------------------------------
# create new link db
##----------------------------------------------------------------

linksDBcon = sqlite3.connect(linkDB, timeout=7200)
linksDBcur = linksDBcon.cursor()


## save all original language pairs that will be covered by this link DB

linksDBcur.execute("CREATE TABLE IF NOT EXISTS langpairs (langpair TEXT NOT NULL PRIMARY KEY)")
linksDBcur.execute(f"INSERT OR IGNORE INTO langpairs VALUES ('{srcLangOld}-{trgLangOld}')")

## bitext DB (this will get new bitextIDs compared to the old DB)

linksDBcur.execute("CREATE TABLE IF NOT EXISTS bitexts ( corpus TEXT, version TEXT, fromDoc TEXT, toDoc TEXT )")
linksDBcur.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_bitexts ON bitexts ( corpus, version, fromDoc, toDoc )")

## tables that map sentences to links

linksDBcur.execute("CREATE TABLE IF NOT EXISTS linkedsource ( sentID INTEGER, linkID INTEGER, bitextID INTEGER, PRIMARY KEY(linkID,sentID) )")
linksDBcur.execute("CREATE TABLE IF NOT EXISTS linkedtarget ( sentID INTEGER, linkID INTEGER, bitextID INTEGER, PRIMARY KEY(linkID,sentID) )")

linksDBcur.execute("CREATE INDEX IF NOT EXISTS idx_linkedsource_bitext ON linkedsource (bitextID,sentID)")
linksDBcur.execute("CREATE INDEX IF NOT EXISTS idx_linkedtarget_bitext ON linkedtarget (bitextID,sentID)")
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
linksDBcur.execute("CREATE TABLE IF NOT EXISTS corpus_range (corpus TEXT, version TEXT,start INTEGER,end INTEGER)")
linksDBcur.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_corpus ON corpus_range ( corpus, version )")

linksDBcon.commit()
linksDBcur.close()




def insert_linkedsource():
    global linkDB, srcbuffer
    if len(srcbuffer) > 0:
        linksDBcon = sqlite3.connect(linkDB, timeout=7200)
        linksDBcur = linksDBcon.cursor()
        linksDBcur.executemany("""INSERT OR IGNORE INTO linkedsource VALUES(?,?,?)""", srcbuffer)
        linksDBcon.commit()
        linksDBcur.close()
        srcbuffer = []

def insert_linkedtarget():
    global linkDB, trgbuffer
    if len(trgbuffer) > 0:
        linksDBcon = sqlite3.connect(linkDB, timeout=7200)
        linksDBcur = linksDBcon.cursor()
        linksDBcur.executemany("""INSERT OR IGNORE INTO linkedtarget VALUES(?,?,?)""", trgbuffer)
        linksDBcon.commit()
        linksDBcur.close()
        trgbuffer = []

def insert_links():
    global linkDB, linkbuffer
    if len(linkbuffer) > 0:
        linksDBcon = sqlite3.connect(linkDB, timeout=7200)
        linksDBcur = linksDBcon.cursor()
        linksDBcur.executemany("""INSERT OR IGNORE INTO links VALUES(?,?,?,?,?,?,?,?,?)""", linkbuffer)
        linksDBcon.commit()
        linksDBcur.close()
        linkbuffer = []

def print_progress():
    global count
    count+=1
    if not count % 5000:
        sys.stderr.write('.')
        if not count % 100000:
            sys.stderr.write(f" {count}\n")
        sys.stderr.flush()



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



##----------------------------------------------------------------
# run through all bitexts and copy the links
##----------------------------------------------------------------

oldLinkDBcon = sqlite3.connect(f"file:{oldLinkDB}?immutable=1",uri=True)
oldLinkDBcur = oldLinkDBcon.cursor()
bitextDBcur = oldLinkDBcon.cursor()


bitextID = 0
fromDocID = 0
toDocID = 0
count = 0

for bitext in bitextDBcur.execute(f"SELECT rowid,corpus,version,fromDoc,toDoc FROM bitexts"):

    oldBitextID = bitext[0]
    corpus = bitext[1]
    version = bitext[2]
    # print(f"processing {bitextID} = {corpus}/{version}")
    
    if reverse:
        fromDoc = bitext[4]
        toDoc = bitext[3]
    else:
        fromDoc = bitext[3]
        toDoc = bitext[4]
        

    linksDBcon = sqlite3.connect(linkDB, timeout=7200)
    linksDBcur = linksDBcon.cursor()
    linksDBcur.execute(f"INSERT OR IGNORE INTO bitexts VALUES ('{corpus}','{version}','{fromDoc}','{toDoc}')")
    linksDBcur.execute(f"""SELECT rowid FROM bitexts
                                        WHERE corpus='{corpus}' AND version='{version}' AND
                                              fromDoc='{fromDoc}' AND toDoc='{toDoc}'""")
    row = linksDBcur.fetchone()
    bitextID = row[0]
    linksDBcon.commit()
    linksDBcur.close()

    
    ## copy the linkedsource and linkedtarget tables (reverse if necessary)

    if reverse:
        srclinktable = 'linkedtarget'
        trglinktable = 'linkedsource'
    else:
        srclinktable = 'linkedsource'
        trglinktable = 'linkedtarget'

    # print(f"copying linkedsource table")
    for linked in oldLinkDBcur.execute(f"SELECT sentID,linkID FROM {srclinktable} WHERE bitextID={oldBitextID} ORDER BY rowid"):
        print_progress()
        linked += (bitextID,)
        srcbuffer.append(linked)
        if len(srcbuffer) >= buffersize:
            insert_linkedsource()
    insert_linkedsource()

    # print(f"copying linkedtarget table")
    for linked in oldLinkDBcur.execute(f"SELECT sentID,linkID FROM {trglinktable} WHERE bitextID={oldBitextID} ORDER BY rowid"):
        print_progress()
        linked += (bitextID,)
        trgbuffer.append(linked)
        if len(trgbuffer) >= buffersize:
            insert_linkedtarget()
    insert_linkedtarget()

    # print(f"copying links table")
    for row in oldLinkDBcur.execute(f"SELECT * FROM links WHERE bitextID={oldBitextID} ORDER BY rowid"):
        print_progress()
        if (reverse):
            srcID = row[2]
            trgID = row[3]
            srcSentID = row[4]
            trgSentID = row[5]
            nrSents = row[6].split('-')
            alignType = str(nrSents[1]) + '-' + str(nrSents[0]) 

            row = list(row)
            row[2] = trgID
            row[3] = srcID
            row[4] = trgSentID
            row[5] = srcSentID
            row[6] = alignType

        linkbuffer.append(row)
        if len(linkbuffer) >= buffersize:
            insert_links()
    
    insert_links()
    insert_range(bitextID)



    
## finally: add corpus range information

linksDBcon = sqlite3.connect(linkDB, timeout=7200)
linksDBcur = linksDBcon.cursor()

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
linksDBcur.close()
