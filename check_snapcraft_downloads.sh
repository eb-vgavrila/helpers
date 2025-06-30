#!/bin/bash

curl -s https://status.snapcraft.io/rss > snap_status.xml

RSS_DISABLED=$(cat snap_status.xml | grep 'RSS feed disabled for this page')
if [[ $RSS_DISABLED == *'RSS feed disabled'* ]]; then echo "RSS status is unavailable. Winging it!"; exit 0; fi

SNAP_STATUS=$(cat snap_status.xml | grep 'Snap downloads is' | cut -d '>' -f2 | cut -d '<' -f1)
PUB_DATE=$(cat snap_status.xml | grep -m 1 'pubDate' | cut -d '>' -f2 | cut -d '<' -f1)

if [[ $SNAP_STATUS != *"Operational"* ]]; then echo "$SNAP_STATUS at $PUB_DATE. Halting the pipeline!"; exit 99;
else echo "$SNAP_STATUS at $PUB_DATE"; fi
