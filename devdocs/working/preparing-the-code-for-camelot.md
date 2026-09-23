# 카멜롯을 받을 수 있게 코드 정리하기 (2026-09-24 시작)

> 상태: **계획이고, 아무것도 안 들어갔다** (2026-09-24). 프로브(`DebindCamelotProbe` 애드온)는 이
> 문서가 필요로 하는 값을 재도록 고쳐 두었다.
>
> 무엇을 왜 싣는지는 `shipping-on-the-camelot-client.md`가 들고, 이 문서는 그것을 받칠 코드 정리의
> 순서를 든다. 클라이언트 차이를 받는 층을 먼저 세우고, 쪼개기와 폴더 정리는 그 뒤에 순수한 이동으로
> 한다.

## 1. 목표와 지킬 것

**목표.** `loadstring` 게이트(`shipping-on-the-camelot-client.md` 3절)가 풀리는 날 카멜롯 판을 태그
하나로 낼 수 있는 상태.

**지킬 것: 정식 서비스에서 동작이 안 바뀐다.** 단계마다 `npm run check`가 초록이고,
`tools/snippet-golden.txt`와 emit 골든의 바이트가 그대로다. 바이트를 바꾸는 단계는 왜 바뀌는지를
그 단계가 적는다.

**클래식은 목표가 아니다.** 클라이언트 차이를 받는 층이 한 곳에 모이면 클래식은 그 층에 구현을
하나 더 넣는 일이 된다. 다만 클래식 쪽 인벤토리는 하지 않았고, 이 문서의 어떤 결정도 클래식을
근거로 삼지 않는다.

## 2. 갈래를 무엇으로 가르나

`shipping-on-the-camelot-client.md` 2절의 결론(파일 한 벌, 갈래가 아니라 능력을 묻는다)은 남는다. 그
결론을 받치던 근거 둘은 틀렸고, 아래가 바뀐 근거다.

**확인한 사실 셋.**

1. **한 패키지에 TOC가 여럿이면 Lua와 XML 안의 `@version-*@` 태그는 빌드를 멈춘다.**
   `BigWigsMods/packager`의 `release.sh`가 "Build type version keywords are not allowed in a
   multi-version build"를 찍고 `exit 1`한다(2026-09-24에 읽음). 그러니 파일 안에서 빌드 때 잘라내기는
   검사가 못 봐서가 아니라 **패키저가 받지 않아서** 선택지가 아니다.
2. **TOC의 파일 줄은 태그로 가를 수 있다.** 루트 `## Interface:`가 한 게임 타입의 번호만 들면
   패키저는 `enable-toc-creation`으로 만드는 갈래별 TOC마다 그 갈래의 `toc_filter version-*`를 건다.
   그러니 갈래별 파일은 TOC 한 벌로 된다. "TOC를 손으로 두 벌 든다"는 옛 근거는 틀렸다. 단,
   `Debind.xml` 같은 XML의 `<Script>` 줄은 1번에 걸리므로, 갈라지는 파일은 TOC에 직접 적혀야 한다.
3. **`WOW_PROJECT_ID`는 카멜롯에서도 1이다**(2026-09-23 프로브). 정식 서비스와 같은 값이라, 갈래
   상수를 만들고 싶어도 그것으로는 못 가른다.

**결정: 기본은 같은 파일 안에서 클라이언트가 가진 API로 고른다.** 헤드리스 shim은 세계를 바꿔 끼워
두 구현을 한 번의 실행에서 다 돌린다(4절). TOC로 가른 파일은 다른 클라이언트의 판에 아예 없으므로,
그 파일을 헤드리스에서 돌리려면 `tests/run.lua`의 손으로 든 파일 목록이 갈래를 알아야 한다.

**파일을 가르는 것은 한 클라이언트에서만 도는 구현이 파일 하나를 채울 때다.** 그때 TOC 줄 태그로
가르고, 그 전에 `tests/run.lua`의 목록을 TOC와 XML의 목록에 맞춰 보는 검사가 먼저 선다(5절). 지금
그런 파일은 없다.

## 3. 클라이언트 층

**새 폴더 `Debind/Client/`.** 클라이언트마다 뽑는 법이 다른 것만 여기서 부르고, 나머지 코드는 여기가
내는 모양 하나만 읽는다. 모든 API 호출을 감싸지 않는다. 두 클라이언트에서 같은 모양으로 답하는
호출은 지금 자리에 그대로 둔다. `Debind.xml`에서 `Constants.lua` 바로 뒤에 싣는다.

아래는 조사로 찾은 자리 전부다. 값만 다른 자리(전문화 번호, 전문화 수)는 층이 필요 없다.
`NUM_SPECS`가 1이 되는 것은 `shipping-on-the-camelot-client.md` 5절의 일이다.

### 3-1. 직업 목록: 지금 카멜롯에서 드루이드가 빠진다

`Misc.lua`의 `ClassSpecCatalog`가 `1..GetNumClasses()`를 돈다. 카멜롯은 `GetNumClasses()`가 9인데
인덱스 6과 10이 비고 드루이드가 11에 있다(2026-09-23 프로브). 그래서 드루이드가 목록에서 빠지고,
드루이드만 고른 전문화 조건은 "고른 것이 없다"는 이슈를 낸다.

블리자드도 같은 루프를 카멜롯에서 바꿨다. 정식 서비스의 `Blizzard_ClassMenu.lua`는
`1..GetNumClasses()`를 돌고, 카멜롯 쪽은 카멜롯에만 있는 `C_SpecializationInfo.GetAllClassIDs()`를
돈다.

**`Client.ClassIDs()`.** 직업 번호 목록을 낸다. `GetAllClassIDs`가 있으면 그것을 쓰고, 없으면
`GetClassInfo`를 인덱스로 돌아 답하는 것만 모은다. 정식 서비스에서는 인덱스가 빈틈없이 이어져
있으므로 지금과 같은 목록이 나온다.

### 3-2. 특성 트리: 뽑는 법이 다르고 조립할 모양은 하나다

`Talents.lua`의 `BuildMenu`는 트리를 **직업과 전문화 둘로** 나눈다. 첫 번째 트리 화폐를 직업 몫으로
보고 노드마다 비용의 화폐로 가른다. 영웅 트리는 `subTreeID`로 붙인다.

카멜롯의 특성 창은 트리를 **그룹으로** 나눈다. 노드가 `groupIDs`를 들고,
`C_Traits.GetGroupDisplayInfoByTreeID`가 그룹마다 이름, 아이콘, `orderIndex`, `skillLineID`를 준다.
둘 다 카멜롯에만 있다.

**잰 값 (2026-09-24, 69977, 드루이드 2레벨).** 트리 화폐는 하나(3820)이고 노드 51개가 전부 그것을
쓴다. 그러니 지금 `BuildMenu`는 카멜롯에서 모든 노드를 직업 쪽에 넣고 전문화 쪽을 비운다. 이름을 든
그룹은 셋이고 클래식의 특성 트리 셋 그대로다. Balance 16, Feral Combat 19, Restoration 16으로 합이
51이다. 노드는 그 밖에 이름 없는 그룹 수십 개에도 들지만, 구역은 이름을 든 그룹으로 나누면 된다.

**`Client.TalentSections(configID, treeID)`.** 구역 목록 `{ name, icon, nodeIDs }`와 영웅 트리 목록을
낸다. 정식 서비스에서는 지금 `BuildMenu`가 하는 가르기가 그대로 이리 옮겨 와 직업과 전문화 두 구역을
낸다. 카멜롯에서는 그룹마다 한 구역이고 영웅 트리는 빈 목록이다. `BuildMenu`는 구역 목록으로
메뉴를 짠다. 조건이 저장하는 것은 노드와 항목 번호뿐이라 저장 형식은 안 바뀐다.

### 3-3. 활성 특성 설정과 이중 전문화

카멜롯은 직업마다 전문화가 하나지만 **전문화 그룹이 둘**이고(이중 전문화), 그룹마다 특성 설정이
따로다. 특성 창은 `GetCombatConfigIDForSpecGroup(group)`로 설정을 얻는다.

우리는 세 자리에서 `C_ClassTalents.GetActiveConfigID()`를 부른다. `Talents.lua`와 `Spells.lua`의
`LiveAPI`, 그리고 `Events.lua`의 `TRAIT_CONFIG_UPDATED` 처리다. 그룹을 바꿀 때 이 값이 따라오는지,
어떤 이벤트가 오는지는 소스로 안 닿는다. 프로브의 spec groups 구역과 events 구역이 잰다.

2레벨까지는 그룹이 하나뿐이라(`GetNumSpecGroups` 1, 그룹 2의 설정 nil) 바꾸는 순간은 아직 못 쟀다.

- 따라오면 층이 필요 없다. 재빌드 트리거만 확인한다.
- 안 따라오면 **`Client.ActiveConfigID()`**가 카멜롯에서 `GetCombatConfigIDForSpecGroup(GetActiveSpecGroup())`를
  내고, 세 자리가 그것을 부른다.

어느 쪽이든 `Spells.lua`의 `EnsureWalked` 캐시는 전문화 인덱스로만 잡혀 있어서, 그룹을 바꿔도
무효화되지 않는다. 키에 그룹이 들어가야 한다.

**결정이 필요한 것 하나: 전문화 레이어를 카멜롯에서 무엇으로 볼까.** 카멜롯 사용자가 실제로 오가는
것은 전문화가 아니라 전문화 그룹이다(성기사가 신성과 징벌을 두 그룹에 둔다). 선택지는 둘이다.

- **그룹은 레이어에 안 들어온다.** `shipping-on-the-camelot-client.md` 5절대로 전문화 탭을 안 세우고,
  두 그룹이 같은 바인딩을 쓴다.
- **카멜롯에서는 전문화 레이어의 축이 그룹이다.** 저장소의 전문화 레이어는 인덱스 1부터 4로 잡혀
  있어 그룹 두 개가 형식 변경 없이 들어간다. 대신 전문화 조건(전문화 번호 집합)은 그룹을 못 가리므로,
  같은 "전문화"라는 이름 아래 탭과 조건이 서로 다른 것을 가리키게 된다.

5절 화면 작업 전에 정해야 한다. 정하기 전까지 3-1과 3-2는 영향이 없다.

### 3-4. 주문책의 직업 줄과 주문 등급

`LayerDisplay.lua`의 `GetSideTabIcon`이 스킬 라인 2를 직업 줄로 보고 직업 탭 아이콘을 거기서 가져온다.
카멜롯의 주문책은 클래식처럼 특성 트리마다 줄이 하나고, 직업 줄은 카멜롯에만 있는
`C_SpellBook.GetClassSkillLineInfo()`로 따로 얻는다(`Camelot/SpellBook/Blizzard_SpellBookFrame.lua`).
**잰 값으로 줄 2는 Restoration이다**(드루이드). 직업 줄 "Druid"는 `GetClassSkillLineInfo`에서만 나온다.

**`Client.ClassSkillLine()`.** 직업 줄의 이름과 아이콘을 낸다. 정식 서비스에서는 지금처럼 줄 2다.

**주문 등급.** 카멜롯은 등급마다 주문 번호가 따로이고 주문책에 등급마다 항목이 있다
(`IsSpellBookItemLowRank`는 카멜롯에만 있다). `ActionCatalog.lua`의 `BuildPlayerSpells`가 항목마다
한 줄을 만들므로 등급 수만큼 줄이 선다. 블리자드 주문책은 CVar `ShowAllSpellRanks`가 꺼져 있으면
낮은 등급을 숨긴다(`Blizzard_SpellBookFrame.lua`). 우리 목록도 같은 CVar를 따른다.

**시전 이름이 등급에 묶인다.** 카멜롯은 주문 부제로 "Rank 1"을 준다(잰 값). `Spells.lua`의
`ComposeSpellCastName`은 부제를 괄호로 붙이므로 `Healing Touch(Rank 1)`을 만들고, 그 액션은 2등급을
배운 뒤에도 1등급을 쓴다. 등급 부제는 붙이지 않아야 한다. 등급을 가리는 법은 층의
`Client.IsRankSubtext` 같은 이름으로 한 곳에 둔다.

**전문 기술 주문은 스킬 라인에 없다.** 약초 채집의 주문 둘은 주문책 오프셋 10에 있는데,
`GetNumSpellBookSkillLines`는 줄 셋(8 + 1 + 1 = 10개 항목)만 센다. 스킬 라인을 도는
`BuildPlayerSpells`는 이 주문을 못 본다. `GetProfessions`가 슬롯 일곱 개를 주고, 약초 채집은 스킬
라인 182다. 전문 기술 주문은 스킬 라인들의 항목 바로 뒤에 붙는다. Restoration 줄이 한 항목 늘자
오프셋도 10에서 11로 밀렸다. 그러니 오프셋은 고정값으로 못 쓰고 `GetProfessionInfo`에게 매번 묻는다.

### 3-5. 층이 아닌 것

- **정식 서비스의 번호로 잡힌 표.** `SpecSpells.lua`의 카멜롯 키(`shipping-on-the-camelot-client.md`
  6절), `Misc.lua`의 `CANCEL_FORM_LINE`의 드루이드 변신 인덱스, `ActionTooltip.lua`와
  `ActionMenuNodes.lua`의 보너스 바 이름(스카이라이딩 플라이아웃 229). 같은 표에 카멜롯 값을 더하는
  일이고, 값은 프로브의 forms 구역이 잰다. `PET_ACTION_SLASH_BY_ID`는 펫 직업으로 재야 해서 이
  프로브가 못 잰다.
- **카멜롯에 없는 기능.** 투기장 프레임(`SettingsTab.lua`의 블리자드 프레임 체크박스 목록)은
  "`CompactArenaFrame`이 있는가"를 묻는다. 투기장 유닛 자체는 카멜롯에서도 답한다(프로브).
  스카이라이딩 축은 남기고, 언제나 거짓이다.
- **이미 가드된 자리.** `C_AssistedCombat`, 하우징 바인딩 컨텍스트, `OverrideActionBar`. 할 일이 없다.

### 3-6. 잰 값이 드러낸 고장 둘

- **`GetFlyoutInfo(229)`가 카멜롯에서 에러를 던진다.** nil을 돌려주는 것이 아니라 "No flyout found"로
  raise한다(69977). `ActionTooltip.lua`의 `GetActionBarTypeLabel`과 `ActionMenuNodes.lua`의 `BONUSBAR`
  메뉴가 처음 그려질 때 이것을 부르므로, 카멜롯에서는 보너스 바 조건의 툴팁과 메뉴가 에러로 멈춘다.
- **아틀라스 `common-icon-minus`가 없다.** `StorageUI.lua`의 `CHECK_SOME`이다. 나머지 20개는 있다.

## 4. 헤드리스

`tests/wow_shim.lua`는 정식 서비스 하나만 흉내 낸다. 여기에 **카멜롯 세계**를 하나 더한다. 인덱스
6과 10이 빈 직업 목록과 `GetAllClassIDs`, 직업마다 전문화 하나(1482, 1484~1491), 그룹을 든 특성 노드와
`GetGroupDisplayInfoByTreeID`, 전문화 그룹 둘. 정식 서비스 세계에는 카멜롯에만 있는 API가 없어야
정식 서비스 쪽 가지가 돈다.

**스위트 전체를 두 번 돌리지 않는다.** 정식 서비스가 전체 스위트를 그대로 들고, 카멜롯 세계는 층의
구현마다 붙는 케이스로 돈다. 층의 모든 함수는 두 세계에서 케이스를 가진다.

3-1이 첫 케이스다. 카멜롯 세계에서 `ClassSpecCatalog`에 드루이드가 있는지 묻는 케이스는 지금 코드에서
빨갛다.

`tools/lib/bake.lua`는 `Constants.lua`와 `Snippets.lua`를 자기 흉내로 싣는다. 층의 파일이 그 둘보다
먼저 서더라도 둘이 층을 부르지 않는 한 손댈 것이 없다.

## 5. 쪼개기와 폴더

**폴더로 옮기는 것은 주석 인용을 안 깬다.** 코드와 문서는 파일을 이름으로 부른다. 깨지는 것은
경로를 손으로 든 도구들이다.

- `tools/lib/snippets.js`의 `forEachSnippet`는 `Debind/`의 맨 위만 읽는다. 스니펫이 든 파일이 하위
  폴더로 가면 `check:snippets`에서 **말없이 빠진다.** 옮기기 전에 재귀로 바꾼다.
- `tests/run.lua`는 불러올 파일 30개를 손으로 들고 있고, 그것을 XML과 맞춰 보는 검사가 없다. 옮기기
  전에 그 검사를 세운다(2절의 파일 가르기도 이 검사를 기다린다).
- 경로를 손으로 든 도구: `bake.lua`, `check-state-eval`, `check-dbver`, `check-reload-options`,
  `check-export-fields`, `check-menu-ctx`, `stamp-dev`, `build-help`. 옮긴 파일마다 같이 고친다.
- XML의 `<Script file=>`은 그 XML이 있는 폴더를 기준으로 푼다.

**쪼개기는 이름 인용을 깬다.** "`Misc.lua`의 X"가 X가 옮겨 간 파일을 가리키도록, 쪼개는 단계마다
옮긴 이름의 인용을 같이 고친다.

**쪼갤 것.**

- **`Misc.lua` (4466줄).** 서로 무관한 것들의 모음이고, 구역을 넘나드는 파일 지역 변수는 여섯
  개뿐이다(`UnitConditionToState`, `RoleMeasuredUnder`, `CannotStand`, `SOURCE_ROW`와 `SOURCE_AT`,
  `IntersectStoredUnitConditions`, `SWITCH_CLICK_TARGET`). 유닛 조건과 역할, 액션에서 바인딩으로의
  파생, 직업과 전문화 카탈로그, 이슈 판정, 매크로 문자열 변환과 해석으로 가른다. `ApplyOptions`는
  `check-reload-options`가 `Misc.lua`에서 찾으므로 남는 쪽에 둔다.
- **`Profile.lua` (4105줄).** 마이그레이션(`MigrateLayer`, `MigrateSwitches`, `MigrateDB`)이 1100줄로
  따로 선다. `check-dbver`가 `Profile.lua`를 경로로 읽으므로 같이 고친다.

**안 쪼갤 것.** `UpdateBindings.lua`는 재빌드마다 쓰는 파일 지역 상태가 파일 전체에 걸쳐 있다.
`SecureBindings.lua`는 `check-state-eval`이 파일과 지역 변수 이름으로 찾고, 스니펫 골든이 파일
이름을 키로 쓴다. 둘 다 쪼개서 얻는 것보다 깨질 것이 많다. `DebindUI.lua`는 이 계획에서 뺀다.

**폴더.** `Client/`가 첫 폴더다. 그 밖에는 묶음이 분명한 것만 옮긴다. 액션 메뉴 넷과 `MenuKit.lua`
(`check-menu-ctx`가 다섯 경로를 든다), 도움말 넷(`HelpPlate`, `HelpTip`, `HelpText`, `HelpTopics`.
`build-help`가 `HelpTopics.lua`를 쓰고 TOC의 순서를 확인한다)이다. 파이프라인의 중심 파일은 맨 위에
남는다.

## 6. 로케일

**카멜롯에서 거짓이 되는 문장만 키를 따로 두고, 부르는 자리가 능력을 물어 고른다.** 갈래별 로케일
파일은 로케일 셋에 갈래 둘을 곱해 번역자가 볼 곳을 가르고, 빌드 때 합치기는 2절 1번에 걸린다. 없는
키에 키 이름을 돌려주는 `__index`가 이미 있어서, 메타테이블 덧씌우기는 빠진 키가 조용히 영어 키
이름으로 뜬다.

카멜롯에 없는 기능의 문자열은 화면에 안 뜨고, 카멜롯에서 헛돌 뿐 거짓은 아닌 문장("전문화를 바꿀
때")은 그대로 둔다. 거짓이 되는 후보는 지금까지 넷이다.

- `CONDITION_TALENT_DESC`의 마지막 문장. 영웅 특성 트리 둘을 보여 준다고 말한다.
- `CUSTOM_TARGET_UNSUPPORTED_UNIT_IN_COMBAT`와 같은 뜻의 도움말 문장. 투기장 프레임을 든다.
- 도움말의 레이어 순서 문장. 전문화 레이어를 든다. 3-3의 결정에 달렸다.
- 도움말의 "스카이라이딩 중" 예시. 카멜롯에 없는 조건을 예로 든다.

도움말은 `docs/ingamehelp/`에서 만들어지므로 그 절차를 따른다.

## 7. 순서

1. **검사 먼저.** `forEachSnippet` 재귀, `tests/run.lua`와 XML 목록 대조. 코드는 안 바뀐다.
2. **`Client/`와 3-1**, shim의 카멜롯 세계. 층의 모양이 여기서 선다. 카멜롯의 실제 고장 하나를 고친다.
3. **3-2, 3-3, 3-4.** 프로브 값이 입력이다. 3-3의 레이어 결정은 3-2와 무관하다.
4. **`Misc.lua`와 `Profile.lua` 쪼개기**, 이어서 폴더. 단계마다 골든이 바이트 그대로인 순수 이동이다.
5. **로케일**(6절).
6. **`shipping-on-the-camelot-client.md`의 나머지**: 5절의 전문화 하나일 때의 화면(3-3 결정 뒤),
   6절 `SpecSpells`, 8절 가져오기 이슈, 9절 배포.

2와 3을 쪼개기보다 앞에 두는 이유는 목표가 카멜롯이기 때문이다. 3-1은 지금 카멜롯에서 난 고장이고
층의 첫 파일이 된다. 쪼개기는 언제 해도 동작이 안 바뀌므로 뒤로 미뤄도 잃는 것이 없다.
