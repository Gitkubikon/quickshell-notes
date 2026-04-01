pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    property bool hidden: false
    property bool noteDragging: false
    property string draggingFromGroupId: ""
    property real dragX: 0
    property real dragY: 0
    property var groupSizes: ({})

    // Focus management - track which note/group is on top
    property string focusedNoteId: ""
    property string focusedGroupId: ""
    property int focusCounter: 0  // Increments on each focus, used for z-order

    // Drag intent tracking
    property real dragStartX: 0
    property real dragStartY: 0
    property real dragStartTime: 0
    property bool dragIntentLock: false  // True = user wants to overlap

    readonly property real overlapTimeThreshold: 400  // ms of hovering over another note
    readonly property real overlapDistanceThreshold: 30  // pixels moved while overlapping

    function registerGroup(gid: string, x: real, y: real, w: real, h: real): void {
        groupSizes[gid] = { x: x, y: y, width: w, height: h };
    }

    function findGroupAt(px: real, py: real, excludeGroupId: string): string {
        for (var gid in groupSizes) {
            if (excludeGroupId && gid === excludeGroupId) continue;
            var g = groupSizes[gid];
            if (px >= g.x && px <= g.x + g.width &&
                py >= g.y && py <= g.y + g.height) {
                return gid;
            }
        }
        return "";
    }

    function focusNote(noteId: string): int {
        focusedNoteId = noteId;
        focusedGroupId = "";
        focusCounter++;
        return focusCounter;
    }

    function focusGroup(groupId: string): int {
        focusedGroupId = groupId;
        focusedNoteId = "";
        focusCounter++;
        return focusCounter;
    }

    function clearFocus(): void {
        focusedNoteId = "";
        focusedGroupId = "";
    }

    function startDrag(x: real, y: real, fromGroupId: string): void {
        dragStartX = x;
        dragStartY = y;
        dragStartTime = Date.now();
        dragIntentLock = false;
        noteDragging = true;
        draggingFromGroupId = fromGroupId || "";
    }

    function updateDrag(x: real, y: real): void {
        dragX = x;
        dragY = y;

        // Check if user has been dragging in same area long enough (intent to overlap)
        var elapsed = Date.now() - dragStartTime;
        var dist = Math.sqrt(Math.pow(x - dragStartX, 2) + Math.pow(y - dragStartY, 2));

        if (elapsed > overlapTimeThreshold && dist < overlapDistanceThreshold) {
            dragIntentLock = true;
        }
    }

    function endDrag(): void {
        noteDragging = false;
        dragIntentLock = false;
        draggingFromGroupId = "";
    }

    function wantsOverlap(): bool {
        return dragIntentLock;
    }

    GlobalShortcut {
        appid: "caelestia"
        name: "notesToggle"
        description: "Toggle notes above/below windows"
        onPressed: root.hidden = !root.hidden
    }
}
