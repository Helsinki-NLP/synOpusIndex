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


ALL_ALG_URLS  := $(sort $(patsubst %,https:%,$(shell find ${OPUSRELEASE}/ -name statistics.yaml | \
						xargs grep 'xml/${LANGPAIR}.xml.gz' | cut -f4 -d:)))
ALL_ALG_DONE  := $(patsubst ${STORAGE_BASE}%.xml.gz,done/%.done,${ALL_ALG_URLS})
ALL_LINK_DONE := $(patsubst ${STORAGE_BASE}%.xml.gz,done/%.linkdb.done,${ALL_ALG_URLS})
ALL_LINK_DBS  := $(subst /xml/,/,$(patsubst done/%/${LANGPAIR}.done,sqlite/%/${LINKDB_LANGPAIR}.db,${ALL_ALG_DONE}))


## alignment databases
##
##   LINK_DB               = all alignments from all corpora (pointing to OPUS sentence IDs)
##   LATEST_LINK_DB        = links from latest releases (pointing to sentence index IDs)
##   LATEST_LINK_DB_MERGED = flags marking that the latest release has been merged

LINK_DB               := ${LANGPAIR3}.db
LATEST_LINK_DB        := sqlite/${LANGPAIR3}.db
OLDER_LINK_DB         := sqlite/${LANGPAIR3}.releases.db

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


## create link-db without parallel threads
## --> avoid errors with locked DB files
## --> avoid mixed rowid ranges for individual corpora

.PHONY: all
all: srclang trglang
	${MAKE} -j1 ${LINK_DB}
	${MAKE} ${LATEST_LINK_DB}

.PHONY: srclang
srclang:
	${MAKE} LANGUAGE=${SRCLANG} all-mono

.PHONY: trglang
trglang:
	${MAKE} LANGUAGE=${TRGLANG} all-mono


.PHONY: all-mono
all-mono:
	$(call retrieve,${LANGUAGE_SENT_DB})
	if [ ! -e ${LANGUAGE_SENT_DB} ]; then ${MAKE} ${LANGUAGE_SENT_DB}; fi
	${MAKE} ${LANGUAGE_IDX_DB}
	${MAKE} ${LANGUAGE_FTS_DB}

.PHONY: all-links
all-links:
	${MAKE} -j1 ${LINK_DB}
	${MAKE} ${LATEST_LINK_DB}


.PHONY: linkdb
linkdb: ${LATEST_LINK_DB}



HPLT_LANGPAIRS = ar-en bs-en ca-en en-et en-eu en-fi en-ga en-gl en-hi en-hr en-is en-mk en-mt en-nn en-sq en-sr en-sw en-zh_Hant

HPLT_LANGS = ar bs ca et eu fi ga gl hi hr is mk mt nn sq sr sw zh_Hant

hplt-all:
	for s in ${HPLT_LANGS}; do \
	  for t in ${HPLT_LANGS}; do \
	    if [ "$$s" \< "$$t" ]; then \
		echo "start making langpair $$s-$$t"; \
		${MAKE} LANGPAIR=$$s-$$t all; \
	    fi \
	  done \
	done
# 	for l in ${HPLT_LANGPAIRS}; do ${MAKE} LANGPAIR=$$l all; done


zh:
	make LANGPAIR=en-zh all-links
	make LANGPAIR=en-zh_Hant all-links
	make LANGPAIR=en-zh_cn all-links
	make LANGPAIR=en-zh_tw all-links
	make LANGPAIR=en-yue all-links
	make LANGPAIR=cmn-en all-links





.PHONY: counts
counts: stats/${LANGUAGE}.counts

.PHONY: dedup
dedup: ${LANGUAGE_DEDUP}



STORAGE_FILES := ${LANGUAGE_SENT_DB} ${LANGUAGE_IDX_DB} ${LANGUAGE_FTS_DB} ${LINK_DB}
SWIFT_PARAMS  := --use-slo --segment-size 5G --changed --skip-identical

## add this before swift command?
#	${LOAD_STORAGE_ENV} && \

.PHONY: upload
upload:
	which a-put
	swift upload OPUS-index ${SWIFT_PARAMS} ${STORAGE_FILES}
	find sqlite -name '${LANGPAIR3}.db' -exec swift upload OPUS-index ${SWIFT_PARAMS} {} \;
	rm -f index.txt
	${MAKE} index.txt
	find done -name '${LANGUAGE}.done' | xargs -n 500 git add
	find done -name '${LANGPAIR}.done' | xargs -n 500 git add
	find sqlite -name '${LINKDB_LANGPAIR}.merged' | xargs -n 500 git add
	git add index.txt


.PHONY: upload-all
upload-all:
	which a-put
	swift upload OPUS-index ${SWIFT_PARAMS} *.db
	find sqlite -name '*.db' -exec swift upload OPUS-index ${SWIFT_PARAMS} {} \;
	rm -f index.txt
	${MAKE} index.txt
	find done -name '*.done' | xargs -n 500 git add
	find sqlite -name '*.merged' | xargs -n 500 git add
	git add index.txt



index.txt:
	which a-get
	swift list OPUS-index | grep '\.db$$' > $@


index-filesize.txt:
	which a-get
	rclone ls allas:OPUS-index | grep  '\.db$$' >> $@



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
	$(call retrieve,$@)
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

${LANGUAGE_SENT_DB}:
	$(call retrieve,$@)
	${MAKE} ${LANGUAGE_DEDUP}
	mkdir -p ${INDEX_TMPDIR}
	if [ -e $@ ]; then rsync $@ ${INDEX_TMPDIR}/$@; fi
	${GZIP} -cd < $< | ${SCRIPTDIR}sent2sqlite.py ${INDEX_TMPDIR}/$@
	mv -f ${INDEX_TMPDIR}/$@ $@
	echo "PRAGMA journal_mode=WAL" | sqlite3 $@


## all sentences in all languages in one database
## --> that's going to be very big ....

opus.db: $(filter-out bitexts.db opus.db %.ids.db %.fts5.db $(wildcard *-*.db),$(wildcard *.db)))
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
## NEW: check rowid's if the fts-DB exists and only update with new rows
##      otherwise, create from scratch in the tmpdir and copy back

${LANGUAGE_FTS_DB}: %.fts5.db: %.db
	$(call retrieve,$@)
	if [ -e $@ ]; then \
	  a=`echo "select max(rowid) from sentences" | sqlite3 $<`; \
	  b=`echo "select max(rowid) from sentences" | sqlite3 $@`; \
	  if [ "$$a" != "$$b" ]; then \
	    echo "ATTACH DATABASE '$<' as org; \
	          ${INSERT_INTO} sentences SELECT * FROM org.sentences WHERE rowid>$$b;" \
	    | sqlite3 $@; \
	  fi; \
	else \
	  mkdir -p $(dir ${INDEX_TMPDIR}/$@); \
	  echo "CREATE VIRTUAL TABLE IF NOT EXISTS sentences USING FTS5(sentence)" \
	  | sqlite3 ${INDEX_TMPDIR}/$@; \
	  echo "ATTACH DATABASE '$<' as org; \
	        ${INSERT_INTO} sentences SELECT * FROM org.sentences;" \
	  | sqlite3 ${INDEX_TMPDIR}/$@; \
	  mv -f ${INDEX_TMPDIR}/$@ $@; \
	fi




## sqlite database of all alignments

${LINK_DB}: ${ALL_ALG_DONE}
	@if [ -e ${INDEX_TMPDIR}/$@ ]; then \
	  mv -f ${INDEX_TMPDIR}/$@ $@; \
	fi


## create an intermediate DB for all links
## TODO: do we still need the alignments view (see scripts/alg2sqlite.py)

.INTERMEDIATE: ${INDEX_TMPDIR}/${LINK_DB}

${INDEX_TMPDIR}/${LINK_DB}:
	$(call retrieve,${LINK_DB})
	mkdir -p $(dir $@)
	if [ -e $(notdir $@) ]; then rsync $(notdir $@) $@; fi
	@if [ ! -e $@ ]; then \
	  echo "${CREATE_TABLE} bitexts (corpus TEXT,version TEXT,fromDoc TEXT,toDoc TEXT)" | sqlite3 $@; \
	  echo "${CREATE_UNIQUE_INDEX} idx_bitexts ON bitexts (corpus,version,fromDoc,toDoc)" | sqlite3 $@; \
	  echo "${CREATE_TABLE} links ( bitextID, srcIDs TEXT, trgIDs TEXT, alignType TEXT, \
			                alignerScore REAL, cleanerScore REAL)" | sqlite3 $@; \
	  echo "${CREATE_UNIQUE_INDEX} idx_links ON links (bitextID,srcIDs,trgIDs)" | sqlite3 $@; \
	  echo "${CREATE_INDEX} idx_bitextid ON links (bitextID)" | sqlite3 $@; \
	  echo "${CREATE_INDEX} idx_aligntype ON links (bitextID,alignType)" | sqlite3 $@; \
	  echo "${CREATE_TABLE} corpora (corpus TEXT,version TEXT,srclang TEXT,trglang TEXT,srclang3 TEXT,trglang3 TEXT)" | sqlite3 $@; \
	  echo "${CREATE_UNIQUE_INDEX} idx_corpora ON corpora (corpus,version,srclang,trglang,srclang3,trglang3)" | sqlite3 $@; \
	  echo "PRAGMA journal_mode=WAL" | sqlite3 $@; \
	fi


${ALL_ALG_DONE}: ${INDEX_TMPDIR}/${LINK_DB}
	@echo "processing $(@:.done=.xml.gz)"
	@wget -qq -O - $(patsubst done/%.done,${STORAGE_BASE}%.xml.gz,$@) \
	| gzip -cd \
	| ${ALG2SQLITE} -d $< -c $(word 2,$(subst /, ,$@)) -v $(word 3,$(subst /, ,$@))
	@echo "${INSERT_INTO} corpora VALUES('$(word 2,$(subst /, ,$@))', \
                                             '$(word 3,$(subst /, ,$@))', \
                                             '${SRCLANG}','${TRGLANG}', \
                                             '${SRCLANG3}','${TRGLANG3}')" \
	| sqlite3 $<
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
## --> add bitext table from the master bitext database
## --> add rowid ranges over bitexts and corpora

${LATEST_LINK_DB}: ${LINK_DB} ${ALL_LINK_DBS}
	${MAKE} -j1 merge-latest-linkdbs
	if [ -e ${TMP_LINK_DB} ]; then mv -f ${TMP_LINK_DB} $@; fi
	sqlite3 $< ".dump bitexts" | ${MODIFY_DB_DUMP} | sqlite3 $@
	echo "${CREATE_UNIQUE_INDEX} idx_bitexts ON bitexts (corpus,version,fromDoc,toDoc)" | sqlite3 $@
	${SCRIPTDIR}add_bitext_range.py $@
	${SCRIPTDIR}add_corpus_range.py -d $@


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

LINKDB_PREREQ_TMPDIR := ${INDEX_TMPDIR}/linkdb

LINKDB_PREREQUISITES := ${LINKDB_PREREQ_TMPDIR}/${LINK_DB} \
			${LINKDB_PREREQ_TMPDIR}/${SRCLANG_IDX_DB} \
			${LINKDB_PREREQ_TMPDIR}/${TRGLANG_IDX_DB}

.INTERMEDIATE: ${LINKDB_PREREQUISITES}
${LINKDB_PREREQUISITES}: ${LINKDB_PREREQ_TMPDIR}/%: %
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

TMP_LATEST_LINK_DB := ${INDEX_TMPDIR}/${LATEST_LINK_DB}
TMP_OLDER_LINK_DB  := ${INDEX_TMPDIR}/${OLDER_LINK_DB}
TMP_LINK_DB        := ${TMP_LATEST_LINK_DB}
.INTERMEDIATE: ${TMP_LINK_DB} ${TMP_LATEST_LINK_DB} ${TMP_OLDER_LINK_DB}


## open with timeout to allow concurrent access
## but that still does not seem to work well (skip timeout?)
SQLITE3 = sqlite3 -cmd ".timeout 100000"

${TMP_LATEST_LINK_DB} ${TMP_OLDER_LINK_DB}:
	$(call retrieve,$(patsubst ${INDEX_TMPDIR}/%,%,$@))
	mkdir -p $(dir $@)
	if [ -e $(patsubst ${INDEX_TMPDIR}/%,%,$@) ]; then rsync -av $(patsubst ${INDEX_TMPDIR}/%,%,$@) $@; fi
	@echo "${CREATE_TABLE} linkedsource (sentID INTEGER,linkID INTEGER,bitextID INTEGER,PRIMARY KEY(linkID,sentID) )" | ${SQLITE3} $@
	@echo "${CREATE_TABLE} linkedtarget (sentID INTEGER,linkID INTEGER,bitextID INTEGER,PRIMARY KEY(linkID,sentID) )" | ${SQLITE3} $@
	@echo "${CREATE_INDEX} idx_linkedsource_bitext ON linkedsource (bitextID,sentID)" | ${SQLITE3} $@
	@echo "${CREATE_INDEX} idx_linkedtarget_bitext ON linkedtarget (bitextID,sentID)" | ${SQLITE3} $@
	@echo "${CREATE_INDEX} idx_linkedsource_linkid ON linkedsource (linkID)" | ${SQLITE3} $@
	@echo "${CREATE_INDEX} idx_linkedtarget_linkid ON linkedtarget (linkID)" | ${SQLITE3} $@
	@echo "${CREATE_INDEX} idx_linkedsource_sentid ON linkedsource (sentID)" | ${SQLITE3} $@
	@echo "${CREATE_INDEX} idx_linkedtarget_sentid ON linkedtarget (sentID)" | ${SQLITE3} $@
	@echo "${CREATE_TABLE} links (linkID INTEGER NOT NULL PRIMARY KEY,bitextID, \
                                      srcIDs TEXT,trgIDs TEXT,srcSentIDs TEXT,trgSentIDs TEXT, \
                                      alignType TEXT,alignerScore REAL,cleanerScore REAL)" | ${SQLITE3} $@
	@echo "${CREATE_UNIQUE_INDEX} idx_links ON links (bitextID,srcIDs,trgIDs)" | ${SQLITE3} $@
	@echo "${CREATE_INDEX} idx_aligntype ON links (bitextID,alignType)" | ${SQLITE3} $@
	@echo "${CREATE_INDEX} idx_bitextid ON links (bitextID)" | ${SQLITE3} $@
	@echo "${CREATE_TABLE} corpora (corpus TEXT,version TEXT,srclang TEXT,trglang TEXT,srclang3 TEXT,trglang3 TEXT)" | sqlite3 $@
	@echo "${CREATE_UNIQUE_INDEX} idx_corpora ON corpora (corpus,version,srclang,trglang,srclang3,trglang3)" | sqlite3 $@
	@sqlite3 ${LINK_DB} ".dump bitexts" | ${MODIFY_DB_DUMP} | sqlite3 $@
	@echo "${CREATE_UNIQUE_INDEX} idx_bitexts ON bitexts (corpus,version,fromDoc,toDoc)" | sqlite3 $@
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
	      echo "DELETE FROM corpora WHERE corpus='$$c' AND version='$$v'" | ${SQLITE3} ${TMP_LINK_DB}; \
	      rm -f sqlite/$$c/$$v/${LINKDB_LANGPAIR}.merged; \
	    fi \
	  done; \
	  if [ ! -e sqlite/$$c/$$l/${LINKDB_LANGPAIR}.merged ]; then \
	    echo "add links for $$c/$$l/${LINKDB_LANGPAIR}"; \
	    if [ ! -e sqlite/$$c/$$l/${LINKDB_LANGPAIR}.db ]; then \
	      if [ -e ${OPUSRELEASE}/$$c/$$l/statistics.yaml ]; then \
	        if [ `grep '${LINKDB_LANGPAIR}.xml.gz' ${OPUSRELEASE}/$$c/$$l/statistics.yaml | wc -l` -gt 0 ]; then \
	          ${MAKE} sqlite/$$c/$$l/${LINKDB_LANGPAIR}.db; \
	        fi \
	      fi \
	    fi; \
	    if [ -e sqlite/$$c/$$l/${LINKDB_LANGPAIR}.db ]; then \
	      rsync sqlite/$$c/$$l/${LINKDB_LANGPAIR}.db ${INDEX_TMPDIR}/$$c-$$l-${LINKDB_LANGPAIR}.db; \
	      echo "ATTACH DATABASE '${INDEX_TMPDIR}/$$c-$$l-${LINKDB_LANGPAIR}.db' as l; \
		    ${INSERT_INTO} links SELECT * FROM l.links; \
		    ${INSERT_INTO} linkedsource SELECT * FROM l.linkedsource; \
		    ${INSERT_INTO} linkedtarget SELECT * FROM l.linkedtarget;" \
	      | ${SQLITE3} ${TMP_LINK_DB}; \
	      echo "${INSERT_INTO} corpora VALUES('$$c','$$l','${SRCLANG}','${TRGLANG}','${SRCLANG3}','${TRGLANG3}')" \
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

##-----------------------------------------------------------------------------
## should we sync back each time a DB has been merged?
## --> more failsafe to get the temporary DB back in place
## --> problematic in parallel threads?
## --> time-consuming
#
#	@rsync ${TMP_LINK_DB} ${LATEST_LINK_DB}
#
##-----------------------------------------------------------------------------
## if we want to only have document pairs that are part of the latest releases
## then we would need to delete bitexts from old releases and add the ones from the latest:
##
## create bitexts table with bitextID as unique key (add to ${TMP_LINK_DB})
##
#	@echo "${CREATE_TABLE} bitexts (bitextID,corpus TEXT,version TEXT,fromDoc TEXT,toDoc TEXT)" | sqlite3 $@
#	@echo "${CREATE_UNIQUE_INDEX} idx_bitexts ON bitexts (corpus,version,fromDoc,toDoc)" | sqlite3 $@
#	@echo "${CREATE_UNIQUE_INDEX} idx_bitext_ids ON bitexts (bitextID)" | sqlite3 $@
#	@echo "${CREATE_INDEX} idx_corpus ON bitexts (corpus,version)" | sqlite3 $@
##
## delete previous (add above in the part where things are removed):
##
#	      echo "DELETE FROM bitexts WHERE corpus='$$c' AND version='$$v'" | ${SQLITE3} ${TMP_LINK_DB}; \
##
## add latest (add above in the part where latest release info is added):
##
#	      echo "ATTACH DATABASE '${LINK_DB}' as l; \
#	            ${INSERT_INTO} bitexts SELECT rowid, corpus, version, fromDoc, toDoc \
#	                                   FROM l.bitexts \
#                                          WHERE corpus='$$c' AND version='$$l';" \
#	      | ${SQLITE3} ${TMP_LINK_DB}; \
##
## this is not compatible with the current way of adding the entire bitexts table
## from the LINK_DB (because this uses rowid as the unique bitext ID)
## see target ${LATEST_LINK_DB} where the bitexts table is simply dumped into the LATEST_LINK_DB
##-----------------------------------------------------------------------------



new-linkdb: ${ALL_LINK_DONE}
	${SCRIPTDIR}add_bitext_range.py ${LATEST_LINK_DB}
	${SCRIPTDIR}add_bitext_range.py ${OLDER_LINK_DB}

new-linkdb-local:
	@$(call lockfile,${LATEST_LINK_DB})
	@$(call lockfile,${OLDER_LINK_DB})
	@$(call create_linkdb,${LATEST_LINK_DB})
	@$(call create_linkdb,${OLDER_LINK_DB})
	@echo "make link DBs in ${INDEX_TMPDIR}"
	@${MAKE} -j 1 \
		LATEST_LINK_DB=${INDEX_TMPDIR}/${LATEST_LINK_DB} \
		OLDER_LINK_DB=${INDEX_TMPDIR}/${OLDER_LINK_DB} \
		new-linkdb
	mv -f ${INDEX_TMPDIR}/${LATEST_LINK_DB} ${LATEST_LINK_DB}
	mv -f ${INDEX_TMPDIR}/${OLDER_LINK_DB} ${OLDER_LINK_DB}
	@$(call unlockfile,${LATEST_LINK_DB})
	@$(call unlockfile,${OLDER_LINK_DB})


redo-langs.txt:
	find done -name '*-*.done' | cut -f5 -d/ | cut -f1 -d. | sort -u > $@

REDO_LANGS = $(patsubst %,%.done,${shell cat redo-langs.txt})

redo-langs: ${REDO_LANGS}

${REDO_LANGS}:
	-${MAKE} LANGPAIR=$(@:.done=) LINKDB_PREREQUISITES='' new-linkdb-local




## extract linkdb data for a given corpus release
## merge all data into the central link DBs
##   - LATEST_LINK_DB for the latest corpus releases
##   - OLDER_LINK_DB for all other corpus releases


## SQL comands to create a link databass

CREATE_LINKDB := \
	${CREATE_TABLE} linkedsource (sentID INTEGER,linkID INTEGER,bitextID INTEGER,PRIMARY KEY(linkID,sentID) ); \
	${CREATE_TABLE} linkedtarget (sentID INTEGER,linkID INTEGER,bitextID INTEGER,PRIMARY KEY(linkID,sentID) ); \
	${CREATE_INDEX} idx_linkedsource_bitext ON linkedsource (bitextID,sentID) ; \
	${CREATE_INDEX} idx_linkedtarget_bitext ON linkedtarget (bitextID,sentID) ;\
	${CREATE_INDEX} idx_linkedsource_linkid ON linkedsource (linkID); \
	${CREATE_INDEX} idx_linkedtarget_linkid ON linkedtarget (linkID); \
	${CREATE_INDEX} idx_linkedsource_sentid ON linkedsource (sentID); \
	${CREATE_INDEX} idx_linkedtarget_sentid ON linkedtarget (sentID); \
	${CREATE_TABLE} links (linkID INTEGER NOT NULL PRIMARY KEY,bitextID, \
                                      srcIDs TEXT,trgIDs TEXT,srcSentIDs TEXT,trgSentIDs TEXT, \
                                      alignType TEXT,alignerScore REAL,cleanerScore REAL); \
	${CREATE_UNIQUE_INDEX} idx_links ON links (bitextID,srcIDs,trgIDs); \
	${CREATE_INDEX} idx_aligntype ON links (bitextID,alignType); \
	${CREATE_INDEX} idx_bitextid ON links (bitextID); \
	${CREATE_TABLE} corpora (corpus TEXT,version TEXT,srclang TEXT,trglang TEXT,srclang3 TEXT,trglang3 TEXT); \
	${CREATE_UNIQUE_INDEX} idx_corpora ON corpora (corpus,version,srclang,trglang,srclang3,trglang3); \
	${CREATE_TABLE} bitexts (corpus TEXT,version TEXT,fromDoc TEXT,toDoc TEXT); \
	${CREATE_UNIQUE_INDEX} idx_bitexts ON bitexts (corpus,version,fromDoc,toDoc); \
	ATTACH DATABASE '${LINK_DB}' as l; \
	${INSERT_INTO} bitexts SELECT * FROM l.bitexts ORDER BY rowid; \
	PRAGMA journal_mode=WAL;


## additional helper functions and variables

create_linkdb =	if [ ! -s $1 ]; then echo "create $1";mkdir -p $(dir $1); echo "${CREATE_LINKDB}" | ${SQLITE3} $1; fi

LINKDB_MATCH_CORPUS      := corpus='$$c' AND srclang='${SRCLANG}' AND trglang='${TRGLANG}'
LINKDB_MATCH_CORPUS_DOCS := corpus='$$c' AND fromDoc LIKE '${SRCLANG}/%' AND toDoc LIKE '${TRGLANG}/%'
LINKDB_CORPUS_SELECT     := SELECT DISTINCT rowid FROM bitexts WHERE ${LINKDB_MATCH_CORPUS_DOCS}
LINKDB_MATCH_BITEXT      := bitextID IN ( ${LINKDB_CORPUS_SELECT} )
LINKDB_COUNT_RELEASES    := echo "SELECT rowid FROM corpora WHERE ${LINKDB_MATCH_CORPUS}" \
				| ${SQLITE3} ${LATEST_LINK_DB} | wc -l


${ALL_LINK_DONE}: ${LINKDB_PREREQUISITES}

## create temporary database for the selected corpus/release/langpair

	@mkdir -p $(dir ${INDEX_TMPDIR}/$@) $(dir ${LATEST_LINK_DB}) $(dir ${OLDER_LINK_DB})
	@if [ -e sqlite/$(word 2,$(subst /, ,$@))/$(word 3,$(subst /, ,$@))/$(notdir $(@:.linkdb.done=.db)) ]; then \
	  echo "copy sqlite DB to ${INDEX_TMPDIR}/$@"; \
	  cp sqlite/$(word 2,$(subst /, ,$@))/$(word 3,$(subst /, ,$@))/$(notdir $(@:.linkdb.done=.db)) ${INDEX_TMPDIR}/$@; \
	elif [ -e sqlite-old/$(word 2,$(subst /, ,$@))/$(word 3,$(subst /, ,$@))/$(notdir $(@:.linkdb.done=.db)) ]; then \
	  echo "copy sqlite-old DB to ${INDEX_TMPDIR}/$@"; \
	  cp sqlite-old/$(word 2,$(subst /, ,$@))/$(word 3,$(subst /, ,$@))/$(notdir $(@:.linkdb.done=.db)) ${INDEX_TMPDIR}/$@; \
	else \
	  if [ "${LINKDB_PREREQUISITES}" != "" ]; then \
	    ${LINK2SQLITE} $^ ${INDEX_TMPDIR}/$@ $(word 2,$(subst /, ,$@)) $(word 3,$(subst /, ,$@)); \
	  else \
	    if [ -e ${TMPDIR}/${SRCLANG_IDX_DB} ]; then S=${TMPDIR}/${SRCLANG_IDX_DB}; else S=${SRCLANG_IDX_DB}; fi; \
	    if [ -e ${TMPDIR}/${TRGLANG_IDX_DB} ]; then T=${TMPDIR}/${TRGLANG_IDX_DB}; else T=${TRGLANG_IDX_DB}; fi; \
	    echo "${LINK2SQLITE} ${LINK_DB} $$S $$T ${INDEX_TMPDIR}/$@ $(word 2,$(subst /, ,$@)) $(word 3,$(subst /, ,$@))"; \
	    mkdir -p $(dir ${INDEX_TMPDIR}/$@); \
	    ${LINK2SQLITE} ${LINK_DB} $$S $$T ${INDEX_TMPDIR}/$@ $(word 2,$(subst /, ,$@)) $(word 3,$(subst /, ,$@)); \
	  fi \
	fi

## if the release is the latest one for that corpus/langpair
## --> move other release data (if they exist) from latest link DB to DB of other releases
## --> add links from temporary DB to latest link DB
## otherwise:
## --> add links from temporary DB to DB of other releases
## do all this in tempdir (which requires locking the DB, creating, syncing back)

	@if [ -s ${INDEX_TMPDIR}/$@ ]; then \
	  c=$(word 2,$(subst /, ,$@)); \
	  v=$(word 3,$(subst /, ,$@)); \
	  l=`grep 'latest_release:' ${OPUSRELEASE}/$$c/info.yaml | cut -f2 -d' ' | xargs`; \
	  if [ ! -e ${OPUSRELEASE}/$$c/$$l/statistics.yaml ] || \
	     [ `grep '$(notdir $(@:.linkdb.done=.xml.gz))' ${OPUSRELEASE}/$$c/$$l/statistics.yaml | wc -l` -eq 0 ]; then \
	     l=`grep '$(notdir $(@:.linkdb.done=.xml.gz))' ${OPUSRELEASE}/$$c/index.txt | tail -1 | cut -f1 -d/`; \
	  fi; \
	  if [ "$$v" == "$$l" ]; then \
	    echo "release $$v is the latest release for $$c"; \
	    $(call lockfile,${LATEST_LINK_DB}); \
	    $(call create_linkdb,${LATEST_LINK_DB}); \
	    if [ `${LINKDB_COUNT_RELEASES}` -gt 0 ]; then \
	      echo "found previous release(s) in ${LATEST_LINK_DB}"; \
	      echo "move links for $$c/*/${LINKDB_LANGPAIR} to DB of older releases"; \
	      $(call lockfile,${OLDER_LINK_DB}); \
	      $(call create_linkdb,${OLDER_LINK_DB}); \
	      echo "ATTACH DATABASE '${LATEST_LINK_DB}' as l; \
	            ${INSERT_INTO} corpora SELECT * from l.corpora WHERE ${LINKDB_MATCH_CORPUS}; \
		    ${INSERT_INTO} links SELECT * FROM l.links WHERE ${LINKDB_MATCH_BITEXT} ; \
		    ${INSERT_INTO} linkedsource SELECT * FROM l.linkedsource WHERE ${LINKDB_MATCH_BITEXT}; \
		    ${INSERT_INTO} linkedtarget SELECT * FROM l.linkedtarget WHERE ${LINKDB_MATCH_BITEXT};" \
	      | ${SQLITE3} ${OLDER_LINK_DB}; \
	      ${SCRIPTDIR}add_corpus_range.py -d ${OLDER_LINK_DB} -c $$c -s ${SRCLANG} -t ${TRGLANG}; \
	      $(call unlockfile,${OLDER_LINK_DB}); \
	      echo "remove links for $$c/*/${LINKDB_LANGPAIR} from link DB of latest releases"; \
	      echo "DELETE FROM corpora WHERE ${LINKDB_MATCH_CORPUS}; \
	            DELETE FROM links WHERE ${LINKDB_MATCH_BITEXT}; \
		    DELETE FROM linkedsource WHERE ${LINKDB_MATCH_BITEXT}; \
		    DELETE FROM linkedtarget WHERE ${LINKDB_MATCH_BITEXT};" \
	      | ${SQLITE3} ${LATEST_LINK_DB}; \
	    fi; \
	    echo "add links for $$c/$$v/${LINKDB_LANGPAIR} to link DB of latest releases"; \
	    echo "ATTACH DATABASE '${INDEX_TMPDIR}/$@' as l; \
	          ${INSERT_INTO} corpora VALUES('$$c','$$l','${SRCLANG}','${TRGLANG}','${SRCLANG3}','${TRGLANG3}'); \
		  ${INSERT_INTO} links SELECT * FROM l.links; \
		  ${INSERT_INTO} linkedsource SELECT * FROM l.linkedsource; \
		  ${INSERT_INTO} linkedtarget SELECT * FROM l.linkedtarget;" \
	    | ${SQLITE3} ${LATEST_LINK_DB}; \
	    rm -f ${INDEX_TMPDIR}/$@; \
	    ${SCRIPTDIR}add_corpus_range.py -d ${LATEST_LINK_DB} -c $$c -v $$v -s ${SRCLANG} -t ${TRGLANG}; \
	    $(call unlockfile,${LATEST_LINK_DB}); \
	  else \
	    echo "release $$v is an older release for $$c"; \
	    $(call lockfile,${OLDER_LINK_DB}); \
	    $(call create_linkdb,${OLDER_LINK_DB}); \
	    echo "add links for $$c/$$v/${LINKDB_LANGPAIR} to link DB of older releases"; \
	    echo "ATTACH DATABASE '${INDEX_TMPDIR}/$@' as l; \
	          ${INSERT_INTO} corpora VALUES('$$c','$$v','${SRCLANG}','${TRGLANG}','${SRCLANG3}','${TRGLANG3}'); \
		  ${INSERT_INTO} links SELECT * FROM l.links; \
		  ${INSERT_INTO} linkedsource SELECT * FROM l.linkedsource; \
		  ${INSERT_INTO} linkedtarget SELECT * FROM l.linkedtarget;" \
	    | ${SQLITE3} ${OLDER_LINK_DB}; \
	    rm -f ${INDEX_TMPDIR}/$@; \
	    ${SCRIPTDIR}add_corpus_range.py -d ${OLDER_LINK_DB} -c $$c -v $$v -s ${SRCLANG} -t ${TRGLANG}; \
	    $(call unlockfile,${OLDER_LINK_DB}); \
	  fi; \
	fi
	@mkdir -p $(dir $@)
	@touch $@





##--------------------------------------------------------------------------------
## database of all bitexts and aligned corpra
## - copy from tables in alignment database and add language information
## - this very inefficident as the individual link files do not include language info
##   --> OPUS language IDs have to be inferred from the document paths
##   --> this is slow and error prone
##   --> should be changed in the future
##   --> or we only use the bitexts.db as the central database anyway
##--------------------------------------------------------------------------------

LANGPAIR_DBS = $(wildcard *-*.db)


bitexts.db: ${LANGPAIR_DBS}
	echo "${CREATE_TABLE} bitexts (bitextID,corpus TEXT,version TEXT,fromDoc TEXT,toDoc TEXT)" | sqlite3 $@
	echo "${CREATE_UNIQUE_INDEX} idx_bitexts ON bitexts (corpus,version,fromDoc,toDoc)" | sqlite3 $@
	echo "${CREATE_UNIQUE_INDEX} idx_bitext_ids ON bitexts (bitextID)" | sqlite3 $@
	echo "${CREATE_INDEX} idx_corpus ON bitexts (corpus,version)" | sqlite3 $@
	echo "${CREATE_TABLE} corpora (corpus TEXT,version TEXT,srclang TEXT,trglang TEXT,srclang3 TEXT,trglang3 TEXT)" | sqlite3 $@
	echo "${CREATE_UNIQUE_INDEX} idx_corpora ON corpora (corpus,version,srclang,trglang,srclang3,trglang3)" | sqlite3 $@
	for d in $?; do \
	  echo "processing $$d"; \
	  echo "ATTACH DATABASE '$$d' as l; \
	        ${INSERT_INTO} bitexts SELECT rowid, corpus, version, fromDoc, toDoc FROM l.bitexts; \
		${INSERT_INTO} corpora SELECT * FROM l.corpora;" | sqlite3 $@; \
	done


## OLD: add language to bitext tables --> avoid this expensive procedure
##      ---> now only in corpora table (see above) copied from existing databases
##
## - copy from tables in alignment database and add language information
## - this very inefficident as the individual link files do not include language info
##   --> OPUS language IDs have to be inferred from the document paths
##   --> this is slow and error prone
##   --> should be changed in the future
##   --> or we only use the bitexts.db as the central database anyway

bitexts-old.db: ${LANGPAIR_DBS}
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
	for d in $?; do \
	  S=`echo $$d | cut -f1 -d-`; \
	  T=`echo $$d | cut -f2 -d- | cut -f1 -d.`; \
	  P=`echo "select fromDoc,toDoc from bitexts" | sqlite3 -separator " " $$d | sed 's/\/[^ ]* /-/' | cut -f1 -d/ | sort -u | xargs`; \
	  for p in $$P; do \
	    s=`echo $$p | cut -f1 -d-`; \
	    t=`echo $$p | cut -f2 -d-`; \
	     echo "$$s $$t $$S $$T"; \
	     echo "ATTACH DATABASE '$$d' as l; \
	           ${INSERT_INTO} bitexts SELECT rowid, corpus, version, fromDoc, toDoc,\
                                                 '$$s','$$t','$$S','$$T' FROM l.bitexts \
	                                  WHERE fromDoc LIKE '$$s/%' AND toDoc LIKE '$$t/%';" \
	     | sqlite3 $@; \
	   done \
	done
	echo "${CREATE_TABLE} corpora (corpus TEXT,version TEXT,srclang TEXT,trglang TEXT,srclang3 TEXT,trglang3 TEXT)" | sqlite3 $@
	echo "${CREATE_UNIQUE_INDEX} idx_corpora ON corpora (corpus,version,srclang,trglang,srclang3,trglang3)" | sqlite3 $@
	echo "${INSERT_INTO} corpora SELECT DISTINCT corpus,version,srclang,trglang,srclang3,trglang3 FROM bitexts" | sqlite3 $@


##--------------------------------------------------
## add corpora tables that include language info
## --> just in case this has not been done yet
##--------------------------------------------------

CORPORA_LINK_DBS = $(patsubst %.db,%.corpora.db,$(wildcard *-*.db) $(wildcard sqlite/*-*.db))

add-corpora2linkdb: $(CORPORA_LINK_DBS)

%.corpora.db: %.db
	echo "${CREATE_TABLE} corpora (corpus TEXT,version TEXT,srclang TEXT,trglang TEXT,srclang3 TEXT,trglang3 TEXT)" | sqlite3 $<
	echo "${CREATE_UNIQUE_INDEX} idx_corpora ON corpora (corpus,version,srclang,trglang,srclang3,trglang3)" | sqlite3 $<
	( S=$(firstword $(subst -, ,$(notdir $(<:.db=)))); \
	  T=$(lastword $(subst -, ,$(notdir $(<:.db=)))); \
	  P=`echo "select fromDoc,toDoc from bitexts" | sqlite3 -separator " " $< | sed 's/\/[^ ]* /-/' | cut -f1 -d/ | sort -u | xargs`; \
	  for p in $$P; do \
	    s=`echo $$p | cut -f1 -d-`; \
	    t=`echo $$p | cut -f2 -d-`; \
	    echo "$$s $$t $$S $$T"; \
	    echo "${INSERT_INTO} corpora SELECT DISTINCT corpus, version,'$$s','$$t','$$S','$$T' \
                                         FROM bitexts \
	                                 WHERE fromDoc LIKE '$$s/%' AND toDoc LIKE '$$t/%';" \
	    | sqlite3 $<; \
	  done )
	${SCRIPTDIR}add_corpus_range.py -d $<


##--------------------------------------------------
## check corpus ranges
## - re-run link extraction if there are overlaps in rowid ranges
##--------------------------------------------------

CHECK_LINK_DBS = $(patsubst %.db,%.check.db,$(wildcard *-*.db))

check-linkdb-overlaps: $(CHECK_LINK_DBS)
remove-linkdb-overlaps:
	${MAKE} RERUN_LINK_EXTRACTION=1 check-linkdb-overlaps

%.check.db: %.db
	@if [ ! -s $< ]; then \
	  if [ -s $<.backup ]; then mv -f $<.backup $<; fi; \
	  if [ -s sqlite/$<.backup ]; then mv -f sqlite/$<.backup sqlite/$<; fi; \
	fi
	@if [ "${RERUN_LINK_EXTRACTION}" == "1" ]; then ${MAKE} $(<:.db=.corpora.db); fi
	@if [ `scripts/check_corpus_ranges.py $< | wc -l` -gt 0 ]; then \
	  echo "# overlaps in $<"; \
	  P=`scripts/check_corpus_ranges.py $< | cut -f3,4 -d, | cut -f1 -d' ' | sort -u | tr ',' '-'`;\
	  if [ "${RERUN_LINK_EXTRACTION}" == "1" ]; then \
	    mv $< $<.backup; \
	    mv sqlite/$< sqlite/$<.backup; \
	  fi; \
	  for p in $$P; do \
	    s=`echo $$p | cut -f1 -d-`; \
	    t=`echo $$p | cut -f2 -d-`; \
	    if [ $$s \< $$t ]; then l="$$s-$$t"; else l="$$t-$$s"; fi; \
	    echo "find done -name '$$l.*' -delete"; \
	    echo "find sqlite -name '$$p.*' -delete"; \
	    echo "make LANGPAIR=$$l all-links"; \
	    if [ "${RERUN_LINK_EXTRACTION}" == "1" ]; then \
	      find done -name "$$l.*" -delete; \
	      find sqlite -name "$$p.*" -delete; \
	      ${MAKE} LANGPAIR=$$l all-links; \
	    fi; \
	  done; \
	fi

BACKUP_LINK_DBS = $(wildcard *-*.db.backup) $(wildcard sqlite/*-*.db.backup)

restore-linkdb-backups:
	@for f in ${BACKUP_LINK_DBS}; do \
	  d=`echo $$f | sed 's/\.backup$$//'`; \
	  if [ ! -s $$d ]; then \
	    if [ -s $$f ]; then \
	      echo "mv -f $$f $$d"; \
	      mv -f $$f $$d; \
	    fi \
	  fi \
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
	$(call retrieve,$(notdir $@))
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
	$(call retrieve,$@)
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


.PHONY: opensub-docs
opensub-docs:
	${MAKE} CORPUS=OpenSubtitles VERSION=v2018 LANGUAGE=en corpus-docs
	${MAKE} CORPUS=OpenSubtitles VERSION=v2018 LANGUAGE=en corpus-docs

.PHONY: europarl-docs
europarl-docs:
	${MAKE} CORPUS=Europarl VERSION=v8 LANGUAGE=en corpus-docs
	${MAKE} CORPUS=Europarl VERSION=v8 LANGUAGE=en corpus-docs

.PHONY: unpc-docs
unpc-docs:
	${MAKE} CORPUS=UNPC VERSION=v1.0 LANGUAGE=en corpus-docs
	${MAKE} CORPUS=UNPC VERSION=v1.0 LANGUAGE=en corpus-docs

.PHONY: corpus-docs
corpus-docs: ${CORPUS}_${VERSION}.${LANGUAGE}.jsonl.gz ${CORPUS}_${VERSION}.${LANGUAGE}.txt.gz

${CORPUS}_${VERSION}.${LANGUAGE}.jsonl.gz:
	${SCRIPTDIR}/opus_get_documents.py -c ${CORPUS} -r ${VERSION} -l ${LANGUAGE} -j | ${GZIP} -c > $@

${CORPUS}_${VERSION}.${LANGUAGE}.txt.gz:
	${SCRIPTDIR}/opus_get_documents.py -c ${CORPUS} -r ${VERSION} -l ${LANGUAGE} | ${GZIP} -c > $@



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






## retrieving files from the storage
## (if they exist and file-retrieval is not disabled)

# GIT_RAW_URL := https://raw.githubusercontent.com/Helsinki-NLP/OpusIndex/refs/heads/
# GIT_BRANCH  := ${shell git rev-parse --abbrev-ref HEAD}
# INDEX_FILE_LIST := ${GIT_RAW_URL}${GIT_BRANCH}/index.txt
# INDEX_FILE_LIST := ${STORAGE_BASE}index/index.txt

ifneq (${SKIP_FILE_RETRIEVAL},1)
retrieve = $(shell \
	if [ ! -e ${1} ]; then \
	  if [ `grep '${1}' index.txt | wc -l` -gt 0 ]; then \
	    mkdir -p $(dir ${1}); \
	    wget -qq -O ${1} ${STORAGE_BASE}index/${1}; \
	  fi \
	fi )
else
retrieve = echo "downloading files is disabled (skip retrieving $1)"
endif

lockfile = ( while [ -e ${1}.lock ]; do \
	       echo "waiting for exclusive access to ${1}"; \
	       sleep 10; \
	       find $(dir ${1}) -name $(notdir ${1}).lock -mtime +1 -delete; \
	     done; \
	     touch ${1}.lock; )

unlockfile = rm -f ${1}.lock


test-lock:
	@$(call lockfile,test)

## OLD: retrieve files from storage as a PHONY make target
## --> this is slow because of a separate make call
## --> use retrieve-function above instead with 'call'

.PHONY: retrieve
retrieve:
ifneq (${SKIP_FILE_RETRIEVAL},1)
	@if [ ! -e ${STORED_FILE} ]; then \
	  if [ `grep '${STORED_FILE}' index.txt | wc -l` -gt 0 ]; then \
	    echo "download ${STORED_FILE}"; \
	    wget -qq ${STORAGE_BASE}index/${STORED_FILE}; \
	  fi \
	fi
endif

