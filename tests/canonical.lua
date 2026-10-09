--- **Every action in the profile has to be one that could be saved or exported at this moment.**
--- The writers keep that shape rather than leaving it to a clean-up. This net looks at every layer
--- right before each `UpdateBindings` and each `SanitizeLoadedLayers` (the load, the import at login,
--- the logout), which is where a writer that relied on the clean-up shows: each test stands its own
--- profile up, so by the end of a spec only the last test's few actions are left to look at.
---
--- **The field tables are the store's** (`ACTION_FIELDS`, `CONDITION_TYPES`, `CASTING_TYPES`), read
--- off Debind's own. The other rules restate the shape here rather than calling
--- `SanitizeAction`, `DropFieldsTheTypeCannotHold` or `Talents.Prune`: a net that called them would
--- agree with whatever they do.
---
--- A test that plants a hand-made value on purpose says so with `ctx.HandMade(action)`, and that
--- action is skipped.

local M = {};

local handMade = setmetatable({}, { __mode = "k" });

function M.HandMade(action)
    handMade[action] = true;
    return action;
end

--- Numbers the keyed actions of one stored list that carry no `seq`, in list order within each
--- (key, arrivalID) group, after whatever that group already holds. A profile a build wrote always
--- has them, since every writer renumbers (`RenumberKeyGroup`), so a fixture standing in for one
--- does too.
function M.Numbered(actions)
    local top = {};
    for _, action in ipairs(actions) do
        if (action.key ~= nil and type(action.seq) == "number") then
            local group = tostring(action.key) .. "/" .. tostring(action.arrivalID);
            top[group] = math.max(top[group] or 0, action.seq);
        end
    end
    for _, action in ipairs(actions) do
        if (action.key ~= nil and action.seq == nil) then
            local group = tostring(action.key) .. "/" .. tostring(action.arrivalID);
            top[group] = (top[group] or 0) + 1;
            action.seq = top[group];
        end
    end
    return actions;
end

--- Where in the spec the rebuild was asked for, so a report points at the test.
--- Every line of the spec on the stack, innermost first, since the innermost is usually a helper.
local function SpecFrame()
    local file, lines = nil, {};
    for level = 3, 60 do
        local info = debug.getinfo(level, "Sl");
        if (info == nil) then
            break;
        end
        if (info.short_src:find("_spec%.lua$")) then
            file = file or info.short_src:match("([^/\\]+)$");
            lines[#lines + 1] = tostring(info.currentline);
        end
    end
    return file and (file .. ":" .. table.concat(lines, "<")) or "?";
end

local function Describe(action)
    return ("%s %s on %s"):format(tostring(action.type), tostring(action.value), tostring(action.key));
end

--- What is wrong with one action, as a list of sentences.
local function Problems(DebindPrivate, DebindStorage, action)
    local Constants = DebindPrivate.Constants;
    local ACTION_FIELDS = DebindStorage.ACTION_FIELDS;
    local CONDITION_TYPES = DebindStorage.CONDITION_TYPES;
    local CASTING_TYPES = DebindStorage.CASTING_TYPES;
    local out = {};
    local function bad(fmt, ...)
        out[#out + 1] = fmt:format(...);
    end
    local function typed(expected, value)
        for want in expected:gmatch("[^|]+") do
            if (type(value) == want) then
                return true;
            end
        end
        return false;
    end

    for k, v in pairs(action) do
        -- `untranslated` rides on the wire only; `arrivalID` is stored only.
        local expected = (k == "arrivalID" and "number") or (k ~= "untranslated" and ACTION_FIELDS[k]);
        if (not expected) then
            bad("field %s is not saved", tostring(k));
        elseif (not typed(expected, v)) then
            bad("%s is a %s", k, type(v));
        end
    end

    local specResolved = Constants.SPEC_RESOLVED_TYPES[action.type];

    local conditions = rawget(action, "conditions");
    if (type(conditions) == "table") then
        if (next(conditions) == nil) then
            bad("conditions is empty");
        end
        for k, v in pairs(conditions) do
            local expected = CONDITION_TYPES[k] or (Constants.IsConditionField(k) and "boolean");
            if (not expected) then
                bad("condition %s is not a condition", tostring(k));
            elseif (not typed(expected, v)) then
                bad("condition %s is a %s", k, type(v));
            end
        end
        local known = conditions.known;
        if (known == false) then
            bad("known is false");
        elseif (known ~= nil and action.type ~= Constants.SPELL and not specResolved) then
            bad("known on a type that asks none");
        elseif (known == true and specResolved) then
            bad("known = true on a spec-resolved type (skipWhenUnusable)");
        end
        local talents = conditions.talents;
        if (type(talents) == "table") then
            if (next(talents) == nil) then
                bad("talents is empty");
            end
            for specID, entry in pairs(talents) do
                local any = false;
                for _, name in ipairs({ "taken", "notTaken" }) do
                    local list = type(entry) == "table" and entry[name];
                    if (type(list) == "table") then
                        if (#list == 0) then
                            bad("talents[%s].%s is empty", tostring(specID), name);
                        else
                            any = true;
                        end
                    end
                end
                if (not any) then
                    bad("talents[%s] says nothing", tostring(specID));
                end
            end
        end
    end

    local casting = rawget(action, "casting");
    if (type(casting) == "table") then
        if (next(casting) == nil) then
            bad("casting is empty");
        end
        for k, v in pairs(casting) do
            local expected = CASTING_TYPES[k];
            if (not expected) then
                bad("casting.%s is not a casting value", tostring(k));
            elseif (not typed(expected, v)) then
                bad("casting.%s is a %s", k, type(v));
            end
        end
        if (casting.normalCast ~= nil and casting.normalCast ~= false) then
            bad("casting.normalCast is the default");
        end
    end

    if (action.priority == Constants.DEFAULT_IMPORTANCE) then
        bad("priority is the default");
    end
    if (action.skipWhenUnusable == false) then
        bad("skipWhenUnusable is false, which is stored as none");
    end
    if (action.skipWhenUnusable ~= nil and not specResolved) then
        bad("skipWhenUnusable on a type that is not spec-resolved");
    end
    if ((action.noTargetMassRez ~= nil or action.battleRezOutOfCombat ~= nil)
            and action.type ~= Constants.RESURRECT) then
        bad("a resurrection switch on a type that is not a resurrection");
    end
    if (action.pinnedSpell ~= nil and action.type ~= Constants.SPELL) then
        bad("pinnedSpell on a type that is not a spell");
    end
    if (action.resolvedSpellID ~= nil
            and (action.type ~= Constants.SPELL or type(action.value) ~= "string")) then
        bad("resolvedSpellID beside something that is not a spell name");
    end
    if (action.key == "ESCAPE") then
        bad("key is ESCAPE");
    end
    if (action.key == nil and action.seq ~= nil) then
        bad("seq on a keyless action");
    elseif (action.key ~= nil and action.seq == nil) then
        bad("no seq on a keyed action");
    end
    return out;
end

local function Sweep(DebindPrivate, DebindStorage, where, report)
    local frame;
    for layerID = 1, 64 do
        local layer = DebindPrivate.GetProfileLayer(layerID);
        if (layer == nil) then
            break;
        end
        local seen = {};
        for _, action in layer:Enumerate() do
            if (not handMade[action]) then
                local problems = Problems(DebindPrivate, DebindStorage, action);
                if (action.key ~= nil and type(action.seq) == "number") then
                    local group = action.key .. "/" .. tostring(action.arrivalID) .. "/" .. action.seq;
                    if (seen[group]) then
                        problems[#problems + 1] = "seq repeats inside its key group";
                    end
                    seen[group] = true;
                end
                for _, problem in ipairs(problems) do
                    frame = frame or SpecFrame();
                    report(("%s, before %s: %s (%s)"):format(frame, where, problem, Describe(action)));
                end
            end
        end
    end
end

--- Puts the net in front of the two calls. `report` is handed each finding once.
function M.Install(DebindPrivate, DebindStorage, report)
    local reported = {};
    local function once(message)
        if (not reported[message]) then
            reported[message] = true;
            report(message);
        end
    end
    for _, name in ipairs({ "UpdateBindings", "SanitizeLoadedLayers" }) do
        local original = DebindPrivate[name];
        DebindPrivate[name] = function(...)
            Sweep(DebindPrivate, DebindStorage, name, once);
            return original(...);
        end;
    end
end

return M;
