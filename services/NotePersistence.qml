pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Notes and groups model. Free note and group positions are global
// (virtual desktop) coordinates; grouped notes use localX/localY inside
// their group's content area.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string statePath: `${Quickshell.env("XDG_STATE_HOME") || `${home}/.local/state`}/caelestia`
    readonly property string notesFile: `${statePath}/notes.json`

    property ListModel notes: ListModel {}
    property ListModel groups: ListModel {}

    // Bumped on every change so bindings calling helper functions re-evaluate
    property int revision: 0
    // Last JSON loaded or written, used to ignore our own file change events
    property string lastJson: ""

    readonly property real gridGap: 8
    readonly property real snapDistance: 20

    readonly property real defaultNoteWidth: 180
    readonly property real defaultNoteHeight: 100
    readonly property real minNoteWidth: 100
    readonly property real minNoteHeight: 60

    readonly property real groupPadding: 8
    readonly property real groupHeaderHeight: 32
    readonly property real groupMinWidth: 180
    readonly property real groupMinHeight: 70

    function newId(): string {
        return Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
    }

    function _noteToModel(obj: var): var {
        return {
            noteId: obj.id || newId(),
            noteX: obj.x || 0,
            noteY: obj.y || 0,
            noteWidth: obj.width || defaultNoteWidth,
            noteHeight: obj.height || defaultNoteHeight,
            text: obj.text || "",
            groupId: obj.groupId || "",
            localX: obj.localX || 0,
            localY: obj.localY || 0
        };
    }

    function _groupToModel(obj: var): var {
        return {
            groupId: obj.id || newId(),
            groupX: obj.x || 0,
            groupY: obj.y || 0,
            title: obj.title || "Group"
        };
    }

    function _noteToJson(index: int): var {
        var item = notes.get(index);
        return {
            id: item.noteId,
            x: item.noteX,
            y: item.noteY,
            width: item.noteWidth,
            height: item.noteHeight,
            text: item.text,
            groupId: item.groupId,
            localX: item.localX,
            localY: item.localY
        };
    }

    function _groupToJson(index: int): var {
        var item = groups.get(index);
        return {
            id: item.groupId,
            x: item.groupX,
            y: item.groupY,
            title: item.title
        };
    }

    function load(data: string): void {
        if (data === lastJson)
            return;
        lastJson = data;

        try {
            var loaded = JSON.parse(data);
            notes.clear();
            groups.clear();

            var rawNotes = [];
            var rawGroups = [];
            if (loaded && typeof loaded === "object" && !Array.isArray(loaded)) {
                if (Array.isArray(loaded.notes))
                    rawNotes = loaded.notes;
                if (Array.isArray(loaded.groups))
                    rawGroups = loaded.groups;
            } else if (Array.isArray(loaded)) {
                rawNotes = loaded;
            }

            var groupIds = {};
            for (var j = 0; j < rawGroups.length; j++) {
                var g = _groupToModel(rawGroups[j]);
                groupIds[g.groupId] = true;
                groups.append(g);
            }
            for (var i = 0; i < rawNotes.length; i++) {
                var n = _noteToModel(rawNotes[i]);
                // Notes pointing at a deleted group would otherwise be invisible
                if (n.groupId !== "" && !groupIds[n.groupId])
                    n.groupId = "";
                notes.append(n);
            }
        } catch (e) {
            console.warn("Failed to parse notes:", e);
            notes.clear();
            groups.clear();
        }

        revision++;
        ensureOnScreen();
    }

    function save(): void {
        saveTimer.restart();
    }

    function saveNow(): void {
        var notesArr = [];
        for (var i = 0; i < notes.count; i++)
            notesArr.push(_noteToJson(i));

        var groupsArr = [];
        for (var j = 0; j < groups.count; j++)
            groupsArr.push(_groupToJson(j));

        const json = JSON.stringify({ notes: notesArr, groups: groupsArr }, null, 4);
        lastJson = json;
        fileView.setText(json);
    }

    function _changed(): void {
        revision++;
        save();
    }

    function noteIndex(noteId: string): int {
        for (var i = 0; i < notes.count; i++) {
            if (notes.get(i).noteId === noteId)
                return i;
        }
        return -1;
    }

    function groupIndex(groupId: string): int {
        for (var i = 0; i < groups.count; i++) {
            if (groups.get(i).groupId === groupId)
                return i;
        }
        return -1;
    }

    function groupOf(noteId: string): string {
        var i = noteIndex(noteId);
        return i < 0 ? "" : notes.get(i).groupId;
    }

    // Move free notes and groups that are not on any connected screen onto the nearest one
    function ensureOnScreen(): void {
        var screens = Quickshell.screens;
        if (!screens || screens.length === 0)
            return;

        function place(x, y, w, h) {
            var cx = x + w / 2;
            var cy = y + h / 2;
            var best = null;
            var bestDist = Infinity;
            for (var s = 0; s < screens.length; s++) {
                var sc = screens[s];
                if (cx >= sc.x && cx < sc.x + sc.width && cy >= sc.y && cy < sc.y + sc.height)
                    return null;
                var dx = Math.max(sc.x - cx, 0, cx - (sc.x + sc.width));
                var dy = Math.max(sc.y - cy, 0, cy - (sc.y + sc.height));
                var dist = dx * dx + dy * dy;
                if (dist < bestDist) {
                    bestDist = dist;
                    best = sc;
                }
            }
            return {
                x: Math.max(best.x, Math.min(x, best.x + best.width - w)),
                y: Math.max(best.y, Math.min(y, best.y + best.height - h))
            };
        }

        var moved = false;
        for (var i = 0; i < notes.count; i++) {
            var n = notes.get(i);
            if (n.groupId !== "")
                continue;
            var p = place(n.noteX, n.noteY, n.noteWidth, n.noteHeight);
            if (p) {
                notes.setProperty(i, "noteX", p.x);
                notes.setProperty(i, "noteY", p.y);
                moved = true;
            }
        }
        for (var j = 0; j < groups.count; j++) {
            var g = groups.get(j);
            var size = groupSize(g.groupId);
            var gp = place(g.groupX, g.groupY, size.width, size.height);
            if (gp) {
                groups.setProperty(j, "groupX", gp.x);
                groups.setProperty(j, "groupY", gp.y);
                moved = true;
            }
        }
        if (moved)
            _changed();
    }

    // Creates a note. When screenName is given, the note grabs keyboard focus on that screen.
    function addNote(x: real, y: real, gid: var, screenName: var): string {
        var groupId = gid || "";
        var localX = 0;
        var localY = 0;

        if (groupId !== "") {
            var pos = findNextSlot(groupId, defaultNoteWidth, defaultNoteHeight);
            localX = pos.x;
            localY = pos.y;
        }

        var id = newId();
        if (screenName) {
            NoteBoardState.pendingEditId = id;
            NoteBoardState.pendingEditScreen = screenName;
        }
        NoteBoardState.raise(groupId !== "" ? groupId : id);

        notes.append({
            noteId: id,
            noteX: x,
            noteY: y,
            noteWidth: defaultNoteWidth,
            noteHeight: defaultNoteHeight,
            text: "",
            groupId: groupId,
            localX: localX,
            localY: localY
        });
        _changed();
        return id;
    }

    function removeNote(noteId: string): void {
        var index = noteIndex(noteId);
        if (index < 0)
            return;
        var groupId = notes.get(index).groupId;
        notes.remove(index);
        if (groupId !== "")
            reflowGroup(groupId);
        _changed();
    }

    function updateNote(noteId: string, data: var): void {
        var index = noteIndex(noteId);
        if (index < 0)
            return;
        var keyMap = { x: "noteX", y: "noteY", width: "noteWidth", height: "noteHeight" };

        // Update position properties BEFORE groupId to avoid visual glitches
        var orderedKeys = ["x", "y", "width", "height", "localX", "localY", "text", "groupId"];
        for (var i = 0; i < orderedKeys.length; i++) {
            var key = orderedKeys[i];
            if (key in data)
                notes.setProperty(index, keyMap[key] || key, data[key]);
        }
        for (var k in data) {
            if (orderedKeys.indexOf(k) === -1)
                notes.setProperty(index, keyMap[k] || k, data[k]);
        }
        _changed();
    }

    function resizeNote(noteId: string, w: real, h: real): void {
        updateNote(noteId, { width: Math.max(minNoteWidth, w), height: Math.max(minNoteHeight, h) });
    }

    function finishResize(noteId: string): void {
        var gid = groupOf(noteId);
        if (gid !== "")
            reflowGroup(gid);
    }

    // Drop a dragged note at global position (x, y): into a group, back into
    // its own group (reordering it), or onto the desktop.
    function dropNote(noteId: string, x: real, y: real, wantsOverlap: bool): void {
        var index = noteIndex(noteId);
        if (index < 0)
            return;
        var n = notes.get(index);
        var oldGroup = n.groupId;
        var w = n.noteWidth;
        var h = n.noteHeight;
        var target = NoteBoardState.findGroupAt(x + w / 2, y + h / 2);

        if (target !== "") {
            // Local drop position decides the slot after reflow
            var g = groupRect(target);
            notes.setProperty(index, "localX", x - g.x - groupPadding);
            notes.setProperty(index, "localY", y - g.y - groupHeaderHeight - groupPadding);
            notes.setProperty(index, "groupId", target);
            reflowGroup(target);
            if (oldGroup !== "" && oldGroup !== target)
                reflowGroup(oldGroup);
        } else {
            var pos = findFreeNotePosition(noteId, x, y, w, h, wantsOverlap);
            notes.setProperty(index, "noteX", pos.x);
            notes.setProperty(index, "noteY", pos.y);
            notes.setProperty(index, "groupId", "");
            if (oldGroup !== "")
                reflowGroup(oldGroup);
        }
        _changed();
    }

    function addGroup(x: real, y: real): string {
        var id = newId();
        NoteBoardState.raise(id);
        groups.append({
            groupId: id,
            groupX: x,
            groupY: y,
            title: "Group"
        });
        _changed();
        return id;
    }

    function removeGroup(groupId: string): void {
        var index = groupIndex(groupId);
        if (index < 0)
            return;
        var g = groups.get(index);
        var originX = g.groupX + groupPadding;
        var originY = g.groupY + groupHeaderHeight + groupPadding;
        // Release notes where they currently are on screen
        for (var i = 0; i < notes.count; i++) {
            var n = notes.get(i);
            if (n.groupId === groupId) {
                notes.setProperty(i, "noteX", originX + n.localX);
                notes.setProperty(i, "noteY", originY + n.localY);
                notes.setProperty(i, "groupId", "");
                NoteBoardState.raise(n.noteId);
            }
        }
        groups.remove(index);
        _changed();
    }

    function updateGroup(groupId: string, data: var): void {
        var index = groupIndex(groupId);
        if (index < 0)
            return;
        var keyMap = { x: "groupX", y: "groupY" };
        for (var key in data)
            groups.setProperty(index, keyMap[key] || key, data[key]);
        _changed();
    }

    function getNotesInGroup(groupId: string): var {
        var result = [];
        for (var i = 0; i < notes.count; i++) {
            if (notes.get(i).groupId === groupId)
                result.push({ index: i, note: notes.get(i) });
        }
        return result;
    }

    // Size of a group from its content. Reads revision so bindings stay live.
    function groupSize(groupId: string): var {
        revision;
        var siblings = getNotesInGroup(groupId);
        var maxRight = 0;
        var maxBottom = 0;
        for (var i = 0; i < siblings.length; i++) {
            var n = siblings[i].note;
            maxRight = Math.max(maxRight, n.localX + n.noteWidth);
            maxBottom = Math.max(maxBottom, n.localY + n.noteHeight);
        }
        return {
            count: siblings.length,
            width: Math.max(groupMinWidth, maxRight + groupPadding * 2),
            height: siblings.length > 0 ? groupHeaderHeight + groupPadding * 2 + maxBottom : groupMinHeight
        };
    }

    // Global rect of a group, following a live drag
    function groupRect(groupId: string): var {
        var index = groupIndex(groupId);
        if (index < 0)
            return { x: 0, y: 0, width: 0, height: 0 };
        var g = groups.get(index);
        var dragging = NoteBoardState.draggingGroupId === groupId;
        var size = groupSize(groupId);
        return {
            x: dragging ? NoteBoardState.dragGroupX : g.groupX,
            y: dragging ? NoteBoardState.dragGroupY : g.groupY,
            width: size.width,
            height: size.height
        };
    }

    // Find next available slot for a new note using smart bin-packing
    function findNextSlot(groupId: string, noteWidth: real, noteHeight: real): var {
        var siblings = getNotesInGroup(groupId);
        if (siblings.length === 0)
            return { x: 0, y: 0 };

        var placed = [];
        for (var i = 0; i < siblings.length; i++) {
            var n = siblings[i].note;
            placed.push({ x: n.localX, y: n.localY, w: n.noteWidth, h: n.noteHeight });
        }
        return findBestPosition(placed, noteWidth, noteHeight);
    }

    // Reflow all notes in a group to achieve a square-ish layout
    function reflowGroup(groupId: string): void {
        var siblings = getNotesInGroup(groupId);
        if (siblings.length === 0) {
            _changed();
            return;
        }

        // Reading order by centre: same row if vertical centres are close
        siblings.sort(function (a, b) {
            var ay = a.note.localY + a.note.noteHeight / 2;
            var by = b.note.localY + b.note.noteHeight / 2;
            if (Math.abs(ay - by) > Math.min(a.note.noteHeight, b.note.noteHeight) / 2)
                return ay - by;
            return (a.note.localX + a.note.noteWidth / 2) - (b.note.localX + b.note.noteWidth / 2);
        });

        var cols = Math.max(1, Math.round(Math.sqrt(siblings.length)));

        // Simple row-based flow: place notes in rows of ~cols items
        var placed = [];
        var currentX = 0;
        var currentY = 0;
        var rowHeight = 0;
        var colInRow = 0;

        for (var j = 0; j < siblings.length; j++) {
            var note = siblings[j];
            var w = note.note.noteWidth;
            var h = note.note.noteHeight;

            if (colInRow >= cols && currentX > 0) {
                currentX = 0;
                currentY += rowHeight + gridGap;
                rowHeight = 0;
                colInRow = 0;
            }

            placed.push({ x: currentX, y: currentY, index: note.index });
            currentX += w + gridGap;
            rowHeight = Math.max(rowHeight, h);
            colInRow++;
        }

        for (var p = 0; p < placed.length; p++) {
            notes.setProperty(placed[p].index, "localX", placed[p].x);
            notes.setProperty(placed[p].index, "localY", placed[p].y);
        }
        _changed();
    }

    // Find the best position for a new note - tries to fit in gaps or at the end
    function findBestPosition(placed: var, w: real, h: real): var {
        if (placed.length === 0)
            return { x: 0, y: 0 };

        var count = placed.length + 1;
        var cols = Math.max(1, Math.round(Math.sqrt(count)));

        var maxBottom = 0;
        for (var i = 0; i < placed.length; i++)
            maxBottom = Math.max(maxBottom, placed[i].y + placed[i].h);

        // Group placed notes by rows (similar Y)
        var rows = [];
        for (var j = 0; j < placed.length; j++) {
            var pr = placed[j];
            var found = false;
            for (var ri = 0; ri < rows.length; ri++) {
                if (Math.abs(rows[ri].y - pr.y) < 5) {
                    rows[ri].rects.push(pr);
                    found = true;
                    break;
                }
            }
            if (!found)
                rows.push({ y: pr.y, rects: [pr] });
        }
        rows.sort(function (a, b) { return a.y - b.y; });

        for (var rj = 0; rj < rows.length; rj++) {
            var row = rows[rj];
            row.rects.sort(function (a, b) { return a.x - b.x; });

            if (row.rects[0].x >= w + gridGap)
                return { x: 0, y: row.y };

            for (var rk = 0; rk < row.rects.length - 1; rk++) {
                var left = row.rects[rk];
                var right = row.rects[rk + 1];
                var gapStart = left.x + left.w + gridGap;
                if (right.x - gapStart >= w)
                    return { x: gapStart, y: row.y };
            }

            if (row.rects.length < cols) {
                var lastRect = row.rects[row.rects.length - 1];
                return { x: lastRect.x + lastRect.w + gridGap, y: row.y };
            }
        }

        return { x: 0, y: maxBottom + gridGap };
    }

    // Snap free-floating notes to other notes/groups
    function findFreeNotePosition(noteId: string, targetX: real, targetY: real, noteWidth: real, noteHeight: real, wantsOverlap: bool): var {
        if (wantsOverlap)
            return { x: targetX, y: targetY };

        var obstacles = [];
        for (var i = 0; i < notes.count; i++) {
            var n = notes.get(i);
            if (n.noteId !== noteId && n.groupId === "")
                obstacles.push({ x: n.noteX, y: n.noteY, w: n.noteWidth, h: n.noteHeight });
        }
        for (var j = 0; j < groups.count; j++) {
            var r0 = groupRect(groups.get(j).groupId);
            obstacles.push({ x: r0.x, y: r0.y, w: r0.width, h: r0.height });
        }

        if (obstacles.length === 0)
            return { x: targetX, y: targetY };

        var x = targetX;
        var y = targetY;

        for (var k = 0; k < obstacles.length; k++) {
            var r = obstacles[k];

            if (Math.abs(x - (r.x + r.w + gridGap)) < snapDistance) x = r.x + r.w + gridGap;
            if (Math.abs(x + noteWidth + gridGap - r.x) < snapDistance) x = r.x - noteWidth - gridGap;
            if (Math.abs(x - r.x) < snapDistance) x = r.x;

            if (Math.abs(y - (r.y + r.h + gridGap)) < snapDistance) y = r.y + r.h + gridGap;
            if (Math.abs(y + noteHeight + gridGap - r.y) < snapDistance) y = r.y - noteHeight - gridGap;
            if (Math.abs(y - r.y) < snapDistance) y = r.y;
        }

        var hasOverlap = false;
        for (var m = 0; m < obstacles.length; m++) {
            if (rectsOverlap(x, y, noteWidth, noteHeight, obstacles[m].x, obstacles[m].y, obstacles[m].w, obstacles[m].h)) {
                hasOverlap = true;
                break;
            }
        }

        if (!hasOverlap)
            return { x: x, y: y };

        // Find nearest non-overlapping spot
        var candidates = [];
        for (var c = 0; c < obstacles.length; c++) {
            var ob = obstacles[c];
            candidates.push({ x: ob.x + ob.w + gridGap, y: ob.y });
            candidates.push({ x: ob.x - noteWidth - gridGap, y: ob.y });
            candidates.push({ x: ob.x, y: ob.y + ob.h + gridGap });
            candidates.push({ x: ob.x, y: ob.y - noteHeight - gridGap });
        }

        var bestPos = { x: targetX, y: targetY };
        var bestDist = Infinity;

        for (var p = 0; p < candidates.length; p++) {
            var pos = candidates[p];
            var valid = true;
            for (var v = 0; v < obstacles.length; v++) {
                if (rectsOverlap(pos.x, pos.y, noteWidth, noteHeight, obstacles[v].x, obstacles[v].y, obstacles[v].w, obstacles[v].h)) {
                    valid = false;
                    break;
                }
            }
            if (valid) {
                var dist = Math.abs(pos.x - targetX) + Math.abs(pos.y - targetY);
                if (dist < bestDist) {
                    bestDist = dist;
                    bestPos = pos;
                }
            }
        }

        return bestPos;
    }

    function rectsOverlap(x1: real, y1: real, w1: real, h1: real, x2: real, y2: real, w2: real, h2: real): bool {
        return x1 < x2 + w2 && x1 + w1 > x2 && y1 < y2 + h2 && y1 + h1 > y2;
    }

    Timer {
        id: saveTimer
        interval: 400
        repeat: false
        onTriggered: root.saveNow()
    }

    FileView {
        id: fileView
        path: root.notesFile
        watchChanges: true
        atomicWrites: true
        // Our own writes are filtered out by comparing against lastJson
        onFileChanged: {
            if (!saveTimer.running)
                reload();
        }
        onLoaded: root.load(text())
    }
}
