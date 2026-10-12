import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.agents"
  ipcTarget: "omarchy.agents"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var providers: usage.enabledProviders
  // The selection follows the provider, not the slot it happens to sit in: a
  // provider whose first scan lands while the panel is open would otherwise
  // shift the list underneath you and swap out what you were reading.
  property string selectedProviderId: ""
  readonly property int providerIndex: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === selectedProviderId) return i
    return 0
  }
  readonly property var provider: providers.length > 0 ? providers[providerIndex] : null

  property bool cursorActive: false

  // Countdowns and "updated" read this instead of Date.now() so the
  // panel keeps telling the truth while it sits open.
  property double nowMs: Date.now()

  readonly property var limits: limitWindows(provider)
  readonly property var models: modelRows(provider)
  readonly property var headline: bindingWindow(provider)
  readonly property var balance: provider ? (provider.balance || null) : null
  // A prepaid account runs low the way a subscription window fills up: the
  // last 10% of the funded credits lights the same alarm.
  readonly property bool balanceAlarming: !!balance && balance.funded > 0
    && balance.remaining / balance.funded <= 0.1
  readonly property bool alarming: (!!headline && headline.percent >= 0.9) || balanceAlarming

  readonly property bool hasBalance: !!balance
  readonly property bool hasLimits: limits.length > 0
  readonly property bool hasUsage: !!provider && !!provider.recentDays && provider.recentDays.length > 0
  readonly property bool hasModels: models.length > 0
  readonly property bool hasLeftSide: hasBalance || hasLimits
  readonly property bool hasRightSide: hasUsage || hasModels

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // Dynamic soft colors for limits: <50% green, <75% yellow, <80% orange, >=80% red
  function limitColor(percent) {
    if (percent < 0) return root.foreground
    if (percent < 0.50) return "#81c784"  // Soft green
    if (percent < 0.75) return "#eed49f"  // Soft yellow
    if (percent < 0.80) return "#f6ad55"  // Soft orange
    return "#e57373"                      // Soft red
  }

  // Soft palette for daily usage bars
  function dayBarColor(day, today, isHovered) {
    if (isHovered) return "#c084fc"
    if (today) return "#a78bfa"
    if (day && Number(day.messageCount || 0) > 0) return "#7dd3fc"
    return root.dim
  }

  // Place-based rankings colors for models comparison
  function rankColor(index) {
    if (index === 0) return "#fbbf24" // 1st: Soft Gold
    if (index === 1) return "#cbd5e1" // 2nd: Soft Silver
    if (index === 2) return "#fb923c" // 3rd: Soft Bronze
    return root.dim                   // 4th+: Muted
  }

  function rankFillColor(index) {
    if (index === 0) return root.alpha("#fbbf24", 0.22)
    if (index === 1) return root.alpha("#cbd5e1", 0.18)
    if (index === 2) return root.alpha("#fb923c", 0.18)
    return root.alpha(root.foreground, 0.10)
  }

  function selectProvider(index) {
    if (providers.length === 0) return
    var wrapped = ((index % providers.length) + providers.length) % providers.length
    selectedProviderId = providers[wrapped].providerId
  }

  function refreshNow() {
    usage.refreshAll(true)
  }

  function launchAgent() {
    if (root.bar) root.bar.run("omarchy-agent --pick")
    root.close()
  }

  // ---------------------------------------------------------------- limits
  //
  // Both providers report the same two shapes: a short rolling session window
  // and a long weekly one. Everything below normalizes them into one record so
  // the meters and the hero speak a single language.

  // Claude spells its windows out ("Session (5-hour)"), Codex abbreviates
  // them ("5h window", "30m window"). Both have to land on the same record.
  function windowIsLong(text) {
    return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
      || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
  }

  function windowSpanMs(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return 30 * 24 * 3600 * 1000
    if (windowIsLong(text)) return 7 * 24 * 3600 * 1000
    var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
    if (hours) return Number(hours[1]) * 3600 * 1000
    var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
    if (minutes) return Number(minutes[1]) * 60 * 1000
    return 0
  }

  function windowTitle(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0) return "Monthly"
    if (windowIsLong(text)) return "Weekly"
    if (text.indexOf("session") >= 0 || windowSpanMs(label) > 0) return "Session"
    var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim()
    return plain === "" ? "Limit" : plain
  }

  // A collector that already knows which window a limit belongs to says so,
  // and that beats reading it back out of the label: a model-scoped limit is
  // titled after its model, and a name like "Opus 5 (1M context)" would parse
  // as a one-minute window.
  function limitWindow(label, percent, resetAt, title) {
    return {
      title: String(title || "") !== "" ? String(title) : windowTitle(label),
      percent: Number(percent),
      resetAt: String(resetAt || "")
    }
  }

  function limitWindows(p) {
    if (!p) return []
    var out = []
    var list = p.limits || []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var percent = Number(entry.percent)
      if (percent >= 0) out.push(limitWindow(entry.label, percent, entry.resetsAt, entry.title))
    }
    return out
  }

  // The window that decides how much room is left — the fullest one, since
  // that is what stops the next prompt.
  function bindingWindow(p) {
    var windows = limitWindows(p)
    var best = null
    for (var i = 0; i < windows.length; i++) {
      if (!best || windows[i].percent > best.percent) best = windows[i]
    }
    return best
  }

  function resetMsFor(w) {
    if (!w || w.resetAt === "") return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  // ---------------------------------------------------------------- balance
  //
  // Prepaid agents report a credit ledger instead of rate-limit windows: the
  // record's balance object carries remaining, funded, and spent amounts.

  function currencyPrefix(currency) {
    var code = String(currency || "USD").toUpperCase()
    if (code === "USD") return "$"
    if (code === "EUR") return "€"
    if (code === "GBP") return "£"
    return code + " "
  }

  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) amount = 0
    return currencyPrefix(currency) + amount.toFixed(2)
  }

  function balanceDetailText(b) {
    if (!b || !(b.funded > 0)) return ""
    var text = formatMoney(b.spent, b.currency) + " spent of " + formatMoney(b.funded, b.currency) + " funded"
    if (b.estimated) text += " · estimated"
    return text
  }

  // ---------------------------------------------------------------- content

  // The plan you pay for, under the name of the tool it pays for. Limits live
  // in their own section; the hero just says what this is.
  function heroMeta(p) {
    if (!p) return ""
    if (String(p.usageStatusText || "") !== "") return p.usageStatusText
    var tier = String(p.tierLabel || "")
    if (tier === "") return "Subscription"
    return tier.charAt(0).toUpperCase() + tier.slice(1)
  }

  // Local calendar date, recomputed from nowMs so a panel left open across
  // midnight moves the "Today" row with the clock.
  function todayDate() {
    var now = new Date(root.nowMs)
    return now.getFullYear()
      + "-" + String(now.getMonth() + 1).padStart(2, "0")
      + "-" + String(now.getDate()).padStart(2, "0")
  }

  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()]
  }

  function dayLabel(date, today) {
    if (today) return "Today"
    return dayName(date)
  }

  function dayTooltip(day, today) {
    if (!day) return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var label = isNaN(parsed.getTime())
      ? String(day.date)
      : dayName(day.date) + " " + (parsed.getMonth() + 1) + "/" + parsed.getDate()
    var text = label + " · " + usage.formatTokenCount(Number(day.messageCount || 0)) + " tokens"
    // Prompt and session counts only exist for today, so they ride along here
    // instead of taking a section of their own. Billing-API agents never
    // count prompts, and "0 prompts" would read as a quiet day, not a gap.
    if (today && provider && provider.hasPromptStats !== false)
      text += " · " + Number(provider.todayPrompts || 0) + " prompts · "
        + Number(provider.todaySessions || 0) + " sessions"
    return text
  }

  function weekPeak(p) {
    var days = p ? (p.recentDays || []) : []
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, Number(days[i].messageCount || 0))
    return peak
  }

  function modelRows(p) {
    var usageByModel = p ? (p.modelUsage || {}) : {}
    var rows = []
    for (var id in usageByModel) {
      var bucket = usageByModel[id] || {}
      var input = Number(bucket.inputTokens || 0)
      var output = Number(bucket.outputTokens || 0)
      var cacheRead = Number(bucket.cacheReadInputTokens || 0)
      var cacheWrite = Number(bucket.cacheCreationInputTokens || 0)
      rows.push({
        name: usage.friendlyModelName(id),
        total: input + output + cacheRead + cacheWrite,
        input: input,
        output: output,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite
      })
    }
    rows.sort(function(a, b) { return b.total - a.total })
    return rows.slice(0, 4)
  }

  function modelTooltip(row) {
    if (!row) return ""
    return "In " + usage.formatTokenCount(row.input)
      + " · out " + usage.formatTokenCount(row.output)
      + " · cache read " + usage.formatTokenCount(row.cacheRead)
      + " · cache write " + usage.formatTokenCount(row.cacheWrite)
  }

  // Only speaks up when the numbers cover more than this machine.
  function footerText() {
    if (usage.syncStatusText !== "") return usage.syncStatusText
    if (provider && provider.syncEnabled && provider.syncDeviceCount > 0)
      return "Merged from " + provider.syncDeviceCount + " device" + (provider.syncDeviceCount === 1 ? "" : "s")
    return ""
  }

  // Agents that ship a white mark carry an `assets/<id>-light.svg` twin for
  // light surfaces; marks that work on both (Claude's brand-orange) ship one
  // file. The luminance check decides which candidate to try first.
  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r)
      + 0.7152 * colorChannelLuminance(color.g)
      + 0.0722 * colorChannelLuminance(color.b)
  }

  // Marks resolve by convention, so a new agent's data file needs nothing
  // from this panel: assets/<id>.svg if it ships one, the module's bar glyph
  // if it doesn't.
  function iconCandidatesForProvider(p, surfaceColor) {
    if (!p) return []
    var candidates = []
    if (colorLuminance(surfaceColor || Color.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/" + p.providerId + "-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/" + p.providerId + ".svg"))
    return candidates
  }

  // Nothing to report, nothing in the bar: Bar.qml collapses a slot whose item
  // is invisible, so the icon appears the moment the first scan finds usage and
  // stays away entirely on a machine that has never run either CLI.
  visible: providers.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onProviderIndexChanged: if (panelFlick) panelFlick.contentY = 0
  onOpenedChanged: if (opened) {
    cursorActive = false
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    usage.refreshLimits()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Main {
    id: usage
    settings: root.settings
  }

  // Cheap enough to keep running: it only re-evaluates text bindings, and a
  // stale "resets in 2h" on a panel that is open is worse than a timer.
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function next(): string { root.selectProvider(root.providerIndex + 1); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󱚣"
    active: root.alarming
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchAgent()
      else if (buttonCode === Qt.MiddleButton) root.selectProvider(root.providerIndex + 1)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dx !== 0) {
          root.cursorActive = true
          root.selectProvider(root.providerIndex + dx)
        }
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refreshNow() }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------- Hero: provider mark · name · plan ----------
          PanelHero {
            id: hero
            visible: !!root.provider
            Layout.fillWidth: true
            title: root.provider ? root.provider.providerName : ""
            meta: root.heroMeta(root.provider)
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Item {
                id: heroMark
                property var candidates: root.iconCandidatesForProvider(root.provider, root.surface)
                // Provider objects are rebuilt on every refresh, which churns the
                // array's identity without changing its content. Restart the fallback
                // walk only when the URLs change: re-pointing source at a URL whose
                // load already failed emits no statusChanged, so an identity-only
                // reset would strand the walker on a missing -light twin.
                property string candidatesKey: candidates.join("\n")
                property int candidateIndex: 0
                onCandidatesKeyChanged: candidateIndex = 0

                width: Style.font.display
                height: Style.font.display

                Image {
                  id: heroMarkImage
                  anchors.fill: parent
                  source: heroMark.candidateIndex < heroMark.candidates.length ? heroMark.candidates[heroMark.candidateIndex] : ""
                  sourceSize.width: Style.font.display * 2
                  sourceSize.height: Style.font.display * 2
                  fillMode: Image.PreserveAspectFit
                  // Advancing source from inside its own status change trips the
                  // binding-loop detector; defer the step one tick.
                  onStatusChanged: if (status === Image.Error && heroMark.candidateIndex < heroMark.candidates.length)
                    Qt.callLater(function() { heroMark.candidateIndex++ })
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  visible: heroMarkImage.status !== Image.Ready
                  text: button.text
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
            }

            trailingControl: Component {
              BorderSurface {
                id: refreshBtn
                implicitWidth: Style.space(28)
                implicitHeight: Style.space(28)
                radius: Style.cornerRadius
                color: refreshMouse.containsMouse ? Style.hoverFillFor(Color.accent, Color.accent) : "transparent"
                borderSpec: Border.controlSpec(refreshMouse.containsMouse ? "hover-cursor" : "normal", root.foreground, Color.accent)

                Text {
                  id: refreshIcon
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "󰑐"
                  color: refreshMouse.containsMouse ? Color.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon

                  RotationAnimation on rotation {
                    running: usage.isUpdating
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 800
                  }
                }

                MouseArea {
                  id: refreshMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.refreshNow()
                }

                PanelToolTip {
                  visible: refreshMouse.containsMouse
                  text: "Refresh usage (R)"
                  fontFamily: root.fontFamily
                }
              }
            }
          }

          Text {
            visible: root.providers.length === 0
            Layout.fillWidth: true
            topPadding: Style.space(24)
            text: "No AI coding subscriptions found.\nAgents show up here once you've used them."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // ---------- Provider switch ----------
          Row {
            id: providerSwitch
            visible: root.providers.length > 1
            Layout.fillWidth: true
            spacing: Style.spacing.md

            readonly property real cellWidth: root.providers.length > 0
              ? (width - spacing * (root.providers.length - 1)) / root.providers.length
              : 0

            Repeater {
              model: root.providers

              Button {
                required property var modelData
                required property int index

                width: providerSwitch.cellWidth
                text: modelData.providerName
                selected: index === root.providerIndex
                hasCursor: root.cursorActive && index === root.providerIndex
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: {
                  root.cursorActive = true
                  root.selectProvider(index)
                }
                onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
              }
            }
          }

          // ---------- Status ----------
          BorderSurface {
            visible: !!root.provider && String(root.provider.usageStatusText || "") !== ""
            Layout.fillWidth: true
            implicitHeight: statusText.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.urgent, 0.10)
            borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: statusText
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: root.provider ? String(root.provider.authHelpText || "") : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator {
            visible: (root.hasLeftSide || root.hasUsage || root.hasModels) && (hero.visible || providerSwitch.visible)
            Layout.fillWidth: true
            foreground: root.foreground
          }

          // ---------- Limits above, Tokens by Day below ----------
          ColumnLayout {
            id: contentRow
            Layout.fillWidth: true
            spacing: Style.space(16)
            visible: root.hasLeftSide || root.hasUsage

            // Left column: Balance & Limits
            Column {
              id: leftColumn
              visible: root.hasLeftSide
              Layout.fillWidth: true
              spacing: Style.space(12)

              // ---------- Balance ----------
              Column {
                id: balanceSection
                visible: root.hasBalance
                width: parent.width
                spacing: Style.space(10)

                readonly property real ratio: root.balance && root.balance.funded > 0
                  ? root.clamp(root.balance.remaining / root.balance.funded, 0, 1)
                  : -1

                PanelSectionHeader {
                  width: parent.width
                  text: "BALANCE"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Item {
                  width: parent.width
                  implicitHeight: Math.max(balanceLabel.implicitHeight, balanceValue.implicitHeight)

                  Text {
                    id: balanceLabel
                    text: "Prepaid credits"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    id: balanceValue
                    textFormat: Text.PlainText
                    text: root.balance ? root.formatMoney(root.balance.remaining, root.balance.currency) : ""
                    color: root.balanceAlarming ? root.urgent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Meter {
                  visible: balanceSection.ratio >= 0
                  width: parent.width
                  value: balanceSection.ratio
                  alarming: root.balanceAlarming
                }

                Text {
                  textFormat: Text.PlainText
                  visible: text !== ""
                  width: parent.width
                  text: root.balanceDetailText(root.balance)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              PanelSeparator {
                visible: root.hasBalance && root.hasLimits
                foreground: root.foreground
              }

              // ---------- Limits ----------
              Column {
                id: limitsSection
                visible: root.hasLimits
                width: parent.width
                spacing: Style.space(18)

                PanelSectionHeader {
                  text: "LIMITS"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Repeater {
                  model: root.limits

                  LimitRow {
                    required property var modelData
                    width: limitsSection.width
                    window: modelData
                  }
                }
              }
            }

            PanelSeparator {
              visible: root.hasLeftSide && root.hasUsage
              Layout.fillWidth: true
              foreground: root.foreground
            }

            // Right column: Tokens by Day (Growing Vertical Bar Chart)
            ColumnLayout {
              id: rightColumn
              visible: root.hasUsage
              Layout.fillWidth: true
              spacing: Style.space(10)

              readonly property var days: root.provider ? (root.provider.recentDays || []) : []
              readonly property real peak: Math.max(1, root.weekPeak(root.provider))

              PanelSectionHeader {
                id: chartHeader
                Layout.fillWidth: true
                text: "TOKENS BY DAY"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              TokenChart {
                id: chartRow
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(180)
                days: rightColumn.days
                peak: rightColumn.peak
                strokeColor: "#7dd3fc"
              }
            }
          }

          // ---------- Models (full width below the row) ----------
          PanelSeparator {
            visible: (root.hasLeftSide || root.hasUsage) && root.hasModels
            Layout.fillWidth: true
            foreground: root.foreground
          }

          Column {
            id: modelSection
            visible: root.hasModels
            Layout.fillWidth: true
            spacing: Style.spacing.md

            PanelSectionHeader {
              width: parent.width
              text: "TOKENS BY MODEL"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.models

              ModelRow {
                required property var modelData
                required property int index

                width: modelSection.width
                row: modelData
                rankIndex: index
                share: modelData.total / Math.max(1, root.models[0].total)
              }
            }
          }

          PanelSeparator {
            visible: footerTextItem.visible
            Layout.fillWidth: true
            foreground: root.foreground
          }

          Text {
            id: footerTextItem
            textFormat: Text.PlainText
            visible: text !== ""
            Layout.fillWidth: true
            topPadding: Style.space(2)
            text: root.footerText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // A limit window: label and percentage, meter, and reset countdown.
  component LimitRow: Column {
    id: limitRow
    property var window: null

    readonly property real percent: window && window.percent >= 0 ? window.percent : -1
    readonly property color tierColor: root.limitColor(percent)
    readonly property bool alarming: percent >= 0.9

    spacing: Style.space(8)

    Item {
      width: parent.width
      implicitHeight: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)

      Text {
        id: limitLabel
        textFormat: Text.PlainText
        // A model-scoped window is titled after its model, and those names run
        // long enough to reach the percentage, so the title gives way first.
        text: limitRow.window ? limitRow.window.title : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: limitValue.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: limitValue
        textFormat: Text.PlainText
        text: limitRow.percent >= 0
          ? Math.round(limitRow.percent * 100) + "%"
          : "—"
        color: limitRow.tierColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Meter {
      width: parent.width
      value: limitRow.percent
      customColor: limitRow.tierColor
      alarming: limitRow.alarming
    }

    Text {
      id: resetText
      textFormat: Text.PlainText
      width: parent.width
      text: {
        var remainingMs = root.resetMsFor(limitRow.window)
        return remainingMs > 0 ? "Resets in " + root.formatDuration(remainingMs) : ""
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Rounded track showing the percentage of the allowance used with soft glow shadow.
  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false
    property color customColor: root.limitColor(meter.value)
    property real thickness: Math.max(Style.space(5), Math.round(Style.spacing.controlHeight * 0.16))

    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    // Soft glow shadow underneath meter fill
    Rectangle {
      id: meterGlow
      anchors.verticalCenter: meterTrack.verticalCenter
      anchors.left: meterTrack.left
      height: meterTrack.height + Style.space(4)
      radius: height / 2
      width: Math.max(0, meterTrack.width * root.clamp(meter.value, 0, 1) + Style.space(4))
      color: root.alpha(meter.customColor, 0.28)
      visible: meter.value > 0

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    Rectangle {
      id: meterFill
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.customColor

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }
  }

  // TokenChart: line and area sparkline chart for daily token usage
  component TokenChart: Item {
    id: tchart
    property var days: []
    property real peak: 1
    property color strokeColor: "#7dd3fc"
    property color fillColor: root.alpha(strokeColor, 0.15)
    property int hoveredIndex: -1

    readonly property var hoveredDay: (hoveredIndex >= 0 && days && hoveredIndex < days.length)
      ? days[hoveredIndex]
      : null

    // Width reserved for the left Y-axis label column
    readonly property real _labelW: Style.space(40)
    // Width reserved for the current-value gutter on the right
    readonly property real _valueW: Style.space(48)
    // Height reserved for the bottom day-label strip
    readonly property real _axisH: Style.font.caption + Style.space(8)
    // Vertical padding inside the plot canvas so lines/text have room
    readonly property real _padTop: 4
    readonly property real _padBot: 4

    // Y-axis labels on the left (relative to the plot area)
    Text {
      anchors.left: parent.left
      anchors.top: chartCanvas.top
      anchors.topMargin: tchart._padTop - 1
      width: tchart._labelW
      horizontalAlignment: Text.AlignRight
      text: usage.formatTokenCount(tchart.peak)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: chartCanvas.verticalCenter
      width: tchart._labelW
      horizontalAlignment: Text.AlignRight
      text: usage.formatTokenCount(tchart.peak / 2)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      anchors.left: parent.left
      anchors.bottom: chartCanvas.bottom
      anchors.bottomMargin: tchart._padBot - 1
      width: tchart._labelW
      horizontalAlignment: Text.AlignRight
      text: "0"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    // Plot canvas between label column and gutter
    Canvas {
      id: chartCanvas
      anchors.left: parent.left
      anchors.leftMargin: tchart._labelW + Style.space(4)
      anchors.right: parent.right
      anchors.rightMargin: tchart._valueW + Style.space(4)
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.bottomMargin: tchart._axisH

      antialiasing: true

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var w = width
        var h = height
        if (w <= 0 || h <= 0) return

        var padTop = tchart._padTop
        var padBot = tchart._padBot
        var plotH  = h - padTop - padBot
        if (plotH <= 0) return

        var gridAlpha = root.alpha(root.foreground, 0.09)

        // --- Faint dashed grid lines at 100%, 50%, 0%
        ctx.save()
        ctx.setLineDash([3, 4])
        ctx.lineWidth = 1
        ctx.strokeStyle = gridAlpha

        // 100% line (top)
        var y100 = padTop
        ctx.beginPath(); ctx.moveTo(0, y100); ctx.lineTo(w, y100); ctx.stroke()

        // 50% line (middle)
        var y50 = padTop + plotH * 0.5
        ctx.beginPath(); ctx.moveTo(0, y50); ctx.lineTo(w, y50); ctx.stroke()

        // 0% baseline (bottom)
        var y0 = padTop + plotH
        ctx.beginPath(); ctx.moveTo(0, y0); ctx.lineTo(w, y0); ctx.stroke()

        ctx.restore()

        var days = tchart.days
        if (!days || days.length === 0) return

        var n = days.length
        var peakVal = tchart.peak > 0 ? tchart.peak : 1

        function dataY(v) {
          var clamped = Math.max(0, Math.min(peakVal, Number(v) || 0))
          return padTop + (1 - clamped / peakVal) * plotH
        }

        var pts = []
        for (var i = 0; i < n; i++) {
          var ptX = (n === 1) ? w : (i * w / (n - 1))
          pts.push({ x: ptX, y: dataY(days[i].messageCount) })
        }

        // Line and area fill
        if (pts.length > 1) {
          ctx.beginPath()
          ctx.moveTo(pts[0].x, pts[0].y)
          for (var j = 1; j < pts.length; j++) {
            ctx.lineTo(pts[j].x, pts[j].y)
          }
          ctx.strokeStyle = tchart.strokeColor
          ctx.lineWidth = 1.5
          ctx.setLineDash([])
          ctx.stroke()

          // Area fill down to baseline
          var lastPt = pts[pts.length - 1]
          ctx.lineTo(lastPt.x, y0)
          ctx.lineTo(pts[0].x, y0)
          ctx.closePath()
          ctx.fillStyle = tchart.fillColor
          ctx.fill()
        }

        // Faint vertical guide line at hovered point
        if (tchart.hoveredIndex >= 0 && tchart.hoveredIndex < pts.length) {
          var hPt = pts[tchart.hoveredIndex]
          ctx.beginPath()
          ctx.moveTo(hPt.x, padTop)
          ctx.lineTo(hPt.x, y0)
          ctx.strokeStyle = root.alpha(root.foreground, 0.25)
          ctx.lineWidth = 1
          ctx.setLineDash([])
          ctx.stroke()
        }

        // Small dot radius 2 at every point, last point dot radius 3
        for (var k = 0; k < pts.length; k++) {
          var r = (k === pts.length - 1) ? 3 : 2
          ctx.beginPath()
          ctx.arc(pts[k].x, pts[k].y, r, 0, Math.PI * 2)
          ctx.fillStyle = tchart.strokeColor
          ctx.fill()
        }

        // Radius 4 dot at hovered point
        if (tchart.hoveredIndex >= 0 && tchart.hoveredIndex < pts.length) {
          var hPt2 = pts[tchart.hoveredIndex]
          ctx.beginPath()
          ctx.arc(hPt2.x, hPt2.y, 4, 0, Math.PI * 2)
          ctx.fillStyle = tchart.strokeColor
          ctx.fill()
        }
      }

      // React to data / size changes
      Connections {
        target: tchart
        function onDaysChanged()         { chartCanvas.requestPaint() }
        function onPeakChanged()         { chartCanvas.requestPaint() }
        function onStrokeColorChanged()  { chartCanvas.requestPaint() }
        function onFillColorChanged()    { chartCanvas.requestPaint() }
        function onHoveredIndexChanged() { chartCanvas.requestPaint() }
      }
      onWidthChanged:  requestPaint()
      onHeightChanged: requestPaint()
      Component.onCompleted: requestPaint()
    }

    // Pill background behind the counter in the right gutter
    Rectangle {
      id: currentValuePill
      z: 1
      visible: currentValueText.text !== ""
      x: currentValueText.x
      y: currentValueText.y
      width: currentValueText.contentWidth + Style.space(8)
      height: currentValueText.height
      radius: height / 2
      color: root.alpha(tchart.strokeColor, 0.18)
    }

    // Current-value text overlay in the right gutter
    Text {
      id: currentValueText
      z: 2
      visible: text !== ""
      x: tchart.width - tchart._valueW
      width: tchart._valueW
      horizontalAlignment: Text.AlignLeft
      leftPadding: Style.space(4)
      rightPadding: Style.space(4)

      // Y coordinate of the last data point
      readonly property real _dataY: {
        var d = tchart.days
        if (!d || d.length === 0) return chartCanvas.height - tchart._padBot
        var last = Math.max(0, Math.min(tchart.peak, Number(d[d.length - 1].messageCount) || 0))
        var plotH = Math.max(0, chartCanvas.height - tchart._padTop - tchart._padBot)
        return tchart._padTop + (1 - (tchart.peak > 0 ? last / tchart.peak : 0)) * plotH
      }

      y: Math.max(0, Math.min(Math.max(0, chartCanvas.height - height), _dataY - height / 2))

      text: {
        var d = tchart.days
        if (!d || d.length === 0) return ""
        return usage.formatTokenCount(Number(d[d.length - 1].messageCount) || 0)
      }
      color: tchart.strokeColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    // Day labels bottom strip
    Item {
      id: axisStrip
      anchors.left: chartCanvas.left
      anchors.right: chartCanvas.right
      anchors.bottom: parent.bottom
      height: tchart._axisH

      Repeater {
        model: tchart.days

        Text {
          required property var modelData
          required property int index

          readonly property int n: tchart.days ? tchart.days.length : 0
          readonly property real ptX: n <= 1 ? axisStrip.width : (index * axisStrip.width / (n - 1))
          readonly property bool isToday: String(modelData.date) === root.todayDate()
          readonly property bool isHovered: tchart.hoveredIndex === index

          x: Math.round(ptX - width / 2)
          anchors.verticalCenter: parent.verticalCenter
          text: root.dayLabel(modelData.date, isToday)
          color: isHovered ? root.foreground : (isToday ? tchart.strokeColor : root.dim)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: isToday
        }
      }
    }

    // Mouse hover tracking over canvas
    MouseArea {
      id: chartMouse
      anchors.fill: chartCanvas
      hoverEnabled: true
      acceptedButtons: Qt.NoButton

      onPositionChanged: {
        var n = tchart.days ? tchart.days.length : 0
        if (n <= 0) {
          tchart.hoveredIndex = -1
          return
        }
        if (n === 1) {
          tchart.hoveredIndex = 0
          return
        }
        var step = width / (n - 1)
        var idx = Math.round(mouseX / step)
        tchart.hoveredIndex = Math.max(0, Math.min(n - 1, idx))
      }
      onExited: tchart.hoveredIndex = -1
    }

    PanelToolTip {
      visible: tchart.hoveredIndex >= 0
      text: tchart.hoveredDay
        ? root.dayTooltip(tchart.hoveredDay, String(tchart.hoveredDay.date) === root.todayDate())
        : ""
      fontFamily: root.fontFamily
    }
  }

  // Model rows read as a ranking table with badges, progress bars, and place colors.
  component ModelRow: Item {
    id: modelRow
    property var row: null
    property int rankIndex: 0
    property real share: 0

    readonly property color rankAccent: root.rankColor(rankIndex)
    readonly property color rankFill: root.rankFillColor(rankIndex)

    implicitHeight: modelName.implicitHeight + Style.spacing.lg * 2

    // Card background
    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.04)
    }

    // Rank-colored share bar fill
    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * root.clamp(modelRow.share, 0, 1)
      radius: Style.cornerRadius
      color: modelRow.rankFill

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    // Rank badge pill (e.g. 1, 2, 3, 4)
    Rectangle {
      id: rankBadge
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(22)
      height: Style.space(20)
      radius: Style.space(5)
      color: root.alpha(modelRow.rankAccent, 0.18)
      border.color: root.alpha(modelRow.rankAccent, 0.35)
      border.width: 1

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: (modelRow.rankIndex + 1)
        color: modelRow.rankAccent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    // Model name
    Text {
      id: modelName
      textFormat: Text.PlainText
      text: modelRow.row ? modelRow.row.name : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: modelRow.rankIndex === 0
      elide: Text.ElideRight
      anchors.left: rankBadge.right
      anchors.leftMargin: Style.space(10)
      anchors.right: modelTokens.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    // Model tokens value
    Text {
      id: modelTokens
      textFormat: Text.PlainText
      text: modelRow.row ? usage.formatTokenCount(modelRow.row.total) : ""
      color: modelRow.rankIndex === 0 ? modelRow.rankAccent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: modelHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: modelHover.containsMouse
      text: root.modelTooltip(modelRow.row)
      fontFamily: root.fontFamily
    }
  }
}
