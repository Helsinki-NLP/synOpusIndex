#!/usr/bin/env python3

import sys
import sqlite3

langpair = sys.argv[1]
langs = langpair.split('-')
src = langs[0]
trg = langs[1]


algDB  = sqlite3.connect(langpair+'.db')
algDBH = algDB.cursor()

srcIdxDB  = sqlite3.connect(src+'.idx.db')
trgIdxDB  = sqlite3.connect(trg+'.idx.db')
srcIdxDBH = srcIdxDB.cursor()
trgIdxDBH = trgIdxDB.cursor()

srcDB  = sqlite3.connect(src+'.db')
trgDB  = sqlite3.connect(trg+'.db')
srcDBH = srcDB.cursor()
trgDBH = trgDB.cursor()


condition = ''
if len(sys.argv) > 2:
    corpus = sys.argv[2]
    condition = f"WHERE corpus='{corpus}'"
if len(sys.argv) > 3:
    version = sys.argv[3]
    condition = f" AND version='{version}'"

columns = 'corpus,version,fromDoc,toDoc,srcIDs,trgIDs'
ordering = 'ORDER BY rowid'

for link in algDBH.execute(f"SELECT {columns} from alignments {condition} {ordering}"):
    corpus  = link[0]
    version = link[1]
    fromDoc = link[2]
    toDoc   = link[3]
    srcIDs  = link[4]
    trgIDs  = link[5]
    
    srcSents = srcIDs.split()
    trgSents = trgIDs.split()

    srcText = []
    trgText = []

    for id in srcSents:
        # print(f"SELECT ID FROM sentindex WHERE corpus='{corpus}' AND version='{version}' AND document='{fromDoc}' AND sentID='{id}'")
        for row in srcIdxDBH.execute(f"SELECT ID FROM sentindex WHERE corpus='{corpus}' AND version='{version}' AND document='{fromDoc}' AND sentID='{id}'"):
            sentID = row[0]
            # print(f"SELECT sentence FROM sentences WHERE rowid='{sentID}'")
            for sent in srcDBH.execute(f"SELECT sentence FROM sentences WHERE rowid='{sentID}'"):
                srcText.append(sent[0])

    for id in trgSents:
        # print(f"SELECT ID FROM sentindex WHERE corpus='{corpus}' AND version='{version}' AND document='{toDoc}' AND sentID='{id}'")
        for row in trgIdxDBH.execute(f"SELECT ID FROM sentindex WHERE corpus='{corpus}' AND version='{version}' AND document='{toDoc}' AND sentID='{id}'"):
            sentID = row[0]
            # print(f"SELECT sentence FROM sentences WHERE rowid='{sentID}'")
            for sent in trgDBH.execute(f"SELECT sentence FROM sentences WHERE rowid='{sentID}'"):
                trgText.append(sent[0])


    # print(f"--{corpus}/{fromDoc}-{toDoc}/{srcIDs}-{trgIDs}------------------------------")
    print(f"-- {corpus}/{srcIDs}-{trgIDs} ------------------------------")
    print(' '.join(srcText))
    print(' '.join(trgText))


