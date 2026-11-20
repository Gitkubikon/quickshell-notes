import QtQuick
import QtQuick.Controls
import "../../common"
import "../../services"

// A note, free or grouped. Every screen has its own copy; position comes from
// the model (or the shared drag state) in global coordinates, so copies stay in sync.
Rectangle {
    id: root
    required property string noteId
    required property real noteX
    required property real noteY
    required property real noteWidth
    required property real noteHeight
    required property string text
    required property string groupId
    required property real localX
    required property real localY
    required property string screenName
    // Group items of this screen, keyed by groupId
    required property var groupItems

    property real noteScale: 1.0
    property bool editing: false
    property bool animReady: false
    property bool localDrop: false

    readonly property bool grouped: groupId !== ""
    readonly property Item groupItem: grouped ? (groupItems[groupId] ?? null) : null
    readonly property bool isFocused: NoteBoardState.focusedNoteId === noteId
    readonly property bool isDragging: NoteBoardState.draggingNoteId === noteId
    readonly property bool followsGroupDrag: grouped && NoteBoardState.draggingGroupId === groupId
    readonly property bool hovered: hover.hovered || textArea.activeFocus

    x: isDragging ? NoteBoardState.dragNoteX
        : groupItem ? groupItem.x + NotePersistence.groupPadding + localX
        : noteX
    y: isDragging ? NoteBoardState.dragNoteY
        : groupItem ? groupItem.y + NotePersistence.groupHeaderHeight + NotePersistence.groupPadding + localY
        : noteY
    z: isDragging ? 100000 : groupItem ? groupItem.z + 0.5 : NoteBoardState.zFor(noteId)
    width: noteWidth
    height: noteHeight
    visible: !grouped || groupItem !== null
    radius: 6
    scale: noteScale
    opacity: noteScale
    color: Appearance.colors.colLayer1
    border.width: isFocused ? 2 : 0
    border.color: Appearance.colors.colPrimary

    // Animate snaps and reflows, never live movement
    readonly property bool animatePosition: animReady && !dragHandler.active && !resizeHandler.active && !followsGroupDrag && (!isDragging || localDrop)
    Behavior on x { enabled: root.animatePosition; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: root.animatePosition; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on border.width { NumberAnimation { duration: 100 } }

    Timer {
        interval: 300
        running: true
        onTriggered: root.animReady = true
    }

    Component.onCompleted: {
        if (NoteBoardState.pendingEditId === noteId && NoteBoardState.pendingEditScreen === screenName) {
            NoteBoardState.pendingEditId = "";
            NoteBoardState.focusNote(noteId, screenName);
            editing = true;
            textArea.forceActiveFocus();
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.OpenHandCursor
    }

    TapHandler {
        onPressedChanged: {
            NoteBoardState.pointerHeld = pressed;
            if (pressed)
                NoteBoardState.focusNote(root.noteId, root.screenName);
        }
        onTapped: {
            root.editing = true;
            if (!textArea.activeFocus)
                textArea.forceActiveFocus();
        }
    }

    // Drag from anywhere (text selection by mouse only while editing).
    // Uses scene deltas so it keeps working past this screen's edge.
    DragHandler {
        id: dragHandler
        target: null
        enabled: !resizeHover.hovered && !resizeHandler.active && !closeMa.containsMouse
        cursorShape: Qt.ClosedHandCursor

        property real startX: 0
        property real startY: 0

        onActiveChanged: {
            if (active) {
                NoteBoardState.focusNote(root.noteId, root.screenName);
                root.localDrop = false;
                startX = root.x;
                startY = root.y;
                NoteBoardState.beginNoteDrag(root.noteId, root.groupId, startX, startY);
            } else {
                root.localDrop = true;
                NotePersistence.dropNote(root.noteId, NoteBoardState.dragNoteX, NoteBoardState.dragNoteY, NoteBoardState.wantsOverlap());
                NoteBoardState.endNoteDrag();
            }
        }

        onCentroidChanged: {
            if (!active)
                return;
            NoteBoardState.moveNoteDrag(startX + centroid.scenePosition.x - centroid.scenePressPosition.x, startY + centroid.scenePosition.y - centroid.scenePressPosition.y, root.width, root.height);
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
            text: "×"
            font.pixelSize: 13
            color: Appearance.colors.colSubtext
        }
        MouseArea {
            id: closeMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: NotePersistence.removeNote(root.noteId)
        }
    }

    // Resize handle (hit area larger than the visual)
    Item {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 22
        height: 22
        z: 100

        HoverHandler {
            id: resizeHover
            cursorShape: Qt.SizeFDiagCursor
        }

        DragHandler {
            id: resizeHandler
            target: null
            cursorShape: Qt.SizeFDiagCursor

            property real startWidth: 0
            property real startHeight: 0

            onActiveChanged: {
                if (active) {
                    NoteBoardState.focusNote(root.noteId, root.screenName);
                    startWidth = root.noteWidth;
                    startHeight = root.noteHeight;
                    NoteBoardState.resizingNoteId = root.noteId;
                } else {
                    NoteBoardState.resizingNoteId = "";
                    NotePersistence.finishResize(root.noteId);
                }
            }

            onCentroidChanged: {
                if (!active)
                    return;
                NotePersistence.resizeNote(root.noteId, startWidth + centroid.scenePosition.x - centroid.scenePressPosition.x, startHeight + centroid.scenePosition.y - centroid.scenePressPosition.y);
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 3
            width: 14
            height: 14
            radius: 3
            visible: root.hovered || root.isFocused || resizeHandler.active
            color: resizeHover.hovered || resizeHandler.active ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1

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
        // Mouse selection would swallow drags, so only enable it while editing
        selectByMouse: root.editing
        placeholderText: "..."
        placeholderTextColor: Appearance.colors.colSubtext

        Keys.onEscapePressed: {
            root.editing = false;
            focus = false;
        }

        onActiveFocusChanged: {
            if (activeFocus)
                NoteBoardState.focusNote(root.noteId, root.screenName);
            else
                root.editing = false;
        }

        onTextChanged: {
            if (text !== root.text)
                NotePersistence.updateNote(root.noteId, { text: text });
        }
    }
}
