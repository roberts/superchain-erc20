#!/usr/bin/env bash
set -euo pipefail

# Deterministically deploy Create3Deployer via CREATE2 using Foundry.
# Requirements:
# - env: RPC (rpc url), PK (private key hex), SALT2 (bytes32 hex salt)
# - forge and cast installed

: "${RPC:?RPC is required}"
: "${PK:?PK is required}"
: "${SALT2:?SALT2 (bytes32 hex) is required}"

CONTRACT_PATH="contracts/deployer.sol:Create3Deployer"

# Deploy deterministically with --salt.
ADDR=$(forge create "$CONTRACT_PATH" --rpc-url "$RPC" --private-key "$PK" --salt "$SALT2" 2>/dev/null | awk '/Deployed to:/ {print $3}')

if [ -z "${ADDR:-}" ]; then
  echo "forge create did not return an address. Check output above." >&2
  exit 1
fi

echo "Create3Deployer deployed at: $ADDR"
echo "$ADDR" > .create3_deployer.addr
