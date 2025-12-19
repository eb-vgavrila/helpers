curl -s https://status.snapcraft.io/rss > snap_status.xml

RSS_DISABLED=$(cat snap_status.xml | grep 'RSS feed disabled for this page')
if [[ $RSS_DISABLED == *'RSS feed disabled'* ]]; then echo "RSS status is unavailable. Winging it!"; exit 0; fi

# Extract "Snap downloads" status from the minified XML using sed to extract the description
SNAP_STATUS=$(cat snap_status.xml | sed -n 's/.*<description>Snap downloads is \([^<]*\)<\/description>.*/\1/p')
PUB_DATE=$(cat snap_status.xml | sed -n 's/.*<pubDate>\([^<]*\)<\/pubDate>.*/\1/p' | head -1)

if [[ $SNAP_STATUS != *"Operational"* ]]; then echo "$SNAP_STATUS at $PUB_DATE. Halting the pipeline!"; exit 18;
else echo "$SNAP_STATUS at $PUB_DATE"; fi
