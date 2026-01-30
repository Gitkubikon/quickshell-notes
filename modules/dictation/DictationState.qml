import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool recording: false
    property real audioLevel: 0.0
    property real rawLevel: 0.0

    property var watcher: FileView {
        path: `${Quickshell.env("HOME")}/.config/hyprwhspr/recording_status`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.recording = true
        onLoadFailed: root.recording = false
    }

    property var levelWatcher: FileView {
        path: `${Quickshell.env("HOME")}/.config/hyprwhspr/audio_level`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const val = parseFloat(text());
            root.rawLevel = isNaN(val) ? 0.0 : val;
            // Light EMA smoothing: rise fast (0.45), fall slower (0.25)
            const alpha = root.rawLevel > root.audioLevel ? 0.45 : 0.25;
            root.audioLevel += alpha * (root.rawLevel - root.audioLevel);
        }
        onLoadFailed: root.audioLevel = 0.0
    }

    // Poll for recording status and audio level
    property var pollTimer: Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            root.watcher.reload();
            if (root.recording)
                root.levelWatcher.reload();
        }
    }
}
