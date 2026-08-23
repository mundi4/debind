std = "lua51"
max_line_length = false
codes = true
exclude_files = {
	"**/Libs",
	"reference/**",
	"DebindTest/**",
	"tests/**",
	"node_modules/**",
}
ignore = {
	"112", -- mutating non-standard global (Mixin method assignments)
	"212/self",
	"1/[A-Z][A-Z][A-Z0-9_]+", -- three letter+ uppercase constants (WoW convention)
	-- **211 / 231 / 311 are on.** They were off from the day this file was born
	-- (2026-04-09, the commit that added luacheck to CI) - the price of pointing a linter at a
	-- codebase that had never seen one, not a decision anybody made. An unused local is code
	-- nobody runs, and this repo treats that as evidence rather than noise: three of them
	-- survived a file split in silence before these came back on.
	--
	-- **212 / 213 / 232 stay off, and they are a different class.** An unused argument is a
	-- signature the game hands us, not code we wrote and abandoned.
	--
	-- **`dump` is exempt by name.** `DebindPrivate.dump` is a real debug facility
	-- (`Constants.lua`), and every file carries a local alias for it so a print can be dropped in
	-- and taken back out without touching the header. Deleting the aliases would only mean
	-- retyping one the next time; leaving them warning forever would teach us to skim the list,
	-- and a list nobody reads catches nothing.
	"211/dump",
	"212", -- unused argument
	"213", -- unused loop variable
	"232", -- argument never accessed
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
	"Enum",
	"C_AddOns",
	"C_AssistedCombat",
	"C_ClassTalents",
	"C_CreatureInfo",
	"C_Item",
	"C_KeyBindings",
	"C_MountJournal",
	"C_Spell",
	"C_ToyBox",
	"C_SpellBook",
	"C_SpecializationInfo",
	-- **Not under `C_SpecializationInfo`, despite naming a specialization.** A plain global, the
	-- way `Blizzard_ClassMenu` and the character create screen call it. Naming a spec of a class
	-- that is not this character's has no other route, and the namespaced spelling raised in the
	-- game while luacheck saw an ordinary field read on a known table.
	"GetSpecializationInfoForClassID",
	"C_Timer",
	"EventRegistry",
	"C_TradeSkillUI",

	-- Frame / Secure handler
	"CreateFrame",
	"RegisterUnitWatch",
	"UnregisterUnitWatch",
	"UnitWatchRegistered",
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
	"UnitLevel",
	"UnitRace",
	"UnitSex",
	"UnitFactionGroup",
	"GetNormalizedRealmName",
	"GetRealmName",
	"UnitExists",
	"UnitIsUnit",
	"UnitIsPlayer",
	"UnitInRaid",
	"UnitInParty",
	"UnitSelectionColor",
	"InCombatLockdown",
	"IsInRaid",
	"IsInGroup",
	-- 12.1 secret-value probe; nil on older clients, callers must guard
	"issecretvalue",

	-- Spell / macro / binding
	"GetShapeshiftFormInfo",
	"PlayerHasToy",
	"GetFlyoutInfo",
	"GetFlyoutSlotInfo",
	-- 야수 소환 플라이아웃의 빈 칸을 거르는 데 쓴다. 블리자드도 같은 목적으로 부른다
	-- (`Blizzard_ActionBar/Shared/SpellFlyout.lua`).
	"GetCallPetSpellInfo",
	-- 플라이아웃 배경 조각을 뒤집는 데 쓴다(`Blizzard_SharedXMLBase/TextureUtil.lua`).
	"SetClampedTextureRotation",
	"GetMacroInfo",
	"GetMacroIndexByName",
	"GetNumMacros",
	"CreateMacro",
	"EditMacro",
	"DeleteMacro",
	"GetNumBindings",
	"GetBinding",
	"GetBindingKey",
	"GetBindingText",
	"GetConvertedKeyOrButton",
	"CreateKeyChordStringFromTable",
	"IsMetaKey",
	"SecureGroupHeader_OnLoad",
	"SecureGroupHeader_Update",
	"SecureGroupPetHeader_OnLoad",
	"SecureGroupPetHeader_Update",
	"GetCVarBool",
	"ACTION_BUTTON_USE_KEY_DOWN",
	"GetTime",
	"time",
	"date",
	-- `C_AddOns.EnableAddOn`은 다음 리로드까지 효력이 없다. 그래서 마이그레이션 오버레이의
	-- [켜고 다시 불러오기]가 둘을 같이 한다(Legacy.lua).
	"ReloadUI",

	-- Cursor / Input
	"GetCursorInfo",
	"GetCursorPosition",
	"ClearCursor",
	"GetMouseFoci",
	"GetCurrentKeyBoardFocus",
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
	-- The class icon on a storage row, built out of the class name and drawn inline in the text.
	"GetClassAtlas",
	"CreateAtlasMarkup",
	"CopyTable",
	"CreateTableEnumerator",
	"CreateDataProvider",
	"CreateScrollBoxListLinearView",
	"CreateScrollBoxListGridView",
	-- InputScrollFrameTemplate's own setter for the placeholder inside the box. The XML KeyValue
	-- the template documents resolves a global name, and our strings are `L` keys.
	"InputScrollFrame_SetInstructions",
	-- The same template's `OnTextChanged`. Chained rather than replaced: it is what hides that
	-- placeholder once anything is typed.
	"InputScrollFrame_OnTextChanged",
	-- `UIPanelDynamicResizeButtonTemplate`'s own sizer. The template calls it from an `OnLoad`,
	-- which is before a panel's `OnLoad` has put a label on the button, so the two storage buttons
	-- call it again once they have one.
	"DynamicResizeButton_Resize",
	"CreateAndInitFromMixin",
	"CreateFromMixins",
	"TextureKitConstants",

	-- FrameXML: panels, tooltips, menus
	"GameFontHighlightSmall",
	"GameFontHighlightLarge",
	"GameFontNormalLarge",
	"GameTooltip",
	"GameTooltip_SetTitle",
	"GameTooltip_AddErrorLine",
	"GameTooltip_AddNormalLine",
	"GameTooltip_AddHighlightLine",
	"GameTooltip_AddInstructionLine",
	"SquareButton_SetIcon",
	"SetPortraitTexture",
	"GameTooltip_AddBlankLineToTooltip",
	"GameTooltip_AddColoredLine",
	"GameTooltip_AddColoredDoubleLine",
	"GameTooltip_Hide",
	"StaticPopup_Show",
	"StaticPopup_ShowCustomGenericConfirmation",
	"StaticPopup_ShowCustomGenericInputBox",
	"StaticPopup_FindVisible",
	"StaticPopup_Hide",
	"StaticPopup_IsAnyDialogShown",
	"StaticPopup_IsCustomGenericConfirmationShown",
	"PanelTemplates_SelectTab",
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
	"IconDataProviderIconType",
	"GetLooseMacroIcons",
	"GetLooseMacroItemIcons",
	"GetMacroIcons",
	"GetMacroItemIcons",
	"DropdownButtonMixin",
	"ListHeaderMixin",
	"InputBoxInstructions_OnTextChanged",
	"SearchBoxTemplate_OnEditFocusLost",
	"SearchBoxTemplate_OnEditFocusGained",
	"SearchBoxTemplateClearButton_OnClick",
	"HideAllInputBoxes",

	-- FrameXML: frames
	"UIParent",
	"UISpecialFrames",
	"RegisterGameMenuEscHandler", -- 12.1+
	"GameMenuEscPriority",        -- 12.1+
	"GetUIPanel",
	"GameMenuFrame",
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
	-- MAX_ACCOUNT_MACROS / MAX_CHARACTER_MACROS는 **전역이 아니다.** 블리자드 트리 전체에
	-- 정의가 0건이고 지금은 Constants.MacroConsts 안에 있다. 여기 적혀 있던 동안 luacheck가
	-- 통과시켜서, nil과 비교하는 코드가 게임에서만 터졌다. DebindPrivate.GetMacroSlotLimits()를 쓸 것.
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
	"BRIGHTBLUE_FONT_COLOR",
	"WARNING_FONT_COLOR",
	"GREEN_FONT_COLOR",
	"FULL_PLAYER_NAME",
	"YES",
	"NO",
	-- Per-class localized names, for saying which class a received string came from.
	"LOCALIZED_CLASS_NAMES_MALE",
	-- The drawer's rows carry the date a string arrived. **The client owns the field order** -
	-- enUS puts the month first and koKR the year, and both are in its own globals.
	"FormatShortDate",

	-- Libraries
	"LibStub",

	-- Addon globals (set by this addon)
	"DebindPublic",
	"DebindPrivate",
	"DebindVars",
	"Debind_CompartmentFunc",
	"Debind_CompartmentOnEnter",
	"Debind_CompartmentOnLeave",
	-- Pre-rename globals. Being listed here does not mean we write them.
	--   DebouncePublic       - compatibility alias we still publish (Public.lua)
	--   DebounceVars(PerChar) - old saved variables, read through the dummy addon (Legacy.lua)
	--   Debounce_CompartmentFunc - only ever read, as the signal that the old real addon
	--                              is still installed alongside us (Legacy.lua)
	"DebouncePublic",
	"DebounceVars",
	"DebounceVarsPerChar",
	"Debounce_CompartmentFunc",
	"SlashCmdList",

	-- Mixin globals (for XML templates)
	"DebindDialogMixin",
	"DebindLineMixin",
	"DebindKeyHeaderMixin",
	"DebindOrderLineMixin",
	"DebindTabMixin",
	"DebindPanelTabMixin",
	"DebindSideTabMixin",
	"DebindOptionsButtonMixin",
	"DebindPortraitMixin",
	"DebindFrameMixin",
	"DebindMigrationDialogMixin",
	"DebindLayerPanelMixin",
	"DebindResultPanelMixin",
	"DebindMacroFrameMixin",
	"DebindIconSelectorFrameMixin",
	"DebindStateDriverUpdateThrottleSliderMixin",
	"DebindSpellPickerFrameMixin",
	-- Blizzard's, mixed into `DebindFrame` (`SharedUIPanelTemplates.lua`).
	"CallbackRegistryMixin",
	"DebindStoragePanelMixin",
	"DebindStorageEntryRowMixin",
	"DebindStoragePreviewRowMixin",
	"DebindStoragePreviewLayerMixin",
	"DebindCopyFrameMixin",
	"DebindPasteFrameMixin",
	"DebindKeyCaptureFrameMixin",
	"DebindSpellPickerHeaderMixin",
	"DebindSpellPickerRowMixin",
	"DebindSpellPickerTabMixin",
	"DebindSwitchesPanelMixin",
	"DebindSwitchRowMixin",
	"DebindSwitchLayerRowMixin",

	-- Named frames
	"DebindFrame",
	"DebindMigrationDialog",
	"DebindLayerPanel",
	"DebindResultPanel",
	"DebindMacroFrame",
	"DebindIconSelectorFrame",
	"DebindActionPlacerFrame",
	"DebindSpellPickerFrame",
	"DebindSwitchesPanel",
	"DebindStoragePanel",
	"DebindCopyFrame",
	"DebindPasteFrame",
	"DebindKeyCaptureFrame",

	-- The font of the output box. A generated string is long and has no line breaks, so it needs
	-- a narrow font to fold into a readable number of lines inside the box.
	"ChatFontNormal",

	-- Optional third-party addons
	"Clique",
	"Grid2",
	"DevTool",
	"ViragDevTool_AddData",
}
