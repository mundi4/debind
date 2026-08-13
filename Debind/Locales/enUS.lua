local _, addon = ...;
addon.L = setmetatable({}, { __index = function(_, key) return key end });
local L = addon.L;

-- 색은 **클라이언트 색 이름**으로 쓴다(`|cnRED_FONT_COLOR:`). 날 hex는 애드온 고유색인
-- _MESSAGE_PREFIX 하나뿐이다 - 그것만 우리 것이고 나머지는 게임의 것이라, 게임이 색을
-- 바꾸면 같이 바뀌어야 맞다. 한때 같은 뜻에 hex와 색 이름이 섞여서, 빨강 하나가
-- 문자열마다 다른 빨강이었다.
L["_MESSAGE_PREFIX"] = "|cff3b9de3[Debind]|r "
L["ADD_CUSTOM_TARGET_MENUS_TO_UNIT_POPUP"] = "Add custom target menus on the unit popup"
L["ADD_CUSTOM_TARGET_MENUS_TO_UNIT_POPUP_DESC"] = "Add 'Set Custom Target' menu items to the unit popup menu if possible. These menus will only work when you are out of combat."
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
-- 목록 위 토글. 켜면 행을 가리키고 키를 누르는 것만으로 지정된다 - 자세한 근거는
-- DebindUI.xml의 BindModeButton 주석에.
L["BIND_MODE"] = "Set Keys"
L["BIND_MODE_STOP"] = "Done"
-- 클라이언트 전역을 그대로 받는다(OVERVIEW_NO_KEY와 같은 자리). 게임이 이미 제 나라 말로
-- 들고 있는 규칙이라 우리가 다시 번역할 것이 없고, 게임이 문구를 바꾸면 같이 바뀌어야 맞다.
L["BIND_MODE_UNBIND_HINT"] = ESCAPE_TO_UNBIND
L["BIND_MODE_CANCEL"] = "Cancel"
L["BIND_MODE_OVERLAY"] = "Point at an action on the right and press the key you want."
L["BIND_MODE_DESC"] = "Turns on a mode where whatever you press becomes the key for the action under your cursor. Selecting and the right-click menu pause while it is on."
L["BINDING_ERROR_BONUSBARS_NONE_SELECTED"] = "No action bar is selected."
L["BINDING_ERROR_CANNOT_USE_HOVER_WITH_CLIQUE"] = "Cannot be used with Clique!"
L["BINDING_ERROR_CONDITIONS_NEVER"] = "The conditions are impossible to meet."
L["BINDING_ERROR_FORMS_NONE_SELECTED"] = "No shapeshift form is selected."
L["BINDING_ERROR_GROUPS_NONE_SELECTED"] = "No group type is selected."
L["BINDING_ERROR_HOVER_NONE_SELECTED"] = "No reaction or frame type is selected."
L["BINDING_ERROR_NOT_SUPPORTED_GAMEMENU_KEY"] = "The key assigned for |cnHIGHLIGHT_FONT_COLOR:Toggle Game Menu|r cannot be used."
L["BINDING_ERROR_NOT_SUPPORTED_HOVER_CLICK_COMMAND"] = "Mouse buttons cannot be used for Binding Command that uses the hover condition."
L["BINDING_ERROR_NOT_SUPPORTED_MOUSE_BUTTON"] = "The left/right mouse button without modifier keys can only be used with the hover condition."
-- %s는 매크로 본문에 적힌 그 이름이다. **이 줄만 인자를 받는다** - 다른 BINDING_ERROR_*는
-- 어느 조건이 문제인지가 이미 그 칸에 보이는데, 이건 본문 안이라 이름을 적어주지 않으면
-- 무엇을 고쳐야 하는지가 안 보인다.
L["BINDING_ERROR_UNDEFINED_STATE"] = "There is no custom state named |cnHIGHLIGHT_FONT_COLOR:%s|r. Until the name is fixed this binding does not fire at all."
-- The second line that takes an argument, for the reason above: a macro name also lives inside the
-- action rather than in a condition control.
--
-- It goes on to name the two ways this happens. A macro name is something the user chose
-- themselves, so "there is no such macro" on its own reads as a typo -- while the common case, now
-- that bindings travel, is a binding that came from a machine where that macro did exist.
L["BINDING_ERROR_MISSING_MACRO"] = "There is no macro named |cnHIGHLIGHT_FONT_COLOR:%s|r on this account or character. It may have been renamed or deleted, or it may have come from someone else's setup."
L["BINDING_ERROR_UNREACHABLE"] = "This binding is always preceded by others."
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
L["CONDITION_CUSTOM_STATES"] = "Custom States"
L["CONDITION_CUSTOM_STATE_NO"] = "When the State Is Off"
L["CONDITION_CUSTOM_STATE_YES"] = "When the State Is On"
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
L["CUSTOM_STATE_INITIAL_VALUE"] = "Initial Value"
L["CUSTOM_STATE_LOGIN_OFF"] = "Turn off when logging in."
L["CUSTOM_STATE_LOGIN_ON"] = "Turn on when logging in."
L["CUSTOM_STATE_MODE_MACRO_CONDITIONAL_DESC"] = "This option lets the addon determine the value of the state based on macro conditional expressions (Example: |cnHIGHLIGHT_FONT_COLOR:[@healer,exists]|r)."
L["CUSTOM_STATE_MODE_MACRO_CONDITIONAL"] = "Set Automatically"
L["CUSTOM_STATE_MODE_MANUAL_INSTRUCTION"] = "You can change the value of the state here, or change it by using |cnBLUE_FONT_COLOR:Set Custom State|r action at any time (even in combat)."
L["CUSTOM_STATE_MODE_MANUAL"] = "Set Manually"
L["CUSTOM_STATE_NUM"] = "Custom State %d"
L["CUSTOM_STATE_OFF"] = "Off"
L["CUSTOM_STATE_ON"] = "On"
L["CUSTOM_STATE_REMEMBER"] = "Restore last state value when logging in."
-- 사용자 지정 상태 포트레잇 버튼의 툴팁이자, 조건 메뉴의 [Custom States] 설명이다.
-- 두 자리가 같은 문단을 쓴다 - CONDITION_CUSTOM_STATES_DESC라는 쌍둥이 키가 따로 있었는데,
-- 글자 하나 다르지 않은 문단을 로케일마다 두 번 번역하게 만드는 자리였다. 조건 메뉴 쪽은
-- 이제 이 키를 명시적으로 넘겨받는다(DropDownMenus.lua의 CreateCustomStateConditionMenu).
L["CUSTOM_STATES_DESC"] = "These are ON/OFF states that can be used as special conditions or macro conditional expressions in |cnLIGHTBLUE_FONT_COLOR:Custom Macros|r (Example: |cnHIGHLIGHT_FONT_COLOR:[$state1]|r). You can turn these states on or off at any time, or you can set them as macro conditionals themselves."
L["CUSTOM_STATES"] = "Custom States"
L["CUSTOM_TARGET_CLEAR"] = "Clear"
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
L["INACTIVE_SPEC_LABEL"] = "%s (Inactive)"
L["KEEP_IN_BINDING_CONTEXT_DESC"] = "The house editor claims a few keys for its own shortcuts while it is open, and this addon leaves those keys alone. An action bound to one of them does nothing while the editor is open.|n|nCheck this to take the key anyway: your action runs, and the editor's shortcut on that key does not. The editor still shows the key on its own button, so that button will look usable while doing nothing."
L["KEEP_IN_BINDING_CONTEXT"] = "Override the house editor"
L["KEY"] = "Key"
L["KEY_GROUP_UNBOUND"] = "No key assigned"
L["LIFE_ALIVE"] = "Alive"
L["LIFE_DEAD"] = "Dead"
L["LINE_TOOLTIP_CONDITION_LABEL"] = "%s:"
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
-- 셋째 마디를 빼면 **거짓말이 된다.** 레이어는 실행 순서의 네 번째 축이라(PRIORITY_DESC:
-- 중요도 → 마우스 올림 → 조건 → 탭 → 순서), 조건이 붙은 공유/일반 액션은 조건 없는
-- 공유/야성 액션보다 먼저 실행된다. 중요도를 건드렸으면 더 그렇다. 툴팁은 일부러 불러서
-- 읽는 글이라 이 길이가 부담이 아니고, 탭마다 반복돼도 한 번에 하나만 보인다.
--
-- **마우스 올림은 절에 안 적는다.** 그것도 탭을 이기는 축이 맞지만, 그 액션을 만든 사람은
-- 자기가 만든 줄 알고 있다 - 조건과 중요도처럼 나중에 잊고 부딪히는 것이 아니다. 넷을 다
-- 적으면 절이 문장보다 길어진다. 전부 알고 싶은 사람은 PRIORITY_DESC가 다섯 축을 순서대로
-- 적어 둔다.
--
-- 지는 쪽은 **레이어 이름 전체**로 부른다("Shared / Druid"). 툴팁 제목이 그 형식이라 참조도
-- 같아야 화면에서 찾을 수 있다 - 근거는 GetSideTabDescription 주석에.
--
-- 영어는 README의 Layers 표 오른쪽 열과 **같은 말**로 적는다. 표를 읽고 온 사람과 툴팁만
-- 보는 사람이 같은 문장을 읽어야 둘이 같은 것이라는 걸 안다.
L["LAYER_DESC_SHARED_GENERAL"] = "Every character on the account."
-- %s 둘은 차례로 직업명(UnitClass), 지는 레이어의 이름.
L["LAYER_DESC_SHARED_CLASS"] = "Every %1$s you own. Beats %2$s unless conditions or Importance say otherwise."
-- %s 셋은 차례로 직업명, 전문화명, 지는 레이어의 이름.
L["LAYER_DESC_SHARED_SPEC"] = "Every %1$s you own, while %2$s. Beats %3$s unless conditions or Importance say otherwise."
-- 여기만 지는 쪽이 레이어 하나가 아니라 공유 셋 전부라, 아래 탭 이름을 그대로 쓴다.
L["LAYER_DESC_CHARACTER_GENERAL"] = "This character. Beats everything Shared unless conditions or Importance say otherwise."
-- 인자는 차례로 지는 레이어의 이름, 전문화명. **위 둘과 차례가 다르다** - 영어는 전문화명을
-- 안 쓰기 때문이다(툴팁 제목이 이미 "Oreo / Balance"라 "this spec"으로 가리킬 것이 있다).
-- 지는 쪽을 1번으로 두면 영어가 자리 번호 없이 끝나고, 한국어만 번호로 차례를 되돌린다.
-- 근거는 GetSideTabDescription 주석에. 서식이 갈리는 것은 check-locales의 EXTRA_SPECS_OK가 안다.
L["LAYER_DESC_CHARACTER_SPEC"] = "This character, in this spec. Beats %s unless conditions or Importance say otherwise."
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
-- 결과 목록에서 **문제가 있는 행**이 순서 대신 다는 빨간 한 줄. `BINDING_ISSUE_*` 코드마다
-- 하나씩 있고, 없는 코드는 ORDER_FLAG_ISSUE로 물러난다(DebindUI.lua의 GetShortIssueText).
--
-- 같은 코드의 긴 문장은 `BINDING_ERROR_*`에 그대로 있다 - **그건 툴팁의 것이다.** 여기는
-- 170px이라 문장을 넣으면 잘리고, 잘린 문장은 아무 말도 안 하느니만 못하다. 대신 짧은 쪽은
-- **무엇을 고치면 되는지**를 말해야 한다. 총칭 하나로 때우던 때는 그걸 툴팁을 열어야 알았다.
L["ORDER_FLAG_BONUSBARS_NONE_SELECTED"] = "No action bar selected"
L["ORDER_FLAG_CANNOT_USE_HOVER_WITH_CLIQUE"] = "Clique conflict"
L["ORDER_FLAG_CONDITIONS_NEVER"] = "Conditions never match"
L["ORDER_FLAG_FORMS_NONE_SELECTED"] = "No form selected"
L["ORDER_FLAG_GROUPS_NONE_SELECTED"] = "No group selected"
L["ORDER_FLAG_HOVER_NONE_SELECTED"] = "No frame type selected"
L["ORDER_FLAG_ISSUE"] = "Has a problem"
L["ORDER_FLAG_MISSING_MACRO"] = "No such macro"
L["ORDER_FLAG_NOT_SUPPORTED_GAMEMENU_KEY"] = "Key opens game menu"
-- 마우스 버튼 두 코드는 서로 다른 규칙이라 문구도 갈라야 한다. 하나는 "호버를 켜면 된다",
-- 다른 하나는 "이 명령에는 어떤 마우스 버튼도 못 쓴다"라서 고칠 방법이 다르다.
L["ORDER_FLAG_NOT_SUPPORTED_HOVER_CLICK_COMMAND"] = "Mouse button not allowed"
L["ORDER_FLAG_NOT_SUPPORTED_MOUSE_BUTTON"] = "Mouse button needs hover"
L["ORDER_FLAG_UNDEFINED_STATE"] = "Unknown state name"
L["ORDER_FLAG_UNREACHABLE"] = "Never runs"
-- %s는 그 액션이 사는 레이어의 라벨(ORDER_LAYER_LABEL)이다.
L["ORDER_LAYER_LABEL"] = "%1$s / %2$s"
L["ORDER_GOTO_ACTION"] = "Go to it in %s"
-- 우클릭 줄은 오른쪽 목록의 것을 그대로 쓴다(LINE_TOOLTIP_INSTRUCTION_MESSAGE2). 두 목록 다
-- 그 액션의 메뉴가 열리므로 여기만 다른 말을 쓸 이유가 없다.
L["ORDER_LINE_TOOLTIP_INSTRUCTION_GOTO"] = "Left click to go to this action and edit it there."
L["OTHER_OPTIONS"] = "Other Options"
L["PET"] = "Pet"
L["PRIORITY_DESC"] = "The same key can be assigned to more than one action. When you press it, Debind tries them in order and runs the first one whose conditions are met -- only one of them ever runs.|n|nImportance is compared first, so it beats everything below it. Between actions that are equally important, the order is decided by:|n|n1. Hover -- an action that only runs while the mouse is over a unit frame is tried first.|n2. Conditions -- an action with conditions is tried before one without.|n3. Tab -- the more specific tab is tried first, from this character and specialization down to shared.|n4. Order -- when everything above is equal, the action you bound to the key first is tried first. That is also the only step you can move an action within."
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
L["PRIORITY_SHARED_WARNING"] = "This action is in a shared scope, so importance is shared too: it changes the order this action is tried on EVERY key it is bound to, on EVERY character of this account. What happens on your other characters cannot be shown here -- Debind only loads the bindings of the character you are on."
L["OVERVIEW"] = "Overview"
-- 이름표에 매달린 툴팁. 열 이름이 한 낱말이라 규칙 셋(키 걸린 것만 / 키로 묶임 / 지금
-- 캐릭터·특성 붙박이)을 말할 자리가 여기밖에 없다. 셋째 문장이 있는 이유는 오른쪽에서
-- 오프스펙을 열어도 왼쪽이 안 따라오기 때문이다 - 모르면 고장으로 읽힌다.
--
-- **"the keyboard you are playing with"라고 쓰지 말 것.** 설계 메모의 말버릇이지 플레이어의
-- 말이 아니다 - 저쪽에게 keyboard는 책상 위의 물건이라, 이 창이 그걸 보여준다는 소리가 된다.
L["OVERVIEW_DESC"] = "Every action that has a key right now, grouped by key. Within a key, they are listed in the order Debind tries them.|n|nWhat is listed is what your current character and specialization would actually do if you pressed the key now. Opening another tab or specialization on the right does not change it, and an action with no key is not listed here at all."
-- 결과 목록에서 한 행이 **바로 아래 행을 이긴 이유**. 순서를 가르는 축은 넷인데 비교자가
-- 위에서부터 훑으므로 처음 갈린 하나가 곧 답이다 - 그래서 다섯 중 언제나 하나만 나온다.
-- 칸 끝에 붙는 회색 한 줄이라 짧아야 한다. 주어는 그 행 자신이다.
-- 순서 이동 버튼. 3.0에서 그대로 돌아온 문자열이다 - 규칙이 안 바뀌었으므로 말도 안 바꾼다.
-- ORDER_BLOCKED_*는 `ComputeOrderSwap`이 돌려주는 사유 코드와 이름이 맞물려 있다.
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
L["ORDER_BLOCKED_PRIORITY"] = "It cannot pass the action next to it -- they have different importance, and importance is compared first."
L["ORDER_WHY_PRIORITY"] = "Importance: %s"
-- 정렬은 hover가 설정됐는지만 본다 - false("마우스오버가 아닐 때만")도 설정된 것이다.
-- 그래서 "hover"라고만 쓰면 false인 행에 거짓말이 된다. 어느 쪽인지는 툴팁이 말한다.
L["ORDER_WHY_HOVER"] = "Unit frame rule"
L["ORDER_WHY_CONDITIONAL"] = "Has conditions"
L["ORDER_WHY_LAYER"] = "%1$s over %2$s"
-- 넷이 다 동률일 때 남는 축. **"your order"라고 쓰면 안 된다** - 자리는 키를 걸 때 그 레이어의
-- 맨 뒤 번호로 자동으로 받는 것이고(Profile.lua의 PlaceLast), 사용자가 고른 적이 없다.
-- placement/put/set 계열이 전부 같은 이유로 거짓이 된다 - 위아래 버튼을 한 번도 안 누른
-- 사람에게는 자기가 놓은 자리가 아니다.
--
-- 지시문("화살표로 옮기세요")도 못 쓴다. 이 줄은 **버튼이 없는 행에도 뜬다** - 버튼은
-- isCurrent인 행에만 서는데(UpdateMoveButtons) 이유 줄은 그룹의 마지막 행만 빼고 다 붙는다.
--
-- 남는 참말은 "넷이 갈리지 않아 순서 그 자체가 정한다"뿐이다. 축의 이름은 PRIORITY_DESC
-- 4번이 부르는 그대로 쓴다 - 툴팁이 가르친 사다리와 칸이 같은 낱말로 맞물려야 한다.
L["ORDER_WHY_SEQ"] = "Order on this key"
L["PRIORITY"] = "Importance"
L["PRIORITY1"] = "Very High"
L["PRIORITY2"] = "High"
-- 순서 목록의 모든 행이 이 낱말을 쓰므로 짧아야 한다. 다섯 중 가운데라 메뉴에서도
-- 기본값이라는 게 자리로 읽힌다 - "(Default)"를 뒤에 달던 것을 뗐다.
L["PRIORITY3"] = "Normal"
L["PRIORITY4"] = "Low"
L["PRIORITY5"] = "Very Low"
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
L["SPELL_PICKER_SHOW_OFFSPEC"] = "Other specializations"
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
-- 아래 탭 둘의 툴팁 설명 줄. 사이드탭 쪽(LAYER_DESC_*)과 같은 마디로 적되, 여기는
-- 사이드탭 셋을 통째로 덮는 자리라 전문화까지 내려가지 않는다. 우선순위에 붙는 단서도
-- 같다 - 같은 주장이면 같은 데서 틀린다.
L["TAB_DESC_SHARED"] = "Every character on the account."
L["TAB_DESC_CHARACTER"] = "This character only. Beats Shared unless conditions or Importance say otherwise."
L["TARGET_UNIT_DESC"] = "The action is used on that unit without targeting it -- even when the hover condition is in play."
L["TARGET_UNIT"] = "Target"
L["TYPE_COMMAND"] = "Binding Command"
L["TYPE_FLYOUT"] = "Flyout"
L["TYPE_FOCUS_DESC"] = "Sets your focus to this unit. With a role-based unit, one key focuses whoever is tanking right now, without you finding them on the frames first."
L["TYPE_FOCUS"] = "Set Focus Target"
L["TYPE_ITEM"] = "Item"
L["TYPE_MACRO"] = "Macro"
L["TYPE_MACROTEXT_DESC"] = "Creates a macro that lives in this addon and leaves WoW's macro slots free. It can aim at special units and read custom states, which a macro in WoW's own list cannot.|n|nExample: |cnHIGHLIGHT_FONT_COLOR:/cast [@tank,exists] Rejuvenation|r"
L["TYPE_MACROTEXT"] = "Custom Macro"
L["TYPE_MOUNT"] = "Mount"
L["TYPE_PETACTION"] = "Pet Command"
L["TYPE_SETCUSTOM_DESC"] = "Pins the unit whose frame you are hovering over as this custom target. A custom target holds a unit the way focus does: aim at it with |cnHIGHLIGHT_FONT_COLOR:@custom1|r or |cnHIGHLIGHT_FONT_COLOR:@custom2|r in a custom macro, or hand it to any action as its target.|n|nWorks over Player, Pet, Party/Raid, Boss and Arena unit frames."
L["TYPE_SETCUSTOM"] = "Set Custom Target"
L["TYPE_SETCUSTOM1"] = "Set Custom Target 1"
L["TYPE_SETCUSTOM2"] = "Set Custom Target 2"
L["TYPE_SETSTATE_DESC"] = "Turns a custom state on or off. A custom state is a switch of your own that other actions take as a condition, so one key does one thing while it is on and another while it is off.|n|nIt flips |cnHIGHLIGHT_FONT_COLOR:in combat|r too, where WoW keeps you from changing a key binding."
L["TYPE_SETSTATE_OFF_NUM"] = "Turn Off Custom State %d"
L["TYPE_SETSTATE_ON_NUM"] = "Turn On Custom State %d"
L["TYPE_SETSTATE_TOGGLE_NUM"] = "Toggle Custom State %d"
L["TYPE_SETSTATE"] = "Set Custom State"
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
L["UNITFRAME_OPTIONS"] = "Unit frame options"
L["UNITFRAME_TRIGGER_ON_MOUSE_DOWN_DESC"] = "Trigger the action on mouse down instead of on mouse up for unit frames. Blizzard's default value is mouse up."
L["UNITFRAME_TRIGGER_ON_MOUSE_DOWN"] = "Use mouse down for click casting"
L["UNNAMED_ACTION"] = "(Unnamed)"
L["WARNING_MESSAGE_CLIQUE_DETECTED"] = "Because you are using Clique, some features of this addon will not work."
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
-- These live here rather than in `DebindShare` because they are eleven strings against that
-- addon's reason for existing, and a second locale tree would need its own parity check.
-- The window's own tabs (`PANELS` in `DebindUI.lua`). The label is one word, so the tooltip is
-- where the tab says what it opens - and Import and Export both open something that leaves for
-- somewhere you cannot reach, so the same "read it on purpose" rule as above applies.
--
-- The two panels themselves live in `DebindShare`, which is load-on-demand and may not be there.
-- **One failure, so one message.** That addon cannot load and then not have built its panel, so
-- "loaded but empty" is not a second case to describe - if it ever happened the install would be
-- broken, and the second line below is already the fix for that.
--
-- **It says what failed and what to do, not where our code lives.** Which addon holds which panel
-- is our filing, not the reader's problem; what they can act on is the switch in the AddOns list
-- and, failing that, installing again. No `%s` either, unlike the chat line further down - the
-- reason string the client hands back is for the log, not the middle of a window.
-- Taking the badge off imported actions. **The verb is about the reader, not the action** -
-- nothing is being changed or repaired, they are saying they will have it, and that is the moment
-- the keys start working.
L["APPROVE_IMPORT"] = "Accept as mine"
L["IMPORT_TITLE"] = "Import"
L["IMPORT_MENU_DESC"] = "Takes a string someone handed you and shows what is in it before anything changes.|n|nYou pick which layer each part lands in, and nothing touches your bindings until you say so."
-- The drawer. **It is a place things pile up in, not a wizard**, so the empty state has to say
-- what fills it rather than what to do next - there is no next step until something is in there.
L["IMPORT_DRAWER_EMPTY"] = "Nothing here yet.|n|nPaste a string somebody sent you and it will sit here until you decide what to do with it. Received strings are kept, so you can come back and finish later."
L["IMPORT_DRAWER_COUNT"] = "%d received"
L["IMPORT_PASTE"] = "Paste a string"
L["IMPORT_PASTE_TITLE"] = "Paste a Debind string"
-- The one thing about the sender that is ever stored, and only because the reader typed it. The
-- string itself carries no character name on purpose.
L["IMPORT_PASTE_SOURCE"] = "Who it came from (optional)"
L["IMPORT_PASTE_ACCEPT"] = "Add to drawer"
-- What a batch is called when no source was typed. Used as the row title and in the delete prompt,
-- so it has to read as a thing rather than as a blank.
L["IMPORT_BATCH_UNNAMED"] = "Received string"
L["IMPORT_BATCH_COUNTS"] = "%1$d keys, %2$d actions"
L["IMPORT_BATCH_AGE"] = "%s ago"
L["IMPORT_BATCH_AGE_PINNED"] = "%s ago - kept"
L["IMPORT_BATCH_AGE_EXPIRING"] = "%1$s ago - goes in %2$s"
L["IMPORT_BATCH_EXPIRED"] = "Past its keep-by date"
L["IMPORT_BATCH_FROM_CLASS"] = "From a %s"
L["IMPORT_BATCH_PIN"] = "Keep this one"
-- **"Not a later date."** Saying "keeps it longer" would invite the reader to look for how much
-- longer, and there is no such number - this takes the batch out of the sweep altogether.
L["IMPORT_BATCH_PIN_DESC"] = "Received strings are cleared out after about a month. This one will not be."
L["IMPORT_BATCH_DELETE"] = "Remove from drawer"
L["IMPORT_DELETE_CONFIRM"] = "Remove |cnHIGHLIGHT_FONT_COLOR:%s|r from the drawer?|n|nThis is the only copy. Anything you already added to your bindings stays where it is."
-- **Four, where the decoder reports eight.** Each of its reasons is a different step, but a reader
-- has three things they might do about one - look again at what they pasted, update, ask for it
-- again - and a sentence per step would spread those three over eight that all end the same way.
-- The mapping is `REASON_TEXT` in `WorkbenchUI.lua`.
L["IMPORT_FAILED_NOT_OURS"] = "That is not a Debind string."
L["IMPORT_FAILED_TOO_NEW"] = "That string was made by a newer version of Debind. Update and try again."
L["IMPORT_FAILED_DAMAGED"] = "That string is a Debind string but could not be read. It was most likely copied only part of the way - ask for it again and copy the whole thing."
L["IMPORT_FAILED_LIBS_MISSING"] = "Debind Share could not load the libraries it reads strings with. Downloading Debind again puts them back."
L["PANEL_ADDON_MISSING"] = "This needs |cnHIGHLIGHT_FONT_COLOR:Debind Share|r, and it could not be loaded.|n|nIf you switched it off, switch it back on in the AddOns list. If it is not in that list at all, install Debind again - Debind Share comes with it."
L["EXPORT_TITLE"] = "Export"
L["EXPORT_MENU_DESC"] = "Turns any part of your setup into a string you can hand to someone else or keep as a backup.|n|nEverything is selected when the window opens, and the specs you are not playing right now are in the list too - you do not have to switch to send them."
L["EXPORT_SELECT_ALL"] = "Select all"
L["EXPORT_SELECT_ALL_COUNT"] = "Select all (%d)"
L["EXPORT_STRIP_KEYS"] = "Leave the keys out"
L["EXPORT_STRIP_KEYS_DESC"] = "Sends the actions without the keys they are on, so whoever receives them picks their own.|n|nWhat has to stay together still does. A key split across several conditional actions arrives as one group, and the far side binds the group rather than the loose pieces."
L["EXPORT_GENERATE"] = "Create string"
L["EXPORT_EMPTY"] = "There is nothing here to export yet."
L["EXPORT_ROW_NO_KEY"] = "No key"
L["EXPORT_LAYER_COUNT"] = "%d actions"
L["EXPORT_FAILED_LIBS_MISSING"] = "The libraries that build the string are missing, which means the install did not finish. Downloading Debind again brings them back."
L["EXPORT_COPY_TITLE"] = "Copy this string (Ctrl-C)"
