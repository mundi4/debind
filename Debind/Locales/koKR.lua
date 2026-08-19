-- 용어는 **koKR 클라이언트가 쓰는 말**을 그대로 받는다(GlobalStrings 대조). 주시 대상, 방어 전담,
-- 지원공격 전담, 위치 표시기, 행동 단축바, 키 설정 해제, 게임 메뉴 열기/닫기, 자신에게 자동 시전.
-- 애드온이 제 말을 따로 만들면 같은 것을 게임과 애드온이 두 이름으로 부르게 된다.
--
-- **"유닛 프레임"으로 되돌리지 말 것.** 클라이언트 문자열 12,431개에 "유닛"은 0회, "프레임"은
-- 22회인데 전부 프레임율(FPS)과 /프레임구성이다 - 한국어 플레이어에게 "프레임"은 초당 프레임
-- 수다. 유닛 창의 이름은 UNITFRAME_LABEL = "개체창"이고, unit 자체는 "개체"다
-- (COMBATLOG_FILTER_STRING_CUSTOM_UNIT = "사용자 개체"). "대상"은 target이 이미 쓰고 있어서
-- unit에 돌려쓸 수 없다.
--
-- 같은 이유로 "자세"도 안 쓴다. 클라이언트에서 자세는 전부 "자세한/자세히"(detailed)이고,
-- stance는 "태세"다(TUTORIAL61_WARRIOR = "방어 태세"). 반대로 "반응"(reaction)은 클라이언트의
-- 말이 맞다(OPTION_TOOLTIP_USE_COLORBLIND_MODE의 "unit reactions" -> "상대방의 반응").
local _, addon = ...;
local L = addon.L;
if (GetLocale() ~= "koKR") then return end

L["_MESSAGE_PREFIX"] = "|cff3b9de3[Debind]|r "
L["ADD_CUSTOM_TARGET_MENUS_TO_UNIT_POPUP"] = "개체 우클릭 메뉴에 사용자 지정 대상 항목 추가"
L["ADD_CUSTOM_TARGET_MENUS_TO_UNIT_POPUP_DESC"] = "가능한 경우 개체 우클릭 메뉴에 '사용자 지정 대상 지정' 항목을 추가합니다. 이 항목은 전투 중이 아닐 때만 동작합니다."
L["ADDON_NAME"] = "Debind"
L["ALL"] = "전체"
-- 근거는 enUS 쪽 주석에.
L["BULK_MENU_TITLE"] = "%d개 선택됨"
L["BULK_SELECTED_COUNT"] = "%d개 선택됨"
-- The toggle in the portrait row. Why it names the mode instead of the act is in the enUS comment.
--
-- **"키 지정" is kept and 모드 is added to it.** The client's own words for this are
-- `QUICK_KEYBIND_MODE`, "빠른 단축키 지정 모드", and the half that is left after dropping 빠른 is
-- "단축키 지정" - which this addon's capture dialog already carries (`KEY_CAPTURE_TITLE`). Taking
-- it here would give one window two things under one name.
L["BIND_MODE"] = "키 지정 모드"
L["BIND_MODE_STOP"] = "완료"
-- **BIND_MODE_UNBIND_HINT는 이제 여기 있어야 한다.** enUS가 클라이언트 전역
-- ESCAPE_TO_UNBIND를 담고 있던 동안에는 한국어가 공짜로 나왔지만, 그 문장이 이 자리에서 틀려서
-- 우리 문장으로 바뀌었다(근거는 enUS 쪽 주석). 번역이 들어오기 전까지 이 줄만 영어로 나온다.
L["BIND_MODE_CANCEL"] = "취소"
L["BIND_MODE_OVERLAY"] = "오른쪽에서 행동을 가리키고 원하는 키를 누르십시오."
L["BIND_MODE_DESC"] = "마우스가 가리키는 행동에 누른 키가 그대로 지정되는 모드를 켭니다. 켜져 있는 동안에는 선택과 우클릭 메뉴가 멈춥니다."
L["BINDING_ERROR_BONUSBARS_NONE_SELECTED"] = "선택된 행동 단축바가 없습니다."
L["BINDING_ERROR_CANNOT_USE_HOVER_WITH_CLIQUE"] = "Clique와 함께 쓸 수 없습니다!"
L["BINDING_ERROR_CONDITIONS_NEVER"] = "충족할 수 없는 조건입니다."
L["BINDING_ERROR_FORMS_NONE_SELECTED"] = "선택된 변신 형태가 없습니다."
L["BINDING_ERROR_GROUPS_NONE_SELECTED"] = "선택된 그룹 종류가 없습니다."
L["BINDING_ERROR_HOVER_NONE_SELECTED"] = "선택된 반응이나 개체창 종류가 없습니다."
L["BINDING_ERROR_NOT_SUPPORTED_GAMEMENU_KEY"] = "|cnHIGHLIGHT_FONT_COLOR:게임 메뉴 열기/닫기|r에 지정된 키는 쓸 수 없습니다."
L["BINDING_ERROR_NOT_SUPPORTED_HOVER_CLICK_COMMAND"] = "마우스 버튼은 마우스 올림 조건을 쓰는 단축키 명령에 쓸 수 없습니다."
L["BINDING_ERROR_NOT_SUPPORTED_MOUSE_BUTTON"] = "조합 키 없는 마우스 왼쪽/오른쪽 버튼은 마우스 올림 조건에서만 쓸 수 있습니다."
L["BINDING_ERROR_MISSING_MACRO"] = "|cnHIGHLIGHT_FONT_COLOR:%s|r라는 매크로가 이 계정에도 이 캐릭터에도 없습니다. 이름이 바뀌었거나 지워졌거나, 남의 설정에서 온 것일 수 있습니다."
L["BINDING_ERROR_UNDEFINED_STATE"] = "|cnHIGHLIGHT_FONT_COLOR:%s|r라는 사용자 지정 상태가 없습니다. 이름을 고치기 전까지 이 지정은 아예 발동하지 않습니다."
L["BINDING_ERROR_UNREACHABLE"] = "이 행동은 실행되지 않습니다. 어떤 경우에도 이 키의 다른 행동이 먼저 실행됩니다."
L["BINDING_TITLE"] = "%2$s (%1$s)"
L["BLIZZARD_UNIT_FRAMES_ARENA"] = "투기장 개체창"
L["BLIZZARD_UNIT_FRAMES_BOSS"] = "우두머리 개체창"
L["BLIZZARD_UNIT_FRAMES_PARTY"] = "파티 개체창"
L["BLIZZARD_UNIT_FRAMES_PET"] = "소환수 개체창"
L["BLIZZARD_UNIT_FRAMES_PLAYER"] = "플레이어 개체창"
L["BLIZZARD_UNIT_FRAMES_RAID"] = "공격대 개체창"
L["BLIZZARD_UNIT_FRAMES_TARGET"] = "대상 및 주시 대상"
L["BLIZZARD_UNIT_FRAMES"] = "블리자드 기본 개체창"
L["CANNOT_OPEN_IN_COMBAT"] = "전투 중에는 열 수 없습니다."
L["CANNOT_OPEN_WITH_GAME_MENU"] = "게임 메뉴를 먼저 닫으십시오."
L["COMPARTMENT_TOOLTIP_LEFT_CLICK"] = "클릭하면 Debind가 열립니다. 왼쪽 열이 단축키 개요입니다."
L["CONDITION_ACTIONBARS"] = "행동 단축바"
L["CONDITION_BONUSBAR"] = "태세별 행동 단축바"
L["CONDITION_COMBAT_NO"] = "전투 중이 아닐 때"
L["CONDITION_COMBAT_YES"] = "전투 중일 때"
L["CONDITION_COMBAT"] = "전투"
L["CONDITION_CUSTOM_STATES"] = "사용자 지정 상태"
L["CONDITION_CUSTOM_STATE_NO"] = "상태가 꺼져 있을 때"
L["CONDITION_CUSTOM_STATE_YES"] = "상태가 켜져 있을 때"
L["CONDITION_EXTRABAR_NO"] = "기타 행동 버튼이 없을 때"
L["CONDITION_EXTRABAR_YES"] = "기타 행동 버튼이 있을 때"
L["CONDITION_EXTRABAR"] = "기타 행동 버튼"
L["CONDITION_FRAMETYPES"] = "개체창 종류"
L["CONDITION_GROUP"] = "그룹"
L["CONDITION_HOVER_NO"] = "마우스를 올리지 않았을 때"
L["CONDITION_HOVER_YES"] = "마우스를 올렸을 때"
L["CONDITION_HOVER"] = "개체창에 마우스 올림"
L["CONDITION_KNOWN"] = "습득"
L["CONDITION_KNOWN_YES"] = "주문을 배웠을 때만"
L["CONDITION_PET_NO"] = "소환수가 없을 때"
L["CONDITION_PET_YES"] = "소환수가 있을 때"
L["CONDITION_PET"] = "소환수"
L["CONDITION_PETBATTLE_NO"] = "애완동물 대전 중이 아닐 때"
L["CONDITION_PETBATTLE_YES"] = "애완동물 대전 중일 때"
L["CONDITION_PETBATTLE"] = "애완동물 대전"
L["CONDITION_REACTIONS"] = "반응"
L["CONDITION_SHAPESHIFT"] = "변신"
L["CONDITION_SPECIALBAR_DESC"] = "차량이나 조종 상태처럼 무언가가 기본 행동 단축바를 대신하고 있는 동안 활성화됩니다."
L["CONDITION_SPECIALBAR_NO"] = "특수 단축바가 활성화되지 않았을 때"
L["CONDITION_SPECIALBAR_YES"] = "특수 단축바가 활성화되었을 때"
L["CONDITION_SPECIALBAR"] = "특수 단축바"
L["CONDITION_STEALTH_NO"] = "은신 중이 아닐 때"
L["CONDITION_STEALTH_YES"] = "은신 중일 때"
L["CONDITION_STEALTH"] = "은신"
L["CONDITION_UNIT_DOES_NOT_EXIST"] = "개체가 없을 때"
L["CONDITION_UNIT_EXISTS"] = "개체가 있을 때"
L["CONDITION_LIFE"] = "생사"
L["CONDITION_UNITS"] = "개체"
L["CONFIRM_CURRENT_CHANGE_FIRST"] = "지금 변경 사항을 먼저 확정하십시오."
L["CONVERT_TO_MACRO_TEXT"] = "|cnLIGHTBLUE_FONT_COLOR:사용자 지정 매크로|r로 변환"
L["COPY_TO"] = "복사할 곳..."
-- 근거는 enUS 쪽 주석에.
L["CURRENT_TAB_SUFFIX"] = "%s |cnLIGHTGRAY_FONT_COLOR:(현재)|r"
L["CUSTOM_STATE_DISPLAY_MESSAGE"] = "바뀔 때 메시지 표시"
L["CUSTOM_STATE_EDIT_VALUE_DESC"] = "매크로 조건문을 입력하십시오.\n(예: |cnHIGHLIGHT_FONT_COLOR:[@tank,exists,combat]|r)"
L["CUSTOM_STATE_EDIT_VALUE"] = "매크로 조건문을 입력하십시오."
L["CUSTOM_STATE_INITIAL_VALUE"] = "초기값"
L["CUSTOM_STATE_LOGIN_OFF"] = "접속할 때 끄기"
L["CUSTOM_STATE_LOGIN_ON"] = "접속할 때 켜기"
L["CUSTOM_STATE_MODE_MACRO_CONDITIONAL_DESC"] = "매크로 조건문을 보고 애드온이 상태 값을 정하게 합니다 (예: |cnHIGHLIGHT_FONT_COLOR:[@healer,exists]|r)."
L["CUSTOM_STATE_MODE_MACRO_CONDITIONAL"] = "자동으로 지정"
L["CUSTOM_STATE_MODE_MANUAL_INSTRUCTION"] = "여기서 상태 값을 바꿀 수 있고, |cnBLUE_FONT_COLOR:사용자 지정 상태 지정|r 행동으로 언제든지(전투 중에도) 바꿀 수 있습니다."
L["CUSTOM_STATE_MODE_MANUAL"] = "직접 지정"
L["CUSTOM_STATE_NUM"] = "사용자 지정 상태 %d"
L["CUSTOM_STATE_OFF"] = "꺼짐"
L["CUSTOM_STATE_ON"] = "켜짐"
L["CUSTOM_STATE_REMEMBER"] = "접속할 때 마지막 상태 값 복원"
-- 근거는 enUS 쪽 주석에.
L["CUSTOM_STATES_DESC"] = "|cnLIGHTBLUE_FONT_COLOR:사용자 지정 매크로|r에서 특수 조건이나 매크로 조건문으로 쓸 수 있는 켜짐/꺼짐 상태입니다 (예: |cnHIGHLIGHT_FONT_COLOR:[$state1]|r). 언제든지 켜고 끌 수 있고, 상태 자체를 매크로 조건문으로 지정할 수도 있습니다."
L["CUSTOM_STATES"] = "사용자 지정 상태"
L["CUSTOM_TARGET_CLEAR"] = "지우기"
L["CUSTOM_TARGET_FAILED"] = "|cnHIGHLIGHT_FONT_COLOR:%1$s|r - |cnRED_FONT_COLOR:'%2$s'에서 지정하지 못했습니다|r"
L["CUSTOM_TARGET_HELP_MESSAGE_ARENA"] = "투기장 개체창에 마우스를 올린 채로 해 보십시오."
L["CUSTOM_TARGET_HELP_MESSAGE_BOSS"] = "우두머리 개체창에 마우스를 올린 채로 해 보십시오."
L["CUSTOM_TARGET_HELP_MESSAGE_GROUP"] = "파티/공격대 개체창에 마우스를 올린 채로 해 보십시오."
L["CUSTOM_TARGET_HELP_MESSAGE_PET"] = "소환수 개체창에 마우스를 올린 채로 해 보십시오."
L["CUSTOM_TARGET_HELP_MESSAGE_PLAYER"] = "플레이어 개체창이나 파티/공격대 개체창에 마우스를 올린 채로 해 보십시오."
L["CUSTOM_TARGET_INVALIDATED"] = "|cnHIGHLIGHT_FONT_COLOR:%s|r - |cnRED_FONT_COLOR:해제됨|r - 이름이 아니라 그룹 자리로 붙들고 있었는데 그룹이 바뀌었습니다. 다시 지정하십시오."
L["CUSTOM_TARGET_SET_VOLATILE"] = "|cnHIGHLIGHT_FONT_COLOR:%1$s|r - %2$s(으)로 지정 - 이번 전투 중에 그룹이 바뀌어서 이름이 아니라 그룹 자리로 붙들고 있습니다. 전투가 끝난 뒤 다시 지정하면 그 사람을 따라갑니다."
L["CUSTOM_TARGET_UNSUPPORTED_UNIT_IN_COMBAT"] = "|cnHIGHLIGHT_FONT_COLOR:%1$s|r - |cnRED_FONT_COLOR:전투 중에는 '%2$s'에서 지정할 수 없습니다|r"
L["CUSTOM_TARGET_UNSUPPORTED_UNIT"] = "|cnHIGHLIGHT_FONT_COLOR:%1$s|r - |cnRED_FONT_COLOR:지원하지 않는 개체: %2$s|r"
L["DEFAULT"] = "기본값"
L["DELETE_CONFIRM_MESSAGE"] = "|cnHIGHLIGHT_FONT_COLOR:%s|r을(를) 삭제하시겠습니까?"
-- 근거는 enUS 쪽 주석에.
L["DELETE_CONFIRM_MESSAGE_MULTIPLE"] = "행동 |cnHIGHLIGHT_FONT_COLOR:%d|r개를 삭제하시겠습니까?"
L["DELETE"] = "삭제"
L["OVERVIEW_EMPTY"] = "아직 지정된 키가 없습니다. 오른쪽에서 행동에 키를 주면 여기에 나타납니다."
-- OVERVIEW_NO_KEY는 여기 없어야 맞다. enUS가 클라이언트 전역 NOT_BOUND를 담고 있어서
-- 한국어 클라이언트에서 이미 제 나라 말로 나온다. 여기서 덮으면 오히려 손해다.
L["DISABLE"] = "비활성화"
L["DISABLE_ALL"] = "모두 비활성화"
L["EDIT_MACRO"] = "매크로 편집"
L["ERROR_MESSAGE_CANNOT_SET_CUSTOM_TARGET_IN_COMBAT"] = "전투 중에는 명령으로 사용자 지정 대상을 지정할 수 없습니다."
L["EXCLUDE_PLAYER_DESC"] = "역할 기반 개체를 찾을 때 자신을 제외합니다."
L["EXCLUDE_PLAYER"] = "자신 제외"
L["FRAMETYPE_ARENA"] = "투기장 개체창"
L["FRAMETYPE_BOSS"] = "우두머리 개체창"
L["FRAMETYPE_GROUP"] = "파티/공격대 개체창"
L["FRAMETYPE_PET"] = "소환수 개체창"
L["FRAMETYPE_PLAYER"] = "플레이어 개체창"
L["FRAMETYPE_TARGET"] = "대상 및 주시 대상"
L["FRAMETYPE_UNKNOWN"] = "기타"
L["GENERAL"] = "일반"
L["GROUP_NONE"] = "그룹에 속하지 않았을 때"
L["GROUP_PARTY"] = "파티에 속했을 때"
L["GROUP_RAID"] = "공격대에 속했을 때"
L["IGNORE_HOVER_UNIT_DESC"] = "선택하면 개체창의 개체를 무시합니다."
L["IGNORE_HOVER_UNIT"] = "마우스 올린 개체 무시"
L["INACTIVE_SPEC_DESC"] = "여기 넣은 키는 이 전문화일 때부터 적용됩니다."
L["INACTIVE_SPEC_LABEL"] = "%s (비활성)"
L["KEEP_IN_BINDING_CONTEXT_DESC"] = "주택 편집기는 열려 있는 동안 몇몇 키를 제 단축키로 가져가고, 이 애드온은 그 키를 건드리지 않습니다. 그 키에 지정된 행동은 편집기가 열려 있는 동안 아무 일도 하지 않습니다.|n|n그래도 키를 가져오려면 체크하십시오. 내 행동이 실행되고, 그 키에 걸린 편집기 단축키는 동작하지 않습니다. 편집기는 여전히 제 버튼에 그 키를 보여주므로, 그 버튼은 쓸 수 있어 보이면서 아무 일도 하지 않습니다."
L["KEEP_IN_BINDING_CONTEXT"] = "주택 편집기보다 우선"
L["KEY"] = "키"
-- 제목이 곧 시킬 말이다. 근거는 enUS 쪽 주석에.
-- Three names for one act stand in this window, and each one says which shape it is: this dialog is
-- "단축키 지정", the toggle is "키 지정 모드" (BIND_MODE), and the client's own key list is
-- "단축키 설정" (KEY_BINDING). None of them may borrow another's words.
L["KEY_CAPTURE_TITLE"] = "단축키 지정"
L["KEY_CAPTURE_DESC"] = "아무 키나 누르면 그 키로 지정됩니다. 마우스 버튼과 휠도 되지만, 그건 이 창 위에서 눌러야 합니다."
L["KEY_CAPTURE_CURRENT_KEY"] = "현재 키:"
-- 겨눈 것들이 서로 다른 키에 걸려 있을 때. 개수를 안 쓰는 이유는 enUS 쪽 주석에.
L["KEY_CAPTURE_CURRENT_KEY_MIXED"] = "제각각"
L["KEY_CAPTURE_TARGETS"] = "다음 행동들에 적용됩니다:"
L["KEY_CAPTURE_MORE"] = "...외 %d개"
-- 키 없는 그룹의 키 자리는 OVERVIEW_NO_KEY(클라이언트 전역 NOT_BOUND)로 나간다. 여기 적을 것이
-- 없다 - 근거는 enUS 쪽 주석에.
-- 받아온 그룹은 그 자리에 보낸 쪽 키가 선다. "왔다"이지 "였다"가 아닌 이유는 enUS 쪽 주석에.
L["OVERVIEW_IMPORTED_FROM_KEY"] = "%s에서"
-- 행에서 여는 쪽. 머리글 것과 낱말이 같고 키만 다른 이유는 enUS 쪽 주석에.
--
-- **목록 둘에서 읽히는 툴팁이다.** 오버뷰 행과 통 행이 같은 항목을 쓰는데, 통 쪽은 이름순이라
-- "한 키를 여럿이 나눠 쓴다"는 것을 화면이 아예 안 보여준다. **"~라면"이 그 전제를 문장이
-- 직접 세우게 해준다** - 못 보는 쪽에는 알려주고, 보는 쪽에는 가리키기만 한다. 나머지 근거는
-- enUS 쪽 주석에.
L["ACTION_SET_KEY"] = "단축키 지정"
L["ACTION_SET_KEY_DESC"] = "이 행동의 단축키를 정합니다.|n|n이 행동이 한 키를 함께 쓰는 묶음의 일부라면, 바뀌는 것은 이 행동 하나입니다 - 나머지는 원래 키를 그대로 씁니다. 양쪽 키 다 동작합니다, 함께 나가지 않을 뿐입니다."
-- 머리글에서 여는 쪽. 범위를 라벨이 아니라 툴팁이 지는 이유(메뉴 폭)와, 「단축키 지정」이
-- `KEY_CAPTURE_TITLE`과 같은 이유는 enUS 쪽 주석에.
--
-- **"아직 안 받은 것은 받는 것까지 겸한다"는 둘째 문단이 빠졌다.** 맞는 말이지만 이 항목은
-- 머리글마다 서므로, 문자열을 한 번도 안 받아본 사람 전부가 읽게 된다. 근거는 enUS 쪽 주석에.
L["KEY_HEADER_SET_KEY"] = "단축키 지정"
L["KEY_HEADER_SET_KEY_DESC"] = "이 머리글 아래의 행동 전부에 단축키 하나를 한 번에 지정합니다. 접어놨든 몇 개가 들었든 전부입니다."
-- "이 캐릭터의 모든 전문화를 통틀어"였다가 고쳤다. 저 열한 레이어에는 직업 공유 둘과 계정
-- 공유 하나가 들어 있어서, 세는 범위가 이 캐릭터에서 끝나지 않는다. 근거는 enUS 쪽 주석에.
L["KEY_GROUP_CONFLICT"] = "|cnHIGHLIGHT_FONT_COLOR:%2$s|r에는 이미 |cnHIGHLIGHT_FONT_COLOR:%3$d|r개가 걸려 있습니다 - 전문화를 가리지 않고, 이 캐릭터에서 그 키에 걸리는 것 전부입니다.|n|n|cnHIGHLIGHT_FONT_COLOR:%1$s|r이(가) 그 키로 가면 그것들은 어떻게 할까요?"
-- 세어준 것 중에 공유 범위 것이 있을 때만 붙는다. 버튼 이름을 문장에 안 적는 이유는 enUS 쪽에.
L["KEY_GROUP_CONFLICT_SHARED"] = "그중 일부는 다른 캐릭터의 것이기도 합니다 - 거기서도 그 키에 걸려 있고, 키를 뺏으면 그 캐릭터들에서도 사라집니다."
-- **enUS가 「Keep both」/「Unbind them」으로 갔고 여기는 아직 옛 낱말이다.** 키 이름만 따라왔다 -
-- 값을 안 옮긴 것은 미룬 것이지 반대한 것이 아니다. 거짓이 되지도 않았는데, 「합치기」는 둘 다
-- 남는다는 것을 약하게나마 말하고 있고 그 아래 툴팁이 "아무것도 키를 잃지 않습니다"로 그 몫을
-- 대신 진다(enUS 라벨은 그 말을 스스로 해서 툴팁에서 뺐다). 「덮어쓰기」는 과장인 채로 남아 있고,
-- 그 교정은 툴팁이 한다.
L["KEY_GROUP_CONFLICT_KEEP"] = "합치기"
L["KEY_GROUP_CONFLICT_KEEP_DESC"] = "아무것도 키를 잃지 않습니다. 이미 걸려 있던 것들 옆에 나란히 서고, 키를 누르면 위에서부터 훑어 조건이 맞는 첫 번째가 실행됩니다 - 그래서 무엇이 나갈지는 늘어선 순서가 정하고, 그 순서는 나중에 바꿀 수 있습니다."
L["KEY_GROUP_CONFLICT_UNBIND"] = "덮어쓰기"
L["KEY_GROUP_CONFLICT_UNBIND_DESC"] = "그 키에 걸려 있던 것은 전부 키를 잃습니다 - 화면에 보이는 것만이 아닙니다. 지워지지는 않습니다: 키 없는 상태로 목록 맨 아래에 모이고, 거기서 다시 지정할 수 있습니다."
L["LIFE_ALIVE"] = "살아있음"
L["LIFE_DEAD"] = "죽음"
L["LINE_TOOLTIP_CONDITION_LABEL"] = "%s:"
L["LINE_TOOLTIP_IMPORTED"] = "문자열로 받아온 것입니다. 받아들이기 전까지는 어떤 키에도 걸리지 않습니다."
-- 키를 지정한다는 말이 빠진 이유는 enUS 쪽 주석에.
L["LINE_TOOLTIP_INSTRUCTION_MESSAGE1"] = "왼쪽 클릭하면 이 행동을 선택합니다. CTRL이나 SHIFT를 누른 채 클릭하면 여러 개를 고를 수 있습니다."
L["LINE_TOOLTIP_INSTRUCTION_BIND"] = "아무 키나 마우스 버튼을 누르면 이 행동에 지정됩니다."
L["LINE_TOOLTIP_INSTRUCTION_MESSAGE2"] = "오른쪽 클릭하면 다른 항목이 나옵니다."
L["LOGIN_MESSAGE"] = "/deb 명령어를 입력하면 창이 열립니다."
-- 세로 탭 툴팁의 설명 줄. 근거는 enUS 쪽 주석에.
--
-- 우선 대상은 **화면에 적힌 낱말로 부른다.** 아래 탭은 SHARED_BINDINGS = "공유"라서 여기서도
-- "공유"다 - 툴팁만 "공용"이라 부르면 같은 것을 두 이름으로 부르게 된다.
--
-- 단서는 영어가 뒤에 붙이는 절("unless …")을 한국어에서는 **앞에 세운다.** 뒤에 달면
-- "우선합니다"를 읽은 뒤에 뒤집는 꼴이라 문장을 두 번 읽게 된다.
L["LAYER_DESC_SHARED_GENERAL"] = "계정 내 모든 캐릭터용."
L["LAYER_DESC_SHARED_CLASS"] = "계정 내 모든 %1$s용. 조건과 중요도가 같다면 여기 있는 키가 %2$s의 같은 키보다 우선합니다."
-- 조사가 직업명 받침을 타므로 "(가)"를 붙인다(사냥꾼이 / 드루이드가). DELETE_CONFIRM_MESSAGE의
-- "을(를)"과 같은 방식이다.
L["LAYER_DESC_SHARED_SPEC"] = "계정 내 모든 %1$s이(가) %2$s일 때. 조건과 중요도가 같다면 여기 있는 키가 %3$s의 같은 키보다 우선합니다."
L["LAYER_DESC_CHARACTER_GENERAL"] = "이 캐릭터 전용. 조건과 중요도가 같다면 여기 있는 키가 공유 전체의 같은 키보다 우선합니다."
-- 영어는 인자가 하나도 없고(툴팁 제목이 전문화를 이미 보여준다) 여기는 전문화명 하나를 받는다.
-- 근거는 enUS 쪽 주석에.
L["LAYER_DESC_CHARACTER_SPEC"] = "이 캐릭터가 %s일 때. 조건과 중요도가 같다면 여기 있는 키가 다른 모든 탭의 같은 키보다 우선합니다."
-- 레이어의 짧은 이름. 근거는 enUS 쪽 주석에.
L["LAYER_SHORT_ACCOUNT"] = "계정"
L["LAYER_SHORT_CLASS"] = "직업"
L["LAYER_SHORT_SPEC"] = "전문화"
L["LAYER_SHORT_CHARACTER"] = "캐릭터"
L["LAYER_SHORT_CHARACTER_SPEC"] = "캐릭터 전문화"
L["MACRO_POPUP_TEXT"] = "매크로 이름 입력 (최대 %d자):"
L["MACROFRAME_CHAR_LIMIT"] = "%1$d/%2$d자 사용"
L["MOVE_TO"] = "옮길 곳..."
L["MOVE_TO_CURRENT_TAB_BLOCKED"] = "이미 이 탭에 있습니다."
L["NO_ACTIONS_IN_THIS_TAB"] = "이 탭에는 행동이 없습니다. 주문, 매크로, 아이템, 탈것을 여기로 끌어다 놓으면 새 행동이 추가됩니다."
-- 근거는 enUS 쪽 주석에.
L["NO_SEARCH_RESULTS"] = "검색과 맞는 것이 없습니다."
L["NO_SHAPESHIFT"] = "변신하지 않음"
L["NOT_SELECTED"] = "선택 안 됨"
L["ONLY_IF"] = "다음일 때만..."
L["OPTIONS"] = "설정"
-- 문제마다 하나씩 있던 짧은 문구는 걷어냈다. 근거는 enUS 쪽 주석에.
L["ORDER_FLAG_ISSUE"] = "문제 있음"
L["ORDER_FLAG_UNREACHABLE"] = "실행되지 않음"
L["ORDER_FLAG_OFFSPEC"] = "비활성 전문화"
L["ORDER_LAYER_LABEL"] = "%1$s / %2$s"
L["ORDER_GOTO_ACTION"] = "%s에서 보기"
L["ORDER_LINE_TOOLTIP_INSTRUCTION_GOTO"] = "왼쪽 클릭하면 그 행동으로 옮겨 가서 편집합니다."
L["OTHER_OPTIONS"] = "기타 설정"
L["PET"] = "소환수"
L["PRIORITY_DESC"] = "같은 키를 여러 행동에 지정할 수 있습니다. 키를 누르면 Debind가 순서대로 훑어서 조건이 맞는 첫 번째 것을 실행합니다 -- 언제나 하나만 실행됩니다.|n|n중요도를 가장 먼저 비교하므로, 중요도가 높으면 아래 것들을 모두 이깁니다. 중요도가 같은 행동끼리는 이 순서로 정해집니다:|n|n1. 마우스 올림 -- 개체창에 마우스를 올렸을 때만 실행되는 행동을 먼저 봅니다.|n2. 조건 -- 조건이 있는 행동을 조건 없는 행동보다 먼저 봅니다.|n3. 탭 -- 더 좁은 탭을 먼저 봅니다. 지금 캐릭터와 전문화에서 시작해 공유까지 내려갑니다.|n4. 순서 -- 위가 모두 같으면, 그 키에 먼저 지정한 행동을 먼저 봅니다. 행동을 옮길 수 있는 단계도 여기뿐입니다."
-- 끝의 이유절에 주어를 세웠다("불러와지지 않았습니다" -> "Debind는 ...만 불러옵니다").
-- 근거는 enUS 쪽 주석에.
L["PRIORITY_SHARED_WARNING"] = "이 행동은 공유 범위에 있어서 중요도도 공유됩니다. 이 계정의 모든 캐릭터에서, 이 행동이 지정된 모든 키의 순서가 함께 바뀝니다. 다른 캐릭터에서 무슨 일이 일어나는지는 여기서 보여줄 수 없습니다 -- Debind는 지금 접속한 캐릭터의 지정만 불러옵니다."
L["OVERVIEW"] = "개요"
-- 근거는 enUS 쪽 주석에.
L["OVERVIEW_DESC"] = "이 캐릭터의 지정 전부를 걸려 있는 키별로 묶어서 보여줍니다. 한 키 안에서는 Debind가 훑는 순서대로 늘어놓습니다.|n|n비활성 전문화의 행동도 같이 나옵니다. 그 전문화가 활성화됐다면 섰을 자리에 서고, 옆에 그렇게 적힙니다 - 활성화하기 전까지는 어떤 키에도 안 걸립니다. 오른쪽에서 다른 탭을 열어도 이 목록은 바뀌지 않습니다.|n|n키가 없는 행동은 맨 끝에 모입니다. 문자열로 받아온 것은 같이 온 묶음 그대로 서고, 나머지는 이름순 한 덩어리입니다. 아직 받아들이지 않은 것도 목록에는 있지만, 받아들이기 전까지는 어떤 키에도 안 걸립니다."
-- 순서 이동 버튼. 근거는 enUS 쪽 주석에.
L["ORDER_ACCEPT"] = "받기"
L["ORDER_ACCEPT_DESC"] = "이것만 내 것으로 받습니다. 이 키는 바로 동작하고, 같이 온 나머지는 꺼진 채로 남습니다."
L["ORDER_MOVE_UP"] = "먼저 실행"
L["ORDER_MOVE_UP_DESC"] = "이 행동을 이 키에서 한 칸 앞으로 옮깁니다. 다른 것은 바뀌지 않습니다."
L["ORDER_MOVE_DOWN"] = "나중에 실행"
L["ORDER_MOVE_DOWN_DESC"] = "이 행동을 이 키에서 한 칸 뒤로 옮깁니다. 다른 것은 바뀌지 않습니다."
L["ORDER_BLOCKED_ALREADY_FIRST"] = "이 행동은 이 키에서 이미 가장 먼저 실행됩니다."
L["ORDER_BLOCKED_ALREADY_LAST"] = "이 행동은 이 키에서 이미 가장 나중에 실행됩니다."
-- 아래 넷은 위의 ALREADY_* 둘과 틀이 다르다. 막혔다는 것, 누구와 누구인지, 무엇이 순서를
-- 정하고 있는지를 한 문장에 담는다. 근거는 enUS 쪽 주석에.
L["ORDER_BLOCKED_CONDITIONAL"] = "옆 행동을 앞지를 수 없습니다 -- 둘 중 하나에만 조건이 있고, 그것을 이 키에서의 순서보다 먼저 비교합니다."
L["ORDER_BLOCKED_HOVER"] = "옆 행동을 앞지를 수 없습니다 -- 둘 중 하나만 개체창에 마우스를 올렸을 때 실행되고, 그것을 이 키에서의 순서보다 먼저 비교합니다."
L["ORDER_BLOCKED_LAYER"] = "옆 행동을 앞지를 수 없습니다 -- 둘은 범위가 다르고, 범위를 이 키에서의 순서보다 먼저 비교합니다."
L["ORDER_BLOCKED_PRIORITY"] = "옆 행동을 앞지를 수 없습니다 -- 둘은 중요도가 다르고, 중요도를 가장 먼저 비교합니다."
L["ORDER_BLOCKED_IMPORTED"] = "이 행동은 아직 이 키의 순서에 없습니다. 문자열로 받아온 것이라, 받아들이기 전까지는 어떤 키에도 걸리지 않습니다."
L["ORDER_BLOCKED_SPEC"] = "옆 행동을 앞지를 수 없습니다 -- 둘은 전문화가 다르고, 한 번에 한 전문화만 활성화되므로 둘 사이에는 정할 순서가 없습니다."
L["ORDER_WHY_PRIORITY"] = "중요도: %s"
-- 정렬은 hover가 설정됐는지만 본다. 근거는 enUS 쪽 주석에.
L["ORDER_WHY_HOVER"] = "개체창 규칙"
L["ORDER_WHY_CONDITIONAL"] = "조건 있음"
L["ORDER_WHY_LAYER"] = "%1$s > %2$s"
-- "직접 정한 순서"라고 쓰면 안 된다. 자리는 키를 걸 때 자동으로 받는 번호라 사용자가 고른
-- 적이 없다. 근거는 enUS 쪽 주석에.
L["ORDER_WHY_SEQ"] = "이 키에서의 순서"
L["PRIORITY"] = "중요도"
L["PRIORITY1"] = "매우 높음"
L["PRIORITY2"] = "높음"
-- 다섯 중 가운데라 자리로 기본값이 읽힌다. 근거는 enUS 쪽 주석에.
L["PRIORITY3"] = "보통"
L["PRIORITY4"] = "낮음"
L["PRIORITY5"] = "매우 낮음"
L["REACTION_ALL"] = "전체"
L["REACTION_HARM"] = "적"
L["REACTION_HELP"] = "아군"
L["REACTION_OTHER"] = "기타"
-- ORDER_BLOCKED_LAYER("둘은 범위가 다릅니다.")와 같은 낱말을 쓴다.
L["SCOPE"] = "범위"
L["SELECTED_TARGET_UNIT_EMPTY"] = "지정된 대상 |cnDISABLED_FONT_COLOR:(없음)|r"
L["SELECTED_TARGET_UNIT"] = "지정된 대상 |cnLIGHTBLUE_FONT_COLOR:(%s)|r"
L["SHARED_BINDINGS"] = "공유"
L["SPECIAL_CONDITIONS"] = "특수 조건"
L["SPECIAL_UNIT_SET_MESSAGE"] = "|cnHIGHLIGHT_FONT_COLOR:%1$s|r - %2$s(으)로 지정"
L["SPECIAL_UNIT_UNSET_MESSAGE_TOO_MANY"] = "|cnHIGHLIGHT_FONT_COLOR:%s|r - |cnDISABLED_FONT_COLOR:해제됨 (개체가 둘 이상 감지됨)|r"
L["SPECIAL_UNIT_UNSET_MESSAGE"] = "|cnHIGHLIGHT_FONT_COLOR:%s|r - |cnDISABLED_FONT_COLOR:해제됨|r"
L["SPECIAL_UNITS"] = "특수 개체"
-- 근거는 enUS 쪽 주석에.
L["SPELL_PICKER_ADD_TO"] = "추가할 곳..."
-- "왼쪽 클릭하면 / 오른쪽 클릭하면"은 LINE_TOOLTIP_INSTRUCTION_MESSAGE1/2의 말이다.
L["SPELL_PICKER_LEFT_CLICK_TO_ADD"] = "왼쪽 클릭하면 |cnHIGHLIGHT_FONT_COLOR:%s|r에 추가됩니다."
L["SPELL_PICKER_EMPTY"] = "여기에는 아무것도 없습니다."
L["SPELL_PICKER_GROUP_ACCOUNT_MACROS"] = "계정 매크로"
L["SPELL_PICKER_GROUP_CHARACTER_MACROS"] = "캐릭터 매크로"
L["SPELL_PICKER_GROUP_FAVORITES"] = "즐겨찾기"
L["SPELL_PICKER_GROUP_OTHERS"] = "나머지 전부"
-- "layer"가 아니라 탭이라고 쓴다. 근거는 enUS 쪽 주석에.
L["SPELL_PICKER_MENU_DESC"] = "이미 가지고 있는 것을 둘러봅니다 -- 주문, 매크로, 탈것, 장난감, 그리고 게임 자체의 단축키 명령. 창은 계속 열려 있고, 클릭할 때마다 지금 열어 둔 탭에 추가됩니다."
L["SPELL_PICKER_NEW_MACROTEXT"] = "새 사용자 지정 매크로"
L["SPELL_PICKER_NO_MATCH"] = "검색과 맞는 것이 없습니다."
L["SPELL_PICKER_ONLY_FAVORITES"] = "즐겨찾기만"
L["SPELL_PICKER_RIGHT_CLICK_TO_ADD"] = "오른쪽 클릭하면 다른 탭에 추가할 수 있습니다."
L["SPELL_PICKER_SHOW_OFFSPEC"] = "비활성 전문화"
L["SPELL_PICKER_TAB_COMMAND"] = "명령"
L["SPELL_PICKER_TAB_MACRO"] = "매크로"
L["SPELL_PICKER_TAB_MOUNT"] = "탈것"
L["SPELL_PICKER_TAB_SPECIAL"] = "특수"
L["SPELL_PICKER_TAB_SPELL"] = "주문"
L["SPELL_PICKER_TAB_TOY"] = "장난감"
-- 창 제목이자 그 창을 여는 [+] 버튼의 툴팁 제목이다. 근거는 enUS 쪽 주석에.
L["SPELL_PICKER_TITLE"] = "행동 추가"
L["STATE_CHANGED_MESSAGE_OFF"] = "|cnRED_FONT_COLOR:꺼짐|r"
L["STATE_CHANGED_MESSAGE_ON"] = "|cnGREEN_FONT_COLOR:켜짐|r"
L["STATE_CHANGED_MESSAGE"] = "|cnLIGHTBLUE_FONT_COLOR:%1$s|r 상태가 %2$s(으)로 바뀌었습니다."
L["STATE_DRIVER_UPDATE_THROTTLE"] = "상태 드라이버 갱신 주기"
L["STATE_DRIVER_UPDATE_THROTTLE_DESC"] = "블리자드 상태 드라이버가 갱신되는 시간 간격입니다. 마우스오버와 관련된 것처럼 일부 상태는 곧바로 갱신되지 않을 수 있습니다. 이 값을 바꾸면 그런 상태의 갱신 빈도를 조절할 수 있습니다. 값이 낮을수록 자주 갱신됩니다 (|cnHIGHLIGHT_FONT_COLOR:0|r은 간격 없음).|n|n걱정하지 않아도 됩니다. 이 값은 영구히 저장되지 않고, 애드온을 비활성화하면 기본값으로 돌아갑니다.|n|n블리자드 기본값은 |cnHIGHLIGHT_FONT_COLOR:0.2|r초입니다."
L["STATE_DRIVER_UPDATE_THROTTLE_WARNING"] = "이 값을 바꾸면 성능 문제가 생길 수 있습니다."
-- 아래 탭 둘의 툴팁 설명 줄. 근거는 enUS 쪽 주석에.
L["TAB_DESC_SHARED"] = "계정 내 모든 캐릭터가 사용합니다."
L["TAB_DESC_CHARACTER"] = "이 캐릭터만 사용합니다. 조건과 중요도가 같다면 여기 있는 키가 공유의 같은 키보다 우선합니다."
L["TARGET_UNIT_DESC"] = "그 개체를 대상으로 잡지 않고 그 개체에게 행동을 사용합니다 -- 마우스 올림 조건이 걸려 있어도 마찬가지입니다."
L["TARGET_UNIT"] = "대상"
L["TYPE_COMMAND"] = "단축키 명령"
L["TYPE_FLYOUT"] = "플라이아웃"
L["TYPE_FOCUS_DESC"] = "이 개체를 주시 대상으로 지정합니다. 역할 기반 개체와 함께 쓰면 개체창에서 먼저 찾을 필요 없이, 키 하나로 지금 방어를 맡고 있는 사람을 주시 대상으로 삼습니다."
L["TYPE_FOCUS"] = "주시 대상 설정"
L["TYPE_ITEM"] = "아이템"
L["TYPE_MACRO"] = "매크로"
L["TYPE_MACROTEXT_DESC"] = "이 애드온 안에 사는 매크로를 만들어서, 와우의 매크로 칸은 그대로 비워 둡니다. 와우 매크로 목록에 있는 매크로와 달리 특수 개체를 겨냥하고 사용자 지정 상태를 읽을 수 있습니다.|n|n예: |cnHIGHLIGHT_FONT_COLOR:/cast [@tank,exists] 회복|r"
L["TYPE_MACROTEXT"] = "사용자 지정 매크로"
L["TYPE_MOUNT"] = "탈것"
L["TYPE_PETACTION"] = "소환수 명령"
L["TYPE_SETCUSTOM_DESC"] = "마우스를 올린 개체창의 개체를 이 사용자 지정 대상으로 붙들어 둡니다. 사용자 지정 대상은 주시 대상과 같은 방식으로 개체를 붙들고 있습니다. 사용자 지정 매크로에서 |cnHIGHLIGHT_FONT_COLOR:@custom1|r이나 |cnHIGHLIGHT_FONT_COLOR:@custom2|r로 겨냥할 수도 있고, 어떤 행동에든 대상으로 넘길 수도 있습니다.|n|n플레이어, 소환수, 파티/공격대, 우두머리, 투기장 개체창 위에서 동작합니다."
L["TYPE_SETCUSTOM"] = "사용자 지정 대상 지정"
L["TYPE_SETCUSTOM1"] = "사용자 지정 대상 1 지정"
L["TYPE_SETCUSTOM2"] = "사용자 지정 대상 2 지정"
L["TYPE_SETSTATE_DESC"] = "사용자 지정 상태를 켜거나 끕니다. 사용자 지정 상태는 다른 행동이 조건으로 삼는 내가 만든 스위치라서, 켜져 있을 때와 꺼져 있을 때 키 하나가 서로 다른 일을 하게 됩니다.|n|n와우가 단축키 변경을 막는 |cnHIGHLIGHT_FONT_COLOR:전투 중|r에도 전환됩니다."
L["TYPE_SETSTATE_OFF_NUM"] = "사용자 지정 상태 %d 끄기"
L["TYPE_SETSTATE_ON_NUM"] = "사용자 지정 상태 %d 켜기"
L["TYPE_SETSTATE_TOGGLE_NUM"] = "사용자 지정 상태 %d 전환"
L["TYPE_SETSTATE"] = "사용자 지정 상태 지정"
L["TYPE_SPELL"] = "주문"
L["TYPE_TARGET_DESC"] = "이 개체를 대상으로 선택합니다. 와우 자체의 대상 지정 단축키보다 목록이 넓습니다 -- |cnHIGHLIGHT_FONT_COLOR:방어 전담|r, |cnHIGHLIGHT_FONT_COLOR:치유 전담|r 같은 역할 기반 개체와 사용자 지정 대상까지 있습니다."
L["TYPE_TARGET"] = "대상 선택"
L["TYPE_TOGGLEMENU_DESC"] = "이 개체의 우클릭 메뉴를 엽니다 -- 개체창을 오른쪽 클릭했을 때 나오는 그 메뉴로, 초대·거래·대상 표시기 같은 것이 들어 있습니다. 개체창이 눈앞에 없는 개체에게도 닿습니다."
L["TYPE_TOGGLEMENU"] = "개체 우클릭 메뉴 열기"
L["TYPE_UNUSED_DESC"] = "고른 상황에서는 키를 와우에 돌려줍니다. 그러면 그 키는 와우 단축키 설정대로 동작하고, 와우에 지정된 것이 없으면 아무 일도 하지 않습니다."
L["TYPE_UNUSED"] = "와우 기본 단축키 사용"
L["TYPE_WORLDMARKER_DESC"] = "커서가 가리키는 바닥에 이 위치 표시기를 놓고, 이미 놓여 있으면 거둡니다. 와우 자체의 표시기라서, 직접 놓을 수 있는 것만 이 키로도 놓입니다."
L["TYPE_WORLDMARKER"] = "위치 표시기"
L["UNABLE_TO_REGISTER_UNIT_FRAME_IN_COMBAT"] = "전투 중이라 일부 개체창을 등록하지 못했습니다. 전투가 끝나면 등록됩니다."
L["UNBIND"] = "키 설정 해제"
L["UNIT_CUSTOM1"] = "사용자 지정 대상 1"
L["UNIT_CUSTOM2"] = "사용자 지정 대상 2"
L["UNIT_DISABLE"] = "비활성화"
L["UNIT_FOCUS"] = "주시 대상"
L["UNIT_HEALER"] = "치유 전담"
L["UNIT_HOVER_DESC"] = "마우스를 올린 개체창의 개체"
L["UNIT_HOVER"] = "개체창"
L["UNIT_MAINASSIST"] = "지원공격 전담"
-- 클라이언트는 역할 방어 전담(TANK)과 임명된 방어 전담(MAIN_TANK)을 둘 다 "방어 전담"이라
-- 부른다. 한 메뉴에 나란히 서는 자리라 그대로 쓰면 둘을 고를 수가 없어서, 임명된 쪽에만
-- "주요"를 붙인다(SET_MAIN_TANK = "방어 전담으로 임명"에서 온 말).
L["UNIT_MAINTANK"] = "주요 방어 전담"
L["UNIT_MOUSEOVER"] = "마우스오버"
L["UNIT_NONE_DESC"] = "선택하면 이미 선택된 대상이 있어도 새 대상을 고를 수 있습니다. 자신에게 자동 시전도 무시합니다."
L["UNIT_NONE"] = "대상 없음"
L["UNIT_PET"] = "소환수"
L["UNIT_PLAYER"] = "플레이어"
-- 하나보다 많으면 풀린다(SPECIAL_UNIT_UNSET_MESSAGE_TOO_MANY). 근거는 enUS 쪽 주석에.
L["UNIT_ROLE_DESC"] = "방어 전담, 치유 전담, 주요 방어 전담, 지원공격 전담은 파티나 공격대에서 그 역할을 맡은 사람이 정확히 한 명일 때만 동작합니다."
L["UNIT_TANK"] = "방어 전담"
L["UNIT_TARGET"] = "대상"
L["UNITFRAME_OPTIONS"] = "개체창 설정"
L["UNITFRAME_TRIGGER_ON_MOUSE_DOWN_DESC"] = "개체창에서 마우스 버튼을 뗄 때가 아니라 누를 때 행동이 발동하게 합니다. 블리자드 기본값은 뗄 때입니다."
L["UNITFRAME_TRIGGER_ON_MOUSE_DOWN"] = "클릭 시전에 마우스 누를 때 사용"
L["UNNAMED_ACTION"] = "(이름 없음)"
-- 한 줄로 끝낸다. 근거는 enUS 쪽 주석에.
L["WARNING_MESSAGE_CLIQUE_DETECTED"] = "Clique를 쓰고 있어서 여기 걸어둔 개체창 지정이 동작하지 않습니다."
-- 창을 덮는 판. 근거는 enUS 쪽 주석에.
L["MIGRATION_DIALOG_HEADER"] = "Debind"
L["MIGRATION_DIALOG_TITLE"] = "설정은 그대로 있습니다 - Debind가 닿지 못할 뿐입니다."
L["MIGRATION_DIALOG_BODY"] = "혹시 모르고 계셨다면: 이 애드온은 3.0 전까지 |cnHIGHLIGHT_FONT_COLOR:Debounce|r였습니다. 같은 애드온, 같은 설정입니다. 3.1에서는 폴더 이름까지 바꾸는데, 와우가 설정 파일을 두는 곳이 바로 그 폴더입니다. 그래서 이제 예전 파일을 읽을 수 있는 것은 함께 들어 있는 |cnHIGHLIGHT_FONT_COLOR:Debind Migration|r뿐이고, 지금 그것이 꺼져 있습니다.|n|n|cnGREEN_FONT_COLOR:어떤 경우에도 켜는 쪽이 맞습니다.|r 애드온이라 하기도 뭣한 것입니다 - 코드도 없고, 도는 것도 없고, 느려질 것도 없습니다. Debind가 캐릭터마다 한 번씩 열어서 옛 파일을 읽고, 모든 캐릭터가 지나가고 나면 다시는 불러오지 않습니다. 드는 값은 애드온 목록의 한 줄뿐입니다.|n|n답을 하기 전까지 Debind는 열리지 않습니다. 이 창을 닫으면 다음에 접속할 때 다시 묻습니다."
L["MIGRATION_DIALOG_ENABLE"] = "켜고 다시 불러오기"
-- 거절 둘의 **범위를 글자가 진다.** 근거는 enUS 쪽 주석에.
L["MIGRATION_DIALOG_DECLINE_CHARACTER"] = "이 캐릭터는 새로 시작"
L["MIGRATION_DIALOG_DECLINE_ACCOUNT"] = "모든 캐릭터를 새로 시작"
-- 툴팁이 버는 것은 **버튼 글자에 못 넣는 것**이다. 근거는 enUS 쪽 주석에.
L["MIGRATION_DIALOG_TITLE_MISSING"] = "예전 설정을 들고 있는 애드온이 설치되어 있지 않습니다."
L["MIGRATION_DIALOG_BODY_MISSING"] = "|cnHIGHLIGHT_FONT_COLOR:Debind Migration|r은 Debind와 함께 들어 있고, 3.0과 그 이전이 저장한 설정을 들고 있습니다. AddOns 폴더에 없는 것으로 보아 지웠거나 설치가 끝까지 되지 않았습니다.|n|nDebind를 다시 받으면 되돌아오고, 그동안에도 예전 설정은 디스크에 그대로 있습니다 - 잃은 것은 없습니다.|n|n이 창을 닫고 다시 설치하면 됩니다. 다음에 접속할 때 다시 묻습니다.|n|n그 설정 없이 새로 시작하실 생각이라면 아래에서 답해 주십시오."
L["MIGRATION_DIALOG_TITLE_CHARACTER_ONLY"] = "이 캐릭터만의 지정이 아직 넘어오지 않았습니다."
L["MIGRATION_DIALOG_BODY_CHARACTER_ONLY"] = "공유 지정은 이미 여기 있습니다 - 다른 캐릭터로 접속했을 때 넘어왔고, 그래서 키 대부분이 동작하는 것입니다.|n|n아직 없는 것은 |cnHIGHLIGHT_FONT_COLOR:이 캐릭터에만|r 만들어 둔 것들입니다. 이 캐릭터의 레이어와 사용자 지정 대상이 그렇습니다. 그것들은 별도 파일에 있고, 그 파일을 읽을 수 있는 것은 함께 들어 있는 |cnHIGHLIGHT_FONT_COLOR:Debind Migration|r뿐인데 지금 꺼져 있습니다.|n|n|cnGREEN_FONT_COLOR:여기서도 켜는 쪽이 맞습니다.|r 이 캐릭터에 따로 만든 지정이 없었다면 아무 일도 일어나지 않고 그것으로 끝입니다. 있었다면 되돌려받습니다. 어느 쪽이든 더 묻지 않습니다.|n|n답을 하기 전까지 Debind는 열리지 않습니다. 이 창을 닫으면 다음에 접속할 때 다시 묻습니다."
L["MIGRATION_DIALOG_ENABLE_TOOLTIP"] = "모든 캐릭터에 대해 |cnHIGHLIGHT_FONT_COLOR:Debind Migration|r을 켜고 인터페이스를 다시 불러옵니다.|n|n이 캐릭터의 설정은 다시 불러오기가 끝나는 즉시 돌아옵니다. 다른 캐릭터는 다음에 그 캐릭터로 접속할 때까지 예전 자리에 그대로 있다가, 각자 첫 접속에서 제 몫을 가져옵니다. 그 밖에 하실 일은 없습니다."
L["MIGRATION_DIALOG_DECLINE_CHARACTER_TOOLTIP"] = "이 캐릭터는 지정 없이 시작하고, 다시는 묻지 않습니다.|n|n다른 캐릭터는 그대로입니다 - 그쪽에는 여전히 예전 설정을 권합니다.|n|n|cnRED_FONT_COLOR:애드온 안에서는 되돌릴 수 없습니다.|r 어느 쪽을 고르든 예전 파일은 디스크에 그대로 둡니다."
L["MIGRATION_DIALOG_DECLINE_ACCOUNT_TOOLTIP"] = "|cnHIGHLIGHT_FONT_COLOR:이 계정의 모든 캐릭터|r에게 Debind가 예전 설정을 더 이상 권하지 않습니다. 아직 접속하지 않은 캐릭터와 앞으로 만들 캐릭터까지 해당됩니다.|n|n|cnRED_FONT_COLOR:애드온 안에서는 되돌릴 수 없습니다.|r 어느 쪽을 고르든 예전 파일은 디스크에 그대로 둡니다."
L["WARNING_MESSAGE_LEGACY_ADDON_STILL_INSTALLED"] = "이 애드온의 예전 전체 사본이 아직 설치되어 있어서 Debind와 나란히 단축키를 지정하고 있습니다. 둘이 키를 두고 다투는 중입니다. Debind를 다시 설치하거나 업데이트하면 그 폴더가 작은 |cnHIGHLIGHT_FONT_COLOR:Debind Migration|r으로 바뀝니다. 폴더를 그냥 지우지는 마십시오 - 업데이트 뒤 아직 접속하지 않은 캐릭터의 설정이 그 안에 남아 있습니다."

-- The window's own tabs. The reasoning is in enUS.
-- 근거는 enUS 쪽 주석에.
L["APPROVE_IMPORT"] = "내 것으로 받기"
-- The overview's import strip. The reasoning is in enUS.
-- 클라이언트가 이 상태를 부르는 말이 "대기 중"이다(`CLUB_FINDER_PENDING`,
-- `COMMUNITIES_MEMBER_LIST_PENDING_INVITE_HEADER` = "대기 중인 초대 (%d)"). 영어는 `|4`로 수를
-- 맞추는데 한국어는 수 일치가 없고, "개"가 이미 수량 단위라 "행동"을 안 붙인다
-- (`OVERVIEW_NO_KEY_COUNT`과 같은 이유).
L["IMPORT_PENDING"] = "대기 중 %d개"
L["IMPORT_PENDING_DESC"] = "문자열로 들어왔지만 아직 안 받은 것들입니다. 받기 전에는 아무 일도 안 하고, 원래 쓰시던 키도 그대로입니다. 개수는 지금 전문화가 아닌 곳에 내려앉은 것까지 포함한 전부입니다."
L["IMPORT_PENDING_INSTRUCTION"] = "클릭하면 전부에 할 수 있는 일이 나옵니다."
L["APPROVE_ALL_IMPORT"] = "모두 받기"
L["APPROVE_ALL_IMPORT_DESC"] = "아직 기다리고 있는 것을 어디에 있든 전부 받습니다 - 지금 전문화가 아닌 곳에 내려앉은 것까지 포함합니다. 받는 즉시 그 키들이 동작합니다."
L["REJECT_ALL_IMPORT"] = "모두 버리기"
L["REJECT_ALL_IMPORT_DESC"] = "아직 기다리고 있는 것을 어디에 있든 전부 지웁니다. 그 문자열은 가져오기 탭에 그대로 있으니 다시 가져올 수 있습니다."
L["BULK_SET_KEY_DESC"] = "고른 것 전부에 단축키 하나를 한 번에 지정합니다.|n|n고르지 않은 것과 키를 함께 쓰고 있었다면 그쪽은 원래 키에 남습니다. 양쪽 키 다 동작합니다, 함께 나가지 않을 뿐입니다."
L["BULK_BLOCKED_ALL_IMPORTED"] = "고른 것이 전부 아직 받아들이지 않은 것입니다. 받아들이는 것이 먼저입니다."
L["BULK_BLOCKED_SOME_IMPORTED"] = "고른 것 중에 아직 받아들이지 않은 것이 섞여 있습니다. 그 행을 선택에서 빼면 됩니다."
L["REJECT_IMPORT"] = "버리기"
L["REJECT_IMPORT_DESC"] = "이것만 지웁니다. 그 문자열은 가져오기 탭에 그대로 있으니 다시 가져올 수 있습니다."
L["REJECT_IMPORT_CONFIRM"] = "가져왔지만 아직 받아들이지 않은 행동 |cnHIGHLIGHT_FONT_COLOR:%d|r개를 버릴까요?|n|n그 문자열은 가져오기 탭에 그대로 있으니 다시 가져올 수 있습니다."
L["FILTER_ACTIVE_SPEC"] = "활성 전문화"
L["FILTER_INACTIVE_SPEC"] = "비활성 전문화"
-- **앞에 "키"를 붙여야 뜻이 닫힌다.** "지정 안 됨"만 두면 무엇이 안 됐다는 것인지 목록 안에서는
-- 안 서고, 그 말은 키 없는 덩어리 머리글이 이미 쓰고 있다(클라이언트 전역 NOT_BOUND).
L["FILTER_KEYED"] = "키 지정됨"
L["FILTER_UNKEYED"] = "키 지정 안 됨"
L["FILTER_PENDING"] = "아직 안 받음"
L["NO_ACTIONS_MATCH_FILTERS"] = "이 탭에는 조건에 맞는 것이 없습니다. 무엇이 꺼져 있는지는 왼쪽 열 위의 목록에 있습니다."
L["OVERVIEW_EMPTY_FILTERED"] = "조건에 맞는 것이 없습니다. 무엇이 꺼져 있는지는 이 열 위의 목록에 있습니다."
-- 부호와 숫자뿐이라 번역할 것이 없다. 그래도 키를 두는 것은, 언젠가 "외 %d개" 같은 말로 바뀔
-- 자리가 여기 하나여야 하기 때문이다.
L["OVERVIEW_KEY_HEADER_MORE"] = "+%d"
-- 영어는 `|4action:actions;`로 수를 맞추는데 한국어는 수 일치가 없다. "행동"도 안 붙인다 -
-- `개`가 이미 수량 단위라 총수로 읽히고, 머리글이 "지정 안 됨"이라고 이미 말했다.
L["OVERVIEW_NO_KEY_COUNT"] = "%d개"
-- 근거는 enUS 쪽 주석에.
L["IMPORT_COMMIT"] = "가져오기"
L["IMPORT_COMMIT_DESC"] = "무엇을 가져올지 먼저 묻고, 고른 것을 꺼둔 채로 지정에 넣습니다. 받아들이기 전까지는 어떤 키도 달라지지 않습니다."
L["IMPORT_NOTHING_PLACED"] = "아무것도 안 들어왔습니다 - 고르신 것 중에 이 캐릭터에 놓일 자리가 있는 것이 없습니다."
L["IMPORT_BRING_TITLE"] = "가져오기 — %s"
L["IMPORT_BRING_LINE_SHARED_GENERAL"] = "공유 / 일반"
L["IMPORT_BRING_LINE_SHARED_CLASS"] = "공유 / %s"
L["IMPORT_BRING_LINE_CHARACTER_GENERAL"] = "캐릭터 / 일반"
L["IMPORT_BRING_LINE_CHARACTER_SPEC"] = "캐릭터 / %s"
L["IMPORT_COMMITTED"] = "행동 %d개를 가져왔습니다. 받아들이기 전까지는 꺼져 있고, 받아들이는 줄이 창 맨 위에 생겼습니다."
L["IMPORT_COMMITTED_SKIPPED"] = "그중 %d개는 여기 놓일 자리가 없어 빠졌습니다 - 이 캐릭터에 없는 전문화이거나, 이 버전이 모르는 레이어입니다."
L["IMPORT_TITLE"] = "가져오기"
L["IMPORT_MENU_DESC"] = "붙여넣은 Debind 문자열을 필요할 때까지 그대로 들고 있습니다.|n|n가져오면 그 안의 행동이 꺼진 채로 들어오므로, 받아들이기 전까지는 무엇을 눌러도 달라지지 않습니다."
-- 근거는 enUS 쪽 주석에.
L["IMPORT_DRAWER_EMPTY"] = "아직 아무것도 없습니다.|n|n문자열을 붙여넣으면 어떻게 할지 정할 때까지 여기 그대로 있고, 정한 뒤에도 사라지지 않으니 나중에 다시 와서 이어서 해도 됩니다."
L["IMPORT_PASTE"] = "문자열 붙여넣기"
L["IMPORT_PASTE_TITLE"] = "Debind 문자열 붙여넣기"
L["IMPORT_PASTE_INPUT_LABEL"] = "가져올 문자열"
L["IMPORT_PASTE_INSTRUCTIONS"] = "이곳에 Debind 문자열을 붙여넣으세요"
L["IMPORT_PASTE_NAME"] = "이름 (선택)"
L["IMPORT_BATCH_COUNTS"] = "키 %1$d개, 행동 %2$d개"
L["IMPORT_BATCH_LINE"] = "%1$s  %2$s"
L["IMPORT_DELETE_CONFIRM"] = "|cnHIGHLIGHT_FONT_COLOR:%s|r을(를) 지우시겠습니까?|n|n사본이 이것뿐입니다. 이미 지정에 넣은 것은 그대로 남습니다."
L["IMPORT_FAILED_NOT_OURS"] = "Debind 문자열이 아닙니다."
L["IMPORT_FAILED_TOO_NEW"] = "더 새 버전의 Debind에서 만든 문자열입니다. 업데이트한 뒤 다시 시도하십시오."
L["IMPORT_FAILED_TOO_OLD"] = "지금 버전이 읽기에는 너무 오래된 Debind에서 만든 문자열입니다.|n|n여기서 할 수 있는 일은 없습니다. 그 문자열은 만들어진 버전에서는 그대로 쓸 수 있습니다."
L["IMPORT_FAILED_DAMAGED"] = "Debind 문자열이 맞지만 읽지 못했습니다. 복사하다 뒷부분이 잘렸을 가능성이 큽니다 - 다시 받아서 전체를 복사하십시오."
L["IMPORT_FAILED_LIBS_MISSING"] = "Debind Storage가 문자열을 읽는 라이브러리를 불러오지 못했습니다. Debind를 다시 받으면 됩니다."
L["PANEL_ADDON_MISSING"] = "이 탭은 |cnHIGHLIGHT_FONT_COLOR:Debind Storage|r가 들고 있는 것을 읽는데, 그것을 불러오지 못했습니다.|n|n꺼 두셨다면 애드온 목록에서 다시 켜 주세요. 목록에 아예 없다면 Debind를 다시 설치하면 함께 들어옵니다."
L["EXPORT_TITLE"] = "내보내기"
L["EXPORT_MENU_DESC"] = "설정의 일부든 전부든 문자열로 만들어 남에게 건네거나 백업으로 둘 수 있습니다.|n|n창을 열면 전부 선택되어 있고, 지금 하고 있지 않은 전문화도 목록에 들어 있습니다 - 담으려고 전문화를 바꿀 필요는 없습니다."
L["EXPORT_SELECT_ALL"] = "전체 선택"
L["EXPORT_SELECT_ALL_COUNT"] = "전체 선택 (%d)"
L["EXPORT_GENERATE"] = "문자열 만들기"
L["EXPORT_EMPTY"] = "아직 내보낼 것이 없습니다."
L["EXPORT_LAYER_HEADER"] = "%1$s (%2$d/%3$d)"
L["EXPORT_LAYER_COUNT"] = "액션 %d개"
L["EXPORT_FAILED_LIBS_MISSING"] = "문자열을 만드는 라이브러리가 없습니다. 설치가 끝까지 되지 않았다는 뜻이고, Debind를 다시 받으면 함께 들어옵니다."
L["EXPORT_COPY_TITLE"] = "이 문자열을 복사하세요 (Ctrl-C)"
