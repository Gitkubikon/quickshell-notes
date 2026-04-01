import QtQuick
import QtQuick.Controls
import "../../common"
import "../../services"

Item {
    id: root
    required property int index
    required property string groupId
    required property real groupX
    required property real groupY
    required property string title

    property bool isFocused: NoteBoardState.focusedGroupId === groupId
    property int zOrder: 0
    property bool hovered: headerHover.containsMouse || titleField.activeFocus
    property real groupScale: 1.0
    property bool isDragging: headerDragHandler.active
    property bool dropHighlight: NoteBoardState.noteDragging &&
        NoteBoardState.findGroupAt(NoteBoardState.dragX, NoteBoardState.dragY, "") === groupId

    property var notesInGroup: NotePersistence.getNotesInGroup(groupId)
    property int noteCount: notesInGroup.length

    readonly property real padding: 8
    readonly property real headerHeight: 32
    readonly property real minWidth: 180
    readonly property real minHeight: 70

    // Freeze bounds while a note is being dragged from this group
    property bool freezeBounds: NoteBoardState.draggingFromGroupId === groupId
    property var contentBounds: NotePersistence.getGroupContentBounds(groupId)
    property real contentRight: contentBounds ? contentBounds.width : 0
    property real contentBottom: contentBounds ? contentBounds.height : 0
    property real frozenWidth: 0
    property real frozenHeight: 0

    width: freezeBounds ? frozenWidth : Math.max(minWidth, contentRight + padding * 2)
    height: freezeBounds ? frozenHeight : (headerHeight + (noteCount > 0 ? padding + contentBottom + padding : minHeight - headerHeight))

    onFreezeBoundsChanged: {
        if (freezeBounds) {
            frozenWidth = width;
            frozenHeight = height;
        }
    }
    x: groupX
    y: groupY
    scale: groupScale
    opacity: groupScale
    z: isDragging ? 9000 : (isFocused ? 4000 + zOrder : zOrder)

    // Border frame
    Rectangle {
        id: borderFrame
        anchors.fill: parent
        radius: 8
        color: "transparent"
        border.width: dropHighlight ? 3 : (isFocused ? 2 : 1)
        border.color: dropHighlight ? Appearance.colors.colPrimary :
                      (isFocused ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant)

        Behavior on border.color { ColorAnimation { duration: 100 } }
        Behavior on border.width { NumberAnimation { duration: 100 } }
    }

    Rectangle {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 2
        height: root.headerHeight - 2
        radius: noteCount > 0 ? 0 : 6
        topLeftRadius: 6
        topRightRadius: 6
        color: Appearance.colors.colLayer1

        MouseArea {
            id: headerHover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.OpenHandCursor

            onPressed: (mouse) => {
                root.zOrder = NoteBoardState.focusGroup(root.groupId);
                mouse.accepted = false;  // Let DragHandler take over
            }
        }

        // Drag handler ONLY on header - drags the whole group
        DragHandler {
            id: headerDragHandler
            target: root
            dragThreshold: 3
            cursorShape: Qt.ClosedHandCursor

            onActiveChanged: {
                if (active) {
                    root.zOrder = NoteBoardState.focusGroup(root.groupId);
                } else {
                    NotePersistence.updateGroup(root.index, { x: root.x, y: root.y });
                }
            }
        }

        TextField {
            id: titleField
            anchors.left: parent.left
            anchors.right: buttons.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 10
            text: root.title
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
            background: null
            selectByMouse: true

            onActiveFocusChanged: {
                if (activeFocus) {
                    root.zOrder = NoteBoardState.focusGroup(root.groupId);
                }
            }

            onTextChanged: {
                if (text !== root.title)
                    NotePersistence.updateGroup(root.index, { title: text });
            }
        }

        Row {
            id: buttons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: 6
            spacing: 4
            visible: root.hovered || root.isFocused

            Rectangle {
                width: 24
                height: 24
                radius: 4
                color: addMa.containsMouse ? Appearance.colors.colLayer2 : "transparent"
                Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 15; color: Appearance.colors.colSubtext }
                MouseArea {
                    id: addMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotePersistence.addNote(0, 0, root.groupId)
                }
            }

            Rectangle {
                width: 24
                height: 24
                radius: 4
                color: closeMa.containsMouse ? Appearance.colors.colLayer2 : "transparent"
                Text { anchors.centerIn: parent; text: "\u00d7"; font.pixelSize: 15; color: Appearance.colors.colSubtext }
                MouseArea {
                    id: closeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotePersistence.removeGroup(root.index)
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: headerHeight / 2
        visible: noteCount === 0
        text: "drop notes"
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        opacity: 0.5
    }

    // Notes inside this group - they are children so they move with the group
    Repeater {
        model: root.notesInGroup.length
        delegate: GroupedNote {
            required property int index
            property var data: root.notesInGroup[index]
            noteIndex: data ? data.index : 0
            noteId: data ? data.note.noteId : ""
            noteWidth: data ? data.note.noteWidth : 180
            noteHeight: data ? data.note.noteHeight : 100
            text: data ? data.note.text : ""
            groupId: root.groupId
            localX: data ? data.note.localX : 0
            localY: data ? data.note.localY : 0
            groupPadding: root.padding
            groupHeaderHeight: root.headerHeight
            noteScale: root.groupScale
            parentGroup: root
            boardItem: root.parent
        }
    }

    Behavior on width { NumberAnimation { duration: 100 } }
    Behavior on height { NumberAnimation { duration: 100 } }

    Component.onCompleted: NoteBoardState.registerGroup(groupId, x, y, width, height)
    onXChanged: NoteBoardState.registerGroup(groupId, x, y, width, height)
    onYChanged: NoteBoardState.registerGroup(groupId, x, y, width, height)
    onWidthChanged: NoteBoardState.registerGroup(groupId, x, y, width, height)
    onHeightChanged: NoteBoardState.registerGroup(groupId, x, y, width, height)
}
