#---------------------------------------------------------------------
# de-duplicate and index sentences in OPUS
#---------------------------------------------------------------------

include Makefile.submit


## language settings
##   LANGPAIR = language pair using original OPUS language codes
##   ISO_SRC2 = source language (original OPUS language code)
##   ISO_TRG2 = target language (original OPUS language code)

LANGPAIR ?= fi-sv
ISO_SRC2 := $(firstword $(subst -, ,${LANGPAIR}))
ISO_TRG2 := $(lastword $(subst -, ,${LANGPAIR}))


# normalized 3-letter code (macro-language if available)
# order of language codes may be reversed in LANGPAIR3!

ISO_SRC3  := $(shell iso639 -n -m ${ISO_SRC2})
ISO_TRG3  := $(shell iso639 -n -m ${ISO_TRG2})
LANGPAIR3 := $(firstword $(sort ${ISO_SRC3} ${ISO_TRG3}))-$(lastword $(sort ${ISO_SRC3} ${ISO_TRG3}))
SRCLANG3  := $(firstword $(subst -, ,${LANGPAIR3}))
TRGLANG3  := $(lastword $(subst -, ,${LANGPAIR3}))


#-----------------------------------------------------------------------
# IMPORTANT: if the 3-letter codes are in reverse alphabetical order
#            then we need to add the reverse-alignment flag!
#            and we also need to reverse the languages in the linkDB's
#-----------------------------------------------------------------------

ifneq (${LANGPAIR3},${ISO_SRC3}-${ISO_TRG3})
  SRCLANG = ${ISO_TRG2}
  TRGLANG = ${ISO_SRC2}
  ALG2SQLITE = ${SCRIPTDIR}alg2sqlite.py -r
else
  SRCLANG = ${ISO_SRC2}
  TRGLANG = ${ISO_TRG2}
  ALG2SQLITE = ${SCRIPTDIR}alg2sqlite.py
endif


LANGUAGE        ?= ${SRCLANG}
LANGUAGE3       := $(shell iso639 -n -m ${LANGUAGE})
LINKDB_LANGPAIR := ${SRCLANG}-${TRGLANG}



## directory with scripts and tools

SCRIPTDIR    := scripts/
INDEX_TMPDIR := ${TMPDIR}/index_tmp_${LANGPAIR3}


OPUSRELEASE  := OPUS/corpus
STORAGE_BASE := https://object.pouta.csc.fi/OPUS-


##------------------------
## monolingual texts
##------------------------

ALL_MONO_URLS      := $(sort $(patsubst %,https:%,$(shell find ${OPUSRELEASE}/ -name statistics.yaml | \
							xargs grep 'mono/${LANGUAGE}.txt.gz' | cut -f4 -d:)))
ALL_MONO_DEDUP     := $(patsubst ${STORAGE_BASE}%.txt.gz,${INDEX_TMPDIR}/%.dedup,${ALL_MONO_URLS})
ALL_MONO_DONE      := $(patsubst ${INDEX_TMPDIR}/%.dedup,done/%.done,${ALL_MONO_DEDUP})
ALL_MONO_IDSDONE   := $(patsubst ${INDEX_TMPDIR}/%.dedup,done/%.ids.done,${ALL_MONO_DEDUP})


##------------------------
## parallel texts
##------------------------


ALL_ALG_URLS := $(sort $(patsubst %,https:%,$(shell find ${OPUSRELEASE}/ -name statistics.yaml | \
						xargs grep 'xml/${LANGPAIR}.xml.gz' | cut -f4 -d:)))
ALL_ALG_DONE := $(patsubst ${STORAGE_BASE}%.xml.gz,done/%.done,${ALL_ALG_URLS})
ALL_LINK_DBS := $(subst /xml/,/,$(patsubst done/%/${LANGPAIR}.done,sqlite/%/${LINKDB_LANGPAIR}.db,${ALL_ALG_DONE}))


## alignment databases
##
##   LINK_DB               = all alignments from all corpora (pointing to OPUS sentence IDs)
##   LATEST_LINK_DB        = links from latest releases (pointing to sentence index IDs)
##   LATEST_LINK_DB_MERGED = flags marking that the latest release has been merged

LINK_DB                := ${LANGPAIR3}.db
LATEST_LINK_DB        := sqlite/${LANGPAIR3}.db
LINK_DB_MERGED        := $(patsubst %.db,%.merged,${ALL_LINK_DBS})
LATEST_LINK_DB_MERGED := $(sort $(shell echo "${LINK_DB_MERGED}" | tr ' ' "\n" | cut -f1,2,4 -d/))


## monolingual datasets and databases
## use standardized 3-letter codes for language DBs

LANGUAGE_DEDUP      := ${LANGUAGE}.dedup.gz
LANGUAGE_SENT_DB    := ${LANGUAGE3}.db
LANGUAGE_FTS_DB     := ${LANGUAGE3}.fts5.db
LANGUAGE_IDX_DB     := ${LANGUAGE3}.ids.db
SRCLANG_IDX_DB      := ${SRCLANG3}.ids.db
TRGLANG_IDX_DB      := ${TRGLANG3}.ids.db


## files that we do not want to delete even if some kind of make target fails

.PRECIOUS: 	${LANGUAGE_SENT_DB} \
		${LANGUAGE_IDX_DB} \
		${LANGUAGE_FTS_DB} \
		${LINK_DB} \
		${LANGUAGE_DEDUP} \
		${LATEST_LINK_DB}


## files that we want to keep even if they are only build as pre-requisites in implicit rules

.NOTINTERMEDIATE: ${ALL_LINK_DBS}


## intermediate files that can be deleted after finishing up

.INTERMEDIATE: ${ALL_MONO_DEDUP}


.PHONY: all
all: ${LINK_DB}
	${MAKE} LANGUAGE=${SRCLANG} all-mono
	${MAKE} LANGUAGE=${TRGLANG} all-mono
	${MAKE} linkdb

.PHONY: all-mono
all-mono: stats/${LANGUAGE}.counts
	${MAKE} ${LANGUAGE_DEDUP} ${LANGUAGE_SENT_DB}
	${MAKE} ${LANGUAGE_IDX_DB}
	${MAKE} ${LANGUAGE_FTS_DB}

.PHONY: all-links
all-links: ${LINK_DB}
	${MAKE} ${LATEST_LINK_DB}


.PHONY: linkdb
linkdb: ${LATEST_LINK_DB}




HPLT_LANGPAIRS = ar-en bs-en ca-en en-et en-eu en-fi en-ga en-gl en-hi en-hr en-is en-mk en-mt en-nn en-sq en-sr en-sw en-zh_Hant cmn_Hant-en cmn-en

hplt-all:
	for l in ${HPLT_LANGPAIRS}; do ${MAKE} LANGPAIR=$$l all; done



.PHONY: counts
counts: stats/${LANGUAGE}.counts

.PHONY: dedup
dedup: ${LANGUAGE_DEDUP}



rename-linkdbs:
	for d in $(wildcard sqlite/*-*.db); do \
	  l=`echo $$d | cut -f2 -d/ | cut -f1 -d. | xargs iso639 -m -n -p`; \
	  n="sqlite/$$l.db"; \
	  if [ $$n != $$d ]; then \
	    if [ ! -e $$n ]; then \
	      mv $$d $$n; \
	    fi \
	  fi \
	done
	for d in $(wildcard *-*.db); do \
	  l=`echo $$d | cut -f1 -d. | xargs iso639 -m -n -p`; \
	  n="$$l.db"; \
	  if [ $$n != $$d ]; then \
	    if [ ! -e $$n ]; then \
	      mv $$d $$n; \
	    fi \
	  fi \
	done




## in case the flags for finishing sentence extraction
## and we don't want to re-run all deduplication for all corpora
## --> run this temporary target to create all flags for all corpora
## --> WARNING: now you don't know whether things have been done

tmp-dedup-fix:
	touch ${ALL_MONO_DONE}
	touch ${LANGUAGE_DEDUP}



## TODO: upload targets are not up-to-date!

SWIFT_PARAMS = --use-slo --segment-size 5G --changed --skip-identical

STORAGE_FILES = ${LANGUAGE_DEDUP} ${LANGUAGE_SENT_DB} ${LANGUAGE_IDX_DB} ${LANGUAGE_FTS_DB} ${LINK_DB}

## add this before swift command?
#	${LOAD_STORAGE_ENV} && \

.PHONY: upload
upload:
	which a-put
	swift upload OPUS-index ${SWIFT_PARAMS} ${STORAGE_FILES}
	find sqlite -name '${LINK_DB}' -exec swift upload OPUS-index ${SWIFT_PARAMS} {} \;
	rm -f index.txt
	${MAKE} index.txt
	find done -name '${LANGUAGE}.done' | xargs -n 500 git add
	find done -name '${LANGPAIR}.done' | xargs -n 500 git add
	find sqlite -name '${LINKDB_LANGPAIR}.merged' | xargs -n 500 git add
	git add stats/${LANGUAGE}.counts index.txt


.PHONY: upload-all
upload-all:
	which a-put
	swift upload OPUS-index ${SWIFT_PARAMS} sqlite *.dedup.gz *.db
	rm -f index.txt
	${MAKE} index.txt
	find done -name '*.done' | xargs -n 500 git add
	find sqlite -name '*.merged' | xargs -n 500 git add
	git add stats/*.counts index.txt



index.txt:
	which a-get
	swift list OPUS-index | grep '\.dedup.gz$$' | \
		sed 's#^#https://object.pouta.csc.fi/OPUS-index/#' > $@
	swift list OPUS-index | grep '\.db$$'       | \
		sed 's#^#https://object.pouta.csc.fi/OPUS-index/#' >> $@


index-filesize.txt:
	which a-get
	rclone ls allas:OPUS-index | grep  '\.dedup.gz$$'  > $@
	rclone ls allas:OPUS-index | grep  '\.db$$'       >> $@




.PHONY: job-puhti
job-puhti:
	${MAKE} HPC_MEM=16g HPC_CORES=8 CORES=4 THREADS=4 HPC_DISK=1000 all-mono.submit

.PHONY: job-puhti
dedup-job-puhti:
	${MAKE} HPC_MEM=16g HPC_CORES=8 CORES=4 THREADS=4 HPC_DISK=1000 dedup.submit


big-job-puhti:
	${MAKE} HPC_MEM=32g HPC_CORES=16 CORES=8 THREADS=8 HPC_DISK=3000 all-mono.submit



## line (=sentence) count and word count
stats/${LANGUAGE}.counts: ${ALL_MONO_DONE}
	mkdir -p stats
	${MAKE} ${LANGUAGE_DEDUP}
	${GZIP} -cd ${LANGUAGE_DEDUP} | wc -lw |\
	sed 's/^ *//;s/  */	/g' > $@





CREATE_TABLE        := CREATE TABLE IF NOT EXISTS
CREATE_INDEX        := CREATE INDEX IF NOT EXISTS
CREATE_UNIQUE_INDEX := CREATE UNIQUE INDEX IF NOT EXISTS
INSERT_INTO         := INSERT OR IGNORE INTO

MODIFY_DB_DUMP      := sed 's/CREATE TABLE/${CREATE_TABLE}/;s/INSERT/INSERT OR IGNORE/;'

## merge all deduplicated files
## download the old dedup file in case it exists
## and no local file exists
${LANGUAGE_DEDUP}: ${ALL_MONO_DONE}
	${MAKE} STORED_FILE=$@ retrieve
	mkdir -p $(dir ${INDEX_TMPDIR}/$@)
	if [ -e $@ ]; then rsync $@ ${INDEX_TMPDIR}/$@; fi
	if [ `find ${INDEX_TMPDIR} -name '*.dedup' | wc -l` -gt 0 ]; then \
	  if [ -e ${INDEX_TMPDIR}/$@ ]; then \
	    echo "merge all corpora with ${LANGUAGE_DEDUP}"; \
	    find ${INDEX_TMPDIR} -name '*.dedup' |\
	    xargs ${MERGE} <(${GZIP} -cd ${INDEX_TMPDIR}/$@) | ${GZIP} -c > $@; \
	  else \
	    echo "merge all corpora into ${LANGUAGE_DEDUP}"; \
	    find ${INDEX_TMPDIR} -name '*.dedup' |\
	    xargs ${MERGE} | ${GZIP} -c > $@; \
	  fi \
	fi

## sqlite database of all sentences

${LANGUAGE_SENT_DB}: ${LANGUAGE_DEDUP}
	${MAKE} STORED_FILE=$@ retrieve
	mkdir -p ${INDEX_TMPDIR}
	if [ -e $@ ]; then rsync $@ ${INDEX_TMPDIR}/$@; fi
	${GZIP} -cd < $< | ${SCRIPTDIR}sent2sqlite.py ${INDEX_TMPDIR}/$@
	mv -f ${INDEX_TMPDIR}/$@ $@
	echo "PRAGMA journal_mode=WAL" | sqlite3 $@


## all sentences in all languages in one database
## --> that's going to be very big ....

opus.db: $(filter-out bitexts.db opus.db %.ids.db %.fts5.db,\
		$(filter-out $(wildcard *-*.db),$(wildcard *.db)))
	mkdir -p ${INDEX_TMPDIR}
	if [ -e $@ ]; then rsync $@ ${INDEX_TMPDIR}/$@; fi
	echo "${CREATE_TABLE} sentences ( sentence TEXT UNIQUE PRIMARY KEY NOT NULL )" \
	| sqlite3 ${INDEX_TMPDIR}/$@
	for d in $^; do \
	  echo "processing $$d"; \
	  rsync $$d ${INDEX_TMPDIR}/$$d; \
	  sqlite3 ${INDEX_TMPDIR}/$$d ".dump sentences" | ${MODIFY_DB_DUMP} | sqlite3 ${INDEX_TMPDIR}/$@; \
	  rm -f ${INDEX_TMPDIR}/$$d; \
	done
	rsync ${INDEX_TMPDIR}/$@ $@


## create a full-text search database from the sentence DB
## NEW: always create from scratch (avoid that we include duplicates)

${LANGUAGE_FTS_DB}: %.fts5.db: %.db
	${MAKE} STORED_FILE=$@ retrieve
	mkdir -p $(dir ${INDEX_TMPDIR}/$@)
#	if [ -e $@ ]; then rsync $@ ${INDEX_TMPDIR}/$@; fi
	echo "CREATE VIRTUAL TABLE IF NOT EXISTS sentences USING FTS5(sentence)" | sqlite3 ${INDEX_TMPDIR}/$@
	echo "ATTACH DATABASE '$(@:.fts5.db=.db)' as org; \
	      ${INSERT_INTO} sentences SELECT * FROM org.sentences;" | sqlite3 ${INDEX_TMPDIR}/$@
	mv -f ${INDEX_TMPDIR}/$@ $@




## sqlite database of all alignments

${LINK_DB}: ${ALL_ALG_DONE}
	@if [ -e ${INDEX_TMPDIR}/$@ ]; then \
	  mv -f ${INDEX_TMPDIR}/$@ $@; \
	  echo "${CREATE_TABLE} aligned_corpora ( corpus TEXT, version TEXT)" | sqlite3 $@; \
	  echo "${CREATE_UNIQUE_INDEX} idx_aligned_corpora ON aligned_corpora ( corpus, version )" \
		| sqlite3 $@; \
	  echo "${INSERT_INTO} aligned_corpora SELECT DISTINCT corpus,version FROM bitexts" \
		| sqlite3 $@; \
	fi


.INTERMEDIATE: ${INDEX_TMPDIR}/${LINK_DB}

${INDEX_TMPDIR}/${LINK_DB}:
	${MAKE} STORED_FILE=${LINK_DB} retrieve
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

${ALL_ALG_DONE}: ${INDEX_TMPDIR}/${LINK_DB}
	@echo "processing $(@:.done=.xml.gz)"
	@wget -qq -O - $(patsubst done/%.done,${STORAGE_BASE}%.xml.gz,$@) \
	| gzip -cd \
	| ${ALG2SQLITE} -d $< -c $(word 2,$(subst /, ,$@)) -v $(word 3,$(subst /, ,$@))
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
##     instead of adding ${LATEST_LINK_DB_MERGED} as pre-requisites
## --> merging takes place in temporary location
## --> move the link database back to the target location
## --> add bitext and aligned_corpora tables from the master bitext database
## --> finally, create indeces over bitexts and aligned_corpora
##
##
## TODO: corpus-range will not work anymore if we join several language pairs
##       that can occupy different parts of the table
##

${LATEST_LINK_DB}: ${LINK_DB} ${ALL_LINK_DBS}
	${MAKE} -j1 merge-latest-linkdbs
	if [ -e ${TMP_LINK_DB} ]; then mv -f ${TMP_LINK_DB} $@; fi
	sqlite3 $< ".dump bitexts" | ${MODIFY_DB_DUMP} | sqlite3 $@
	sqlite3 $< ".dump aligned_corpora" | ${MODIFY_DB_DUMP} | sqlite3 $@
	echo "${CREATE_UNIQUE_INDEX} idx_bitexts ON bitexts (corpus,version,fromDoc,toDoc)" | sqlite3 $@
	echo "${CREATE_UNIQUE_INDEX} idx_corpora ON aligned_corpora (corpus,version)" | sqlite3 $@
	${SCRIPTDIR}add_bitext_range.py $@
	${SCRIPTDIR}add_corpus_range.py $@


## phony target to merge link tables from each corpus
## --> only the latest release will be added
## --> this makes updating very complicated because old data needs to be deleted

.PHONY: merge-latest-linkdbs
merge-latest-linkdbs: ${LATEST_LINK_DB_MERGED}
	@if [ -e ${TMP_LINK_DB} ]; then \
	  echo "cleanup and copy ${LATEST_LINK_DB}"; \
	  echo "VACUUM;" | ${SQLITE3} ${TMP_LINK_DB}; \
	  rsync -av ${TMP_LINK_DB} ${LATEST_LINK_DB}; \
	fi



## create individual link databases (one per corpus/version)
## --> pre-requisite databases will be copied to a temporary location
## --> this makes lookup much faster (assuming that the tmpdisk is a fast local disk)

LINKDB_PREREQUISITES := ${INDEX_TMPDIR}/linkdb/${LINK_DB} \
			${INDEX_TMPDIR}/linkdb/${SRCLANG_IDX_DB} \
			${INDEX_TMPDIR}/linkdb/${TRGLANG_IDX_DB}

.INTERMEDIATE: ${LINKDB_PREREQUISITES}
${LINKDB_PREREQUISITES}: ${INDEX_TMPDIR}/linkdb/%: %
	mkdir -p $(dir $@)
	rsync -av $< $@


## add all links to the individual link databases
## do that in a temporary location and move the final database back to the target

LINK2SQLITE = ${SCRIPTDIR}links2sqlite.py

${ALL_LINK_DBS}: ${LINKDB_PREREQUISITES}
	@mkdir -p $(dir ${INDEX_TMPDIR}/$@)
	${LINK2SQLITE} $^ ${INDEX_TMPDIR}/$@ $(word 2,$(subst /, ,$@)) $(word 3,$(subst /, ,$@))
	@mkdir -p $(dir $@)
	mv -f ${INDEX_TMPDIR}/$@ $@



## initialize the global link database in local tmp dir with fast I/O
## declare this to be an intermediate file to remove it after finishing the process

TMP_LINK_DB := ${INDEX_TMPDIR}/${LATEST_LINK_DB}
.INTERMEDIATE: ${TMP_LINK_DB}


## open with timeout to allow concurrent access
## but that still does not seem to work well (skip timeout?)
SQLITE3 = sqlite3 -cmd ".timeout 100000"

${TMP_LINK_DB}:
	${MAKE} STORED_FILE=${LATEST_LINK_DB} retrieve
	mkdir -p $(dir $@)
	if [ -e ${LATEST_LINK_DB} ]; then rsync -av ${LATEST_LINK_DB} $@; fi
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

${LATEST_LINK_DB_MERGED}: ${TMP_LINK_DB}
	@( c=$(word 2,$(subst /, ,$@)); \
	  l=`grep 'latest_release:' ${OPUSRELEASE}/$$c/info.yaml | cut -f2 -d' ' | xargs`; \
	  m=`find sqlite/$$c -mindepth 2 -name '${LINKDB_LANGPAIR}.merged' | cut -f3 -d/ | xargs`; \
	  for v in $$m; do \
	    if [ "$$l" != "$$v" ]; then \
	      echo "remove links for $$c/$$v/${LINKDB_LANGPAIR}"; \
	      echo "ATTACH DATABASE '${LINKDB_LANGPAIR}.db' as b;\
		    DELETE FROM links WHERE bitextID IN \
			( SELECT DISTINCT rowid FROM b.bitexts WHERE corpus='$$c' AND version='$$v' ); \
		    DELETE FROM linkedsource WHERE bitextID IN \
			( SELECT DISTINCT rowid FROM b.bitexts WHERE corpus='$$c' AND version='$$v' ); \
		    DELETE FROM linkedtarget WHERE bitextID IN \
			( SELECT DISTINCT rowid FROM b.bitexts WHERE corpus='$$c' AND version='$$v' );" \
	  	    | ${SQLITE3} ${TMP_LINK_DB}; \
	      rm -f sqlite/$$c/$$v/${LINKDB_LANGPAIR}.merged; \
	    fi \
	  done; \
	  if [ ! -e sqlite/$$c/$$l/${LINKDB_LANGPAIR}.merged ]; then \
	    echo "add links for $$c/$$l/${LINKDB_LANGPAIR}"; \
	    if [ ! -e sqlite/$$c/$$l/${LINKDB_LANGPAIR}.db ]; then \
		${MAKE} sqlite/$$c/$$l/${LINKDB_LANGPAIR}.db; \
	    fi; \
	    if [ -e sqlite/$$c/$$l/${LINKDB_LANGPAIR}.db ]; then \
	      rsync sqlite/$$c/$$l/${LINKDB_LANGPAIR}.db ${INDEX_TMPDIR}/$$c-$$l-${LINKDB_LANGPAIR}.db; \
	      echo "ATTACH DATABASE '${INDEX_TMPDIR}/$$c-$$l-${LINKDB_LANGPAIR}.db' as l; \
		    ${INSERT_INTO} links SELECT * FROM l.links; \
		    ${INSERT_INTO} linkedsource SELECT * FROM l.linkedsource; \
		    ${INSERT_INTO} linkedtarget SELECT * FROM l.linkedtarget;" \
	      | ${SQLITE3} ${TMP_LINK_DB}; \
	      rm -f ${INDEX_TMPDIR}/$$c-$$l-${LINKDB_LANGPAIR}.db; \
	      touch sqlite/$$c/$$l/${LINKDB_LANGPAIR}.merged; \
	    else \
	      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"; \
	      echo "!!!!!!!! PROBLEM WITH sqlite/$$c/$$l/${LINKDB_LANGPAIR}.db"; \
	      echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"; \
	    fi \
	  fi )
	@touch $@

## should we sync back each time a DB has been merged?
## --> more failsafe to get the temporary DB back in place
## --> problematic in parallel threads?
## --> time-consuming
#
#	@rsync ${TMP_LINK_DB} ${LATEST_LINK_DB}







##--------------------------------------------------------------------------------
## database of all bitexts and aligned corpra
## (copy from tables in alignment database)
##--------------------------------------------------------------------------------

LANGPAIR_DBS = $(wildcard *-*.db)

bitexts.db: ${LANGPAIR_DBS}
	echo "${CREATE_TABLE} bitexts ( bitextID, corpus TEXT, version TEXT, fromDoc TEXT, toDoc TEXT, \
                                        srclang TEXT, trglang TEXT, srclang3 TEXT, trglang3 TEXT )" \
		| sqlite3 $@
	echo "${CREATE_UNIQUE_INDEX} idx_bitexts ON bitexts ( corpus, version, fromDoc, toDoc, \
                                                              srclang, trglang, srclang3, trglang3 )" \
		| sqlite3 $@
	echo "${CREATE_UNIQUE_INDEX} idx_bitext_ids ON bitexts ( bitextID, srclang, trglang )" | sqlite3 $@
	echo "${CREATE_INDEX} idx_langpair ON bitexts ( srclang, trglang )" | sqlite3 $@
	echo "${CREATE_INDEX} idx_langpair3 ON bitexts ( srclang3, trglang3 )" | sqlite3 $@
	echo "${CREATE_INDEX} idx_corpus ON bitexts ( corpus, version )" | sqlite3 $@
	for d in $^; do \
	  s=`echo $$d | cut -f1 -d-`; \
	  t=`echo $$d | cut -f2 -d- | cut -f1 -d.`; \
	  S=`iso639 -n -m $$s`; \
	  T=`iso639 -n -m $$t`; \
	  echo "$$s $$t $$S $$T"; \
	  echo "ATTACH DATABASE '$$d' as l; \
	        ${INSERT_INTO} bitexts SELECT rowid, corpus, version, fromDoc, toDoc,\
                                              '$$s','$$t','$$S','$$T' FROM l.bitexts;" \
	  | sqlite3 $@; \
	done

##------------------------------------------------------------------------------------
## sentence index that maps corpus-specific indeces to the ID in the sentence DB
##------------------------------------------------------------------------------------

sentence-index: ${LANGUAGE_IDX_DB}


TMP_SENTENCE_DB := ${INDEX_TMPDIR}/${LANGUAGE}-sentences.db
.INTERMEDIATE: ${TMP_SENTENCE_DB}

${LANGUAGE_IDX_DB}: ${ALL_MONO_IDSDONE}
	if [ -e ${TMP_SENTENCE_DB} ]; then mv -f ${TMP_SENTENCE_DB} ${LANGUAGE_SENT_DB}; fi
	if [ -e ${INDEX_TMPDIR}/$@ ]; then mv -f ${INDEX_TMPDIR}/$@ $@; fi


## separate makefile targets for source and target language
## if necessary (i.e. LANGUAGE is not set to either language)

ifneq (${LANGUAGE},${SRCLANG})
${SRCLANG_IDX_DB}:
	${MAKE} LANGUAGE=${SRCLANG} $@
endif

ifneq (${LANGUAGE},${TRGLANG})
${TRGLANG_IDX_DB}:
	${MAKE} LANGUAGE=${TRGLANG} $@
endif



${ALL_MONO_IDSDONE}: ${INDEX_TMPDIR}/${LANGUAGE_IDX_DB} ${TMP_SENTENCE_DB}
	@echo "process $@"
	@${SCRIPTDIR}sentid2sqlite.py \
		-i $< \
		-c $(word 2,$(subst /, ,$@)) \
		-r $(word 3,$(subst /, ,$@)) \
		-l ${LANGUAGE} \
		-d ${TMP_SENTENCE_DB}
	@mkdir -p $(dir $@)
	@touch $@




.INTERMEDIATE: ${INDEX_TMPDIR}/${LANGUAGE_IDX_DB}
${INDEX_TMPDIR}/${LANGUAGE_IDX_DB}:
	${MAKE} STORED_FILE=$(notdir $@) retrieve
	mkdir -p $(dir $@)
	if [ -e $(notdir $@) ]; then rsync -av $(notdir $@) $@; fi
	echo "${CREATE_TABLE} documents ( corpus, version, document )" | sqlite3 $@
	echo "${CREATE_UNIQUE_INDEX} idx_documents ON documents (corpus,version,document)" | sqlite3 $@
	echo "${CREATE_TABLE} sentids ( id INTEGER, docID INTEGER, sentID TEXT)" | sqlite3 $@
	echo "${CREATE_UNIQUE_INDEX} idx_sentids ON sentids ( docID, sentID)" | sqlite3 $@
# 	echo "CREATE INDEX idx_id ON sentids (id)" | sqlite3 $@


ifneq (${LANGUAGE},${SRCLANG})
.INTERMEDIATE: ${INDEX_TMPDIR}/${SRCLANG_IDX_DB}
${INDEX_TMPDIR}/${SRCLANG_IDX_DB}:
	${MAKE} LANGUAGE=${SRCLANG} $@
endif

ifneq (${LANGUAGE},${TRGLANG})
.INTERMEDIATE: ${INDEX_TMPDIR}/${TRGLANG_IDX_DB}
${INDEX_TMPDIR}/${TRGLANG_IDX_DB}:
	${MAKE} LANGUAGE=${TRGLANG} $@
endif



${TMP_SENTENCE_DB}:
	mkdir -p $(dir $@)
	rsync ${LANGUAGE_SENT_DB} $@



## misc target: add another index over internal sentence IDs
## TODO: do we need that? (takes quite some space)

SENTIDS_DBS = $(patsubst %.ids.db,%.sentids.db,$(wildcard *.ids.db))

add-sentid-index: ${SENTIDS_DBS}

%.sentids.db:
	mkdir -p ${INDEX_TMPDIR}
	cp $(@:.sentids.db=.ids.db) ${INDEX_TMPDIR}/$@
	echo "CREATE INDEX idx_id ON sentids (id)" | sqlite3 ${INDEX_TMPDIR}/$@
	mv -f ${INDEX_TMPDIR}/$@ $@






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

${ALL_MONO_DONE}: done/%.done: ${INDEX_TMPDIR}/%.dedup
##
## immediately add sentences to the sentence DB
## --> this is too slow on shared filesystems
## --> but we can't copy and sync back as this may break concurrent tasks
## --> skip this and hope that the job does not stop prematurely
##
#	if [ -e ${LANGUAGE_SENT_DB} ]; then \
#	  if [ -s $< ]; then \
#	    cat $< | ${SCRIPTDIR}sent2sqlite.py ${LANGUAGE_SENT_DB}; \
#	  fi \
#	fi
	mkdir -p $(dir $@)
	touch $@





## retrieve a file from allas if it exists
## and sync it to the temporary file location as well

retrieve:
ifneq (${SKIP_FILE_RETRIEVAL},1)
	@if [ ! -e ${STORED_FILE} ]; then \
	  if [ `grep '${STORED_FILE}' index.txt | wc -l` -gt 0 ]; then \
	    echo "download ${STORED_FILE}"; \
	    wget -qq ${STORAGE_BASE}index/${STORED_FILE}; \
	  fi \
	fi
endif






