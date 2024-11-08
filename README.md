
# OpusIndex

Various ways of indexing OPUS data. Index files can be used to retrieve sentences from various languages, match sentences with IDs in OPUS corpora etc. The SQLIite databases are also used by the OpusExplorer interface.


## Monolingual sentence index

Sentences are indexed per language using this procedure:

* extract all sentences from monolingual OPUS releases, sort and merge them into `xx.dedup.gz` files
* dump the sorted sentences into a database `xxx.db`
* create an index file that maps sentence IDs in that database to sentenceIDs in OPUS corpora (`xxx.ids.db`)

The last step may add sentences to the sentence DB if they are missing in the list extracted in step 1.
The tables are stored in different files because queries are faster when different files can be opened and each of them has its own cache. Note that `xxx` refers to three-letter ISO-639-3 language codes (using macro-language codes if available) whereas `xx` refers to the original language codes used in OPUS.

Optionally, one can also create a full-text-search index over sentences in yet another database `xxx.fts5.db`.


### Sentence DB `xxx.db`

* Table `sentences`

| column      | type                             |
|-------------|----------------------------------|
| rowid       | INTEGER UNIQUE                   |
| sentence    | TEXT UNIQUE PRIMARY KEY NOT NULL |


`rowid` is the automatically assigned row ID and will be used as unique key for each sentence.



### Sentence index DB `xxx.ids.db`

* Table `documents`:

| column      | type           |
|-------------|----------------|
| rowid       | INTEGER UNIQUE |
| corpus      | TEXT           |
| version     | TEXT           |
| document    | TEXT           |


Unique index over columns (corpus,version,document).
`rowid` is used as a unique document ID.

* Table `sentids`:

| column      | type           |
|-------------|----------------|
| id          | INTEGER        |
| docID       | INTEGER        |
| sentID      | TEXT           |


Unique index over columns (docID,sentID). `docID` correspond to rowid's in the `documents` table. `sentID` is taken from original sentence IDs in XML documents in OPUS. `id` corresponds to rowid's in the `sentences` table in the sentence DB.

There is also a view `sentindex` defined over an inner join between the tables `document` and `sentids`. An insert trigger can be used to directly insert data entries into both tables (joined over the `document.rowid` and `sentids.docID` fields).



### Full-text-search DB `xxx.fts5.db`

This database has the same structure as the sentence DB but uses the FTS5 extension of SQLite to enable full-text search over sentences. This is useful for querying the data with advanced and efficient search queries (see https://www.sqlitetutorial.net/sqlite-full-text-search/).



## Bitext alignment DB `xxx-yyy.db`

Sentence alignments are stored per language pair (source language `xxx` and target language `yyy` using ISO-639-3 language codes). There are three tables in the database similar to the monolingual sentence index DB but here focusing on bitexts and alignments:


* Table `corpora`:

| column      | type           |
|-------------|----------------|
| rowid       | INTEGER UNIQUE |
| corpus      | TEXT           |
| version     | TEXT           |
| srclang     | TEXT           |
| trglang     | TEXT           |
| srclang3    | TEXT           |
| trglang3    | TEXT           |
| latest      | INTEGER        |

The `rowid` will provide the internal ID used for the parallel corpus (referring to a specific language pair and corpus release, i.e. corpus/version/srclang-trglang). The original language IDs of the source language and target language used in OPUS are stored in `srclang` and `trglang`. Their mapping to 3-letter codes from ISO-639-3 (using macro-language codes if available) is stored in `srclang3` and `trglang3`.


* Table `bitexts`:

| column      | type           |
|-------------|----------------|
| rowid       | INTEGER UNIQUE |
| corpus      | TEXT           |
| version     | TEXT           |
| fromDoc     | TEXT           |
| toDoc       | TEXT           |


All information is directly taken from the XCES Align files in OPUS. `fromDoc` corresponds to the document name in the source language and `toDoc` to the aligned document in the target language. The automatically assigned `rowid` is, again, taken as a unique document ID (of this bitext). There is a unique index over columns (corpus, version, fromDoc, toDoc). `latest` is a binary flag with `1` indicating that this version is the latest release of that corpus.


* Table `links`:

| column       | type           |
|--------------|----------------|
| rowid        | INTEGER UNIQUE |
| bitextID     | INTEGER        |
| srcIDs       | TEXT           |
| trgIDs       | TEXT           |
| alignType    | TEXT           |
| alignerScore | REAL           |
| cleanerScore | REAL           |


`bitextID` corresponds to `rowid` in table `bitexs`. `srcIDs` and `trgIDs` are strings that correspond to lists of sentence IDs in OPUS (that should match `sentID` in the `sentids` table in the corresponding sentence indeces of source and target language). The strings are directly taken from the XCES Align files in OPUS (`xtargets` argument in sentence links). `alignType` specifies the alignment type in terms of the number of source and target sentences. For example, `2-1` refers to an alignment of 2 sentences in the source language aligned to one sentence in the target language. `alignerScore` is also taken from the original OPUS alignment files and may correspond to different scores depending on the tool used for producing the original bitext. If there is no score it will be set to 0. `cleanerScore` is reserved for an additional score that may be produced by tools like bicleaner or OpusFilter.

Similar to the sentence index DB, there is also a view `alignments` defined over tables `bitexts` and `links` that joins both tables over columns `bitexts.rowid` and `links.bitextID`. An insert trigger is also specified that allows to enter data for both tables if needed.



## Sentence Link DB `linkdb/xxx-yyy.db`

In order to search and browse through the bitexts in OPUS, there are also the following tables extracted from the databases described above. Those tables map internal sentence IDs to sentence alignments to avoid expensive joins over the sentence index table. There are four main tables in this database:

* `links`: Similar to the `links` table in the master alignment database but with additional fields `srcSentIDs` and `trgSentIDs` that provide the internal sentence IDs of aligned sentences corresponding to the `rowid` of the sentence table for each language. `linkID` corresponds to `rowid` in the master alignment file
* `linkedsource`: A table that maps internal sentence IDs of the source language (rowid's in the corresponding sentence DB) to sentence alignment IDs (`linkID` corresponding to `rowid` in the `links` table of the master alignment database)
* `linkedtarget`: The same mapping for linked target language sentences

There are also indivudual link DB's for each corpus release. They are stored in sub-directories of `sqlite` indicating the corpus name and release version.


* Table `links`:

| column       | type           |
|--------------|----------------|
| linkID       | INTEGER UNIQUE |
| bitextID     | INTEGER        |
| srcIDs       | TEXT           |
| trgIDs       | TEXT           |
| srcSentIDs   | TEXT           |
| trgSentIDs   | TEXT           |
| alignType    | TEXT           |
| alignerScore | REAL           |
| cleanerScore | REAL           |

The difference to the alignment DB is that we copy the `rowid` into the `linkID` to correctly map links. `srcSentIDs` and `trgSentIDs` have internal sentence IDs in plain text form (as there can be more than one sentence in a link). 


* Table `linkedsource`:

| column       | type           |
|--------------|----------------|
| sentID       | INTEGER        |
| linkID       | INTEGER        |
| bitextID     | INTEGER        |
| corpusID     | INTEGER        |

`(sentID,linkID)` is used as a unique primary key. `bitextID` and `corpusID` are added to make it possible to restrict the search to specific bitexts or parallel corpora.


* Table `linkedtarget`:

| column       | type           |
|--------------|----------------|
| sentID       | INTEGER        |
| linkID       | INTEGER        |
| bitextID     | INTEGER        |
| corpusID     | INTEGER        |

`(sentID,linkID)` is used as a unique primary key.



* Table `corpora`:

| column      | type           |
|-------------|----------------|
| corpusID    | INTEGER UNIQUE |
| corpus      | TEXT           |
| version     | TEXT           |
| srclang     | TEXT           |
| trglang     | TEXT           |
| srclang3    | TEXT           |
| trglang3    | TEXT           |
| latest      | INTEGER        |


This table is similar to the one in the master alignment DB but uses `corpusID` to correctly map the ID from that DB even if not all corpora are present in this DB. Only corpora added to the DB will be listed here.



* Table `bitexts`:

This is basically a copy of the same table from the bitext alignment DB `xx-yy.db` above but, again, using `bitextID` instead of `rowid` to properly map between the two.

| column      | type           |
|-------------|----------------|
| bitextID    | INTEGER UNIQUE |
| corpus      | TEXT           |
| version     | TEXT           |
| fromDoc     | TEXT           |
| toDoc       | TEXT           |




* Table `corpus_range` and `bitext_range`:

There are two additional tables to facilitate browsing through a coprus and a bitext with the possibility to jump to different positions. We assume links to appear without gaps in the `links` table and the following two tables save the first and last `linkID` for a parallel corpus or a bitext, respectively. With that we know the range of links in the alignment table that correspond to a specific corpus or bitext. The `corpus_range` table:

| column      | type           |
|-------------|----------------|
| corpusID    | INTEGER UNIQUE |
| start       | INTEGER        |
| end         | INTEGER        |

And similarly the `bitext_range` table:

| column      | type           |
|-------------|----------------|
| bitextID    | INTEGER UNIQUE |
| start       | INTEGER        |
| end         | INTEGER        |




## Creating and updating index files


There are various Makfile targets that support the creation and update of index files. The most generic command for creating / updating all files for a specific language pair would be:

```
make LANGPAIR=xx-yy all
```

`xx` refers to the source language ID and `yy` to the target language ID. This will create the bitext index and the monolingual sentence indeces. It will also create the sorted list if unique sentences for each language. Existing files will be re-used and updated. Make sure that there is enough space (also in TMPDIR). It will try to download files that have been uploaded to the OpusIndex bucket on [allas](https://docs.csc.fi/data/Allas/). It will also create flags in the sub-directory `done` for corpora and bitexts that are processed already. Those datasets will not be processed again.





### Working on HPC clusters with SLURM jobs

All Makefile targets can be queued as SLURM jobs by adding the suffix `.submit` to the make target. There are several variables that can be used to control the resources that should be allocated for the job (see [Makefile.submit](Makefile.submit) for more details). Note that this most likely needs some adjustments for your HPC environment.

The environment is now adjusted for [puhti at CSC](https://docs.csc.fi/computing/systems-puhti/).
There are also some example targets that show-case typical job requirements. For example, to run a typical generic target for indexing one language on puhti you can queue a SLURM job like this:

```
make LANGUAGE=de job-puhti
```


### Storing and retrieving files from Allas







### SQLite Performance tuning

* should use FTS5 for storing sentences (https://www.sqlitetutorial.net/sqlite-full-text-search/)
* https://phiresky.github.io/blog/2020/sqlite-performance-tuning/
* attach another database: https://www.sqlite.org/lang_attach.html
* write-ahead logging: https://www.sqlite.org/wal.html


### Links

* save query result in new table: https://stackoverflow.com/questions/57134793/how-to-save-query-results-to-a-new-sqlite
* DB analysis: https://stackoverflow.com/questions/5900050/sqlite-table-disk-usage










## Sentence lists and de-duplication index

Get all sentences for a given language, de-duplicate and then create an index over all sorted sentences.

* [De-duplicated lists of sorted sentences](index.txt) are available from the OPUS storage
* Sentence and word counts are in the files ending on `*.counts`

For example, create a list of sorted sentences for German and then dump them into a hashed DB:

```
make LANGUAGE=de dedup
make LANGUAGE=de sent2id
```











## MCDB-based index

MCDB is an implementation of a fast constant (not updatable) has table. It is used for creating a fixed sentence DB that can be used for lookup and de-duplication.

Install pre-requisites (on puhti):

```
module load perl
cpanm MCDB_File
```


There is also a script to create DB files for looking up sentences in a selected language (e.g. German) by their index. You can create them by running

```
make de.id2sent.db
```

This takes all monolingual corpus files from OPUS (need to be in the local OPUSNLPL path) in the selected language (de in the example above), de-duplicates and merges all of them and puts them into a database file (`de.sent2id.db` in the example above). This database provides a lookup table for all sentences as key and a unique ID as value.

Testing the lookup function is possible by running the `test_index.pl` script:

```
./test_index.pl de.id2sent.db 10000 5
```

This will print 5 sentences starting with index 10000. The index arguments are optional and default is starting at index 100 and printing 10 sentences.

Ready-made index files and de-duplicated data sets are available from allas. Download links are listed in [index.txt](index.txt).

The plain text files with de-duplicated sentences can also directly be used by the Berkeley RECNO database. For testing this, you need to unpack the `*.dedup.gz` of your choice and run `test_recno_index.pl` in the same way as the other test script.

```
gunzip de.dedup.gz
./test_recno_index.pl de.id2sent.db 10000 5
```



### Implementation

* based on https://github.com/gstrauss/mcdb
* Perl interface: https://metacpan.org/pod/MCDB_File
* python interface for mcdb: https://github.com/gstrauss/mcdb/blob/master/contrib/python-mcdb


alternative: cdb (but there is a 4gb file limit - so, doesn't work for big corpora)

* https://metacpan.org/pod/CDB_File
* https://pypi.org/project/python-cdb/
* https://pypi.org/project/pycdb/
* https://pypi.org/project/cdbx/ (http://opensource.perlig.de/cdbx/)
