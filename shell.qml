// hypr-overview — a Windows-style task switcher for Hyprland.
//
// One overlay per monitor, each showing live thumbnails of every window that
// lives on that monitor, from every workspace. Click a tile to focus it (its
// monitor switches to that window's workspace; the others stay put). While the
// overlay is open, Super+Tab / Super+Shift+Tab move a highlight through every
// window on every monitor, most recently used first, and letting go of Super
// switches to the highlighted one. Esc, or a click on empty space, cancels.
//
// Driven over IPC (`qs -p <dir> ipc call overview <fn>`):
//   open   show it, or step forward if it is already showing
//   prev   show it, or step backward
//   toggle show / hide
//   commit switch to the highlighted window
//   close  hide without switching

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io

ShellRoot {
    id: root

    property bool shown: false
    // Every window, most recently focused first, as plain objects:
    // { top: HyprlandToplevel, mon: monitor name, ws: workspace label }
    property var order: []
    property int sel: 0

    // --- theme -------------------------------------------------------------
    // ~/.config/hypr-overview/theme.json overrides any of these keys.
    property var theme: ({
        backdrop: "#b0080a0e",
        tile: "#cc1a1f27",
        tileHover: "#cc2a313c",
        accent: "#5fb3ff",
        text: "#e8eaed",
        dim: "#9aa3ad",
        radius: 10,
        font: "sans-serif"
    })

    FileView {
        id: themeFile
        path: Quickshell.env("HOME") + "/.config/hypr-overview/theme.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const t = JSON.parse(text());
                const merged = Object.assign({}, root.theme);
                for (const k in t) merged[k] = t[k];
                root.theme = merged;
            } catch (e) {
                console.warn("hypr-overview: bad theme.json:", e);
            }
        }
    }

    // --- window list -------------------------------------------------------
    function ipc(t) {
        return t.lastIpcObject || {};
    }

    // glade (blaney-pc) minimises a window by parking it on special:minimized
    // with a "glade-min-<monitor>" tag; show it on the monitor it came from.
    function monitorOf(t) {
        const o = ipc(t);
        for (const tag of (o.tags || [])) {
            const m = String(tag).match(/^glade-min-(.+?)\*?$/);
            if (m) return m[1];
        }
        return t.monitor ? t.monitor.name : "";
    }

    // An icon for a window: its desktop entry's, else one named after its
    // class, else a generic one. "" when the theme has none of them.
    function iconFor(t) {
        const cls = ipc(t).class || "";
        const e = cls ? DesktopEntries.heuristicLookup(cls) : null;
        for (const n of [e ? e.icon : "", cls, cls.toLowerCase(), "application-x-executable", "applications-other"]) {
            const p = n ? Quickshell.iconPath(n, true) : "";
            if (p) return p;
        }
        return "";
    }

    function wsLabel(t) {
        const w = t.workspace;
        if (!w) return "";
        if (w.name === "special:minimized") return "–";
        if (w.name.startsWith("special:")) return w.name.slice(8);
        return w.name;
    }

    function rebuild() {
        const list = [];
        for (const t of Hyprland.toplevels.values) {
            const o = ipc(t);
            if (!t.workspace || o.mapped === false) continue;
            // Scratchpads (special:ckb etc.) are not windows you switch to;
            // glade's minimised windows are.
            if (t.workspace.name.startsWith("special:") && t.workspace.name !== "special:minimized") continue;
            list.push({ top: t, mon: monitorOf(t), ws: wsLabel(t),
                        hist: o.focusHistoryID === undefined ? 9999 : o.focusHistoryID });
        }
        list.sort((a, b) => a.hist - b.hist);
        root.order = list;
    }

    function tilesFor(monName) {
        return root.order.filter(e => e.mon === monName);
    }

    // --- actions -----------------------------------------------------------
    function show(step) {
        if (root.shown) {
            if (root.order.length > 0)
                root.sel = (root.sel + step + root.order.length) % root.order.length;
            return;
        }
        Hyprland.refreshToplevels();
        rebuild();
        // Like Windows: the first press already points at the window you used
        // before this one.
        root.sel = root.order.length > 1 ? (step > 0 ? 1 : root.order.length - 1) : 0;
        root.shown = true;
    }

    function activate(entry) {
        root.shown = false;
        if (!entry) return;
        Hyprland.dispatch("focuswindow address:0x" + entry.top.address);
        Hyprland.dispatch("alterzorder top");
    }

    function commit() {
        if (root.shown) activate(root.order[root.sel]);
    }

    function close() {
        root.shown = false;
    }

    // focusHistoryID arrives with the refreshed IPC data, a moment after open.
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (root.shown && (ev.name === "openwindow" || ev.name === "closewindow"
                               || ev.name === "movewindowv2"))
                Hyprland.refreshToplevels();
        }
    }
    Timer {
        id: settle
        interval: 60
        onTriggered: {
            const cur = root.order[root.sel];
            root.rebuild();
            if (root.order.length === 0) { root.shown = false; return; }
            if (cur) {
                const i = root.order.findIndex(e => e.top === cur.top);
                if (i >= 0) root.sel = i;
            }
            root.sel = Math.min(root.sel, root.order.length - 1);
        }
    }
    Instantiator {
        model: Hyprland.toplevels
        delegate: Connections {
            required property var modelData
            target: modelData
            function onLastIpcObjectChanged() { if (root.shown) settle.restart(); }
            function onWorkspaceChanged() { if (root.shown) settle.restart(); }
        }
    }

    IpcHandler {
        target: "overview"
        function open(): void { root.show(1); }
        function prev(): void { root.show(-1); }
        function toggle(): void { if (root.shown) root.close(); else root.show(1); }
        function commit(): void { root.commit(); }
        function close(): void { root.close(); }
        function state(): string {
            return JSON.stringify({ sel: root.sel, order: root.order.map(e => [e.top.address, e.mon, e.ws, e.hist, root.ipc(e.top).class, (DesktopEntries.heuristicLookup(root.ipc(e.top).class || "") || {}).icon]) });
        }
    }

    // --- one overlay per monitor ------------------------------------------
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            readonly property var hmon: Hyprland.monitorFor(modelData)
            readonly property bool focusedMon: Hyprland.focusedMonitor === hmon
            readonly property var tiles: root.shown ? root.tilesFor(modelData.name) : []

            visible: root.shown
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "hypr-overview"
            WlrLayershell.keyboardFocus: root.shown && focusedMon
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Rectangle {
                anchors.fill: parent
                color: root.theme.backdrop
            }

            // Empty space cancels.
            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }

            Item {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onPressed: ev => {
                    if (ev.key === Qt.Key_Escape) { root.close(); ev.accepted = true; }
                    else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { root.commit(); ev.accepted = true; }
                    else if (ev.key === Qt.Key_Tab || ev.key === Qt.Key_Right || ev.key === Qt.Key_Down) { root.show(1); ev.accepted = true; }
                    else if (ev.key === Qt.Key_Backtab || ev.key === Qt.Key_Left || ev.key === Qt.Key_Up) { root.show(-1); ev.accepted = true; }
                }
                Keys.onReleased: ev => {
                    if (ev.key === Qt.Key_Super_L || ev.key === Qt.Key_Super_R || ev.key === Qt.Key_Meta) {
                        root.commit();
                        ev.accepted = true;
                    }
                }
            }
            onVisibleChanged: if (visible) keys.forceActiveFocus()

            // --- the grid -------------------------------------------------
            // Pick the column count that gives the biggest tiles that fit.
            readonly property real areaW: width * 0.86
            readonly property real areaH: height * 0.80
            readonly property int gap: 22
            readonly property int caption: 34
            readonly property real aspect: 16 / 10
            readonly property var grid: {
                const n = tiles.length;
                let best = { cols: 1, w: 0 };
                for (let c = 1; c <= Math.max(1, n); c++) {
                    const r = Math.ceil(n / c);
                    const wByW = (areaW - gap * (c - 1)) / c;
                    const wByH = ((areaH - gap * (r - 1)) / r - caption) * aspect;
                    const w = Math.min(wByW, wByH, 520);
                    if (w > best.w) best = { cols: c, w: w };
                }
                return best;
            }
            readonly property real tileW: grid.w
            readonly property real thumbH: tileW / aspect

            Text {
                anchors.centerIn: parent
                visible: tiles.length === 0
                text: "No windows on this screen"
                color: root.theme.dim
                font.family: root.theme.font
                font.pixelSize: 20
            }

            Flow {
                anchors.centerIn: parent
                width: Math.min(win.grid.cols, Math.max(1, tiles.length)) * (win.tileW + win.gap) - win.gap
                spacing: win.gap

                Repeater {
                    model: win.tiles

                    Rectangle {
                        id: tile
                        required property var modelData
                        readonly property bool selected: root.order[root.sel] !== undefined && root.order[root.sel].top.address === modelData.top.address
                        readonly property string icon: root.iconFor(modelData.top)

                        width: win.tileW
                        height: win.thumbH + win.caption
                        radius: root.theme.radius
                        color: hover.containsMouse ? root.theme.tileHover : root.theme.tile
                        border.width: selected ? 3 : (hover.containsMouse ? 1 : 0)
                        border.color: root.theme.accent

                        Item {
                            id: thumb
                            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 8 }
                            height: win.thumbH - 8

                            ScreencopyView {
                                id: shot
                                anchors.centerIn: parent
                                captureSource: root.shown ? tile.modelData.top.wayland : null
                                live: root.shown
                                constraintSize: Qt.size(thumb.width, thumb.height)
                                width: implicitWidth
                                height: implicitHeight
                            }

                            // No capture (yet, or ever): a big icon instead.
                            Image {
                                anchors.centerIn: parent
                                visible: !shot.hasContent
                                width: Math.min(96, parent.height * 0.6)
                                height: width
                                sourceSize: Qt.size(width, height)
                                source: tile.icon
                            }
                        }

                        Row {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                                      leftMargin: 10; rightMargin: 10; bottomMargin: 7 }
                            spacing: 8
                            height: 22

                            Image {
                                width: 20; height: 20
                                anchors.verticalCenter: parent.verticalCenter
                                sourceSize: Qt.size(20, 20)
                                source: tile.icon
                            }
                            Text {
                                width: parent.width - 20 - badge.width - 16
                                anchors.verticalCenter: parent.verticalCenter
                                text: tile.modelData.top.title
                                elide: Text.ElideRight
                                color: root.theme.text
                                font.family: root.theme.font
                                font.pixelSize: 14
                            }
                            Rectangle {
                                id: badge
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(22, wsText.implicitWidth + 10)
                                height: 20
                                radius: 5
                                color: "transparent"
                                border.width: 1
                                border.color: root.theme.dim
                                Text {
                                    id: wsText
                                    anchors.centerIn: parent
                                    text: tile.modelData.ws
                                    color: root.theme.dim
                                    font.family: root.theme.font
                                    font.pixelSize: 12
                                }
                            }
                        }

                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onEntered: root.sel = root.order.findIndex(e => e.top.address === tile.modelData.top.address)
                            onClicked: ev => {
                                if (ev.button === Qt.MiddleButton) {
                                    Hyprland.dispatch("closewindow address:0x" + tile.modelData.top.address);
                                } else {
                                    root.activate(tile.modelData);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
