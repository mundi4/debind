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
--- `devdocs/legacy/setting-up-a-dev-profile.md`.

--- One builder per `dbver`. **When `dbver` goes up, add the new one and leave the old ones where
--- they are.** Carrying all of them is what makes this file right wherever it is copied, so no
--- worktree ever has to be checked against its seed. It is also what `/deb seed <dbver>` picks
--- from: an old builder plants what an upgrading user brings, and one newer than this build plants
--- what a downgrading user brings.

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
--- The keys are the shifted and control function rows, which is where a PTR character has nothing
--- of its own. Five rows carry no real key: two share a synthetic number with a badge, two share one
--- without, and one has no key at all - the three shapes `dbver` 5 could hold, and what the step
--- that raises it has to tell apart.
SEEDS[5] = function(guid)
    local CLASS = Constants.PLAYER_CLASS;
    local HEARTHSTONE = 6948;

    return {
        dbver = 5,

        shared = {
            --- **The account layer is where the coverage lives**, and it is filled by walking three
            --- lists rather than by taste: every action type the picker can hand out, every field in
            --- `KEYS_TO_SAVE`, and every name `Constants.IsConditionField` answers yes to. A row
            --- goes in for anything none of the rows above it already reaches.
            ---
            --- Four of those are left out on purpose and each has a reason that is not "forgot":
            ---
            ---   * `SPELL`, `FLYOUT`, `PETACTION` name something a class has. Seeded, they come up
            ---     as red rows on every character that is not that class, which is the one thing
            ---     this seed exists to avoid.
            ---   * `known` is dropped on anything that is not a `SPELL` (`Misc.lua`), so it cannot
            ---     be reached from here at all while `SPELL` is out.
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
                --- The quarantine badge as `dbver` 5 wrote it, and **this shape is why this builder
                --- is kept.** Back then an arriving set was renamed onto a number of ours and the
                --- sender's key was carried in `imported`; the step that raises 5 puts the key back
                --- and turns the badge into an arrival number (`Profile.lua`,
                --- `devdocs/building-export-import.md` 12절). Seeding 5 is what runs that step, so
                --- **the old field names are spelled out here on purpose** and nothing in this
                --- builder follows a rename made elsewhere.
                ---
                --- Two of them on the one number, because what the heading names is a **set**.
                ---
                --- **The counter is deliberately left out.** A profile with numbers in it and no
                --- counter is exactly the case the migration has to answer, and writing one here
                --- would step around it.
                { type = Constants.ITEM, value = HEARTHSTONE, key = 1, seq = 1,
                    imported = "CTRL-Q" },
                { type = Constants.MACROTEXT, icon = QUESTION_MARK_ICON,
                    value = "/say arrived", name = "Say arrived", key = 1, seq = 2,
                    imported = "CTRL-Q" },
                --- The other arrival shape 5 could hold: the sender left it on no key at all, so
                --- there was no key to move aside and the badge is `true`. **No key, no `seq`.**
                { type = Constants.MACROTEXT, icon = QUESTION_MARK_ICON,
                    value = "/say unplaced", name = "Say unplaced", imported = true },
                --- A set the reader unbound whole: a synthetic key **and no badge**, which is what
                --- tells it from the two above. The step turns this one into two keyless actions
                --- rather than into an arrival, and that difference is the whole of what it has to
                --- get right.
                { type = Constants.WORLDMARKER, value = 3, key = 2, seq = 1 },
                { type = Constants.WORLDMARKER, value = 4, key = 2, seq = 2 },
                { type = Constants.SETCUSTOM, value = 1, key = "SHIFT-F6", seq = 1 },
                --- Click casting, so the frame menu and the hover half of the tooltip have a row.
                --- Three fields ride along here because this is the only row they can sit on: the
                --- menu enables `ignoreHoverUnit` and the frame-type boxes only while a hover
                --- condition is on (`DropDownMenus.lua`), and `GetBindingInfoForAction` drops
                --- both outright on a binding that does not hover.
                ---
                --- `frameTypes` is short of every bit on purpose - all-on is normalised back to
                --- nil, so a full mask would draw no line at all. `dead` is the life axis, and
                --- `false` is its "alive" answer.
                { type = Constants.MACROTEXT, icon = QUESTION_MARK_ICON,
                    value = "/say hovered", name = "Say hovered",
                    key = "SHIFT-F7", seq = 1, ignoreHoverUnit = true,
                    frameTypes = Constants.FRAMETYPE_PLAYER + Constants.FRAMETYPE_GROUP,
                    checkedUnits = { hover = { reaction = Constants.REACTION_HELP, dead = false } } },
                -- Enough conditions on one action that its tooltip has to lay several out at once.
                { type = Constants.ITEM, value = HEARTHSTONE, key = "SHIFT-F8", seq = 1,
                    combat = true, groups = Constants.GROUP_PARTY,
                    priority = Constants.MAX_PRIORITY, ["$state1"] = true },
                --- **The target, which is `action.unit` and not a condition.** Without one of
                --- these the row's `@unit` suffix, the tooltip's target line and the target menu
                --- are all unreachable in a seeded profile. `TARGET` is used because it takes a
                --- unit and names no spell, so it stays class independent like everything else
                --- here.
                { type = Constants.TARGET, unit = "focus", key = "SHIFT-F9", seq = 1 },
                --- Target and the `"@"` unit condition on one action, which is a tooltip line of
                --- its own: `"@"` is drawn as `SELECTED_TARGET_UNIT` and that branch asks for
                --- `action.unit` (`ActionTooltip.lua`), so neither row above can reach it alone. The
                --- unit has to be one that can be absent, since `"@"` is dropped again on `none`
                --- and on `player` (`Misc.lua`).
                { type = Constants.ITEM, value = HEARTHSTONE, unit = "target",
                    key = "SHIFT-F10", seq = 1, checkedUnits = { ["@"] = {} } },
                -- The binding-context exception: this key stays bound while an editor holds it
                -- (`Debind.lua`'s `IsKeyYielded`).
                { type = Constants.MACROTEXT, icon = QUESTION_MARK_ICON,
                    value = "/say kept", name = "Say kept",
                    key = "SHIFT-F11", seq = 1, keepInBindingContext = true },
                --- Mount, on the one value that resolves for every character alive: `0` is the
                --- random favourite, drawn from a spell rather than the journal
                --- (`ActionDisplay.lua`), so a client with nothing collected still gets a name and an
                --- icon. A real `mountID` would be a red row on any character that has not
                --- learned it.
                { type = Constants.MOUNT, value = 0, key = "SHIFT-F12", seq = 1 },
                --- The remaining two types that take a unit. Both come off the command tab with
                --- no `value` and only `props = { unit = ... }` (`ActionCatalog.lua`), which is why
                --- these rows carry a unit and nothing else. The unit is not free either:
                --- `UNIT_INFO` bars `focus` from `FOCUS` and `mouseover` from `TOGGLEMENU`.
                { type = Constants.FOCUS, unit = "target", key = "CTRL-F1", seq = 1 },
                { type = Constants.TOGGLEMENU, unit = "player", key = "CTRL-F2", seq = 1 },
                --- The game's own keybinding commands, whose stored value is the command string.
                --- Only commands with a `BINDING_NAME_*` reach the picker, so the seed uses one
                --- that has had one for as long as the game has.
                { type = Constants.COMMAND, value = "TOGGLEBACKPACK", key = "CTRL-F3", seq = 1 },
                --- Switch flipping. **The old shape, spelled out.** `dbver` 5 packed the mode
                --- into the high bits over the state index, and neither that type name nor the
                --- mode flags survive in `Constants.lua` -- reaching for a constant would plant
                --- `dbver` 6 data under a `dbver` 5 stamp, and `/deb seed 5` is what the step
                --- that unpacks it is verified against (`MigrateLayer` in `Profile.lua`).
                --- `0x400` is toggle, and state 2 is one the seed actually defines below.
                { type = "setstate", value = 0x400 + 2, key = "CTRL-F4", seq = 1 },
                --- [Unused], which carries no value at all: the key is handed back to the game's
                --- own binding rather than taken.
                { type = Constants.UNUSED, key = "CTRL-F5", seq = 1 },
                --- The role units, which is the whole `UnitWatch.lua` half. Nothing else in the
                --- seed reaches it: a role unit is neither a basic unit nor a condition, it is
                --- what the addon resolves at the click.
                { type = Constants.ITEM, value = HEARTHSTONE, unit = "healer",
                    key = "CTRL-F6", seq = 1 },
                --- Unit conditions on units other than the hovered one and the aimed one, which
                --- is the third of the three menus that write `checkedUnits` and the only one
                --- with no row until now. `exists = false` is the "not there" answer, the one
                --- shape `"@"` is locked out of.
                { type = Constants.ITEM, value = HEARTHSTONE, key = "CTRL-F7", seq = 1,
                    checkedUnits = { tank = {}, custom1 = { exists = false } } },
                --- The three yes/no conditions with no row. `false` is here on purpose: the
                --- menu writes it for [No] and the tooltip has a whole second sentence for it, so
                --- a seed of nothing but `true` leaves half of every one of them unseen.
                ---
                --- **`petbattle` and `specialbar` cannot share an action** - the second is
                --- dropped when both are set (`Misc.lua`), so the bar row below is a row of its
                --- own rather than more fields on this one.
                { type = Constants.ITEM, value = HEARTHSTONE, key = "CTRL-F8", seq = 1,
                    stealth = true, pet = false, petbattle = true },
                --- Shapeshift and the action bars. Both masks are one bit rather than several,
                --- and it is the bit that means the same thing on every class: `[form:0]` is "not
                --- shifted" and bonus bar `0` is the default bar. A mask naming a druid form
                --- would be a row nobody else can read.
                { type = Constants.ITEM, value = HEARTHSTONE, key = "CTRL-F9", seq = 1,
                    forms = 1, bonusbars = 1, specialbar = true, extrabar = true },
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
            addCustomTargetMenusToUnitPopup = true,
            blizzframes = {},
        },

        --- Three of the five set up differently, so the switches screen has both modes on it and
        --- `$state1` above has something to point at. **The other two are not here and do not
        --- appear**: nothing plants an empty definition any more, and the `dbver` 6 step throws
        --- away the untouched ones this seed's own migration walks past.
        ---
        --- **`$state3` is the one the migration has work to do on.** It is a switch somebody
        --- pressed and never configured, so the whole of it is a `savedValue` sitting on the
        --- account table - which is what the `dbver` 6 step moves onto the characters and what its
        --- pruning has to recognise from the other side (`MigrateSwitches`). Without a row like
        --- this, `/deb seed 5` walks past that step with nothing to carry.
        ---
        --- **The old names and the old numbers, spelled out.** This is the shape `dbver` 5 stored,
        --- and `Constants.SWITCH_MODES` no longer holds a word for it -- reaching for the constant
        --- would plant `dbver` 6 data under a `dbver` 5 stamp, and `/deb seed 5` is what a
        --- migration is verified against. `0` is manual and `3` is the expression mode
        --- (`MigrateSwitches` in `Profile.lua` is the other half of this pair).
        customStates = {
            [1] = { mode = 0, initialValue = true, displayMessage = true },
            [2] = { mode = 3, expr = "[combat]" },
            [3] = { mode = 0, savedValue = true },
        },
    };
end;

--- `dbver` 6. 위 판과 둘이 다르다 - 조건이 `conditions` 안으로 내려갔고, 스위치 정의가
--- `switches`라는 이름 아래 문자열 `mode`와 `resetValue`로 앉는다.
SEEDS[6] = function(guid)
    local CLASS = Constants.PLAYER_CLASS;
    local HEARTHSTONE = 6948;

    return {
        dbver = 6,

        --- **Above every `arrivalID` planted below.** `NextArrivalID` reads this and nothing else:
        --- it stopped walking the store for the highest number in use the day that number moved out
        --- of `key`, because the migration writes the counter itself. Left out here, the first real
        --- arrival would be handed 1 and land inside the seeded set.
        nextArrivalID = 2,

        shared = {
            --- **The account layer is where the coverage lives**, and it is filled by walking three
            --- lists rather than by taste: every action type the picker can hand out, every field in
            --- `KEYS_TO_SAVE`, and every name `Constants.IsConditionField` answers yes to. A row
            --- goes in for anything none of the rows above it already reaches.
            ---
            --- Four of those are left out on purpose and each has a reason that is not "forgot":
            ---
            ---   * `SPELL`, `FLYOUT`, `PETACTION` name something a class has. Seeded, they come up
            ---     as red rows on every character that is not that class, which is the one thing
            ---     this seed exists to avoid.
            ---   * `known` is dropped on anything that is not a `SPELL` (`Misc.lua`), so it cannot
            ---     be reached from here at all while `SPELL` is out.
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
                --- **An arrival, and it sits on the key it was sent on.** What holds it back is the
                --- badge, `arrivalID`, and with `key` that pair is also which group it belongs to
                --- (`devdocs/building-export-import.md` 12절). A number in `key` is a shape no path
                --- produces any more.
                ---
                --- **On `SHIFT-F3`, which the account layer already uses.** That collision is the
                --- state the pair exists for and no other row here reaches it: the column stands two
                --- headings on one key, one live and one waiting, and neither is drawn into the
                --- other. Landing it on a free key would seed a screen that looks the same whether
                --- the grouping is right or wrong.
                ---
                --- Two of them on the one arrival, because what the heading names is a **set**.
                { type = Constants.ITEM, value = HEARTHSTONE, key = "SHIFT-F3", seq = 1,
                    arrivalID = 1 },
                { type = Constants.MACROTEXT, icon = QUESTION_MARK_ICON,
                    value = "/say arrived", name = "Say arrived", key = "SHIFT-F3", seq = 2,
                    arrivalID = 1 },
                --- The other arrival shape: the sender had it on no key, so it lands on none.
                --- **No key, no group and no `seq`** - it goes to the unbound pile wearing a badge,
                --- rather than under a heading of its own.
                { type = Constants.MACROTEXT, icon = QUESTION_MARK_ICON,
                    value = "/say unplaced", name = "Say unplaced", arrivalID = 1 },
                { type = Constants.SETCUSTOM, value = 1, key = "SHIFT-F6", seq = 1 },
                --- Click casting, so the frame menu and the hover half of the tooltip have a row.
                --- Three fields ride along here because this is the only row they can sit on: the
                --- menu enables `ignoreHoverUnit` and the frame-type boxes only while a hover
                --- condition is on (`DropDownMenus.lua`), and `GetBindingInfoForAction` drops
                --- both outright on a binding that does not hover.
                ---
                --- `frameTypes` is short of every bit on purpose - all-on is normalised back to
                --- nil, so a full mask would draw no line at all. `dead` is the life axis, and
                --- `false` is its "alive" answer.
                ---
                --- **`ignoreHoverUnit` stays at the top of the action while `frameTypes` moves
                --- down**: only the second one is a condition. That is the one place these two
                --- seeds are not a straight copy of each other.
                { type = Constants.MACROTEXT, icon = QUESTION_MARK_ICON,
                    value = "/say hovered", name = "Say hovered",
                    key = "SHIFT-F7", seq = 1, ignoreHoverUnit = true,
                    conditions = {
                        frameTypes = Constants.FRAMETYPE_PLAYER + Constants.FRAMETYPE_GROUP,
                        units = { hover = { reaction = Constants.REACTION_HELP, dead = false } } } },
                -- Enough conditions on one action that its tooltip has to lay several out at once.
                { type = Constants.ITEM, value = HEARTHSTONE, key = "SHIFT-F8", seq = 1,
                    priority = Constants.MAX_PRIORITY,
                    conditions = { combat = true, groups = Constants.GROUP_PARTY,
                        ["$state1"] = true } },
                --- **The target, which is `action.unit` and not a condition.** It stays at the
                --- top of the action on this version too, which is why the two seeds carry this
                --- row identically. Without one of these the row's `@unit` suffix, the tooltip's
                --- target line and the target menu are all unreachable in a seeded profile.
                --- `TARGET` is used because it takes a unit and names no spell, so it stays class
                --- independent like everything else here.
                { type = Constants.TARGET, unit = "focus", key = "SHIFT-F9", seq = 1 },
                --- Target and the `"@"` unit condition on one action, which is a tooltip line of
                --- its own: `"@"` is drawn as `SELECTED_TARGET_UNIT` and that branch asks for
                --- `action.unit` (`ActionTooltip.lua`), so neither row above can reach it alone. The
                --- unit has to be one that can be absent, since `"@"` is dropped again on `none`
                --- and on `player` (`Misc.lua`).
                { type = Constants.ITEM, value = HEARTHSTONE, unit = "target",
                    key = "SHIFT-F10", seq = 1,
                    conditions = { units = { ["@"] = {} } } },
                -- The binding-context exception: this key stays bound while an editor holds it
                -- (`Debind.lua`'s `IsKeyYielded`).
                { type = Constants.MACROTEXT, icon = QUESTION_MARK_ICON,
                    value = "/say kept", name = "Say kept",
                    key = "SHIFT-F11", seq = 1, keepInBindingContext = true },
                --- Mount, on the one value that resolves for every character alive: `0` is the
                --- random favourite, drawn from a spell rather than the journal
                --- (`ActionDisplay.lua`), so a client with nothing collected still gets a name and an
                --- icon. A real `mountID` would be a red row on any character that has not
                --- learned it.
                { type = Constants.MOUNT, value = 0, key = "SHIFT-F12", seq = 1 },
                --- The remaining two types that take a unit. Both come off the command tab with
                --- no `value` and only `props = { unit = ... }` (`ActionCatalog.lua`), which is why
                --- these rows carry a unit and nothing else. The unit is not free either:
                --- `UNIT_INFO` bars `focus` from `FOCUS` and `mouseover` from `TOGGLEMENU`.
                { type = Constants.FOCUS, unit = "target", key = "CTRL-F1", seq = 1 },
                { type = Constants.TOGGLEMENU, unit = "player", key = "CTRL-F2", seq = 1 },
                --- The game's own keybinding commands, whose stored value is the command string.
                --- Only commands with a `BINDING_NAME_*` reach the picker, so the seed uses one
                --- that has had one for as long as the game has.
                { type = Constants.COMMAND, value = "TOGGLEBACKPACK", key = "CTRL-F3", seq = 1 },
                --- Switch flipping. The mode is the type and the target is the switch name
                --- (`ActionCatalog.lua` builds it the same way), and `$state2` is one the seed
                --- actually defines below.
                { type = Constants.SETSTATE_TOGGLE, value = "$state2",
                    key = "CTRL-F4", seq = 1 },
                --- [Unused], which carries no value at all: the key is handed back to the game's
                --- own binding rather than taken.
                { type = Constants.UNUSED, key = "CTRL-F5", seq = 1 },
                --- The role units, which is the whole `UnitWatch.lua` half. Nothing else in the
                --- seed reaches it: a role unit is neither a basic unit nor a condition, it is
                --- what the addon resolves at the click.
                { type = Constants.ITEM, value = HEARTHSTONE, unit = "healer",
                    key = "CTRL-F6", seq = 1 },
                --- Unit conditions on units other than the hovered one and the aimed one, which
                --- is the third of the three menus that write `units` and the only one
                --- with no row until now. `exists = false` is the "not there" answer, the one
                --- shape `"@"` is locked out of.
                { type = Constants.ITEM, value = HEARTHSTONE, key = "CTRL-F7", seq = 1,
                    conditions = { units = { tank = {}, custom1 = { exists = false } } } },
                --- The three yes/no conditions with no row. `false` is here on purpose: the
                --- menu writes it for [No] and the tooltip has a whole second sentence for it, so
                --- a seed of nothing but `true` leaves half of every one of them unseen.
                ---
                --- **`petbattle` and `specialbar` cannot share an action** - the second is
                --- dropped when both are set (`Misc.lua`), so the bar row below is a row of its
                --- own rather than more fields on this one.
                { type = Constants.ITEM, value = HEARTHSTONE, key = "CTRL-F8", seq = 1,
                    conditions = { stealth = true, pet = false, petbattle = true } },
                --- Shapeshift and the action bars. Both masks are one bit rather than several,
                --- and it is the bit that means the same thing on every class: `[form:0]` is "not
                --- shifted" and bonus bar `0` is the default bar. A mask naming a druid form
                --- would be a row nobody else can read.
                { type = Constants.ITEM, value = HEARTHSTONE, key = "CTRL-F9", seq = 1,
                    conditions = { forms = 1, bonusbars = 1, specialbar = true,
                        extrabar = true } },
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
                --- **The remembered switch value, and it belongs to this character alone.** An alt
                --- on the same account comes up with `$state3` off, which is the whole point of it
                --- living here rather than next to the definition (§5 of
                --- `devdocs/redesigning-custom-states.md`).
                switches = { ["$state3"] = true },
            },
        },

        --- **Answered, so the pre-rename question never comes up on a seeded client.** `false` is
        --- the value a fresh install reaches on its own first login (`Legacy.lua`), and without it
        --- the overlay would stand in front of the window this seed exists to look at.
        migrated = { [guid] = true },
        legacyNeeded = false,

        options = {
            addCustomTargetMenusToUnitPopup = true,
            blizzframes = {},
        },

        --- Three of the five set up differently, so the switches screen has both modes on it and
        --- `$state1` above has something to point at. **The other two are simply absent** - a
        --- definition is a switch somebody made, and nothing plants empty ones
        --- (`BindDerivedTables`).
        ---
        --- **`$state3` looks like an empty definition and is not one.** It remembers rather than
        --- resetting (`resetValue` absent), and everything that says somebody used it is the value
        --- on the character above. That split is what the seed above turns into when it migrates.
        ---
        --- **Filed by name, which is what `dbver` 6 stores.** The numbers this held are the shape
        --- the seed above carries, and the step between the two is the one that moves them
        --- (`MigrateSwitches`).
        --- **One of them answers differently on one tab**, so the Switches list has a switch with
        --- more than the account-wide row under it and the tick has somewhere to move to. It is on
        --- the class tab for specialization 1, which makes changing specialization the thing that
        --- moves it - the case §4-8 exists for and the one no check can see.
        ---
        --- **The key shape is `GetSwitchLayerKey`'s** and is written out here the way every other
        --- stored shape in this file is. A character tab's key would name a GUID, which is a
        --- character this seed cannot know; a class tab's key is the class of whoever plants it.
        switches = {
            ["$state1"] = { mode = Constants.SWITCH_MODES.MANUAL, resetValue = true,
                displayMessage = true,
                overrides = {
                    [Constants.PLAYER_CLASS .. ":1"] = {
                        mode = Constants.SWITCH_MODES.MANUAL, resetValue = false },
                },
            },
            ["$state2"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[combat]" },
            ["$state3"] = { mode = Constants.SWITCH_MODES.MANUAL },
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

    local reason, dbver;
    if (dev.seedPending) then
        -- The flag carries the `dbver` that was asked for, so an older one arrives here as an
        -- older one and `MigrateDB` runs on it for real. Cleared before the seed is built: if
        -- that dbver has no builder the `error` below kills this login, and a flag left standing
        -- would kill every login after it too.
        dbver = dev.seedPending;
        dev.seedPending = nil;
        reason = format("asked for, dbver %d", dbver);
    elseif (db.dbver == nil) then
        reason = "nothing saved yet";
    elseif (db.dbver > Constants.DB_VERSION) then
        reason = "what is saved is newer than this build";
    else
        return db;
    end

    db = DebindPrivate.MakeSeed(dbver or Constants.DB_VERSION);
    _G.DebindVars = db;
    -- A plain literal, not `L[...]`. Locale files are shipped and this sentence is not.
    DebindPrivate.DisplayMessage(format("Development seed planted (%s).", reason));
    return db;
end

--- The `dbver`s this file has a builder for, low to high, as text for a message.
local function SeededVersions()
    local versions = {};
    for dbver in pairs(SEEDS) do
        tinsert(versions, dbver);
    end
    sort(versions);
    return table.concat(versions, ", ");
end

--- `/deb seed`, or `/deb seed <dbver>`. Returns whether this call handled the command.
---
--- **A `dbver` is asked for to reach a path only an old or a new profile reaches.** Without one
--- the seed is this build's own and `InitDB` has nothing to do with it. An older one lands where
--- an upgrading user's profile lands, so `MigrateDB` runs on data nobody hand wrote for the
--- occasion. A newer one lands where a downgrading user's lands and this build stands down
--- (`guarding-against-a-downgrade.md`), which is a state that otherwise takes two clients to
--- produce; a worktree cut from an older release can reach it because the later builders are still
--- in the copy of this file it carries.
---
--- **So the number is not clamped to what this build can read.** Both directions are the point,
--- and planting the current one is the way back out of either. `/deb seed` is reachable while
--- stood down, since `HandleNewerProfileReset` only takes `reset`.
---
--- **The number is checked here rather than on the next login.** What is typed wrong is typed at
--- a prompt that can answer; the same mistake read back at load time comes out as an `error`
--- inside `InitDB`, with the window gone and the reason a line in the chat frame.
---
--- **The confirmation comes before the flag is set**, because that is the step that cannot be
--- taken back: what the flag costs on the next login is whatever the client had.
function DebindPrivate.HandleDevSeedCommand(chunks)
    if (chunks[1] ~= "seed") then
        return false;
    end

    local dbver = Constants.DB_VERSION;
    if (chunks[2]) then
        dbver = tonumber(chunks[2]);
        if (not dbver or not SEEDS[dbver]) then
            -- Plain literals throughout, not `L[...]`. Locale files are shipped and this is not.
            DebindPrivate.DisplayMessage(format("No seed written for dbver %s. Have: %s.",
                chunks[2], SeededVersions()));
            return true;
        end
    end

    StaticPopup_ShowCustomGenericConfirmation({
        text = format("Replace this account's Debind settings with the development seed for dbver %d?|n|nWhat is there now is deleted and cannot be brought back.", dbver),
        callback = function()
            local dev = _G.DebindDevVars;
            if (not dev) then
                dev = {};
                _G.DebindDevVars = dev;
            end
            dev.seedPending = dbver;
            ReloadUI();
        end,
        acceptText = YES,
        cancelText = NO,
        showAlert = true,
        referenceKey = "DebindDevSeed",
    });
    return true;
end
