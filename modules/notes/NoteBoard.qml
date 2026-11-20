import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../../common"
import "../../services"

// One board window per screen. Board content is offset by the screen's
// position so all notes live in one global (virtual desktop) coordinate space.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: root
        required property ShellScreen modelData
        readonly property string screenName: modelData.name

        // Group items on this screen keyed by groupId, and every item that takes input
        property var groupItems: ({})
        property var maskItems: []

        screen: modelData
        color: "transparent"

        property bool hasContent: NotePersistence.notes.count > 0 || NotePersistence.groups.count > 0

        WlrLayershell.namespace: "caelestia-notes"
        WlrLayershell.layer: layerHidden || !hasContent ? WlrLayer.Bottom : WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        property bool layerHidden: NoteBoardState.hidden
        Connections {
            target: NoteBoardState
            function onHiddenChanged() {
                boardContent.animating = true;
                implodeAnim.start();
            }
        }

        function trackItem(item: Item, isGroup: bool): void {
            if (isGroup) {
                var m = Object.assign({}, groupItems);
                m[item.groupId] = item;
                groupItems = m;
            }
            maskItems = maskItems.concat([item]);
        }

        function untrackItem(item: Item, isGroup: bool): void {
            if (isGroup) {
                var m = Object.assign({}, groupItems);
                for (var k in m) {
                    if (m[k] === item)
                        delete m[k];
                }
                groupItems = m;
            }
            maskItems = maskItems.filter(i => i !== item);
        }

        mask: layerHidden || !hasContent || NoteBoardState.interacting ? null : inputMask

        Region {
            id: inputMask
            regions: maskRegions.instances

            // Quickshell doesn't forward changes of regions that were swapped in by a list
            // reassignment, so children poke the parent themselves. Toggling radius emits
            // `changed` without affecting the (empty) parent rect.
            function rebuild(): void {
                radius = radius === 0 ? 1 : 0;
            }
        }

        Variants {
            id: maskRegions
            model: root.maskItems
            // Unscaled geometry: `item:` would measure the scale animation and could stay 0x0
            Region {
                required property Item modelData
                x: modelData.x + boardContent.x
                y: modelData.y + boardContent.y
                width: modelData.width
                height: modelData.height
                onChanged: inputMask.rebuild()
            }
        }

        anchors { top: true; bottom: true; left: true; right: true }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            // Safety net: if a release was ever missed, the first background press
            // restores the mask instead of leaving an invisible input blocker
            onPressed: {
                if (NoteBoardState.interacting)
                    NoteBoardState.resetInteraction();
            }
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    // Spawn point in global coordinates, kept on this screen
                    contextMenu.spawnX = root.modelData.x + Math.min(mouse.x, root.width - NotePersistence.defaultNoteWidth);
                    contextMenu.spawnY = root.modelData.y + Math.min(mouse.y, root.height - NotePersistence.defaultNoteHeight);
                    contextMenu.x = mouse.x;
                    contextMenu.y = mouse.y;
                    contextMenu.open();
                } else {
                    NoteBoardState.clearFocus();
                    root.contentItem.forceActiveFocus();
                }
            }
        }

        // Losing keyboard focus clears selection, unless focus moved to another screen's board
        Connections {
            target: root.contentItem
            function onActiveFocusChanged() {
                if (!root.contentItem.activeFocus && NoteBoardState.focusScreen === root.screenName)
                    NoteBoardState.clearFocus();
            }
        }

        Menu {
            id: contextMenu
            property real spawnX: 0
            property real spawnY: 0

            background: Rectangle {
                implicitWidth: 140
                color: Appearance.colors.colLayer1
                radius: 8
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
            }

            MenuItem {
                text: "Add Note"
                // Right-click inside a group adds the note to that group
                onTriggered: NotePersistence.addNote(contextMenu.spawnX, contextMenu.spawnY, NoteBoardState.findGroupAt(contextMenu.spawnX, contextMenu.spawnY), root.screenName)
                background: Rectangle { color: parent.hovered ? Appearance.colors.colLayer2 : "transparent" }
                contentItem: Text { text: parent.text; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small; leftPadding: 10 }
            }

            MenuItem {
                text: "Add Group"
                onTriggered: NotePersistence.addGroup(contextMenu.spawnX, contextMenu.spawnY)
                background: Rectangle { color: parent.hovered ? Appearance.colors.colLayer2 : "transparent" }
                contentItem: Text { text: parent.text; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small; leftPadding: 10 }
            }
        }

        Item {
            id: boardContent
            x: -root.modelData.x
            y: -root.modelData.y
            property real itemScale: 1.0
            property bool animating: false

            NumberAnimation {
                id: implodeAnim
                target: boardContent; property: "itemScale"; to: 0; duration: 90
                easing.type: Easing.InBack; easing.overshoot: 0.7
                onFinished: { root.layerHidden = NoteBoardState.hidden; explodeAnim.start(); }
            }

            NumberAnimation {
                id: explodeAnim
                target: boardContent; property: "itemScale"; to: 1; duration: 190
                easing.type: Easing.OutBack; easing.overshoot: 1.4
                onFinished: boardContent.animating = false
            }

            Repeater {
                model: NotePersistence.groups
                delegate: NoteGroup {
                    screenName: root.screenName
                    groupScale: boardContent.itemScale
                }
                onItemAdded: (index, item) => root.trackItem(item, true)
                onItemRemoved: (index, item) => root.untrackItem(item, true)
            }

            Repeater {
                model: NotePersistence.notes
                delegate: NoteWidget {
                    screenName: root.screenName
                    groupItems: root.groupItems
                    noteScale: boardContent.itemScale
                }
                onItemAdded: (index, item) => root.trackItem(item, false)
                onItemRemoved: (index, item) => root.untrackItem(item, false)
            }
        }
    }
}
