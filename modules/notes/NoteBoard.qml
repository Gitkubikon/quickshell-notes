import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../../common"
import "../../services"

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: root
        required property var modelData
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

        mask: layerHidden || !hasContent ? null : inputMask

        Region {
            id: inputMask
            width: 0
            height: 0
            regions: allRegions.instances
        }

        Variants {
            id: allRegions
            model: {
                var regions = [];
                for (var g = 0; g < NotePersistence.groups.count; g++) {
                    var grp = NotePersistence.groups.get(g);
                    var size = NoteBoardState.groupSizes[grp.groupId] || {width: 200, height: 100};
                    regions.push({x: grp.groupX, y: grp.groupY, w: size.width, h: size.height});
                }
                for (var n = 0; n < NotePersistence.notes.count; n++) {
                    var note = NotePersistence.notes.get(n);
                    if (!note.groupId || note.groupId === "")
                        regions.push({x: note.noteX, y: note.noteY, w: note.noteWidth, h: note.noteHeight});
                }
                return regions;
            }
            Region {
                required property var modelData
                x: modelData.x
                y: modelData.y
                width: modelData.w
                height: modelData.h
            }
        }

        anchors { top: true; bottom: true; left: true; right: true }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    contextMenu.x = mouse.x;
                    contextMenu.y = mouse.y;
                    contextMenu.open();
                } else {
                    NoteBoardState.clearFocus();
                    root.contentItem.forceActiveFocus();
                }
            }
        }

        Connections {
            target: root.contentItem
            function onActiveFocusChanged() {
                if (!root.contentItem.activeFocus) {
                    NoteBoardState.clearFocus();
                }
            }
        }

        Menu {
            id: contextMenu
            property real spawnX: x
            property real spawnY: y

            background: Rectangle {
                implicitWidth: 140
                color: Appearance.colors.colLayer1
                radius: 8
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant
            }

            MenuItem {
                text: "Add Note"
                onTriggered: NotePersistence.addNote(contextMenu.spawnX, contextMenu.spawnY, "")
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
            anchors.fill: parent
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
                delegate: NoteGroup { groupScale: boardContent.itemScale }
            }

            Repeater {
                model: NotePersistence.notes
                delegate: NoteWidget {
                    visible: !groupId || groupId === ""
                    noteScale: boardContent.itemScale
                }
            }


        }
    }
}
