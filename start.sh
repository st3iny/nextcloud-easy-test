#!/bin/bash

cd /tmp

# Remove local remote script if already present
rm -f remote.sh

# Download remote script
if ! wget https://raw.githubusercontent.com/st3iny/nextcloud-easy-test/enh/noid/k8s-operator/remote.sh; then
    echo "Failed to download the remote script."
    exit 1
fi

# Execute it
set -o pipefail
mkdir -p /var/log/remote.sh
if ! bash remote.sh 2>&1 | tee /var/log/promtail/remote.sh.log; then
    exit 1
fi

# Run the default CMD script
exec "$@"
