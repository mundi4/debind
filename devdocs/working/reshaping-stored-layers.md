# 저장된 레이어 모양 바꾸기 (2026-09-27 시작)

> 상태: **계획. 코드는 아직 한 줄도 안 바뀌었다.** 모양(1절)과 그 이유(2절)는 소유자와 정했다.
> 5절의 물음들은 아직 답이 없다.
>
> 쓴 세션: `debind-43`, 세션 ID `8661be18-b7a9-47ca-9014-f4260da6eec7`.

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
        account = { burst = { ...정의... }, aoe = { ... } },
        ["Player-3041-0A1B2C3D"] = { burst = true },
    },
    characters = {
        ["Player-3041-0A1B2C3D"] = {
            name, realm, class, race, sex, level, faction, firstSeen, lastSeen, origin,
        },
    },
    -- CustomTargets도 characters를 떠나 guid로 묶인 형제 표가 된다(이름은 5절)
    -- dbver, options, ui, tipsSeen, migrated, ... 그대로
}
```

- **레이어는 `layers` 한 곳에 모인다.** 계정 칸(`account`)과 캐릭터 칸(`[guid]`)이 같은 모양이다. 칸
  안의 키는 직업이고, 그 밑은 `{ [0] = 직업 전체, [1..4] = 전문화 }`다. 공유 일반은 직업이 아니므로
  같은 모양의 칸 `GENERAL`을 하나 따로 두고 `[0]`만 쓴다.
- **전문화 키는 인덱스 그대로다.** `LAYER_INFOS`의 `spec`, `GetSpecialization()`, 발동 순서의
  `specRank`가 모두 이 번호를 쓴다.
- **캐릭터 칸은 직업 키를 늘 하나만 가진다.** 캐릭터의 직업은 바뀌지 않는다. 그 한 겹은 정보가 아니라
  계정 칸과 모양을 맞추는 값이고, 그 덕에 칸 하나만 떼어 놓아도 누구의 전문화인지가 읽힌다.
- **스위치도 `layers`의 형제로, 같은 규칙으로 둔다** (소유자). 계정 칸은 지금의 `db.switches`(정의),
  캐릭터 칸은 지금의 `characters[guid].switches`(그 캐릭터가 기억한 값)다. 두 칸이 담는 것의 종류는
  다르지만 "계정 것은 `account`, 캐릭터 것은 guid"라는 읽는 규칙은 같다.
- **`characters`는 표시용 메타데이터일 뿐이다** (소유자). `RefreshIdentity`가 3.1부터 로그인마다 쓰는
  값들이고, 사람에게 누구의 칸인지 보여 주는 데만 쓴다. **동작을 정하는 코드는 이것을 읽지 않는다.**
  캐릭터 칸의 직업도 `characters[guid].class`가 아니라 `layers[guid]`의 키가 답한다. 그래서 여기 있을 수
  있는 것은 신원뿐이고, 켜고 끌 때마다 바뀌는 스위치 값이나 `CustomTargets` 같은 상태는 들어오지 않는다.
  - 예외는 옮기는 단계 한 번이다. `layers[guid]`의 직업 키를 세우려면 `characters[guid].class`를
    읽을 수밖에 없다. 옮긴 뒤로는 읽지 않는다.

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
    states = { ... },   -- 지금과 같다
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
    characters = {
        ["Player-3041-0A1B2C3D"] = { name = ..., realm = ..., class = "MAGE" },
        ["Player-3041-0B2C3D4E"] = { name = ..., realm = ..., class = "DRUID" },
    },
    states = { ... },
}
```

- **두 용도가 모양 하나를 쓴다.** 가르는 것은 캐릭터 칸의 키와 거기 딸린 신원뿐이다. 읽는 코드는
  `layers`를 도는 한 갈래이고, `account`가 아닌 키는 모두 캐릭터 칸이다.
- **공유용의 캐릭터 칸 키는 그 문자열 안에서만 겹치지 않으면 된다** (소유자). `"1"`, `"2"`처럼 쓰고,
  숫자 키여도 된다. 다만 숫자 키가 그대로 돌아오는 것은 1-2절의 CBOR을 잰 뒤에 확정된다. 받는 쪽은 칸을 골라 제 guid 자리에
  넣으므로 키는 거기서 버려진다. guid도 캐릭터를 가리키는 식별자라 공유
  문자열에 싣지 않는다는 원칙(`building-export-import.md` 3절)이 그대로 선다. 공유 문자열에도 캐릭터가
  여럿 들어갈 수 있어야 해서 번호다. 고정된 `character`는 칸이 하나일 때만 맞고, `character-1`처럼
  읽히는 이름은 얻는 것이 없다. guid(`Player-`로 시작)와 겹칠 일이 없고 사람이 열어 볼 일도 없다.
  배열로 바꾸지 않고 키를 쓰는 것은 칸의 모양을 저장 데이터와 같게 두어 읽는 길을 하나로 두기
  위해서다.
- **받는 쪽은 캐릭터 칸 중 하나를 골라 넣는다.** 받는 캐릭터는 하나다. 칸마다 직업이 키로 붙어 있으니
  다른 직업의 칸은 고를 수 없게 한다. 고르는 화면에 보여 줄 것은 5절.
- **`characters`는 캐릭터 칸의 신원이다.** 되돌릴 때 누구의 칸인지 보여 주고 짝을 맞추는 데 쓴다.
  공유용에는 넣지 않는다. `switches`, `CustomTargets`를 백업에 넣을지는 5절.
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
- `payload.class`를 지운다.

`DebindStorageVars`에 쌓인 v2 항목도 열 때 이 단계를 거친다.

### 1-2. 문자열 포장

**새 버전은 LibSerialize와 LibDeflate를 쓰지 않고 클라이언트의 `C_EncodingUtil`로 포장한다** (소유자).
`0-IDEAS.md`의 "공유 코드를 클라이언트 API로"가 여기로 자라 왔다.

- **CBOR이다.** `C_EncodingUtil`의 JSON은 표의 키를 전부 문자열로 만든다. 전문화 칸 `[0]`~`[4]`,
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
- **이 절이 서려면 먼저 재야 한다.** CBOR이 우리 페이로드(숫자 키 `[0]`, 숫자와 문자열이 섞인 키,
  빈 테이블, 중첩)를 두 클라이언트에서 그대로 되돌려주는지. 헤드리스로는 잴 수 없다.

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
- `Profile.lua`의 스위치 쪽: `BindDerivedTables`(`db.switches`를 `DebindPrivate.Switches`로 묶는 곳),
  `db.char.switches`를 읽고 쓰는 자리들.
- `Migration.lua`: `MigrateDB`, `MigrateShared`, `MigrateSpecTable`, `MigrateSwitches`. 옮기는 단계가
  여기 들어간다.
- `Legacy.lua`: 개명 전 SavedVariables를 옮겨 오는 곳이 `shared.GENERAL`, `shared.classes`,
  `charEntry.layers`에 직접 쓴다. 이 이전은 캐릭터마다 그 캐릭터로 접속할 때 돈다.
- `Constants.lua`: `DB_VERSION`.

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
- 인게임 킷: `DebindDev/DebindTest.lua`가 페이로드의 `shared`, `char`를 직접 짚는 자리가 있다.

## 4. 순서

1. **저장 데이터의 모양만 바꾼다.** `dbver`를 올리고 옮기는 단계를 넣고, 저장 모양을 짚는 자리를
   모두 새 모양으로 바꾼다. 화면에 보이는 것은 아무것도 안 바뀌어야 하고, 헤드리스 전부와 옮기기
   전후의 발동 순서가 같다는 것이 이 단계의 합격선이다.
2. **페이로드를 같은 모양으로 올린다.** `SCHEMA_VERSION` 3, v2를 올리는 단계, `payload.class` 제거,
   다른 직업의 캐릭터 칸을 가져오지 않는 것.
3. **전체 백업.** 5절의 물음에 답이 나온 뒤.

2의 앞에는 1-2절의 측정이 선다. 1과 2를 한 릴리스에 묶을지는 5절.

## 5. 정할 것

- **옮길 때 직업을 모르는 캐릭터 칸.** 3.1부터 로그인마다 `class`가 쓰이니 캐릭터 칸이 있는 캐릭터는
  모두 가진 값이어야 한다. 없는 칸이 실제로 있는지는 아직 안 봤다. 있으면 그 칸은 그 캐릭터로 접속할
  때 옮기는 안이 있다(`Legacy.lua`의 `migrated`와 같은 방식).
- **`layers[guid]`와 `characters[guid]`를 붙이고 떼는 규칙.** 지금은 캐릭터 칸에 내용이 생겨야
  붙이고(`CleanUpDB`), 비면 뗀다. 레이어가 떨어져 나가면 `HasCharContent`가 `layers[guid]`도 봐야 하고,
  레이어가 있는 캐릭터는 백업에서 이름을 보여 줘야 하니 신원 칸도 함께 있어야 한다.
- **`CustomTargets`의 형제 표 이름과 모양.** `characters`에서 나가는 것은 정해졌다(표시용이 아니다).
  `switches`처럼 `account` 칸도 두는지는 계정 단위로 기억할 값이 있느냐에 달렸다.
- **백업에 스위치를 어디까지 싣나.** 정의는 지금도 공유 문자열에 `states`로 실린다. 캐릭터가 기억한
  값(`switches[guid]`)과 `CustomTargets`를 백업에 넣을지. 레이어만 되돌리면 스위치를 조건으로 쓰는
  액션이 그 값 없이 돌아온다.
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
