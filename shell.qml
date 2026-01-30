//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import "./modules/notes/"
import "./modules/dictation/"
import "./services/"
import "./common/"
import "./common/functions/"
import "./common/widgets/"

import QtQuick
import Quickshell

ShellRoot {
    NoteBoard {}
    DictationIndicator {}
}
