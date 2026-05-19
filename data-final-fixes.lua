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
    },
    {
        type = "collision-layer",
        name = "cb_cliff"
    }
})

local technologies = data.raw["technology"] or {}
local cliffs = data.raw["cliff"] or {}

local function starts_with(str, prefix)
    return type(str) == "string" and string.sub(str, 1, #prefix) == prefix
end

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

local function cliff_display_name(cliff_name, source)
    if cliff_name == "crater-cliff" then
        return { "item-name.cb-mountains" }
    end
    return source.localised_name or { "entity-name." .. cliff_name }
end

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
    nauvis = { r = 0.80, g = 0.68, b = 0.56, a = 1.0 },
    fulgora = { r = 1.0, g = 0.76, b = 0.66, a = 1.0 },
    gleba = { r = 0.70, g = 0.88, b = 0.60, a = 1.0 },
    aquilo = { r = 0.85, g = 0.92, b = 1.0, a = 1.0 },
    vulcanus = false
}

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

local function mountain_range_variant_name(base_name, surface_name)
    return base_name .. "-" .. surface_name
end

local function create_surface_tinted_mountain_range_variant(base_entity, base_name, source_cliff_name, surface_name, tint)
    if source_cliff_name ~= "crater-cliff" then return end
    if not (base_entity and base_entity.type == "cliff") then return end
    if not tint then return end

    local variant = table.deepcopy(base_entity)
    variant.name = mountain_range_variant_name(base_name, surface_name)
    variant.hidden = true
    variant.hidden_in_factoriopedia = true
    variant.placeable_by = { item = base_name, count = 1 }
    variant.minable = { mining_time = 1.0, result = base_name, count = 1 }

    local surface_cliff = cliffs["cliff-" .. surface_name]
    if surface_cliff then
        variant.map_color = surface_cliff.map_color or variant.map_color
    end

    tint_sprite_tree(variant.orientations, tint)
    extend_or_update(variant)
end

local function create_surface_tinted_mountain_range_variants(base_entity, base_name, source_cliff_name)
    for surface_name, tint in pairs(surface_mountain_range_tints) do
        create_surface_tinted_mountain_range_variant(base_entity, base_name, source_cliff_name, surface_name, tint)
    end
end

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

local function create_compatibility_map_gen_set(definition)
    local cliff = definition.name

    create_cliff_supporting_prototypes(definition, cliff, true, false)

    local visible_marker = data.raw["simple-entity-with-owner"]["visible-4x4-" .. cliff]
    if visible_marker then
        visible_marker.placeable_by = { { item = CLIFF_PREFIX .. cliff, count = 1 } }
    end
end

local function create_map_gen_set(definition)
    local cliff = definition.name
    local source = definition.source

    configure_cliff_entity(source, cliff, false)
    create_surface_tinted_mountain_range_variants(source, cliff, cliff)
    create_cliff_supporting_prototypes(definition, cliff, false, true)
end

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
