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
        .map(([k, want]) => [k, want.join(""), specs.get(k).join("")])
        .filter(([, want, got]) => want !== got);

    const missing = [...base.keys]
        .filter((k) => !keys.has(k))
        .filter((k) => !(ALLOWED_MISSING[k] || []).includes(locale))
        .sort();
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
        console.log(`${locale}: 서식 지정자가 ${BASE}와 다른 키 ${badSpecs.length}개`);
        for (const [k, want, got] of badSpecs) {
            console.log(`  - ${k}: ${BASE}는 [${want || "없음"}], 여기는 [${got || "없음"}]`);
        }
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
