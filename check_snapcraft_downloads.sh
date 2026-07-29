#!/bin/bash
# Reports the Snapcraft "Snap downloads" component status.
#   exit 0  - Operational, or the status could not be determined (fail open)
#   exit 18 - confirmed not Operational

FEED_URL="${SNAP_STATUS_URL:-https://status.snapcraft.io/rss}"
ATTEMPTS="${SNAP_STATUS_ATTEMPTS:-10}"

FEED=$(mktemp) || exit 0
trap 'rm -f "$FEED"' EXIT

STATUS=
PUB_DATE=

for attempt in $(seq 1 "$ATTEMPTS"); do
  if ! curl -fsS --max-time 10 "$FEED_URL" -o "$FEED"; then
    sleep 1
    continue
  fi

  # status.snapcraft.io load-balances across backends and the unhealthy ones
  # answer HTTP 200 with a 4-byte non-XML body, so a retry may land elsewhere.
  if ! grep -q '<rss' "$FEED"; then
    sleep 1
    continue
  fi

  if grep -q 'RSS feed disabled for this page' "$FEED"; then
    echo "RSS status is unavailable. Winging it!"
    exit 0
  fi

  STATUS=$(sed -n 's/.*<description>Snap downloads is \([^<]*\)<\/description>.*/\1/p' "$FEED")
  PUB_DATE=$(sed -n 's/.*<pubDate>\([^<]*\)<\/pubDate>.*/\1/p' "$FEED" | head -1)
  [ -n "$STATUS" ] && break
  sleep 1
done

if [ -z "$STATUS" ]; then
  echo "Could not determine Snap downloads status from $FEED_URL after $ATTEMPTS attempts. Winging it!"
  exit 0
fi

if [[ $STATUS != *"Operational"* ]]; then
  echo "Snap downloads is $STATUS at $PUB_DATE. Halting the pipeline!"
  exit 18
fi

echo "Snap downloads is $STATUS at $PUB_DATE"
