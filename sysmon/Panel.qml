import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import qs.Commons
import qs.Ui

// System monitor popup: CPU breakdown, per-core meters, sparklines,
// memory & swap meters, top processes, and btop launcher.
// State lives in BarWidget.qml (hostWidget); this file renders it.
Panel {
  id: root
  moduleName: "rualisher.sysmon"
  ipcTarget: "rualisher.sysmon"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var h: hostWidget

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property color track: Qt.rgba(fg.r, fg.g, fg.b, 0.12)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function formatBytes(kb) {
    if (kb >= 1048576) {
      return (kb / 1048576).toFixed(1) + " GiB"
    }
    return Math.round(kb / 1024) + " MiB"
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: if (root.h) root.h.openBtop()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (!root.h) return
        if (t === "b" || t === "B") root.h.openBtop()
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

        Column {
          id: column
          width: scroll.width
          spacing: Style.space(12)

          // ---------------------------------------------------- 1. CPU SECTION
          PanelSectionHeader {
            text: "CPU"
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          // Top row: Big CPU % + Temp + MHz + Cores
          Row {
            width: parent.width
            spacing: Style.space(14)

            Text {
              text: (root.h ? Math.round(root.h.cpuPercent) : 0) + "%"
              color: (root.h && root.h.cpuPercent > 85) ? root.urgent : root.fg
              font.family: root.fontFamily
              font.pixelSize: 32
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Row {
                spacing: Style.space(8)

                Text {
                  visible: !!(root.h && root.h.hasTemp)
                  text: " " + (root.h ? Math.round(root.h.cpuTemp) : 0) + "°C"
                  color: (root.h && root.h.cpuTemp > 85) ? root.urgent : root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Text {
                  visible: !!(root.h && root.h.cpuFreqMhz > 0)
                  text: "󰓅 " + (root.h ? (root.h.cpuFreqMhz >= 1000 ? (root.h.cpuFreqMhz / 1000).toFixed(2) + " GHz" : root.h.cpuFreqMhz + " MHz") : "")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }

              Text {
                text: (root.h ? root.h.coreCount : 0) + " threads"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // CPU Sparkline (60 samples)
          Item {
            width: parent.width
            height: Style.space(96)

            Sparkline {
              anchors.fill: parent
              values: root.h ? root.h.cpuHistory : []
              strokeColor: (root.h && root.h.cpuPercent > 85) ? root.urgent : root.accent
              fillColor: Qt.rgba(strokeColor.r, strokeColor.g, strokeColor.b, 0.15)
            }
          }

          // Per-core horizontal bars with % (2 columns)
          Grid {
            id: coreGrid
            width: parent.width
            columns: 2
            columnSpacing: Style.space(12)
            rowSpacing: Style.space(6)

            readonly property real itemWidth: (width - columnSpacing) / 2

            Repeater {
              model: root.h ? root.h.corePercents : []

              Item {
                required property var modelData
                required property int index

                width: coreGrid.itemWidth
                height: Style.space(16)

                Text {
                  id: coreLabel
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(26)
                  text: "C" + index
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  id: coreValText
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(32)
                  horizontalAlignment: Text.AlignRight
                  text: modelData + "%"
                  color: modelData > 85 ? root.urgent : root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: modelData > 85
                }

                // Bar track
                Rectangle {
                  anchors.left: coreLabel.right
                  anchors.right: coreValText.left
                  anchors.leftMargin: Style.space(4)
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(6)
                  radius: height / 2
                  color: root.track

                  Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    radius: parent.radius
                    width: parent.width * Math.max(0, Math.min(1, modelData / 100))
                    color: modelData > 85 ? root.urgent : root.accent

                    Behavior on width {
                      NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                  }
                }
              }
            }
          }

          // Row with load average 1/5/15 and uptime
          Row {
            width: parent.width
            spacing: Style.space(12)

            Item {
              width: (parent.width - parent.spacing) / 2
              height: Style.space(20)

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Load"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.h ? (root.h.load1.toFixed(2) + "  " + root.h.load5.toFixed(2) + "  " + root.h.load15.toFixed(2)) : "—"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Item {
              width: (parent.width - parent.spacing) / 2
              height: Style.space(20)

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Uptime"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.h ? root.h.formatUptime(root.h.uptimeSec) : "—"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }

          // ---------------------------------------------------- GPU SECTION
          PanelSeparator {
            visible: !!(root.h && root.h.hasGpu)
            foreground: root.fg
          }

          PanelSectionHeader {
            visible: !!(root.h && root.h.hasGpu)
            text: "GPU"
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          // Top row: Big GPU % + Freq + GPU Name
          Row {
            id: gpuTopRow
            visible: !!(root.h && root.h.hasGpu)
            width: parent.width
            spacing: Style.space(14)

            Text {
              id: bigGpuPercent
              text: (root.h ? Math.round(root.h.gpuPercent) : 0) + "%"
              color: (root.h && root.h.gpuPercent > 90) ? root.urgent : root.fg
              font.family: root.fontFamily
              font.pixelSize: 32
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(0, parent.width - bigGpuPercent.width - parent.spacing)
              spacing: Style.space(2)

              Text {
                visible: !!(root.h && (root.h.gpuFreqMhz > 0 || root.h.gpuMaxFreqMhz > 0))
                text: {
                  if (!root.h) return ""
                  var act = Math.round(root.h.gpuFreqMhz)
                  var max = Math.round(root.h.gpuMaxFreqMhz)
                  if (max > 0) return "󰓅 " + act + " / " + max + " MHz"
                  if (act > 0) return "󰓅 " + act + " MHz"
                  return ""
                }
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                width: parent.width
                text: { var n = root.h ? (root.h.gpuName || "GPU") : "GPU"; var m = n.match(/\[([^\]]+)\]/); return m ? m[1] : n }
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }

          // GPU Sparkline (60 samples)
          Item {
            visible: !!(root.h && root.h.hasGpu)
            width: parent.width
            height: Style.space(96)

            Sparkline {
              anchors.fill: parent
              values: root.h ? root.h.gpuHistory : []
              strokeColor: (root.h && root.h.gpuPercent > 90) ? root.urgent : root.accent
              fillColor: Qt.rgba(strokeColor.r, strokeColor.g, strokeColor.b, 0.15)
            }
          }

          // VRAM used / total bar (only if gpuVramTotal > 0)
          Column {
            visible: !!(root.h && root.h.hasGpu && root.h.gpuVramTotal > 0)
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              height: Style.space(16)

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "VRAM"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: {
                  if (!root.h || root.h.gpuVramTotal <= 0) return ""
                  var u = root.formatBytes(root.h.gpuVramUsed / 1024)
                  var t = root.formatBytes(root.h.gpuVramTotal / 1024)
                  var pct = Math.round((root.h.gpuVramUsed / root.h.gpuVramTotal) * 100)
                  return u + " / " + t + " (" + pct + "%)"
                }
                color: (root.h && root.h.gpuVramTotal > 0 && (root.h.gpuVramUsed / root.h.gpuVramTotal > 0.9)) ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Rectangle {
              width: parent.width
              height: Style.space(6)
              radius: height / 2
              color: root.track

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                radius: parent.radius
                width: parent.width * (root.h && root.h.gpuVramTotal > 0 ? Math.max(0, Math.min(1, root.h.gpuVramUsed / root.h.gpuVramTotal)) : 0)
                color: (root.h && root.h.gpuVramTotal > 0 && (root.h.gpuVramUsed / root.h.gpuVramTotal > 0.9)) ? root.urgent : root.accent

                Behavior on width {
                  NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
              }
            }
          }

          // ---------------------------------------------------- 2. MEMORY SECTION
          PanelSeparator {
            foreground: root.fg
          }

          PanelSectionHeader {
            text: "MEMORY"
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          // RAM: used / total GiB with a bar
          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              height: Style.space(18)

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "RAM"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.h ? (root.formatBytes(root.h.memUsed) + " / " + root.formatBytes(root.h.memTotal) + " (" + Math.round(root.h.ramPercent) + "%)") : "—"
                color: (root.h && root.h.ramPercent > 90) ? root.urgent : root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            // RAM bar
            Rectangle {
              width: parent.width
              height: Style.space(8)
              radius: height / 2
              color: root.track

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                radius: parent.radius
                width: parent.width * (root.h ? Math.max(0, Math.min(1, root.h.ramPercent / 100)) : 0)
                color: (root.h && root.h.ramPercent > 90) ? root.urgent : root.accent

                Behavior on width {
                  NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
              }
            }
          }

          // Available, cached, buffers
          Row {
            width: parent.width
            spacing: Style.space(8)

            Item {
              width: (parent.width - parent.spacing * 2) / 3
              height: Style.space(20)

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Avail"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.h ? root.formatBytes(root.h.memAvailable) : "—"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Item {
              width: (parent.width - parent.spacing * 2) / 3
              height: Style.space(20)

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Cached"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.h ? root.formatBytes(root.h.memCached) : "—"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Item {
              width: (parent.width - parent.spacing * 2) / 3
              height: Style.space(20)

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Buffers"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.h ? root.formatBytes(root.h.memBuffers) : "—"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // Swap used / total bar
          Column {
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              height: Style.space(16)

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Swap"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.h && root.h.swapTotal > 0
                  ? (root.formatBytes(root.h.swapUsed) + " / " + root.formatBytes(root.h.swapTotal) + " (" + Math.round(root.h.swapPercent) + "%)")
                  : "None"
                color: (root.h && root.h.swapPercent > 90) ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Rectangle {
              visible: !!(root.h && root.h.swapTotal > 0)
              width: parent.width
              height: Style.space(6)
              radius: height / 2
              color: root.track

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                radius: parent.radius
                width: parent.width * (root.h ? Math.max(0, Math.min(1, root.h.swapPercent / 100)) : 0)
                color: (root.h && root.h.swapPercent > 90) ? root.urgent : root.accent

                Behavior on width {
                  NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
              }
            }
          }

          // RAM Sparkline (60 samples)
          Item {
            width: parent.width
            height: Style.space(96)

            Sparkline {
              anchors.fill: parent
              values: root.h ? root.h.ramHistory : []
              strokeColor: (root.h && root.h.ramPercent > 90) ? root.urgent : root.accent
              fillColor: Qt.rgba(strokeColor.r, strokeColor.g, strokeColor.b, 0.15)
            }
          }

          // ---------------------------------------------------- 3. TOP PROCESSES
          PanelSeparator {
            foreground: root.fg
          }

          PanelSectionHeader {
            text: "TOP PROCESSES"
            foreground: root.fg
            fontFamily: root.fontFamily
          }

          Row {
            id: procRow
            width: parent.width
            spacing: Style.space(12)

            readonly property real colWidth: (width - spacing) / 2

            // By CPU column
            Column {
              width: procRow.colWidth
              spacing: Style.space(4)

              Item {
                width: parent.width
                height: Style.space(16)

                Text {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "By CPU"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Text {
                  anchors.right: cpuRssHdr.left
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(42)
                  horizontalAlignment: Text.AlignRight
                  text: "%CPU"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  id: cpuRssHdr
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(58)
                  horizontalAlignment: Text.AlignRight
                  text: "RSS"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Repeater {
                model: root.h ? root.h.topCpuProcesses : []

                Item {
                  required property var modelData
                  width: parent.width
                  height: Style.space(18)

                  Text {
                    anchors.left: parent.left
                    anchors.right: cpuVal.left
                    anchors.rightMargin: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  Text {
                    id: cpuVal
                    anchors.right: rssVal.left
                    anchors.rightMargin: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(42)
                    horizontalAlignment: Text.AlignRight
                    text: modelData.cpuText
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    id: rssVal
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(58)
                    horizontalAlignment: Text.AlignRight
                    text: modelData.rssText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            // By Memory column
            Column {
              width: procRow.colWidth
              spacing: Style.space(4)

              Item {
                width: parent.width
                height: Style.space(16)

                Text {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "By Memory"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Text {
                  anchors.right: memRssHdr.left
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(42)
                  horizontalAlignment: Text.AlignRight
                  text: "%CPU"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  id: memRssHdr
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(58)
                  horizontalAlignment: Text.AlignRight
                  text: "RSS"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Repeater {
                model: root.h ? root.h.topMemProcesses : []

                Item {
                  required property var modelData
                  width: parent.width
                  height: Style.space(18)

                  Text {
                    anchors.left: parent.left
                    anchors.right: cpuVal2.left
                    anchors.rightMargin: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  Text {
                    id: cpuVal2
                    anchors.right: rssVal2.left
                    anchors.rightMargin: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(42)
                    horizontalAlignment: Text.AlignRight
                    text: modelData.cpuText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    id: rssVal2
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(58)
                    horizontalAlignment: Text.AlignRight
                    text: modelData.rssText
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }
            }
          }

          // ---------------------------------------------------- 4. FOOTER
          PanelSeparator {
            foreground: root.fg
          }

          Button {
            width: parent.width
            text: "Open btop"
            iconText: "󰓅"
            bordered: true
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.body
            onClicked: {
              if (root.h) root.h.openBtop()
              root.close()
            }
          }
        }
      }
    }
  }

  // Sparkline component — canvas chart + Y-axis labels + current value overlay
  component Sparkline: Item {
    id: spark
    property var values: []
    property color strokeColor: Color.accent
    property color fillColor: Qt.rgba(strokeColor.r, strokeColor.g, strokeColor.b, 0.15)
    property real maxVal: 100

    // Width reserved for the Y-axis label column
    readonly property real _labelW: Style.space(30)
    // Width reserved for the current-value gutter on the right
    readonly property real _valueW: Style.space(40)
    // Vertical padding inside the plot canvas so lines/text have room
    readonly property real _padTop: 4
    readonly property real _padBot: 4

    // Y-axis labels on the left
    Text {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.topMargin: spark._padTop - 1
      width: spark._labelW
      horizontalAlignment: Text.AlignRight
      text: "100%"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: spark._labelW
      horizontalAlignment: Text.AlignRight
      text: "50%"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.bottomMargin: spark._padBot - 1
      width: spark._labelW
      horizontalAlignment: Text.AlignRight
      text: "0%"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    // The canvas occupies the area to the right of the label column
    Canvas {
      id: sparkCanvas
      anchors.left: parent.left
      anchors.leftMargin: spark._labelW + Style.space(4)
      anchors.right: parent.right
      anchors.rightMargin: spark._valueW + Style.space(4)
      anchors.top: parent.top
      anchors.bottom: parent.bottom

      antialiasing: true

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var w = width
        var h = height
        if (w <= 0 || h <= 0) return

        var padTop = spark._padTop
        var padBot = spark._padBot
        var plotH  = h - padTop - padBot   // usable pixel height for data

        var gridAlpha = Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.09)

        // --- Faint dashed grid lines at 0%, 50%, 100%
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

        // 0% baseline
        var y0 = padTop + plotH
        ctx.beginPath(); ctx.moveTo(0, y0); ctx.lineTo(w, y0); ctx.stroke()

        ctx.restore()

        var vals = spark.values
        if (!vals || vals.length < 2) return

        var n = vals.length
        var maxPoints = 60
        var step = w / (maxPoints - 1)
        var xOffset = (maxPoints - n) * step

        // Helper: data value → canvas Y
        function dataY(v) {
          var clamped = Math.max(0, Math.min(spark.maxVal, Number(v) || 0))
          return padTop + (1 - clamped / spark.maxVal) * plotH
        }

        // Build points array (reused for line + fill + overlay)
        var pts = []
        for (var i = 0; i < n; i++) {
          pts.push({ x: xOffset + i * step, y: dataY(vals[i]) })
        }

        // Sparkline line
        ctx.beginPath()
        ctx.moveTo(pts[0].x, pts[0].y)
        for (var j = 1; j < pts.length; j++) {
          ctx.lineTo(pts[j].x, pts[j].y)
        }
        ctx.strokeStyle = spark.strokeColor
        ctx.lineWidth = 1.5
        ctx.setLineDash([])
        ctx.stroke()

        // Area fill down to baseline
        var lastPt = pts[pts.length - 1]
        ctx.lineTo(lastPt.x, y0)
        ctx.lineTo(pts[0].x, y0)
        ctx.closePath()
        ctx.fillStyle = spark.fillColor
        ctx.fill()

        // Dot at the last data point
        ctx.beginPath()
        ctx.arc(lastPt.x, lastPt.y, 2.5, 0, Math.PI * 2)
        ctx.fillStyle = spark.strokeColor
        ctx.fill()
      }

      // React to data / size changes
      Connections {
        target: spark
        function onValuesChanged()     { sparkCanvas.requestPaint() }
        function onStrokeColorChanged(){ sparkCanvas.requestPaint() }
        function onFillColorChanged()  { sparkCanvas.requestPaint() }
      }
      onWidthChanged:  requestPaint()
      onHeightChanged: requestPaint()
      Component.onCompleted: requestPaint()
    }

    // Pill background behind the counter
    Rectangle {
      id: currentValuePill
      z: 1
      visible: currentValueText.text !== ""
      x: currentValueText.x
      y: currentValueText.y
      width: currentValueText.contentWidth + Style.space(8)
      height: currentValueText.height
      radius: height / 2
      color: Qt.rgba(spark.strokeColor.r, spark.strokeColor.g, spark.strokeColor.b, 0.18)
    }

    // Current-value text overlay in the right gutter
    Text {
      id: currentValueText
      z: 2
      x: spark.width - spark._valueW
      width: spark._valueW
      horizontalAlignment: Text.AlignLeft
      leftPadding: Style.space(4)
      rightPadding: Style.space(4)

      // Y coordinate of the last data point (0 = top of item)
      readonly property real _dataY: {
        var vals = spark.values
        if (!vals || vals.length === 0) return spark.height - spark._padBot
        var last = Math.max(0, Math.min(spark.maxVal, Number(vals[vals.length - 1]) || 0))
        var plotH = spark.height - spark._padTop - spark._padBot
        return spark._padTop + (1 - last / spark.maxVal) * plotH
      }

      y: Math.max(0, Math.min(spark.height - height, _dataY - height / 2))

      text: {
        var vals = spark.values
        if (!vals || vals.length === 0) return ""
        return Math.round(Number(vals[vals.length - 1]) || 0) + "%"
      }
      color: spark.strokeColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }
}
