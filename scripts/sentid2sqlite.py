#!/usr/bin/env python3


import argparse
import xml.parsers.expat
import zipfile
import os
import urllib.request
import sqlite3
import sys
from os.path import exists



storage_url_base = 'https://object.pouta.csc.fi/synOPUS-'


parser = argparse.ArgumentParser(prog='opus_sentid_index',
    description='Read OPUS documents and extract sentence IDs and row numbers from an index DB')

parser.add_argument('-i', '--index', help='Sentence index DB', required=True)
parser.add_argument('-d', '--database', help='Sentence DB', required=True)
parser.add_argument('-c', '--corpus', help='Corpus name', required=True)
parser.add_argument('-r', '--release', help='Release version', required=True)
parser.add_argument('-l', '--language', help='Language', required=True)
parser.add_argument('-f', '--file_name',help='File name (if not given, prints all files)')
parser.add_argument('-v', '--verbose', help='verbose output', action='store_true', default=False)

args = parser.parse_args()

verbose = args.verbose;

corpus    = args.corpus
release   = args.release
data_url  = storage_url_base + corpus + '/' + release + '/raw/' + args.language + '.zip'
data_file = corpus + '_' + release + '_raw_' + args.language + '.zip'



if not exists(data_file):
    sys.stderr.write(f"Downloading {data_url}\n")
    urllib.request.urlretrieve(data_url, data_file)
    
lzip = zipfile.ZipFile(data_file)


## document ID from document index

docID = 0

## global buffer for mass-inserting links

buffer = []
buffersize = 100000


## function to insert the current data buffer

def insert_buffer():
    global idxCon, idxCur, buffer
    
    if len(buffer) > 0:
        idxCur.executemany("""INSERT OR IGNORE INTO sentids VALUES(?,?,?)""", buffer)
        idxCon.commit()
        buffer = []

def start_element(name, attrs):
    global inSent, sentStr, sentCount, sentID
              
    if name == 's':
        inSent = True
        sentCount += 1
        sentStr = ''
        if 'id' in attrs:
            sentID = attrs['id']
        else:
            sentID = str(sentCount)
        if not sentCount % 2000:
            sys.stderr.write('.')
            if not sentCount % 100000:
                sys.stderr.write(f" {sentCount}\n")
            sys.stderr.flush()



            
def end_element(name):
    global inSent, sentStr, sentID, docID
    global corpus, release, document
    global cur, con, verbose
    global buffer, buffersize
        
    if name == 's':
        inSent = False
        sentStr = sentStr.lstrip().rstrip()
        res = cur.execute("""SELECT ROWID FROM sentences WHERE sentence = ?""", [sentStr])
        record = res.fetchone()
        if record:
            buffer.append(tuple([record[0],docID,sentID]))
        else:
            ## insert a new sentence!
            if verbose:
                sys.stderr.write('NEW SENTENCES - ' + sentID + ': ' + sentStr + "\n")
            cur.execute("""INSERT OR IGNORE INTO sentences VALUES(?)""", [sentStr])
            con.commit()                
            res = cur.execute("""SELECT ROWID FROM sentences WHERE sentence = ?""", [sentStr])
            record = res.fetchone()
            if record:
                buffer.append(tuple([record[0],docID,sentID]))
            else:
                sys.stderr.write('FAILED TO INSERT - ' + sentID + ': ' + sentStr + "\n")
        if len(buffer) >= buffersize:
            insert_buffer()

def char_data(data):
    global inSent, sentStr
    if inSent:
        sentStr = sentStr + data



## wait for max 2 hours
# con = sqlite3.connect(args.database, timeout=7200, isolation_level='EXCLUSIVE')
con = sqlite3.connect(args.database, timeout=7200)
# con.execute("PRAGMA journal_mode=WAL")
cur = con.cursor()

cur.execute("CREATE TABLE IF NOT EXISTS sentences ( sentence TEXT UNIQUE PRIMARY KEY NOT NULL )")


idxCon = sqlite3.connect(args.index, timeout=7200)
idxCur = idxCon.cursor();

idxCur.execute("CREATE TABLE IF NOT EXISTS documents ( corpus, version, document )")
idxCur.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_documents ON documents (corpus,version,document)")
idxCur.execute("CREATE TABLE IF NOT EXISTS sentids ( id INTEGER, docID INTEGER, sentID TEXT)")
idxCur.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_sentids ON sentids ( docID, sentID)")

idxCur.execute("""CREATE VIEW IF NOT EXISTS sentindex (id, corpus, version, document, sentID)
			AS SELECT id, corpus, version, document, sentID
			FROM sentids INNER JOIN documents ON documents.rowid = sentids.docID""")

idxCur.execute("""CREATE TRIGGER IF NOT EXISTS insert_sentid
		INSTEAD OF INSERT ON sentindex
		BEGIN
		  INSERT OR IGNORE INTO documents(corpus,version,document)
			VALUES (NEW.corpus,NEW.version,NEW.document);
		  INSERT INTO sentids(docID, id, sentID)
			VALUES ( ( SELECT rowid FROM documents
				   WHERE corpus=NEW.corpus AND version=NEW.version AND document=NEW.document ),
				 NEW.id, NEW.sentID );
		END""")

idxCon.commit()



count = 0



for filename in lzip.namelist():
    if filename[-4:] == '.xml':

        parser = xml.parsers.expat.ParserCreate()
        parser.StartElementHandler = start_element
        parser.EndElementHandler = end_element
        parser.CharacterDataHandler = char_data

        inSent    = False
        sentStr   = ''
        sentID    = ''
        sentCount = 0
        errorCount = 0
        
        document  = '/'.join(filename.split('/')[2:])

        idxCur.execute(f"""INSERT OR IGNORE INTO documents(corpus,version,document) 
                                     VALUES ('{corpus}','{release}','{document}')""")
        idxCon.commit()
        idxCur.execute(f"""SELECT rowid FROM documents
	                   WHERE corpus='{corpus}' AND version='{release}' AND document='{document}'""")
        row = idxCur.fetchone()
        docID = row[0]

        if verbose:
            sys.stderr.write(f"process {filename} ({count} sentences done)\n")
        with lzip.open(filename, 'r') as f:
            for line in f:
                try:
                    parser.Parse(line)
                except:
                    errorCount += 1
                    if verbose:
                        sys.stderr.write(f"error parsing {line}\n")

        insert_buffer()
        count += sentCount
        if errorCount > 0:
            sys.stderr.write(f"XML parsing errors for {filename}: {errorCount} lines\n")


sys.stderr.write(f"A total of {count} sentences found\n")
os.unlink(data_file)
