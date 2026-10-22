import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Quickshell.Hyprland
import "Motion.js" as Motion
import "ClipboardHistory.js" as ClipboardHistory
import "WebShortcuts.js" as WebShortcuts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "MenuModel.js" as MenuModel

Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // Plugin lifecycle hooks. The host calls open(payloadJson) after
  // `omarchy-shell shell summon omarchy.menu ...` and close() when hidden.
  property string pendingInitialMenu: "root"

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    if (payload.fontFamily) root.fontFamily = payload.fontFamily

    if (payload.mode === "select" || payload.mode === "input") {
      root.openDmenu(payload)
    } else {
      root.openRoute(payload.initialMenu || payload.menu || "root")
    }
  }

  function close() {
    root.cancel()
  }

  function refresh() {
    defaultMenuFile.reload()
    userMenuFile.reload()
    return "ok"
  }

  function ping() { return "ok" }

  property string fontFamily: "Inter"
  readonly property bool hasVariableFont: Qt.fontFamilies().indexOf("Inter Variable")>=0
  // JSONC menu definitions. The shell parses both at startup and merges
  // the user file on top of the defaults, so the keybind → IPC → visible
  // path doesn't have to shell out to bash + jq on every open.
  property string defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  property var defaultMenuItems: []
  property var userMenuItems: []
  property bool opened: false
  property string mode: "menu"
  readonly property bool dmenuActive: mode === "select" || mode === "input"
  property string dmenuPrompt: ""
  property var dmenuOptions: []
  property string selectionFile: ""
  property string doneFile: ""
  property int dmenuWidth: 300
  property int dmenuMaxHeight: 0
  property bool requestActive: false
  property bool rowsLoaded: false
  property string activeMenu: "root"
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property int requestSerial: 0
  property int applySerial: 0
  property var items: ({})
  property var itemOrder: []
  property var navStack: []
  property var providersLoaded: ({})
  property var providerQueue: []
  property int providerRevision: 0

  // Shared application engine (entries, hidden filters, icons, launch,
  // removal), owned by the shell and also used by the standalone launcher.
  readonly property var appLibrary: root.shell && root.shell.appLibrary ? root.shell.appLibrary : localLibrary
  DesktopLibrary { id: localLibrary }
  property bool deleteConfirmOpen: false
  property var deleteTarget: null
  property bool openingPending: false
  function beginOpening() {
    if(!opened)return
    openingPending=false
    beginScale(true,presentation>.001)
    openPresentation.from=presentation;openPresentation.start()
    openOpacity.from=opacityProgress;openOpacity.start()
    idleCategories.restart()
  }
  onOpenedChanged: {
    if (opened) {
      screenName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
      resizeReady = false
      resizeAnimation.stop();resizeFrom=desiredHeight;resizeTo=desiredHeight;resizeInitialVelocity=0;resizeClock=.6
      Qt.callLater(function(){root.resizeReady=true})
      closePresentation.stop();closeOpacity.stop()
      // Do not spend the first animation ticks while Wayland is mapping the
      // surface. Begin after its transparent first frame has been submitted.
      if(presentation<=.001)openingPending=true
      else beginOpening()
    } else {
      openingPending=false
      beginScale(false,presentation>.001)
      if(mode === "menu" && category === "all") {lastQuery=filterText;lastResults=forceResults;lastCompletionSuppressed=completionSuppressed}
      openPresentation.stop();closePresentation.from=presentation;closePresentation.start()
      openOpacity.stop();closeOpacity.from=opacityProgress;closeOpacity.start()
      idleCategories.stop()
      deleteConfirmOpen = false; deleteTarget = null
    }
  }
  // Bound to the central [menu] section in shell.toml via Commons.Color.qml.
  // Each color already includes its alpha companion (composed in the
  // singleton), so consumers can drop them straight into a Rectangle.
  property color background: "#ed18181b"
  property color foreground: "#f5f5f7"
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: "#30ffffff"
  property color selectedText: "#ffffff"
  property color selectedBorder: Commons.Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  readonly property real rowReservedBorderLeft: Border.left(selectedBorderSpec)
  readonly property real rowReservedBorderRight: Border.right(selectedBorderSpec)
  readonly property int cornerRadius: 18
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int baseRowHeight: Math.max(Style.space(50), Style.font.body + Style.spacing.rowPaddingX * 2)
  property int detailRowHeight: Math.max(Style.space(58), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  // How much of the first hidden row stays visible at the fold — enough to
  // read as a cut-off row rather than a bottom border.
  property int rowPeek: Math.round(baseRowHeight * 0.55)
  property int rowSpacing: Style.spacing.xs
  property int dividerHeight: Style.space(17)
  property bool searchDivider: false
  property int layoutSerial: 0
  property int cardWidth: Math.min(root.dmenuActive ? Style.space(root.dmenuWidth) : ((root.activeMenu === "trigger.capture.screenrecord" || root.activeMenu === "style.font") ? Style.space(520) : Style.space(300)), panel.width - Style.gapsOut * 2)
  property int visibleRowsHeight: root.dmenuActive ? dmenuRowListHeight(layoutSerial, displayModel.count, filterText) : rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)
  property int cardHeight: root.dmenuActive
    ? Math.min(contentMargin * 2 + headerHeight + (mode === "input" ? 0 : contentSpacing + visibleRowsHeight), panel.height - Style.gapsOut * 2)
    : Math.min(contentMargin * 2 + headerHeight + contentSpacing + visibleRowsHeight, panel.height - Style.gapsOut * 2)

  function finishRequest(selection) {
    if (!root.requestActive || !root.doneFile) {
      root.opened = false
      return
    }

    var activeSelectionFile = root.selectionFile
    var activeDoneFile = root.doneFile
    root.requestActive = false
    root.selectionFile = ""
    root.doneFile = ""

    if (selection === null || selection === undefined) {
      resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(activeDoneFile)]
    } else {
      resultProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(selection) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)]
    }
    resultProc.running = true
  }

  function runAction(action) {
    var command = String(action || "")
    if (!command) return

    Util.execDetached(command)
  }

  // Menu rows only surface their detail while a search is narrowing them;
  // dmenu rows carry caller-supplied subtext that must always be visible.
  function rowHeightForDetail(detail) {
    return (root.filterText || root.dmenuActive) && detail ? root.detailRowHeight : root.baseRowHeight
  }

  // Height the card can devote to rows before running off the screen — or
  // past the frozen top edge once a search has pinned the card in place.
  // Uses panel.cardTop rather than effectiveCardTop: the centered top is
  // derived from the card height, which this value feeds.
  function availableRowsHeight() {
    var top = panel.cardTop >= 0 ? panel.cardTop : Style.gapsOut
    var available = panel.height - top - Style.gapsOut - root.contentMargin * 2 - root.headerHeight - root.contentSpacing
    // The starting menu sets the ceiling along with the offset: drilling into
    // a longer submenu scrolls behind the fold instead of growing the card.
    if (panel.maxRowsHeight >= 0) available = Math.min(available, panel.maxRowsHeight)
    // A card that swallows the whole screen reads as a page, not a menu.
    return Math.min(available, Math.round(panel.height * 0.7))
  }

  // When every row fits, the list gets its full height. When they don't,
  // the card must end mid-row: a clipped row is what tells the eye there is
  // more below the fold, so never come out even on a row boundary.
  function foldedListHeight(totals, available) {
    var count = totals.length
    if (count === 0) return root.baseRowHeight
    if (totals[count - 1] <= available) return totals[count - 1]

    var peek = root.rowPeek
    var full = 0
    while (full < count && totals[full] <= available) full++
    while (full > 1 && totals[full - 1] + root.rowSpacing + peek > available) full--
    if (full < 1) return Math.max(available, root.baseRowHeight)

    return totals[full - 1] + root.rowSpacing + peek
  }

  function rowListHeight(_serial, _count, _filter, _divider) {
    if (displayModel.count === 0) return root.baseRowHeight

    var totals = []
    var total = 0
    var previousSection = ""

    for (var i = 0; i < displayModel.count; i++) {
      var row = displayModel.get(i)
      if (i > 0) total += root.rowSpacing
      if (row.section === "drilldown" && previousSection !== "drilldown") total += root.dividerHeight
      total += root.rowHeightForDetail(row.detail)
      previousSection = row.section
      totals.push(total)
    }

    return foldedListHeight(totals, availableRowsHeight())
  }

  function dmenuRowListHeight(_serial, _count, _filter) {
    if (root.mode === "input") return 0
    if (displayModel.count === 0) return root.baseRowHeight

    var available = availableRowsHeight()
    if (root.dmenuMaxHeight > 0) available = Math.min(available, Style.space(root.dmenuMaxHeight))

    var totals = []
    var total = 0
    for (var i = 0; i < displayModel.count; i++) {
      if (i > 0) total += root.rowSpacing
      total += root.rowHeightForDetail(displayModel.get(i).detail)
      totals.push(total)
    }

    return foldedListHeight(totals, available)
  }

  function item(id) {
    return root.items[id] || null
  }

  // ------------------------------------------------------------------
  // JSONC → normalized item array. Mirrors the bash bin's jq pipeline so
  // the on-disk authoring format stays untouched.
  // ------------------------------------------------------------------

  function stripJsonc(raw) {
    return MenuModel.stripJsonc(raw)
  }

  function normalizeAliases(value) {
    return MenuModel.normalizeAliases(value)
  }

  function normalizeItem(id, raw) {
    return MenuModel.normalizeItem(id, raw)
  }

  function parseMenuJsonc(raw) {
    return MenuModel.parseMenuJsonc(raw)
  }

  // Merge defaults + user extension. Later entries override earlier ones
  // on a per-key basis (so the user can tweak label/icon/action without
  // re-declaring the whole row).
  function rebuildItemsFromSources() {
    var mergedMenu = MenuModel.mergeMenuSources(root.defaultMenuItems, root.userMenuItems)
    root.providerRevision += 1
    root.providersLoaded = ({})
    root.providerQueue = []
    root.items = mergedMenu.items
    root.itemOrder = mergedMenu.itemOrder
    root.rowsLoaded = true
    root.evaluateGuards()
    if (root.opened) {
      root.rebuildDisplay()
      if (!root.dmenuActive) {
        if (root.filterText.trim()) root.loadProvidersForSearch()
        else root.loadProviderForMenu(root.activeMenu)
      }
    }
  }

  // Each known provider is a tiny bash one-liner that enumerates a list and
  // emits one tab-delimited row per item: `label\tvalue\tcurrent`. The shell
  // turns those into menu items children of `menuId`. A `volatile` provider
  // re-runs every time its submenu is entered, so a font installed since the
  // shell started shows up without restarting it.
  readonly property var providers: ({
    "fonts": {
      script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
      icon: "",
      volatile: true,
      actionFor: function(value) { return "omarchy-font-set " + Util.shellQuote(value) }
    },
    "power-profiles": {
      script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
      icon: "\udb81\udc0b",
      actionFor: function(value) { return "omarchy-powerprofiles-set autodetect " + Util.shellQuote(value) }
    }
  })

  function slugify(value) {
    return MenuModel.slugify(value)
  }

  // The apps provider is QML-native: rows come from the shared AppLibrary
  // (DesktopEntries) instead of a bash enumeration, so they carry image
  // icons, launch feedback, and uninstall support like the launcher.
  function mergeAppRows() {
    if (!root.appLibrary) return

    var rows = root.appLibrary.sortedEntries("")
    var appRows = []
    for (var j = 0; j < rows.length; j++) {
      var entry = rows[j].entry
      var appId = String(entry.id || "")
      if (!appId) continue
      var subtext = root.appLibrary.entrySubtext(entry)
      var aliases = subtext ? [subtext] : []
      try {
        if (entry.keywords && typeof entry.keywords.join === "function") aliases = aliases.concat(entry.keywords)
      } catch (e) { }
      appRows.push({
        id: "apps." + appId,
        parent: "apps",
        kind: "app",
        icon: "",
        appIcon: String(entry.icon || ""),
        appId: appId,
        label: root.appLibrary.entryName(entry),
        title: "",
        target: "",
        description: subtext,
        action: "",
        provider: "",
        aliases: aliases,
        when: "",
        checked: "",
        order: 0
      })
    }

    var merged = MenuModel.mergeAppRows(root.items, root.itemOrder, appRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return
    if (entry.provider === "apps") {
      root.providersLoaded[id] = true
      root.mergeAppRows()
      return
    }
    var spec = root.providers[entry.provider]
    if (!spec) return

    root.providersLoaded[id] = true
    providerProc.menuId = id
    providerProc.providerKey = entry.provider
    providerProc.revision = root.providerRevision
    providerProc.collected = ""
    providerProc.command = ["bash", "-lc", spec.script]
    providerProc.running = true
  }

  function mergeProviderRows(rows, menuId, providerKey) {
    var spec = root.providers[providerKey]
    if (!spec) return
    var lines = String(rows || "").split("\n")
    var providerRows = []
    var takenIds = ({})
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var parts = line.split("\t")
      var label = parts[0] || ""
      var value = parts[1] || parts[0] || ""
      var current = parts[2] || ""
      if (!label) continue
      // Distinct values can slugify alike — Fira Code and Fira-Code both give
      // fira-code — and a repeated id is dropped, which would silently lose a
      // row from the list. Nudge it until it is the row's own.
      var rowId = menuId + "." + root.slugify(value)
      while (takenIds[rowId]) rowId += "-"
      takenIds[rowId] = true

      providerRows.push({
        id: rowId,
        parent: menuId,
        kind: "action",
        icon: (value === current) ? "✓" : (spec.icon || ""),
        label: label,
        title: "",
        target: "",
        description: "",
        action: spec.actionFor(value),
        provider: "",
        aliases: [],
        when: "",
        checked: "",
        order: 0
      })
    }
    var merged = MenuModel.swapProviderRows(root.items, root.itemOrder, menuId, providerRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startNextProvider() {
    if (providerProc.running) return

    while (root.providerQueue.length > 0) {
      var id = root.providerQueue.shift()
      var entry = root.item(id)
      if (!entry || !entry.provider || root.providersLoaded[id]) continue

      root.startProviderForMenu(id)
      return
    }
  }

  // Entering a submenu is the one moment a volatile list is worth paying for
  // again: it may have been reshaped by the last pick from it. Search doesn't
  // invalidate, or every keystroke would restart the same enumeration.
  function invalidateVolatileProvider(id) {
    var entry = root.item(id)
    var spec = entry && entry.provider ? root.providers[entry.provider] : null
    if (spec && spec.volatile) root.providersLoaded[id] = false
  }

  function loadProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return

    // Native providers don't touch providerProc, so they never need to queue.
    if (entry.provider === "apps") {
      root.startProviderForMenu(id)
      return
    }

    if (providerProc.running) {
      if (root.providerQueue.indexOf(id) < 0) root.providerQueue = root.providerQueue.concat([id])
      return
    }

    root.startProviderForMenu(id)
  }

  function loadProvidersForSearch() {
    var active = root.item(root.activeMenu) ? root.activeMenu : "root"

    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue
      if (active !== "root" && entry.id !== active && !root.isDescendantOf(entry.id, active)) continue

      root.loadProviderForMenu(entry.id)
    }
  }

  function depthFor(id) {
    return MenuModel.depthFor(root.items, id)
  }

  function pathFor(id) {
    return MenuModel.pathFor(root.items, id)
  }

  function parentPathFor(id) {
    return MenuModel.parentPathFor(root.items, id)
  }

  function isDescendantOf(id, ancestorId) {
    return MenuModel.isDescendantOf(root.items, id, ancestorId)
  }

  function childCount(id) {
    return MenuModel.childCount(root.items, root.itemOrder, id)
  }

  // Guarded items are hidden when their `when:` evaluates false. Static
  // submenus are also hidden when none of their descendants are visible;
  // provider-backed menus stay visible because their rows load on demand.
  function isVisible(entry) {
    return MenuModel.isVisible(root.items, root.itemOrder, root.whenResults, entry)
  }

  // Label with the ✓ marker baked in when `checked:` evaluated truthy.
  function labelFor(entry) {
    return MenuModel.labelFor(entry, root.checkedResults)
  }

  function searchableToken(value) {
    return MenuModel.searchableToken(value)
  }

  function leafIdFor(id) {
    return MenuModel.leafIdFor(id)
  }

  function nameSearchText(entry) {
    return MenuModel.nameSearchText(entry)
  }

  function termInSearchWords(term, text) {
    return MenuModel.termInSearchWords(term, text)
  }

  function descriptionTextMatches(query, text) {
    return MenuModel.descriptionTextMatches(query, text)
  }

  function matchesQuery(entry, query) {
    return MenuModel.matchesQuery(entry, query, root.isVisible(entry))
  }

  function searchScore(entry, query) {
    return MenuModel.searchScore(root.items, entry, query)
  }

  function displayRow(entry, detail, score, section) {
    return MenuModel.displayRow(root.items, root.itemOrder, root.checkedResults, entry, detail, score, section)
  }

  function rebuildDmenuDisplay() {
    displayModel.clear()
    root.searchDivider = false

    if (root.mode === "input") {
      layoutSerial += 1
      return
    }

    var query = root.filterText.trim().toLowerCase()
    for (var i = 0; i < root.dmenuOptions.length; i++) {
      // An option is "<label>", "<glyph>\t<label>", or
      // "<glyph>\t<label>\t<subtext>". The glyph never comes back with the
      // selection; the subtext renders under the label, filters alongside it,
      // and returns with the selection as a stable key for same-named rows.
      var parts = String(root.dmenuOptions[i] || "").split("\t")
      var icon = parts.length > 1 ? parts.shift() : ""
      var label = parts.shift() || ""
      var detail = parts.join("\t")
      if (query && label.toLowerCase().indexOf(query) < 0
          && detail.toLowerCase().indexOf(query) < 0) continue
      displayModel.append({
        itemId: "dmenu." + i,
        kind: "dmenu",
        icon: icon,
        iconFont: "",
        appIcon: "",
        appId: "",
        label: label,
        target: "",
        detail: detail,
        path: "",
        childCount: 0,
        action: "",
        provider: "",
        score: i,
        section: ""
      })
    }

    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  property string displaySignature: ""
  Timer {id:clearResultsDelay;interval:120;onTriggered:root.rebuildDisplay(true)}
  function rebuildDisplay(afterFade) {
    // Keep the outgoing rows through their fade. Replacing them with the root
    // menu immediately makes an unrelated Apps row flash during collapse.
    if(!afterFade && opened && !resultsShown && presentHeight>56.5 && !webShortcut) {
      if(!clearResultsDelay.running)clearResultsDelay.start()
      return
    }
    clearResultsDelay.stop()
    if (!root.dmenuActive && (category === "files" || category === "clipboard")) {
      displaySignature="";rebuildExtras(); return
    }
    if (root.dmenuActive) {
      displaySignature="";root.rebuildDmenuDisplay()
      return
    }

    if (!root.rowsLoaded) {displaySignature="";displayModel.clear();return}

    var active = root.item(root.activeMenu) ? root.activeMenu : "root"
    root.activeMenu = active
    var rows = []
    var query = root.filterText.trim()
    root.searchDivider = false

    if (query) {
      var currentRows = []
      var drilldownRows = []

      for (var i = 0; i < root.itemOrder.length; i++) {
        var entry = root.item(root.itemOrder[i])
        if (!entry || entry.id === "root") continue
        if (!root.isDescendantOf(entry.id, active)) continue
        if (!root.matchesQuery(entry, query)) continue

        var detail = root.parentPathFor(entry.id)
        var row = root.displayRow(entry, detail, root.searchScore(entry, query))
        if (entry.parent === active) currentRows.push(row)
        else drilldownRows.push(row)
      }

      var searchSort = function(a, b) {
        if (a.score !== b.score) return a.score - b.score
        return a.path.localeCompare(b.path)
      }

      currentRows.sort(searchSort)
      drilldownRows.sort(searchSort)
      root.searchDivider = currentRows.length > 0 && drilldownRows.length > 0
      if (root.searchDivider) {
        for (var d = 0; d < drilldownRows.length; d++) drilldownRows[d].section = "drilldown"
      }
      rows = currentRows.concat(drilldownRows)
      if (category === "all") rows.sort(function(a,b) {
        const appA=a.kind === "app" ? -1000 : 0, appB=b.kind === "app" ? -1000 : 0
        return appA-appB || a.score-b.score || a.label.localeCompare(b.label)
      })
    } else {
      for (var j = 0; j < root.itemOrder.length; j++) {
        var child = root.item(root.itemOrder[j])
        if (!child || child.parent !== active) continue
        if (!root.isVisible(child)) continue
        rows.push(root.displayRow(child, child.description, child.order))
      }

      // DesktopEntries can reorder its values when an application starts.
      // Keep the Apps menu alphabetical independently of provider refreshes.
      if (active === "apps") {
        rows.sort(function(a, b) {
          var aLabel = String(a.label || "").toLowerCase()
          var bLabel = String(b.label || "").toLowerCase()
          if (aLabel < bLabel) return -1
          if (aLabel > bLabel) return 1
          var aId = String(a.itemId || "")
          var bId = String(b.itemId || "")
          if (aId < bId) return -1
          if (aId > bId) return 1
          return 0
        })
      }
    }

    // Reserve exact website aliases ahead of application matches.
    if (webShortcut) rows.unshift(WebShortcuts.row(query))

    const signature=JSON.stringify(rows)
    if(signature!==displaySignature) {
      displayModel.clear()
      for (var k = 0; k < rows.length; k++) displayModel.append(rows[k])
      displaySignature=signature;layoutSerial += 1
    }

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  // Contain alone parks the cursor row flush with the viewport edge, hiding
  // the neighbor entirely and losing the fold affordance. Keep the next
  // hidden row peeking past the cursor in the direction of travel.
  function revealCursor() {
    if (!displayModel.count) return
    if (root.selectedIndex === 0) resultList.positionViewAtBeginning()
    else resultList.positionViewAtIndex(root.selectedIndex,ListView.Contain)
  }

  function select(delta) {
    if (displayModel.count === 0) return

    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    revealCursor()
  }

  function setFilter(nextFilter) {
    panel.freezeCardTop()
    const hadQuery=!!root.filterText
    const fresh=!hadQuery && !!nextFilter
    if(fresh) { forceResults=false;completionSuppressed=false;quickReady=false;exactDelay.restart() }
    if(!nextFilter) { forceResults=false;completionSuppressed=false;quickReady=false;exactDelay.stop() }
    hoveredCategory=-1
    if(nextFilter) { categoriesReady=false;idleCategories.restart() }
    else if(hadQuery) { categoriesReady=true;idleCategories.stop() }
    else if(!categoriesReady)idleCategories.restart()
    root.filterText = nextFilter
    if(category === "files") fileSearchDelay.restart()
    root.selectedIndex = 0
    root.cursorActive = root.mode !== "input"
    root.disarmPointer()
    if (!root.dmenuActive && root.filterText.trim()) root.loadProvidersForSearch()
    root.rebuildDisplay()
  }

  function setActiveMenu(id, pushHistory, fromPointer) {
    panel.freezeCardTop()
    if (!root.item(id)) id = "root"
    forceResults = true
    if (id === "apps") category = "apps"
    else category = "actions"
    if (pushHistory && id !== root.activeMenu) root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = id
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    if (fromPointer) pointerGate.allowInitialSample()
    else root.disarmPointer()
    root.rebuildDisplay()
    root.invalidateVolatileProvider(id)
    root.loadProviderForMenu(id)
  }

  function goBack() {
    if (root.activeMenu === "root") {
      if(category !== "all") { chooseCategory("all"); return true }
      return false
    }

    if (root.navStack.length > 0) {
      var previous = root.navStack[root.navStack.length - 1]
      root.navStack = root.navStack.slice(0, root.navStack.length - 1)
      root.setActiveMenu(previous, false)
      return true
    }

    var active = root.item(root.activeMenu)
    root.setActiveMenu((active && active.parent) ? active.parent : "root", false)
    return true
  }

  function activateIndex(index, fromPointer) {
    if (root.deleteConfirmOpen) return
    if (!root.dmenuActive && category === "files") {
      if(index>=0 && index<extraRows.length) { const path=extraRows[index].path; root.cancel(); Quickshell.execDetached(["xdg-open",path]) }
      return
    }
    if (!root.dmenuActive && category === "clipboard") {
      if(index<0 || index>=extraRows.length) return
      const row=extraRows[index]
      root.cancel()
      if(row.entryType === "image") Quickshell.execDetached(["omarchy-clipboard-paste-file",row.mime,row.path])
      else Quickshell.execDetached(["omarchy-clipboard-paste-text","--shift-insert","--history-index",String(row.index)])
      return
    }
    if (root.dmenuActive) {
      if (root.mode === "input") {
        root.applyDmenuSelection(root.filterText)
        return
      }
      if (index < 0 || index >= displayModel.count) return
      var picked = displayModel.get(index)
      root.applyDmenuSelection(picked.detail ? picked.label + "\t" + picked.detail : picked.label)
      return
    }

    if (index < 0 || index >= displayModel.count) return

    var row = displayModel.get(index)
    if (row.kind === "web") {
      const command = WebShortcuts.command(row.itemId)
      if (command) { root.cancel(); Quickshell.execDetached(command) }
    } else if (row.kind === "menu" || row.kind === "link") {
      root.setActiveMenu(row.target || row.itemId, true, fromPointer)
    } else if (row.kind === "app") {
      var appId = row.appId
      var label = row.label
      applySerial = requestSerial
      opened = false
      filterText = ""
      if (root.appLibrary) root.appLibrary.launch(appId, label)
    } else {
      root.applySelected(row.itemId, row.action)
    }
  }

  function requestDeleteSelected() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.kind !== "app") return
    root.deleteTarget = { appId: row.appId, label: row.label }
    deleteConfirm.selectedIndex = 1
    root.deleteConfirmOpen = true
  }

  function cancelDelete() {
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    deleteConfirm.selectedIndex = 1
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmDelete() {
    var target = root.deleteTarget
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    if (!target) return
    root.cancel()
    if (root.appLibrary) root.appLibrary.remove(target.appId, target.label)
  }

  function applyDmenuSelection(value) {
    applySerial = requestSerial
    opened = false
    root.finishRequest(value)
  }

  function applySelected(id, action) {
    if (!id) { cancel(); return }

    applySerial = requestSerial
    opened = false
    root.runAction(action)
  }

  function cancel() {
    if (root.dmenuActive) root.finishRequest(null)
    opened = false
  }

  function openExistingMenu(initialMenu) {
    const remembered=!opened && initialMenu === "root" ? lastQuery : ""
    if(!opened) {card.morphAnimationReset()}
    requestSerial += 1
    mode = "menu"
    requestActive = false
    selectionFile = ""
    doneFile = ""
    category = initialMenu === "root" ? "all" : initialMenu === "apps" ? "apps" : "actions"
    forceResults = initialMenu !== "root" || (!!remembered && lastResults)
    quickReady = !!remembered; categoriesReady = false; completionSuppressed=!!remembered && lastCompletionSuppressed;hoveredCategory=-1
    activeMenu = root.item(initialMenu) ? initialMenu : "root"
    navStack = []
    filterText = remembered
    selectedIndex = 0
    cursorActive = true
    root.disarmPointer()
    root.evaluateGuards()
    rebuildDisplay()
    opened = true
    idleCategories.restart()
    exactDelay.restart()
    invalidateVolatileProvider(activeMenu)
    loadProviderForMenu(activeMenu)
    loadProviderForMenu("apps")
    // The shell may start before first-install packages have finished placing
    // their icons. Refresh here even when the desktop entry list did not change.
    deferredIcons.restart()

    Qt.callLater(function() { keyCatcher.forceActiveFocus(); if(root.filterText)keyCatcher.selectAll() })
  }

  function openDmenu(payload) {
    requestSerial += 1
    category = "actions"
    forceResults = true
    mode = payload.mode === "input" ? "input" : "select"
    dmenuPrompt = String(payload.prompt || (mode === "input" ? "Input" : "Select"))
    dmenuOptions = Array.isArray(payload.options) ? payload.options : []
    selectionFile = String(payload.selectionFile || "")
    doneFile = String(payload.doneFile || "")
    requestActive = !!doneFile
    dmenuWidth = Math.max(1, Number(payload.width || 300))
    dmenuMaxHeight = Math.max(0, Number(payload.maxHeight || 0))
    activeMenu = "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = mode !== "input"
    root.disarmPointer()
    opened = true
    idleCategories.restart()
    exactDelay.restart()
    rebuildDisplay()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  ListModel { id: displayModel }

  // ----------------------------------------------------------- route surface
  //
  // The menu is opened through the standard plugin lifecycle:
  // `omarchy-shell shell summon omarchy.menu '{"menu":"system"}'`.
  // Callers may pass a real id (`system`, `setup.power`) or an alias declared
  // in JSONC (`power`, `reminder-set`). Unknown strings fall through to the
  // id-as-route behavior so misspellings still attempt to open the literal id.
  function resolveRoute(input) {
    return MenuModel.resolveRoute(root.items, root.itemOrder, input)
  }

  function openRoute(initialMenu) {
    var id = root.resolveRoute(initialMenu)
    var entry = root.items[id]
    // If the resolved id is an action (i.e. the user invoked an alias for
    // a leaf, e.g. `omarchy menu summon screenrecord-stop`), run it directly
    // instead of opening an action with no children.
    if (entry && entry.kind === "action" && entry.action) {
      root.cancel()
      root.runAction(entry.action)
      return "ok"
    }
    // If it's a link (a redirect to another menu), follow the link.
    if (entry && entry.kind === "link" && entry.target) id = entry.target
    root.pendingInitialMenu = id
    root.openExistingMenu(id)
    return "ok"
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  Process {
    id: providerProc
    property string menuId: ""
    property string providerKey: ""
    property string collected: ""
    property int revision: 0
    stdout: SplitParser {
      onRead: function(data) { providerProc.collected += data + "\n" }
    }
    onExited: {
      if (providerProc.revision === root.providerRevision) {
        root.mergeProviderRows(providerProc.collected, providerProc.menuId, providerProc.providerKey)
        if (root.filterText.trim()) root.loadProvidersForSearch()
      }
      root.startNextProvider()
    }
  }

  Process {
    id: resultProc
    onExited: {
      if (root.applySerial === root.requestSerial)
        root.opened = false
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.providersLoaded["apps"]) root.mergeAppRows()
    }
  }

  // The JSONC sources are watched so live edits to the default file (or the
  // user extension at ~/.config/omarchy/extensions/omarchy-menu.jsonc) take
  // effect without restarting the shell.
  FileView {
    id: defaultMenuFile
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.defaultMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.userMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onLoadFailed: { root.userMenuItems = []; root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  // ---------------------------------------------------------------- guards
  //
  // `when:` (visibility) and `checked:` (✓ marker) are bash expressions the
  // shell wasn't allowed to evaluate before the perf rewrite. Now the shell
  // batches them into one bash subprocess per (re)load so the open path
  // never has to wait on them.

  property var whenResults: ({})       // id → true|false (allow visibility)
  property var checkedResults: ({})    // id → true|false (show ✓)
  property bool guardsPending: false

  function evaluateGuards() {
    // Process ignores a command change while it is running, and `collected`
    // belongs to the run in flight, so a second evaluation cannot overwrite
    // the first: it would throw away the lines already read and never start.
    // The surviving tail then lands as the whole answer, and every id lost
    // with it goes back to showing, since a `when:` only hides on an explicit
    // false. Wait for the run in flight and evaluate once it lands instead.
    if (guardProc.running) {
      root.guardsPending = true
      return
    }
    root.guardsPending = false

    var script = MenuModel.guardScript(root.items)
    if (!script) {
      root.whenResults = ({})
      root.checkedResults = ({})
      return
    }
    guardProc.collected = ""
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { guardProc.collected += data + "\n" }
    }
    onExited: function(exitCode, exitStatus) {
      // A batch that was killed rather than finished has only told us about
      // the rows it reached, and a row whose `when:` went unanswered shows.
      // Keep the last complete set rather than let a half-read one through.
      // A signal leaves the exit code at 0, so the status is what tells us.
      if (exitCode !== 0 || exitStatus !== 0) {
        if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
        return
      }

      var nextWhen = ({})
      var nextChecked = ({})
      var lines = guardProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        var colon = line.lastIndexOf(":")
        if (colon < 0) continue
        var value = line.substring(colon + 1) === "1"
        var rest = line.substring(0, colon)
        var tagAt = rest.lastIndexOf(":")
        if (tagAt < 0) continue
        var id = rest.substring(0, tagAt)
        var tag = rest.substring(tagAt + 1)
        if (tag === "w") nextWhen[id] = value
        else if (tag === "c") nextChecked[id] = value
      }
      root.whenResults = nextWhen
      root.checkedResults = nextChecked
      if (root.opened) root.rebuildDisplay()
      // Run the evaluation that had to stand aside. Deferred by a turn so the
      // process is settled before its command is set again.
      if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
    }
  }
  property string category: "all"
  property bool categoriesReady: false
  property bool quickReady: false
  property bool completionSuppressed: false
  property int hoveredCategory: -1
  property bool forceResults: false
  property var lastScaleTransition: ({})
  property real scaleClock: .1
  property bool scaleOpening: false
  property real scaleFrom: 1
  property real scaleVelocity: 0
  property bool scaleInterrupted: false
  readonly property real visualScale: Motion.visibilityScale(scaleClock,scaleOpening,scaleFrom,scaleVelocity,scaleInterrupted)
  function beginScale(opening,wasVisible) {
    const position=visualScale
    const velocity=scaleAnimation.running?Motion.visibilityVelocity(scaleClock,scaleOpening,scaleFrom,scaleVelocity,scaleInterrupted):0
    scaleAnimation.stop()
    scaleOpening=opening;scaleFrom=position;scaleVelocity=velocity
    scaleInterrupted=wasVisible && (Math.abs(position-Motion.visibilityBase(0,opening))>.00001 || Math.abs(velocity)>.00001)
    scaleClock=0;scaleAnimation.to=(opening?Motion.openDuration:Motion.closeDuration)/1000
    scaleAnimation.duration=opening?Motion.openDuration:Motion.closeDuration
    lastScaleTransition={opening:opening,from:position,start:visualScale,velocity:velocity,interrupted:scaleInterrupted}
    scaleAnimation.start()
  }
  NumberAnimation {id:scaleAnimation;target:root;property:"scaleClock";from:0;easing.type:Easing.Linear}
  property real presentation: 0
  property real opacityProgress: 0
  property string lastQuery: ""
  property bool lastResults: false
  property bool lastCompletionSuppressed: false
  property string screenName: ""
  property real dragX: 0
  property real dragY: 0
  property bool resizeReady: false
  property real resizeFrom: Motion.searchHeight
  property real resizeTo: Motion.searchHeight
  property real resizeClock: .6
  property real resizeInitialVelocity: 0
  readonly property real presentHeight: Motion.resizedHeight(resizeClock,resizeFrom,resizeTo,resizeInitialVelocity)
  function resizeSurface() {
    if(!opened || Math.abs(resizeTo-desiredHeight)<.01)return
    const current=presentHeight
    const velocity=resizeAnimation.running?Motion.resizeVelocity(resizeClock,resizeFrom,resizeTo,resizeInitialVelocity):0
    resizeAnimation.stop();resizeFrom=current;resizeTo=desiredHeight;resizeInitialVelocity=velocity;resizeClock=0
    if(resizeReady && opened)resizeAnimation.start();else resizeClock=.6
  }
  NumberAnimation {id:resizeAnimation;target:root;property:"resizeClock";from:0;to:.6;duration:Motion.resizeDuration;easing.type:Easing.Linear}
  property var extraRows: []
  property var fileRows: []
  property var clipboardHistory: []
  readonly property var webShortcut: !dmenuActive && category === "all" && activeMenu === "root" ? WebShortcuts.resolve(filterText) : null
  readonly property var topResult: { const rev=layoutSerial; return displayModel.count ? displayModel.get(0) : null }
  readonly property bool exactApp: !!topResult && (topResult.kind === "app" || topResult.kind === "web") && filterText.trim().length > 0
      && (topResult.label.toLowerCase() === filterText.trim().toLowerCase()
          || topResult.appId.toLowerCase() === filterText.trim().toLowerCase())
  readonly property string completion: {
    if(!topResult || (topResult.kind!=="app" && topResult.kind!=="web") || !filterText || completionSuppressed || dmenuActive)return ""
    const name=topResult.label, q=filterText.toLowerCase()
    if(name.toLowerCase().startsWith(q))return name.slice(filterText.length)
    return ""
  }
  readonly property bool inlineApp: !!topResult && (topResult.kind==="app" || topResult.kind==="web") && !!filterText && !completionSuppressed && !dmenuActive
      && quickReady && (exactApp || completion.length>0)
  readonly property bool quick: inlineApp && !forceResults
  readonly property bool resultsShown: dmenuActive ? mode !== "input" : forceResults || category!=="all" || (!!filterText && quickReady && !inlineApp)
  readonly property bool categoriesShown: !dmenuActive && !resultsShown && !filterText && categoriesReady
  readonly property real lightWidth: Math.min(Motion.width,panel.logicalWidth-40)
  readonly property real desiredHeight: resultsShown ? Math.min(panel.logicalHeight-panel.effectiveCardTop-32,67+Math.min(7,Math.max(1,displayModel.count))*Motion.rowHeight+13) : Motion.searchHeight
  onDesiredHeightChanged: if(opened) Qt.callLater(root.resizeSurface)
  onFilterTextChanged: if(keyCatcher.text !== filterText) keyCatcher.text=filterText
  NumberAnimation { id:openPresentation;target:root;property:"presentation";to:1;duration:Motion.openDuration;easing.type:Easing.Linear }
  NumberAnimation { id:closePresentation;target:root;property:"presentation";to:0;duration:Motion.closeDuration;easing.type:Easing.Linear;onFinished:if(!root.opened)root.filterText="" }
  NumberAnimation {id:openOpacity;target:root;property:"opacityProgress";to:1;duration:150;easing.type:Easing.OutCubic}
  NumberAnimation {id:closeOpacity;target:root;property:"opacityProgress";to:0;duration:100;easing.type:Easing.OutCubic}
  Timer {id:deferredIcons;interval:550;onTriggered:if(root.opened)localLibrary.refreshIcons()}
  Timer { id:idleCategories; interval:Motion.idleDelay; onTriggered:root.categoriesReady=true }
  Timer { id:exactDelay; interval:Motion.suggestionDelay; onTriggered:root.quickReady=true }
  Timer { id:fileSearchDelay; interval:130; onTriggered: {
    if(fileSearch.running) { fileSearch.running=false; fileSearchDelay.restart(); return }
    fileSearch.query=root.filterText
    fileSearch.command=["python3",decodeURIComponent(Qt.resolvedUrl("search-files.py").toString().replace("file://","")),fileSearch.query]
    fileSearch.running=true
  } }
  Process {
    id:fileSearch
    property string query:""
    stdout:StdioCollector { onStreamFinished: {
      if(fileSearch.query!==root.filterText) return
      try { root.fileRows=JSON.parse(text); if(root.category==="files")root.rebuildExtras() } catch(e) { root.fileRows=[] }
    } }
  }
  FileView {
    id:clipboardFile
    path:Quickshell.env("HOME")+"/.local/state/omarchy/clipboard-history.json"
    watchChanges:true; printErrors:false
    onLoaded: { root.clipboardHistory=ClipboardHistory.parseHistory(text()); if(root.category==="clipboard")root.rebuildExtras() }
    onFileChanged:reload()
  }
  function chooseCategory(value) {
    category=value; activeMenu=value==="apps"?"apps":"root"; navStack=[]
    filterText=""; forceResults=value!=="all"; quickReady=false;completionSuppressed=false;hoveredCategory=-1; selectedIndex=0; cursorActive=true
    categoriesReady=value!=="all"
    if(value==="files") { fileRows=[]; fileSearchDelay.restart() }
    if(value==="clipboard") clipboardFile.reload()
    if(value==="apps") loadProviderForMenu("apps")
    rebuildDisplay(); idleCategories.restart(); disarmPointer()
    Qt.callLater(()=>keyCatcher.forceActiveFocus())
  }
  function rebuildExtras() {
    displaySignature="";displayModel.clear()
    extraRows=category==="files"?fileRows:ClipboardHistory.displayRows(clipboardHistory,filterText,80)
    for(let i=0;i<extraRows.length;i++) {
      const e=extraRows[i]
      displayModel.append({itemId:category+"."+i,kind:category,icon:"",iconFont:"",appIcon:"",appId:"",
        label:category==="files"?e.name:e.previewText,detail:category==="files"?e.detail:(e.entryType==="image"?"Image":"Clipboard"),
        path:e.path||"",action:"",target:"",childCount:0,section:""})
    }
    selectedIndex=Math.min(selectedIndex,Math.max(0,displayModel.count-1));layoutSerial++
  }
  function placeholder() {
    if(dmenuActive)return dmenuPrompt
    if(category==="all")return hoveredCategory>=0?["Applications","Files","Actions","Clipboard"][hoveredCategory]:"OmarchyLight Search"
    if(category==="files")return "Files"
    if(category==="clipboard")return "Clipboard"
    return activeMenu==="root"?"Actions":(item(activeMenu)?(item(activeMenu).title||item(activeMenu).label):"Search")
  }
  function escapeLight() {
    if(deleteConfirmOpen) cancelDelete()
    else if(filterText) { setFilter(""); if(category==="all")forceResults=false }
    else if(category!=="all" && !dmenuActive) { if(!goBack())chooseCategory("all") }
    else cancel()
  }
  IpcHandler {
    target:"omarchylight"
    function inspect(): string { return JSON.stringify({opened:root.opened,category:root.category,route:root.activeMenu,query:root.filterText,
      selectedResult:displayModel.count&&root.selectedIndex>=0&&root.selectedIndex<displayModel.count?{id:displayModel.get(root.selectedIndex).itemId,kind:displayModel.get(root.selectedIndex).kind,label:displayModel.get(root.selectedIndex).label}:null,
      appLibrary:!!root.appLibrary,apps:root.appLibrary?root.appLibrary.sortedEntries("").length:-1,loaded:root.providersLoaded,appRows:root.itemOrder.filter(id=>id.indexOf("apps.")===0).length,count:displayModel.count,results:root.resultsShown,quick:root.quick,inline:root.inlineApp,completion:root.completion,hover:root.hoveredCategory,geometry:card.geometry,split:card.split,presentation:root.presentation,scale:card.scale,scaleClock:root.scaleClock,scaleInterrupted:root.scaleInterrupted,scaleTransition:root.lastScaleTransition,
      resize:{time:root.resizeClock,from:root.resizeFrom,to:root.resizeTo,initialVelocity:root.resizeInitialVelocity,velocity:Motion.resizeVelocity(root.resizeClock,root.resizeFrom,root.resizeTo,root.resizeInitialVelocity)},
      bounds:{x:card.x,y:card.y,width:card.width,height:card.height},actionBounds:{x:card.x+openHint.x,y:card.y+openHint.y,width:openHint.width,height:openHint.height},screen:panel.screen?panel.screen.name:"",shader:glass.status}) }
    // Deterministic local visual verification: freeze the liquid transition at a timestamp.
    function sampleMerge(seconds:real):void {
      root.categoriesReady=true;morphAnimation.stop();card.morphVelocity=null;card.morphFrom=Motion.separatedGeometry(card.width)
      card.symbolFromOpacity=1;card.symbolFromSigma=0;card.separating=false;card.morphClock=Math.max(0,Math.min(1.1,seconds))
    }
    function sampleTransition(seconds:real):void {
      root.categoriesReady=true;morphAnimation.stop();card.morphVelocity=null;card.morphFrom=Motion.closedGeometry(card.width)
      card.symbolFromOpacity=0;card.symbolFromSigma=12;card.separating=true;card.morphClock=Math.max(0,Math.min(1.1,seconds))
    }
    function search(query:string):void { root.setFilter(query) }
    function category(name:string):void { root.chooseCategory(name) }
  }
  PanelWindow {
    id:panel
    screen:Quickshell.screens.find(s=>s.name===root.screenName)||Quickshell.screens[0]
    visible:root.rowsLoaded && (root.opened || root.presentation>0.001)
    anchors { top:true;bottom:true;left:true;right:true }
    color:"transparent"
    WlrLayershell.namespace:"omarchylight"
    WlrLayershell.layer:WlrLayer.Overlay
    WlrLayershell.keyboardFocus:root.opened?WlrKeyboardFocus.Exclusive:WlrKeyboardFocus.None
    exclusionMode:ExclusionMode.Ignore
    property int cardTop:-1
    property int maxRowsHeight:-1
    readonly property real logicalWidth:screen?screen.width:1920
    readonly property real logicalHeight:screen?screen.height:1080
    readonly property int effectiveCardTop:Math.max(28,Math.min(logicalHeight-100,Math.round(logicalHeight*Motion.topFraction+root.dragY)))
    function freezeCardTop() {}
    Connections {
      target: panel.contentItem.Window.window
      function onFrameSwapped() {
        if(root.openingPending && root.opened)root.beginOpening()
      }
    }
    MouseArea { anchors.fill:parent;onClicked:root.cancel() }
    Item {
      id:card
      x:Math.max(20,Math.min(panel.logicalWidth-width-20,Math.round((panel.logicalWidth-width)/2+root.dragX)))
      y:panel.effectiveCardTop
      width:root.lightWidth;height:root.presentHeight
      opacity:root.opacityProgress
      scale:root.visualScale
      transformOrigin:Item.Center
      property real morphClock: 1.1
      property bool separating: false
      property var morphFrom: Motion.closedGeometry(width)
      property var morphVelocity: null
      property real symbolFromOpacity: 0
      property real symbolFromSigma: 12
      readonly property real symbolOpacity: Motion.symbolOpacity(morphClock,separating,symbolFromOpacity)
      readonly property real symbolSigma: Motion.symbolBlur(morphClock,separating,symbolFromSigma)
      readonly property var geometry: Motion.geometry(morphClock,separating,morphFrom,width,morphVelocity)
      readonly property real split: Math.max(0,Math.min(1,(width-geometry[0])/256))
      function morphAnimationReset() {
        morphAnimation.stop();morphVelocity=null;symbolFromOpacity=0;symbolFromSigma=12;separating=false;morphFrom=Motion.closedGeometry(width);morphClock=1.1
      }
      function morph(separate) {
        const current=geometry.slice()
        const previousOpacity=symbolOpacity, previousSigma=symbolSigma
        const velocity=morphAnimation.running?Motion.velocityAt(morphClock,separating,morphFrom,width,morphVelocity):null
        morphAnimation.stop();morphVelocity=velocity;morphFrom=current;symbolFromOpacity=previousOpacity;symbolFromSigma=separate?(previousOpacity<.001?12:previousSigma):previousSigma;separating=separate;morphClock=0;morphAnimation.start()
      }
      NumberAnimation { id:morphAnimation;target:card;property:"morphClock";from:0;to:1.1;duration:1100;easing.type:Easing.Linear }
      Connections { target:root;function onCategoriesShownChanged(){card.morph(root.categoriesShown)} }
      ShaderEffect {
        id:glass
        x:-24;y:-24;width:card.width+48;height:card.height+48
        property vector2d surfaceSize:Qt.vector2d(width,height)
        property real cardWidth:card.width
        property real cardHeight:card.height
        property real mainWidth:card.geometry[0]
        property vector4d centers:Qt.vector4d(card.geometry[1],card.geometry[2],card.geometry[3],card.geometry[4])
        property vector4d radii:Qt.vector4d(card.geometry[5],card.geometry[6],card.geometry[7],card.geometry[8])
        property real joinRadius:card.geometry[9]
        property real corner:Math.min(card.height/2,28)
        fragmentShader:Qt.resolvedUrl("shaders/glass.frag.qsb")
      }
      MouseArea { x:0;y:0;width:card.geometry[0];height:card.height;onClicked:keyCatcher.forceActiveFocus() }
      LightSymbol {
        id:searchMark;x:20;y:16;width:24;height:24;ink:"#939397"
        kind:root.category!=="all"&&!root.filterText&&!root.dmenuActive?"back":"search"
        MouseArea { anchors.fill:parent;onClicked: { if(root.category!=="all"&&!root.filterText)root.goBack();else keyCatcher.forceActiveFocus() } }
      }
      TextInput {
        id:keyCatcher
        x:root.hasVariableFont?59.5:60;y:11;width:Math.max(80,card.geometry[0]-110);height:34
        focus:true;clip:true;color:root.hasVariableFont?"white":"#f5f5f7"
        font.family:root.hasVariableFont?"Inter Variable":"Inter Display"
        font.pixelSize:root.hasVariableFont?25:26;font.weight:root.hasVariableFont?475:500
        font.variableAxes:root.hasVariableFont?({wght:475,opsz:24}):({})
        font.letterSpacing:root.hasVariableFont?-.25:-.5
        font.hintingPreference:Font.PreferNoHinting;renderType:root.hasVariableFont?Text.QtRendering:Text.NativeRendering
        selectionColor:"#477aab";selectedTextColor:"white";selectByMouse:true
        verticalAlignment:TextInput.AlignVCenter
        onTextEdited:root.setFilter(text)
        cursorDelegate:Rectangle { width:1.5;height:30;color:"#cfcfd4";visible:keyCatcher.activeFocus && cursorBlink.on && !root.inlineApp }
        Timer { id:cursorBlink;property bool on:true;interval:550;running:root.opened;repeat:true;onTriggered:on=!on }
        Text {
          visible:!keyCatcher.text && !keyCatcher.preeditText
          anchors.verticalCenter:parent.verticalCenter
          text:root.placeholder();color:"#96969a";font:parent.font;renderType:keyCatcher.renderType
        }
        Keys.priority:Keys.BeforeItem
        Keys.onPressed:function(event) {
          if(root.deleteConfirmOpen) { event.accepted=deleteConfirm.handleKey(event);return }
          if(event.key===Qt.Key_Escape) { root.escapeLight();event.accepted=true }
          else if(event.key===Qt.Key_Backspace && root.inlineApp && keyCatcher.selectionStart===keyCatcher.selectionEnd) {
            root.completionSuppressed=true;root.forceResults=true;event.accepted=true
          } else if(event.key===Qt.Key_Right && root.inlineApp && root.completion) {
            root.setFilter(root.filterText+root.completion);event.accepted=true
          }
          else if((event.modifiers&Qt.ControlModifier)&&event.key>=Qt.Key_1&&event.key<=Qt.Key_4) {
            root.chooseCategory(["apps","files","actions","clipboard"][event.key-Qt.Key_1]);event.accepted=true
          } else if(event.key===Qt.Key_Tab) {
            const cats=["all","apps","files","actions","clipboard"]
            root.chooseCategory(cats[(cats.indexOf(root.category)+1)%cats.length]);event.accepted=true
          } else if(event.key===Qt.Key_Backspace&&!text&&!preeditText&&!root.dmenuActive) {root.goBack();event.accepted=true}
          else if(event.key===Qt.Key_Down||event.key===Qt.Key_Up) {
            const was=root.resultsShown;root.forceResults=true
            if(was)root.select(event.key===Qt.Key_Down?1:-1);else {root.selectedIndex=0;root.cursorActive=true}
            event.accepted=true
          } else if(event.key===Qt.Key_PageDown||event.key===Qt.Key_PageUp) {root.forceResults=true;root.select(event.key===Qt.Key_PageDown?6:-6);event.accepted=true}
          else if(event.key===Qt.Key_Return||event.key===Qt.Key_Enter) {root.activateIndex(root.selectedIndex);event.accepted=true}
          else if(event.key===Qt.Key_Delete&&(event.modifiers&Qt.ControlModifier)) {root.requestDeleteSelected();event.accepted=true}
        }
      }
      Text {
        id:completionLabel;x:keyCatcher.x+keyCatcher.contentWidth;y:keyCatcher.y;height:keyCatcher.height
        text:root.inlineApp?root.completion:"";font:keyCatcher.font;color:keyCatcher.color
        verticalAlignment:Text.AlignVCenter;renderType:keyCatcher.renderType
      }
      Row {
        visible:root.hoveredCategory>=0 && root.categoriesShown
        x:card.geometry[0]-58;y:21;spacing:4
        Repeater {model:["⌃",String(root.hoveredCategory+1)]
          Rectangle {required property string modelData;width:14;height:14;radius:3;color:"#18ffffff"
            Text {anchors.centerIn:parent;text:parent.modelData;font.family:root.fontFamily;font.pixelSize:10;color:"#b5b5ba"}
          }
        }
      }
      Rectangle {
        id:openHint
        x:Math.min(card.width-120,keyCatcher.x+keyCatcher.contentWidth+completionLabel.contentWidth+1);y:12;width:82;height:30;radius:11
        color:openMouse.containsMouse?"#20ffffff":"#12ffffff";visible:root.inlineApp
        Accessible.role:Accessible.Button
        Accessible.name:"Open "+(root.topResult?root.topResult.label:"")
        Accessible.onPressAction:root.activateIndex(0,true)
        MouseArea {id:openMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:root.activateIndex(0,true)}
        Rectangle {x:13;y:18;width:12;height:1;radius:.5;color:"#616165"}
        Text {x:35.5;y:4;width:44;height:28;text:"Open";color:"#5e5e62";font.family:"Inter";font.pixelSize:15;font.weight:500;font.letterSpacing:-.4;font.hintingPreference:Font.PreferNoHinting;renderType:Text.QtRendering;verticalAlignment:Text.AlignVCenter}
      }
      Image {
        x:card.width-46;y:15.5;width:26;height:26
        visible:root.inlineApp
        source:visible&&root.appLibrary?localLibrary.iconSource(root.topResult.appIcon):""
        sourceSize:Qt.size(width*Math.max(2,Screen.devicePixelRatio),height*Math.max(2,Screen.devicePixelRatio));fillMode:Image.PreserveAspectFit;smooth:true;mipmap:true
      }
      Repeater {
        model:["apps","files","actions","clipboard"]
        Item {
          required property int index
          required property string modelData
          x:card.geometry[index+1]-28;y:0;width:56;height:56
          visible:card.geometry[index+5]>1 && card.split>.05
          readonly property real reveal: card.symbolOpacity
          opacity:reveal
          Rectangle { anchors.fill:parent;radius:28;color:catMouse.containsMouse?"#0affffff":"transparent" }
          SoftSymbol {anchors.centerIn:parent;kind:modelData;sigma:card.symbolSigma;ink:catMouse.containsMouse?"#b7b7bd":modelData==="apps"?"#96969a":"#8b8b90"}
          MouseArea {
            id:catMouse;anchors.fill:parent;hoverEnabled:true
            onEntered:root.hoveredCategory=index
            onExited:if(root.hoveredCategory===index)root.hoveredCategory=-1
            onClicked:root.chooseCategory(modelData)
          }
        }
      }
      Item {
        id:resultsViewport
        x:10;y:56;width:parent.width-20;height:Math.max(0,parent.height-y-8)
        clip:true;visible:height>1
        opacity:root.resultsShown?1:0
        Behavior on opacity {NumberAnimation {duration:100}}
        Rectangle {x:10;y:0;width:parent.width-20;height:1;color:"#28ffffff"}
        ListView {
          id:resultList
          x:0;y:11;width:parent.width;height:Math.max(0,parent.height-11)
          model:displayModel;clip:true;spacing:0
          boundsBehavior:Flickable.StopAtBounds
          ScrollBar.vertical:ScrollBar {width:4;policy:ScrollBar.AsNeeded}
          delegate:Rectangle {
            id:row
            required property int index
            required property string itemId
            required property string kind
            required property string icon
            required property string iconFont
            required property string appIcon
            required property string appId
            required property string label
            required property string target
            required property string detail
            required property string path
            required property string action
            required property int childCount
            readonly property bool hasCursor:root.cursorActive&&index===root.selectedIndex
            readonly property bool showDetail:detail.length>0&&kind!=="app"
            width:ListView.view.width;height:Motion.rowHeight;radius:18
            color:hasCursor?"#20f7fbff":"transparent"
            Image {
              x:11.5;y:13.5;width:29;height:29;visible:row.kind==="app"||row.kind==="web"
              source:visible&&root.appLibrary?localLibrary.iconSource(row.appIcon):""
              sourceSize:Qt.size(width*Math.max(2,Screen.devicePixelRatio),height*Math.max(2,Screen.devicePixelRatio));fillMode:Image.PreserveAspectFit;smooth:true;mipmap:true
            }
            LightSymbol {x:13;y:14;width:26;height:28;visible:row.kind==="files"||row.kind==="clipboard";kind:row.kind;ink:"#c5c5cb"}
            Text {
              x:12;y:13;width:28;height:30;visible:row.kind!=="app"&&row.kind!=="web"&&row.kind!=="files"&&row.kind!=="clipboard"
              text:row.icon;font.family:row.iconFont||"Symbols Nerd Font";font.pixelSize:23;color:"#c5c5cb"
              horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter;renderType:Text.NativeRendering
            }
            Item {
              x:61;width:parent.width-x-(rowHint.visible?rowHint.width+28:45);height:parent.height
              Text {y:row.showDetail?8:0;height:row.showDetail?24:parent.height;verticalAlignment:Text.AlignVCenter;width:parent.width;text:row.label;color:"#f5f5f7";font.family:root.fontFamily;font.pixelSize:17;font.weight:500;font.letterSpacing:-0.5;font.hintingPreference:Font.PreferNoHinting;renderType:Text.NativeRendering;elide:Text.ElideRight}
              Text {y:29;height:24;verticalAlignment:Text.AlignVCenter;width:parent.width;visible:row.showDetail;text:row.detail;color:"#606065";font.family:"Inter Display";font.pixelSize:16;font.weight:350;font.letterSpacing:0;font.hintingPreference:Font.PreferNoHinting;renderType:Text.NativeRendering;elide:Text.ElideMiddle}
            }
            LightSymbol {x:parent.width-30;y:20;width:14;height:16;kind:"chevron";visible:row.kind==="menu"||row.kind==="link";ink:"#85858b"}
            Row {
              id:rowHint
              anchors.right:parent.right;anchors.rightMargin:10;anchors.verticalCenter:parent.verticalCenter;spacing:8
              visible:row.hasCursor&&row.kind!=="menu"&&row.kind!=="link"
              Text {
                width:Math.min(160,implicitWidth);height:18;verticalAlignment:Text.AlignVCenter;elide:Text.ElideRight
                text:root.dmenuActive?"Select":row.kind==="web"?"Open in Chrome":row.kind==="app"?"Open "+row.label:row.kind==="clipboard"?"Paste":row.kind==="files"?"Open File":"Run"
                color:"#76767c";font.family:"Inter";font.pixelSize:10;font.weight:500
              }
              Rectangle {
                width:27;height:18;radius:5;color:"#29ffffff"
                Text {anchors.centerIn:parent;text:"↵";color:"#b3b3b7";font.family:"Inter";font.pixelSize:13}
              }
            }
            MouseArea {
              id:rowMouse;anchors.fill:parent;hoverEnabled:true
              onPositionChanged:function(mouse){root.selectFromPointer(row.index,row,mouse)}
              onClicked:root.activateIndex(row.index,true)
            }
          }
          Text {
            anchors.centerIn:parent;visible:displayModel.count===0
            text:root.category==="files"&&fileSearch.running?"Searching files…":root.filterText?"No results":root.category==="clipboard"?"Clipboard is empty":"No items"
            color:"#96969c";font.family:root.fontFamily;font.pixelSize:14
          }
        }
      }
      MouseArea {
        x:0;y:0;width:card.geometry[0]
        height:root.category==="all" && !root.filterText && !keyCatcher.preeditText && !root.dmenuActive?56:7
        cursorShape:height>7?Qt.IBeamCursor:Qt.ArrowCursor
        property point last
        property point start
        property bool dragging:false
        onPressed:function(mouse){last=mapToItem(panel.contentItem,mouse.x,mouse.y);start=last;dragging=false;keyCatcher.forceActiveFocus()}
        onPositionChanged:function(mouse){
          if(!pressed)return
          const p=mapToItem(panel.contentItem,mouse.x,mouse.y)
          if(!dragging && Math.hypot(p.x-start.x,p.y-start.y)<4)return
          dragging=true;root.dragX+=p.x-last.x;root.dragY+=p.y-last.y;last=p
        }
      }
      ConfirmDialog {
        id:deleteConfirm;anchors.fill:parent;z:10;opened:root.deleteConfirmOpen
        message:"Uninstall "+((root.deleteTarget&&root.deleteTarget.label)||"")+"?";confirmText:"Uninstall"
        background:"#f5252528";foreground:root.foreground;scrim:"#80101012";selectedBackground:"#3478f6";selectedText:"white";fontFamily:root.fontFamily;cornerRadius:12
        onCanceled:root.cancelDelete();onConfirmed:root.confirmDelete()
      }
    }
  }
}
