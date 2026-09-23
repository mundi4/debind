# 발동 순서에 조건 유무를 되돌린다

> 상태: **구현했다** (2026-09-23). 결정은 2026-09-23(소유자).
>
> `taking-conditions-out-of-the-order.md`(`ec0bf78`)를 되돌린다. 그 변경은 아직 배포되지 않았다
> (마지막 태그 `v3.5.2`, CHANGELOG `# 4.0` 미출시). 그래서 옮길 사용자 데이터가 없고, 사용자는
> 순서가 바뀐 적을 겪지 않는다. **4.0이 나간 뒤에는 이 기회가 없다.**

## 1. 결정과 이유

순서는 다시 priority, isConditional, layerRank, specRank, seq다. 조건 있는 액션이 조건 없는
액션보다 먼저 선다.

- **레이어 하나 안에서는 이 단계가 틀린 순서를 고를 수 없다.** 조건 없는 액션이 조건 있는 액션
  위에 서면 아래 것은 어떤 누름에도 안 닿는다. 이 단계가 막는 배치는 쓸모가 없는 배치다.
- **두 규칙이 갈리는 자리는 레이어를 넘는 한 곳이고, 거기서 풀 길이 비대칭이다.** 넓은 레이어의
  조건 있는 액션과 좁은 레이어의 조건 없는 액션이 한 키에 있을 때다.
  - 받쳐 주기(좁은 쪽이 폴백)를 조건 없는 규칙에서 풀려면 좁은 쪽에 넓은 쪽 조건의 부정을 걸어야
    한다. 부활 갈래의 부정은 NOT(우호 AND 죽음)이라 한 바인딩으로 안 적힌다
    (`adding-spec-resolved-actions.md` §6). 남는 길이 Importance뿐이다.
  - 덮어쓰기(좁은 쪽이 넓은 쪽을 없앰)를 이 규칙에서 풀려면 넓은 쪽 액션에 전문화 조건으로 그
    직업을 빼면 된다. 계정 레이어의 전문화 조건은 모든 직업을 고를 수 있다. 캐릭터 하나만 빼는
    조건은 없다.
- **넓은 레이어에 조건을 다는 까닭은 대개 "모든 캐릭터에서, 이 상황에만"이다.** 하늘비행,
  추가 행동 단추, 탈것, 특수 행동 단축바, 부활. 받쳐 주기가 더 흔한 쪽이다.
- **사용자에게 Importance를 바꾸라고 말하지 않는다**(소유자). 받쳐 주기가 흔한 쪽인 이상 조건
  없는 규칙은 그 말을 더 자주 하게 한다.

뺐던 이유는 설명할 것이 많다는 것이었다(소유자). `ordering.md`는 이미 "조건 없는 액션 아래는
안 닿는다"를 가르치고, 이 단계는 그 문장의 결론을 애드온이 대신 지켜 주는 것이다.

## 2. 조건 유무를 무엇으로 세나: 그대로 둔다

`MakeOrderRecord`의 `IsConditionalBinding(GetBindingInfoForAction(action))`을 안 바꾼다.

전문화 타입(해제, Raid Buff, 부활)에서 이 값은 "뒤 액션으로 넘어갈 수 있나"와 정확히 겹친다.

- "Spell to Cast"(`skipWhenUnusable`)를 켜면 `FillBinding`이 원본 조건 표에 `known = true`를
  넣는다. 부활의 원본이 `omitted`가 되어도 그 표는 남는다. 그래서 조건 있음이다.
- 끄면 원본이 `holdsOnly`로 키를 쥔다. 넘어갈 수 없으니 조건 없음이 맞다.

영혼석 폴백은 부활에 Spell to Cast를 켜는 것으로 선다. 켜야 폴백이 도는 것과 켜야 순서가 서는
것이 같은 스위치다.

**Normal Cast의 Skip은 조건으로 안 센다** (2026-09-23, 소유자). v3.5.2의 맨 개체창 조건 액션은
`MigrateLayer`에서 조건을 벗고 쌍둥이 전용 액션이 되므로 조건 없음으로 선다. 그래서 둘이 달라진다.

- **목록에서 그려지는 자리.** 조건 있는 액션 아래로 내려간다. 발동은 안 바뀐다. 쌍둥이 전용이라
  hover층에서 나가고, 층이 원본들보다 앞이다.
- **옛날에 죽어 있던 액션이 살아난다.** hover층 안에서 맨 개체창 액션 뒤에 있던 조건 있는 개체창
  액션은 3.5.2에서 한 번도 안 돌았다. 이제 그 앞에 서서 제 조건에서 나간다.

세면 둘 다 막히지만, 사용자에게 설명할 예외가 하나 는다. 그 값을 안 치르기로 했다.
`orderupgrade_spec`은 층마다, 옛날에 돌던 액션끼리만 옛 순서를 잰다.

## 3. 같이 풀어야 하는 것: 무시된 스위치

옛 문서 §3-5가 "닿기 전에 사라진다"고 한 자리가 **되살아난다.** 무시 모드는 4.0에 처음 나가고,
무시된 스위치는 바인딩 조건 표에 안 담긴다(`Misc.lua`, `IsSwitchIgnored`). 조건이 그 스위치 하나뿐인
공유 레이어 액션은 무시한 캐릭터에서 조건 없음, 아닌 캐릭터에서 조건 있음이 되고,
`RenumberKeyGroup`이 그 판정을 공유 레이어의 `seq`에 굽는다.

**순서 판정은 무시를 안 본다**(소유자, 2026-09-23). 사용자 눈에는 조건이 있는 액션이고,
`SWITCH_ANSWER_IGNORE_DESC`도 스위치가 켜졌든 꺼졌든 통과한다고 말한다. 조건이 없어진다고 하지
않는다. 그 라벨이 조건을 지운다는 뜻으로 읽힌다면 라벨을 고칠 일이다. 전문화 조건이 선례다.
지금 전문화에서는 늘 참인데도 바인딩 조건 표에 `specs`가 남아 조건 있음으로 선다.

그래서 `MakeOrderRecord`는 저장된 액션 조건에 스위치 이름이 있는지를 따로 보고, 있으면 조건
있음이다. 조건부 마크(`IsConditionalAction`)는 이 결정의 범위 밖이라 지금대로 둔다.

헤드리스 케이스: 조건이 스위치 하나뿐인 액션을 그 스위치를 무시로 두고 레코드를 만들면
`isConditional`이 참이다. 판정을 되돌리고 빨개지는 것을 본 뒤에 넘긴다.

## 4. 걷는 것

코드:

| 자리 | 무엇 |
|---|---|
| `Ordering.lua` | `CompareActionOrder`가 조건 단계를 다시 든다. `CompareActionOrderWithConditions`, `IsLegacyOrderOn`, `KeyGroupOrderMoved`를 지운다. `GetDecidingOrderAxis`의 `CONDITIONAL`에서 옵션 게이트를 뗀다. 머리주석의 "Two steps have gone"과 레코드 필드 설명 |
| `Misc.lua` | `IsConditionalBinding`, `MakeOrderRecord` 머리주석(기본 순서가 이것을 읽는다). §3의 판정 |
| `Profile.lua` | `MigrateDB`의 `orderChangedFrom`, `HasCharContent`의 `orderMovedSeen`, `ShouldWarnOrderMoved`, `AcknowledgeOrderMoved`. `RenumberKeyGroup` 머리주석의 밴드. `MigrateLayer`의 `dbver <= 6` 재번호는 **안 건드린다**(개체창 축 때문에 필요하다). 그 안 주석 중 조건 단계가 빠진 것을 이유로 든 줄만 본다 |
| `DebindUI.lua` | `_orderMovedGroups`, `BuildKeyboardElements`의 훑기와 `elementData.orderMoved`, `DebindKeyHeaderMixin:Init`의 `orderMoved` 갈래, `GroupIssueMarkTooltip`의 넘김, 개요 버튼 함수, `StaticPopupDialogs["DEBIND_ORDER_MOVED"]`, 필터 `marked`/`unmarked` |
| `DebindUI.xml` | `OrderChanged` 버튼 |
| `ActionTooltip.lua` | `AddGroupIssuesToTooltip`의 `orderMoved` 인자 |
| `SettingsTab.lua` | `LEGACY_ORDER` 체크박스 |
| `ActionMenuModel.lua` | `ec0bf78`이 고친 `OnActionsChanged`와 `TableFor` 게이트 주석을 되돌린다 |
| `Options` | `legacyOrder`. 배포 전이라 `CleanUpDB`에 걷는 줄을 안 둔다. 소유자 계정의 값은 손으로 지운다 |

로케일(enUS, koKR, ruRU): `LEGACY_ORDER`, `LEGACY_ORDER_DESC`, `ORDER_MOVED_*` 넷, `FILTER_MARKED`,
`FILTER_UNMARKED`를 지운다. `IMPORTANCE_DESC`에 조건 항목을 되살리고, "an action added to the key
goes last"는 조건 단계 아래에서만 참이므로 그 자리에 맞게 다시 쓴다. "unless conditions or
Importance say otherwise" 다섯 줄(`LAYER_DESC_SHARED_CLASS`, `LAYER_DESC_SHARED_SPEC`,
`LAYER_DESC_CHARACTER_GENERAL`, `LAYER_DESC_CHARACTER_SPEC`, `TAB_DESC_CHARACTER`)을 되살린다.
`TYPE_BLOCK_DESC`에 붙인 Run Sooner 문장을 다시 본다(조건 있는 Block은 조건 없는 액션 위에 저절로
서지만, 다른 조건 있는 액션과는 `seq`다). `ORDER_BLOCKED_CONDITIONAL`과 그 위 주석(옵션을 켠
사람만 본다)을 다시 쓴다. 레이어 설명 줄 위의 주석과 `ORDER_BLOCKED_*` 위의 주석에서
`ec0bf78`이 바꾼 사다리 서술. 문구는 `writing-user-facing-text.md`를 보고 쓴다.

문서:

| 자리 | 무엇 |
|---|---|
| `CHANGELOG.md` `# 4.0` | 순서 변경 두 문단(19, 21행 근처)을 지운다. "Replace an Action"의 "place in the run order"는 그대로 참이다 |
| `docs/ingamehelp/enUS/changelog.md` | 43, 45행. 개체창 단계가 빠진 것만 남긴다 |
| `docs/ingamehelp/enUS/ordering.md` | §6-1이 따로 든다 |
| `README.md` | `ec0bf78`이 바꾼 순서 설명 |
| `which-action-a-key-runs.md` | §2, 211행 근처의 "조건 유무 물음도 없어졌다", §8 표와 507, 525행 근처의 "옛 순서" 서술. §S 표의 기대값이 바뀌는 행은 그 헤드리스 케이스와 같이 고친다 |
| `showing-the-changelog-on-login.md` | 20행의 *Run Order Changed* 언급 |
| `adding-spec-resolved-actions.md` | 346행 "되돌릴지가 따로 열렸다"를 이 문서로 닫는다 |
| `taking-conditions-out-of-the-order.md` | 상태 머리에 이 문서가 되돌렸다고 적는다. 본문은 legacy 기록이라 둔다 |

## 5. 테스트와 테스트 주석

**틀린 전제를 든 주석을 남기지 않는다**(소유자, 2026-09-23). 아래는 `ec0bf78` 뒤로 조건 단계가
없다는 것을 이유나 전제로 든 자리 전부다. 구현 뒤 같은 grep으로 다시 훑는다(§6).

| 자리 | 무엇 |
|---|---|
| `tests/ordering_spec.lua` | 머리(8, 15행), 1절 "조건 유무는 기본 순서를 안 가른다"와 "옛 순서 옵션" 케이스는 기본 비교자에 대한 단계 테스트 하나로 되돌린다. 2절 무차별 대조는 옵션 없이 옛 통짜 비교자와 **기본값에서** 같아야 한다. 2-2 `KeyGroupOrderMoved` 절 전부 지운다. 522~534행의 막힘 케이스는 옵션 없이 `CONDITIONAL`로 막히는 것으로 |
| `tests/migration_spec.lua` | 1226행 뒤 "dbver 7 ... old conditional step" 다섯 케이스. 그 재번호의 조건 갈래는 이제 결과를 못 바꾼다(새 비교자가 같은 단계를 든다). 무엇을 먹여도 통과하는 케이스라 지운다. 1018~1079행 개체창 케이스의 "둘 다 조건부로 동률" 같은 이유절은 다시 읽고 참인지 본다 |
| `tests/orderupgrade_spec.lua` | 머리주석 "neither the unit frame step nor the conditional one". 새 비교자는 조건 단계를 든다. 한 레이어 코퍼스라 판정은 그대로 선다 |
| `tests/keygroup_spec.lua` | 209~233행. "조건부 도착분도 무조건인 기존 액션을 못 앞지른다"(옛 §3-4)는 **거꾸로 된다.** 케이스를 뒤집어 조건부 도착분이 앞서는 것을 잰다 |
| `tests/keymap_spec.lua` | 217행 "Having conditions does not move a record"와 그 케이스 |
| `tests/renumber_spec.lua` | 10행 머리. 이 파일이 Importance로 가르는 이유가 조건 단계의 부재였다 |
| `tests/eval_spec.lua` | 1181행 "Having conditions stopped being an ordering step" |
| `tests/emit_fixture.lua` | 189~191행. 픽스처 배치를 `ec0bf78` 전 모양으로 되돌릴지 보고, `tests/emit-golden.txt`와 `tests/emit-shipped-golden.txt`를 다시 낸다 |
| `tests/normalize_spec.lua` | 74~75행 "기본 발동 순서는 안 읽는다" |
| `tests/specid_spec.lua` | 323행. 이미 조건 단계를 전제로 한 문장이라 참이 되지만 `ec0bf78`이 고친 설정이 있는지 본다 |
| `tests/hovertwin_spec.lua` | 382~397행 단언은 그대로. 이유 주석만 본다 |
| `DebindDev/DebindTest.lua` | 1475행과 2765행 주석. `PlantImportanceLockedPair`는 그대로 쓸 수 있다. `CONDITIONAL`로 막히는 화살표 케이스가 없어졌으니 `ec0bf78` 전의 조건 쌍 케이스를 되살린다 |

## 6. 끝났다고 말하기 전에

다음 낱말로 코드, 테스트, 로케일, `docs/`, 이 문서를 뺀 `devdocs/`를 다시 훑어 0건이어야 한다.
`legacyOrder`, `IsLegacyOrderOn`, `KeyGroupOrderMoved`, `orderMoved`, `orderChangedFrom`,
`ORDER_MOVED`, `LEGACY_ORDER`, `FILTER_MARKED`, `CompareActionOrderWithConditions`. 그리고
`taking-conditions-out-of-the-order`를 인용한 자리는 남은 것마다 그 인용이 아직 참인지 읽는다.

`npm run check`.

### 6-1. 마지막: `ordering.md`

코드와 로케일이 다 선 뒤에 한다(소유자). 페이지가 말하는 규칙이 화면과 같아야 하기 때문이다.
**`help-pages` 스킬을 먼저 불러 그 절차를 따른다.**

- 목록에 조건 항목을 되살린다. 셋이 넷이 되므로 "Three things put them in that order"와 각
  항목의 서로 가리키는 말을 같이 본다. Importance 항목이 머리말에서 마지막 수단임을 말하는 것은
  그대로 둔다.
- "Putting a condition on an action does not move it."과 *Use the old run order* 인용문을 지운다.
- 목록 뒤 "An action with no conditions is tried on every press..." 문단은 조건 단계가 있으면 한
  레이어 안에서는 저절로 지켜지는 말이 된다. 레이어를 넘는 경우에 무엇을 말해야 하는지로 다시
  쓴다.
- 주석 블록의 "Conditions came out of the axis"와 "The one-time move on upgrade"를 지우고, 남는
  주석이 지금 규칙에 참인지 읽는다.
- `Locales/Help/enUS.lua`는 `npm run help`가 낸다. 손으로 안 고친다.

## 7. 커버리지

- **헤드리스:** 비교자의 단계, `GetDecidingOrderAxis`와 비교자가 같은 말을 하는 것, 레이어 넘는
  받쳐 주기 배치(넓은 레이어 조건 있음이 좁은 레이어 조건 없음 앞), Spell to Cast를 켠 부활이
  조건 있음으로 세이는 것, 무시된 스위치가 판정을 안 바꾸는 것, v3.5.2 대조.
- **킷:** `CONDITIONAL`로 잠긴 화살표와 그 툴팁.
- **안 재는 것:** 걷은 UI(버튼, 팝업, 필터, 설정 줄)의 부재.
