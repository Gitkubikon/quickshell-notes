import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../common"
import "../../common/functions"
import "../../common/widgets"
import "../../services"

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: root
        required property var modelData
        screen: modelData

        color: "transparent"
        property bool showWindow: false
        visible: showWindow

        WlrLayershell.namespace: "caelestia-dictation"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        mask: Region {}

        anchors {
            top: true
            left: true
            right: true
        }

        implicitHeight: 56

        DictationState { id: indicator }

        property real smoothLevel: indicator.audioLevel

        // Animate pill in/out
        property bool showPill: indicator.recording

        // Shadow
        StyledRectangularShadow {
            target: pill
            opacity: pill.opacity
        }

        Rectangle {
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 10
            width: pillContent.implicitWidth + 28
            height: 36
            radius: Appearance.rounding.full
            color: Colours.layer(Colours.current.m3surfaceContainerLow, 1)
            border.width: 1
            border.color: Colours.transparencyEnabled
                ? ColorUtils.applyAlpha(Appearance.colors.colOutlineVariant, Colours.transparencyLayers)
                : Appearance.colors.colOutlineVariant

            // Entrance/exit animation state
            scale: 0
            opacity: 0
            transformOrigin: Item.Top

            // Enter animation
            ParallelAnimation {
                id: enterAnim

                NumberAnimation {
                    target: pill; property: "scale"
                    from: 0.3; to: 1
                    duration: 400
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.6
                }
                NumberAnimation {
                    target: pill; property: "opacity"
                    from: 0; to: 1
                    duration: 300
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: pill; property: "anchors.topMargin"
                    from: -10; to: 10
                    duration: 400
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.6
                }
            }

            // Exit animation
            ParallelAnimation {
                id: exitAnim
                onFinished: root.showWindow = false

                NumberAnimation {
                    target: pill; property: "scale"
                    to: 0.3
                    duration: 200
                    easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: pill; property: "opacity"
                    to: 0
                    duration: 200
                    easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: pill; property: "anchors.topMargin"
                    to: -10
                    duration: 200
                    easing.type: Easing.InCubic
                }
            }

            Connections {
                target: root
                function onShowPillChanged() {
                    enterAnim.stop();
                    exitAnim.stop();
                    if (root.showPill) {
                        root.showWindow = true;
                        enterAnim.start();
                    } else {
                        exitAnim.start();
                    }
                }
            }

            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            Row {
                id: pillContent
                anchors.centerIn: parent
                spacing: 8

                // Recording dot
                Rectangle {
                    width: 8
                    height: 8
                    radius: width / 2
                    color: Appearance.colors.colError
                    anchors.verticalCenter: parent.verticalCenter

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: indicator.recording
                        NumberAnimation { to: 0.4; duration: 800; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                    }
                }

                // Voice visualizer
                Row {
                    id: visualizer
                    spacing: 2
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: 5

                        Rectangle {
                            id: vbar
                            required property int index

                            readonly property real phase: index / 4.0 * Math.PI
                            readonly property real wave: 0.5 + 0.5 * Math.sin(waveTime + phase)
                            readonly property real barLevel: {
                                const level = root.smoothLevel;
                                const center = 2.0;
                                const dist = Math.abs(index - center) / center;
                                const sensitivity = 1.0 - dist * 0.35;
                                const audio = Math.min(1.0, level * sensitivity);
                                const idle = 0.15 + wave * 0.1;
                                return Math.max(idle, audio + wave * 0.15 * audio);
                            }

                            property real waveTime: 0.0

                            NumberAnimation on waveTime {
                                from: 0
                                to: 2 * Math.PI
                                duration: 1800
                                loops: Animation.Infinite
                                running: indicator.recording
                            }

                            width: 3
                            height: 4 + barLevel * 18
                            radius: width / 2
                            color: ColorUtils.mix(
                                Appearance.colors.colPrimary,
                                Appearance.colors.colError,
                                1.0 - root.smoothLevel * 0.6
                            )
                            anchors.verticalCenter: parent.verticalCenter

                            Behavior on color {
                                ColorAnimation { duration: 200 }
                            }
                        }
                    }
                }

                // Label
                StyledText {
                    text: "Listening"
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
