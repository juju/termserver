#!/bin/sh

# Check that the termserver is up and running on the given LXD instance.

set -e

if [ $# -ne 1 ]; then
    echo "instance name not provided"
    exit 1
fi

ADDR=`lxc info $1 | grep eth0 | grep -v inet6 | head -1 | awk '{print $3}'`
if [ -z "$ADDR" ]; then
    echo "no address found for $1"
    exit 1
fi

echo "connecting to $1 at http://$ADDR:8765/status"
curl -f -w '\n' http://$ADDR:8765/status
echo "check succeeded"
