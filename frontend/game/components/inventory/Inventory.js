/**
 * components/inventory/Inventory.js
 * Self-contained inventory component.
 * Renders an RPG-style grid. Supports click-to-inspect and drag-to-reorder.
 * No framework dependency — works with the existing vanilla JS stack.
 */

import { fetchInventory, ITEM_DEFS } from "../../services/inventoryService.js"

// ─── Rarity Config ──────────────────────────────────────────────────────────
const RARITY_COLORS = {
    common:    { border: "#6b7280", glow: "rgba(107,114,128,0.35)", badge: "#6b7280", text: "#d1d5db" },
    rare:      { border: "#3b82f6", glow: "rgba(59,130,246,0.45)",  badge: "#3b82f6", text: "#93c5fd" },
    epic:      { border: "#8b5cf6", glow: "rgba(139,92,246,0.5)",   badge: "#8b5cf6", text: "#c4b5fd" },
    legendary: { border: "#f59e0b", glow: "rgba(245,158,11,0.55)",  badge: "#d97706", text: "#fcd34d" },
}

const TOTAL_SLOTS = 20  // grid always shows 20 slots

// ─── State ─────────────────────────────────────────────────────────────────
let _items         = []
let _selectedIndex = null
let _dragSrc       = null

// ─── Main Render ────────────────────────────────────────────────────────────

/** Call this to mount the inventory into a container element */
export function mountInventory(containerEl) {
    containerEl.innerHTML = buildInventoryHTML()
    bindInventoryEvents(containerEl)
}

/** Reload items from chain/mock and re-render grid */
export async function refreshInventory(address) {
    _items = await fetchInventory(address)
    const grid = document.getElementById("inv-grid")
    if (grid) renderGrid(grid)
    if (_selectedIndex !== null) {
        renderDetail(_items[_selectedIndex] || null)
    }
}

// ─── HTML Builders ─────────────────────────────────────────────────────────

function buildInventoryHTML() {
    return `
<div class="inv-wrapper" id="inv-wrapper">

    <!-- Header bar -->
    <div class="inv-header">
        <div class="inv-title-row">
            <span class="inv-icon">🎒</span>
            <h2 class="inv-title">Inventory</h2>
            <span class="inv-count" id="inv-count">Loading...</span>
        </div>
        <div class="inv-header-actions">
            <button class="inv-btn inv-btn-loot" id="inv-loot-btn" title="Request VRF Loot Drop">
                🎲 Loot Drop
            </button>
            <button class="inv-btn inv-btn-refresh" id="inv-refresh-btn" title="Refresh from chain">
                ↺ Refresh
            </button>
        </div>
    </div>
    <div class="inv-loot-status" id="inv-loot-status"></div>

    <!-- Main content: grid + detail panel -->
    <div class="inv-body">

        <!-- Grid -->
        <div class="inv-grid-wrap">
            <div class="inv-grid" id="inv-grid">
                ${buildLoadingSlots()}
            </div>
            <p class="inv-hint">Click item to inspect · Drag to rearrange</p>
        </div>

        <!-- Detail panel -->
        <div class="inv-detail" id="inv-detail">
            ${buildEmptyDetail()}
        </div>

    </div>
</div>`
}

function buildLoadingSlots() {
    return Array.from({ length: TOTAL_SLOTS }, () =>
        `<div class="inv-slot inv-slot--loading"></div>`
    ).join("")
}

function buildEmptyDetail() {
    return `
    <div class="inv-detail-empty">
        <div class="inv-detail-empty-icon">🎒</div>
        <p>Select an item to<br>view its details</p>
    </div>`
}

// ─── Grid Renderer ──────────────────────────────────────────────────────────

function renderGrid(grid) {
    const countEl = document.getElementById("inv-count")
    const totalItems = _items.reduce((s, i) => s + i.amount, 0)
    if (countEl) countEl.textContent = `${_items.length} types · ${totalItems} total`

    const slots = Array(TOTAL_SLOTS).fill(null)
    _items.forEach((item, i) => { if (i < TOTAL_SLOTS) slots[i] = item })

    grid.innerHTML = slots.map((item, i) => buildSlot(item, i)).join("")

    // Re-bind drag events after re-render
    grid.querySelectorAll(".inv-slot--filled").forEach(slot => {
        slot.addEventListener("dragstart", onDragStart)
        slot.addEventListener("dragover",  onDragOver)
        slot.addEventListener("drop",      onDrop)
        slot.addEventListener("dragend",   onDragEnd)
    })
}

function buildSlot(item, index) {
    if (!item) {
        return `<div class="inv-slot inv-slot--empty" 
                     data-index="${index}"
                     ondragover="event.preventDefault()"
                     ondrop="window._invDropEmpty && window._invDropEmpty(event, ${index})">
                </div>`
    }

    const rc = RARITY_COLORS[item.rarity] || RARITY_COLORS.common
    const isSelected = _selectedIndex === index

    return `
    <div class="inv-slot inv-slot--filled ${isSelected ? "inv-slot--selected" : ""}"
         data-index="${index}"
         data-item-id="${item.id}"
         draggable="true"
         style="
            --slot-border: ${rc.border};
            --slot-glow:   ${rc.glow};
         "
         title="${item.name} (${item.rarityLabel})"
    >
        <div class="inv-slot-inner">
            <span class="inv-slot-emoji">${item.emoji}</span>
            <span class="inv-slot-amount" ${item.amount === 1 ? 'style="opacity:0.3"' : ""}>×${item.amount}</span>
        </div>
        <div class="inv-slot-rarity-bar" style="background:${rc.border}"></div>
    </div>`
}

// ─── Detail Panel ───────────────────────────────────────────────────────────

function renderDetail(item) {
    const panel = document.getElementById("inv-detail")
    if (!panel) return

    if (!item) {
        panel.innerHTML = buildEmptyDetail()
        return
    }

    const rc = RARITY_COLORS[item.rarity] || RARITY_COLORS.common

    const statsHTML = Object.entries(item.stats || {}).map(([k, v]) => {
        const isNeg = v < 0
        const pct   = Math.min(Math.abs(v), 120) / 120 * 100
        return `
        <div class="inv-stat-row">
            <span class="inv-stat-name">${k}</span>
            <div class="inv-stat-bar-wrap">
                <div class="inv-stat-bar ${isNeg ? "inv-stat-bar--neg" : ""}" 
                     style="width:${pct}%;background:${isNeg ? "#ef4444" : rc.border}"></div>
            </div>
            <span class="inv-stat-val ${isNeg ? "inv-stat-neg" : ""}">${v > 0 ? "+" : ""}${v}</span>
        </div>`
    }).join("")

    panel.innerHTML = `
    <div class="inv-detail-content">
        <div class="inv-detail-hero" style="--rarity-color:${rc.border};--rarity-glow:${rc.glow}">
            <div class="inv-detail-emoji">${item.emoji}</div>
            <span class="inv-detail-badge" style="background:${rc.badge};color:#fff">${item.rarityLabel}</span>
        </div>
        <h3 class="inv-detail-name">${item.name}</h3>
        <p class="inv-detail-type">${item.type}</p>
        <p class="inv-detail-desc">${item.description}</p>
        <div class="inv-detail-qty">
            <span class="inv-detail-qty-label">Owned</span>
            <span class="inv-detail-qty-val">${item.amount}</span>
        </div>
        ${statsHTML ? `<div class="inv-stats">${statsHTML}</div>` : ""}
    </div>`
}

// ─── Event Binding ──────────────────────────────────────────────────────────

function bindInventoryEvents(containerEl) {
    // Delegate click on grid
    const grid = containerEl.querySelector("#inv-grid")
    grid.addEventListener("click", e => {
        const slot = e.target.closest(".inv-slot--filled")
        if (!slot) return
        const idx = parseInt(slot.dataset.index, 10)
        _selectedIndex = (_selectedIndex === idx) ? null : idx
        renderGrid(grid)
        renderDetail(_selectedIndex !== null ? _items[_selectedIndex] : null)
    })

    // Refresh button
    const refreshBtn = containerEl.querySelector("#inv-refresh-btn")
    if (refreshBtn) {
        refreshBtn.addEventListener("click", async () => {
            refreshBtn.disabled = true
            refreshBtn.textContent = "↺ Loading..."
            await refreshInventory(window._userAddress || null)
            refreshBtn.disabled = false
            refreshBtn.textContent = "↺ Refresh"
        })
    }

    // Loot Drop button
    const lootBtn = containerEl.querySelector("#inv-loot-btn")
    const lootStatus = containerEl.querySelector("#inv-loot-status")
    if (lootBtn && lootStatus) {
        lootBtn.addEventListener("click", async () => {
            lootBtn.disabled = true
            const { requestLootDrop } = await import("../../services/inventoryService.js")
            try {
                await requestLootDrop((type, msg) => {
                    lootStatus.className = `inv-loot-status tx-status ${type}`
                    lootStatus.textContent = msg
                    lootStatus.style.display = "block"
                })
                await refreshInventory(window._userAddress)
            } catch {}
            lootBtn.disabled = false
            setTimeout(() => { lootStatus.style.display = "none" }, 6000)
        })
    }
}

// ─── Drag & Drop ────────────────────────────────────────────────────────────

function onDragStart(e) {
    _dragSrc = parseInt(e.currentTarget.dataset.index, 10)
    e.currentTarget.classList.add("inv-slot--dragging")
    e.dataTransfer.effectAllowed = "move"
}

function onDragOver(e) {
    e.preventDefault()
    e.dataTransfer.dropEffect = "move"
    e.currentTarget.classList.add("inv-slot--dragover")
}

function onDrop(e) {
    e.preventDefault()
    const target = parseInt(e.currentTarget.dataset.index, 10)
    e.currentTarget.classList.remove("inv-slot--dragover")
    if (_dragSrc === null || _dragSrc === target) return

    // Swap items
    const tmp = _items[_dragSrc]
    if (!_items[target]) {
        _items[target] = _items[_dragSrc]
        _items[_dragSrc] = null
        _items = _items.filter(Boolean)
    } else {
        _items[_dragSrc] = _items[target]
        _items[target] = tmp
    }
    _selectedIndex = null
    const grid = document.getElementById("inv-grid")
    if (grid) renderGrid(grid)
}

function onDragEnd(e) {
    e.currentTarget.classList.remove("inv-slot--dragging")
    document.querySelectorAll(".inv-slot--dragover").forEach(el =>
        el.classList.remove("inv-slot--dragover"))
    _dragSrc = null
}
