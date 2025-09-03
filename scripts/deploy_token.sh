#!/usr/bin/env bash
set -euo pipefail

# Build init code, run vanity salt search (external), and deploy token via Create3Deployer.
# Requirements:
# - env: RPC, PK, DEPLOYER (address of Create3Deployer), SALT3 (bytes32 hex for token), CONTRACT (path:Name), ARGS (optional)
# - forge and cast installed

: "${RPC:?RPC is required}"
: "${PK:?PK is required}"
: "${DEPLOYER:?DEPLOYER address is required}"
: "${SALT3:?SALT3 (bytes32 hex) is required}"
: "${CONTRACT:?CONTRACT (path:Name) is required}"

# Build init code with constructor args (if any)
if [ -n "${ARGS:-}" ]; then
  INIT_CODE=$(forge inspect "$CONTRACT" creationCodeWithArgs $ARGS)
else
  INIT_CODE=$(forge inspect "$CONTRACT" creationCode)
fi

echo "Init code length: $((${#INIT_CODE}/2)) bytes (hex chars/2)"

# Optional preflight prediction
PRED=$(cast call "$DEPLOYER" 'predict(bytes32)(address)' "$SALT3" --rpc-url "$RPC")
echo "Predicted token address: $PRED"

# Deploy via CREATE3
TX=$(cast send "$DEPLOYER" 'deploy(bytes,bytes32)(address)' "$INIT_CODE" "$SALT3" --rpc-url "$RPC" --private-key "$PK")
echo "TX: $TX"

# Fetch deployed address from logs by calling predict again (deterministic)
echo "Deployed token address (deterministic): $PRED"
