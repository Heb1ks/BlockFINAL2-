/**
 * inventoryService.js
 * Wraps GameItemsV2 ERC-1155 contract calls via ethers.js.
 * Falls back transparently to mock service when no wallet or wrong network.
 */

import { ITEM_DEFS, CRAFTING_RECIPES, getMockInventory, mockCraft } from "./mockService.js"


export const GAME_ITEMS_ADDRESS = "0xD9F25A49ea7fE5f8a6Fa38DAfeCD7113AA5D72C7"
export const LOOT_DROP_ADDRESS  = "0x3E2543ee4ecF024e12ace9Ca12D4A9Fd3E0deAe0"

export const GAME_ITEMS_V2_ABI = [
    // ERC-1155 read
    "function balanceOf(address account, uint256 id) view returns (uint256)",
    "function balanceOfBatch(address[] accounts, uint256[] ids) view returns (uint256[])",
    // ERC-1155 write
    "function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes data)",
    // GameItemsV2
    "function craftingEnabled() view returns (bool)",
    "function craftingRecipes(bytes32 key) view returns (bool)",
    "function craft(uint256[] inputIds, uint256[] inputAmounts, uint256 outputId, uint256 outputAmount)",
    // Events
    "event ItemCrafted(address indexed player, uint256 outputId, uint256 amount)",
    "event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value)",
]

export const LOOT_DROP_ABI = [
    "function requestLoot() returns (uint256 requestId)",
    "event LootRequested(uint256 indexed requestId, address indexed player)",
    "event LootDropped(uint256 indexed requestId, address indexed player, uint256 itemId)",
    "event LootMissed(uint256 indexed requestId, address indexed player)",
]

// Re-export for convenience
export { ITEM_DEFS, CRAFTING_RECIPES }


let _contract = null
let _lootContract = null
let _signer = null
let _address = null
let _useMock = true

/**
 * Call this once wallet is connected (from app.js connectWallet).
 * Pass the ethers signer and user address.
 */
export function initInventoryService(signer, address) {
    _signer = signer
    _address = address

    if (typeof ethers !== "undefined" && signer) {
        try {
            _contract = new ethers.Contract(GAME_ITEMS_ADDRESS, GAME_ITEMS_V2_ABI, signer)
            _lootContract = new ethers.Contract(LOOT_DROP_ADDRESS, LOOT_DROP_ABI, signer)
            _useMock = false
        } catch (e) {
            console.warn("[InventoryService] Contract init failed, using mock:", e)
            _useMock = true
        }
    } else {
        _useMock = true
    }
}

/** Returns true when using real blockchain, false when mock */
export function isLive() { return !_useMock }



/**
 * Fetch all item balances for the connected user.
 * Returns array of { id, name, emoji, rarity, amount, ... }
 */
export async function fetchInventory(address) {
    const addr = address || _address
    if (!addr) return getMockInventory()

    if (_useMock || !_contract) {
        return getMockInventory()
    }

    try {
        const ids = [0, 1, 2, 3, 4]
        const addrs = ids.map(() => addr)
        const balances = await _contract.balanceOfBatch(addrs, ids)

        return ids.map((id, i) => ({
            ...ITEM_DEFS[id],
            amount: Number(balances[i]),
        })).filter(item => item.amount > 0)

    } catch (err) {
        console.error("[InventoryService] fetchInventory failed, falling back to mock:", err)
        return getMockInventory()
    }
}


/**
 * Check if crafting is enabled on the contract.
 */
export async function isCraftingEnabled() {
    if (_useMock || !_contract) return true
    try {
        return await _contract.craftingEnabled()
    } catch {
        return true
    }
}

/**
 * Execute a craft transaction.
 * @param {object} recipe - from CRAFTING_RECIPES
 * @param {function} onStatus - callback(type: 'pending'|'success'|'error', msg)
 * @returns {{ success, outputItem, outputAmount, txHash? }}
 */
export async function executeCraft(recipe, onStatus = () => {}) {
    if (_useMock || !_contract) {
        // Mock path
        onStatus("pending", "Simulating transaction...")
        const result = await mockCraft(recipe)
        onStatus("success", ` Crafted ${result.outputAmount}× ${result.outputItem.name}!`)
        return result
    }

    // Live blockchain path
    try {
        onStatus("pending", "Sending craft transaction...")

        const tx = await _contract.craft(
            recipe.inputIds,
            recipe.inputAmounts,
            recipe.outputId,
            recipe.outputAmount
        )

        onStatus("pending", ` Pending: ${tx.hash.slice(0, 12)}...`)
        const receipt = await tx.wait()

        const outputItem = ITEM_DEFS[recipe.outputId]
        onStatus("success", `Crafted! tx: ${tx.hash.slice(0, 10)}...`)

        return {
            success: true,
            outputItem,
            outputAmount: recipe.outputAmount,
            txHash: tx.hash,
        }
    } catch (err) {
        const msg = err.reason || err.shortMessage || err.message?.slice(0, 100) || "Unknown error"
        onStatus("error", `❌ ${msg}`)
        throw err
    }
}

/**
 * Request a loot drop via Chainlink VRF.
 * @param {function} onStatus - callback(type, msg)
 */
export async function requestLootDrop(onStatus = () => {}) {
    if (_useMock || !_lootContract) {
        onStatus("pending", "Requesting loot (mock)...")
        await new Promise(r => setTimeout(r, 1500))
        // Random mock result
        const won = Math.random() > 0.5
        if (won) {
            const itemId = Math.floor(Math.random() * 5)
            onStatus("success", ` Loot dropped: ${ITEM_DEFS[itemId].emoji} ${ITEM_DEFS[itemId].name}!`)
            return { won: true, itemId }
        } else {
            onStatus("error", " No loot this time. Try again!")
            return { won: false }
        }
    }

    try {
        onStatus("pending", "Requesting VRF loot drop...")
        const tx = await _lootContract.requestLoot()
        onStatus("pending", ` Waiting: ${tx.hash.slice(0, 12)}...`)
        await tx.wait()
        onStatus("success", " VRF request submitted! Item will arrive shortly.")
        return { success: true, txHash: tx.hash }
    } catch (err) {
        const msg = err.reason || err.shortMessage || err.message?.slice(0, 80)
        onStatus("error", `❌ ${msg}`)
        throw err
    }
}
