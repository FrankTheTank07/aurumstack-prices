#!/bin/bash
set -euo pipefail

mkdir -p data

API_URL="https://api.metals.dev/v1/latest?api_key=${METALS_DEV_API_KEY}&currency=USD&unit=toz"

curl -sS "$API_URL" -o /tmp/metals.json

GOLD=$(jq -r '.metals.gold // .gold // empty' /tmp/metals.json)
SILVER=$(jq -r '.metals.silver // .silver // empty' /tmp/metals.json)

UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq -n \
  --arg updatedAt "$UPDATED_AT" \
  --argjson gold "$GOLD" \
  --argjson silver "$SILVER" \
  '{
    updatedAt: $updatedAt,
    metals: {
      gold: { spot: $gold },
      silver: { spot: $silver }
    }
  }' > data/prices.json
