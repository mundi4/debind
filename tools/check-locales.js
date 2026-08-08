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

const localesDir = path.join(__dirname, "..", "Debounce", "Locales");
const BASE = "enUS";

// enUS에는 있는데 다른 로케일에는 **없는 게 맞는** 키. 넣을 때는 왜 정상인지 한 줄 남길 것.
const ALLOWED_MISSING = {
    // enUS는 클라이언트 전역 NOT_BOUND를 담는다. 다른 로케일에서는 그 전역이 이미
    // 제 나라 말이라 따로 번역할 것이 없다.
    OVERVIEW_NO_KEY: ["ruRU"],
    // 같은 이유. 클라이언트 전역 ESCAPE_TO_UNBIND를 그대로 받는다.
    BIND_MODE_UNBIND_HINT: ["ruRU"],
};

// `L["KEY"] = ...` 형태만 센다. 주석(`-- L["X"]`)은 안 잡히도록 줄 앞을 고정한다.
const ASSIGN = /^L\["([^"]+)"\]\s*=/gm;

function readKeys(file) {
    const src = fs.readFileSync(file, "utf8");
    const keys = new Set();
    const dupes = [];
    for (const m of src.matchAll(ASSIGN)) {
        if (keys.has(m[1])) {
            dupes.push(m[1]);
        }
        keys.add(m[1]);
    }
    return { keys, dupes };
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

    const { keys, dupes } = readKeys(path.join(localesDir, file));

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
    if (missing.length === 0 && stale.length === 0 && dupes.length === 0) {
        console.log(`${locale}: 키 ${keys.size}개, ${BASE}와 일치.`);
    }
}

if (failed) {
    process.exitCode = 1;
} else {
    console.log(`전부 ${BASE}(${base.keys.size}개)와 같은 키 집합이다.`);
}
