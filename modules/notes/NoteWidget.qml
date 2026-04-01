import QtQuick
import QtQuick.Controls
import "../../common"
import "../../services"

Rectangle {
    id: root
    required property int index
    required property string noteId
    required property real noteX
    required property real noteY
    required property real noteWidth
    required property real noteHeight
    required property string text
    required property string groupId

    property bool isFocused: NoteBoardState.focusedNoteId === noteId
    property int zOrder: 0
    property bool hovered: hoverArea.containsMouse || textArea.activeFocus
    property real noteScale: 1.0
    property bool isDragging: dragHandler.active

    width: noteWidth
    height: noteHeight
    x: noteX
    y: noteY
    radius: 6

    Component.onCompleted: console.log("NoteWidget created - noteId:", noteId, "x:", x, "y:", y, "noteX:", noteX, "noteY:", noteY)
    scale: noteScale
    opacity: noteScale
    z: isDragging ? 10000 : (isFocused ? 5000 + zOrder : zOrder)
    color: Appearance.colors.colLayer1
    border.width: isFocused ? 2 : 0
    border.color: Appearance.colors.colPrimary

    Behavior on border.width { NumberAnimation { duration: 100 } }

    // Hover detection
    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.OpenHandCursor

        onPressed: (mouse) => {
            root.zOrder = NoteBoardState.focusNote(root.noteId);
            mouse.accepted = false;  // Let DragHandler take over
        }
    }

    // Drag handling - let Qt handle the actual dragging smoothly
    DragHandler {
        id: dragHandler
        target: root
        dragThreshold: 3
        cursorShape: Qt.ClosedHandCursor

        onActiveChanged: {
            if (active) {
                root.zOrder = NoteBoardState.focusNote(root.noteId);
                NoteBoardState.startDrag(root.x + root.width / 2, root.y + root.height / 2, "");
            } else {
                // Drag ended - apply snap logic
                var cx = root.x + root.width / 2;
                var cy = root.y + root.height / 2;
                var targetId = NoteBoardState.findGroupAt(cx, cy, "");
                var wantsOverlap = NoteBoardState.wantsOverlap();

                NoteBoardState.endDrag();

                if (targetId !== "") {
                    // Dropped into a group - find next slot and reflow
                    var pos = NotePersistence.findNextSlot(targetId, root.width, root.height);
                    NotePersistence.updateNote(root.index, {
                        groupId: targetId,
                        localX: pos.x,
                        localY: pos.y
                    });
                    Qt.callLater(NotePersistence.reflowGroup, targetId);
                } else {
                    // Free-floating - snap to other notes/groups
                    var finalPos = NotePersistence.findFreeNotePosition(
                        root.noteId, root.x, root.y, root.width, root.height, wantsOverlap
                    );
                    NotePersistence.updateNote(root.index, {
                        x: finalPos.x,
                        y: finalPos.y,
                        groupId: ""
                    });
                }
            }
        }

        onCentroidChanged: {
            if (active) {
                NoteBoardState.updateDrag(root.x + root.width / 2, root.y + root.height / 2);
            }
        }
    }

    // Close button
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 4
        width: 20
        height: 20
        radius: 4
        visible: root.hovered || root.isFocused
        color: closeMa.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
        z: 100
        Text {
            anchors.centerIn: parent
            text: "\u00d7"
            font.pixelSize: 13
            color: Appearance.colors.colSubtext
        }
        MouseArea {
            id: closeMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: NotePersistence.removeNote(root.index)
        }
    }

    // Resize handle
    Rectangle {
        id: resizeHandle
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 3
        width: 14
        height: 14
        radius: 3
        visible: root.hovered || root.isFocused
        color: resizeArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
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
            id: resizeArea
            anchors.fill: parent
            anchors.margins: -4  // Extend hit area
            hoverEnabled: true
            cursorShape: Qt.SizeFDiagCursor
        }

        DragHandler {
            id: resizeDragHandler
            target: null
            cursorShape: Qt.SizeFDiagCursor
            property real startWidth: 0
            property real startHeight: 0
            onActiveChanged: {
                if (active) {
                    root.zOrder = NoteBoardState.focusNote(root.noteId);
                    startWidth = root.width;
                    startHeight = root.height;
                } else {
                    NotePersistence.updateNote(root.index, { width: root.width, height: root.height });
                }
            }
            onTranslationChanged: {
                root.width = Math.max(100, startWidth + translation.x);
                root.height = Math.max(60, startHeight + translation.y);
            }
        }
    }

    TextArea {
        id: textArea
        anchors.fill: parent
        anchors.margins: 8
        anchors.rightMargin: 28
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
                NotePersistence.updateNote(root.index, { text: text });
        }
    }
}
