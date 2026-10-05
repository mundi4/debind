--- Brings across settings that were saved before the addon was renamed from Debounce to Debind.
---
--- A SavedVariables file is named after the addon **folder**. Renaming the folder to `Debind` made
--- the game start reading and writing `Debind.lua`, which leaves the old `Debounce.lua` unreachable
--- in principle. So we ship a code-less dummy addon still called `Debounce`; the whole of it is two
--- TOC lines declaring the old globals, and we load it on demand.
---
--- ## Three states, and only one of them is a question
---
--- `legacyNeeded` is the account's answer to "is there anything to bring across at all":
---
---   nil    - we have never managed to look. The dummy has not loaded once.
---   false  - there is nothing, and there never will be. Nothing below ever runs again.
---   true   - there is. Each character brings its own share the first time it logs in.
---
--- `false` is the resting state, and a fresh install reaches it on its first login: the dummy loads,
--- `DebounceVars` is absent, and that settles it for every character including ones not yet created.
--- The other way to reach it is the user saying they do not want the old settings - **the same
--- value, so from then on the code cannot tell the two apart, and does not need to.**
---
--- Note what `true` does *not* become: there is no "finished". We cannot prove every character has
--- logged in since the update, so a migrated account keeps checking one character at a time, for as
--- long as it exists. That is one `LoadAddOn` per character, ever.
---
--- ## Nothing here decides anything on the user's behalf
---
--- When the companion is unavailable this file does nothing at all - it does not guess, does not
--- import half of something, and does not warn. A dialog asks instead, and the main window stays
--- shut until the user answers (`DebindUI.lua`, `DebindPublic:ToggleUI`).
---
--- That is what lets the import below be unconditional: bindings can only be made through the main
--- window, so if it never opens with the question open, "the user already built something here"
--- cannot arise.
---
--- **The question that has to be settled is the account one**, not this character's. A per-character
--- "no" leaves `legacyNeeded` at nil, and the account share is account-wide - answer only for
--- yourself, build a shared config, and the next character to resolve the account would import
--- straight over it. So the dialog offers the per-character answer only once the account share has
--- already come across (`IsLegacyAccountResolved`).
---
--- ## The old globals are read-only
---
--- In a session where the dummy is loaded, WoW **rewrites** `Debounce.lua` on logout. Anything we
--- change in those tables lands on disk, and a user who rolls back to the old addon then finds
--- their data altered. Leave them alone and rolling back works with no loss at all - which is why
--- everything below is copied out with `CopyTable`.

local _, DebindPrivate = ...;

local Constants        = DebindPrivate.Constants;

local LEGACY_ADDON     = "Debounce";

--- The addon's own click targets were renamed along with the addon, and **the old names are sitting
--- inside users' saved macros.** "Convert to a Custom Macro" writes the frame name into the macro
--- body (`/click DebounceCustom1 hover`, `/click DebounceStates $state1-on` before the rename), so
--- an action converted before the rename now clicks a frame that does not exist. Nothing errors -
--- the key just stops doing anything, which is the one outcome this whole file exists to prevent.
---
--- Rewritten on the way in rather than papered over with alias frames: the old names have no reason
--- to exist in a running client, and 3.1 is the first release carrying the new ones, so every macro
--- body that could hold an old name passes through here exactly once.
---
--- **To the names the rename gave them, and before the ladder.** Those are the names of the shape
--- this file knows, and a later rename of a frame is a ladder step that carries them on from there.
--- Repaired after the ladder, a body would come out holding the rename's name and miss every step
--- after it.
---
--- **A substring rewrite, not a whole-body match.** The generated bodies are only the common case -
--- the same `/click` line can be typed by hand into a Custom Macro, or pasted next to other lines,
--- and those deserve the same repair.
local LEGACY_CLICK_TARGETS = {
    { "DebounceCustom", "DebindCustom" },
    { "DebounceStates", "DebindStates" },
};

local function RepairLegacyClickTargets(layerTbl)
    if (layerTbl == nil) then
        return;
    end
    for i = 1, #layerTbl do
        local action = layerTbl[i];
        if (action and action.type == Constants.MACROTEXT and type(action.value) == "string") then
            for j = 1, #LEGACY_CLICK_TARGETS do
                local old, new = LEGACY_CLICK_TARGETS[j][1], LEGACY_CLICK_TARGETS[j][2];
                action.value = action.value:gsub(old, new);
            end
        end
    end
end

--- ## The old data rides the whole ladder
---
--- Each share is laid out the way `DebindVars` stood at the rename, stamped with the `dbver` the old
--- file carries, and handed to `MigrateDB` like any stored profile. **This file knows that one
--- shape and nothing later.** It used to call single steps of the ladder by hand, and every change
--- to the stored shape left one of them missing here until somebody noticed (`options` and the
--- switch definitions both arrived that way). Now a change goes into the ladder and reaches this
--- path with nothing to remember.
---
--- **What is taken is the pre-rename addon's own keys and nothing else.** Its last build wrote
--- `GENERAL`, one spec table per class, `customStates`, `options`, `ui`, `spellPickerUI` and
--- `spellPicker` on the account and spec tables plus `CustomTargets` on the character. The three
--- that only the window read (window positions and the picker's filters) are left behind with
--- anything else in those files: they cost a drag and a click to set again, and a key the old
--- addon never wrote was never ours to read.

--- A copy of spec 0..5 of an old spec table, its click targets repaired, or nil when there is none.
local function CopySpecTable(source)
    if (type(source) ~= "table") then
        return nil;
    end
    local copy = {};
    for spec = 0, 5 do
        if (type(source[spec]) == "table") then
            copy[spec] = CopyTable(source[spec]);
            RepairLegacyClickTargets(copy[spec]);
        end
    end
    return copy;
end

--- `db.layers[owner]`, made on the way down.
local function OwnerLayersOf(db, owner)
    db.layers[owner] = db.layers[owner] or {};
    return db.layers[owner];
end

--- Lays each spec list of `from` (`class -> spec -> actions`) over the same place in `into`. A spec
--- the old file did not carry is left as it is.
local function MergeLayers(into, from)
    for class, specTbl in pairs(from or {}) do
        into[class] = into[class] or {};
        for spec = 0, 5 do
            if (specTbl[spec]) then
                into[class][spec] = specTbl[spec];
            end
        end
    end
end

--- The account's share, raised: `DebounceVars` laid out as a rename-era profile and run through
--- `MigrateDB`.
---
--- **Runs exactly once**, guarded by `legacyAccountPulled` - otherwise a second character loading
--- the dummy for its own per-character data would resurrect shared bindings deleted in between.
---
--- **The profile holds the old file and nothing live.** Every step of the ladder reads one version's
--- shape, and a live table in there would be the current one. What the old file carries is joined
--- to the live tables after the ladder, below, and only when the ladder reached the end. Returns
--- whether it did.
local function ImportAccount(db, old)
    local classes = {};
    for class in pairs(Constants.CLASS_IDS) do
        classes[class] = CopySpecTable(old[class]);
    end

    local general = type(old.GENERAL) == "table" and CopyTable(old.GENERAL) or nil;
    RepairLegacyClickTargets(general);

    local profile = {
        dbver = old.dbver or 1,
        shared = {
            GENERAL = general,
            classes = classes,
        },
        customStates = type(old.customStates) == "table" and CopyTable(old.customStates) or nil,
        options = type(old.options) == "table" and CopyTable(old.options) or nil,
    };
    if (not DebindPrivate.TryMigrateDB(profile)) then
        return false;
    end

    -- **Only what the old file had.** The ladder makes some tables whether or not there was
    -- anything to raise (`layers.account`, `options`), so what is laid down is asked of the old
    -- file, one layer at a time, and what it did not carry leaves the live one where it is.
    MergeLayers(OwnerLayersOf(db, "account"), profile.layers.account);
    if (type(old.customStates) == "table") then
        db.switches = profile.switches;
    end
    if (type(old.options) == "table") then
        db.options = profile.options;
    end
    -- **The higher of the two.** The ladder stamps every badge in old data as arrival 1 and sets
    -- its own counter past it; the live one may still be at 1 on a profile made this session.
    db.nextArrivalID = max(db.nextArrivalID or 1, profile.nextArrivalID or 1);
    return true;
end

--- This character's share, raised the same way: `DebounceVarsPerChar` as a rename-era entry, with
--- the class of the character logging in, which is whose file it is.
---
--- Nothing is written into `characters` or `layers` here. Whether the layers get attached is
--- decided by `CleanUpDB` from their contents (lazy creation), so an alt that never used a
--- character-specific binding - and therefore has only empty tables in the old file - still ends up
--- with no layers. Returns whether the ladder reached the end, as `ImportAccount` does.
local function ImportCharacter(old)
    local guid = DebindPrivate.playerGUID;
    local entry = {
        class = Constants.PLAYER_CLASS,
        layers = CopySpecTable(old),
        CustomTargets = type(old.CustomTargets) == "table" and CopyTable(old.CustomTargets) or nil,
    };
    local profile = { dbver = old.dbver or 1, characters = { [guid] = entry } };
    if (not DebindPrivate.TryMigrateDB(profile)) then
        return false;
    end

    MergeLayers(DebindPrivate.db.charLayers, profile.layers[guid]);
    local targets = profile.states and profile.states[guid] and profile.states[guid].CustomTargets;

    -- **Layers can be attached unconditionally; custom targets cannot.** The file header's argument
    -- for an unconditional import is that bindings can only be made through the main window, and the
    -- window stays shut until the question is answered. Custom targets are the one thing that does
    -- not go through it - `DebindPublic:SetCustomTarget` and the unit popup both write without it.
    --
    -- The gap is narrow: the import runs at login, so it only opens when the companion failed to
    -- load and the user played on anyway. Narrow is not none, and an overwrite here is silent and
    -- unrecoverable, so the newer value wins.
    local state = DebindPrivate.db.charState;
    if (targets and state.CustomTargets == nil) then
        state.CustomTargets = targets;
    end
    return true;
end

--- Is there still something for **this character** to answer or bring across?
---
--- `false` is the resting state and short-circuits everything. Otherwise the character is done only
--- once its own flag is set - which, in the `nil` case, has not happened and cannot happen yet.
function DebindPrivate.IsLegacyPending()
    local db = DebindPrivate.db and DebindPrivate.db.global;
    local guid = DebindPrivate.playerGUID;
    if (not db or not guid or db.legacyNeeded == false) then
        return false;
    end
    return not db.migrated[guid];
end

--- 계정 몫이 이미 넘어온 상태인가.
---
--- `legacyNeeded`가 `true`라는 것은 **`DebounceVars`를 실제로 봤다**는 뜻이고, 그 판정과 계정
--- 몫 인수는 같은 호출 안에서 일어난다. 그래서 이 둘이 같이 참이면 공유 레이어는 이미 여기 있다.
---
--- 다이얼로그가 무슨 말을 할지, 그리고 **"이 캐릭터만"이라는 답이 성립하는지**가 여기서 갈린다.
function DebindPrivate.IsLegacyAccountResolved()
    local db = DebindPrivate.db.global;
    return db.legacyNeeded == true and db.legacyAccountPulled == true;
end

--- Runs at login. Does the whole job when it can, and **nothing at all when it cannot**.
---
--- Returns true when something was brought across, so the caller knows to rebuild.
function DebindPrivate.RunLegacyMigration()
    local db = DebindPrivate.db.global;
    local guid = DebindPrivate.playerGUID;

    if (not guid or not DebindPrivate.IsLegacyPending()) then
        return false;
    end

    local loaded, reason = C_AddOns.LoadAddOn(LEGACY_ADDON);
    if (not loaded) then
        -- Leave every flag exactly as it is. `nil` stays `nil`, an unmigrated character stays
        -- unmigrated, and the dialog asks the user.
        --
        -- **The reason matters to the dialog.** "DISABLED" can be fixed by a button; a folder that
        -- is not there at all cannot, and offering to switch it on would reload straight back into
        -- the same window.
        DebindPrivate.legacyLoadFailure = reason;
        DebindPrivate.log("[legacy] companion unavailable:", tostring(reason));
        return false;
    end
    DebindPrivate.legacyLoadFailure = nil;
    DebindPrivate.legacyImportFailed = nil;

    if (db.legacyNeeded == nil) then
        -- **`DebounceVars` only.** Every version that could have written a per-character file
        -- created this one too, on its first run, unconditionally - so its absence means this
        -- account never ran an older version at all. Keying off both would let `legacyNeeded`
        -- become true with no account share to pull, and then `legacyAccountPulled` would latch
        -- anyway and the dialog would tell people their shared bindings had already moved when
        -- nothing shared ever existed.
        db.legacyNeeded = _G.DebounceVars ~= nil;
        DebindPrivate.log("[legacy] determined legacyNeeded =", db.legacyNeeded);
        if (not db.legacyNeeded) then
            return false;
        end
    end

    local changed = false;

    -- **A share whose ladder failed leaves its flag down**, so the next login brings it across
    -- again with whatever build fixed the step. Nothing of it was joined (`TryMigrateDB`), and the
    -- dialog says that rather than calling the companion unreachable (`legacyImportFailed`).
    if (not db.legacyAccountPulled) then
        local old = _G.DebounceVars;
        if (old) then
            if (not ImportAccount(db, old)) then
                DebindPrivate.legacyImportFailed = true;
                return false;
            end
            changed = true;
        end
        db.legacyAccountPulled = true;
    end

    local oldChar = _G.DebounceVarsPerChar;
    if (oldChar) then
        if (not ImportCharacter(oldChar)) then
            DebindPrivate.legacyImportFailed = true;
            return changed;
        end
        changed = true;
    end

    db.migrated[guid] = true;
    DebindPrivate.log("[legacy] imported for", guid, "changed:", changed);
    return changed;
end

--- The user answered "I don't need them" in the window's overlay.
---
--- Recorded as `false`, the **same value a fresh install reaches on its first login**. There is no
--- separate "declined" state: from here on this account is simply not a migration target, and every
--- character - including ones created later - takes the same path a new installation does.
---
--- It is account-wide on purpose. The shared layers are account-wide, so a per-character "no" would
--- leave the next character free to import over what this one built. Nothing is lost either way:
--- the old file is never written to, so it stays on disk exactly as it was.
function DebindPrivate.DeclineLegacyMigration()
    DebindPrivate.db.global.legacyNeeded = false;
    DebindPrivate.log("[legacy] declined for the account");
end

--- The user answered "not on this character".
---
--- A separate answer exists because **an addon is enabled per character.** Turning the companion
--- back on covers the whole account, but it can be switched off again for one character, or ahead
--- of time for one that has not logged in yet - so "I deliberately do not want the old settings
--- here" is a real position, and without a way to say it that character is asked every login.
---
--- Only this character's own share is refused. The shared layers are account-wide and stay that
--- way: if another character brings them across later, they apply here too. That is what shared
--- means, and no per-character answer can change it.
--- **계정 질문이 이미 끝난 뒤에만 뜻이 있다.** 아직 `nil`이면 이 답은 계정 몫을 미결로 둔 채
--- 창만 열어주고, 그러면 사용자가 만든 공유 바인딩을 나중에 다른 캐릭터의 인수가 덮는다.
--- 그래서 다이얼로그는 그 상태에서 이 버튼을 아예 안 보여준다(`UpdateText`).
function DebindPrivate.DeclineLegacyMigrationForCharacter()
    local guid = DebindPrivate.playerGUID;
    if (not guid) then
        return;
    end
    DebindPrivate.db.global.migrated[guid] = true;
    DebindPrivate.log("[legacy] declined for", guid);
end

--- Turn the dummy addon back on for the user, then reload so it is there on the next pass.
---
--- `EnableAddOn` is what Blizzard's own addon list calls, and it does not take effect until the UI
--- reloads - which is why this does both rather than asking the user to go and find it.
function DebindPrivate.EnableLegacyAddonAndReload()
    C_AddOns.EnableAddOn(LEGACY_ADDON);
    ReloadUI();
end

--- Is the old real addon still installed?
---
--- The packager overwrites the `Debounce/` folder with the dummy, but a manual install or another
--- client may not. Then **two real addons run at once and fight over the same keys.** Only the old
--- one puts `Debounce_CompartmentFunc` in the global namespace - we renamed ours to `Debind_` - so
--- that single global tells them apart.
function DebindPrivate.CheckLegacyAddonConflict()
    return _G.Debounce_CompartmentFunc ~= nil;
end


DebindPrivate.LEGACY_ADDON_NAME = LEGACY_ADDON;
