const STORAGE_KEY = "gamefi_wallet"

const WalletState = (() => {
    let _callbacks = []

    function save(data) {
        try {
            sessionStorage.setItem(STORAGE_KEY, JSON.stringify(data))
        } catch (_) {}
    }

    function load() {
        try {
            const raw = sessionStorage.getItem(STORAGE_KEY)
            return raw ? JSON.parse(raw) : null
        } catch (_) {
            return null
        }
    }

    function clear() {
        sessionStorage.removeItem(STORAGE_KEY)
    }

    function onConnect(cb) {
        _callbacks.push(cb)
    }

    function _emit(data) {
        _callbacks.forEach(cb => { try { cb(data) } catch (_) {} })
    }

    /**
     * Attempt to reconnect silently using previously saved address.
     * Returns { provider, signer, address } or null.
     */
    async function tryRestore() {
        const saved = load()
        if (!saved || !saved.address) return null
        if (!window.ethereum) return null

        try {
            const provider = new ethers.BrowserProvider(window.ethereum)
            // eth_accounts does NOT prompt user — silent check
            const accounts = await provider.send("eth_accounts", [])
            if (!accounts || accounts.length === 0) {
                clear()
                return null
            }
            // Make sure saved address is still active
            const active = accounts[0].toLowerCase()
            if (active !== saved.address.toLowerCase()) {
                clear()
                return null
            }
            const signer = await provider.getSigner()
            const address = await signer.getAddress()
            const state = { provider, signer, address }
            _emit(state)
            return state
        } catch (_) {
            clear()
            return null
        }
    }

    /**
     * Full connect (prompts user). Saves state on success.
     */
    async function connect() {
        if (!window.ethereum) {
            alert("MetaMask not found! Please install it from https://metamask.io")
            return null
        }
        const provider = new ethers.BrowserProvider(window.ethereum)
        await provider.send("eth_requestAccounts", [])
        const signer = await provider.getSigner()
        const address = await signer.getAddress()
        save({ address })
        const state = { provider, signer, address }
        _emit(state)
        return state
    }

    return { save, load, clear, connect, tryRestore, onConnect }
})()

window.WalletState = WalletState
