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
LOAD_STORAGE_ENV := module load allas && allas-conf -k ${CSC_PROJECT}


## monolingual texts

LANGUAGE ?= en

INDEX_TMPDIR = ${TMPDIR}/index_tmp_${LANGUAGE}

ALL_MONO_URLS    := $(patsubst %,https:%,$(shell find ${OPUSRELEASE}/ -name statistics.yaml | \
			xargs grep 'mono/${LANGUAGE}.txt.gz' | cut -f4 -d:))
ALL_MONO_DEDUP   := $(patsubst ${STORAGE_BASE}%.txt.gz,${INDEX_TMPDIR}/%.dedup,${ALL_MONO_URLS})
ALL_MONO_IDX     := $(patsubst ${STORAGE_BASE}%.txt.gz,${INDEX_TMPDIR}/%.idx,${ALL_MONO_URLS})
ALL_MONO_JSONL   := $(patsubst ${STORAGE_BASE}%.txt.gz,${INDEX_TMPDIR}/%.jsonl,${ALL_MONO_URLS})
# DOC_MONO_JSONL   := $(filter-out ${INDEX_TMPDIR}/ELRA% \
# 				${INDEX_TMPDIR}/ELRC% \
# 				${INDEX_TMPDIR}/fiskmo% \
# 				${INDEX_TMPDIR}/DGT% \
# 				${INDEX_TMPDIR}/HPLT% \
# 				${INDEX_TMPDIR}/JRC-Acquis% \
# 				${INDEX_TMPDIR}/MultiHPLT% \
# 				${INDEX_TMPDIR}/NLLB% \
# 				${INDEX_TMPDIR}/WikiMatrix% \
# 				${INDEX_TMPDIR}/CCMatrix% \
# 				${INDEX_TMPDIR}/CCAligned% \
# 				${INDEX_TMPDIR}/MultiCCAligned% \
# 				${INDEX_TMPDIR}/WMT-News% \
# 				${INDEX_TMPDIR}/XLEnt% \
# 				${INDEX_TMPDIR}/LinguaTools-WikiTitles% \
# 				${INDEX_TMPDIR}/ParaCrawl% \
# 				${INDEX_TMPDIR}/MultiParaCrawl%,${ALL_MONO_JSONL})

ALL_MONO_DONE      := $(patsubst ${INDEX_TMPDIR}/%.dedup,done/%.done,${ALL_MONO_DEDUP})
ALL_MONO_IDXDONE   := $(patsubst ${INDEX_TMPDIR}/%.idx,done/%.idx.done,${ALL_MONO_IDX})
ALL_MONO_IDSDONE := $(patsubst ${INDEX_TMPDIR}/%.idx,done/%.ids.done,${ALL_MONO_IDX})
ALL_MONO_JSONLDONE := $(patsubst ${INDEX_TMPDIR}/%.jsonl,done/%.jsonl.done,${ALL_MONO_JSONL})

TMP_SENTENCE_DB  := ${INDEX_TMPDIR}/${LANGUAGE}-sentences.db



## alignment files

LANGPAIR ?= fi-sv
SRCLANG := $(firstword $(subst -, ,${LANGPAIR}))
TRGLANG := $(lastword $(subst -, ,${LANGPAIR}))

ALL_ALG_URLS      := $(patsubst %,https:%,$(shell find ${OPUSRELEASE}/ -name statistics.yaml | \
			xargs grep 'xml/${LANGPAIR}.xml.gz' | cut -f4 -d:))
ALL_ALG_DONE      := $(patsubst ${STORAGE_BASE}%.xml.gz,done/%.done,${ALL_ALG_URLS})


.PRECIOUS: 	${LANGUAGE}.db ${LANGUAGE}.ids.db ${LANGUAGE}.idx.db ${LANGPAIR}.db \
		${LANGUAGE}.idx.gz ${LANGUAGE}.dedup.gz 

## intermediate files that can be deleted after finishing up

.INTERMEDIATE: ${ALL_MONO_DEDUP}
.INTERMEDIATE: ${ALL_MONO_IDX}
.INTERMEDIATE: ${TMP_SENTENCE_DB}

# FIX_UNICODE := 	perl -CS -pe 'tr[\x{9}\x{A}\x{D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}][]cd;'
FIX_UNICODE := 	${PARALLEL} ftfy


.PHONY: all
all: ${LANGPAIR}.db
	${MAKE} LANGUAGE=${SRCLANG} all-mono
	${MAKE} LANGUAGE=${TRGLANG} all-mono

.PHONY: all-mono
all-mono: ${LANGUAGE}.counts
	${MAKE} ${LANGUAGE}.dedup.gz ${LANGUAGE}.db
	${MAKE} ${LANGUAGE}.ids.db
#	${MAKE} ${LANGUAGE}.idx.gz ${LANGUAGE}.idx.db

.PHONY: all-links
all-links: ${LANGPAIR}.db


.PHONY: counts
counts: ${LANGUAGE}.counts

.PHONY: dedup
dedup: ${LANGUAGE}.dedup.gz

.PHONY: jsonl
jsonl: ${LANGUAGE}.jsonl.gz

print-jsonl:
	@echo "${ALL_MONO_JSONLDONE}" | tr ' ' "\n"


# LANGUAGES = ar ca cs de en es et fi fo fr ga he hr lt lv nb nn no pt_br pt se sk sl sr sv sw uk zh_cn zh zh_tw
LANGUAGES = ar ca cs de es et fi fo fr ga he hr lt lv nb nn no pt_br pt se sk sl sr sv sw uk zh_cn zh zh_tw

FTS5_DBS = $(patsubst %,%.fts5.db,${LANGUAGES})

all-fts5: ${FTS5_DBS}



## in case the flags for finishing sentence extraction
## and we don't want to re-run all deduplication for all corpora
## --> run this temporary target to create all flags for all corpora
## --> WARNING: now you don't know whether things have been done

tmp-dedup-fix:
	touch ${ALL_MONO_DONE}
	touch ${LANGUAGE}.dedup.gz


SWIFT_PARAMS = --use-slo --segment-size 5G --changed --skip-identical

# STORAGE_FILES = ${LANGUAGE}.dedup.gz ${LANGUAGE}.db ${LANGUAGE}.idx.gz ${LANGUAGE}.idx.db ${LANGPAIR}.db
STORAGE_FILES = ${LANGUAGE}.dedup.gz ${LANGUAGE}.db ${LANGUAGE}.ids.db ${LANGPAIR}.db

.PHONY: upload
upload:
	which a-get
	${LOAD_STORAGE_ENV} && \
	swift upload OPUS-index ${SWIFT_PARAMS} ${STORAGE_FILES}
	rm -f index.txt
	${MAKE} index.txt
	find done -name '${LANGUAGE}.done' | xargs git add
	git add ${LANGUAGE}.counts index.txt


.PHONY: upload-all
upload-all:
	which a-get
	${LOAD_STORAGE_ENV} && swift upload OPUS-index ${SWIFT_PARAMS} *.dedup.gz *.db *.idx.gz
	rm -f index.txt
	${MAKE} index.txt
	find done -name '*.done' | xargs git add
	git add *.counts index.txt


index.txt:
	which a-get
	${LOAD_STORAGE_ENV} && swift list OPUS-index | grep '\.dedup.gz$$' | \
		sed 's#^#https://object.pouta.csc.fi/OPUS-index/#' > $@
	${LOAD_STORAGE_ENV} && swift list OPUS-index | grep '\.db$$'       | \
		sed 's#^#https://object.pouta.csc.fi/OPUS-index/#' >> $@
	${LOAD_STORAGE_ENV} && swift list OPUS-index | grep '\.idx.gz$$'   | \
		sed 's#^#https://object.pouta.csc.fi/OPUS-index/#' >> $@


index-filesize.txt:
	which a-get
	${LOAD_STORAGE_ENV} && rclone ls allas:OPUS-index | grep  '\.dedup.gz$$'  > $@
	${LOAD_STORAGE_ENV} && rclone ls allas:OPUS-index | grep  '\.db$$'       >> $@
	${LOAD_STORAGE_ENV} && rclone ls allas:OPUS-index | grep  '\.idx.gz$$'   >> $@




.PHONY: job-puhti
job-puhti:
	${MAKE} HPC_MEM=16g HPC_CORES=8 CORES=4 THREADS=4 HPC_DISK=1000 all.submit

.PHONY: job-puhti
dedup-job-puhti:
	${MAKE} HPC_MEM=16g HPC_CORES=8 CORES=4 THREADS=4 HPC_DISK=1000 dedup.submit


big-job-puhti:
	${MAKE} HPC_MEM=32g HPC_CORES=16 CORES=8 THREADS=8 HPC_DISK=3000 all.submit



## line (=sentence) count and word count
${LANGUAGE}.counts: ${ALL_MONO_DONE}
	${MAKE} ${LANGUAGE}.dedup.gz
	${GZIP} -cd ${LANGUAGE}.dedup.gz | wc -lw |\
	sed 's/^ *//;s/  */	/g' > $@


counts-from-storage:
	for l in aa ca cs de en es et eu fi fr ga nb nds nn no se sk sv; do \
	  wget -qq -O - ${STORAGE_BASE}index/$$l.dedup.gz |\
	  ${GZIP} -cd | wc -lw | sed 's/^ *//;s/  */	/g' > $$l.counts; \
	done


## merge all deduplicated files
## download the old dedup file in case it exists
## and no local file exists
${LANGUAGE}.dedup.gz: ${ALL_MONO_DONE}
	${MAKE} STORED_FILE=$@ retrieve
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


## create MCDB index databases
## OBSOLETE?

%.sent2id.db: %.dedup.gz
	mkdir -p ${INDEX_TMPDIR}
	${GZIP} -cd $< | ./add2mcdb.pl ${INDEX_TMPDIR}/$(notdir $@)
	mv -f ${INDEX_TMPDIR}/$(notdir $@) $@

%.id2sent.db: %.dedup.gz
	mkdir -p ${INDEX_TMPDIR}
	${GZIP} -cd $< | ./add2index.pl ${INDEX_TMPDIR}/$(notdir $@)
	mv -f ${INDEX_TMPDIR}/$(notdir $@) $@




## sqlite database of all sentences

${LANGUAGE}.db: ${LANGUAGE}.dedup.gz
	${MAKE} STORED_FILE=$@ retrieve
	${GZIP} -cd < $< | ./sent2sqlite.py ${INDEX_TMPDIR}/$@
	rsync ${INDEX_TMPDIR}/$@ $@
	echo "PRAGMA journal_mode=WAL" | sqlite3 $@


## create a full-text search database from the sentence DB
## TODO: fts5 DB should depend on sentence DB,
##       but we don't want to redo dedup.gz and the sentence DB if not needed

# %.fts5.db: %.db
# ${LANGUAGE}.fts5.db: ${LANGUAGE}.db
#	${MAKE} STORED_FILE=$@ retrieve
#	echo "CREATE VIRTUAL TABLE IF NOT EXISTS sentences USING FTS5(sentence)" | sqlite3 ${INDEX_TMPDIR}/$@
#	echo "ATTACH DATABASE '$<' as org;INSERT OR IGNORE INTO sentences SELECT * FROM org.sentences;" | sqlite3 $@
#	rsync ${INDEX_TMPDIR}/$@ $@

## fts DB without dependence


%.fts5.db:
	${MAKE} STORED_FILE=$@ retrieve
	echo "CREATE VIRTUAL TABLE IF NOT EXISTS sentences USING FTS5(sentence)" | sqlite3 ${INDEX_TMPDIR}/$@
	echo "ATTACH DATABASE '$(@:.fts5.db=.db)' as org;INSERT OR IGNORE INTO sentences SELECT * FROM org.sentences;" | sqlite3 ${INDEX_TMPDIR}/$@
	rsync ${INDEX_TMPDIR}/$@ $@



## sqlite database of all alignments

${LANGPAIR}.db: ${ALL_ALG_DONE}
	mv -f ${INDEX_TMPDIR}/$@ $@
	echo "CREATE TABLE IF NOT EXISTS aligned_corpora ( corpus TEXT, version TEXT)" | sqlite3 $@
	echo "CREATE UNIQUE INDEX idx_aligned_corpora ON aligned_corpora ( corpus, version )" | sqlite3 $@
	echo "INSERT OR IGNORE INTO aligned_corpora SELECT DISTINCT corpus,version FROM bitexts" | sqlite3 $@



${INDEX_TMPDIR}/${LANGPAIR}.db:
	${MAKE} STORED_FILE=${LANGPAIR}.db retrieve
	@if [ ! -e $@ ]; then \
	  echo "CREATE TABLE IF NOT EXISTS bitexts ( corpus TEXT, version TEXT, fromDoc TEXT, toDoc TEXT )" | sqlite3 $@; \
	  echo "CREATE UNIQUE INDEX IF NOT EXISTS idx_bitexts ON bitexts ( corpus, version, fromDoc, toDoc )" | sqlite3 $@; \
	  echo "CREATE TABLE IF NOT EXISTS links ( bitextID, srcIDs TEXT, trgIDs TEXT, alignType TEXT, \
			alignerScore REAL, cleanerScore REAL)" | sqlite3 $@; \
	  echo "CREATE UNIQUE INDEX IF NOT EXISTS idx_links ON links ( bitextID, srcIDs, trgIDs )" | sqlite3 $@; \
	  echo "CREATE INDEX IF NOT EXISTS idx_bitextid ON links ( bitextID )" | sqlite3 $@; \
	  echo "CREATE INDEX IF NOT EXISTS idx_aligntype ON links ( bitextID, alignType )" | sqlite3 $@; \
	fi

${ALL_ALG_DONE}: ${INDEX_TMPDIR}/${LANGPAIR}.db
	@echo "processing $(@:.done=.xml.gz)"
	@wget -qq -O - $(patsubst done/%.done,${STORAGE_BASE}%.xml.gz,$@) \
	| gzip -cd \
	| ./alg2sqlite.py $< $(word 2,$(subst /, ,$@)) $(word 3,$(subst /, ,$@))
	@mkdir -p $(dir $@)
	@touch $@



##------------------------------------------------------------
## bitext index with just one table (may become quite big!)
##------------------------------------------------------------

# ${LANGPAIR}.db: ${ALL_ALG_DONE}
# 	mv -f ${INDEX_TMPDIR}/$@ $@
# 	echo "CREATE TABLE IF NOT EXISTS aligned_corpora ( corpus TEXT, version TEXT)" | sqlite3 $@
# 	echo "CREATE UNIQUE INDEX idx_aligned_corpora ON aligned_corpora ( corpus, version )" | sqlite3 $@
# 	echo "INSERT OR IGNORE INTO aligned_corpora AS SELECT DISTINCT corpus,version FROM alignments" | sqlite3 $@
#
# ${INDEX_TMPDIR}/${LANGPAIR}.db:
# 	${MAKE} STORED_FILE=${LANGPAIR}.db retrieve
# 	if [ ! -e $@ ]; then \
# 	  echo "CREATE TABLE IF NOT EXISTS alignments ( corpus TEXT, version TEXT, fromDoc TEXT, toDoc TEXT, srcIDs TEXT, trgIDs TEXT, alignType TEXT, alignScore REAL, hunScore REAL, timeOverlap REAL, bicleanerScore REAL)" | sqlite3 $@; \
# 	  echo "CREATE INDEX idx_all ON alignments ( corpus, version, fromDoc, toDoc, alignType)" | sqlite3 $@; \
# 	  echo "CREATE INDEX idx_corpus ON alignments ( corpus, version )" | sqlite3 $@; \
# 	fi
#
# ${ALL_ALG_DONE}: ${INDEX_TMPDIR}/${LANGPAIR}.db
# 	@echo "processing $(@:.done=.xml.gz)"
# 	@wget -qq -O - $(patsubst done/%.done,${STORAGE_BASE}%.xml.gz,$@) \
# 	| gzip -cd \
# 	| ./alg2csv.py \
# 	| sed 's/^/$(word 2,$(subst /, ,$@)),$(word 3,$(subst /, ,$@)),/' \
# 	| sqlite3 $< ".import /dev/stdin alignments --csv"
# 	@mkdir -p $(dir $@)
# 	@touch $@


##------------------------------------------------------------------------------------
## sentence index that maps corpus-specific indeces to the ID in the sentence DB
##------------------------------------------------------------------------------------

sentence-index: ${LANGUAGE}.ids.db

${TMP_SENTENCE_DB}:
	mkdir -p $(dir $@)
	rsync ${LANGUAGE}.db $@

${LANGUAGE}.ids.db: ${ALL_MONO_IDSDONE}
	if [ -e ${TMP_SENTENCE_DB} ]; then rsync ${TMP_SENTENCE_DB} ${LANGUAGE}.db; fi
	if [ -e ${INDEX_TMPDIR}/$@ ]; then rsync ${INDEX_TMPDIR}/$@ $@; fi

${INDEX_TMPDIR}/${LANGUAGE}.ids.db:
	${MAKE} STORED_FILE=$(notdir $@) retrieve
	echo "CREATE TABLE IF NOT EXISTS documents ( corpus, version, document )" | sqlite3 $@
	echo "CREATE UNIQUE INDEX idx_documents ON documents (corpus,version,document)" | sqlite3 $@
	echo "CREATE TABLE IF NOT EXISTS sentids ( id INTEGER, docID INTEGER, sentID TEXT)" | sqlite3 $@
	echo "CREATE UNIQUE INDEX idx_sentids ON sentids ( docID, sentID)" | sqlite3 $@

${ALL_MONO_IDSDONE}: ${INDEX_TMPDIR}/${LANGUAGE}.ids.db ${TMP_SENTENCE_DB}
	@echo "process $@"
	@./sentid2sqlite.py \
		-i $< \
		-c $(word 2,$(subst /, ,$@)) \
		-r $(word 3,$(subst /, ,$@)) \
		-l ${LANGUAGE} \
		-d ${TMP_SENTENCE_DB}
	@mkdir -p $(dir $@)
	@touch $@



##-------------------------------------------------------------------------
## OLD format: all in one table also including parID and sentence length
## --> this grows big quite quickly
##-------------------------------------------------------------------------

${LANGUAGE}.idx.db: ${LANGUAGE}.idx.gz
	mkdir -p ${INDEX_TMPDIR}
	${MAKE} STORED_FILE=$@ retrieve
	echo "CREATE TABLE IF NOT EXISTS sentindex ( id, corpus, version, document, parID, sentID, length)" \
	| sqlite3 ${INDEX_TMPDIR}/$@
	echo "create index idx_all on sentindex (corpus,version,document,sentID);" | sqlite3 ${INDEX_TMPDIR}/$@
	echo "create index idx_corpus on sentindex (corpus,version);" | sqlite3 ${INDEX_TMPDIR}/$@
	${GZIP} -cd < $< | tr "\t" ',' | sqlite3  ${INDEX_TMPDIR}/$@ ".import /dev/stdin sentindex --csv"
	rsync ${INDEX_TMPDIR}/$@ $@

## merge index files into the existing list

${LANGUAGE}.idx.gz: ${ALL_MONO_IDXDONE}
	mkdir -p ${INDEX_TMPDIR}
	${MAKE} STORED_FILE=$@ retrieve
	if [ -e ${INDEX_TMPDIR}/$@ ]; then \
	  find ${INDEX_TMPDIR} -name '*.idx' | xargs cat <(${GZIP} -cd ${INDEX_TMPDIR}/$@) | ${GZIP} -c > $@; \
	else \
	  find ${INDEX_TMPDIR} -name '*.idx' | xargs cat | ${GZIP} -c > $@; \
	fi
	if [ -e ${TMP_SENTENCE_DB} ]; then rsync ${TMP_SENTENCE_DB} ${LANGUAGE}.db; fi

## create temporary index files for a specific corpus

${INDEX_TMPDIR}/%.idx: ${TMP_SENTENCE_DB}
	mkdir -p ${dir $@}
	./opus_sentid_index.py \
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
	echo "CREATE TABLE IF NOT EXISTS documents ( corpus, version, document )" | sqlite3 $@
	echo "CREATE UNIQUE INDEX idx_documents ON documents (corpus,version,document)" | sqlite3 $@
	echo "CREATE TABLE IF NOT EXISTS sentids ( id INTEGER, docID INTEGER, parID TEXT, sentID TEXT, length INTEGER)" | sqlite3 $@
	echo "CREATE UNIQUE INDEX idx_sentids ON sentids ( docID, sentID)" | sqlite3 $@
	echo "${SENTINDEX_VIEW}" | sqlite3 $@
	echo "${SENTINDEX_INSERT_TRIGGER}" | sqlite3 $@
	sqlite3 ${LANGUAGE}.idx.db ".dump sentindex" | sqlite3 $@ >$@.out 2>$@.err

##---------------------------------
## end of temporary fix to map old index to new format
##---------------------------------






## jsonl format

${LANGUAGE}.jsonl.gz: ${ALL_MONO_JSONLDONE}
	${MAKE} STORED_FILE=$@ retrieve
	if [ -e ${INDEX_TMPDIR}/$@ ]; then \
	  find ${INDEX_TMPDIR} -name '*.jsonl' | xargs cat <(${GZIP} -cd ${INDEX_TMPDIR}/$@) | ${GZIP} -c > $@; \
	else \
	  find ${INDEX_TMPDIR} -name '*.jsonl' | xargs cat | ${GZIP} -c > $@; \
	fi


#	./opus_get_documents.py -j -sp \

${INDEX_TMPDIR}/%.jsonl:
	mkdir -p ${dir $@}
	./opus_get_documents.py -j \
		-c $(word 1,$(subst /, ,$(patsubst ${INDEX_TMPDIR}/%.jsonl,%,$@))) \
		-r $(word 2,$(subst /, ,$(patsubst ${INDEX_TMPDIR}/%.jsonl,%,$@))) \
		-l ${LANGUAGE} > $@


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
	    cat $@ | ./sent2sqlite.py $(notdir $(@:.dedup=.db)); \
	  fi \
	fi

en.dedup.fixed.gz: en.dedup.gz
	${GZIP} -cd < $< | ${FIX_UNICODE} | ${GZIP} -c > $@
#	${GZIP} -cd < $< | ${FIX_UNICODE} | ${SORT} -u  | ${GZIP} -c > $@

en.dedup.missing.fixed.gz: en.dedup.missing.gz
	${GZIP} -cd < $< | ${FIX_UNICODE} | ${GZIP} -c > $@

en.dedup.all.gz:
	zcat en.dedup.done.gz en.dedup.missing.fixed.gz | ${GZIP} -c > $@


${ALL_MONO_DONE}: done/%.done: ${INDEX_TMPDIR}/%.dedup
	mkdir -p $(dir $@)
	touch $@

${ALL_MONO_JSONLDONE}: done/%.jsonl.done: ${INDEX_TMPDIR}/%.jsonl
	mkdir -p $(dir $@)
	touch $@




## retrieve a file from allas if it exists
## and sync it to the temporary file location as well

retrieve: ${INDEX_TMPDIR}/${STORED_FILE}

${INDEX_TMPDIR}/${STORED_FILE}:
	mkdir -p ${INDEX_TMPDIR}
	if [ ! -e ${STORED_FILE} ]; then \
	  if [ `grep '${STORED_FILE}' index.txt | wc -l` -gt 0 ]; then \
	    echo "download ${STORED_FILE}"; \
	    wget -qq ${STORAGE_BASE}index/${STORED_FILE}; \
	  fi \
	fi
	if [ -e ${STORED_FILE} ]; then \
	  rsync ${STORED_FILE} $@; \
	fi






## test targets


de.CCMatrix-v1.idx: de.sent2id.db
	perl opus_sentid_index.pl -c CCMatrix -r v1 -l de -d $< > $@

fi.OpenSubtitles-v2018.idx: fi.sent2id.db
	perl opus_sentid_index.pl -c OpenSubtitles -r v2018 -l fi -d $< > $@

sv.OpenSubtitles-v2018.idx: sv.sent2id.db
	perl opus_sentid_index.pl -c OpenSubtitles -r v2018 -l sv -d $< > $@

de.OpenSubtitles-v2018.idx: de.sent2id.db
	perl opus_sentid_index.pl -c OpenSubtitles -r v2018 -l de -d $< > $@

fi.Europarl-v8.idx: fi.sent2id.db
	perl opus_sentid_index.pl -c Europarl -r v8 -l fi -d $< > $@

sv.Europarl-v8.idx: sv.sent2id.db
	perl opus_sentid_index.pl -c Europarl -r v8 -l sv -d $< > $@


sv.OpenSubtitles-v2018.idx2: sv.sent2id.db
	cp $< ${LOCAL_SCRATCH}/$<
	perl opus_sentid_index.pl -c OpenSubtitles -r v2018 -l sv -d ${LOCAL_SCRATCH}/$< > $@

sv.OpenSubtitles-v2018.idx3:
	cp sv.db ${LOCAL_SCRATCH}/sv.db
	./opus_sentid_index.py -c OpenSubtitles -r v2018 -l sv -d ${LOCAL_SCRATCH}/sv.db > $@


# en.dedup.new.gz:
# 	gzip -cd en.dedup.gz | parallel --pipe --keep-order -q ${FIX_UNICODE} | gzip -c > $@

