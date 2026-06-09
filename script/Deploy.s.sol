// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/GameToken.sol";
import "../src/GameItems.sol";
import "../src/GameItemsV2.sol";
import "../src/GameAMM.sol";
import "../src/GameVault.sol";
import "../src/GameDAO.sol";
import "../src/GameFactory.sol";
import "../src/NFTRentalVault.sol";
import "../src/LootDrop.sol";

/// @dev Simple ERC-20 resource token for AMM pairing on testnet
contract GameResource is ERC20 {
    constructor() ERC20("GameResource", "GRES") {
        _mint(msg.sender, 1_000_000e18);
    }
}

/// @dev Minimal Chainlink-compatible price feed mock for testnet
contract DeployMockPriceFeed {
    uint8 public decimals;
    int256 public answer;
    uint80 public roundId;

    constructor(uint8 _dec, int256 _ans) {
        decimals = _dec;
        answer = _ans;
        roundId = 1;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, block.timestamp, block.timestamp, roundId);
    }
}

/// @title Deploy - idempotent full-protocol deployment to Arbitrum Sepolia
///
/// forge script script/Deploy.s.sol \
///   --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
///   --broadcast --verify \
///   --etherscan-api-key $ARBISCAN_API_KEY -vvvv
///
/// Required env:
///   DEPLOYER_PRIVATE_KEY, ARBITRUM_SEPOLIA_RPC_URL, ARBISCAN_API_KEY
/// Optional env:
///   VRF_COORDINATOR, VRF_KEY_HASH, VRF_SUBSCRIPTION_ID, PRICE_FEED_ADDRESS
contract Deploy is Script {
    uint256 constant TIMELOCK_DELAY = 2 days;
    uint256 constant STALENESS = 3600;

    address deployer;

    GameToken gameToken;
    address gameItemsProxy;
    GameAMM gameAMM;
    GameVault gameVault;
    TimelockController timelock;
    GameDAO gameDAO;
    GameFactory gameFactory;
    NFTRentalVault rentalVault;
    LootDrop lootDrop;

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        deployer = vm.addr(pk);

        console.log("Deployer:", deployer);
        console.log("Chain:   ", block.chainid);

        vm.startBroadcast(pk);

        _step1_tokens();
        _step2_items();
        _step3_factory();
        _step4_governance();
        _step5_amm();
        _step6_vault();
        _step7_rental();
        _step8_lootdrop();
        _step9_postSetup();

        vm.stopBroadcast();

        _printSummary();
        _runChecks();
    }

    function _step1_tokens() internal {
        gameToken = new GameToken(deployer);
        console.log("[1] GameToken:", address(gameToken));
    }

    function _step2_items() internal {
        GameItemsV2 impl = new GameItemsV2();
        bytes memory d = abi.encodeCall(GameItems.initialize, (deployer));
        ERC1967Proxy px = new ERC1967Proxy(address(impl), d);
        gameItemsProxy = address(px);
        console.log("[2] GameItemsV2 proxy:", gameItemsProxy);
        console.log("[2] GameItemsV2 impl: ", address(impl));
    }

    function _step3_factory() internal {
        gameFactory = new GameFactory(deployer);
        console.log("[3] GameFactory:", address(gameFactory));
    }

    function _step4_governance() internal {
        address[] memory empty = new address[](0);
        timelock = new TimelockController(TIMELOCK_DELAY, empty, empty, deployer);
        gameDAO = new GameDAO(IVotes(address(gameToken)), timelock);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(gameDAO));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(gameDAO));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(gameDAO));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        console.log("[4] Timelock:", address(timelock));
        console.log("[4] GameDAO: ", address(gameDAO));
    }

    function _step5_amm() internal {
        GameResource resource = new GameResource();
        gameAMM = new GameAMM(address(gameToken), address(resource));
        console.log("[5] GameAMM:      ", address(gameAMM));
        console.log("[5] GameResource: ", address(resource));
    }

    function _step6_vault() internal {
        address priceFeed = vm.envOr("PRICE_FEED_ADDRESS", address(0));
        if (priceFeed == address(0)) {
            DeployMockPriceFeed mock = new DeployMockPriceFeed(8, 2e8);
            priceFeed = address(mock);
            console.log("[6] MockPriceFeed:", priceFeed);
        }
        gameVault = new GameVault(IERC20(address(gameToken)), priceFeed, deployer, STALENESS);
        console.log("[6] GameVault:", address(gameVault));
    }

    function _step7_rental() internal {
        rentalVault = new NFTRentalVault(gameItemsProxy, address(gameToken), deployer);
        console.log("[7] NFTRentalVault:", address(rentalVault));
    }

    function _step8_lootdrop() internal {
        address vrfCoord = vm.envOr("VRF_COORDINATOR", address(0));
        bytes32 keyHash = vm.envOr("VRF_KEY_HASH", bytes32(0));
        uint256 subId = vm.envOr("VRF_SUBSCRIPTION_ID", uint256(1));

        if (vrfCoord == address(0)) {
            console.log("[8] VRF_COORDINATOR not set - skipping LootDrop");
            return;
        }
        lootDrop = new LootDrop(vrfCoord, gameItemsProxy, keyHash, subId);
        console.log("[8] LootDrop:", address(lootDrop));
    }

    function _step9_postSetup() internal {
        GameItemsV2 items = GameItemsV2(gameItemsProxy);

        if (address(lootDrop) != address(0)) {
            items.grantRole(items.MINTER_ROLE(), address(lootDrop));
        }

        gameVault.setYieldDepositor(address(rentalVault), true);

        // ✅ SETUP CRAFTING BEFORE REVOKING DEPLOYER ROLE
        _setupCraftingBeforeRevokeRole(items);

        // Transfer all admin power to Timelock
        gameToken.transferOwnership(address(timelock));
        gameVault.transferOwnership(address(timelock));
        rentalVault.transferOwnership(address(timelock));

        items.grantRole(items.DEFAULT_ADMIN_ROLE(), address(timelock));
        items.renounceRole(items.DEFAULT_ADMIN_ROLE(), deployer);

        console.log("[9] Ownership transferred to Timelock");
    }

    // ✅ FIX BUG 2: Setup crafting BEFORE deployer role is revoked
    function _setupCraftingBeforeRevokeRole(GameItemsV2 items) internal {
        // Enable crafting
        items.setCraftingEnabled(true);
        console.log("[10] Crafting enabled");

        // Recipe 0: Forge a Sword — Potion×2 + Shield×1 → Sword×1
        {
            uint256[] memory ids = new uint256[](2);
            ids[0] = 2; // Potion
            ids[1] = 1; // Shield

            uint256[] memory amts = new uint256[](2);
            amts[0] = 2; // 2x Potion
            amts[1] = 1; // 1x Shield

            items.registerRecipe(ids, amts, 0); // outputId = 0 (Sword)
            console.log("[10] Recipe 0 (Forge Sword) registered");
        }

        // Recipe 1: Brew Potions — MagicOrb×1 → Potion×3
        {
            uint256[] memory ids = new uint256[](1);
            ids[0] = 4; // MagicOrb

            uint256[] memory amts = new uint256[](1);
            amts[0] = 1; // 1x MagicOrb

            items.registerRecipe(ids, amts, 2); // outputId = 2 (Potion)
            console.log("[10] Recipe 1 (Brew Potions) registered");
        }

        // Recipe 2: Craft Epic Armor — Shield×2 + MagicOrb×1 → Armor×1
        {
            uint256[] memory ids = new uint256[](2);
            ids[0] = 1; // Shield
            ids[1] = 4; // MagicOrb

            uint256[] memory amts = new uint256[](2);
            amts[0] = 2; // 2x Shield
            amts[1] = 1; // 1x MagicOrb

            items.registerRecipe(ids, amts, 3); // outputId = 3 (Armor)
            console.log("[10] Recipe 2 (Craft Epic Armor) registered");
        }

        // Recipe 3: Infuse Magic Orb — Potion×3 → MagicOrb×1
        {
            uint256[] memory ids = new uint256[](1);
            ids[0] = 2; // Potion

            uint256[] memory amts = new uint256[](1);
            amts[0] = 3; // 3x Potion

            items.registerRecipe(ids, amts, 4); // outputId = 4 (MagicOrb)
            console.log("[10] Recipe 3 (Infuse Magic Orb) registered");
        }

        console.log("[10] All crafting recipes registered!");
    }

    function _printSummary() internal view {
        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("GameToken:          ", address(gameToken));
        console.log("GameItemsV2 (proxy):", gameItemsProxy);
        console.log("GameFactory:        ", address(gameFactory));
        console.log("TimelockController: ", address(timelock));
        console.log("GameDAO:            ", address(gameDAO));
        console.log("GameAMM:            ", address(gameAMM));
        console.log("GameVault:          ", address(gameVault));
        console.log("NFTRentalVault:     ", address(rentalVault));
        if (address(lootDrop) != address(0)) {
            console.log("LootDrop:           ", address(lootDrop));
        }
        console.log("==================");
    }

    /// @notice Post-deploy sanity checks (run after broadcast)
    function _runChecks() internal view {
        require(gameToken.owner() == address(timelock), "FAIL: token owner != timelock");
        require(gameVault.owner() == address(timelock), "FAIL: vault owner != timelock");
        require(rentalVault.owner() == address(timelock), "FAIL: rental owner != timelock");
        require(timelock.getMinDelay() == TIMELOCK_DELAY, "FAIL: wrong timelock delay");

        GameItemsV2 items = GameItemsV2(gameItemsProxy);
        require(items.hasRole(items.DEFAULT_ADMIN_ROLE(), address(timelock)), "FAIL: timelock missing items admin role");
        require(items.craftingEnabled(), "FAIL: crafting not enabled");

        console.log("\n[checks] All post-deploy assertions passed!");
    }
}
