import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// System monitor bar widget: CPU %, CPU temperature, RAM %, load averages,
// and sparklines. State lives here; Panel.qml is the popup host.
//
// Bar: left click = toggle popup · right click = open btop
BarWidget {
  id: root
  moduleName: "rualisher.sysmon"

  // ---- System metrics state
  property real cpuPercent: 0
  property var corePercents: []
  property int coreCount: 0
  property var cpuHistory: []
  property real cpuFreqMhz: 0
  property real cpuTemp: 0
  property bool hasTemp: false

  property real load1: 0
  property real load5: 0
  property real load15: 0
  property real uptimeSec: 0

  property real memTotal: 0
  property real memAvailable: 0
  property real memUsed: 0
  property real memCached: 0
  property real memBuffers: 0
  property real ramPercent: 0
  property var ramHistory: []

  property real swapTotal: 0
  property real swapFree: 0
  property real swapUsed: 0
  property real swapPercent: 0

  // Top processes (polled only while popup is open)
  property var topCpuProcesses: []
  property var topMemProcesses: []

  // Internal state for deltas
  property real _prevTotal: 0
  property real _prevBusy: 0
  property var _prevCores: ({})
  property string tempPath: ""

  // GPU metrics state
  property bool hasGpu: false
  property string gpuName: ""
  property real gpuPercent: 0
  property real gpuFreqMhz: 0
  property real gpuMaxFreqMhz: 0
  property real gpuVramUsed: 0
  property real gpuVramTotal: 0
  property var gpuHistory: []
  property real _prevRc6: -1
  property real _prevRc6Time: 0
  property string gpuPath: ""

  // Icons
  readonly property string cpuIcon: ""
  readonly property string tempIcon: ""
  readonly property string gpuIcon: "󰢮"
  readonly property string ramIcon: "󰘚"

  // Warning thresholds: CPU > 85%, RAM > 90%, temp > 85°C, GPU > 90%
  readonly property bool isWarning: cpuPercent > 85 || ramPercent > 90 || (hasTemp && cpuTemp > 85) || (hasGpu && gpuPercent > 90)
  readonly property color warningColor: bar ? bar.urgent : Color.urgent

  readonly property string horizontalText: {
    var str = cpuIcon + " " + Math.round(cpuPercent) + "%"
    if (hasGpu) str += " " + gpuIcon + " " + Math.round(gpuPercent) + "%"
    str += " " + ramIcon + " " + Math.round(ramPercent) + "%"
    return str
  }

  readonly property var verticalLines: {
    var lines = [cpuIcon + " " + Math.round(cpuPercent) + "%"]
    if (hasGpu) lines.push(gpuIcon + " " + Math.round(gpuPercent) + "%")
    lines.push(ramIcon + " " + Math.round(ramPercent) + "%")
    return lines
  }

  readonly property string tooltipStr: {
    var usedGiB = (memUsed / 1048576).toFixed(1)
    var totalGiB = (memTotal / 1048576).toFixed(1)
    var str = "CPU " + Math.round(cpuPercent) + "%"
    if (hasGpu) str += " · GPU " + Math.round(gpuPercent) + "%"
    str += " · load " + load1.toFixed(2) + " " + load5.toFixed(2) + " " + load15.toFixed(2) + " · RAM " + usedGiB + "/" + totalGiB + " GiB"
    return str
  }

  function formatUptime(sec) {
    var d = Math.floor(sec / 86400)
    var h = Math.floor((sec % 86400) / 3600)
    var m = Math.floor((sec % 3600) / 60)
    if (d > 0) return d + "d " + h + "h " + m + "m"
    if (h > 0) return h + "h " + m + "m"
    return m + "m"
  }

  function openBtop() {
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy-launch-or-focus-tui btop")
    }
  }

  // ---------------------------------------------------------------- Data Polling

  // Startup resolution of hwmon path for CPU temperature and GPU card resolution
  Process {
    id: hwmonInitProcess
    running: true
    command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do [ -f \"$h/name\" ] || continue; n=$(cat \"$h/name\" 2>/dev/null); if [ \"$n\" = \"coretemp\" ] && [ -f \"$h/temp1_input\" ]; then t=\"$h/temp1_input\"; break; fi; if [ \"$n\" = \"acpitz\" ] && [ -z \"$acp\" ] && [ -f \"$h/temp1_input\" ]; then acp=\"$h/temp1_input\"; fi; done; [ -z \"$t\" ] && [ -n \"$acp\" ] && t=\"$acp\"; [ -n \"$t\" ] && echo \"TEMP=$t\"; for c in /sys/class/drm/card[0-9]*; do [ -d \"$c\" ] || continue; b=${c##*/}; case \"$b\" in *-*) continue ;; esac; if [ -f \"$c/gt_act_freq_mhz\" ] || [ -f \"$c/device/gpu_busy_percent\" ]; then gpu=\"$c\"; break; fi; done; if [ -n \"$gpu\" ]; then echo \"GPU=$gpu\"; slot=$(sed -n 's/^PCI_SLOT_NAME=//p' \"$gpu/device/uevent\" 2>/dev/null); if [ -n \"$slot\" ]; then gname=$(lspci -s \"$slot\" 2>/dev/null | head -n1 | sed -E -e 's/^[0-9a-fA-F:.]+ [^:]+: //' -e 's/ *\\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\\]//g' -e 's/ \\(rev [0-9a-fA-F]+\\)$//'); fi; [ -n \"$gname\" ] && echo \"GPUNAME=$gname\"; fi"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim()
          if (!line) continue
          if (line.indexOf("TEMP=") === 0) {
            root.tempPath = line.substring(5).trim()
          } else if (line.indexOf("GPU=") === 0) {
            root.gpuPath = line.substring(4).trim()
            root.hasGpu = root.gpuPath.length > 0
          } else if (line.indexOf("GPUNAME=") === 0) {
            root.gpuName = line.substring(8).trim()
          } else if (!root.tempPath && line.indexOf("/") === 0) {
            root.tempPath = line
          }
        }
      }
    }
  }

  // Periodic metrics sampler (every 2s via a single Process)
  Process {
    id: sampleProcess
    running: false
    command: ["sh", "-c", "cat /proc/stat; echo '---SECTION---'; cat /proc/loadavg; echo '---SECTION---'; cat /proc/meminfo; echo '---SECTION---'; cat /proc/uptime; echo '---SECTION---'; cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null || true; echo '---SECTION---'; if [ -n \"$1\" ] && [ -f \"$1\" ]; then cat \"$1\"; else echo ''; fi; echo '---SECTION---'; if [ -n \"$2\" ] && [ -d \"$2\" ]; then g=\"$2\"; out=\"\"; [ -f \"$g/gt_act_freq_mhz\" ] && out=\"${out}act=$(cat \"$g/gt_act_freq_mhz\" 2>/dev/null) \"; [ -f \"$g/gt_max_freq_mhz\" ] && out=\"${out}max=$(cat \"$g/gt_max_freq_mhz\" 2>/dev/null) \"; [ -f \"$g/power/rc6_residency_ms\" ] && out=\"${out}rc6=$(cat \"$g/power/rc6_residency_ms\" 2>/dev/null) \"; [ -f \"$g/device/gpu_busy_percent\" ] && out=\"${out}busy=$(cat \"$g/device/gpu_busy_percent\" 2>/dev/null) \"; [ -f \"$g/device/mem_info_vram_used\" ] && out=\"${out}vused=$(cat \"$g/device/mem_info_vram_used\" 2>/dev/null) \"; [ -f \"$g/device/mem_info_vram_total\" ] && out=\"${out}vtotal=$(cat \"$g/device/mem_info_vram_total\" 2>/dev/null) \"; echo \"$out\"; else echo ''; fi", "sampler", root.tempPath, root.gpuPath]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseSample(text)
    }
  }

  Timer {
    id: sampleTimer
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!sampleProcess.running) {
        sampleProcess.command = ["sh", "-c", "cat /proc/stat; echo '---SECTION---'; cat /proc/loadavg; echo '---SECTION---'; cat /proc/meminfo; echo '---SECTION---'; cat /proc/uptime; echo '---SECTION---'; cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null || true; echo '---SECTION---'; if [ -n \"$1\" ] && [ -f \"$1\" ]; then cat \"$1\"; else echo ''; fi; echo '---SECTION---'; if [ -n \"$2\" ] && [ -d \"$2\" ]; then g=\"$2\"; out=\"\"; [ -f \"$g/gt_act_freq_mhz\" ] && out=\"${out}act=$(cat \"$g/gt_act_freq_mhz\" 2>/dev/null) \"; [ -f \"$g/gt_max_freq_mhz\" ] && out=\"${out}max=$(cat \"$g/gt_max_freq_mhz\" 2>/dev/null) \"; [ -f \"$g/power/rc6_residency_ms\" ] && out=\"${out}rc6=$(cat \"$g/power/rc6_residency_ms\" 2>/dev/null) \"; [ -f \"$g/device/gpu_busy_percent\" ] && out=\"${out}busy=$(cat \"$g/device/gpu_busy_percent\" 2>/dev/null) \"; [ -f \"$g/device/mem_info_vram_used\" ] && out=\"${out}vused=$(cat \"$g/device/mem_info_vram_used\" 2>/dev/null) \"; [ -f \"$g/device/mem_info_vram_total\" ] && out=\"${out}vtotal=$(cat \"$g/device/mem_info_vram_total\" 2>/dev/null) \"; echo \"$out\"; else echo ''; fi", "sampler", root.tempPath, root.gpuPath]
        sampleProcess.running = true
      }
    }
  }

  function parseSample(text) {
    if (!text) return
    var sections = String(text).split("\n---SECTION---\n")
    if (sections.length < 6) return

    // Section 0: /proc/stat
    var statLines = sections[0].split("\n")
    var newCorePercents = []
    for (var i = 0; i < statLines.length; i++) {
      var line = statLines[i].trim()
      if (!line) continue
      var parts = line.split(/\s+/)
      var name = parts[0]
      if (name === "cpu") {
        var user = Number(parts[1]) || 0
        var nice = Number(parts[2]) || 0
        var sys = Number(parts[3]) || 0
        var idle = Number(parts[4]) || 0
        var iowait = Number(parts[5]) || 0
        var irq = Number(parts[6]) || 0
        var softirq = Number(parts[7]) || 0
        var steal = Number(parts[8]) || 0
        var total = user + nice + sys + idle + iowait + irq + softirq + steal
        var busy = total - idle - iowait

        if (_prevTotal > 0 && total > _prevTotal) {
          var dTotal = total - _prevTotal
          var dBusy = busy - _prevBusy
          root.cpuPercent = dTotal > 0 ? Math.max(0, Math.min(100, (dBusy / dTotal) * 100)) : 0
        }
        _prevTotal = total
        _prevBusy = busy
      } else if (/^cpu\d+$/.test(name)) {
        var coreIdx = parseInt(name.substring(3), 10)
        var cu = Number(parts[1]) || 0
        var cn = Number(parts[2]) || 0
        var cs = Number(parts[3]) || 0
        var cid = Number(parts[4]) || 0
        var cio = Number(parts[5]) || 0
        var cir = Number(parts[6]) || 0
        var csi = Number(parts[7]) || 0
        var cst = Number(parts[8]) || 0
        var cTotal = cu + cn + cs + cid + cio + cir + csi + cst
        var cBusy = cTotal - cid - cio

        var corePct = 0
        if (_prevCores[coreIdx] && cTotal > _prevCores[coreIdx].total) {
          var cdTotal = cTotal - _prevCores[coreIdx].total
          var cdBusy = cBusy - _prevCores[coreIdx].busy
          corePct = cdTotal > 0 ? Math.max(0, Math.min(100, (cdBusy / cdTotal) * 100)) : 0
        }
        _prevCores[coreIdx] = { total: cTotal, busy: cBusy }
        newCorePercents[coreIdx] = Math.round(corePct)
      }
    }
    if (newCorePercents.length > 0) {
      root.corePercents = newCorePercents
      root.coreCount = newCorePercents.length
    }

    // History: last 60 CPU samples
    var newCpuHist = root.cpuHistory.slice()
    newCpuHist.push(root.cpuPercent)
    if (newCpuHist.length > 60) newCpuHist.shift()
    root.cpuHistory = newCpuHist

    // Section 1: /proc/loadavg
    var loadParts = sections[1].trim().split(/\s+/)
    if (loadParts.length >= 3) {
      root.load1 = parseFloat(loadParts[0]) || 0
      root.load5 = parseFloat(loadParts[1]) || 0
      root.load15 = parseFloat(loadParts[2]) || 0
    }

    // Section 2: /proc/meminfo
    var memLines = sections[2].split("\n")
    var memMap = {}
    for (var m = 0; m < memLines.length; m++) {
      var match = memLines[m].match(/^([A-Za-z0-9_()]+):\s*(\d+)/)
      if (match) memMap[match[1]] = Number(match[2])
    }
    var mTotal = memMap["MemTotal"] || 0
    var mAvail = memMap["MemAvailable"] || 0
    var mUsed = Math.max(0, mTotal - mAvail)
    var mCached = memMap["Cached"] || 0
    var mBuffers = memMap["Buffers"] || 0
    var sTotal = memMap["SwapTotal"] || 0
    var sFree = memMap["SwapFree"] || 0
    var sUsed = Math.max(0, sTotal - sFree)

    root.memTotal = mTotal
    root.memAvailable = mAvail
    root.memUsed = mUsed
    root.memCached = mCached
    root.memBuffers = mBuffers
    root.swapTotal = sTotal
    root.swapFree = sFree
    root.swapUsed = sUsed
    root.ramPercent = mTotal > 0 ? (mUsed / mTotal) * 100 : 0
    root.swapPercent = sTotal > 0 ? (sUsed / sTotal) * 100 : 0

    // History: last 60 RAM samples
    var newRamHist = root.ramHistory.slice()
    newRamHist.push(root.ramPercent)
    if (newRamHist.length > 60) newRamHist.shift()
    root.ramHistory = newRamHist

    // Section 3: /proc/uptime
    var upParts = sections[3].trim().split(/\s+/)
    if (upParts.length > 0) {
      root.uptimeSec = Math.floor(parseFloat(upParts[0]) || 0)
    }

    // Section 4: CPU frequency
    var freqLines = sections[4].trim().split("\n")
    var fSum = 0, fCount = 0
    for (var f = 0; f < freqLines.length; f++) {
      var freqKhz = Number(freqLines[f].trim())
      if (isFinite(freqKhz) && freqKhz > 0) {
        fSum += freqKhz
        fCount++
      }
    }
    root.cpuFreqMhz = fCount > 0 ? Math.round(fSum / fCount / 1000) : 0

    // Section 5: CPU temp
    var rawTemp = sections[5].trim()
    var tempNum = Number(rawTemp)
    if (rawTemp !== "" && isFinite(tempNum) && tempNum > 0) {
      root.hasTemp = true
      root.cpuTemp = Math.round(tempNum / 1000)
    } else {
      root.hasTemp = false
      root.cpuTemp = 0
    }

    // Section 6: GPU stats
    if (sections.length >= 7 && root.hasGpu) {
      var gpuRaw = sections[6].trim()
      var gpuTokens = gpuRaw ? gpuRaw.split(/\s+/) : []
      var gpuMap = {}
      for (var gi = 0; gi < gpuTokens.length; gi++) {
        var eqIdx = gpuTokens[gi].indexOf("=")
        if (eqIdx !== -1) {
          gpuMap[gpuTokens[gi].substring(0, eqIdx)] = gpuTokens[gi].substring(eqIdx + 1)
        }
      }

      if (gpuMap["act"] !== undefined) {
        root.gpuFreqMhz = parseFloat(gpuMap["act"]) || 0
      }
      if (gpuMap["max"] !== undefined) {
        root.gpuMaxFreqMhz = parseFloat(gpuMap["max"]) || 0
      }

      var now = Date.now()
      if (gpuMap["busy"] !== undefined) {
        var busyVal = parseFloat(gpuMap["busy"])
        if (isFinite(busyVal)) {
          root.gpuPercent = Math.max(0, Math.min(100, busyVal))
        }
      } else if (gpuMap["rc6"] !== undefined) {
        var rc6 = parseFloat(gpuMap["rc6"])
        if (isFinite(rc6)) {
          if (root._prevRc6 >= 0 && root._prevRc6Time > 0 && now > root._prevRc6Time) {
            var dRc6 = rc6 - root._prevRc6
            var dWall = now - root._prevRc6Time
            if (dWall > 0) {
              var busyPct = 100 * (1 - (dRc6 / dWall))
              root.gpuPercent = Math.max(0, Math.min(100, busyPct))
            }
          }
          root._prevRc6 = rc6
          root._prevRc6Time = now
        }
      }

      if (gpuMap["vused"] !== undefined) {
        root.gpuVramUsed = parseFloat(gpuMap["vused"]) || 0
      }
      if (gpuMap["vtotal"] !== undefined) {
        root.gpuVramTotal = parseFloat(gpuMap["vtotal"]) || 0
      }

      // History: last 60 GPU samples
      var newGpuHist = root.gpuHistory.slice()
      newGpuHist.push(root.gpuPercent)
      if (newGpuHist.length > 60) newGpuHist.shift()
      root.gpuHistory = newGpuHist
    }
  }

  // ------------------------------------------------------------- Top Processes
  // Sampled ONLY while the popup is open
  Process {
    id: topProcess
    running: false
    command: ["sh", "-c", "ps -eo pid,comm,%cpu,rss --sort=-%cpu --no-headers | head -6; echo '---SECTION---'; ps -eo pid,comm,%cpu,rss --sort=-rss --no-headers | head -6"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseTopProcesses(text)
    }
  }

  Timer {
    id: topTimer
    interval: 2000
    running: root.opened
    repeat: true
    onTriggered: {
      if (root.opened && !topProcess.running) {
        topProcess.running = true
      }
    }
  }

  onOpenedChanged: {
    if (opened && !topProcess.running) {
      topProcess.running = true
    }
  }

  function parseTopProcesses(text) {
    if (!text) return
    var sections = String(text).split("\n---SECTION---\n")
    if (sections.length < 2) return
    root.topCpuProcesses = parsePsSection(sections[0])
    root.topMemProcesses = parsePsSection(sections[1])
  }

  function parsePsSection(raw) {
    var lines = String(raw || "").split("\n")
    var result = []
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var tokens = line.split(/\s+/)
      if (tokens.length < 4) continue
      var pid = tokens[0]
      var rss = parseInt(tokens[tokens.length - 1], 10) || 0
      var cpu = parseFloat(tokens[tokens.length - 2]) || 0
      var comm = tokens.slice(1, -2).join(" ")
      result.push({
        pid: pid,
        name: comm,
        cpu: cpu,
        rss: rss,
        cpuText: cpu.toFixed(1) + "%",
        rssText: formatRss(rss)
      })
    }
    return result
  }

  function formatRss(kb) {
    if (kb >= 1048576) {
      return (kb / 1048576).toFixed(1) + " GiB"
    }
    return Math.round(kb / 1024) + " MiB"
  }

  // ------------------------------------------------------------- Popup Host Contract
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "rualisher.sysmon"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  // ------------------------------------------------------------- Bar UI
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.horizontalText
    labelVisible: !root.vertical
    hasVisualContent: true
    active: root.isWarning
    activeColor: root.warningColor
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.tooltipStr

    onPressed: function(b) {
      if (b === Qt.RightButton) root.openBtop()
      else root.togglePanel()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: button.fontSize
          color: root.isWarning ? button.activeColor : button.foreground
        }
      }
    }
  }
}
