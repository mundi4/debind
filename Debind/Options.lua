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

--- Called once the profile stands, since every getter below reads it (`Events.ADDON_LOADED`).
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

    --------------------------------------------------------------------------
    -- The window
    --------------------------------------------------------------------------

    --- **It stands whether there is a fight on or not, and that is what lets it stand at all.**
    --- A row that comes and goes with combat is the panel adding and dropping a row, which is the
    --- one thing this file may not ask for (see the top). Unconditional, it is also the only
    --- wording that is true at every moment: out of a fight nothing waits, so the sentence has to
    --- say which changes wait rather than that changes wait.
    Settings.RegisterInitializer(category, Settings.CreateElementInitializer(
        "DebindSettingsNoticeTemplate", { name = L["SETTINGS_APPLIED_AFTER_COMBAT"] }));

    --- **The window's own toggle, and only in the direction the label promises.** That toggle
    --- already turns down a fight, the game menu and a profile from a newer build and says which
    --- it was (`Public.lua`), so there is no second answer to give here -- but it also closes a
    --- window that is up, and a button that says "open" may not do that. What is left for the
    --- press to do when the window is already open is bring it in front of this one.
    ---
    --- Out of the search index, the way the client keeps its own open-something-else buttons out
    --- of it (`AdvancedOptions.lua`).
    local addSearchTags = false;
    Settings.RegisterInitializer(category, CreateSettingsButtonInitializer("",
        L["OPEN_ADDON_WINDOW"], function()
            if (DebindFrame:IsShown()) then
                DebindFrame:Raise();
                return;
            end
            DebindPublic:ToggleUI();
        end, nil, addSearchTags));

    --------------------------------------------------------------------------
    -- Unit frames
    --------------------------------------------------------------------------

    --- **Three headed groups, and no box is the parent of another.** Every box in these three
    --- only ever takes something away -- one pack, the frames nobody handed over, one of the
    --- client's own windows -- so what is left is what the unticked boxes have not removed, and
    --- two of them being off at once needs no explaining. A parent box would say the opposite,
    --- that the children mean nothing while it is off, and none of these stands in that relation
    --- to another. Grouping is what a section header is for and it is what the client uses at this
    --- depth; the list has only one step of indentation to offer anyway
    --- (`Blizzard_SettingControls.lua`).
    ---
    --- **The client's own words for the first one.** Every locale already carries
    --- `UNITFRAME_LABEL`, so there is nothing to translate and the game changing its wording
    --- carries us along.
    Header(UNITFRAME_LABEL);

    --- Clique drives the unit frames while it is installed and we stand aside, so every row in
    --- this section is greyed and carries the sentence saying which addon has them.
    local function NotClique()
        return not DebindPrivate.CliqueDetected;
    end

    local function UnitFrameTooltip(text)
        return function()
            if (not DebindPrivate.CliqueDetected) then
                return text;
            end
            if (not text) then
                return L["BINDING_ERROR_CANNOT_USE_HOVER_WITH_CLIQUE"];
            end
            return text .. "|n|n" .. L["BINDING_ERROR_CANNOT_USE_HOVER_WITH_CLIQUE"];
        end;
    end

    local function UnitFrameCheckbox(setting, tooltip)
        local initializer = Settings.CreateCheckbox(category, setting, tooltip);
        initializer:AddModifyPredicate(NotClique);
        return initializer;
    end

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
        UnitFrameTooltip(format(L["UNITFRAME_CLICK_EDGE_DESC"], ACTION_BUTTON_USE_KEY_DOWN)))
        :AddModifyPredicate(NotClique);

    Header(L["BLIZZARD_UNIT_FRAMES"]);

    --- **Turning one off takes effect at the next login, and the box has to say so.** A frame is
    --- deregistered when its owner asks for it back and Blizzard never asks; unticking stops us
    --- registering that set from the next login rather than handing back what is already wired.
    --- `REQUIRES_RELOAD` is the client's own words for that.
    for _, frameType in ipairs({ "player", "pet", "target", "party", "raid", "boss", "arena" }) do
        local key = "BLIZZARD_UNIT_FRAMES_" .. strupper(frameType);
        UnitFrameCheckbox(Proxy(key, Settings.VarType.Boolean, L[key], true,
            function()
                return DebindPrivate.Options.blizzframes[frameType] ~= false;
            end,
            function(value)
                if (value) then
                    DebindPrivate.Options.blizzframes[frameType] = nil;
                else
                    DebindPrivate.Options.blizzframes[frameType] = false;
                end
                DebindPrivate.QueueUpdateBindings();
            end), UnitFrameTooltip(REQUIRES_RELOAD));
    end

    --- **Stands even with no pack installed**, because the row at the end of it always does and
    --- that row is about somebody else's unit frames too.
    Header(L["ADDON_UNIT_FRAMES"]);

    --- **Only the packs that are installed.** A row for an addon the reader does not have says
    --- nothing they can act on. Off is `false` and on is the key gone, so a pack nobody touched and
    --- one turned back on are the same row: absent.
    ---
    --- **Unticked, that addon is not touched at all**, whichever way its frames would have reached
    --- us, the ones it hands over included. Which is why the tooltip says nothing about handing
    --- over: that is the vocabulary of somebody who knows the Clique API, and the answer here does
    --- not depend on it.
    local packs = DebindPrivate.LoadedKnownPacks();
    for i = 1, #packs do
        local addon = packs[i][1];
        UnitFrameCheckbox(Proxy("PACK_FRAMES_" .. strupper(addon), Settings.VarType.Boolean,
            packs[i][2], true,
            function()
                local stored = DebindPrivate.db.global.packFrames;
                return stored == nil or stored[addon] ~= false;
            end,
            function(value)
                local stored = DebindPrivate.db.global.packFrames;
                if (value) then
                    if (stored) then
                        stored[addon] = nil;
                    end
                    return;
                end
                if (not stored) then
                    stored = {};
                    DebindPrivate.db.global.packFrames = stored;
                end
                stored[addon] = false;
            end), UnitFrameTooltip(L["PACK_FRAMES_DESC"] .. "|n|n" .. REQUIRES_RELOAD));
    end

    --- **Ticked is the wider behaviour and the default.** Some unit frame addons run hover casting
    --- of their own and hand their frames to nobody; ticked, Debind works on those too and that
    --- addon goes on working there as well.
    UnitFrameCheckbox(Proxy("TAKE_UNREGISTERED_UNIT_FRAMES", Settings.VarType.Boolean,
        L["TAKE_UNREGISTERED_UNIT_FRAMES"], true,
        function()
            return DebindPrivate.db.global.takeUnregisteredFrames ~= false;
        end,
        function(value)
            if (value) then
                DebindPrivate.db.global.takeUnregisteredFrames = nil;
            else
                DebindPrivate.db.global.takeUnregisteredFrames = false;
            end
        end),
        UnitFrameTooltip(L["TAKE_UNREGISTERED_UNIT_FRAMES_DESC"] .. "|n|n" .. REQUIRES_RELOAD));

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

    -- **The master switch first, then the account setting the four boxes hold.** Off ignores every
    -- action's option rather than clearing anything, so it is not one of the four.
    local enabled = Settings.CreateCheckbox(category,
        Proxy("SMART_CAST_ENABLED", Settings.VarType.Boolean, L["SMART_CAST_ENABLED"], true,
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
            Proxy("SMART_CAST_" .. strupper(key), Settings.VarType.Boolean, label,
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
    -- Special units
    --------------------------------------------------------------------------

    Header(L["SPECIAL_UNITS"]);

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
                end),
            L["EXCLUDE_PLAYER_DESC"]);
    end

    --------------------------------------------------------------------------
    -- The state driver
    --------------------------------------------------------------------------

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
--- us in the game: the mixin was there -- `Init` ran and coloured the line, which is why scrolling
--- the row back into view showed the fight's colour -- but no `PLAYER_REGEN_DISABLED` ever
--- arrived. Nothing in the client's own source says why; the panel's pool creates the frame with a
--- plain `CreateFrame` and that should run the script (measured 2026-09-08). So the registration is
--- made here, where it is not in doubt, and the row is reached through `Init` instead.
local NoticeWatcher = CreateFrame("Frame");
NoticeWatcher:RegisterEvent("PLAYER_REGEN_DISABLED");
NoticeWatcher:RegisterEvent("PLAYER_REGEN_ENABLED");
NoticeWatcher:SetScript("OnEvent", function()
    if (_noticeFrame) then
        _noticeFrame.Text:SetTextColor(NoticeColor():GetRGB());
    end
end);

function DebindSettingsNoticeMixin:Init(initializer)
    _noticeFrame = self;
    self.Text:SetText(initializer:GetName());
    self.Text:SetTextColor(NoticeColor():GetRGB());
end
