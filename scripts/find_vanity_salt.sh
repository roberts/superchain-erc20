#!/usr/bin/env bash
set -euo pipefail

# Brute-force a vanity salt for CREATE3 using the deployed Create3Deployer's predict(bytes32).
# Pattern: 2-hex prefix and 5-hex suffix on the final address (0x-prefixed lowercased hex).
# Requirements:
# - env: RPC, DEPLOYER, PREFIX (e.g., ab), SUFFIX (e.g., 12345), START (optional int), COUNT (optional int)
# - cast installed
# - Note: This is a simple CPU-bound loop; parallelize across processes/machines for speed.

: "${RPC:?RPC is required}"
: "${DEPLOYER:?DEPLOYER address is required}"
: "${PREFIX:?PREFIX (2 hex) is required}"
: "${SUFFIX:?SUFFIX (5 hex) is required}"

START=${START:-0}
COUNT=${COUNT:-1000000}

lcase() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

PREFIX=$(lcase "$PREFIX")
SUFFIX=$(lcase "$SUFFIX")

printf "Searching salts starting at %s for %s...%s\n" "$START" "$PREFIX" "$SUFFIX"

found=0
for ((i=START; i<START+COUNT; i++)); do
  # Derive a bytes32 salt from the counter.
  SALT=$(printf "0x%064x" "$i")
  ADDR=$(cast call "$DEPLOYER" 'predict(bytes32)(address)' "$SALT" --rpc-url "$RPC")
  LADDR=$(lcase "$ADDR")
  # Strip 0x and test prefix/suffix.
  HEX=${LADDR#0x}
  if [[ ${HEX:0:2} == "$PREFIX" && ${HEX: -5} == "$SUFFIX" ]]; then
    echo "Match found!"
    echo "SALT3=$SALT"
    echo "ADDRESS=$LADDR"
    found=1
    break
  fi
  # Optional: progress every 100k
  if (( i % 100000 == 0 )); then
    echo "Checked $i... current $LADDR"
  fi
done

if (( found == 0 )); then
  echo "No match in range [$START, $((START+COUNT-1))]. Increase COUNT or run more workers." >&2
  exit 1
fi
