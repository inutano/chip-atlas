#!/bin/bash
# Usage:
# bash download-references.sh <minio-access-key> <minio-secret-key>

# Install mc command by apt if not found
which mc || (sudo apt-get update -y && sudo apt-get install -y mc)

# Set up mc command alias
mc alias set chip-atlas-dbcls https://chip-atlas.dbcls.jp ${1} ${2}

# Sync data/others/lib/genome_size
mc cp chip-atlas-dbcls/chip-atlas-data/others/lib/genome_size ${HOME}/chip-atlas/data/others/lib/genome_size

# Sync data/others/lib/id2symbol
mc cp chip-atlas-dbcls/chip-atlas-data/others/lib/id2symbol ${HOME}/chip-atlas/data/others/lib/id2symbol

# Sync data/others/lib/TSS
mc cp chip-atlas-dbcls/chip-atlas-data/others/lib/TSS ${HOME}/chip-atlas/data/others/lib/TSS

# Sync data/metadata/experimentList.tab
mc cp chip-atlas-dbcls/chip-atlas-data/metadata/experimentList.tab ${HOME}/chip-atlas/data/metadata/experimentList.tab

# Sync data/metadata/fileList.tab
mc cp chip-atlas-dbcls/chip-atlas-data/metadata/fileList.tab ${HOME}/chip-atlas/data/metadata/fileList.tab

# Sync data/others/lib/inSilicoChIP
mc cp chip-atlas-dbcls/chip-atlas-data/others/lib/inSilicoChIP ${HOME}/chip-atlas/data/others/lib/inSilicoChIP
