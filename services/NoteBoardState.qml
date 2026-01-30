pragma Singleton

import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    property bool hidden: false

    GlobalShortcut {
        appid: "caelestia"
        name: "notesToggle"
        description: "Toggle notes above/below windows"
        onPressed: root.hidden = !root.hidden
    }
}
