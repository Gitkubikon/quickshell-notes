pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// Ephemeral board state shared by every screen. All coordinates are global
// (virtual desktop) coordinates, so a drag started on one monitor is rendered
// live on every other monitor too.
Singleton {
    id: root

    property bool hidden: false

    // Focus management
    property string focusedNoteId: ""
    property string focusedGroupId: ""
    property string focusScreen: ""

    // Stacking order - each raise gets a higher number
    property int focusCounter: 0
    property var zOrders: ({})
    property int zRevision: 0

    // Newly created note that should grab keyboard focus on the given screen
    property string pendingEditId: ""
    property string pendingEditScreen: ""

    // Note drag
    property string draggingNoteId: ""
    property string draggingFromGroupId: ""
    property real dragNoteX: 0
    property real dragNoteY: 0
    property string hoverGroupId: ""
    readonly property bool noteDragging: draggingNoteId !== ""

    // Note being resized
    property string resizingNoteId: ""

    // Pointer pressed on any board item
    property bool pointerHeld: false

    // While true every screen takes all pointer input (no mask), so a fast
    // drag can't slip off the item onto the window underneath
    readonly property bool interacting: pointerHeld || noteDragging || draggingGroupId !== "" || resizingNoteId !== ""

    function resetInteraction(): void {
        pointerHeld = false;
        resizingNoteId = "";
        if (draggingNoteId !== "")
            endNoteDrag();
        if (draggingGroupId !== "")
            endGroupDrag();
    }

    // Group drag
    property string draggingGroupId: ""
    property real dragGroupX: 0
    property real dragGroupY: 0

    // Drag intent tracking
    property real dragStartX: 0
    property real dragStartY: 0
    property real dragStartTime: 0
    property bool dragIntentLock: false  // True = user wants to overlap

    readonly property real overlapTimeThreshold: 400  // ms of hovering over another note
    readonly property real overlapDistanceThreshold: 30  // pixels moved while overlapping

    function zFor(id: string): real {
        zRevision;
        return zOrders[id] || 0;
    }

    function raise(id: string): void {
        if (!id)
            return;
        focusCounter++;
        zOrders[id] = focusCounter;
        zRevision++;
    }

    function focusNote(noteId: string, screenName: string): void {
        focusedNoteId = noteId;
        focusedGroupId = "";
        focusScreen = screenName || "";
        // Grouped notes stack with their group
        var gid = NotePersistence.groupOf(noteId);
        raise(gid !== "" ? gid : noteId);
    }

    function focusGroup(groupId: string, screenName: string): void {
        focusedGroupId = groupId;
        focusedNoteId = "";
        focusScreen = screenName || "";
        raise(groupId);
    }

    function clearFocus(): void {
        focusedNoteId = "";
        focusedGroupId = "";
        focusScreen = "";
    }

    function beginNoteDrag(noteId: string, fromGroupId: string, x: real, y: real): void {
        dragNoteX = x;
        dragNoteY = y;
        dragStartX = x;
        dragStartY = y;
        dragStartTime = Date.now();
        dragIntentLock = false;
        hoverGroupId = "";
        draggingFromGroupId = fromGroupId || "";
        draggingNoteId = noteId;
    }

    function moveNoteDrag(x: real, y: real, w: real, h: real): void {
        dragNoteX = x;
        dragNoteY = y;

        // Check if user has been dragging in same area long enough (intent to overlap)
        var elapsed = Date.now() - dragStartTime;
        var dist = Math.sqrt(Math.pow(x - dragStartX, 2) + Math.pow(y - dragStartY, 2));
        if (elapsed > overlapTimeThreshold && dist < overlapDistanceThreshold)
            dragIntentLock = true;

        hoverGroupId = findGroupAt(x + w / 2, y + h / 2);
    }

    function endNoteDrag(): void {
        draggingNoteId = "";
        draggingFromGroupId = "";
        hoverGroupId = "";
        dragIntentLock = false;
    }

    function wantsOverlap(): bool {
        return dragIntentLock;
    }

    function beginGroupDrag(groupId: string, x: real, y: real): void {
        dragGroupX = x;
        dragGroupY = y;
        draggingGroupId = groupId;
    }

    function moveGroupDrag(x: real, y: real): void {
        dragGroupX = x;
        dragGroupY = y;
    }

    function endGroupDrag(): void {
        draggingGroupId = "";
    }

    // Topmost group containing the point, or ""
    function findGroupAt(px: real, py: real): string {
        var best = "";
        var bestZ = -1;
        var groups = NotePersistence.groups;
        for (var i = 0; i < groups.count; i++) {
            var gid = groups.get(i).groupId;
            var r = NotePersistence.groupRect(gid);
            if (px >= r.x && px <= r.x + r.width && py >= r.y && py <= r.y + r.height) {
                var z = zOrders[gid] || 0;
                if (z > bestZ) {
                    bestZ = z;
                    best = gid;
                }
            }
        }
        return best;
    }

    GlobalShortcut {
        appid: "caelestia"
        name: "notesToggle"
        description: "Toggle notes above/below windows"
        onPressed: root.hidden = !root.hidden
    }
}
