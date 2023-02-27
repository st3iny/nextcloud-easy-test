#!/bin/bash

# Remove local remote script if already present
rm -f remote.sh

# Download remote script
if ! wget https://raw.githubusercontent.com/st3iny/nextcloud-easy-test/testing/remote.sh; then
    echo "Failed to download the remote script."
    exit 1
fi

# Execute it
if ! bash remote.sh; then
    exit 1
fi

# Start system cron
exec bash /cron.sh &

# Run the default CMD script
exec "$@"
