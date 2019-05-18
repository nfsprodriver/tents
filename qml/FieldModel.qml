/*
 * Copyright 2016 Robert Ancell
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License version 3 as published by the
 * Free Software Foundation. See http://www.gnu.org/copyleft/gpl.html the full
 * text of the license.
 */

import QtQuick 2.4

ListModel {
    id: model
    property int rows
    property int columns
    property int n_trees
    property bool started: false
    property bool completed: false
    property bool easy_rules: false
    property var start_time
    property var end_time
    signal solved ()

    // Tables of square combinations (based on size of field)
    property var row_squares
    property var column_squares
    property var adjacent_squares
    property var surrounding_squares

    property var solution

    function set_size (n_columns, n_rows, n_trees_) {
        rows = n_rows
        columns = n_columns
        n_trees = n_trees_
        started = false
        completed = false
        clear ()
        append ({"state": "blank", "count": -1, "error": false})
        for (var column = 0; column < n_columns; column++)
            append ({"state": "count", "count": -1, "error": false})
        for (var row = 0; row < n_rows; row++) {
            append ({"state": "count", "count": -1, "error": false})
            for (var column = 0; column < n_columns; column++)
                append ({"state": "unknown", "count": -1, "error": false})
        }

        // Build up table of rows / columns / adjacent and surrounding squares
        row_squares = []
        for (var row = 0; row < rows; row++) {
            var r = row_squares[row] = []
            for (var column = 0; column < columns; column++)
                r[r.length] = row * columns + column
        }
        column_squares = []
        for (var column = 0; column < columns; column++) {
            var c = column_squares[column] = []
            for (var row = 0; row < rows; row++)
                c[c.length] = row * columns + column
        }
        // Generate adjacent and surround square tables
        // i.e.
        //
        //  _?_        ???
        //  ?_?  and   ?_?
        //  _?_        ???
        //
        // Generate pairs of unknown squares that if can only match one tree cause other spaces to be invalidated
        // i.e.
        //
        //   ?X   X?  (tree is in either X location)
        //   X?   ?X
        //
        //  _X_  _?_
        //  ?T?  XTX
        //  _X_  _?_
        adjacent_squares = []
        surrounding_squares = []
        for (var square = 0; square < rows * columns; square++) {
            // Work out squares around this one
            var n = square - columns
            var s = square + columns
            var e = square + 1
            var w = square - 1
            var ne = square - columns + 1
            var se = square + columns + 1
            var sw = square + columns - 1
            var nw = square - columns - 1
            var x = square % columns
            var y = Math.floor (square / columns)
            if (x == 0)
                w = nw = sw = undefined
            if (x == columns - 1)
                e = ne = se = undefined
            if (y == 0)
                n = ne = nw = undefined
            if (y == rows - 1)
                s = se = sw = undefined

            function make_direction_array (a) {
                var result = []
                for (var i = 0; i < a.length; i++)
                    if (a[i] != undefined)
                        result[result.length] = a[i]
                return result
            }
            adjacent_squares[square] = make_direction_array ([n, e, s, w])
            surrounding_squares[square] = make_direction_array ([n, ne, e, se, s, sw, w, nw])
        }
    }

    function generate (easy_rules_) {
        // Shuffle an array
        function shuffle (a) {
            for (var i = a.length; i; i--) {
                var j = Math.floor (Math.random () * i)
                var x = a[i - 1]
                a[i - 1] = a[j]
                a[j] = x
            }
        }

        function flow_network () {
            var n = {}
            n.edges = []
            n.source = 0
            n.sink = 1

            n.add_edge = function (from, to, capacity) {
                var edge = {}
                edge.from = from
                edge.to = to
                edge.capacity = capacity
                n.edges[n.edges.length] = edge
            }

            // Calculate the maximum flow using the Edmonds-Karp algorithm
            // https://en.wikipedia.org/wiki/Edmonds–Karp_algorithm
            n.get_max_flow = function () {
                var edge_flow = []
                for (var i = 0; i < n.edges.length; i++)
                    edge_flow[i] = 0

                var total_flow = 0
                while (true) {
                    // Find a path through the network using a breadth first search
                    function find_path () {
                        var edge_to_node = []
                        var head = 0
                        var nodes = [ n.source ]
                        while (head < nodes.length && edge_to_node[n.sink] == undefined) {
                            var node = nodes[head++]

                            // Find edges with capacity leaving this node
                            for (var i = 0; i < n.edges.length; i++) {
                                var edge = n.edges[i]

                                // Flowing forwards (use unused capacity)
                                if (edge.from == node && edge_to_node[edge.to] == undefined && (edge_flow[i] < edge.capacity || edge.capacity < 0)) {
                                    edge_to_node[edge.to] = i
                                    nodes[nodes.length] = edge.to
                                }
                                // Flowing backwards (undo flow)
                                if (edge.to == node && edge_to_node[edge.from] == undefined && edge_flow[i] > 0) {
                                    edge_to_node[edge.from] = i
                                    nodes[nodes.length] = edge.from
                                }
                            }
                        }

                        return edge_to_node
                    }

                    // Find a path from the source to the sink; if none we've achieved maximum flow
                    var edge_to_node = find_path ()
                    if (edge_to_node[n.sink] == undefined)
                        return { total_flow: total_flow, edge_flow: edge_flow }

                    // Follow path to work out maximum flow
                    var node = n.sink
                    var flow = -1
                    while (node != n.source) {
                        var e = edge_to_node[node]
                        var edge = n.edges[e]

                        // Flowing forwards can use what unused capactity is left; backwards can use what flow is currently there
                        var available = edge_flow[e]
                        if (edge.to == node)
                            available = edge.capacity - available

                        if (flow < 0 || available < flow)
                            flow = available

                        if (edge.to == node)
                            node = edge.from
                        else
                            node = edge.to
                    }

                    // There is unlimited flow between source and sink...
                    if (flow < 0)
                        return { total_flow: -1, edge_flow: edge_flow }

                    // Apply this flow along the path we've used
                    node = n.sink
                    while (node != n.source) {
                        var e = edge_to_node[node]
                        var edge = n.edges[e]
                        if (edge.to == node)
                            edge_flow[e] += flow
                        else
                            edge_flow[e] -= flow

                        if (edge.to == node)
                            node = edge.from
                        else
                            node = edge.to
                    }

                    total_flow += flow
                }
            }

            return n
        }

        // Make random boards until we find a valid one
        var row_counts
        var column_counts
        while (true) {
            // Start with an empty field
            const GRASS = 0
            const TREE = 1
            const TENT = 2
            var grid = []
            for (var square = 0; square < rows * columns; square++)
                grid[square] = GRASS

            // Place tents randomly
            var n_placed = 0;
            var random_order = []
            for (var i = 0; i < grid.length; i++)
                random_order[i] = i
            shuffle (random_order)
            for (var i = 0; i < random_order.length && n_placed < n_trees; i++) {
                var index = random_order[i]
                var surrounding = surrounding_squares[index]

                var beside_tent = false
                for (var j = 0; j < surrounding.length; j++) {
                    if (grid[surrounding[j]] == TENT) {
                        beside_tent = true
                        break;
                    }
                }
                if (beside_tent)
                    continue

                grid[index] = TENT
                n_placed++
            }
            if (n_placed != n_trees)
                continue

            // Work out where to place trees using a flow network - this helps us resolve tents that can have a tree in a shared location
            // FIXME: Describe how this works
            var network = flow_network ()
            for (var square = 0; square < grid.length; square++) {
                if (grid[square] == TENT) {
                    network.add_edge (network.source, square + 2, 1)
                    var adjacent = adjacent_squares[square]
                    for (var i = 0; i < adjacent.length; i++)
                        if (grid[adjacent[i]] == GRASS)
                            network.add_edge (square + 2, adjacent[i] + 2, 1)
                }
                else
                    network.add_edge (square + 2, network.sink, 1)
            }
            // Randomize edges so different paths are taken
            shuffle (network.edges)
            var result = network.get_max_flow ()
            if (result.total_flow != n_trees)
                continue
            for (var i = 0; i < network.edges.length; i++) {
                var e = network.edges[i]
                if (e.to == network.sink && result.edge_flow[i] > 0)
                    grid[e.from - 2] = TREE
            }

            // Count tents
            var row_counts = []
            for (var row = 0; row < rows; row++) {
                var squares = row_squares[row]
                row_counts[row] = 0
                for (var i = 0; i < squares.length; i++)
                    if (grid[squares[i]] == TENT)
                        row_counts[row]++
            }
            var column_counts = []
            for (var column = 0; column < columns; column++) {
                var squares = column_squares[column]
                column_counts[column] = 0
                for (var i = 0; i < squares.length; i++)
                    if (grid[squares[i]] == TENT)
                        column_counts[column]++
            }

            // Remove everything except for the trees
            for (var i = 0; i < grid.length; i++)
                if (grid[i] != TREE)
                    grid[i] = undefined

            // Check is solvable (could have multiple solutions, we reject those)
            var s = solve (grid, row_counts, column_counts)
            if (s.solved && easy_rules_ == s.easy_rules) {
                solution = s.grid
                easy_rules = s.easy_rules
                break
            }
        }

        // Update the model with the generated puzzle
        for (var row = 0; row < rows; row++) {
            for (var column = 0; column < columns; column++) {
                var v = grid[row * columns + column]
                var cell = get_cell (row, column)
                if (v == TREE)
                    cell.state = "tree"
                else
                    cell.state = "unknown"
            }
        }
        for (var row = 0; row < rows; row++)
            get_row_count_cell (row).count = row_counts[row]
        for (var column = 0; column < columns; column++)
            get_column_count_cell (column).count = column_counts[column]
    }
    
    function reset () {
        started = false
        completed = false
        for (var row = 0; row < rows; row++) {
            for (var column = 0; column < columns; column++) {
                var cell = get_cell (row, column)
                if (cell.state != "tree")
                    cell.state = "unknown"
            }
        }
        for (var row = 0; row < rows; row++) {
            var cell = get_row_count_cell (row)
            cell.error = false
        }
        for (var column = 0; column < columns; column++) {
            var cell = get_column_count_cell (column)
            cell.error = false
        }
    }

    function solve (grid, row_counts, column_counts) {
        var result = {}

        // Array of tent / tree pairs
        var pairs = []

        // Copy the grid
        const GRASS = 0
        const TREE = 1
        const TENT = 2
        result.grid = []
        for (var i = 0; i < grid.length; i++)            
            result.grid[i] = grid[i]

        // Solve by applying the following rules:
        // 1. A square not adjacent to a tree must be grass.
        // 2. A tent cannot have another tent beside it.
        // 3. Pair together tents / trees when there is only one option.
        // 4. Where there are two options, set the other squares to grass
        // 5. Clear remaining squares in rows / columns to grass when we have
        //    placed enough tents.
        // 6. Try all the possibilities in rows columns and check if there are
        //    common outcomes (i.e. a square contains grass or a tent in all
        //    cases).
        result.easy_rules = true
        while (true) {
            var made_progress = false

            for (var square = 0; square < result.grid.length; square++) {
                var value = result.grid[square]
                var adjacent = adjacent_squares[square]
                var surrounding = surrounding_squares[square]

                // Unknown squares must be grass if beside a tent or no trees nearby
                if (value == undefined) {
                    function contains_unused_tree (squares) {
                        for (var i = 0; i < squares.length; i++)
                            if (result.grid[squares[i]] == TREE && pairs[squares[i]] == undefined)
                                return true
                        return false
                    }
                    function contains_tent (squares) {
                        for (var i = 0; i < squares.length; i++)
                            if (result.grid[squares[i]] == TENT)
                                return true
                        return false
                    }

                    if (contains_tent (surrounding) || !contains_unused_tree (adjacent)) {
                        result.grid[square] = GRASS
                        made_progress = true
                    }
                }

                // Find the tree this tent is paired with
                if (value == TENT && pairs[square] == undefined) {
                    var tree_squares = []
                    for (var i = 0; i < adjacent.length; i++) {
                        var adjacent_square = adjacent[i]
                        if (result.grid[adjacent_square] == TREE && pairs[adjacent_square] == undefined)
                            tree_squares[tree_squares.length] = adjacent_square
                    }
                    if (tree_squares.length == 1) {
                        var tree_square = tree_squares[0]
                        pairs[square] = tree_square
                        pairs[tree_square] = square
                        made_progress = true
                    }
                }

                // Find the tent this tree is paired with (placing it if only one location)
                if (value == TREE && pairs[square] == undefined) {
                    var tent_squares = []
                    for (var i = 0; i < adjacent.length; i++) {
                        var adjacent_square = adjacent[i]
                        if (result.grid[adjacent_square] == undefined ||
                            (result.grid[adjacent_square] == TENT && pairs[adjacent_square] == undefined))
                            tent_squares[tent_squares.length] = adjacent_square
                    }
                    if (tent_squares.length == 1) {
                        var tent_square = tent_squares[0]
                        result.grid[tent_square] = TENT
                        pairs[square] = tent_square
                        pairs[tent_square] = square
                        made_progress = true
                    }
                    // If only two possibilities, then some squares can be marked as grass, i.e.
                    //
                    // _?X  ___  ___  X?_
                    // _T?  _T?  ?T_  ?T_
                    // ___  _?X  X?_  ___
                    //
                    else if (tent_squares.length == 2 && !result.easy_rules) {
                        // Diagonal case is when midpoint is not the tree square
                        if (tent_squares[0] + tent_squares[1] != square * 2) {
                            // Corner is the original square + the deltas
                            var corner = square + (tent_squares[0] - square) + (tent_squares[1] - square)
                            if (result.grid[corner] == undefined) {
                                result.grid[corner] = GRASS
                                made_progress = true
                            }
                        }
                    }
                }
            }
            if (made_progress)
                continue

            // If unknown squares must be grass (all tents placed) or tents (only enough spaces for tents), then fill them
            function fill_squares (squares, tent_count) {
                var n_tents = 0
                var n_unknown = 0
                for (var i = 0; i < squares.length; i++) {
                    var square = result.grid[squares[i]]
                    if (square == TENT)
                        n_tents++
                    else if (square == undefined)
                        n_unknown++
                }

                if (n_unknown == 0)
                    return false

                var fill_value
                if (n_tents >= tent_count)
                    fill_value = GRASS
                else if (n_tents + n_unknown == tent_count)
                    fill_value = TENT
                else
                    return false

                for (var i = 0; i < squares.length; i++) {
                    var j = squares[i]
                    if (result.grid[j] == undefined)
                        result.grid[j] = fill_value
                }

                return true
            }
            for (var row = 0; row < rows; row++) {
                var squares = row_squares[row]
                if (fill_squares (squares, row_counts [row]))
                    made_progress = true
            }
            for (var column = 0; column < columns; column++) {
                var squares = column_squares[column]
                if (fill_squares (squares, column_counts [column]))
                    made_progress = true
            }
            if (made_progress)
                continue

            // Try all possibilities in a line and work out which squares must be tents / not tents
            // NOTE: This relies on the previous rules making sure any unknown square can contain a tent
            // FIXME: Doesn't reject overused trees (i.e. trees with more than one tent)
            function try_line (line, count) {
                // Make a line which we'll use to test all possibilities in
                // Make counters to check how many times we place a tent / grass in each square
                var test_grid = []
                var tent_counts = []
                var grass_counts = []
                for (var i = 0; i < result.grid.length; i++) {
                    test_grid[i] = undefined
                    tent_counts[i] = grass_counts[i] = 0
                }

                // Work out how many tents we need to try placing
                var n_to_place = count
                for (var i = 0; i < line.length; i++) {
                    if (result.grid[line[i]] == TENT)
                        n_to_place--
                }
                if (n_to_place <= 0)
                    return false;

                // Place tents as left as possible
                function place_tents (start_index, n_tents) {
                    var n_placed = 0
                    var last_index = 0;
                    for (var i = start_index; i < line.length && n_placed < n_tents; i++) {
                        if (result.grid[line[i]] == undefined) {
                            test_grid[line[i]] = TENT
                            last_index = i
                            n_placed++
                            // Skip next square because tents can't be adjacent
                            i++
                        }
                    }

                    if (n_placed != n_tents) {
                        for (var i = start_index; i < line.length; i++)
                            if (test_grid[line[i]] == TENT)
                                test_grid[line[i]] = undefined
                        return -1
                    }

                    return last_index
                }

                // Start with first possible layout. If none possible then something is broken!!
                var last_index = place_tents (0, n_to_place)
                if (last_index < 0)
                    return false;

                var n_possibilities = 0
                while (true) {
                    // Try the right most tent in all possible positions
                    for (var i = last_index; i < line.length; i++) {
                        if (result.grid[line[i]] == undefined) {
                            test_grid[line[last_index]] = undefined
                            test_grid[line[i]] = TENT
                            last_index = i

                            // Mark all squares adjacent our guessed tents and unknown spaces in the line with grass
                            for (var j = 0; j < line.length; j++) {
                                var square = line[j]
                                if (test_grid[square] == undefined && result.grid[square] == undefined)
                                    test_grid[square] = GRASS
                                if (test_grid[square] == TENT) {
                                    var surrounding = surrounding_squares[square]
                                    for (var k = 0; k < surrounding.length; k++)
                                        if (result.grid[surrounding[k]] == undefined)
                                            test_grid[surrounding[k]] = GRASS
                                }
                            }

                            function has_orphaned_tree () {
                                // Check unmatched trees have a possibility of a tent
                                for (var i = 0; i < line.length; i++) {
                                    var square = line[i]
                                    if (result.grid[square] == TREE && pairs[square] == undefined) {
                                        var adjacent = adjacent_squares[square]
                                        var n_possible_tents = 0
                                        for (var j = 0; j < adjacent.length; j++) {
                                            var adjacent_square = adjacent[j]
                                            if (test_grid[adjacent_square] == TENT)
                                                n_possible_tents++
                                            else if (test_grid[adjacent_square] != GRASS) {
                                                if ((result.grid[adjacent_square] == TENT && pairs[adjacent_square] == undefined) || result.grid[adjacent_square] == undefined)
                                                    n_possible_tents++
                                            }
                                        }
                                        if (n_possible_tents == 0)
                                            return true
                                    }
                                }

                                return false
                            }

                            // If this possibility is valid update counters of square state
                            if (!has_orphaned_tree ()) {
                                for (var j = 0; j < test_grid.length; j++) {
                                    if (test_grid[j] == GRASS)
                                        grass_counts[j]++
                                    else if (test_grid[j] == TENT)
                                        tent_counts[j]++
                                }
                                n_possibilities++
                            }

                            // Clear placed grass for next guess
                            for (var j = 0; j < test_grid.length; j++)
                                if (test_grid[j] == GRASS)
                                    test_grid[j] = undefined
                        }
                    }

                    // Find the rightmost tent that can move and the space it can move to
                    // Remove the unmovable tents as we pass them
                    function move_right () {
                        var movable_space = -1
                        var n_to_place = 0
                        for (var i = line.length - 1; i >= 0; i--) {
                            var square = line[i]
                            if (test_grid[square] == TENT) {
                                if (movable_space >= 0) {
                                    test_grid[square] = undefined
                                    test_grid[line[movable_space]] = TENT

                                    // Re-place tents as far left as possible after the one we could move
                                    var index = place_tents (movable_space + 2, n_to_place)
                                    if (index >= 0)
                                        return index

                                    // Can't move this tent, move onto the next one
                                    test_grid[line[movable_space]] = undefined
                                }

                                movable_space = -1
                                test_grid[square] = undefined
                                n_to_place++
                            }
                            else if (result.grid[square] == undefined)
                                movable_space = i
                        }

                        return -1
                    }
                    last_index = move_right ()
                    if (last_index < 0)
                        break
                }

                // Uh-oh... give up
                if (n_possibilities == 0)
                    return false

                // Check counters - if in all cases we placed the same then that must be the squares value
                var n_changed = 0
                for (var i = 0; i < result.grid.length; i++) {
                    if (tent_counts[i] == n_possibilities) {
                        result.grid[i] = TENT
                        n_changed++
                    }
                    else if (grass_counts[i] == n_possibilities) {
                        result.grid[i] = GRASS
                        n_changed++
                    }
                }

                return n_changed > 0
            }
            if (!result.easy_rules) {
                for (var row = 0; row < rows; row++)
                    if (try_line (row_squares[row], row_counts [row]))
                        made_progress = true
                for (var column = 0; column < columns; column++)
                    if (try_line (column_squares[column], column_counts [column]))
                        made_progress = true
            }

            // If tried all the rules either complete, or try harder rules or give up
            if (!made_progress) {
                result.solved = true
                for (var i = 0; i < result.grid.length; i++)
                    if (result.grid[i] == undefined)
                        result.solved = false
                if (result.solved)
                    return result

                if (result.easy_rules)
                    result.easy_rules = false // Try with harder rules
                else
                    return result // Failed to solve
            }
        }
    }

    function is_solved () {
        const TREE = 1
        const TENT = 2
        for (var row = 0; row < rows; row++) {
            for (var column = 0; column < columns; column++) {
                var cell = get_cell (row, column)
                var s = solution[row * columns + column]
                if (s == TENT && cell.state != "tent" ||
                    s != TENT && cell.state == "tent")
                    return false
            }
        }

        return true
    }

    function set_state (index, state) {
        // Consider the first move as the game start. This does mean any time
        // taken to consider your moves is not counted, but this is better
        // than having a super long duration from a game that wasn't being
        // looked at
        if (!started) {
            start_time = new Date ()
            app.timer = 0
            timerO.start()
            started = true
        }

        var cell = get (index)
        cell.state = state

        var row = Math.floor (index / (columns + 1)) - 1
        var column = index % (columns + 1) - 1
        var n_tents = 0
        var n_unknown = 0
        for (var c = 0; c < columns; c++) {
            var cell = get_cell (row, c).state
            if (cell == "tent")
                n_tents++
            if (cell == "unknown")
                n_unknown++
        }
        cell = get_row_count_cell (row)
        cell.error = n_tents > cell.count || n_tents + n_unknown < cell.count
        n_tents = 0
        n_unknown = 0
        for (var r = 0; r < rows; r++) {
            var cell = get_cell (r, column).state
            if (cell == "tent")
                n_tents++
            if (cell == "unknown")
                n_unknown++
        }
        cell = get_column_count_cell (column)
        cell.error = n_tents > cell.count || n_tents + n_unknown < cell.count

        // Check if solved and mark all unknown squares as grass if done
        completed = is_solved ()
        if (completed) {
            end_time = new Date ()
            for (var row = 0; row < rows; row++) {
                for (var column = 0; column < columns; column++) {
                    var cell = get_cell (row, column)
                    if (cell.state == "unknown")
                        cell.state = "grass"
                }
            }
            timerO.stop()
            solved ()
            app.game_over()
        }
    }

    function get_cell (row, column) {
        return get ((row + 1) * (columns + 1) + (column + 1))
    }
    
    function get_row_count_cell (row) {
        return get ((row + 1) * (columns + 1))
    }

    function get_column_count_cell (column) {
        return get (column + 1)
    }
}
