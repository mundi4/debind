-- Probe_BindingList.lua
-- Every row of the game's binding list, grouped by category, written to
-- `DebindDevDB.bindingList`. Also times the loop `CollectClaimedKeys` in
-- `Debind/BindingContexts.lua` runs, to see what walking the whole list costs.
--
--   /debbinds        take the list and time the loop
--   /debbinds wipe   drop the stored result

local TAG = "|cff00ccff[Bindings]|r "
local TIMING_RUNS = 100

local CONTEXT_NAME = {}
if (Enum and Enum.BindingContext) then
    for name, value in pairs(Enum.BindingContext) do
        CONTEXT_NAME[value] = name
    end
end

local function GetContext(action)
    if (C_KeyBindings and C_KeyBindings.GetBindingContextForAction and action) then
        return C_KeyBindings.GetBindingContextForAction(action)
    end
end

local function Collect()
    local byCategory = {}
    local categories = {}
    local count = GetNumBindings()

    for i = 1, count do
        local action, category = GetBinding(i)
        category = category or "(none)"
        local group = byCategory[category]
        if (not group) then
            local heading = _G[category]
            group = {
                category = category,
                -- An addon's category can share its name with the addon's own table.
                categoryName = type(heading) == "string" and heading or category,
                firstIndex = i,
                bindings = {},
            }
            byCategory[category] = group
            tinsert(categories, group)
        end
        local context = GetContext(action)
        local name = action and _G["BINDING_NAME_" .. action]
        tinsert(group.bindings, {
            index = i,
            action = action,
            name = type(name) == "string" and name or nil,
            context = context,
            contextName = context and CONTEXT_NAME[context] or nil,
            keys = { GetBindingKey(action) },
        })
    end

    sort(categories, function(a, b) return a.firstIndex < b.firstIndex end)
    return categories, count
end

local function TimeLoop(fn)
    local start = debugprofilestop()
    for _ = 1, TIMING_RUNS do
        fn()
    end
    return (debugprofilestop() - start) / TIMING_RUNS
end

-- The same calls `CollectClaimedKeys` makes, with every context treated as active so the
-- `GetBindingKey` branch runs for every contexted row whether the editor is open or not.
local function WalkLikeCollectClaimedKeys()
    local out = {}
    for i = 1, GetNumBindings() do
        local action = GetBinding(i)
        local context = action and C_KeyBindings.GetBindingContextForAction(action)
        if (context and context ~= Enum.BindingContext.None) then
            C_KeyBindings.IsBindingContextActive(context)
            for j = 1, select("#", GetBindingKey(action)) do
                local key = select(j, GetBindingKey(action))
                if (key) then
                    out[key] = true
                end
            end
        end
    end
end

local function WalkOnlyGetBinding()
    for i = 1, GetNumBindings() do
        GetBinding(i)
    end
end

local function Run()
    local categories, count = Collect()

    local contexted = 0
    for _, group in ipairs(categories) do
        for _, row in ipairs(group.bindings) do
            if (row.context and row.context ~= (Enum.BindingContext and Enum.BindingContext.None)) then
                contexted = contexted + 1
            end
        end
    end

    local timing = { runs = TIMING_RUNS }
    timing.getBindingOnlyMs = TimeLoop(WalkOnlyGetBinding)
    if (C_KeyBindings and C_KeyBindings.GetBindingContextForAction and Enum and Enum.BindingContext) then
        timing.collectClaimedKeysMs = TimeLoop(WalkLikeCollectClaimedKeys)
    end

    DebindDevDB = DebindDevDB or {}
    DebindDevDB.bindingList = {
        at = date("%Y-%m-%d %H:%M:%S"),
        build = select(4, GetBuildInfo()),
        numBindings = count,
        numContexted = contexted,
        timing = timing,
        categories = categories,
    }

    print(TAG .. format("%d bindings in %d categories, %d in a context. Saved to DebindDevDB.bindingList.",
        count, #categories, contexted))
    print(TAG .. format("GetBinding only: %.3f ms. CollectClaimedKeys loop: %s (average of %d)",
        timing.getBindingOnlyMs,
        timing.collectClaimedKeysMs and format("%.3f ms", timing.collectClaimedKeysMs) or "n/a",
        TIMING_RUNS))
end

SLASH_DEBBINDS1 = "/debbinds"
SlashCmdList["DEBBINDS"] = function(msg)
    if (strlower(strtrim(msg or "")) == "wipe") then
        if (DebindDevDB) then
            DebindDevDB.bindingList = nil
        end
        print(TAG .. "stored result dropped")
        return
    end
    Run()
end
