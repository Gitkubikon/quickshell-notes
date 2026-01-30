pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string statePath: `${Quickshell.env("XDG_STATE_HOME") || `${home}/.local/state`}/caelestia`
    readonly property string notesFile: `${statePath}/notes.json`

    property ListModel notes: ListModel {}
    property bool saving: false

    // Map from JSON format to ListModel roles (avoiding QML property name clashes)
    function _toModel(obj: var): var {
        return {
            noteId: obj.id || Date.now().toString(),
            noteX: obj.x || 0,
            noteY: obj.y || 0,
            noteWidth: obj.width || 220,
            noteHeight: obj.height || 180,
            text: obj.text || "",
            noteColor: obj.color || "surface"
        };
    }

    // Map from ListModel roles back to JSON format
    function _toJson(index: int): var {
        var item = notes.get(index);
        return {
            id: item.noteId,
            x: item.noteX,
            y: item.noteY,
            width: item.noteWidth,
            height: item.noteHeight,
            text: item.text,
            color: item.noteColor
        };
    }

    function load(data: string): void {
        try {
            var loaded = JSON.parse(data);
            notes.clear();
            if (Array.isArray(loaded)) {
                for (var i = 0; i < loaded.length; i++)
                    notes.append(_toModel(loaded[i]));
            }
        } catch (e) {
            console.warn("Failed to parse notes:", e);
            notes.clear();
        }
    }

    function save(): void {
        saveTimer.restart();
    }

    function saveNow(): void {
        var arr = [];
        for (var i = 0; i < notes.count; i++)
            arr.push(_toJson(i));
        const json = JSON.stringify(arr, null, 4);
        saving = true;
        writer.stdinEnabled = true;
        writer.stdinData = json;
        writer.command = ["sh", "-c", `mkdir -p '${statePath}' && cat > '${notesFile}'`];
        writer.running = true;
    }

    function addNote(x: real, y: real): void {
        notes.append({
            noteId: Date.now().toString(),
            noteX: x,
            noteY: y,
            noteWidth: 220,
            noteHeight: 180,
            text: "",
            noteColor: "surface"
        });
        save();
    }

    function removeNote(index: int): void {
        notes.remove(index);
        save();
    }

    function updateNote(index: int, data: var): void {
        if (index < 0 || index >= notes.count) return;
        // Map external keys to model role names
        var keyMap = { x: "noteX", y: "noteY", width: "noteWidth", height: "noteHeight", color: "noteColor" };
        for (var key in data) {
            var role = keyMap[key] || key;
            notes.setProperty(index, role, data[key]);
        }
        save();
    }

    Timer {
        id: saveTimer
        interval: 400
        repeat: false
        onTriggered: root.saveNow()
    }

    FileView {
        path: root.notesFile
        watchChanges: true
        onFileChanged: {
            if (!root.saving && !saveTimer.running) reload();
        }
        onLoaded: root.load(text())
    }

    Process {
        id: writer
        command: ["sh", "-c", ""]
        property string stdinData: ""
        onRunningChanged: {
            if (writer.running) {
                writer.write(stdinData);
                stdinEnabled = false;
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.saving = false;
            if (exitCode !== 0) {
                console.warn("Failed to save notes, exit code:", exitCode);
            }
        }
    }
}
