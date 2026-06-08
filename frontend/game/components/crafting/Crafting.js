/**
 * components/crafting/Crafting.js
 * Self-contained crafting component.
 * Shows recipes, validates inventory, fires blockchain (or mock) tx.
 */

import { CRAFTING_RECIPES, ITEM_DEFS } from "../../services/inventoryService.js"
import { fetchInventory, executeCraft, isCraftingEnabled } from "../../services/inventoryService.js"
import { showToast } from "./Toast.js"

const RARITY_COLORS = {
    common:    "#6b7280",
    rare:      "#3b82f6",
    epic:      "#8b5cf6",
    legendary: "#f59e0b",
}

// ─── State ─────────────────────────────────────────────────────────────────
let _inventory     = {}   // { itemId: amount }
let _selectedRecipe = null
let _crafting      = false

// ─── Mount ──────────────────────────────────────────────────────────────────

export async function mountCrafting(containerEl) {
    containerEl.innerHTML = buildCraftingHTML()
    await loadInventoryMap()
    renderRecipes()
    bindCraftingEvents(containerEl)
}

export async function refreshCrafting(address) {
    const items = await fetchInventory(address)
    _inventory = {}
    items.forEach(it => { _inventory[it.id] = it.amount })
    renderRecipes()
    if (_selectedRecipe) renderCraftDetail(_selectedRecipe)
}

// ─── HTML ───────────────────────────────────────────────────────────────────

function buildCraftingHTML() {
    return `
<div class="craft-wrapper" id="craft-wrapper">

    <!-- Header -->
    <div class="craft-header">
        <span class="craft-icon">⚒️</span>
        <h2 class="craft-title">Crafting Forge</h2>
        <span class="craft-status-badge" id="craft-mode-badge">● MOCK</span>
    </div>

    <div class="craft-body">

        <!-- Recipe list -->
        <div class="craft-recipes" id="craft-recipes">
            <!-- populated by JS -->
        </div>

        <!-- Craft panel -->
        <div class="craft-panel" id="craft-panel">
            <div class="craft-panel-empty">
                <div class="craft-panel-empty-icon">⚒️</div>
                <p>Select a recipe<br>to begin crafting</p>
            </div>
        </div>

    </div>
</div>`
}

// ─── Recipe List ────────────────────────────────────────────────────────────

function renderRecipes() {
    const list = document.getElementById("craft-recipes")
    if (!list) return

    list.innerHTML = CRAFTING_RECIPES.map(recipe => {
        const canCraft = checkCanCraft(recipe)
        const outItem  = ITEM_DEFS[recipe.output.itemId]
        const rc       = RARITY_COLORS[outItem.rarity] || "#6b7280"
        const isSelected = _selectedRecipe?.id === recipe.id

        return `
        <div class="craft-recipe-card ${canCraft ? "craft-recipe-card--can" : "craft-recipe-card--cant"} 
                                       ${isSelected ? "craft-recipe-card--selected" : ""}"
             data-recipe-id="${recipe.id}"
             style="--recipe-color:${rc}">
            <div class="craft-recipe-output">
                <span class="craft-recipe-emoji">${outItem.emoji}</span>
                <div class="craft-recipe-info">
                    <span class="craft-recipe-name">${recipe.name}</span>
                    <span class="craft-recipe-rarity" style="color:${rc}">${outItem.rarityLabel}</span>
                </div>
            </div>
            <div class="craft-recipe-inputs">
                ${recipe.inputs.map(inp => {
            const have   = _inventory[inp.itemId] || 0
            const enough = have >= inp.amount
            const inpDef = ITEM_DEFS[inp.itemId]
            return `<span class="craft-ingredient ${enough ? "" : "craft-ingredient--missing"}"
                                  title="${inpDef.name}: have ${have}/${inp.amount}">
                                ${inpDef.emoji}${inp.amount > 1 ? "×" + inp.amount : ""}
                            </span>`
        }).join("")}
            </div>
            <div class="craft-recipe-badge ${canCraft ? "craft-badge--ready" : "craft-badge--locked"}">
                ${canCraft ? "READY" : "LOCKED"}
            </div>
        </div>`
    }).join("")
}

// ─── Craft Detail Panel ─────────────────────────────────────────────────────

function renderCraftDetail(recipe) {
    const panel = document.getElementById("craft-panel")
    if (!panel) return

    const outItem  = ITEM_DEFS[recipe.output.itemId]
    const rc       = RARITY_COLORS[outItem.rarity] || "#6b7280"
    const canCraft = checkCanCraft(recipe)

    const inputsHTML = recipe.inputs.map(inp => {
        const inpDef = ITEM_DEFS[inp.itemId]
        const have   = _inventory[inp.itemId] || 0
        const enough = have >= inp.amount
        return `
        <div class="craft-detail-ingredient ${enough ? "" : "craft-detail-ingredient--missing"}">
            <span class="craft-detail-ing-emoji">${inpDef.emoji}</span>
            <div class="craft-detail-ing-info">
                <span class="craft-detail-ing-name">${inpDef.name}</span>
                <span class="craft-detail-ing-count">${have} / ${inp.amount} ${enough ? "✓" : "✗"}</span>
            </div>
            <div class="craft-detail-ing-bar-wrap">
                <div class="craft-detail-ing-bar ${enough ? "" : "craft-detail-ing-bar--lack"}"
                     style="width:${Math.min(have / inp.amount * 100, 100)}%"></div>
            </div>
        </div>`
    }).join("")

    panel.innerHTML = `
    <div class="craft-detail">

        <div class="craft-detail-header" style="--recipe-color:${rc}">
            <div class="craft-detail-out-icon">${outItem.emoji}</div>
            <div>
                <h3 class="craft-detail-title">${recipe.name}</h3>
                <p class="craft-detail-desc">${recipe.description}</p>
            </div>
        </div>

        <!-- Ingredients -->
        <div class="craft-detail-section">
            <h4 class="craft-detail-section-title">Required Materials</h4>
            <div class="craft-detail-ingredients">${inputsHTML}</div>
        </div>

        <!-- Arrow + Output -->
        <div class="craft-detail-arrow">
            <span class="craft-arrow-line"></span>
            <span class="craft-arrow-label">yields</span>
            <span class="craft-arrow-line"></span>
        </div>
        <div class="craft-detail-output-box" style="--recipe-color:${rc}">
            <span class="craft-output-emoji">${outItem.emoji}</span>
            <div>
                <span class="craft-output-name">${outItem.name}</span>
                <span class="craft-output-amount">×${recipe.output.amount}</span>
                <span class="craft-output-rarity" style="color:${rc}">${outItem.rarityLabel}</span>
            </div>
        </div>

        <!-- Status -->
        <div class="craft-detail-status" id="craft-detail-status"></div>

        <!-- Craft button -->
        <button class="craft-btn ${canCraft ? "" : "craft-btn--disabled"}"
                id="craft-execute-btn"
                ${canCraft ? "" : "disabled"}
                data-recipe-id="${recipe.id}">
            ${canCraft ? "⚒️ Craft Now" : "🔒 Insufficient Materials"}
        </button>
    </div>`

    // Bind craft button
    const btn = panel.querySelector("#craft-execute-btn")
    if (btn && canCraft) {
        btn.addEventListener("click", () => doExecuteCraft(recipe))
    }
}

// ─── Craft Execution ────────────────────────────────────────────────────────

async function doExecuteCraft(recipe) {
    if (_crafting) return
    _crafting = true

    const btn      = document.getElementById("craft-execute-btn")
    const statusEl = document.getElementById("craft-detail-status")

    if (btn) { btn.disabled = true; btn.textContent = "⏳ Crafting..." }

    const setStatus = (type, msg) => {
        if (!statusEl) return
        statusEl.className = `craft-detail-status tx-status ${type}`
        statusEl.textContent = msg
    }

    try {
        const result = await executeCraft(recipe, setStatus)

        // Show toast
        showToast(
            `${result.outputItem.emoji} Crafted ${result.outputAmount}× ${result.outputItem.name}!`,
            "success"
        )

        // Refresh after craft
        const items = await fetchInventory(window._userAddress || null)
        _inventory = {}
        items.forEach(it => { _inventory[it.id] = it.amount })
        renderRecipes()
        renderCraftDetail(recipe)

    } catch (err) {
        showToast(`❌ Craft failed: ${err.message?.slice(0, 60) || "Unknown error"}`, "error")
    }

    _crafting = false
    if (btn) { btn.disabled = false; btn.textContent = "⚒️ Craft Now" }
}

// ─── Helpers ────────────────────────────────────────────────────────────────

async function loadInventoryMap() {
    const items = await fetchInventory(window._userAddress || null)
    _inventory = {}
    items.forEach(it => { _inventory[it.id] = it.amount })
}

function checkCanCraft(recipe) {
    return recipe.inputs.every(inp =>
        (_inventory[inp.itemId] || 0) >= inp.amount
    )
}

function bindCraftingEvents(containerEl) {
    const list  = containerEl.querySelector("#craft-recipes")
    const badge = containerEl.querySelector("#craft-mode-badge")

    // Update mock/live badge
    import("../../services/inventoryService.js").then(({ isLive }) => {
        if (badge) {
            if (isLive()) {
                badge.textContent = "● LIVE"
                badge.style.color = "#34d399"
            } else {
                badge.textContent = "● MOCK"
                badge.style.color = "#f59e0b"
            }
        }
    })

    // Delegate click on recipe cards
    if (list) {
        list.addEventListener("click", e => {
            const card = e.target.closest(".craft-recipe-card")
            if (!card) return
            const rid = card.dataset.recipeId
            _selectedRecipe = CRAFTING_RECIPES.find(r => r.id === rid) || null
            renderRecipes()
            if (_selectedRecipe) renderCraftDetail(_selectedRecipe)
        })
    }
}
