local _, DebindPrivate = ...;
local Constants        = DebindPrivate.Constants;
local L                = DebindPrivate.L;

--- The account-wide settings, in the game's own settings window under AddOns.
---
--- **Every one of them is a `RegisterProxySetting`.** `RegisterAddOnSetting` takes a table and a
--- key and writes that cell directly, and nearly every row here answers `nil` as one of its
--- values: absent is the default for a pack, for Smart Cast and for the exclusions, and for the
--- click edge it is the third of the three a reader can pick. A proxy also lets the setter clear
--- the cell when the value comes back to the default, which is what keeps the Defaults button
--- from writing a wall of defaults into the saved variables.
---
--- **No setter here reaches a secure frame.** The window is open and every control in it is
--- pressable during a fight, so a setter writes the stored value and asks for a rebuild;
--- `ApplyOptions` is what carries the answer across, and a rebuild refused during a fight is
--- replayed once it ends (`Misc.lua`, `Events.PLAYER_REGEN_ENABLED`).
---
--- **Nothing here hangs a function on an initializer that the panel reads outside a secure call.**
--- What we write into a table is a tainted slot, and the panel reads `ShouldShow` in `Display` and
--- `RepairDisplay` bare, then rebuilds the list in the same pass: one `AddShownPredicate` and every
--- number the scroll box holds is tainted for the rest of the session, and the next wheel scroll
--- in combat is `Frame:SetHeight()` blocked (measured 2026-09-08). The reads the panel does wrap
--- -- a row's `Init`, its extent, its factory, the proxy getter and setter -- are the only places a
--- value of ours may be a function. The modify predicates below are read from those.

--- The prefix on every variable name. They are looked up across the whole settings panel, so they
--- are ours to keep unique.
local VAR = "DEBIND_";

local _category;

--- The hidden setting the Reload button hangs off. Its value is `IsReloadRequired()` and its setter
--- does nothing: what moves it is the option somebody just wrote, not this.
local _reloadRequired;

--- Says a reload-needing option has been written. **Called by those setters and nowhere else** --
--- the value is worked out on the spot, so what this carries is the fact that the answer may have
--- moved, not the answer.
function DebindPrivate.NotifyReloadRequired()
    if (_reloadRequired) then
        _reloadRequired:SetValue(DebindPrivate.IsReloadRequired());
    end
end

--- What the gear on the title bar does (`DebindUI.lua`). Our own window is left where it is.
function DebindPrivate.OpenOptionsCategory()
    if (not _category) then
        return;
    end
    Settings.OpenToCategory(_category:GetID());
end

--- Called once the profile stands, since every getter below reads it. **From `PLAYER_LOGIN` and
--- not earlier**, and the call site says why: the pack rows are the packs that are installed, and
--- an addon loading after us has not answered `IsAddOnLoaded` at our own `ADDON_LOADED`.
function DebindPrivate.RegisterOptionsCategory()
    if (_category) then
        return;
    end

    local category = Settings.RegisterVerticalLayoutCategory(L["ADDON_NAME"]);
    _category = category;

    --- **The owner is passed rather than closed over, because there are two of them now.** The unit
    --- frame rows live in a subcategory of their own and everything else stays on this one; a
    --- helper that remembered which was current would put a row in the wrong list the day somebody
    --- moves one, and say nothing about it.
    local function Proxy(owner, variable, varType, name, default, get, set)
        return Settings.RegisterProxySetting(owner, VAR .. variable, varType, name, default,
            get, set);
    end

    local function Header(owner, name, tooltip)
        local initializer = CreateSettingsListSectionHeaderInitializer(name, tooltip);
        Settings.RegisterInitializer(owner, initializer);
        return initializer;
    end

    --- A row that is a word and nothing else, for naming the group of boxes under it.
    ---
    --- **A second section header would not have shown a level.** Headers do not nest: one under
    --- `Blacklist` would stand in the same weight beside it and read as a third heading rather than
    --- as its child. `SettingsExpandableSectionTemplate` is the only thing in the client that
    --- groups, and expanding is adding and dropping rows, which this file may not ask for (see the
    --- top) - on top of `OnExpandedChanged` and `GetExtent` being ours to write.
    ---
    --- So it is the shape the notice row already proved: our own template, one font string, a fixed
    --- height, and nothing hung on the initializer that the panel reads bare.
    local function Label(owner, name)
        Settings.RegisterInitializer(owner, Settings.CreateElementInitializer(
            "DebindSettingsLabelTemplate", { name = name }));
    end

    --------------------------------------------------------------------------
    -- The window
    --------------------------------------------------------------------------

    --- **The predicate is read here, so the setting has to stand before either header does.** Its
    --- getter is `IsReloadRequired()` and its setter does nothing: what moves the value is the
    --- option somebody just wrote (`NotifyReloadRequired`).
    ---
    --- **A modify predicate on its own would never be read again.** `EvaluateState` is what reads
    --- it, and it runs on four axes: the row's `Init`, a parent setting's value moving, a frame
    --- event the row asked for, and a CVar (`Blizzard_SettingControls.lua`). Ticking one of our
    --- boxes is none of them, so the button would sit grey until the row happened to be built
    --- again by a scroll. `SettingMixin:ApplyValue` fires the value-changed event whether or not
    --- the value moved (`Blizzard_Setting.lua`), which is what the row is listening on.
    _reloadRequired = Proxy(category, "RELOAD_REQUIRED", Settings.VarType.Boolean, RELOADUI, false,
        DebindPrivate.IsReloadRequired, function() end);

    --- Out of the search index, the way the client keeps its own open-something-else buttons out
    --- of it (`AdvancedOptions.lua`).
    local addSearchTags = false;

    --- The three rows that head every one of our lists.
    ---
    --- **On each list rather than on the first**, because a list in the left column is a page of
    --- its own and the reader may never see another: every option that needs a reload is on the
    --- unit frame list, so a Reload button only on the top one is on the page that does not need
    --- it. The same goes for the combat notice, which is about the row the reader is looking at.
    local function WindowHeader(owner)
        --- **It stands whether there is a fight on or not, and that is what lets it stand at all.**
        --- A row that comes and goes with combat is the panel adding and dropping a row, which is
        --- the one thing this file may not ask for (see the top). Unconditional, it is also the
        --- only wording that is true at every moment: out of a fight nothing waits, so the sentence
        --- has to say which changes wait rather than that changes wait.
        Settings.RegisterInitializer(owner, Settings.CreateElementInitializer(
            "DebindSettingsNoticeTemplate", { name = L["SETTINGS_APPLIED_AFTER_COMBAT"] }));

        --- **The window's own toggle, and only in the direction the label promises.** That toggle
        --- already turns down a fight, the game menu and a profile from a newer build and says
        --- which it was (`Public.lua`), so there is no second answer to give here -- but it also
        --- closes a window that is up, and a button that says "open" may not do that. What is left
        --- for the press to do when the window is already open is bring it in front of this one.
        Settings.RegisterInitializer(owner, CreateSettingsButtonInitializer("",
            L["OPEN_ADDON_WINDOW"], function()
                if (DebindFrame:IsShown()) then
                    DebindFrame:Raise();
                    return;
                end
                DebindPublic:ToggleUI();
            end, nil, addSearchTags));

        --- **The row always stands and only the button greys.** Showing it when a reload is owed
        --- and hiding it otherwise is `ShouldShow`, which is the panel adding and dropping a row.
        ---
        --- **A parent initializer of its own per list.** It is never registered, which is what
        --- `CreateCheckboxInitializer` is for (`Blizzard_Settings.lua` makes one without laying it
        --- out), so `IsParentInitializerInLayout` answers false and the button is neither indented
        --- nor put in the smaller font. Both wrap the one setting, so both buttons move together.
        ---
        --- **The predicate does not ask about combat.** `SetButtonState` is `Button:SetEnabled` on
        --- a `UIPanelButtonTemplate` (`Blizzard_SettingControls.lua`), which no lockdown blocks,
        --- and `ReloadUI` is the reader's to press whenever they like.
        local reloadButton = CreateSettingsButtonInitializer("", RELOADUI, ReloadUI, nil,
            addSearchTags);
        reloadButton:SetParentInitializer(Settings.CreateCheckboxInitializer(_reloadRequired),
            DebindPrivate.IsReloadRequired);
        Settings.RegisterInitializer(owner, reloadButton);
    end

    WindowHeader(category);

    --------------------------------------------------------------------------
    -- Smart Cast
    --------------------------------------------------------------------------

    Header(category, L["SMART_CAST_DEFAULTS"],
        L["SMART_CAST_DESC"] .. "|n|n" .. L["SMART_CAST_DEFAULTS_DESC"]);

    --- **The table is made only when something has to be written into it.** Coming back to the
    --- built-in answer clears the cell, and clearing a cell in a table that is not there is
    --- nothing to do -- so the Defaults button cannot leave an empty table behind either.
    local function SetSmartCast(key, value, default)
        local stored = DebindPrivate.Options.smartCast;
        if (value == default) then
            if (stored) then
                stored[key] = nil;
            end
        else
            if (not stored) then
                stored = {};
                DebindPrivate.Options.smartCast = stored;
            end
            stored[key] = value;
        end
        DebindPrivate.QueueUpdateBindings();
    end

    -- **The master switch first, then the account setting the four boxes hold.** Off ignores every
    -- action's option rather than clearing anything, so it is not one of the four.
    local enabled = Settings.CreateCheckbox(category,
        Proxy(category, "SMART_CAST_ENABLED", Settings.VarType.Boolean, L["SMART_CAST_ENABLED"], true,
            DebindPrivate.SmartCastEnabled,
            function(value)
                SetSmartCast("enabled", value, true);
            end),
        L["SMART_CAST_ENABLED_DESC"]);

    local branchLabels = {
        rez = L["SMART_CAST_REZ"],
        battleRez = L["SMART_CAST_BATTLE_REZ"],
        dispel = L["SMART_CAST_DISPEL"],
        buff = L["SMART_CAST_BUFF"],
    };
    -- The same tooltips as on an action (`CreateSmartCastMenuItem`), because the box means the
    -- same thing in both places. The two aura branches carry the shared caveat behind them.
    local branchTooltips = {
        rez = L["SMART_CAST_REZ_DESC"],
        battleRez = L["SMART_CAST_BATTLE_REZ_DESC"],
        dispel = L["SMART_CAST_DISPEL_DESC"] .. "|n|n" .. L["SMART_CAST_OUT_OF_COMBAT_DESC"],
        buff = L["SMART_CAST_BUFF_DESC"] .. "|n|n" .. L["SMART_CAST_OUT_OF_COMBAT_DESC"],
    };

    local function SmartCastCheckbox(key, label, tooltip)
        return Settings.CreateCheckbox(category,
            Proxy(category, "SMART_CAST_" .. strupper(key), Settings.VarType.Boolean, label,
                DebindPrivate.SMART_CAST_DEFAULTS[key] and true or false,
                function()
                    return DebindPrivate.SmartCastDefault(key) and true or false;
                end,
                function(value)
                    SetSmartCast(key, value, DebindPrivate.SMART_CAST_DEFAULTS[key] and true or false);
                end),
            tooltip);
    end

    --- Locked while the switch above is off. They would still write, and the account setting they
    --- write is still what an action following it gets back the moment Smart Cast returns -- but a
    --- live box over a dead feature is read as the feature being alive.
    ---
    --- **The predicate is what greys them, not the parent on its own.** A parent initializer buys
    --- the indent and a redraw when its value moves; `SettingsControlMixin:IsEnabled` reads the
    --- modify predicates and nothing else (`Blizzard_SettingControls.lua`).
    for _, branch in ipairs(DebindPrivate.SMART_CAST_BRANCHES) do
        local initializer = SmartCastCheckbox(branch, branchLabels[branch], branchTooltips[branch]);
        initializer:SetParentInitializer(enabled, DebindPrivate.SmartCastEnabled);
        initializer:Indent();

        --- **Directly under resurrection and a step further in.** It is not a fifth branch: it
        --- says what the resurrection branch may reach for where the class has no resurrection out
        --- of combat, so it belongs to that row. It needs both that row and the switch above to be
        --- on, which is why the predicate asks for two things and not one.
        if (branch == "rez") then
            local withBattleRez = SmartCastCheckbox("rezWithBattleRez",
                L["SMART_CAST_REZ_WITH_BATTLE_REZ"], L["SMART_CAST_REZ_WITH_BATTLE_REZ_DESC"]);
            withBattleRez:SetParentInitializer(initializer, function()
                return DebindPrivate.SmartCastEnabled() and DebindPrivate.SmartCastDefault("rez")
                    and true or false;
            end);
            withBattleRez:Indent();

            --- **The settings list has one indent step, and this row is the second one.**
            --- `GetIndent` answers `indentSize` or `0` and nothing between
            --- (`Blizzard_SettingControls.lua`), so a row two levels deep has to say so itself.
            --- The step is read back off `Indent()` rather than written down here, so the day
            --- Blizzard moves it this row moves with it.
            local step = withBattleRez:GetData().indent;
            withBattleRez.GetIndent = function()
                return step * 2;
            end
        end
    end

    --------------------------------------------------------------------------
    -- Don't Count Myself As
    --------------------------------------------------------------------------

    --- **The sentence is on the header and the four rows are just the role names.** Every box says
    --- the same thing about a different role, so repeating it four times is four copies of one
    --- line; on the header it is read once, over the rows it covers.
    Header(category, L["SPECIAL_UNITS"], L["EXCLUDE_PLAYER_DESC"]);

    local UNIT_INFO = DebindPrivate.DebindUI.UNIT_INFO;
    for _, unit in ipairs(DebindPrivate.EXCLUDE_PLAYER_UNITS) do
        Settings.CreateCheckbox(category,
            Proxy(category, "EXCLUDE_PLAYER_" .. strupper(unit), Settings.VarType.Boolean,
                UNIT_INFO[unit].name, false,
                function()
                    local excluded = DebindPrivate.Options.excludePlayer;
                    return (excluded and excluded[unit]) and true or false;
                end,
                function(value)
                    local excluded = DebindPrivate.Options.excludePlayer;
                    if (value) then
                        if (not excluded) then
                            excluded = {};
                            DebindPrivate.Options.excludePlayer = excluded;
                        end
                        excluded[unit] = true;
                    elseif (excluded) then
                        excluded[unit] = nil;
                    end
                    DebindPrivate.QueueUpdateBindings();
                end));
    end

    --------------------------------------------------------------------------
    -- Miscellaneous
    --------------------------------------------------------------------------

    --- **The client's own word.** One row is not a subject, and whatever else ends up here will be
    --- the same kind of leftover, so the game's own heading for that is the one to use.
    Header(category, MISCELLANEOUS);

    local defaultThrottle = Constants.STATE_DRIVER_UPDATETIME_DEFAULT;
    local throttle = Proxy(category, "STATE_DRIVER_UPDATE_THROTTLE", Settings.VarType.Number,
        L["STATE_DRIVER_UPDATE_THROTTLE"], defaultThrottle,
        function()
            return DebindPrivate.Options.stateDriverUpdateThrottle or defaultThrottle;
        end,
        function(value)
            -- **Rounded to the step, so what is stored is the number the reader was shown.** A
            -- slider hands back the float its arithmetic landed on (`0.2 / 20 * 7` is not `0.07`),
            -- and the label above rounds to hundredths, so the store has to as well or the profile
            -- holds a number nothing on screen ever said.
            value = floor(value * 100 + 0.5) / 100;
            if (value == defaultThrottle) then
                DebindPrivate.Options.stateDriverUpdateThrottle = nil;
            else
                DebindPrivate.Options.stateDriverUpdateThrottle = value;
            end
            DebindPrivate.QueueUpdateBindings();
        end);

    local sliderOptions = Settings.CreateSliderOptions(0, defaultThrottle, 0.01);
    sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return (format("%.2f", value):gsub("%.?0+$", ""));
    end);
    Settings.CreateSlider(category, throttle, sliderOptions, function()
        return L["STATE_DRIVER_UPDATE_THROTTLE_DESC"] .. "|n|n"
            .. "|cnRED_FONT_COLOR:" .. L["STATE_DRIVER_UPDATE_THROTTLE_WARNING"] .. "|r";
    end);

    --------------------------------------------------------------------------
    -- Unit Frame Support
    --------------------------------------------------------------------------

    --- **A list of its own in the panel's left column.** What belongs here is every decision about
    --- somebody else's unit frames, and that had grown past one section header on a page of
    --- unrelated things.
    ---
    --- **Named for the subject and not for the blacklist**, even though the blacklist is most of the
    --- rows. The click edge takes nothing away, and a list called `Frame Blacklist` has no room for
    --- a row that is not a removal.
    ---
    --- **The subcategory needs no `RegisterAddOnCategory` of its own**: it is created on the parent
    --- (`PrivateSettingsCategoryMixin.CreateSubcategory`) and goes into the panel with it.
    local unitFrames = Settings.RegisterVerticalLayoutSubcategory(category, L["UNIT_FRAME_SUPPORT"]);

    WindowHeader(unitFrames);

    --- **No header over this row.** It is the only one that is not part of the blacklist, and the
    --- category's own name in the left column already says what the page is about; a header over a
    --- single dropdown names a group of one.
    ---
    --- **A dropdown value cannot be `nil`, and one of the three answers is.** So the three are
    --- folded onto three strings here and unfolded on the way back in. `nil` is not the absence of
    --- an answer: it is "whatever the game does", which `ApplyOptions` resolves off the CVar.
    local function GetClickEdge()
        local stored = DebindPrivate.Options.unitframeUseMouseDown;
        if (stored == nil) then
            return "game";
        end
        if (stored) then
            return "down";
        end
        return "up";
    end

    local function SetClickEdge(value)
        local stored;
        if (value == "down") then
            stored = true;
        elseif (value == "up") then
            stored = false;
        end
        DebindPrivate.Options.unitframeUseMouseDown = stored;
        DebindPrivate.QueueUpdateBindings();
    end

    local function ClickEdgeOptions()
        local container = Settings.CreateControlTextContainer();
        container:Add("game", L["UNITFRAME_CLICK_EDGE_GAME"]);
        container:Add("down", L["UNITFRAME_CLICK_EDGE_DOWN"]);
        container:Add("up", L["UNITFRAME_CLICK_EDGE_UP"]);
        return container:GetData();
    end

    local clickEdge = Proxy(unitFrames, "UNITFRAME_CLICK_EDGE", Settings.VarType.String,
        L["UNITFRAME_CLICK_EDGE"], "game", GetClickEdge, SetClickEdge);
    Settings.CreateDropdown(unitFrames, clickEdge, ClickEdgeOptions,
        format(L["UNITFRAME_CLICK_EDGE_DESC"], ACTION_BUTTON_USE_KEY_DOWN));

    --- **One list, and every box in it takes something away.** Every unit frame in the game is
    --- ours and the reader's only lever is naming one to leave alone
    --- (`devdocs/legacy/taking-every-unit-frame-with-one-blacklist.md`), so a reader who has
    --- touched nothing sees every box empty and that is what "all of them" looks like.
    ---
    --- **The word carries the polarity, so no sentence has to.** Somebody who has installed a
    --- click-casting addon knows what a blacklist is, and knows a ticked row is one that is out.
    Header(unitFrames, L["FRAME_BLACKLIST"]);

    --- **The two groups are label rows and not headers**, because a header under a header stands in
    --- the same weight beside it and shows no level. See `Label` above.
    Label(unitFrames, L["FRAME_BLACKLIST_BLIZZARD"]);

    --- **Ticking one takes effect at the next login, and the box has to say so.** A frame already
    --- wired stays wired; ticking stops us registering that set from the next login rather than
    --- handing back what is on screen. `REQUIRES_RELOAD` is the client's own words for that, and
    --- the gate reads the login snapshot so unticking waits the same way (`Profile.lua`).
    ---
    --- **Storage keeps the polarity it already had.** `false` is "leave alone" and the key gone is
    --- "ours", which is what these two tables have always held; only the box reads the other way
    --- round.
    ---
    --- **No rebuild is asked for.** Nothing a rebuild does reads the blacklist any more, so what
    --- the write owes is the Reload button and nothing else.
    for _, frameType in ipairs({ "player", "pet", "target", "party", "raid", "boss", "arena" }) do
        local key = "BLIZZARD_UNIT_FRAMES_" .. strupper(frameType);
        Settings.CreateCheckbox(unitFrames,
            Proxy(unitFrames, key, Settings.VarType.Boolean, L[key], false,
                function()
                    return DebindPrivate.Options.frameBlacklist.blizzard[frameType] == false;
                end,
                function(value)
                    if (value) then
                        DebindPrivate.Options.frameBlacklist.blizzard[frameType] = false;
                    else
                        DebindPrivate.Options.frameBlacklist.blizzard[frameType] = nil;
                    end
                    DebindPrivate.NotifyReloadRequired();
                end),
            L["LEAVE_UNIT_FRAMES_ALONE_DESC"] .. "|n|n" .. REQUIRES_RELOAD):Indent();
    end

    Label(unitFrames, L["FRAME_BLACKLIST_ADDONS"]);

    --- **Only the packs that are installed.** A row for an addon the reader does not have says
    --- nothing they can act on. Left alone is `false` and ours is the key gone, so a pack nobody
    --- touched and one handed back to us are the same row: absent.
    ---
    --- **Ticked, that addon is not touched at all**, whichever way its frames would have reached
    --- us, the ones it hands over included. Which is why the tooltip says nothing about handing
    --- over: that is the vocabulary of somebody who knows the Clique API, and the answer here does
    --- not depend on it.
    local packs = DebindPrivate.LoadedKnownPacks();
    for i = 1, #packs do
        local addon = packs[i][1];
        Settings.CreateCheckbox(unitFrames,
            Proxy(unitFrames, "PACK_FRAMES_" .. strupper(addon),
                Settings.VarType.Boolean, packs[i][2], false,
                function()
                    return DebindPrivate.Options.frameBlacklist.addons[addon] == false;
                end,
                function(value)
                    if (value) then
                        DebindPrivate.Options.frameBlacklist.addons[addon] = false;
                    else
                        DebindPrivate.Options.frameBlacklist.addons[addon] = nil;
                    end
                    DebindPrivate.NotifyReloadRequired();
                end),
            L["LEAVE_PACK_FRAMES_ALONE_DESC"] .. "|n|n" .. REQUIRES_RELOAD):Indent();
    end

    --- **The last row, and the last way out.** Everything above names something we know; this names
    --- everything we do not, so somebody whose frames are broken by an addon we have never heard of
    --- has an answer today instead of waiting for its name to reach `KNOWN_PACK_FRAMES`.
    ---
    --- **Deliberately blunt.** It takes an addon that hands its frames over politely with the rest,
    --- which is a loss - but whoever ticks this already has something broken, and a last resort
    --- that has to be aimed is not one.
    ---
    --- **Its cell sits beside `addons` and not inside it.** A reserved name in that table is a name
    --- some addon's folder may have, and the two would answer as one with nothing said.
    ---
    --- **The row always stands**, so `Addon Frames` above never has an empty group under it and
    --- there is no board with no packs to draw differently.
    Settings.CreateCheckbox(unitFrames,
        Proxy(unitFrames, "LEAVE_OTHER_ADDON_FRAMES", Settings.VarType.Boolean,
            L["LEAVE_OTHER_ADDON_FRAMES"], false,
            function()
                return DebindPrivate.Options.frameBlacklist.other == false;
            end,
            function(value)
                if (value) then
                    DebindPrivate.Options.frameBlacklist.other = false;
                else
                    DebindPrivate.Options.frameBlacklist.other = nil;
                end
                DebindPrivate.NotifyReloadRequired();
            end),
        L["LEAVE_OTHER_ADDON_FRAMES_DESC"] .. "|n|n" .. REQUIRES_RELOAD):Indent();

    --------------------------------------------------------------------------
    -- Help
    --------------------------------------------------------------------------

    --- **A list of its own, because nothing here is a setting.** These rows change nothing; each
    --- opens a piece of writing. Put among the checkboxes they would read as options somebody
    --- forgot to give a value.
    ---
    --- **This is the door the reader can find.** What the ordering rules are cannot be taught by
    --- the tooltip that reports one of them: that tooltip is read once and skimmed after, and it
    --- knows only the pair under the cursor. A page in the panel's left column is somewhere a
    --- reader arrives on purpose.
    --- **No `WindowHeader` on this one.** Those three rows are about settings -- which changes wait
    --- for a fight to end, and a reload owed by one of them -- and this page holds none. The combat
    --- notice would be false here, and a Reload button on a page that can owe nothing is a button
    --- that is grey for good.
    local help = Settings.RegisterVerticalLayoutSubcategory(category, L["HELP_TOPICS"]);

    --- **Out of the search index, like the other buttons that open something.** A search hit that
    --- lands on a button whose only job is to open a window teaches nothing about the search term.
    Settings.RegisterInitializer(help, CreateSettingsButtonInitializer("",
        L["HELP_ORDERING"], function()
            DebindPrivate.DebindUI.ShowHelp("ordering");
        end, nil, addSearchTags));

    Settings.RegisterAddOnCategory(category);
end

--- The notice row's frame. **Its own font string and nothing else.** `Init` runs inside the
--- panel's secure call like every row's, and the two regen events reach this frame directly, so
--- neither path writes into the panel -- which is the whole of why this row is allowed to exist
--- (see the top).
---
--- **Red while the fight is on, and the words never move.** Colouring is not the panel's business:
--- the text keeps its size, so no row changes extent and nothing re-lays the list out. What a
--- shown predicate would have done here -- have the panel add and drop the row -- is the thing
--- that tainted the scroll box, and this reaches none of it.
---
--- `Init` colours it too, for the reader who opens the window with the fight already on: that one
--- never sees an event.
DebindSettingsNoticeMixin = {};

local function NoticeColor()
    return InCombatLockdown() and RED_FONT_COLOR or HIGHLIGHT_FONT_COLOR;
end

--- The row's frame while one is drawn. The panel pools these, so this is whichever frame it last
--- handed the row to; a frame it has taken back keeps the last colour, which nobody can see.
local _noticeFrame;

--- **The events are on a frame of ours, not on the row's.** The row's own `OnLoad` did not reach
--- us in the game (measured 2026-09-08), and the panel's pool creating the frame with a plain
--- `CreateFrame` should have run the script. So the registration is made here, where it is not in
--- doubt, and the row is reached through `Init` instead.
local NoticeWatcher = CreateFrame("Frame");
NoticeWatcher:RegisterEvent("PLAYER_REGEN_DISABLED");
NoticeWatcher:RegisterEvent("PLAYER_REGEN_ENABLED");

--- **The line says a fight is on, and `InCombatLockdown()` answers a different question.** The
--- lockdown has not begun when `PLAYER_REGEN_DISABLED` arrives: the flag answers false and a
--- protected write still lands, and both turn over before the next `OnUpdate` (measured
--- 2026-09-09; `devdocs/reading-back-what-you-just-set.md`). So asking it here is not the flag lying, it
--- is the wrong question, and it painted the line white at the moment it had to go red. The event
--- is the answer. `NoticeColor` is left for `Init`, which is a cold read at any other moment.
NoticeWatcher:SetScript("OnEvent", function(_, event)
    if (_noticeFrame) then
        local color = (event == "PLAYER_REGEN_DISABLED") and RED_FONT_COLOR or HIGHLIGHT_FONT_COLOR;
        _noticeFrame.Text:SetTextColor(color:GetRGB());
    end
end);

function DebindSettingsNoticeMixin:Init(initializer)
    _noticeFrame = self;
    self.Text:SetText(initializer:GetName());
    self.Text:SetTextColor(NoticeColor():GetRGB());
end

--- The group name over a run of boxes. **Its whole job is one `SetText`**: no colour, no events and
--- no state, which is what keeps it inside the rule the notice row above had to argue for.
DebindSettingsLabelMixin = {};

function DebindSettingsLabelMixin:Init(initializer)
    self.Text:SetText(initializer:GetName());
end
