require("constants")

local util = require("util")

local use_map_gen_cliffs = settings.startup[USE_MAP_GEN_CLIFFS_SETTING]
    and settings.startup[USE_MAP_GEN_CLIFFS_SETTING].value == true

local technologies = data.raw["technology"] or {}
local cliffs = data.raw["cliff"] or {}

--- Localised strings are represented as either a plain string key or a parameterized table.
--- This narrower alias keeps LuaLS from inferring unsupported primitive values from generic prototype tables.
--- @alias CliffBuilderLocalisedString string|table

--- Returns whether `str` starts with `prefix`.
--- @param str string|nil String to test.
--- @param prefix string Prefix to match.
--- @return boolean
local function starts_with(str, prefix)
    return type(str) == "string" and string.sub(str, 1, #prefix) == prefix
end

--- Adds a prototype or updates an existing one with the same type/name.
--- @param prototype data.AnyPrototype Prototype definition to add or merge.
local function extend_or_update(prototype)
    local prototypes = data.raw[prototype.type]
    local existing = prototypes and prototypes[prototype.name]

    if existing then
        for key, value in pairs(prototype) do
            existing[key] = value
        end
    else
        data:extend({ prototype })
    end
end

--- Copies icon fields from a source prototype, falling back to the base cliff icon.
--- @param target table Prototype receiving icon fields.
--- @param source table Source prototype that may define `icon` or `icons`.
local function copy_icon_fields(target, source)
    if source.icons then
        target.icons = table.deepcopy(source.icons)
    elseif source.icon then
        target.icon = source.icon
        target.icon_size = source.icon_size or 64
        target.icon_mipmaps = source.icon_mipmaps
    else
        target.icon = "__base__/graphics/icons/cliff.png"
        target.icon_size = 64
    end
end

--- Returns the localised display name used by cliff items, recipes, and markers.
--- @param cliff_name string Source cliff prototype name.
--- @param source table Source cliff prototype.
--- @return CliffBuilderLocalisedString localised_name Display name.
local function cliff_display_name(cliff_name, source)
    if cliff_name == "crater-cliff" then
        return { "item-name.cb-mountains" }
    end

    local source_localised_name = source.localised_name
    if source_localised_name ~= nil then
        return source_localised_name --[[@as CliffBuilderLocalisedString]]
    end

    return { "entity-name." .. cliff_name }
end

--- Returns compatibility buildability rules for temporary marker entities.
--- @return table<string, boolean> rules Maraxsis-compatible buildability flags.
local function temporary_marker_buildability_rules()
    return {
        water = true,
        dome = true,
        coral = true,
        trench = true,
        trench_entrance = true,
        trench_lava = true
    }
end

--- Returns a collision mask for buildable cliff/marker placement.
--- @param source data.CliffPrototype|nil Source cliff prototype.
--- @return data.CollisionMaskConnector collision_mask Collision mask including the custom cb_cliff layer.
local function cliff_collision_mask(source)
    local mask = source and source.collision_mask and table.deepcopy(source.collision_mask) or {
        layers = {
            item = true,
            meltable = true,
            object = true,
            player = true,
            water_tile = true,
            is_object = true,
            is_lower_object = true,
            cliff = true
        },
        not_colliding_with_itself = true
    }

    mask.layers = mask.layers or {}
    mask.layers.cliff = true
    mask.layers.cb_cliff = true
    mask.not_colliding_with_itself = true

    return mask
end

local surface_mountain_range_tints = {
    nauvis = { r = 1, g = 0.833, b = 0.667, a = 1 },
    fulgora = { r = 1, g = 0.667, b = 0.667, a = 1 },
    gleba = { r = 0.667, g = 1, b = 0.667, a = 1 },
    aquilo = { r = 0.4, g = 0.833, b = 1, a = 1 },
    vulcanus = { r = 1, g = 1, b = 1, a = 1 }
}

--- Recursively applies a tint to non-shadow sprite definitions.
--- @param value table|nil Sprite or nested sprite table.
--- @param tint Color Tint applied to visible sprites.
local function tint_sprite_tree(value, tint)
    if type(value) ~= "table" then return end

    if value.filename and value.draw_as_shadow ~= true then
        value.tint = table.deepcopy(tint)
    end

    for _, child in pairs(value) do
        if type(child) == "table" then
            tint_sprite_tree(child, tint)
        end
    end
end

--- Returns the hidden visual variant name for a mountain-range cliff on a surface.
--- @param base_name string Base cliff prototype name.
--- @param surface_name string Surface name suffix.
--- @return string variant_name Hidden variant prototype name.
local function mountain_range_variant_name(base_name, surface_name)
    return base_name .. "-" .. surface_name
end

--- Creates one hidden surface-tinted mountain-range cliff variant.
--- @param base_entity data.CliffPrototype Base cliff entity to copy.
--- @param base_name string Base prototype/item name used for placement and mining.
--- @param source_cliff_name string Original source cliff prototype name.
--- @param surface_name string Surface name suffix for the hidden variant.
--- @param tint Color|false Tint to apply, or false to skip the surface.
local function create_surface_tinted_mountain_range_variant(base_entity, base_name, source_cliff_name, surface_name, tint)
    if source_cliff_name ~= "crater-cliff" then return end
    if not (base_entity and base_entity.type == "cliff") then return end
    if not tint then return end

    local variant = table.deepcopy(base_entity)
    variant.name = mountain_range_variant_name(base_name, surface_name)
    variant.hidden = true
    variant.hidden_in_factoriopedia = true
    variant.localised_name = base_entity.localised_name or cliff_display_name(source_cliff_name, base_entity)
    variant.placeable_by = { item = base_name, count = 1 }
    variant.minable = { mining_time = 1.0, result = base_name, count = 1 }

    local surface_cliff = cliffs["cliff-" .. surface_name]
    if surface_cliff then
        variant.map_color = surface_cliff.map_color or variant.map_color
    end

    tint_sprite_tree(variant.orientations, tint)
    extend_or_update(variant)
end

--- Creates all configured hidden visual variants for a mountain-range cliff.
--- @param base_entity data.CliffPrototype Base cliff entity to copy.
--- @param base_name string Base prototype/item name used for placement and mining.
--- @param source_cliff_name string Original source cliff prototype name.
local function create_surface_tinted_mountain_range_variants(base_entity, base_name, source_cliff_name)
    for surface_name, tint in pairs(surface_mountain_range_tints) do
        create_surface_tinted_mountain_range_variant(base_entity, base_name, source_cliff_name, surface_name, tint)
    end
end

--- Configures a copied cliff prototype so it is buildable by this mod.
--- @param entity data.CliffPrototype Cliff prototype to mutate.
--- @param name string Prototype/item name to assign.
--- @param hidden boolean|nil Whether the entity should be hidden compatibility content.
local function configure_cliff_entity(entity, name, hidden)
    entity.name = name
    entity.hidden = hidden == true
    entity.hidden_in_factoriopedia = hidden == true
    entity.minable = { mining_time = 1.0, result = name, count = 1 }
    entity.selectable_in_game = true
    entity.placeable_by = { item = name, count = 1 }
    entity.surface_conditions = nil

    entity.flags = {
        "player-creation",
        "placeable-neutral",
        "not-rotatable"
    }

    entity.collision_mask = cliff_collision_mask(entity)
end

--- Creates the item, recipe, and visible/invisible marker prototypes for a cliff.
--- @param definition table Source cliff definition with `name`, `source`, and `ingredient`.
--- @param name string Prototype/item name to create.
--- @param hidden boolean|nil Whether created prototypes are hidden compatibility content.
--- @param unlock_recipe boolean|nil Whether to unlock the recipe from landfill technology.
local function create_cliff_supporting_prototypes(definition, name, hidden, unlock_recipe)
    local cliff = definition.name
    local source = definition.source
    local item = {
        type = "item",
        name = name,
        hidden = hidden == true,
        stack_size = 50,
        place_result = name,
        localised_name = cliff_display_name(cliff, source),
        subgroup = "terrain",
        order = "c[landfill]-b[" .. cliff .. "]",
        weight = 20 * kg
    }
    copy_icon_fields(item, source)
    extend_or_update(item)

    extend_or_update({
        type = "recipe",
        name = name,
        hidden = hidden == true,
        enabled = false,
        energy_required = 1,
        category = "crafting",
        ingredients = {
            { type = "item", name = "landfill",            amount = 4 },
            { type = "item", name = definition.ingredient, amount = 10 }
        },
        results = {
            { type = "item", name = name, amount = 1 }
        },
        localised_name = cliff_display_name(cliff, source)
    })

    if unlock_recipe ~= false and technologies["landfill"] and technologies["landfill"].effects then
        local already_unlocked = false
        for _, effect in ipairs(technologies["landfill"].effects) do
            if effect.type == "unlock-recipe" and effect.recipe == name then
                already_unlocked = true
                break
            end
        end
        if not already_unlocked then
            table.insert(technologies["landfill"].effects, { type = "unlock-recipe", recipe = name })
        end
    end

    local invisible = {
        type = "simple-entity-with-owner",
        name = "invisible-4x4-" .. name,
        flags = { "placeable-neutral", "player-creation", "not-on-map" },
        selectable_in_game = false,
        allow_copy_paste = true,
        is_military_target = false,
        selection_priority = 40,
        hidden_in_factoriopedia = true,
        -- Maraxsis reads this custom field before adding tile_buildability_rules.
        -- Keep temporary cliff-builder markers buildable anywhere the real cliff may be restored.
        maraxsis_buildability_rules = temporary_marker_buildability_rules(),
        build_grid_size = 2,
        selection_box = { { -2, -2 }, { 2, 2 } },
        collision_box = { { -1.9, -1.9 }, { 1.9, 1.9 } },
        collision_mask = { layers = {} },
        picture = util.empty_sprite(),
        localised_name = cliff_display_name(cliff, source)
    }
    copy_icon_fields(invisible, source)
    extend_or_update(invisible)

    local invisible_item = {
        type = "item",
        name = "invisible-4x4-" .. name,
        stack_size = 50,
        weight = 20 * kg,
        place_result = "invisible-4x4-" .. name,
        hidden = hidden == true,
        hidden_in_factoriopedia = true,
        auto_recycle = false,
        localised_name = cliff_display_name(cliff, source)
    }
    copy_icon_fields(invisible_item, source)
    extend_or_update(invisible_item)

    local visible = {
        type = "simple-entity-with-owner",
        name = "visible-4x4-" .. name,
        flags = { "placeable-neutral", "player-creation", "not-on-map", "not-rotatable" },
        selectable_in_game = true,
        allow_copy_paste = true,
        is_military_target = false,
        selection_priority = 40,
        placeable_by = { { item = name, count = 1 } },
        hidden_in_factoriopedia = true,
        -- See the invisible marker note above.
        maraxsis_buildability_rules = temporary_marker_buildability_rules(),
        build_grid_size = 2,
        selection_box = { { -2, -2 }, { 2, 2 } },
        collision_box = { { -1.9, -1.9 }, { 1.9, 1.9 } },
        collision_mask = cliff_collision_mask(source),
        picture = {
            filename = "__cliff-builder__/graphics/entity/visible-4x4.png",
            priority = "extra-high",
            width = 256,
            height = 256,
            scale = 0.5
        },
        localised_name = cliff_display_name(cliff, source)
    }
    copy_icon_fields(visible, source)
    extend_or_update(visible)

    local visible_item = {
        type = "item",
        name = "visible-4x4-" .. name,
        stack_size = 50,
        weight = 20 * kg,
        place_result = "visible-4x4-" .. name,
        hidden = hidden == true,
        hidden_in_factoriopedia = true,
        auto_recycle = false,
        localised_name = cliff_display_name(cliff, source)
    }
    copy_icon_fields(visible_item, source)
    extend_or_update(visible_item)
end

--- Creates the primary cb-* buildable cliff set for cliff-builder mode.
--- @param definition table Source cliff definition with `name`, `source`, and `ingredient`.
local function create_cliff_builder_set(definition)
    local cliff = definition.name
    local name = CLIFF_PREFIX .. cliff
    local source = definition.source

    local entity = table.deepcopy(source)
    configure_cliff_entity(entity, name, false)
    data:extend({ entity })
    create_surface_tinted_mountain_range_variants(entity, name, cliff)

    create_cliff_supporting_prototypes(definition, name, false, true)
end

--- Creates hidden cb-* compatibility prototypes while map-gen mode is active.
--- @param definition table Source cliff definition with `name`, `source`, and `ingredient`.
local function create_compatibility_cliff_builder_set(definition)
    local cliff = definition.name
    local name = CLIFF_PREFIX .. cliff
    local source = definition.source

    if not cliffs[name] then
        local entity = table.deepcopy(source)
        configure_cliff_entity(entity, name, true)
        data:extend({ entity })
        create_surface_tinted_mountain_range_variants(entity, name, cliff)
    end

    create_cliff_supporting_prototypes(definition, name, true, false)

    local visible_marker = data.raw["simple-entity-with-owner"]["visible-4x4-" .. name]
    if visible_marker then
        visible_marker.placeable_by = { { item = cliff, count = 1 } }
    end
end

--- Hides the inactive source/map-gen cliff entry from Factoriopedia.
--- The source prototype remains available for map generation and compatibility; only the encyclopedia entry is suppressed.
--- @param definition table Source cliff definition with `name` and `source`.
local function hide_source_cliff_factoriopedia_entry(definition)
    local source = definition.source
    if source then
        source.hidden_in_factoriopedia = true
    end
end

--- Creates hidden map-gen-name compatibility prototypes while cliff-builder mode is active.
--- @param definition table Source cliff definition with `name`, `source`, and `ingredient`.
local function create_compatibility_map_gen_set(definition)
    local cliff = definition.name

    hide_source_cliff_factoriopedia_entry(definition)
    create_cliff_supporting_prototypes(definition, cliff, true, false)

    local visible_marker = data.raw["simple-entity-with-owner"]["visible-4x4-" .. cliff]
    if visible_marker then
        visible_marker.placeable_by = { { item = CLIFF_PREFIX .. cliff, count = 1 } }
    end
end

--- Configures source cliff prototypes directly for map-gen cliff mode.
--- @param definition table Source cliff definition with `name`, `source`, and `ingredient`.
local function create_map_gen_set(definition)
    local cliff = definition.name
    local source = definition.source

    configure_cliff_entity(source, cliff, false)
    create_surface_tinted_mountain_range_variants(source, cliff, cliff)
    create_cliff_supporting_prototypes(definition, cliff, false, true)
end

--- Returns whether a source cliff should receive buildable prototypes.
--- @param name string Source cliff prototype name.
--- @param cliff data.CliffPrototype Source cliff prototype.
--- @return boolean supported True when the cliff should be supported.
local function should_support_cliff(name, cliff)
    if starts_with(name, CLIFF_PREFIX) then return false end
    if cliff.hidden == true or cliff.hidden_in_factoriopedia == true then return false end
    return true
end

local regular_cliff_ingredients = {
    ["cliff"] = "stone",
    ["cliff-fulgora"] = "holmium-ore",
    ["cliff-gleba"] = "spoilage",
    ["cliff-vulcanus"] = "calcite",
    ["crater-cliff"] = "stone",
}

--- Returns the recipe ingredient used to craft a buildable cliff item.
--- @param name string Source cliff prototype name.
--- @return string ingredient Item prototype name used as the recipe ingredient.
local function ingredient_for_cliff(name)
    -- Keep the vanilla/Space Age recipes aligned with the original mod.
    -- Mountains use stone so they stay generic and craftable on all surfaces.
    return regular_cliff_ingredients[name] or "stone"
end

local supported_cliff_names = {}
for name, cliff in pairs(cliffs) do
    if should_support_cliff(name, cliff) then
        table.insert(supported_cliff_names, name)
    end
end
table.sort(supported_cliff_names)

for _, name in ipairs(supported_cliff_names) do
    local cliff = cliffs[name]
    local definition = {
        name = name,
        source = cliff,
        ingredient = ingredient_for_cliff(name)
    }

    if use_map_gen_cliffs then
        create_map_gen_set(definition)
        create_compatibility_cliff_builder_set(definition)
    else
        if not cliffs[CLIFF_PREFIX .. name] then
            create_cliff_builder_set(definition)
        end
        create_compatibility_map_gen_set(definition)
    end
end
