import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Converter.js" as Conv

Panel {
    id: root
    moduleName: "io.github.nixsh5.convertio"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null

    function open() {
        root.controller.show()
    }

    function close() {
        root.controller.hide()
    }

    function switchPanel(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root.hostWidget || root, direction)
        return false
    }

    function pasteFromClipboard() {
        clipProc.running = true
    }

    readonly property color foreground: root.barForeground
    readonly property color dim: Qt.darker(foreground, 1.55)
    readonly property color borderColor: Util.alpha(foreground, 0.22)
    readonly property color cardFill: Util.alpha(foreground, 0.08)
    readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

    property string selectedFile: ""
    property string fileSizeText: "--"
    property real fileBytes: 0
    property real mediaDurationSec: 0
    property string targetFormat: ""
    property bool keepOriginal: true
    property bool converting: false
    property string statusLine: "DROP OR PICK A FILE"
    property string lastOutputPath: ""

    // Engine installation state
    property var installedEngines: ({})
    property string missingPackagesList: ""
    property bool installingDeps: false
    readonly property bool engineReady: !plan || installedEngines[plan.engine] === true
    readonly property string missingPackage: plan ? Conv.getPackageForEngine(plan.engine) : ""

    // GPU Hardware Acceleration state
    property string detectedHwAccel: "cpu"
    property bool useGpu: true
    readonly property string activeHwAccel: useGpu ? detectedHwAccel : "cpu"

    // Live ETA & Progress tracking
    property double startTimeMs: 0
    property real elapsedSec: 0
    property real estimatedTotalSec: 0
    property real etaRemainingSec: -1
    property real progressRatio: 0
    property bool hasExactProgress: false

    readonly property string srcExt: Conv.getExtension(selectedFile)
    readonly property var availableFormats: srcExt !== "" ? Conv.getTargets(srcExt) : ["MP4", "PNG", "PDF", "MD"]
    readonly property var plan: (selectedFile !== "" && targetFormat !== "")
        ? Conv.buildCommand(selectedFile, targetFormat, activeHwAccel)
        : null

    readonly property string etaDisplayText: {
        if (converting) {
            if (etaRemainingSec >= 0) return "~" + Conv.formatDuration(etaRemainingSec) + " left"
            return "Finalizing..."
        }
        if (plan && fileBytes > 0) {
            return "~" + Conv.formatDuration(Conv.estimateInitialSeconds(plan.engine, fileBytes, mediaDurationSec, activeHwAccel))
        }
        return "--"
    }

    function probeEngines() {
        if (!engineProbeProc.running) engineProbeProc.running = true
    }

    function installPackages(pkgString) {
        if (pkgString === "" || installingDeps) return
        installingDeps = true
        statusLine = "INSTALLING DEPENDENCIES..."
        var cmdStr = "sudo pacman -S --needed " + pkgString + "; echo; read -p 'Finished. Press Enter to close...'"
        installProc.command = [
            "bash", "-c",
            "if command -v xdg-terminal-exec >/dev/null 2>&1; then xdg-terminal-exec bash -c \"$1\"; " +
            "elif command -v alacritty >/dev/null 2>&1; then alacritty -e bash -c \"$1\"; " +
            "elif command -v ghostty >/dev/null 2>&1; then ghostty -e bash -c \"$1\"; " +
            "elif command -v kitty >/dev/null 2>&1; then kitty bash -c \"$1\"; " +
            "else exit 127; fi",
            "bash", cmdStr
        ]
        installProc.running = true
    }

    function loadFile(rawPath) {
        var clean = Conv.normalizePath(rawPath)
        if (clean === "") return
        selectedFile = clean
        fileBytes = 0
        mediaDurationSec = 0
        etaRemainingSec = -1
        progressRatio = 0
        hasExactProgress = false

        var ext = Conv.getExtension(clean)
        var targets = Conv.getTargets(ext)
        targetFormat = targets.length > 0 ? targets[0].toUpperCase() : ""
        statusLine = targetFormat !== "" ? "READY TO CONVERT" : "UNSUPPORTED FORMAT (." + ext + ")"

        statProc.command = ["bash", "-c", "printf '%s|%s' \"$(du -h \"$1\" 2>/dev/null | cut -f1)\" \"$(stat -c %s \"$1\" 2>/dev/null || echo 0)\"", "bash", clean]
        statProc.running = true

        if (Conv.isMedia(ext)) {
            durationProc.command = ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", clean]
            durationProc.running = true
        }
    }

    function openFilePicker() {
        if (pickerProc.running) return
        statusLine = "OPENING FILE DIALOG..."
        pickerProc.running = true
    }

    function runConversion() {
        if (!plan || converting || !engineReady) return
        converting = true
        startTimeMs = Date.now()
        elapsedSec = 0
        hasExactProgress = false
        estimatedTotalSec = Conv.estimateInitialSeconds(plan.engine, fileBytes, mediaDurationSec, activeHwAccel)
        etaRemainingSec = estimatedTotalSec
        progressRatio = 0.04
        statusLine = "CONVERTING · ~" + Conv.formatDuration(etaRemainingSec).toUpperCase() + " LEFT"

        convertProc.outPath = plan.outPath
        convertProc.command = plan.cmd
        convertProc.running = true
    }

    function handleFfmpegProgressLine(line) {
        var trimmed = line.trim()
        if (trimmed.indexOf("out_time_us=") === 0) {
            var us = parseFloat(trimmed.substring(12))
            if (!isNaN(us) && us > 0 && mediaDurationSec > 0) {
                var processedSec = us / 1000000.0
                var ratio = Math.min(0.99, Math.max(0.01, processedSec / mediaDurationSec))
                hasExactProgress = true
                progressRatio = ratio
                var nowElapsed = Math.max(0.2, (Date.now() - startTimeMs) / 1000.0)
                var speed = processedSec / nowElapsed
                if (speed > 0.01) {
                    etaRemainingSec = Math.max(0, (mediaDurationSec - processedSec) / speed)
                    statusLine = "CONVERTING " + Math.round(ratio * 100) + "% · ~" + Conv.formatDuration(etaRemainingSec).toUpperCase() + " LEFT"
                }
            }
        } else if (trimmed === "progress=end") {
            progressRatio = 1.0
            etaRemainingSec = 0
        }
    }

    Component.onCompleted: {
        gpuProbeProc.running = true
        probeEngines()
    }

    onOpenedChanged: {
        if (opened) probeEngines()
    }

    // Probe installed CLI engines and missing Arch packages
    Process {
        id: engineProbeProc
        command: [
            "bash", "-c",
            "for pair in ffmpeg:ffmpeg magick:imagemagick pandoc:pandoc soffice:libreoffice-fresh pdftotext:poppler pdftoppm:poppler zenity:zenity wl-paste:wl-clipboard; do " +
            "  cmd=${pair%%:*}; pkg=${pair#*:}; " +
            "  if command -v $cmd >/dev/null 2>&1; then echo \"$cmd:1:\"; else echo \"$cmd:0:$pkg\"; fi; " +
            "done"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var map = {}
                var missing = []
                var lines = text.trim().split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split(":")
                    if (parts.length >= 2) {
                        var ok = (parts[1] === "1")
                        map[parts[0]] = ok
                        if (!ok && parts.length === 3 && parts[2] !== "" && missing.indexOf(parts[2]) === -1) {
                            missing.push(parts[2])
                        }
                    }
                }
                root.installedEngines = map
                root.missingPackagesList = missing.join(" ")
            }
        }
    }

    // Terminal package installer
    Process {
        id: installProc
        onExited: function(exitCode) {
            root.installingDeps = false
            root.probeEngines()
            gpuProbeProc.running = true
            if (exitCode === 0) {
                root.statusLine = root.selectedFile !== "" ? "READY TO CONVERT" : "DEPENDENCIES INSTALLED"
            } else {
                root.statusLine = "NO TERMINAL FOUND FOR INSTALL"
            }
        }
    }

    // Probe working GPU hardware encoder
    Process {
        id: gpuProbeProc
        command: [
            "bash", "-c",
            "if ffmpeg -hide_banner -loglevel error -f lavfi -i nullsrc=s=256x256:d=0.1 -c:v h264_nvenc -f null - 2>/dev/null; then echo nvenc; " +
            "elif ffmpeg -hide_banner -loglevel error -vaapi_device /dev/dri/renderD128 -f lavfi -i nullsrc=s=256x256:d=0.1 -vf 'format=nv12,hwupload' -c:v h264_vaapi -f null - 2>/dev/null; then echo vaapi; " +
            "else echo cpu; fi"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var mode = text.trim()
                root.detectedHwAccel = (mode === "nvenc" || mode === "vaapi") ? mode : "cpu"
            }
        }
    }

    Timer {
        id: etaTimer
        interval: 250
        running: root.converting
        repeat: true
        onTriggered: {
            root.elapsedSec = (Date.now() - root.startTimeMs) / 1000.0
            if (!root.hasExactProgress) {
                var rem = root.estimatedTotalSec - root.elapsedSec
                if (rem > 1) {
                    root.etaRemainingSec = rem
                    root.progressRatio = Math.min(0.92, Math.max(0.05, root.elapsedSec / root.estimatedTotalSec))
                    root.statusLine = "CONVERTING · ~" + Conv.formatDuration(rem).toUpperCase() + " LEFT"
                } else {
                    root.etaRemainingSec = -1
                    root.progressRatio = Math.min(0.96, root.progressRatio + 0.008)
                    root.statusLine = "CONVERTING · " + Conv.formatDuration(root.elapsedSec).toUpperCase() + " ELAPSED"
                }
            }
        }
    }

    Process {
        id: pickerProc
        command: [
            "bash", "-c",
            "if command -v zenity >/dev/null 2>&1; then zenity --file-selection --title='Select File to Convert' 2>/dev/null; " +
            "elif command -v kdialog >/dev/null 2>&1; then kdialog --getopenfilename \"$HOME\" 2>/dev/null; " +
            "elif command -v yad >/dev/null 2>&1; then yad --file --title='Select File to Convert' 2>/dev/null; " +
            "elif python3 -c 'import tkinter' 2>/dev/null; then python3 -c 'import tkinter as tk; from tkinter import filedialog; r=tk.Tk(); r.withdraw(); print(filedialog.askopenfilename())'; " +
            "else echo '__NO_DIALOG__'; fi"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var res = text.trim()
                if (res === "__NO_DIALOG__") root.statusLine = "INSTALL ZENITY OR DROP FILE"
                else if (res !== "") root.loadFile(res)
                else root.statusLine = root.selectedFile !== "" ? "READY TO CONVERT" : "DROP OR PICK A FILE"
            }
        }
    }

    Process {
        id: clipProc
        command: ["wl-paste", "-n"]
        stdout: StdioCollector {
            onStreamFinished: {
                var p = Conv.normalizePath(text)
                if (p.startsWith("/")) root.loadFile(p)
                else root.statusLine = "CLIPBOARD HAS NO FILE PATH"
            }
        }
    }

    Process {
        id: statProc
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = text.trim().split("|")
                root.fileSizeText = parts[0] || "--"
                root.fileBytes = parts.length > 1 ? (parseFloat(parts[1]) || 0) : 0
            }
        }
    }

    Process {
        id: durationProc
        stdout: StdioCollector {
            onStreamFinished: {
                var d = parseFloat(text.trim())
                if (!isNaN(d) && d > 0) root.mediaDurationSec = d
            }
        }
    }

    Process {
        id: convertProc
        property string outPath: ""
        stdout: SplitParser {
            onRead: function(line) { root.handleFfmpegProgressLine(line) }
        }
        stderr: StdioCollector {
            id: errCollector
        }
        onExited: function(exitCode) {
            var totalTook = ((Date.now() - root.startTimeMs) / 1000.0).toFixed(1)
            root.converting = false
            root.etaRemainingSec = -1
            if (exitCode === 0) {
                root.progressRatio = 1.0
                root.lastOutputPath = outPath
                root.statusLine = "DONE IN " + totalTook + "S"
                if (!root.keepOriginal && root.selectedFile !== outPath) {
                    Util.execArgv(["rm", "-f", root.selectedFile])
                }
            } else {
                root.progressRatio = 0
                var errLines = errCollector.text.trim().split("\n")
                var lastErr = errLines.length > 0 ? errLines[errLines.length - 1].trim() : ""
                root.statusLine = lastErr !== "" ? lastErr.substring(0, 38).toUpperCase() : ("FAILED (" + (root.plan ? root.plan.engine.toUpperCase() : "CLI") + ")")
            }
        }
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(390))
        contentHeight: panel.fittedContentHeight(mainCol.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: function(direction) { root.switchPanel(direction) }

            DropArea {
                id: dropZone
                anchors.fill: parent
                keys: ["text/uri-list", "text/plain"]
                onEntered: function(drag) { drag.accept(Qt.CopyAction) }
                onDropped: function(drop) {
                    if (drop.hasUrls && drop.urls.length > 0) root.loadFile(drop.urls[0].toString())
                    else if (drop.hasText) root.loadFile(drop.text.split("\n")[0])
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                radius: Style.cornerRadius
                color: Util.alpha(Commons.Color.accent, 0.08)
                border.color: Commons.Color.accent
                border.width: 1
                visible: dropZone.containsDrag
                z: 10

                Text {
                    anchors.centerIn: parent
                    text: "DROP FILE TO LOAD"
                    color: Commons.Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                    font.letterSpacing: 1.5
                }
            }

            ColumnLayout {
                id: mainCol
                width: parent.width
                spacing: Style.spacing.panelGap

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(10)

                    Text {
                        text: "󰈔"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(2)

                        Text {
                            Layout.fillWidth: true
                            text: root.selectedFile !== "" ? root.selectedFile.split("/").pop() : "Drop or Pick a File"
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.subtitle
                            font.weight: Font.DemiBold
                            elide: Text.ElideMiddle
                        }

                        Text {
                            text: root.statusLine
                            color: (root.converting || root.installingDeps) ? Commons.Color.accent : root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.letterSpacing: 1.2
                        }
                    }

                    // Folder Picker Button
                    Rectangle {
                        width: Style.space(30)
                        height: Style.space(30)
                        radius: Style.cornerRadius
                        color: pickArea.containsMouse ? root.cardFill : "transparent"
                        border.color: pickArea.containsMouse ? root.foreground : root.borderColor
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "󰉋"
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                        }

                        MouseArea {
                            id: pickArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openFilePicker()
                        }
                    }

                    // Paste Path Button
                    Rectangle {
                        width: Style.space(30)
                        height: Style.space(30)
                        radius: Style.cornerRadius
                        color: pasteArea.containsMouse ? root.cardFill : "transparent"
                        border.color: pasteArea.containsMouse ? root.foreground : root.borderColor
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "󰅌"
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                        }

                        MouseArea {
                            id: pasteArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pasteFromClipboard()
                        }
                    }

                    // Keep Original Rectangular Switch
                    Rectangle {
                        width: Style.space(42)
                        height: Style.space(22)
                        radius: Style.cornerRadius
                        color: root.cardFill
                        border.color: root.borderColor
                        border.width: 1

                        Rectangle {
                            width: Style.space(16)
                            height: Style.space(16)
                            radius: Style.cornerRadius
                            y: Style.space(3)
                            x: root.keepOriginal ? parent.width - width - Style.space(3) : Style.space(3)
                            color: root.keepOriginal ? root.foreground : root.dim
                            Behavior on x { NumberAnimation { duration: Style.duration(120) } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.keepOriginal = !root.keepOriginal
                        }
                    }
                }

                // Missing Dependencies Banner (only visible if any backend package is missing)
                Rectangle {
                    visible: root.missingPackagesList !== ""
                    Layout.fillWidth: true
                    height: Style.space(34)
                    radius: Style.cornerRadius
                    color: depBannerArea.containsMouse ? root.cardFill : "transparent"
                    border.color: Commons.Color.accent
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Style.space(10)
                        anchors.rightMargin: Style.space(10)
                        spacing: Style.space(8)

                        Text {
                            text: "󰏗"
                            color: Commons.Color.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Missing: " + root.missingPackagesList
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                        }

                        Text {
                            text: root.installingDeps ? "INSTALLING..." : "INSTALL ALL"
                            color: Commons.Color.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.letterSpacing: 1.0
                        }
                    }

                    MouseArea {
                        id: depBannerArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !root.installingDeps
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.installPackages(root.missingPackagesList)
                    }
                }

                // 2x4 Metadata Grid
                GridLayout {
                    Layout.fillWidth: true
                    columns: 4
                    columnSpacing: Style.space(12)
                    rowSpacing: Style.space(6)

                    Text { text: "Source"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                    Text { text: root.srcExt !== "" ? root.srcExt.toUpperCase() : "--"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; Layout.alignment: Qt.AlignRight; Layout.fillWidth: true }
                    Text { text: "Target"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                    Text { text: root.targetFormat || "--"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; Layout.alignment: Qt.AlignRight; Layout.fillWidth: true }

                    Text { text: "Size"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                    Text { text: root.fileSizeText; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; Layout.alignment: Qt.AlignRight; Layout.fillWidth: true }
                    Text { text: "Engine"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                    Text {
                        text: root.plan ? (root.plan.engine + (root.engineReady ? "" : " (missing)")) : "--"
                        color: (root.plan && !root.engineReady) ? Commons.Color.accent : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        Layout.alignment: Qt.AlignRight
                        Layout.fillWidth: true
                    }

                    Text { text: "Compute"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                    Text {
                        text: root.plan ? root.plan.accel : (root.activeHwAccel !== "cpu" ? ("GPU (" + root.activeHwAccel.toUpperCase() + ")") : "CPU")
                        color: (root.plan ? root.plan.accel.indexOf("GPU") === 0 : root.activeHwAccel !== "cpu") ? Commons.Color.accent : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        Layout.alignment: Qt.AlignRight
                        Layout.fillWidth: true

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (!root.converting) root.useGpu = !root.useGpu
                        }
                    }
                    Text { text: root.converting ? "ETA" : "Est. Time"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                    Text {
                        text: root.etaDisplayText
                        color: root.converting ? Commons.Color.accent : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        Layout.alignment: Qt.AlignRight
                        Layout.fillWidth: true
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: root.borderColor }

                // Target Format Wrap Grid
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(8)

                    Text {
                        text: "TARGET FORMAT"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.letterSpacing: 1.2
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Style.space(6)

                        Repeater {
                            model: root.availableFormats
                            Rectangle {
                                required property string modelData
                                readonly property string label: modelData.toUpperCase()
                                readonly property bool selected: root.targetFormat === label

                                width: Math.max(Style.space(58), fmtText.implicitWidth + Style.space(20))
                                height: Style.space(32)
                                radius: Style.cornerRadius
                                color: selected ? root.cardFill : "transparent"
                                border.color: selected ? root.foreground : root.borderColor
                                border.width: 1

                                Text {
                                    id: fmtText
                                    anchors.centerIn: parent
                                    text: parent.label
                                    color: parent.selected ? root.foreground : root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.selectedFile !== "" && !root.converting) {
                                            root.targetFormat = parent.label
                                            root.progressRatio = 0
                                            root.statusLine = "READY TO CONVERT"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Actions + Live Progress Bar / One-Click Engine Installer
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(6)

                    Text {
                        text: "ACTIONS"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.letterSpacing: 1.2
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: Style.space(48)
                        radius: Style.cornerRadius
                        color: root.plan ? root.cardFill : "transparent"
                        border.color: (root.converting || (root.plan && !root.engineReady)) ? Commons.Color.accent : root.borderColor
                        border.width: 1
                        opacity: root.plan ? 1.0 : 0.5
                        clip: true

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * root.progressRatio
                            color: Util.alpha(Commons.Color.accent, 0.16)
                            visible: root.converting || root.progressRatio > 0
                            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Style.space(12)
                            anchors.rightMargin: Style.space(12)
                            spacing: Style.space(10)

                            Text {
                                text: root.converting ? "󰔟" : ((root.plan && !root.engineReady) ? "󰏗" : "󰑐")
                                color: (root.converting || (root.plan && !root.engineReady)) ? Commons.Color.accent : root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.subtitle
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    text: {
                                        if (root.converting) return "Converting to " + root.targetFormat + " (" + root.etaDisplayText + ")"
                                        if (!root.plan) return "Drop or pick a file first"
                                        if (!root.engineReady) return "Install " + root.missingPackage + " to convert"
                                        return "Convert to " + root.targetFormat
                                    }
                                    color: root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    text: {
                                        if (root.converting) return "Elapsed: " + Conv.formatDuration(root.elapsedSec) + " · " + root.plan.accel
                                        if (!root.plan) return "Drag onto panel, click folder, or paste"
                                        if (!root.engineReady) return "Click to install via pacman in terminal"
                                        return "Est. " + root.etaDisplayText + " via " + root.plan.engine + " (" + root.plan.accel + ")"
                                    }
                                    color: root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                }
                            }

                            Text {
                                text: root.converting ? (Math.round(root.progressRatio * 100) + "%") : "󰁔"
                                color: (root.converting || (root.plan && !root.engineReady)) ? Commons.Color.accent : root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.plan !== null && !root.converting && !root.installingDeps
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (!root.engineReady) root.installPackages(root.missingPackage)
                                else root.runConversion()
                            }
                        }
                    }

                    Rectangle {
                        visible: root.lastOutputPath !== ""
                        Layout.fillWidth: true
                        height: Style.space(38)
                        radius: Style.cornerRadius
                        color: openArea.containsMouse ? root.cardFill : "transparent"
                        border.color: root.borderColor
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Style.space(12)
                            anchors.rightMargin: Style.space(12)
                            spacing: Style.space(10)

                            Text {
                                text: "󰏌"
                                color: Commons.Color.accent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.lastOutputPath.split("/").pop()
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                elide: Text.ElideMiddle
                            }

                            Text {
                                text: "OPEN"
                                color: Commons.Color.accent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.letterSpacing: 1.0
                            }
                        }

                        MouseArea {
                            id: openArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var dir = root.lastOutputPath.substring(0, root.lastOutputPath.lastIndexOf("/"))
                                Util.execArgv(["xdg-open", dir])
                            }
                        }
                    }
                }
            }
        }
    }
}
