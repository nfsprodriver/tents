/*
 * Copyright 2016 Robert Ancell
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License version 3 as published by the
 * Free Software Foundation. See http://www.gnu.org/copyleft/gpl.html the full
 * text of the license.
 */

import QtQuick 2.4
import Ubuntu.Components 1.3

Grid {
    id: grid
    columns: model.columns + 1
    rows: model.rows + 1
    property int cell_size: Math.floor (Math.min (parent.width / columns, parent.height / rows)) - 2
    property FieldModel model
    Repeater {
        id: repeater
        model: grid.model
        Rectangle {
            width: grid.cell_size
            height: grid.cell_size
            color: {
                if (model.state == "unknown")
                    return "#eeeeec"
                else if (model.state == "count" || model.state == "blank")
                    return "transparent"
                else
                    return "#8ae234"
            }
            border.width: 1
            border.color: model.state == "count" || model.state == "blank" ? "transparent" : "black"
            Image {
                id: image
                anchors.centerIn: parent
                sourceSize.width: parent.width * 0.8
                source: {
                    if (model.state == "tree")
                        return "tree.svg"
                    else if (model.state == "tent")
                        return "tent.svg"
                    else
                        return ""
                }
            }
            Label {
                anchors.fill: parent
                anchors.margins: units.gu (1)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: model.state == "count" ? model.count : ""
                color: {
                    if (grid.model.completed)
                        return UbuntuColors.green
                    if (model.error)
                        return UbuntuColors.red
                    return UbuntuColors.darkGrey
                }
                font.bold: true
                font.pixelSize: grid.cell_size * 0.6
            }
            MouseArea {
                anchors.fill: parent
                enabled: !grid.model.completed
                acceptedButtons: Qt.LeftButton | Qt.RightButton                
                onClicked: {
                    if (mouse.button == Qt.LeftButton) {
                        if (model.state == "unknown")
                            grid.model.set_state (index, "grass")
                        else if (model.state == "grass")
                            grid.model.set_state (index, "tent")
                        else if (model.state == "tent")
                            grid.model.set_state (index, "unknown")
                    }
                    else {
                        if (model.state == "unknown")
                            grid.model.set_state (index, "tent")
                        else if (model.state == "tent")
                            grid.model.set_state (index, "grass")
                        else if (model.state == "grass")
                            grid.model.set_state (index, "unknown")
                    }
                }
            }
        }
    }
}
