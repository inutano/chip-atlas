#!/bin/bash
# Usage:
# bash download-references.sh <minio-access-key> <minio-secret-key>
set -eux

# Install mc command by apt if not found
if [[ ! -e $HOME/minio-binaries/mc ]]; then
  curl https://dl.min.io/client/mc/release/linux-amd64/mc \
    --create-dirs \
    -o $HOME/minio-binaries/mc
  chmod +x $HOME/minio-binaries/mc
fi
export PATH=$PATH:$HOME/minio-binaries/

# Set up mc command alias
. ${HOME}/.minio-env
mc alias set chip-atlas-dbcls https://chip-atlas.dbcls.jp ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY}

# Create directories
mkdir -p ${HOME}/chip-atlas/data/others/lib
mkdir -p ${HOME}/chip-atlas/data/metadata

# Sync data/others/lib/genome_size
mc cp --recursive chip-atlas-dbcls/data/others/lib/genome_size ${HOME}/chip-atlas/data/others/lib/

# Sync data/others/lib/id2symbol
mc cp --recursive chip-atlas-dbcls/data/others/lib/id2symbol ${HOME}/chip-atlas/data/others/lib/

# Sync data/others/lib/TSS
mc cp --recursive chip-atlas-dbcls/data/others/lib/TSS ${HOME}/chip-atlas/data/others/lib/

# Sync data/metadata/experimentList.tab
mc cp chip-atlas-dbcls/data/metadata/experimentList.tab ${HOME}/chip-atlas/data/metadata/experimentList.tab

# Sync data/metadata/fileList.tab
mc cp chip-atlas-dbcls/data/metadata/fileList.tab ${HOME}/chip-atlas/data/metadata/fileList.tab

# Sync data/others/lib/inSilicoChIP
mc cp --recursive chip-atlas-dbcls/data/others/lib/inSilicoChIP ${HOME}/chip-atlas/data/others/lib/
