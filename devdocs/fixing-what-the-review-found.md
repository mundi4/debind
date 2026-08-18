# 브랜치 리뷰가 찾은 것 고치기 (2026-08-18 시작)

> 상태: **넷 남았다.** 아래 1~4가 열려 있고 나머지는 닫혀서 여기서 지웠다.
>
> 1번과 2번은 바로 착수할 수 있다. 3번은 고칠 것인지부터 재야 한다.

## 이 문서는 무엇인가

2026-08-18에 `origin/main...HEAD`(익스포트/임포트 트랙)를 리뷰해서 나온 것들 중 **아직 안 고친
것**을 담는다.

**전부 내가 코드 경로를 직접 따라가서 확인했다.** 리뷰를 돌린 것은 에이전트 셋이지만, 남의
보고를 그대로 옮겨 적으면 이 문서가 두 번째 진실이 된다. 확인 못 한 것은 그렇다고 적었다.

**닫힌 항목은 지운다.** 남는 것이 곧 미해결이다. **넷이 다 닫히면 이 문서는 그냥 지운다** -
버그 목록이라 `legacy/`로 옮길 것이 없다.

새 리뷰가 새 항목을 낳으면 여기 붙인다. **붙이기 전에 코드 경로를 따라갈 것.**

---

## 1. 손으로 만든 문자열이 마우스만 올려도 터진다

`ImportUI.lua`의 `DebindImportBatchRowMixin:OnEnter`, 그리고 같은 값이 닿는 `ClassName`.

`batch.class`가 검증 없이 `format`에 들어간다. `Import.lua`의 `AddBatch`가 `class = payload.class`로
그대로 싣고, `DecodeExportString`은 `payload.v`만 본다. 서술자의 `class`는 `KNOWN_CLASSES`로
거르는데(`Import.lua`가 "서술자의 class는 저장으로 바로 들어가는 키"라고 이유까지 적어놨다)
**`payload.class`는 아무 데서도 안 건다.**

`class`가 테이블이면 `LOCALIZED_CLASS_NAMES_MALE[테이블]`이 nil이라 원값이 `format`으로 가고,
와우의 Lua 5.1은 `%s`에 테이블을 받으면 던진다. 붙여넣기는 성공하고 서랍에 줄도 서는데, **그
줄에 마우스를 올리면 터진다.** 같은 값이 `ClassName`에도 가서 [가져오기]도 못 누른다. 그 배치는
열 수가 없다.

**고칠 자리는 `AddBatch`, 저장하기 전이다.** 읽는 쪽에 두면 늦는다. 배치는 `DebindStorageVars`,
곧 SavedVariables로 들어가서 **쓰레기 값이 디스크에 앉고 로그인마다 통째로 읽힌다.** 붙여넣을
때마다 하나씩 쌓인다. 문 하나가 읽는 자리 셋보다 낫기도 하다.

검사는 이미 있다. `ImportAddress`가 쓰는 `KNOWN_CLASSES`를 그대로 지나면 되고, 값이 아니면
`nil`로 떨군다. 이 필드는 원래 없어도 되는 필드다 - 툴팁이 `if (batch.class)`로 열고 `ClassName`이
`entry.class or batch.class`다.

**이미 저장된 배치는 안 고쳐진다.** 그러려면 누가 이미 그런 문자열을 붙여넣었어야 하고, 드로어에
스토어 버전이 없어서 마이그레이션을 붙이려면 그것부터 만들어야 한다. 라벨 한 줄 때문에 구조를
세울 값이 아니라고 본다. **그렇게 정하면 그 이유를 문 옆에 한 줄 적을 것.** 안 적으면 다음
사람이 "왜 여기만 막았나"를 다시 묻는다.

## 2. 화이트리스트를 지난 뒤에 손으로 쓰는 것들

> **문제 삼는 세 줄은 없어질 예정이다.** 매크로 본문을 안 싣기로 정해졌고
> (`building-export-import.md`의 "매크로는 이름만 나간다", 2026-08-18), 그러면 `BuildAction`의
> 매크로 갈래가 통째로 사라진다. **먼저 그것부터 하면 이 항목의 절반이 원인째 닫힌다.**
>
> 남는 절반은 아래 "문을 마지막에 하나만"이다. 그건 오늘 있는 세 줄이 아니라 **내일 누가 손으로
> 쓸 네 번째 줄**을 막는 것이라 매크로와 무관하게 값이 있다.

`Import.lua`의 `BuildAction`.

**루프는 제대로 닫혀 있다.** `FieldAllowed(k, v)`가 `ACTION_FIELDS`에서 기대 타입을 꺼내 값의
타입까지 본다. 문제는 **그 루프가 끝난 뒤에 손으로 쓰는 블록들이 그 문을 안 지난다**는 것이다.

```lua
action.value = source.macro.body;
action.name  = source.macro.name;
action.icon  = source.macro.icon;
```

셋 다 검사 없이 프로필에 앉고 SavedVariables까지 간다. `macro`는 형식의 낱말이라 `ACTION_FIELDS`에
없고, 그래서 루프가 건너뛴 것을 이 줄들이 손으로 열어서 꺼낸다.

`MacroMatches`도 같은 자리의 같은 사정이다. `luatype(snapshot) ~= "table" or not snapshot.name`으로
**있느냐만 보고** 바로 `GetMacroInfo(snapshot.name)`을 부른다. 이름이 테이블이면 거기서 던지고,
그 던짐은 **배치를 반쯤 넣다 말고** 일어난다.

**바로 위 `setstate` 블록에는 그 조심이 있다.** *"있느냐가 아니라 테이블이냐를 묻는다. 손으로
만든 `setstate = 5`는 여기서 던져서 커밋 전체를 끌고 내려간다"*고 적혀 있다. 한 함수 안에서 위
블록은 알고 썼고 아래 블록은 안 그랬다.

### 문을 마지막에 하나만

세 군데를 각각 고치면 **오늘 있는 세 줄만** 고친 것이다. 내일 네 번째 줄을 손으로 쓰면 구멍이
다시 난다. 사람이 규칙을 기억해야 하는 모양이라 단단하지 않다.

순서를 뒤집는다. 결정들이 **믿을 수 없는 테이블**에 쓰고, 문은 맨 마지막에 한 번만 돈다.

```lua
local function BuildAction(source)
    local fields = CopyTable(source);

    -- 결정들은 전부 여기서. 아직 믿을 수 없다.
    if (luatype(source.setstate) == "table") then ... fields.value = ... end

    -- 문은 하나, 맨 마지막.
    local action = {};
    for k, v in pairs(fields) do
        if (luatype(k) == "string" and FieldAllowed(k, v)) then
            action[k] = luatype(v) == "table" and CopyTable(v) or v;
        end
    end
    return action;
end
```

불변식이 **"`action`에 쓰는 것은 저 루프뿐"**이 된다. 그 함수에서 `action[`을 grep 하면 한 줄이다.
새 규칙을 얹는 사람은 `fields`에 쓰게 되고 그건 여전히 문을 지난다. **비켜갈 방법이 구조적으로
없다.**

"거부하면 어떻게 되나"도 물음이 아니게 된다. **답이 루프의 답과 같다.** 그 필드만 빠지고 액션은
남는다. 통째로 버리는 쪽이 아닌 이유는 이 리포의 규칙이 "깨진 것도 보내고 읽는 쪽이 빨간 걸 보고
지운다"이기 때문이다. 조용히 사라지면 보낸 사람과 받는 사람이 다른 개수를 본다.

그리고 `macro`와 `setstate`는 `ACTION_FIELDS`에 없어서 문이 알아서 떨군다. 지금 "이 둘은 형식의
낱말이라 여기서 멈춘다"고 주석으로 지키는 것을 표가 대신한다.

### 문이 못 잡는 것

**문은 타입을 보지 뜻을 안 본다.** `setstate` 갈래가 커스텀 상태 결정으로 없어지고 매크로 갈래가
위 결정으로 없어지면 남는 것이 없지만, 규칙으로 적어둔다. 타입이 맞고 뜻이 틀린 값은 화이트리스트가
아니라 그 값을 만드는 자리에서 막아야 한다.

## 3. 검색 한 글자마다 키보드 목록을 여러 번 짓는다

`DebindUI.lua`의 `NarrowedVisibleActions`가 `CollectVisibleActions`를 거쳐 `BuildKeyboardElements`를
부른다. 그게 **키마다** `CollectActionsForKey`를 부르고, 그건 다시 열한 레이어를 훑으면서 걸린
액션마다 `MakeRow`를 짓는다. `MakeRow` 하나가 `GetBindingInfoForAction`(바인딩을 통째로 다시
쓴다)과 `GetBindingIssue`와 `IsUnreachableAction`을 부른다.

`NarrowedVisibleActions`를 부르는 자리가 셋이고(`PruneSelectionToBinFilter`, `Refresh`,
`UpdateActionCounts`) `RefreshKeyboard`가 자기 몫으로 한 번 더 짓는다. 검색창의 `OnTextChanged`
한 번이 그 넷을 다 지난다. 필터 설정과 초기화도 같은 길이다.

이전 형태는 액션당 `strfind` 하나였다.

> 정확히 몇 번인지는 끝까지 안 세었다. 호출 자리가 셋이고 `RefreshKeyboard`가 따로 짓는다는
> 것까지 확인했다.

### 어떻게 고칠 것인가

**한 번의 갱신 안에서 `visible` 집합을 한 번만 짓는다.**

같은 입력에 대해 같은 답이 나오는데 네 번 짓는 것이 문제다. 그러니 캐시가 아니라 **한 갱신의
수명**을 갖는 값이어야 한다. 캐시는 언제 낡는지를 새로 관리해야 하고, 이 목록은 프로필이 바뀔
때마다 낡는다.

제안하는 모양은 셋 중 하나다. 첫째를 민다.

1. **갱신 진입점이 한 번 짓고 인자로 내린다.** `Refresh`/`Update`가 시작할 때 한 번 짓고,
   `BuildSortedElements`와 `UpdateActionCounts`와 `RefreshKeyboard`에 넘긴다. 수명이 호출
   스택으로 드러나서 무효화 규칙이 아예 없다. 대신 인자가 몇 군데 늘고, 지금 저 넷이 서로를
   부르는 순서를 한 번 정리해야 한다.
2. **한 프레임짜리 메모.** `NarrowedVisibleActions`가 결과와 함께 세대 번호를 들고 있다가 같은
   갱신 안이면 그대로 돌려준다. 인자는 안 늘지만 "같은 갱신인가"를 판정할 값이 필요하고, 그게
   곧 무효화 규칙이라 1번이 없애는 것을 도로 만든다.
3. **`BuildKeyboardElements` 자체를 싸게 만든다.** `MakeRow`가 바인딩을 다시 짓는 것이 진짜
   비용이라 거기를 손보는 길인데, `GetBindingInfoForAction`의 dirty 검사가 `if (true)`로
   우회돼 있는 것과 얽힌다(`sharing-one-action-tooltip.md`의 "여기서 안 고치는 것"). **범위가
   다른 일이다.**

1번으로 가되, **먼저 잴 것.** 지금 "느리다"는 코드를 읽고 센 것이지 화면에서 본 것이 아니다.
프로필이 작으면 넷을 지나도 티가 안 날 수 있고, 그러면 이 항목은 고칠 것이 아니라 지울 것이다.
`/debtest`에 키를 여럿 세워두고 검색창에 한 글자씩 쳐보는 것이 재는 방법이다.

## 4. ESC가 메인 창을 닫고 공유 다이얼로그를 남긴다

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
방법을 받았다. 고칠 자리는 그 사다리이고, `InitDialog`의 `UISpecialFrames` 등록은 그 창들이 이
윈도우 없이 서 있을 때를 위한 것이라 남는다.

---

## 무엇부터

내 제안이고 그뿐이다.

1. **4번과 1번.** 사용자가 평범하게 쓰다 바로 만난다. 4번은 ESC 한 번에 엉뚱한 창이 닫히는
   것이고, 1번은 남이 준 문자열 하나로 그 배치를 영영 못 열게 된다.
2. **2번.** 임포트가 만들어낼 수 있는 모양이고, **복사 상자를 안 막기로 한 결정이 기대는 곳이
   여기다**(`0-DECISION-LOG.md` 2026-08-18). 나가는 쪽을 안 지키기로 했으면 들어오는 쪽이 아무
   문자열에나 안전해야 한다.
3. **3번.** 재보고 나서 정한다.

## 닫힌 것

지운 항목은 아래가 전부다. 무엇을 왜 그렇게 했는지는 커밋 메시지에 있다.

- **복사 상자의 편집 막기** - 소유자가 막지 않기로 했다. 나가는 쪽 가드는 잘린 붙여넣기도 손으로
  만든 문자열도 못 막으므로, 어차피 들어오는 쪽이 져야 하는 몫을 안 덜어준다.
  `0-DECISION-LOG.md` 2026-08-18.
- **배지 붙은 행이 메뉴로는 움직이던 것** - `IsRowInOrder` 하나로 모았다. 헤드리스 스펙을 먼저
  빨갛게 만들어 보고 넣었다.
- **접힌 머리글의 요약이 안 돌아오던 것** - 감추는 대신 폭을 clamp 한다. 요약은 이제 접힘과
  무관하게 늘 선다.
- **익스포트 실패 폴백이 죽어 있던 것** - `L` 앞에 평범한 표를 뒀다.
- **주석 하나가 남의 함수 위에 서 있던 것** - `ApproveImportedActions`를 `MoveActions` 아래로
  옮기고 들여쓰기를 탭으로 맞췄다.
- **익스포트 탭이 닫힐 때 툴팁 최소 폭이 안 돌아오던 것** - 툴팁 작업이 만든 회귀라 그 자리에서
  고쳤다.

하나는 닫힌 게 아니라 **옮겼다.** 임포트가 만든 `SETSTATE`가 값 없이 돌아다니다
`band(nil, …)`으로 터지던 것. 그 자리를 파고 보니 커스텀 상태를 숫자로 접어둔 것이 원인이라,
`.zzz/custom-states-redesign.md` §9-1이 답할 물음이었다. 거기서 **타입을 셋으로 가르는 것으로
정해졌고**(2026-08-18) 그 변경이 이 버그를 원인째 없앤다.
