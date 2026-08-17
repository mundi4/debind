// `relativeKey="$parent.X"`가 **뒤에 선언된** 형제를 가리키는지 본다.
//   npm run check:xml-anchors
//
// 이걸 만든 이유: XML은 위에서부터 만들므로, 앵커가 가리키는 키가 아직 nil이면 **그 앵커는
// 조용히 버려진다.** 오류도 경고도 없고, 그 프레임만 화면 어디에도 안 붙은 채로 남는다.
//
// 이미 코드 주석이 세 군데에서 이 얘기를 하고 있다 - `OverviewTab`("탭이 창 어디에도 안 붙고
// 떠 있었다"), 지정 모드 토글(그 주석은 토글이 포트레잇 줄로 옮겨가면서 없어졌다),
// `SelectionCount`("이 <Layers>가 <Frames> 뒤에 있어야 하는 이유가 여기 있다"). 세 번 적어야
// 했다는 것이 사람이 기억할 규칙이 아니라는 뜻이고, 실제로
// 임포트 배치 행 템플릿에서 한 파일에 두 번 다시 났다(핀 버튼이 안 보였고, 붙여넣기 거절 사유가
// 안 보였다). check-locales가 같은 이유로 검사가 된 것과 같은 자리다.
//
// **"선언은 됐는데 뒤에 있는" 것만 잡는다.** 아예 안 보이는 키는 물려받은 템플릿의 것일 수
// 있어서(`$parent.TitleText` 같은) 판단하지 않는다. 여기서 잡는 것은 전부 진짜다.

const fs = require("fs");
const path = require("path");

const roots = [
    path.join(__dirname, "..", "Debind"),
    // Only `libs.xml` today - the sharing panels moved to `Debind` with the addon boundary. It
    // stays listed anyway: a list of shipped folders that quietly drops one is how the sibling
    // check (`check-templates.js`) went wrong once already, and the next XML added here would go
    // unchecked without a word.
    path.join(__dirname, "..", "DebindStorage"),
    path.join(__dirname, "..", "DebindCliqueFake"),
    path.join(__dirname, "..", "DebindTest"),
];

/** 여는 태그 / 닫는 태그 / 자기완결 태그. 주석과 CDATA는 미리 지운다. */
const TAG = /<(\/?)([A-Za-z][\w.-]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(\/?)>/g;
const ATTR = /([A-Za-z][\w.-]*)\s*=\s*"([^"]*)"/g;

function readAttrs(text) {
    const out = {};
    for (const m of text.matchAll(ATTR)) {
        out[m[1]] = m[2];
    }
    return out;
}

/** 트리를 만든다. 각 노드는 `{ name, attrs, line, parent, children }`. */
function parse(src) {
    const stripped = src
        .replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, " "))
        .replace(/<!\[CDATA\[[\s\S]*?\]\]>/g, (m) => m.replace(/[^\n]/g, " "));

    const root = { name: "#doc", attrs: {}, children: [], parent: null };
    let node = root;

    for (const m of stripped.matchAll(TAG)) {
        const [, closing, name, attrText, selfClosing] = m;
        if (closing) {
            if (node.parent) {
                node = node.parent;
            }
            continue;
        }
        const child = {
            name,
            attrs: readAttrs(attrText),
            line: stripped.slice(0, m.index).split("\n").length,
            children: [],
            parent: node,
        };
        node.children.push(child);
        if (!selfClosing) {
            node = child;
        }
    }

    return root;
}

/**
 * **프레임이 아니라 묶음일 뿐인 태그.** `$parent`는 이것들을 세지 않는다 - 텍스처의 부모는
 * `<Layer>`가 아니라 그 `<Layer>`를 담은 프레임이다.
 *
 * 처음에 이걸 빼먹어서 검사에 구멍이 났다. `<Layers>` 안에서 `<Frames>`의 키를 가리키는
 * 앵커가 정확히 실제로 났던 사고인데(임포트 배치 행의 개수 칸), 그때 이 검사는 통과했다 -
 * 컨테이너를 `<Layer>`로 잡는 바람에 형제가 하나도 없어서 견줄 것이 없었기 때문이다.
 */
const WRAPPERS = new Set(["Anchors", "Layers", "Layer", "Frames", "Animations", "Scripts",
    "KeyValues", "Attributes", "ButtonText", "Frame.Attributes"]);

/** 위로 올라가며 묶음 태그를 건너뛴다. */
function frameAbove(node) {
    let cur = node && node.parent;
    while (cur && WRAPPERS.has(cur.name)) {
        cur = cur.parent;
    }
    return cur;
}

function walk(node, visit) {
    visit(node);
    for (const child of node.children) {
        walk(child, visit);
    }
}

function checkFile(file, rel) {
    const src = fs.readFileSync(file, "utf8");
    const root = parse(src);
    const problems = [];

    // **차례는 문서 순서다.** 프레임은 위에서부터 만들어지므로, "먼저 선언됐나"는 트리에서
    // 형제 번호를 세는 것보다 문서에서 먼저 나오는지를 보는 것이 곧바르다 - 그래야 묶음
    // 태그가 몇 겹이든 답이 같다.
    let ordinal = 0;
    walk(root, (node) => {
        node.ordinal = ordinal;
        ordinal += 1;
    });

    walk(root, (node) => {
        if (node.name !== "Anchor") {
            return;
        }
        const key = node.attrs.relativeKey;
        if (!key || !key.startsWith("$parent")) {
            return;
        }

        const parts = key.split(".");
        let hops = 0;
        while (parts[hops] === "$parent") {
            hops += 1;
        }
        const wanted = parts[hops];
        if (!wanted) {
            return;
        }

        // 이 앵커를 소유한 프레임. `<Anchors>`뿐 아니라 `<Layer>`·`<Layers>`도 건너뛴다.
        const owner = frameAbove(node);
        if (!owner) {
            return;
        }

        // `$parent`를 hops번 거슬러 올라간 것이 그 키를 들고 있어야 할 컨테이너다.
        let container = owner;
        for (let i = 0; i < hops; i += 1) {
            container = frameAbove(container);
        }
        // 문서 밖으로 나갔다 = 이 파일이 모르는 부모다(가상 템플릿의 뿌리, 최상위 프레임).
        // 판단하지 않는다.
        if (!container || container.name === "#doc" || !frameAbove(container)) {
            return;
        }

        // 그 컨테이너에 딸린 키들. **중첩된 프레임 안으로는 안 들어간다** - 거기 있는
        // `parentKey`는 그 프레임의 것이지 이 컨테이너의 것이 아니다.
        let declared = null;
        (function collect(node) {
            for (const child of node.children) {
                if (child.attrs.parentKey === wanted && !declared) {
                    declared = child;
                }
                if (WRAPPERS.has(child.name)) {
                    collect(child);
                }
            }
        })(container);

        // **여기 없으면 넘어간다.** 물려받은 템플릿이 준 키일 수 있고, 그건 이 파일이 답할 수
        // 있는 질문이 아니다. 잡는 것은 "여기 있는데 뒤에 있다" 하나뿐이다.
        if (!declared || declared.ordinal < owner.ordinal) {
            return;
        }

        problems.push({
            line: node.line,
            wanted,
            ownerKey: owner.attrs.parentKey || owner.attrs.name || owner.name,
            declaredLine: declared.line,
        });
    });

    if (problems.length > 0) {
        console.log(`${rel}: 뒤에 선언된 것을 가리키는 앵커 ${problems.length}개`);
        for (const p of problems) {
            console.log(`  - ${p.line}행: ${p.ownerKey}가 $parent.${p.wanted}를 가리키는데`
                + ` 그건 ${p.declaredLine}행에 있다 (앵커가 조용히 버려진다)`);
        }
    }
    return problems.length;
}

// **Walked, not listed.** This used to read each root's top level only, so `DebindCliqueFake` was
// missed entirely and anything put in a subfolder would go unchecked without a word. `Libs` stays
// out for the reason its siblings give: it is somebody else's code.
let files = [];
const collectXml = (dir, rel) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (entry.isDirectory()) {
            if (entry.name !== "Libs") collectXml(path.join(dir, entry.name), path.join(rel, entry.name));
        } else if (entry.name.endsWith(".xml")) {
            files.push({ file: path.join(dir, entry.name), rel: path.join(rel, entry.name) });
        }
    }
};
for (const dir of roots) {
    if (fs.existsSync(dir)) {
        collectXml(dir, path.basename(dir));
    }
}

// **An empty list is not a pass.** Rename a folder and this would otherwise print "0 files, all
// clean" and exit 0, which is the one answer a check must never give.
if (files.length === 0) {
    console.error("검사할 XML을 하나도 못 찾았다. roots가 실제 폴더를 가리키는지 볼 것.");
    process.exit(1);
}

let bad = 0;
for (const { file, rel } of files) {
    bad += checkFile(file, rel);
}

if (bad > 0) {
    process.exitCode = 1;
} else {
    console.log(`XML ${files.length}개에서 뒤를 가리키는 앵커가 없다.`);
}
