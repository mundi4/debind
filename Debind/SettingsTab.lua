local _, DebindPrivate = ...;
local Constants = DebindPrivate.Constants;
local L = DebindPrivate.L;

local INDENT = 15;

local panel = CreateFrame("Frame", nil, DebindFrame);
panel:SetAllPoints();
panel:Hide();
panel.preferredWidth = 660;
DebindFrame.SettingsPanel = panel;

local background = CreateFrame("Frame", nil, panel, "TooltipBackdropTemplate");
background:SetPoint("TOPLEFT", 4, -85);
background:SetPoint("BOTTOMRIGHT", -31, 8);
background:SetBackdropBorderColor(DARKGRAY_COLOR:GetRGB());
background:SetBackdropColor(BLACK_FONT_COLOR:GetRGB());

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

local function TooltipFunc(title, text)
    return function()
        Settings.InitTooltip(title, text);
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

local function Button(text, onClick)
    local row = AddRow("DebindSettingsButtonRowTemplate");
    row.Button:SetText(text);
    row.Button:SetScript("OnClick", onClick);
end

local function Radios(rootDescription, choices, get, set)
    for _, choice in ipairs(choices) do
        rootDescription:CreateRadio(choice.label, function(data)
            return get() == data.value;
        end, function(data)
            set(data.value);
        end, choice);
    end
end

local function Options()
    return DebindPrivate.Options;
end

local function Build()
    Header(GENERAL);
    local hoverCastChoices = {
        { value = "off", label = OFF },
        { value = "hover", label = L["POINTED_UNIT_CAST_FRAMES"], tooltip = L["POINTED_UNIT_CAST_FRAMES_DESC"] },
        { value = "mouseover", label = L["POINTED_UNIT_CAST_MOUSEOVER"], tooltip = L["POINTED_UNIT_CAST_MOUSEOVER_DESC"] },
    };
    Dropdown(L["POINTED_UNIT_CAST"], L["POINTED_UNIT_CAST_DESC"], function(_, rootDescription)
        Radios(rootDescription, hoverCastChoices, function()
            if (DebindPrivate.MouseoverCastEnabled()) then
                return "mouseover";
            end
            if (DebindPrivate.HoverCastEnabled()) then
                return "hover";
            end
            return "off";
        end, function(value)
            Options().hoverCast = (value == "hover") or nil;
            Options().mouseoverCast = (value == "mouseover") or nil;
            DebindPrivate.QueueUpdateBindings();
        end);
    end, hoverCastChoices);

    local function SetSmartCast(key, value, default)
        local stored = Options().smartCast;
        if (value == default) then
            if (stored) then
                stored[key] = nil;
            end
        else
            if (not stored) then
                stored = {};
                Options().smartCast = stored;
            end
            stored[key] = value;
        end
        DebindPrivate.QueueUpdateBindings();
    end

    local BRANCHES = DebindPrivate.SMART_CAST_BRANCHES;
    local DEFAULTS = DebindPrivate.SMART_CAST_DEFAULTS;
    local branchLabels = {
        rez = L["SMART_CAST_REZ"],
        battleRez = L["SMART_CAST_BATTLE_REZ"],
    };
    local branchTooltips = {
        rez = L["SMART_CAST_REZ_DESC"],
        battleRez = L["SMART_CAST_BATTLE_REZ_DESC"],
    };
    local smartCastChoices = {};
    for _, branch in ipairs(BRANCHES) do
        smartCastChoices[#smartCastChoices + 1] = { label = branchLabels[branch], tooltip = branchTooltips[branch] };
    end
    smartCastChoices[#smartCastChoices + 1] = {
        label = L["SMART_CAST_REZ_WITH_BATTLE_REZ"], tooltip = L["SMART_CAST_REZ_WITH_BATTLE_REZ_DESC"],
    };

    local smartCast;
    local function RefreshSmartCast()
        smartCast.Control:SetEnabled(DebindPrivate.SmartCastEnabled());
    end

    smartCast = AddRow("DebindSettingsCheckboxDropdownRowTemplate");
    Label(smartCast, L["SMART_CAST"]);
    WireCheckbox(smartCast, L["SMART_CAST"], L["SMART_CAST_DESC"] .. "|n|n" .. L["SMART_CAST_DEFAULTS_DESC"]
        .. "|n|n" .. L["SMART_CAST_ENABLED_DESC"], DebindPrivate.SmartCastEnabled,
        function(value)
            SetSmartCast("enabled", value, true);
            RefreshSmartCast();
        end);
    WireDropdown(smartCast.Control, function(_, rootDescription)
        for _, branch in ipairs(BRANCHES) do
            rootDescription:CreateCheckbox(branchLabels[branch], function()
                return DebindPrivate.SmartCastDefault(branch) and true or false;
            end, function()
                SetSmartCast(branch, not DebindPrivate.SmartCastDefault(branch), DEFAULTS[branch]);
            end);
        end
        rootDescription:CreateDivider();
        local battleRez = rootDescription:CreateCheckbox(L["SMART_CAST_REZ_WITH_BATTLE_REZ"], function()
            return DebindPrivate.SmartCastDefault("rezWithBattleRez") and true or false;
        end, function()
            SetSmartCast("rezWithBattleRez", not DebindPrivate.SmartCastDefault("rezWithBattleRez"),
                DEFAULTS.rezWithBattleRez);
        end);
        battleRez:SetEnabled(function()
            return DebindPrivate.SmartCastDefault("rez") and true or false;
        end);
    end, OptionsTooltip(L["SMART_CAST"], L["SMART_CAST_DEFAULTS_DESC"], smartCastChoices));
    smartCast.Control.Dropdown:SetSelectionText(function()
        local count = 0;
        for _, branch in ipairs(BRANCHES) do
            if (DebindPrivate.SmartCastDefault(branch)) then
                count = count + 1;
            end
        end
        if (count == #BRANCHES) then
            return ALL;
        elseif (count == 0) then
            return NONE;
        end
    end);
    smartCast.Control.Dropdown:RegisterCallback(DropdownButtonMixin.Event.OnMenuClose, RefreshSmartCast, smartCast);

    refreshers[#refreshers + 1] = RefreshSmartCast;

    local defaultThrottle = Constants.STATE_DRIVER_UPDATETIME_DEFAULT;
    local throttle = AddRow("DebindSettingsSliderRowTemplate");
    Label(throttle, L["STATE_DRIVER_UPDATE_THROTTLE"]);
    throttle.Slider:SetWidth(250);
    throttle.Tooltip:SetTooltipFunc(TooltipFunc(L["STATE_DRIVER_UPDATE_THROTTLE"],
        L["STATE_DRIVER_UPDATE_THROTTLE_DESC"] .. "|n|n|cnRED_FONT_COLOR:"
        .. L["STATE_DRIVER_UPDATE_THROTTLE_WARNING"] .. "|r"));
    local formatters = {
        [MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(
            MinimalSliderWithSteppersMixin.Label.Right, function(value)
                return (format("%.2f", value):gsub("%.?0+$", ""));
            end),
    };
    throttle.Slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        value = floor(value * 100 + 0.5) / 100;
        if (value == defaultThrottle) then
            Options().stateDriverUpdateThrottle = nil;
        else
            Options().stateDriverUpdateThrottle = value;
        end
        DebindPrivate.QueueUpdateBindings();
    end, throttle);
    refreshers[#refreshers + 1] = function()
        throttle.Slider:Init(Options().stateDriverUpdateThrottle or defaultThrottle, 0, defaultThrottle,
            floor(defaultThrottle / 0.01 + 0.5), formatters);
    end;

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

    Header(L["HELP_TOPICS"]);
    Button(L["HELP_ORDERING"], function()
        DebindPrivate.DebindUI.ShowHelp("ordering");
    end);
    Button(L["HELP_TARGETING"], function()
        DebindPrivate.DebindUI.ShowHelp("targeting");
    end);

    content:SetHeight(y - SPACING + PAD_VERTICAL);
end

local function Refresh()
    for i = 1, #refreshers do
        refreshers[i]();
    end
end

local built = false;
panel:SetScript("OnShow", function()
    if (not built) then
        built = true;
        content:SetWidth(scroll:GetWidth());
        Build();
    end
    Refresh();
end);

local function ResetToDefaults()
    local options = Options();
    options.hoverCast = nil;
    options.mouseoverCast = nil;
    options.smartCast = nil;
    options.excludePlayer = nil;
    options.stateDriverUpdateThrottle = nil;
    options.unitframeUseMouseDown = nil;
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

local defaults = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate");
defaults:SetSize(120, 22);
defaults:SetPoint("BOTTOMRIGHT", background, "TOPRIGHT", 0, 0);
defaults:SetText(SETTINGS_DEFAULTS);
defaults:SetScript("OnClick", function()
    StaticPopup_Show("DEBIND_SETTINGS_DEFAULTS");
end);

local reload = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate");
reload:SetSize(120, 22);
reload:SetPoint("RIGHT", defaults, "LEFT", -6, 0);
reload:SetText(RELOADUI);
reload:SetScript("OnClick", ReloadUI);

UpdateReloadButton = function()
    reload:SetEnabled(DebindPrivate.IsReloadRequired());
end
refreshers[#refreshers + 1] = UpdateReloadButton;
