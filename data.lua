require("constants")

local util = require("util")

local use_map_gen_cliffs = settings.startup[USE_MAP_GEN_CLIFFS_SETTING]
    and settings.startup[USE_MAP_GEN_CLIFFS_SETTING].value == true

data:extend({
    {
        type = "custom-input",
        name = "cliff-flip",
        key_sequence = "SHIFT + R",
        include_selected_prototype = true,
    },
    {
        type = "custom-input",
        name = "cliff-flip-selected",
        key_sequence = "R",
        include_selected_prototype = true,
    },
    {
        type = "custom-input",
        name = "display-cliff-orientation",
        key_sequence = "SHIFT + mouse-button-1",
        consuming = "none"
    }
})

data:extend({
    {
        type = "collision-layer",
        name = "cb_cliff"
    }
})

local cliff_definitions = {
    {
        name = "cliff",
        ingredient = "stone",
    }
}

if mods["space-age"] then
    table.insert(cliff_definitions,
        {
            name = "cliff-fulgora",
            ingredient = "holmium-ore",
        })

    table.insert(cliff_definitions,
        {
            name = "cliff-gleba",
            ingredient = "spoilage",
        })

    table.insert(cliff_definitions,
        {
            name = "cliff-vulcanus",
            ingredient = "calcite",
        })
end

local technologies = data.raw["technology"] or {}

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

local function configure_cliff_entity(entity, name, hidden)
    entity.name = name
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

    entity.collision_mask = {
        layers = {
            item = true,
            meltable = true,
            object = true,
            player = true,
            water_tile = true,
            is_object = true,
            is_lower_object = true,
            cliff = true,
            cb_cliff = true
        },
        not_colliding_with_itself = true
    }
end

local function create_cliff_supporting_prototypes(definition, name, icon, hidden, unlock_recipe)
    local cliff = definition.name

    extend_or_update({
        type = "item",
        name = name,
        hidden = hidden == true,
        icon = icon,
        icon_size = 64,
        stack_size = 50,
        place_result = name,

        localised_name = { "", { "entity-name." .. name } },
        subgroup = "terrain",
        order = "c[landfill]-b[" .. cliff .. "]",
        weight = 20 * kg
    })

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
        }
    })

    if unlock_recipe ~= false and technologies["landfill"] and technologies["landfill"].effects then
        table.insert(technologies["landfill"].effects, { type = "unlock-recipe", recipe = name })
    end

    data:extend({
        {
            type = "simple-entity-with-owner",
            name = "invisible-4x4-" .. name,
            icon = icon,
            icon_size = 64,

            flags = { "placeable-neutral", "player-creation", "not-on-map" },
            selectable_in_game = false,
            allow_copy_paste = true,
            is_military_target = false,
            selection_priority = 40,
            hidden_in_factoriopedia = true,
            build_grid_size = 2,

            selection_box = { { -2, -2 }, { 2, 2 } },
            collision_box = { { -1.9, -1.9 }, { 1.9, 1.9 } },
            collision_mask = { layers = {} },

            picture = util.empty_sprite(),
        },
        {
            type = "item",
            name = "invisible-4x4-" .. name,
            icon = icon,
            icon_size = 64,
            stack_size = 50,
            weight = 20 * kg,
            place_result = "invisible-4x4-" .. name,
            hidden = hidden == true,
            hidden_in_factoriopedia = true,
            auto_recycle = false
        }
    })

    data:extend({
        {
            type = "simple-entity-with-owner",
            name = "visible-4x4-" .. name,
            icon = icon,
            icon_size = 64,

            flags = { "placeable-neutral", "player-creation", "not-on-map", "not-rotatable" },
            selectable_in_game = true,
            allow_copy_paste = true,
            is_military_target = false,
            selection_priority = 40,
            placeable_by = { { item = name, count = 1 } },
            hidden_in_factoriopedia = true,
            build_grid_size = 2,

            selection_box = { { -2, -2 }, { 2, 2 } },
            collision_box = { { -1.9, -1.9 }, { 1.9, 1.9 } },

            collision_mask = {
                layers = {
                    item = true,
                    meltable = true,
                    object = true,
                    player = true,
                    water_tile = true,
                    is_object = true,
                    is_lower_object = true,
                    cliff = true,
                    cb_cliff = true
                },
                not_colliding_with_itself = true
            },

            picture = {
                filename = "__cliff-builder__/graphics/entity/visible-4x4.png",
                priority = "extra-high",
                width = 256,
                height = 256,
                scale = 0.5
            }
        },
        {
            type = "item",
            name = "visible-4x4-" .. name,
            icon = icon,
            icon_size = 64,
            stack_size = 50,
            weight = 20 * kg,
            place_result = "visible-4x4-" .. name,
            hidden = hidden == true,
            hidden_in_factoriopedia = true,
            auto_recycle = false
        }
    })
end

local function create_cliff_builder_set(definition)
    local cliff = definition.name
    local name = CLIFF_PREFIX .. cliff
    local vanilla_entity = data.raw["cliff"][cliff]

    if not vanilla_entity then return end

    local entity = table.deepcopy(vanilla_entity)
    configure_cliff_entity(entity, name, false)
    data:extend({ entity })

    create_cliff_supporting_prototypes(definition, name, vanilla_entity.icon, false, true)
end

local function create_compatibility_cliff_builder_set(definition)
    local cliff = definition.name
    local name = CLIFF_PREFIX .. cliff
    local vanilla_entity = data.raw["cliff"][cliff]

    if not vanilla_entity then return end

    local entity = table.deepcopy(vanilla_entity)
    configure_cliff_entity(entity, name, true)
    data:extend({ entity })

    -- Keep old cb-* prototypes loadable for saves/blueprints while map-gen mode is enabled.
    -- They are hidden and their recipes are not unlocked; on_configuration_changed migrates
    -- existing entities/markers to the vanilla/map-gen names.
    create_cliff_supporting_prototypes(definition, name, vanilla_entity.icon, true, false)

    -- Old blueprints contain visible-4x4-cb-* ghosts. In map-gen mode those ghosts must
    -- be satisfied by the active vanilla/map-gen cliff item, not the hidden cb-* item.
    -- The runtime build handler then converts the legacy marker name to the vanilla cliff.
    local visible_marker = data.raw["simple-entity-with-owner"]["visible-4x4-" .. name]
    if visible_marker then
        visible_marker.placeable_by = { { item = cliff, count = 1 } }
    end
end

local function create_compatibility_map_gen_set(definition)
    local cliff = definition.name
    local vanilla_entity = data.raw["cliff"][cliff]

    if not vanilla_entity then return end

    -- Keep visible-4x4-* and invisible-4x4-* prototypes loadable for blueprints
    -- made while map-gen mode was enabled. They are hidden and their recipes are
    -- not unlocked; runtime normalization restores cb-* cliffs in cb mode.
    create_cliff_supporting_prototypes(definition, cliff, vanilla_entity.icon, true, false)

    -- Map-gen-mode blueprints contain visible-4x4-* ghosts. In cb mode those
    -- ghosts must be satisfied by the active cb-* cliff item, not the hidden
    -- vanilla/map-gen item. The runtime build handler then converts the marker
    -- name to the cb cliff.
    local visible_marker = data.raw["simple-entity-with-owner"]["visible-4x4-" .. cliff]
    if visible_marker then
        visible_marker.placeable_by = { { item = CLIFF_PREFIX .. cliff, count = 1 } }
    end
end

local function create_map_gen_set(definition)
    local cliff = definition.name
    local vanilla_entity = data.raw["cliff"][cliff]

    if not vanilla_entity then return end

    configure_cliff_entity(vanilla_entity, cliff, false)
    create_cliff_supporting_prototypes(definition, cliff, vanilla_entity.icon, false, true)
end

for _, definition in ipairs(cliff_definitions) do
    if use_map_gen_cliffs then
        create_map_gen_set(definition)
        create_compatibility_cliff_builder_set(definition)
    else
        create_cliff_builder_set(definition)
        create_compatibility_map_gen_set(definition)
    end
end
