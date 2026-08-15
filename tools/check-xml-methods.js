// Does `<OnClick method="Foo"/>` in XML actually reach anything?
//   npm run check:xml-methods
//
// **`method=` looks the name up on the element's *own* mixin.** A mixin on the parent frame does
// not help a child button that has none, and the game says so once in the log at load time:
//
//     Frame Button: Unknown method OnGenerateClicked in element OnClick
//
// and that button becomes **a button that does nothing**. No error, nothing wrong on screen. This
// shipped once already, and it took someone clicking the button to find out.
//
// So two things are checked:
//   1. the element using `method=` has a mixin at all (on its own tag, or inherited through one
//      of our templates)
//   2. that mixin really has a function of that name in the Lua
//
// Mixins that are not ours have no definition to read, so 2 cannot be checked for them. Those go in
// EXTERNAL_MIXINS below and only get 1 - writing one down leaves "this one is unverified" visible.

const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");

// Mixins we cannot verify. When adding one, leave a line saying whose it is.
const EXTERNAL_MIXINS = {
    // (none)
};

function walk(dir, out, ext) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        // `reference/` is Blizzard's code and the client's strings, not ours. The name it had here
        // was `BlizzardInterfaceCode`, and when that moved this line went on naming a directory
        // that no longer exists - so the walk started descending into `reference/globalstrings`,
        // which is a real directory full of `.lua`. Nothing broke, because those files declare no
        // mixins, which is exactly why nobody would have noticed. `wow-ui-source` escaped only
        // because it is a junction and `isDirectory()` is false for one.
        if (entry.name.startsWith(".") || entry.name === "node_modules"
            || entry.name === "reference") continue;
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) walk(full, out, ext);
        else if (entry.name.endsWith(ext)) out.push(full);
    }
    return out;
}

const xmlFiles = walk(root, [], ".xml");
const luaFiles = walk(root, [], ".lua");

// ---------------------------------------------------------------------------
// Lua: which mixin has which methods
// ---------------------------------------------------------------------------

const methodsByMixin = {};
for (const file of luaFiles) {
    const text = fs.readFileSync(file, "utf8");
    const re = /function\s+([A-Za-z_][\w]*)\s*[:.]\s*([A-Za-z_][\w]*)\s*\(/g;
    let m;
    while ((m = re.exec(text))) {
        (methodsByMixin[m[1]] = methodsByMixin[m[1]] || new Set()).add(m[2]);
    }
}

// ---------------------------------------------------------------------------
// XML: walk the elements, carrying the open ones' mixin/inherits on a stack
// ---------------------------------------------------------------------------

// The mixin/inherits of every named virtual template. Following `inherits` upward needs them all
// collected first.
const templates = {};
const TAG = /<(\/?)([A-Za-z][\w.]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(\/?)>|<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<\?[\s\S]*?\?>/g;

function attr(attrs, name) {
    const m = attrs.match(new RegExp(`\\b${name}="([^"]*)"`));
    return m ? m[1] : null;
}

function eachTag(text, fn) {
    TAG.lastIndex = 0;
    let m;
    while ((m = TAG.exec(text))) {
        if (m[0].startsWith("<!--") || m[0].startsWith("<?") || m[0].startsWith("<![CDATA[")) continue;
        fn({
            closing: m[1] === "/",
            selfClosing: m[4] === "/",
            name: m[2],
            attrs: m[3] || "",
            index: m.index,
        });
    }
}

for (const file of xmlFiles) {
    eachTag(fs.readFileSync(file, "utf8"), (tag) => {
        if (tag.closing) return;
        const name = attr(tag.attrs, "name");
        if (name) {
            templates[name] = {
                mixin: attr(tag.attrs, "mixin"),
                inherits: attr(tag.attrs, "inherits"),
            };
        }
    });
}

/** Every mixin name this element actually carries. `inherits` is followed through our own
    templates only. */
function resolveMixins(mixinAttr, inheritsAttr, seen) {
    const out = [];
    if (mixinAttr) {
        for (const name of mixinAttr.split(",")) out.push(name.trim());
    }
    if (!inheritsAttr) return out;

    seen = seen || new Set();
    for (const parentName of inheritsAttr.split(",")) {
        const key = parentName.trim();
        if (!key || seen.has(key)) continue;
        seen.add(key);
        const parent = templates[key];
        // Not one of ours (so, Blizzard's) means there is no definition to follow, and that counts
        // as no mixin. A Blizzard template that does supply one has to be named in EXTERNAL_MIXINS.
        if (parent) out.push(...resolveMixins(parent.mixin, parent.inherits, seen));
    }
    return out;
}

const problems = [];

/** `method=` attributes that reached the mixin lookup. The success line reports this and not a
 *  re-count of the files, so a walk that quietly stopped checking cannot report a healthy number. */
let resolved = 0;

for (const file of xmlFiles) {
    const text = fs.readFileSync(file, "utf8");
    const rel = path.relative(root, file);
    // The open elements. On reaching `<Scripts>`, the element **just outside it** is the one whose
    // mixin the method is looked up on.
    const stack = [];

    eachTag(text, (tag) => {
        const line = () => text.slice(0, tag.index).split("\n").length;

        if (tag.closing) {
            stack.pop();
            return;
        }

        if (!/^On[A-Z]/.test(tag.name)) {
            if (!tag.selfClosing) {
                stack.push({
                    name: tag.name,
                    mixin: attr(tag.attrs, "mixin"),
                    inherits: attr(tag.attrs, "inherits"),
                });
            }
            return;
        }

        // Getting here means a script element such as `<OnClick .../>`.
        //
        // **Read the owner before pushing, and push whenever this one has a body.** A script
        // element written as `<OnLoad>function body</OnLoad>` is a pair like any other, so leaving
        // it off the stack while its close tag still pops means every element after it in that file
        // sits one rung too low. The stack then underflows, `owner` comes back undefined, and every
        // remaining `method=` in the file is skipped without a word - which is exactly what this
        // tool was written to stop happening.
        const method = attr(tag.attrs, "method");

        // Skipping over `<Scripts>` lands on the element the scripts are attached to.
        const owner = stack[stack.length - 2];

        if (!tag.selfClosing) {
            stack.push({ name: tag.name });
        }

        if (!method || !owner) return;
        resolved++;

        const mixins = resolveMixins(owner.mixin, owner.inherits);
        if (mixins.length === 0) {
            problems.push(
                `${rel}:${line()}: <${tag.name} method="${method}"/> 인데 <${owner.name}>에 믹스인이 없다.\n` +
                `    method=은 그 요소 자신의 믹스인에서만 이름을 찾는다. 부모의 메서드는 안 보인다.\n` +
                `    Lua에서 SetScript로 붙이거나, 이 요소에 mixin=을 줄 것.`
            );
            return;
        }

        const known = mixins.filter((name) => methodsByMixin[name] || EXTERNAL_MIXINS[name]);
        if (known.length === 0) {
            problems.push(
                `${rel}:${line()}: <${owner.name}>의 믹스인(${mixins.join(", ")})을 Lua에서 못 찾았다.\n` +
                `    우리 것이 아니면 tools/check-xml-methods.js의 EXTERNAL_MIXINS에 적을 것.`
            );
            return;
        }

        const found = mixins.some((name) =>
            EXTERNAL_MIXINS[name] || (methodsByMixin[name] && methodsByMixin[name].has(method)));
        if (!found) {
            problems.push(
                `${rel}:${line()}: <${tag.name} method="${method}"/> 인데 ${mixins.join(", ")}에 그 함수가 없다.\n` +
                `    게임은 로드할 때 "Unknown method"만 찍고 그 스크립트를 안 단다.`
            );
        }
    });
}

if (problems.length > 0) {
    for (const problem of problems) process.stderr.write(`  ${problem}\n`);
    process.stderr.write(`\nXML method= 배선이 어긋난다 (${problems.length}건).\n`);
    process.exit(1);
}

// **The number is what the walk actually resolved**, counted where it resolves. It used to be
// re-derived afterwards with a raw `method="` sweep over the same files, which cannot see the walk
// having stopped checking - the failure the comment above `owner` describes, where the stack
// underflows and every `method=` returns early, would still have printed a healthy count and
// exited 0. (That sweep was also plainly wrong: it counted a commented-out `<OnLoad method="…"/>`
// the walker correctly skips.)
process.stdout.write(`XML method= ${resolved}개가 전부 실재하는 믹스인 함수에 닿는다.\n`);
