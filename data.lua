require("constants")

local util = require("util")

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
        surface_conditions = mods["space-age"] and SURFACE_CONDITIONS["nauvis"] or nil,
    }
}

if mods["space-age"] then
    table.insert(cliff_definitions,
        {
            name = "cliff-fulgora",
            ingredient = "holmium-ore",
            surface_conditions = SURFACE_CONDITIONS["fulgora"],
        })

    table.insert(cliff_definitions,
        {
            name = "cliff-gleba",
            ingredient = "spoilage",
            surface_conditions = SURFACE_CONDITIONS["gleba"],
        })

    table.insert(cliff_definitions,
        {
            name = "cliff-vulcanus",
            ingredient = "calcite",
            surface_conditions = SURFACE_CONDITIONS["vulcanus"],
        })
end

local technologies = data.raw["technology"]

for _, definition in ipairs(cliff_definitions) do
    local cliff = definition.name
    local name = CLIFF_PREFIX .. cliff

    local entity = table.deepcopy(data.raw["cliff"][cliff])
    entity.name = name
    entity.hidden_in_factoriopedia = false
    entity.minable = { mining_time = 1.0, result = name, count = 1 }
    entity.selectable_in_game = true
    entity.placeable_by = { item = name, count = 1 }
    entity.surface_conditions = definition.surface_conditions

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

    data:extend({ entity })

    local icon = data.raw["cliff"][cliff].icon

    data:extend({
        {
            type = "item",
            name = name,
            hidden = false,
            icon = icon,
            icon_size = 64,
            stack_size = 50,
            place_result = name,

            localised_name = { "", { "entity-name." .. name } },
            subgroup = "terrain",
            order = "c[landfill]-b[" .. cliff .. "]",
            weight = 20 * kg
        }
    })

    data:extend({
        {
            type = "recipe",
            name = name,
            hidden = false,
            enabled = false,
            energy_required = 1,
            category = "crafting",
            surface_conditions = definition.surface_conditions,
            ingredients = {
                { type = "item", name = "landfill",            amount = 4 },
                { type = "item", name = definition.ingredient, amount = 10 }
            },
            results = {
                { type = "item", name = name, amount = 1 }
            }
        }
    })

    if technologies["landfill"] and technologies["landfill"].effects then
        table.insert(technologies["landfill"].effects, { type = "unlock-recipe", recipe = name })
    end

    data:extend({
        {
            type = "item",
            name = "invisible-4x4-" .. name,
            icon = icon,
            icon_size = 64,
            stack_size = 50,
            weight = 20 * kg,
            place_result = "invisible-4x4-" .. name,
            hidden_in_factoriopedia = true
        },

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
        }
    })

    data:extend({
        {
            type = "item",
            name = "visible-4x4-" .. name,
            icon = icon,
            icon_size = 64,
            stack_size = 50,
            weight = 20 * kg,
            place_result = "visible-4x4-" .. name,
            hidden_in_factoriopedia = true
        },

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
        }
    })
end

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
