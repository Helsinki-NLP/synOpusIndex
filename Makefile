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

SCRIPTDIR    := scripts/

ifneq (${LANGPAIR3},${ISO_SRC3}-${ISO_TRG3})
  SRCLANG    := ${ISO_TRG2}
  TRGLANG    := ${ISO_SRC2}
  ALG2SQLITE := ${SCRIPTDIR}alg2sqlite.py -r
else
  SRCLANG    := ${ISO_SRC2}
  TRGLANG    := ${ISO_TRG2}
  ALG2SQLITE := ${SCRIPTDIR}alg2sqlite.py
endif

LINK2SQLITE  := ${SCRIPTDIR}links2sqlite.py
ALG2LINKS    := ${SCRIPTDIR}alg2links.py



LANGUAGE        ?= ${SRCLANG}
LANGUAGE3       := $(shell iso639 -n -m ${LANGUAGE})
LINKDB_LANGPAIR := ${SRCLANG}-${TRGLANG}


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

## all bitexts that need to be processed
## and flags indicating that a specific bitext is done

ALL_ALG_URLS   := $(sort $(patsubst %,https:%,$(shell find ${OPUSRELEASE}/ -name statistics.yaml | \
						xargs grep 'xml/${LANGPAIR}.xml.gz' | cut -f4 -d:)))
ALL_ALG_DONE   := $(patsubst ${STORAGE_BASE}%.xml.gz,done/%.done,${ALL_ALG_URLS})
ALL_LINKS_DONE := $(patsubst ${STORAGE_BASE}%/xml/,done/%/${LANGPAIR3}.done,$(dir ${ALL_ALG_URLS}))


## alignment databases
##
##   ALIGN_DB = all alignments from all corpora (pointing to OPUS sentence IDs)
##   LINK_DB  = alignment DB augmented with links pointing to sentence index IDs

ALIGN_DB       := ${LANGPAIR3}.db
LINK_DB        := linkdb/${LANGPAIR3}.db


## monolingual datasets and databases
## use standardized 3-letter codes for language DBs

LANGUAGE_DEDUP   := ${LANGUAGE}.dedup.gz
LANGUAGE_SENT_DB := ${LANGUAGE3}.db
LANGUAGE_FTS_DB  := ${LANGUAGE3}.fts5.db
LANGUAGE_IDX_DB  := ${LANGUAGE3}.ids.db
SRCLANG_IDX_DB   := ${SRCLANG3}.ids.db
TRGLANG_IDX_DB   := ${TRGLANG3}.ids.db


## files that we do not want to delete even if some kind of make target fails

.PRECIOUS: 	${LANGUAGE_SENT_DB} \
		${LANGUAGE_IDX_DB} \
		${LANGUAGE_FTS_DB} \
		${ALIGN_DB} \
		${LINK_DB} \
		${LANGUAGE_DEDUP}


## intermediate files that can be deleted after finishing up

.INTERMEDIATE: ${ALL_MONO_DEDUP}


## create link-db without parallel threads
## --> avoid errors with locked DB files
## --> avoid mixed rowid ranges for individual corpora

.PHONY: all
all: srclang trglang
	${MAKE} all-links

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
	@$(call lockfile,${LANGUAGE_SENT_DB})
	@$(call lockfile,${LANGUAGE_IDX_DB})
	${MAKE} ${LANGUAGE_IDX_DB}
	@$(call unlockfile,${LANGUAGE_IDX_DB})
	@$(call unlockfile,${LANGUAGE_SENT_DB})
	${MAKE} ${LANGUAGE_FTS_DB}

.PHONY: all-links
all-links:
	@$(call retrieve,${ALIGN_DB})
	@$(call retrieve,${LINK_DB})
	${MAKE} aligndb-local
	${MAKE} linkdb-local


.PHONY: all-langpairs
all-langpairs: ${LANGPAIRS}

${LANGPAIRS}:
	@if [ $(firstword $(subst -, ,$@)) \< $(lastword $(subst -, ,$@)) ]; then \
	  echo "make -j1 LANGPAIR=$@ all-links"; \
	  make -j1 LANGPAIR=$@ all-links; \
	fi

.PHONY: aligndb
aligndb: ${ALIGN_DB}

.PHONY: linkdb
linkdb: ${LINK_DB}


## run alignment extraction in temporary file locations
## --> much faster on fast local disks
## TODO: can we avoid syncing to temp if no update is needed?

TMP_ALIGN_DB := ${INDEX_TMPDIR}/${ALIGN_DB}
TMP_LINK_DB  := ${INDEX_TMPDIR}/${LINK_DB}

.PHONY: aligndb-local
aligndb-local:
	@$(call lockfile,${ALIGN_DB})
	@mkdir -p $(dir ${TMP_ALIGN_DB})
	@if [ -s ${ALIGN_DB} ]; then rsync ${ALIGN_DB} ${TMP_ALIGN_DB}; fi
	${MAKE} ALIGN_DB=${TMP_ALIGN_DB} aligndb
	@if [ -s ${TMP_ALIGN_DB} ]; then mv -f ${TMP_ALIGN_DB} ${ALIGN_DB}; fi
	@$(call unlockfile,${ALIGN_DB})

.PHONY: linkdb-local
linkdb-local:
	@mkdir -p $(dir ${LINK_DB}) $(dir ${TMP_LINK_DB})
	@$(call lockfile,${LINK_DB})
	@if [ -s ${LINK_DB} ]; then rsync ${LINK_DB} ${TMP_LINK_DB}; fi
	${MAKE} LINK_DB=${TMP_LINK_DB} linkdb
	@if [ -s ${TMP_LINK_DB} ]; then mv -f ${TMP_LINK_DB} ${LINK_DB}; fi
	@$(call unlockfile,${LINK_DB})


######################################
# some teporary target to do specific jobs
# - HPLT language pairs
# - redo things that were broken
# ....
######################################

HPLT_LANGS := ar bs ca et en eu fi ga gl hi hr is mk mt nn sq sr sw zh_hant
HPLT_PAIRS := $(foreach s,${HPLT_LANGS},$(foreach t,${HPLT_LANGS},$s-$t))
HPLT_ZH := $(foreach s,${HPLT_LANGS},$s-zh_hant)
HPLT_EN := $(foreach s,${HPLT_LANGS},$s-en en-$s)

hplt-pairs:
	make LANGPAIRS="${HPLT_PAIRS}" all-langpairs

hplt-zh:
	make LANGPAIRS="${HPLT_ZH}" all-langpairs

hplt-en:
	make LANGPAIRS="${HPLT_EN}" all-langpairs

zh:
	${MAKE} LANGPAIRS="en-zh en-zh_hant en-zh_cn en-zh_tw en_yue cmn-en" all-langpairs

redo-done:
	${MAKE} LANGPAIRS="$(shell find done -mindepth 4 -name '*-*.done' | cut -f5 -d/ | cut -f1 -d. | sort -u)" all-langpairs


redo-done-non-english:
	${MAKE} LANGPAIRS="$(shell find done -mindepth 4 -name '*-*.done' | cut -f5 -d/ | cut -f1 -d. | sort -u | grep -v 'en')" all-langpairs

redo-done-english:
	${MAKE} LANGPAIRS="$(shell find done -mindepth 4 -name '*-*.done' | cut -f5 -d/ | cut -f1 -d. | sort -u | grep 'en')" all-langpairs



######################################
######################################



.PHONY: counts
counts: stats/${LANGUAGE}.counts

.PHONY: dedup
dedup: ${LANGUAGE_DEDUP}


#--------------------------------------
# upload to allas (OnjectStorage@CSC)
#--------------------------------------

STORAGE_FILES := ${LANGUAGE_SENT_DB} ${LANGUAGE_IDX_DB} ${LANGUAGE_FTS_DB} ${ALIGN_DB} ${LINK_DB}
SWIFT_PARAMS  := --use-slo --segment-size 5G --changed --skip-identical

## add this before swift command?
#	${LOAD_STORAGE_ENV} && \

.PHONY: upload
upload:
	which a-put
	swift upload OPUS-index ${SWIFT_PARAMS} ${STORAGE_FILES}
	rm -f index.txt
	${MAKE} index.txt
	find done -name '${LANGUAGE}.done'  | xargs -n 500 git add
	find done -name '${LANGPAIR}.done'  | xargs -n 500 git add
	find done -name '${LANGPAIR3}.done' | xargs -n 500 git add
	git add index.txt


.PHONY: upload-all
upload-all:
	which a-put
	-swift upload OPUS-index ${SWIFT_PARAMS} *.db *.gz
	-find linkdb -name '*.db' -exec swift upload OPUS-index ${SWIFT_PARAMS} {} \;
	rm -f index.txt
	${MAKE} index.txt
	find done -name '*.done' | xargs -n 500 git add
	git add index.txt

upload-all2:
	which a-put
	-find linkdb -name '*.db' -exec swift upload OPUS-index ${SWIFT_PARAMS} {} \;
	rm -f index.txt
	${MAKE} index.txt
	find done -name '*.done' | xargs -n 500 git add
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



## open with timeout to allow concurrent access
## but that still does not seem to work well (skip timeout?)
SQLITE3             := sqlite3 -cmd ".timeout 100000"

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
	@$(call lockfile,$@)
	if [ -e $@ ]; then rsync $@ ${INDEX_TMPDIR}/$@; fi
	${GZIP} -cd < $< | ${SCRIPTDIR}sent2sqlite.py ${INDEX_TMPDIR}/$@
	mv -f ${INDEX_TMPDIR}/$@ $@
	echo "PRAGMA journal_mode=WAL" | sqlite3 $@
	@$(call unlockfile,$@)


## all sentences in all languages in one database
## --> that's going to be very big ....

opus.db: $(filter-out bitexts.db opus.db %.ids.db %.fts5.db $(wildcard *-*.db),$(wildcard *.db)))
	mkdir -p ${INDEX_TMPDIR}
	if [ -e $@ ]; then rsync $@ ${INDEX_TMPDIR}/$@; fi
	echo "${CREATE_TABLE} sentences ( sentence TEXT UNIQUE PRIMARY KEY NOT NULL )" \
	| sqlite3 ${INDEX_TMPDIR}/$@
	for d in $?; do \
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
	    $(call lockfile,$@); \
	    echo "ATTACH DATABASE '$<' as org; \
	          ${INSERT_INTO} sentences SELECT * FROM org.sentences WHERE rowid>$$b;" \
	    | sqlite3 $@; \
	    $(call unlockfile,$@); \
	  fi; \
	else \
	  $(call lockfile,$@); \
	  mkdir -p $(dir ${INDEX_TMPDIR}/$@); \
	  echo "CREATE VIRTUAL TABLE IF NOT EXISTS sentences USING FTS5(sentence)" \
	  | sqlite3 ${INDEX_TMPDIR}/$@; \
	  echo "ATTACH DATABASE '$<' as org; \
	        ${INSERT_INTO} sentences SELECT * FROM org.sentences;" \
	  | sqlite3 ${INDEX_TMPDIR}/$@; \
	  mv -f ${INDEX_TMPDIR}/$@ $@; \
	  $(call unlockfile,$@); \
	fi



##---------------------------------------
## sqlite database of all alignments
##---------------------------------------

## TODO: should we integrate the updates to the corpora and table to the ALG2SQLITE script?
##       should we also move table creation commands to the script (are they there already)

${ALIGN_DB}: ${ALL_ALG_DONE}

${ALL_ALG_DONE}:
	@echo "processing $(@:.done=.xml.gz)"
	@mkdir -p $(dir ${ALIGN_DB})
	@$(call lockfile,${ALIGN_DB})
	@$(call create_algdb,${ALIGN_DB})
	@wget -qq -O - $(patsubst done/%.done,${STORAGE_BASE}%.xml.gz,$@) | gzip -cd \
	| ${ALG2SQLITE} -d ${ALIGN_DB} -c $(word 2,$(subst /, ,$@)) -v $(word 3,$(subst /, ,$@))
	@( c=$(word 2,$(subst /, ,$@)); \
	   v=$(word 3,$(subst /, ,$@)); \
	   l=`grep 'latest_release:' ${OPUSRELEASE}/$$c/info.yaml | cut -f2 -d' ' | xargs`; \
	   if [ ! -e ${OPUSRELEASE}/$$c/$$l/statistics.yaml ] || \
	      [ `grep '$(notdir $(@:.done=.xml.gz))' ${OPUSRELEASE}/$$c/$$l/statistics.yaml | wc -l` -eq 0 ]; then \
	      l=`grep '$(notdir $(@:.done=.xml.gz))' ${OPUSRELEASE}/$$c/index.txt | tail -1 | cut -f1 -d/`; \
	   fi; \
	   if [ "$$v" == "$$l" ]; then \
	     echo "release $$v is the latest release for $$c"; \
	     echo "UPDATE corpora SET latest=0 WHERE corpus='$$c' AND srclang='${SRCLANG}' AND trglang='${TRGLANG}'; \
	           ${INSERT_INTO} corpora VALUES('$$c','$$v','${SRCLANG}','${TRGLANG}','${SRCLANG3}','${TRGLANG3}',1);" \
	     | sqlite3 ${ALIGN_DB}; \
	   else \
	     echo "release $$v is an older release for $$c"; \
	     echo "${INSERT_INTO} corpora VALUES('$$c','$$v','${SRCLANG}','${TRGLANG}','${SRCLANG3}','${TRGLANG3}',0)" \
	     | sqlite3 ${ALIGN_DB}; \
	   fi )
	@$(call unlockfile,${ALIGN_DB})
	@mkdir -p $(dir $@)
	@touch $@




## SQL comands to create the alignment database

CREATE_ALGDB := \
	  ${CREATE_TABLE} bitexts (corpus TEXT,version TEXT,fromDoc TEXT,toDoc TEXT); \
	  ${CREATE_UNIQUE_INDEX} idx_bitexts ON bitexts (corpus,version,fromDoc,toDoc); \
	  ${CREATE_TABLE} links ( bitextID, srcIDs TEXT, trgIDs TEXT, alignType TEXT, \
			          alignerScore REAL, cleanerScore REAL); \
	  ${CREATE_UNIQUE_INDEX} idx_links ON links (bitextID,srcIDs,trgIDs) ;\
	  ${CREATE_INDEX} idx_bitextid ON links (bitextID); \
	  ${CREATE_INDEX} idx_aligntype ON links (bitextID,alignType); \
	  ${CREATE_TABLE} corpora (corpus TEXT,version TEXT,srclang TEXT,trglang TEXT,srclang3 TEXT,trglang3 TEXT,latest INTEGER); \
	  ${CREATE_UNIQUE_INDEX} idx_corpora ON corpora (corpus,version,srclang,trglang,srclang3,trglang3,latest); \
	  ${CREATE_UNIQUE_INDEX} idx_release ON corpora (corpus,version,srclang,trglang); \
	  PRAGMA journal_mode=WAL;

create_algdb =	if [ ! -s $1 ]; then echo "create $1";mkdir -p $(dir $1); echo "${CREATE_ALGDB}" | ${SQLITE3} $1; fi
update_algdb =	echo "create $1";mkdir -p $(dir $1); echo "${CREATE_ALGDB}" | ${SQLITE3} $1;




##--------------------------------------------------------------------------------
## database of linked source and target sentences
##  --> maps internal sentence IDs to internal link IDs
##--------------------------------------------------------------------------------

${LINK_DB}: ${ALL_LINKS_DONE}

LINKDB_PREREQ_TMPDIR := ${INDEX_TMPDIR}/linkdbtmp
TMP_ALIGNMENT_DB     := ${LINKDB_PREREQ_TMPDIR}/${ALIGN_DB}
TMP_SRCLANG_IDX_DB   := ${LINKDB_PREREQ_TMPDIR}/${SRCLANG_IDX_DB}
TMP_TRGLANG_IDX_DB   := ${LINKDB_PREREQ_TMPDIR}/${TRGLANG_IDX_DB}
LINKDB_PREREQUISITES := ${TMP_ALIGNMENT_DB} ${TMP_SRCLANG_IDX_DB} ${TMP_TRGLANG_IDX_DB}

.INTERMEDIATE: ${LINKDB_PREREQUISITES}
${LINKDB_PREREQUISITES}: ${LINKDB_PREREQ_TMPDIR}/%: %
	mkdir -p $(dir $@)
	rsync -av $< $@

${ALL_LINKS_DONE}: ${LINKDB_PREREQUISITES}
	@echo "making $@"
	@mkdir -p $(dir ${LINK_DB})
	@$(call lockfile,${LINK_DB})
	${ALG2LINKS} 	-l ${LINK_DB} \
			-a ${TMP_ALIGNMENT_DB} \
			-s ${TMP_SRCLANG_IDX_DB} \
			-t ${TMP_TRGLANG_IDX_DB} \
			-c $(word 2,$(subst /, ,$@)) \
			-v $(word 3,$(subst /, ,$@)) \
			-s3 ${SRCLANG3} \
			-t3 ${TRGLANG3}
	@$(call unlockfile,${LINK_DB})
	@touch $@


##--------------------------------------------------------------------------------
## database of all bitexts and aligned corpra
##--------------------------------------------------------------------------------

LANGPAIR_DBS = $(wildcard *-*.db)

bitexts.db: ${LANGPAIR_DBS}
	echo "${CREATE_TABLE} bitexts (bitextID,corpus TEXT,version TEXT,fromDoc TEXT,toDoc TEXT)" | sqlite3 $@
	echo "${CREATE_UNIQUE_INDEX} idx_bitexts ON bitexts (corpus,version,fromDoc,toDoc)" | sqlite3 $@
	echo "${CREATE_UNIQUE_INDEX} idx_bitext_ids ON bitexts (bitextID)" | sqlite3 $@
	echo "${CREATE_INDEX} idx_corpus ON bitexts (corpus,version)" | sqlite3 $@
	echo "${CREATE_TABLE} corpora (corpusID,corpus TEXT,version TEXT,srclang TEXT,trglang TEXT,srclang3 TEXT,trglang3 TEXT, latest INTEGER)" | sqlite3 $@
	echo "${CREATE_UNIQUE_INDEX} idx_corpora ON corpora (corpus,version,srclang,trglang,srclang3,trglang3,latest)" | sqlite3 $@
	echo "${CREATE_UNIQUE_INDEX} idx_release ON corpora (corpus,version,srclang,trglang)" | sqlite3 $@
	for d in $?; do \
	  echo "processing $$d"; \
	  echo "ATTACH DATABASE '$$d' as l; \
	        ${INSERT_INTO} bitexts SELECT rowid,* FROM l.bitexts; \
		${INSERT_INTO} corpora SELECT rowid,* FROM l.corpora;" | sqlite3 $@; \
	done



##----------------------------------------------------------------------------------------
## some miscellaneous targets to check for certain issues
##   - check for empty bitexts (bitexts without non-empty links)
##   - check for empty coprora (corpora without bitexts)
##   - check that corpora-table exists and create if not
##----------------------------------------------------------------------------------------

## check link database and remove bitexts and corpora that do not have any non-empty link
## (this can happen if, for example, the sentence index DB is not complete or other issues)

ALL_LINK_DBS        := $(wildcard linkdb/*-*.db)
CHECK_EMPTY_BITEXTS := $(patsubst %.db,%.check-empty-bitexts.db,$(ALL_LINK_DBS))
CHECK_EMPTY_CORPORA := $(patsubst %.db,%.check-empty-corpora.db,$(ALL_LINK_DBS))
CHECK_CORPORA_TABLE := $(patsubst %.db,%.check-corpora-table.db,$(ALL_LINK_DBS))


.PHONY: check-empty-bitexts check-empty-corpora check-corpora-table
check-empty-bitexts: $(CHECK_EMPTY_BITEXTS)
check-empty-corpora: $(CHECK_EMPTY_CORPORA)
check-corpora-table: $(CHECK_CORPORA_TABLE)

## check link database and remove bitexts and corpora that do not have any non-empty link
## (this can happen if, for example, the sentence index DB is not complete or other issues)

%.check-empty-bitexts.db: %.db
	@echo "testing $<"
	@for c in `echo "select distinct bitextID from links where srcSentIDs='' or trgSentIDs=''" | sqlite3 $<`; do \
	  echo "testing bitext $$c"; \
	  if [ `echo "select rowid from links where bitextID=$$c and srcSentIDs<>'' limit 1" | sqlite3 $< | wc -l` -eq 0 ] || \
	     [ `echo "select rowid from links where bitextID=$$c and trgSentIDs<>'' limit 1" | sqlite3 $< | wc -l` -eq 0 ]; then \
	    echo "no links in $< for bitext with ID $$c"; \
	    echo "delete from links where bitextID=$$c"        | sqlite3 $<; \
	    echo "delete from linkedsource where bitextID=$$c" | sqlite3 $<; \
	    echo "delete from linkedtarget where bitextID=$$c" | sqlite3 $<; \
	    echo "delete from bitexts where bitextID=$$c"      | sqlite3 $<; \
	    echo "delete from bitext_range where bitextID=$$c" | sqlite3 $<; \
	  fi \
	done
	${MAKE} $(<:.db=.check-empty-corpora.db)

%.check-empty-corpora.db: %.db
	@for c in `echo "select corpusID,corpus,version,srclang,trglang from corpora" | sqlite3 $<`; do \
	  I=`echo $$c | cut -f1 -d\|`; \
	  C=`echo $$c | cut -f2 -d\|`; \
	  V=`echo $$c | cut -f3 -d\|`; \
	  S=`echo $$c | cut -f4 -d\|`; \
	  T=`echo $$c | cut -f5 -d\|`; \
	  echo "testing corpus $$C/$$V/$$S-$$T ($$I)"; \
	  if [ `echo "select bitextID from bitexts where corpus='$$C' and version='$$V' and fromDoc like '$$S/%' and toDoc like '$$T/%'" | sqlite3 $< | wc -l` -eq 0 ]; then \
	    echo "no bitexts in $< for corpus $$C/$$V/$$S-$$T"; \
	    echo "delete from corpora where corpusID=$$I"      | sqlite3 $<; \
	    echo "delete from corpus_range where corpusID=$$I" | sqlite3 $<; \
	    if [ -d done/$$C ]; then \
	      if [ -d done/$$C/$$V ]; then \
	        if [ -e done/$$C/$$V/xml/$$S-$$T.done ]; then \
	          rm -f done/$$C/$$V/xml/$$S-$$T.done; \
	        elif [ -e done/$$C/$$V/xml/$$T-$$S.done ]; then \
	          rm -f done/$$C/$$V/xml/$$T-$$S.done; \
	        fi \
	      fi \
	    fi; \
	  fi \
	done
	@echo "VACUUM" | sqlite3 $<
	@if [ `echo "select corpusID from corpora limit 1" | sqlite3 $< | wc -l` -eq 0 ]; then \
	  echo "no corpus in $< - remove the database"; \
	  rm -f $<; \
	  find done -maxdepth 4 -name '$(notdir $(<:.db=.done))' -delete; \
	fi


## add corpora table that includes language info
## in case it does not exist

%.check-corpora-table.db: %.db
	@if [ `echo "SELECT name FROM sqlite_master WHERE type='table' AND name='corpora'" | sqlite3 $< | wc -l` -eq 0 ]; then \
	  echo "$< does not contain the necessary table corpora!"; \
	  echo "${CREATE_TABLE} corpora (corpus TEXT,version TEXT,srclang TEXT,trglang TEXT,srclang3 TEXT,trglang3 TEXT,latest INTEGER)" | sqlite3 $<; \
	  echo "${CREATE_UNIQUE_INDEX} idx_corpora ON corpora (corpus,version,srclang,trglang,srclang3,trglang3,latest)" | sqlite3 $<; \
	  echo "${CREATE_UNIQUE_INDEX} idx_release ON corpora (corpus,version,srclang,trglang)" | sqlite3 $<; \
	  S=$(firstword $(subst -, ,$(notdir $(<:.db=)))); \
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
	  done; \
	  ${SCRIPTDIR}add_corpus_range.py -d $<; \
	fi



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

ifneq (${SKIP_FILE_RETRIEVAL},1)
retrieve = if [ ! -e ${1} ]; then \
	     if [ `grep '${1}' index.txt | wc -l` -gt 0 ]; then \
	       mkdir -p $(dir ${1}); \
	       wget -qq -O ${1} ${STORAGE_BASE}index/${1}; \
	     fi \
	   fi
else
retrieve = echo "downloading files is disabled (skip retrieving $1)"
endif

lockfile = ( while [ -e ${1}.lock ]; do \
	       echo "waiting for exclusive access to ${1}"; \
	       sleep 10; \
	       if [ -d $(dir ${1}) ]; then \
	         find $(dir ${1}) -name $(notdir ${1}).lock -mtime +1 -delete; \
	       else \
	         find . -maxdepth 1 -name $(notdir ${1}).lock -mtime +1 -delete; \
	       fi; \
	     done; \
	     touch ${1}.lock; )

unlockfile = rm -f ${1}.lock

