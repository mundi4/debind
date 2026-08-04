// 우리 XML이 상속하는 블리자드 템플릿이 실제로 존재하는지 확인한다.
//   npm run check:templates          캐시가 있으면 그걸 쓴다
//   npm run check:templates -- --refresh   무조건 다시 받는다
//
// 이슈 #8(GlowBorderTemplate이 사라진 걸 릴리스 후에 알았다)이 이걸 만든 이유다.
// 없어진 템플릿을 inherits하면 게임에서만 터지므로, 게임 없이 잡을 수 있는 유일한 자리가 CI다.
//
// 출처는 Gethe/wow-ui-source의 live 브랜치. 라이브에 나가는 물건이니 live로 본다
// (로컬 BlizzardInterfaceCode/는 PTR 추출본이라 한 패치 앞서 있어서 이 판정엔 못 쓴다).

const fs = require("fs");
const path = require("path");
const https = require("https");
const zlib = require("zlib");

const BRANCH = process.env.WOW_UI_BRANCH || "live";
const REPO = "Gethe/wow-ui-source";

const repoRoot = path.resolve(__dirname, "..");
const cacheDir = path.join(__dirname, "cache");
const cachePath = path.join(cacheDir, `blizzard-templates-${BRANCH}.json`);

// 우리 것이 아닌데 블리자드 XML에도 없는 이름들. 여기 있는 건 "없어도 정상"이라는 뜻이므로
// 추가할 때는 왜 정상인지 한 줄 남길 것.
const ALLOWED_MISSING = {
    // (없음)
};

// XML에서 여는 태그를 훑는다. 속성이 여러 줄에 걸쳐 있어도 잡히도록 줄 단위로 안 본다.
const TAG = /<([A-Za-z]\w*)((?:[^>"']|"[^"]*"|'[^']*')*?)\/?>/g;

function attr(attrs, name) {
    const m = attrs.match(new RegExp(`\\b${name}="([^"]*)"`));
    return m ? m[1] : null;
}

/** virtual="true"로 선언된 템플릿 이름과 폰트 오브젝트 이름을 모은다. */
function collectDefined(xml, into) {
    for (const [, tag, attrs] of xml.matchAll(TAG)) {
        const name = attr(attrs, "name");
        if (!name) continue;
        // 폰트 오브젝트는 virtual 없이도 이름으로 상속된다.
        if (attr(attrs, "virtual") === "true" || tag === "Font" || tag === "FontFamily") {
            into.add(name);
        }
    }
}

/** inherits="A, B"가 가리키는 이름들을 모은다. */
function collectReferenced(xml, into, file) {
    for (const [, , attrs] of xml.matchAll(TAG)) {
        const inherits = attr(attrs, "inherits");
        if (!inherits) continue;
        for (const name of inherits.split(",")) {
            const trimmed = name.trim();
            if (trimmed) {
                if (!into.has(trimmed)) into.set(trimmed, new Set());
                into.get(trimmed).add(file);
            }
        }
    }
}

function ourXmlFiles() {
    const files = [];
    const walk = (dir) => {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory()) {
                // Libs는 남의 코드다. 자기들끼리 상속하고 우리가 책임질 것도 아니다.
                if (entry.name !== "Libs") walk(full);
            } else if (entry.name.toLowerCase().endsWith(".xml")) {
                files.push(full);
            }
        }
    };
    for (const dir of ["Debounce", "DebounceCliqueFake"]) {
        const full = path.join(repoRoot, dir);
        if (fs.existsSync(full)) walk(full);
    }
    return files;
}

/** tar 스트림에서 .xml만 골라 콜백한다. 통째로 풀면 수백 MB라 흘리면서 읽는다. */
function readTarXml(stream, onFile) {
    return new Promise((resolve, reject) => {
        let buf = Buffer.alloc(0);
        let mode = "header";
        let remaining = 0;
        let pad = 0;
        let wanted = false;
        let chunks = null;
        let name = "";

        const str = (b, off, len) => {
            const end = b.indexOf(0, off);
            return b.toString("utf8", off, end >= 0 && end < off + len ? end : off + len);
        };

        stream.on("data", (chunk) => {
            buf = buf.length ? Buffer.concat([buf, chunk]) : chunk;
            let off = 0;
            for (;;) {
                if (mode === "header") {
                    if (buf.length - off < 512) break;
                    const h = buf.subarray(off, off + 512);
                    off += 512;
                    if (h[0] === 0) continue; // 아카이브 끝의 0블록
                    const entry = str(h, 0, 100);
                    const prefix = str(h, 345, 155);
                    remaining = parseInt(str(h, 124, 12).trim() || "0", 8) || 0;
                    pad = (512 - (remaining % 512)) % 512;
                    name = prefix ? `${prefix}/${entry}` : entry;
                    wanted = String.fromCharCode(h[156]) === "0" && name.toLowerCase().endsWith(".xml");
                    chunks = wanted ? [] : null;
                    mode = "data";
                } else {
                    if (remaining > 0) {
                        const take = Math.min(remaining, buf.length - off);
                        if (take === 0) break;
                        if (wanted) chunks.push(Buffer.from(buf.subarray(off, off + take)));
                        off += take;
                        remaining -= take;
                    }
                    if (remaining === 0) {
                        if (buf.length - off < pad) break;
                        off += pad;
                        if (wanted) onFile(name, Buffer.concat(chunks).toString("utf8"));
                        chunks = null;
                        mode = "header";
                    }
                }
            }
            buf = buf.subarray(off);
        });
        stream.on("end", resolve);
        stream.on("error", reject);
    });
}

function get(url) {
    return new Promise((resolve, reject) => {
        https.get(url, { headers: { "User-Agent": "debounce-check-templates" } }, (res) => {
            if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
                res.resume();
                resolve(get(res.headers.location));
            } else if (res.statusCode !== 200) {
                res.resume();
                reject(new Error(`${url} -> HTTP ${res.statusCode}`));
            } else {
                resolve(res);
            }
        }).on("error", reject);
    });
}

async function downloadBlizzardTemplates() {
    const url = `https://codeload.github.com/${REPO}/tar.gz/refs/heads/${BRANCH}`;
    console.error(`${REPO}@${BRANCH} 받는 중...`);
    const res = await get(url);
    const defined = new Set();
    let files = 0;
    await readTarXml(res.pipe(zlib.createGunzip()), (_, xml) => {
        files++;
        collectDefined(xml, defined);
    });
    console.error(`  XML ${files}개에서 템플릿 ${defined.size}개`);
    return [...defined].sort();
}

async function blizzardTemplates() {
    const refresh = process.argv.includes("--refresh");
    if (!refresh && fs.existsSync(cachePath)) {
        return new Set(JSON.parse(fs.readFileSync(cachePath, "utf8")).names);
    }
    const names = await downloadBlizzardTemplates();
    fs.mkdirSync(cacheDir, { recursive: true });
    fs.writeFileSync(cachePath, JSON.stringify({ branch: BRANCH, names }, null, 0));
    return new Set(names);
}

async function main() {
    const ours = new Set();
    const referenced = new Map();
    for (const file of ourXmlFiles()) {
        const xml = fs.readFileSync(file, "utf8");
        collectDefined(xml, ours);
        collectReferenced(xml, referenced, path.relative(repoRoot, file));
    }

    const blizzard = await blizzardTemplates();
    const missing = [];
    for (const [name, files] of referenced) {
        if (ours.has(name) || blizzard.has(name) || name in ALLOWED_MISSING) continue;
        missing.push([name, [...files]]);
    }

    const external = [...referenced.keys()].filter((n) => !ours.has(n)).length;
    console.log(`inherits ${referenced.size}개 중 우리 것 ${referenced.size - external}개, 블리자드 것 ${external}개`);

    if (missing.length) {
        console.error(`\n블리자드 소스(${REPO}@${BRANCH})에 없는 템플릿 ${missing.length}개:`);
        for (const [name, files] of missing.sort()) {
            console.error(`  ${name}  <- ${files.join(", ")}`);
        }
        console.error(`\n이름이 바뀌었거나 삭제된 것이다. 게임에서만 터지므로 여기서 막는다.`);
        process.exit(1);
    }
    console.log("전부 존재함.");
}

main().catch((err) => {
    console.error(err.message);
    process.exit(1);
});
