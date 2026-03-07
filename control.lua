-----------------------------
-- State
-----------------------------
-- Only one CURRENT temporary endcap is tracked at a time.
-- When a new isolated chain is started, the previous chain's endcap becomes "permanent" (stop tracking it).
local isolated_cliffs = {} ---@type LuaEntity[] Tracks isolated starters (may contain many).
local free_end = nil ---@type LuaEntity|nil Current temporary endcap ONLY (the most recently spawned helper endcap).
local free_end_owner = nil ---@type LuaEntity|nil The isolated starter cliff that owns `free_end`.

-- Most recently started isolated chain that does NOT have an endcap yet.
-- When a new isolated chain start is placed, spawn an endcap for the PREVIOUS pending starter,
-- then mark the newly placed starter as pending.
local pending_isolated = nil ---@type LuaEntity|nil
local pending_isolated_dir = nil ---@type string|nil Cardinal direction ("north"|"south"|"east"|"west") used to place that pending starter's endcap.

-----------------------------
-- Small helpers
-----------------------------

local VISIBLE_PREFIX = "visible-4x4-"
local INVISIBLE_PREFIX = "invisible-4x4-"

--- Returns whether `str` begins with `prefix`.
--- @param str string|nil String to test.
--- @param prefix string Prefix to check for.
--- @return boolean
local function starts_with(str, prefix)
    return type(str) == "string" and string.sub(str, 1, #prefix) == prefix
end

--- Converts a visible marker prototype name into its cliff prototype name.
--- Example: `"visible-4x4-cf-cliff"` -> `"cf-cliff"`.
--- @param marker_name string
--- @return string|nil cliff_entity_name
local function cliff_name_from_visible_marker(marker_name)
    if not starts_with(marker_name, VISIBLE_PREFIX) then return nil end
    return string.sub(marker_name, #VISIBLE_PREFIX + 1)
end

--- Converts a cliff prototype name into its invisible marker prototype name.
--- Example: `"cf-cliff"` -> `"invisible-4x4-cf-cliff"`.
--- @param cliff_entity_name string
--- @return string marker_entity_name
local function invisible_marker_name_for_cliff(cliff_entity_name)
    return INVISIBLE_PREFIX .. cliff_entity_name
end

--- Converts an invisible marker prototype name into its visible marker prototype name.
--- Example: `"invisible-4x4-cf-cliff"` -> `"visible-4x4-cf-cliff"`.
--- @param marker_name string
--- @return string|nil visible_marker_name
local function visible_marker_name_from_invisible(marker_name)
    if not starts_with(marker_name, INVISIBLE_PREFIX) then return nil end
    return VISIBLE_PREFIX .. string.sub(marker_name, #INVISIBLE_PREFIX + 1)
end

--- Finds a value in an array-like table.
--- @param lookup_table table|nil Array-like table to search.
--- @param value any Value to find.
--- @param return_index boolean|nil When true, also returns the matching index.
--- @return boolean found
--- @return integer|nil index
local function helper_find_in_table(lookup_table, value, return_index)
    if not lookup_table then return false end
    for index, element in ipairs(lookup_table) do
        if element == value then
            if return_index then return true, index end
            return true
        end
    end
    return false
end

--- Splits a string by a Lua pattern delimiter.
--- Defaults to whitespace when `separator` is nil.
--- @param input_str string
--- @param separator string|nil Lua pattern used as delimiter.
--- @return string[] tokens
local function tokenize(input_str, separator)
    if separator == nil then
        separator = "%s"
    end
    local tokens = {}
    for str in string.gmatch(input_str, "([^" .. separator .. "]+)") do
        table.insert(tokens, str)
    end
    return tokens
end

-----------------------------
-- Cardinal / direction utils
-----------------------------

--- Returns the opposite cardinal direction.
--- @param direction string `"north"`|`"south"`|`"east"`|`"west"`
--- @return string|nil opposite_direction
local function cardinal_reverse(direction)
    if direction == "north" then
        return "south"
    elseif direction == "south" then
        return "north"
    elseif direction == "east" then
        return "west"
    elseif direction == "west" then
        return "east"
    end
end

--- Returns the cardinal direction from `cliff` to `adjacent_cliff`
--- based on their position delta.
--- @param cliff LuaEntity
--- @param adjacent_cliff LuaEntity
--- @return string|nil direction `"north"`|`"south"`|`"east"`|`"west"`
local function cardinal(cliff, adjacent_cliff)
    local dx = adjacent_cliff.position.x - cliff.position.x
    local dy = adjacent_cliff.position.y - cliff.position.y

    -- prefer the dominant axis and require some minimum separation
    if math.abs(dx) > math.abs(dy) then
        if dx > 0 then return "east" end
        if dx < 0 then return "west" end
    else
        if dy > 0 then return "south" end
        if dy < 0 then return "north" end
    end

    return nil
end

--- Returns whether a direction is horizontal.
--- @param d string
--- @return boolean
local function is_horizontal_dir(d)
    return d == "east" or d == "west"
end

--- Returns whether a direction is vertical.
--- @param d string
--- @return boolean
local function is_vertical_dir(d)
    return d == "north" or d == "south"
end

--- Returns whether the two directions are opposites.
--- @param a string
--- @param b string
--- @return boolean
local function is_opposite(a, b)
    return a == cardinal_reverse(b)
end

--- Returns whether the two directions form a corner/curve.
--- @param a string
--- @param b string
--- @return boolean
local function is_curve(a, b)
    if not (a and b) then return false end
    return a and b and a ~= b and not is_opposite(a, b)
end

--- Creates an order-independent key for a pair of strings.
--- @param dir1 string
--- @param dir2 string
--- @return string key
local function make_unordered_pair_key(dir1, dir2)
    return (dir1 < dir2) and (dir1 .. "|" .. dir2) or (dir2 .. "|" .. dir1)
end

-----------------------------
-- Orientation utils
-----------------------------

--- Rotates a cliff until it matches `target`, or rotates once when `target` is nil.
--- @param cliff_to_rotate LuaEntity
--- @param target string|nil Orientation string such as `"north-to-south"` or `"none-to-east"`.
local function rotate_cliff(cliff_to_rotate, target)
    if target then
        local attempts = 0
        while cliff_to_rotate.cliff_orientation ~= target and attempts < 20 do
            cliff_to_rotate.rotate()
            attempts = attempts + 1
        end
    else
        cliff_to_rotate.rotate()
    end
end

--- Flips a directed orientation string by swapping endpoints.
--- Example: `"north-to-east"` -> `"east-to-north"`.
--- @param orientation string
--- @return string flipped_orientation
local function flip_orientation(orientation)
    local tokens = tokenize(orientation, "-")
    return tokens[3] .. "-to-" .. tokens[1]
end

--- Parses a directed orientation string of the form `"a-to-b"`.
--- @param orientation string
--- @return string from_dir
--- @return string to_dir
local function parse_from_to(orientation)
    local tokens = tokenize(orientation, "-")
    return tokens[1], tokens[3] -- KEEP ORDER
end

--- Adjusts an end-segment orientation when a new direction is attached or removed.
--- @param keep_as_end_seg boolean Whether the neighbor should remain an end segment.
--- @param orientation string Existing orientation string.
--- @param new_direction string New cardinal direction to insert.
--- @return string swapped_orientation
local function swap_orientation(keep_as_end_seg, orientation, new_direction)
    if type(new_direction) ~= "string" then return orientation end

    local tokens = tokenize(orientation, "-")
    if tokens[1] == "none" then
        tokens[1] = new_direction
    elseif keep_as_end_seg == true then
        tokens[1] = "none"
    end
    if tokens[3] == "none" then
        tokens[3] = new_direction
    elseif keep_as_end_seg == true then
        tokens[3] = "none"
    end

    return tokens[1] .. "-to-" .. tokens[3]
end

--- Returns cliffs found exactly 4 tiles away from `cliff` in one cardinal direction.
--- @param cliff LuaEntity
--- @param direction string
--- @return LuaEntity[] neighbors
local function get_cliff_neighbors_in_direction(cliff, direction)
    local surface = cliff.surface
    if not (surface and surface.valid) then return {} end

    local position = { x = cliff.position.x, y = cliff.position.y }

    if direction == "north" then
        position.y = position.y - 4
    elseif direction == "south" then
        position.y = position.y + 4
    elseif direction == "east" then
        position.x = position.x + 4
    elseif direction == "west" then
        position.x = position.x - 4
    else
        return {}
    end

    return surface.find_entities_filtered {
        type = "cliff",
        position = position,
        radius = 1
    } or {}
end

--- Returns neighboring cliffs adjacent to `cliff`.
--- When `direction` is nil, returns the union of the exact 4-tile N/E/S/W probes.
--- When `direction` is cardinal, probes only that 4-tile offset.
--- @param cliff LuaEntity
--- @param direction string|nil
--- @return LuaEntity[] neighbors
local function get_cliff_neighbors(cliff, direction)
    if direction then
        return get_cliff_neighbors_in_direction(cliff, direction)
    end

    local out = {}
    local directions = {
        "north",
        "east",
        "south",
        "west"
    }

    for _, dir in ipairs(directions) do
        for _, entity in ipairs(get_cliff_neighbors_in_direction(cliff, dir)) do
            table.insert(out, entity)
        end
    end
    return out
end

--- Returns the first valid cliff 4 tiles away in the given direction, if any.
--- @param cliff LuaEntity
--- @param direction string
--- @return LuaEntity|nil neighbor
local function get_neighbor(cliff, direction)
    local list = get_cliff_neighbors(cliff, direction)
    local neighbor = list and list[1] or nil
    if neighbor and neighbor.valid then return neighbor end
    return nil
end

--- Returns all cardinal neighbors that are currently end-segments
--- (their orientation contains `"none"`).
--- @param cliff LuaEntity
--- @return LuaEntity[] end_neighbors
local function get_cardinal_end_neighbors(cliff)
    local out = {}
    local directions = {
        "north",
        "east",
        "south",
        "west"
    }

    for _, direction in ipairs(directions) do
        local neighbor = get_neighbor(cliff, direction)
        if neighbor and neighbor.valid and string.find(neighbor.cliff_orientation, "none") then
            table.insert(out, neighbor)
        end
    end
    return out
end

--- Removes a cliff from all state structures and tracked temporary endcaps.
--- If the cliff owns the currently tracked temporary endcap, that endcap is destroyed.
--- @param cliff LuaEntity|nil
local function forget_cliff_everywhere(cliff)
    if not cliff then return end

    -- remove from isolated_cliffs list
    local found, index = helper_find_in_table(isolated_cliffs, cliff, true)
    if found then table.remove(isolated_cliffs, index) end

    -- pending
    if pending_isolated == cliff then
        pending_isolated = nil
        pending_isolated_dir = nil
    end

    -- free end owner tracking
    if free_end_owner == cliff then
        if free_end and free_end.valid then free_end.destroy() end
        free_end = nil
        free_end_owner = nil
    end
end

-----------------------------
-- Chain analysis
-----------------------------

--- Walks the cliff chain starting at `start_cliff` and determines whether it forms a loop.
--- Chains with branching (`> 2` valid neighbors) are treated as loop-like/closed for this logic.
--- @param start_cliff LuaEntity
--- @return boolean is_loop
local function chain_is_loop(start_cliff)
    if not (start_cliff and start_cliff.valid) then return false end

    local previous = nil
    local current = start_cliff

    local steps = 0
    local max_cliffs = 1000

    while current and current.valid do
        steps = steps + 1
        if steps > max_cliffs then
            return false
        end

        local neighbors = get_cliff_neighbors(current) or {}

        local valid_neighbors = {}
        for _, neighbor in ipairs(neighbors) do
            if neighbor and neighbor.valid and neighbor ~= current then
                table.insert(valid_neighbors, neighbor)
            end
        end

        if current == start_cliff and previous == nil then
            if #valid_neighbors < 2 then
                return false
            end
        end

        if #valid_neighbors > 2 then
            return true
        end

        local next_cliff = nil
        for _, neighbor in ipairs(valid_neighbors) do
            if neighbor ~= previous then
                next_cliff = neighbor
                break
            end
        end

        if not next_cliff then
            return false
        end

        if next_cliff == start_cliff then
            return true
        end

        previous = current
        current = next_cliff
    end

    return false
end

-----------------------------
-- Isolated chain state
-----------------------------

--- Handles the transition from "isolated starter" state to connected-chain state.
--- Removes the cliff from isolated tracking, clears pending state, and destroys any tracked
--- temporary endcap owned by that starter.
--- @param cliff LuaEntity
--- @return boolean was_isolated True when the cliff had isolated state to clear.
local function check_isolated(cliff)
    local found, index = helper_find_in_table(isolated_cliffs, cliff, true)
    if not found then return false end

    table.remove(isolated_cliffs, index)

    if pending_isolated == cliff then
        pending_isolated = nil
        pending_isolated_dir = nil
    end

    if free_end_owner == cliff then
        if free_end and free_end.valid then
            free_end.destroy()
        end
        free_end = nil
        free_end_owner = nil
    end

    return true
end

--- Spawns the invisible marker companion entity for a cliff, if missing.
--- @param cliff LuaEntity
local function spawn_invisible_marker_for_cliff(cliff)
    if not (cliff and cliff.valid) then return end
    local surface = cliff.surface
    if not (surface and surface.valid) then return end

    local marker_name = invisible_marker_name_for_cliff(cliff.name)

    -- prevent duplicates
    local existing = surface.find_entities_filtered {
        name = marker_name,
        position = cliff.position,
        radius = 1
    }
    if existing and existing[1] then return end

    local created = surface.create_entity {
        name = marker_name,
        position = cliff.position,
        force = cliff.force,
        raise_built = false
    }
end

--- Spawns a helper endcap cliff 4 tiles away from `cliff` in `direction`.
--- The spawned helper is tracked as the current temporary `free_end`.
--- @param cliff LuaEntity
--- @param direction string Cardinal direction for placement.
local function spawn_endcap(cliff, direction)
    if not (cliff and cliff.valid) then return end
    local surface = cliff.surface

    local position = { x = cliff.position.x, y = cliff.position.y }

    if direction == "north" then
        position.y = position.y - 4
    elseif direction == "south" then
        position.y = position.y + 4
    elseif direction == "east" then
        position.x = position.x + 4
    elseif direction == "west" then
        position.x = position.x - 4
    else
        position.y = position.y + 4
        direction = "south"
    end

    if surface.can_place_entity and not surface.can_place_entity {
            name = cliff.name,
            position = position,
            force = cliff.force
        } then
        return
    end

    local free_cliff = surface.create_entity {
        name = cliff.name,
        position = position,
        force = cliff.force,
        raise_built = false
    }

    if free_cliff and free_cliff.valid then
        -- Marker for the spawned endcap
        spawn_invisible_marker_for_cliff(free_cliff)

        free_end = free_cliff
        local back = cardinal_reverse(direction)
        rotate_cliff(free_end, back .. "-to-none")
    end
end

-----------------------------
-- Chain operations (flip)
-----------------------------

--- Returns whether an orientation uses the given direction on either end.
--- @param orientation string
--- @param direction string
--- @return boolean
local function orientation_has_direction(orientation, direction)
    local from_direction, to_direction = parse_from_to(orientation)
    return from_direction == direction or to_direction == direction
end

--- Returns whether two cliffs are actually connected to each other.
--- They must be cardinal neighbors and each orientation must point toward the other.
--- @param cliff LuaEntity
--- @param neighbor LuaEntity
--- @return boolean
local function cliffs_are_connected(cliff, neighbor)
    if not (cliff and cliff.valid and neighbor and neighbor.valid) then return false end

    local direction = cardinal(cliff, neighbor)
    if not direction then return false end

    local opposite_direction = cardinal_reverse(direction)
    if not opposite_direction then return false end

    return orientation_has_direction(cliff.cliff_orientation, direction)
        and orientation_has_direction(neighbor.cliff_orientation, opposite_direction)
end

--- Returns the actually connected cardinal chain neighbors (N/E/S/W) of `cliff`.
--- Nearby cliffs that do not connect through matching orientations are ignored.
--- @param cliff LuaEntity
--- @return LuaEntity[] neighbors
local function get_cardinal_chain_neighbors(cliff)
    local out = {}

    for _, direction in ipairs({ "north", "east", "south", "west" }) do
        local neighbor = get_neighbor(cliff, direction)
        if neighbor and neighbor.valid and neighbor ~= cliff then
            if cliffs_are_connected(cliff, neighbor) then
                table.insert(out, neighbor)
            end
        end
    end

    return out
end

--- Recursively flips the orientation of the connected cliff chain by spatial adjacency.
--- `flip_record` is used as a visited set in array form to prevent re-entry on loops.
--- @param flip_record LuaEntity[] Visited cliffs.
--- @param cliff LuaEntity
local function flip_chain(flip_record, cliff)
    if not (cliff and cliff.valid) then return end
    if helper_find_in_table(flip_record, cliff) then return end

    -- Mark visited first to prevent cycles from re-entering
    table.insert(flip_record, cliff)

    local new = flip_orientation(cliff.cliff_orientation)
    rotate_cliff(cliff, new)

    for _, next_cliff in ipairs(get_cardinal_chain_neighbors(cliff)) do
        flip_chain(flip_record, next_cliff)
    end
end

-----------------------------
-- Loop joint orientation (curve/straight)
-----------------------------

-- Given the two neighbor directions (relative to this cliff), pick which corner it is.
local CORNER_FROM_NEIGHBORS = {
    [make_unordered_pair_key("east", "south")] = "NW",
    [make_unordered_pair_key("south", "west")] = "NE",
    [make_unordered_pair_key("north", "west")] = "SE",
    [make_unordered_pair_key("east", "north")] = "SW",
}

-- For each corner, you have two directed curve images (flip).
-- Choose between them based on whether the H-neighbor touches on its TO vs FROM.
local CURVE_VARIANTS = {
    NW = { horizontal_to_touch = "east-to-south", horizontal_from_touch = "south-to-east" },
    NE = { horizontal_to_touch = "west-to-south", horizontal_from_touch = "south-to-west" },
    SE = { horizontal_to_touch = "west-to-north", horizontal_from_touch = "north-to-west" },
    SW = { horizontal_to_touch = "east-to-north", horizontal_from_touch = "north-to-east" },
}

--- Chooses the directed curve orientation for a loop joint based on neighbor directions
--- and the directed touch side of the horizontal neighbor.
--- @param direction_1 string
--- @param neighbor_1 LuaEntity
--- @param direction_2 string
--- @param neighbor_2 LuaEntity
--- @return string orientation
local function choose_curve_orientation_from_neighbors(direction_1, neighbor_1, direction_2, neighbor_2)
    local corner = CORNER_FROM_NEIGHBORS[make_unordered_pair_key(direction_1, direction_2)]
    if not corner then
        return direction_1 .. "-to-" .. direction_2
    end

    local horizontal_direction, horizontal_neighbor = nil, nil
    local vertical_direction, vertical_neighbor = nil, nil

    if is_horizontal_dir(direction_1) then horizontal_direction, horizontal_neighbor = direction_1, neighbor_1 end
    if is_horizontal_dir(direction_2) then horizontal_direction, horizontal_neighbor = direction_2, neighbor_2 end
    if is_vertical_dir(direction_1) then vertical_direction, vertical_neighbor = direction_1, neighbor_1 end
    if is_vertical_dir(direction_2) then vertical_direction, vertical_neighbor = direction_2, neighbor_2 end

    if not (horizontal_direction and horizontal_neighbor and vertical_direction and vertical_neighbor) then
        return direction_1 .. "-to-" .. direction_2
    end

    local touch_side = cardinal_reverse(horizontal_direction)
    local horizontal_from, horizontal_to = parse_from_to(horizontal_neighbor.cliff_orientation)

    local variants = CURVE_VARIANTS[corner]
    if not variants then
        return direction_1 .. "-to-" .. direction_2
    end

    if horizontal_to == touch_side then
        return variants.horizontal_to_touch
    elseif horizontal_from == touch_side then
        return variants.horizontal_from_touch
    end

    return variants.horizontal_to_touch
end

--- Chooses the directed straight orientation for a loop joint by comparing how the two
--- neighboring directed segments touch this cliff.
--- @param direction_1 string
--- @param neighbor_1 LuaEntity
--- @param direction_2 string
--- @param neighbor_2 LuaEntity
--- @return string orientation
local function choose_straight_orientation_from_neighbors(direction_1, neighbor_1, direction_2, neighbor_2)
    --- Returns whether the neighbor touches this cliff via its FROM or TO side.
    --- @param neighbor LuaEntity
    --- @param touch_side string
    --- @return string|nil
    local function touch_end(neighbor, touch_side)
        if not touch_side then return nil end

        local neighbor_from, neighbor_to = parse_from_to(neighbor.cliff_orientation)
        if neighbor_to == touch_side then return "TO" end
        if neighbor_from == touch_side then return "FROM" end
        return nil
    end

    local touch_side_1 = cardinal_reverse(direction_1)
    local touch_side_2 = cardinal_reverse(direction_2)
    if not (touch_side_1 and touch_side_2) then return "" end

    local end_type_1 = touch_end(neighbor_1, touch_side_1)
    local end_type_2 = touch_end(neighbor_2, touch_side_2)

    --- Scores how many directed touches favor a candidate from->to orientation.
    --- @param from_direction string
    --- @param to_direction string
    --- @return integer
    local function touches(from_direction, to_direction)
        local touch = 0
        if end_type_1 == "TO" and from_direction == direction_1 then touch = touch + 1 end
        if end_type_2 == "TO" and from_direction == direction_2 then touch = touch + 1 end
        if end_type_1 == "FROM" and to_direction == direction_1 then touch = touch + 1 end
        if end_type_2 == "FROM" and to_direction == direction_2 then touch = touch + 1 end
        return touch
    end

    local touch_1 = touches(direction_1, direction_2)
    local touch_2 = touches(direction_2, direction_1)

    if touch_2 > touch_1 then
        return direction_2 .. "-to-" .. direction_1
    else
        return direction_1 .. "-to-" .. direction_2
    end
end

--- Chooses the correct joint orientation for a loop closure cliff.
--- Uses curve logic for corners and straight logic for opposites.
--- @param cliff LuaEntity
--- @param direction_1 string
--- @param direction_2 string
--- @return string orientation
local function choose_loop_joint_orientation(cliff, direction_1, direction_2)
    local neighbor_along_direction_1 = get_neighbor(cliff, direction_1)
    local neighbor_along_direction_2 = get_neighbor(cliff, direction_2)

    if neighbor_along_direction_1 and neighbor_along_direction_2 then
        if is_curve(direction_1, direction_2) then
            return choose_curve_orientation_from_neighbors(direction_1, neighbor_along_direction_1, direction_2,
                neighbor_along_direction_2)
        elseif is_opposite(direction_1, direction_2) then
            return choose_straight_orientation_from_neighbors(direction_1, neighbor_along_direction_1, direction_2,
                neighbor_along_direction_2)
        end
    end

    return direction_1 .. "-to-" .. direction_2
end

--- Ensures directed continuity across a non-loop joint by flipping either side chain
--- when its touch direction does not match the new joint orientation.
--- @param cliff LuaEntity
--- @param direction_1 string
--- @param direction_2 string
local function ensure_chain_continuity(cliff, direction_1, direction_2)
    local up = get_neighbor(cliff, direction_1)
    local down = get_neighbor(cliff, direction_2)
    if not (up and down) then return end

    local cliff_split = tokenize(cliff.cliff_orientation, "-")
    local up_split = tokenize(up.cliff_orientation, "-")
    local down_split = tokenize(down.cliff_orientation, "-")

    if cliff_split[1] ~= cardinal_reverse(up_split[3]) then
        flip_chain({ cliff }, up)
    end

    if cliff_split[3] ~= cardinal_reverse(down_split[1]) then
        flip_chain({ cliff }, down)
    end
end

-----------------------------
-- Marker helpers / ghost->cliff helpers
-----------------------------

--- Removes any invisible companion marker matching a given cliff's name and position.
--- @param cliff LuaEntity
local function remove_invisible_marker_for_cliff(cliff)
    if not (cliff and cliff.valid) then return end
    local surface = cliff.surface
    local marker_name = invisible_marker_name_for_cliff(cliff.name)

    local markers = surface.find_entities_filtered {
        name = marker_name,
        position = cliff.position,
        radius = 1
    }
    for _, marker in ipairs(markers) do
        if marker and marker.valid then marker.destroy() end
    end
end

--- Attempts to spawn a real cliff from a visible marker entity name.
--- Any provided blueprint orientation tag is applied to the spawned cliff.
--- @param surface LuaSurface
--- @param position MapPosition
--- @param force LuaForce|string|int
--- @param marker_entity_name string Visible marker entity prototype name.
--- @param tags Tags|nil Blueprint/entity tags.
--- @return LuaEntity|nil cliff
local function try_spawn_cliff_from_marker(surface, position, force, marker_entity_name, tags)
    if not (surface and surface.valid and position and marker_entity_name) then return nil end

    local cliff_name = cliff_name_from_visible_marker(marker_entity_name)
    if not cliff_name then return nil end

    if surface.can_place_entity and not surface.can_place_entity {
            name = cliff_name,
            position = position,
            force = force
        } then
        return nil
    end

    local cliff = surface.create_entity {
        name = cliff_name,
        position = position,
        force = force,
        raise_built = false
    }
    if not (cliff and cliff.valid) then return nil end

    if tags and tags.cf_cliff_orientation then
        rotate_cliff(cliff, tostring(tags.cf_cliff_orientation))
    end

    return cliff
end

-----------------------------
-- Cliff placement/orientation logic (refactored to accept entity)
-----------------------------

--- Handles placement/orientation logic for a newly built live cliff.
--- When `suppress_endcaps` is true, isolated placement will not create or advance helper endcaps.
--- @param cliff LuaEntity
--- @param suppress_endcaps boolean
local function handle_cliff_built(cliff, suppress_endcaps)
    if not (cliff and cliff.valid and cliff.type == "cliff") then return end

    spawn_invisible_marker_for_cliff(cliff)

    local adjacent_ends = get_cardinal_end_neighbors(cliff)

    -- Case: starting an isolated chain
    if next(adjacent_ends) == nil then
        if suppress_endcaps then
            if not cliff.cliff_orientation or cliff.cliff_orientation == "none-to-none" then
                rotate_cliff(cliff, "none-to-north")
            end
            return
        end

        table.insert(isolated_cliffs, cliff)

        local set_direction
        if #get_cliff_neighbors(cliff, "north") > 0 then
            set_direction = "east"
        elseif #get_cliff_neighbors(cliff, "east") > 0 then
            set_direction = "south"
        elseif #get_cliff_neighbors(cliff, "south") > 0 then
            set_direction = "west"
        elseif #get_cliff_neighbors(cliff, "west") > 0 then
            set_direction = "north"
        else
            set_direction = "north"
        end

        rotate_cliff(cliff, "none-to-" .. set_direction)

        if pending_isolated and pending_isolated.valid and pending_isolated_dir then
            spawn_endcap(pending_isolated, pending_isolated_dir)
            free_end_owner = pending_isolated
        end

        pending_isolated = cliff
        pending_isolated_dir = set_direction
        return
    end

    -- Case: extending from one endcap
    if #adjacent_ends == 1 then
        local adjacent_cliff = adjacent_ends[1]
        local cardinal_dir = cardinal(cliff, adjacent_cliff)
        if not cardinal_dir then return end
        local inv_cardinal = cardinal_reverse(cardinal_dir)
        if not inv_cardinal then return end
        local adj_orientation = adjacent_cliff.cliff_orientation

        local adj_orientation_new = swap_orientation(check_isolated(adjacent_cliff), adj_orientation, inv_cardinal)
        rotate_cliff(adjacent_cliff, adj_orientation_new)

        local split_string = tokenize(adj_orientation, "-")
        local orientation_new
        if split_string[1] == "none" then
            orientation_new = "none-to-" .. cardinal_dir
        elseif split_string[3] == "none" then
            orientation_new = cardinal_dir .. "-to-none"
        end
        rotate_cliff(cliff, orientation_new)
        return
    end

    -- Case: joining two endcaps (straight or curve)
    if #adjacent_ends == 2 then
        local direction_1
        local direction_2

        for index, adjacent_cliff in ipairs(adjacent_ends) do
            local cardinal_dir = cardinal(cliff, adjacent_cliff)
            if not cardinal_dir then return end
            local inv_cardinal = cardinal_reverse(cardinal_dir)
            if not inv_cardinal then return end
            local adj_orientation = adjacent_cliff.cliff_orientation

            local adj_orientation_new = swap_orientation(check_isolated(adjacent_cliff), adj_orientation, inv_cardinal)

            if index == 1 then
                direction_1 = cardinal_dir
            elseif index == 2 then
                direction_2 = cardinal_dir
            end

            rotate_cliff(adjacent_cliff, adj_orientation_new)
        end

        if adjacent_ends[1].cliff_orientation == adjacent_ends[2].cliff_orientation then
            rotate_cliff(cliff, adjacent_ends[1].cliff_orientation)
        else
            rotate_cliff(cliff, direction_1 .. "-to-" .. direction_2)
        end

        if chain_is_loop(cliff) then
            local target_orientation = choose_loop_joint_orientation(cliff, direction_1, direction_2)
            rotate_cliff(cliff, target_orientation)
        else
            ensure_chain_continuity(cliff, direction_1, direction_2)
        end

        return
    end
end

--- Destroys any cliff or invisible marker entities occupying the given tile probe area.
--- Used before restoring a real cliff from a visible marker.
--- @param surface LuaSurface
--- @param position MapPosition
local function clear_cliff_tile(surface, position)
    local entities = surface.find_entities_filtered {
        position = position,
        radius = 1
    }

    for _, entity in ipairs(entities) do
        if entity.valid and (entity.type == "cliff" or starts_with(entity.name, INVISIBLE_PREFIX)) then
            entity.destroy()
        end
    end
end

-----------------------------
-- Event handlers
-----------------------------

--- Unified built-entity dispatcher for real cliffs and visible markers.
--- Visible marker ghosts are ignored until they become real entities.
--- Handles player builds, robot builds, and script-raised builds/revives.
--- @param event EventData.on_built_entity
---| EventData.on_robot_built_entity
---| EventData.script_raised_built
---| EventData.script_raised_revive
local function on_any_built(event)
    local entity = event.entity
    if not (entity and entity.valid) then return end

    -- normal cliff
    if entity.type == "cliff" then
        handle_cliff_built(entity, false)
        return
    end

    -- ignore visible ghost; conversion happens when it becomes real
    if entity.type == "entity-ghost" and starts_with(entity.ghost_name, VISIBLE_PREFIX) then
        return
    end

    -- robots built the real visible marker
    if starts_with(entity.name, VISIBLE_PREFIX) then
        local surface = entity.surface
        local position = entity.position
        local force = entity.force
        local marker_name = entity.name

        local tags = event.tags
        if tags and tags.cf_missing_cliff then
            entity.destroy()
            return
        end

        -- Remove marker first so it can’t block placement
        entity.destroy()

        clear_cliff_tile(surface, position)

        local spawned = try_spawn_cliff_from_marker(surface, position, force, marker_name, tags)
        if spawned then
            -- For blueprint/copy-paste restoration, the saved tag already contains
            -- the correct final cliff orientation. Do not run normal placement logic
            -- against a partially constructed robot-built chain.
            spawn_invisible_marker_for_cliff(spawned)
        end
        return
    end
end

--- Handles cliff removal/mining/death cleanup.
--- Also refunds silently deleted newly-isolated neighbor endcaps to the mining player, when present.
--- @param event EventData.on_player_mined_entity
---| EventData.on_robot_mined_entity
---| EventData.on_entity_died
local function on_cliff_removed(event)
    local cliff = event.entity
    if not (cliff and cliff.valid and cliff.type == "cliff") then return end

    local player = event.player_index and game.get_player(event.player_index) or nil
    local neighbors = get_cliff_neighbors(cliff)

    -- Handle the engine silently deleting the newly-isolated neighbor
    -- The neighbor is invalid at this point
    if neighbors then
        for _, neighbor in ipairs(neighbors) do
            if neighbor and neighbor.type == "cliff" and string.find(neighbor.cliff_orientation, "none") then
                remove_invisible_marker_for_cliff(neighbor)
                forget_cliff_everywhere(neighbor)

                if player then
                    player.insert { name = neighbor.name, count = 1 }
                end
            end
        end
    end

    -- Always remove marker for the cliff that was explicitly removed
    remove_invisible_marker_for_cliff(cliff)
    forget_cliff_everywhere(cliff)
end

-----------------------------
-- Custom input handlers
-----------------------------

--- Flips the entire connected chain under the cursor when the selected prototype is a cliff.
--- @param event EventData.CustomInputEvent
local function flip_cliff_event(event)
    local entity = event.selected_prototype
    if entity then
        if entity.derived_type == "cliff" then
            local player = game.get_player(event.player_index)
            if not player then return end
            local surface = player.surface
            local cliff = surface.find_entities_filtered({ type = "cliff", position = event.cursor_position, radius = 1 })
            if cliff[1] then
                local flip_record = {}
                flip_chain(flip_record, cliff[1])
            end
        end
    end
end

--- Flips only the currently selected cliff entity.
--- @param event EventData.CustomInputEvent
local function flip_cliff_selected_event(event)
    local player = game.get_player(event.player_index)
    if not player then return end

    local entity = player.selected
    if entity and entity.valid and entity.type == "cliff" then
        local cliff = entity
        local new = flip_orientation(cliff.cliff_orientation)
        rotate_cliff(cliff, new)
    end
end

--- Displays the orientation of the currently selected cliff as local flying text.
--- @param event EventData.CustomInputEvent
local function display_selected_cliff_orientation(event)
    local player = game.get_player(event.player_index)
    if not player then return end

    local entity = player.selected
    if entity and entity.valid and entity.type == "cliff" then
        player.create_local_flying_text {
            text = entity.cliff_orientation,
            position = entity.position
        }
    end
end

-----------------------------
-- Blueprint tagging
-----------------------------

--- Finds a cliff entity at the given position probe.
--- @param surface LuaSurface
--- @param position MapPosition
--- @return LuaEntity|nil cliff
local function find_cliff_at(surface, position)
    local cliffs = surface.find_entities_filtered {
        type = "cliff",
        position = position,
        radius = 1
    }
    for _, cliff in ipairs(cliffs) do
        if cliff and cliff.valid and cliff.type == "cliff" then
            return cliff
        end
    end
    return nil
end

--- Rewrites exported marker entities so invisible markers become visible markers
--- and carry cliff-orientation tags for blueprint/copy-paste export.
--- @param exported_entities BlueprintEntity[]
--- @param mapping table<any, LuaEntity> entity_number -> world entity
--- @return boolean changed
local function rewrite_exported_cliff_entities(exported_entities, mapping)
    if not (exported_entities and mapping) then return false end

    local exported_by_number = {}
    for i, exported_entity in ipairs(exported_entities) do
        if exported_entity.entity_number then
            exported_by_number[exported_entity.entity_number] = i
        end
    end

    local changed = false

    for entity_number, world_entity in pairs(mapping) do
        if world_entity and world_entity.valid and starts_with(world_entity.name, INVISIBLE_PREFIX) then
            local index = exported_by_number[entity_number]
            if index then
                local exported_entity = exported_entities[index]
                local cliff = find_cliff_at(world_entity.surface, world_entity.position)

                local visible_name = visible_marker_name_from_invisible(world_entity.name)
                if visible_name and exported_entity.name ~= visible_name then
                    exported_entity.name = visible_name
                    changed = true
                end

                exported_entity.tags = exported_entity.tags or {}

                if cliff then
                    exported_entity.tags.cf_cliff_orientation = cliff.cliff_orientation
                    exported_entity.tags.cf_missing_cliff = nil
                else
                    exported_entity.tags.cf_missing_cliff = true
                    exported_entity.tags.cf_cliff_orientation = nil
                end

                changed = true
            end
        end
    end

    return changed
end

--- Handles both normal blueprint setup and copy/paste-style temporary blueprint setup.
--- @param event EventData.on_player_setup_blueprint
local function on_player_setup_blueprint(event)
    if not event.mapping then return end

    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end

    local stack = player.blueprint_to_setup
    if not (stack and stack.valid_for_read and stack.is_blueprint) then
        stack = player.cursor_stack
        if not (stack and stack.valid_for_read and stack.is_blueprint) then
            return
        end
    end

    local exported_entities = stack.get_blueprint_entities()
    if not exported_entities then return end

    local mapping = event.mapping:get()
    if not mapping or type(mapping) ~= "table" then return end

    if rewrite_exported_cliff_entities(exported_entities, mapping) then
        stack.set_blueprint_entities(exported_entities)
    end
end

-----------------------------
-- Event hooks
-----------------------------

script.on_event(defines.events.on_built_entity, on_any_built)
script.on_event(defines.events.on_robot_built_entity, on_any_built)
script.on_event(defines.events.script_raised_built, on_any_built)
script.on_event(defines.events.script_raised_revive, on_any_built)

script.on_event(defines.events.on_player_setup_blueprint, on_player_setup_blueprint)

script.on_event(defines.events.on_player_mined_entity, on_cliff_removed, { { filter = "type", type = "cliff" } })
script.on_event(defines.events.on_robot_mined_entity, on_cliff_removed, { { filter = "type", type = "cliff" } })
script.on_event(defines.events.on_entity_died, on_cliff_removed, { { filter = "type", type = "cliff" } })

script.on_event("cliff-flip", flip_cliff_event)
script.on_event("cliff-flip-selected", flip_cliff_selected_event)
script.on_event("display-cliff-orientation", display_selected_cliff_orientation)
