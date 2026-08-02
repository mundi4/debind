std = "lua51"
max_line_length = false
codes = true
exclude_files = {
	"**/Libs",
	"BlizzardInterfaceCode/**",
	"DebounceTest/**",
	"tests/**",
	"node_modules/**",
}
ignore = {
	"112", -- mutating non-standard global (Mixin method assignments)
	"212/self",
	"1/[A-Z][A-Z][A-Z0-9_]+", -- three letter+ uppercase constants (WoW convention)
	"211", -- unused local variable
	"212", -- unused argument
	"213", -- unused loop variable
	"231", -- variable never accessed
	"232", -- argument never accessed
	"311", -- value assigned to variable is unused
	"321", -- accessing uninitialized variable
	"432", -- shadowing upvalue
	"542", -- empty if branch
	"581", -- negation of ~= can be simplified
	"611", -- line contains only whitespace
	"612", -- line contains trailing whitespace
}
globals = {
	-- Lua standard (exposed as WoW globals)
	"abs",
	"bit",
	"floor",
	"format",
	"max",
	"min",
	"sort",
	"strfind",
	"strlower",
	"strmatch",
	"strsplit",
	"strsub",
	"strtrim",
	"strupper",
	"tinsert",
	"tremove",
	"wipe",
	"hooksecurefunc",
	"securecall",
	"GenerateClosure",
	"MergeTable",
	"GetLocale",

	-- WoW core API
	"C_AddOns",
	"C_ClassTalents",
	"C_CreatureInfo",
	"C_Item",
	"C_MountJournal",
	"C_Spell",
	"C_SpellBook",
	"C_SpecializationInfo",
	"C_Timer",
	"C_TradeSkillUI",

	-- Frame / Secure handler
	"CreateFrame",
	"RegisterUnitWatch",
	"SecureHandlerSetFrameRef",
	"SecureHandlerExecute",
	"SecureHandlerWrapScript",
	"SecureHandlerUnwrapScript",
	"ClearOverrideBindings",
	"SetOverrideBindingClick",

	-- Unit functions
	"UnitClass",
	"UnitName",
	"UnitGUID",
	"UnitExists",
	"UnitIsUnit",
	"UnitIsPlayer",
	"UnitInRaid",
	"UnitInParty",
	"UnitSelectionColor",
	"InCombatLockdown",
	"IsInRaid",
	"IsInGroup",

	-- Spell / macro / binding
	"GetShapeshiftFormInfo",
	"GetFlyoutInfo",
	"GetMacroInfo",
	"GetNumMacros",
	"CreateMacro",
	"EditMacro",
	"DeleteMacro",
	"GetNumBindings",
	"GetBinding",
	"GetBindingText",
	"GetConvertedKeyOrButton",
	"CreateKeyChordStringFromTable",
	"IsMetaKey",
	"GetCVarBool",
	"GetTime",

	-- Cursor / Input
	"GetCursorInfo",
	"GetCursorPosition",
	"ClearCursor",
	"GetMouseFoci",
	"DoesAncestryInclude",
	"IsAltKeyDown",
	"IsControlKeyDown",
	"IsShiftKeyDown",
	"IsMetaKeyDown",
	"IsLeftAltKeyDown",
	"IsRightAltKeyDown",
	"IsLeftControlKeyDown",
	"IsRightControlKeyDown",
	"IsLeftShiftKeyDown",
	"IsRightShiftKeyDown",
	"PlaySound",

	-- UI utility
	"CreateColor",
	"GetClassColorObj",
	"CopyTable",
	"CreateTableEnumerator",
	"CreateDataProvider",
	"CreateScrollBoxListLinearView",
	"CreateAndInitFromMixin",
	"CreateFromMixins",
	"TextureKitConstants",

	-- FrameXML: panels, tooltips, menus
	"GameFontHighlightSmall",
	"GameTooltip",
	"GameTooltip_SetTitle",
	"GameTooltip_AddErrorLine",
	"GameTooltip_AddNormalLine",
	"GameTooltip_AddHighlightLine",
	"GameTooltip_AddInstructionLine",
	"GameTooltip_AddBlankLineToTooltip",
	"GameTooltip_Hide",
	"StaticPopup_ShowCustomGenericConfirmation",
	"StaticPopup_ShowCustomGenericInputBox",
	"StaticPopup_FindVisible",
	"StaticPopup_Hide",
	"PanelTemplates_TabResize",
	"PanelTemplates_SetNumTabs",
	"PanelTemplates_SetTab",
	"PanelTemplates_SetTabEnabled",
	"ScrollUtil",
	"ScrollBoxConstants",

	-- Menu API
	"Menu",
	"MenuUtil",
	"MenuResponse",
	"IconSelectorPopupFrameModes",
	"IconSelectorPopupFrameIconFilterTypes",
	"IconSelectorPopupFrameTemplateMixin",
	"IconDataProviderMixin",
	"IconDataProviderExtraType",
	"DropdownButtonMixin",
	"InputBoxInstructions_OnTextChanged",
	"SearchBoxTemplate_OnEditFocusLost",
	"SearchBoxTemplateClearButton_OnClick",
	"HideAllInputBoxes",

	-- FrameXML: frames
	"UIParent",
	"MacroFrame",
	"PlayerFrame",
	"PetFrame",
	"TargetFrame",
	"TargetFrameToT",
	"FocusFrame",
	"FocusFrameToT",
	"PartyFrame",
	"SecureStateDriverManager",
	"CompactUnitFrame_SetUpFrame",
	"ScrollingEdit_OnTextChanged",

	-- WoW constants
	"MAX_PARTY_MEMBERS",
	"MAX_RAID_MEMBERS",
	"MAX_ARENA_ENEMIES",
	"MAX_BOSS_FRAMES",
	"MAX_ACCOUNT_MACROS",
	"MAX_CHARACTER_MACROS",
	"NUM_WORLD_RAID_MARKERS",
	"WORLD_RAID_MARKER_ORDER",
	"SOUNDKIT",
	"ChatTypeInfo",
	"DEFAULT_CHAT_FRAME",

	-- Binding headers
	"BINDING_HEADER_MOVEMENT",
	"BINDING_HEADER_INTERFACE",
	"BINDING_HEADER_CHAT",
	"BINDING_HEADER_TARGETING",
	"BINDING_HEADER_RAID_TARGET",
	"BINDING_HEADER_VEHICLE",
	"BINDING_HEADER_CAMERA",
	"BINDING_HEADER_MISC",
	"BINDING_HEADER_OTHER",

	-- Slash command constants
	"SLASH_SCRIPT1",
	"SLASH_CANCELFORM1",
	"SLASH_CAST1",
	"SLASH_USE1",

	-- Color objects
	"GRAY_FONT_COLOR",
	"DISABLED_FONT_COLOR",
	"ERROR_COLOR",
	"INACTIVE_COLOR",
	"HIGHLIGHT_FONT_COLOR",
	"BLUE_FONT_COLOR",
	"WARNING_FONT_COLOR",
	"FULL_PLAYER_NAME",
	"YES",
	"NO",

	-- Libraries
	"LibStub",

	-- Addon globals (set by this addon)
	"DebouncePublic",
	"DebouncePrivate",
	"DebounceVars",
	"DebounceVarsPerChar",
	"Debounce_CompartmentFunc",
	"SlashCmdList",

	-- Mixin globals (for XML templates)
	"DebounceLineMixin",
	"DebounceTabMixin",
	"DebounceSideTabMixin",
	"DebouncePortraitMixin",
	"DebounceFrameMixin",
	"DebounceKeybindFrameMixin",
	"DebounceDetailPanelMixin",
	"DebounceIconSelectorFrameMixin",
	"DebounceOverviewFrameMixin",
	"DebounceOverviewHeaderMixin",
	"DebounceOverviewLineMixin",
	"DebounceStateDriverUpdateThrottleSliderMixin",

	-- Named frames
	"DebounceFrame",
	"DebounceOverviewFrame",
	"DebounceKeybindFrame",
	"DebounceDetailPanel",
	"DebounceIconSelectorFrame",
	"DebounceActionPlacerFrame",

	-- Optional third-party addons
	"Clique",
	"Grid2",
	"DevTool",
	"ViragDevTool_AddData",
}
