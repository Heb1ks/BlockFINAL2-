const ADDRESSES = {
    gameToken:  "0x924C3De70B818Eff9E9f9420E7549337f76799EC",
    gameAMM:    "0x9D6BdA08801c0FDAA34f321B3091A2c5b8d59733",
    gameVault:  "0x07FA70449CF0dB5806CbCf99fe4a104E9007d7E1",
    gameDAO:    "0x8500fE560F12BBB92Dbeb4F2ed0f7d65CfFF1490",
}

const SUBGRAPH_URL = "https://api.studio.thegraph.com/query/1753408/gamefi-protocol/v0.0.8"
const ARBITRUM_SEPOLIA_CHAIN_ID = 421614n

const ERC20_ABI = [
    "function balanceOf(address) view returns (uint256)",
    "function approve(address spender, uint256 amount) returns (bool)",
    "function allowance(address owner, address spender) view returns (uint256)",
]

const VOTES_ABI = [
    ...ERC20_ABI,
    "function getVotes(address account) view returns (uint256)",
    "function delegates(address account) view returns (address)",
    "function delegate(address delegatee)",
]

const AMM_ABI = [
    "function swapAtoB(uint256 amountIn, uint256 minAmountOut) returns (uint256)",
    "function swapBtoA(uint256 amountIn, uint256 minAmountOut) returns (uint256)",
    "function getReserves() view returns (uint256 rA, uint256 rB)",
    "function balanceOf(address) view returns (uint256)",
    "function TOKEN_B() view returns (address)",
]

const VAULT_ABI = [
    "function deposit(uint256 assets, address receiver) returns (uint256)",
    "function redeem(uint256 shares, address receiver, address owner) returns (uint256)",
    "function balanceOf(address) view returns (uint256)",
    "function totalAssets() view returns (uint256)",
    "function totalSupply() view returns (uint256)",
]

// FIX BUG 1: Complete DAO ABI with propose and state functions
const DAO_ABI = [
    "function propose(address[] targets, uint256[] values, bytes[] calldatas, string description) returns (uint256)",
    "function castVote(uint256 proposalId, uint8 support) returns (uint256)",
    "function hasVoted(uint256 proposalId, address account) view returns (bool)",
    "function state(uint256 proposalId) view returns (uint8)",
    "function proposalThreshold() view returns (uint256)",
    "function votingDelay() view returns (uint256)",
    "function votingPeriod() view returns (uint256)",
]

let provider    = null
let signer      = null
let userAddress = null
let swapAtoB    = true

const contracts = {}

// ─── Wallet Connection ───────────────────────────────────────────────────────

async function connectWallet() {
    try {
        const state = await WalletState.connect()
        if (!state) return
        await _onWalletReady(state)
    } catch (err) {
        console.error("Wallet connection failed:", err)
        alert("Connection failed: " + err.message)
    }
}

/**
 * Shared setup run after wallet is connected (fresh or restored).
 */
async function _onWalletReady(state) {
    provider    = state.provider
    signer      = state.signer
    userAddress = state.address
    window._userAddress = userAddress

    // Update UI
    document.getElementById("connectBtn").style.display = "none"
    const wi = document.getElementById("walletInfo")
    wi.textContent = userAddress.slice(0, 6) + "..." + userAddress.slice(-4)
    wi.classList.add("visible")

    await checkNetwork()

    // Init contracts
    contracts.token = new ethers.Contract(ADDRESSES.gameToken, VOTES_ABI, signer)
    contracts.amm   = new ethers.Contract(ADDRESSES.gameAMM,   AMM_ABI,   signer)
    contracts.vault = new ethers.Contract(ADDRESSES.gameVault, VAULT_ABI, signer)
    contracts.dao   = new ethers.Contract(ADDRESSES.gameDAO,   DAO_ABI,   signer)

    // FIX BUG 1: Show proposal creation card after wallet is ready
    document.getElementById("create-proposal-card").style.display = ""

    // FIX BUG 1: load wallet data on entry
    await refreshStats()
    await loadSubgraphData()

    window.ethereum.on("chainChanged",    () => window.location.reload())
    window.ethereum.on("accountsChanged", () => {
        WalletState.clear()
        window.location.reload()
    })
}

async function checkNetwork() {
    const net     = await provider.getNetwork()
    const warning = document.getElementById("networkWarning")
    if (net.chainId !== ARBITRUM_SEPOLIA_CHAIN_ID) {
        warning.classList.add("visible")
    } else {
        warning.classList.remove("visible")
    }
}

async function switchNetwork() {
    try {
        await window.ethereum.request({
            method: "wallet_switchEthereumChain",
            params: [{ chainId: "0x66eee" }],
        })
    } catch (err) {
        await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [{
                chainId:            "0x66eee",
                chainName:          "Arbitrum Sepolia",
                nativeCurrency:     { name: "ETH", symbol: "ETH", decimals: 18 },
                rpcUrls:            ["https://sepolia-rollup.arbitrum.io/rpc"],
                blockExplorerUrls:  ["https://sepolia.arbiscan.io"],
            }],
        })
    }
}

// ─── FIX BUG 1: refreshStats reads live chain data ───────────────────────────

async function refreshStats() {
    if (!signer || !userAddress) return

    try {
        const [
            balance,
            votingPower,
            delegateTo,
            vaultShares,
            lpBalance,
            reserves,
            vaultAssets,
            vaultSupply,
        ] = await Promise.all([
            contracts.token.balanceOf(userAddress),
            contracts.token.getVotes(userAddress),
            contracts.token.delegates(userAddress),
            contracts.vault.balanceOf(userAddress),
            contracts.amm.balanceOf(userAddress),
            contracts.amm.getReserves(),
            contracts.vault.totalAssets(),
            contracts.vault.totalSupply(),
        ])

        setText("gameBalance",      fmt(balance)       + " GAME")
        setText("votingPower",      fmt(votingPower)    + " GAME")
        setText("delegate",         shortAddr(delegateTo))
        setText("vaultShares",      fmt(vaultShares)    + " sGAME")
        setText("lpBalance",        fmt(lpBalance)      + " GLP")
        setText("reserveA",         fmt(reserves.rA)    + " GAME")
        setText("reserveB",         fmt(reserves.rB)    + " RES")
        setText("vaultAssets",      fmt(vaultAssets)    + " GAME")
        setText("vaultTotalShares", fmt(vaultSupply)    + " sGAME")

    } catch (err) {
        console.error("refreshStats error:", err)
    }
}

// ─── Swap ───────────────────────────────────────────────────────────

function setSwapDir(aToB) {
    swapAtoB = aToB
    document.getElementById("tabAtoB").classList.toggle("active", aToB)
    document.getElementById("tabBtoA").classList.toggle("active", !aToB)
}

async function doSwap() {
    const amtInput = document.getElementById("swapAmount").value
    const minInput = document.getElementById("swapMinOut").value || "0"

    if (!amtInput || parseFloat(amtInput) <= 0) {
        alert("Please enter an amount to swap")
        return
    }

    const statusEl = document.getElementById("swapStatus")

    try {
        const amtWei = ethers.parseEther(amtInput)
        const minWei = ethers.parseEther(minInput)

        setStatus(statusEl, "pending", "Step 1/2: Approving token...")

        let tokenAddr = ADDRESSES.gameToken
        if (!swapAtoB) tokenAddr = await contracts.amm.TOKEN_B()

        const tokenContract = new ethers.Contract(tokenAddr, ERC20_ABI, signer)
        const allowance = await tokenContract.allowance(userAddress, ADDRESSES.gameAMM)

        if (allowance < amtWei) {
            const approveTx = await tokenContract.approve(ADDRESSES.gameAMM, ethers.MaxUint256)
            setStatus(statusEl, "pending", "Step 1/2: Waiting for approval...")
            await approveTx.wait()
        }

        setStatus(statusEl, "pending", "Step 2/2: Sending swap...")
        const tx = swapAtoB
            ? await contracts.amm.swapAtoB(amtWei, minWei)
            : await contracts.amm.swapBtoA(amtWei, minWei)

        setStatus(statusEl, "pending", "Pending: " + tx.hash.slice(0, 14) + "...")
        await tx.wait()
        setStatus(statusEl, "success", "✅ Swap confirmed! " + shortHash(tx.hash))

        // FIX BUG 1: refetch after tx
        await refreshStats()
        setTimeout(() => loadSubgraphData(), 4000)

    } catch (err) {
        // FIX BUG 1: correct 3-arg call
        setStatus(statusEl, "error", parseError(err))
    }
}

// ─── Vault ──────────────────────────────────────────────────────────

async function doDeposit() {
    const amtInput = document.getElementById("depositAmount").value

    if (!amtInput || parseFloat(amtInput) <= 0) {
        alert("Please enter an amount to deposit")
        return
    }

    const statusEl = document.getElementById("depositStatus")

    try {
        const amtWei    = ethers.parseEther(amtInput)
        setStatus(statusEl, "pending", "Step 1/2: Approving GAME...")
        const allowance = await contracts.token.allowance(userAddress, ADDRESSES.gameVault)

        if (allowance < amtWei) {
            const approveTx = await contracts.token.approve(ADDRESSES.gameVault, ethers.MaxUint256)
            await approveTx.wait()
        }

        setStatus(statusEl, "pending", "Step 2/2: Depositing...")
        const tx = await contracts.vault.deposit(amtWei, userAddress)
        setStatus(statusEl, "pending", "Pending: " + shortHash(tx.hash))
        await tx.wait()
        setStatus(statusEl, "success", "✅ Deposited successfully! " + shortHash(tx.hash))

        // FIX BUG 1: refetch after tx
        await refreshStats()

    } catch (err) {
        setStatus(statusEl, "error", parseError(err))
    }
}

async function doRedeem() {
    const sharesInput = document.getElementById("withdrawShares").value

    if (!sharesInput || parseFloat(sharesInput) <= 0) {
        alert("Please enter the number of shares to redeem")
        return
    }

    const statusEl = document.getElementById("redeemStatus")

    try {
        const sharesWei = ethers.parseEther(sharesInput)
        setStatus(statusEl, "pending", "Redeeming shares...")
        const tx = await contracts.vault.redeem(sharesWei, userAddress, userAddress)
        setStatus(statusEl, "pending", "Pending: " + shortHash(tx.hash))
        await tx.wait()
        setStatus(statusEl, "success", "✅ Redeemed successfully! " + shortHash(tx.hash))

        // FIX BUG 1: refetch after tx
        await refreshStats()

    } catch (err) {
        setStatus(statusEl, "error", parseError(err))
    }
}

// ─── Delegate ─────────────────────────────────────────────────────────

async function doDelegate() {
    const input  = document.getElementById("delegateAddr").value.trim()
    const target = input || userAddress

    const statusEl = document.getElementById("delegateStatus")

    try {
        setStatus(statusEl, "pending", "Delegating votes...")
        const tx = await contracts.token.delegate(target)
        setStatus(statusEl, "pending", "Pending: " + shortHash(tx.hash))
        await tx.wait()
        setStatus(statusEl, "success",
            "✅ Delegated to " + shortAddr(target) + " — " + shortHash(tx.hash))

        // FIX BUG 1: refetch after delegate so Voting Power / Delegated To update
        await refreshStats()

    } catch (err) {
        setStatus(statusEl, "error", parseError(err))
    }
}

// ─── FIX BUG 1: Create Proposal ─────────────────────────────────────────────────

async function doCreateProposal() {
    if (!signer) {
        alert("Connect wallet first")
        return
    }

    const desc = document.getElementById("proposalDesc").value.trim()
    if (!desc) {
        alert("Please enter a description")
        return
    }

    const statusEl = document.getElementById("proposalCreateStatus")

    try {
        // Check voting power threshold
        const power = await contracts.token.getVotes(userAddress)
        const threshold = await contracts.dao.proposalThreshold()
        if (power < threshold) {
            setStatus(statusEl, "error",
                `❌ Need ${fmt(threshold)} GAME voting power. You have ${fmt(power)}.`)
            return
        }

        setStatus(statusEl, "pending", "Submitting proposal...")

        // No-op proposal — targets the DAO itself with empty calldata
        const tx = await contracts.dao.propose(
            [ADDRESSES.gameDAO],  // targets
            [0n],                 // values
            ["0x"],               // calldatas (no-op)
            desc                  // description
        )

        setStatus(statusEl, "pending", "Pending: " + shortHash(tx.hash))
        const receipt = await tx.wait()

        setStatus(statusEl, "success",
            "✅ Proposal submitted! List will refresh in ~5s. " + shortHash(tx.hash))
        document.getElementById("proposalDesc").value = ""

        // Обновить список через 5 сек (дать время subgraph проиндексировать)
        setTimeout(() => loadProposals(), 5000)
        setTimeout(() => loadProposals(), 15000) // второй retry

    } catch (err) {
        setStatus(statusEl, "error", parseError(err))
    }
}

// ─── DAO Voting ─────────────────────────────────────────────────────────

// FIX BUG 1: Check hasVoted before casting vote
async function castVote(proposalId, support) {
    if (!signer) {
        alert("Please connect your wallet first")
        return
    }
    const statusEl = document.getElementById("voteStatus-" + proposalId)
    if (!statusEl) return

    try {
        // Check if already voted
        const alreadyVoted = await contracts.dao.hasVoted(proposalId, userAddress)
        if (alreadyVoted) {
            setStatus(statusEl, "error", "❌ You have already voted on this proposal")
            return
        }

        setStatus(statusEl, "pending", "Submitting vote...")
        const tx = await contracts.dao.castVote(proposalId, support)
        setStatus(statusEl, "pending", "Pending: " + shortHash(tx.hash))
        await tx.wait()
        setStatus(statusEl, "success", "✅ Vote cast! " + shortHash(tx.hash))
        setTimeout(() => loadSubgraphData(), 4000)
    } catch (err) {
        setStatus(statusEl, "error", parseError(err))
    }
}

// ─── Subgraph ─────────────────────────────────────────────────────────

async function loadSubgraphData() {
    await Promise.all([loadProposals(), loadRecentSwaps()])
}

async function queryGraph(query, variables = {}) {
    try {
        const response = await fetch(SUBGRAPH_URL, {
            method:  "POST",
            headers: { "Content-Type": "application/json" },
            body:    JSON.stringify({ query, variables }),
        })
        if (!response.ok) throw new Error("HTTP " + response.status)
        const json = await response.json()
        if (json.errors && json.errors.length > 0) throw new Error(json.errors[0].message)
        return json.data
    } catch (err) {
        console.warn("Subgraph query failed:", err.message)
        return null
    }
}

// FIX BUG 1: Improved loadProposals with fallback and state updates
async function loadProposals() {
    const el = document.getElementById("proposalsList")
    el.className = "empty-state"
    el.textContent = "Loading from The Graph..."

    const data = await queryGraph(`{
    proposals(first: 10, orderBy: createdAt, orderDirection: desc) {
      id proposalId proposer description state
      forVotes againstVotes abstainVotes createdAt
    }
  }`)

    // Fallback: If subgraph unavailable, try chain query
    if (!data || !data.proposals) {
        el.textContent = "⚠️ Subgraph unavailable. Trying direct chain query..."
        await loadProposalsFromChain(el)
        return
    }
    if (data.proposals.length === 0) {
        el.textContent = "No proposals yet. Create one above!"
        return
    }

    // FIX BUG 1: Update state for each proposal from contract
    const stateNames = ["Pending","Active","Canceled","Defeated","Succeeded","Queued","Expired","Executed"]
    if (contracts.dao) {
        await Promise.all(data.proposals.map(async (p) => {
            try {
                const stateNum = await contracts.dao.state(p.proposalId)
                p.state = stateNames[Number(stateNum)] || p.state
            } catch { /* fallback to subgraph state */ }
        }))
    }

    el.className = ""
    el.innerHTML = data.proposals.map(p => {
        const forVotes     = BigInt(p.forVotes)
        const againstVotes = BigInt(p.againstVotes)
        const abstainVotes = BigInt(p.abstainVotes)
        const total        = forVotes + againstVotes + abstainVotes
        const forPct       = total > 0n ? Number(forVotes * 100n / total) : 0
        const date         = new Date(parseInt(p.createdAt) * 1000).toLocaleDateString()
        const desc         = p.description.length > 90
            ? p.description.slice(0, 90) + "..."
            : p.description

        return `
      <div class="proposal">
        <div class="proposal-desc">${escapeHtml(desc)}</div>
        <div class="proposal-meta">
          <span>By ${shortAddr(p.proposer)}</span><span>·</span>
          <span>${date}</span>
          <span class="state-badge state-${p.state}">${p.state}</span>
        </div>
        <div class="vote-bar">
          <div class="vote-bar-fill" style="width: ${forPct}%"></div>
        </div>
        <div class="vote-counts">
          <span>✅ For: ${fmtVotes(p.forVotes)}</span>
          <span>❌ Against: ${fmtVotes(p.againstVotes)}</span>
          <span>⬜ Abstain: ${fmtVotes(p.abstainVotes)}</span>
        </div>
        ${p.state === "Active" ? `
        <div class="vote-buttons">
          <button class="btn-vote btn-for"     onclick="castVote('${p.proposalId}', 1)">Vote For</button>
          <button class="btn-vote btn-against" onclick="castVote('${p.proposalId}', 0)">Vote Against</button>
          <button class="btn-vote btn-abstain" onclick="castVote('${p.proposalId}', 2)">Abstain</button>
        </div>
        <div id="voteStatus-${p.proposalId}" class="tx-status"></div>
        ` : ""}
      </div>`
    }).join("")
}

// FIX BUG 1: Fallback to read proposals from chain if subgraph unavailable
async function loadProposalsFromChain(el) {
    if (!contracts.dao || !provider) {
        el.textContent = "⚠️ Connect wallet to load proposals from chain."
        return
    }
    try {
        const filter = contracts.dao.filters.ProposalCreated()
        const logs   = await contracts.dao.queryFilter(filter, -10000)
        if (logs.length === 0) {
            el.textContent = "No proposals found on chain."
            return
        }
        const stateNames = ["Pending","Active","Canceled","Defeated","Succeeded","Queued","Expired","Executed"]
        const items = await Promise.all(logs.slice(-10).reverse().map(async log => {
            const { proposalId, proposer, description } = log.args
            const stateNum = await contracts.dao.state(proposalId).catch(() => 0)
            const stateName = stateNames[Number(stateNum)] || "Unknown"
            const block = await provider.getBlock(log.blockNumber)
            return { proposalId: proposalId.toString(), proposer, description, state: stateName,
                     forVotes: "0", againstVotes: "0", abstainVotes: "0",
                     createdAt: block?.timestamp?.toString() || "0" }
        }))

        el.className = ""
        el.innerHTML = items.map(p => {
            const date = new Date(parseInt(p.createdAt) * 1000).toLocaleDateString()
            const desc = p.description.length > 90 ? p.description.slice(0,90) + "..." : p.description
            return `
      <div class="proposal">
        <div class="proposal-desc">${escapeHtml(desc)}</div>
        <div class="proposal-meta">
          <span>By ${shortAddr(p.proposer)}</span><span>·</span>
          <span>${date}</span>
          <span class="state-badge state-${p.state}">${p.state}</span>
        </div>
        <div class="vote-counts" style="color:#6b7280;font-size:12px">Vote counts from chain (subgraph offline)</div>
        ${p.state === "Active" ? `
        <div class="vote-buttons">
          <button class="btn-vote btn-for"     onclick="castVote('${p.proposalId}', 1)">Vote For</button>
          <button class="btn-vote btn-against" onclick="castVote('${p.proposalId}', 0)">Vote Against</button>
          <button class="btn-vote btn-abstain" onclick="castVote('${p.proposalId}', 2)">Abstain</button>
        </div>
        <div id="voteStatus-${p.proposalId}" class="tx-status"></div>
        ` : ""}
      </div>`
        }).join("")
    } catch(err) {
        el.textContent = "⚠️ Failed to load proposals: " + err.message?.slice(0,80)
    }
}

async function loadRecentSwaps() {
    const el = document.getElementById("swapHistory")
    el.className = "empty-state"
    el.textContent = "Loading from The Graph..."

    const data = await queryGraph(`{
    swaps(first: 10, orderBy: timestamp, orderDirection: desc) {
      id user amountIn amountOut aToB timestamp transactionHash
    }
  }`)

    if (!data || !data.swaps) {
        el.textContent = "⚠️ Subgraph not deployed yet, or no swaps found."
        return
    }
    if (data.swaps.length === 0) {
        el.textContent = "No swaps yet. Try swapping some tokens above!"
        return
    }

    el.className = ""
    const rows = data.swaps.map(s => {
        const dir  = s.aToB ? "GAME → RES" : "RES → GAME"
        const time = new Date(parseInt(s.timestamp) * 1000).toLocaleTimeString()
        return `
      <div class="swap-row">
        <span class="swap-dir">${dir}</span>
        <span class="swap-amount">${fmt(s.amountIn)} → ${fmt(s.amountOut)}</span>
        <span class="swap-user">${shortAddr(s.user)}</span>
        <span class="swap-time">${time}</span>
      </div>`
    }).join("")

    el.innerHTML = `<div class="swap-history">${rows}</div>`
}

// ─── Utils ──────────────────────────────────────────────────────────

function fmt(wei) {
    const val = parseFloat(ethers.formatEther(wei.toString()))
    return val.toLocaleString(undefined, { maximumFractionDigits: 2 })
}

function fmtVotes(wei) {
    const val = parseFloat(ethers.formatEther(wei.toString()))
    if (val >= 1000) return (val / 1000).toFixed(1) + "k"
    return val.toFixed(0)
}

function shortAddr(addr) {
    if (!addr || addr === "0x0000000000000000000000000000000000000000") return "—"
    return addr.slice(0, 6) + "..." + addr.slice(-4)
}

function shortHash(hash) {
    return hash.slice(0, 10) + "..."
}

function setText(id, text) {
    const el = document.getElementById(id)
    if (el) el.textContent = text
}

// FIX BUG 1: correct signature — always (el, type, message)
function setStatus(el, type, message) {
    el.className  = "tx-status " + type
    el.textContent = message
}

// FIX BUG 2: Improved parseError handling
function parseError(err) {
    if (err.reason)       return err.reason
    if (err.shortMessage) return err.shortMessage
    // Handle "execution reverted (no data)" — likely require(false)
    if (err.message?.includes("no data")) {
        return "Crafting is disabled or recipe not registered. Contact admin."
    }
    if (err.message)      return err.message.slice(0, 100)
    return "Unknown error"
}

function escapeHtml(str) {
    return str
        .replace(/&/g, "&amp;")
        .replace(/</g,  "&lt;")
        .replace(/>/g,  "&gt;")
        .replace(/"/g,  "&quot;")
}

// ─── Boot ───────────────────────────────────────────────────────────

window.addEventListener("load", async () => {
    // Always load public subgraph data immediately
    setTimeout(() => loadSubgraphData(), 500)

    // FIX BUG 2: try to silently restore wallet connection from sessionStorage
    try {
        const state = await WalletState.tryRestore()
        if (state) {
            await _onWalletReady(state)
        }
    } catch (err) {
        console.warn("Silent wallet restore failed:", err)
    }
})
