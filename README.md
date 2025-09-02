# Superchain ERC-20

A minimal, Superchain-aware ERC-20 extension built on Solady’s high-performance ERC20 and an inlined IERC7802 interface for unified cross-chain fungibility across OP Stack chains.

## What this contract does

- Extends Solady ERC20 for gas-efficient ERC-20 behavior (including EIP-2612 permit).
- Implements IERC7802 to standardize cross-chain mint/burn semantics across the Superchain.
- Restricts mint/burn to the SuperchainTokenBridge predeploy address (0x4200000000000000000000000000000000000028).
- Exposes a semantic version via ISemver.
- Advertises support for ERC165 (for IERC7802) and returns the IERC20 interface id for convenience.

Notes:
- The contract is abstract. You inherit and implement name/symbol (and optionally override hooks) for a concrete token.
- Cross-chain actions: `crosschainMint` and `crosschainBurn` can only be called by the SuperchainTokenBridge (the bridge will call these via OP messaging under the hood).

## Deterministic deployments with vanity address targets

Goal: Deploy the token with a vanity address that has 6 hex characters at the start and 6 at the end, and then reuse the exact same address on Ethereum mainnet and OP chains.

Two common approaches:

1) CREATE2
- Address formula: keccak256(0xff ++ deployer ++ salt ++ keccak256(init_code))[12..32].
- To get a vanity address, you brute-force the `salt` (and/or harmless init args) until the computed address matches your prefix/suffix pattern.
- For cross-chain consistency, the deployer address, salt, and init_code must be identical on every chain.

2) CREATE3 (via a factory)
- Pattern: a factory uses CREATE2 to deploy a temporary contract whose address depends on `salt`, then that contract uses CREATE to deploy your target at a deterministic address that depends only on the temporary contract address and a fixed nonce (usually 1).
- Benefits: simplifies reproducibility by decoupling the target address from the caller’s nonce; you just need the same factory address and salt on every chain.

Feasibility of 6+6 vanity
- Constraining 6 hex at the start AND 6 at the end is 12 hex (48 bits) of constraint. Expected brute-force work is ~2^48 tries, which is impractical without significant compute (specialized miners/GPUs/clusters).
- Practical targets for individual developers: 3+3 (24 bits, ~16.7M tries) or 4+4 (32 bits, ~4.3B tries) may be achievable with optimized search and parallelism. Consider relaxing the requirement or using a compute service.

Pragmatic strategy
- Use a well-known CREATE3 factory at a consistent address on all target chains (or deploy your own factory to the same address using deterministic deployment).
- Write an offline vanity search script that iterates salts and computes the resulting target address for your init_code until your pattern is matched.
- Once a salt is found on mainnet, reuse the same bytecode, salt, and factory address across OP chains to reproduce the address.

Important requirements for same address across chains
- Same bytecode (compiler version, settings, constructor params).
- Same salt.
- Same deployer/factory address on each chain.

## Deployment flow (high level)

1) Prepare the build
- Compile with Foundry, pinning the compiler version and settings used for production.

2) Vanity search (offline)
- For CREATE2: iterate `salt` and compute the address from the formula; stop on a match.
- For CREATE3: iterate `salt`, compute the factory-derived deployer and the final target address; stop on a match.

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

