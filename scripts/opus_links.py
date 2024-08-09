#!/usr/bin/env python3
#
# read sentence alignment files and convert to tsv format
# lookup global sentence IDs if a database is given
# add also the link type to the table
# TODO: add scores etc
#

import argparse
import gzip
import os
import urllib.request
import sqlite3
import sys
from os.path import exists

from xml.parsers.expat import ParserCreate, ExpatError, errors


storage_url_base = 'https://object.pouta.csc.fi/OPUS-'


parser = argparse.ArgumentParser(prog='opus_sentid_index',
    description='Read OPUS documents and extract sentence IDs and row numbers from an index DB')

parser.add_argument('-c', '--corpus', help='Corpus name', required=True)
parser.add_argument('-r', '--release', help='Release version', required=True)
parser.add_argument('-l', '--language', help='Language pair', required=True)
parser.add_argument('-sd', '--source-database', help='Source language database')
parser.add_argument('-td', '--target-database', help='Target language database')
parser.add_argument('-v', '--verbose', help='verbose output', action='store_true', default=False)

args = parser.parse_args()

verbose = args.verbose;

corpus    = args.corpus
release   = args.release
data_url  = storage_url_base + corpus + '/' + release + '/xml/' + args.language + '.xml.gz'
data_file = corpus + '_' + release + '_raw_' + args.language + '.xml.gz'

get_sids = False
if (args.source_database):
    get_sids = True
    sdb = sqlite3.connect(args.source_database)
    sdbc = sdb.cursor()
    

get_tids = False
if (args.target_database):
    get_tids = True
    tdb = sqlite3.connect(args.target_database)
    tdbc = tdb.cursor()



if not exists(data_file):
    sys.stderr.write(f"Downloading {data_url}\n")
    urllib.request.urlretrieve(data_url, data_file)
    
def start_element(name, attrs):
    global corpus, release
    global fromDoc, toDoc
    global get_sids, get_tids
    
    if name == 'linkGrp':
        fromDoc = attrs['fromDoc'][:-3]
        toDoc = attrs['toDoc'][:-3]
    elif name == 'link':
        xtargets = attrs['xtargets']
        link = xtargets.split(';')
        src = link[0].split(' ')
        trg = link[1].split(' ')

        srcids = ''
        if get_sids:
            global sdbc
            srcids = get_sentence_ids(corpus, release, fromDoc, src, sdbc)

        trgids = ''
        if get_tids:
            global tdbc
            trgids = get_sentence_ids(corpus, release, toDoc, trg, tdbc)

        print("\t".join((corpus,release,fromDoc,toDoc,link[0],link[1],str(len(src)),str(len(trg)),srcids,trgids)))

## loop through source and target sentence IDs and repeat the link
## why? to make all source and target IDs searchable in a DB
## (quite a waste of space, isn't it?)
##
#        for s in src:
#            for t in trg:
#                print("\t".join((corpus,release,fromDoc,toDoc,s,t,link[0],link[1],str(len(src)),str(len(trg)))))
                

def get_sentence_ids(corpus, release, doc, ids, dbc):    
    sent_ids = []
    for i in ids:
        res = dbc.execute("""SELECT id FROM sentindex WHERE corpus = ? AND version = ? AND document = ? AND sentID = ?""",
                          [corpus, release, doc, i])
        record = res.fetchone()
        if record:
            sent_ids.append(record[0])

    return ' '.join(sent_ids)




parser = ParserCreate()
parser.StartElementHandler = start_element
errorCount = 0

with gzip.open(data_file,'r') as f:        
    for line in f:        
        try:
            parser.Parse(line)
        except ExpatError as err:
            errorCount += 1
            if verbose:
                sys.stderr.write("Error:", errors.messages[err.code])
                sys.stderr.write(f"error parsing {line}\n")


if errorCount > 0:
    sys.stderr.write(f"XML parsing errors for {data_file}: {errorCount} lines\n")

os.unlink(data_file)
