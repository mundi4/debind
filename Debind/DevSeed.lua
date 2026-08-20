local _, DebindPrivate = ...;
local Constants        = DebindPrivate.Constants;

--- **A file that only exists in a development build.** Its TOC line sits inside `#@debug@` and
--- `.pkgmeta`'s `ignore` list keeps the file itself out of the staging copy. `DevStamp.lua` stands
--- in the same place, with one difference that decides the second half: that one is a gitignored
--- artefact, and this is committed source, so the TOC line alone would not be enough to keep it
--- out of a release.
---
--- What it is for: a client with no usable profile. Two of those, and they are the same shape. An
--- empty client, where what is missing is a designed set of bindings covering the places
--- `/debtest` cannot look (overview rows, all five layer tiers, menus, badges, tooltips). And a
--- worktree cut from an older release, where the client's profile was written by a newer build and
--- this one cannot read it.
---
--- **The seed is written, not captured.** No real name and no real GUID goes in, which is the
--- whole reason it can be committed at all.
---
--- `devdocs/setting-up-a-dev-profile.md`.

--- One builder per `dbver`. **When `dbver` goes up, add the new one and leave the old ones where
--- they are.** A given worktree only ever calls the one matching its own `Constants.DB_VERSION`;
--- carrying all of them is what makes this file right wherever it is copied, so no worktree ever
--- has to be checked against its seed.

--- Every macrotext row below carries one, because **an action with no icon is a shape the addon
--- cannot otherwise produce**: the only way to make one is [New Custom Macro], and that goes through
--- the icon selector, which always hands back a texture. A seeded row without one came up blank in
--- the name/icon editor and looked like a bug in that window.
local QUESTION_MARK_ICON = 134400;

local SEEDS = {};

--- Everything here is class independent on purpose. A PTR client is whatever character happens to
--- exist on it, and a seed that named class spells would come up as a screen full of red rows on
--- most of them. `Constants.SPELL` is left out for the same reason and nothing is lost: what these
--- rows are for is the window, not the cast.
---
--- The keys are the shifted function row, which is where a PTR character has nothing of its own.
SEEDS[5] = function(guid)
    local CLASS = Constants.PLAYER_CLASS;
    local HEARTHSTONE = 6948;

    return {
        dbver = 5,

        shared = {
            --- The account layer carries the states that only show up on a row: two actions on one
            --- key, an action naming a macro that is not there, one still waiting to be accepted,
            --- and one carrying enough conditions to fill a tooltip.
            GENERAL = {
                { type = Constants.ITEM, value = HEARTHSTONE, key = "SHIFT-F1", seq = 1 },
                { type = Constants.MACROTEXT, icon = QUESTION_MARK_ICON,
                    value = "/say account", name = "Say account",
                    key = "SHIFT-F2", seq = 1 },
                -- Two on one key, so the overview has a group to order and the ordering menu has
                -- something to move.
                { type = Constants.WORLDMARKER, value = 1, key = "SHIFT-F3", seq = 1 },
                { type = Constants.WORLDMARKER, value = 2, key = "SHIFT-F3", seq = 2 },
                -- The issue badge: a `MACRO` naming one that does not exist is left out of the
                -- build entirely and the row says so (`Events.lua`'s UPDATE_MACROS comment).
                { type = Constants.MACRO, value = "DebindNoSuchMacro", key = "SHIFT-F4", seq = 1 },
                -- The quarantine badge. `imported` holding a string is an action that arrived from
                -- somebody else on that key and has not been accepted yet (`Profile.lua`'s
                -- `KEYS_TO_SAVE`), so it reaches no key until the reader says yes.
                { type = Constants.ITEM, value = HEARTHSTONE, key = "SHIFT-F5", seq = 1,
                    imported = "CTRL-Q" },
                { type = Constants.SETCUSTOM, value = 1, key = "SHIFT-F6", seq = 1 },
                -- Click casting, so the unit column and the frame menu have a row to describe.
                { type = Constants.MACROTEXT, icon = QUESTION_MARK_ICON,
                    value = "/say hovered", name = "Say hovered",
                    key = "SHIFT-F7", seq = 1,
                    checkedUnits = { hover = { reaction = Constants.REACTION_HELP } } },
                -- Enough conditions on one action that its tooltip has to lay several out at once.
                { type = Constants.ITEM, value = HEARTHSTONE, key = "SHIFT-F8", seq = 1,
                    combat = true, groups = Constants.GROUP_PARTY,
                    priority = Constants.MAX_PRIORITY, ["$state1"] = true },
            },

            --- The class tiers. `SHIFT-F1` is deliberately the account layer's key as well, so the
            --- overview has a row where a narrower layer wins and the wider one is shown losing.
            classes = {
                [CLASS] = {
                    [0] = {
                        { type = Constants.MACROTEXT, icon = QUESTION_MARK_ICON,
                            value = "/say class", name = "Say class",
                            key = "SHIFT-F1", seq = 1 },
                    },
                    -- Specs 1 and 2 only: every class has at least two, and no class has the same
                    -- number as every other.
                    [1] = {
                        { type = Constants.MACROTEXT, icon = QUESTION_MARK_ICON,
                            value = "/say spec one", name = "Say spec one",
                            key = "SHIFT-F2", seq = 1 },
                    },
                    [2] = {
                        { type = Constants.MACROTEXT, icon = QUESTION_MARK_ICON,
                            value = "/say spec two", name = "Say spec two",
                            key = "SHIFT-F2", seq = 1 },
                    },
                },
            },
        },

        --- **The GUID is read when the seed is planted, never carried in the file.** ptr and xptr
        --- hold different characters with different GUIDs and either can be deleted without anyone
        --- being surprised, so a GUID written into a seed would only ever sit there unreachable.
        --- Planting is inside the addon, where the GUID is available, so the two character tiers
        --- can be filled after all.
        characters = {
            [guid] = {
                layers = {
                    [0] = {
                        { type = Constants.MACROTEXT, icon = QUESTION_MARK_ICON,
                            value = "/say character",
                            name = "Say character", key = "SHIFT-F3", seq = 1 },
                    },
                    [1] = {
                        { type = Constants.MACROTEXT, icon = QUESTION_MARK_ICON,
                            value = "/say character spec one",
                            name = "Say character spec one", key = "SHIFT-F4", seq = 1 },
                    },
                },
            },
        },

        --- **Answered, so the pre-rename question never comes up on a seeded client.** `false` is
        --- the value a fresh install reaches on its own first login (`Legacy.lua`), and without it
        --- the overlay would stand in front of the window this seed exists to look at.
        migrated = { [guid] = true },
        legacyNeeded = false,

        options = {
            unitframeUseMouseDown = true,
            addCustomTargetMenusToUnitPopup = true,
            blizzframes = {},
        },

        --- Two of the five set up differently, so the custom-state screen has both modes on it and
        --- `$state1` above has something to point at. The other three come up as defaults from
        --- `BindDerivedTables`.
        customStates = {
            [1] = { mode = Constants.CUSTOM_STATE_MODES.MANUAL, initialValue = true,
                displayMessage = true },
            [2] = { mode = Constants.CUSTOM_STATE_MODES.MACRO_CONDITIONAL, expr = "[combat]" },
        },
    };
end;

--- The profile for one `dbver`, built from code. **Built rather than read**, because the case this
--- has to stand up in is a client whose saved profile cannot be touched and whose disk holds
--- nothing else we could use.
function DebindPrivate.MakeSeed(dbver)
    local build = SEEDS[dbver];
    if (not build) then
        error(format("DevSeed: no seed written for dbver %s", tostring(dbver)));
    end
    return build(UnitGUID("player"));
end

--- Called at the head of `InitDB`, and it answers three things at once. Returns the table to carry
--- on with, which is the one it was handed unless a seed went in.
---
--- **The forced case is the one that matters.** With the addon at `dbver` 5 and the client's
--- profile at 6 there is no command to type, because typing one means being logged in and that
--- login is the problem. So the decision is made at load time, and it has to stand up with nothing
--- on disk at all.
---
--- **No reload needed.** This is load time: `_G.DebindVars` is what came off disk and nobody has
--- taken hold of it yet, so replacing it here means `MigrateDB` through `CleanUpDB` run as though
--- this had always been the data. That is exactly why the command below reloads instead of
--- planting the seed where it was typed.
---
--- **The displaced profile is not parked anywhere.** The seed lives in code and comes back on
--- demand, so there is nothing to lose by dropping it.
function DebindPrivate.ApplyDevSeed(db)
    local dev = _G.DebindDevVars;
    if (not dev) then
        dev = {};
        _G.DebindDevVars = dev;
    end

    local reason;
    if (dev.seedPending) then
        dev.seedPending = nil;
        reason = "asked for";
    elseif (db.dbver == nil) then
        reason = "nothing saved yet";
    elseif (db.dbver > Constants.DB_VERSION) then
        reason = "what is saved is newer than this build";
    else
        return db;
    end

    db = DebindPrivate.MakeSeed(Constants.DB_VERSION);
    _G.DebindVars = db;
    -- A plain literal, not `L[...]`. Locale files are shipped and this sentence is not.
    DebindPrivate.DisplayMessage(format("Development seed planted (%s).", reason));
    return db;
end

--- `/deb seed`. Returns whether this call handled the command.
---
--- **The confirmation comes before the flag is set**, because that is the step that cannot be
--- taken back: what the flag costs on the next login is whatever the client had.
function DebindPrivate.HandleDevSeedCommand(chunks)
    if (chunks[1] ~= "seed") then
        return false;
    end

    StaticPopup_ShowCustomGenericConfirmation({
        text = "Replace this account's Debind settings with the development seed?|n|nWhat is there now is deleted and cannot be brought back.",
        callback = function()
            local dev = _G.DebindDevVars;
            if (not dev) then
                dev = {};
                _G.DebindDevVars = dev;
            end
            dev.seedPending = true;
            ReloadUI();
        end,
        acceptText = YES,
        cancelText = NO,
        showAlert = true,
        referenceKey = "DebindDevSeed",
    });
    return true;
end
