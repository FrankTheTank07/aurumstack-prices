#!/bin/bash
set -euo pipefail

# Ensure output directory exists
mkdir -p data

# Data sources
GOLD_URL="https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/XAU/USD"
SILVER_URL="https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/XAG/USD"

# Fetch data
GOLD_RESPONSE=$(curl -sS "$GOLD_URL")
SILVER_RESPONSE=$(curl -sS "$SILVER_URL")

# Extract bid/ask
GOLD_BID=$(echo "$GOLD_RESPONSE" | jq -r '.[0].spreadProfilePrices[0].bid // empty')
GOLD_ASK=$(echo "$GOLD_RESPONSE" | jq -r '.[0].spreadProfilePrices[0].ask // empty')

SILVER_BID=$(echo "$SILVER_RESPONSE" | jq -r '.[0].spreadProfilePrices[0].bid // empty')
SILVER_ASK=$(echo "$SILVER_RESPONSE" | jq -r '.[0].spreadProfilePrices[0].ask // empty')

# Validate values
if ! [[ "$GOLD_BID" =~ ^[0-9]+([.][0-9]+)?$ ]] || \
   ! [[ "$GOLD_ASK" =~ ^[0-9]+([.][0-9]+)?$ ]] || \
   ! [[ "$SILVER_BID" =~ ^[0-9]+([.][0-9]+)?$ ]] || \
   ! [[ "$SILVER_ASK" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  exit 0
fi

# Calculate midpoint (spot)
GOLD_SPOT=$(awk "BEGIN { printf \"%.2f\", ($GOLD_BID + $GOLD_ASK) / 2 }")
SILVER_SPOT=$(awk "BEGIN { printf \"%.2f\", ($SILVER_BID + $SILVER_ASK) / 2 }")

# Read previous published values when they exist
PREVIOUS_UPDATED_AT=$(jq -r '.updatedAt // .updated_at // empty' data/prices.json 2>/dev/null || true)
PREVIOUS_GOLD_SPOT=$(jq -r '.metals.gold.spot // empty' data/prices.json 2>/dev/null || true)
PREVIOUS_SILVER_SPOT=$(jq -r '.metals.silver.spot // empty' data/prices.json 2>/dev/null || true)
CURRENT_DAY_START_AT=$(date -u +"%Y-%m-%dT00:00:00Z")
EXISTING_DAY_START_AT=$(jq -r '.dayStartAt // empty' data/prices.json 2>/dev/null || true)
EXISTING_GOLD_DAY_OPEN=$(jq -r '.metals.gold.dayOpenSpot // empty' data/prices.json 2>/dev/null || true)
EXISTING_SILVER_DAY_OPEN=$(jq -r '.metals.silver.dayOpenSpot // empty' data/prices.json 2>/dev/null || true)

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

# Write JSON
jq -n \
  --arg updatedAt "$UPDATED_AT" \
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
