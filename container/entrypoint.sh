#!/bin/sh
set -e

# Initialize SSHITMAIDS_DEST if not set.
SSHITMAIDS_DEST="${SSHITMAIDS_DEST:-"git@github.com:22"}"

### Call reconfigure (idempotent rebuild)
# reconfigure.sh is always at /reconfigure (guaranteed by Dockerfile)
if [ -x /reconfigure ]; then
    echo "Calling reconfigure $SSHITMAIDS_DEST..."
    ./reconfigure "$SSHITMAIDS_DEST"
else
    echo "ERROR: /reconfigure not found. Image build failed."
    exit 1
fi

echo "Confirming sshd is running (in case reconfigure didn't start it)..."
if [ -n "$(ps -C sshd --no-headers)" ]; then
    echo "sshd is running."
else
    echo "ERROR: sshd is not running, startup failed. Check reconfigure logs for errors."
    exit 1
fi

echo "Container is ready. sshd is running and listening for client connections."
echo "Switching to log tailing mode."
exec tail -f /var/log/sshd.log