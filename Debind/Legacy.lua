--- Pulls in settings that were saved before the addon was renamed from Debounce to Debind.
---
--- A SavedVariables file is named after the addon **folder**. Renaming the folder to `Debind`
--- made the game start reading and writing `Debind.lua`, which leaves the old `Debounce.lua`
--- unreachable in principle - nothing in this addon can open it. So we ship a code-less dummy
--- addon still called `Debounce`; the whole of it is two TOC lines declaring the old globals,
--- and we turn it on with `LoadAddOn` only when we need it.
---
--- ## This file is permanent
---
--- There is no way to prove every character has logged in since the rename, and an alt that has
--- not come back yet still has its data over there. So neither the dummy addon nor this path
--- ever gets deleted. The cost per login is one `migrated[guid]` lookup.
---
--- ## The old globals are read-only
---
--- In a session where the dummy is loaded, WoW **rewrites** `Debounce.lua` on logout. Anything we
--- change in those tables lands on disk, and a user who rolls back to the old addon then finds
--- their data altered. Leave them alone and rolling back works with **no loss at all** - which is
--- why everything below is copied out with `CopyTable`. Plugging in a reference instead would let
--- later edits made in Debind leak back into the old file.

local _, DebindPrivate = ...;

local LEGACY_ADDON     = "Debounce";

--- Copies an old per-spec table (`{[0]=…, [1]=…}`) and brings it up to the current version.
---
--- **Imports arrive carrying their own version.** Raising them before they are attached is what
--- keeps two different versions from ever coexisting inside `characters`/`shared` (see the
--- `MigrateDB` comment in `Profile.lua`).
local function ImportSpecTable(source, dbver)
    if (source == nil) then
        return nil;
    end
    local copy = CopyTable(source);
    DebindPrivate.MigrateSpecTable(copy, dbver);
    return copy;
end

--- Same, for a single layer array. Layer 1 (`GENERAL`) has no specs, so its shape differs.
local function ImportLayer(source, dbver)
    if (source == nil) then
        return nil;
    end
    local copy = CopyTable(source);
    DebindPrivate.MigrateLayer(copy, dbver);
    return copy;
end

--- Top-level keys whose shape we change, or that we drop on purpose. Everything else is carried
--- over untouched.
---
--- This is a deny list rather than an allow list because the import is **one-shot and
--- irreversible**: a key that is not named here is far more likely to be one we *forgot* than one
--- that was meant to be dropped. That is not hypothetical - the first version listed the keys to
--- copy by hand and lost `spellPicker` (the spell picker's per-tab filters) outright, because the
--- list was transcribed from a structure diagram that had already gone stale.
local RESHAPED_KEYS = {
    -- The container changes.
    dbver         = true,
    GENERAL       = true,
    ui            = true,
    spellPickerUI = true,
    -- Already gone from the code - zero references left, so there is nothing to carry it into.
    overviewui    = true,
};

--- Does this layer array hold anything?
local function LayerHasContent(tbl)
    return tbl ~= nil and #tbl > 0;
end

--- Does any spec layer in this per-spec table hold anything?
local function SpecTableHasContent(tbl)
    if (tbl == nil) then
        return false;
    end
    for spec = 0, 5 do
        if (LayerHasContent(tbl[spec])) then
            return true;
        end
    end
    return false;
end

--- The account's share: `DebounceVars` -> `DebindVars.shared` plus the housekeeping tables.
---
--- **Runs exactly once**, guarded by `legacyAccountPulled` - otherwise a second character loading
--- the dummy for its own per-character data would resurrect shared bindings deleted in between.
---
--- ## Nothing here ever replaces something the user already has
---
--- The one-shot guard is not enough on its own, because it only starts counting once the import
--- actually runs. If the dummy is disabled or missing, the import keeps failing (by design - see
--- `ImportLegacySavedVars`), and in the meantime the user can build a complete configuration in
--- Debind. Re-enable the dummy weeks later and an unconditional import would replace all of it
--- with pre-rename data, silently, on a login the user had no reason to treat as special.
---
--- So every destination is checked first and **only empty ones are filled**. That keeps the normal
--- case identical (a fresh `DebindVars` is empty everywhere, so everything comes across) while
--- making the delayed case incapable of destroying anything. Whatever was skipped is reported, so
--- the user is told rather than left to notice.
---
--- This is deliberately not a merge. Merging two populated layers would need a human to say which
--- side wins, and that answer cannot be guessed.
local function ImportAccount(db, old, storedKeys)
    local dbver = old.dbver or 1;
    local skipped = false;

    if (LayerHasContent(old.GENERAL)) then
        if (LayerHasContent(db.shared.GENERAL)) then
            skipped = true;
        else
            db.shared.GENERAL = ImportLayer(old.GENERAL, dbver);
        end
    end

    local isClassKey = {};
    for classId = 1, 20 do
        local classInfo = C_CreatureInfo.GetClassInfo(classId);
        local class = classInfo and classInfo.classFile;
        if (class) then
            isClassKey[class] = true;
            if (SpecTableHasContent(old[class])) then
                if (SpecTableHasContent(db.shared.classes[class])) then
                    skipped = true;
                else
                    db.shared.classes[class] = ImportSpecTable(old[class], dbver);
                end
            end
        end
    end

    -- Window positions were folded into one table. Not worth reporting when skipped - losing a
    -- remembered window position costs the user one drag.
    if (db.ui == nil) then
        local ui = {};
        if (old.ui and old.ui.anchorPos) then
            ui.main = CopyTable(old.ui.anchorPos);
        end
        if (old.spellPickerUI and old.spellPickerUI.pos) then
            ui.spellPicker = CopyTable(old.spellPickerUI.pos);
        end
        if (next(ui) ~= nil) then
            db.ui = ui;
        end
    end

    -- Everything else verbatim: `options`, `customStates`, `spellPicker`, and whatever anyone adds
    -- after this was written.
    --
    -- The test is `storedKeys` rather than `db[key] == nil` because `InitDB` synthesizes defaults
    -- for `options` and `customStates` before this ever runs, so they are never nil. What we need
    -- to know is whether the **saved file** had them.
    for key, value in pairs(old) do
        if (not RESHAPED_KEYS[key] and not isClassKey[key]) then
            if (storedKeys[key]) then
                skipped = true;
            else
                db[key] = (type(value) == "table") and CopyTable(value) or value;
            end
        end
    end

    return skipped;
end

--- This character's share: `DebounceVarsPerChar` -> `DebindVars.characters[guid]`.
---
--- Note that nothing is written into `characters[guid]` here. Whether the entry gets attached at
--- all is decided by `CleanUpDB` from its contents (lazy creation), so an alt that never used a
--- character-specific binding - and therefore has only empty tables in the old file - still ends
--- up with no entry.
--- Same rule as `ImportAccount`: fill only what is empty, per layer. A character that has been
--- played in Debind while the dummy was unavailable keeps everything it has.
local function ImportCharacter(charEntry, old)
    local dbver = old.dbver or 1;
    local skipped = false;

    local layers = ImportSpecTable(old, dbver);
    if (layers) then
        for spec = 0, 5 do
            if (LayerHasContent(layers[spec])) then
                if (LayerHasContent(charEntry.layers[spec])) then
                    skipped = true;
                else
                    charEntry.layers[spec] = layers[spec];
                end
            end
        end
    end

    if (old.CustomTargets and next(old.CustomTargets) ~= nil) then
        if (charEntry.CustomTargets and next(charEntry.CustomTargets) ~= nil) then
            skipped = true;
        else
            charEntry.CustomTargets = CopyTable(old.CustomTargets);
        end
    end

    return skipped;
end

--- Called **synchronously** at the very top of PLAYER_LOGIN.
---
--- Why it must not be late is spelled out on `ACTIVE_PLAYER_SPECIALIZATION_CHANGED` in
--- `Events.lua`: bindings have to be up in the same tick as PLAYER_LOGIN for the addon to survive
--- a reconnect into a boss encounter. So this path has **no `C_Timer`, no waiting on an event, and
--- no retry**.
---
--- And **failure has no right to delay bindings.** If the dummy is disabled, `LoadAddOn` answers
--- `DISABLED`; we record nothing and fall straight through. Going one session without the old data
--- beats going a whole encounter without bindings, and since no flag was set it is retried on the
--- next login.
function DebindPrivate.ImportLegacySavedVars()
    local db = DebindPrivate.db.global;
    local guid = DebindPrivate.playerGUID;

    if (not guid or db.migrated[guid]) then
        return false;
    end

    local loaded, reason = C_AddOns.LoadAddOn(LEGACY_ADDON);
    if (not loaded) then
        DebindPrivate.legacyLoadFailure = reason or "UNKNOWN";
        return false;
    end

    local changed = false;
    local skipped = false;

    if (not db.legacyAccountPulled) then
        local old = _G.DebounceVars;
        if (old) then
            skipped = ImportAccount(db, old, DebindPrivate.storedTopLevelKeys or {}) or skipped;
            changed = true;
        end
        db.legacyAccountPulled = true;
    end

    local oldChar = _G.DebounceVarsPerChar;
    if (oldChar) then
        skipped = ImportCharacter(DebindPrivate.db.char, oldChar) or skipped;
        changed = true;
    end

    db.migrated[guid] = true;
    DebindPrivate.legacySkipped = skipped;
    return changed;
end

--- Is the old real addon still installed?
---
--- The packager overwrites the `Debounce/` folder with the dummy, but a manual install or another
--- client may not. Then **two real addons run at once and fight over the same keys.** Only the old
--- one puts `Debounce_CompartmentFunc` in the global namespace - we renamed ours to `Debind_` - so
--- that single global tells them apart.
---
--- Call this after the first `UpdateBindings`. The warning must never come before the bindings.
function DebindPrivate.CheckLegacyAddonConflict()
    return _G.Debounce_CompartmentFunc ~= nil;
end

DebindPrivate.LEGACY_ADDON_NAME = LEGACY_ADDON;
