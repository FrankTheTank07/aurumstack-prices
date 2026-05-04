#!/bin/bash
set -euo pipefail

mkdir -p data

GOLD_URL="https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/XAU/USD"
SILVER_URL="https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/XAG/USD"

echo "Fetching gold price..."
GOLD_RESPONSE=$(curl -sS "$GOLD_URL")

echo "Fetching silver price..."
SILVER_RESPONSE=$(curl -sS "$SILVER_URL")

GOLD_BID=$(echo "$GOLD_RESPONSE" | jq -r '.[0].spreadProfilePrices[0].bid // empty')
GOLD_ASK=$(echo "$GOLD_RESPONSE" | jq -r '.[0].spreadProfilePrices[0].ask // empty')

SILVER_BID=$(echo "$SILVER_RESPONSE" | jq -r '.[0].spreadProfilePrices[0].bid // empty')
SILVER_ASK=$(echo "$SILVER_RESPONSE" | jq -r '.[0].spreadProfilePrices[0].ask // empty')

if ! [[ "$GOLD_BID" =~ ^[0-9]+([.][0-9]+)?$ ]] || \
   ! [[ "$GOLD_ASK" =~ ^[0-9]+([.][0-9]+)?$ ]] || \
   ! [[ "$SILVER_BID" =~ ^[0-9]+([.][0-9]+)?$ ]] || \
   ! [[ "$SILVER_ASK" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "Invalid data, skipping update"
  exit 0
fi

GOLD_SPOT=$(awk "BEGIN { printf \"%.2f\", ($GOLD_BID + $GOLD_ASK) / 2 }")
SILVER_SPOT=$(awk "BEGIN { printf \"%.2f\", ($SILVER_BID + $SILVER_ASK) / 2 }")

UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

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

echo "Updated prices:"
cat data/prices.json
