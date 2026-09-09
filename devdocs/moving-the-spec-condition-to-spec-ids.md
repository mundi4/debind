> 상태: 안이다. 아직 구현하지 않았다. 2026-09-09에 소유자와 정한 것을 적었고, 열린 물음은
> §8에 모아 두었다.

# 전문화 조건을 전문화 ID로 옮기기

`conditions.specs`가 지금은 1~5의 번호 집합이고 5비트 정수 하나로 저장된다
(`legacy/adding-a-spec-index-condition.md`). 그것을 **전문화 ID의 집합**으로 바꾼다.

## 1. 이걸로 직업 조건까지 끝난다

한 직업은 자기 전문화 ID들의 집합이다. 전사 줄을 켠다는 것은 전사의 전문화 ID를 전부 담는다는
뜻이고, 그러면 "전사일 때"라는 조건이 별도의 축 없이 표현된다. 직업 조건을 따로 만들 이유가
사라지는 것이 이 변경의 값이다.

덤으로 하나 더 있다. 지금 번호 체크박스 다섯은 전문화가 둘뿐인 직업에서 3번과 4번이 아무것도
안 가리키는 칸으로 남는데, 화면에서는 다른 번호와 구별되지 않고 체크도 된다. ID 목록이면 그
두 줄이 애초에 생기지 않는다.

## 2. 표현이 아니라 뜻이 바뀐다

번호를 고른 이유는 `legacy/adding-a-spec-index-condition.md` §2에 있다. **번호는 어디에 있어도
같은 뜻**이라는 것이었다. 계정 층 액션에 걸린 `1`은 어느 직업으로 접속해도 그 직업의 1번을
가리킨다.

ID는 그 이식성을 버린다. 250이 걸린 액션은 죽음의 기사가 아닌 캐릭터에서 영영 참이 되지 않는다.
**그 대신 직업을 얻는다.** 이 문서가 뒤집는 것이 그 결정이고, 뒤집는 근거는 §1이다.

**마이그레이션은 없다.** 전문화 조건 자체가 아직 배포되지 않았다. `v3.5.2`(2026-09-03) 뒤에
들어온 기능이라 어느 SavedVariables에도 이 필드가 앉아 있지 않다. 저장 모양을 그냥 바꾼다.
`dbver` 범프는 이미 7이 미배포로 열려 있다(`0-ROADMAP.md`).

## 3. 저장 모양

비트마스크는 버린다. ID는 5비트에 안 들어간다.

**키 있는 집합으로 둔다.** `conditions.specs = { [250] = true, [251] = true }`. 배열이 아닌
이유는 맞히는 자리가 `specs[currentSpecID]` 한 번의 조회로 끝나서다. 배열이면 매번 훑어야 하고,
그건 리빌드마다 바인딩 수만큼 도는 자리다. `conditions.units`가 이미 키 있는 테이블이라 모양의
선례도 그쪽에 있다.

`Constants.SPEC_ALL`과 `Constants.SpecIndexFlag`는 쓰는 곳이 없어지므로 지운다.
`Constants.MAX_SPEC_INDEX`는 남는다. 뜻이 "전문화 번호의 최댓값"에서 **"초기 전문화가 앉는
번호"**로 좁아지고, 주석이 그렇게 바뀐다(§4).

## 4. 초기 전문화

번호 5는 전문화가 넷인 직업에서만 마지막이 아니다. **전문화가 둘인 직업도 1, 2, 5를 갖고 3과
4가 없다**(2026-09-09, 소유자가 게임에서 확인). 그러니 한 직업의 전문화를 다 세는 것은
`1..GetNumSpecializationsForClassID(classID)`에 5번을 따로 붙이는 일이다.

**초기 전문화도 직업마다 다른 진짜 ID를 갖는다.** 드루이드가 1447이고 도적이 1453이다
(같은 날, 같은 경로로 확인). `reference/`만 보면 반대로 읽히니 주의할 것. `IsInitialSpec(index)`가
`index > GetNumSpecializations()`이고, 블리자드 코드에서 전문화를 도는 루프는 전부
`1, GetNumSpecializationsForClassID(classID)`로 끊는다. 그건 그 번호에 값이 없다는 뜻이 아니다.

**그 항목은 각 직업 하위에 하나씩 붙는다.** 바닥에 「None chosen」 한 줄로 몰면 그 줄은 열세
개 ID를 한꺼번에 켜고 끄는 스위치가 되어, 드루이드의 초기 전문화만 고르는 것을 표현할 방법이
없어진다. 라벨은 지금 쓰는 `NO_SPECIALIZATION`("None chosen")을 그대로 쓴다. 이름이 없는 것은
그대로이기 때문이다.

## 5. 메뉴

```
전문화
  Disable
  전사
    무기
    분노
    방어
    None chosen
  사제
    ...
```

`Disable` 줄은 지금 그대로다. `kit:Disable("CONDITION_SPEC", "specs")`가 `specs`를 nil로
되돌리는 라디오이고, 값 모양을 안 보고 nil만 쓰므로 이 변경에 안 걸린다.

직업 줄을 노드로 세우는 것은 `CreateUnitConditionSubmenu`가 이미 하는 방식이다
(`ActionMenuNodes.lua`). `Appender:Checkboxes`는 항목마다 `isSelected`/`setSelected`를 따로
받으므로, 비트 대신 집합을 읽는 체크박스가 킷을 안 고치고 들어간다(`MenuKit.lua`).

**직업 줄 자체가 체크박스인가가 열린 물음이다.** §8에 있다.

## 6. 굽는 쪽은 그대로다

전문화 조건은 매크로 조건식으로 나가지 않는다. 상태 드라이버도 솔버 컬럼도 스니펫도 없고,
비보안 쪽에서 `SpecConditionHolds`가 한 번 걸러서 끝난다. 그 근거는
`legacy/adding-a-spec-index-condition.md` §1에 있고 이 변경이 건드리지 않는다. **`Solver.lua`에
컬럼을 만들면 안 된다는 것도 그대로다.**

그래서 "구울 때 번호로 되돌린다"는 단계는 없다. 맞히는 값이 처음부터 지금 전문화의 ID다.

번호가 남는 자리는 하나뿐이다. 창이 **다른** 전문화의 순서를 그릴 때
`CollectActionsForKey(key, spec)`에 넘기는 번호이고, `SpecConditionHolds`의 둘째 인자가 그것을
받는다(`Profile.lua`의 `MakeRow`). 거기서 번호를 ID로 바꿔 받는다.
`C_SpecializationInfo.GetSpecializationInfo(index)`가 그 변환이고, `SpecSpells.lua`의
`CurrentSpecID`가 이미 같은 호출을 쓴다.

**층은 안 건드린다.** 전문화 층은 번호로 남는다. `Import.lua`의 `NUM_SPECS`도 층 주소를 막는
자리라 이 변경과 무관하다.

## 7. 손대는 자리

- `Debind/Constants.lua`
  - `SPEC_ALL`, `SpecIndexFlag` 삭제. `MAX_SPEC_INDEX`는 뜻이 좁아지고 주석이 바뀐다.
  - `CONDITION_FIELDS`의 `specs` 위에 붙은 "번호지 이름이 아니다" 주석은 거짓이 되므로
    새로 쓴다.
- `Debind/Misc.lua`
  - `SpecConditionHolds`: 마스크 대조가 집합 조회가 되고, 인자가 번호에서 ID로 바뀐다.
    빈 집합이 참이라는 규칙과 그 이유는 그대로 살린다.
  - 정규화(`NormalizeBinding` 안의 `SPEC_ALL` 접기)는 **없앤다.** ID에는 "전부"에 해당하는
    값이 없고, 한 직업을 다 켠 집합은 접어야 할 중복이 아니라 그 자체로 뜻이 있는 조건이다.
  - `GetBindingIssue`의 빈 집합 갈래(`BINDING_ISSUE_SPECS_NONE_SELECTED`)는 남는다.
    `specs == 0`이 "빈 집합"으로 바뀐다.
- `Debind/ActionMenuNodes.lua`: `SPEC` 노드를 §5의 모양으로 다시 쓴다.
- `Debind/ActionTooltip.lua`: 번호를 늘어놓던 자리가 이름을 늘어놓는다. `~= SPEC_ALL`로 건너뛰던
  줄은 접기가 없어지므로 같이 사라진다.
- `Debind/Profile.lua`: `MakeRow`의 `specExcluded`가 번호 대신 ID를 넘긴다.
- `Debind/Debind.lua`: `BuildKeyMap`의 거르는 자리. 호출은 그대로고 주변 주석이 번호를 말하는
  만큼만 고친다.
- `Debind/Locales/*.lua`
  - `CONDITION_SPEC_DESC`가 통째로 거짓이 된다. 번호가 직업마다 다른 것을 설명하는 문장인데
    이제 이름으로 고른다. enUS와 koKR 둘 다.
  - `CONDITION_SPECS`, `NO_SPECIALIZATION`, `BINDING_ERROR_SPECS_NONE_SELECTED`는 남는다.
  - 문구는 `writing-user-facing-text.md`를 먼저 읽고 쓴다.
- `DebindStorage/Export.lua`: `CONDITION_TYPES`의 `specs = "number"`가 `"table"`이 된다.
- `DebindStorage/Import.lua`: 머리의 "우리보다 전문화가 많은 직업" 주석은 층 이야기라 그대로다.
  `ConditionAllowed`는 §8을 볼 것.
- `tests/wow_shim.lua`: `GetSpecializationInfo`가 드루이드 넷의 ID를 답하고 있다. 여기에 초기
  전문화와 다른 직업 하나가 더 필요하다. `GetSpecializationInfoForClassID`도 없어서 새로 세운다.
- `tests/specindex_spec.lua`: 파일 전체가 `Flag(n)`으로 조건을 만든다. ID로 다시 쓴다.
  파일 이름도 더 이상 맞지 않는다.
- `tests/import_spec.lua`: `specs = 1 + 4`가 마스크다.

## 8. 열린 물음

**직업 줄 자체가 체크박스인가.** 직업 조건이 "하위 전부"라서, 전사 줄을 켜면 셋이 다 켜지고
하나를 끄면 전사 줄은 부분 상태가 된다. 그 부분 상태를 그릴 수 있는지가 관건이고, 못 그리면
직업 조건은 하위를 다 켠 모습으로만 보인다. 이 답에 따라 `Appender`에 무엇이 필요한지가 갈린다.

**들어온 집합의 안쪽을 거르는가.** `ConditionAllowed`는 이름과 최상위 타입만 본다.
`units`가 이미 `"table"`로 안을 안 보고 통과하므로 `specs`도 같아진다. 안 거르고 두는 쪽이
방어적으로 안전하기는 하다. 모르는 ID는 지금 전문화 ID와 절대 안 맞으니 조건을 **덜** 참으로
만들 뿐이고, 키바인딩 애드온이 틀릴 수 있는 나쁜 방향은 반대쪽이다. 다만 툴팁은 이름을 붙이려고
그 집합을 훑으므로, 숫자가 아닌 키가 거기까지 간다. 거르든 툴팁에서 막든 한쪽은 정해야 한다.

## 9. 커버리지

헤드리스가 덮는 것:

- 조건이 맞고 틀릴 때 키맵에 무엇이 남는가. 지금 `specindex_spec.lua`가 보는 것이고, ID로 다시
  쓰면 그대로 이어진다. 전문화 변경 뒤 리빌드까지 포함해서다.
- 빈 집합이 `BINDING_ISSUE_SPECS_NONE_SELECTED`를 내는 것.
- 공유 문자열에 실려 나갔다 들어오는 것. `import_spec.lua`가 보고, 이 변경 뒤에는 **다른 직업의
  ID가 실린 문자열**이 새 경우로 붙는다. 마스크 시절에는 만들 수 없던 경우다.
- `check:export-fields`가 두 목록의 어긋남을 잡는다. 타입이 바뀌는 것은 못 본다. 이름만 본다.

원리상 못 보는 것:

- 메뉴가 실제로 그려지는 모양. 직업 줄의 부분 상태, 열세 줄의 길이, 초기 전문화 줄의 자리.
  프레임을 안 세우는 헤드리스에서는 물어볼 대상이 없다.
- `GetSpecializationInfoForClassID`가 실제로 무엇을 답하는가. 셰임이 답하는 것은 우리가 적어
  넣은 값이다. 초기 전문화 ID가 직업마다 다르다는 것은 게임에서 읽어 확인했고(§4), 열세 직업
  전부를 확인한 것은 아니다.
