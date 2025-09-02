# Libraries and OP Stack context

This repo avoids vendoring Optimism contracts by default. The main token contract inlines only the minimal pieces needed for OP Stack compatibility and imports the rest from OpenZeppelin and Solady.

What’s inlined in `contracts/superchainerc20.sol`:
- Unauthorized error
- ISemver (version string)
- IERC7802 (crosschainMint/crosschainBurn and events)
- Predeploys.SUPERCHAIN_TOKEN_BRIDGE constant (0x4200000000000000000000000000000000000028)

These allow the token to authorize the SuperchainTokenBridge to mint/burn and to advertise its supported interfaces without pulling in the full Optimism library set.

OP Stack predeploys you might add later:
- L2StandardBridge: classic ERC20 bridge between L1↔L2
- L2CrossDomainMessenger: generic L1↔L2 messaging
- L2ToL1MessagePasser: part of withdrawal proofs
- GasPriceOracle: L2 gas/L1 fee breakdown
- L1Block (L1_BLOCK_ATTRIBUTES): exposes L1 state on L2
- CrossL2Inbox + L2ToL2CrossDomainMessenger (Interop): L2↔L2 messaging
- OptimismSuperchainERC20Factory + Beacon: superchain-native ERC20 factory pattern
- WETH: canonical WETH on L2

Messaging vs. bridging:
- The token integrates with the SuperchainTokenBridge via IERC7802. The bridge performs cross-chain mint/burn using underlying OP Stack messaging. You generally don’t need to call messenger contracts directly unless you plan to relay admin operations from L1, build custom cross-chain workflows, or do direct L2↔L2 messaging.

Deterministic deployments (CREATE2/CREATE3):
- Deterministic addresses don’t change messaging/bridge setup.
- To get the same token address across chains, deploy the same bytecode with the same salt and a consistent deployer/factory address on each chain (CREATE3 helps by standardizing via a factory).

Keeping the repo lean:
- We inlined only the SUPERCHAIN_TOKEN_BRIDGE constant used by the token. If you need more predeploys later, add a small curated library with just the addresses you use, or vendor the upstream file if you want full parity with OP Stack predeploys.

## Solady ERC20 (reference copy)

Path: `contracts/lib/solady/ERC20.sol` — exact source of Solady v0.0.245’s ERC20, included for reference only.

What it provides:
- High-performance ERC20 implementation with EIP-2612 permit built-in.
- Custom errors and manually inlined assembly for mint/transfer/approve flows.
- Deterministic storage layout via fixed slot seeds for balances, allowances, and nonces.
- Hooks to override: `_beforeTokenTransfer`, `_afterTokenTransfer`.
- Optional Permit2 integration flag via `_givePermit2InfiniteAllowance()`.

Why it’s included here:
- Transparency: to inspect exactly what the token inherits when importing `@solady-v0.0.245/tokens/ERC20.sol`.
- Reviewability: auditors and contributors can read the concrete implementation without leaving the repo.
- No behavior change: imports still resolve to the external package; this file is not compiled against or used by our contracts.

Notes for implementers:
- ERC20 does not require ERC165. Our token advertises ERC165 support for IERC7802 only; we include the IERC20 interface ID purely for convenience in `supportsInterface`.
- If you override metadata or decimals, ensure permit domain/version logic still matches expectations.
- Never violate the invariant: sum of balances == totalSupply.
