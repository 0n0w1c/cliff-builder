require("constants")

local CARDINAL_DIRECTIONS = { "north", "east", "south", "west" }
local VISIBLE_PREFIX = "visible-4x4-"
local INVISIBLE_PREFIX = "invisible-4x4-"
local MAXIMUM_CLIFF_CHAIN = 1000

local isolated_cliffs = {}

-----------------------------
-- Small helpers
-----------------------------

--- Returns whether `str` begins with `prefix`.
--- @param str string|nil String to test.
--- @param prefix string Prefix to check for.
--- @return boolean
local function starts_with(str, prefix)
    return type(str) == "string" and string.sub(str, 1, string.len(prefix)) == prefix
end

--- Removes `prefix` from `str` when present.
--- @param str string|nil String to trim.
--- @param prefix string Prefix to remove.
--- @return string|nil suffix Remaining string after the prefix.
local function remove_prefix(str, prefix)
    if type(str) ~= "string"
        or not starts_with(str, prefix)
    then
        return nil
    end

    return string.sub(str, string.len(prefix) + 1)
end

--- Returns whether the startup setting requests map_gen/vanilla cliff prototypes.
--- @return boolean
local function use_map_gen_cliffs()
    local setting = settings.startup[USE_MAP_GEN_CLIFFS_SETTING]
    return setting and setting.value == true
end

--- Returns whether a runtime prototype exists and is a cliff.
--- @param cliff_name string|nil
--- @return boolean
local function cliff_prototype_exists(cliff_name)
    if type(cliff_name) ~= "string" then return false end
    return prototypes
        and prototypes.entity
        and prototypes.entity[cliff_name]
        and prototypes.entity[cliff_name].type == "cliff"
end

--- Returns whether an item prototype exists.
--- @param item_name string|nil
--- @return boolean
local function item_prototype_exists(item_name)
    if type(item_name) ~= "string" then return false end
    return prototypes and prototypes.item and prototypes.item[item_name] ~= nil
end

--- Returns the canonical cliff prototype/item name used by gameplay logic.
--- Surface-tinted mountain variants are normalized to their base cliff name.
--- @param cliff_name string|nil Prototype name to normalize.
--- @return string|nil canonical_name Canonical cliff name, or nil for non-string input.
local function canonical_cliff_name(cliff_name)
    if type(cliff_name) ~= "string" then
        return nil
    end

    local base_names = {
        CLIFF_PREFIX .. "crater-cliff",
        "crater-cliff"
    }

    for _, base_name in ipairs(base_names) do
        if remove_prefix(cliff_name, base_name .. "-") then
            return base_name
        end
    end

    return cliff_name
end

--- Returns whether a cliff prototype name belongs to this mod's supported set.
--- By default, cliff-builder cliffs are named with the `cb-` prefix.
--- With "Use map_gen cliffs" enabled, any cliff that has a matching cliff-builder item is supported.
--- @param cliff_name string|nil
--- @return boolean
local function is_supported_cliff_name(cliff_name)
    if type(cliff_name) ~= "string" then return false end

    local canonical_name = canonical_cliff_name(cliff_name) or cliff_name
    if use_map_gen_cliffs() then
        return cliff_prototype_exists(cliff_name) and item_prototype_exists(canonical_name)
    end
    return starts_with(canonical_name, CLIFF_PREFIX) and cliff_prototype_exists(cliff_name)
end

--- Returns whether an entity is a cliff managed by this mod.
--- @param entity LuaEntity|nil
--- @return boolean
local function is_supported_cliff_entity(entity)
    if not (entity and entity.valid) then return false end
    return entity.type == "cliff" and is_supported_cliff_name(entity.name)
end

local MIGRATION_TO_MAP_GEN = "to-map-gen"
local MIGRATION_TO_CB = "to-cb"

--- Returns the migration direction that matches the current startup setting.
--- @return string direction
local function active_migration_direction()
    return use_map_gen_cliffs() and MIGRATION_TO_MAP_GEN or MIGRATION_TO_CB
end

--- Converts a cliff prototype name from one startup-setting family to the other.
--- @param cliff_name string|nil
--- @param direction string One of MIGRATION_TO_MAP_GEN or MIGRATION_TO_CB.
--- @return string|nil converted_cliff_name
local function convert_cliff_name_for_direction(cliff_name, direction)
    if not cliff_name then return nil end

    if direction == MIGRATION_TO_MAP_GEN then
        if not starts_with(cliff_name, CLIFF_PREFIX) then return nil end

        local map_gen_name = remove_prefix(cliff_name, CLIFF_PREFIX)
        if map_gen_name and cliff_prototype_exists(map_gen_name) and item_prototype_exists(map_gen_name) then
            return map_gen_name
        end

        return nil
    end

    if direction == MIGRATION_TO_CB then
        local cb_name = CLIFF_PREFIX .. cliff_name
        if cliff_prototype_exists(cliff_name) and cliff_prototype_exists(cb_name) and item_prototype_exists(cb_name) then
            return cb_name
        end
    end

    return nil
end

--- Converts a visible or invisible marker prototype/item name between startup-setting families.
--- @param marker_name string|nil
--- @param marker_prefix string
--- @param direction string One of MIGRATION_TO_MAP_GEN or MIGRATION_TO_CB.
--- @return string|nil converted_marker_name
local function convert_marker_name_for_direction(marker_name, marker_prefix, direction)
    local cliff_name = remove_prefix(marker_name, marker_prefix)
    if not cliff_name then return nil end

    local converted_cliff_name = convert_cliff_name_for_direction(cliff_name, direction)
    if converted_cliff_name then
        return marker_prefix .. converted_cliff_name
    end

    return nil
end

--- Converts an item prototype name between startup-setting families.
--- Handles cliff items plus hidden visible/invisible marker items kept for compatibility.
--- @param item_name string|nil
--- @param direction string One of MIGRATION_TO_MAP_GEN or MIGRATION_TO_CB.
--- @return string|nil converted_item_name
local function convert_item_name_for_direction(item_name, direction)
    return convert_cliff_name_for_direction(item_name, direction)
        or convert_marker_name_for_direction(item_name, VISIBLE_PREFIX, direction)
        or convert_marker_name_for_direction(item_name, INVISIBLE_PREFIX, direction)
end

--- Converts a visible marker prototype name into the active cliff prototype name.
--- Example: `"visible-4x4-cb-cliff"` -> `"cliff"` while map-gen mode is enabled.
--- @param marker_name string
--- @return string|nil cliff_entity_name
local function cliff_name_from_visible_marker(marker_name)
    local cliff_name = remove_prefix(marker_name, VISIBLE_PREFIX)
    if not cliff_name then return nil end

    return convert_cliff_name_for_direction(cliff_name, active_migration_direction()) or cliff_name
end

--- Converts a cliff prototype name into its active invisible marker prototype name.
--- Example: `"cb-cliff"` -> `"invisible-4x4-cb-cliff"`.
--- @param cliff_entity_name string
--- @return string marker_entity_name
local function invisible_marker_name_for_cliff(cliff_entity_name)
    return INVISIBLE_PREFIX .. (canonical_cliff_name(cliff_entity_name) or cliff_entity_name)
end

--- Converts either a visible or invisible marker prototype name into the active cliff prototype name.
--- @param marker_name string
--- @return string|nil cliff_entity_name
local function cliff_name_from_marker(marker_name)
    local cliff_name = remove_prefix(marker_name, VISIBLE_PREFIX)
        or remove_prefix(marker_name, INVISIBLE_PREFIX)
    if not cliff_name then return nil end

    return convert_cliff_name_for_direction(cliff_name, active_migration_direction()) or cliff_name
end

--- Converts an invisible marker prototype name into the corresponding visible marker prototype name.
--- Example: `"invisible-4x4-cb-cliff"` -> `"visible-4x4-cb-cliff"`.
--- @param marker_name string
--- @return string|nil visible_marker_name
local function visible_marker_name_from_invisible(marker_name)
    local suffix = remove_prefix(marker_name, INVISIBLE_PREFIX)
    if not suffix then return nil end

    return VISIBLE_PREFIX .. suffix
end

--- Returns whether an entity is a visible marker managed by this mod.
--- @param entity LuaEntity|nil
--- @return boolean
local function is_supported_visible_marker_entity(entity)
    if not (entity and entity.valid) then return false end
    local cliff_name = cliff_name_from_visible_marker(entity.name)
    return is_supported_cliff_name(cliff_name)
end

--- Returns whether an entity is an invisible marker managed by this mod.
--- @param entity LuaEntity|nil
--- @return boolean
local function is_supported_invisible_marker_entity(entity)
    if not (entity and entity.valid) then return false end
    local visible_marker_name = visible_marker_name_from_invisible(entity.name)
    local cliff_name = visible_marker_name and cliff_name_from_visible_marker(visible_marker_name) or nil
    return is_supported_cliff_name(cliff_name)
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

--- Returns the source/map-gen cliff name for either a map-gen cliff or its cb-* copy.
--- @param cliff_name string|nil
--- @return string|nil base_name
local function base_cliff_name(cliff_name)
    cliff_name = canonical_cliff_name(cliff_name)
    if type(cliff_name) ~= "string" then return nil end
    return remove_prefix(cliff_name, CLIFF_PREFIX) or cliff_name
end

local MOUNTAIN_RANGE_CLIFFS = {
    ["crater-cliff"] = true
}

local PLANET_TILE_SETS = {
    nauvis = {
        ["grass-1"] = true,
        ["grass-2"] = true,
        ["grass-3"] = true,
        ["grass-4"] = true,
        ["dry-dirt"] = true,
        ["dirt-1"] = true,
        ["dirt-2"] = true,
        ["dirt-3"] = true,
        ["dirt-4"] = true,
        ["dirt-5"] = true,
        ["dirt-6"] = true,
        ["dirt-7"] = true,
        ["sand-1"] = true,
        ["sand-2"] = true,
        ["sand-3"] = true,
        ["red-desert-0"] = true,
        ["red-desert-1"] = true,
        ["red-desert-2"] = true,
        ["red-desert-3"] = true,
        ["water"] = true,
        ["deepwater"] = true
    },
    fulgora = {
        ["oil-ocean-shallow"] = true,
        ["oil-ocean-deep"] = true,
        ["fulgoran-rock"] = true,
        ["fulgoran-dust"] = true,
        ["fulgoran-sand"] = true,
        ["fulgoran-dunes"] = true,
        ["fulgoran-walls"] = true,
        ["fulgoran-paving"] = true,
        ["fulgoran-conduit"] = true,
        ["fulgoran-machinery"] = true
    },
    gleba = {
        ["natural-yumako-soil"] = true,
        ["natural-jellynut-soil"] = true,
        ["wetland-yumako"] = true,
        ["wetland-jellynut"] = true,
        ["wetland-blue-slime"] = true,
        ["wetland-light-green-slime"] = true,
        ["wetland-green-slime"] = true,
        ["wetland-light-dead-skin"] = true,
        ["wetland-dead-skin"] = true,
        ["wetland-pink-tentacle"] = true,
        ["wetland-red-tentacle"] = true,
        ["gleba-deep-lake"] = true,
        ["lowland-brown-blubber"] = true,
        ["lowland-olive-blubber"] = true,
        ["lowland-olive-blubber-2"] = true,
        ["lowland-olive-blubber-3"] = true,
        ["lowland-pale-green"] = true,
        ["lowland-cream-cauliflower"] = true,
        ["lowland-cream-cauliflower-2"] = true,
        ["lowland-dead-skin"] = true,
        ["lowland-dead-skin-2"] = true,
        ["lowland-cream-red"] = true,
        ["lowland-red-vein"] = true,
        ["lowland-red-vein-2"] = true,
        ["lowland-red-vein-3"] = true,
        ["lowland-red-vein-4"] = true,
        ["lowland-red-vein-dead"] = true,
        ["lowland-red-infection"] = true,
        ["midland-turquoise-bark"] = true,
        ["midland-turquoise-bark-2"] = true,
        ["midland-cracked-lichen"] = true,
        ["midland-cracked-lichen-dull"] = true,
        ["midland-cracked-lichen-dark"] = true,
        ["midland-yellow-crust"] = true,
        ["midland-yellow-crust-2"] = true,
        ["midland-yellow-crust-3"] = true,
        ["midland-yellow-crust-4"] = true,
        ["highland-dark-rock"] = true,
        ["highland-dark-rock-2"] = true,
        ["highland-yellow-rock"] = true,
        ["pit-rock"] = true
    },
    aquilo = {
        ["snow-flat"] = true,
        ["snow-crests"] = true,
        ["snow-lumpy"] = true,
        ["snow-patchy"] = true,
        ["ice-rough"] = true,
        ["ice-smooth"] = true,
        ["brash-ice"] = true,
        ["ammoniacal-ocean"] = true,
        ["ammoniacal-ocean-2"] = true
    },
    vulcanus = {
        ["volcanic-soil-dark"] = true,
        ["volcanic-soil-light"] = true,
        ["volcanic-ash-soil"] = true,
        ["volcanic-ash-flats"] = true,
        ["volcanic-ash-light"] = true,
        ["volcanic-ash-dark"] = true,
        ["volcanic-cracks"] = true,
        ["volcanic-cracks-warm"] = true,
        ["volcanic-folds"] = true,
        ["volcanic-folds-flat"] = true,
        ["lava"] = true,
        ["lava-hot"] = true,
        ["volcanic-folds-warm"] = true,
        ["volcanic-pumice-stones"] = true,
        ["volcanic-cracks-hot"] = true,
        ["volcanic-jagged-ground"] = true,
        ["volcanic-smooth-stone"] = true,
        ["volcanic-smooth-stone-warm"] = true,
        ["volcanic-ash-cracks"] = true
    }
}

local NON_NAUVIS_TILE_PRIORITY = { "gleba", "aquilo", "vulcanus", "fulgora" }

local DEFAULT_UNTINTED_MOUNTAIN_PLANET = "vulcanus"

--- Returns the planet tile set found under the 4x4 mountain placement footprint.
--- @param surface LuaSurface|nil
--- @param position MapPosition|nil
--- @return string|nil planet_name
local function planet_name_from_mountain_footprint_tiles(surface, position)
    if not (surface and surface.valid and position) then return nil end

    local counts = {}
    local nauvis_count = 0
    local total_tiles = 0
    local tiles = surface.find_tiles_filtered {
        area = {
            { position.x - 2, position.y - 2 },
            { position.x + 2, position.y + 2 }
        }
    } or {}

    for _, tile in ipairs(tiles) do
        local tile_name = tile and tile.name
        if tile_name then
            total_tiles = total_tiles + 1
            if PLANET_TILE_SETS.nauvis[tile_name] then
                nauvis_count = nauvis_count + 1
            else
                for planet_name, tile_set in pairs(PLANET_TILE_SETS) do
                    if planet_name ~= "nauvis" and tile_set[tile_name] then
                        counts[planet_name] = (counts[planet_name] or 0) + 1
                    end
                end
            end
        end
    end

    local best_planet = nil
    local best_count = 0
    for _, planet_name in ipairs(NON_NAUVIS_TILE_PRIORITY) do
        local count = counts[planet_name] or 0
        if count > best_count then
            best_planet = planet_name
            best_count = count
        end
    end

    if best_planet then return best_planet end
    if total_tiles > 0 and nauvis_count == total_tiles then return "nauvis" end

    return nil
end

--- Returns a tile-specific visual mountain cliff prototype when one exists.
--- @param cliff_name string
--- @param surface LuaSurface|nil
--- @param position MapPosition|nil
--- @return string cliff_name
local function visual_cliff_name_for_tiles(cliff_name, surface, position)
    local canonical_name = canonical_cliff_name(cliff_name) or cliff_name
    if MOUNTAIN_RANGE_CLIFFS[base_cliff_name(canonical_name)] ~= true then return cliff_name end

    local planet_name = planet_name_from_mountain_footprint_tiles(surface, position)
        or DEFAULT_UNTINTED_MOUNTAIN_PLANET

    local variant_name = canonical_name .. "-" .. planet_name
    if cliff_prototype_exists(variant_name) then return variant_name end

    return cliff_name
end

--- The eight visually distinct crater/mountain section sprites. Other crater
--- orientations are duplicate aliases, so manual rotation cycles only these.
local MOUNTAIN_RANGE_SECTION_ORIENTATIONS = {
    "west-to-east",
    "west-to-south",
    "north-to-south",
    "north-to-west",
    "east-to-west",
    "east-to-north",
    "south-to-north",
    "south-to-east"
}

local MOUNTAIN_RANGE_SECTION_ORIENTATION_INDEX = {}
for i, orientation in pairs(MOUNTAIN_RANGE_SECTION_ORIENTATIONS) do
    MOUNTAIN_RANGE_SECTION_ORIENTATION_INDEX[orientation] = i
end

--- Some cliff prototypes are useful as buildable mountain-range sections rather than
--- normal chain cliffs. Their *_to_none orientations may reuse generic section art,
--- so treat them as continuous pieces instead of relying on visible end-cap graphics.
--- @param cliff LuaEntity|nil
--- @return boolean
local function uses_mountain_range_orientations(cliff)
    if not (cliff and cliff.valid) then return false end
    return MOUNTAIN_RANGE_CLIFFS[base_cliff_name(cliff.name)] == true
end

--- Returns the entity orientation that must be preserved when recreating a cliff.
--- Mountain-range sections use entity orientation for visual variants; normal cliffs do not.
--- @param cliff LuaEntity|nil Cliff entity being replaced or migrated.
--- @return RealOrientation|nil entity_orientation Orientation to pass to create_entity, if needed.
local function preserved_entity_orientation_for_cliff(cliff)
    if not (cliff and cliff.valid) then return nil end

    if uses_mountain_range_orientations(cliff) then
        return cliff.orientation
    end
    return nil
end

--- Returns the end-cap orientation that points toward one connected neighbor.
--- @param direction string Cardinal direction of the neighbor.
--- @return string orientation Cliff orientation string.
local function one_neighbor_orientation(direction)
    return "none-to-" .. direction
end

--- Maps placement direction to the mountain section sprite that follows that axis.
local MOUNTAIN_RANGE_VECTOR_ORIENTATIONS = {
    north = "south-to-north",
    northeast = "south-to-east",
    east = "west-to-east",
    southeast = "west-to-south",
    south = "north-to-south",
    southwest = "north-to-west",
    west = "east-to-west",
    northwest = "east-to-north"
}

--- Returns the nearest cardinal direction for a position delta.
--- Mountain-range placement uses cardinal axis alignment for automatic chain
--- orientation; manual rotation still exposes diagonal sections.
--- @param dx double
--- @param dy double
--- @return string|nil direction
local function cardinal_direction_from_delta(dx, dy)
    if dx == 0 and dy == 0 then return nil end

    local abs_dx = math.abs(dx)
    local abs_dy = math.abs(dy)

    if abs_dx > abs_dy then
        if dx > 0 then return "east" end
        if dx < 0 then return "west" end
    else
        if dy > 0 then return "south" end
        if dy < 0 then return "north" end
    end

    return nil
end

--- Returns the orientation used for a mountain range segment following a vector.
--- @param from LuaEntity
--- @param to LuaEntity
--- @return string|nil orientation
local function mountain_range_orientation_from_vector(from, to)
    if not (from and from.valid and to and to.valid) then return nil end

    local direction = cardinal_direction_from_delta(
        to.position.x - from.position.x,
        to.position.y - from.position.y
    )

    if not direction then return nil end
    return MOUNTAIN_RANGE_VECTOR_ORIENTATIONS[direction]
end

--- Returns nearby mountain-range cliffs. This intentionally includes diagonal and
--- slightly-wide spacing because crater section art is larger than normal cliffs.
--- @param cliff LuaEntity
--- @return LuaEntity[] neighbors
local function get_mountain_range_neighbors(cliff)
    if not (cliff and cliff.valid) then return {} end

    local found = cliff.surface.find_entities_filtered {
        type = "cliff",
        position = cliff.position,
        radius = 6.5
    } or {}

    local neighbors = {}
    for _, entity in ipairs(found) do
        if entity ~= cliff and uses_mountain_range_orientations(entity) then
            table.insert(neighbors, entity)
        end
    end

    table.sort(neighbors, function(a, b)
        local adx = a.position.x - cliff.position.x
        local ady = a.position.y - cliff.position.y
        local bdx = b.position.x - cliff.position.x
        local bdy = b.position.y - cliff.position.y
        return adx * adx + ady * ady < bdx * bdx + bdy * bdy
    end)

    return neighbors
end


-----------------------------
-- Orientation utils used during placement
-----------------------------

local function rotate_cliff(cliff, target)
    if not target then
        cliff.rotate()
        return
    end

    local attempts = 0

    while cliff.cliff_orientation ~= target and attempts < 20 do
        cliff.rotate()
        attempts = attempts + 1
    end
end

-----------------------------
-- Isolated cliff tracking
-----------------------------

local function remove_isolated_cliff(cliff)
    if not cliff then return false end

    local found, index =
        helper_find_in_table(isolated_cliffs, cliff, true)

    if not found then return false end

    table.remove(isolated_cliffs, index)

    return true
end

--- Orients a newly built mountain section from the nearest existing section.
--- @param cliff LuaEntity
local function handle_mountain_range_cliff_built(cliff)
    local neighbors = get_mountain_range_neighbors(cliff)

    if #neighbors == 0 then
        table.insert(isolated_cliffs, cliff)
        return
    end

    remove_isolated_cliff(cliff)

    local previous = neighbors[1]

    local cliff_orientation = mountain_range_orientation_from_vector(cliff, previous)
    if cliff_orientation then
        rotate_cliff(cliff, cliff_orientation)
    end

    local previous_orientation = mountain_range_orientation_from_vector(previous, cliff)
    if previous_orientation then
        rotate_cliff(previous, previous_orientation)
        remove_isolated_cliff(previous)
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
    return a ~= b and not is_opposite(a, b)
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
    return tokens[1], tokens[3]
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

    local found = surface.find_entities_filtered {
        type = "cliff",
        position = position,
        radius = 1
    } or {}

    local neighbors = {}
    for _, entity in ipairs(found) do
        if is_supported_cliff_entity(entity) then
            table.insert(neighbors, entity)
        end
    end

    return neighbors
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

    for _, dir in ipairs(CARDINAL_DIRECTIONS) do
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

    for _, direction in ipairs(CARDINAL_DIRECTIONS) do
        local neighbor = get_neighbor(cliff, direction)
        if neighbor and neighbor.valid then
            if not uses_mountain_range_orientations(neighbor)
                and string.find(neighbor.cliff_orientation, "none") then
                table.insert(out, neighbor)
            end
        end
    end
    return out
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
    local max_cliffs = MAXIMUM_CLIFF_CHAIN

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
-- Isolated cliff tracking
-----------------------------

--- Spawns the invisible marker companion entity for a cliff, if missing.
--- @param cliff LuaEntity
local function spawn_invisible_marker_for_cliff(cliff)
    if not (cliff and cliff.valid) then return end
    local surface = cliff.surface
    if not (surface and surface.valid) then return end

    local marker_name = invisible_marker_name_for_cliff(cliff.name)

    local existing = surface.find_entities_filtered {
        name = marker_name,
        position = cliff.position,
        radius = 1
    }
    if existing and existing[1] then return end

    surface.create_entity {
        name = marker_name,
        position = cliff.position,
        force = cliff.force,
        raise_built = false
    }
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

    for _, direction in ipairs(CARDINAL_DIRECTIONS) do
        local neighbor = get_neighbor(cliff, direction)
        if neighbor and neighbor.valid and neighbor ~= cliff then
            if cliffs_are_connected(cliff, neighbor) then
                table.insert(out, neighbor)
            end
        end
    end

    return out
end

--- Returns a stable key for a cliff during one traversal.
--- @param cliff LuaEntity
--- @return string|nil key
local function cliff_traversal_key(cliff)
    if not (cliff and cliff.valid) then return nil end

    local surface = cliff.surface
    local position = cliff.position
    if not (surface and surface.valid and position) then return nil end

    return surface.index .. ":" .. cliff.name .. ":" .. position.x .. ":" .. position.y
end

--- Iteratively flips the orientation of the connected cliff chain by spatial adjacency.
--- `flip_record` is keyed by stable surface/name/position strings.
--- @param flip_record table<string, boolean> Visited cliffs.
--- @param cliff LuaEntity
local function flip_chain(flip_record, cliff)
    if not (cliff and cliff.valid) then return end

    local stack = { cliff }

    while #stack > 0 do
        local current = table.remove(stack)
        if current and current.valid then
            local key = cliff_traversal_key(current)
            if key and not flip_record[key] then
                flip_record[key] = true

                local neighbors = get_cardinal_chain_neighbors(current)

                local new = flip_orientation(current.cliff_orientation)
                rotate_cliff(current, new)

                for _, next_cliff in ipairs(neighbors) do
                    local next_key = cliff_traversal_key(next_cliff)
                    if next_key and not flip_record[next_key] then
                        table.insert(stack, next_cliff)
                    end
                end
            end
        end
    end
end

-----------------------------
-- Loop joint orientation (curve/straight)
-----------------------------

local corner_from_neighbors = {
    [make_unordered_pair_key("east", "south")] = "NW",
    [make_unordered_pair_key("south", "west")] = "NE",
    [make_unordered_pair_key("north", "west")] = "SE",
    [make_unordered_pair_key("east", "north")] = "SW",
}

local curve_variants = {
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
    local corner = corner_from_neighbors[make_unordered_pair_key(direction_1, direction_2)]
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

    local variants = curve_variants[corner]
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

    local source_key = cliff_traversal_key(cliff)
    local flip_record = {}
    if source_key then
        flip_record[source_key] = true
    end

    if cliff_split[1] ~= cardinal_reverse(up_split[3]) then
        flip_chain(flip_record, up)
    end

    if cliff_split[3] ~= cardinal_reverse(down_split[1]) then
        flip_chain(flip_record, down)
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

--- Returns the craftable item name to refund for a cliff entity.
--- @param cliff LuaEntity|nil Cliff entity being refunded.
--- @return string|nil item_name Item prototype name to insert into an inventory.
local function item_name_for_cliff_entity(cliff)
    if not (cliff and cliff.valid) then return nil end
    return canonical_cliff_name(cliff.name) or cliff.name
end

--- Destroys cliff entities overlapping `cliff`, except for `cliff` itself.
--- Used after a blueprint marker has produced the intended cliff so existing
--- map cliffs are corrected without pre-clearing neighboring blueprint cliffs.
--- @param cliff LuaEntity
local function destroy_overlapping_cliffs_for_cliff(cliff)
    if not (cliff and cliff.valid) then return end

    local surface = cliff.surface
    if not (surface and surface.valid) then return end

    local cliffs = surface.find_entities_filtered {
        type = "cliff",
        position = cliff.position,
        radius = 1
    }

    for _, other in ipairs(cliffs) do
        if other and other.valid and other ~= cliff then
            remove_invisible_marker_for_cliff(other)
            other.destroy { do_cliff_correction = true }
        end
    end
end

--- Destroys cliff entities at the intended marker placement position.
--- Used only after `can_place_entity` reports that the intended cliff is blocked,
--- so ordinary neighboring blueprint-restored cliffs are not pre-cleared.
--- @param surface LuaSurface
--- @param position MapPosition
--- @return boolean removed_any
local function destroy_cliffs_blocking_marker_position(surface, position)
    if not (surface and surface.valid and position) then return false end

    local removed_any = false
    local cliffs = surface.find_entities_filtered {
        type = "cliff",
        position = position,
        radius = 1
    }

    for _, cliff in ipairs(cliffs) do
        if cliff and cliff.valid then
            remove_invisible_marker_for_cliff(cliff)
            cliff.destroy { do_cliff_correction = true }
            removed_any = true
        end
    end

    return removed_any
end

--- Attempts to spawn a real cliff from a temporary marker entity name.
--- Any provided blueprint orientation tag is applied to the spawned cliff.
--- @param surface LuaSurface
--- @param position MapPosition
--- @param force LuaForce|string|int
--- @param marker_entity_name string Visible or invisible marker entity prototype name.
--- @param tags Tags|nil Blueprint/entity tags.
--- @return LuaEntity|nil cliff
local function try_spawn_cliff_from_marker(surface, position, force, marker_entity_name, tags)
    if not (surface and surface.valid and position and marker_entity_name) then return nil end

    local cliff_name = cliff_name_from_marker(marker_entity_name)
    if not cliff_name then return nil end
    cliff_name = visual_cliff_name_for_tiles(cliff_name, surface, position)

    local entity_orientation = tags and tonumber(tags.cb_entity_orientation) or nil

    local place_parameters = {
        name = cliff_name,
        position = position,
        force = force,
        orientation = entity_orientation
    }

    if surface.can_place_entity and not surface.can_place_entity(place_parameters) then
        if not destroy_cliffs_blocking_marker_position(surface, position) then
            return nil
        end

        if not surface.can_place_entity(place_parameters) then
            return nil
        end
    end

    local cliff = surface.create_entity {
        name = cliff_name,
        position = position,
        force = force,
        orientation = entity_orientation,
        raise_built = false
    }
    if not (cliff and cliff.valid) then return nil end

    destroy_overlapping_cliffs_for_cliff(cliff)

    if tags and tags.cb_cliff_orientation then
        rotate_cliff(cliff, tostring(tags.cb_cliff_orientation))
    end

    return cliff
end

-----------------------------
-- Cliff placement/orientation logic
-----------------------------

--- Handles an isolated newly built live cliff.
--- @param cliff LuaEntity
local function handle_isolated_cliff_built(cliff)
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

    rotate_cliff(cliff, one_neighbor_orientation(set_direction))
end

--- Handles a cliff extending from one open end.
--- @param cliff LuaEntity
--- @param adjacent_cliff LuaEntity
local function handle_cliff_extension_built(cliff, adjacent_cliff)
    local cardinal_dir = cardinal(cliff, adjacent_cliff)
    if not cardinal_dir then return end

    local inv_cardinal = cardinal_reverse(cardinal_dir)
    if not inv_cardinal then return end

    local adj_orientation = adjacent_cliff.cliff_orientation
    local adj_orientation_new = swap_orientation(remove_isolated_cliff(adjacent_cliff), adj_orientation, inv_cardinal)

    rotate_cliff(adjacent_cliff, adj_orientation_new)
    rotate_cliff(cliff, one_neighbor_orientation(cardinal_dir))
end

--- Handles a cliff joining two open ends.
--- @param cliff LuaEntity
--- @param adjacent_ends LuaEntity[]
local function handle_cliff_join_built(cliff, adjacent_ends)
    local direction_1
    local direction_2

    for index, adjacent_cliff in ipairs(adjacent_ends) do
        local cardinal_dir = cardinal(cliff, adjacent_cliff)
        if not cardinal_dir then return end

        local inv_cardinal = cardinal_reverse(cardinal_dir)
        if not inv_cardinal then return end

        local adj_orientation = adjacent_cliff.cliff_orientation
        local adj_orientation_new = swap_orientation(remove_isolated_cliff(adjacent_cliff), adj_orientation, inv_cardinal)

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
end

--- Replaces a freshly built mountain-range cliff with the visual variant selected
--- from the 4x4 tile footprint under the mountain, when one exists.
--- @param cliff LuaEntity
--- @return LuaEntity cliff
local function replace_with_surface_visual_variant_if_needed(cliff)
    if not (cliff and cliff.valid) then return cliff end

    local desired_name = visual_cliff_name_for_tiles(cliff.name, cliff.surface, cliff.position)
    if desired_name == cliff.name then return cliff end

    local surface = cliff.surface
    local position = cliff.position
    local force = cliff.force
    local orientation = cliff.orientation
    local cliff_orientation = cliff.cliff_orientation

    cliff.destroy { do_cliff_correction = false }

    local replacement = surface.create_entity {
        name = desired_name,
        position = position,
        force = force,
        orientation = orientation,
        raise_built = false
    }

    if replacement and replacement.valid then
        rotate_cliff(replacement, cliff_orientation)
        return replacement
    end

    return cliff
end

--- Dispatcher for placement/orientation logic for a newly built live cliff.
--- @param cliff LuaEntity
local function handle_cliff_built(cliff)
    if not is_supported_cliff_entity(cliff) then return end
    cliff = replace_with_surface_visual_variant_if_needed(cliff)
    if not is_supported_cliff_entity(cliff) then return end

    destroy_overlapping_cliffs_for_cliff(cliff)
    spawn_invisible_marker_for_cliff(cliff)

    if uses_mountain_range_orientations(cliff) then
        return handle_mountain_range_cliff_built(cliff)
    end

    local adjacent_ends = get_cardinal_end_neighbors(cliff)

    if #adjacent_ends == 0 then
        return handle_isolated_cliff_built(cliff)
    end

    if #adjacent_ends == 1 then
        return handle_cliff_extension_built(cliff, adjacent_ends[1])
    end

    if #adjacent_ends == 2 then
        return handle_cliff_join_built(cliff, adjacent_ends)
    end
end

--- Destroys invisible marker companions occupying the exact marker probe area.
--- @param surface LuaSurface
--- @param position MapPosition
local function clear_invisible_markers_at_position(surface, position)
    local entities = surface.find_entities_filtered {
        position = position,
        radius = 1
    }

    for _, entity in ipairs(entities) do
        if entity.valid and is_supported_invisible_marker_entity(entity) then
            entity.destroy()
        end
    end
end

-----------------------------
-- Startup-setting state migration
-----------------------------

--- Finds the cliff represented by an invisible marker in the source startup-setting family.
--- @param marker LuaEntity
--- @param direction string One of MIGRATION_TO_MAP_GEN or MIGRATION_TO_CB.
--- @return LuaEntity|nil cliff
local function find_source_cliff_for_invisible_marker(marker, direction)
    if not (marker and marker.valid) then return nil end

    local source_cliff_name = remove_prefix(marker.name, INVISIBLE_PREFIX)
    if not source_cliff_name then return nil end
    if not convert_cliff_name_for_direction(source_cliff_name, direction) then return nil end

    local cliffs = marker.surface.find_entities_filtered {
        name = source_cliff_name,
        position = marker.position,
        radius = 1
    }

    for _, cliff in ipairs(cliffs) do
        if cliff.valid and cliff.type == "cliff" and cliff.name == source_cliff_name then
            return cliff
        end
    end

    return nil
end

--- Replaces one cliff with its equivalent prototype in the target startup-setting family.
--- @param cliff LuaEntity
--- @param direction string One of MIGRATION_TO_MAP_GEN or MIGRATION_TO_CB.
--- @return LuaEntity|nil migrated_cliff
local function migrate_cliff_entity_for_direction(cliff, direction)
    if not (cliff and cliff.valid and cliff.type == "cliff") then return nil end

    local new_name = convert_cliff_name_for_direction(cliff.name, direction)
    if not new_name then return nil end

    local surface = cliff.surface
    local position = { x = cliff.position.x, y = cliff.position.y }
    local force = cliff.force
    local orientation = cliff.cliff_orientation
    local entity_orientation = preserved_entity_orientation_for_cliff(cliff)

    remove_invisible_marker_for_cliff(cliff)
    cliff.destroy { do_cliff_correction = false }

    local migrated = surface.create_entity {
        name = new_name,
        position = position,
        force = force,
        orientation = entity_orientation,
        raise_built = false
    }

    if not (migrated and migrated.valid) then return nil end

    rotate_cliff(migrated, orientation)
    return migrated
end

--- Replaces one invisible marker with its equivalent prototype in the target startup-setting family.
--- @param marker LuaEntity
--- @param direction string One of MIGRATION_TO_MAP_GEN or MIGRATION_TO_CB.
--- @return LuaEntity|nil migrated_marker
local function migrate_invisible_marker_for_direction(marker, direction)
    if not (marker and marker.valid) then return nil end

    local new_name = convert_marker_name_for_direction(marker.name, INVISIBLE_PREFIX, direction)
    if not new_name then return nil end

    local surface = marker.surface
    local position = { x = marker.position.x, y = marker.position.y }
    local force = marker.force

    local existing = surface.find_entities_filtered {
        name = new_name,
        position = position,
        radius = 1
    }

    --- @type LuaEntity?
    local migrated = nil
    if existing then
        migrated = existing[1]
    end

    if not (migrated and migrated.valid) then
        migrated = surface.create_entity {
            name = new_name,
            position = position,
            force = force,
            raise_built = false
        }
    end

    marker.destroy()

    if migrated and migrated.valid then
        return migrated
    end

    return nil
end

--- Migrates one invisible-marker/cliff pair to the target startup-setting family.
--- @param marker LuaEntity
--- @param direction string One of MIGRATION_TO_MAP_GEN or MIGRATION_TO_CB.
--- @return boolean migrated
local function migrate_marked_cliff_pair_for_direction(marker, direction)
    if not (marker and marker.valid) then return false end

    local cliff = find_source_cliff_for_invisible_marker(marker, direction)
    if not (cliff and cliff.valid) then
        return migrate_invisible_marker_for_direction(marker, direction) ~= nil
    end

    local migrated_cliff = migrate_cliff_entity_for_direction(cliff, direction)
    if not (migrated_cliff and migrated_cliff.valid) then return false end

    spawn_invisible_marker_for_cliff(migrated_cliff)

    if marker.valid then
        marker.destroy()
    end

    return true
end

--- Migrates placed cliff/marker pairs on all surfaces to match the current startup setting.
local function migrate_all_entities_for_current_setting()
    local direction = active_migration_direction()

    for _, surface in pairs(game.surfaces) do
        -- Invisible markers are the ownership marker for both directions. This keeps the
        -- migration symmetric and prevents natural map-generated cliffs from being converted.
        local markers = surface.find_entities_filtered { type = "simple-entity-with-owner" }
        for _, marker in ipairs(markers) do
            if marker.valid and convert_marker_name_for_direction(marker.name, INVISIBLE_PREFIX, direction) then
                migrate_marked_cliff_pair_for_direction(marker, direction)
            end
        end
    end
end

--- Safely reads an inventory from an owner that supports `get_inventory`.
--- @param owner LuaPlayer|LuaEntity
--- @param inventory_type defines.inventory
--- @return LuaInventory|nil
local function get_inventory_safe(owner, inventory_type)
    local ok, inventory = pcall(function()
        return owner.get_inventory(inventory_type)
    end)

    if ok and inventory and inventory.valid then
        return inventory
    end

    return nil
end

--- Replaces item stacks in one inventory using the supplied name mapper.
--- @param inventory LuaInventory|nil
--- @param map_item_name fun(item_name:string|nil):string|nil
--- @return uint migrated_count
local function migrate_inventory_items(inventory, map_item_name)
    if not (inventory and inventory.valid) then return 0 end

    local migrated_count = 0

    -- Snapshot first, because we mutate the inventory while migrating.
    local stacks_to_migrate = {}

    for i = 1, #inventory do
        local item_stack = inventory[i]
        if item_stack and item_stack.valid_for_read then
            local old_name = item_stack.name
            local new_name = map_item_name(old_name)

            if new_name and new_name ~= old_name then
                local quality = item_stack.quality
                stacks_to_migrate[#stacks_to_migrate + 1] = {
                    name = old_name,
                    new_name = new_name,
                    count = item_stack.count,
                    quality = quality and quality.name or nil
                }
            end
        end
    end

    for _, stack in pairs(stacks_to_migrate) do
        local removed = inventory.remove {
            name = stack.name,
            count = stack.count,
            quality = stack.quality
        }

        if removed > 0 then
            local inserted = inventory.insert {
                name = stack.new_name,
                count = removed,
                quality = stack.quality
            }

            migrated_count = migrated_count + inserted

            local remainder = removed - inserted
            if remainder > 0 then
                inventory.insert {
                    name = stack.name,
                    count = remainder,
                    quality = stack.quality
                }
            end
        end
    end

    return migrated_count
end

--- Migrates matching item stacks held by players.
--- @param map_item_name fun(item_name:string|nil):string|nil
local function migrate_player_items(map_item_name)
    for _, player in pairs(game.players) do
        local main = get_inventory_safe(player, defines.inventory.character_main)
        migrate_inventory_items(main, map_item_name)

        local trash = get_inventory_safe(player, defines.inventory.character_trash)
        migrate_inventory_items(trash, map_item_name)
    end
end

--- Migrates matching item stacks in regular and logistic chests.
--- @param map_item_name fun(item_name:string|nil):string|nil
local function migrate_chest_items(map_item_name)
    local chest_entity_types = { "container", "logistic-container" }

    for _, surface in pairs(game.surfaces) do
        for _, entity_type in ipairs(chest_entity_types) do
            local entities = surface.find_entities_filtered { type = entity_type }
            for _, entity in ipairs(entities) do
                if entity.valid then
                    local inventory = get_inventory_safe(entity, defines.inventory.chest)
                    migrate_inventory_items(inventory, map_item_name)
                end
            end
        end
    end
end

--- Migrates item stacks to match the current startup setting.
local function migrate_all_items_for_current_setting()
    local direction = active_migration_direction()

    local function convert_name(item_name)
        return convert_item_name_for_direction(item_name, direction)
    end

    migrate_player_items(convert_name)
    migrate_chest_items(convert_name)
end

--- Handles save migration after startup setting or prototype changes.
--- @param _event ConfigurationChangedData
local function on_configuration_changed(_event)
    migrate_all_entities_for_current_setting()
    migrate_all_items_for_current_setting()
end

-----------------------------
-- Event handlers
-----------------------------

--- Unified built-entity dispatcher for real cliffs and visible markers.
--- @param event EventData.on_built_entity
---| EventData.on_robot_built_entity
---| EventData.script_raised_built
---| EventData.script_raised_revive
local function on_any_built(event)
    local entity = event.entity
    if not (entity and entity.valid) then return end
    if is_supported_cliff_entity(entity) then
        handle_cliff_built(entity)
        return
    end

    if entity.type == "entity-ghost" then
        local cliff_name = cliff_name_from_visible_marker(entity.ghost_name)
        if is_supported_cliff_name(cliff_name) then
            return
        end
    end

    if is_supported_visible_marker_entity(entity) or is_supported_invisible_marker_entity(entity) then
        local surface = entity.surface
        local position = entity.position
        local force = entity.force
        local marker_name = entity.name
        local was_visible_marker = is_supported_visible_marker_entity(entity)

        local tags = event.tags
        if tags and tags.cb_missing_cliff then
            entity.destroy()
            return
        end

        entity.destroy()

        if was_visible_marker then
            clear_invisible_markers_at_position(surface, position)
        end

        local spawned = try_spawn_cliff_from_marker(surface, position, force, marker_name, tags)
        if spawned then
            spawn_invisible_marker_for_cliff(spawned)
        end
        return
    end
end

--- Handles cliff removal/mining/death cleanup.
--- Also refunds silently deleted newly-isolated neighbor endcaps through the mining event buffer, when present.
--- @param event EventData.on_player_mined_entity
---| EventData.on_robot_mined_entity
---| EventData.on_entity_died
local function on_cliff_removed(event)
    local cliff = event.entity
    if not is_supported_cliff_entity(cliff) then return end

    local player = event.player_index and game.get_player(event.player_index) or nil
    local refund_inventory = event.buffer
    local neighbors = get_cliff_neighbors(cliff)

    if neighbors then
        for _, neighbor in ipairs(neighbors) do
            if is_supported_cliff_entity(neighbor) and string.find(neighbor.cliff_orientation, "none") then
                remove_invisible_marker_for_cliff(neighbor)
                remove_isolated_cliff(neighbor)

                local refund_name = item_name_for_cliff_entity(neighbor)
                if refund_name and refund_inventory and refund_inventory.valid then
                    refund_inventory.insert { name = refund_name, count = 1 }
                elseif refund_name and player then
                    player.insert { name = refund_name, count = 1 }
                end
            end
        end
    end

    remove_invisible_marker_for_cliff(cliff)
    remove_isolated_cliff(cliff)
end

-----------------------------
-- Custom input handlers
-----------------------------

--- Rotates mountain-range cliff sections through their visually distinct variants.
--- Normal cliffs continue to use the original flip behavior.
--- @param cliff LuaEntity
--- @return boolean handled
local function rotate_mountain_range_section(cliff)
    if not uses_mountain_range_orientations(cliff) then return false end

    local current_index = MOUNTAIN_RANGE_SECTION_ORIENTATION_INDEX[cliff.cliff_orientation]
    local next_index = 1
    if current_index then
        next_index = current_index + 1
        if next_index > #MOUNTAIN_RANGE_SECTION_ORIENTATIONS then
            next_index = 1
        end
    end

    rotate_cliff(cliff, MOUNTAIN_RANGE_SECTION_ORIENTATIONS[next_index])
    return true
end

--- Flips the entire connected chain under the cursor or current selection.
--- Mountain-range cliffs rotate one section instead of flipping a chain.
--- @param event EventData.CustomInputEvent
local function flip_cliff_event(event)
    local player = game.get_player(event.player_index)
    if not player then return end

    local selected = player.selected
    if selected and is_supported_cliff_entity(selected) then
        if rotate_mountain_range_section(selected) then return end
        flip_chain({}, selected)
        return
    end

    local cursor_position = event.cursor_position
    if not cursor_position then return end

    local surface = player.surface
    local cliffs = surface.find_entities_filtered {
        type = "cliff",
        position = cursor_position,
        radius = 1
    }

    for _, cliff in ipairs(cliffs) do
        if is_supported_cliff_entity(cliff) then
            if not rotate_mountain_range_section(cliff) then
                flip_chain({}, cliff)
            end
            break
        end
    end
end

--- Flips only the currently selected cliff entity.
--- Mountain-range cliffs rotate through variants instead.
--- @param event EventData.CustomInputEvent
local function flip_cliff_selected_event(event)
    local player = game.get_player(event.player_index)
    if not player then return end

    local entity = player.selected
    if not entity then return end

    if is_supported_cliff_entity(entity) then
        local cliff = entity
        if rotate_mountain_range_section(cliff) then return end

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
    if not entity then return end

    if is_supported_cliff_entity(entity) then
        player.create_local_flying_text {
            text = entity.cliff_orientation,
            position = entity.position
        }
    end
end

-----------------------------
-- Blueprint rewriting
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
        if is_supported_cliff_entity(cliff) then
            return cliff
        end
    end
    return nil
end

--- Returns a field from an object without letting unsupported fields abort blueprint setup.
--- @param object any
--- @param field string
--- @return any value
local function safe_get_field(object, field)
    local ok, value = pcall(function() return object[field] end)
    if ok then return value end
    return nil
end

--- Builds a minimal BlueprintEntity snapshot from a source entity.
--- @param source_entity LuaEntity
--- @param blueprint_index uint
--- @return BlueprintEntity blueprint_entity
local function snapshot_blueprint_entity(source_entity, blueprint_index)
    local entity = {
        entity_number = blueprint_index,
        name = source_entity.name,
        position = {
            x = source_entity.position.x,
            y = source_entity.position.y
        }
    }

    local direction = safe_get_field(source_entity, "direction")
    if direction ~= nil then
        entity.direction = direction
    end

    local mirror = safe_get_field(source_entity, "mirror")
    if mirror ~= nil then
        entity.mirror = mirror
    else
        local mirroring = safe_get_field(source_entity, "mirroring")
        if mirroring ~= nil then
            entity.mirror = mirroring
        end
    end

    local quality = safe_get_field(source_entity, "quality")
    if quality ~= nil then
        if type(quality) == "string" then
            entity.quality = quality
        else
            local quality_name = safe_get_field(quality, "name")
            if type(quality_name) == "string" then
                entity.quality = quality_name
            end
        end
    end

    return entity
end

--- Returns the mapping table from an on_player_setup_blueprint event.
--- Factorio 2.1 exposes this as a LuaLazyLoadedValue.
--- @param event EventData.on_player_setup_blueprint
--- @return table<any, LuaEntity>|nil mapping
local function setup_blueprint_mapping(event)
    local mapping = event.mapping
    if not mapping then return nil end

    if type(mapping) == "table" then
        return mapping
    end

    local get_mapping = mapping["get"]
    if type(get_mapping) ~= "function" then return nil end

    local ok, loaded = pcall(get_mapping)
    if ok and type(loaded) == "table" then
        return loaded
    end

    return nil
end

--- Returns the writable blueprint-like object from an on_player_setup_blueprint event.
--- @param event EventData.on_player_setup_blueprint
--- @return LuaItemStack|LuaRecord|nil blueprint
local function writable_blueprint_from_setup_event(event)
    local target = event.stack or event.record
    if target then return target end
    return nil
end

--- Applies cliff blueprint export rewriting to a source-entity snapshot.
--- @param blueprint_entity BlueprintEntity
--- @param source_entity LuaEntity
--- @return boolean changed
local function rewrite_blueprint_snapshot_for_cliff(blueprint_entity, source_entity)
    if not (source_entity and source_entity.valid and starts_with(source_entity.name, INVISIBLE_PREFIX)) then
        return false
    end

    local changed = false
    local visible_name = visible_marker_name_from_invisible(source_entity.name)
    if visible_name and blueprint_entity.name ~= visible_name then
        blueprint_entity.name = visible_name
        changed = true
    end

    blueprint_entity.tags = blueprint_entity.tags or {}
    local cliff = find_cliff_at(source_entity.surface, source_entity.position)

    if cliff then
        if blueprint_entity.tags.cb_cliff_orientation ~= cliff.cliff_orientation then
            blueprint_entity.tags.cb_cliff_orientation = cliff.cliff_orientation
            changed = true
        end

        local entity_orientation = preserved_entity_orientation_for_cliff(cliff)
        if entity_orientation ~= nil then
            if blueprint_entity.tags.cb_entity_orientation ~= entity_orientation then
                blueprint_entity.tags.cb_entity_orientation = entity_orientation
                changed = true
            end
        end
    else
        blueprint_entity.tags.cb_missing_cliff = true
        changed = true
    end

    return changed
end

--- Rewrites blueprint entity names so legacy/current entities match the active startup mode.
--- @param blueprint_entity BlueprintEntity
--- @return boolean changed
local function normalize_blueprint_snapshot_name_for_active_mode(blueprint_entity)
    local new_name = convert_item_name_for_direction(blueprint_entity.name, active_migration_direction())
    if new_name and blueprint_entity.name ~= new_name then
        blueprint_entity.name = new_name
        return true
    end

    return false
end

--- Builds the replacement blueprint entity list from setup mapping.
--- @param mapping table<any, LuaEntity> blueprint entity_number -> source entity
--- @return BlueprintEntity[] entities
--- @return boolean changed
local function build_setup_blueprint_entities(mapping)
    local entities = {}
    local changed = false

    for blueprint_index, source_entity in pairs(mapping) do
        if source_entity and source_entity.valid then
            local blueprint_entity = snapshot_blueprint_entity(source_entity, blueprint_index)

            if rewrite_blueprint_snapshot_for_cliff(blueprint_entity, source_entity) then
                changed = true
            end

            if normalize_blueprint_snapshot_name_for_active_mode(blueprint_entity) then
                changed = true
            end

            entities[#entities + 1] = blueprint_entity
        end
    end

    table.sort(entities, function(a, b)
        return (a.entity_number or 0) < (b.entity_number or 0)
    end)

    return entities, changed
end

--- Writes the replacement BlueprintEntity list back to a LuaRecord/LuaItemStack blueprint.
--- @param blueprint LuaRecord|LuaItemStack
--- @param entities BlueprintEntity[]
--- @return boolean wrote
local function set_blueprint_entities_safe(blueprint, entities)
    if not (blueprint and entities) then return false end

    local set_entities = blueprint["set_blueprint_entities"]
    if type(set_entities) ~= "function" then return false end

    local ok = pcall(set_entities, entities)
    return ok == true
end

--- Handles both normal blueprint setup and copy/paste-style temporary blueprint setup.
--- @param event EventData.on_player_setup_blueprint
local function on_player_setup_blueprint(event)
    local blueprint = writable_blueprint_from_setup_event(event)
    if not blueprint then return end

    local mapping = setup_blueprint_mapping(event)
    if not mapping then return end

    local entities, changed = build_setup_blueprint_entities(mapping)
    if changed then
        set_blueprint_entities_safe(blueprint, entities)
    end
end

-----------------------------
-- Event hooks
-----------------------------

script.on_configuration_changed(on_configuration_changed)

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
