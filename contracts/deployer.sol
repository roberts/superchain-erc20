// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// Solady CREATE3 library inlined to avoid external imports.
/// Original: https://github.com/Vectorized/solady/blob/main/src/utils/CREATE3.sol (MIT)
library CREATE3 {
    /// @dev Unable to deploy the contract.
    error DeploymentFailed();

    /**
     * Proxy bytecode used by CREATE3. See Solady for documentation.
     * This constant is the 8-byte initcode for the minimal proxy that does:
     * - copy calldata
     * - CREATE with the forwarded value and calldata
     */
    uint256 private constant _PROXY_INITCODE = 0x67363d3d37363d34f03d5260086018f3;

    /// @dev keccak256(abi.encodePacked(hex"67363d3d37363d34f03d5260086018f3"))
    bytes32 internal constant PROXY_INITCODE_HASH =
        0x21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f;

    /// @dev Deploys `initCode` deterministically with `salt`.
    /// Returns the deterministic address of the deployed contract.
    function deployDeterministic(bytes memory initCode, bytes32 salt)
        internal
        returns (address deployed)
    {
        deployed = deployDeterministic(0, initCode, salt);
    }

    /// @dev Deploys `initCode` deterministically with `salt`, forwarding `value` wei.
    /// Returns the deterministic address of the deployed contract.
    function deployDeterministic(uint256 value, bytes memory initCode, bytes32 salt)
        internal
        returns (address deployed)
    {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, _PROXY_INITCODE) // Store the `_PROXY_INITCODE`.
            let proxy := create2(0, 0x10, 0x10, salt)
            if iszero(proxy) {
                mstore(0x00, 0x30116425) // `DeploymentFailed()` selector.
                revert(0x1c, 0x04)
            }
            mstore(0x14, proxy) // Store the proxy's address at 0x14..0x33.
            // RLP encode: keccak256(rlp([proxy, 1])).
            // 0xd6 = 0xc0 (short list) + 0x16 (len of: 0x94 ++ proxy ++ 0x01).
            // 0x94 = 0x80 + 0x14 (20 bytes for an address).
            mstore(0x00, 0xd694)
            mstore8(0x34, 0x01) // Nonce of the proxy (1).
            deployed := keccak256(0x1e, 0x17)
            if iszero(
                mul(
                    extcodesize(deployed),
                    call(gas(), proxy, value, add(initCode, 0x20), mload(initCode), 0x00, 0x00)
                )
            ) {
                mstore(0x00, 0x30116425) // `DeploymentFailed()` selector.
                revert(0x1c, 0x04)
            }
        }
    }

    /// @dev Returns the deterministic address for `salt` using `address(this)` as deployer.
    function predictDeterministicAddress(bytes32 salt) internal view returns (address deployed) {
        deployed = predictDeterministicAddress(salt, address(this));
    }

    /// @dev Returns the deterministic address for `salt` with `deployer`.
    function predictDeterministicAddress(bytes32 salt, address deployer)
        internal
        pure
        returns (address deployed)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40) // Cache free memory pointer.
            mstore(0x00, deployer) // Store `deployer` at 0x00..0x13.
            mstore8(0x0b, 0xff) // Store the prefix.
            mstore(0x20, salt) // Store the salt.
            mstore(0x40, PROXY_INITCODE_HASH) // Store the bytecode hash.
            mstore(0x14, keccak256(0x0b, 0x55)) // Store the proxy address.
            mstore(0x40, m) // Restore free memory pointer.
            // RLP encode: keccak256(rlp([proxy, 1])).
            mstore(0x00, 0xd694)
            mstore8(0x34, 0x01) // Nonce of the proxy (1).
            deployed := keccak256(0x1e, 0x17)
        }
    }
}

/// @title Create3Deployer
/// @notice Minimal owner-gated wrapper around Solady's CREATE3 utilities.
/// @dev Final deployed contract address depends only on this contract's address and the salt.
contract Create3Deployer {
    /// @dev Emitted after a successful deployment.
    event Deployed(address indexed deployed, bytes32 indexed salt);

    /// @dev Contract owner for controlling deployments.
    address public owner;

    error Unauthorized();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Transfer ownership to a new owner.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    /// @notice Predict the final CREATE3 target address for a given salt.
    /// @param salt The salt used for CREATE3.
    /// @return predicted The predicted target address.
    function predict(bytes32 salt) external view returns (address predicted) {
        predicted = CREATE3.predictDeterministicAddress(salt, address(this));
    }

    /// @notice Deploy a contract deterministically via CREATE3.
    /// @param initCode Creation bytecode (constructor args ABI-encoded within).
    /// @param salt The salt used for CREATE3.
    /// @return deployed The address of the deployed contract.
    function deploy(bytes calldata initCode, bytes32 salt)
        external
        onlyOwner
        returns (address deployed)
    {
        deployed = CREATE3.deployDeterministic(initCode, salt);
        emit Deployed(deployed, salt);
    }

    /// @notice Deploy a contract deterministically via CREATE3, forwarding ETH.
    /// @param initCode Creation bytecode (constructor args ABI-encoded within).
    /// @param salt The salt used for CREATE3.
    /// @return deployed The address of the deployed contract.
    function deployWithValue(bytes calldata initCode, bytes32 salt)
        external
        payable
        onlyOwner
        returns (address deployed)
    {
        deployed = CREATE3.deployDeterministic{value: msg.value}(initCode, salt);
        emit Deployed(deployed, salt);
    }

    /// @notice Withdraw ETH accidentally sent or left over in this contract.
    function sweep(address payable to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        to.transfer(address(this).balance);
    }
}
