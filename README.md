# Superchain ERC-20

A minimal, Superchain-aware ERC-20 extension built on Solady’s high-performance ERC20 and an inlined IERC7802 interface for unified cross-chain fungibility across OP Stack chains.

## What this contract does

- Extends Solady ERC20 for gas-efficient ERC-20 behavior (including EIP-2612 permit).
- Implements IERC7802 to standardize cross-chain mint/burn semantics across the Superchain.
- Restricts mint/burn to the SuperchainTokenBridge predeploy address (0x4200000000000000000000000000000000000028).
- Exposes a semantic version via ISemver.
- Advertises ERC165 support for IERC7802, and returns the IERC20 interface id for convenience.

Notes:
- The contract is abstract. You inherit and implement name/symbol (and optionally override hooks) for a concrete token.
- Cross-chain actions: `crosschainMint` and `crosschainBurn` can only be called by the SuperchainTokenBridge (the bridge will call these via OP messaging under the hood).

## Foundry Deployment Overview

Add details here..

## Deterministic deployments with vanity address targets

Goal: get the same token address on L1 and OP chains while matching a 2+5 vanity pattern (2 hex prefix + 5 hex suffix).

At a glance
- Address under CREATE3 depends only on: deployer contract address + salt.
- Make the deployer address identical on all chains (use CREATE2), then reuse the same CREATE3 salt.
- 2+5 vanity ≈ 28 bits (≈ 2^28 tries). Use a parallelized search for practicality.

## Utilize CREATE2 to create CREATE3 Deployer

Goal: get the same `Create3Deployer` contract address on every chain so CREATE3 yields identical token addresses for a given salt.

Deterministic recipe (CREATE2):
- Build `initCode` for `contracts/deployer.sol` (constructor sets `owner = msg.sender`). If you want the same deployer address, keep the constructor args/bytecode identical across chains.
- Pick a `salt` (bytes32). Keep it the same across chains.
- Predict the deployer address with the CREATE2 formula:
	- `address = keccak256(0xff ++ factoryAddress ++ salt ++ keccak256(initCode))[12:]`
- Deploy via the factory’s `create2` method with the same `salt` and `initCode` on each chain.
- Confirm the deployed address matches the prediction on each chain.

Key invariants to keep addresses identical:
- Same factory address on each chain (canonical or deterministically deployed).
- Same `salt`.
- Same `initCode` (constructor args and compiler settings) for the deployer.

Once `Create3Deployer` is identical across chains:
- Run your vanity search using `predict(salt)` from the deployer to find a 2+5 address for the token.
- Deploy the token with `deploy(initCode, salt)` on each chain reusing the same salt.

## How to deploy with Foundry (deterministic + vanity)

Prereqs
- Foundry installed and configured (forge, cast).
- RPC URLs and a funded deployer key for each network.

1) Deterministically deploy Create3Deployer with CREATE2
- Choose a CREATE2 salt (bytes32 hex), e.g., SALT2 = 0x.... Keep the same across chains.
- Use forge to deploy deterministically with CREATE2. Recent Foundry supports `--salt` to route via the universal CREATE2 deployer:

```sh
forge create contracts/deployer.sol:Create3Deployer \
	--rpc-url $RPC \
	--private-key $PK \
	--salt $SALT2
```

- Repeat for each chain using the same $SALT2. Verify the deployer address is identical across chains.

2) Offline vanity salt search for the token (2+5)
- Use the deployed Create3Deployer to predict addresses without deploying the token:

```sh
# Single check
cast call $DEPLOYER 'predict(bytes32)(address)' $SALT --rpc-url $RPC
```

- Brute-force: iterate salts and call `predict(bytes32)` until the 2+5 pattern matches. Run your script against any RPC; you’ll reuse the winning salt on all chains since the deployer address is identical.
- Keep constructor args fixed during search; address doesn’t depend on init code with CREATE3, but fixing args keeps verification consistent.

3) Build init code for your token
- Encode constructor args into creation code with Foundry:

```sh
# Replace <Path:Contract> and args
INIT_CODE=$(forge inspect <path:ContractName> creationCodeWithArgs <constructor-args>)
```

4) Deploy the token via Create3Deployer (CREATE3)
- Use the vanity salt you found (SALT3) and the same deployer address on each chain:

```sh
cast send $DEPLOYER 'deploy(bytes,bytes32)(address)' $INIT_CODE $SALT3 \
	--rpc-url $RPC \
	--private-key $PK
```

- If you need to send ETH alongside deployment, use `deployWithValue(bytes,bytes32)` and add `--value` to cast.

5) Repeat on OP chains
- Reuse the same $DEPLOYER address and $SALT3. The token address will match across chains.

## Solady CREATE3 (library) and this repo’s deployer

- Source (library): https://github.com/Vectorized/solady/blob/main/src/utils/CREATE3.sol
- In this repo, call it via `contracts/deployer.sol` (Create3Deployer), which wraps the library and exposes:
	- `predict(bytes32 salt)` → uses `CREATE3.predictDeterministicAddress(salt, address(this))`
	- `deploy(bytes initCode, bytes32 salt)` and `deployWithValue(bytes initCode, bytes32 salt)` → use `CREATE3.deployDeterministic`

Typical flow with CREATE3
1) Build init code from the compiled artifact (constructor args encoded as bytes).
2) Off-chain, iterate salts and call `predictDeterministicAddress` to compute the address; check against the 2+5 vanity pattern.
3) When a salt matches, deploy on mainnet by calling your `Create3Deployer.deploy(initCode, salt)` from the deployer at the agreed address.
4) Repeat the exact same deployment on OP chains (same deployer address + same salt) to reproduce the address.

### Notes

- CREATE3 lets you reuse the same vanity address across Ethereum mainnet and OP chains.
- The final address depends on: deployer/factory address and salt (not your EOA nonce, not init code).
- Prefer parallelized search to make the 2+5 vanity target practical.

## Deployment flow (high level)

1) Prepare the build
- Compile with Foundry, pinning the compiler version and settings used for production.

2) Vanity search (offline)
- Iterate salts and compute `CREATE3.predictDeterministicAddress(salt, deployer)`; stop on a 2+5 match.

3) Deploy to Ethereum mainnet
- Use the selected salt and the exact same bytecode/constructor args through your deployment script.
- Verify the contract and record the address and salt.

4) Deploy to OP chains (Base, Optimism, Unichain, etc.)
- Ensure the CREATE3 factory (or deployer) is at the same address.
- Re-run the deployment with the exact same salt and bytecode to reproduce the same contract address on each chain.

5) Post-deploy
- Verify on each chain.
- Optionally, document the chain IDs, factory addresses, bytecode hash, and the chosen salt for reproducibility.

## Superchain specifics

- SuperchainTokenBridge predeploy is fixed at 0x4200000000000000000000000000000000000028 on OP Stack L2s. The token’s cross-chain mint/burn authorization relies on this constant.
- You don’t need to integrate messenger contracts directly unless you want custom cross-chain admin or L2↔L2 logic beyond standard bridging.

## Repository guide

- contracts/superchainerc20.sol: The abstract Superchain-aware token base.
- contracts/lib/solady/ERC20.sol: Reference copy of Solady v0.0.245 ERC20 (for inspection only).
- contracts/lib/readme.md: Additional context on OP messaging, predeploys, and Solady notes.
