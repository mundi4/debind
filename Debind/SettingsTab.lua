local _, DebindPrivate = ...;
local L = DebindPrivate.L;

local INDENT = 15;

local panel = CreateFrame("Frame", nil, DebindFrame);
panel:SetAllPoints();
panel:Hide();
panel.preferredWidth = 660;
DebindFrame.SettingsPanel = panel;

-- The client's own settings window wears `FlatPanelBackgroundTemplate` (`SettingsFrameTemplate`),
-- where `PortraitFrameTemplate` gives `DebindFrame` the rock texture and its streaks. Those two are
-- regions of `DebindFrame` itself and draw over a frame at level 0, so they are hidden while this
-- panel is up rather than covered.
local flatBackground = CreateFrame("Frame", nil, panel, "FlatPanelBackgroundTemplate");
flatBackground:SetFrameLevel(0);
flatBackground:SetPoint("TOPLEFT", 2, -20);
flatBackground:SetPoint("BOTTOMRIGHT", -2, 3);

local background = CreateFrame("Frame", nil, panel, "TooltipBackdropTemplate");
background:SetPoint("TOPLEFT", 4, -85);
background:SetPoint("BOTTOMRIGHT", -31, 8);
background:SetBackdropBorderColor(DARKGRAY_COLOR:GetRGB());
background:SetBackdropColor(0, 0, 0, 0.5);

local scroll = CreateFrame("ScrollFrame", nil, background, "DebindScrollFrameTemplate");
scroll:SetPoint("TOPLEFT", 5, -5);
scroll:SetPoint("BOTTOMRIGHT", -5, 5);
scroll.ScrollBar:ClearAllPoints();
scroll.ScrollBar:SetPoint("TOPLEFT", background, "TOPRIGHT", 5, -5);
scroll.ScrollBar:SetPoint("BOTTOMLEFT", background, "BOTTOMRIGHT", 5, 5);

local content = CreateFrame("Frame", nil, scroll);
content:SetSize(1, 1);
scroll:SetScrollChild(content);

local PAD_VERTICAL, PAD_LEFT, SPACING = 10, 25, 9;

local y = PAD_VERTICAL;
local refreshers = {};
local UpdateReloadButton;

local function AddRow(template)
    local row = CreateFrame("Frame", nil, content, template);
    row:SetPoint("TOPLEFT", PAD_LEFT, -y);
    row:SetPoint("TOPRIGHT", 0, -y);
    y = y + row:GetHeight() + SPACING;
    return row;
end

--- `text` may be a function, for a tooltip that reads something the game can change while the tab
--- is open.
local function TooltipFunc(title, text)
    return function()
        Settings.InitTooltip(title, type(text) == "function" and text() or text);
    end
end

local function Label(row, text, indent)
    row.Text:SetText(text);
    if (indent) then
        row.Text:SetPoint("LEFT", 37 + indent, 0);
    end
end

local function Header(text, tooltip)
    local row = AddRow("DebindSettingsHeaderTemplate");
    row.Title:SetText(text);
    if (tooltip) then
        row.Tooltip:SetTooltipFunc(TooltipFunc(text, tooltip));
        row.Tooltip:Show();
    end
end

local function Group(text)
    local row = AddRow("DebindSettingsGroupTemplate");
    row.Text:SetText(text);
end

local function WireCheckbox(row, text, tooltip, get, set)
    local tooltipFunc = TooltipFunc(text, tooltip);
    row.Tooltip:SetTooltipFunc(tooltipFunc);
    row.Checkbox:Init(get(), tooltipFunc);
    row.Checkbox:RegisterCallback(SettingsCheckboxMixin.Event.OnValueChanged, function(_, value)
        PlaySound(value and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF);
        set(value);
    end, row);
    row.Tooltip:SetScript("OnMouseUp", function()
        if (row.Checkbox:IsEnabled()) then
            row.Checkbox:Click();
        end
    end);
    refreshers[#refreshers + 1] = function()
        row.Checkbox:SetChecked(get());
    end;
end

local function Checkbox(text, tooltip, get, set, indent)
    local row = AddRow("DebindSettingsCheckboxRowTemplate");
    Label(row, text, indent);
    WireCheckbox(row, text, tooltip, get, set);
    return row;
end

local function OptionsTooltip(title, text, choices, footer)
    return function()
        Settings.InitTooltip(title, text);
        for _, choice in ipairs(choices or {}) do
            if (choice.tooltip) then
                GameTooltip_AddBlankLineToTooltip(SettingsTooltip);
                GameTooltip_AddDisabledLine(SettingsTooltip, format("%s: %s",
                    HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(choice.label),
                    NORMAL_FONT_COLOR:WrapTextInColorCode(choice.tooltip)));
            end
        end
        if (footer) then
            GameTooltip_AddBlankLineToTooltip(SettingsTooltip);
            GameTooltip_AddNormalLine(SettingsTooltip, footer);
        end
    end
end

local function WireDropdown(control, setup, tooltipFunc)
    local dropdown = control.Dropdown;
    dropdown:SetWidth(220);
    dropdown:SetupMenu(setup);
    -- **A stepper or the mouse wheel picks with no menu to answer**, so nothing tells the steppers
    -- the selection moved (`MenuElementDescriptionProxyMixin:Pick`). The client's settings window
    -- rebuilds the dropdown on every value change instead; this row has no setting object to do that.
    hooksecurefunc(dropdown, "Pick", function()
        dropdown:SignalUpdate();
    end);
    Mixin(dropdown, DefaultTooltipMixin);
    dropdown:SetTooltipFunc(tooltipFunc);
    dropdown:SetDefaultTooltipAnchors();
    dropdown:SetScript("OnEnter", function()
        ButtonStateBehaviorMixin.OnEnter(dropdown);
        DefaultTooltipMixin.OnEnter(dropdown);
    end);
    dropdown:SetScript("OnLeave", function()
        ButtonStateBehaviorMixin.OnLeave(dropdown);
        DefaultTooltipMixin.OnLeave(dropdown);
    end);
    refreshers[#refreshers + 1] = function()
        dropdown:GenerateMenu();
        control:SetSteppersShown(dropdown:HasAnyRadioDescriptions());
        control:UpdateSteppers();
    end;
end

local function Dropdown(text, tooltip, setup, choices)
    local row = AddRow("DebindSettingsDropdownRowTemplate");
    Label(row, text);
    local tooltipFunc = OptionsTooltip(text, tooltip, choices);
    row.Tooltip:SetTooltipFunc(tooltipFunc);
    WireDropdown(row.Control, setup, tooltipFunc);
    return row;
end

--- A row that opens a help page. **Green, the way every other way into a page is** (`build-help.js`,
--- `ActionMenuItems.lua`), and pressed on the row itself rather than on a button of its own: a
--- button here would read as a setting being changed, which is what every other row does.
local function HelpLink(title, page)
    local row = AddRow("DebindSettingsLinkRowTemplate");
    row.Text:SetText(DebindPrivate.MenuKit.HelpLinkText(title));
    row.Tooltip:SetScript("OnMouseUp", function()
        DebindPrivate.DebindUI.ToggleHelp(page);
    end);
end

local function Radios(rootDescription, choices, get, set)
    for _, choice in ipairs(choices) do
        rootDescription:CreateHighlightRadio(choice.label, function(data)
            return get() == data.value;
        end, function(data)
            set(data.value);
        end, choice);
    end
end

local function Options()
    return DebindPrivate.Options;
end

--- The key the game has for `command` right now, named the way its own dropdown names it
--- (`Settings.CreateModifiedClickOptions`). Setting Self Cast to None or Auto writes `"NONE"` here.
local MODIFIED_CLICK_NAMES = { ALT = ALT_KEY, CTRL = CTRL_KEY, SHIFT = SHIFT_KEY };

local function CastKeyTooltip(desc, current, command)
    return function()
        local name = MODIFIED_CLICK_NAMES[GetModifiedClick(command)] or NONE_KEY;
        return desc .. "|n|n" .. format(L[current], HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(name))
            .. "|n" .. L["CAST_KEY_CHANGE_IN_GAME_OPTIONS"];
    end
end

local function Build()
    Header(L["CASTING"]);
    Checkbox(AUTO_SELF_CAST_KEY_TEXT,
        CastKeyTooltip(L["SELF_CAST_KEY_DESC"], "CURRENT_SELF_CAST_KEY", "SELFCAST"),
        DebindPrivate.SelfCastEnabled,
        function(value)
            if (value) then
                Options().selfCast = nil;
            else
                Options().selfCast = false;
            end
            DebindPrivate.QueueUpdateBindings();
        end);
    Checkbox(FOCUS_CAST_KEY_TEXT,
        CastKeyTooltip(L["FOCUS_CAST_KEY_DESC"], "CURRENT_FOCUS_CAST_KEY", "FOCUSCAST"),
        DebindPrivate.FocusCastEnabled,
        function(value)
            if (value) then
                Options().focusCast = nil;
            else
                Options().focusCast = false;
            end
            DebindPrivate.QueueUpdateBindings();
        end);
    local hoverCastChoices = {
        { value = "unitframe", label = L["POINTED_UNIT_CAST_FRAMES"], tooltip = L["POINTED_UNIT_CAST_FRAMES_DESC"] },
        { value = "mouseover", label = L["POINTED_UNIT_CAST_MOUSEOVER"], tooltip = L["POINTED_UNIT_CAST_MOUSEOVER_DESC"] },
    };
    -- **The mode and nothing else.** Hover Cast is turned off per action, not here
    -- (`devdocs/which-action-a-key-runs.md` §1): an account-wide off would have to be beaten by the
    -- actions carried over from the unit frame condition, and a value the account cannot hold is one
    -- value fewer than a value every one of those actions has to override.
    Dropdown(L["POINTED_UNIT_CAST"], L["POINTED_UNIT_CAST_DESC"], function(_, rootDescription)
        Radios(rootDescription, hoverCastChoices, DebindPrivate.AccountHoverCastMode, function(value)
            if (value == "mouseover") then
                Options().hoverCastMode = value;
            else
                Options().hoverCastMode = nil;
            end
            DebindPrivate.QueueUpdateBindings();
        end);
    end, hoverCastChoices);
    -- **The one help link that is not in the list further down.** What Hover Cast is has to be
    -- within reach of the row that asks a reader to pick a mode for it, and a reader who has not met
    -- the name yet cannot know to scroll to a list of page titles.
    HelpLink(L["HELP_HOVER_CAST_TITLE"], "hover-cast");

    Header(L["SPECIAL_UNITS"], L["EXCLUDE_PLAYER_DESC"]);
    local UNIT_INFO = DebindPrivate.DebindUI.UNIT_INFO;
    for _, unit in ipairs(DebindPrivate.EXCLUDE_PLAYER_UNITS) do
        Checkbox(UNIT_INFO[unit].name, nil,
            function()
                local excluded = Options().excludePlayer;
                return (excluded and excluded[unit]) and true or false;
            end,
            function(value)
                local excluded = Options().excludePlayer;
                if (value) then
                    if (not excluded) then
                        excluded = {};
                        Options().excludePlayer = excluded;
                    end
                    excluded[unit] = true;
                elseif (excluded) then
                    excluded[unit] = nil;
                end
                DebindPrivate.QueueUpdateBindings();
            end);
    end

    Header(L["UNIT_FRAME_SUPPORT"]);
    Dropdown(L["UNITFRAME_CLICK_EDGE"], L["UNITFRAME_CLICK_EDGE_DESC"],
        function(_, rootDescription)
            Radios(rootDescription, {
                { value = "game", label = format("%s (%s)", L["UNITFRAME_CLICK_EDGE_GAME"],
                    GetCVarBool("ActionButtonUseKeyDown") and L["UNITFRAME_CLICK_EDGE_DOWN"]
                    or L["UNITFRAME_CLICK_EDGE_UP"]) },
                { value = "down", label = L["UNITFRAME_CLICK_EDGE_DOWN"] },
                { value = "up", label = L["UNITFRAME_CLICK_EDGE_UP"] },
            }, function()
                local stored = Options().unitframeUseMouseDown;
                if (stored == nil) then
                    return "game";
                end
                return stored and "down" or "up";
            end, function(value)
                local stored;
                if (value == "down") then
                    stored = true;
                elseif (value == "up") then
                    stored = false;
                end
                Options().unitframeUseMouseDown = stored;
                DebindPrivate.QueueUpdateBindings();
            end);
        end);

    local function Whitelist(text, get, set)
        Checkbox(text, REQUIRES_RELOAD, function()
            return get() ~= false;
        end, function(value)
            if (value) then
                set(nil);
            else
                set(false);
            end
            UpdateReloadButton();
        end, INDENT);
    end

    Group(L["FRAME_BLACKLIST_BLIZZARD"]);
    for _, frameType in ipairs({ "player", "pet", "target", "party", "raid", "boss", "arena" }) do
        local key = "BLIZZARD_UNIT_FRAMES_" .. strupper(frameType);
        Whitelist(L[key],
            function()
                return Options().frameBlacklist.blizzard[frameType];
            end,
            function(stored)
                Options().frameBlacklist.blizzard[frameType] = stored;
            end);
    end

    Group(L["FRAME_BLACKLIST_ADDONS"]);
    local packs = DebindPrivate.InstalledKnownPacks();
    for i = 1, #packs do
        local addon = packs[i][1];
        Whitelist(packs[i][2],
            function()
                return Options().frameBlacklist.addons[addon];
            end,
            function(stored)
                Options().frameBlacklist.addons[addon] = stored;
            end);
    end
    Whitelist(L["LEAVE_OTHER_ADDON_FRAMES"],
        function()
            return Options().frameBlacklist.other;
        end,
        function(stored)
            Options().frameBlacklist.other = stored;
        end);

    Header(L["GIVE_BACK_KEYS"]);
    --- `set` takes the value the box now shows and stores it only where it is not the default, so
    --- an untouched profile carries none of these (`devdocs/giving-keys-back.md` §7).
    local function GiveBack(text, tooltip, get, field, defaultOn, indent)
        Checkbox(text, tooltip, get, function(value)
            if (value == defaultOn) then
                Options()[field] = nil;
            else
                Options()[field] = value;
            end
            DebindPrivate.QueueUpdateBindings();
        end, indent);
    end

    GiveBack(L["CONDITION_SPECIALBAR"], L["GIVE_BACK_REPLACED_BAR_DESC"],
        DebindPrivate.GiveBackOnReplacedBar, "giveBackOnReplacedBar", false);
    GiveBack(L["GIVE_BACK_ONLY_WITH_ACTION"], L["GIVE_BACK_ONLY_WITH_ACTION_DESC"],
        DebindPrivate.GiveBackWhenActionExists, "giveBackWhenActionExists", false, INDENT);
    GiveBack(L["GIVE_BACK_PET_BATTLE"], L["GIVE_BACK_PET_BATTLE_DESC"],
        DebindPrivate.GiveBackInPetBattle, "giveBackInPetBattle", true);
    GiveBack(L["GIVE_BACK_HOUSE_EDITOR"], L["GIVE_BACK_HOUSE_EDITOR_DESC"],
        DebindPrivate.GiveBackInBindingContext, "giveBackInBindingContext", true);

    Header(MISCELLANEOUS);
    Checkbox(L["SWITCH_MESSAGES"], L["SWITCH_MESSAGES_DESC"], DebindPrivate.SwitchMessagesEnabled,
        function(value)
            if (value) then
                Options().switchMessages = nil;
            else
                Options().switchMessages = false;
            end
            -- No rebuild. The box is read where the line is printed (`SwitchesChangedCallback`),
            -- and nothing a rebuild builds depends on it.
        end);

    -- **The state driver interval slider is not built** (2026-09-19, owner). It moved Blizzard's
    -- own `updatetime`, and after the state loop went there was nothing of ours left waiting on it:
    -- every moment a key is handed back arrives as an event, and an event zeroes the manager's
    -- timer. A slider that cannot change what the reader sees is worse than no slider.
    --
    -- The three strings it used are still in the locales. What would bring the row back is
    -- something of ours that has to be worked out with nobody pressing anything.

    content:SetHeight(y - SPACING + PAD_VERTICAL);
end

local function Refresh()
    for i = 1, #refreshers do
        refreshers[i]();
    end
end

local built = false;
panel:SetScript("OnShow", function()
    DebindFrame.Bg:Hide();
    DebindFrame.TopTileStreaks:Hide();
    if (not built) then
        built = true;
        content:SetWidth(scroll:GetWidth());
        Build();
    end
    Refresh();
end);
panel:SetScript("OnHide", function()
    DebindFrame.Bg:Show();
    DebindFrame.TopTileStreaks:Show();
end);

local function ResetToDefaults()
    local options = Options();
    options.selfCast = nil;
    options.focusCast = nil;
    options.hoverCastMode = nil;
    options.switchMessages = nil;
    options.excludePlayer = nil;
    options.stateDriverUpdateThrottle = nil;
    options.unitframeUseMouseDown = nil;
    options.giveBackOnReplacedBar = nil;
    options.giveBackWhenActionExists = nil;
    options.giveBackInPetBattle = nil;
    options.giveBackInBindingContext = nil;
    wipe(options.frameBlacklist.blizzard);
    wipe(options.frameBlacklist.addons);
    options.frameBlacklist.other = nil;
    DebindPrivate.QueueUpdateBindings();
    Refresh();
end

StaticPopupDialogs["DEBIND_SETTINGS_DEFAULTS"] = {
    text = CONFIRM_RESET_SETTINGS,
    button1 = YES,
    button2 = NO,
    OnAccept = ResetToDefaults,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
};

local toolbarLeft = CreateFrame("Frame", nil, panel, "DebindToolbarLeftTemplate");
local toolbarRight = CreateFrame("Frame", nil, panel, "DebindToolbarRightTemplate");

local back = CreateFrame("Button", nil, toolbarLeft, "UIPanelButtonTemplate");
back.layoutIndex = 1;
back:SetSize(90, 22);
back:SetText(BACK);
back:SetScript("OnClick", function()
    DebindFrame:LeaveSettings();
end);

local reload = CreateFrame("Button", nil, toolbarRight, "UIPanelButtonTemplate");
reload.layoutIndex = 1;
reload:SetSize(120, 22);
reload:SetText(RELOADUI);
reload:SetScript("OnClick", ReloadUI);

local defaults = CreateFrame("Button", nil, toolbarRight, "UIPanelButtonTemplate");
defaults.layoutIndex = 2;
defaults:SetSize(120, 22);
defaults:SetText(SETTINGS_DEFAULTS);
defaults:SetScript("OnClick", function()
    StaticPopup_Show("DEBIND_SETTINGS_DEFAULTS");
end);

UpdateReloadButton = function()
    reload:SetEnabled(DebindPrivate.IsReloadRequired());
end
refreshers[#refreshers + 1] = UpdateReloadButton;
