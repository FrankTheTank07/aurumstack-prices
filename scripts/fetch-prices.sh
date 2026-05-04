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

# Timestamp
UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Write JSON
jq -n \
  --arg updatedAt "$UPDATED_AT" \
  --arg source "Swissquote public quotes" \
  --arg currency "USD" \
  --arg unit "troy_ounce" \
  --argjson gold "$GOLD_SPOT" \
  --argjson silver "$SILVER_SPOT" \
  '{
    updatedAt: $updatedAt,
    source: $source,
    currency: $currency,
    unit: $unit,
    metals: {
      gold: { spot: $gold },
      silver: { spot: $silver }
    }
  }' > data/prices.json
