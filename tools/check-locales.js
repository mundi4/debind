// 로케일 파일들이 enUS와 같은 키 집합을 갖고 있는지 확인한다.
//   npm run check:locales
//
// 이걸 만든 이유: 빠진 키는 **조용히** 나간다. locales의 __index가 키를 그대로 돌려주므로
// 오류 한 줄 없이 화면에 `ORDER_DESC`라는 글자가 뜬다. 러시아어 사용자는 실제로 순서 패널의
// 설명 줄 자리에서 그걸 보고 있었다 (7f16906이 enUS에만 키를 넣었다).
//
// resolved.md의 "ruRU를 따라잡았다"는 한 번 손으로 맞춘 것이라 다음 커밋에서 다시 벌어졌다.
// 사람이 기억해야 하는 규칙은 규칙이 아니므로 검사로 내린다.
//
// 네트워크를 안 쓰므로 check-templates와 달리 언제 돌려도 된다.

const fs = require("fs");
const path = require("path");

const localesDir = path.join(__dirname, "..", "Debind", "Locales");
const BASE = "enUS";

// enUS에는 있는데 다른 로케일에는 **없는 게 맞는** 키. 넣을 때는 왜 정상인지 한 줄 남길 것.
const ALLOWED_MISSING = {
    // enUS는 클라이언트 전역 NOT_BOUND를 담는다. 다른 로케일에서는 그 전역이 이미
    // 제 나라 말이라 따로 번역할 것이 없다.
    OVERVIEW_NO_KEY: ["koKR", "ruRU"],
    // 같은 이유. 클라이언트 전역 ESCAPE_TO_UNBIND를 그대로 받는다.
    BIND_MODE_UNBIND_HINT: ["koKR", "ruRU"],
};

// **번역을 기다리는 중인 키.** 위와 갈라 둔다 - 저쪽은 영영 없는 게 맞는 키이고, 이쪽은
// 번역자가 손대면 지워져야 하는 빚이다. 한 통에 담으면 둘을 구별할 방법이 없어서, 아무도
// 이 목록을 줄이지 않게 된다.
//
// 없는 동안 화면에 나오는 것은 키 이름이 아니라 **영어**다. locales.xml이 enUS를 먼저
// 읽고 각 로케일이 같은 테이블을 덮어쓰는 구조라, 안 덮은 자리에는 enUS가 남는다.
const PENDING_TRANSLATION = {
    // 레이어 툴팁(3.1). 러시아어는 ZamestoTV 담당이다.
    TAB_DESC_SHARED: ["ruRU"],
    TAB_DESC_CHARACTER: ["ruRU"],
    LAYER_DESC_SHARED_GENERAL: ["ruRU"],
    LAYER_DESC_SHARED_CLASS: ["ruRU"],
    LAYER_DESC_SHARED_SPEC: ["ruRU"],
    LAYER_DESC_CHARACTER_GENERAL: ["ruRU"],
    LAYER_DESC_CHARACTER_SPEC: ["ruRU"],
    // The life axis on unit conditions. Same owner as the rows above.
    CONDITION_LIFE: ["ruRU"],
    LIFE_ALL: ["ruRU"],
    LIFE_ALIVE: ["ruRU"],
    LIFE_DEAD: ["ruRU"],
};

// **base보다 자리표시자를 더 쓰는 게 맞는 키.** 부르는 쪽이 이미 그 인자를 넘기고 있고
// base 쪽이 안 받고 있을 뿐인 경우다 - Lua의 `format()`은 남는 인자를 그냥 버리므로 터지지
// 않는다. 터지는 것은 반대 방향(인자가 모자란 쪽)뿐이라 그건 계속 잡는다.
//
// 언어마다 갈리는 자리라 실재한다: 영어는 툴팁 제목이 이미 말한 것을 "this spec"으로 가리킬
// 수 있는데, 한국어는 그 자리에 이름을 넣어야 문장이 선다.
//
// 값은 그 로케일이 **써도 되는 자리표시자 전부**다. "봐준다"가 아니라 base 대신 이걸로
// 맞춰 본다 - base가 자리표시자를 하나도 안 쓰면 견줄 앞부분이 없어서, 그냥 봐주면 `%d`로
// 잘못 적은 것까지 통과한다(그건 문자열을 넣는 순간 진짜로 터진다).
//
// 넣을 때는 **어느 호출부가 그 인자를 넘기는지** 한 줄 남길 것.
const EXTRA_SPECS_OK = {
    // DebindUI.lua의 GetSideTabDescription이 (지는 레이어, 전문화명) 둘을 언제나 넘긴다.
    // enUS는 전문화명을 안 쓰고 "in this spec"으로 대신하므로 1번 하나로 끝나는데(`%s`),
    // 한국어는 둘 다 쓰면서 차례가 반대라 번호를 붙인다.
    LAYER_DESC_CHARACTER_SPEC: { koKR: "%2$s%1$s" },
};

// `L["KEY"] = ...` 형태만 센다. 주석(`-- L["X"]`)은 안 잡히도록 줄 앞을 고정한다.
const ASSIGN = /^L\["([^"]+)"\]\s*=\s*(.*)$/gm;

// **키가 맞아도 서식이 어긋나면 그 줄은 터진다.** 빠진 키와 달리 조용하지도 않다 -
// `format()`이 인자를 못 찾으면 그 자리에서 Lua 오류가 나고, 번역한 사람은 자기 클라이언트로
// 그 화면을 열어본 적이 없다. koKR을 통째로 넣으면서(3.1) 손으로 대조하던 것을 검사로 내린다.
//
// `%%`는 리터럴 퍼센트라 인자를 안 먹으므로 센 다음 뺀다.
const SPEC = /%(\d+\$)?[-+ #0]*\d*(\.\d+)?[sdfxXqcieg%]/g;

function readKeys(file) {
    const src = fs.readFileSync(file, "utf8");
    const keys = new Set();
    const dupes = [];
    const specs = new Map();
    for (const m of src.matchAll(ASSIGN)) {
        if (keys.has(m[1])) {
            dupes.push(m[1]);
        }
        keys.add(m[1]);
        specs.set(m[1], (m[2].match(SPEC) || []).filter((s) => s !== "%%"));
    }
    return { keys, dupes, specs };
}

const files = fs.readdirSync(localesDir).filter((f) => f.endsWith(".lua"));
const base = readKeys(path.join(localesDir, `${BASE}.lua`));

let failed = false;

if (base.dupes.length > 0) {
    failed = true;
    console.log(`${BASE}: 중복 키 ${base.dupes.length}개 - ${base.dupes.join(", ")}`);
}

for (const file of files) {
    const locale = path.basename(file, ".lua");
    if (locale === BASE) {
        continue;
    }

    const { keys, dupes, specs } = readKeys(path.join(localesDir, file));

    // 순서까지 본다. 자리표시자 둘이 뒤집힌 번역은 오류 없이 **틀린 값을 두 자리에 꽂는다**
    // (`ORDER_WHY_LAYER`의 "%s over %s"가 그런 모양이다). `%1$s`를 쓸 생각이면 여기가 아니라
    // enUS부터 그렇게 쓸 것 - 한쪽만 번호를 붙이면 그것도 어긋남으로 잡힌다.
    const badSpecs = [...base.specs]
        .filter(([k]) => keys.has(k))
        .map(([k, want]) => [k, (EXTRA_SPECS_OK[k] || {})[locale] ?? want.join(""), specs.get(k).join("")])
        .filter(([, want, got]) => want !== got);

    const absent = [...base.keys].filter((k) => !keys.has(k));
    const missing = absent
        .filter((k) => !(ALLOWED_MISSING[k] || []).includes(locale))
        .filter((k) => !(PENDING_TRANSLATION[k] || []).includes(locale))
        .sort();
    // 봐준 것은 **세어서 말한다.** 조용히 넘기면 목록이 늘기만 한다.
    const pending = absent.filter((k) => (PENDING_TRANSLATION[k] || []).includes(locale)).sort();
    // enUS에 없는 키는 **지워진 문자열의 잔재**다. 화면에 안 나오므로 무해해 보이지만,
    // 다음 사람이 그게 아직 쓰이는 줄 알고 손본다.
    const stale = [...keys].filter((k) => !base.keys.has(k)).sort();

    if (dupes.length > 0) {
        failed = true;
        console.log(`${locale}: 중복 키 ${dupes.length}개 - ${dupes.join(", ")}`);
    }
    if (missing.length > 0) {
        failed = true;
        console.log(`${locale}: ${BASE}에 있는데 빠진 키 ${missing.length}개`);
        for (const k of missing) {
            console.log(`  - ${k}`);
        }
    }
    if (stale.length > 0) {
        failed = true;
        console.log(`${locale}: ${BASE}에 없는 키 ${stale.length}개 (지워진 문자열의 잔재)`);
        for (const k of stale) {
            console.log(`  - ${k}`);
        }
    }
    if (badSpecs.length > 0) {
        failed = true;
        console.log(`${locale}: 서식 지정자가 어긋나는 키 ${badSpecs.length}개`);
        // 기대값이 늘 `${BASE}`인 것은 아니다 - EXTRA_SPECS_OK가 걸린 키는 거기 적힌 값이다.
        for (const [k, want, got] of badSpecs) {
            console.log(`  - ${k}: 기대값 [${want || "없음"}], 여기는 [${got || "없음"}]`);
        }
    }
    if (pending.length > 0) {
        console.log(`${locale}: 번역 대기 ${pending.length}개 (그동안 ${BASE}로 나간다) - ${pending.join(", ")}`);
    }
    if (missing.length === 0 && stale.length === 0 && dupes.length === 0 && badSpecs.length === 0) {
        console.log(`${locale}: 키 ${keys.size}개, 서식까지 ${BASE}와 일치.`);
    }
}

if (failed) {
    process.exitCode = 1;
} else {
    console.log(`전부 ${BASE}(${base.keys.size}개)와 같은 키 집합이다.`);
}
