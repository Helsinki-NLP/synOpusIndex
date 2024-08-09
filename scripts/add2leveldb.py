#!/usr/bin/env python3

import leveldb
import sys


db = leveldb.LevelDB(sys.argv[1])

sentID = 0
for line in sys.stdin:
    sentID += 1
    db.Put(line.rstrip().encode(),bytes(sentID))

    if not sentID % 50000:
        sys.stderr.write('.')
        sys.stderr.flush()
    if not sentID % 2500000:
        sys.stderr.write(f" {sentID}\n")
        sys.stderr.flush()

