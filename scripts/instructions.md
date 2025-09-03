# Scripts: Deterministic CREATE3 deployment with Foundry

This folder contains simple helpers to:
- Deterministically deploy the `Create3Deployer` (factory) with CREATE2.
- Brute-force a vanity salt (2 hex prefix + 5 hex suffix) for your token address.
- Deploy your token via the deployer using CREATE3.

If you’re new to Foundry, follow these steps end-to-end.

## Prerequisites

- Install Foundry (forge, cast). See: https://book.getfoundry.sh/getting-started/installation
- Have an RPC URL and a funded private key for each network you’ll deploy to.
- Export your environment variables in your shell.

Example:
```sh
export RPC=https://mainnet.infura.io/v3/<key>
export PK=0xdeadbeef... # hex private key
```

## 1) Deterministically deploy the Create3Deployer (CREATE2)

This pins the deployer’s address so CREATE3 produces the same token address across chains.

Pick a CREATE2 salt (bytes32 hex) and export it:
```sh
export SALT2=0x000000000000000000000000000000000000000000000000000000000000a11c
```

Run the script:
```sh
./scripts/deploy_deployer.sh
```

Output example:
```
Create3Deployer deployed at: 0xabc...def
```

Repeat on each network with the same SALT2. The deployer address should be identical.

Tip: The script also writes the address to .create3_deployer.addr.

## 2) Search for a vanity salt (2+5) offline

We’ll find a salt that makes your final token address match the pattern (2-hex prefix + 5-hex suffix).

Set your pattern and run the search against any single RPC (the result will work on every chain because the deployer address is the same):
```sh
export DEPLOYER=$(cat .create3_deployer.addr)
export PREFIX=ab
export SUFFIX=12345
# Optional: split work across processes by setting START and COUNT
export START=0
export COUNT=1000000
./scripts/find_vanity_salt.sh
```

The script prints SALT3 and the matched address when found. For large searches, run multiple processes with disjoint START ranges.

High-throughput (Node, multithreaded, offline):
```sh
cd scripts
npm install
# Single-threaded
node find_vanity_salt.js --deployer $(cat ../.create3_deployer.addr) --prefix ab --suffix 12345 --start 0 --count 10000000
# Multithreaded (8 workers)
node find_vanity_salt.js --deployer $(cat ../.create3_deployer.addr) --prefix ab --suffix 12345 --start 0 --count 10000000 --workers 8
```
This version does not make RPC calls per try; it computes the CREATE3 address offline using the hash formulas for maximum throughput.

## 3) Build init code and deploy the token (CREATE3)

Prepare your contract path and constructor args, then deploy with the vanity salt:
```sh
export CONTRACT=contracts/superchainerc20.sol:YourToken
export ARGS="<arg1> <arg2> ..."   # optional, space-separated
export SALT3=0x....               # from step 2

./scripts/deploy_token.sh
```

The script:
- Builds creation code (with args, if provided) using `forge inspect`.
- Calls `predict(bytes32)` on the deployer to show the expected address.
- Sends a transaction to `deploy(bytes,bytes32)` on the deployer.

Repeat this step on your OP chains with the same DEPLOYER and SALT3 to reproduce the exact same address.

## Troubleshooting

- forge not found: ensure Foundry is installed and `forge --version` works.
- Insufficient funds: top up the deployer account for each network.
- Different deployer addresses across chains: ensure the same SALT2 and identical init code for the deployer; differing compiler/settings change the CREATE2 result.
- Verification: while CREATE3 address doesn’t depend on init code, keep compiler version, settings, and constructor args consistent for easier verification.

## Notes

- With CREATE3, the final token address depends only on the deployer address and SALT3 (not on your EOA nonce or the token’s init code).
- For speed, the vanity search is a simple shell loop. Consider writing a parallelized Rust/Go/JS tool if you need higher throughput.
