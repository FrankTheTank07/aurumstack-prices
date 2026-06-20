#!/bin/bash
set -euo pipefail

# Ensure output directory exists
mkdir -p data

# The metals session runs from Sunday 17:00 through Friday 16:00 in Chicago,
# with a daily maintenance break from 16:00 to 17:00. Keep this guard for
# manual workflow runs as well as the narrower GitHub Actions schedule.
MARKET_DAY=${AURUMSTACK_MARKET_DAY:-$(TZ=America/Chicago date +%u)}
MARKET_HOUR=${AURUMSTACK_MARKET_HOUR:-$(TZ=America/Chicago date +%H)}
MARKET_HOUR=$((10#$MARKET_HOUR))

MARKET_IS_OPEN=false
case "$MARKET_DAY" in
  1|2|3|4)
    if (( MARKET_HOUR < 16 || MARKET_HOUR >= 17 )); then
      MARKET_IS_OPEN=true
    fi
    ;;
  5)
    if (( MARKET_HOUR < 16 )); then
      MARKET_IS_OPEN=true
    fi
    ;;
  7)
    if (( MARKET_HOUR >= 17 )); then
      MARKET_IS_OPEN=true
    fi
    ;;
esac

if [[ "$MARKET_IS_OPEN" != true ]]; then
  echo "Precious metals market is closed; skipping price update."
  exit 0
fi

# Data sources
GOLD_URL="https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/XAU/USD"
SILVER_URL="https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/XAG/USD"
CURL_OPTIONS=(
  --fail
  --silent
  --show-error
  --retry 3
  --retry-all-errors
  --connect-timeout 10
  --max-time 30
)

# Fetch data
GOLD_RESPONSE=$(curl "${CURL_OPTIONS[@]}" "$GOLD_URL")
SILVER_RESPONSE=$(curl "${CURL_OPTIONS[@]}" "$SILVER_URL")

# Extract bid/ask
GOLD_BID=$(echo "$GOLD_RESPONSE" | jq -r '.[0].spreadProfilePrices[0].bid // empty')
GOLD_ASK=$(echo "$GOLD_RESPONSE" | jq -r '.[0].spreadProfilePrices[0].ask // empty')
GOLD_SOURCE_TIMESTAMP=$(echo "$GOLD_RESPONSE" | jq -r '.[0].ts // empty')

SILVER_BID=$(echo "$SILVER_RESPONSE" | jq -r '.[0].spreadProfilePrices[0].bid // empty')
SILVER_ASK=$(echo "$SILVER_RESPONSE" | jq -r '.[0].spreadProfilePrices[0].ask // empty')
SILVER_SOURCE_TIMESTAMP=$(echo "$SILVER_RESPONSE" | jq -r '.[0].ts // empty')

# Validate values
if ! [[ "$GOLD_BID" =~ ^[0-9]+([.][0-9]+)?$ ]] || \
   ! [[ "$GOLD_ASK" =~ ^[0-9]+([.][0-9]+)?$ ]] || \
   ! [[ "$SILVER_BID" =~ ^[0-9]+([.][0-9]+)?$ ]] || \
   ! [[ "$SILVER_ASK" =~ ^[0-9]+([.][0-9]+)?$ ]] || \
   ! [[ "$GOLD_SOURCE_TIMESTAMP" =~ ^[0-9]+$ ]] || \
   ! [[ "$SILVER_SOURCE_TIMESTAMP" =~ ^[0-9]+$ ]]; then
  echo "Price source returned an invalid response; refusing to publish stale data." >&2
  exit 1
fi

if (( GOLD_SOURCE_TIMESTAMP < SILVER_SOURCE_TIMESTAMP )); then
  SOURCE_TIMESTAMP_MS=$GOLD_SOURCE_TIMESTAMP
else
  SOURCE_TIMESTAMP_MS=$SILVER_SOURCE_TIMESTAMP
fi
SOURCE_UPDATED_AT=$(jq -nr \
  --argjson milliseconds "$SOURCE_TIMESTAMP_MS" \
  '$milliseconds / 1000 | floor | todateiso8601')

# Calculate midpoint (spot)
GOLD_SPOT=$(awk "BEGIN { printf \"%.2f\", ($GOLD_BID + $GOLD_ASK) / 2 }")
SILVER_SPOT=$(awk "BEGIN { printf \"%.2f\", ($SILVER_BID + $SILVER_ASK) / 2 }")

# Read previous published values when they exist
PREVIOUS_UPDATED_AT=$(jq -r '.updatedAt // .updated_at // empty' data/prices.json 2>/dev/null || true)
PREVIOUS_SOURCE_UPDATED_AT=$(jq -r '.sourceUpdatedAt // .source_updated_at // empty' data/prices.json 2>/dev/null || true)
PREVIOUS_GOLD_SPOT=$(jq -r '.metals.gold.spot // empty' data/prices.json 2>/dev/null || true)
PREVIOUS_SILVER_SPOT=$(jq -r '.metals.silver.spot // empty' data/prices.json 2>/dev/null || true)
CURRENT_DAY_START_AT=$(date -u +"%Y-%m-%dT00:00:00Z")
EXISTING_DAY_START_AT=$(jq -r '.dayStartAt // empty' data/prices.json 2>/dev/null || true)
EXISTING_GOLD_DAY_OPEN=$(jq -r '.metals.gold.dayOpenSpot // empty' data/prices.json 2>/dev/null || true)
EXISTING_SILVER_DAY_OPEN=$(jq -r '.metals.silver.dayOpenSpot // empty' data/prices.json 2>/dev/null || true)

if [[ -n "$PREVIOUS_SOURCE_UPDATED_AT" ]] && \
   [[ "$PREVIOUS_SOURCE_UPDATED_AT" == "$SOURCE_UPDATED_AT" ]]; then
  echo "Swissquote has not published a new source quote; skipping duplicate observation."
  exit 0
fi

if ! [[ "$PREVIOUS_GOLD_SPOT" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  PREVIOUS_GOLD_SPOT=null
fi

if ! [[ "$PREVIOUS_SILVER_SPOT" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  PREVIOUS_SILVER_SPOT=null
fi

if [[ "$EXISTING_DAY_START_AT" == "$CURRENT_DAY_START_AT" ]] && \
   [[ "$EXISTING_GOLD_DAY_OPEN" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  GOLD_DAY_OPEN="$EXISTING_GOLD_DAY_OPEN"
else
  GOLD_DAY_OPEN="$GOLD_SPOT"
fi

if [[ "$EXISTING_DAY_START_AT" == "$CURRENT_DAY_START_AT" ]] && \
   [[ "$EXISTING_SILVER_DAY_OPEN" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  SILVER_DAY_OPEN="$EXISTING_SILVER_DAY_OPEN"
else
  SILVER_DAY_OPEN="$SILVER_SPOT"
fi

# Timestamp
UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Preserve every successful observation in a separate feed so the latest-price
# response can stay small for current app clients.
HISTORY_FILE="data/price-history.json"
if [[ ! -f "$HISTORY_FILE" ]]; then
  jq -n \
    --arg source "Swissquote public quotes" \
    --arg currency "USD" \
    --arg unit "troy_ounce" \
    '{
      schemaVersion: 1,
      source: $source,
      currency: $currency,
      unit: $unit,
      firstRecordedAt: null,
      lastUpdated: null,
      entries: []
    }' > "$HISTORY_FILE"
elif ! jq -e '.schemaVersion == 1 and (.entries | type == "array")' "$HISTORY_FILE" >/dev/null; then
  echo "Price history is invalid; refusing to overwrite it." >&2
  exit 1
fi

HISTORY_TEMP=$(mktemp)
jq \
  --arg recordedAt "$UPDATED_AT" \
  --arg sourceUpdatedAt "$SOURCE_UPDATED_AT" \
  --argjson goldBid "$GOLD_BID" \
  --argjson goldAsk "$GOLD_ASK" \
  --argjson gold "$GOLD_SPOT" \
  --argjson silverBid "$SILVER_BID" \
  --argjson silverAsk "$SILVER_ASK" \
  --argjson silver "$SILVER_SPOT" \
  '
    .firstRecordedAt = (.firstRecordedAt // $recordedAt)
    | .lastUpdated = $recordedAt
    | .entries += [{
        recordedAt: $recordedAt,
        sourceUpdatedAt: $sourceUpdatedAt,
        metals: {
          gold: {bid: $goldBid, ask: $goldAsk, spot: $gold},
          silver: {bid: $silverBid, ask: $silverAsk, spot: $silver}
        }
      }]
  ' "$HISTORY_FILE" > "$HISTORY_TEMP"
mv "$HISTORY_TEMP" "$HISTORY_FILE"

# Write JSON
jq -n \
  --arg updatedAt "$UPDATED_AT" \
  --arg sourceUpdatedAt "$SOURCE_UPDATED_AT" \
  --arg previousUpdatedAt "$PREVIOUS_UPDATED_AT" \
  --arg dayStartAt "$CURRENT_DAY_START_AT" \
  --arg source "Swissquote public quotes" \
  --arg currency "USD" \
  --arg unit "troy_ounce" \
  --argjson gold "$GOLD_SPOT" \
  --argjson silver "$SILVER_SPOT" \
  --argjson previousGold "$PREVIOUS_GOLD_SPOT" \
  --argjson previousSilver "$PREVIOUS_SILVER_SPOT" \
  --argjson goldDayOpen "$GOLD_DAY_OPEN" \
  --argjson silverDayOpen "$SILVER_DAY_OPEN" \
  '{
    updatedAt: $updatedAt,
    sourceUpdatedAt: $sourceUpdatedAt,
    previousUpdatedAt: (if $previousUpdatedAt == "" then null else $previousUpdatedAt end),
    dayStartAt: $dayStartAt,
    source: $source,
    currency: $currency,
    unit: $unit,
    metals: {
      gold: {
        spot: $gold,
        previousSpot: $previousGold,
        change: (if $previousGold == null then null else (($gold - $previousGold) * 100 | round / 100) end),
        changePercent: (if $previousGold == null or $previousGold == 0 then null else ((($gold - $previousGold) / $previousGold * 10000) | round / 100) end),
        dayOpenSpot: $goldDayOpen,
        dayChange: (($gold - $goldDayOpen) * 100 | round / 100),
        dayChangePercent: (if $goldDayOpen == 0 then null else ((($gold - $goldDayOpen) / $goldDayOpen * 10000) | round / 100) end)
      },
      silver: {
        spot: $silver,
        previousSpot: $previousSilver,
        change: (if $previousSilver == null then null else (($silver - $previousSilver) * 100 | round / 100) end),
        changePercent: (if $previousSilver == null or $previousSilver == 0 then null else ((($silver - $previousSilver) / $previousSilver * 10000) | round / 100) end),
        dayOpenSpot: $silverDayOpen,
        dayChange: (($silver - $silverDayOpen) * 100 | round / 100),
        dayChangePercent: (if $silverDayOpen == 0 then null else ((($silver - $silverDayOpen) / $silverDayOpen * 10000) | round / 100) end)
      }
    }
  }' > data/prices.json
