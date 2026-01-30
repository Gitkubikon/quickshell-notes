import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../common"
import "../../services"

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: root
        required property var modelData // screen
        screen: modelData

        color: "transparent"

        // Default top layer (floating above windows), toggle to bottom with shortcut
        WlrLayershell.namespace: "caelestia-notes"
        WlrLayershell.layer: layerHidden || NotePersistence.notes.count === 0 ? WlrLayer.Bottom : WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        // Ensure it doesn't reserve space
        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        // Tracks the actual layer state, delayed on hide so fade-out plays first
        property bool layerHidden: NoteBoardState.hidden
        Connections {
            target: NoteBoardState
            function onHiddenChanged() {
                notesRepeater.animating = true;
                implodeAnim.start();
            }
        }

        // Background (or no notes): full input for right-click to add notes
        // Foreground with notes: only note areas receive input
        mask: layerHidden || NotePersistence.notes.count === 0 ? null : notesMask

        Region {
            id: notesMask
            width: 0
            height: 0
            regions: noteRegions.instances
        }

        Variants {
            id: noteRegions
            model: notesRepeater.children

            Region {
                required property Item modelData
                x: modelData.x
                y: modelData.y
                width: modelData.width
                height: modelData.height
            }
        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Click to defocus notes, right-click to add
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    NotePersistence.addNote(mouse.x, mouse.y);
                } else {
                    root.contentItem.forceActiveFocus();
                }
            }
        }

        Item {
            id: notesRepeater
            anchors.fill: parent

            // Drives per-note scale: 1.0 = fully visible, 0.0 = collapsed
            property real noteScale: 1.0
            property bool animating: false

            NumberAnimation {
                id: implodeAnim
                target: notesRepeater
                property: "noteScale"
                to: 0
                duration: 90
                easing.type: Easing.InBack
                easing.overshoot: 0.7
                onFinished: {
                    root.layerHidden = NoteBoardState.hidden;
                    explodeAnim.start();
                }
            }

            NumberAnimation {
                id: explodeAnim
                target: notesRepeater
                property: "noteScale"
                to: 1
                duration: 190
                easing.type: Easing.OutBack
                easing.overshoot: 1.4
                onFinished: notesRepeater.animating = false
            }

            Repeater {
                model: NotePersistence.notes
                delegate: NoteWidget {
                    noteScale: notesRepeater.noteScale
                }
            }
        }
    }
}
