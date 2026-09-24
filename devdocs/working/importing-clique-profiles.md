# Clique 프로필 가져오기 (2026-09-24 시작)

> 상태: **설계 중. §4는 id로 바꿔 저장하는 것만 빼고 구현했다.** 정한 것은 §1부터 §6까지이고, 안
> 정한 것은 §8에 모았다.
>
> Clique의 저장 모양과 조합의 뜻을 코드에서 읽은 원문은 `.zzz/clique-savedvars.md`가 든다. 여기는
> 그 조사에서 나온 결론과 이유만 담는다.

Clique가 켜져 있으면 `CliqueDB3`를 읽어 보관함 항목을 만든다. 사용자는 그 항목을 여느 항목처럼
미리 보고 추가한다. 보관함의 미리보기, 추가, 승인은 그대로 쓴다.

## 1. 입구

**`CliqueDB3`를 바로 읽는다.** Clique는 `Debind.toc`의 `OptionalDeps`에 있어서 로그인 뒤에는 전역으로
읽힌다. `profileKeys`가 계정의 모든 캐릭터를 프로필에 잇고 있으므로, 한 번 읽으면 접속하지 않은
캐릭터의 것까지 전부 나온다.

## 2. 항목은 변환된 결과만 든다

**Clique의 원래 모양은 항목에 남기지 않는다.** 변환 전의 것을 들고 있으면 그쪽 데이터 구조가 바뀔
때마다 우리가 따라가야 한다(소유자, 2026-09-24). 항목에 든 것은 우리 액션이고, 그래서 출처를 적는
필드도 두지 않는다. 추가할 때 출처를 읽는 코드가 없다.

**문자열을 거치지 않는다.** 항목은 문자열이 아니라 payload를 저장하므로(`StoreEntry`) 인코딩하면
곧바로 다시 푸는 헛일이 된다. `Import.lua`에 `ImportEntry`에서 디코드만 뺀 함수를 하나 연다.
`PayloadIsImpossible`로 거르고 `StoreEntry`에 넘긴다.

## 3. 항목을 나눈다

**General 항목 하나와 캐릭터마다 항목 하나.** Clique 프로필은 캐릭터 것이고(AceDB 기본 프로필이
캐릭터 이름이다), 9월 5일의 "전부 Shared General"은 한 프로필 안에 직업 전용과 공용이 섞여 있다는
전제에 섰다. 실제 저장 파일은 캐릭터마다 프로필이 따로여서 그 전제가 안 맞는다. 그대로 General에
넣으면 한 캐릭터의 바인딩이 모든 캐릭터에 걸린다.

**General을 캐릭터 항목마다 넣지 않고 따로 둔다.** 받는 쪽에는 중복을 거르는 곳이 없다
(`PlanArrival`, `PlaceArrivedActions`). 캐릭터마다 자기 항목을 추가할 때마다 계정 공용인 General이
한 벌씩 더 쌓인다.

**직업은 없다.** Clique는 직업을 저장하지 않는다. payload의 `class`는 이미 없어도 되는 값이고
(`PayloadIsImpossible`이 nil을 통과시킨다), 직업이 필요한 주소는 `shared.classes`뿐인데 이 항목들은
General과 캐릭터 층만 쓴다.

**이름**은 `Imported Clique Profile (Global)`, `Imported Clique Profile (이름-서버)` 꼴이고 항목의
`name`에 든다. 캐릭터 이름과 서버는 `profileKeys`의 키에서 나온다.

**`entry.character`는 쓰지 않는다.** 그 필드는 "여기서 만든 항목", 곧 내 백업이라는 표시다
(`CreateEntry`, `STORAGE_ENTRY_MADE`).

**미리보기의 층 이름을 고친다.** `class`가 nil이면 `GetLayerLabel`이 캐릭터 층을 `UnitName("player")`로
부른다. 다른 캐릭터의 항목을 열면 읽는 사람의 이름이 찍힌다.

## 4. 주문은 이름으로 들어온다

**Clique는 주문을 이름으로만 저장한다.** 주문서에서 id로 고르지만 저장할 때는 이름과 부제만 남긴다.
변환하는 순간에는 이름을 id로 풀 수 없다. 이름을 푸는 표는 그 캐릭터의 그 전문화에서만 서고, 가져오기는
접속하지 않은 캐릭터의 것까지 한 번에 만든다.

**그래서 `SPELL`의 `value`가 이름도 받는다.** 우리 액션이 반드시 id일 필요는 없다(소유자). 버튼에는
이미 id가 아니라 이름이 나가고 있어서(`DescribeBinding`), 새 경로가 아니라 id에서 이름을 얻는 단계를
건너뛰는 갈래다.

**리빌드마다 이름에서 id로, 다시 이름으로 간다.** `CollectBindingFacts`가 문자열 값을 만나면
`Spells.GetObtainableIDsByName()`에서 id를 찾고, 찾으면 지금의 id 갈래를 그대로 탄다. 부제, 누르고
떼기 판정, 아이콘이 id로 저장한 액션과 같아진다. 못 찾으면 이름을 그대로 버튼에 넣는다. 매 리빌드에
풀므로 전문화를 바꾸면 새 전문화의 표로 다시 풀린다.

**한 번 풀리면 id로 바꿔 저장한다.** 그 이름으로 찾은 id라서 id에서 꺼낸 이름은 언제나 저장된 이름과
같다. 달라지는 것은 버튼에 붙는 부제 하나이고, 그것은 우리 주문서에서 고른 액션이 받는 대우와 같다.
완전히 우리 액션으로 옮긴다는 방향이 이것을 정한다. 로케일에 묶이지 않게 되는 것도 이쪽이다.

**`spellSubName`이 등급이면 `pinRank`로 옮긴다.** 등급 처리는 `shipping-on-the-camelot-client.md`가
들인다.

손볼 곳은 `value`를 id로 가정하고 client에 묻는 자리다. `CollectBindingFacts`, 표시의
`FindBaseSpellByID`(`ActionDisplay.lua`), `ConvertToMacroText`, 보관함의 `VALUE_SHAPES`.
`ResolveBaseSpell`이 이름을 받으므로(`Spells.ResolveName`) 그것을 거치는 자리(`KnownRows`, DEBUG의
`SpellFacts`)는 따로 손대지 않았다.

**이름 하나에 id가 여럿이면 뿌리를 쓴다.** 재능판과 그것이 덮는 주문이 한 이름을 나누고, 어느 쪽 id로
저장했든 `ResolveBase`가 닿는 곳이 뿌리라서 이름도 같은 버튼, 부제, 아이콘에 닿는다.

**버튼 캐시는 이름이 아니라 풀린 id로 잡는다.** 캐시는 적중하면 속성을 안 쓰고 한 번도 안 지워지므로,
이름으로 잡으면 전문화를 바꿔 다르게 풀려도 첫 리빌드가 구운 `*spell-`이 계속 나간다.

**`wow_shim.lua`의 `C_SpellBook`은 id만 받는다.** 클라이언트 문서가 인자를 `number`로 적는다. 전에는
이름에 nil로 답해서, 이름이 `FindBaseSpellByID`에 닿아도 헤드리스가 몰랐다.

## 5. Hover Cast 모드는 계정 설정을 따른다

**가져온 액션에는 `hoverCastMode`를 넣지 않는다.** `default` 세트(개체창 위, 프레임의 유닛)와
`hovercast` 세트(커서 아래 무엇이든)는 우리 쪽에서 Unit Frames와 Mouseover에 맞는다. 둘을 갈라
넣는 길은 둘 다 문제가 있다.

- 액션마다 넣으면 설정 탭의 모드를 바꿔도 가져온 액션이 따라오지 않고, 왜 안 따라오는지가 화면에
  안 보인다.
- `hovercast`를 Hover Cast가 아니라 `unit = mouseover`와 존재 조건으로 옮기면 두 세트가 안 섞이지만,
  그것은 Clique가 속성을 거는 방식을 흉내 낸 것이다. 우리 사용자는 그렇게 짜지 않는다(소유자).

**계정 모드와 다른 세트가 있으면 변환할 때 알린다.** 몇 개가 어느 모드로 동작하게 되는지를 한 줄로.
항목을 만드는 순간과 추가하는 순간은 같은 계정이고 모드도 계정 설정이라, 알릴 것은 변환할 때 이미
정해진다. 추가할 때 묻는 선택지(전역 설정대로와 액션별로)는 더 간단한 이쪽으로 접었다.

## 6. 세트와 필드의 대응

| Clique | Debind | 이유 |
|---|---|---|
| `type = "spell"` | `SPELL`, 값은 이름 | §4 |
| `type = "macro"` + `macrotext` | `MACROTEXT` | |
| `type = "macro"` + `macro` | `MACRO` | 이름으로 찾는다 |
| `type = "item"`, 장비칸 번호 | `USESLOT` | |
| `type = "target"` | `TARGET` | |
| `type = "menu"` | `TOGGLEMENU` | |
| `sets.default`, `sets.hovercast` | Hover Cast 켬, `normalCast = false`, 모드 없음 | §5 |
| `sets.global` | 조건 없는 평범한 키 | |
| `sets.ooc` | `combat = false` | |
| `ooc`가 있는 키의 `ooc` 아닌 짝 | `combat = true` | Clique는 그 짝을 전투 밖에서 통째로 치운다. 우리는 조건이 안 맞으면 다음 액션으로 넘어가서, 안 붙이면 전투 밖에서 짝이 나간다 |
| `sets.friend` / `sets.enemy` | `units["@"].reaction` 아군 / 적 | 둘 다 있으면 Clique가 `friend`만 읽으니 우리도 그렇게 |
| 수정자 없는 `BUTTON1`·`BUTTON2`의 `hovercast`·`global` | 버린다 | Clique가 걸지 않는다 |
| META가 붙은 마우스 클릭의 `default` | 버린다 | 블리자드의 `SecureButton_GetModifierPrefix`가 META를 안 봐서 Clique에서도 한 번도 발동한 적이 없다. 우리는 `BINDING_ISSUE_NOT_SUPPORTED_META_CLICK` |
| 바인딩의 `unit` | 버린다 | Clique의 속성 코드가 읽지 않는다 |
| 프로필 기본값 두 줄(`BUTTON1` target, `BUTTON2` menu, `default`) | 버린다 | 우리 액션이 없는 클릭은 프레임 자신의 대상 지정과 메뉴가 그대로 나가고, 가져오면 캐릭터마다 하는 일 없는 액션이 둘씩 생긴다 |

## 7. 검사

변환기는 client를 부르지 않는 순수 함수로 짜서 헤드리스 스펙이 §6의 표를 한 줄씩 잡는다. 입력은
Clique 바인딩 표, 출력은 payload다. 이름 색인을 거치는 리빌드 갈래(§4)는 `CollectBindingFacts`가
client 호출을 한 곳에 모아 두었으므로 같은 식으로 세계를 넘겨 잡는다. 이름이 풀리는 경우, 안 풀리는
경우, 풀린 뒤 id로 바꿔 저장하는 경우가 그것이다. 앞의 둘과 id가 여럿인 이름, 다음 리빌드에서 다시
풀리는 경우, 표시와 매크로 변환, `VALUE_SHAPES`는 `spellname_spec.lua`가 잡는다. `CliqueDB3`를 실제로 읽는 입구와 보관함 화면은
헤드리스가 닿지 않는다.

## 8. 안 정한 것

- **General 항목에 무엇이 들어가나.** Clique가 계정 단위로 저장하는 바인딩은 없다. 여러 캐릭터가 같은
  프로필을 가리킬 때 그 프로필이 후보다.
- **`sets.specN`을 어디로.** 캐릭터+전문화 층(`char[N]`)에 넣으면 직업이 필요 없고, 전문화가 여럿인
  줄은 층마다 한 벌씩 복사한다. 전문화 조건(`conditions.specs`)은 `{ [classID] = mask }` 꼴이라
  직업이 있어야 한다.
- **아이템 이름.** Clique의 `item`은 장비칸 번호가 아니면 이름이다. 주문과 같은 모양으로 받을지.
- **id로 바꿔 저장하는 시점.** 리빌드에서 프로필을 쓰는 것은 지금까지 없던 일이다.
- **`menu`에 `hovercast`가 붙은 바인딩을 계정 모드가 Mouseover인 사람이 가져올 때.** 우리
  `TOGGLEMENU`는 mouseover를 대상으로 받지 않는다(`UNIT_INFO`). 메뉴가 열리면 항목이 커서 아래의 메뉴를
  대상으로 잡기 때문이고, 넣는 것은 짧다(소유자).
- **`CL01:` 문자열.** 지원할지.
- **`char` 설정.** `blizzframes`, `blacklist`, `specswap`과 전문화별 프로필, `stopcastingfix`,
  `downclick`. 옮길 것이 있는지.
