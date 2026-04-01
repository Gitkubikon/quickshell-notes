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
    property ListModel groups: ListModel {}
    property bool saving: false

    readonly property real gridGap: 8
    readonly property real snapDistance: 20

    function _noteToModel(obj: var): var {
        return {
            noteId: obj.id || Date.now().toString(),
            noteX: obj.x || 0,
            noteY: obj.y || 0,
            noteWidth: obj.width || 180,
            noteHeight: obj.height || 100,
            text: obj.text || "",
            groupId: obj.groupId || "",
            localX: obj.localX || 0,
            localY: obj.localY || 0
        };
    }

    function _groupToModel(obj: var): var {
        return {
            groupId: obj.id || Date.now().toString(),
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
        try {
            var loaded = JSON.parse(data);
            notes.clear();
            groups.clear();

            if (loaded && typeof loaded === "object" && !Array.isArray(loaded)) {
                if (Array.isArray(loaded.notes)) {
                    for (var i = 0; i < loaded.notes.length; i++)
                        notes.append(_noteToModel(loaded.notes[i]));
                }
                if (Array.isArray(loaded.groups)) {
                    for (var j = 0; j < loaded.groups.length; j++)
                        groups.append(_groupToModel(loaded.groups[j]));
                }
            } else if (Array.isArray(loaded)) {
                for (var k = 0; k < loaded.length; k++)
                    notes.append(_noteToModel(loaded[k]));
            }
        } catch (e) {
            console.warn("Failed to parse notes:", e);
            notes.clear();
            groups.clear();
        }
    }

    function save(): void { saveTimer.restart(); }

    function saveNow(): void {
        var notesArr = [];
        for (var i = 0; i < notes.count; i++)
            notesArr.push(_noteToJson(i));

        var groupsArr = [];
        for (var j = 0; j < groups.count; j++)
            groupsArr.push(_groupToJson(j));

        const json = JSON.stringify({ notes: notesArr, groups: groupsArr }, null, 4);
        saving = true;
        writer.stdinEnabled = true;
        writer.stdinData = json;
        writer.command = ["sh", "-c", `mkdir -p '${statePath}' && cat > '${notesFile}'`];
        writer.running = true;
    }

    function addNote(x: real, y: real, gid: var): void {
        var groupId = gid || "";
        var localX = 0;
        var localY = 0;

        if (groupId !== "") {
            // Find next available position (flow layout for new notes)
            var pos = findNextSlot(groupId, 180, 100);
            localX = pos.x;
            localY = pos.y;
        }

        notes.append({
            noteId: Date.now().toString(),
            noteX: x,
            noteY: y,
            noteWidth: 180,
            noteHeight: 100,
            text: "",
            groupId: groupId,
            localX: localX,
            localY: localY
        });
        save();
    }

    function removeNote(index: int): void {
        var groupId = notes.get(index).groupId;
        notes.remove(index);
        if (groupId && groupId !== "") {
            Qt.callLater(reflowGroup, groupId);
        }
        save();
    }

    function updateNote(index: int, data: var): void {
        if (index < 0 || index >= notes.count) return;
        var keyMap = { x: "noteX", y: "noteY", width: "noteWidth", height: "noteHeight" };

        // Update position properties BEFORE groupId to avoid visual glitches
        // (when groupId changes, visibility changes, so position must be set first)
        var orderedKeys = ["x", "y", "width", "height", "localX", "localY", "text", "groupId"];
        for (var i = 0; i < orderedKeys.length; i++) {
            var key = orderedKeys[i];
            if (key in data) {
                var role = keyMap[key] || key;
                notes.setProperty(index, role, data[key]);
            }
        }
        // Handle any other keys not in our ordered list
        for (var k in data) {
            if (orderedKeys.indexOf(k) === -1) {
                var r = keyMap[k] || k;
                notes.setProperty(index, r, data[k]);
            }
        }
        save();
    }

    function addGroup(x: real, y: real): void {
        groups.append({
            groupId: Date.now().toString(),
            groupX: x,
            groupY: y,
            title: "Group"
        });
        save();
    }

    function removeGroup(index: int): void {
        var gid = groups.get(index).groupId;
        for (var i = 0; i < notes.count; i++) {
            if (notes.get(i).groupId === gid)
                notes.setProperty(i, "groupId", "");
        }
        groups.remove(index);
        save();
    }

    function updateGroup(index: int, data: var): void {
        if (index < 0 || index >= groups.count) return;
        var keyMap = { x: "groupX", y: "groupY" };
        for (var key in data) {
            var role = keyMap[key] || key;
            groups.setProperty(index, role, data[key]);
        }
        save();
    }

    function getNotesInGroup(groupId: string): var {
        var result = [];
        for (var i = 0; i < notes.count; i++) {
            if (notes.get(i).groupId === groupId)
                result.push({ index: i, note: notes.get(i) });
        }
        return result;
    }

    // Find next available slot for a new note using smart bin-packing
    function findNextSlot(groupId: string, noteWidth: real, noteHeight: real): var {
        var siblings = getNotesInGroup(groupId);
        if (siblings.length === 0) return { x: 0, y: 0 };

        // Collect all existing note rectangles as "placed" array
        var placed = [];
        for (var i = 0; i < siblings.length; i++) {
            var n = siblings[i].note;
            placed.push({ x: n.localX, y: n.localY, w: n.noteWidth, h: n.noteHeight });
        }

        // Use the same algorithm as reflow for consistency
        return findBestPosition(placed, noteWidth, noteHeight);
    }

    // Reflow all notes in a group to achieve a square-ish layout
    function reflowGroup(groupId: string): void {
        var siblings = getNotesInGroup(groupId);
        if (siblings.length === 0) return;

        // Sort by original position to maintain relative order
        siblings.sort(function(a, b) {
            var scoreA = a.note.localY * 10000 + a.note.localX;
            var scoreB = b.note.localY * 10000 + b.note.localX;
            return scoreA - scoreB;
        });

        // Calculate target columns for square-ish layout
        var count = siblings.length;
        // For a square grid, we want roughly sqrt(n) columns
        // But we need to account for varying note sizes
        var cols = Math.max(1, Math.round(Math.sqrt(count)));

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

            // Wrap to next row after cols items
            if (colInRow >= cols && currentX > 0) {
                currentX = 0;
                currentY += rowHeight + gridGap;
                rowHeight = 0;
                colInRow = 0;
            }

            placed.push({ x: currentX, y: currentY, w: w, h: h, index: note.index });
            currentX += w + gridGap;
            rowHeight = Math.max(rowHeight, h);
            colInRow++;
        }

        // Update all note positions
        for (var p = 0; p < placed.length; p++) {
            notes.setProperty(placed[p].index, "localX", placed[p].x);
            notes.setProperty(placed[p].index, "localY", placed[p].y);
        }

        save();
    }

    // Find the best position for a new note - tries to fit in gaps or at the end
    function findBestPosition(placed: var, w: real, h: real): var {
        if (placed.length === 0) return { x: 0, y: 0 };

        var count = placed.length + 1; // Including the new note
        var cols = Math.max(1, Math.round(Math.sqrt(count)));

        // Calculate current bounds
        var maxBottom = 0;
        for (var i = 0; i < placed.length; i++) {
            var r = placed[i];
            maxBottom = Math.max(maxBottom, r.y + r.h);
        }

        // Group placed notes by rows (similar Y)
        var rows = [];
        for (var j = 0; j < placed.length; j++) {
            var pr = placed[j];
            var found = false;
            for (var ri = 0; ri < rows.length; ri++) {
                if (Math.abs(rows[ri].y - pr.y) < 5) {
                    rows[ri].rects.push(pr);
                    rows[ri].maxHeight = Math.max(rows[ri].maxHeight, pr.h);
                    found = true;
                    break;
                }
            }
            if (!found) {
                rows.push({ y: pr.y, rects: [pr], maxHeight: pr.h });
            }
        }
        rows.sort(function(a, b) { return a.y - b.y; });

        // Try to find a gap in existing rows or append to incomplete row
        for (var rj = 0; rj < rows.length; rj++) {
            var row = rows[rj];
            row.rects.sort(function(a, b) { return a.x - b.x; });

            // Check gap at start of row
            if (row.rects[0].x >= w + gridGap) {
                return { x: 0, y: row.y };
            }

            // Check gaps between rects
            for (var rk = 0; rk < row.rects.length - 1; rk++) {
                var left = row.rects[rk];
                var right = row.rects[rk + 1];
                var gapStart = left.x + left.w + gridGap;
                var gapWidth = right.x - gapStart;
                if (gapWidth >= w) {
                    return { x: gapStart, y: row.y };
                }
            }

            // Check if row has room for more (less than cols items)
            if (row.rects.length < cols) {
                var lastRect = row.rects[row.rects.length - 1];
                return { x: lastRect.x + lastRect.w + gridGap, y: row.y };
            }
        }

        // Start a new row below everything
        return { x: 0, y: maxBottom + gridGap };
    }

    // Snap position to nearby notes (for reordering within group)
    function snapInGroup(groupId: string, noteId: string, rawX: real, rawY: real, noteWidth: real, noteHeight: real): var {
        var siblings = getNotesInGroup(groupId);
        var x = Math.max(0, rawX);
        var y = Math.max(0, rawY);

        // Collect all sibling rectangles
        var rects = [];
        for (var i = 0; i < siblings.length; i++) {
            var n = siblings[i].note;
            if (n.noteId !== noteId) {
                rects.push({ x: n.localX, y: n.localY, w: n.noteWidth, h: n.noteHeight });
            }
        }

        // Snap to origin first
        if (x < snapDistance) x = 0;
        if (y < snapDistance) y = 0;

        if (rects.length === 0) return { x: x, y: y };

        // Find best snap - only snap if close enough
        var bestSnapX = null;
        var bestSnapY = null;
        var bestDistX = snapDistance;
        var bestDistY = snapDistance;

        for (var j = 0; j < rects.length; j++) {
            var r = rects[j];

            // X snaps
            var snaps_x = [
                { target: r.x, dist: Math.abs(x - r.x) },  // align left
                { target: r.x + r.w + gridGap, dist: Math.abs(x - (r.x + r.w + gridGap)) },  // right of
                { target: r.x - noteWidth - gridGap, dist: Math.abs(x - (r.x - noteWidth - gridGap)) }  // left of
            ];

            for (var sx = 0; sx < snaps_x.length; sx++) {
                if (snaps_x[sx].dist < bestDistX && snaps_x[sx].target >= 0) {
                    bestDistX = snaps_x[sx].dist;
                    bestSnapX = snaps_x[sx].target;
                }
            }

            // Y snaps
            var snaps_y = [
                { target: r.y, dist: Math.abs(y - r.y) },  // align top
                { target: r.y + r.h + gridGap, dist: Math.abs(y - (r.y + r.h + gridGap)) },  // below
                { target: r.y - noteHeight - gridGap, dist: Math.abs(y - (r.y - noteHeight - gridGap)) }  // above
            ];

            for (var sy = 0; sy < snaps_y.length; sy++) {
                if (snaps_y[sy].dist < bestDistY && snaps_y[sy].target >= 0) {
                    bestDistY = snaps_y[sy].dist;
                    bestSnapY = snaps_y[sy].target;
                }
            }
        }

        return {
            x: bestSnapX !== null ? bestSnapX : x,
            y: bestSnapY !== null ? bestSnapY : y
        };
    }

    // Get bounding box of all notes in group
    function getGroupContentBounds(groupId: string): var {
        var siblings = getNotesInGroup(groupId);
        var maxRight = 0;
        var maxBottom = 0;

        for (var i = 0; i < siblings.length; i++) {
            var n = siblings[i].note;
            var right = n.localX + n.noteWidth;
            var bottom = n.localY + n.noteHeight;
            if (right > maxRight) maxRight = right;
            if (bottom > maxBottom) maxBottom = bottom;
        }

        return { width: maxRight, height: maxBottom };
    }

    // Snap free-floating notes to other notes/groups
    function findFreeNotePosition(noteId: string, targetX: real, targetY: real, noteWidth: real, noteHeight: real, wantsOverlap: bool): var {
        if (wantsOverlap) return { x: targetX, y: targetY };

        var obstacles = [];

        for (var i = 0; i < notes.count; i++) {
            var n = notes.get(i);
            if (n.noteId !== noteId && (!n.groupId || n.groupId === "")) {
                obstacles.push({ x: n.noteX, y: n.noteY, w: n.noteWidth, h: n.noteHeight });
            }
        }

        for (var j = 0; j < groups.count; j++) {
            var g = groups.get(j);
            var size = NoteBoardState.groupSizes[g.groupId] || { width: 200, height: 100 };
            obstacles.push({ x: g.groupX, y: g.groupY, w: size.width, h: size.height });
        }

        if (obstacles.length === 0) return { x: targetX, y: targetY };

        // Snap to edges
        var x = targetX;
        var y = targetY;

        for (var k = 0; k < obstacles.length; k++) {
            var r = obstacles[k];

            // Horizontal snaps
            if (Math.abs(x - (r.x + r.w + gridGap)) < snapDistance) x = r.x + r.w + gridGap;
            if (Math.abs(x + noteWidth + gridGap - r.x) < snapDistance) x = r.x - noteWidth - gridGap;
            if (Math.abs(x - r.x) < snapDistance) x = r.x;

            // Vertical snaps
            if (Math.abs(y - (r.y + r.h + gridGap)) < snapDistance) y = r.y + r.h + gridGap;
            if (Math.abs(y + noteHeight + gridGap - r.y) < snapDistance) y = r.y - noteHeight - gridGap;
            if (Math.abs(y - r.y) < snapDistance) y = r.y;
        }

        // Check if we're overlapping and need to find alternative
        var hasOverlap = false;
        for (var m = 0; m < obstacles.length; m++) {
            if (rectsOverlap(x, y, noteWidth, noteHeight,
                            obstacles[m].x, obstacles[m].y, obstacles[m].w, obstacles[m].h)) {
                hasOverlap = true;
                break;
            }
        }

        if (!hasOverlap) return { x: x, y: y };

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
        var bestDist = 999999;

        for (var p = 0; p < candidates.length; p++) {
            var pos = candidates[p];
            var valid = true;
            for (var v = 0; v < obstacles.length; v++) {
                if (rectsOverlap(pos.x, pos.y, noteWidth, noteHeight,
                                obstacles[v].x, obstacles[v].y, obstacles[v].w, obstacles[v].h)) {
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
        path: root.notesFile
        watchChanges: true
        onFileChanged: { if (!root.saving && !saveTimer.running) reload(); }
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
        onExited: (exitCode, exitStatus) => { root.saving = false; }
    }
}
