/**
 * components/crafting/Toast.js
 * Lightweight toast notification system.
 * No external deps — pure DOM manipulation.
 */

let _container = null

function ensureContainer() {
    if (_container && document.body.contains(_container)) return _container
    _container = document.createElement("div")
    _container.id = "toast-container"
    _container.style.cssText = `
        position: fixed;
        bottom: 24px;
        right: 24px;
        display: flex;
        flex-direction: column;
        gap: 10px;
        z-index: 9999;
        pointer-events: none;
        max-width: 340px;
    `
    document.body.appendChild(_container)
    return _container
}

const TYPE_STYLES = {
    success: {
        bg: "linear-gradient(135deg, #064e3b, #065f46)",
        border: "#34d399",
        icon: "✅",
    },
    error: {
        bg: "linear-gradient(135deg, #450a0a, #7f1d1d)",
        border: "#f87171",
        icon: "❌",
    },
    info: {
        bg: "linear-gradient(135deg, #1e1b4b, #312e81)",
        border: "#818cf8",
        icon: "ℹ️",
    },
    warning: {
        bg: "linear-gradient(135deg, #451a03, #78350f)",
        border: "#fbbf24",
        icon: "⚠️",
    },
}

/**
 * Show a toast notification.
 * @param {string} message
 * @param {'success'|'error'|'info'|'warning'} type
 * @param {number} duration - ms before auto-dismiss (default 4000)
 */
export function showToast(message, type = "info", duration = 4000) {
    const container = ensureContainer()
    const style = TYPE_STYLES[type] || TYPE_STYLES.info

    const toast = document.createElement("div")
    toast.style.cssText = `
        display: flex;
        align-items: center;
        gap: 10px;
        background: ${style.bg};
        border: 1px solid ${style.border};
        border-radius: 10px;
        padding: 12px 16px;
        color: #f0f0ff;
        font-family: 'Segoe UI', system-ui, sans-serif;
        font-size: 0.88rem;
        font-weight: 500;
        box-shadow: 0 4px 24px rgba(0,0,0,0.5), 0 0 12px ${style.border}44;
        pointer-events: all;
        cursor: pointer;
        transform: translateX(120%);
        transition: transform 0.3s cubic-bezier(0.34,1.56,0.64,1), opacity 0.3s ease;
        opacity: 0;
        letter-spacing: 0.01em;
        min-width: 220px;
    `
    toast.innerHTML = `
        <span style="font-size:1.1rem;flex-shrink:0">${style.icon}</span>
        <span style="flex:1;line-height:1.4">${message}</span>
        <span style="opacity:0.5;font-size:1rem;flex-shrink:0">✕</span>
    `

    container.appendChild(toast)

    // Animate in
    requestAnimationFrame(() => {
        requestAnimationFrame(() => {
            toast.style.transform = "translateX(0)"
            toast.style.opacity = "1"
        })
    })

    const dismiss = () => {
        toast.style.transform = "translateX(120%)"
        toast.style.opacity = "0"
        setTimeout(() => {
            if (toast.parentNode) toast.parentNode.removeChild(toast)
        }, 350)
    }

    toast.addEventListener("click", dismiss)
    setTimeout(dismiss, duration)

    return toast
}
