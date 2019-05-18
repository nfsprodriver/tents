/*
 * Copyright 2016 Robert Ancell
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License version 3 as published by the
 * Free Software Foundation. See http://www.gnu.org/copyleft/gpl.html the full
 * text of the license.
 */

import QtQuick 2.0
import Ubuntu.Components 1.3
import Ubuntu.Components.ListItems 1.3 as ListItem
import Ubuntu.Components.Popups 1.3
import Ubuntu.Components.Themes 1.3
import QtQuick.Layouts 1.1
import QtQuick.LocalStorage 2.0

MainView {
    applicationName: "tents.robert-ancell"
    automaticOrientation: true
    id: app

    width: units.gu (40)
    height: units.gu (71)

    property int mode: size_selector.selectedIndex
    property var timer: 0

    function get_settings_database () {
        return LocalStorage.openDatabaseSync ("settings", "1", "Tents Settings", 0)
    }

    function get_history_database () {
        return LocalStorage.openDatabaseSync ("history", "1", "Tents History", 0)
    }

    Component.onCompleted: {
        get_settings_database ().transaction (function (t) {
            try {
                var r = t.executeSql('SELECT grid_width, grid_height, n_trees, easy_rules FROM Settings')
                var item = r.rows.item (0)
                for (var i = 0; i < size_selector.model.count; i++) {
                    var s = size_selector.model.get (i)
                    if (s.grid_width == item.grid_width &&
                            s.grid_height == item.grid_height &&
                            s.n_trees == item.n_trees &&
                            s.easy_rules == item.easy_rules) {
                        size_selector.selectedIndex = i
                        break
                    }
                }
            }
            catch (e) {
            }
        })
    }

    FieldModel {
        id: field
        onSolved: {
            get_history_database ().transaction (function (t) {
                t.executeSql ("CREATE TABLE IF NOT EXISTS History(columns INTEGER, rows INTEGER, n_trees INTEGER, easy_rules BOOLEAN, date TEXT, duration INTEGER)")
                var duration = field.end_time - field.start_time
                t.executeSql ("INSERT INTO History VALUES(?, ?, ?, ?, ?, ?)", [field.columns, field.rows, field.n_trees, field.easy_rules, field.start_time.toISOString (), duration])
            })
        }
    }

    function save_state () {
        get_settings_database ().transaction (function (t) {
            var grid_options = size_selector.model.get (size_selector.selectedIndex)
            // The lock field is to ensure the INSERT will always replace this row instead of adding another
            t.executeSql ("CREATE TABLE IF NOT EXISTS Settings(lock INTEGER, grid_width INTEGER, grid_height INTEGER, n_trees INTEGER, easy_rules BOOLEAN, PRIMARY KEY (lock))")
            t.executeSql ("INSERT OR REPLACE INTO Settings VALUES(0, ?, ?, ?, ?)", [grid_options.grid_width, grid_options.grid_height, grid_options.n_trees, grid_options.easy_rules])
        })
    }

    function reset_field () {
        var grid_options = size_selector.model.get (size_selector.selectedIndex)
        field.set_size (grid_options.grid_width, grid_options.grid_height, grid_options.n_trees)
        field.generate (grid_options.easy_rules)
    }


    function game_over () {
        // Save score
        var now = new Date ()
        var time = (field.end_time - field.start_time) / 1000
        get_database ().transaction (function (t) {
            t.executeSql ("CREATE TABLE IF NOT EXISTS Scores(date TEXT, time TEXT)")
            t.executeSql ("INSERT INTO Scores VALUES(?, ?)", [now.toISOString (), time.toFixed(1)])
        })
    }

    function update_scores () {
        var scores
        get_database ().transaction (function (t) {
            try {
                scores = t.executeSql ("SELECT * FROM Scores ORDER BY time ASC LIMIT 5")
            }
            catch (e) {
            }
        })
        var n_scores = 0
        if (scores !== undefined)
            n_scores = scores.rows.length

        var score_entries = [ score_entry0, score_entry1, score_entry2, score_entry3, score_entry4 ]
        var i
        for (i = 0; i < n_scores; i++) {
            var item = scores.rows.item (i)
            score_entries[i].visible = true
            score_entries[i].score = item.time + " " + i18n.tr("seconds")
            score_entries[i].date = format_date (new Date (item.date))
        }
        for (; i < 5; i++) {
            score_entries[i].score = ""
            score_entries[i].date = ""
        }
    }

    function format_date (date) {
        var now = new Date ()
        var seconds = (now.getTime () - date.getTime ()) / 1000
        if (seconds < 1) {
            // TRANSLATORS: Label shown below high score for a score just achieved
            return i18n.tr ("Now")
        }
        if (seconds < 120) {
            var n_seconds = Math.floor (seconds)
            // TRANSLATORS: Label shown below high score for a score achieved seconds ago
            return i18n.tr ("%n second ago", "%n seconds ago", n_seconds).replace ("%n", n_seconds)
        }
        var minutes = seconds / 60
        if (minutes < 120) {
            var n_minutes = Math.floor (minutes)
            // TRANSLATORS: Label shown below high score for a score achieved minutes ago
            return i18n.tr ("%n minute ago", "%n minutes ago", n_minutes).replace ("%n", n_minutes)
        }
        var hours = minutes / 60
        if (hours < 48) {
            var n_hours = Math.floor (hours)
            // TRANSLATORS: Label shown below high score for a score achieved hours ago
            return i18n.tr ("%n hour ago", "%n hours ago", n_hours).replace ("%n", n_hours)
        }
        var days = hours / 24
        if (days < 30) {
            var n_days = Math.floor (days)
            // TRANSLATORS: Label shown below high score for a score achieved days ago
            return i18n.tr ("%n day ago", "%n days ago", n_days).replace ("%n", n_days)
        }
        if (date.getFullYear () != now.getFullYear ())
            return Qt.formatDate (date, "MMM yyyy")
        return Qt.formatDate (date, "d MMM")
    }

    function clear_scores () {
        get_database ().transaction (function (t) {
            try {
                t.executeSql ("DELETE FROM Scores")
            }
            catch (e) {
            }
        })
        update_scores ()
    }

    function get_database () {
        return LocalStorage.openDatabaseSync (mode, 0, "Tents Scores", 0)
    }

    function genName () {
        var name = field_size_model.get(mode).name
        var parts = name.split("-")
        return parts[0][0].toUpperCase() + parts[0].substring(1) + " (" + parts[1] + ")"

    }

    Component {
        id: confirm_new_game_dialog
        Dialog {
            id: d
            // TRANSLATORS: Title for dialog shown when starting a new game while one in progress
            title: i18n.tr ("Game in progress")
            // TRANSLATORS: Content for dialog shown when starting a new game while one in progress
            text: i18n.tr ("Are you sure you want to restart this game?")
            Button {
                // TRANSLATORS: Button in new game dialog that cancels the current game and starts a new one
                text: i18n.tr ("Restart game")
                color: UbuntuColors.red
                onClicked: {
                    timerO.stop()
                    timer = 0
                    reset_field ()
                    PopupUtils.close (d)
                }
            }
            Button {
                // TRANSLATORS: Button in new game dialog that removes the user placed grass and tents
                text: i18n.tr ("Remove grass and tents")
                onClicked: {
                    timerO.stop()
                    timer = 0
                    field.reset ()
                    PopupUtils.close (d)
                }
            }
            Button {
                // TRANSLATORS: Button in new game dialog that cancels new game request
                text: i18n.tr ("Continue current game")
                onClicked: PopupUtils.close (d)
            }
        }
    }
    Component {
        id: confirm_clear_scores_dialog
        Dialog {
            id: d
            // TRANSLATORS: Title for dialog confirming if scores should be cleared
            title: i18n.tr ("Clear scores for") + " " + i18n.tr(genName())
            // TRANSLATORS: Content for dialog confirming if scores should be cleared
            text: i18n.tr ("Existing scores will be deleted. This cannot be undone.")
            Button {
                // TRANSLATORS: Button in clear scores dialog that clears scores
                text: i18n.tr ("Clear scores")
                color: UbuntuColors.red
                onClicked: {
                    clear_scores ()
                    PopupUtils.close (d)
                }
            }
            Button {
                // TRANSLATORS: Button in clear scores dialog that cancels clear scores request
                text: i18n.tr ("Keep existing scores")
                onClicked: PopupUtils.close (d)
            }
        }
    }

    PageStack {
        id: page_stack
        Component.onCompleted: {
            push (main_page)
        }

        Page {
            id: main_page
            visible: false
            // TRANSLATORS: Title of application
            title: i18n.tr ("Tents")
            head.actions:
                [
                Action {
                    // TRANSLATORS: Action on main page that shows settings dialog
                    text: i18n.tr ("Settings")
                    iconName: "settings"
                    onTriggered: page_stack.push (settings_page)
                },
                Action {
                    // TRANSLATORS: Action on main page that starts a new game
                    text: i18n.tr ("New Game")
                    iconName: "reload"
                    onTriggered: {
                        if (field.started && !field.completed)
                            PopupUtils.open (confirm_new_game_dialog)
                        else
                            timerO.stop()
                            timer = 0
                            reset_field ()
                    }
                },
                Action {
                    // TRANSLATORS: Action on main page that shows game instructions
                    text: i18n.tr ("How to Play")
                    iconName: "help"
                    onTriggered: page_stack.push (how_to_play_page)
                },
                Action {
                    text: i18n.tr("High scores")
                    iconSource: "../assets/high-scores.svg"
                    onTriggered: {
                        update_scores ()
                        page_stack.push (scores_page)
                    }
                }
            ]

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.head.top
                Timer {
                    id: timerO
                    interval: 100
                    repeat: true
                    onTriggered: {
                        timer = timer + 0.1
                        time.text = timer.toFixed(1) + " " + i18n.tr("seconds")
                    }
                }

                Text {
                    id: time
                    color: theme.palette.normal.backgroundText
                    visible: timer !== 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: (app.height / app.width) * 13
                }
            }

            Item {
                id: fieldItem
                anchors.fill: parent
                anchors.margins: units.gu (2)
                FieldView {
                    model: field
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Page {
            id: how_to_play_page
            visible: false
            // TRANSLATORS: Title of page with game instructions
            title: i18n.tr ("How to Play")

            Label {
                anchors.fill: parent
                anchors.margins: units.gu (2)

                wrapMode: Text.Wrap
                textFormat: Text.StyledText
                // TRANSLATORS: Game instructions
                text: i18n.tr ("<p><i>Tents</i> is a puzzle game where you need to work out where all the tents are in a field.</p>\
<br/>\
<p>The rules are:</p>\
<ul>\
<li>Each camper has claimed a tree and placed their tent beside it (these campers like shade).</li>\
<li>The field is full - there is one tent for every tree.</li>\
<li>No two tents are beside each other, even diagonally (too noisy!).</li>\
<li>The number of tents in each row / column is shown with a number.</li>\
</ul>\
<p>You can always work out where all the tents are with just these rules. Touching a square allows you to mark it as grass (i.e. a tent cannot be here) or a tent.</p>\
<br/>\
<p>Have fun!</p>")
            }
        }

        Page {
            id: settings_page
            visible: false
            // TRANSLATORS: Title of page showing settings
            title: i18n.tr ("Settings")

            Column {
                anchors.fill: parent
                ListItem.ItemSelector {
                    id: size_selector
                    // TRANSLATORS: Label above setting to choose the field size
                    text: i18n.tr ("Field size:")
                    model: field_size_model
                    selectedIndex: -1
                    delegate: OptionSelectorDelegate {
                        text: {
                            switch (name) {
                            case "small-easy":
                                // TRANSLATORS: Setting name for small and easy field
                                return i18n.tr ("Small (easy)")
                            case "small-difficult":
                                // TRANSLATORS: Setting name for small and difficult field
                                return i18n.tr ("Small (difficult)")
                            case "medium-easy":
                                // TRANSLATORS: Setting name for medium and easy field
                                return i18n.tr ("Medium (easy)")
                            case "medium-difficult":
                                // TRANSLATORS: Setting name for medium and difficult field
                                return i18n.tr ("Medium (difficult)")
                            case "large-easy":
                                // TRANSLATORS: Setting name for large and easy field
                                return i18n.tr ("Large (easy)")
                            case "large-difficult":
                                // TRANSLATORS: Setting name for large and difficult field
                                return i18n.tr ("Large (difficult)")
                            default:
                                return ""
                            }
                        }
                        // TRANSLATORS: Description format for field size, %width%, %height% and %ntrees% is replaced with the field width, height and number of trees
                        subText: i18n.tr ("%width%×%height%, %ntrees% trees").replace ("%width%", grid_width).replace ("%height%", grid_height).replace ("%ntrees%", n_trees)
                    }
                    onSelectedIndexChanged: {
                        save_state ()
                        if (!field.started || field.completed)
                            reset_field ()
                    }
                }
            }
        }

        ListModel {
            id: field_size_model
            ListElement {
                name: "small-easy"
                grid_width: 8
                grid_height: 8
                n_trees: 12
                easy_rules: true
            }
            ListElement {
                name: "small-difficult"
                grid_width: 8
                grid_height: 8
                n_trees: 12
                easy_rules: false
            }
            ListElement {
                name: "medium-easy"
                grid_width: 10
                grid_height: 10
                n_trees: 20
                easy_rules: true
            }
            ListElement {
                name: "medium-difficult"
                grid_width: 10
                grid_height: 10
                n_trees: 20
                easy_rules: false
            }
            ListElement {
                name: "large-easy"
                grid_width: 15
                grid_height: 15
                n_trees: 45
                easy_rules: true
            }
            ListElement {
                name: "large-difficult"
                grid_width: 15
                grid_height: 15
                n_trees: 45
                easy_rules: false
            }
        }

        Page {
            id: scores_page
            visible: false
            header: PageHeader {
                id: score_header
                // TRANSLATORS: Title of page showing high scores
                title: i18n.tr ("High Scores for") + " " + i18n.tr(genName())
                trailingActionBar.actions: [
                    Action {
                        iconName: "reset"
                        onTriggered: PopupUtils.open (confirm_clear_scores_dialog)
                    }
                ]
            }

            GridLayout {
                anchors.top: score_header.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.margins: units.gu (2)
                rowSpacing: units.gu (4)
                columns: 1

                ScoreEntry {
                    id: score_entry0
                    Layout.alignment: Qt.AlignHCenter
                }
                ScoreEntry {
                    id: score_entry1
                    Layout.alignment: Qt.AlignHCenter
                }
                ScoreEntry {
                    id: score_entry2
                    Layout.alignment: Qt.AlignHCenter
                }
                ScoreEntry {
                    id: score_entry3
                    Layout.alignment: Qt.AlignHCenter
                }
                ScoreEntry {
                    id: score_entry4
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }
}
