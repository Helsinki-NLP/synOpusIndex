#!/usr/bin/env python3

import lmdb
import sys

env = lmdb.open(sys.argv[1], max_dbs=10)
sent_db = env.open_db(b'sentences')

sentID = 0
with env.begin(write=True) as txn:
    for line in sys.stdin:
        sentID += 1
        txn.put(line.rstrip().encode('utf-8'), bytes(sentID), db=sent_db)

        if not sentID % 50000:
            sys.stderr.write('.')
            sys.stderr.flush()
        if not sentID % 2500000:
            sys.stderr.write(f" {sentID}\n")
            sys.stderr.flush()

