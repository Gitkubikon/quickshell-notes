import QtQuick
import QtQuick.Controls
import "../../common"
import "../../services"

Rectangle {
    id: root
    required property int noteIndex
    required property string noteId
    required property real noteWidth
    required property real noteHeight
    required property string text
    required property string groupId
    required property real localX
    required property real localY
    required property real groupHeaderHeight
    required property real groupPadding
    required property Item parentGroup
    required property Item boardItem

    property bool isFocused: NoteBoardState.focusedNoteId === noteId
    property int zOrder: 0
    property bool hovered: hoverArea.containsMouse || textArea.activeFocus
    property real noteScale: 1.0
    property bool isDragging: false

    x: groupPadding + localX
    y: groupHeaderHeight + groupPadding + localY
    width: noteWidth
    height: noteHeight
    radius: 6
    scale: noteScale
    opacity: noteScale
    z: isDragging ? 10000 : (isFocused ? 5000 + zOrder : zOrder)
    color: Appearance.colors.colLayer1
    border.width: isFocused ? 2 : 0
    border.color: Appearance.colors.colPrimary

    Behavior on border.width { NumberAnimation { duration: 100 } }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        anchors.rightMargin: 18
        anchors.bottomMargin: 18
        cursorShape: root.isDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        preventStealing: true

        property point startMouse
        property point globalStartPos

        onPressed: (mouse) => {
            root.zOrder = NoteBoardState.focusNote(root.noteId);
            startMouse = mapToItem(root.boardItem, mouse.x, mouse.y);
            globalStartPos = root.mapToItem(root.boardItem, 0, 0);
        }

        onPositionChanged: (mouse) => {
            if (!pressed) return;

            var boardMouse = mapToItem(root.boardItem, mouse.x, mouse.y);
            var dx = boardMouse.x - startMouse.x;
            var dy = boardMouse.y - startMouse.y;

            if (!root.isDragging && (Math.abs(dx) > 5 || Math.abs(dy) > 5)) {
                root.isDragging = true;
                root.parent = root.boardItem;
                root.x = globalStartPos.x;
                root.y = globalStartPos.y;
            }

            if (root.isDragging) {
                root.x = globalStartPos.x + dx;
                root.y = globalStartPos.y + dy;
            }
        }

        onReleased: {
            if (!root.isDragging) return;

            root.isDragging = false;
            var dropX = root.x;
            var dropY = root.y;
            var originalGroupId = root.groupId;

            // Clear drag state first so group bounds unfreeze
            NoteBoardState.endDrag();

            // Check if we're inside original group bounds (use parentGroup directly)
            var groupBounds = root.parentGroup.mapToItem(root.boardItem, 0, 0);
            var gx = groupBounds.x;
            var gy = groupBounds.y;
            var gw = root.parentGroup.width;
            var gh = root.parentGroup.height;

            var cx = dropX + root.width / 2;
            var cy = dropY + root.height / 2;

            console.log("=== DROP DEBUG ===");
            console.log("dropX:", dropX, "dropY:", dropY);
            console.log("note center cx:", cx, "cy:", cy);
            console.log("group bounds: x:", gx, "y:", gy, "w:", gw, "h:", gh);
            console.log("group right:", gx + gw, "group bottom:", gy + gh);

            // Check if center is inside original group
            var insideOriginalGroup = (cx >= gx && cx <= gx + gw && cy >= gy && cy <= gy + gh);
            console.log("insideOriginalGroup:", insideOriginalGroup);

            if (insideOriginalGroup) {
                console.log("-> Snapping back to same group");
                // Still in same group - snap back, no change
                root.parent = root.parentGroup;
                return;
            }

            // Check other groups (exclude original)
            var targetGroupId = NoteBoardState.findGroupAt(cx, cy, originalGroupId);
            console.log("targetGroupId from findGroupAt:", targetGroupId);

            if (targetGroupId !== "") {
                console.log("-> Moving to different group:", targetGroupId);
                // Hide this component immediately since it will be recreated in new group
                root.visible = false;
                // Different group
                var pos = NotePersistence.findNextSlot(targetGroupId, root.width, root.height);
                NotePersistence.updateNote(root.noteIndex, {
                    groupId: targetGroupId,
                    localX: pos.x,
                    localY: pos.y
                });
                // Reflow both groups (defer to avoid conflicts)
                Qt.callLater(NotePersistence.reflowGroup, originalGroupId);
                Qt.callLater(NotePersistence.reflowGroup, targetGroupId);
            } else {
                console.log("-> Becoming free note at:", dropX, dropY);
                // Hide this component immediately since it will be replaced by NoteWidget
                root.visible = false;
                // Outside all groups - become free note
                NotePersistence.updateNote(root.noteIndex, {
                    x: dropX,
                    y: dropY,
                    groupId: ""
                });
                // Reflow remaining notes in the old group (defer to avoid conflicts)
                Qt.callLater(NotePersistence.reflowGroup, originalGroupId);
            }
        }
    }

    // Close button
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 3
        width: 18
        height: 18
        radius: 3
        visible: root.hovered || root.isFocused
        color: closeMa.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
        z: 100
        Text {
            anchors.centerIn: parent
            text: "\u00d7"
            font.pixelSize: 12
            color: Appearance.colors.colSubtext
        }
        MouseArea {
            id: closeMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: NotePersistence.removeNote(root.noteIndex)
        }
    }

    // Resize handle
    Rectangle {
        id: resizeHandle
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 2
        width: 16
        height: 16
        radius: 2
        visible: root.hovered || root.isFocused
        color: resizeMa.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
        z: 100

        Canvas {
            anchors.fill: parent
            anchors.margins: 3
            onPaint: {
                var ctx = getContext("2d");
                ctx.strokeStyle = Appearance.colors.colSubtext;
                ctx.lineWidth = 1.5;
                ctx.beginPath();
                ctx.moveTo(width, 0);
                ctx.lineTo(0, height);
                ctx.moveTo(width, height * 0.5);
                ctx.lineTo(width * 0.5, height);
                ctx.stroke();
            }
        }

        MouseArea {
            id: resizeMa
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.SizeFDiagCursor
            preventStealing: true

            property real startWidth: 0
            property real startHeight: 0
            property real startX: 0
            property real startY: 0

            onPressed: (mouse) => {
                root.zOrder = NoteBoardState.focusNote(root.noteId);
                startWidth = root.width;
                startHeight = root.height;
                startX = mouseX;
                startY = mouseY;
            }

            onPositionChanged: {
                if (pressed) {
                    var dx = mouseX - startX;
                    var dy = mouseY - startY;
                    root.width = Math.max(80, startWidth + dx);
                    root.height = Math.max(50, startHeight + dy);
                }
            }

            onReleased: {
                NotePersistence.updateNote(root.noteIndex, { width: root.width, height: root.height });
            }
        }
    }

    TextArea {
        id: textArea
        anchors.fill: parent
        anchors.margins: 6
        anchors.rightMargin: 22
        text: root.text
        color: Appearance.colors.colOnLayer1
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.Wrap
        background: null
        selectByMouse: true
        placeholderText: "..."
        placeholderTextColor: Appearance.colors.colSubtext

        onActiveFocusChanged: {
            if (activeFocus) {
                root.zOrder = NoteBoardState.focusNote(root.noteId);
            }
        }

        onTextChanged: {
            if (text !== root.text)
                NotePersistence.updateNote(root.noteIndex, { text: text });
        }
    }
}
