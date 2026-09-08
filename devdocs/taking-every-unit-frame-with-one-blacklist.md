# 유닛 프레임은 전부 잡고, 빼는 것은 블랙리스트 하나 (2026-09-09 설계)

> 상태: 결론이 섰다. 구현은 아직 안 했다. §6이 코드에서 없어지는 것과 남는 것, §7이 무엇이 그것을
> 지키는지다. `legacy/coexisting-with-clique.md`의 옵션과 `legacy/making-the-pack-box-own-its-addon.md`의
> 상자 셋을 이 문서가 대신한다. 그 둘의 **기계**(Clique 곁에 서는 것, 팩 상자가 소유권인 것)는 그대로
> 살고, 없어지는 것은 스위치다.

## 0. 어디서 나온 자리인가

9월 8일 하루에 유닛 프레임 규칙에 축이 둘 들어왔다. Clique와 나란히 서는 것(`Use Alongside Clique`),
그리고 팩 상자가 거부권에서 소유권으로 바뀐 것. 각각 자기 스위치와 자기 예외를 들고 왔고, 그날 밤
코드 리뷰 뒤에 소유자가 잡은 구멍 다섯이 전부 같은 모양이었다. **한 자리에서 고친 규칙이 같은 축을
묻는 다른 자리에 안 걸렸다.** 되가져가기는 팩에만 걸렸고, 재조립 예산은 세는 것으로는 애드온의
정상 동작과 싸움을 가를 수 없었고, Clique 판별은 "깔려 있음"이었고, 경고를 걷자 Clique 프레임 위의
클릭 바인딩이 말없이 먹통이 됐다.

소유자가 물었다. "규칙이 너무 복잡한 게 사실이지?" 그렇다. 프레임 하나가 우리 것인지에 답하는 축이
다섯이었다. Clique가 깔렸는지, 공존을 켰는지, 이름을 쥔 것이 누구인지, 목록에 있는지와 그 상자,
그리고 `Use Unit Frames Addons Keep to Themselves`. 이 문서는 그 다섯을 하나로 줄인다.

## 1. 결정

**유닛 프레임은 전부 우리 것이다.** 어느 문으로 오든, 아무 문으로도 안 오든, Clique가 있든 없든,
누가 이름을 쥐고 있든. 빼는 수단은 **블랙리스트 하나**다. 블리자드 개체창 일곱과 설치된 팩. 체크가
"이 프레임은 안 건드린다"다.

남는 물음은 하나다. **"이 프레임이 블랙리스트에 있나."** 아니면 우리 것이다.

### 1-1. Clique와는 무조건 같이 선다

`Use Alongside Clique` 스위치를 없앤다. Clique가 있으면 그 테이블과 헤더에서 듣고, 없으면 지금처럼
Clique 이름을 우리가 쓴다(`DebindCliqueFake`). 물러나는 상태 자체가 없어진다.

**왜.** 그 스위치는 Clique 사용자의 판을 묻지 않고 바꾸지 않겠다는 배려였고, 누가 원해서 만든 것이
아니다. 둘을 같이 깐 사람이 기대하는 것은 "둘 다 돈다"이고, 그것을 안전하게 만드는 것은 옵션이
아니라 남의 래퍼 위에 서서 그쪽 본문을 대신 돌려 주는 기계다(`legacy/standing-on-top-of-foreign-wrappers.md`).
그 기계가 있는 이상 스위치가 지키는 것은 두려움뿐이다.

**값.** Clique를 쓰는 모든 사람의 판이 업데이트로 바뀐다. 지금까지 그 사람에게 우리는 없는 것과
같았는데 이제 같은 프레임에서 두 엔진이 같이 돈다. Clique는 안 깨지고, 겹치는 것은 양쪽에 같은 키를
걸었을 때뿐이다. 릴리스 노트 한 줄로 알린다.

### 1-2. 블리자드 개체창은 전부 잡고, 일곱 상자는 블랙리스트로 남는다

`Options.blizzframes`는 그대로 쓴다. 저장이 이미 `[type] = false`라 블랙리스트 모양이고, 바뀌는 것은
화면의 극성뿐이다. 옛 기능이라 쓰던 사람이 있을 수 있고, 어렵지 않으니 둔다.

### 1-3. 모르는 애드온의 유닛 프레임도 전부 잡는다

`Use Unit Frames Addons Keep to Themselves`와 `TakesUnregisteredFrames`를 없앤다. 아무도 안 건넨
프레임을 집는 문 셋(이름 후크, 헤더 자식 훑기, oUF 훑기)은 늘 열려 있다.

**왜.** 그 상자는 9월 5일에 남의 엔진을 깰까 봐 물러섰던 자리의 흔적이고, 그 걱정은 9월 7일에
기계로 풀렸다. 걱정이 풀렸으면 스위치도 갈 자리다.

### 1-4. 아는 애드온만 사용자가 뺀다

팩 상자는 남는다. 이름을 보고 끄는 것이 사용자가 이해하는 유일한 어휘고, 어느 애드온에서 문제가 나면
그 이름을 `KNOWN_PACK_FRAMES`에 넣는 것이 우리 유일한 회피로다. 저장은 지금 그대로
`packFrames[addon] = false`.

### 1-5. 밖에서 온 해제는 뜻이 없다

블랙리스트에 없는 프레임은 우리 것이고, 있는 프레임은 애초에 등록되지 않는다. 옵션은 리로드로만
바뀌니 세션 중에 "이제 이 프레임을 안 잡는다"로 바뀌는 경우가 없다. 그래서 `UnregisterFrame`이
없어진다. 남는 것은 싸움에서 스스로 물러나는 `StandDown`과, API 모양으로 남기는 빈 함수
(`DebindPublic:UnregisterFrame`, 헤더의 `clickcast_unregister`)뿐이다.

`legacy/leaving-unregistered-frames-alone.md`의 "외부에서 들어오는 해제는 그대로 받는다"는 이것으로
닫힌다. 그 문장은 찾아내서 집는 문이 없던 때의 것이었다.

## 2. 화면

```
Unit Frames                                   (섹션 헤더, UNITFRAME_LABEL)
  Clicking a Unit Frame Casts On              (드롭다운)
Leave These Unit Frames Alone                 (섹션 헤더)
  Player Frame
  Pet Frame
  Target and Focus
  Party Frames
  Raid Frames
  Boss Frames
  Arena Frames
  Grid2                                       (설치된 팩마다 하나, 그 애드온의 Title)
  EllesmereUI Unit Frames
  VuhDo
```

- **목록이 하나다.** 블리자드 일곱이 늘 있으니 헤더가 늘 서고, 팩이 하나도 없어도 빈 헤더가 안 남는다.
- **체크가 "안 건드린다"다.** 아무것도 안 건드린 사람의 화면이 전부 빈 상자고, 그것이 "전부 쓴다"와
  일치한다. 부정형 상자는 클라이언트 자신의 어휘다("Hide …" 류).
- **툴팁은 한 문장 꼴이다.** "Ticked, Debind leaves this unit frame alone. Its own click handling is
  unaffected." 팩 줄은 "this addon's unit frames". 뒤에 `REQUIRES_RELOAD`.
- **회색이 없다.** 물러나는 상태가 없으니 `NotClique` 술어와 "Cannot be used with Clique!" 문장도
  없어진다.
- `Use Alongside Clique` 행, `Use Unit Frames Addons Keep to Themselves` 행, `BLIZZARD_UNIT_FRAMES`와
  `ADDON_UNIT_FRAMES` 두 헤더가 빠지고, 새 헤더 키 하나가 들어온다.

## 3. 마이그레이션

없다. `blizzframes[type] = false`와 `packFrames[addon] = false`는 그대로 읽는다.
`db.global.workAlongsideClique`와 `db.global.takeUnregisteredFrames`는 읽지 않게 되고, 남은 값은
`CleanUpDB`가 지우는 목록에 넣는다(끄는 것과 지우는 것이 다르다는 원칙은 옵션이 살아 있을 때의
것이고, 없어진 옵션의 값은 고아다).

## 4. 남의 애드온 쪽에서 달라지는 것

- **Clique 사용자.** 위 §1-1의 값. 그 밖에는 없다.
- **EllesmereUI가 자기 엔진을 켜서 이름을 쥔 판.** 지금은 그쪽이 쥔 프레임을 마지막 상자가 정했는데,
  이제 무조건 우리 것이다. 위에 서서 그쪽 본문을 돌려 주니 그쪽 동작은 그대로다. 팩 상자로 빼는
  길은 남는다.
- **모르는 애드온.** 블리자드 헤더나 oUF를 쓰면 전부 잡힌다. 자기 헤더를 굴리고 문도 안 여는
  애드온은 지금처럼 못 본다.

## 5. 재조립은 그대로다

두 엔진이 한 프레임에 서는 기계(`Reassemble`, `Overs`, 재진입 가드)는 이 설계의 전제라 손대지 않는다.
싸움의 정의도 그대로다. 우리가 얹는 도중에 그 위에 다시 얹는 것. 횟수는 세지 않는다.
`.zzz/guarding-the-replay-against-another-replayer.md`의 미착수 건도 그대로다.

## 6. 코드에서 무엇이 없어지고 무엇이 남나

**없어지는 것**

- `StandsAsideForClique`와 그것을 묻는 자리 전부. `ApplyStandAsideForClique`, `GetHoveredUnit`의 Clique
  갈래, 문마다 첫 줄의 "물러나 있으면 돌아감", `Options.lua`의 `NotClique`와 `UnitFrameTooltip`.
- `workAlongsideClique`, `takeUnregisteredFrames`, `TakesUnregisteredFrames`, `TakesUnofferedFrame`
  (목록에 있으면 팩 상자, 아니면 참이 되므로 `TakesPackFrames` 하나로 접힌다), `KeepsFrameOnRelease`.
- `UnregisterFrame`과 그것을 부르는 자리. 테이블의 `nil` 쓰기, 홀더의 `nil`, Clique의
  `export_unregister`, 헤더의 `clickcast_unregister`, `DebindPublic:UnregisterFrame`은 이름만 남고
  아무것도 안 한다. 전투 큐의 `unregister` 항목과 `QueuedFrameOp`, `ClearHeaderOwned` 경로,
  `hccframes`에서 빼는 자리.
- 홀더 기계의 대부분. `HolderAnswer`, `AskHolder`, `AskHolderAgain`, `deferred`, `offered`,
  `RememberCliqueTable`, 되묻기 이벤트 셋. 남이 이름을 쥐고 있어도 쥔 것도 우리 것이니 물을 것이
  없다. 남는 것은 그 프록시의 `__newindex`를 감싸서 등록을 듣는 것과 `HandOver`, 그리고 잠긴
  테이블은 손대지 않는 것.
- 로케일: `WORK_ALONGSIDE_CLIQUE`(2), `TAKE_UNREGISTERED_UNIT_FRAMES`(2),
  `BINDING_ERROR_CANNOT_USE_HOVER_WITH_CLIQUE`, `BLIZZARD_UNIT_FRAMES`, `ADDON_UNIT_FRAMES`,
  `PACK_FRAMES_DESC`. 새로: 헤더 키 하나, 툴팁 키 하나(블리자드용과 팩용 문장 둘).
- 테스트 킷과 스펙에서 위의 것을 재던 케이스. 특히 `holder_spec`의 물러남 케이스들, `frames_spec`의
  해제·물러남·공존 케이스들, `options_spec`의 회색 케이스.

**남는 것**

- 문 일곱과 `KNOWN_PACK_FRAMES`. 찾는 수단과 프레임 종류는 여전히 거기서 나온다.
- `RegisterFrame`의 관문 한 곳. 묻는 것은 `TakesPackFrames`와 `blizzframes`.
- `Reassemble`과 재진입 가드, `StandDown`.
- Clique에 붙는 것. 테이블 감싸기, 헤더 훅, 붙을 때 `Clique.ccframes`와 `Clique.hccframes` 쓸어 담기,
  헤더 문의 한 틱 미루기. `InitDB`의 Clique 분기는 "깔려 있으면 붙는다" 하나다.
- `DebindCliqueFake`, 헤더 표시(`hd`, `hccframes`, `MarkHeaderOwned`). Clique 모양으로 `hccframes`를
  읽는 애드온이 있어서다.
- 전투 큐. 등록만 남으니 항목 하나짜리가 된다.

## 7. 무엇이 무엇을 지킬 수 있나

- **헤드리스 (`tests/frames_spec.lua`)** — 블랙리스트에 없는 프레임이 문 일곱 각각으로 들어오는 것.
  블랙리스트의 팩과 블리자드 종류가 어느 문에서도 거절되는 것. 밖에서 온 해제 다섯 갈래가 행을
  건드리지 않는 것. 전투 중 등록이 큐를 거쳐 서는 것. Clique 스탠드인에 대해 테이블과 헤더 둘 다에서
  듣고, 붙을 때 이미 든 것을 쓸어 담는 것. 재진입 싸움에서 물러나고 되얹기에는 안 물러나는 것.
- **헤드리스 (`tests/holder_spec.lua`)** — 남이 이름을 쥔 판에서 쓴 것이 전부 우리 것이 되는 것, 잠긴
  테이블은 손대지 않는 것, `HandOver`.
- **헤드리스 (`tests/options_spec.lua`)** — 헤더 셋과 줄의 차례, 팩 줄이 설치된 것만 서는 것, 체크가
  `false`를 쓰고 해제가 칸을 지우는 것, 어느 줄도 회색 술어를 안 지는 것.
- **정적** — `check:snippet-golden`이 `GetHoveredUnit`이 한 본문으로 돌아온 것과 두 헤더 스니펫을 잠근다.
  `check:locales`가 지운 키와 새 키의 세 벌 일치를 본다.
- **게임 안에서만 (`/debtest`)** — 진짜 Clique 곁에서 같은 프레임 위에 두 엔진이 도는 것, Clique의
  `export_register`가 실제로 우리 행을 세우는 것, 설정창에 목록 하나가 그려지는 것.
- **원리상 못 보는 것** — Clique와 EllesmereUI의 내부 배선이 바뀌는 것. 지금과 같다.
