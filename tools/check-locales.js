// Compare every locale file against enUS.
//   npm run check:locales
//   npm run check:locales -- --missing    (also list the untranslated keys)
//
// What it is here for is what goes wrong without a word on screen: a key left behind after enUS
// dropped it, a key written twice in one file, a placeholder that moved. That last one is the
// loud failure - `format()` raises where an argument is not there, and whoever wrote the
// translation has never opened that window in their own client.
//
// **A key a locale does not carry is not a failure.** locales.xml loads enUS first and each
// locale overwrites only what it translates, so an untranslated key comes out in English, which
// is a working answer - enUS is the one file that has to be complete. Their number is printed and
// nothing has to be registered to excuse it: the exemption list this file used to keep cost an
// edit for every new string and told nobody anything the count does not.
// devdocs/writing-user-facing-text.md holds the rule.
//
// No network, unlike check-templates, so it can be run at any time.

const fs = require("fs");
const path = require("path");

const localesDir = path.join(__dirname, "..", "Debind", "Locales");
const BASE = "enUS";
const LIST_MISSING = process.argv.includes("--missing");

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
// 값도 로케일 문자열과 똑같이 읽으므로 **적는 차례가 그대로 기대값이다.** 어순이 갈리는
// 언어는 여기가 그걸 적어두는 자리다 - 뒤집힌 번역과 뒤집어야 맞는 번역을 기계가 가를 수는
// 없어서, 후자만 사람이 한 줄 적고 나머지는 전부 걸리게 둔다.
//
// 넣을 때는 **어느 호출부가 그 인자를 넘기는지** 한 줄 남길 것.
const EXTRA_SPECS_OK = {
    // DebindUI.lua의 GetSideTabDescription이 전문화명 하나만 넘긴다. enUS는 그것마저 안 쓴다 -
    // 툴팁 제목이 이미 "Oreo / Balance"라 "in this spec"으로 가리킬 것이 있어서, 서식이 하나도
    // 없는 줄이 된다. 한국어는 그 이름이 필요하다.
    LAYER_DESC_CHARACTER_SPEC: { koKR: "%s" },
};

// `L["KEY"] = ...` 형태만 센다. 주석(`-- L["X"]`)은 안 잡히도록 줄 앞을 고정한다.
const ASSIGN = /^L\["([^"]+)"\]\s*=\s*(.*)$/gm;

// **키가 맞아도 서식이 어긋나면 그 줄은 터진다.** 빠진 키와 달리 조용하지도 않다 -
// `format()`이 인자를 못 찾으면 그 자리에서 Lua 오류가 나고, 번역한 사람은 자기 클라이언트로
// 그 화면을 열어본 적이 없다. koKR을 통째로 넣으면서(3.1) 손으로 대조하던 것을 검사로 내린다.
const SPEC = /%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?([sdfxXqcieg%])/g;

/** `%%`는 리터럴 퍼센트라 인자를 안 먹으므로 뺀다. */
function readSpecs(text) {
    const out = [];
    for (const m of text.matchAll(SPEC)) {
        if (m[2] !== "%") {
            out.push({ arg: m[1] ? Number(m[1]) : null, conv: m[2] });
        }
    }
    return out;
}

/**
 * 자리표시자들을 견줄 수 있는 꼴로 편다: **어느 자리에 몇 번 인자가 어떤 종류로 오는가.**
 * 번호를 안 붙였으면 나오는 차례가 곧 번호다(`format()`이 그렇게 읽는다).
 *
 * 여기서 하는 일의 전부는 **번호를 드러내는 것**이다. 차례가 바뀌었는지는 이걸 base와
 * 견주는 쪽이 본다 - 어순이 갈리는 언어가 실제로 있으므로(`EXTRA_SPECS_OK`), 옳고 그름을
 * 여기서 정하지 않고 사람이 한 줄 적게 한다.
 *
 * **같은 종류가 둘 이상이면 번호를 요구한다.** 그때가 이 검사에 구멍이 나는 유일한 자리다 -
 * `"%s over %s"`의 두 인자를 뒤집어 번역하면 양쪽 다 `%s%s`라 구별할 방법이 아예 없고,
 * `format()`은 안 터지며, 화면에만 두 값이 서로 반대로 찍힌다. 번호를 붙이고 나서야 뒤집힌
 * 것이 글자로 남아서 여기서 잡힌다.
 *
 * 종류가 서로 다르면(`%s`와 `%d`) 뒤집힌 것이 그 자체로 드러나므로 번호가 필요 없다.
 */
function contract(specs) {
    const numbered = specs.filter((s) => s.arg !== null);
    if (numbered.length > 0 && numbered.length !== specs.length) {
        return { error: "번호를 붙인 자리표시자와 안 붙인 것이 한 문자열에 섞였다" };
    }

    if (numbered.length === 0) {
        for (const s of specs) {
            if (specs.filter((o) => o.conv === s.conv).length > 1) {
                return { error: `%${s.conv}가 둘 이상인데 번호가 없다 - \`%1$${s.conv}\`처럼 붙일 것` };
            }
        }
    }

    const conv = new Map();
    for (const s of numbered) {
        const prev = conv.get(s.arg);
        if (prev !== undefined && prev !== s.conv) {
            return { error: `${s.arg}번 인자를 %${prev}와 %${s.conv} 둘로 쓴다` };
        }
        conv.set(s.arg, s.conv);
    }

    return { sig: specs.map((s, i) => `%${s.arg ?? i + 1}$${s.conv}`).join("") };
}

function readKeys(file) {
    const src = fs.readFileSync(file, "utf8");
    const keys = new Set();
    const dupes = [];
    const contracts = new Map();
    for (const m of src.matchAll(ASSIGN)) {
        if (keys.has(m[1])) {
            dupes.push(m[1]);
        }
        keys.add(m[1]);
        contracts.set(m[1], contract(readSpecs(m[2])));
    }
    return { keys, dupes, contracts };
}

const files = fs.readdirSync(localesDir).filter((f) => f.endsWith(".lua"));
const base = readKeys(path.join(localesDir, `${BASE}.lua`));

let failed = false;

if (base.dupes.length > 0) {
    failed = true;
    console.log(`${BASE}: 중복 키 ${base.dupes.length}개 - ${base.dupes.join(", ")}`);
}

// **base부터 계약이 서야 한다.** 번호 없이 `%s`를 둘 쓴 원문은 그 자체로는 안 터지지만,
// 번역자에게 뒤집어도 되는 자리처럼 보이는 틀을 물려준다. 견줄 기준이 없는 셈이라 여기서 끊는다.
const baseBroken = [...base.contracts].filter(([, c]) => c.error);
if (baseBroken.length > 0) {
    failed = true;
    console.log(`${BASE}: 자리표시자가 애매한 키 ${baseBroken.length}개`);
    for (const [k, c] of baseBroken) {
        console.log(`  - ${k}: ${c.error}`);
    }
}

for (const file of files) {
    const locale = path.basename(file, ".lua");
    if (locale === BASE) {
        continue;
    }

    const { keys, dupes, contracts } = readKeys(path.join(localesDir, file));

    // 애매한 것부터 끊는다. 계약이 안 서는 문자열은 견줄 값 자체가 없다.
    const vague = [...contracts].filter(([, c]) => c.error);

    // 그 다음이 대조다. **차례까지 본다** - 뒤집힌 번역은 오류 없이 두 값을 서로 반대 자리에
    // 꽂는다. 뒤집어야 맞는 언어는 `EXTRA_SPECS_OK`에 적고, 적히지 않은 것은 전부 걸린다.
    const badSpecs = [...base.contracts]
        .filter(([k, c]) => keys.has(k) && !c.error && !contracts.get(k).error)
        .map(([k, c]) => {
            const extra = (EXTRA_SPECS_OK[k] || {})[locale];
            return [k, extra !== undefined ? contract(readSpecs(extra)).sig : c.sig, contracts.get(k).sig];
        })
        .filter(([, want, got]) => want !== got);

    // Not translated here yet. Reported, never failed - enUS stands in for every one of them.
    const absent = [...base.keys].filter((k) => !keys.has(k)).sort();
    // enUS에 없는 키는 **지워진 문자열의 잔재**다. 화면에 안 나오므로 무해해 보이지만,
    // 다음 사람이 그게 아직 쓰이는 줄 알고 손본다.
    const stale = [...keys].filter((k) => !base.keys.has(k)).sort();

    if (dupes.length > 0) {
        failed = true;
        console.log(`${locale}: 중복 키 ${dupes.length}개 - ${dupes.join(", ")}`);
    }
    if (stale.length > 0) {
        failed = true;
        console.log(`${locale}: ${BASE}에 없는 키 ${stale.length}개 (지워진 문자열의 잔재)`);
        for (const k of stale) {
            console.log(`  - ${k}`);
        }
    }
    if (vague.length > 0) {
        failed = true;
        console.log(`${locale}: 자리표시자가 애매한 키 ${vague.length}개`);
        for (const [k, c] of vague) {
            console.log(`  - ${k}: ${c.error}`);
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
    if (absent.length > 0) {
        const how = LIST_MISSING ? "" : " - 목록은 `-- --missing`";
        console.log(`${locale}: 아직 안 옮긴 키 ${absent.length}개 (그동안 ${BASE}로 나간다)${how}`);
        if (LIST_MISSING) {
            for (const k of absent) {
                console.log(`  - ${k}`);
            }
        }
    }
    if (stale.length === 0 && dupes.length === 0 && vague.length === 0 && badSpecs.length === 0) {
        console.log(`${locale}: 옮긴 키 ${keys.size}개, 서식까지 ${BASE}와 일치.`);
    }
}

if (failed) {
    process.exitCode = 1;
} else {
    console.log(`${BASE} ${base.keys.size}개 기준, 옮겨진 자리는 전부 맞는다.`);
}
