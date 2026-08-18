# 브랜치 리뷰가 찾은 것 고치기 (2026-08-18 시작)

> 상태: **아무것도 안 고쳤다.** 아래 아홉 개가 전부 열려 있다. 하나(익스포트 탭이 닫힐 때 툴팁
> 최소 폭이 안 돌아오던 것)는 툴팁 작업이 만든 회귀라 그 자리에서 고쳤고, 여기 없다.
>
> **순서는 정해져 있지 않다.** 아래 "무엇부터"가 내 제안이고 그뿐이다.

## 이 문서는 무엇인가

2026-08-18에 `origin/main...HEAD`(익스포트/임포트 트랙, 커밋 135개)를 리뷰해서 나온 것들 중
**그 자리에서 안 고친 것**을 담는다. 고친 것은 여기 없고 git이 갖고 있다.

**전부 내가 코드 경로를 직접 따라가서 확인했다.** 리뷰를 돌린 것은 에이전트 셋이지만, 남의
보고를 그대로 옮겨 적으면 이 문서가 두 번째 진실이 된다. 확인 못 한 것은 그렇다고 적었다.

**하나도 이번 툴팁 작업의 것이 아니다**(`sharing-one-action-tooltip.md`). 전부 익스포트/임포트
트랙에서 왔다.

---

## 1. 손으로 만든 문자열이 마우스만 올려도 터진다

`ImportUI.lua`의 `DebindImportBatchRowMixin:OnEnter`, 그리고 같은 값이 닿는 `ClassName`.

`batch.class`가 검증 없이 `format`에 들어간다. `Drawer.lua`의 `AddBatch`가 `class = payload.class`로
그대로 싣고, `DecodeExportString`은 `payload.v`만 본다. 서술자의 `class`는 `KNOWN_CLASSES`로 거르는데
(`Drawer.lua`가 "서술자의 class는 저장으로 바로 들어가는 키"라고 이유까지 적어놨다) **`payload.class`는
아무 데서도 안 건다.**

`class`가 테이블이면 `LOCALIZED_CLASS_NAMES_MALE[테이블]`이 nil이라 원값이 `format`으로 가고,
와우의 Lua 5.1은 `%s`에 테이블을 받으면 던진다. 붙여넣기는 성공하고 서랍에 줄도 서는데,
**그 줄에 마우스를 올리면 터진다.** 같은 값이 `ClassName`에도 가서 [가져오기]도 못 누른다.
그 배치는 열 수가 없다.

이게 실재하는 입력인 이유는 `Drawer.lua`가 이미 적어뒀다. 붙여넣은 문자열은 믿을 수 없는
입력이고 여기서는 아무것도 터지면 안 된다.

## 2. 복사 상자의 "아무도 못 친다" 가드가 절반만 덮는다

`ExportUI.lua`의 `DebindCopyFrameMixin:OnLoad`.

```lua
editBox:SetScript("OnChar", function() editBox:SetText(self.text or ""); end);
```

`OnChar`는 **찍히는 글자에만** 온다. 백스페이스와 Delete는 안 낸다. 이 믹스인이 거는 스크립트는
`OnChar`와 `OnEscapePressed` 둘뿐이고 `OnTextChanged`는 없다. 상자는 `InputScrollFrameTemplate`의
편집 가능한 여러 줄 상자다.

`ShowText`가 열면서 `SetFocus()`와 `HighlightText()`를 한다. **전체가 선택된 채로 뜬다.**
백스페이스 한 번이면 비고, 되돌리는 것이 없다. 그 상태로 Ctrl-A, Ctrl-C를 하면 빈 문자열을
복사한다. 받는 쪽은 `IMPORT_FAILED_NOT_OURS`나 `IMPORT_FAILED_DAMAGED`를 보고, **보낸 쪽은 뭐가
잘못됐는지 알 길이 없다.**

## 3. ESC가 메인 창을 닫고 공유 다이얼로그를 남긴다

`DebindUI.lua`의 `DebindDialogMixin:InitDialog`가 다이얼로그 이름을 `UISpecialFrames`에 넣는다.
그 표를 읽는 것은 `CloseSpecialWindows()` 하나이고, 그건 ESCAPE **바인딩**이 부른다.

그런데 `DebindFrame`은 `enableKeyboard`가 늘 켜져 있어서 `OnKeyDown`이 ESCAPE를 먼저 받는다.
`BlizzardOwnsEscape()`는 블리자드 패널과 스태틱 팝업 앞에서만 물러나는데 복사·붙여넣기·가져오기
창은 셋 다 아니고 셋 다 키보드를 안 켠다. 그래서 `SetPropagateKeyboardInput(false)`가 걸리고
`HandleEscape()`로 간다. **그 사다리에는 저 셋의 칸이 없다.** 아이콘 선택기와 주문 선택 창의
칸만 있고, 나머지는 `self:Hide()`로 떨어진다.

익스포트 탭에서 복사 창을 열고 ESC를 누르면 **메인 창이 사라지고 복사 창만 남는다.** 한 번 더
누르면 그때야 복사 창이 닫힌다.

**같은 파일이 이 사정을 이미 적어뒀다.** 주문 선택 창 자리에 "저쪽을 `UISpecialFrames`에 넣어도
닿지 않는 자리라 사다리 한 칸으로 넣었다"고 있다. 공유 다이얼로그 셋은 그 주석이 안 된다고 말한
방법을 받았다.

## 4. 임포트가 만든 `SETSTATE`가 값 없이 돌아다닌다

`Import.lua`의 `BuildAction`은 **일부러** 모르는 모드나 상태 이름에 `action.value = nil`을 준다.
"타입은 두고 값을 잃는다, 빨간 글씨가 이미 할 말이 있는 모양이다"가 그 자리의 근거다.

`Misc.lua`의 `GetSetCustomStateModeAndIndex`는 첫 줄이 `band(value, ...)`이고 가드가 없다.
`band(nil, x)`는 던진다.

부르는 데가 다섯이다. `DebindUI.lua`의 `NameAndIconForAction`, `Misc.lua`, `UpdateBindings.lua`
둘, `Export.lua`. **오버뷰가 그 행을 그리는 순간 첫 번째가 터지고**, 그 액션이 승인되고 나면
익스포트도 같이 죽는다.

고칠 자리는 `Misc.lua`의 그 함수다. 값이 없으면 무엇을 돌려줄지가 결정이고, 그건 이 문서가 아니라
고치는 사람이 정한다.

## 5. 매크로 스냅샷이 화이트리스트를 비켜간다

`Import.lua`의 `MacroMatches`가 `luatype(snapshot) ~= "table" or not snapshot.name`만 본다.
**있느냐만 보고 무엇이냐는 안 본다.** 바로 다음 줄이 `GetMacroInfo(snapshot.name)`이라 이름이
문자열이 아니면 거기서 던진다.

그리고 매칭이 실패했을 때의 갈래가 `source.macro`의 `body`/`name`/`icon`을 `FieldAllowed`를 안
거치고 액션에 옮긴다. 문자열이 아닌 값이 프로필에 앉고 SavedVariables까지 간다.

**이건 그 파일의 머리말이 양쪽 끝에서 닫았다고 말하는 바로 그 구멍이다.** 같은 파일의 `setstate`
쪽은 그 사정을 알고 굳혀놨다.

> 아래 갈래(`FieldAllowed`를 안 거치는 복사)는 코드를 눈으로 본 것이고, 어떤 값이 실제로 어디까지
> 가는지는 끝까지 안 따라갔다. 고칠 때 그 절반을 먼저 확인할 것.

## 6. 배지 붙은 행이 메뉴로는 움직인다

`Ordering.lua`의 `ComputeOrderSwap`.

대상 행의 가드가 `specRank`만 본다.

```lua
if ((rows[targetIndex].specRank or 0) ~= 0) then
    return nil, "SPEC";
end
```

바로 아래 이웃 건너뛰기는 `imported`와 `specRank`를 **둘 다** 본다. 그리고 그 위 주석은
"배지 붙은 행은 상대가 아니다"를 먼저 적어놓고 있다. **근거는 적혀 있는데 대상 쪽 가드에는
그 절반이 없다.**

`ApproveImportedActions`가 배지만 걷고 합성 키는 남기므로 한 그룹에 승인된 행과 배지 붙은 행이
같이 설 수 있다. 배지 붙은 행에서 우클릭하면 이동 항목이 켜지고, 눌리면 실제로 순서가 바뀐다.
**화살표 버튼은 같은 동작을 거부한다.** 켜는 조건과 실행하는 조건이 갈려 있다.

## 7. 접힌 머리글의 요약이 한 번 사라지면 안 돌아온다

`DebindUI.lua`의 `DebindKeyHeaderMixin:LayoutSummary`가 `if (not name:IsShown()) then return end`로
연다. 폭이 모자라면 `name:Hide()`, `count:Hide()`를 하고 끝난다.

다시 재는 통로는 `OnSizeChanged` 하나인데 그것도 `LayoutSummary`만 부르므로 저 가드에서 되돌아
나간다. 다시 켜는 것은 `UpdateSummary`뿐이고 그건 `Init`에서만 온다.

한 번 좁아졌던 프레임은 **풀에서 다시 나올 때까지 요약을 영영 잃는다.** 키 그룹을 접어두고 탭을
익스포트로 옮겼다 돌아오면(`SelectPanel`이 폭을 바꾼다) 머리글에 키만 남고 액션 이름과 `+N`이
없다.

## 8. 검색 한 글자마다 키보드 목록을 여러 번 짓는다

`DebindUI.lua`의 `NarrowedVisibleActions`가 `CollectVisibleActions`를 거쳐 `BuildKeyboardElements`를
부른다. 그게 **키마다** `CollectActionsForKey`를 부르고, 그건 다시 열한 레이어를 훑으면서 걸린
액션마다 `MakeRow`를 짓는다. `MakeRow` 하나가 `GetBindingInfoForAction`(바인딩을 통째로 다시
쓴다)과 `GetBindingIssue`와 `IsUnreachableAction`을 부른다.

검색창의 `OnTextChanged` 한 번에 `NarrowedVisibleActions`가 여러 번 불린다. 호출 자리는 셋이고
(`PruneSelectionToBinFilter`, `Refresh`, `UpdateActionCounts`) `RefreshKeyboard`가 자기 몫으로 한 번
더 짓는다. 필터 설정과 초기화도 같은 길을 간다.

이전 형태는 액션당 `strfind` 하나였다. 한 번의 `Refresh`/`Update` 안에서 `visible` 집합을 한 번만
짓고 돌려쓰면 접힌다.

> 정확히 몇 번인지는 끝까지 안 세었다. 호출 자리가 셋이고 `RefreshKeyboard`가 따로 짓는다는
> 것까지 확인했다.

## 9. 익스포트 실패 폴백이 도달 불가다

`ExportUI.lua`에 `LLL["EXPORT_FAILED_" .. tostring(reason)] or tostring(reason)`이 있다.

로케일 표는 `setmetatable({}, { __index = function(_, key) return key end })`라 **없는 키에 키
자체를 돌려준다.** 앞항이 언제나 참이므로 `or` 뒤는 못 간다.

오늘은 잠복이다. `EncodeExportPayload`가 내는 사유가 `LIBS_MISSING` 하나고 그건 문자열이 있다.
두 번째 사유가 문자열 없이 붙는 순간 사용자가 빨간 글씨로 `EXPORT_FAILED_SOMETHING`을 본다.

`ImportUI.lua`는 같은 자리를 제대로 한다. 폴백을 평범한 표 조회 안에 뒀다
(`REASON_TEXT[reason] or "IMPORT_FAILED_DAMAGED"`).

## 10. 주석 하나가 남의 함수 위에 서 있다

`DebindUI.lua`에서 `ApproveImportedActions`가 `MoveActions`의 문서 블록과 `MoveActions` 사이에
끼어 들어갔다. "옮긴 뒤에는 선택을 접는다. `MoveAction`이 액션 테이블을 복사해서 넣으므로…"가
`ApproveImportedActions` 바로 위에 있고, 거기서는 아무것도 설명하지 않는다.

같은 함수 본문만 탭 대신 스페이스로 들여쓰여 있다.

---

## 무엇부터

내 제안이고 그뿐이다.

1. **1번과 3번.** 사용자가 평범하게 쓰다 바로 만난다. 3번은 ESC 한 번에 엉뚱한 창이 닫히는
   것이고, 1번은 남이 준 문자열 하나로 그 배치를 영영 못 열게 된다.
2. **2번.** 조용히 망가진 문자열을 내보내고 **보낸 쪽이 모른다.** 이 트랙의 값이 문자열을
   주고받는 것인데 그 문자열이 조용히 깨진다.
3. **4번과 5번과 6번.** 임포트가 만들어낼 수 있는 모양들, 그리고 켜기와 실행이 갈린 자리.
4. **7번과 8번.** 화면과 반응 속도.
5. **9번과 10번.** 잠복과 정리.

## 닫는 법

**항목이 닫히면 이 문서에서 지운다.** 남는 것이 곧 미해결이다. 아홉이 다 닫히면 문서째
`devdocs/legacy/`로 간다.

새 리뷰가 새 항목을 낳으면 여기 붙인다. **붙이기 전에 코드 경로를 따라갈 것.** 확인 안 한
보고를 그대로 싣는 순간 이 목록은 다음 사람이 처음부터 다시 검증해야 하는 것이 된다.
