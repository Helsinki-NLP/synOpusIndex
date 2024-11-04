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


ALL_ALG_URLS  := $(sort $(patsubst %,https:%,$(shell find ${OPUSRELEASE}/ -name statistics.yaml | \
						xargs grep 'xml/${LANGPAIR}.xml.gz' | cut -f4 -d:)))
ALL_ALG_DONE  := $(patsubst ${STORAGE_BASE}%.xml.gz,done/%.done,${ALL_ALG_URLS})
ALL_LINK_DONE := $(patsubst ${STORAGE_BASE}%.xml.gz,done/%.linkdb.done,${ALL_ALG_URLS})
ALL_LINKS_DONE := $(patsubst ${STORAGE_BASE}%/xml/,done/%/${LANGPAIR3}.done,$(dir ${ALL_ALG_URLS}))

ALL_ALG_CORPORA_DONE  := $(patsubst ${STORAGE_BASE}%.xml.gz,done/%.corpora.done,${ALL_ALG_URLS})



## alignment databases
##
##   ALIGN_DB       = all alignments from all corpora (pointing to OPUS sentence IDs)
##   LATEST_LINK_DB = links from latest releases (pointing to sentence index IDs)
##   OLDER_LINK_DB  = links from other releases (pointing to sentence index IDs)

ALIGN_DB       := ${LANGPAIR3}.db
LINK_DB        := linkdb/${LANGPAIR3}.db
LATEST_LINK_DB := sqlite/${LANGPAIR3}.db
OLDER_LINK_DB  := sqlite/${LANGPAIR3}.releases.db


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
		${LANGUAGE_DEDUP} \
		${LATEST_LINK_DB} \
		${OLDER_LINK_DB}


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

#	@$(call retrieve,${LATEST_LINK_DB})
#	@$(call retrieve,${OLDER_LINK_DB})


.PHONY: aligndb
aligndb: ${ALIGN_DB}

.PHONY: linkdb
linkdb: ${LINK_DB}
# linkdb: ${LATEST_LINK_DB}


TMP_ALIGN_DB       := ${INDEX_TMPDIR}/${ALIGN_DB}
TMP_LINK_DB        := ${INDEX_TMPDIR}/${LINK_DB}
# TMP_LATEST_LINK_DB := ${INDEX_TMPDIR}/${LATEST_LINK_DB}
# TMP_OLDER_LINK_DB  := ${INDEX_TMPDIR}/${OLDER_LINK_DB}

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


# linkdb-local-old:
# 	@$(call lockfile,${LATEST_LINK_DB})
# 	@$(call lockfile,${OLDER_LINK_DB})
# 	@echo "make link DBs in ${INDEX_TMPDIR}"
# 	@mkdir -p $(dir ${TMP_LATEST_LINK_DB}) $(dir ${TMP_OLDER_LINK_DB})
# 	if [ -s ${LATEST_LINK_DB} ]; then rsync ${LATEST_LINK_DB} ${TMP_LATEST_LINK_DB}; fi
# 	if [ -s ${OLDER_LINK_DB} ];  then rsync ${OLDER_LINK_DB} ${TMP_OLDER_LINK_DB}; fi
# 	@${MAKE} LATEST_LINK_DB=${TMP_LATEST_LINK_DB} OLDER_LINK_DB=${TMP_OLDER_LINK_DB} linkdb
# 	if [ -s ${TMP_LATEST_LINK_DB} ]; then mv -f ${TMP_LATEST_LINK_DB} ${LATEST_LINK_DB}; fi
# 	if [ -s ${TMP_OLDER_LINK_DB} ];  then mv -f ${TMP_OLDER_LINK_DB} ${OLDER_LINK_DB}; fi
# 	@$(call unlockfile,${LATEST_LINK_DB})
# 	@$(call unlockfile,${OLDER_LINK_DB})




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


all-langpairs: ${LANGPAIRS}

${LANGPAIRS}:
	@if [ $(firstword $(subst -, ,$@)) \< $(lastword $(subst -, ,$@)) ]; then \
	  echo "make -j1 LANGPAIR=$@ all-links"; \
	  make -j1 LANGPAIR=$@ all-links; \
	fi

.PHONY: check-links
check-links:
	@$(call retrieve,${ALIGN_DB})
	@$(call retrieve,${LATEST_LINK_DB})
	@$(call retrieve,${OLDER_LINK_DB})
	if [ `echo "SELECT rowid FROM corpora WHERE srclang='${SRCLANG}' AND trglang='${TRGLANG}'" | sqlite3 ${ALIGN_DB} | wc -l` -eq 0 ]; then \
	  find done -name ${LANGPAIR}.done -delete; \
	  ${MAKE} aligndb-local; \
	fi
	if [ `echo "SELECT rowid FROM corpora WHERE srclang='${SRCLANG}' AND trglang='${TRGLANG}'" | sqlite3 ${LATEST_LINK_DB} | wc -l` -eq 0 ]; then \
	  find done -name ${LANGPAIR}.linkdb.done -delete; \
	  ${MAKE} linkdb-local; \
	fi



.PHONY: counts
counts: stats/${LANGUAGE}.counts

.PHONY: dedup
dedup: ${LANGUAGE_DEDUP}



STORAGE_FILES := ${LANGUAGE_SENT_DB} ${LANGUAGE_IDX_DB} ${LANGUAGE_FTS_DB} ${ALIGN_DB}
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
	git add index.txt


.PHONY: upload-all
upload-all:
	which a-put
	swift upload OPUS-index ${SWIFT_PARAMS} *.db
	find sqlite -name '*.db' -exec swift upload OPUS-index ${SWIFT_PARAMS} {} \;
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

${ALIGN_DB}: ${ALL_ALG_DONE}

${ALL_ALG_DONE}:
	@echo "processing $(@:.done=.xml.gz)"
	@mkdir -p $(dir ${ALIGN_DB})
	@$(call lockfile,${ALIGN_DB})
	@$(call create_algdb,${ALIGN_DB})
	@wget -qq -O - $(patsubst done/%.done,${STORAGE_BASE}%.xml.gz,$@) \
	| gzip -cd \
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




# ## add correct corpora table with column for indicating the latest release

# DONE_LANGPAIRS = $(shell find done -name '*-*.done' | cut -f5 -d/ | cut -f1 -d. | sort -u)

# correct-all-corpus-table:
# 	find done -name '*.corpora.done' -delete
# 	for d in $(wildcard *-*.db); do \
# 	  echo "DROP TABLE IF EXISTS corpora" | sqlite3 $$d; \
# 	done
# 	for p in ${DONE_LANGPAIRS}; do \
# 	  echo "make LANGPAIR=$$p correct-corpus-table"; \
# 	  make LANGPAIR=$$p correct-corpus-table; \
# 	done


# correct-corpus-table:
# 	@$(call lockfile,${ALIGN_DB})
# 	@$(call update_algdb,${ALIGN_DB})
# 	@${MAKE} add-correct-corpus-table
# 	@$(call unlockfile,${ALIGN_DB})

# add-correct-corpus-table: ${ALL_ALG_CORPORA_DONE}

# ${ALL_ALG_CORPORA_DONE}:
# 	@echo "processing $(@:.corpora.done=.xml.gz)"
# 	@mkdir -p $(dir ${ALIGN_DB})
# 	@( c=$(word 2,$(subst /, ,$@)); \
# 	   v=$(word 3,$(subst /, ,$@)); \
# 	   l=`grep 'latest_release:' ${OPUSRELEASE}/$$c/info.yaml | cut -f2 -d' ' | xargs`; \
# 	   if [ ! -e ${OPUSRELEASE}/$$c/$$l/statistics.yaml ] || \
# 	      [ `grep '$(notdir $(@:.corpora.done=.xml.gz))' ${OPUSRELEASE}/$$c/$$l/statistics.yaml | wc -l` -eq 0 ]; then \
# 	      l=`grep '$(notdir $(@:.corpora.done=.xml.gz))' ${OPUSRELEASE}/$$c/index.txt | tail -1 | cut -f1 -d/`; \
# 	   fi; \
# 	   if [ "$$v" == "$$l" ]; then \
# 	     echo "release $$v is the latest release for $$c"; \
# 	     echo "UPDATE corpora SET latest=0 WHERE corpus='$$c' AND srclang='${SRCLANG}' AND trglang='${TRGLANG}'; \
# 	           ${INSERT_INTO} corpora VALUES('$$c','$$v','${SRCLANG}','${TRGLANG}','${SRCLANG3}','${TRGLANG3}',1);" \
# 	     | sqlite3 ${ALIGN_DB}; \
# 	   else \
# 	     echo "release $$v is an older release for $$c"; \
# 	     echo "${INSERT_INTO} corpora VALUES('$$c','$$v','${SRCLANG}','${TRGLANG}','${SRCLANG3}','${TRGLANG3}',0)" \
# 	     | sqlite3 ${ALIGN_DB}; \
# 	   fi )
# 	@mkdir -p $(dir $@)
# 	@touch $@




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
	@echo "processing $(@:.done=.xml.gz)"
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
## database of linked source and target sentences
##  --> maps internal sentence IDs to internal link IDs
##--------------------------------------------------------------------------------

${LATEST_LINK_DB}: ${ALL_LINK_DONE}
	@if [ -s ${LATEST_LINK_DB} ]; then \
	  $(call lockfile,${LATEST_LINK_DB}); \
	  ${SCRIPTDIR}add_bitext_range.py ${LATEST_LINK_DB}; \
	  echo "VACUUM;" | ${SQLITE3} ${LATEST_LINK_DB}; \
	  $(call unlockfile,${LATEST_LINK_DB}); \
	fi
	@if [ -s ${OLDER_LINK_DB} ]; then \
	  $(call lockfile,${OLDER_LINK_DB}); \
	  ${SCRIPTDIR}add_bitext_range.py ${OLDER_LINK_DB}; \
	  echo "VACUUM;" | ${SQLITE3} ${OLDER_LINK_DB}; \
	  $(call unlockfile,${OLDER_LINK_DB}); \
	fi




## SQL comands to create a link database

CREATE_LINKDB := \
	${CREATE_TABLE} linkedsource (sentID INTEGER,linkID INTEGER,bitextID INTEGER,corpusID INTEGER,\
	                PRIMARY KEY(linkID,sentID) ); \
	${CREATE_TABLE} linkedtarget (sentID INTEGER,linkID INTEGER,bitextID INTEGER,corpusID INTEGER,\
	                PRIMARY KEY(linkID,sentID) ); \
	${CREATE_INDEX} idx_linkedsource_bitext ON linkedsource (corpusID,bitextID,sentID) ; \
	${CREATE_INDEX} idx_linkedtarget_bitext ON linkedtarget (corpusID,bitextID,sentID) ;\
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
	${CREATE_TABLE} corpora (corpusID INTEGER NOT NULL PRIMARY KEY,\
	                         corpus TEXT,version TEXT,srclang TEXT,trglang TEXT,\
	                         srclang3 TEXT,trglang3 TEXT,latest INTEGER); \
	${CREATE_UNIQUE_INDEX} idx_corpora ON corpora (corpus,version,srclang,trglang,srclang3,trglang3,latest); \
	${CREATE_UNIQUE_INDEX} idx_release ON corpora (corpus,version,srclang,trglang); \
	${CREATE_TABLE} bitexts (bitextID INTEGER NOT NULL PRIMARY KEY,\
	                         corpus TEXT,version TEXT,fromDoc TEXT,toDoc TEXT); \
	${CREATE_UNIQUE_INDEX} idx_bitexts ON bitexts (corpus,version,fromDoc,toDoc); \
	PRAGMA journal_mode=WAL;

#	ATTACH DATABASE '${ALIGN_DB}' as l; \
#	${INSERT_INTO} bitexts SELECT * FROM l.bitexts ORDER BY rowid;



## additional helper functions and variables

create_linkdb =	if [ ! -s $1 ]; then echo "create $1";mkdir -p $(dir $1); echo "${CREATE_LINKDB}" | ${SQLITE3} $1; fi
update_linkdb =	echo "create $1";mkdir -p $(dir $1); echo "${CREATE_LINKDB}" | ${SQLITE3} $1;


LINKDB_MATCH_CORPUS      := corpus='$$c' AND srclang='${SRCLANG}' AND trglang='${TRGLANG}'
LINKDB_MATCH_CORPUS_DOCS := corpus='$$c' AND fromDoc LIKE '${SRCLANG}/%' AND toDoc LIKE '${TRGLANG}/%'
LINKDB_CORPUS_SELECT     := SELECT DISTINCT rowid FROM bitexts WHERE ${LINKDB_MATCH_CORPUS_DOCS}
LINKDB_MATCH_BITEXT      := bitextID IN ( ${LINKDB_CORPUS_SELECT} )
LINKDB_COUNT_RELEASES    := echo "SELECT rowid FROM corpora WHERE ${LINKDB_MATCH_CORPUS}" \
				| ${SQLITE3} ${LATEST_LINK_DB} | wc -l


## extract linkdb data for a given corpus release
## merge all data into the central link DBs
##   - LATEST_LINK_DB for the latest corpus releases
##   - OLDER_LINK_DB for all other corpus releases


${ALL_LINK_DONE}: ${LINKDB_PREREQUISITES}

## create temporary database for the selected corpus/release/langpair

	@mkdir -p $(dir ${INDEX_TMPDIR}/$@) $(dir ${LATEST_LINK_DB}) $(dir ${OLDER_LINK_DB})
	${LINK2SQLITE} $^ ${INDEX_TMPDIR}/$@ $(word 2,$(subst /, ,$@)) $(word 3,$(subst /, ,$@))

## if the release is the latest one for that corpus/langpair
## --> move other release data (if they exist) from latest link DB to DB of other releases
## --> add links from temporary DB to latest link DB
## otherwise: add links from temporary DB to DB of other releases

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


##--------------------------------------------------
## add corpora tables that include language info
## --> just in case this has not been done yet
##--------------------------------------------------

CORPORA_LINK_DBS = $(patsubst %.db,%.corpora.db,$(wildcard *-*.db) $(wildcard sqlite/*-*.db))

add-corpora2linkdb: $(CORPORA_LINK_DBS)

%.corpora.db: %.db
	echo "${CREATE_TABLE} corpora (corpus TEXT,version TEXT,srclang TEXT,trglang TEXT,srclang3 TEXT,trglang3 TEXT,latest INTEGER)" | sqlite3 $<
	echo "${CREATE_UNIQUE_INDEX} idx_corpora ON corpora (corpus,version,srclang,trglang,srclang3,trglang3,latest)" | sqlite3 $<
	echo "${CREATE_UNIQUE_INDEX} idx_release ON corpora (corpus,version,srclang,trglang)" | sqlite3 $<
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


# CHECK_CORPORA_LINK_DBS = $(patsubst %.db,%.check-corpora.db,$(wildcard *-*.db) $(wildcard sqlite/*-*.db))
CHECK_CORPORA_LINK_DBS = $(patsubst %.db,%.check-corpora.db,$(wildcard sqlite/*-*.db))

check-corpora-table: $(CHECK_CORPORA_LINK_DBS)

%.check-corpora.db:
	@if [ `echo "SELECT name FROM sqlite_master WHERE type='table' AND name='corpora'" | sqlite3 $(@:.check-corpora.db=.db) | wc -l` -eq 0 ]; then \
	  echo "$(@:.check-corpora.db=.db) does not contain the necessary table corpora!"; \
	  ${MAKE} $(@:.check-corpora.db=.corpora.db); \
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

