const ADDRESSES = {
    gameToken:  "0x407a5Da64E3fc9FF202b76355d0FC0F34390c41A",
    gameAMM:    "0xFf494842f23dbad3b478CDe35486e101cD880AF9",
    gameVault:  "0xCB082d44E32f27D30C54c28F947A8C54fDFb6de8",
    gameDAO:    "0xCb0aD118Fc15313305d138097A2E6AE21706A59C",
}

// do not forget
const SUBGRAPH_URL = "https://api.studio.thegraph.com/query/1753408/gamefi-protocol/v0.0.5"

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
const DAO_ABI = [
    "function castVote(uint256 proposalId, uint8 support) returns (uint256)",
    "function hasVoted(uint256 proposalId, address account) view returns (bool)",
]


let provider = null
let signer   = null
let userAddress = null
let swapAtoB = true

const contracts = {}


async function connectWallet() {
    if (!window.ethereum) {
        alert("MetaMask not found! Please install it from https://metamask.io")
        return
    }

    try {
        provider = new ethers.BrowserProvider(window.ethereum)
        await provider.send("eth_requestAccounts", [])
        signer = await provider.getSigner()
        userAddress = await signer.getAddress()
        window._userAddress = userAddress

        // Update UI
        document.getElementById("connectBtn").style.display = "none"
        const wi = document.getElementById("walletInfo")
        wi.textContent = userAddress.slice(0, 6) + "..." + userAddress.slice(-4)
        wi.classList.add("visible")

        // Check network
        await checkNetwork()

        // Init contracts
        contracts.token = new ethers.Contract(ADDRESSES.gameToken, VOTES_ABI, signer)
        contracts.amm   = new ethers.Contract(ADDRESSES.gameAMM,   AMM_ABI,   signer)
        contracts.vault = new ethers.Contract(ADDRESSES.gameVault, VAULT_ABI, signer)
        contracts.dao   = new ethers.Contract(ADDRESSES.gameDAO,   DAO_ABI,   signer)

        // Load data
        await refreshStats()
        await loadSubgraphData()

        // Listen for changes
        window.ethereum.on("chainChanged",    () => window.location.reload())
        window.ethereum.on("accountsChanged", () => window.location.reload())

    } catch (err) {
        console.error("Wallet connection failed:", err)
        alert("Connection failed: " + err.message)
    }
}

async function checkNetwork() {
    const net = await provider.getNetwork()
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
        // Network not added yet — add it
        await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [{
                chainId: "0x66eee",
                chainName: "Arbitrum Sepolia",
                nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
                rpcUrls: ["https://sepolia-rollup.arbitrum.io/rpc"],
                blockExplorerUrls: ["https://sepolia.arbiscan.io"],
            }],
        })
    }
}

async function refreshStats() {
    if (!signer) return

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

        setText("gameBalance",     fmt(balance)      + " GAME")
        setText("votingPower",     fmt(votingPower)   + " GAME")
        setText("delegate",        shortAddr(delegateTo))
        setText("vaultShares",     fmt(vaultShares)   + " sGAME")
        setText("lpBalance",       fmt(lpBalance)     + " GLP")
        setText("reserveA",        fmt(reserves.rA)   + " GAME")
        setText("reserveB",        fmt(reserves.rB)   + " RES")
        setText("vaultAssets",     fmt(vaultAssets)   + " GAME")
        setText("vaultTotalShares",fmt(vaultSupply)   + " sGAME")

    } catch (err) {
        console.error("refreshStats error:", err)
    }
}

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

        // Approve the token being sold
        setStatus(statusEl, "pending", "Step 1/2: Approving token...")

        let tokenAddr = ADDRESSES.gameToken
        if (!swapAtoB) {
            tokenAddr = await contracts.amm.TOKEN_B()
        }

        const tokenContract = new ethers.Contract(tokenAddr, ERC20_ABI, signer)
        const allowance = await tokenContract.allowance(userAddress, ADDRESSES.gameAMM)

        if (allowance < amtWei) {
            const approveTx = await tokenContract.approve(ADDRESSES.gameAMM, ethers.MaxUint256)
            setStatus(statusEl, "pending", "Step 1/2: Waiting for approval...")
            await approveTx.wait()
        }

        // Swap
        setStatus(statusEl, "pending", "Step 2/2: Sending swap...")
        const tx = swapAtoB
            ? await contracts.amm.swapAtoB(amtWei, minWei)
            : await contracts.amm.swapBtoA(amtWei, minWei)

        setStatus(statusEl, "pending", "Pending: " + tx.hash.slice(0, 14) + "...")
        await tx.wait()
        setStatus(statusEl, "success", " Swap confirmed! " + shortHash(tx.hash))

        await refreshStats()
        // Reload subgraph after a few seconds (indexing delay)
        setTimeout(() => loadSubgraphData(), 4000)

    } catch (err) {
        setStatus(statusEl, "error: "  + parseError(err))
    }
}

async function doDeposit() {
    const amtInput = document.getElementById("depositAmount").value

    if (!amtInput || parseFloat(amtInput) <= 0) {
        alert("Please enter an amount to deposit")
        return
    }

    const statusEl = document.getElementById("depositStatus")

    try {
        const amtWei = ethers.parseEther(amtInput)

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
        setStatus(statusEl, "success", " Deposited successfully! " + shortHash(tx.hash))

        await refreshStats()

    } catch (err) {
        setStatus(statusEl, "error: "  + parseError(err))
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
        setStatus(statusEl, "success", " Redeemed successfully! " + shortHash(tx.hash))

        await refreshStats()

    } catch (err) {
        setStatus(statusEl, "error: "  + parseError(err))
    }
}


async function doDelegate() {
    const input = document.getElementById("delegateAddr").value.trim()
    const target = input || userAddress  // empty = delegate to self

    const statusEl = document.getElementById("delegateStatus")

    try {
        setStatus(statusEl, "pending", "Delegating votes...")
        const tx = await contracts.token.delegate(target)
        setStatus(statusEl, "pending", "Pending: " + shortHash(tx.hash))
        await tx.wait()
        setStatus(statusEl, "success",
            " Delegated to " + shortAddr(target) + " — " + shortHash(tx.hash))

        await refreshStats()

    } catch (err) {
        setStatus(statusEl, "error: "  + parseError(err))
    }
}

async function loadSubgraphData() {
    await Promise.all([
        loadProposals(),
        loadRecentSwaps(),
    ])
}

async function queryGraph(query, variables = {}) {
    try {
        const response = await fetch(SUBGRAPH_URL, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ query, variables }),
        })

        if (!response.ok) {
            throw new Error("HTTP " + response.status)
        }

        const json = await response.json()

        if (json.errors && json.errors.length > 0) {
            throw new Error(json.errors[0].message)
        }

        return json.data

    } catch (err) {
        console.warn("Subgraph query failed:", err.message)
        return null
    }
}

async function loadProposals() {
    const el = document.getElementById("proposalsList")
    el.className = "empty-state"
    el.textContent = "Loading from The Graph..."

    const data = await queryGraph(`{
    proposals(first: 10, orderBy: createdAt, orderDirection: desc) {
      id
      proposalId
      proposer
      description
      state
      forVotes
      againstVotes
      abstainVotes
      createdAt
    }
  }`)

    if (!data || !data.proposals) {
        el.textContent = " Subgraph not deployed yet, or no proposals found."
        return
    }

    if (data.proposals.length === 0) {
        el.textContent = "No proposals yet. Create one via the DAO contract."
        return
    }

    el.className = ""

    el.innerHTML = data.proposals.map(p => {
        const forVotes     = BigInt(p.forVotes)
        const againstVotes = BigInt(p.againstVotes)
        const abstainVotes = BigInt(p.abstainVotes)
        const total = forVotes + againstVotes + abstainVotes
        const forPct = total > 0n ? Number(forVotes * 100n / total) : 0
        const date = new Date(parseInt(p.createdAt) * 1000).toLocaleDateString()
        const desc = p.description.length > 90
            ? p.description.slice(0, 90) + "..."
            : p.description

        return `
      <div class="proposal">
        <div class="proposal-desc">${escapeHtml(desc)}</div>
        <div class="proposal-meta">
          <span>By ${shortAddr(p.proposer)}</span>
          <span>·</span>
          <span>${date}</span>
          <span class="state-badge state-${p.state}">${p.state}</span>
        </div>
        <div class="vote-bar">
          <div class="vote-bar-fill" style="width: ${forPct}%"></div>
        </div>
        <div class="vote-counts">
          <span> For: ${fmtVotes(p.forVotes)}</span>
          <span> Against: ${fmtVotes(p.againstVotes)}</span>
          <span> Abstain: ${fmtVotes(p.abstainVotes)}</span>
        </div>
        ${p.state === 'Active' ? `
        <div class="vote-buttons">
          <button class="btn-vote btn-for"     onclick="castVote('${p.proposalId}', 1)">Vote For</button>
          <button class="btn-vote btn-against" onclick="castVote('${p.proposalId}', 0)">Vote Against</button>
          <button class="btn-vote btn-abstain" onclick="castVote('${p.proposalId}', 2)">Abstain</button>
        </div>
        <div id="voteStatus-${p.proposalId}" class="tx-status"></div>
        ` : ''}
      </div>
    `
    }).join("")
}

async function loadRecentSwaps() {
    const el = document.getElementById("swapHistory")
    el.className = "empty-state"
    el.textContent = "Loading from The Graph..."

    const data = await queryGraph(`{
    swaps(first: 10, orderBy: timestamp, orderDirection: desc) {
      id
      user
      amountIn
      amountOut
      aToB
      timestamp
      transactionHash
    }
  }`)

    if (!data || !data.swaps) {
        el.textContent = " Subgraph not deployed yet, or no swaps found."
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
      </div>
    `
    }).join("")

    el.innerHTML = `<div class="swap-history">${rows}</div>`
}



/**
 * Format a BigInt wei value to a human-readable number string.
 * Accepts both BigInt and string (from subgraph).
 */
function fmt(wei) {
    const val = parseFloat(ethers.formatEther(wei.toString()))
    return val.toLocaleString(undefined, { maximumFractionDigits: 2 })
}

/**
 * Format vote counts (subgraph returns strings)
 */
function fmtVotes(wei) {
    const val = parseFloat(ethers.formatEther(wei.toString()))
    if (val >= 1000) return (val / 1000).toFixed(1) + "k"
    return val.toFixed(0)
}

/**
 * Shorten a wallet address: 0x1234...abcd
 */
function shortAddr(addr) {
    if (!addr || addr === "0x0000000000000000000000000000000000000000") return "—"
    return addr.slice(0, 6) + "..." + addr.slice(-4)
}

/**
 * Shorten a tx hash: 0x1234abcd...
 */
function shortHash(hash) {
    return hash.slice(0, 10) + "..."
}

/**
 * Set text content of an element by ID
 */
function setText(id, text) {
    const el = document.getElementById(id)
    if (el) el.textContent = text
}

/**
 * Set transaction status message with appropriate styling
 */
function setStatus(el, type, message) {
    el.className = "tx-status " + type
    el.textContent = message
}

/**
 * Extract a readable error message from ethers errors
 */
function parseError(err) {
    if (err.reason)       return err.reason
    if (err.shortMessage) return err.shortMessage
    if (err.message)      return err.message.slice(0, 100)
    return "Unknown error"
}

/**
 * Escape HTML to prevent XSS from subgraph data
 */
function escapeHtml(str) {
    return str
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
}


// Load subgraph data on page load (no wallet needed for read-only data)
window.addEventListener("load", () => {
    setTimeout(() => loadSubgraphData(), 500)
})