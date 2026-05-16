// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/AggregatorV3Interface.sol";

/// @title GameVault — ERC-4626 tokenized yield vault for GAME tokens
/// @notice Players deposit GAME tokens and earn yield from protocol fees.
///         Share price automatically increases as fees are forwarded to this vault.
///         Chainlink price feed provides on-chain USD valuation.
contract GameVault is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Chainlink price feed for GAME/USD (or GAME/ETH)
    AggregatorV3Interface public immutable priceFeed;

    /// @notice Maximum age of a Chainlink price before considered stale
    uint256 public stalenessThreshold;

    /// @notice Authorized yield depositors (e.g. NFTRentalVault)
    mapping(address => bool) public yieldDepositors;

    // ─── Events ──────────────────────────────────────────────────────────────
    event YieldDeposited(address indexed from, uint256 amount);
    event YieldDepositorSet(address indexed depositor, bool authorized);
    event StalenessThresholdUpdated(uint256 newThreshold);

    // ─── Errors ───────────────────────────────────────────────────────────────
    error UnauthorizedDepositor();
    error StalePriceFeed(uint256 updatedAt, uint256 currentTime);
    error InvalidPrice(int256 price);
    error IncompleteRound();

    // ─── Constructor ──────────────────────────────────────────────────────────
    constructor(
        IERC20 _asset,
        address _priceFeed,
        address _owner,
        uint256 _stalenessThreshold
    )
    ERC4626(_asset)
    ERC20("Staked GameToken", "sGAME")
    Ownable(_owner)
    {
        priceFeed = AggregatorV3Interface(_priceFeed);
        stalenessThreshold = _stalenessThreshold;
    }

    // ─── Yield Management ────────────────────────────────────────────────────

    /// @notice Allow an address to deposit yield into the vault
    function setYieldDepositor(address depositor, bool authorized) external onlyOwner {
        yieldDepositors[depositor] = authorized;
        emit YieldDepositorSet(depositor, authorized);
    }

    /// @notice Deposit protocol fees as yield — increases share price for all depositors
    /// @dev Caller must be an authorized yield depositor
    function depositYield(uint256 amount) external nonReentrant {
        if (!yieldDepositors[msg.sender] && msg.sender != owner()) {
            revert UnauthorizedDepositor();
        }
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        emit YieldDeposited(msg.sender, amount);
    }

    // ─── Oracle ───────────────────────────────────────────────────────────────

    /// @notice Update the staleness threshold (owner only)
    function setStalenessThreshold(uint256 newThreshold) external onlyOwner {
        stalenessThreshold = newThreshold;
        emit StalenessThresholdUpdated(newThreshold);
    }

    /// @notice Fetch the latest price from Chainlink with full staleness & validity checks
    /// @return price  Raw answer from the aggregator (8 decimals for USD pairs)
    /// @return updatedAt  Timestamp of the last price update
    function getLatestPrice() public view returns (int256 price, uint256 updatedAt) {
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 timestamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        if (answer <= 0) revert InvalidPrice(answer);
        if (timestamp == 0) revert IncompleteRound();
        if (block.timestamp - timestamp > stalenessThreshold) {
            revert StalePriceFeed(timestamp, block.timestamp);
        }
        // answeredInRound < roundId means the data is from an earlier round (stale)
        require(answeredInRound >= roundId, "Stale answeredInRound");

        return (answer, timestamp);
    }

    /// @notice Total vault value denominated in USD (result has 8 decimals)
    /// @dev totalAssets is 18-decimal, price is 8-decimal → divide by 1e18
    function totalValueUSD() external view returns (uint256) {
        (int256 price, ) = getLatestPrice();
        return (totalAssets() * uint256(price)) / 1e18;
    }

    // ─── ERC-4626 overrides ───────────────────────────────────────────────────

    /// @inheritdoc ERC4626
    /// @dev OZ ERC4626 already handles CEI correctly; nonReentrant adds extra safety
    function deposit(uint256 assets, address receiver)
    public
    override
    nonReentrant
    returns (uint256)
    {
        return super.deposit(assets, receiver);
    }

    /// @inheritdoc ERC4626
    function withdraw(uint256 assets, address receiver, address owner_)
    public
    override
    nonReentrant
    returns (uint256)
    {
        return super.withdraw(assets, receiver, owner_);
    }

    /// @inheritdoc ERC4626
    function mint(uint256 shares, address receiver)
    public
    override
    nonReentrant
    returns (uint256)
    {
        return super.mint(shares, receiver);
    }

    /// @inheritdoc ERC4626
    function redeem(uint256 shares, address receiver, address owner_)
    public
    override
    nonReentrant
    returns (uint256)
    {
        return super.redeem(shares, receiver, owner_);
    }
}
