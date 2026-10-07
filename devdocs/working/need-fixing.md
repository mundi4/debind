# 고칠 것

> 상태: 미착수. 항목 1 하나.
>
> 쓴 세션: `debind-45` (세션 ID `69a358ab-115a-49d9-9681-65106e3c7003`).

다른 일을 하다 찾은 결함이다. 그 일의 범위가 아니라 여기 따로 둔다.

## 1. 유닛 조건을 접는 두 곳이 role과 frameTypes에서 갈린다

찾은 곳: ee05ce9의 리뷰(2026-10-08). 키 돌려주기 3-1절 작업 중이었다(`giving-keys-back-when-no-action-runs.md`).

### 무엇이 갈리나

유닛 조건은 두 곳에서 접힌다. 솔버 쪽은 `Units.lua`의 `BuildUnitStates`이고, 방출 쪽은 `UpdateBindings.lua`의
`mergeUnitConditions`다.

- `BuildUnitStates`는 role과 frameTypes를 `unitframe` 행에서만 읽는다(`narrowRole`, `narrowFrameTypes`).
  다른 유닛 행의 두 값은 무시한다.
- `mergeUnitConditions`는 유닛을 가리지 않는다. 같은 유닛에 떨어진 두 행의 frameTypes가 겹치지 않으면 `NEVER`를
  낸다. role도 겹치지 않으면 `NEVER`다. 다만 두 행 다 role을 하나 이상 골랐을 때만이다.
- group은 두 쪽 다 모든 유닛에서 읽으므로 갈리지 않는다.

### 재현 조건

- 한 액션의 유닛 조건 두 행이 `unitframe`이 아닌 같은 유닛에 떨어진다. 보기는 대상 없는 액션의 `"@"`(target으로
  풀린다)와 `target` 행이다.
- 두 행의 role이 겹치지 않는다. 보기는 `"@"`에 TANK, `target`에 HEALER다. frameTypes가 겹치지 않아도 같다.
- `"@"` 행의 role과 frameTypes는 메뉴로 넣을 수 있다. `"@"` 하위 메뉴는 액션이 무엇을 겨누든 그 둘을 내준다
  (`ActionMenuNodes.lua`의 `pointedFrame`). `target` 행에는 메뉴가 그 둘을 안 내준다. 그래서 두 행이 다 갖는 모양은
  손으로 고친 프로필이나, 그런 값을 담은 가져오기 문자열로만 들어온다.

### 무슨 일이 일어나나

- 솔버는 바인딩을 살려 둔다. `dead`도 아니고 opaque도 아니다. 그래서 이슈도 없다.
- 방출은 그 바인딩을 버린다. 접으면 `NEVER`이니 `PrepareKeyBindings`가 빼고 레코드가 안 나간다.
- 솔버는 이 바인딩을 덮개로 쓴다. 이 바인딩의 상자(target이 있는 상태)에 완전히 덮이는 아래 바인딩은 솔버가 지운다.
  그러면 둘 다 안 나가고, 그 상태의 누름에서 아무 액션도 안 돈다.
- 아래 바인딩이 완전히 덮이지 않으면 그것은 나가고, 누름에서 그것이 돈다. 위 바인딩은 레코드가 없다.
- 키에 다른 레코드가 없으면 키는 옵션(`giveBackWhenNoActionRuns`)대로 처리된다.
- 창은 위 액션에 아무것도 표시하지 않는다. 완전히 덮인 아래 액션의 행에는 "Never runs"(`BINDING_ERROR_UNREACHABLE`)가
  붙는다. 그 원인으로 읽히는 위 액션은 실제로 나가지 않는다.

누름에서 아무 액션도 안 도는 것은 3-1절 작업 전(6bbe915)에도 같았다. 그때는 `BuildKeyRecord`가 nil을 내고 레코드를
건너뛰었다. 키를 쥐는 쪽은 달랐다. 그때는 키를 끝 레코드만으로 묶어 우리 것으로 읽었고, 개체창 전용 마우스 버튼은 빈
목록을 등록했다(a31ab92 메시지).

### 같이 고칠 주석

`mergeUnitConditions` 위의 `NEVER IS UNREACHABLE` 주석은 `NEVER`로 가는 길을 셋만 적는다. 모두
`binding.unitStates`의 0 마스크다. 실제로는 role, frameTypes, group의 셋이 더 있다. 이 셋은 솔버의 다른 칸
(`unitRole`, `unitFrameTypes`, `unitGroups`)에 들어간다. 그리고 `unitframe` 밖의 role과 frameTypes는 그 칸에도
안 들어가서, "닿지 않는다"는 말이 그 경우에 틀렸다.

`EmitRecord`의 role 주석("The menu cannot make that shape")도 틀렸다. 위에 적은 대로 `"@"` 행에는 메뉴가 role을
넣는다.

### 고치는 길 (정하지 않았다)

- **접기에서 `unitframe` 밖의 role과 frameTypes를 무시한다.** 방출은 이미 role을 `unitframe`에만 내보낸다
  (`EmitRecord`). 그러니 접기도 같은 규칙을 따르면 세 곳이 맞는다. 대가는 손으로 넣은 그 값이 조용히 무시되는 것이다.
- **솔버가 모든 유닛에서 두 값을 읽는다.** 그러면 바인딩이 `dead`가 되고 이슈가 뜬다. 대가는 런타임이 재지 않는
  값(target의 role)을 솔버가 조건으로 다루는 것이다. 역할은 파티·공격대 개체창에서만 잰다.
- **읽을 때 그 값을 지운다.** ESC를 `CleanUpDB`와 `BringPayloadDataForward`에서 지우는 것과 같은 꼴이다. 데이터에서
  갈림의 원인이 사라진다. 대가는 저장 데이터를 고치는 길이 하나 더 생기는 것이다.

어느 쪽이든 고치기 전에 시험을 먼저 세운다. `loopoff_spec`의 "makes no record" 두 경우가 이 갈림을
`ResolvedUnitOf`를 바꿔서 흉내 낸다. 진짜 갈림(role 두 행)으로 같은 결과를 내는 경우를 세우면 고친 뒤의 기대를
거기에 걸 수 있다.
