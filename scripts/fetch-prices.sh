#!/bin/bash
set -euo pipefail

mkdir -p data

API_URL="https://api.metals.dev/v1/latest?api_key=${METALS_DEV_API_KEY}&currency=USD&unit=toz"

echo "Fetching prices from metals.dev..."

RESPONSE=$(curl -sS "$API_URL")

echo "Raw API response:"
echo "$RESPONSE"

# Make sure the response is valid JSON
if ! echo "$RESPONSE" | jq empty >/dev/null 2>&1; then
  echo "API did not return valid JSON. Keeping existing prices.json."
  exit 0
fi

# Try multiple possible response formats
GOLD=$(echo "$RESPONSE" | jq -r '
  .metals.gold //
  .rates.gold //
  .rates.XAU //
  .rates.GOLD //
  .gold //
  empty
')

SILVER=$(echo "$RESPONSE" | jq -r '
  .metals.silver //
  .rates.silver //
  .rates.XAG //
  .rates.SILVER //
  .silver //
  empty
')

echo "Parsed gold: $GOLD"
echo "Parsed silver: $SILVER"

# Make sure both values exist and are numeric
if ! [[ "$GOLD" =~ ^[0-9]+([.][0-9]+)?$ ]] || ! [[ "$SILVER" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "Gold or silver price was missing/non-numeric. Keeping existing prices.json."
  exit 0
fi

# Round to 2 decimal places
GOLD=$(printf "%.2f" "$GOLD")
SILVER=$(printf "%.2f" "$SILVER")

UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq -n \
  --arg updatedAt "$UPDATED_AT" \
  --arg currency "USD" \
  --arg unit "troy_ounce" \
  --arg source "metals.dev" \
  --argjson gold "$GOLD" \
  --argjson silver "$SILVER" \
  '{
    updatedAt: $updatedAt,
    source: $source,
    currency: $currency,
    unit: $unit,
    metals: {
      gold: {
        spot: $gold
      },
      silver: {
        spot: $silver
      }
    }
  }' > data/prices.json

echo "Updated data/prices.json successfully:"
cat data/prices.json
