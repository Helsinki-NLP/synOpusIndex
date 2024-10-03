#!/usr/bin/env python3

import sys
import sqlite3

dbfile = sys.argv[1]
con = sqlite3.connect(dbfile, timeout=7200)
cur = con.cursor()
cur.execute("CREATE TABLE IF NOT EXISTS sentences ( sentence TEXT UNIQUE PRIMARY KEY NOT NULL )")
con.commit()
cur.close()


buffer = []
buffersize = 100000
bufferCount = 0

while True:
    try:
        line = sys.stdin.readline()
        if line == '':
            break
        buffer.append(tuple([line.rstrip()]))
        if len(buffer) >= buffersize:
            con = sqlite3.connect(dbfile, timeout=7200)
            cur = con.cursor()
            cur.executemany("""INSERT OR IGNORE INTO sentences VALUES(?)""", buffer)
            con.commit()
            cur.close()
            buffer = []
        
            bufferCount += 1
            sys.stderr.write('.')
            if not bufferCount % 100:
                sys.stderr.write(f" {bufferCount} * {buffersize}\n")
            sys.stderr.flush()
    except:
        sys.stderr.write("Something wrong with the input. Ignore this line.\n")
        sys.stderr.flush()
        

# for line in sys.stdin:
#     buffer.append(tuple([line.rstrip()]))
#     if len(buffer) >= buffersize:
#         cur.executemany("""INSERT OR IGNORE INTO sentences VALUES(?)""", buffer)
#         con.commit()
#         buffer = []
        
#         bufferCount += 1
#         sys.stderr.write('.')
#         if not bufferCount % 100:
#             sys.stderr.write(f" {bufferCount} * {buffersize}\n")
#         sys.stderr.flush()



if len(buffer) > 0:
    con = sqlite3.connect(dbfile, timeout=7200)
    cur = con.cursor()
    cur.executemany("""INSERT OR IGNORE INTO sentences VALUES(?)""", buffer)
    con.commit()
    cur.close()
