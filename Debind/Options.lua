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

    local function Proxy(variable, varType, name, default, get, set)
        return Settings.RegisterProxySetting(category, VAR .. variable, varType, name, default,
            get, set);
    end

    local function Header(name, tooltip)
        local initializer = CreateSettingsListSectionHeaderInitializer(name, tooltip);
        Settings.RegisterInitializer(category, initializer);
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
    local function Label(name)
        Settings.RegisterInitializer(category, Settings.CreateElementInitializer(
            "DebindSettingsLabelTemplate", { name = name }));
    end

    --------------------------------------------------------------------------
    -- The window
    --------------------------------------------------------------------------

    --- Out of the search index, the way the client keeps its own open-something-else buttons out
    --- of it (`AdvancedOptions.lua`).
    local addSearchTags = false;

    --- **It stands whether there is a fight on or not, and that is what lets it stand at all.**
    --- A row that comes and goes with combat is the panel adding and dropping a row, which is the
    --- one thing this file may not ask for (see the top). Unconditional, it is also the only
    --- wording that is true at every moment: out of a fight nothing waits, so the sentence has to
    --- say which changes wait rather than that changes wait.
    Settings.RegisterInitializer(category, Settings.CreateElementInitializer(
        "DebindSettingsNoticeTemplate", { name = L["SETTINGS_APPLIED_AFTER_COMBAT"] }));

    --- **The window's own toggle, and only in the direction the label promises.** That toggle
    --- already turns down the game menu, a pending migration and a profile from a newer build and
    --- says which it was (`Public.lua`), so there is no second answer to give here -- but it also closes a window
    --- that is up, and a button that says "open" may not do that. What is left for the press to do
    --- when the window is already open is bring it in front of this one.
    -- Settings.RegisterInitializer(category, CreateSettingsButtonInitializer("",
    --     L["OPEN_ADDON_WINDOW"], function()
    --         if (DebindFrame:IsShown()) then
    --             DebindFrame:Raise();
    --             return;
    --         end
    --         DebindPublic:ToggleUI();
    --     end, nil, addSearchTags));

    --- **Always pressable: no parent initializer and no modify predicate.** A parent makes the
    --- row's `Init` put a value-changed handle into the frame's `cbrHandles`, and that frame is
    --- pooled with every other `SettingButtonControlTemplate` row in the panel. The handle is
    --- written after reading our setting, so its slot is tainted; `Unregister` on release reads it
    --- and writes `handles` back tainted, and the next row the frame is handed to reads that first
    --- thing in `Init`. Social's Discord button was `IsUserOAuthed()` blocked on a wheel scroll
    --- that way (taint log, 2026-09-13).
    -- Settings.RegisterInitializer(category, CreateSettingsButtonInitializer("", RELOADUI, ReloadUI,
    --     nil, addSearchTags));

    --------------------------------------------------------------------------
    -- Hover Cast
    --------------------------------------------------------------------------

    Header(L["POINTED_UNIT_CAST"], L["POINTED_UNIT_CAST_DESC"]);

    --- **One row of three, not two boxes.** The wider reach contains the narrower one whole
    --- (`Misc.lua`'s `TwinUnitFor`), so a pair of boxes offered a combination that was
    --- indistinguishable from one of them being on alone.
    ---
    --- **Two cells behind it, and only one is ever written.** The stored shape stayed as it was;
    --- what the reader picks is which of the two is set, and `TwinUnitFor` goes on resolving a
    --- profile that carries both.
    local function GetPointedUnitCast()
        if (DebindPrivate.MouseoverCastEnabled()) then
            return "mouseover";
        end
        if (DebindPrivate.HoverCastEnabled()) then
            return "hover";
        end
        return "off";
    end

    --- **Absent is off and is what gets stored back**, the same shape every other row on this page
    --- writes: picking the default clears the cell rather than writing `false`, so the Defaults
    --- button leaves nothing behind.
    local function SetPointedUnitCast(value)
        local options = DebindPrivate.Options;
        options.hoverCast = nil;
        options.mouseoverCast = nil;
        if (value == "hover") then
            options.hoverCast = true;
        elseif (value == "mouseover") then
            options.mouseoverCast = true;
        end
        DebindPrivate.QueueUpdateBindings();
    end

    local function PointedUnitCastOptions()
        local container = Settings.CreateControlTextContainer();
        container:Add("off", OFF);
        container:Add("hover", L["POINTED_UNIT_CAST_FRAMES"], L["POINTED_UNIT_CAST_FRAMES_DESC"]);
        container:Add("mouseover", L["POINTED_UNIT_CAST_MOUSEOVER"],
            L["POINTED_UNIT_CAST_MOUSEOVER_DESC"]);
        return container:GetData();
    end

    local pointedUnitCast = Proxy("POINTED_UNIT_CAST", Settings.VarType.String,
        L["POINTED_UNIT_CAST_MODE"], "off", GetPointedUnitCast, SetPointedUnitCast);
    Settings.CreateDropdown(category, pointedUnitCast, PointedUnitCastOptions);

    --------------------------------------------------------------------------
    -- Smart Cast
    --------------------------------------------------------------------------

    Header(L["SMART_CAST_DEFAULTS"],
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

    local BRANCHES = DebindPrivate.SMART_CAST_BRANCHES;
    local DEFAULTS = DebindPrivate.SMART_CAST_DEFAULTS;

    --- A checkbox option's bit is `value - 1` (`Settings.CreateDropdownOptionInserter`), so a
    --- branch's value is its place in `SMART_CAST_BRANCHES`.
    local function BranchBit(i)
        return 2 ^ (i - 1);
    end

    local function BranchMask(read)
        local mask = 0;
        for i = 1, #BRANCHES do
            if (read(BRANCHES[i])) then
                mask = mask + BranchBit(i);
            end
        end
        return mask;
    end

    local branchLabels = {
        rez = L["SMART_CAST_REZ"],
        battleRez = L["SMART_CAST_BATTLE_REZ"],
    };
    local branchTooltips = {
        rez = L["SMART_CAST_REZ_DESC"],
        battleRez = L["SMART_CAST_BATTLE_REZ_DESC"],
    };

    local function BranchOptions()
        local container = Settings.CreateControlTextContainer();
        for i = 1, #BRANCHES do
            local branch = BRANCHES[i];
            container:AddCheckbox(i, branchLabels[branch], branchTooltips[branch]);
        end
        return container:GetData();
    end

    local branches = Proxy("SMART_CAST_BRANCHES", Settings.VarType.Number, L["SMART_CAST"],
        BranchMask(function(branch)
            return DEFAULTS[branch];
        end),
        function()
            return BranchMask(DebindPrivate.SmartCastDefault);
        end,
        function(mask)
            for i = 1, #BRANCHES do
                local branch = BRANCHES[i];
                SetSmartCast(branch, floor(mask / BranchBit(i)) % 2 == 1, DEFAULTS[branch]);
            end
        end);

    --- **Ticked is on, which the control forces**: it locks the list while the box is clear
    --- (`SettingsCheckboxDropdownControlMixin:EvaluateState`). Off ignores every action's option
    --- rather than clearing anything, so it is not one of the branches.
    ---
    --- **The battle resurrection row is woken by hand from here.** Its parent carries
    --- `SMART_CAST_BRANCHES` and a row listens to its parent's setting alone
    --- (`SettingsListElementMixin:Init`), yet its predicate asks about this switch too.
    --- Re-applying the branches fires their value-changed whether or not the value moved
    --- (`SettingMixin:ApplyValue`).
    local enabled = Proxy("SMART_CAST_ENABLED", Settings.VarType.Boolean, L["SMART_CAST"], true,
        DebindPrivate.SmartCastEnabled,
        function(value)
            SetSmartCast("enabled", value, true);
            branches:SetValue(branches:GetValue(), true);
        end);

    local smartCast = CreateSettingsCheckboxDropdownInitializer(enabled, L["SMART_CAST"],
        L["SMART_CAST_ENABLED_DESC"], branches, BranchOptions, L["SMART_CAST"],
        L["SMART_CAST_DEFAULTS_DESC"]);
    smartCast.getSelectionTextFunc = function(selections)
        if (#selections == #BRANCHES) then
            return ALL;
        elseif (#selections == 0) then
            return NONE;
        end
    end;
    Settings.RegisterInitializer(category, smartCast);

    --- **Under the list and a step in.** It is not a branch: it says what the resurrection
    --- branch may reach for where the class has no resurrection out of combat, so it needs both
    --- the switch and that branch on.
    ---
    --- **Its parent is an initializer that is never laid out.** A row is re-evaluated when its
    --- parent's setting moves, and the checkbox-dropdown row has no `setting` of its own to be
    --- that parent. Being out of the layout also keeps this row out of the child font
    --- (`IsParentInitializerInLayout`); `Indent()` is what steps it in.
    local withBattleRez = Settings.CreateCheckbox(category,
        Proxy("SMART_CAST_REZWITHBATTLEREZ", Settings.VarType.Boolean,
            L["SMART_CAST_REZ_WITH_BATTLE_REZ"], DEFAULTS.rezWithBattleRez,
            function()
                return DebindPrivate.SmartCastDefault("rezWithBattleRez") and true or false;
            end,
            function(value)
                SetSmartCast("rezWithBattleRez", value, DEFAULTS.rezWithBattleRez);
            end),
        L["SMART_CAST_REZ_WITH_BATTLE_REZ_DESC"]);
    withBattleRez:SetParentInitializer(Settings.CreateDropdownInitializer(branches, BranchOptions),
        function()
            return DebindPrivate.SmartCastEnabled() and DebindPrivate.SmartCastDefault("rez")
                and true or false;
        end);
    withBattleRez:Indent();

    --------------------------------------------------------------------------
    -- Exclude self from role targets
    --------------------------------------------------------------------------

    --- **The direction is on the header, not on each box.** Every box says the same thing about a
    --- different target, so putting it on each is four copies of one line.
    Header(L["SPECIAL_UNITS"], L["EXCLUDE_PLAYER_DESC"]);

    local UNIT_INFO = DebindPrivate.DebindUI.UNIT_INFO;
    for _, unit in ipairs(DebindPrivate.EXCLUDE_PLAYER_UNITS) do
        Settings.CreateCheckbox(category,
            Proxy("EXCLUDE_PLAYER_" .. strupper(unit), Settings.VarType.Boolean,
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
    Header(MISCELLANEOUS);

    --- **Over every switch's own box, not instead of it.** Unticked, no switch says anything, and the
    --- boxes keep what they hold for when this is ticked again.
    Settings.CreateCheckbox(category,
        Proxy("SWITCH_MESSAGES", Settings.VarType.Boolean, L["SWITCH_MESSAGES"], true,
            DebindPrivate.SwitchMessagesEnabled,
            function(value)
                if (value) then
                    DebindPrivate.Options.switchMessages = nil;
                else
                    DebindPrivate.Options.switchMessages = false;
                end
                DebindPrivate.QueueUpdateBindings();
            end),
        L["SWITCH_MESSAGES_DESC"]);

    local defaultThrottle = Constants.STATE_DRIVER_UPDATETIME_DEFAULT;
    local throttle = Proxy("STATE_DRIVER_UPDATE_THROTTLE", Settings.VarType.Number,
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

    --- **Named for the subject and not for the blacklist**, even though the blacklist is most of the
    --- rows. The click edge takes nothing away, and a group called `Frame Blacklist` has no room
    --- for a row that is not a removal.
    Header(L["UNIT_FRAME_SUPPORT"]);

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

    local clickEdge = Proxy("UNITFRAME_CLICK_EDGE", Settings.VarType.String,
        L["UNITFRAME_CLICK_EDGE"], "game", GetClickEdge, SetClickEdge);
    Settings.CreateDropdown(category, clickEdge, ClickEdgeOptions,
        L["UNITFRAME_CLICK_EDGE_DESC"]);

    --- **Every box in the group takes something away.** Every unit frame in the game is
    --- ours and the reader's only lever is naming one to leave alone
    --- (`devdocs/legacy/taking-every-unit-frame-with-one-blacklist.md`), so a reader who has
    --- touched nothing sees every box empty and that is what "all of them" looks like.
    ---
    --- **The word carries the polarity, so no sentence has to.** Somebody who has installed a
    --- click-casting addon knows what a blacklist is, and knows a ticked row is one that is out.
    Header(L["FRAME_BLACKLIST"]);

    --- **The two groups are label rows and not headers**, because a header under a header stands in
    --- the same weight beside it and shows no level. See `Label` above.
    Label(L["FRAME_BLACKLIST_BLIZZARD"]);

    --- **Ticking one takes effect at the next login, and the box has to say so.** A frame already
    --- wired stays wired; ticking stops us registering that set from the next login rather than
    --- handing back what is on screen. `REQUIRES_RELOAD` is the client's own words for that, and
    --- the gate reads the login snapshot so unticking waits the same way (`Profile.lua`).
    ---
    --- **Storage keeps the polarity it already had.** `false` is "leave alone" and the key gone is
    --- "ours", which is what these two tables have always held; only the box reads the other way
    --- round.
    ---
    --- **No rebuild is asked for.** Nothing a rebuild does reads the blacklist any more.
    for _, frameType in ipairs({ "player", "pet", "target", "party", "raid", "boss", "arena" }) do
        local key = "BLIZZARD_UNIT_FRAMES_" .. strupper(frameType);
        Settings.CreateCheckbox(category,
            Proxy(key, Settings.VarType.Boolean, L[key], false,
                function()
                    return DebindPrivate.Options.frameBlacklist.blizzard[frameType] == false;
                end,
                function(value)
                    if (value) then
                        DebindPrivate.Options.frameBlacklist.blizzard[frameType] = false;
                    else
                        DebindPrivate.Options.frameBlacklist.blizzard[frameType] = nil;
                    end
                end),
            L["LEAVE_UNIT_FRAMES_ALONE_DESC"] .. "|n|n" .. REQUIRES_RELOAD):Indent();
    end

    Label(L["FRAME_BLACKLIST_ADDONS"]);

    --- **Only the packs that are installed.** A row for an addon the reader does not have says
    --- nothing they can act on. Left alone is `false` and ours is the key gone, so a pack nobody
    --- touched and one handed back to us are the same row: absent.
    ---
    --- **Ticked, that addon is not touched at all**, whichever way its frames would have reached
    --- us, the ones it hands over included. Which is why the tooltip says nothing about handing
    --- over: that is the vocabulary of somebody who knows the Clique API, and the answer here does
    --- not depend on it.
    local packs = DebindPrivate.InstalledKnownPacks();
    for i = 1, #packs do
        local addon = packs[i][1];
        Settings.CreateCheckbox(category,
            Proxy("PACK_FRAMES_" .. strupper(addon),
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
    Settings.CreateCheckbox(category,
        Proxy("LEAVE_OTHER_ADDON_FRAMES", Settings.VarType.Boolean,
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
            end),
        L["LEAVE_OTHER_ADDON_FRAMES_DESC"] .. "|n|n" .. REQUIRES_RELOAD):Indent();

    --------------------------------------------------------------------------
    -- Help
    --------------------------------------------------------------------------

    --- **A group of its own, because nothing here is a setting.** These rows change nothing; each
    --- opens a piece of writing. Put among the checkboxes they would read as options somebody
    --- forgot to give a value.
    ---
    --- **This is the door the reader can find.** What the ordering rules are cannot be taught by
    --- the tooltip that reports one of them: that tooltip is read once and skimmed after, and it
    --- knows only the pair under the cursor.
    ---
    --- **Last on the list**, since the rows above are what a reader came here to change.
    Header(L["HELP_TOPICS"]);

    --- **Out of the search index, like the other buttons that open something.** A search hit that
    --- lands on a button whose only job is to open a window teaches nothing about the search term.
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer("",
        L["HELP_ORDERING"], function()
            DebindPrivate.DebindUI.ShowHelp("ordering");
        end, nil, addSearchTags));

    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer("",
        L["HELP_TARGETING"], function()
            DebindPrivate.DebindUI.ShowHelp("targeting");
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
