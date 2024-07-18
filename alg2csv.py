#!/usr/bin/env python3

import sys
import xml.parsers.expat

fromDoc = ''
toDoc = ''


def start_element(name, attrs):
    global fromDoc
    global toDoc
    
    if name == 'linkGrp':
        if 'fromDoc' in attrs:
            fromDoc = attrs['fromDoc'].replace('.xml.gz','.xml')
        if 'toDoc' in attrs:
            toDoc = attrs['toDoc'].replace('.xml.gz','.xml')
    elif name == 'link':
        if 'xtargets' in attrs:
            link = attrs['xtargets'].split(';')
            alignScore = ''
            hunScore = ''
            timeOverlap = ''
            bicleanerScore = ''
            if 'score' in attrs:
                alignScore = attrs['score']
            if 'certainty' in attrs:
                hunScore = attrs['certainty']
            if 'overlap' in attrs:
                timeOverlap = attrs['overlap']
            if 'bicleaner' in attrs:
                alignScore = attrs['bicleanerScore']
            if 'type' in attrs:
                alignType = attrs['alignType']
            else:
                srcIDs = link[0].split()
                trgIDs = link[1].split()
                alignType = str(len(srcIDs)) + '-' + str(len(trgIDs))
            print(','.join([fromDoc,toDoc,link[0],link[1],alignType,alignScore,hunScore,timeOverlap,bicleanerScore]))


parser = xml.parsers.expat.ParserCreate()
parser.StartElementHandler = start_element
for line in sys.stdin:
    parser.Parse(line)
