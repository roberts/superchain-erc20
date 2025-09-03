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
    /// @notice Emitted when the canonical initial supply is minted on the canonical chain.
    event InitialSupplyMinted(address indexed to, uint256 amount, uint256 chainId);
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

/// @title Ownable (minimal)
/// @notice Lightweight ownership control for admin-only actions.
contract Ownable {
    /// @notice Current owner.
    address public owner;

    /// @notice Emitted when ownership is transferred.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Error for non-owner calls.
    error NotOwner();
    /// @notice Error for zero address.
    error ZeroAddress();

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Transfer ownership to `newOwner`.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

/// @title Superchain ERC20 Token (Concrete)
/// @notice Concrete implementation of SuperchainERC20 with configurable metadata and optional initial mint.
/// @dev Name, symbol, and decimals are stored to allow constructor configuration.
contract SwampGoldToken is SuperchainERC20, Ownable {
    // ERC-20 metadata.
    string private _name;
    string private _symbol;

    /// @notice Canonical chain id for initial supply (Ethereum mainnet).
    uint256 public constant CANONICAL_CHAIN_ID = 1;

    /// @notice Per-chain trading status. When false, non-owner transfers are blocked.
    /// @dev This is intentionally per-chain because each deployment has independent storage.
    bool public chainTradable;

    /// @notice Emitted when trading status is changed.
    event TradingStatusChanged(bool enabled);

    /// @notice Error thrown when trading is paused.
    error TradingPaused();

    /// @notice Returns true if running on the canonical chain.
    function isCanonicalChain() public view returns (bool) {
        return block.chainid == CANONICAL_CHAIN_ID;
    }

    /// @notice Deploy the fixed-supply Swamp Gold token (18 decimals).
    /// @dev On the canonical chain (Ethereum mainnet), mints 100,000,000 tokens (18 decimals) to the owner.
    constructor() {
        _name = "Swamp Gold";
        _symbol = "GOLD";

        // Explicitly set the owner to the requested address to avoid CREATE3 proxy-as-sender issues.
        address initialOwner = 0xDEB333a3240eb2e1cA45D38654c26a8C1AAd0507;
        emit OwnershipTransferred(owner, initialOwner);
        owner = initialOwner;

    // Mint the fixed 100M supply only on the canonical chain (Ethereum mainnet) to the owner.
    if (isCanonicalChain()) {
            uint256 totalSupply = 100_000_000 ether;
            _mint(owner, totalSupply);
            emit InitialSupplyMinted(owner, totalSupply, block.chainid);
        }
    }

    /// @inheritdoc SuperchainERC20
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @inheritdoc SuperchainERC20
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// @notice Accept ETH sent to this contract.
    receive() external payable {}

    /// @notice Owner can withdraw ETH held by this contract to the owner.
    function withdrawStuckETH() public onlyOwner {
        uint256 bal = address(this).balance;
        if (bal == 0) return;
        (bool ok, ) = payable(owner).call{value: bal}("");
        require(ok, "ETH transfer failed");
    }

    /// @notice Owner can withdraw any ERC20 tokens held by this contract to the owner.
    function withdrawStuckTokens(address tkn) public onlyOwner {
        uint256 amount = IERC20(tkn).balanceOf(address(this));
        require(amount > 0, "No tokens");
        bool ok = IERC20(tkn).transfer(owner, amount);
        require(ok, "Token transfer failed");
    }

    /// @notice Enable trading on this chain. Irreversible.
    function enableTrading() external onlyOwner {
        if (chainTradable) revert("Trading already enabled");
        chainTradable = true;
        emit TradingStatusChanged(true);
    }

    /// @dev Gating for transfers while paused.
    /// Allows:
    /// - Mints and burns (not routed via _transfer in Solady, but kept for clarity)
    /// - Owner-related transfers (from or to owner) so the owner can seed liquidity or move tokens
    /// Blocks:
    /// - All other transfers while chainTradable == false
    function _transfer(address from, address to, uint256 amount) internal override {
        if (!chainTradable) {
            // If neither side is the zero address (i.e., not mint/burn) and neither side is the owner,
            // block the transfer while paused.
            if (from != address(0) && to != address(0)) {
                if (from != owner && to != owner) revert TradingPaused();
            }
        }
        super._transfer(from, to, amount);
    }
}