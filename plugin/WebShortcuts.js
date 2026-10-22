// Exact aliases are scoped to the main launcher, never menu input/file search.
const shortcuts = [
  { key: "x", label: "X", url: "https://x.com/" },
  { key: "y", label: "YouTube", url: "https://www.youtube.com/" },
  { key: "g", label: "GitHub", url: "https://github.com/" }
]

function resolve(query) {
  const key = String(query || "").trim().toLowerCase()
  return shortcuts.find(item => item.key === key || item.label.toLowerCase() === key) || null
}

function row(query) {
  const item = resolve(query)
  if (!item) return null
  return {
    itemId: "web-shortcut." + item.key, kind: "web", icon: "", iconFont: "",
    appIcon: "google-chrome", appId: "", label: item.label,
    target: item.url, detail: item.url.replace(/^https:\/\//, "").replace(/\/$/, "") + " · Chrome",
    path: item.label, childCount: 0, action: "", provider: "", score: -1000000, section: ""
  }
}

function command(id) {
  const item = shortcuts.find(item => "web-shortcut." + item.key === id)
  return item ? ["uwsm-app", "--", "gtk-launch", "google-chrome.desktop", item.url] : null
}

if (typeof module !== "undefined") module.exports = { resolve, row, command }
