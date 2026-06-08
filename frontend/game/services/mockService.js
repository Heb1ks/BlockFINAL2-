/**
 * mockService.js
 * Mock data layer — used when GameItemsV2 contract is unavailable
 * or wallet is not connected. Mirrors the real contract interface.
 */

// ─── Item Definitions ──────────────────────────────────────────────────────
export const ITEM_DEFS = {
    0: {
        id: 0,
        name: "Sword",
        emoji: "⚔️",
        rarity: "rare",
        rarityLabel: "Rare",
        description: "A razor-edged blade forged in the heart of a dying star. Deals 45–70 physical damage.",
        stats: { Attack: 58, Speed: 32, Magic: 0 },
        type: "Weapon",
    },
    1: {
        id: 1,
        name: "Shield",
        emoji: "🛡️",
        rarity: "common",
        rarityLabel: "Common",
        description: "Tempered ironwood reinforced with rune-inscribed steel bands. Block chance +25%.",
        stats: { Defense: 72, HP: 15, Speed: -5 },
        type: "Armor",
    },
    2: {
        id: 2,
        name: "Potion",
        emoji: "🧪",
        rarity: "common",
        rarityLabel: "Common",
        description: "Shimmering life-essence brewed from moonflower extract. Restores 120 HP instantly.",
        stats: { Healing: 120 },
        type: "Consumable",
    },
    3: {
        id: 3,
        name: "Armor",
        emoji: "🪖",
        rarity: "epic",
        rarityLabel: "Epic",
        description: "Dragonscale plate imbued with ancient wards. Reduces all incoming damage by 30%.",
        stats: { Defense: 95, HP: 40, Speed: -10 },
        type: "Armor",
    },
    4: {
        id: 4,
        name: "Magic Orb",
        emoji: "🔮",
        rarity: "legendary",
        rarityLabel: "Legendary",
        description: "A crystallized fragment of pure arcane energy. Amplifies all spells by 80% and glows eternally.",
        stats: { Magic: 110, MP: 60, Wisdom: 45 },
        type: "Accessory",
    },
}

// ─── Crafting Recipes ──────────────────────────────────────────────────────
// Each recipe mirrors what would be registered via GameItemsV2.registerRecipe()
export const CRAFTING_RECIPES = [
    {
        id: "recipe_0",
        name: "Forge a Sword",
        description: "Combine raw materials at the forge to create a battle-ready blade.",
        inputs: [
            { itemId: 2, amount: 2, label: "Potion ×2" },
            { itemId: 1, amount: 1, label: "Shield ×1" },
        ],
        output: { itemId: 0, amount: 1 },
        // Solidity calldata
        inputIds: [2, 1],
        inputAmounts: [2, 1],
        outputId: 0,
        outputAmount: 1,
    },
    {
        id: "recipe_1",
        name: "Brew Potions",
        description: "Distill arcane essence from a Magic Orb into healing draughts.",
        inputs: [
            { itemId: 4, amount: 1, label: "Magic Orb ×1" },
        ],
        output: { itemId: 2, amount: 3 },
        inputIds: [4],
        inputAmounts: [1],
        outputId: 2,
        outputAmount: 3,
    },
    {
        id: "recipe_2",
        name: "Craft Epic Armor",
        description: "Layer shields and magical energy into impenetrable dragonscale plate.",
        inputs: [
            { itemId: 1, amount: 2, label: "Shield ×2" },
            { itemId: 4, amount: 1, label: "Magic Orb ×1" },
        ],
        output: { itemId: 3, amount: 1 },
        inputIds: [1, 4],
        inputAmounts: [2, 1],
        outputId: 3,
        outputAmount: 1,
    },
    {
        id: "recipe_3",
        name: "Infuse Magic Orb",
        description: "Channel three potions into a single crystallized arcane focus.",
        inputs: [
            { itemId: 2, amount: 3, label: "Potion ×3" },
        ],
        output: { itemId: 4, amount: 1 },
        inputIds: [2],
        inputAmounts: [3],
        outputId: 4,
        outputAmount: 1,
    },
]

// ─── In-Memory Mock Inventory ──────────────────────────────────────────────
let _mockInventory = {
    0: 2,  // 2× Sword
    1: 3,  // 3× Shield
    2: 5,  // 5× Potion
    3: 1,  // 1× Armor
    4: 1,  // 1× Magic Orb
}

/** Returns array of { itemId, amount, ...itemDef } for items with amount > 0 */
export function getMockInventory() {
    return Object.entries(_mockInventory)
        .filter(([, amt]) => amt > 0)
        .map(([id, amount]) => ({
            ...ITEM_DEFS[Number(id)],
            amount,
        }))
}

/** Simulates a craft transaction (burn inputs, mint output) */
export async function mockCraft(recipe) {
    // Validate balances
    for (const inp of recipe.inputs) {
        const have = _mockInventory[inp.itemId] || 0
        if (have < inp.amount) {
            throw new Error(`Not enough ${ITEM_DEFS[inp.itemId].name} (need ${inp.amount}, have ${have})`)
        }
    }

    // Simulate network delay
    await delay(1800)

    // Burn inputs
    for (const inp of recipe.inputs) {
        _mockInventory[inp.itemId] = (_mockInventory[inp.itemId] || 0) - inp.amount
    }

    // Mint output
    const outId = recipe.output.itemId
    const outAmt = recipe.output.amount
    _mockInventory[outId] = (_mockInventory[outId] || 0) + outAmt

    return {
        success: true,
        outputItem: ITEM_DEFS[outId],
        outputAmount: outAmt,
    }
}

function delay(ms) {
    return new Promise(res => setTimeout(res, ms))
}
