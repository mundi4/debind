local _, addon = ...;
addon.L = setmetatable({}, { __index = function(_, key) return key end });
local L = addon.L;

-- 색은 **클라이언트 색 이름**으로 쓴다(`|cnRED_FONT_COLOR:`). 날 hex는 애드온 고유색인
-- _MESSAGE_PREFIX 하나뿐이다 - 그것만 우리 것이고 나머지는 게임의 것이라, 게임이 색을
-- 바꾸면 같이 바뀌어야 맞다. 한때 같은 뜻에 hex와 색 이름이 섞여서, 빨강 하나가
-- 문자열마다 다른 빨강이었다.
L["_MESSAGE_PREFIX"] = "|cff3b9de3[Debind]|r "
L["ADDON_NAME"] = "Debind"
L["ALL"] = "All"
-- 여럿을 고른 채로 연 우클릭 메뉴의 제목. 이름을 나열하지 않는 이유는 DELETE_CONFIRM_MESSAGE_MULTIPLE
-- 쪽 주석에 있다. 아래 카운트와 낱말을 맞춘다 - 한 화면에서 같은 것을 두 가지로 부르지 않는다.
L["BULK_MENU_TITLE"] = "%d selected"
-- 목록 위 스트립. 고른 것이 둘 이상일 때만 뜬다 - 하나일 때는 행 강조가 이미 말했다.
L["BULK_SELECTED_COUNT"] = "%d selected"
-- 조건 툴팁에서 조건 이름(CONDITION_BONUSBAR / CONDITION_GROUP) **바로 아래** 붙는 줄이다.
-- 둘 다 "No option is selected."였는데, 그러면 같은 툴팁에 두 번 떠도 어느 쪽 이야기인지
-- 줄만 봐서는 모른다. FORMS/HOVER처럼 무엇이 안 골렸는지를 말한다.
-- The toggle in the portrait row. With it on, pointing at a row and pressing a key is the whole
-- act. The reasoning is in the `BindModePortrait` comment in DebindUI.xml.
--
-- **It names the mode, not the act** ("Set Keys" before). What the toggle turns on outlives the
-- press, and a verb on a control that stays lit reads as a one-shot.
--
-- The client owns this concept for the action bars - `QUICK_KEYBIND_MODE`, "Quick Keybind Mode" -
-- and we deliberately do not take that string: ours is a different mode in a different window, and
-- borrowing the name would promise the game's. "Bind Mode" is still the client's own compound
-- (`QUICK_KEYBIND_MODE_BUTTON` reads "Quick Bind Mode"), so no word here is invented.
--
-- The second one is what the toggle says while the mode is on, and it is a tooltip title now that
-- the button carries an icon instead of a label. It stays a verb: at that point the only thing left
-- to say about the button is what pressing it now does.
L["BIND_MODE"] = "Bind Mode"
L["BIND_MODE_STOP"] = "Done"
-- **This used to be the client global `ESCAPE_TO_UNBIND`, and that was the wrong sentence in this
-- position.** The client hangs it off the very button being hovered (`QuickKeybindTooltip`), where
-- "this action" points at something. Ours is nailed to a standing overlay in the left column, so
-- "this" has nothing to point at. Worse, the reader most likely to be reading it is pointing at
-- nothing, which is the one state where Escape does not unbind anything at all.
--
-- So it names the condition instead of pointing, and it carries **both** of Escape's meanings. The
-- second one cannot be taken back, and [Cancel] is the only other place that says it exists.
--
-- **Two lines, because it is one key with two meanings and the reader has to pick theirs.** Run
-- together, the second half reads as a footnote to the first; broken at `|n` the two stand as a
-- pair, opening on the thing that tells them apart. `README.md` carries the same two facts as a
-- two-item list.
--
-- The cost, taken knowingly: the client global came out in the reader's own language for free, and
-- every locale now has to translate this. Korean and Russian read this English line until they do.
L["BIND_MODE_UNBIND_HINT"] = "If you are pointing at an action, Escape clears its key.|nIf you are pointing at nothing, Escape puts back every key you changed and leaves."
L["BIND_MODE_CANCEL"] = "Cancel"
L["BIND_MODE_OVERLAY"] = "Point at an action on the right and press the key you want."
L["BIND_MODE_DESC"] = "Turns on a mode where whatever you press becomes the key for the action under your cursor. Selecting and the right-click menu pause while it is on."
L["BINDING_ERROR_BONUSBARS_NONE_SELECTED"] = "No action bar is selected."
L["BINDING_ERROR_CANNOT_USE_HOVER_WITH_CLIQUE"] = "Cannot be used with Clique!"
L["BINDING_ERROR_CONDITIONS_NEVER"] = "The conditions are impossible to meet."
L["BINDING_ERROR_FORMS_NONE_SELECTED"] = "No shapeshift form is selected."
L["BINDING_ERROR_GROUPS_NONE_SELECTED"] = "No group type is selected."
L["BINDING_ERROR_HOVER_NONE_SELECTED"] = "No reaction or frame type is selected."
-- The fourth of the *_NONE_SELECTED family, and the only one that is not about a condition: the
-- action itself has not been told which switch it works. Kept apart from the line below on
-- purpose. "You have not picked one" and "the one you picked is gone" send the reader to two
-- different places, and the second names a switch while this one has none to name.
L["BINDING_ERROR_SWITCH_NONE_SELECTED"] = "No switch is picked. Until one is, this binding does not fire at all."
L["BINDING_ERROR_NOT_SUPPORTED_GAMEMENU_KEY"] = "The key assigned for |cnHIGHLIGHT_FONT_COLOR:Toggle Game Menu|r cannot be used."
L["BINDING_ERROR_NOT_SUPPORTED_HOVER_CLICK_COMMAND"] = "Mouse buttons cannot be used for Binding Command that uses the hover condition."
L["BINDING_ERROR_NOT_SUPPORTED_MOUSE_BUTTON"] = "The left/right mouse button without modifier keys can only be used with the hover condition."
-- %s is the name the action carries: written into a macro body, or picked as what an on/off/toggle
-- action sets. **This line and the macro one below are the only errors that take an argument** --
-- every other BINDING_ERROR_* is about a condition, and which condition is already visible in the
-- box it belongs to. Neither of these two has a box, so without the name there is nothing on
-- screen saying what to fix.
L["BINDING_ERROR_UNDEFINED_STATE"] = "There is no switch named |cnHIGHLIGHT_FONT_COLOR:%s|r. Until the name is fixed this binding does not fire at all."
-- The second line that takes an argument, for the reason above: a macro name also lives inside the
-- action rather than in a condition control.
--
-- It goes on to name the two ways this happens. A macro name is something the user chose
-- themselves, so "there is no such macro" on its own reads as a typo -- while the common case, now
-- that bindings travel, is a binding that came from a machine where that macro did exist.
L["BINDING_ERROR_MISSING_MACRO"] = "There is no macro named |cnHIGHLIGHT_FONT_COLOR:%s|r on this account or character. It may have been renamed or deleted, or it may have come from someone else's setup."
-- The only MINOR code, so this states what happened and stops there. The key itself still fires,
-- and leaving an outranked action in place is a choice the reader is allowed to make.
--
-- Two things it must not say. The coverage can come from several earlier actions at once
-- (`CheckUnreachableBindings` hands the whole set to `isCovered`), so sending the reader off to
-- look at one action points at something that may not exist. And this action may carry no
-- conditions at all, so any wording resting on the situations it was set up for is false for the
-- plainest case there is, two condition-less actions on one key.
--
-- "No matter what" is what the sentence turns on. Every action but the first is preceded by others,
-- which is what this line said before, and it was true of the healthy rows just as much.
L["BINDING_ERROR_UNREACHABLE"] = "This action never runs. No matter what, another action on this key gets there first."
L["BINDING_TITLE"] = "%2$s (%1$s)"
L["BLIZZARD_UNIT_FRAMES_ARENA"] = "Arena Frames"
L["BLIZZARD_UNIT_FRAMES_BOSS"] = "Boss Frames"
L["BLIZZARD_UNIT_FRAMES_PARTY"] = "Party Frames"
L["BLIZZARD_UNIT_FRAMES_PET"] = "Pet Frame"
L["BLIZZARD_UNIT_FRAMES_PLAYER"] = "Player Frame"
L["BLIZZARD_UNIT_FRAMES_RAID"] = "Raid Frames"
L["BLIZZARD_UNIT_FRAMES_TARGET"] = "Target And Focus"
L["BLIZZARD_UNIT_FRAMES"] = "Blizzard unit frames"
L["CANNOT_OPEN_IN_COMBAT"] = "Cannot open in combat."
L["CANNOT_OPEN_WITH_GAME_MENU"] = "Close the game menu first."
L["COMPARTMENT_TOOLTIP_LEFT_CLICK"] = "Click to open Debind. The bindings overview is the left column."
L["CONDITION_ACTIONBARS"] = "Action Bars"
L["CONDITION_BONUSBAR"] = "Stance-based Action Bar"
L["CONDITION_COMBAT_NO"] = "While Not in Combat"
L["CONDITION_COMBAT_YES"] = "While in Combat"
L["CONDITION_COMBAT"] = "Combat"
L["CONDITION_CUSTOM_STATES"] = "Switches"
L["CONDITION_CUSTOM_STATE_NO"] = "When the Switch Is Off"
L["CONDITION_CUSTOM_STATE_YES"] = "When the Switch Is On"
L["CONDITION_EXTRABAR_NO"] = "When the Extra Action Button Is Not Present"
L["CONDITION_EXTRABAR_YES"] = "When the Extra Action Button Is Present"
L["CONDITION_EXTRABAR"] = "Extra Action Button"
L["CONDITION_FRAMETYPES"] = "Unit Frame Types"
L["CONDITION_GROUP"] = "Group";
L["CONDITION_HOVER_NO"] = "When Not Hovered Over"
L["CONDITION_HOVER_YES"] = "When Hovered Over"
L["CONDITION_HOVER"] = "Hovering Over Unit Frame"
L["CONDITION_KNOWN"] = "Known"
L["CONDITION_KNOWN_YES"] = "Only When Spell Known"
L["CONDITION_PET_NO"] = "While Without a Pet"
L["CONDITION_PET_YES"] = "While With a Pet"
L["CONDITION_PET"] = "Pet"
L["CONDITION_PETBATTLE_NO"] = "Not in a Pet Battle"
L["CONDITION_PETBATTLE_YES"] = "In a Pet Battle"
L["CONDITION_PETBATTLE"] = "Pet Battle"
L["CONDITION_REACTIONS"] = "Reactions"
L["CONDITION_SHAPESHIFT"] = "Shapeshift"
L["CONDITION_SPECIALBAR_DESC"] = "Active while something has replaced your main action bar -- a vehicle, a possession, and the like."
L["CONDITION_SPECIALBAR_NO"] = "While a Special Bar Is Not Active"
L["CONDITION_SPECIALBAR_YES"] = "While a Special Bar Is Active"
L["CONDITION_SPECIALBAR"] = "Special Bar"
L["CONDITION_STEALTH_NO"] = "While Not Stealthed"
L["CONDITION_STEALTH_YES"] = "While Stealthed"
L["CONDITION_STEALTH"] = "Stealth"
L["CONDITION_UNIT_DOES_NOT_EXIST"] = "When the unit doesn't exist"
L["CONDITION_UNIT_EXISTS"] = "When the unit exists"
L["CONDITION_LIFE"] = "Alive or Dead"
L["CONDITION_UNITS"] = "Units"
L["CONFIRM_CURRENT_CHANGE_FIRST"] = "Confirm current change first."
L["CONVERT_TO_MACRO_TEXT"] = "Convert to a |cnLIGHTBLUE_FONT_COLOR:Custom Macro|r"
L["COPY_TO"] = "Copy to..."
-- 이동·복사 목록에서 지금 그 액션이 사는 탭. %s는 다른 줄과 **똑같은** 탭 이름이고, 뒤에
-- 붙는 표시만 그 줄을 가른다 - 이름을 갈아치우면 목록에서 그 탭의 자리를 잃는다.
L["CURRENT_TAB_SUFFIX"] = "%s |cnLIGHTGRAY_FONT_COLOR:(current)|r"
L["CUSTOM_STATE_DISPLAY_MESSAGE"] = "Show message on change."
L["CUSTOM_STATE_EDIT_VALUE_DESC"] = "Enter macro conditional expression.\n(Example: |cnHIGHLIGHT_FONT_COLOR:[@tank,exists,combat]|r)"
L["CUSTOM_STATE_EDIT_VALUE"] = "Enter macro conditional expression."
L["CUSTOM_STATE_MODE_MACRO_CONDITIONAL_DESC"] = "This option lets the addon determine the value of the switch based on macro conditional expressions (Example: |cnHIGHLIGHT_FONT_COLOR:[@healer,exists]|r)."
L["CUSTOM_STATE_MODE_MACRO_CONDITIONAL"] = "Set Automatically"
L["CUSTOM_STATE_OFF"] = "Off"
L["CUSTOM_STATE_ON"] = "On"
-- What a switch is, said once. The Switches tab's own tooltip prints it (PANELS in DebindUI.lua)
-- and so does the condition menu's switch group, which is handed this key explicitly
-- (CreateSwitchConditionMenu in DropDownMenus.lua). A twin key, CONDITION_CUSTOM_STATES_DESC, used
-- to hold a paragraph that did not differ from this one by a single character, which meant
-- translating the same text twice in every locale.
--
-- It said "the tooltip of the SwitchesPortrait button" until 3c took that button off the window.
L["CUSTOM_STATES_DESC"] = "These are ON/OFF switches that can be used as special conditions or macro conditional expressions in |cnLIGHTBLUE_FONT_COLOR:Custom Macros|r (Example: |cnHIGHLIGHT_FONT_COLOR:[$state1]|r). You can turn these switches on or off at any time, or you can set them as macro conditionals themselves."
L["CUSTOM_STATES"] = "Switches"
L["CUSTOM_TARGET_FAILED"] = "|cnHIGHLIGHT_FONT_COLOR:%1$s|r - |cnRED_FONT_COLOR:Failed to set from '%2$s'|r"
L["CUSTOM_TARGET_HELP_MESSAGE_ARENA"] = "Try while hovering over arena frames."
L["CUSTOM_TARGET_HELP_MESSAGE_BOSS"] = "Try while hovering over boss frames."
L["CUSTOM_TARGET_HELP_MESSAGE_GROUP"] = "Try while hovering over party/raid frames."
L["CUSTOM_TARGET_HELP_MESSAGE_PET"] = "Try while hovering over the pet frame."
L["CUSTOM_TARGET_HELP_MESSAGE_PLAYER"] = "Try while hovering over the player frame or party/raid frames."
L["CUSTOM_TARGET_INVALIDATED"] = "|cnHIGHLIGHT_FONT_COLOR:%s|r - |cnRED_FONT_COLOR:Cleared|r - it was held by group slot, not by name, and the group changed. Set it again."
L["CUSTOM_TARGET_SET_VOLATILE"] = "|cnHIGHLIGHT_FONT_COLOR:%1$s|r - Set to %2$s - held by group slot rather than by name, because the group changed during this fight. Set it again after combat and it will follow them."
L["CUSTOM_TARGET_UNSUPPORTED_UNIT_IN_COMBAT"] = "|cnHIGHLIGHT_FONT_COLOR:%1$s|r - |cnRED_FONT_COLOR:Cannot be set from '%2$s' in combat|r"
L["CUSTOM_TARGET_UNSUPPORTED_UNIT"] = "|cnHIGHLIGHT_FONT_COLOR:%1$s|r - |cnRED_FONT_COLOR:Not supported unit: %2$s|r"
L["DEFAULT"] = "Default"
L["DELETE_CONFIRM_MESSAGE"] = "Are you sure you want to delete |cnHIGHLIGHT_FONT_COLOR:%s|r?"
-- 여럿을 한꺼번에 지울 때. **이름 대신 개수로 묻는다** - 열몇 개를 나열하면 팝업이 화면을
-- 덮고, 몇 개만 적으면 나머지를 숨긴 채로 묻는 꼴이 된다.
L["DELETE_CONFIRM_MESSAGE_MULTIPLE"] = "Are you sure you want to delete |cnHIGHLIGHT_FONT_COLOR:%d|r actions?"
L["DELETE"] = "Delete"
-- 클라이언트가 이미 모든 언어로 갖고 있는 말이다. 여기서 한 번 받아두면 로케일 파일이
-- 없는 언어도 제 나라 말로 나온다.
--
-- 단축키 버튼과 행 툴팁이 **같이** 쓴다. 한때 행 툴팁만 따로 L["NOT_BOUND"]를 들고
-- 있었는데, 그러면 로케일이 손으로 옮긴 말과 클라이언트의 말이 같은 창 안에서 갈릴 수
-- 있었다 - 같은 뜻은 한 군데서만 나와야 한다.
L["OVERVIEW_NO_KEY"] = NOT_BOUND
-- What a folded key group's heading says after the first action's name: how many more are under it.
-- **Not a total** - the one being named is not counted again, so a key with two actions reads
-- "Charge +1".
--
-- A sign and a number and nothing else, because it sits inside a line that is already carrying a
-- key and a name. Anything wordier and the name it belongs to starts losing characters to it: what
-- shortens when the bar runs out is the name, never this.
L["OVERVIEW_KEY_HEADER_MORE"] = "+%d"
-- What the folded pile with no key says instead. **A total, not a "+N"** - nothing is named beside
-- it, because the pile is sorted by name and its first entry is only alphabetically first. A key
-- group's first row is what that key actually sends; this one represents nothing.
--
-- Dropping the sign is what tells the two apart, since they stand in the same place: "+1" counts
-- what is not named, this counts everything.
--
-- `|4` is the client's own plural form, resolved when the string is drawn rather than by `format`
-- (`BN_TOAST_PENDING_INVITES` and `D_MINUTES` are handed straight to a FontString the same way).
-- Russian takes three forms in that escape, not two.
L["OVERVIEW_NO_KEY_COUNT"] = "%d |4action:actions;"
-- 이 열은 접히지 않으므로 빈 자리가 늘 보인다. "비었다"가 아니라 **무엇을 하면 채워지는지**를
-- 말한다 - 오른쪽 목록의 빈 문장들과 같은 규칙이다.
L["OVERVIEW_EMPTY"] = "No key is bound yet. Give an action a key on the right and it turns up here."
L["DISABLE"] = "Disable"
L["DISABLE_ALL"] = "Disable All"
L["EDIT_MACRO"] = "Edit Macro"
L["ERROR_MESSAGE_CANNOT_SET_CUSTOM_TARGET_IN_COMBAT"] = "Cannot set a custom target by command while in combat."
L["EXCLUDE_PLAYER_DESC"] = "Exclude self from role-based unit detection."
L["EXCLUDE_PLAYER"] = "Exclude self"
L["FRAMETYPE_ARENA"] = "Arena Frames"
L["FRAMETYPE_BOSS"] = "Boss Frames"
L["FRAMETYPE_GROUP"] = "Party/Raid Frames"
L["FRAMETYPE_PET"] = "Pet Frame"
L["FRAMETYPE_PLAYER"] = "Player Frame"
L["FRAMETYPE_TARGET"] = "Target And Focus"
L["FRAMETYPE_UNKNOWN"] = "Others"
L["GENERAL"] = "General"
-- 목록 위의 체크박스. 묶어도 줄 순서는 이름순이라는 것과, 진짜 발동 순서는 어디서
-- 보는지를 툴팁이 대신 말한다 - 그걸 말할 자리가 여기밖에 없다(InitializeButtons 참고).
-- 축은 비교자와 **같은 수, 같은 차례**로 적는다(Ordering.lua의 CompareActionOrder).
-- 한때 hover가 빠져 있었는데, 그건 중요도 바로 다음에 오는 축이고 이 애드온에서 제일
-- 자주 순서를 가르는 것이기도 하다. 어디서 보는지는 **화면에 있는 그대로** 적는다 -
-- 한때 "Key & Order 탭"이었고 그 탭이 없어졌다. 없는 것을 부르면 찾다가 못 찾는다.
L["GROUP_NONE"] = "When Not In Group";
L["GROUP_PARTY"] = "When In Party";
L["GROUP_RAID"] = "When In Raid";
L["IGNORE_HOVER_UNIT_DESC"] = "When selected, the action ignores the unit frame's unit."
L["IGNORE_HOVER_UNIT"] = "Ignore hover unit"
-- The last line on a spec tab that is not the one being played. The line above it states the
-- layer's precedence in the present tense, which is not true while the layer is out of play; this
-- says when it starts being true.
--
-- **No verb for entering the spec.** "Switch to it" and the like read equally well as "click this
-- tab" -- which is what the reader's cursor is on and what they are about to do -- and that
-- reading is false, since clicking does not make the layer apply. A state ("when you're in this
-- spec") cannot be read the second way.
L["INACTIVE_SPEC_DESC"] = "Keys you put here start working when you're in this spec."
L["INACTIVE_SPEC_LABEL"] = "%s (Inactive)"
L["KEEP_IN_BINDING_CONTEXT_DESC"] = "The house editor claims a few keys for its own shortcuts while it is open, and this addon leaves those keys alone. An action bound to one of them does nothing while the editor is open.|n|nCheck this to take the key anyway: your action runs, and the editor's shortcut on that key does not. The editor still shows the key on its own button, so that button will look usable while doing nothing."
L["KEEP_IN_BINDING_CONTEXT"] = "Override the house editor"
L["KEY"] = "Key"
--- The dialog that asks for one key, for one action or one set of them (`KeyCapture.lua`).
---
--- **The title is the instruction**, which is what the other three dialogs in this window do -
--- "Bring in - %s", "Paste a Debind string", `EXPORT_COPY_TITLE`. Each of them names the act the
--- reader came to perform. `KEY_BINDING` stood here first and was the odd one out: the client's word
--- for the settings *category*, a noun where the neighbours are all verbs, saying nothing about what
--- pressing something now would do.
---
--- **And it does not name the target**, because the dialog shows it - the actions about to get the
--- key are listed under this line with their icons, the way every other list in the addon draws an
--- action. Saying "for Wrath +2" in a sentence was the version that had to stand in for showing
--- them.
L["KEY_CAPTURE_TITLE"] = "Assign a Key"
--- **The middle clause is the one that earns its place.** That mouse buttons and the wheel are keys
--- here is where this addon parts company with the game's own keybinding panel, which will not take
--- them - so a reader who knows that panel does not try, and nothing else on screen says otherwise.
---
--- The last clause is the rule that cannot be guessed at all: those are read where they land, and
--- landing anywhere else does whatever it always does. The keyboard has no such condition and the
--- line does not raise one - saying it works anywhere only made the reader wonder why it was worth
--- mentioning.
L["KEY_CAPTURE_DESC"] = "Press any key to assign it - mouse buttons and the wheel included, but those only count over this window."
--- The key the set is on today, said once over the whole list. **A label, not a sentence**, because
--- what follows it is the value - which is also what [Unbind Key] is talking about, so the button
--- being lit or dead has something on screen to point at.
L["KEY_CAPTURE_CURRENT_KEY"] = "Current key:"
--- What the line above says when the actions being asked about are **not all on the same key**. It
--- is the state a hand-made selection can be in and a key group never is, so it arrived with this
--- window being opened on more than a key group.
---
--- **Not the first one's key.** The rows are listed right underneath, so naming one of several keys
--- is the window contradicting itself in the space of two lines.
---
--- Deliberately not a count. "3 keys" invites the reader to work out which three, and the answer to
--- that is the list below - what this line has to say is only that there is no single answer.
L["KEY_CAPTURE_CURRENT_KEY_MIXED"] = "More than one"
--- The caption over the list. **It reads for one action and for twelve** - a set on one key is the
--- ordinary case here, so "this action" would be wrong more often than not.
L["KEY_CAPTURE_TARGETS"] = "Applies to these actions:"
--- Only when the set is longer than the dialog will draw. **The cap is what this is for**: a key
--- group has no ceiling the addon can name, and a dialog that grows with it walks off the screen.
--- Everything counted here is still getting the key - the line says what is not being drawn, not
--- what is being left out.
L["KEY_CAPTURE_MORE"] = "...and %d more"
--- A row's right-click item. **Same three words as the heading's** (`KEY_HEADER_SET_KEY`), because
--- the act is the same one and the same dialog opens; what differs is how much of the column it
--- reaches, and that is said by where the reader clicked and by the tooltip below. Two keys and not
--- one, so the two tooltips can never be made to share a sentence they only half fit.
L["ACTION_SET_KEY"] = "Assign a key"
-- The same item on a row that arrived and has not been accepted. **Giving one a key accepts it**
-- (`DebindFrameMixin:SetActionKey`), which the reader had no way of knowing before pressing.
--
-- **The three words stay, and a clause goes after them** (2026-08-23, 소유자). They are the act's
-- name at every scope it is offered at, so replacing them here would make this look like a
-- different operation; what is added is the half that is true only on this row.
--
-- **`&`, and it is doing a different job from the client's** (2026-08-23, 소유자). The client keeps
-- the ampersand for pairs of nouns ("Dungeons & Raids") and spells the word out on a button that
-- does two things ("Save and Exit"). In a menu the two halves have to be told apart at a glance
-- from the item above, which is the first half on its own - the ampersand is the mark that reads as
-- a join before the words are read at all.
L["ACTION_SET_KEY_ACCEPT"] = "Assign a key & Accept"
--- **The one thing this has to say is what happens to the rest.** A key's actions are told apart by
--- conditions, on purpose - so a row walking off to its own key produces no error, no warning and
--- nothing on screen that looks wrong. The reader finds out later, when two keys each do half of
--- what one key used to do.
---
--- **It is not written as a mistake**, because it is not one: giving one condition its own shortcut
--- is a thing people mean to do. It is written as what happens, and the reader decides.
---
--- **It does not describe the dialog.** The opening line used to say "the key you press", which is
--- wrong twice over - the answer can be a mouse button or the wheel, and it can be [Unbind Key],
--- which presses nothing and still takes this action out of the set. How the key is given is the
--- dialog's own line to say (`KEY_CAPTURE_DESC`); this one says who it is given to.
---
--- **One string for two lists, and the conditional is what makes that possible.** It is read from
--- the overview's rows, where the set is drawn under one heading, and from the bin's, where the list
--- is one layer in name order and nothing says a key can carry several actions at all. "If this
--- action is part of a set on one key" carries its own premise, so it introduces the fact for the
--- reader who cannot see it and merely points at it for the reader who can.
---
--- Three earlier wordings assumed the overview and read as a non-sequitur in the bin: "the ones it
--- is listed with" (names the wrong rows there), "only this one moves" (nothing moves there), and
--- opening on "this action alone", which answers a question that list gives nobody a reason to ask.
---
--- It is also right that the clause is conditional rather than flat. Most actions are alone on their
--- key, and announcing what happens to "the others" every time describes a situation the reader is
--- usually not in.
---
--- "Group" is not available for any of it: in this window that word is the party/raid kind
--- (`CONDITION_GROUP`).
L["ACTION_SET_KEY_DESC"] = "Sets the key for this action.|n|nIf this action is part of a set sharing one key, only this action changes - the rest keep the key they are on. Both keys still work; they just stop working as one."
-- The same item on a row that arrived, where the line above is **false**: "both keys still work" is
-- what happens between two sets of the reader's own, and the set this one is leaving is pending - so
-- its key does nothing at all.
--
-- **And the warning does not come back in another form** (2026-08-23, 소유자). It is there above
-- because a set of the reader's own comes apart with nothing to show for it until both halves fire.
-- What is left behind here is drawn in the arrival's blue and is still sitting on screen, so the
-- reader is told by the list rather than by a sentence.
L["ACTION_SET_KEY_ACCEPT_DESC"] = "Sets the key for this action and takes it: it starts working on that key."
--- Asked when the key that was pressed is already carrying something.
---
--- **The count is what this dialog is for.** The walk behind it reaches every layer this character
--- has, so some of what is being counted can be off screen right now - another specialization's, or
--- hidden by the "only what came in" switch. Saying the number before the choice is how that is paid
--- for, the same way "Accept all %d" pays for reaching past the screen.
---
--- **It used to say "counting every specialization of this character", which drew the line in the
--- wrong place.** Those eleven layers are not all this character's: two of them belong to the class
--- and one to the account (`EnumerateAllProfileLayers`), so an action counted here can be one that is
--- on that key for every character the reader has. Naming specializations made the sentence sound
--- like the reach stopped at this character, and the answer beside it takes the key away from
--- whatever is counted - which is where that mattered. It now says what the number is: everything
--- that key does here. Who else that touches is `KEY_GROUP_CONFLICT_SHARED`'s line, and only when
--- there is somebody.
---
--- Numbered placeholders because two of them are strings; the rule is in
--- `devdocs/writing-user-facing-text.md`.
L["KEY_GROUP_CONFLICT"] = "|cnHIGHLIGHT_FONT_COLOR:%2$s|r already has |cnHIGHLIGHT_FONT_COLOR:%3$d|r actions on it - everything that key does on this character, whichever specialization they belong to.|n|nWhat should happen to them when |cnHIGHLIGHT_FONT_COLOR:%1$s|r moves there?"
--- Added under the question when any of the ones being counted lives in a shared scope.
---
--- **Only then, because most of the time it is not true**, and a dialog that warns about other
--- characters every time teaches the reader to stop reading it. The test is the layer's own
--- `isCharacterSpecific`, the same one the importance menu asks before it warns
--- (`IMPORTANCE_SHARED_WARNING`).
---
--- **It does not name the button.** Spelling out what [Overwrite] says leaves this sentence pointing
--- at something that is not there the day that word changes, and a line here has already died that
--- way. "Taking the key from them" is the same act named by what it does.
L["KEY_GROUP_CONFLICT_SHARED"] = "Some of them are your other characters' as well - they are on that key there too, and taking the key from them takes it everywhere."
--- **Not a compromise, and not a warning.** Several actions on one key, told apart by conditions, is
--- what this addon is for - so the answer that puts the two sets on one key needs no caveat.
---
--- **It said "Keep both", and before that "Merge", and it is back to `Merge` because the objection
--- that killed it stopped being true.** That objection was that nothing is combined -- the two sets
--- simply both sat on the key with their conditions telling them apart, because what arrived was
--- parked on a key of its own. It is not parked anywhere now: accepting moves it onto `(key, nil)`,
--- the reader's own group, and `RenumberKeyGroup` ranks the two as **one** group, 1..n
--- (`devdocs/building-export-import.md` 12절). Combining is exactly what happens.
---
--- The other half of that objection was that the client does not use the word. That test answers
--- "is there a word here to reuse", and it was being read as "would a reader know this one" -- which
--- it does not answer at all. Somebody who plays this game has merged a save, a profile and an addon
--- config, and `Merge` costs them nothing to read (2026-08-23, owner).
---
--- **And it says what `Keep both` could not.** "Both" names the outcome and leaves the mechanism to
--- the tooltip; the mechanism is the part the reader has to picture, because from here on the two
--- move as one and the order between them is a thing they own.
L["KEY_GROUP_CONFLICT_KEEP"] = "Merge"
--- On the button, because **the two answers to this question are the two most expensive things in
--- the window** and a word each is not enough for either. One of them takes bindings off keys.
---
--- What this one adds is the part nobody expects: **the order becomes a decision**. A key runs down
--- its list and fires the first action whose conditions match, so two sets landing on one key means
--- the ranking now decides between them - and nobody chose that ranking, it fell out of the two sets
--- having been written at different times.
---
--- That both sides are kept is the label's line and is not repeated here, the same trim "the key you
--- press" got. **Where the order is changed is not named either**: spelling out a tab or a menu is a
--- sentence pointing at something that can be renamed out from under it.
L["KEY_GROUP_CONFLICT_KEEP_DESC"] = "Pressing the key then runs down the list until something matches, so which one goes off depends on the order they land in - and that order is yours to change."
--- **The client's own verb for this, and the reader met it a moment ago** - `UNBIND` is a global
--- ("Unbind Key"), it is what the button on the key capture dialog says, and it names exactly what
--- happens to these: they lose the key and nothing else.
---
--- It said "Overwrite" for a while, which is not a client word either (the one place the game names
--- that idea, `TUTORIAL_PERKS_PROGRAM_OVERWRITE_FROZEN_ITEM`, reads "Replace") and which overstates
--- what happens - it sounds like a delete, and nothing is deleted.
---
--- **This pair was rejected once and is back on purpose.** The objection was that the two buttons
--- answer different questions - this one says what happens to the occupants, its partner describes
--- what the key ends up holding - and that is still true. It was accepted because the pair that
--- replaced it had the same fault ("Merge" is an end state too) while spending two words the client
--- does not use, and because the wording that would have fixed the axis reads as [Cancel] beside a
--- button that unbinds. The mismatch is the cheaper fault; `building-export-import.md` has the line.
L["KEY_GROUP_CONFLICT_UNBIND"] = "Unbind them"
--- Two things the label cannot say: **how far it reaches** and **what it does not do.**
---
--- The reach, because the count above is every layer this character has and some of those rows are
--- not on screen - another specialization's, or filtered out. The reader is answering about things
--- they cannot see, which is the same debt the prompt's number is paying.
---
--- And **what it cannot put back.** Nothing is deleted, and each of them can be given a key again --
--- but they stop being one set, and which ones belonged together is not written down anywhere. The
--- half-sentence this used to be read as "you can undo this", which is false for the part that
--- matters. Saying it here rather than in the label keeps the button one act long.
L["KEY_GROUP_CONFLICT_UNBIND_DESC"] = "All of them, not just the ones you can see - the count above is every layer this character has. Nothing is deleted: each one ends up with no key at the bottom of the list, where you can give it one again. They stop being one set, though, and nothing records which ones went together."
--- The heading's item. **The words are `ACTION_SET_KEY`'s** - the act is the same and the same
--- dialog opens - and how much of the column it reaches is left to the tooltip.
---
--- **The scope is not in the label, and the reason is width.** "Everything under this" was tried
--- here and the menu came out wider than the bar it hangs off: a context menu takes the width of its
--- longest line, and this menu has two lines and no third to hide behind. What pays for the short
--- label is **the position and the title above it** - the reader right-clicked the set's own bar,
--- and the title names that set by what is in it.
---
--- **The act is named the way the window it opens names itself** (`KEY_CAPTURE_TITLE`). The press
--- lands in that dialog, so a reader who takes the item and a reader who reads the title are being
--- told the same thing. Separate keys on purpose - if that dialog is ever renamed, whether this
--- follows is a decision, not a rename that happens to it.
--- The heading's tooltip, and the only line in it. **It exists because the gesture it names is the
--- one thing on this bar that nothing points at**, and since the row menu stopped offering the set's
--- own items there is no other way in to them.
---
--- **Folding is not mentioned, and that is the rule rather than an omission.** Not knowing it costs
--- the reader nothing: the column opens expanded, so a fold they never discover leaves every action
--- and every operation reachable. Not knowing the right-click costs them the whole menu. The bar's
--- end cap is Blizzard's own collapse art besides, so the visible half teaches itself.
---
--- "under this heading" rather than "on this key", because a set can be sitting on no key at all and
--- the heading still stands over it - and because that is the phrase the item's own tooltip uses
--- (`KEY_HEADER_SET_KEY_DESC`). One set, one way of naming it per screen.
L["KEY_HEADER_TOOLTIP_INSTRUCTION"] = "Right-click for what can be done to everything under this heading."
L["KEY_HEADER_SET_KEY"] = "Assign a key"
--- The heading's import items.
---
--- **A heading stands over rows nobody picked**, and what is waiting under it can be five scattered
--- through twelve that are already the reader's - so the item has to say what it is about to gather.
--- Where the reader chose the target by hand the count is theirs already and the plain label reads
--- better, which is why the row and bulk menus keep `APPROVE_IMPORT` / `REJECT_IMPORT`.
---
--- **It names the state and does not point.** "Accept these 5" was written first and contradicts
--- itself over a heading with twelve rows under it: "these" claims the rows, the number is a
--- fraction of them, and the label cannot say which fraction. "Still waiting" is the subset itself,
--- and it is the phrase this screen already uses for it (`APPROVE_ALL_IMPORT_DESC`).
---
--- **Not the strip's "Accept all %d".** That one reaches the whole profile, and "all" is exactly the
--- word that would make this promise more than it does: these take what is drawn under this one
--- heading and nothing else.
---
--- **A singular of its own**, because "the 1 still waiting" is not English and falling back to the
--- bare `APPROVE_IMPORT` would put the pointing problem back - over twelve rows, a label with no
--- count in it reads as all of them.
L["KEY_HEADER_APPROVE"] = "Accept the %d still waiting"
L["KEY_HEADER_APPROVE_ONE"] = "Accept the one still waiting"
L["KEY_HEADER_REJECT"] = "Reject the %d still waiting"
L["KEY_HEADER_REJECT_ONE"] = "Reject the one still waiting"
-- **[Unbind] came off the heading's menu** (2026-08-23, 소유자) and this went with it. The other end
-- of that axis is a button on the window [Assign a key] opens, over the same set, so the menu item
-- was a second door to it that could scatter a set without the reader having gone to decide its
-- key. What the sentence here explained lives on that button now.
--- **This is where the label's missing half went, so the first line has to carry it**: one key, the
--- whole set, at once.
---
--- **The tail is the part the reader cannot check** (2026-08-23, 소유자). It read "folded or not, and
--- however many of them there are", which answers a hazard nobody has: a folded heading is still
--- that heading, and the count is not a danger. What is actually out of sight is that the set is
--- collected from every layer this character has, so a specialization they are not in changes too.
---
--- No warning about the set coming apart, which is the row tooltip's job. From here there is no one
--- row on offer - the heading cannot pick one out - so the sentence would be describing something
--- this menu cannot do.
---
--- **That it accepts what is waiting is the arrival's line, not this one.** Deciding a key is that
--- decision and the badge comes off with it (`SetKeyForActions`), but **this item is on every
--- heading** - saying it here teaches a vocabulary to everyone who has never taken a string from
--- anybody. The heading that arrived has a string of its own, and a label that says it out loud.
---
--- It said "the key you press" too, and that is wrong here for the reasons it was wrong there: the
--- answer can be a mouse button or the wheel, and [Unbind Key] presses nothing and still settles
--- the whole set. How the key arrives is `KEY_CAPTURE_DESC`'s line.
L["KEY_HEADER_SET_KEY_DESC"] = "Sets one key for every action under this heading, in one go - including any in specializations you are not in."
-- The same item over a heading that arrived. **Nothing is left behind here**, which is the one way
-- it differs from the row's: the press takes the whole set, so there is no half still pending to
-- warn about. The reach is still what the label cannot say.
L["KEY_HEADER_SET_KEY_ACCEPT_DESC"] = "Sets one key for every action under this heading and takes them all, in one go - including any in specializations you are not in."
L["LIFE_ALIVE"] = "Alive"
L["LIFE_DEAD"] = "Dead"
L["LINE_TOOLTIP_CONDITION_LABEL"] = "%s:"
-- Sits directly under the key line, because the key is what it qualifies: that line says which key
-- it has, this one says that key does nothing yet.
--
-- **It is the only thing in the tooltip that says so.** The title used to carry the badge as a
-- colour and no longer does, so if this sentence goes the tooltip stops mentioning it at all.
--
-- No source and no date, though the action carries the key it arrived on. Reading either of those means
-- reading `DebindStorage`'s saved variables, and that addon is load-on-demand - a tooltip that says
-- where a string came from only after some other window has been opened is worse than one that
-- never claims to.
L["LINE_TOOLTIP_IMPORTED"] = "Came in from a string. It reaches no key until you accept it."
-- 한때 "and set its key"가 붙어 있었다. 그 시절에는 행을 고르면 왼쪽 열이 그 액션의 상세
-- 패널이 되고 거기서 키를 걸었다. 지금 왼쪽 열은 키보드 사영이라 보여주기만 하고, 키는
-- 목록 위의 [키 지정] 모드에서 건다 - 좌클릭은 고르는 것이 전부다.
--
-- 그 모드를 여기서 가리키지 않는 이유는, 가리키려면 버튼 글자(BIND_MODE)를 이 문장에
-- 복사해 넣어야 하고 그러면 버튼 이름을 바꾸는 날 이 줄이 없는 버튼을 가리키게 되기
-- 때문이다. 방금 죽은 문장이 정확히 그렇게 죽었다.
--
-- 수식어는 **한 줄로 붙여 둔다.** 따로 세우면 안내 줄이 셋이 되는데, 저것은 이 줄이 말한
-- 좌클릭의 뒷말이지 다른 조작이 아니다. 좌클릭 줄이 짧아져서 자리도 났다.
--
-- **이 줄이 다중 선택을 알리는 유일한 자리다.** 한때 같은 말을 하는 도움말 풍선
-- (TIP_MULTI_SELECT)이 통 아래에 떴는데, 이 줄이 그 말을 하게 된 뒤로는 묻지도 않은 사람을
-- 한 번 붙잡는 값이 남지 않아 풍선 쪽을 지웠다. 그러니 이 문장에서 수식어를 덜어내면
-- CTRL/SHIFT-클릭을 알리는 곳이 UI에 하나도 없어진다.
L["LINE_TOOLTIP_INSTRUCTION_MESSAGE1"] = "Left click to select this action. Hold CTRL or SHIFT while clicking to select more than one."
-- 지정 모드 중에 이 행을 가리키면 위아래 두 줄 대신 이것만 뜬다(`DebindLineMixin:OnEnter`).
-- **BIND_MODE_OVERLAY와 다른 말이어야 한다.** 저쪽은 "오른쪽에서 행동을 가리키라"고 하는데,
-- 이 줄을 읽는 사람은 이미 가리키는 중이라 그 문장이 할 일이 없다. 남은 물음은 하나다.
L["LINE_TOOLTIP_INSTRUCTION_BIND"] = "Press any key or mouse button to give it to this action."
L["LINE_TOOLTIP_INSTRUCTION_MESSAGE2"] = "Right click for more options."
L["LOGIN_MESSAGE"] = "Run the /deb slash command to open the UI."
-- %d는 MACRO_NAME_CHAR_LIMIT다. 한때 32가 글자로 박혀 있었는데, 호출부는 그때도 한계값을
-- 넘기고 있었다(DebindUI.lua의 OpenForAction) - 받을 자리가 없어서 조용히 버려졌을 뿐이다.
-- 세로 탭(사이드탭) 툴팁의 설명 줄. 다섯 레이어에 하나씩이고, 세 마디로 고정한다:
-- **누가 쓰는가**, **무엇보다 우선하는가**, 그리고 **언제 그 말이 안 맞는가.**
--
-- 셋째 마디를 빼면 **거짓말이 된다.** 레이어는 실행 순서의 네 번째 축이라(IMPORTANCE_DESC:
-- 중요도 → 마우스 올림 → 조건 → 탭 → 순서), 조건이 붙은 공유/일반 액션은 조건 없는
-- 공유/야성 액션보다 먼저 실행된다. 중요도를 건드렸으면 더 그렇다. 툴팁은 일부러 불러서
-- 읽는 글이라 이 길이가 부담이 아니고, 탭마다 반복돼도 한 번에 하나만 보인다.
--
-- **마우스 올림은 절에 안 적는다.** 그것도 탭을 이기는 축이 맞지만, 그 액션을 만든 사람은
-- 자기가 만든 줄 알고 있다 - 조건과 중요도처럼 나중에 잊고 부딪히는 것이 아니다. 넷을 다
-- 적으면 절이 문장보다 길어진다. 전부 알고 싶은 사람은 IMPORTANCE_DESC가 다섯 축을 순서대로
-- 적어 둔다.
--
-- 지는 쪽은 **레이어 이름 전체**로 부른다("Shared / Druid"). 툴팁 제목이 그 형식이라 참조도
-- 같아야 화면에서 찾을 수 있다 - 근거는 GetSideTabDescription 주석에.
--
-- 영어는 README의 Layers 표 오른쪽 열과 **같은 말**로 적는다. 표를 읽고 온 사람과 툴팁만
-- 보는 사람이 같은 문장을 읽어야 둘이 같은 것이라는 걸 안다.
L["LAYER_DESC_SHARED_GENERAL"] = "Every character on the account."
-- %s 둘은 차례로 직업명(UnitClass), 지는 레이어의 이름.
L["LAYER_DESC_SHARED_CLASS"] = "Every %1$s you own. A key here beats the same key in %2$s, unless conditions or Importance say otherwise."
-- %s 셋은 차례로 직업명, 전문화명, 지는 레이어의 이름.
L["LAYER_DESC_SHARED_SPEC"] = "Every %1$s you own, while %2$s. A key here beats the same key in %3$s, unless conditions or Importance say otherwise."
-- 여기만 지는 쪽이 레이어 하나가 아니라 공유 셋 전부라, 아래 탭 이름을 그대로 쓴다.
L["LAYER_DESC_CHARACTER_GENERAL"] = "This character. A key here beats the same key everywhere in Shared, unless conditions or Importance say otherwise."
-- **This is the narrowest layer, so it beats every other one** -- not the one directly below it.
-- Naming a single loser here was wrong, and naming all four would be a list nobody reads, so it
-- says "everywhere else", the same move `LAYER_DESC_CHARACTER_GENERAL` makes with "in Shared".
--
-- That leaves English with no argument at all: the tooltip title already reads "Oreo / Balance",
-- so "this spec" has something to point at. Korean still needs the spec name and takes it as the
-- only `%s`. The two locales therefore disagree on format specifiers, which check-locales knows
-- about through EXTRA_SPECS_OK.
L["LAYER_DESC_CHARACTER_SPEC"] = "This character, in this spec. A key here beats the same key everywhere else, unless conditions or Importance say otherwise."
-- 레이어의 짧은 이름. "X over Y" 한 줄에 들어가는 값이라 한두 낱말이어야 한다.
-- Shared/General을 Account라 부르는 이유는 GetLayerShortName 주석에.
L["LAYER_SHORT_ACCOUNT"] = "Account"
L["LAYER_SHORT_CLASS"] = "Class"
L["LAYER_SHORT_SPEC"] = "Spec"
L["LAYER_SHORT_CHARACTER"] = "Character"
L["LAYER_SHORT_CHARACTER_SPEC"] = "Character spec"
L["MACRO_POPUP_TEXT"] = "Enter Macro Name (Max %d Characters):"
-- 둘째 %d는 MACRO_CHAR_LIMIT다. 위와 같은 이유로 1000이 박혀 있었다.
L["MACROFRAME_CHAR_LIMIT"] = "%1$d/%2$d Characters Used"
-- The tooltip on the same button when it reads REVERT, which happens only on an action the
-- conversion menu item just made. The label alone would be read as "undo my typing", and this
-- button is bigger than that: the action goes back to what it was and the body goes with it. The
-- second sentence is the one that has to be there, since nothing on screen shows that cost.
L["MACROFRAME_REVERT_DESC"] = "Puts this action back to what it was before it became a Custom Macro. Anything typed here is lost."
L["MOVE_TO"] = "Move to..."
-- 회색으로 선 현재 탭 줄의 툴팁. 하나를 옮기든 여럿을 옮기든 같은 문장이라 주어를 안 세운다.
L["MOVE_TO_CURRENT_TAB_BLOCKED"] = "Already on this tab."
L["NO_ACTIONS_IN_THIS_TAB"] = "There are no actions in this tab. You can add a new action by dragging a spell, a macro, an item, or a mount here."
-- 검색 결과가 없을 때. 위와 갈라 쓴다 - 저쪽은 "끌어다 놓으세요"라고 시키는데, 검색에 안
-- 맞아서 빈 것뿐이면 할 일이 그게 아니다.
L["NO_SEARCH_RESULTS"] = "Nothing here matches your search."
L["NO_SHAPESHIFT"] = "No Shapeshift"
L["NOT_SELECTED"] = "Not Selected"
L["ONLY_IF"] = "Only if..."
L["OPTIONS"] = "Options"
-- What the overview's reason column says instead of an ordering sentence when the row has something
-- wrong with it. **Two words for the whole set of problems, one per grade** -- red for a row that is
-- waiting on the reader, grey for one that is merely outranked.
--
-- There was a short line per `BINDING_ISSUE_*` code here once ("No group selected", "Unknown state
-- name") and they were dropped, which is worth knowing because the reasoning ran the other way at
-- the time. This column is scanned, not read: its own subject is which row beat the one below it,
-- and a problem pitched several levels finer made one slot talk at two resolutions. **The detail was
-- not lost, it was gathered** -- `BINDING_ERROR_*` says it in full, under the very condition it is
-- about, on the surface the reader opens on purpose.
L["ORDER_FLAG_ISSUE"] = "Has a problem"
L["ORDER_FLAG_UNREACHABLE"] = "Never runs"
-- **The row stands where it would stand if that specialization were the active one**, so this line
-- is the only thing on screen telling it apart from what is running right now. Which one it is comes
-- from the row tooltip, which names the layer; this slot is a few words wide and what has to fit in
-- it is that the row is not in play.
--
-- **The client's word, not ours.** A specialization is made current with `TALENT_SPEC_ACTIVATE`
-- ("Activate"), so the state is active / inactive - and `FACTION_INACTIVE` is where the other half
-- of the pair is already spelled. "Other specialization" was ours and said the wrong thing besides:
-- it reads as "some specialization elsewhere" when what matters is that this one is switched off.
L["ORDER_FLAG_OFFSPEC"] = "Inactive specialization"
-- %s는 그 액션이 사는 레이어의 라벨(ORDER_LAYER_LABEL)이다.
L["ORDER_LAYER_LABEL"] = "%1$s / %2$s"
L["ORDER_GOTO_ACTION"] = "Go to it in %s"
-- 우클릭 줄은 오른쪽 목록의 것을 그대로 쓴다(LINE_TOOLTIP_INSTRUCTION_MESSAGE2). 두 목록 다
-- 그 액션의 메뉴가 열리므로 여기만 다른 말을 쓸 이유가 없다.
L["ORDER_LINE_TOOLTIP_INSTRUCTION_GOTO"] = "Left click to go to this action and edit it there."
L["OTHER_OPTIONS"] = "Other Options"
L["PET"] = "Pet"
L["IMPORTANCE_DESC"] = "The same key can be assigned to more than one action. When you press it, Debind tries them in order and runs the first one whose conditions are met -- only one of them ever runs.|n|nImportance is compared first, so it beats everything below it. Between actions that are equally important, the order is decided by:|n|n1. Hover -- an action that only runs while the mouse is over a unit frame is tried first.|n2. Conditions -- an action with conditions is tried before one without.|n3. Tab -- the more specific tab is tried first, from this character and specialization down to shared.|n4. Order -- when everything above is equal, the action you bound to the key first is tried first. That is also the only step you can move an action within."
-- 끝의 이유절에 **주어를 세웠다.** 원래는 "their own bindings are not loaded this session"이라
-- 누가 안 불러왔는지가 없었는데, 3.1 전까지는 읽을 갈래가 하나뿐이라 그래도 됐다 - 캐릭터
-- 전용 지정이 진짜 캐릭터별 SavedVariables(`DebounceVarsPerChar`)에 있어서, 그 캐릭터로
-- 접속하지 않은 세션에는 **디스크에서 올라오지도 않았다.**
--
-- 3.1이 그걸 계정 파일 하나로 접었다(`DebindVars.characters[guid]`). 이제 부캐 지정도 로그인
-- 때 통째로 메모리에 올라오고 세션 내내 거기 있다 - `CleanUpDB`도 지금 guid 한 칸만 만진다.
-- 안 하는 것은 그걸 `LayerArray`로 짓는 일뿐이다(`Profile.lua`의 `InitDB`).
--
-- 그래서 주어 없는 원문이 **"우리가 안 읽었다"로 읽으면 참, "파일에서 안 올라왔다"로 읽으면
-- 거짓**이 됐다. 문장이 스스로 어느 쪽인지 못 정한다. 하필 이 줄은 계정 전체를 바꾼다는
-- 경고에 붙어서 "숨기는 게 아니라 여기 없는 것"이라는 안심을 맡고 있는데, 계정 파일 하나에
-- 부캐 지정이 다 들어 있는 것을 나중에 본 사람에게 그 안심은 얼버무린 것이 된다.
--
-- 낱말은 그대로 "load"를 쓴다. 갈라진 것은 낱말이 아니라 빠진 주어였다.
L["IMPORTANCE_SHARED_WARNING"] = "This action is in a shared scope, so importance is shared too: it changes the order this action is tried on EVERY key it is bound to, on EVERY character of this account. What happens on your other characters cannot be shown here -- Debind only loads the bindings of the character you are on."
L["OVERVIEW"] = "Overview"
-- 이름표에 매달린 툴팁. 열 이름이 한 낱말이라 이 열의 규칙을 말할 자리가 여기밖에 없다.
--
-- **"the keyboard you are playing with"라고 쓰지 말 것.** 설계 메모의 말버릇이지 플레이어의
-- 말이 아니다 - 저쪽에게 keyboard는 책상 위의 물건이라, 이 창이 그걸 보여준다는 소리가 된다.
--
-- **"여기 있는 것은 지금 누르면 실제로 일어날 일"이 두 번 무너졌다.** 처음은 격리였다 - 꺼진
-- 채로 들어온 것이 목록에 있고 키도 있는데 눌러도 아무 일이 없다. 두 번째가 오프스펙이다.
-- 그래서 그 약속은 이제 문장에 없고, 대신 **자리가 무엇을 뜻하는지**를 말한다: 다른 전문화의
-- 행동은 그 전문화였다면 섰을 자리에 서고, 지금 안 돈다는 것은 옆 칸이 말한다. 약속을 지킬 수
-- 없게 됐을 때 문장을 안 고치면 읽는 사람은 그것을 고장으로 읽는다.
L["OVERVIEW_DESC"] = "Everything in this character's bindings, grouped by the key it is on. Within a key, they are listed in the order Debind tries them.|n|nActions on an inactive specialization are listed too, in the place they would take if that specialization were active. The line beside them says so, and they reach no key until you activate it. Opening another tab on the right does not change what is listed here.|n|nActions with no key are gathered at the end: what came in from a string keeps the set it arrived in, and everything else is one pile in name order. Anything still waiting to be accepted is listed as well, and reaches no key until you say so."
-- 결과 목록에서 한 행이 **바로 아래 행을 이긴 이유**. 순서를 가르는 축은 넷인데 비교자가
-- 위에서부터 훑으므로 처음 갈린 하나가 곧 답이다 - 그래서 다섯 중 언제나 하나만 나온다.
-- 칸 끝에 붙는 회색 한 줄이라 짧아야 한다. 주어는 그 행 자신이다.
-- 순서 이동 버튼. 3.0에서 그대로 돌아온 문자열이다 - 규칙이 안 바뀌었으므로 말도 안 바꾼다.
-- ORDER_BLOCKED_*는 `ComputeOrderSwap`이 돌려주는 사유 코드와 이름이 맞물려 있다.
-- The button that stands in the arrows' place on a row that came in. **Its being there is the row's
-- way of saying it has not been accepted**, which is why no label says that as well.
--
-- **Not the client's `ACCEPT`**, even though the word matches and taking a client global is usually
-- the right move. That one is for invitations and quests; the rule here is different, and borrowing
-- it would put a third word (수락) beside the two this feature already uses on the same screen -
-- "Accept as mine" in the menu, "Accept all %d" in the strip. One thing, one name per screen.
L["ORDER_ACCEPT"] = "Accept"
-- **The one thing the label cannot say** (2026-08-23, 소유자): the press is the moment the key goes
-- live. It also said "take this one as yours", which is the label again in other words, and that the
-- rest of the arrival stays pending - a thing nobody reads the item as doing, since the menu was
-- opened over one row and its title names that row.
L["ORDER_ACCEPT_DESC"] = "This one starts working on the key it came in on."
-- **The same press on something that arrived with no key** (2026-08-23, 소유자). The line above is
-- false there and false in the way that costs most: it names an outcome the reader then goes looking
-- for. Nothing about the screen changes on this press except that the row stops being pending, so
-- the sentence has to be the part that is still missing.
--
-- The item under it does both halves in one press (`ACTION_SET_KEY_ACCEPT`), which is what a reader
-- who wanted this working wants instead.
L["ORDER_ACCEPT_NO_KEY_DESC"] = "This one came in with no key. Accepting takes it, but it does nothing until you give it one."
L["ORDER_MOVE_UP"] = "Run Sooner"
L["ORDER_MOVE_UP_DESC"] = "Move this action one place earlier on this key. Nothing else about it changes."
L["ORDER_MOVE_DOWN"] = "Run Later"
L["ORDER_MOVE_DOWN_DESC"] = "Move this action one place later on this key. Nothing else about it changes."
L["ORDER_BLOCKED_ALREADY_FIRST"] = "This action already runs first on this key."
L["ORDER_BLOCKED_ALREADY_LAST"] = "This action already runs last on this key."
-- 아래 넷은 위의 ALREADY_* 둘과 **틀이 다르다.** 저 둘은 그 자체로 막는 이유이고 주어도
-- 제 안에 있다("This action already runs first"). 이 넷은 **두 액션 사이의 관계**라, 한때
-- "They have different importance."처럼 관계만 적어놨었다 - 그런데 이 툴팁은 죽은 버튼 하나에
-- 딸려 뜨고 두 번째 액션을 꺼낸 적이 없다. they가 누구인지 화면 어디에도 없었다.
--
-- 그래서 셋을 한 문장에 담는다: **막혔다는 것**(제목과 설명은 일어날 일을 말하는데 그 일은
-- 안 일어난다), **누구와 누구인지**, 그리고 **무엇이 순서를 정하고 있는지**. 마지막이 이
-- 자리의 값어치다 - UpdateMoveButtons 주석대로 규칙을 가르치는 몇 안 되는 자리다.
--
-- "the action next to it"이라고 부르는 이유는 위/아래 버튼이 이 문자열을 같이 쓰기 때문이다.
-- 위아래를 짚으면 방향마다 문자열을 따로 둬야 하고, 늘어난 만큼 로케일이 갈라진다.
L["ORDER_BLOCKED_CONDITIONAL"] = "It cannot pass the action next to it -- only one of the two has conditions, and that is compared before the order on this key."
L["ORDER_BLOCKED_HOVER"] = "It cannot pass the action next to it -- only one of the two runs while hovering a unit frame, and that is compared before the order on this key."
L["ORDER_BLOCKED_LAYER"] = "It cannot pass the action next to it -- they are in different scopes, and scope is compared before the order on this key."
L["ORDER_BLOCKED_IMPORTANCE"] = "It cannot pass the action next to it -- they have different importance, and importance is compared first."
-- **The one of the four that is not about a rule the reader could change.** The other three name a
-- property either action could be given; this one says the two never run in the same world, so
-- there is no order between them to settle. The order on this key is only ever compared inside one
-- specialization, because that is the only place the numbers mean the same thing.
-- **Not the shape the rest of this family uses**, and it should not be: the others say why this
-- action cannot pass the one beside it, and this one is not in the running at all. What came in a
-- string reaches no key until it is accepted, so there is no order for it to have a place in.
-- The second sentence is the one `LINE_TOOLTIP_IMPORTED` already says, because it is the same fact
-- and a reader who has met it once should not have to learn it twice.
L["ORDER_BLOCKED_IMPORTED"] = "This action is not in the key's order yet. It came in from a string, and it reaches no key until you accept it."
L["ORDER_BLOCKED_SPEC"] = "It cannot pass the action next to it -- they belong to different specializations, and only one specialization is active at a time."
L["ORDER_WHY_IMPORTANCE"] = "Importance: %s"
-- 정렬은 hover가 설정됐는지만 본다 - false("마우스오버가 아닐 때만")도 설정된 것이다.
-- 그래서 "hover"라고만 쓰면 false인 행에 거짓말이 된다. 어느 쪽인지는 툴팁이 말한다.
L["ORDER_WHY_HOVER"] = "Unit frame rule"
L["ORDER_WHY_CONDITIONAL"] = "Has conditions"
L["ORDER_WHY_LAYER"] = "%1$s over %2$s"
-- The step that is left when the four above it are all tied. **It must not say "your order"** --
-- the place is handed out automatically, at the back of the group, when the key is given
-- (Profile.lua's PlaceInKeyGroup), and the reader never picked it. placement/put/set all turn false
-- for the same reason: to someone who has never pressed an arrow, it is not a place they put
-- anything.
--
-- An instruction ("move it with the arrows") is out too. This line **appears on rows with no
-- buttons** -- the buttons stand only on isCurrent rows (UpdateMoveButtons) while the reason line
-- goes on every row but the group's last.
--
-- What is left true is "the four did not split, so the order itself decides". The step is named the
-- way IMPORTANCE_DESC's fourth line names it, so the ladder the tooltip teaches and this column mesh
-- on the same words.
L["ORDER_WHY_SEQ"] = "Order on this key"
L["IMPORTANCE"] = "Importance"
L["IMPORTANCE1"] = "Very High"
L["IMPORTANCE2"] = "High"
-- 순서 목록의 모든 행이 이 낱말을 쓰므로 짧아야 한다. 다섯 중 가운데라 메뉴에서도
-- 기본값이라는 게 자리로 읽힌다 - "(Default)"를 뒤에 달던 것을 뗐다.
L["IMPORTANCE3"] = "Normal"
L["IMPORTANCE4"] = "Low"
L["IMPORTANCE5"] = "Very Low"
L["REACTION_ALL"] = "All"
L["REACTION_HARM"] = "Enemy"
L["REACTION_HELP"] = "Friendly"
L["REACTION_OTHER"] = "Others"
-- 순서 목록의 행 툴팁에서 쓰는 이름표. 값은 ORDER_LAYER_LABEL이다.
-- ORDER_BLOCKED_LAYER("...they are in different scopes...")와 같은 낱말을 쓴다.
L["SCOPE"] = "Scope"
L["SELECTED_TARGET_UNIT_EMPTY"] = "Assigned Target |cnDISABLED_FONT_COLOR:(None)|r"
L["SELECTED_TARGET_UNIT"] = "Assigned Target |cnLIGHTBLUE_FONT_COLOR:(%s)|r"
L["SHARED_BINDINGS"] = "Shared"
L["SPECIAL_CONDITIONS"] = "Special Conditions"
L["SPECIAL_UNIT_SET_MESSAGE"] = "|cnHIGHLIGHT_FONT_COLOR:%1$s|r - Set to %2$s"
L["SPECIAL_UNIT_UNSET_MESSAGE_TOO_MANY"] = "|cnHIGHLIGHT_FONT_COLOR:%s|r - |cnDISABLED_FONT_COLOR:Cleared (More than one unit detected)|r"
L["SPECIAL_UNIT_UNSET_MESSAGE"] = "|cnHIGHLIGHT_FONT_COLOR:%s|r - |cnDISABLED_FONT_COLOR:Cleared|r"
L["SPECIAL_UNITS"] = "Special units"
-- Title over the right-click menu's list. The list itself is tab names, so this line is what
-- says which question they answer. Shaped like the move and copy menus' "Move to... / Copy to..."
-- on purpose: three menus showing the same list should not each name it differently.
L["SPELL_PICKER_ADD_TO"] = "Add to..."
L["SPELL_PICKER_EMPTY"] = "Nothing here."
L["SPELL_PICKER_GROUP_ACCOUNT_MACROS"] = "Account Macros"
L["SPELL_PICKER_GROUP_CHARACTER_MACROS"] = "Character Macros"
L["SPELL_PICKER_GROUP_FAVORITES"] = "Favorites"
L["SPELL_PICKER_GROUP_OTHERS"] = "Everything Else"
-- 행 툴팁의 안내 줄 둘(이 줄과 SPELL_PICKER_RIGHT_CLICK_TO_ADD). **왼쪽/오른쪽을 부르는 말은
-- 왼쪽 목록 행 툴팁의 것을 그대로 쓴다**("Left click to ..." / "Right click ..." -
-- LINE_TOOLTIP_INSTRUCTION_MESSAGE1/2). 같은 애드온의 두 목록이 같은 조작을 다르게 부르면
-- 다른 조작으로 읽힌다.
--
-- **하이픈은 안 쓴다.** 클라이언트 표기가 두 낱말이다 - GlobalStrings에 "Right Click to Open"
-- 꼴은 있어도 "Left-Click"/"Right-Click"은 한 줄도 없다(wago.tools GlobalStrings 조회).
--
-- %s는 지금 열려 있는 탭의 이름(GetLayerLabel)이다. "현재 탭"이라고만 적지 않는 이유: 창 둘이
-- 나란히 서 있고 탭은 저쪽 창에만 있어서, 이 창의 툴팁이 "현재"라고 말하면 어느 창의 현재인지를
-- 읽는 사람이 눈으로 찾아야 한다. 이름을 적으면 커서가 있는 자리에서 답이 끝난다.
L["SPELL_PICKER_LEFT_CLICK_TO_ADD"] = "Left click to add it to |cnHIGHLIGHT_FONT_COLOR:%s|r."
-- "layer"는 코드가 쓰는 말이고 화면에 나온 적이 없다. 사용자가 보는 것은 탭이므로
-- 탭이라고 쓴다(ORDER_BLOCKED_LAYER와 같은 낱말).
L["SPELL_PICKER_MENU_DESC"] = "Browse what you already have -- spells, macros, mounts, toys, and the game's own binding commands. The window stays open, and each click adds to whichever tab you have open."
L["SPELL_PICKER_NEW_MACROTEXT"] = "New Custom Macro"
L["SPELL_PICKER_NO_MATCH"] = "Nothing matches your search."
L["SPELL_PICKER_ONLY_FAVORITES"] = "Favorites only"
-- SPELL_PICKER_LEFT_CLICK_TO_ADD의 짝. 오른쪽 클릭이 있다는 것을 말하는 자리가 화면에
-- 여기뿐이다 - 행은 있으나 없으나 같은 모양이다.
L["SPELL_PICKER_RIGHT_CLICK_TO_ADD"] = "Right click to add it to another tab."
-- Same thing the overview's `ORDER_FLAG_OFFSPEC` names, so it has to be the same word: two names
-- for one thing in one window is how a reader ends up thinking there are two things.
L["SPELL_PICKER_SHOW_OFFSPEC"] = "Inactive specializations"
L["SPELL_PICKER_TAB_COMMAND"] = "Commands"
L["SPELL_PICKER_TAB_MACRO"] = "Macros"
L["SPELL_PICKER_TAB_MOUNT"] = "Mounts"
L["SPELL_PICKER_TAB_SPECIAL"] = "Special"
L["SPELL_PICKER_TAB_SPELL"] = "Spells"
L["SPELL_PICKER_TAB_TOY"] = "Toys"
-- 창 제목이자 그 창을 여는 [+] 버튼의 툴팁 제목이다(DebindUI.xml의 AddPortrait).
-- 버튼 쪽은 "Add..."라는 따로 놀던 낱말을 쓰고 있었는데, 눌러서 열리는 창이 다른 이름을
-- 달고 있으면 같은 것인지 알 수가 없다.
L["SPELL_PICKER_TITLE"] = "Add an Action"
L["STATE_CHANGED_MESSAGE_OFF"] = "|cnRED_FONT_COLOR:OFF|r"
L["STATE_CHANGED_MESSAGE_ON"] = "|cnGREEN_FONT_COLOR:ON|r"
L["STATE_CHANGED_MESSAGE"] = "|cnLIGHTBLUE_FONT_COLOR:%1$s|r is now %2$s."
L["STATE_DRIVER_UPDATE_THROTTLE"] = "State driver update throttle"
L["STATE_DRIVER_UPDATE_THROTTLE_DESC"] = "The time interval between Blizzard's state driver updates. Some states, such as those related to mouseover, may not be updated immediately. By changing this value, you can adjust the update frequency for these states. The lower the value, the more frequently the state driver updates (|cnHIGHLIGHT_FONT_COLOR:0|r means no interval at all).|n|nDon't worry. This value is not permanently saved and will reset to the default value if you disable the addon.|n|nBlizzard's default value is |cnHIGHLIGHT_FONT_COLOR:0.2|r seconds."
L["STATE_DRIVER_UPDATE_THROTTLE_WARNING"] = "Changing this value may cause performance issues."
-- The Switches tab. Everything below is read on that tab and nowhere else.
--
-- **The four answers.** A switch is either worked out from a macro conditional or pressed by hand,
-- and a pressed one still has to say what it is when the session starts. Those are one question to
-- a reader, so the four are worded as four answers to it rather than as a mode plus a setting --
-- the last of them is `CUSTOM_STATE_MODE_MACRO_CONDITIONAL`, which keeps its old key name from
-- the settings menu on the portrait that 3c took off the window.
--
-- **The label says the ordinary thing and the tooltip carries the rest.** This read "comes up on"
-- for a while, picked so that no one moment was named: the answer is applied at login and on every
-- specialization change too. That was a code lesson wearing a screen label. `initialValue` was
-- renamed for naming one moment because a field that is incomplete is a field that is wrong, and
-- the same is not true of a word somebody reads.
--
-- **A reader only asks what it starts as.** Resetting on a specialization change is ours: a value
-- that is going to be thrown away is a value not worth keeping, so we throw it away at the moment
-- it stops applying. That is a reason to write the code that way, not a reason to make the label
-- vague enough to cover it. The tooltips below say both moments in one sentence, which is where
-- somebody who wants that goes.
L["SWITCH_ANSWER_ON"] = "Starts on"
L["SWITCH_ANSWER_ON_DESC"] = "Turns on when you log in and when you change specialization. You can still turn it off by hand in between."
L["SWITCH_ANSWER_OFF"] = "Starts off"
L["SWITCH_ANSWER_OFF_DESC"] = "Turns off when you log in and when you change specialization. You can still turn it on by hand in between."
L["SWITCH_ANSWER_REMEMBER"] = "As you left it"
L["SWITCH_ANSWER_REMEMBER_DESC"] = "Starts on if you left it on. Every character remembers its own answer."
-- The rows under a switch: one per override, and the account-wide answer last.
--
-- **"Override" is the client's own word**, and 덮어쓰기 in Korean: `TRANSMOG_ARTIFACT_OPTIONS_HEADER`
-- is "Legion Artifact Override" / "군단 유물 덮어쓰기", `TRANSMOG_SLOT_DISPLAY_TYPE_UNASSIGNED_ARTIFACT`
-- is "Ignore Override" / "덮어쓰기 무시".
--
-- ⚠ **Not "tab", which is what this said first.** IMPORTANCE_DESC calls a layer a tab, and it is right
-- to: that line compares two actions by *where they were put*. This list answers *when does this
-- apply*, the Switches tab has no side tabs to point at, and an override does not live in the tab it
-- names -- copying a tab copies actions and leaves the override behind (§4-7-1). Naming the tab
-- would promise the opposite.
--
-- **The axis has no name here, only its values**: a class, a specialization, a character. That is
-- the `reaction` move in `devdocs/writing-user-facing-text.md`, and it is what keeps the sentence
-- out of the window's furniture.
--
-- ⚠ **The two lines below are what stops the rows reading as an order.** Stacked rows mean "the
-- next one runs when this one does not match" everywhere else in this window; here exactly one is
-- in use and the rest do nothing at all. The tick says which, and these say what the tick means.
L["SWITCH_OVERRIDE"] = "Override"
L["SWITCH_OVERRIDE_DESC"] = "Say what this switch comes up as for one class, one specialization or one character. Wherever you set none, the account-wide answer wins."
L["SWITCH_OVERRIDE_REMOVE"] = "Remove this override"
-- **Which one wins, not which one differs.** These rows are not a same-or-different reading of the
-- one above them: exactly one of them decides what the switch comes up as and the rest decide
-- nothing, so what a row has to say is that it won or that it lost. "Different" names the gap
-- between two rows, which is neither.
--
-- **"Wins" is this addon's own word for it** and the README teaches it in the same breath as the
-- layers: "The narrowest row that fits wins."
L["SWITCH_LAYER_WINNING"] = "This one wins here, so it is what the switch comes up as."
-- **Two ways to lose, and the row shows neither.** An override loses either because it is for a
-- character or specialization that is not the one in play, or because a narrower one beat it.
L["SWITCH_LAYER_LOSING"] = "This one does not win here. Either it is not for this character and specialization, or a narrower override beats it."
L["SWITCH_LAYER_MENU_INSTRUCTION"] = "Right-click to change this answer or take it away."
-- The row's own tooltip. **The three distances are the point of it**: a switch belongs to the
-- account while the list belongs to the character reading it, and one total cannot separate a
-- switch three characters depend on from one that does nothing here any more.
--
-- Written as label-and-number rather than as sentences. Three sentences saying almost the same
-- thing is a paragraph to read; three labels is a column to compare, which is what the reader is
-- actually doing with them.
L["SWITCH_USED_BY_HEADER"] = "Actions using it:"
L["SWITCH_USED_ACCOUNT"] = "Across the account"
L["SWITCH_USED_CHARACTER"] = "This character"
-- **"Right now" is a specialization, not a session.** This one counts what the current
-- specialization reads, so it drops when the reader changes specialization and the two above do
-- not. That is the whole reason it is a third line.
L["SWITCH_USED_LIVE"] = "Active right now"
L["SWITCH_MENU_INSTRUCTION"] = "Right-click for settings, renaming and deleting."
L["SWITCH_TURN_ON"] = "Turn On"
L["SWITCH_TURN_OFF"] = "Turn Off"
L["SWITCH_NOT_TRACKED"] = "Not tracked"
L["SWITCH_NOT_TRACKED_WHY"] = "No action reads it."
L["SWITCH_TOGGLE_INSTRUCTION"] = "Click to turn it on or off."
L["SWITCH_TOGGLE_IN_COMBAT"] = "Not from here during combat. A key set up to work the switch does it any time."
L["SWITCH_TOGGLE_IS_AUTOMATIC"] = "This one is worked out from its macro conditional, so pressing it would not hold."
L["SWITCH_RENAME"] = "Rename"
-- **The rule is spelled out because the box refuses on it.** A reader who types a space and is told
-- no learns the rule one refusal at a time; a reader who is told first types a name that takes.
L["SWITCH_RENAME_PROMPT"] = "What should this switch be called?\nLetters, numbers and |cnHIGHLIGHT_FONT_COLOR:_|r."
L["SWITCH_RENAME_ERROR_GONE"] = "That switch is not here any more."
-- Making one. **Three places open this box**: the button under the Switches list, the condition
-- menu, and an on/off/toggle action's own menu. All three exist because a reader finds out they
-- want a switch while they are setting up the thing that needs it, not while looking at a list of
-- switches.
L["SWITCH_CREATE"] = "New switch..."
L["SWITCH_CREATE_BUTTON"] = "New switch"
L["SWITCH_CREATE_DESC"] = "Makes a switch and puts it on this action straight away."
L["SWITCH_CREATE_PROMPT"] = "What should the new switch be called?\nLetters, numbers and |cnHIGHLIGHT_FONT_COLOR:_|r."
-- **The two refusals a typed name gets, and they are about the name rather than about which box
-- it was typed into.** Renaming and creating both hand them back (`RenameSwitch`, `CreateSwitch`),
-- which is why they are not called SWITCH_RENAME_ERROR_* any more.
L["SWITCH_NAME_ERROR_INVALID"] = "A switch name can hold only letters, numbers and |cnHIGHLIGHT_FONT_COLOR:_|r."
L["SWITCH_NAME_ERROR_TAKEN"] = "There is already a switch by that name."
-- The [Set Switch] menu on an on/off/toggle action: which switch the key works, and what it does
-- to it. **The verbs are worded as what the key does, not as what the switch is.** "On" beside a
-- list of switches reads as the switch's own value, which is the one thing this menu cannot set.
L["SWITCH_ACTION_TITLE"] = "Pressing the key"
L["SWITCH_ACTION_ON"] = "Turns it on"
L["SWITCH_ACTION_OFF"] = "Turns it off"
L["SWITCH_ACTION_TOGGLE"] = "Turns it over"
-- **Deleting says how much it reaches, because the list cannot.** The definition is the account's
-- and the list shows what this character can see, so the number is the only place a reader learns
-- that deleting here takes conditions off actions on their other characters.
--
-- It says the actions keep the name rather than that they lose it: they do, they turn red, and
-- that red is how they get found again.
L["SWITCH_DELETE_CONFIRM"] = "Delete |cnHIGHLIGHT_FONT_COLOR:%1$s|r?\n|cnHIGHLIGHT_FONT_COLOR:%2$d|r actions across the account name it. They keep the name and go red until you fix them."
-- **A second line only when there is one to say.** Appended to the sentence above rather than
-- written into it, so the ordinary case -- a switch that is the same everywhere -- is not made to
-- read a sentence about overrides it does not have.
--
-- It says "this list does not show" for the same reason the line above counts the whole account:
-- the list draws what one character reaches, so a druid's overrides go without ever having been
-- on screen.
L["SWITCH_DELETE_CONFIRM_OVERRIDES"] = "|cnHIGHLIGHT_FONT_COLOR:%d|r overrides go with it, including ones on your other characters that this list does not show."
-- Empty-list text says what fills it, and now it can quote the button: it is the one under this
-- list, with a label. It pointed at the picture on the title bar until 3c, which had none.
--
-- **%s is that button's own label** (SWITCH_CREATE), put in rather than written out again. Two
-- copies of a button's name is one of them going stale the day the button is reworded, and the
-- sentence points at a control the reader is meant to find by its glyphs.
L["SWITCHES_EMPTY"] = "No switches yet.\n|cnHIGHLIGHT_FONT_COLOR:%s|r below makes one."
-- 아래 탭 둘의 툴팁 설명 줄. 사이드탭 쪽(LAYER_DESC_*)과 같은 마디로 적되, 여기는
-- 사이드탭 셋을 통째로 덮는 자리라 전문화까지 내려가지 않는다. 중요도에 붙는 단서도
-- 같다 - 같은 주장이면 같은 데서 틀린다.
L["TAB_DESC_SHARED"] = "Every character on the account."
L["TAB_DESC_CHARACTER"] = "This character only. A key here beats the same key in Shared, unless conditions or Importance say otherwise."
L["TARGET_UNIT_DESC"] = "The action is used on that unit without targeting it -- even when the hover condition is in play."
L["TARGET_UNIT"] = "Target"
L["TYPE_COMMAND"] = "Binding Command"
L["TYPE_FLYOUT"] = "Flyout"
L["TYPE_FOCUS_DESC"] = "Sets your focus to this unit. With a role-based unit, one key focuses whoever is tanking right now, without you finding them on the frames first."
L["TYPE_FOCUS"] = "Set Focus Target"
L["TYPE_ITEM"] = "Item"
L["TYPE_MACRO"] = "Macro"
L["TYPE_MACROTEXT_DESC"] = "Creates a macro that lives in this addon and leaves WoW's macro slots free. It can aim at special units and read your switches, which a macro in WoW's own list cannot.|n|nExample: |cnHIGHLIGHT_FONT_COLOR:/cast [@tank,exists] Rejuvenation|r"
L["TYPE_MACROTEXT"] = "Custom Macro"
L["TYPE_MOUNT"] = "Mount"
L["TYPE_PETACTION"] = "Pet Command"
L["TYPE_SETCUSTOM_DESC"] = "Pins the unit whose frame you are hovering over as this custom target. A custom target holds a unit the way focus does: aim at it with |cnHIGHLIGHT_FONT_COLOR:@custom1|r or |cnHIGHLIGHT_FONT_COLOR:@custom2|r in a custom macro, or hand it to any action as its target.|n|nWorks over Player, Pet, Party/Raid, Boss and Arena unit frames."
L["TYPE_SETCUSTOM"] = "Set Custom Target"
L["TYPE_SETCUSTOM1"] = "Set Custom Target 1"
L["TYPE_SETCUSTOM2"] = "Set Custom Target 2"
L["TYPE_SETSTATE_DESC"] = "Turns a switch on or off. A switch is an on/off value of your own that other actions take as a condition, so one key does one thing while it is on and another while it is off.|n|nRight-click it once it is in to pick which switch it works, and whether the key turns that switch on, turns it off, or flips it.|n|nIt flips |cnHIGHLIGHT_FONT_COLOR:in combat|r too."
L["TYPE_SETSTATE_ANY"] = "a Switch"
L["TYPE_SETSTATE_OFF"] = "Turn Off %s"
L["TYPE_SETSTATE_ON"] = "Turn On %s"
L["TYPE_SETSTATE_TOGGLE"] = "Toggle %s"
L["TYPE_SETSTATE"] = "Switch"
L["TYPE_SPELL"] = "Spell"
L["TYPE_TARGET_DESC"] = "Makes this unit your target. The list reaches further than WoW's own targeting bindings -- role-based units such as |cnHIGHLIGHT_FONT_COLOR:Tank|r and |cnHIGHLIGHT_FONT_COLOR:Healer|r, and your custom targets."
L["TYPE_TARGET"] = "Set Target"
L["TYPE_TOGGLEMENU_DESC"] = "Opens this unit's popup menu -- the one right-clicking a unit frame gives you, carrying invite, trade, raid marker and the rest. The key reaches units whose frame is not in front of you."
L["TYPE_TOGGLEMENU"] = "Open Unit Popup Menu"
L["TYPE_UNUSED_DESC"] = "Hands the key back to WoW for the situations you pick. The key then does whatever your WoW key bindings say, and nothing at all if WoW has no binding on it."
L["TYPE_UNUSED"] = "Use WoW's Own Binding"
L["TYPE_WORLDMARKER_DESC"] = "Drops this world marker on the ground your cursor points at, and takes it back if the marker is already out. These are WoW's own markers, so the key places whatever your group lets you place by hand."
L["TYPE_WORLDMARKER"] = "World Marker"
L["UNABLE_TO_REGISTER_UNIT_FRAME_IN_COMBAT"] = "Unable to register some unit frames due to being in combat. They will be registered when combat is over."
L["UNBIND"] = "Unbind Key"
--- Asked before a key comes off two or more actions that share one.
---
--- **The whole point of the sentence is the last clause.** Taking a key off deletes nothing and the
--- reader can give each action a key again, so the obvious reading of "unbind" is that it can be
--- undone. What it actually costs is the grouping, and no field anywhere remembers it -- so if they
--- do not remember which ones went together, there is no way back to it.
---
--- **The count is what the box is for.** A single action is never asked about: there is no set there
--- to lose. What the reader is being told is the size of what comes apart.
---
--- "Separate actions" and not "lose their key", because losing the key is the part they asked for.
L["UNBIND_SCATTERS_CONFIRM"] = "%d actions share a key here. Taking it off leaves them as separate actions with no key, and nothing records that they went together - if you do not remember, you cannot put them back."
--- **The verb, not [Okay].** The reader is agreeing to the thing the sentence just described rather
--- than acknowledging that they read it, and the client's own destructive prompts name the act.
L["UNBIND_SCATTERS_CONFIRM_YES"] = "Unbind and separate"
L["UNIT_CUSTOM1"] = "Custom Target 1"
L["UNIT_CUSTOM2"] = "Custom Target 2"
L["UNIT_DISABLE"] = "Disable"
L["UNIT_FOCUS"] = "Focus"
L["UNIT_HEALER"] = "Healer"
L["UNIT_HOVER_DESC"] = "The unit on the frame you are hovering over"
L["UNIT_HOVER"] = "Unit Frame"
L["UNIT_MAINASSIST"] = "Main Assist"
L["UNIT_MAINTANK"] = "Main Tank"
L["UNIT_MOUSEOVER"] = "Mouseover"
L["UNIT_NONE_DESC"] = "When selected, you can select a new target, even if a currently selected target exists. It also ignores auto self cast."
L["UNIT_NONE"] = "No Target"
L["UNIT_PET"] = "Pet"
L["UNIT_PLAYER"] = "Player"
-- 하나보다 많으면 풀린다(SPECIAL_UNIT_UNSET_MESSAGE_TOO_MANY). 예전 문장은 "only one
-- that role must exist"라 문장이 깨져 있었고, 하나만 있어야 한다는 것도 안 읽혔다.
L["UNIT_ROLE_DESC"] = "Tank, Healer, Main Tank and Main Assist only work while exactly one member of your party or raid holds that role."
L["UNIT_TANK"] = "Tank"
L["UNIT_TARGET"] = "Target"
-- **`nil` is one of the three and not a missing answer.** The game only asks this question of
-- keybinds (`ACTION_BUTTON_USE_KEY_DOWN`), so the entry names the game rather than the key
-- setting: a reader who has never opened that setting still knows what "the game" means, and one
-- who has will find the wording again in the tooltip.
L["UNITFRAME_CLICK_EDGE"] = "Clicking a unit frame casts on"
-- `%s` is the game's own wording for its keybind setting, put in where it is shown.
L["UNITFRAME_CLICK_EDGE_DESC"] = "Blizzard's own unit frames cast when the mouse button comes back up.|n|nWhatever the game does follows |cnHIGHLIGHT_FONT_COLOR:%s|r in the game's own settings, which is the setting your keys already follow."
L["UNITFRAME_CLICK_EDGE_DOWN"] = "Mouse down"
L["UNITFRAME_CLICK_EDGE_GAME"] = "Whatever the game does"
L["UNITFRAME_CLICK_EDGE_UP"] = "Mouse up"
L["UNITFRAME_OPTIONS"] = "Unit frame options"
L["UNNAMED_ACTION"] = "(Unnamed)"
-- Printed once at login, and only when something is actually stopped
-- (`HasBindingBlockedByClique`). It used to go out on the mere presence of Clique, which is why it
-- could only say "some features" -- now it can name what stopped.
--
-- **One chat line.** This lands in the same frame as loot and quest text, so it says the one thing
-- and stops; the addon name is already on the front of it (`_MESSAGE_PREFIX`).
L["WARNING_MESSAGE_CLIQUE_DETECTED"] = "Clique is installed, so unit frame bindings here do not fire."
-- **The addon has stood down from settings written by a newer version of itself**, and will not
-- read or write one byte of them (`Profile.lua`). It goes out at login, and again every time
-- somebody tries to open the window, and it keeps going out on every login until the reader does
-- something about it, because the state it describes does not go away on its own.
--
-- **One chat line, like every other thing this addon says here.** It was three, one per thing to
-- say, and three lines land as three prefixes and three timestamps in the same frame as loot and
-- quest text. Wrapping costs nothing; a second entry costs the reader a second look.
--
-- **The symptom opens it, not the cause.** What the reader is looking at is a character whose keys
-- have all stopped, and what they are looking for is why that happened. The reassurance came first
-- until this was read on a screen, and there it had nothing to attach to yet.
--
-- **"Put the newer version back", not "update".** Rolling an addon back is something people do on
-- purpose, and telling somebody to undo what they just deliberately did reads as not having
-- understood them. This sentence is true either way.
--
-- **No version number in it.** The one this build could name is its own, and the number the reader
-- needs is the one they came from, which nothing here knows.
L["NEWER_PROFILE_MESSAGE"] = "None of your keys work: what Debind saved is from a newer version and this one cannot read it. Nothing was changed, so put that version back and it all returns. Or type |cnHIGHLIGHT_FONT_COLOR:/deb reset|r to wipe it and start over."
-- The first of the two steps. It says what goes and that it is final, and **ends on the token**, so
-- the thing to be typed is the last thing read and sits directly above the typing. Nothing to count
-- and nothing to remember (`Profile.lua`).
--
-- **"on every character of this account" is not decoration.** One file holds the whole account, so
-- somebody typing this on an alt they barely play is about to delete their main's keys too.
--
-- The token itself is never translated: every command this addon has is English already.
L["NEWER_PROFILE_RESET_PROMPT"] = "This wipes everything Debind saved, on every character of this account, and cannot be undone. To go ahead, type: |cnHIGHLIGHT_FONT_COLOR:/deb reset confirm|r"
-- 창을 덮는 판. **"왜 이 화면을 보고 있나"를 먼저 답한다** - 사용자는 자기가 무언가를
-- 껐다는 사실과 이 화면을 연결하지 못한다. 그다음이 "그게 뭔데"이고, 마지막이 부탁이다.
-- 순서를 뒤집으면(부탁부터) 이유는 안 읽히고 [필요 없음]만 눌린다.
L["MIGRATION_DIALOG_HEADER"] = "Debind"
L["MIGRATION_DIALOG_TITLE"] = "Your settings are still here - Debind just cannot reach them."
L["MIGRATION_DIALOG_BODY"] = "In case you missed it: this addon was called |cnHIGHLIGHT_FONT_COLOR:Debounce|r until version 3.0. Same addon, same settings. Version 3.1 renames the folder as well, and that is where WoW keeps your settings file - so the companion addon |cnHIGHLIGHT_FONT_COLOR:Debind Migration|r is now the only thing that can read the old one. Right now it is switched off.|n|n|cnGREEN_FONT_COLOR:Turning it on is the right answer in every case.|r It is barely an addon - no code, nothing that runs, nothing to slow down. Debind opens it once per character to read the old file, and once every character has been through it is never loaded again. All it costs you is one line in your addon list.|n|nUntil you answer, Debind will not open. Closing this window asks again next time you log in."
L["MIGRATION_DIALOG_ENABLE"] = "Turn it on and reload"
-- 거절 둘의 **범위를 글자가 진다.** 되돌릴 버튼이 없으므로 어디까지 걸리는지 읽고 누르게 한다.
-- 캐릭터 단위가 따로 있는 이유는 애드온 활성 상태가 캐릭터별이기 때문이다(XML의 근거).
L["MIGRATION_DIALOG_DECLINE_CHARACTER"] = "Start fresh on this character"
L["MIGRATION_DIALOG_DECLINE_ACCOUNT"] = "Start fresh on every character"
-- 툴팁이 버는 것은 **버튼 글자에 못 넣는 것**이다 - 되돌릴 수 없다는 사실, 옛 파일이 남는다는
-- 사실, 아직 로그인하지 않은 캐릭터까지 걸린다는 사실. 글자를 다시 풀어 쓰는 툴팁은 없느니만
-- 못하다. 셋 다 다는 이유는 하나만 비면 그 버튼에 마우스를 올린 사람이 "툴팁 없는 창"으로
-- 판단하고 나머지도 안 보기 때문이다.
-- 계정 몫이 이미 넘어온 뒤에 이 캐릭터만 남은 경우. **공유 바인딩은 지금 멀쩡히 동작 중이고**
-- 그 사람은 그걸 보면서 이 창을 읽는다. "네 설정을 못 읽는다"고 뭉뚱그리면 눈앞의 사실과
-- 어긋나서, 창이 무엇을 말하는지가 아니라 창을 믿을지가 문제가 된다.
-- 폴더가 아예 없는 경우. **켜기 버튼이 할 수 있는 게 없어서 숨긴다** - `EnableAddOn`은 없는
-- 애드온에 아무 일도 안 하고, 리로드하면 같은 창으로 돌아온다. 그러면 남는 선택지가 되돌릴 수
-- 없는 둘뿐이므로, 다시 받는 길을 먼저 알려주고 창을 닫아도 된다고 말해준다.
L["MIGRATION_DIALOG_TITLE_MISSING"] = "The addon that holds your old settings is not installed."
L["MIGRATION_DIALOG_BODY_MISSING"] = "|cnHIGHLIGHT_FONT_COLOR:Debind Migration|r ships with Debind and holds the settings saved by 3.0 and earlier. It is not in your AddOns folder, so it was either removed or the install did not finish.|n|nDownloading Debind again puts it back, and your old settings are still on disk in the meantime - nothing has been lost.|n|nYou can close this window and reinstall. It will ask again next time you log in.|n|nOnly answer below if you would rather start over without those settings."
L["MIGRATION_DIALOG_TITLE_CHARACTER_ONLY"] ="This character's own bindings have not come across yet."
L["MIGRATION_DIALOG_BODY_CHARACTER_ONLY"] = "Your shared bindings are already here - they moved when you logged in on another character, which is why most of your keys work.|n|nWhat is still missing is anything you set up for |cnHIGHLIGHT_FONT_COLOR:this character alone|r: its own layers and its custom targets. Those live in a separate file, and the companion addon |cnHIGHLIGHT_FONT_COLOR:Debind Migration|r is the only thing that can read it. Right now it is switched off.|n|n|cnGREEN_FONT_COLOR:Turning it on is still the right answer.|r If it turns out you never made character-specific bindings here, nothing happens and you are done. If you did, you get them back. Either way it stops asking.|n|nUntil you answer, Debind will not open. Closing this window asks again next time you log in."
L["MIGRATION_DIALOG_ENABLE_TOOLTIP"] ="Enables |cnHIGHLIGHT_FONT_COLOR:Debind Migration|r for every character and reloads your interface.|n|nThis character's settings are back as soon as the reload finishes. Your other characters keep theirs until you next log in on them - each one brings its own across on its own first login, whenever that is. Nothing else to do."
L["MIGRATION_DIALOG_DECLINE_CHARACTER_TOOLTIP"] = "This character starts with no bindings, and is never asked again.|n|nOther characters are unaffected - they will still be offered their settings.|n|n|cnRED_FONT_COLOR:This cannot be undone from inside the addon.|r Your old file is left untouched on disk either way."
L["MIGRATION_DIALOG_DECLINE_ACCOUNT_TOOLTIP"] = "Debind stops offering old settings to |cnHIGHLIGHT_FONT_COLOR:every character on this account|r, including ones you have not logged in on and ones you make later.|n|n|cnRED_FONT_COLOR:This cannot be undone from inside the addon.|r Your old file is left untouched on disk either way."
L["WARNING_MESSAGE_LEGACY_ADDON_STILL_INSTALLED"] = "An older full copy of this addon is still installed and is setting keybinds alongside Debind, so the two are fighting over your keys. Reinstalling or updating Debind replaces that folder with the small |cnHIGHLIGHT_FONT_COLOR:Debind Migration|r companion. Do not just delete the folder - characters you have not logged in on since updating still have their settings in it."

-- The sharing window. The tooltips are long because both choices it offers - what to send, and
-- whether the keys ride along - leave for somewhere you cannot reach: a string handed to someone
-- else is not recallable. A tooltip is read on purpose, so length is not the cost it looks like.
--
-- These live here rather than in `DebindStorage` because they are eleven strings against that
-- addon's reason for existing, and a second locale tree would need its own parity check.
-- The window's own tabs (`PANELS` in `DebindUI.lua`). The label is one word, so the tooltip is
-- where the tab says what it opens - and Import and Export both open something that leaves for
-- somewhere you cannot reach, so the same "read it on purpose" rule as above applies.
--
-- The two panels themselves live in `DebindStorage`, which is load-on-demand and may not be there.
-- **One failure, so one message.** That addon cannot load and then not have built its panel, so
-- "loaded but empty" is not a second case to describe - if it ever happened the install would be
-- broken, and the second line below is already the fix for that.
--
-- **It says what failed and what to do, not where our code lives.** Which addon holds which panel
-- is our filing, not the reader's problem; what they can act on is the switch in the AddOns list
-- and, failing that, installing again. No `%s` either, unlike the chat line further down - the
-- reason string the client hands back is for the log, not the middle of a window.
-- Taking the badge off imported actions. **The verb is about the reader, not the action** -
-- nothing is being changed or repaired, they are saying they will have it.
--
-- **It is the moment a key starts working.** What arrives keeps the key it was sent on and the badge
-- is the only thing holding it back, so this press puts it live. It used to be the opposite - what
-- arrived sat on a number the build skipped - and the sentence that said so went with the number
-- (`devdocs/building-export-import.md` 12절).
--
-- **"As mine" came off** (2026-08-23, 소유자). It marked the answer while there was nothing else in
-- the menu it could be confused with; the item beside it now is the same verb with a key picked
-- first, and the two read as a pair only if the plain one is plain. `ORDER_ACCEPT` on the row is
-- the same word for the same press, which is what one thing having one name means.
L["APPROVE_IMPORT"] = "Accept"
-- The row above the two columns, which is the only thing on that row while anything is waiting.
--
-- **It names the state, and the two answers to it are in the menu it opens.** Two buttons stood
-- here - [Accept all %d] and [Reject all %d] - and a label per answer meant the row could not be
-- one control. Naming the state instead is what folds them: a reader who has not decided yet is
-- told what there is to decide about, and both verbs are one press away.
--
-- **"Pending" is the client's word for exactly this** - something that arrived and is waiting on
-- the reader to say yes or no (`COMMUNITIES_MEMBER_LIST_PENDING_INVITE_HEADER` = "Pending Invites
-- (%d)", `CLUB_FINDER_PENDING_REQUESTS`). It is a third name for the state on this screen, after
-- the filter tick's "Not Accepted Yet" and the menu items' "still waiting", and it earns that by
-- being the only one of the three that has to stand **alone**: the other two sit inside a sentence
-- or a verb that supplies what is being waited on, and a button on an empty row has neither.
--
-- **"Action" is the reader's word for the thing being counted** and this window already counts them
-- that way (`OVERVIEW_NO_KEY_COUNT`). `|4` is the client's own plural form, resolved when the
-- string is drawn rather than by `format`.
--
-- **It breaks off** (2026-08-23, 소유자). The press opens a menu rather than doing anything, and a
-- label that names a state on a button that acts is the one shape a reader cannot tell apart from a
-- label that names a state on a button that asks. The tab's own [Add to My Setup...] breaks off for
-- the same reason.
L["IMPORT_PENDING"] = "%d Pending |4Action:Actions;..."
-- **Two facts, and the reader needs both before opening the menu.** What the state means - none of
-- this is doing anything - and how far the count reaches, which is the one thing they cannot see
-- from here (the same reason `APPROVE_ALL_IMPORT_DESC` has to say "wherever it went").
--
-- **It does not repeat the number**; the title is the button's own text and already carries it.
L["IMPORT_PENDING_DESC"] = "These came in from a string and do nothing until you accept them - no key of yours behaves any differently while they wait. The count is everything still waiting anywhere in your bindings, including specializations you are not in."
-- **Both mouse buttons, so neither is named.** Saying "left-click" would make the right one look
-- like something else; saying both would spend a line on a distinction that does not exist here.
L["IMPORT_PENDING_INSTRUCTION"] = "Click for what can be done to all of it."
-- Accepting everything at once, which is the ordinary way out.
--
-- **The number is not here, and there is still no confirmation box.** It used to be - this was a
-- button on the row above the columns and read "Accept all %d", with that number standing in for
-- the box, since the one useful thing such a box could have said is how much is about to start
-- working. What carries it now is the button this menu opens off, which reads `IMPORT_PENDING` and
-- is on screen the whole time the menu is: the count is one widget away rather than gone, and it is
-- the same count because both come from `CollectArrivedActions`.
--
-- **"all" is the whole of the scope, and it means the profile.** The heading menu's items name the
-- subset they gather instead (`KEY_HEADER_APPROVE`) precisely because "all" would overpromise
-- there; here it does not.
L["APPROVE_ALL_IMPORT"] = "Accept all"
-- **It has to say "wherever it went"**, because the count includes actions on specializations you
-- are not in, and those are on no list the reader can see from here.
--
-- **And it has to say that these go live.** They arrive on the keys the sender had them on and the
-- badge is the only thing holding them back, so taking the badge off is the moment they start
-- working. It used to say the opposite, truthfully: what arrived sat on a number the build skipped,
-- so accepting could not reach a key. That number is gone
-- (`devdocs/building-export-import.md` 12절) and the sentence went with it.
L["APPROVE_ALL_IMPORT_DESC"] = "Accepts everything that is still waiting, wherever it went, including other specializations. They start working on the keys they came in on. If any of those is a key you already use, you will be asked what to do about it first."
-- Asked once for the whole batch, when accepting would take keys the reader is using.
--
-- **Two doors reach it and the sentence has to be true from both** (2026-08-23, 소유자). [Accept
-- all] takes every badge in the profile, so it opened "%d actions are waiting" - which the storage
-- tab's [Add and Accept] makes false twice over: nothing was waiting, since that press is what put
-- them there, and the count is what that press placed rather than the backlog. What both have in
-- common is the moment: some keys are about to change hands.
--
-- **Two numbers, and they count different things.** The first is how many actions start working,
-- which is what the reader pressed for. The second is how many of their own are standing on the
-- contested keys, which is what the answer decides the fate of.
--
-- **Both count actions** (2026-08-23, 소유자). The second one counted key groups, on the grounds
-- that a group is the unit at risk - taking a key off four actions leaves four loose ones and no
-- record that they went together (`KEY_GROUP_CONFLICT_UNBIND_DESC`). A group is not a thing the
-- reader has ever been shown a count of, though, and two numbers in one sentence counting two
-- different units is a sentence nobody can read at speed.
--
-- **And a hedge went with it.** It read "some of them came in on keys you already use", which is a
-- vague quantity standing in front of an exact one. There was nothing for the vagueness to cover
-- once both numbers count the same thing.
--
-- **The question asks who gets the key, not what happens to one side.** It read "What should happen
-- to yours?" while the answers were two, and stayed there when a third was added - at which point
-- [Merge] was not an answer to the question above it. Every one of the three names a winner, so the
-- question has to be the one they all answer.
L["APPROVE_ALL_OCCUPIED"] = "|cnHIGHLIGHT_FONT_COLOR:%1$d|r actions are about to take the keys they came in on, and |cnHIGHLIGHT_FONT_COLOR:%2$d|r of yours are on those keys already.|n|nWho gets those keys?"
-- **The answer that changes nothing of what is already there**, and first because that is where
-- Enter lands.
--
-- **`Existing` and not `Mine`.** The pair with `Incoming` is exact - the two words name the two
-- sides and neither claims anything about them. `Mine` claims one thing that is not always true:
-- what came in can be the reader's own backup (`Create` makes a payload out of this profile), and
-- then both sides are theirs and the label says otherwise. That is the same fault `Theirs` was
-- turned down for on the other button.
L["APPROVE_ALL_KEEP_EXISTING"] = "Keep Existing"
-- What the label cannot say: **the incoming ones still arrive.** This answer is about the key, not
-- about whether to take them - the reader already pressed accept - so what steps aside is the key
-- and they land unbound. That is the state everything used to arrive in before an arrival kept the
-- key it was sent on (`devdocs/building-export-import.md` 12절).
--
-- **And that it is only the contested keys.** Anything that came in on a key nobody was using takes
-- that key whichever of the three is pressed.
L["APPROVE_ALL_KEEP_EXISTING_DESC"] = "Only on the keys you are already using. What came in on those ends up with no key at the bottom of the list, where you can give it one. Anything that came in on a free key takes that key either way."
-- The other exclusive answer. **`Take` rather than `Overwrite`** - nothing is deleted and your
-- actions only lose the key, so a word that says "destroyed" would have to be walked back by its own
-- tooltip. It also puts both labels on one axis: each of the three names what ends up on the key,
-- and the reader reads the set instead of each label.
L["APPROVE_ALL_TAKE_INCOMING"] = "Take Incoming"
-- The other answer, and the design note always had the two side by side. **The same set as
-- [Accept all], opposite verb** - two items standing together must not quietly mean different
-- amounts.
--
-- **The pair is accept/reject, and it must not be crossed with keep/discard.** Both are pairs the
-- reader already owns, so borrowing one word from each leaves them looking for the missing halves.
--
-- **Not keep/discard, because "keep" would say the thing is already running** - it asks whether to
-- let something continue, and the one fact quarantine exists to establish is that none of this is
-- doing anything yet. The button would contradict the badge. ("Reject" not naming the removal is
-- the smaller cost, and the prompt below spends one clause on it.)
L["REJECT_ALL_IMPORT"] = "Reject all"
L["REJECT_ALL_IMPORT_DESC"] = "Removes everything that is still waiting, wherever it went. The string it came from stays in the Import tab, so you can bring it in again."
-- **Why [Move to] and [Copy to] are dead on the multi-selection menu.** Neither names the act, since
-- one string stands on both - and a sentence naming it would have to be two, saying the same thing
-- about the same rows.
--
-- **Two of them, because the way out differs.** With some of the picked rows still waiting, the
-- selection is what to change; with all of them waiting there is nothing to take out of it, so what
-- is left to do is accept, and that item is two rows further down the same menu.
--
-- Neither says why moving is refused. The reason is that what arrived is ordered the way its sender
-- ordered it, which is a sentence about machinery the reader has no reason to hold - and the answer
-- to "why not" is the same in both cases anyway: it has not been accepted yet.
-- The third scope [Assign a key] is offered at, after a row (`ACTION_SET_KEY_DESC`) and a heading
-- (`KEY_HEADER_SET_KEY_DESC`). **The label is the same three words in all three**, since the act is
-- one act and the same window opens; the scope is what the three tooltips are for.
--
-- **The second half is the row's warning, and it is needed more here than there.** A selection can
-- hold part of a key group, so the rows left behind are ones the reader chose not to pick rather
-- than ones they never saw - and a key coming apart shows nothing at all until both halves fire.
L["BULK_SET_KEY_DESC"] = "Sets one key for everything you picked, in one go.|n|nRows sharing a key with something you did not pick are left on it. Both keys still work; they just stop working as one."
L["BULK_BLOCKED_ALL_IMPORTED"] = "None of what you picked has been accepted yet. That has to come first."
L["BULK_BLOCKED_SOME_IMPORTED"] = "Some of what you picked has not been accepted yet. Take those rows out of the selection."
-- The single one, from a row's right-click menu.
L["REJECT_IMPORT"] = "Reject"
-- **The second sentence is the whole reason this has a tooltip**, and it is the one [Reject all]
-- ends on: what makes the item pressable is that the arrival is still in the drawer. Only the first
-- half had to be rewritten, because this one is aimed at a single row.
--
-- Its opposite number is `ORDER_ACCEPT_DESC`, which the menu borrows from the row's accept button.
-- There was nothing to borrow for this half - no row carries a reject button.
L["REJECT_IMPORT_DESC"] = "Removes this one. The string it came from stays in the Import tab, so you can bring it in again."
-- **The second sentence is what makes this pressable.** Without it this reads as the destructive
-- half of the pair, when it is in fact the reversible one - accepting is what cannot be undone.
L["REJECT_IMPORT_CONFIRM"] = "Reject |cnHIGHLIGHT_FONT_COLOR:%d|r actions that came in and have not been accepted?|n|nThey are removed, but the string they came from stays in the Import tab, so you can bring it in again."
--- The one-shot in the options menu. **A sweep of what the reader already has**, not of what is
--- arriving - two payloads made by the same person share their account layer, and bringing both in
--- leaves that layer holding the same action twice.
---
--- "Duplicate" and not "identical": the client uses neither on a button, and between the two only
--- one says the second copy is redundant rather than merely alike.
L["REMOVE_DUPLICATES"] = "Remove Duplicate Actions"
--- Three things the label has no room for, and each of them changes what the reader expects.
---
--- **Which two count as the same one**: everything about the action including the key, so two on
--- different keys are two bindings and stay.
--- **How far it looks**: inside one layer only. The same action on the general layer and on a
--- specialization layer is the stack this addon is for, not a mistake.
--- **What it keeps**: the one that fires first, so nothing about what a key does moves.
L["REMOVE_DUPLICATES_DESC"] = "Looks for actions that are exactly the same - same key and all - sitting in the same layer, and removes the extra copies. The one that fires first stays. The same action on two different layers is left alone: that is how a specialization overrides the general list."
--- Pressed on a profile with nothing to find. **A line rather than a box** - there is nothing to
--- confirm and nothing to look at, and a dialog saying "no" is a dialog to dismiss.
L["REMOVE_DUPLICATES_NONE"] = "No duplicate actions to remove."
--- **The count is the whole question.** Naming them would be the same name repeated, which is what
--- a duplicate is.
---
--- **And it says nothing is lost**, which is what makes one press over rows the reader has not
--- looked at offerable at all: every one of these has a twin staying behind.
L["REMOVE_DUPLICATES_CONFIRM"] = "Remove |cnHIGHLIGHT_FONT_COLOR:%d|r duplicate actions?|n|nEach one is an exact copy of another in the same layer, and the copy that fires first is staying. Nothing your keys do will change."
-- **The filter dropdown, one tick per value.** Two axes, and each is written out value by value
-- rather than as one switch that hides a side, so that every tick means the same thing: show this
-- too. A switch called "off-spec" would mean the opposite of its neighbours - ticking it would add
-- rows where ticking the others removes them.
--
-- The client's own shape, from the collection windows: [Collected] / [Not Collected] side by side,
-- all ticked to begin with, and untick everything on one axis and the list is honestly empty.
--
-- **Title Case, because that is what the client's filter items use** - [Collected] / [Not Collected]
-- / [Usable Items] in the collection windows, and `NOT_BOUND` below is one of those strings.
--
-- **"Inactive specialization" is not a fresh wording.** `ORDER_FLAG_OFFSPEC` and
-- `SPELL_PICKER_SHOW_OFFSPEC` already name this, and one thing has one name per screen - these two
-- keys exist so each position can be reworded on its own, never so they can say different things.
--
-- **Plural, and its neighbour is not.** A tick here covers every specialization that is not the one
-- being played, which is why `SPELL_PICKER_SHOW_OFFSPEC` is plural in the same position;
-- `ORDER_FLAG_OFFSPEC` is singular because it marks one row. There is only ever one active
-- specialization, so that side stays singular even though the pair then looks uneven.
L["FILTER_ACTIVE_SPEC"] = "Active Specialization"
L["FILTER_INACTIVE_SPEC"] = "Inactive Specializations"
-- The key axis. **Three values, and none of them overlaps another**: an action either presses on a
-- key, or is waiting to be accepted, or is neither.
--
-- **The word carries "key" with it.** The client's `NOT_BOUND` was tried here and taken back out:
-- there it stands beside a `Key:` label that supplies the subject, and alone in a list "Bound"
-- reads as soulbound first. `OVERVIEW_EMPTY` already says it the way that closes - "No key is
-- bound yet".
--
-- **Not "assigned", though the addon says that too.** [Assigned Target] has that word in this same
-- window, and one word naming two things on one screen is how a reader ends up thinking there is
-- a connection.
--
-- "No Key Bound" is narrower than it sounds: what is waiting to be accepted has no key either, and
-- the line below carries that. The three standing together is what makes it read - a reader picking
-- among three does not take one of them for the whole.
L["FILTER_KEYED"] = "Key Bound"
L["FILTER_UNKEYED"] = "No Key Bound"
-- **"Accepted" is the word the rest of the import uses** (`APPROVE_IMPORT`, `LINE_TOOLTIP_IMPORTED`),
-- so this is not a new idea for the reader - it is the same state named where it can be filtered on.
L["FILTER_PENDING"] = "Not Accepted Yet"
-- Empty right-hand list because a filter took everything out. **Different from the search one**:
-- that reader knows what they typed, and this one has to open the dropdown to see which value is
-- switched off.
L["NO_ACTIONS_MATCH_FILTERS"] = "Nothing in this tab matches the filters. The dropdown above the left column has what is switched off."
-- Empty left-hand column for the same reason. Different from the one above: that list is one tab,
-- this one is the whole keyboard.
L["OVERVIEW_EMPTY_FILTERED"] = "Nothing matches the filters. The dropdown above this column has what is switched off."
-- Everything picked turned out to have nowhere to go - the same two causes as
-- `IMPORT_COMMITTED_SKIPPED`, with nothing left over to report a count against.
L["IMPORT_NOTHING_PLACED"] = "Nothing came in - none of what you picked has anywhere to go here."
-- **Said out loud because the screen barely moves.** What just arrived is bound to nothing, so a
-- press that did a lot looks like a press that did nothing.
--
-- **It used to end "look for the glowing icons", and nothing glows.** The badge is a colour on the
-- name and a dot on the icon, and even when that was closer to true it was the wrong thing to send
-- somebody hunting for - the actions are scattered by name and by key, which is why the strip
-- exists. So the line points at where the strip stands rather than describing any art.
--
-- It says the position, not the words on the controls: renaming either of them must not turn this
-- sentence into a pointer at something that is not there.
-- The other way in. **Both halves are said** because a string can hold either kind: what the sender
-- had on a key is on that key now, and what they had not bound yet cannot be, so it lands the same
-- way everything else does.
L["IMPORT_COMMITTED_KEYED"] = "Brought in %d actions on the keys they came with. Anything that arrived without one is unbound until you give it a key."
L["IMPORT_COMMITTED"] = "Brought in %d actions. They are pending until you accept them - a row for doing that is now at the top of the window."
-- **Two things reach this and neither is the reader's doing**, so it names both rather than picking
-- one: a specialization this character's class does not have, and a layer a newer Debind invented.
-- It used to say only the second, and the first is the one that actually turns up.
L["IMPORT_COMMITTED_SKIPPED"] = "%d of them had nowhere to go here and were left out - a specialization this character does not have, or a layer this version does not know."
-- The right-click menu on an action in the preview. **Taking things out is the only edit an entry
-- has**, so these two are the whole menu.
--
-- "This action" rather than the action's name: the row is under the cursor and the menu is over
-- it, so naming it again would be the menu reading the screen back.
L["STORAGE_DELETE_ACTION"] = "Delete this action"
-- The other item. %d is what is ticked, which starts as everything in the entry - so the number is
-- usually large and is usually not a number the reader chose.
L["STORAGE_DELETE_SELECTED"] = "Delete %d selected"
-- Which is why two or more ask. One does not: a menu is already enough hands not to reach by
-- accident, and the second look is for the count rather than for the act.
L["STORAGE_DELETE_SELECTED_CONFIRM"] = "Take %1$d actions out of this? They do not come back - you would have to make it again."
-- The door that makes a row out of what this character has right now, beside the one that makes a
-- row out of a code somebody sent.
--
-- **The thing has a name now, and the name is the code's** (2026-08-23, 소유자). 12절 spent a while
-- looking for a word for what sits in this list and settled on not naming it, on the grounds that
-- the client's own names are each already something else and the free ones are free because nobody
-- uses them. That is overturned: the reader is told the word rather than kept away from it, and the
-- tooltip below is where they are told (`0-DECISION-LOG.md`).
--
-- **`Save` was here for one commit and did not hold.** It reads as the button that keeps a settings
-- screen, which is a thing this window has none of.
--
-- **No object and no range on it.** What this takes is everything the character has, including the
-- specializations they are not playing, so any range it named would be too narrow - and what it
-- makes is the row that appears right above it.
L["STORAGE_CREATE"] = "New Payload"
-- What the word means, on the button that makes one. **A tooltip is read by someone who stopped to
-- ask**, so it has the room to teach a word the list itself only uses.
--
-- **The two lines have two subjects and that is why they are two lines** (2026-08-23, 소유자). This
-- one is about the thing: what a payload is, and what having one is good for. The instruction line
-- under it is about the press. Written as one paragraph they came out as three sentences the reader
-- has to sort by subject as they go.
--
-- It says the two directions rather than the contents: a payload is worth having because it goes
-- somewhere, and both places it goes are one press away on this screen.
L["STORAGE_CREATE_TOOLTIP"] = "A payload is a saved set of actions, kept outside your bindings. Add one to your bindings later, or send it to somebody as a share code."
-- The press, in the line the client keeps for what a click does.
L["STORAGE_CREATE_INSTRUCTION"] = "Click to make one out of everything this character has right now."
-- **Not "Import", which the client owns and spends on something else.** Every one of those buttons
-- takes a code and makes it yours in one press. This one takes a code and puts a row in a list, and
-- nothing the reader has is any different afterwards, so the word would promise the half of the
-- client's gesture that only happens later and on another button (2026-08-22, 소유자).
--
-- Says "Share Code" because `STORAGE_COPY` does, and the two are the same code going opposite ways.
--
-- **It keeps "Paste", where the other one names what it makes.** The two doors are not the same
-- shape: one takes what the reader already has and the other wants something out of their
-- clipboard, and the verb is the part of that they have to know before pressing.
L["STORAGE_PASTE"] = "Paste Share Code"
-- `HOUSING_BLUEPRINT_COLLECTION_COPY`, on the button doing exactly this job: a saved thing turned
-- into text to hand to somebody.
--
-- **"String" is our word, not the client's, and this key is the first to stop using it.**
-- Measured 2026-08-17: every place the game shows one of these to a player it calls it a **code**
-- - `LOADOUT_ERROR_BAD_STRING` reads "Invalid loadout code",
-- `COOLDOWN_VIEWER_SETTINGS_ERROR_ENTER_IMPORT_STRING_AND_NAME` reads "a valid import code",
-- `HOUSING_BLUEPRINT_IMPORT_SHARECODE_LABEL` reads "Enter Import Code:" - and keeps "string" to
-- its own key names, which is the same line this file is supposed to draw. koKR says 코드
-- throughout.
--
-- **The rest are not renamed, and that is still a finding rather than a decision.** It is a dozen
-- keys across two files and one track's whole vocabulary; ruRU carries none of them, so the cost
-- when it is done is enUS and koKR only.
-- **"With Their Keys" came off** (2026-08-23, 소유자). It named the whole of what the answer decided
-- while an arrival was parked on a number of ours; since the badge became the only thing holding
-- one back, an arrival carries the sender's key from the moment it lands and accepting is what lets
-- that key fire. The clause said what `Accept` already says.
L["STORAGE_ADD_ACCEPTED"] = "Add and Accept"
-- **The second sentence is the same one the other door to that prompt uses**
-- (`APPROVE_ALL_IMPORT_DESC`). One question asked from two places is announced the same way, or the
-- reader meets a prompt one of them never mentioned.
--
-- **No warning that accepting cannot be undone.** True of accepting wherever it is pressed rather
-- than of this item, and a warning on the ordinary choice is what turns a decision into a hazard.
L["STORAGE_ADD_ACCEPTED_DESC"] = "They start working straight away, on the keys they came in on. If any of those is a key you use, you are asked what to do about it first."
-- **What the label leaves out is that nothing of the reader's moves**, which is the reason to pick
-- this item at all: "pending" says they are waiting and says nothing about what happens to the keys
-- already in use.
--
-- It named the row in Overview where a pending arrival is accepted. That is one of three places
-- accepting is offered - the row's own button and its menu are the others - so the sentence was
-- wrong about the only part it added, and the count is on screen the moment the reader gets there.
L["STORAGE_ADD_QUARANTINED_DESC"] = "They go into your bindings doing nothing, and none of your keys change until you accept them."
-- The other item on that menu, and the one the reader wants nine times out of ten.
--
-- **No switch on this tab** (2026-08-23, 소유자). It read "Switched Off Until I Accept Them", which
-- drags a word this addon has a whole tab of into a screen that has nothing to do with one - and
-- promises a thing that flips both ways, where accepting an arrival is a door that only opens one
-- way (`ApproveArrivedActions` is the only writer, and nothing puts the badge back).
--
-- `Pending` is what the overview's button and filter already call this state (`IMPORT_PENDING`).
L["STORAGE_ADD_QUARANTINED"] = "Add as Pending"
L["STORAGE_COPY"] = "Create Share Code"
-- **The destination, because `Add` on its own points at the list.** This said the client's `ADD`,
-- and in the client that word sits on buttons that put a row in a list: add a friend, add to the
-- ignore list. Two buttons under the list on the left already do that here, so a reader looking at
-- a list and a button beside it read the third one as another of those.
--
-- **Not "keys" and not "this character".** Neither is true. Nothing new turns up under a key while
-- an arrival is still pending, and where an action lands is what its own address says, which can be
-- a place every character shares.
--
-- **Not "My Actions"** (2026-08-23, 소유자). The other end of the same press is a payload, which is
-- a set of actions (`STORAGE_CREATE_TOOLTIP`); naming both ends "actions" makes the sentence say a
-- thing goes into itself. What it goes into is the lot of what the reader has.
--
-- **"My Bindings", after a spell as "My Setup"** (2026-08-23, 소유자). Bindings was turned down on
-- the grounds that some actions have no key, and that reading is wrong: the client's own Key
-- Bindings screen lists a command that is not bound, so **unbound is a state inside bindings rather
-- than outside them**. A word is cut for being wrong about the thing, not for being awkward in a
-- corner of it (`devdocs/writing-user-facing-text.md`) - and following the corner left `Setup`,
-- which is a word of ours that says less. This one is the client's, it is what this window edits,
-- and the item's own tooltip was already saying it.
--
-- **It breaks off, because the press asks rather than acts** (2026-08-23, 소유자). The two ways the
-- actions can land are the reader's to pick, so the menu finishes the sentence the label starts.
L["STORAGE_ADD"] = "Add to My Bindings..."
-- **The date has to say which date it is.** The row shows it bare, where it is one of two lines
-- and the reader is scanning rather than reading; the tooltip is where somebody stops to ask, and
-- an unlabelled number there answers "made", "pasted" and "today" equally well.
--
-- Which word applies is which way the entry got here, and the character name is what says so: only
-- an entry made on this account carries one.
L["STORAGE_ENTRY_MADE"] = "Created %s"
L["STORAGE_ENTRY_RECEIVED"] = "Received %s"
-- The tab. **A place, not the thing kept in it** - the client has no empty word for one of these
-- (Blueprint, Layout and Loadout are each already something else) and naming a place needs none.
--
-- The client's own word for a tab holding what you own and have not put anywhere yet is
-- `HOUSE_EDITOR_CATALOG_STORAGE_TAB`, the housing catalog's. **Three locales come off that one
-- string**, which is what settled it against counting the word on its own - "보관함" is 65 lines
-- in koKR and almost none of them are this in enUS.
--
-- It is also the AddOns list name of the addon that keeps the payloads, and that was known and
-- taken: the two never stand on one screen (12절 of `devdocs/building-export-import.md`).
L["STORAGE_TITLE"] = "Storage"
-- The header over actions this version has no layer for: a specialization number past the end of
-- the class they came from, which only a hand-edited string carries. **They are drawn rather than
-- dropped**, so what the preview counts is what the string holds - and adding them puts them
-- nowhere, which is the number said separately after a press.
L["STORAGE_PREVIEW_ELSEWHERE"] = "Nowhere to put these"
-- The right column's resting state: nothing picked. **It said "pick something"** because the thing
-- in the list had no name to call it by, which is what a screen that will not name its object is
-- reduced to. It has one now (`STORAGE_CREATE`), so the sentence says which thing to pick.
L["STORAGE_NOTHING_PICKED"] = "Pick a payload on the left to see what is in it."
L["STORAGE_MENU_DESC"] = "Where payloads are kept: ones you save from this character, and ones you paste in from somebody else.|n|nAdding one puts its actions in as pending, so none of your keys change until you accept them."

-- The drawer. **It is a place things pile up in, not a wizard**, so the empty state says what fills
-- it rather than what to do next - there is no next step until something is in there.
--
-- **The instruction came out when the button moved.** It stood on the far bottom corner of the
-- frame and this sentence was the only thing pointing at it; it stands directly above this text
-- now, so telling the reader to press it is the screen describing what the screen already shows.
-- What is left is the half a visible button cannot say: that anything landing here stays.
L["IMPORT_DRAWER_EMPTY"] = "Nothing here yet.|n|nA string you paste will sit here until you decide what to do with it, and it is kept afterwards - so you can come back and finish later."
L["IMPORT_PASTE_TITLE"] = "Paste a Debind string"
-- The two halves of the game's own import dialog, which this one is shaped after: a caption over
-- the box, and the instruction **inside** it. The caption names what the box holds; the
-- instruction says what to do and then gets out of the way the moment anything is typed. Blizzard
-- runs them as "Import Text" over "Paste loadout code here" - the caption deliberately does not
-- repeat the instruction, and the instruction deliberately does not repeat the title.
L["IMPORT_PASTE_INPUT_LABEL"] = "Text to import"
L["IMPORT_PASTE_INSTRUCTIONS"] = "Paste the Debind string here"
-- **A name, not a sender.** It asked "Who it came from", which presumes something the game cannot
-- do: no string is sent anywhere. One is copied off a page, out of a chat window, out of your own
-- notes - and the reader pasting their own backup had nothing to put there, which is the case a
-- name is worth most in. The client asks beside its own paste box and asks for a name
-- (HUD_CLASS_TALENTS_IMPORT_DIALOG_NAME_LABEL, "New Loadout Name").
--
-- No noun in front of it: the dialog title says what is being named.
L["IMPORT_PASTE_NAME"] = "Name (optional)"
-- **The client's own, taken whole.** Its loadout import dialog is this dialog - a box to paste
-- into, an optional name beside it, one button to finish - and that button is this global. So the
-- word is the game's in every locale and stays the game's if it ever changes it; enUS assigns it
-- and no other locale file carries the key.
--
-- It read "Add to drawer", which named a place nothing on screen is called and made the press
-- sound like filing rather than importing. The tab is Import and this is the button that does it.
L["IMPORT_PASTE_ACCEPT"] = HUD_CLASS_TALENTS_IMPORT_LOADOUT_ACCEPT_BUTTON
-- Two things about an entry, side by side. The row's second line puts the date in front of the
-- counts and the delete prompt puts the sender in front of the date, so what fills the two is the
-- caller's. **Two of the same conversion, so they are numbered** - a locale that wants them the
-- other way round can swap them, and unnumbered the swap would silently print them in the wrong
-- order.
L["IMPORT_ENTRY_LINE"] = "%1$s  %2$s"
L["IMPORT_ENTRY_COUNTS"] = "%1$d keys, %2$d actions"
-- The free text typed at paste time, on the row's tooltip. **The only human writing about an
-- entry**, and optional - so it is a line that may not be there rather than the name the entry is
-- known by. The class it came from is in that name already (`IMPORT_ENTRY_LINE`), which is why the
-- line that used to say it here is gone.
-- **The first line is the title**: this popup has no title bar, so it is what the reader reads
-- first and it has to name what goes.
--
-- **It said "from the drawer".** Nothing on this screen is called a drawer - the tab says Import
-- and the list has no name - so the phrase asked the reader to remove something from a place they
-- have never been shown. What it is being removed from is this list, and the popup is standing on
-- top of it.
L["IMPORT_DELETE_CONFIRM"] = "Remove |cnHIGHLIGHT_FONT_COLOR:%s|r?|n|nThis is the only copy. Anything you already added to your bindings stays where it is."
-- **Four, where the decoder reports eight.** Each of its reasons is a different step, but a reader
-- has three things they might do about one - look again at what they pasted, update, ask for it
-- again - and a sentence per step would spread those three over eight that all end the same way.
-- The mapping is `REASON_TEXT` in `StorageUI.lua`.
L["IMPORT_FAILED_NOT_OURS"] = "That is not a Debind string."
L["IMPORT_FAILED_TOO_NEW"] = "That string was made by a newer version of Debind. Update and try again."
-- The same refusal pointing the other way, and it must not borrow the sentence above: updating is
-- what the reader already did. There is nothing for them to do here, so this says so rather than
-- asking - and it says where the string can still be used, because it can.
L["IMPORT_FAILED_TOO_OLD"] = "That string was made by a version of Debind too old for this one to read.|n|nNothing you can do here changes that. The string still works in the version it came from."
L["IMPORT_FAILED_DAMAGED"] = "That string is a Debind string but could not be read. It was most likely copied only part of the way - ask for it again and copy the whole thing."
L["IMPORT_FAILED_LIBS_MISSING"] = "Debind Storage could not load the libraries it reads strings with. Downloading Debind again puts them back."
-- **What is missing is what this tab reads, not the tab.** Import and Export are Debind's own
-- panels now; `Debind Storage` is the load-on-demand part that keeps the strings, and without it
-- there is nothing for either to show. Switching it off in the AddOns list is the one way here.
L["PANEL_ADDON_MISSING"] = "This tab reads what |cnHIGHLIGHT_FONT_COLOR:Debind Storage|r keeps, and it could not be loaded.|n|nIf you switched it off, switch it back on in the AddOns list. If it is not in that list at all, install Debind again - Debind Storage comes with it."
-- **One box does both jobs**, so the label says what is true and not what a click would do. It
-- read "Select all" while checked, at the moment a click would put everything down.
--
-- **Both numbers, because one on its own reads as the total.** "Select all (8)" says there are
-- eight here, which is the opposite of what it meant on an entry of 24 with 8 picked.
L["EXPORT_SELECTED_COUNT"] = "%1$d of %2$d selected"
L["EXPORT_EMPTY"] = "There is nothing here to export yet."
L["EXPORT_LAYER_HEADER"] = "%1$s (%2$d/%3$d)"
L["EXPORT_LAYER_COUNT"] = "%d actions"
L["EXPORT_FAILED_LIBS_MISSING"] = "The libraries that build the string are missing, which means the install did not finish. Downloading Debind again brings them back."
L["EXPORT_COPY_TITLE"] = "Copy this string (Ctrl-C)"
