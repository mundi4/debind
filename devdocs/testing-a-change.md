# How to test a change in this addon

Three layers can fail. They see different things, and none of them sees everything. **Pick the
cheapest layer that could actually catch the mistake you are capable of making here**, and if a
change spans layers, land a check in each.

| | runs | sees | cannot see |
|---|---|---|---|
| `npm test` | headless, no client, **both shapes** | **the whole pipeline** — solving, ordering, derivations, migration, what a rebuild decides, what it emits, which record a press picks, and **what a key ends up bound to** | the sandbox itself, taint, combat lockdown, Blizzard's own 0.2s beat, a real frame under a real cursor |
| `npm run check` | headless | lint, XML, locale/template parity, snippet syntax, **the exact bytes every snippet bakes to** | whether any of it behaves |
| `/debtest` | in the game | the real restricted environment: snippets compiling, attributes wiring, event ordering, the client's own frames, dialogs and menus | nothing that needs a second player or a real fight |

`npm run check` runs the first two together. It does **not** run the third, and it never will.

---

## 1. Headless specs — `tests/`

The cheapest layer, and the only one that runs without the game. Use it for anything that is a
function of its inputs — which, since `going-headless-outside-the-ui.md`, is the whole pipeline.

`tests/run.lua` reads **`Debind.xml` plus two of `DebindUI.xml`'s**, in their order, under a shim.
The rule is not whether a file is UI but **whether the function needs a frame**. `Flyout.lua` is UI,
needs one, and is in anyway — the pipeline asks it for a flyout opener. `ActionDisplay.lua` and
`ActionTooltip.lua` are UI files that need none: one resolves what an action is called, the other
takes the tooltip as an argument, so both are in and the words a reader sees became testable with
them. `Public.lua` is not UI, is not in `Debind.xml`, and is out. `StorageUI.lua` was in for two
functions that needed no frame, and went when those went with the bring dialog.

**The list is the answer, not this paragraph.** It has grown twice; read `tests/run.lua` before
concluding that something is out of reach.

What stands in for the client is three things:

| | |
|---|---|
| `tests/wow_shim.lua` | the value-returning queries, answered out of `shim.world` — spells, mounts, units, the game's own binding table. A spec puts a world up rather than swapping a function out |
| `tests/wow_frames.lua` | the frame shell, a recorder that keeps **everything** the addon hands to the secure side in order, the override bindings in force, the timer queue, and `fireEvent` to deliver a client event |
| `tests/restricted.lua` | the restricted environment. It replays that recording, so the tables the click path reads are the ones the game would have built, and then runs `EVAL_SNIPPET` — which is how "which action does this key fire" has a headless answer at all |

**One table is not a recording, and it is the one that moved the boundary.** An override is state —
put on by one rebuild and taken off by the next — so recording the calls could never answer *what is
in force now*. `wow_frames.lua` keeps it: the restricted `SetBindingClick` writes it, a rebuild's
`ClearOverrideBindings` takes its own back off, and `GetBindingAction(key, true)` reads it. That is
the whole of why `tests/boundkey_spec.lua` exists, and why **an old comment saying the game alone
can report a key is not evidence** — check `tests/run.lua` and this table before believing one.

Two of the specs are worth knowing about before adding one:

- **`emit_spec.lua` is the emission golden.** One rebuild against a fixed profile, every string it
  hands to the secure side, held byte for byte against `tests/emit-golden.txt`. It is a net for
  refactoring and **not a specification**: when the emission is meant to move, run
  `node tests/run.js --update-golden` and read the diff.
- **Every spec gets its own addon and its own client**, loaded and reset a moment before it runs.
  Nothing one leaves behind reaches the next, so the order of the list is readability and nothing
  else — reversing it is a run that has to pass.

`npm test` runs the suite **twice**: once as the working tree reads, once as
`node tests/run.js --shipped`, which cuts the `--@debug@` blocks out the way the packager does.
That second pass is the only place the shape a user actually gets is ever run. It emits different
bytes and has its own recording (`tests/emit-shipped-golden.txt`), because `Constants.DEBUG` being
false takes the DEBUG-only lines out of what a rebuild emits and leaves the driver frame unnamed.

`eval_spec` has nothing to run in that pass and says so with the one check that is left: the
click-time eval hooks are **DEBUG-only on purpose**, and the shipped pass asserts they are absent.
A build that shipped them would be handing every user a test entry point on the driver frame.

Add a spec by dropping a file in `tests/` and registering it in the `specs` list in
`tests/run.lua`. A spec is a function taking `DebindPrivate` and returning
`{ passed = n, failures = {...} }`; copy the harness at the top of any existing one.

Run: `npm test`, or `node tests/run.js` if there is no `lua` binary.

## 2. Static checks — `npm run check`

Most of these are self-explanatory. Three are not.

**`check:snippets`** parses every secure snippet body. Snippets are Lua but they live inside
strings, so `luacheck` cannot see into them, and a body the restricted environment fails to
compile does not raise anything — the snippet simply never attaches, and the symptom is "that one
key stopped working". The checker finds bodies by call name; the list is `CALLS` in
`tools/lib/snippets.js`. **If you pass a body to a function that is not in that list, that snippet
silently leaves every check.** Watch the count.

It also refuses a comment at the end of a line of code, which is the one comment rule that holds in
every body (`restricted-environment.md`). Nothing else could see it: the body still parses, and the
golden below bakes every body — so in one of the many that are **not** baked in the game, the golden
would show the line stripped while the game gets the comment.

**`check:snippet-golden`** records what each body bakes to and compares on every run. It exists
because the bake is where injection for testing attaches, and the claim that injection costs a
shipped build nothing is not one to verify by eye.

Two rules follow from how probes bake:

- a probe that unwraps to a call — `PROBE.UnitExists(unit)` becomes `UnitExists(unit)` — must move
  the golden **not at all**
- a probe that vanishes in a shipped build leaves the blank line its source line occupied, so the
  golden gains **one blank line per probe** and nothing else

Both of those rest on the bake being line for line: one line of source, one line of body, comments
emptied rather than removed. A diff where the line count moved is a diff where something other than
a probe changed.

Anything beyond that means the live table is changing bodies. If you edited a body deliberately,
`node tools/check-snippet-golden.js --update` and read the diff.

**Neither golden is compared as raw bytes on Windows, and that is deliberate.** Both are recordings
of bytes, and `core.autocrlf` rewrites line endings on checkout, so a golden matched only in the
working tree that generated it: a fresh checkout went red on line 1 showing two lines that look
identical. Both are marked `-text` in `.gitattributes` and both strip carriage returns on read,
because the attribute governs what is checked out from here on and a copy already converted stays
converted. If you are writing a third file of this kind, it needs both halves.

**`check:state-eval`** bakes `EVAL_SNIPPET` and holds it against
`Constants.STATE_EVAL_EXPRESSIONS`, which is where the state loop gets its own lines. The loop
measures on its 0.2s beat and the click path measures at the press, so if the two read one axis
differently the same state answers two ways and nothing below them can tell which answer was
wrong. It was a load-time `assert` under `Constants.DEBUG` until 2026-08-20, which meant the only
thing that ever ran it was logging in on a development client.

## 3. In-game tests — `DebindTest`

Needs `Constants.DEBUG` on, since the kit reaches the addon through `_G.DebindPrivate`.

**What belongs here is what needs the game.** Twenty-nine cases came down to `tests/` when the
harness learned to read the emitters and run the restricted environment; five more on 2026-08-23
when `GetBindingAction` learned to answer, and three that day when `ActionDisplay.lua` and
`ActionTooltip.lua` joined the load list. Every one of them was a question about a value. What
stayed asks something a client alone can answer, and **each of those carries a line above it saying
so** — a test still here without one is a test nobody has re-read.

**An event handler needs the login fired first.** Everything but `ADDON_LOADED` and `PLAYER_LOGIN`
is registered inside `Events.PLAYER_LOGIN`, so `frames.fireEvent("PLAYER_LOGIN")` comes before
`frames.fireEvent(whatever)`. The login's last line reaches `DebindUI.lua`, which needs frames, so
a spec stands `ShowMigrationDialogIfPending` in — that one call is UI and has its own coverage.

**A line saying so is not proof that it is still true.** The five that came down last were all
carrying confident ones, and four of those named a file the harness had started loading a year
before. So when the line names something the harness cannot do, read `tests/run.lua`'s list and
`wow_frames.lua` before you believe it — that boundary has moved twice and will move again.

Two of them are in **both** places deliberately: the `Multi-axis:` sweeps. Four axes over seven
records is where the headless reading of the restricted environment and the real one would part,
and there is no other way to find out that they have.

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

        -- No wait: `SetMockState` ends in a rebuild, and a rebuild runs the state pass and
        -- the bindings before it returns. See "Waiting" below.
        SetMockState("combat", true)

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
| `WaitUntil(pred, limit)` | hands the frame back until `pred` answers. **There is no fixed-duration wait** — see "Waiting" below for why, and for the four `WaitFor…` helpers built on this |
| `AddTeardown(fn)` | the runner runs it after the test, however the test ended |
| `InsertAction` / `ApplyBindings` / `CleanupActions` | build the bindings the test needs |
| `SetMockState(state, value)` | force a watched state. `nil` releases it; teardown is registered for you. Unit axes take a suffixed name -- `"<unit>-exists"`, `"<unit>-dead"` -- because the value is overridden where the update loop computes it, and that is per axis. **Life is the axis that needs this**: a test can stand up a friendly unit or an absent one, but not a dead one |
| `CreateTestUnitFrame(unit, frameType)` | a unit frame the test owns, registered through the real path. Returns `nil, reason` if registration was refused |
| `SetFrameUnit` / `HoverEnter` / `HoverLeave` / `GetHoverUnit` | drive and read the hover slot |
| `EnableProbes()` | rebake the snippets with reporting turned on |
| `EvalClickTimeKey(key)` + `WaitForWinner()` | run a click-time key's decision and read which record the snippet picked. `LastWinner()` is the unwaited reader, for when a winner is not what is expected |
| `EvalClickCast(frame, n, mod)` + `WaitForEvalAnswer()` | the same for a unit-frame click. Wait on the **answer**, not on a winner — declining is a legitimate outcome and there is no winner to wait for; then read `LastWinner()` / `LastEvalAnswer()` |
| `ReadKeyMembership(key)` + `WaitForMembership()` | which tables the key's record list landed in: `stateDriven`, `clickTime`, `clickCast`, any combination or none. **Always assert a positive one too** — on its own, "not state-driven" also describes a key that never emitted |
| `RequestReload(phase)` + `crossesReload = true` | end the session and resume in the same test. `Scratch()` is what survives |

A test that legitimately takes a while — sweeping a cross product drives a rebuild at every point
— raises its own ceiling with `timeout = <seconds>` in the registration. The
runner's 30s default is a guard against a hung coroutine, and raising it for everyone would give
that up for the sake of a few tests.

### Waiting

**Almost nothing here needs a wait, and there is no fixed-duration one left in the kit.** This
section used to say the opposite — that nothing lands in the frame you asked for it, so when in
doubt spend 0.4s — and it was wrong on three of its four counts. `CallMethod` is called rather
than queued, restricted `SetBindingClick` binds the key on the spot, and a direct
`UpdateBindings()` runs its own state pass before it returns. The full map is
[reading-back-what-you-just-set.md](reading-back-what-you-just-set.md); read it before adding a
wait.

What is left waits on a named event and stops the moment it happens, so a passing run pays what it
actually costs rather than a flat sum:

| | waits for |
|---|---|
| `WaitUntil(pred, limit)` | the primitive. Asks `pred` **before** the first yield, so an already-true condition costs nothing |
| `WaitForIdle()` | a **queued** rebuild (`QueueUpdateBindings` -> next frame), plus one frame for the one that just ran |
| `WaitForMembership()` / `WaitForWinner()` / `WaitForEvalAnswer()` | a snippet's answer. Already there in practice; the wait is what turns "no answer at all" into a bounded failure |
| `WaitForHoverSlot(filled)` | the hover mirror. Free after `HoverEnter`/`HoverLeave`; a real wait after `SetFrameUnit`, which only Blizzard's 0.2s poll notices |

Two ways to get this wrong:

- **Do not wait for the thing you are about to assert.** The assertion can then only fail by
  timing out, and where the expected value is also the current one the wait returns instantly and
  proves nothing. `WaitForHoverSlot` asks whether the slot is filled and deliberately not *which*
  unit, for this reason.
- **Waiting can be the weaker test.** The poll refills a wiped hover slot within a tick, so giving
  "does the slot survive a rebuild" any time at all lets it read the recovered value and pass over
  the bug.

**A test that never yields is unaffected** — a coroutine that runs straight through finishes on
its first resume, so a suite of them still completes in one frame.

---

## 4. Rules that came from real failures

**Ask the game, not yourself.** Assert on what the game reports — `GetBindingAction(key, true)`
for what a key is bound to, `GetHoverUnit()` for the hover slot, `LastWinner()` for
which binding the snippet chose. A test that reads back the value it injected proves nothing.

**And ask the restricted side, not its mirror.** `ReadSecureState` / `ReadSecureUnit` go to
`States` and `UnitAliasMap` themselves; `DebindPrivate.Units` is a copy kept up to date by a
report, and a copy that held a value the restricted side had dropped would read as a pass. Hover
has no copy at all any more — `SetUnit` stopped reporting it on 2026-08-22.

**Move a widget the way a hand moves it.** `EditBox:SetText()` puts the string in and does **not**
run `OnTextChanged`, which is where the window does the work. The macro editor lights [Cancel] there
and the search box sets the search term there, so two tests that typed with `SetText` measured
nothing and reported a bug the addon did not have. Set the text, then run that widget's own script.
Fail when there is no script to run: skipping it quietly means the day the XML wiring goes missing,
those tests pass (`TypeInto` in `DebindTest.lua`).

**Assert the negative too.** Set the condition, check the effect appears; then unset it and check
it goes away. Without the second half the test also passes on something that was true the whole
time.

**Build your own preconditions.** What gets generated depends on the bindings that exist. With
nothing measuring the hover axis, `UPDATE_MOUSEOVER_UNIT` is never registered and
`rebindOnHoverFrame` stays false; with no petbattle binding, that state is resolved by a different
branch. Insert what you need and call `ApplyBindings()` — do not hope for it.

**Verify that setup took.** `RegisterFrame` refuses quietly and remembers the refusal. Left
unchecked, a test drives a frame the addon is not watching, reads an empty slot, and reports it.

**Assert outcomes, not mechanism.** Reaching into how a result was produced — which attributes got
stamped where — ties the test to wiring that is being replaced. Check what the game ended up doing.

**The emission golden is the one deliberate exception, and it is one because it is not a test of
behaviour.** It records the mechanism on purpose: every string a rebuild hands to the secure side,
byte for byte. That is a net for moving code, not a claim that what came out is right, and the two
must not be confused — a spec that wants to know whether a key fires the right action asks
`restricted.lua`, not the golden.

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

**The client you verify in is a PTR build, and it can be the thing that is wrong — until it isn't.**
The two clients differ in runtime behaviour and not only in API surface, and that difference is not
stable across builds. Measured here: `1/0` raised `Division by zero` on the PTR install while
retail, PUC 5.1, LuaJIT and 5.4 all answered `inf` — and by 2026-08-14 the same install answered
`inf` as well. Both halves are the rule. When something in the game looks like a bug in a library or
in our own logic, "because this is a PTR build" belongs in the candidate list; and anything pinned
or worked around because of such a difference has to be **re-measured on a schedule**, because it
expires without telling you. One stack trace read as a rule about the whole platform came within a
step of filing an issue on somebody else's library
([building-export-import.md](building-export-import.md), the LibSerialize section).

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
