# 브랜치 리뷰가 찾은 것 고치기 (2026-08-18 시작)

> 상태: **다섯 남았다.** 아래 1~5가 열려 있고 나머지는 닫혀서 여기서 지웠다.
>
> 1번은 값의 모양을 정해야 시작할 수 있고, 4번은 고칠 것인지부터 재야 한다.

## 이 문서는 무엇인가

2026-08-18에 `origin/main...HEAD`(익스포트/임포트 트랙)를 리뷰해서 나온 것들 중 **아직 안 고친
것**을 담는다.

**전부 내가 코드 경로를 직접 따라가서 확인했다.** 리뷰를 돌린 것은 에이전트 셋이지만, 남의
보고를 그대로 옮겨 적으면 이 문서가 두 번째 진실이 된다. 확인 못 한 것은 그렇다고 적었다.

**닫힌 항목은 지운다.** 남는 것이 곧 미해결이다. **다섯이 다 닫히면 이 문서는 그냥 지운다** -
버그 목록이라 `legacy/`로 옮길 것이 없다.

새 리뷰가 새 항목을 낳으면 여기 붙인다. **붙이기 전에 코드 경로를 따라갈 것.**

---

## 1. 커스텀 상태를 숫자로 접는다

`SETSTATE` 액션의 `value`가 `모드플래그 + 인덱스`인 숫자다. 이걸 **문자열로 바꾼다.**

**전선 형식은 이미 문자열이다.** `{ mode = "on", state = "$state3" }`으로 나가고 들어온다. 즉
이 결정은 한 번 내려졌고 프로필만 혼자 접고 있다. 바꾸면 `Import`는 포장을, `Export`는 푸는
것을 그만둬서 양쪽 다 짧아진다.

바꿔야 하는 이유는 임포트 쪽에서 나왔다. 모르는 상태 이름이 오면 지금은 `action.value = nil`이
되는데, 숫자에는 이름을 실을 자리가 없어서 그렇다. 그리고 `GetSetCustomStateModeAndIndex`가
`band(value, ...)`로 열려서 **nil을 받으면 던진다.** 오버뷰가 그 행을 그리는 순간 터지고, 그
액션이 승인되고 나면 익스포트도 같이 죽는다.

문자열이면 모르는 이름은 그냥 실려 들어오고, 이슈 검사가 `CUSTOM_STATE_INDICES`와 견줘서
걸러낸다. 매크로 본문의 `[$오타]`에 `GetUndefinedCustomState`가 하는 것과 같은 일이고,
`BINDING_ISSUE_UNDEFINED_STATE`가 이미 있고 등급이 ERROR고 문자열이 `%s`로 이름을 받는다.
**새 이슈 코드도 새 문자열도 필요 없다.**

크기:

- **포장 둘** - `ActionCatalog.lua`(카탈로그 항목), `Import.lua`(전선 → 프로필)
- **푸는 것 하나** - `Misc.lua`의 `GetSetCustomStateModeAndIndex`. 부르는 데 다섯인데 **넷은 이미
  "풀렸냐 아니냐"로만 분기**한다
- **마이그레이션 하나** - `Profile.lua`에 `dbver <= 5` 단계, `DB_VERSION` 5 → 6

> **안 정한 것: 값의 모양.** 모드와 상태를 한 필드에 담아야 한다. `action.value`는 타입마다
> "무엇을 가리키는가" 하나를 드는 필드라 여기에만 필드를 더 달면 익스포트 표까지 번진다.
> `"on:$state3"` 꼴로 가되 구분자를 정해야 한다.
>
> 런타임이 이미 쓰는 `"$state3-on"`(`/click DebindStates $state3-on`)도 후보였는데 **기각했다.**
> 저장 값이 클릭 프로토콜과 같아지면 그 프로토콜을 건드릴 때 저장된 데이터가 같이 묶인다.
> 지금 이득은 `format` 한 줄이고 그 값에 못 미친다.

**저장 데이터를 바꾸므로 끝나면 `/debtest`가 필요하다.**

## 2. 손으로 만든 문자열이 마우스만 올려도 터진다

`ImportUI.lua`의 `DebindImportBatchRowMixin:OnEnter`, 그리고 같은 값이 닿는 `ClassName`.

`batch.class`가 검증 없이 `format`에 들어간다. `Drawer.lua`의 `AddBatch`가 `class = payload.class`로
그대로 싣고, `DecodeExportString`은 `payload.v`만 본다. 서술자의 `class`는 `KNOWN_CLASSES`로
거르는데(`Drawer.lua`가 "서술자의 class는 저장으로 바로 들어가는 키"라고 이유까지 적어놨다)
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

## 3. 화이트리스트를 지난 뒤에 손으로 쓰는 것들

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

그러니 고칠 모양은 세 군데 패치가 아니라 규칙 하나다. **루프가 끝난 뒤 `action`에 쓰는 것도
루프와 같은 문을 지난다.** `MacroMatches`의 타입 검사도 그 규칙의 결과로 따라온다.

곁가지 하나. 매칭이 **성공했을 때** `action.value = source.macro.name`을 쓰는데, `GetMacroInfo`는
슬롯 번호도 받는다. 보낸 쪽이 `name`에 숫자를 실었으면 매칭이 통과하고 **슬롯 번호가 그대로
값이 된다.** 바로 그 줄의 주석이 "슬롯 번호는 읽는 사람의 네 번째 매크로를 가리키므로 이름을
쓴다"고 말하는 그 상황이다.

## 4. 검색 한 글자마다 키보드 목록을 여러 번 짓는다

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

## 5. ESC가 메인 창을 닫고 공유 다이얼로그를 남긴다

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

1. **5번과 2번.** 사용자가 평범하게 쓰다 바로 만난다. 5번은 ESC 한 번에 엉뚱한 창이 닫히는
   것이고, 2번은 남이 준 문자열 하나로 그 배치를 영영 못 열게 된다.
2. **1번과 3번.** 둘 다 임포트가 만들어낼 수 있는 모양이고, **복사 상자를 안 막기로 한 결정이
   기대는 곳이 여기다**(`0-DECISION-LOG.md` 2026-08-18). 나가는 쪽을 안 지키기로 했으면 들어오는
   쪽이 아무 문자열에나 안전해야 한다.
3. **4번.** 재보고 나서 정한다.

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
