require("constants")

local function set_hidden(name, hidden)
    local entity = data.raw["cliff"] and data.raw["cliff"][name]
    if entity then
        entity.hidden_in_factoriopedia = hidden
    end

    local item = data.raw["item"] and data.raw["item"][name]
    if item then
        item.hidden = hidden
        item.hidden_in_factoriopedia = hidden
    end

    local recipe = data.raw["recipe"] and data.raw["recipe"][name]
    if recipe then
        recipe.hidden = hidden
        recipe.hidden_in_factoriopedia = hidden
    end
end

local function set_surface_conditions(name, surface_conditions)
    local entity = data.raw["cliff"] and data.raw["cliff"][name]
    if entity then
        entity.surface_conditions = surface_conditions
    end

    local recipe = data.raw["recipe"] and data.raw["recipe"][name]
    if recipe then
        recipe.surface_conditions = surface_conditions
    end
end

local function apply_everything_on_nauvis_compat()
    set_surface_conditions("cf-cliff", surface_conditions["nauvis"])
    set_surface_conditions("cf-cliff-gleba", surface_conditions["nauvis"])
    set_surface_conditions("cf-cliff-vulcanus", surface_conditions["nauvis"])

    set_hidden("cf-cliff-fulgora", true)
end

local function apply_eon_fulgora_discovered_compat()
    set_surface_conditions("cf-cliff", surface_conditions["nauvis"])
    set_surface_conditions("cf-cliff-gleba", surface_conditions["nauvis"])
    set_surface_conditions("cf-cliff-vulcanus", surface_conditions["nauvis"])
    set_surface_conditions("cf-cliff-fulgora", surface_conditions["fulgora"])
end

if mods["space-age"] then
    if mods["EverythingOnNauvis"] then
        apply_everything_on_nauvis_compat()
    end

    if mods["EON-FulgoraDiscovered"] then
        apply_eon_fulgora_discovered_compat()
    end
end
