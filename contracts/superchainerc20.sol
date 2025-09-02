// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// Contracts
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@solady-v0.0.245/tokens/ERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

// ---- Minimal inlined Optimism types ----

/// @notice Error for an unauthorized CALLER.
error Unauthorized();

/// @title ISemver
/// @notice Simple interface to expose semantic version of a contract.
interface ISemver {
    /// @notice Semantic version.
    /// @custom:semver The version string should follow semver, e.g. "1.0.0".
    function version() external view returns (string memory);
}

/// @title IERC7802
/// @notice Minimal interface for ERC-7802 cross-chain mint/burn hooks used by SuperchainERC20.
interface IERC7802 is IERC165 {
    /// @notice Emitted when tokens are minted cross-chain.
    event CrosschainMint(address indexed to, uint256 amount, address indexed caller);

    /// @notice Emitted when tokens are burned cross-chain.
    event CrosschainBurn(address indexed from, uint256 amount, address indexed caller);

    /// @notice Mint tokens to an address. Intended to be called by a bridge contract.
    function crosschainMint(address to, uint256 amount) external;

    /// @notice Burn tokens from an address. Intended to be called by a bridge contract.
    function crosschainBurn(address from, uint256 amount) external;
}

/// @title Predeploys
/// @notice Contains constant addresses for protocol contracts that are pre-deployed to the L2 system.
library Predeploys {
    /// @notice Address of the SuperchainTokenBridge predeploy.
    address internal constant SUPERCHAIN_TOKEN_BRIDGE = 0x4200000000000000000000000000000000000028;
}

/// @title SuperchainERC20
/// @notice A standard ERC20 extension implementing IERC7802 for unified cross-chain fungibility
///         across the Superchain. Gives the SuperchainTokenBridge mint and burn permissions.
/// @dev    This contract inherits from Solady@v0.0.245 ERC20. Carefully review Solady's,
///         documentation including all warnings, comments and natSpec, before extending or
///         interacting with this contract.
abstract contract SuperchainERC20 is ERC20, IERC7802, ISemver {
    /// @notice Semantic version.
    /// @custom:semver 1.0.2
    function version() external view virtual returns (string memory) {
        return "1.0.2";
    }

    /// @notice Allows the SuperchainTokenBridge to mint tokens.
    /// @param _to     Address to mint tokens to.
    /// @param _amount Amount of tokens to mint.
    function crosschainMint(address _to, uint256 _amount) external {
        if (msg.sender != Predeploys.SUPERCHAIN_TOKEN_BRIDGE) revert Unauthorized();

        _mint(_to, _amount);

        emit CrosschainMint(_to, _amount, msg.sender);
    }

    /// @notice Allows the SuperchainTokenBridge to burn tokens.
    /// @param _from   Address to burn tokens from.
    /// @param _amount Amount of tokens to burn.
    function crosschainBurn(address _from, uint256 _amount) external {
        if (msg.sender != Predeploys.SUPERCHAIN_TOKEN_BRIDGE) revert Unauthorized();

        _burn(_from, _amount);

        emit CrosschainBurn(_from, _amount, msg.sender);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 _interfaceId) public view virtual returns (bool) {
        return _interfaceId == type(IERC7802).interfaceId || _interfaceId == type(IERC20).interfaceId
            || _interfaceId == type(IERC165).interfaceId;
    }
}
