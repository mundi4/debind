--- **Every action in the profile has to be one that could be saved or exported at this moment.**
--- The writers keep that shape rather than leaving it to a clean-up. This net looks at every stored
--- list (`EachStoredList`) right before each `UpdateBindings` and each `SanitizeLoadedLayers` (the
--- load, the import at login, the logout), and at what each writer hands `SanitizeWrittenActions`,
--- which is where a writer that relied on the clean-up shows: each test stands its own profile up,
--- so by the end of a spec only the last test's few actions are left to look at.
---
--- **The field tables are the store's** (`ACTION_FIELDS`, `CONDITION_TYPES`, `CASTING_TYPES`), read
--- off Debind's own. The other rules restate the shape here rather than calling
--- `SanitizeAction`, `DropFieldsTheTypeCannotHold` or `Talents.Prune`: a net that called them would
--- agree with whatever they do.
---
--- A test that plants a hand-made value on purpose says so with `ctx.HandMade(action)`, and that
--- action is skipped. One that plants something that is no action at all marks the list holding it
--- the same way, and that list is skipped whole.

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
        -- **A row is a table under a unit the menu lists**, holding only the fields a row stores. An old
        -- scalar row or the old row name `hover` is no version 8 shape (`SanitizeAction` drops both),
        -- so a fixture that still writes one stands for a profile no build has.
        local units = conditions.units;
        if (type(units) == "table") then
            local listed = { ["@"] = true };
            for _, unit in ipairs(DebindPrivate.DebindUI.SORTED_UNIT_LIST) do
                if (unit ~= "none") then
                    listed[unit] = true;
                end
            end
            for unit, row in pairs(units) do
                if (not listed[unit]) then
                    bad("units.%s is not a unit a row is kept for", tostring(unit));
                elseif (type(row) ~= "table") then
                    bad("units.%s is a %s, not a row", tostring(unit), type(row));
                else
                    for k, v in pairs(row) do
                        local expected = Constants.UNIT_CONDITION_FIELDS[k];
                        if (not expected) then
                            bad("units.%s.%s is not a row field", tostring(unit), tostring(k));
                        elseif (not typed(expected, v)) then
                            bad("units.%s.%s is a %s", tostring(unit), k, type(v));
                        end
                    end
                end
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
    if (action.disabled == false) then
        bad("disabled is false, which is stored as none");
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

--- Every stored action list, each once, with where it is. `fn(list, at)` for a list, and
--- `bad(problem, at)` for what stands where a table belongs and is not one.
---
--- **Not only the loaded layers**, because writers reach cells no layer of this session holds: an
--- arrival is placed by the scope it was sent with (`PlaceArrivedActions`), another class's cell
--- included, and a switch rename rewrites every character's pending actions (`ForEachPendingAction`).
--- So: the loaded layers, every cell under `DebindVars.layers`, this character's own while they are
--- not attached yet (lazy creation), and every `pendingActions` share.
---
--- **Walked here rather than through the addon's own walks** (`ForEachStoredList`), for the reason
--- the rules above are restated: a net that walked with the addon would miss what the addon's walk
--- misses, and a fixture that is not a table where one belongs is reported instead of raising.
local function EachStoredList(DebindPrivate, fn, bad)
    local walked = {};
    local function visit(list, at)
        if (type(list) ~= "table") then
            bad(("is a %s, not a list"):format(type(list)), at);
        elseif (not walked[list] and not handMade[list]) then
            walked[list] = true;
            fn(list, at);
        end
    end
    local function visitClasses(classes, at)
        if (type(classes) ~= "table") then
            bad(("is a %s, not a table of classes"):format(type(classes)), at);
            return;
        end
        for class, specTbl in pairs(classes) do
            local classAt = ("%s/%s"):format(at, tostring(class));
            if (type(specTbl) ~= "table") then
                bad(("is a %s, not a table of specializations"):format(type(specTbl)), classAt);
            else
                for spec, list in pairs(specTbl) do
                    visit(list, ("%s/%s"):format(classAt, tostring(spec)));
                end
            end
        end
    end

    -- **Asked through the seam the in-game kit stands its layers behind**, which also passes over a
    -- specialization layer this class does not have instead of stopping at it.
    for layerID, layer in DebindPrivate.EnumerateAllProfileLayers() do
        visit(layer.actions, "layer " .. layerID);
    end

    local db = DebindPrivate.db;
    local global = db and db.global;
    if (type(global) ~= "table") then
        return;
    end
    for owner, classes in pairs(type(global.layers) == "table" and global.layers or {}) do
        visitClasses(classes, "layers/" .. tostring(owner));
    end
    if (db.charLayers ~= nil) then
        visitClasses(db.charLayers, "layers/" .. tostring(DebindPrivate.playerGUID));
    end
    for guid, share in pairs(type(global.pendingActions) == "table" and global.pendingActions or {}) do
        local at = "pendingActions/" .. tostring(guid);
        if (type(share) ~= "table") then
            bad(("is a %s, not a share"):format(type(share)), at);
        else
            if (share.account ~= nil) then
                visitClasses(share.account, at .. "/account");
            end
            if (share.character ~= nil) then
                visitClasses({ character = share.character }, at);
            end
        end
    end
end

--- What is wrong in every stored list, as sentences ending in where it is.
local function Findings(DebindPrivate, DebindStorage)
    local out = {};
    local function bad(problem, at)
        out[#out + 1] = ("%s (at %s)"):format(problem, at);
    end
    EachStoredList(DebindPrivate, function(list, at)
        -- **Positions 1..n are the list.** `#` and `ipairs` are all that read one, so an action under a
        -- name or past a hole is in no list anything reads (`SanitizeActionList` drops it).
        local count, top = 0, 0;
        local seen = {};
        for position, action in pairs(list) do
            if (type(position) ~= "number" or position < 1 or position % 1 ~= 0) then
                bad(("an element under %q, not at a position"):format(tostring(position)), at);
            else
                count = count + 1;
                top = math.max(top, position);
            end
            if (type(action) ~= "table") then
                bad(("[%s] is a %s, not an action"):format(tostring(position), type(action)), at);
            elseif (not handMade[action]) then
                local problems = Problems(DebindPrivate, DebindStorage, action);
                if (action.key ~= nil and type(action.seq) == "number") then
                    local group = action.key .. "/" .. tostring(action.arrivalID) .. "/" .. action.seq;
                    if (seen[group]) then
                        problems[#problems + 1] = "seq repeats inside its key group";
                    end
                    seen[group] = true;
                end
                for _, problem in ipairs(problems) do
                    bad(("%s (%s)"):format(problem, Describe(action)), at);
                end
            end
        end
        if (top ~= count) then
            bad(("a hole: %d elements up to [%d]"):format(count, top), at);
        end
    end, bad);
    return out;
end
M.Findings = Findings;

local function Sweep(DebindPrivate, DebindStorage, where, report)
    local findings = Findings(DebindPrivate, DebindStorage);
    if (#findings > 0) then
        local frame = SpecFrame();
        for _, finding in ipairs(findings) do
            report(("%s, before %s: %s"):format(frame, where, finding));
        end
    end
end

--- Puts the net in front of the three calls. `report` is handed each finding once.
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

    -- **The writers' own entry point sanitizes what it is handed**, so the sweeps above would only
    -- ever meet what it already fixed, and a writer that left a shape nothing stores would pass.
    -- What it is handed is read here first. `ActionsChanged` and the two writers outside the window
    -- (`PlaceArrivedActions`, the switch rename) all hand theirs to this one.
    local sanitizeWritten = DebindPrivate.SanitizeWrittenActions;
    DebindPrivate.SanitizeWrittenActions = function(actions, ...)
        local frame;
        for _, action in ipairs(actions) do
            if (type(action) == "table" and not handMade[action]) then
                for _, problem in ipairs(Problems(DebindPrivate, DebindStorage, action)) do
                    frame = frame or SpecFrame();
                    once(("%s, written: %s (%s)"):format(frame, problem, Describe(action)));
                end
            end
        end
        return sanitizeWritten(actions, ...);
    end;
end

return M;
