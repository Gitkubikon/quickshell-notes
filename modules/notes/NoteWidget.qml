import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../common"
import "../../common/functions"
import "../../common/widgets"
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
    required property string noteColor

    property bool hovered: hoverArea.containsMouse || textArea.hovered || closeMa.containsMouse
    property real noteScale: 1.0

    width: noteWidth
    height: noteHeight
    x: noteX
    y: noteY
    radius: Appearance.rounding.small
    scale: noteScale
    opacity: noteScale
    transformOrigin: Item.Center
    color: Appearance.colors.colLayer1
    border.width: 1
    border.color: textArea.activeFocus
        ? Appearance.colors.colPrimary
        : Appearance.colors.colOutlineVariant

    Behavior on color { ColorAnimation { duration: 100 } }
    Behavior on border.color { ColorAnimation { duration: 100 } }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: true
    }

    DragHandler {
        target: root
        xAxis.enabled: true
        yAxis.enabled: true
        onActiveChanged: {
            if (!active)
                NotePersistence.updateNote(root.index, { x: root.x, y: root.y });
        }
    }

    StyledRectangularShadow { target: root }

    // Close button
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        width: 20
        height: 20
        radius: width / 2
        z: 2
        visible: root.hovered
        color: closeMa.containsMouse
            ? (closeMa.pressed ? Appearance.colors.colError : Appearance.colors.colLayer2)
            : "transparent"

        StyledText {
            anchors.centerIn: parent
            text: "\u00d7"
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: closeMa.containsMouse && closeMa.pressed
                ? Appearance.colors.colOnError
                : Appearance.colors.colOnLayer1
        }

        MouseArea {
            id: closeMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: NotePersistence.removeNote(root.index)
        }
    }

    // Resize grip
    Item {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 14
        height: 14
        z: 2
        visible: root.hovered

        Canvas {
            anchors.fill: parent
            anchors.margins: 2
            onPaint: {
                var ctx = getContext("2d");
                ctx.strokeStyle = Appearance.colors.colOutlineVariant.toString();
                ctx.lineWidth = 1;
                ctx.lineCap = "round";
                ctx.beginPath();
                ctx.moveTo(width, 0);
                ctx.lineTo(0, height);
                ctx.moveTo(width, height * 0.45);
                ctx.lineTo(width * 0.45, height);
                ctx.stroke();
            }
        }

        DragHandler {
            target: null
            cursorShape: Qt.SizeFDiagCursor
            onActiveChanged: {
                if (!active)
                    NotePersistence.updateNote(root.index, { width: root.width, height: root.height });
            }
            onTranslationChanged: (delta) => {
                root.width = Math.max(140, root.width + delta.x);
                root.height = Math.max(80, root.height + delta.y);
            }
        }
    }

    ScrollView {
        anchors.fill: parent
        anchors.margins: 8

        TextArea {
            id: textArea
            text: root.text
            color: Appearance.colors.colOnLayer1
            selectedTextColor: Appearance.colors.colOnPrimary
            selectionColor: Appearance.colors.colPrimary
            font.pixelSize: Appearance.font.pixelSize.small
            font.family: Appearance.font.family.main
            wrapMode: Text.Wrap
            background: null
            selectByMouse: true
            placeholderText: "Note..."
            placeholderTextColor: Appearance.colors.colSubtext

            onTextChanged: {
                if (text !== root.text)
                    NotePersistence.updateNote(root.index, { text: text });
            }

            // Handle Ctrl+Shift+V (terminal-style paste, used by hyprwhspr)
            Shortcut {
                sequence: "Ctrl+Shift+V"
                onActivated: textArea.paste()
            }
        }
    }
}
