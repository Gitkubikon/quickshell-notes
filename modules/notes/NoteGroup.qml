import QtQuick
import QtQuick.Controls
import "../../common"
import "../../services"

// Group frame and header. Its notes are siblings on the board that position
// themselves relative to this item, so nothing is reparented while dragging.
Item {
    id: root
    required property string groupId
    required property real groupX
    required property real groupY
    required property string title
    required property string screenName

    property real groupScale: 1.0
    property bool editingTitle: false

    readonly property real padding: NotePersistence.groupPadding
    readonly property real headerHeight: NotePersistence.groupHeaderHeight
    readonly property bool isFocused: NoteBoardState.focusedGroupId === groupId
    readonly property bool isDragging: NoteBoardState.draggingGroupId === groupId
    readonly property bool hovered: headerHover.hovered || editingTitle
    readonly property bool dropHighlight: NoteBoardState.noteDragging && NoteBoardState.hoverGroupId === groupId
    readonly property var size: NotePersistence.groupSize(groupId)
    readonly property int noteCount: size.count

    x: isDragging ? NoteBoardState.dragGroupX : groupX
    y: isDragging ? NoteBoardState.dragGroupY : groupY
    z: isDragging ? 90000 : NoteBoardState.zFor(groupId)
    width: size.width
    height: size.height
    scale: groupScale
    opacity: groupScale

    Behavior on width { NumberAnimation { duration: 100 } }
    Behavior on height { NumberAnimation { duration: 100 } }

    function startTitleEdit(): void {
        editingTitle = true;
        titleField.forceActiveFocus();
        titleField.selectAll();
    }

    // Border frame
    Rectangle {
        id: borderFrame
        anchors.fill: parent
        radius: 8
        color: "transparent"
        border.width: root.dropHighlight ? 3 : (root.isFocused ? 2 : 1)
        border.color: root.dropHighlight || root.isFocused ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

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
        radius: root.noteCount > 0 ? 0 : 6
        topLeftRadius: 6
        topRightRadius: 6
        color: Appearance.colors.colLayer1

        HoverHandler {
            id: headerHover
            cursorShape: Qt.OpenHandCursor
        }

        TapHandler {
            onPressedChanged: {
                NoteBoardState.pointerHeld = pressed;
                if (pressed)
                    NoteBoardState.focusGroup(root.groupId, root.screenName);
            }
        }

        // Whole header (title included) drags the group
        DragHandler {
            id: headerDragHandler
            target: null
            enabled: !root.editingTitle
            cursorShape: Qt.ClosedHandCursor

            property real startX: 0
            property real startY: 0

            onActiveChanged: {
                if (active) {
                    NoteBoardState.focusGroup(root.groupId, root.screenName);
                    startX = root.x;
                    startY = root.y;
                    NoteBoardState.beginGroupDrag(root.groupId, startX, startY);
                } else {
                    NotePersistence.updateGroup(root.groupId, { x: NoteBoardState.dragGroupX, y: NoteBoardState.dragGroupY });
                    NoteBoardState.endGroupDrag();
                }
            }

            onCentroidChanged: {
                if (!active)
                    return;
                NoteBoardState.moveGroupDrag(startX + centroid.scenePosition.x - centroid.scenePressPosition.x, startY + centroid.scenePosition.y - centroid.scenePressPosition.y);
            }
        }

        TextField {
            id: titleField
            anchors.left: parent.left
            anchors.right: buttons.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 10
            // Disabled until clicked so it doesn't swallow header drags
            enabled: root.editingTitle
            text: root.title
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
            background: null
            selectByMouse: true

            onEditingFinished: root.editingTitle = false
            onActiveFocusChanged: {
                if (!activeFocus)
                    root.editingTitle = false;
            }
            Keys.onEscapePressed: root.editingTitle = false

            onTextChanged: {
                if (text !== root.title)
                    NotePersistence.updateGroup(root.groupId, { title: text });
            }
        }

        // Click (without dragging) on the title to rename
        Item {
            anchors.fill: titleField
            visible: !root.editingTitle

            TapHandler {
                onTapped: root.startTitleEdit()
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
                    onClicked: NotePersistence.addNote(0, 0, root.groupId, root.screenName)
                }
            }

            Rectangle {
                width: 24
                height: 24
                radius: 4
                color: closeMa.containsMouse ? Appearance.colors.colLayer2 : "transparent"
                Text { anchors.centerIn: parent; text: "×"; font.pixelSize: 15; color: Appearance.colors.colSubtext }
                MouseArea {
                    id: closeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotePersistence.removeGroup(root.groupId)
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.headerHeight / 2
        visible: root.noteCount === 0
        text: "drop notes"
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        opacity: 0.5
    }
}
