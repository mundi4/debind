# 저장된 레이어 모양 바꾸기 (2026-09-27 시작)

> 상태: **1단계와 1-2 뒷정리(4절) 구현됨, 다음은 2단계.** 모양(1절)과 그 이유(2절)는 소유자와
> 정했다. 5절에 남은 물음은 2단계와 3단계의 것이다.
> 1단계와 2단계는 한 릴리스로 나간다.
>
> 쓴 세션: `debind-43`, 세션 ID `8661be18-b7a9-47ca-9014-f4260da6eec7`. 1단계 구현과 1-2 계획, 1-1절의
> `switches`: `debind-d0`, 세션 ID `2a9fdeca-0bbb-4a0c-b443-336064187474`. 1-2 구현: `debind-95`,
> 세션 ID `eb79d1d0-eebb-4a2c-8fa5-fb654ab3d0c9`.

저장 탭 오른쪽 열에 키별 보기를 넣다가 나온 일이다. 행마다 레이어를 칠해 보여 주려고 보니 캐릭터
레이어는 누구의 직업인지를 자기 주소로 말하지 못했고, 거기서 두 가지가 드러났다.

1. **캐릭터 레이어의 주소에 직업이 없다.** 저장 데이터는 `characters[guid].layers[spec]`이고 페이로드는
   `char[spec]`이다. 전문화 번호는 직업을 알아야 읽히는데, 페이로드에서 그 직업은 꼭대기의
   `payload.class` 하나에 떨어져 있고 선택 필드다.
2. **계정 전체를 백업할 길이 없다.** `BuildExportPayload`는 `EnumerateAllProfileLayers`를 돌고, 그
   함수가 도는 `LAYER_INFOS`의 직업 키는 `Constants.PLAYER_CLASS` 하나다. 항목 하나에 드는 것은 공유
   일반, 이 캐릭터 직업의 공유 레이어, 이 캐릭터의 레이어뿐이다. 다른 직업의 공유 레이어와 다른
   캐릭터의 레이어는 어떤 항목에도 못 들어간다.

## 1. 모양

```lua
DebindVars = {
    layers = {
        account = {
            GENERAL = { [0] = {...} },
            MAGE    = { [0] = {...}, [1] = {...}, [2] = {...} },
            DRUID   = { ... },
        },
        ["Player-3041-0A1B2C3D"] = {
            MAGE = { [0] = {...}, [2] = {...} },
        },
    },
    switches = {
        account = {
            GENERAL = { [0] = { burst = { mode, resetValue, expr }, aoe = { ... } } },
            MAGE    = { [2] = { burst = { mode = ... } } },
        },
        ["Player-3041-0A1B2C3D"] = {
            MAGE = { [2] = { burst = { mode = ... } } },
        },
    },
    characters = {
        ["Player-3041-0A1B2C3D"] = {
            name, realm, class, race, sex, level, faction, firstSeen, lastSeen, origin,
            switches      = { burst = true },   -- 기억한 값
            CustomTargets = { ... },
        },
    },
    options = { frameBlacklist, excludePlayer, unitframeUseMouseDown, ... },
    dbver, changelogSeen, nextArrivalID, legacyNeeded, legacyAccountPulled, migrated,
}

DebindUIVars = {
    main        = { pos = { x, y }, binSort = ... },
    spellPicker = { pos = { x, y }, filters = { spell = { showOffSpec, favoritesOnly }, item = ..., ... } },
    tipsSeen    = { settingsGear = true },
}
```

- **레이어는 `layers` 한 곳에 모인다.** 계정 칸(`account`)과 캐릭터 칸(`[guid]`)이 같은 모양이다. 칸
  안의 키는 직업이고, 그 밑은 `{ [0] = 직업 전체, [1..5] = 전문화 }`다. 공유 일반은 직업이 아니므로
  같은 모양의 칸 `GENERAL`을 하나 따로 두고 `[0]`만 쓴다.
- **전문화 키는 인덱스 그대로다.** `LAYER_INFOS`의 `spec`, `GetSpecialization()`, 발동 순서의
  `specRank`가 모두 이 번호를 쓴다.
  - **5는 초기 전문화다.** `GetSpecialization()`이 실제로 돌려주는 번호이고, 지금도 `ForEachStoredAction`,
    `HasCharContent`, `MigrateSpecTable`, Legacy가 0..5를 돈다. 옮기는 단계도 0..5를 빠짐없이 옮긴다.
  - **번호에는 구멍이 있다.** 전문화가 둘인 직업은 1, 2, 5를 갖는다. 전문화 표는 `ipairs`나 `#`으로
    돌지 않는다. 그러면 2에서 멈추고 5를 놓친다.
- **캐릭터 칸은 직업 키를 늘 하나만 가진다.** 캐릭터의 직업은 바뀌지 않는다. 그 한 겹은 정보가 아니라
  계정 칸과 모양을 맞추는 값이고, 그 덕에 칸 하나만 떼어 놓아도 누구의 전문화인지가 읽힌다.
- **스위치는 정의만 담고, 칸과 주소는 `layers`와 같다** (소유자). `GENERAL[0]`이 정의 전체(뿌리 답)를
  들고, 나머지 칸은 그 레이어의 오버라이드 행을 든다. 끝에 닿으면 액션 배열이 아니라 `이름 → 행` 표라는
  것만 `layers`와 다르다.
  - **오버라이드가 정의 밖으로 나온다.** 7까지는 `definition.overrides`가 `"MAGE:2"`, `"Player-…:2"`
    문자열 키로 계정 쪽 정의 안에 캐릭터의 답까지 들었다. 그러면 계정 칸이 캐릭터의 것을 들게 되고,
    레이어 주소를 문자열로 한 번 더 적는 두 번째 주소 체계가 남는다. 새 모양에서 캐릭터 행은
    `switches[guid]`에 가므로 캐릭터 칸을 떼어 백업하면 그 캐릭터의 오버라이드가 따라간다.
    `GetSwitchLayerKey`의 문자열은 호출과 화면에서 층을 부르는 이름으로만 남고 저장되지 않는다.
  - **직업을 모르는 캐릭터의 행은 `"*"`에서 기다린다** (소유자). 7까지는 오버라이드만 있는 캐릭터에
    `characters` 항목이 없어 옮기는 단계가 그 직업을 알 수 없다. 그 행은 `switches[guid]["*"]`에 두고,
    그 캐릭터가 접속하면 자기 직업 칸으로 옮긴 뒤 `"*"`와 빈 표를 걷는다(`HealSwitchCells`). 그 행을
    적용하는 것은 그 캐릭터뿐이라, 기다리는 동안 다른 캐릭터에서는 표시되고 세어질 뿐이다. 이름 바꾸기와
    지우기는 `"*"` 칸에도 닿는다. 8부터는 `switches[guid]`에 행이 있으면 `characters[guid]`도 남으므로
    새로 생기지 않는다.
  - **정의의 `value`는 저장하지 않는다.** 실행 중의 값이고 로그인마다 `ApplySwitchResets`가 다시 쓴다.
    수동 모드는 `resetValue`나 기억한 값으로 덮고, 식 모드는 첫 평가까지만 옛 값을 들고 간다. 정의 안에
    두면 설정 표가 실행 상태를 들게 되니, 저장하지 않는 실행용 표로 뺀다.
- **`characters`는 캐릭터의 신원만 든다. 그 캐릭터가 들고 있는 상태는 `states[guid]`로 뗀다** (소유자,
  2026-09-27에 한 번 합쳤다가 같은 날 뒤집었다). 신원은 `RefreshIdentity`가 3.1부터 로그인마다 쓰는
  값들이고, 상태는 기억한 스위치 값과 `CustomTargets`다.
  - **뒤집은 이유.** 합칠 때의 근거는 guid로 묶인 표가 하나 준다는 것이었다. 그 뒤에 페이로드의
    `characters`가 신원만 싣고 상태는 공유에도 백업에도 싣지 않기로 정해졌다(1-1절). 저장 쪽에 상태가
    섞여 있으면 내보낼 때마다 상태 필드를 골라내야 하고, 떼면 저장과 페이로드의 `characters`가 같은
    모양이라 백업이 그 표를 그대로 옮긴다. 상태는 이미 `Profile.lua`의 함수로만 읽고 쓰므로 떼는 비용도
    작다.
  - **`states`라는 이름은 스위치 쪽의 "state" 이름을 걷어낸 뒤에야 겹치지 않는다** (4절 1-2).
  - 기억한 값을 `switches[guid]`에 두지 않는 것은 그 칸의 모양을 `layers`와 같게 두기 위해서다.
  - `characters[guid]`는 그 guid의 `layers`, `switches`, `states` 칸 중 하나라도 있으면 남는다.
  - **레이어의 직업은 여기서 읽지 않는다.** 캐릭터 칸의 직업은 `characters[guid].class`가 아니라
    `layers[guid]`의 키가 답한다.
  - **상태는 `Profile.lua`의 함수로만 읽고 쓴다** (소유자). 저장 모양과 지연 생성(내용이 생기면 붙이고
    비면 떼기)을 그 파일 하나만 알게 하기 위해서다. 사다리와 `Legacy.lua`는 예외다. 둘은 로드 전에
    저장 모양을 직접 옮기는 자리다.
  - `states[guid]`의 필드 이름은 `characters[guid]`에 있을 때와 같다(`switches`, `CustomTargets`).
    옮기는 단계가 필드를 통째로 옮기기만 하게 하려는 것이다.
  - 직업을 읽는 예외는 옮기는 단계 한 번이다. `layers[guid]`의 직업 키를 세우려면 `characters[guid].class`를
    읽을 수밖에 없다. 옮긴 뒤로는 읽지 않는다.
  - **붙어 있는 캐릭터 항목은 모두 `class`를 가진다.** 항목을 `characters`에 붙이는 것은 로그아웃 때의
    `CleanUpDB`뿐이고, 같은 세션의 PLAYER_LOGIN에서 `RefreshIdentity`가 먼저 쓴다. 둘은 개명 커밋
    (27348de)에서 같이 들어왔다. 없는 것은 손으로 고친 파일뿐이다.
  - **손으로 고친 파일은 의도를 되살려 주지 않는다. 모르는 값은 거부하거나 지운다** (소유자). 우리가 할
    일은 그런 파일을 만나도 애드온이 터지지 않게 막는 것까지다. 살리려 들면 그것이 족쇄가 된다. 옮기는
    단계는 `class`가 없는 항목의 레이어를 지운다. 접속할 때 되살리는 길도 두지 않는다.
- **붙이고 떼는 규칙.** `layers[guid]`와 `switches[guid]`는 비면 뗀다. `characters[guid]`는 그 guid 아래
  무엇이든 있으면 둔다. 레이어, 오버라이드, 기억한 값, `CustomTargets` 중 하나라도 있으면 된다. 신원
  필드는 지금처럼 내용으로 세지 않는다. 레이어가 있는 캐릭터는 백업에서 이름을 보여 줘야 하므로 신원이
  함께 남아야 한다.
- **창이 안 열리면 뜻이 없는 값은 `DebindUIVars`로 간다** (소유자). 창 위치, `binSort`, 스펠 선택창의
  필터, `tipsSeen`이다. 코드의 대부분이 화면이라 나중에 화면을 LoadOnDemand 애드온으로 떼어 낼
  생각이고(`DebindStorage`와 합칠 수도 있다), 그날 그 애드온이 이 전역 하나만 가져가면 되게 하려는 것이다.
  - **`changelogSeen`은 본체에 남는다** (소유자). 창을 한 번도 안 여는 사람에게도 로그인 때 도움말 창을
    띄우는 값이라, 창이 안 열려도 뜻이 있다. 화면을 떼어 낸 뒤에는 새 번호가 나올 때 한 번 화면 애드온을
    로드하게 된다. 창이 실제로 떴을 때만 번호를 올리므로 로드가 실패해도 다음 로그인에 다시 시도하고,
    화면 쪽 XML에 secure 템플릿이 없어 전투 중 로드도 막히지 않는다.
  - **선언은 `Debind.toc`에 둔다.** `## SavedVariables: DebindVars, DebindUIVars`. SavedVariables 파일
    이름은 선언한 애드온의 폴더를 따르므로, 화면 애드온의 TOC로 옮기면 `Debind.lua`에 있던 값을 새 파일이
    못 읽어 Legacy 같은 이전이 한 번 더 필요해진다. 본체에 남겨 두면 늦게 로드되는 화면 애드온이 이미
    올라온 전역을 그대로 쓴다. 대가는 창을 안 여는 사람도 로그인 때 이 작은 표를 읽는 것뿐이다.
  - **`DebindUIVars`는 사다리를 타지 않는다. 모양이 바뀌면 옮기지 않고 비운다** (소유자). 잃는 것은 창
    위치와 필터뿐이고 처음 상태로 돌아갈 뿐이다. **`tipsSeen`만은 남긴다** (소유자). 비우면 이미 본 팁이
    모두 다시 떠서, 창 위치와 달리 사람이 눈으로 겪는다. 모양이 바뀌었는지는 표 안의 번호 하나로 알고,
    코드의 번호와 다르면 `tipsSeen`을 뺀 나머지를 비운다.

### 1-1. 페이로드 (제안)

저장 데이터와 같은 `layers`를 싣는다. `SCHEMA_VERSION` 3.

```lua
-- 공유용: 이 캐릭터가 고른 것
payload = {
    v = 3,
    dbver = 8,
    layers = {
        account = {
            GENERAL = { [0] = {...} },
            MAGE    = { [0] = {...}, [2] = {...} },
        },
        ["1"] = {
            MAGE = { [0] = {...}, [2] = {...} },
        },
    },
    switches = {
        account = {
            GENERAL = { [0] = { ["$burst"] = { mode, resetValue, expr } } },
            MAGE    = { [2] = { ["$burst"] = { mode = ... } } },
        },
        ["1"] = { MAGE = { [0] = { ["$burst"] = { ... } } } },
    },
}

-- 백업: 계정 전체
payload = {
    v = 3,
    dbver = 8,
    layers = {
        account = { GENERAL = {...}, MAGE = {...}, DRUID = {...} },
        ["Player-3041-0A1B2C3D"] = { MAGE = {...} },
        ["Player-3041-0B2C3D4E"] = { DRUID = {...} },
    },
    switches = {
        account = { GENERAL = { [0] = {...} }, MAGE = {...} },
        ["Player-3041-0A1B2C3D"] = { MAGE = {...} },
    },
    characters = {
        ["Player-3041-0A1B2C3D"] = { name = ..., realm = ..., class = "MAGE" },
        ["Player-3041-0B2C3D4E"] = { name = ..., realm = ..., class = "DRUID" },
    },
}
```

- **두 용도가 모양 하나를 쓴다.** 가르는 것은 캐릭터 칸의 키와 거기 딸린 신원뿐이다. 읽는 코드는
  `layers`를 도는 한 갈래이고, `account`가 아닌 키는 모두 캐릭터 칸이다.
- **공유용의 캐릭터 칸 키는 그 문자열 안에서만 겹치지 않으면 된다** (소유자). `"1"`, `"2"`처럼 쓰고,
  숫자 키여도 된다. 숫자 키가 그대로 돌아오는 것은 1-2절에서 쟀다. 받는 쪽은 칸을 골라 제 guid 자리에
  넣으므로 키는 거기서 버려진다. guid도 캐릭터를 가리키는 식별자라 공유
  문자열에 싣지 않는다는 원칙(`building-export-import.md` 3절)이 그대로 선다. 공유 문자열에도 캐릭터가
  여럿 들어갈 수 있어야 해서 번호다. 고정된 `character`는 칸이 하나일 때만 맞고, `character-1`처럼
  읽히는 이름은 얻는 것이 없다. guid(`Player-`로 시작)와 겹칠 일이 없고 사람이 열어 볼 일도 없다.
  배열로 바꾸지 않고 키를 쓰는 것은 칸의 모양을 저장 데이터와 같게 두어 읽는 길을 하나로 두기
  위해서다.
- **받는 쪽은 캐릭터 칸 중 하나를 골라 넣는다.** 받는 캐릭터는 하나다. 칸마다 직업이 키로 붙어 있으니
  다른 직업의 칸은 고를 수 없게 한다. 고르는 화면에 보여 줄 것은 5절.
- **`switches`도 저장 데이터와 같은 이름, 같은 모양으로 싣는다** (소유자). v2의 `states`(이름 →
  정의의 평평한 표)는 없어진다. 정의는 `account.GENERAL[0]`에, 오버라이드는 그 층의 칸에 싣고, 캐릭터
  칸의 키는 `layers`와 같은 번호로 바꾼다. 받는 쪽이 캐릭터 칸을 고르면 같은 번호의 스위치 칸도 함께
  고른 것이다.
  - **오버라이드도 싣는다.** v2가 싣지 않은 이유는 키가 `"Player-1329-…:2"`처럼 이 설치의 캐릭터를
    가리킨다는 것이었다(`Export.lua`의 `STATE_FIELDS` 주석). 새 모양에서 직업 칸은 직업 레이어와 같은
    주소라 어느 계정에서나 뜻이 같고, 캐릭터 칸은 레이어처럼 번호로 바뀌니 그 이유가 없어진다.
  - 무엇을 싣나는 지금처럼 액션이 참조하는 스위치와 그 식이 부르는 스위치까지다(`BuildStateManifest`).
  - 받는 쪽이 정의를 쓰지 않는다는 결정(`building-export-import.md`, 2026-08-21)은 그대로다. 싣는
    모양만 바뀐다.
- **`characters`는 캐릭터 칸의 신원이다.** 되돌릴 때 누구의 칸인지 보여 주고 짝을 맞추는 데 쓴다.
  **`layers`나 `switches`에 캐릭터 칸으로 나오는 키만 든다** (소유자). 공유용에는 이름과 서버를 넣지
  않는다(무엇을 넣어 고르게 할지는 5절).
  - **기억한 스위치 값과 `CustomTargets`는 싣지 않는다** (소유자). 백업에도 싣지 않는다.
- **`payload.class`는 없다.** 직업은 모든 칸이 키로 들고 있다.
- **`source`는 지금처럼 남는다.** Clique로 만든 항목은 `layers.account.GENERAL[0]` 하나만 가진다.

**다른 애드온에서 만든 페이로드** (`importing-bindpad-profiles.md`)

BindPad도 계정 공용 칸과 캐릭터별 프로필을 가지니, 이 모양에 그대로 들어간다. 다만 두 가지가 우리
데이터와 다르다.

- **캐릭터가 guid가 아니라 서버와 이름으로만 구분된다** (`PROFILE_<서버>_<이름>`). 그래서 캐릭터 칸의
  키는 guid라고 정하지 않고 **그 페이로드 안에서만 뜻이 있는 문자열**로 둔다. 우리 백업은 guid, 공유용은
  `"1"`, `"2"`, BindPad는 `"서버-이름"`이다. 누구인지는 `characters[키]`가 말한다.
- **직업이 어디에도 없다.** 전문화 번호는 `GetSpecialization()`의 값 그대로이고, Clique의
  `spec1`~`spec5`도 같다. 번호가 뜻을 갖는 것은 추가하는 캐릭터의 직업을 알게 되는 순간뿐이다. 그래서
  직업 자리에 **"추가하는 캐릭터의 직업"을 뜻하는 키 `"*"`**를 둔다.

```lua
-- BindPad에서 만든 페이로드
payload = {
    v = 3,
    dbver = 8,
    source = "bindpad",
    layers = {
        account = { GENERAL = { [0] = {...} } },            -- 일반 탭
        ["Fyrakk-Adelia"] = { ["*"] = { [0] = {...}, [1] = {...}, [4] = {...} } },
    },
    characters = {
        ["Fyrakk-Adelia"] = { name = "Adelia", realm = "Fyrakk" },   -- class 없음
    },
}
```

- **`"*"`는 원본이 직업을 몰랐을 때만 쓴다.** 우리가 만든 페이로드에는 나오지 않는다. 지금
  `ImportAddress`가 모든 캐릭터 레이어에 하는 일(번호로 이 캐릭터의 전문화에 넣기)이 이 키에서만
  남는다. 그 일이 틀린 것은 직업을 아는데도 무시할 때이고, 원본이 모를 때는 그것 말고 할 수 있는 일이
  없다.
- **`"*"`는 계정 칸에도 올 수 있다.** 원본이 "모든 캐릭터의 전문화 N"을 말하는데 직업이 없을 때다.
- **원본의 중복을 걷어내는 것은 변환하는 쪽의 일이다.** BindPad는 계정 공용 키를 모든 프로필에 한 번
  더 적는다(`importing-bindpad-profiles.md` 3절). 페이로드는 걷어낸 뒤의 결과만 싣는다.
- **`characters`는 백업만의 것이 아니게 된다.** 원본이 캐릭터를 여럿 들고 오면 그 이름을 보여 줄
  곳이 여기다. 그래서 `characters`의 유무로 공유용과 백업을 가르지 않는다. 공유용이 신원을 싣지 않는
  것은 그 문자열을 만드는 쪽이 넣지 않아서다.

**v2를 v3로 올리는 단계** (`BringPayloadForward`):

- `shared.GENERAL`은 `layers.account.GENERAL[0]`으로 간다.
- `shared.classes[C]`는 `layers.account[C]`로 간다.
- `char`는 `layers["1"][payload.class]`로 간다. `payload.class`가 없으면(손으로 고친 문자열만
  해당) 5절.
- `states`는 `switches.account.GENERAL[0]`으로 간다. v2는 오버라이드를 싣지 않았으니 다른 칸은 없다.
- `payload.class`를 지운다.

`DebindStorageVars`에 쌓인 v2 항목도 열 때 이 단계를 거친다.

### 1-2. 문자열 포장

**새 버전은 LibSerialize와 LibDeflate를 쓰지 않고 클라이언트의 `C_EncodingUtil`로 포장한다** (소유자).
`0-IDEAS.md`의 "공유 코드를 클라이언트 API로"가 여기로 자라 왔다.

- **CBOR이다.** `C_EncodingUtil`의 JSON은 표의 키를 전부 문자열로 만든다. 전문화 칸 `[0]`~`[5]`,
  `conditions.specs`의 직업 id 키, 숫자로 된 캐릭터 칸 키가 `"2"`처럼 되어 돌아온다.
- **포장 번호를 올린다.** `Export.lua`가 스키마(`SCHEMA_VERSION`)와 포장(`ENVELOPE_VERSION`, 접두어
  `DEB1:`)을 처음부터 따로 센다. 포장을 바꾸면 옛 문자열이 무효가 되고 필드를 더하는 것은 그러면 안
  된다는 이유였는데, 이번이 그 첫 경우다. 새 문자열은 `DEB2:`이고 스키마 3을 싣는다.
- **라이브러리는 뺀다. 다만 `DEB2:`와 같은 때가 아니라 그 뒤다** (소유자, "당장은 아니지만 언젠가
  곧"). `DEB2:`가 나가도 한동안은 `DEB1:`을 계속 받고, 라이브러리를 빼는 날 `DEB1:`은 애드온 안에서
  풀리지 않게 된다. Clique의 `CL01:` 받기도 같은 라이브러리에 기대므로 그날 함께 없어진다
  (`importing-clique-profiles.md` §1). `CL02:`는 처음부터 `C_EncodingUtil`로 풀고 있어 그대로다.
  - 빼는 이유: 두 파일이 204KB로 `DebindStorage` 344KB의 절반을 넘는다. 그리고 모두가 새 버전을 쓰게
    되면 옛 문자열 하나를 받자고 모든 사용자가 쓰지 않는 의존을 계속 지고 있어야 한다(소유자).
- **보관함에 쌓인 항목은 영향이 없다.** `DebindStorageVars`에는 문자열이 아니라 페이로드 테이블이
  들어 있다.
- **CBOR은 키의 타입까지 그대로 되돌려준다** (2026-09-27, 12.1.5.69952, `Probe_CBOR.lua`). 직렬화,
  압축, base64를 거쳐 되돌린 14가지가 모두 같았다. `[0]`, 중간이 빈 전문화 표(0·1·2·5, 1·2·5), 한 표에
  같이 있는 `1`과 `"1"`, 빈 표, 구멍 난 배열, 음수와 소수 키, 1절의 `layers` 모양이 들었다. 카멜롯
  클라이언트는 아직 재지 않았다.

## 2. 왜 이 모양인가

**캐릭터 레이어가 제 직업을 주소로 든다.** 위 1번 문제가 여기서 끝난다. 표시(이름표와 직업 색)도,
넣을 자리를 정하는 것도 칸만 보고 한다.

**다른 직업의 캐릭터 레이어를 번호로 남의 전문화에 넣지 않게 된다.** 지금 `ImportAddress`의 캐릭터
분기는 직업을 안 보고 번호만으로 이 캐릭터의 같은 번호 전문화에 넣는다. 마법사의 캐릭터 / 2번을
드루이드가 받으면 드루이드 2번에 들어간다. 직업이 다르면 가져오지 않고 그렇다고 알린다(소유자).
이것은 지금 포맷에서도 `payload.class`로 할 수 있는 일이지만, 새 모양에서는 주소가 답한다.

**전체 백업이 그냥 복사다.** 계정 칸과 모든 캐릭터 칸이 한 테이블에 같은 모양으로 있으니, 내보내기가
번역 없이 `layers`를 옮긴다.

**버린 안과 그 이유.**

- **전문화 ID를 키로 쓰는 평평한 칸** (`account = { MAGE = {...}, [63] = {...}, GENERAL = {...} }`).
  ID는 그 자체로 직업을 말하므로 직업 한 겹이 없어도 칸이 스스로를 설명한다. 버린 이유는 흔드는
  범위다. 게임이 지금 전문화를 인덱스로 알려 주고, `LAYER_INFOS`, `LoadLayer`, 발동 순서의 `specRank`가
  모두 인덱스를 쓴다. ID로 가면 그 자리마다 변환이 끼고, 순서를 바꾸지 말라는 경고가 붙은
  `Ordering.lua`까지 닿는다. 카멜롯은 직업마다 전문화가 하나라 정식 서비스의 ID 대부분이 그 클라이언트의
  표에 없다는 것도 있다. 인덱스와 ID는 어느 직업이든 언제든 서로 바꿀 수 있으니
  (`GetSpecializationInfoForClassID`), 필요해지면 저장 모양을 안 바꾸고 표로 해결된다.
  - 다시 열 조건: 전문화 번호의 뜻이 바뀌는 패치(순서가 바뀌거나 전문화가 추가되어 번호가 밀리는 것).
    그때는 인덱스로 저장한 것 전부가 남의 전문화를 가리키게 된다.
- **캐릭터 칸을 직업으로 묶기** (`char.MAGE[2]`). 같은 직업 캐릭터가 둘이면 한 자리를 나눠 쓰게 되어
  백업에서 한쪽이 덮인다. 캐릭터 레이어의 단위는 직업이 아니라 캐릭터다.
- **캐릭터 칸의 키를 "캐릭터-서버"로.** 사람이 읽을 수 있지만 이름을 바꾸면 키가 어긋난다. 키는
  guid로 두고 읽을 이름은 `characters[guid]`에서 꺼낸다(소유자). guid도 서버 이전을 하면 바뀌는데,
  그때 짝을 맞출 근거도 같은 칸의 이름과 직업이다.
- **포맷은 두고 `payload.class`로만 막기.** 1번의 표시 문제와 직업 확인은 이것으로 된다. 2번의
  백업은 안 된다.

## 3. 닿는 곳

지금 코드에서 저장 모양을 직접 짚는 자리다. 이름은 이 문서를 쓴 날의 것이다.

**Debind (저장 데이터)**

- `Profile.lua`: `LoadLayer`(레이어를 저장 테이블에 물리는 곳), `InitDB`(`shared`, `characters`,
  `charEntry.layers`를 세우는 곳), `CleanUpDB`와 `HasCharContent`(캐릭터 칸을 붙이고 떼는 곳),
  `ForEachStoredAction`, `StoredActionsAt`(가져오기가 남의 좌표에 쓰는 곳), 모든 저장 액션을 훑어
  목록을 만드는 곳(`walkLayer`로 `shared`와 `characters`를 도는 함수), `LAYER_INFOS`.
- `Profile.lua`의 `StandDown`: 더 새 프로필을 만나 물러설 때 옛 모양의 db를 손으로 세운다.
- `Profile.lua`의 스위치 쪽: `BindDerivedTables`(`db.switches`를 `DebindPrivate.Switches`로 묶는 곳),
  `db.char.switches`를 읽고 쓰는 자리들, 그리고 오버라이드: `GetSwitchLayerKey`와 그 키로
  `definition.overrides`를 읽고 쓰는 자리들(`ResolveSwitchAnswer`, 행을 만들고 지우는 함수, 이름 바꾸기와
  지우기).
- `SwitchesUI.lua`: `GetSwitchLayerKey`로 오버라이드 행을 찾고 그리는 곳.
- `UnitWatch.lua`: `LoadCustomTargets`와 저장하는 콜백이 `db.char.CustomTargets`를 직접 읽고 쓴다.
- `Events.lua`: `RefreshIdentity`가 `db.char`에 신원을 쓴다. 지금 `db.char`는 레이어, 스위치 값, 신원이
  한 테이블이라, 새 모양에서는 이것이 무엇을 가리키는지부터 다시 정한다.
- `Migration.lua`: `MigrateDB`, `MigrateShared`, `MigrateSpecTable`, `MigrateSwitches`(오버라이드를 도는
  자리 포함). 옮기는 단계가 여기 들어간다.
- `Legacy.lua`: 개명 전 SavedVariables를 옮겨 오는 곳이 `shared.GENERAL`, `shared.classes`,
  `charEntry.layers`에 직접 쓴다. 이 이전은 캐릭터마다 그 캐릭터로 접속할 때 돈다. PLAYER_LOGIN에서
  돌아 `MigrateDB`(ADDON_LOADED)보다 늦고, 지금은 사다리의 단계를 하나씩 골라 부른다(`MigrateLayer`,
  `MigrateSwitches`, `MigrateOptions`). 4절 1단계가 이것을 사다리 전체를 타게 바꾼다.
- `Constants.lua`: `DB_VERSION`.
- `Debind.toc`: `## SavedVariables`에 `DebindUIVars`를 더한다.
- `DebindUI.lua`(창 위치, `binSort`), `SpellPicker.lua`(위치와 필터), `Help/HelpTip.lua`(`tipsSeen`):
  `db.global.ui`, `db.global.spellPicker`, `db.global.tipsSeen`을 짚는 자리가 `DebindUIVars`로 간다.

**DebindStorage (페이로드)**

- `Export.lua`: `SCHEMA_VERSION`, `BucketAt`, `BucketForLayer`, `BuildExportPayload`, `FilterPayload`,
  `BringPayloadForward`(여기에 v2를 새 모양으로 올리는 단계가 들어간다).
- `Import.lua`: `ForEachPayloadLayer`, `ImportAddress`, `PayloadIsImpossible`, 항목에서 액션을 지우는
  곳(`payload.shared.GENERAL = nil` 등).
- `Clique.lua`: `PayloadFromCliqueBindings`가 `shared.GENERAL`을 직접 만든다.
- `DebindStorageVars`에 이미 쌓인 항목들은 v2 페이로드다. 항목을 열 때 `BringPayloadForward`를
  거치므로 따로 옮기지 않아도 거기서 올라온다.

**화면**

- `StorageUI.lua`: `EntryClass`(왼쪽 행의 보낸 사람 직업), `BuildPreviewLayers`(레이어 헤더 이름표).
  둘 다 `payload.class`를 읽는다.

**테스트**

- 헤드리스: `tests/`의 `export_spec`, `import_spec`, `entry_spec`, `clique_spec`, `migration_spec`,
  `keygroup_spec`, `switch_spec`, `automatics_spec`.
- 인게임 킷: `DebindDev/DebindTest.lua`가 페이로드의 `shared`, `char`를 직접 짚는 자리가 있고,
  `db.char.switches`를 직접 짚는 자리가 열한 군데다.

## 4. 순서

1. **저장 데이터의 모양만 바꾼다.** `dbver`를 올리고 옮기는 단계를 넣고, 저장 모양을 짚는 자리를
   모두 새 모양으로 바꾼다. 화면에 보이는 것은 아무것도 안 바뀌어야 하고, 헤드리스 전부와 옮기기
   전후의 발동 순서가 같다는 것이 이 단계의 합격선이다.
   - **Legacy는 사다리를 통째로 탄다** (소유자). 옛 `DebounceVars`와 `DebounceVarsPerChar`를 개명
     당시의 `DebindVars` 모양(`shared`, `characters[guid]`)으로만 옮겨 옛 `dbver`를 찍은 임시 테이블에
     담고, 거기에 `MigrateDB`를 돌린 뒤 결과를 붙인다. 그러면 Legacy가 아는 모양은 개명 당시로 고정되고,
     이번을 포함한 앞으로의 모양 변경은 사다리 한 곳에만 들어간다. 단계를 하나씩 골라 부르는 지금 방식은
     모양이 바뀔 때마다 빠진 단계를 메워야 했다(`Legacy.lua`의 `MigrateSwitches`, `MigrateOptions` 호출이
     그렇게 들어왔다).
   - 모양을 아는 것은 붙이는 자리 하나만 남는다. 계정 몫은 옮겨진 최상위 키를 그대로 덮는다. 답하기
     전에는 창이 안 열리므로 덮일 사용자 설정이 없다. 캐릭터 몫은 각 표의 `[guid]` 칸만 옮긴다. 계정 몫이
     먼저 넘어온 뒤 다른 캐릭터로 접속해서 돌기 때문이다.
   - 기억한 스위치 값과 `CustomTargets`를 `Profile.lua`의 함수로 돌리는 것도 이 단계다. `UnitWatch.lua`와
     `DebindTest.lua`가 모양을 모르게 된다.
   - **같은 단계에서 치운다** (소유자, 리팩터링은 dbver를 올릴 때 같이). 아래는 읽는 코드가 없거나
     로그인마다 다시 계산되는 값이라 지워도 동작이 안 바뀐다. 2026-09-27에 SavedVariables 세 벌
     (`_retail_` 하나, `_xptr_` 둘)을 열어 확인했다.
     - 최상위 `global`, `char`, `class`, `profileKeys`: `_retail_` 파일에 있다. 이 저장소의 어느 커밋도 쓴
       적이 없고, Legacy가 옛 `DebounceVars`의 나머지 키를 그대로 복사하면서 따라 들어온 것으로 보인다.
       Legacy가 개명 당시 모양으로 옮기도록 바꿀 때 이 키들은 건넌다.
     - 최상위 `unitFrameNoticeSeen`.
     - `options`의 `overviewui`, `stateDriverUpdateThrottle`, `removeStateDriverUpdateThrottle`,
       `addCustomTargetMenusOnUnitPopup`, `addCustomTargetMenusToUnitPopup`, 그리고 dbver 7 파일에 남은
       `blizzframes`(`MigrateOptions`가 `frameBlacklist`로 옮기는 옛 이름).
     - 스위치 정의의 `value`(1절)와 `displayMessage`.
     - 레이어 배열 안의 `customStates = {}`처럼 액션이 아닌 키. 옮길 때 액션 표가 아닌 것은 버린다.
   - **`tipsSeen`만 `DebindUIVars`로 옮기고, `ui`와 `spellPicker`는 지운다** (1절, `tipsSeen` 말고는
     비워도 되는 값이다).
1-2. **뒷정리** (소유자, 2단계보다 먼저). 같은 `dbver <= 7` 단계에 넣는다.
   - **캐릭터 상태를 `states[guid]`로 뗀다** (1절 `characters`). 기억한 스위치 값과 `CustomTargets`가
     옮겨 간다. 읽고 쓰는 문은 이미 `Profile.lua`의 `GetRememberedSwitch`, `SetRememberedSwitch`,
     `GetSavedCustomTarget`, `SaveCustomTarget`이다. 안에서 `db.char`를 짚는 자리(`SetSwitchValue`,
     `ApplySwitchResets`, 이름 바꾸기와 지우기, `HasCharContent`, `MigrateSwitches`의 값 옮기기,
     `Legacy.lua`의 `CustomTargets`)와 `CleanUpDB`의 붙이고 떼는 규칙이 바뀐다.
   - **스위치를 "state"라고 부르는 이름을 `switch`로 바꾼다** (소유자). 이름 한 번 바꾸는 비용보다
     뒤의 세션들이 매번 헷갈림을 피해 가는 비용이 크다. 크기는 `States` 약 340곳, `SETSTATE` 약
     160곳, `customStates` 약 20곳이다.
     - **코드 이름**: `STATE_FIELDS`, `stateName` 같은 지역 이름, 스니펫의 `arg.state`, 주석의
       "custom state". 제한 환경 쪽은 스니펫 골든이 바뀌므로 `restricted-environment.md`를 따른다.
     - **제한 환경의 `States` 표는 그대로다** (소유자, 2026-09-27). 스위치만의 표가 아니라
       `States.combat`, `States.unitframe` 같은 게임 상태를 함께 들고, 스위치 값은 그 옆에 앉을 뿐이다.
       스위치만 드는 표는 이미 `ClickSwitches`, `ComputedSwitches`, `SwitchEntries`다.
     - **저장된 액션 타입 문자열** `"setstate_on"`, `"setstate_off"`, `"setstate_toggle"`도 이번 단계에서
       옮긴다 (소유자, 2026-09-27). 따로 두면 저장값을 옮기는 단계가 나중에 한 번 더 생긴다. v2 공유
       문자열의 액션도 `MigrateLayer`를 타니 같이 풀린다.
     - **클릭 대상 프레임 `DebindStates`도 `DebindSwitch`로 바꾼다** (소유자, 이름은 2026-09-27).
       복수형 `DebindSwitches`는 값을 모아 둔 표처럼 읽히고 정의 모음 `DebindPrivate.Switches`와도
       겹친다. 매크로 한 줄은 스위치 하나를 누르므로 단수다. 뒤에 `Button`은 붙이지 않는다. `/click`의
       대상은 늘 버튼이라 알려 주는 것이 없고, 이 이름은 액션마다 255자 제한인 매크로 본문에 들어간다. [매크로로 바꾸기]가 켜기/끄기/전환 액션을
       `/click DebindStates $burst-on`으로 펴서 액션의 매크로 본문에 써 넣으므로, 옮기는 단계가
       `MigrateLayer`에서 그 본문을 새 이름으로 고쳐 쓴다(v2 공유 문자열도 같이 풀린다). 개명 때
       `Legacy.lua`의 `RepairLegacyClickTargets`가 `DebounceStates`를 같은 방식으로 고쳤다. 사다리가
       닿지 않는 곳, 곧 사용자가 그 줄을 게임의 매크로 창으로 옮겨 적은 것은 고칠 수 없다. **옛 이름을
       받아 주는 별칭 프레임은 두지 않는다** (소유자, 2026-09-27). 개명 때 `DebounceStates`에도 두지
       않았다.
     - **바꾸지 않는 것**: 옛 데이터의 실제 키라서 사다리 단계 안에만 남는 `customStates`와 v2 페이로드의
       `states`. 옛 `setstate` 비트팩 타입과 v1 선의 `setstate` 서브테이블도 같은 이유로 남는다.
       **v2의 `payload.states`는 지금도 내보내는 필드라** 2단계가 `switches`로 바꿀 때까지 선에 남고,
       안에서 쓰는 이름(`SWITCH_FIELDS`, `BuildSwitchManifest`)만 바꿨다.
   - **구현하며 정한 것** (2026-09-27).
     - **타입 이름은 `SETSWITCH_ON`/`_OFF`/`_TOGGLE`, 저장값은 `"setswitch_on"` 등.** 제한 환경의
       `SetSwitch`와 같은 말이고, `SWITCH_MODES`는 이미 수동/계산식이 쓰고 있어서 `SETSWITCH_MODES`로
       둔다. 로케일 키는 타입에서 조립되므로(`"TYPE_" .. strupper(type)`) `TYPE_SETSWITCH_*`로 같이 간다.
     - **목록에 없던 것도 같은 기준으로 바꿨다.** `BINDING_ISSUE_UNDEFINED_STATE`와 그 값(오류 문구 키가
       `"BINDING_ERROR_" .. 코드`로 조립되므로 로케일 키도 같이), 이슈 분류 `states`, 로케일 키
       `CUSTOM_STATE*`와 `STATE_CHANGED_MESSAGE*`, 솔버의 스위치 축 상수, 스니펫의 `arg.state`와 `t.state`.
     - **단계는 자기 판에서 다음 판으로 가는 일만 한다** (소유자). 한 판 안에서는 이름도 모양도 하나다.
       - **`MigrateDB`는 모든 사다리를 한 판씩 함께 올린다.** 판마다 칸(`MigrateContainers`), 액션
         (`MigrateLayer`), 정의(`MigrateSwitches`), 나머지 계정 표(`MigrateAccount`) 순서로 그 판의
         단계만 돌리고 다음 판으로 간다. 단계 머리는 `if (dbver <= N and N < to) then`이고
         `check:dbver`가 두 N이 같은지까지 본다. 전에는 사다리마다 끝까지 돌려서, 5에서 6의 정의
         단계가 8의 칸(`db.layers`)과 8의 타입 이름을 읽고 있었다. 액션 목록은 `ForEachActionList`가
         그 판의 칸 모양대로 찾는다.
       - `states`로 옮기는 것은 7에서 8의 일이라 `MigrateAccount`의 `dbver <= 7` 단계에 있다.
       - 옛 타입 비트팩을 푸는 `dbver <= 5` 단계와 v1 어댑터는 6의 이름(`"setstate_on"` 등)을 문자
         그대로 쓰고, 8의 이름으로 바꾸는 것은 `dbver <= 7` 단계가 한다.
     - **5까지 계정에 하나 있던 기억한 값은 버린다** (소유자, 2026-09-27, "주지마"). 6부터는 캐릭터가
       제 값을 기억하는데, 그 하나가 어느 캐릭터의 것이었는지는 데이터에 없다. 전에는 항목이 있는
       캐릭터 모두에게 나눠 주느라 이 단계가 `db.characters`와 접속 중인 캐릭터를 알아야 했고,
       항목이 없으면 사다리 안에서 직업 없는 항목을 붙였다. 값은 버리기 전에 "눌러 본 적 있다"는
       증거로만 읽어 정의를 걷어낼지 정한다. `MigrateDB`는 캐릭터를 받지 않는다.
     - **스위치 프레임을 누르는 경로는 헤드리스가 잰다** (`clickswitch_spec`). 킷에서 `Click()`으로 재려던
       두 테스트는 게임에서 실패했는데, 기능이 아니라 측정이 틀렸다. 애드온 코드의 `Click()`은
       테인트된 실행이라 `CallRestrictedClosure`가 `_onclick`과 감싼 `OnClick`의 몸통을 돌리지 않는다.
       매크로의 `/click`은 보안 실행이라 여기 걸리지 않는다. 헤드리스 제한 환경에 없던 `strsplit`를
       넣었다.
     - **개명 전 데이터의 3에서 4는 `Legacy.lua`의 가져오기가 겸한다.** 3.1의 사다리에 그 단계가
       없었다. 그래서 가져오기는 옛 파일의 복사본을 개명 당시 이름(`DebindStates`, `DebindCustom`)으로
       고친 뒤 사다리에 넣고, 이번 단계는 `DebindStates`를 `DebindSwitch`로 바꾸는 일만 한다. 전에는
       사다리 뒤에 고쳐서 `dbver <= 6` 단계가 개명 전 이름까지 느슨하게 맞췄고, 그 우회는 걷었다.
     - **가져오기는 옛 파일만으로 된 프로필을 올리고, 현재 표와는 사다리 뒤에 합친다.** 전에는 현재
       `characters`를 옛 판 프로필에 끼워 넣어 `dbver <= 5` 단계가 "이미 있는 값이 이긴다"를 들고
       있었다. 계정 몫의 기억한 값을 버리면서 그 규칙도 필요 없어졌다.
2. **페이로드를 같은 모양으로 올린다.** `SCHEMA_VERSION` 3, v2를 올리는 단계, `payload.class` 제거,
   다른 직업의 캐릭터 칸을 가져오지 않는 것.
3. **전체 백업.** 5절의 물음에 답이 나온 뒤.

2의 앞에는 1-2절의 측정이 선다. 정식 서비스는 쟀고, 카멜롯이 남았다. **1과 2는 한 릴리스로 나간다** (소유자). 1은 페이로드 없이도 설 수 있지만(보관함 애드온은
저장 테이블을 직접 짚지 않고 `EnumerateAllProfileLayers`, `ResolveSwitchDefinition`, `PlaceArrivedActions`만
거친다), 1만 나가면 `DB_VERSION`이 올라 새 문자열이 `dbver = 8`을 달고, 업데이트 안 한 사람의 애드온은 액션
모양이 같은데도 그것을 `UNSUPPORTED_SCHEMA`로 거절한다. 나눠 내면 그 거절을 두 번 겪는다.

## 5. 정할 것

- **Legacy의 세 값을 묶을지.** `legacyNeeded`, `legacyAccountPulled`, `migrated`를 `legacy = { ... }`
  하나로. 동작은 안 바뀌고 모양의 취향이다.
- **백업을 되돌릴 때 캐릭터 칸을 누구에게 넣나.** guid가 맞으면 그 캐릭터다. 서버 이전 등으로 안
  맞을 때 사람이 고르는 화면이 필요한지.
- **v2 문자열의 캐릭터 레이어.** 올릴 때 `payload.class`를 그 칸의 직업으로 쓴다. `payload.class`가
  없는 v2(손으로 고친 문자열만 해당)의 캐릭터 레이어를 버릴지, 둘 자리 없음으로 보여 줄지.
- **`"*"` 칸을 추가할 때 전문화 번호가 이 직업에 없으면.** BindPad의 4번 프로필을 전문화가 셋인
  직업이 받는 경우다. 지금 `ImportAddress`처럼 둘 자리 없음으로 둘지.
- **공유용에서 캐릭터 칸을 고를 때 보여 줄 것.** 이름은 실을 수 없다. 직업과 레벨처럼 신원이 드러나지
  않는 값만 `characters`에 싣는 안과, 보내는 사람이 붙인 이름표를 싣는 안이 있다.
- **라이브러리를 뺀 뒤 옛 `DEB1:`을 가진 사람에게 무엇을 주나.** 그때부터 애드온은 `DEB1:`을 못
  푼다(1-2절). 웹 페이지로
  `DEB1:`을 `DEB2:`로 바꾸는 도구를 낼 수는 있다. 두 포맷 모두 공개되어 있고, 도구는 포장만 바꾸고
  페이로드는 v2 그대로 싸서 v3로 올리는 일을 애드온에 맡기면 된다. 낼지, `DEB2:`의 `CompressString`이
  무엇으로 싸는지 잰 뒤에 정한다.
- **저장 탭의 왼쪽 행이 보여 줄 보낸 사람.** 지금은 `payload.class` 하나다. 백업처럼 직업이 여럿인
  항목이 생기면 무엇을 보여 줄지.
