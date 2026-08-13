# How to test a change in this addon

Three layers can fail. They see different things, and none of them sees everything. **Pick the
cheapest layer that could actually catch the mistake you are capable of making here**, and if a
change spans layers, land a check in each.

| | runs | sees | cannot see |
|---|---|---|---|
| `npm test` | headless, no client | pure logic — solving, ordering, derivations, migration | anything that needs a frame, an attribute, or the restricted environment |
| `npm run check` | headless | lint, XML, locale/template parity, snippet syntax, **the exact bytes every snippet bakes to** | whether any of it behaves |
| `/debtest` | in the game | the real restricted environment: snippets compiling, attributes wiring, event ordering, what the game reports a key is bound to | nothing that needs a second player or a real fight |

`npm run check` runs the first two together. It does **not** run the third, and it never will.

---

## 1. Headless specs — `tests/`

The cheapest layer, and the only one that runs without the game. Use it for anything that is a
function of its inputs.

`tests/run.lua` loads a subset of the addon under a shim: `Constants`, `Ordering`, `Solver`,
`Misc`, `ActionCatalog`, `Profile`, `Legacy`. **`UpdateBindings.lua` and `SecureBindings.lua` are
not loaded** — the parts of them that are pure (expression emitters, condition merging) are
testable in principle but the files also build frames at load, so they are not reachable yet.

Add a spec by dropping a file in `tests/` and registering it in the `specs` list in
`tests/run.lua`. A spec is a function taking `DebindPrivate` and returning
`{ passed = n, failures = {...} }`; copy the harness at the top of any existing one.

Run: `npm test`, or `node tests/run.js` if there is no `lua` binary.

## 2. Static checks — `npm run check`

Most of these are self-explanatory. Two are not.

**`check:snippets`** parses every secure snippet body. Snippets are Lua but they live inside
strings, so `luacheck` cannot see into them, and a body the restricted environment fails to
compile does not raise anything — the snippet simply never attaches, and the symptom is "that one
key stopped working". The checker finds bodies by call name; the list is `CALLS` in
`tools/lib/snippets.js`. **If you pass a body to a function that is not in that list, that snippet
silently leaves every check.** Watch the count.

**`check:snippet-golden`** records what each body bakes to and compares on every run. It exists
because the bake is where injection for testing attaches, and the claim that injection costs a
shipped build nothing is not one to verify by eye.

Two rules follow from how probes bake:

- a probe that unwraps to a call — `PROBE.UnitExists(unit)` becomes `UnitExists(unit)` — must move
  the golden **not at all**
- a probe that vanishes in a shipped build leaves the blank line its source line occupied, so the
  golden gains **one blank line per probe** and nothing else

Anything beyond that means the live table is changing bodies. If you edited a body deliberately,
`node tools/check-snippet-golden.js --update` and read the diff.

## 3. In-game tests — `DebindTest`

Needs `Constants.DEBUG` on, since the kit reaches the addon through `_G.DebindPrivate`.

```
/debtest          the list window. Everything a run needs is in it:
                    [실행]                  everything that does not end the session
                    [리로드 포함]            also the tests that cross a /reload
                    [기존 바인딩 남겨두기]     skip the blackout below, to tell its faults from the addon's
/debtest last     the stored result from a previous run
```

### What a run does to the session

For the length of a run the tester's world is put aside, so the suite answers the same on every
machine:

- **the profile is one layer, and it is the test's.** A test key carrying the tester's own actions
  means the record a test looks up could be someone else's
- **the game's own bindings are unbound.** In-memory only — `SetBinding` never reaches disk, and
  `LoadBindings(GetCurrentBindingSet())` puts the saved set back, which is how Blizzard's own
  quick-keybind cancels. `TOGGLEGAMEMENU` and the two chat keys are left alone so a wedged run is
  still recoverable by typing `/reload`
- both are the **runner's** to undo, not a test's, and every exit is covered — finish, the reload
  request, declining the reload popup, `PLAYER_LOGOUT`, and a restore deferred past combat

So `GetBindingAction(KEY)` on a key the test did not bind answers with nothing. Before this it
answered with whatever the tester had there, which made every "and now it goes away again"
assertion true only on a machine where that key happened to be free.

### Writing one

```lua
RegisterTest("what it checks", {
    description = "한 줄 설명",
    run = function(phase)
        local NAME = "short name"

        InsertAction({ type = Constants.SPELL, value = 585, key = "CTRL-SHIFT-F9", combat = true })
        ApplyBindings()

        SetMockState("combat", true)
        Wait(0.4)

        local bound = GetBindingAction("CTRL-SHIFT-F9", true) or ""
        if bound:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format("got %q", bound))
        end
        return Pass(NAME, bound)
    end,
})
```

### What the kit gives you

| | |
|---|---|
| `Wait(seconds)` | hands the frame back. **Nothing here lands in the frame it was asked for** — see below |
| `AddTeardown(fn)` | the runner runs it after the test, however the test ended |
| `InsertAction` / `ApplyBindings` / `CleanupActions` | build the bindings the test needs |
| `SetMockState(state, value)` | force a watched state. `nil` releases it; teardown is registered for you. Unit axes take a suffixed name -- `"<unit>-exists"`, `"<unit>-dead"` -- because the value is overridden where the update loop computes it, and that is per axis. **Life is the axis that needs this**: a test can stand up a friendly unit or an absent one, but not a dead one |
| `CreateTestUnitFrame(unit, frameType)` | a unit frame the test owns, registered through the real path. Returns `nil, reason` if registration was refused |
| `SetFrameUnit` / `HoverEnter` / `HoverLeave` / `GetHoverUnit` | drive and read the hover slot |
| `EnableProbes()` | rebake the snippets with reporting turned on |
| `EvalClickTimeKey(key)` + `LastWinner()` / `WaitForWinner()` | run a click-time key's decision and read which record the snippet picked. `WaitForWinner` gives the frame back until the report lands instead of spending a flat `Wait(0.4)` — use it in a sweep, where the flat wait is most of the runtime |
| `ReadKeyMembership(key)` / `LastMembership()` | which tables the key's record list landed in: `stateDriven`, `clickTime`, `clickCast`, any combination or none. **Always assert a positive one too** — on its own, "not state-driven" also describes a key that never emitted |
| `RequestReload(phase)` + `crossesReload = true` | end the session and resume in the same test. `Scratch()` is what survives |

A test that legitimately takes a while — sweeping a cross product means waiting on a rebuild and a
poll for every point — raises its own ceiling with `timeout = <seconds>` in the registration. The
runner's 30s default is a guard against a hung coroutine, and raising it for everyone would give
that up for the sake of a few tests.

### Waiting is not optional

Nothing this addon does completes in the frame you asked for it:

- the state driver polls on its own 0.2s beat
- `_onattributechanged` propagates after that
- `CallMethod` is queued, not called — anything the snippet reports outward arrives later
- `DirtyFlags` reaches `UpdateBindings` on a later pass

A test that sets something up and reads it back in the same breath reads the old value and calls
it a result. When in doubt, `Wait(0.4)`.

**A test that never yields is unaffected** — a coroutine that runs straight through finishes on
its first resume, so a suite of them still completes in one frame.

---

## 4. Rules that came from real failures

**Ask the game, not yourself.** Assert on what the game reports — `GetBindingAction(key, true)`
for what a key is bound to, `DebindPrivate.Units.hover` for the hover slot, `LastWinner()` for
which binding the snippet chose. A test that reads back the value it injected proves nothing.

**Assert the negative too.** Set the condition, check the effect appears; then unset it and check
it goes away. Without the second half the test also passes on something that was true the whole
time.

**Build your own preconditions.** What gets generated depends on the bindings that exist. With no
hover binding anywhere, `HoverBindings` stays false and the hover axis is never wired; with no
petbattle binding, that state is resolved by a different branch. Insert what you need and call
`ApplyBindings()` — do not hope for it.

**Verify that setup took.** `RegisterFrame` refuses quietly and remembers the refusal. Left
unchecked, a test drives a frame the addon is not watching, reads an empty slot, and reports it.

**Assert outcomes, not mechanism.** Reaching into how a result was produced — which attributes got
stamped where — ties the test to wiring that is being replaced. Check what the game ended up doing.

**One condition on one key proves almost nothing.** It answers "does it look at the condition at
all", and every fault worth finding is past that line: a key carrying several records, each naming
several axes, where exactly one has to win. The `Multi-axis:` tests sweep the full cross product of
four axes over a seven-record key — and they do not write the thirty-six expected winners out by
hand. The record definition is the one source; the actions and the expectations are both derived
from it, because a mistranscribed row reads exactly like a bug in the addon.

Two things such a sweep has to check about itself, or it goes green while measuring nothing: that
**the emitted record count still matches** (an index means nothing once the solver drops one and
shifts the rest) and that **every record won at least once** (a record no combination can reach is
a hole in the sweep, not a pass).

**Cleanup belongs to the runner.** Register it with `AddTeardown`; do not write it at the end of
the test. A test only has to fail early once and everything after it runs against a state nobody
chose.

**A test session is a test session.** Actions really firing, a state driver throttle changed, the
UI reloading — none of that is a cost worth bending the design around. Do not avoid pressing a key
because pressing it does something.

**`npm run check` passing is not "it works".** It cannot see the game. Say what was checked and
what was not, and do not report a UI or in-game change as done before someone has run `/debtest`.

---

## 5. Where a fault will actually surface

Failures in the secure layer are quiet. A snippet that fails to compile does not error — it never
attaches, and one key stops working. A generated snippet that fails is reported from inside
`RestrictedExecution.lua` against a chunk you cannot open. In DEBUG builds every generated snippet
is compiled with `loadstring` first (`AssertSnippetCompiles`), which says only "this text is Lua"
— but that is the class of fault that is otherwise most expensive to place.

If something in the game behaves as though the addon is loaded and doing nothing, suspect a
snippet that did not attach before suspecting logic.
