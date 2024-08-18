#!/usr/bin/env python3
#
# USAGE: alg2sqlite.py dbname corpus version < xces-align-file


import sys
import xml.parsers.expat
import sqlite3


con = sqlite3.connect(sys.argv[1])
cur = con.cursor()

corpus = sys.argv[2]
version = sys.argv[3]


## create bitexts and links tables with indeces over columns

cur.execute("CREATE TABLE IF NOT EXISTS bitexts ( corpus TEXT, version TEXT, fromDoc TEXT, toDoc TEXT )")
cur.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_bitexts ON bitexts ( corpus, version, fromDoc, toDoc )")

cur.execute("""CREATE TABLE IF NOT EXISTS links ( bitextID, srcIDs TEXT, trgIDs TEXT, alignType TEXT,
                                                alignerScore REAL, cleanerScore REAL)""")
cur.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_links ON links ( bitextID, srcIDs, trgIDs )")
cur.execute("CREATE INDEX IF NOT EXISTS idx_aligntype ON links ( bitextID, alignType )")
cur.execute("CREATE INDEX IF NOT EXISTS idx_bitextid ON links ( bitextID )")


## create a view that joins the bitexts and links tables

cur.execute("""CREATE VIEW IF NOT EXISTS alignments (corpus, version, fromDoc, toDoc,
		                                     srcIDs, trgIDs, alignType,
				                     alignerScore, cleanerScore)
		    AS SELECT corpus, version, fromDoc, toDoc, 
                              srcIDs, trgIDs, alignType,
			      alignerScore, cleanerScore
		       FROM links
		       INNER JOIN bitexts ON bitexts.rowid = links.bitextID""")


## create an insert trigger that allows to insert data into the alignments view
## (triggers an insert into the bitexts table and connects links with the correct bitextID)

cur.execute("""CREATE TRIGGER IF NOT EXISTS insert_alignment
                    INSTEAD OF INSERT ON alignments
		    BEGIN
		        INSERT OR IGNORE INTO bitexts(corpus,version,fromDoc,toDoc)
			VALUES (NEW.corpus,NEW.version,NEW.fromDoc,NEW.toDoc);
			INSERT INTO links( bitextID, srcIDs, trgIDs, alignType,
                                           alignerScore, cleanerScore)
			VALUES ( ( SELECT rowid FROM bitexts
				          WHERE corpus=NEW.corpus AND version=NEW.version AND
				                fromDoc=NEW.fromDoc AND toDoc=NEW.toDoc ),
				 NEW.srcIDs,NEW.trgIDs,NEW.alignType,
                                 NEW.alignerScore, NEW.cleanerScore);
		END""")

con.commit()


## global variables to store the current document pair and their bitext ID

fromDoc = ''
toDoc = ''
bitextID = 0


## global buffer for mass-inserting links

buffer = []
buffersize = 100000
bufferCount = 0


## function to insert the current data buffer

def insert_buffer():
    global con, cur
    global buffer, bufferCount
    
    if len(buffer) > 0:
        cur.executemany("""INSERT OR IGNORE INTO links VALUES(?,?,?,?,?,?)""", buffer)
        con.commit()
        buffer = []
        
        bufferCount += 1
        sys.stderr.write('.')
        if not bufferCount % 100:
            sys.stderr.write(f" {bufferCount} buffers ({buffersize})\n")
        sys.stderr.flush()


## XML parser handles
        
def end_element(name):
    if name == 'linkGrp':
        insert_buffer()

def start_element(name, attrs):
    global bitextID, corpus, version, fromDoc, toDoc
    global buffer
    
    if name == 'linkGrp':
        insert_buffer()
        if 'fromDoc' in attrs:
            fromDoc = attrs['fromDoc'].replace('.xml.gz','.xml')
            if 'toDoc' in attrs:
                toDoc = attrs['toDoc'].replace('.xml.gz','.xml')
                cur.execute(f"""INSERT OR IGNORE INTO bitexts(corpus,version,fromDoc,toDoc) 
                                       VALUES ('{corpus}','{version}','{fromDoc}','{toDoc}')""")
                con.commit()
                cur.execute(f"""SELECT rowid FROM bitexts
			        WHERE corpus='{corpus}' AND version='{version}' AND
                                      fromDoc='{fromDoc}' AND toDoc='{toDoc}'""")
                row = cur.fetchone()
                bitextID = row[0]
        
    elif name == 'link':
        if 'xtargets' in attrs:
            link = attrs['xtargets'].split(';')
            alignScore = 0.0
            cleanScore = 0.0
            if 'score' in attrs:
                alignScore = float(attrs['score'])
            if 'certainty' in attrs:
                alignScore = float(attrs['certainty'])
            if 'overlap' in attrs:
                alignScore = float(attrs['overlap'])
            if 'bicleaner' in attrs:
                cleanScore = float(attrs['bicleanerScore'])
            srcIDs = link[0].split()
            trgIDs = link[1].split()
            alignType = str(len(srcIDs)) + '-' + str(len(trgIDs))
            buffer.append(tuple([bitextID,link[0],link[1],alignType,alignScore,cleanScore]))

            # srcLen = len(srcIDs)
            # trgLen = len(trgIDs)
            # buffer.append(tuple([bitextID,link[0],link[1],srcLen,trgLen,alignScore,cleanScore]))
            if len(buffer) >= buffersize:
                insert_buffer()
            
            # print(','.join([fromDoc,toDoc,link[0],link[1],str(srcLen),str(trgLen),str(alignScore),str(cleanScore)]))
            # alignType = str(len(srcIDs)) + '-' + str(len(trgIDs))
            # print(','.join([fromDoc,toDoc,link[0],link[1],alignType,alignScore,cleanScore]))



parser = xml.parsers.expat.ParserCreate()
parser.StartElementHandler = start_element
parser.EndElementHandler   = end_element

errorCount = 0;
for line in sys.stdin:
    try:
        parser.Parse(line)
    except:
        errorCount+=1
        # sys.stderr.write("x")

con.close()
if errorCount:
    print(f"Could not parse {errorCount} lines")
    print(argv)
    
