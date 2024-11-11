
# todo list

* create index files for more languages and language pairs
* smarter way of downloading files needed for a new language pair in the opus-explorer
* reduce size (storing links with sentence IDs as plain text takes a lot of extra space)
* check full-text-search across all languages (tokenization issues?)


# errors in OPUS

* XLEnt has problems: ar-mkd --> mkd as arz? (in v1 and v1.1?)


# to be checked

* avoid creating fts5 databases from scratch each time there is an update
  - can use rowid's to determine what needs to be added?


# done

* fix corpus range (include opus lang codes? opus langpair?)
* cleanup bucket on allas and remove old files that are not needed anymore
* link DB only for latest version (avoid duplicated search results from different versions)
  * can use information in yaml files from OPUS releases
  * problem: need to update the index when new versions appear (i.e. we have to remove the old version!)

