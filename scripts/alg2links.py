#!/usr/bin/env python3

import argparse
import sys
import sqlite3
import os, traceback

parser = argparse.ArgumentParser(prog='alg2links',description='convert alignments from bitexts to link databases')
parser.add_argument("-a", "--alignments", type=str, required=True, help="name of the alignment database file (input)")
parser.add_argument("-s", "--srcids", type=str, required=True, help="source sentence ID database file")
parser.add_argument("-t", "--trgids", type=str, required=True, help="target sentence ID database file")
parser.add_argument("-l", "--links", type=str, required=True, help="name of the link database file (output)")

parser.add_argument("-c", "--corpus", type=str, help="name of the OPUS corpus")
parser.add_argument("-v", "--version", type=str, help="release of the corpus")
parser.add_argument("-s2", "--srclang2", type=str, help="source language code (OPUS langids)")
parser.add_argument("-t2", "--trglang2", type=str, help="target language code (OPUS langids)")
parser.add_argument("-s3", "--srclang3", type=str, help="source language code (ISO-639-3)")
parser.add_argument("-t3", "--trglang3", type=str, help="target language code (ISO-639-3)")


args = parser.parse_args()

algDB = args.alignments
srcDB = args.srcids
trgDB = args.trgids
linkDB = args.links


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


## corpus and bitext tables

linksDBcur.execute("""CREATE TABLE IF NOT EXISTS corpora (corpusID INTEGER NOT NULL PRIMARY KEY,
	                                                  corpus TEXT,version TEXT,srclang TEXT,trglang TEXT,
	                                                  srclang3 TEXT,trglang3 TEXT,latest INTEGER)""")
linksDBcur.execute("""CREATE UNIQUE INDEX IF NOT EXISTS idx_corpora 
                      ON corpora (corpus,version,srclang,trglang,srclang3,trglang3,latest)""")
linksDBcur.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_release ON corpora (corpus,version,srclang,trglang)")
linksDBcur.execute("""CREATE TABLE IF NOT EXISTS bitexts (bitextID INTEGER NOT NULL PRIMARY KEY,
	                                         corpus TEXT,version TEXT,fromDoc TEXT,toDoc TEXT)""")
linksDBcur.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_bitexts ON bitexts (corpus,version,fromDoc,toDoc)")
linksDBcur.execute("CREATE TABLE IF NOT EXISTS bitext_range (bitextID INTEGER NOT NULL PRIMARY KEY,start INTEGER,end INTEGER)")
linksDBcur.execute("CREATE TABLE IF NOT EXISTS corpus_range (corpusID INTEGER NOT NULL PRIMARY KEY,start INTEGER,end INTEGER)")

linksDBcon.commit()


##----------------------------------------------------------------
## connect to original sentence alignment DB
##----------------------------------------------------------------

algDBcon = sqlite3.connect(f"file:{algDB}?immutable=1",uri=True)
algDBcur = algDBcon.cursor()
bitextDBcur = algDBcon.cursor()

##----------------------------------------------------------------
## insert links from buffer
##----------------------------------------------------------------

srcbuffer = []
trgbuffer = []
linkbuffer = []

def insert_links():
    global linkDB, linksDBcon, linksDBcur, srcbuffer, trgbuffer, linkbuffer
    if len(srcbuffer) > 0 or len(trgbuffer) > 0:
        if len(srcbuffer) > 0:
            linksDBcur.executemany("""INSERT OR IGNORE INTO linkedsource VALUES(?,?,?,?)""", srcbuffer)
        if len(trgbuffer) > 0:
            linksDBcur.executemany("""INSERT OR IGNORE INTO linkedtarget VALUES(?,?,?,?)""", trgbuffer)
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
        
        srcbuffer = []
        trgbuffer = []
        linkbuffer = []


##----------------------------------------------------------------
## insert rowid range for a bitext
##----------------------------------------------------------------

def insert_bitext_range(bitextID):
    global linkDB, linksDBcon, linksDBcur

    for rowids in linksDBcur.execute(f"SELECT MIN(rowid),MAX(rowid) FROM links WHERE bitextID={bitextID}"):
        start = rowids[0]
        end = rowids[1]
        if start and end:
            linksDBcur.execute(f"INSERT OR IGNORE INTO bitext_range VALUES ({bitextID},{start},{end})")
            linksDBcur.execute(f"UPDATE bitext_range SET start={start},end={end} WHERE bitextID='{bitextID}'")
        
    linksDBcon.commit()


def insert_corpus_range(corpusID,corpus,version,srclang,trglang):
    global linkDB, linksDBcon, linksDBcur

    start = 0
    end = 0
    for rowids in linksDBcur.execute(f"SELECT MIN(rowid),MAX(rowid) FROM links WHERE bitextID IN (SELECT rowid FROM bitexts WHERE corpus='{corpus}' AND version='{version}' AND fromDoc LIKE '{srclang}/%' AND toDoc LIKE '{trglang}/%')"):
        start = rowids[0]
        end = rowids[1]
        if start and end:
            linksDBcur.execute(f"INSERT OR IGNORE INTO corpus_range VALUES ({corpusID},{start},{end})")
            linksDBcur.execute(f"UPDATE corpus_range SET start={start},end={end} WHERE corpusID='{corpusID}'")

    if not start and not end:
        linksDBcur.execute(f"DELETE FROM corpora WHERE corpusID='{corpusID}'")
        linksDBcur.execute(f"DELETE FROM corpus_range WHERE corpusID='{corpusID}'")
        
    linksDBcon.commit()


def insert_corpus(data):
    global linkDB, linksDBcon, linksDBcur
    
    linksDBcur.execute("INSERT OR IGNORE INTO corpora VALUES(?,?,?,?,?,?,?,?)", data)
    if data[7] == 1:
        linksDBcur.execute("""UPDATE corpora SET latest=0 WHERE corpus='{corpus}' 
                              AND srclang='{srclang}' AND trglang='{trglang}'""")
        
    linksDBcur.execute(f"""UPDATE corpora SET latest={data[7]} 
                                  WHERE corpus='{corpus}' AND version='{version}' 
                                  AND srclang='{srclang}' AND trglang='{trglang}'""")
    linksDBcon.commit()

def delete_corpus(corpusID):
    global linksDBcon, linksDBcur
    linksDBcur.execute(f"DELETE FROM corpora WHERE corpusID='{corpusID}'")
    linksDBcur.execute(f"DELETE FROM corpus_range WHERE corpusID='{corpusID}'")
    linksDBcon.commit()


def insert_bitext(data):
    global linksDBcon, linksDBcur
    linksDBcur.execute("INSERT OR IGNORE INTO bitexts VALUES(?,?,?,?,?)", data)
    linksDBcon.commit()

def delete_bitext(bitextID):
    global linksDBcon, linksDBcur
    linksDBcur.execute(f"DELETE FROM bitexts WHERE bitextID='{bitextID}'")
    linksDBcur.execute(f"DELETE FROM bitext_range WHERE bitextID='{bitextID}'")
    linksDBcon.commit()


#----------------------------------------------------------------
# run through all bitexts in a selected corpus (aligned document pairs)
# and store links that map internal sentence IDs to internal linkIDs
#----------------------------------------------------------------

def copy_links(corpus,version,srclang,trglang):
    global bitextDBcur, algDBcur, srcDBcur, trgDBcur
    global srcbuffer, trgbuffer, linkbuffer

    ## get corpus ID and copy the corpus entry to the new DB

    corpusID = 0
    matchCorpus = f"corpus='{corpus}' AND version='{version}'"
    matchLangs = f"srclang='{srclang}' AND trglang='{trglang}'"
    matchDocLangs = f"fromDoc LIKE '{srclang}/%' AND toDoc LIKE '{trglang}/%'"
    
    for data in bitextDBcur.execute(f"SELECT rowid,* FROM corpora WHERE {matchCorpus} AND {matchLangs}"):
        corpusID = data[0]
        insert_corpus(tuple(data))

    bitextID = 0
    fromDocID = 0
    toDocID = 0
    count = 0
    countCorpusLinks = 0

    for bitext in bitextDBcur.execute(f"SELECT rowid,* FROM bitexts WHERE {matchCorpus} AND {matchDocLangs}"):
    
        # find document IDs (fromDocID and toDocID)
        
        bitextID = bitext[0]
        fromDoc = bitext[3]
        toDoc = bitext[4]
        countBitextLinks = 0

        # print(f"now doing {bitextID}: {fromDoc}-{toDoc}")    
        for doc in srcDBcur.execute(f"SELECT rowid FROM documents WHERE {matchCorpus} AND document='{fromDoc}'"):
            fromDocID = doc[0]
            for doc in trgDBcur.execute(f"SELECT rowid FROM documents WHERE {matchCorpus} AND document='{toDoc}'"):
                toDocID = doc[0]
    
        # run through alignments in this bitext

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
                        if sentID:
                            srcbuffer.append(tuple([sentID,linkID,bitextID,corpusID]))
                            srcSentIDs.append(str(sentID))

            for t in trgIDs:
                if (t):
                    cleanTrgIDs.append(t)
                    for sent in trgDBcur.execute(f"SELECT id FROM sentids WHERE docID={toDocID} AND sentID='{t}'"):
                        sentID = sent[0]
                        if sentID:
                            trgbuffer.append(tuple([sentID,linkID,bitextID,corpusID]))
                            trgSentIDs.append(str(sentID))

            if (len(cleanSrcIDs) == len(srcSentIDs)) and ((len(cleanTrgIDs) == len(trgSentIDs))):
                countBitextLinks+=1
                
                srcID = ' '.join(cleanSrcIDs)
                trgID = ' '.join(cleanTrgIDs)
                srcSentID = ' '.join(srcSentIDs)
                trgSentID = ' '.join(trgSentIDs)

                linkbuffer.append([linkID,bitextID,srcID,trgID,srcSentID,trgSentID,row[3],row[4],row[5]])

            if len(srcbuffer) >= buffersize or len(trgbuffer) >= buffersize:
                insert_links()

        insert_links()
        if (countBitextLinks):
            insert_bitext(tuple(bitext))
            insert_bitext_range(bitextID)
        else:
            delete_bitext(bitextID)

        countCorpusLinks += countBitextLinks
        

    # final insert if necessary (should not be necessary)
    insert_links()
    if countCorpusLinks:
        insert_corpus_range(corpusID,corpus,version,srclang,trglang)
    else:
        delete_corpus(corpusID)




conditions = []
if (args.corpus):
    conditions.append(f"corpus='{args.corpus}'")
if (args.version):
    conditions.append(f"version='{args.version}'")
if (args.srclang2):
    conditions.append(f"srclang='{args.srclang2}'")
if (args.trglang2):
    conditions.append(f"trglang='{args.trglang2}'")
if (args.srclang3):
    conditions.append(f"srclang3='{args.srclang3}'")
if (args.trglang3):
    conditions.append(f"trglang3='{args.trglang3}'")

if conditions:
    condition = "WHERE " + " AND ".join(conditions)
else:
    condition = ''

corpusDBcur = algDBcon.cursor()
for bitext in corpusDBcur.execute(f"SELECT DISTINCT corpus,version,srclang,trglang FROM corpora {condition}"):
    
    corpus = bitext[0]
    version = bitext[1]
    srclang = bitext[2]
    trglang = bitext[3]

    linksDBcur.execute(f"""SELECT rowid FROM corpora 
                           WHERE corpus='{corpus}' AND version='{version}' 
                           AND srclang='{srclang}' AND trglang='{trglang}'""")
    if linksDBcur.fetchone():
        print(f"already done: {corpus}/{version}/{srclang}-{trglang}")
    else:
        print(f"processing {corpus}/{version}/{srclang}-{trglang}")
        copy_links(corpus,version,srclang,trglang)

linksDBcon.close()
algDBcon.close()
srcDBcon.close()
trgDBcon.close()
