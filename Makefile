#---------------------------------------------------------------------
# de-duplicate and index sentences in OPUS
#---------------------------------------------------------------------
#
# for moving the sentindex table into the sentence DB run:
#   sqlite3 fi.idx.db ".dump sentindex" | sqlite3 fi.db
#

SHELL := bash

include Makefile.def
include Makefile.submit


STORAGE_BASE = https://object.pouta.csc.fi/OPUS-

CSC_PROJECT      := project_2000661
HPC_MODULES      += allas parallel
ALLAS_CONF       := source /appl/opt/csc-cli-utils/allas-cli-utils/allas_conf -s
LOAD_STORAGE_ENV := module load allas && ${ALLAS_CONF} -k ${CSC_PROJECT}


## language settings

LANGPAIR ?= fi-sv
SRCLANG  := $(firstword $(subst -, ,${LANGPAIR}))
TRGLANG  := $(lastword $(subst -, ,${LANGPAIR}))
LANGUAGE ?= ${SRCLANG}


## directory with scripts and tools

SCRIPTDIR    := scripts/
INDEX_TMPDIR := ${TMPDIR}/index_tmp_${LANGPAIR}


## monolingual texts

ALL_MONO_URLS      := $(patsubst %,https:%,$(shell find ${OPUSRELEASE}/ -name statistics.yaml | \
			xargs grep 'mono/${LANGUAGE}.txt.gz' | cut -f4 -d:))
ALL_MONO_DEDUP     := $(patsubst ${STORAGE_BASE}%.txt.gz,${INDEX_TMPDIR}/%.dedup,${ALL_MONO_URLS})
ALL_MONO_IDX       := $(patsubst ${STORAGE_BASE}%.txt.gz,${INDEX_TMPDIR}/%.idx,${ALL_MONO_URLS})
ALL_MONO_DONE      := $(patsubst ${INDEX_TMPDIR}/%.dedup,done/%.done,${ALL_MONO_DEDUP})
ALL_MONO_IDXDONE   := $(patsubst ${INDEX_TMPDIR}/%.idx,done/%.idx.done,${ALL_MONO_IDX})
ALL_MONO_IDSDONE   := $(patsubst ${INDEX_TMPDIR}/%.idx,done/%.ids.done,${ALL_MONO_IDX})


## parallel texts

LINK_DB      := sqlite/${LANGPAIR}.db
ALL_ALG_URLS := $(patsubst %,https:%,$(shell find ${OPUSRELEASE}/ -name statistics.yaml | \
				xargs grep 'xml/${LANGPAIR}.xml.gz' | cut -f4 -d:))
ALL_ALG_DONE := $(patsubst ${STORAGE_BASE}%.xml.gz,done/%.done,${ALL_ALG_URLS})
ALL_LINK_DBS := $(subst /xml/,/,$(patsubst done/%.done,sqlite/%.db,${ALL_ALG_DONE}))


LINK_DB_MERGED        := $(patsubst %.db,%.merged,${ALL_LINK_DBS})
LINK_DB_LATEST_MERGED := $(sort $(shell echo "${LINK_DB_MERGED}" | tr ' ' "\n" | cut -f1,2,4 -d/))





## files that we do not want to delete even if some kind of make target fails

.PRECIOUS: 	${LANGUAGE}.db \
		${LANGUAGE}.ids.db \
		${LANGUAGE}.fts5.db \
		${LANGUAGE}.idx.db \
		${LANGPAIR}.db \
		${LANGUAGE}.idx.gz \
		${LANGUAGE}.dedup.gz \
		${LINK_DB}


## files that we want to keep even if they are only build as pre-requisites in implicit rules

.NOTINTERMEDIATE: ${ALL_LINK_DBS}


## intermediate files that can be deleted after finishing up

.INTERMEDIATE: ${ALL_MONO_DEDUP}
.INTERMEDIATE: ${ALL_MONO_IDX}



.PHONY: all
all: ${LANGPAIR}.db
	${MAKE} LANGUAGE=${SRCLANG} all-mono
	${MAKE} LANGUAGE=${TRGLANG} all-mono
	${MAKE} linkdb

.PHONY: all-mono
all-mono: ${LANGUAGE}.counts
	${MAKE} ${LANGUAGE}.dedup.gz ${LANGUAGE}.db
	${MAKE} ${LANGUAGE}.ids.db
	${MAKE} ${LANGUAGE}.fts5.db

.PHONY: all-links
all-links: ${LANGPAIR}.db
	${MAKE} ${LINK_DB}




.PHONY: linkdb
linkdb: ${LINK_DB}



old-linkdb: ${LANGPAIR}.linked.db



.PHONY: counts
counts: ${LANGUAGE}.counts

.PHONY: dedup
dedup: ${LANGUAGE}.dedup.gz



%-job:
	${MAKE} HPC_CORES=4 THREADS=4 HPC_MEM=16g HPC_TIME=72:00 HPC_DISK=1000 $(@:-job=).submit

%-largejob:
	${MAKE} HPC_CORES=8 THREADS=8 HPC_MEM=32g HPC_TIME=72:00 HPC_DISK=3000 $(@:-largejob=).submit



## in case the flags for finishing sentence extraction
## and we don't want to re-run all deduplication for all corpora
## --> run this temporary target to create all flags for all corpora
## --> WARNING: now you don't know whether things have been done

tmp-dedup-fix:
	touch ${ALL_MONO_DONE}
	touch ${LANGUAGE}.dedup.gz



## TODO: upload targets are not up-to-date!

SWIFT_PARAMS = --use-slo --segment-size 5G --changed --skip-identical

STORAGE_FILES = ${LANGUAGE}.dedup.gz ${LANGUAGE}.db ${LANGUAGE}.ids.db ${LANGUAGE}.fts5.db ${LANGPAIR}.db sqlite


.PHONY: upload
upload:
	which a-put
	${LOAD_STORAGE_ENV} && \
	swift upload OPUS-index ${SWIFT_PARAMS} ${STORAGE_FILES}
	rm -f index.txt
	${MAKE} index.txt
	find done -name '${LANGUAGE}.done' | xargs -n 500 git add
	find done -name '${LANGPAIR}.done' | xargs -n 500 git add
	find sqlite -name '${LANGPAIR}.merged' | xargs -n 500 git add
	git add ${LANGUAGE}.counts index.txt


.PHONY: upload-all
upload-all:
	which a-put
	${LOAD_STORAGE_ENV} && \
	swift upload OPUS-index ${SWIFT_PARAMS} sqlite *.dedup.gz *.db
	rm -f index.txt
	${MAKE} index.txt
	find done -name '*.done' | xargs -n 500 git add
	find sqlite -name '*.merged' | xargs -n 500 git add
	git add *.counts index.txt


index.txt:
	which a-get
	swift list OPUS-index | grep '\.dedup.gz$$' | \
		sed 's#^#https://object.pouta.csc.fi/OPUS-index/#' > $@
	swift list OPUS-index | grep '\.db$$'       | \
		sed 's#^#https://object.pouta.csc.fi/OPUS-index/#' >> $@
	swift list OPUS-index | grep '\.idx.gz$$'   | \
		sed 's#^#https://object.pouta.csc.fi/OPUS-index/#' >> $@


index-filesize.txt:
	which a-get
	${LOAD_STORAGE_ENV} && rclone ls allas:OPUS-index | grep  '\.dedup.gz$$'  > $@
	${LOAD_STORAGE_ENV} && rclone ls allas:OPUS-index | grep  '\.db$$'       >> $@
	${LOAD_STORAGE_ENV} && rclone ls allas:OPUS-index | grep  '\.idx.gz$$'   >> $@




.PHONY: job-puhti
job-puhti:
	${MAKE} HPC_MEM=16g HPC_CORES=8 CORES=4 THREADS=4 HPC_DISK=1000 all-mono.submit

.PHONY: job-puhti
dedup-job-puhti:
	${MAKE} HPC_MEM=16g HPC_CORES=8 CORES=4 THREADS=4 HPC_DISK=1000 dedup.submit


big-job-puhti:
	${MAKE} HPC_MEM=32g HPC_CORES=16 CORES=8 THREADS=8 HPC_DISK=3000 all-mono.submit



## line (=sentence) count and word count
${LANGUAGE}.counts: ${ALL_MONO_DONE}
	${MAKE} ${LANGUAGE}.dedup.gz
	${GZIP} -cd ${LANGUAGE}.dedup.gz | wc -lw |\
	sed 's/^ *//;s/  */	/g' > $@

# counts-from-storage:
# 	for l in aa ca cs de en es et eu fi fr ga nb nds nn no se sk sv; do \
# 	  wget -qq -O - ${STORAGE_BASE}index/$$l.dedup.gz |\
# 	  ${GZIP} -cd | wc -lw | sed 's/^ *//;s/  */	/g' > $$l.counts; \
# 	done




CREATE_TABLE        := CREATE TABLE IF NOT EXISTS
CREATE_INDEX        := CREATE INDEX IF NOT EXISTS
CREATE_UNIQUE_INDEX := CREATE UNIQUE INDEX IF NOT EXISTS
INSERT_INTO         := INSERT OR IGNORE INTO

MODIFY_DB_DUMP      := sed 's/CREATE TABLE/${CREATE_TABLE}/;s/INSERT/INSERT OR IGNORE/;'

## merge all deduplicated files
## download the old dedup file in case it exists
## and no local file exists
${LANGUAGE}.dedup.gz: ${ALL_MONO_DONE}
	${MAKE} STORED_FILE=$@ retrieve
	mkdir -p $(dir ${INDEX_TMPDIR}/$@)
	if [ -e $@ ]; then rsync $@ ${INDEX_TMPDIR}/$@; fi
	if [ `find ${INDEX_TMPDIR} -name '*.dedup' | wc -l` -gt 0 ]; then \
	  if [ -e ${INDEX_TMPDIR}/$@ ]; then \
	    echo "merge all corpora with ${LANGUAGE}.dedup.gz"; \
	    find ${INDEX_TMPDIR} -name '*.dedup' |\
	    xargs ${MERGE} <(${GZIP} -cd ${INDEX_TMPDIR}/$@) | ${GZIP} -c > $@; \
	  else \
	    echo "merge all corpora into ${LANGUAGE}.dedup.gz"; \
	    find ${INDEX_TMPDIR} -name '*.dedup' |\
	    xargs ${MERGE} | ${GZIP} -c > $@; \
	  fi \
	fi

## sqlite database of all sentences

${LANGUAGE}.db: ${LANGUAGE}.dedup.gz
	${MAKE} STORED_FILE=$@ retrieve
	mkdir -p $(dir ${INDEX_TMPDIR}/$@)
	if [ -e $@ ]; then rsync $@ ${INDEX_TMPDIR}/$@; fi
	${GZIP} -cd < $< | ${SCRIPTDIR}sent2sqlite.py ${INDEX_TMPDIR}/$@
	mv -f ${INDEX_TMPDIR}/$@ $@
	echo "PRAGMA journal_mode=WAL" | sqlite3 $@




## create a full-text search database from the sentence DB
## TODO: fts5 DB should depend on sentence DB,
##       but we don't want to redo dedup.gz and the sentence DB if not needed

%.fts5.db: %.db
	${MAKE} STORED_FILE=$@ retrieve
	mkdir -p $(dir ${INDEX_TMPDIR}/$@)
	if [ -e $@ ]; then rsync $@ ${INDEX_TMPDIR}/$@; fi
	echo "CREATE VIRTUAL TABLE IF NOT EXISTS sentences USING FTS5(sentence)" | sqlite3 ${INDEX_TMPDIR}/$@
	echo "ATTACH DATABASE '$(@:.fts5.db=.db)' as org; \
	      ${INSERT_INTO} sentences SELECT * FROM org.sentences;" | sqlite3 ${INDEX_TMPDIR}/$@
	mv -f ${INDEX_TMPDIR}/$@ $@





## sqlite database of all alignments

${LANGPAIR}.db: ${ALL_ALG_DONE}
	@if [ -e ${INDEX_TMPDIR}/$@ ]; then \
	  mv -f ${INDEX_TMPDIR}/$@ $@; \
	  echo "${CREATE_TABLE} aligned_corpora ( corpus TEXT, version TEXT)" | sqlite3 $@; \
	  echo "${CREATE_UNIQUE_INDEX} idx_aligned_corpora ON aligned_corpora ( corpus, version )" \
		| sqlite3 $@; \
	  echo "${INSERT_INTO} aligned_corpora SELECT DISTINCT corpus,version FROM bitexts" \
		| sqlite3 $@; \
	fi


.INTERMEDIATE: ${INDEX_TMPDIR}/${LANGPAIR}.db

${INDEX_TMPDIR}/${LANGPAIR}.db:
	${MAKE} STORED_FILE=${LANGPAIR}.db retrieve
	mkdir -p $(dir $@)
	if [ -e $(notdir $@) ]; then rsync $(notdir $@) $@; fi
	@if [ ! -e $@ ]; then \
	  echo "${CREATE_TABLE} bitexts ( corpus TEXT, version TEXT, fromDoc TEXT, toDoc TEXT )" \
		| sqlite3 $@; \
	  echo "${CREATE_UNIQUE_INDEX} idx_bitexts ON bitexts ( corpus, version, fromDoc, toDoc )" \
		| sqlite3 $@; \
	  echo "${CREATE_TABLE} links ( bitextID, srcIDs TEXT, trgIDs TEXT, alignType TEXT, \
			                alignerScore REAL, cleanerScore REAL)" \
		| sqlite3 $@; \
	  echo "${CREATE_UNIQUE_INDEX} idx_links ON links ( bitextID, srcIDs, trgIDs )" \
		| sqlite3 $@; \
	  echo "${CREATE_INDEX} idx_bitextid ON links ( bitextID )" | sqlite3 $@; \
	  echo "${CREATE_INDEX} idx_aligntype ON links ( bitextID, alignType )" | sqlite3 $@; \
	  echo "PRAGMA journal_mode=WAL" | sqlite3 $@; \
	fi

${ALL_ALG_DONE}: ${INDEX_TMPDIR}/${LANGPAIR}.db
	@echo "processing $(@:.done=.xml.gz)"
	@wget -qq -O - $(patsubst done/%.done,${STORAGE_BASE}%.xml.gz,$@) \
	| gzip -cd \
	| ${SCRIPTDIR}alg2sqlite.py $< $(word 2,$(subst /, ,$@)) $(word 3,$(subst /, ,$@))
	@mkdir -p $(dir $@)
	@touch $@










##--------------------------------------------------------------------------------
## database of linked source and target sentences
##  --> maps internal sentence IDs to internal link IDs
##
## (1) create individual link DBs for each corpus release
## (2) merge them into one link DB for the current language pair
##--------------------------------------------------------------------------------


## individual linkDBs as pre-requisites
## merging into on link DB does not seem to work with multiple threads
## --> call the PHONY target merge-latest-linkdbs below with a single-threaded make call
##     instead of adding ${LINK_DB_LATEST_MERGED} as pre-requisites
## --> merging takes place in temporary location
## --> move the link database back to the target location
## --> add bitext and aligned_corpora tables from the master bitext database
## --> finally, create indeces over bitexts and aligned_corpora

${LINK_DB}: ${LANGPAIR}.db ${ALL_LINK_DBS}
	${MAKE} -j1 merge-latest-linkdbs
	if [ -e ${TMP_LINK_DB} ]; then mv -f ${TMP_LINK_DB} $@; fi
	sqlite3 ${LANGPAIR}.db ".dump bitexts" | ${MODIFY_DB_DUMP} | sqlite3 $@
	sqlite3 ${LANGPAIR}.db ".dump aligned_corpora" | ${MODIFY_DB_DUMP} | sqlite3 $@
	echo "${CREATE_UNIQUE_INDEX} idx_bitexts ON bitexts (corpus,version,fromDoc,toDoc)" | sqlite3 $@
	echo "${CREATE_UNIQUE_INDEX} idx_corpora ON aligned_corpora (corpus,version)" | sqlite3 $@


## phony target to merge link tables from each corpus
## --> only the latest release will be added
## --> this makes updating very complicated because old data needs to be deleted

.PHONY: merge-latest-linkdbs
merge-latest-linkdbs: ${LINK_DB_LATEST_MERGED}
	@if [ -e ${TMP_LINK_DB} ]; then \
	  echo "cleanup and copy ${LINK_DB}"; \
	  echo "VACUUM;" | ${SQLITE3} ${TMP_LINK_DB}; \
	  rsync -av ${TMP_LINK_DB} ${LINK_DB}; \
	fi



## create individual link databases (one per corpus/version)
## --> pre-requisite databases will be copied to a temporary location
## --> this makes lookup much faster (assuming that the tmpdisk is a fast local disk)

LINKDB_PREREQUISITES := ${INDEX_TMPDIR}/linkdb/${LANGPAIR}.db \
			${INDEX_TMPDIR}/linkdb/${SRCLANG}.ids.db \
			${INDEX_TMPDIR}/linkdb/${TRGLANG}.ids.db

.INTERMEDIATE: ${LINKDB_PREREQUISITES}
${LINKDB_PREREQUISITES}: ${INDEX_TMPDIR}/linkdb/%: %
	mkdir -p $(dir $@)
	rsync -av $< $@


## add all links to the individual link databases
## do that in a temporary location and move the final database back to the target

# LINK2SQLITE = ${SCRIPTDIR}bitextlinks.py
LINK2SQLITE = ${SCRIPTDIR}links2sqlite.py

${ALL_LINK_DBS}: ${LINKDB_PREREQUISITES}
	@mkdir -p $(dir ${INDEX_TMPDIR}/$@)
	${LINK2SQLITE} $^ ${INDEX_TMPDIR}/$@ $(word 2,$(subst /, ,$@)) $(word 3,$(subst /, ,$@))
	@mkdir -p $(dir $@)
	mv -f ${INDEX_TMPDIR}/$@ $@



## initialize the global link database in local tmp dir with fast I/O
## declare this to be an intermediate file to remove it after finishing the process

TMP_LINK_DB := ${INDEX_TMPDIR}/${LINK_DB}
.INTERMEDIATE: ${TMP_LINK_DB}


## open with timeout to allow concurrent access
## but that still does not seem to work well (skip timeout?)
SQLITE3 = sqlite3 -cmd ".timeout 100000"

${TMP_LINK_DB}:
	${MAKE} STORED_FILE=${LINK_DB} retrieve
	mkdir -p $(dir $@)
	if [ -e ${LINK_DB} ]; then rsync -av ${LINK_DB} $@; fi
	@echo "${CREATE_TABLE} linkedsource ( sentID INTEGER, linkID INTEGER, bitextID INTEGER, PRIMARY KEY(linkID,sentID) )" | ${SQLITE3} $@
	@echo "${CREATE_TABLE} linkedtarget ( sentID INTEGER, linkID INTEGER, bitextID INTEGER, PRIMARY KEY(linkID,sentID) )" | ${SQLITE3} $@
	@echo "${CREATE_INDEX} idx_linkedsource_bitext ON linkedsource (bitextID,sentID)" | ${SQLITE3} $@
	@echo "${CREATE_INDEX} idx_linkedtarget_bitext ON linkedtarget (bitextID,sentID)" | ${SQLITE3} $@
	@echo "${CREATE_INDEX} idx_linkedsource_linkid ON linkedsource (linkID)" | ${SQLITE3} $@
	@echo "${CREATE_INDEX} idx_linkedtarget_linkid ON linkedtarget (linkID)" | ${SQLITE3} $@
	@echo "${CREATE_INDEX} idx_linkedsource_sentid ON linkedsource (sentID)" | ${SQLITE3} $@
	@echo "${CREATE_INDEX} idx_linkedtarget_sentid ON linkedtarget (sentID)" | ${SQLITE3} $@
	@echo "${CREATE_TABLE} links ( linkID INTEGER NOT NULL PRIMARY KEY, bitextID, \
                                       srcIDs TEXT, trgIDs TEXT, srcSentIDs TEXT, trgSentIDs TEXT, \
                                       alignType TEXT, alignerScore REAL, cleanerScore REAL)" | ${SQLITE3} $@
	@echo "${CREATE_UNIQUE_INDEX} idx_links ON links ( bitextID, srcIDs, trgIDs )" | ${SQLITE3} $@
	@echo "${CREATE_INDEX} idx_aligntype ON links ( bitextID, alignType )" | ${SQLITE3} $@
	@echo "${CREATE_INDEX} idx_bitextid ON links ( bitextID )" | ${SQLITE3} $@
	@echo "PRAGMA journal_mode=WAL" | ${SQLITE3} $@



## merge links into the global link database
## --> only the latest release will be kept
## --> this makes updating quite complicated
##
## - check for the latest release in the corpus yaml file
## - remove links from previously merged releases
## - add links from the latest release
## - mark the corpus as done (merged flag)

${LINK_DB_LATEST_MERGED}: ${TMP_LINK_DB}
	@( c=$(word 2,$(subst /, ,$@)); \
	  l=`grep 'latest_release:' releases/$$c/info.yaml | cut -f2 -d' ' | xargs`; \
	  m=`find sqlite/$$c -mindepth 2 -name '${LANGPAIR}.merged' | cut -f3 -d/ | xargs`; \
	  for v in $$m; do \
	    if [ "$$l" != "$$v" ]; then \
	      echo "remove links for $$c/$$v/${LANGPAIR}"; \
	      echo "ATTACH DATABASE '${LANGPAIR}.db' as b;\
		    DELETE FROM links WHERE bitextID IN \
			( SELECT DISTINCT rowid FROM b.bitexts WHERE corpus='$$c' AND version='$$v' ); \
		    DELETE FROM linkedsource WHERE bitextID IN \
			( SELECT DISTINCT rowid FROM b.bitexts WHERE corpus='$$c' AND version='$$v' ); \
		    DELETE FROM linkedtarget WHERE bitextID IN \
			( SELECT DISTINCT rowid FROM b.bitexts WHERE corpus='$$c' AND version='$$v' );" \
	  	    | ${SQLITE3} ${TMP_LINK_DB}; \
	      rm -f sqlite/$$c/$$v/${LANGPAIR}.merged; \
	    fi \
	  done; \
	  if [ ! -e sqlite/$$c/$$l/${LANGPAIR}.merged ]; then \
	    echo "add links for $$c/$$l/${LANGPAIR}"; \
	    if [ ! -e sqlite/$$c/$$l/${LANGPAIR}.db ]; then \
		${MAKE} sqlite/$$c/$$l/${LANGPAIR}.db; \
	    fi; \
	    if [ -e sqlite/$$c/$$l/${LANGPAIR}.db ]; then \
	      rsync sqlite/$$c/$$l/${LANGPAIR}.db ${INDEX_TMPDIR}/$$c-$$l-${LANGPAIR}.db; \
	      echo "ATTACH DATABASE '${INDEX_TMPDIR}/$$c-$$l-${LANGPAIR}.db' as l; \
		    ${INSERT_INTO} links SELECT * FROM l.links; \
		    ${INSERT_INTO} linkedsource SELECT * FROM l.linkedsource; \
		    ${INSERT_INTO} linkedtarget SELECT * FROM l.linkedtarget;" \
	      | ${SQLITE3} ${TMP_LINK_DB}; \
	      rm -f ${INDEX_TMPDIR}/$$c-$$l-${LANGPAIR}.db; \
	      touch sqlite/$$c/$$l/${LANGPAIR}.merged; \
	    else \
	      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"; \
	      echo "!!!!!!!! PROBLEM WITH sqlite/$$c/$$l/${LANGPAIR}.db"; \
	      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"; \
	    fi \
	  fi )
	@touch $@

## should we sync back each time a DB has been merged?
## --> more failsafe to get the temporary DB back in place
## --> problematic in parallel threads?
## --> time-consuming
#
#	@rsync ${TMP_LINK_DB} ${LINK_DB}






## OBSOLETE ##
##
## 2.2a: merge all individual link databases with the global link DB in tmp dir
##  ---> all releases of all corpora are merged into one DB
##  ---> a lot of repeated sentence alignments will be included
##  ---> merge only the latest release with the target below instead (merge-latest-linkdbs)

.PHONY: merge-all-linkdbs
merge-all-linkdbs: ${LINK_DB_MERGED}

${LINK_DB_MERGED}: %.merged: %.db ${TMP_LINK_DB}
	@mkdir -p $(dir ${INDEX_TMPDIR}/$<)
	@rsync $< ${INDEX_TMPDIR}/$<.tmp
	@echo "PRAGMA journal_mode=WAL" | ${SQLITE3} ${TMP_LINK_DB}
	${SQLITE3} ${INDEX_TMPDIR}/$<.tmp ".dump links" | ${MODIFY_DB_DUMP} | ${SQLITE3} ${TMP_LINK_DB}
	${SQLITE3} ${INDEX_TMPDIR}/$<.tmp ".dump linkedsource" | ${MODIFY_DB_DUMP} | ${SQLITE3} ${TMP_LINK_DB}
	${SQLITE3} ${INDEX_TMPDIR}/$<.tmp ".dump linkedtarget" | ${MODIFY_DB_DUMP} | ${SQLITE3} ${TMP_LINK_DB}
	@rm -f ${INDEX_TMPDIR}/$<.tmp
	@rsync ${TMP_LINK_DB} ${LINK_DB}
	@touch $@





##--------------------------------------------------------------------------------
## database of all bitexts and aligned corpra
## (copy from tables in alignment database)
##
## ?OBSOLETE? - bitext tables are also in the link database
##--------------------------------------------------------------------------------

BITEXT_DB := sqlite/${LANGPAIR}.bitexts.db

bitext-db: ${BITEXT_DB}

${BITEXT_DB}: ${LANGPAIR}.db
	mkdir -p $(dir $@)
	rm -f $@.tmp
	sqlite3 ${LANGPAIR}.db ".dump bitexts" | sqlite3 $@.tmp
	sqlite3 ${LANGPAIR}.db ".dump aligned_corpora" | sqlite3 $@.tmp
	echo "${CREATE_UNIQUE_INDEX} idx_bitexts ON bitexts ( corpus, version, fromDoc, toDoc )" \
	| sqlite3 $@.tmp
	echo "${CREATE_UNIQUE_INDEX} idx_corpora ON aligned_corpora ( corpus, version )" | sqlite3 $@.tmp
	mv -f $@.tmp $@



##------------------------------------------------------------------------------------
## sentence index that maps corpus-specific indeces to the ID in the sentence DB
##------------------------------------------------------------------------------------

sentence-index: ${LANGUAGE}.ids.db


TMP_SENTENCE_DB := ${INDEX_TMPDIR}/${LANGUAGE}-sentences.db
.INTERMEDIATE: ${TMP_SENTENCE_DB}

${LANGUAGE}.ids.db: ${ALL_MONO_IDSDONE}
	if [ -e ${TMP_SENTENCE_DB} ]; then mv -f ${TMP_SENTENCE_DB} ${LANGUAGE}.db; fi
	if [ -e ${INDEX_TMPDIR}/$@ ]; then mv -f ${INDEX_TMPDIR}/$@ $@; fi


## separate makefile targets for source and target language
## if necessary (i.e. LANGUAGE is not set to either language)

ifneq (${LANGUAGE},${SRCLANG})
${SRCLANG}.ids.db:
	${MAKE} LANGUAGE=${SRCLANG} $@
endif

ifneq (${LANGUAGE},${TRGLANG})
${TRGLANG}.ids.db:
	${MAKE} LANGUAGE=${TRGLANG} $@
endif



${ALL_MONO_IDSDONE}: ${INDEX_TMPDIR}/${LANGUAGE}.ids.db ${TMP_SENTENCE_DB}
	@echo "process $@"
	@${SCRIPTDIR}sentid2sqlite.py \
		-i $< \
		-c $(word 2,$(subst /, ,$@)) \
		-r $(word 3,$(subst /, ,$@)) \
		-l ${LANGUAGE} \
		-d ${TMP_SENTENCE_DB}
	@mkdir -p $(dir $@)
	@touch $@




.INTERMEDIATE: ${INDEX_TMPDIR}/${LANGUAGE}.ids.db
${INDEX_TMPDIR}/${LANGUAGE}.ids.db:
	${MAKE} STORED_FILE=$(notdir $@) retrieve
	mkdir -p $(dir $@)
	if [ -e $(notdir $@) ]; then rsync -av $(notdir $@) $@; fi
	echo "${CREATE_TABLE} documents ( corpus, version, document )" | sqlite3 $@
	echo "${CREATE_UNIQUE_INDEX} idx_documents ON documents (corpus,version,document)" | sqlite3 $@
	echo "${CREATE_TABLE} sentids ( id INTEGER, docID INTEGER, sentID TEXT)" | sqlite3 $@
	echo "${CREATE_UNIQUE_INDEX} idx_sentids ON sentids ( docID, sentID)" | sqlite3 $@
# 	echo "CREATE INDEX idx_id ON sentids (id)" | sqlite3 $@


ifneq (${LANGUAGE},${SRCLANG})
.INTERMEDIATE: ${INDEX_TMPDIR}/${SRCLANG}.ids.db
${INDEX_TMPDIR}/${SRCLANG}.ids.db:
	${MAKE} LANGUAGE=${SRCLANG} $@
endif

ifneq (${LANGUAGE},${TRGLANG})
.INTERMEDIATE: ${INDEX_TMPDIR}/${TRGLANG}.ids.db
${INDEX_TMPDIR}/${TRGLANG}.ids.db:
	${MAKE} LANGUAGE=${TRGLANG} $@
endif



${TMP_SENTENCE_DB}:
	mkdir -p $(dir $@)
	rsync ${LANGUAGE}.db $@



## misc target: add another index over internal sentence IDs
## TODO: do we need that? (takes quite some space)

SENTIDS_DBS = $(patsubst %.ids.db,%.sentids.db,$(wildcard *.ids.db))

add-sentid-index: ${SENTIDS_DBS}

%.sentids.db:
	mkdir -p ${INDEX_TMPDIR}
	cp $(@:.sentids.db=.ids.db) ${INDEX_TMPDIR}/$@
	echo "CREATE INDEX idx_id ON sentids (id)" | sqlite3 ${INDEX_TMPDIR}/$@
	mv -f ${INDEX_TMPDIR}/$@ $@




##-------------------------------------------------------------------------
## OLD format: all in one table also including parID and sentence length
## --> this grows big quite quickly
##-------------------------------------------------------------------------

${LANGUAGE}.idx.db: ${LANGUAGE}.idx.gz
	${MAKE} STORED_FILE=$@ retrieve
	mkdir -p $(dir ${INDEX_TMPDIR}/$@)
	if [ -e $@ ]; then rsync $@ ${INDEX_TMPDIR}/$@; fi
	echo "${CREATE_TABLE} sentindex ( id, corpus, version, document, parID, sentID, length)" \
	| sqlite3 ${INDEX_TMPDIR}/$@
	echo "create index idx_all on sentindex (corpus,version,document,sentID);" | sqlite3 ${INDEX_TMPDIR}/$@
	echo "create index idx_corpus on sentindex (corpus,version);" | sqlite3 ${INDEX_TMPDIR}/$@
	${GZIP} -cd < $< | tr "\t" ',' | sqlite3  ${INDEX_TMPDIR}/$@ ".import /dev/stdin sentindex --csv"
	rsync ${INDEX_TMPDIR}/$@ $@

## merge index files into the existing list

${LANGUAGE}.idx.gz: ${ALL_MONO_IDXDONE}
	${MAKE} STORED_FILE=$@ retrieve
	mkdir -p $(dir ${INDEX_TMPDIR}/$@)
	if [ -e $@ ]; then rsync $@ ${INDEX_TMPDIR}/$@; fi
	if [ -e ${INDEX_TMPDIR}/$@ ]; then \
	  find ${INDEX_TMPDIR} -name '*.idx' | xargs cat <(${GZIP} -cd ${INDEX_TMPDIR}/$@) | ${GZIP} -c > $@; \
	else \
	  find ${INDEX_TMPDIR} -name '*.idx' | xargs cat | ${GZIP} -c > $@; \
	fi
	if [ -e ${TMP_SENTENCE_DB} ]; then rsync ${TMP_SENTENCE_DB} ${LANGUAGE}.db; fi

## create temporary index files for a specific corpus

${INDEX_TMPDIR}/%.idx: ${TMP_SENTENCE_DB}
	mkdir -p ${dir $@}
	${SCRIPTDIR}opus_sentid_index.py \
		-c $(word 1,$(subst /, ,$(patsubst ${INDEX_TMPDIR}/%.idx,%,$@))) \
		-r $(word 2,$(subst /, ,$(patsubst ${INDEX_TMPDIR}/%.idx,%,$@))) \
		-l ${LANGUAGE} \
		-d ${TMP_SENTENCE_DB} > $@
	if [ -e $(notdir $@).db ]; then \
	  tr "\t" ',' < $@ | sqlite3 $(notdir $@).db ".import /dev/stdin sentindex --csv"; \
	fi

${ALL_MONO_IDXDONE}: done/%.idx.done: ${INDEX_TMPDIR}/%.idx
	mkdir -p $(dir $@)
	touch $@



##---------------------------------
## map old into the new new format
##---------------------------------

SENTINDEX_VIEW = CREATE VIEW sentindex (id, corpus, version, document, parID, sentID, length) \
			AS SELECT id, corpus, version, document, parID, sentID, length \
			FROM sentids INNER JOIN documents ON documents.rowid = sentids.docID

SENTINDEX_INSERT_TRIGGER = CREATE TRIGGER insert_sentid \
		INSTEAD OF INSERT ON sentindex \
		BEGIN \
		  INSERT OR IGNORE INTO documents(corpus,version,document) \
			VALUES (NEW.corpus,NEW.version,NEW.document); \
		  INSERT INTO sentids(docID, id, parID, sentID, length) \
			VALUES ( ( SELECT rowid FROM documents \
				   WHERE corpus=NEW.corpus AND version=NEW.version AND document=NEW.document ), \
				 NEW.id, NEW.parID, NEW.sentID, NEW.length ); \
		END

${LANGUAGE}-new.idx.db:
	echo "${CREATE_TABLE} documents ( corpus, version, document )" | sqlite3 $@
	echo "CREATE UNIQUE INDEX idx_documents ON documents (corpus,version,document)" | sqlite3 $@
	echo "${CREATE_TABLE} sentids ( id INTEGER, docID INTEGER, parID TEXT, sentID TEXT, length INTEGER)" | sqlite3 $@
	echo "CREATE UNIQUE INDEX idx_sentids ON sentids ( docID, sentID)" | sqlite3 $@
	echo "${SENTINDEX_VIEW}" | sqlite3 $@
	echo "${SENTINDEX_INSERT_TRIGGER}" | sqlite3 $@
	sqlite3 ${LANGUAGE}.idx.db ".dump sentindex" | sqlite3 $@ >$@.out 2>$@.err

##---------------------------------
## end of temporary fix to map old index to new format
##---------------------------------







##------------------------------------------------------------------------------------
## convert OPUS data into jsonl format
##------------------------------------------------------------------------------------

ALL_MONO_JSONL     := $(patsubst ${STORAGE_BASE}%.txt.gz,${INDEX_TMPDIR}/%.jsonl,${ALL_MONO_URLS})
ALL_MONO_JSONLDONE := $(patsubst ${INDEX_TMPDIR}/%.jsonl,done/%.jsonl.done,${ALL_MONO_JSONL})

.PHONY: jsonl
jsonl: ${LANGUAGE}.jsonl.gz

print-jsonl:
	@echo "${ALL_MONO_JSONLDONE}" | tr ' ' "\n"



## jsonl format

${LANGUAGE}.jsonl.gz: ${ALL_MONO_JSONLDONE}
	${MAKE} STORED_FILE=$@ retrieve
	mkdir -p $(dir ${INDEX_TMPDIR}/$@)
	if [ -e $@ ]; then rsync $@ ${INDEX_TMPDIR}/$@; fi
	if [ -e ${INDEX_TMPDIR}/$@ ]; then \
	  find ${INDEX_TMPDIR} -name '*.jsonl' | xargs cat <(${GZIP} -cd ${INDEX_TMPDIR}/$@) | ${GZIP} -c > $@; \
	else \
	  find ${INDEX_TMPDIR} -name '*.jsonl' | xargs cat | ${GZIP} -c > $@; \
	fi


${ALL_MONO_JSONLDONE}: done/%.jsonl.done: ${INDEX_TMPDIR}/%.jsonl
	mkdir -p $(dir $@)
	touch $@


#	${SCRIPTDIR}opus_get_documents.py -j -sp \

${INDEX_TMPDIR}/%.jsonl:
	mkdir -p ${dir $@}
	${SCRIPTDIR}opus_get_documents.py -j \
		-c $(word 1,$(subst /, ,$(patsubst ${INDEX_TMPDIR}/%.jsonl,%,$@))) \
		-r $(word 2,$(subst /, ,$(patsubst ${INDEX_TMPDIR}/%.jsonl,%,$@))) \
		-l ${LANGUAGE} > $@


## unicode cleanup

# FIX_UNICODE := perl -CS -pe 'tr[\x{9}\x{A}\x{D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}][]cd;'
FIX_UNICODE := ${PARALLEL} ftfy


## download monolingual corpus and de-duplicate
#
# downloading and feeding directly into a pipe:
#	wget -O - -qq $(patsubst ${INDEX_TMPDIR}/%.dedup,${STORAGE_BASE}%.txt.gz,$@) |

${INDEX_TMPDIR}/%.dedup:
	mkdir -p ${dir $@}
	wget -qq -O $@.txt.gz $(patsubst ${INDEX_TMPDIR}/%.dedup,${STORAGE_BASE}%.txt.gz,$@)
	${GZIP} -cd < $@.txt.gz | ${FIX_UNICODE} | ${SORT} -u  > $@
	rm -f $@.txt.gz
	if [ -e $(notdir $(@:.dedup=.db)) ]; then \
	  if [ -s $@ ]; then \
	    cat $@ | ${SCRIPTDIR}sent2sqlite.py $(notdir $(@:.dedup=.db)); \
	  fi \
	fi


${ALL_MONO_DONE}: done/%.done: ${INDEX_TMPDIR}/%.dedup
	mkdir -p $(dir $@)
	touch $@





## retrieve a file from allas if it exists
## and sync it to the temporary file location as well

retrieve:
	@if [ ! -e ${STORED_FILE} ]; then \
	  if [ `grep '${STORED_FILE}' index.txt | wc -l` -gt 0 ]; then \
	    echo "download ${STORED_FILE}"; \
	    wget -qq ${STORAGE_BASE}index/${STORED_FILE}; \
	  fi \
	fi
#	mkdir -p ${INDEX_TMPDIR}
#	if [ -e ${STORED_FILE} ]; then \
#	  rsync ${STORED_FILE} ${INDEX_TMPDIR}/${STORED_FILE}; \
#	fi





# retrieve: ${INDEX_TMPDIR}/${STORED_FILE}

# ${INDEX_TMPDIR}/${STORED_FILE}:
# 	mkdir -p ${INDEX_TMPDIR}
# 	if [ ! -e ${STORED_FILE} ]; then \
# 	  if [ `grep '${STORED_FILE}' index.txt | wc -l` -gt 0 ]; then \
# 	    echo "download ${STORED_FILE}"; \
# 	    wget -qq ${STORAGE_BASE}index/${STORED_FILE}; \
# 	  fi \
# 	fi
# 	if [ -e ${STORED_FILE} ]; then \
# 	  rsync ${STORED_FILE} $@; \
# 	fi





## create MCDB index databases
## OBSOLETE?

.PHONY: sent2id
sent2id: ${LANGUAGE}.sent2id.db

%.sent2id.db: %.dedup.gz
	mkdir -p ${INDEX_TMPDIR}
	${GZIP} -cd $< | ${SCRIPTDIR}add2mcdb.pl ${INDEX_TMPDIR}/$(notdir $@)
	mv -f ${INDEX_TMPDIR}/$(notdir $@) $@

%.id2sent.db: %.dedup.gz
	mkdir -p ${INDEX_TMPDIR}
	${GZIP} -cd $< | ${SCRIPTDIR}add2index.pl ${INDEX_TMPDIR}/$(notdir $@)
	mv -f ${INDEX_TMPDIR}/$(notdir $@) $@







## test targets


de.CCMatrix-v1.idx: de.sent2id.db
	${SCRIPTDIR}opus_sentid_index.pl -c CCMatrix -r v1 -l de -d $< > $@

fi.OpenSubtitles-v2018.idx: fi.sent2id.db
	${SCRIPTDIR}opus_sentid_index.pl -c OpenSubtitles -r v2018 -l fi -d $< > $@

sv.OpenSubtitles-v2018.idx: sv.sent2id.db
	${SCRIPTDIR}opus_sentid_index.pl -c OpenSubtitles -r v2018 -l sv -d $< > $@

de.OpenSubtitles-v2018.idx: de.sent2id.db
	${SCRIPTDIR}opus_sentid_index.pl -c OpenSubtitles -r v2018 -l de -d $< > $@

fi.Europarl-v8.idx: fi.sent2id.db
	${SCRIPTDIR}opus_sentid_index.pl -c Europarl -r v8 -l fi -d $< > $@

sv.Europarl-v8.idx: sv.sent2id.db
	${SCRIPTDIR}opus_sentid_index.pl -c Europarl -r v8 -l sv -d $< > $@


sv.OpenSubtitles-v2018.idx2: sv.sent2id.db
	cp $< ${LOCAL_SCRATCH}/$<
	${SCRIPTDIR}opus_sentid_index.pl -c OpenSubtitles -r v2018 -l sv -d ${LOCAL_SCRATCH}/$< > $@

sv.OpenSubtitles-v2018.idx3:
	cp sv.db ${LOCAL_SCRATCH}/sv.db
	${SCRIPTDIR}opus_sentid_index.py -c OpenSubtitles -r v2018 -l sv -d ${LOCAL_SCRATCH}/sv.db > $@


# en.dedup.new.gz:
# 	gzip -cd en.dedup.gz | parallel --pipe --keep-order -q ${FIX_UNICODE} | gzip -c > $@

