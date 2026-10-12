# What one key runs

> **A standing document.** It replaces `which-action-a-key-runs.md`, which moved to `legacy/` on 2026-10-12 and stays there
> because the documents of that time point into its sections. Written by session `debind-85` (session ID
> `9cd7550f-cb70-483d-af31-d3c6140fbb66`). Why it was rewritten: the original says "the code is not the
> evidence" and is then written in bindings, twins, tiers, storage names and function names, so that a user-level rule such as
> "Target comes before the cast keys" stood nowhere as one line. This document is written from what the user **set** and what
> the user **pressed**, in the words the window uses. Our own storage names and function names do not appear. **The client's
> names do.** Unit IDs (`player`, `focus`), button attributes (`checkselfcast`) and CVars are not our implementation but the law
> outside it, and following that law can only be said in its names (2026-10-12, owner). How the implementation builds this is
> the business of `implementing-focus-and-self-cast.md` and the code; where the two differ, this document is right.
>
> **Why it does not go stale.** Each row of §6 is one headless test (`tests/eval_spec.lua` runs them as `§6 #n`). When the table
> and the code differ, the run goes red. Adding a row adds a test. A combination the table does not cover is a hole in the spec,
> and fixing the table is the answer (2026-09-16, owner: a spec is something you can write the test cases from, with the answers).
>
> Three things settled with the owner on 2026-10-12 are in here: the definition of a **named unit** (§1), the **fallback**
> (cast on yourself when the conditions do not hold, §3-4), and the Target-before-cast-keys priority written as a rule (§2).
> The fallback replaced an older option that left the `[@]` condition unasked; why that was dropped is in
> `falling-back-to-yourself.md` §1.

Several actions sit on one key. When the key is pressed, one of them runs. **Which one runs, and on which unit**, is decided by
the rules in this document and nothing else. What the game then does with that cast, whether Auto Self Cast takes it and
whether the spell can be used on that unit, is not ours: we can neither know it nor decide it (the authoring note in
`targeting.md`: "What the game does with it is not ours to say").

## 0. Words

**The window's words are used.** Menus and values are named as the window shows them.

| Word | Meaning |
|---|---|
| **Target** | The action's target menu. `Off` means none picked. Everything else (`Player`, `Pet`, `Target`, `Focus`, `Mouseover`, `Tank`, `Healer`, `Main Tank`, `Main Assist`, `Custom Target 1`/`2`, `Unit Frame`, `Always Ask`) is a picked unit |
| **Cast keys** | The Self Cast Key and the Focus Cast Key: the game's two modifier keys. Each can be turned off in Debind's settings tab |
| **Cast Options** | A submenu of the action menu with four rows: `Self Cast Key`, `Focus Cast Key`, `Hover Cast`, `Normal Cast` |
| **Usual target** | A cast that goes out without naming a unit. The same as pressing an action bar button, and the `[]` of a macro. Where it lands is the game's decision. The window's value for it is `Cast on the usual target` |
| **Pointed unit** | The unit the action's Hover Cast mode looks at. With `Unit Frames`, the unit of the unit frame under the mouse; with `Mouseover`, whatever is under the mouse, on a frame or in the world. Over a unit frame the two are the same unit |
| **Resolved Unit** | One row of the unit condition menu. It asks its conditions of **the unit this action goes to** on that press (§3-3). The other unit rows (`Target`, `Focus`, `Unit Frame`, `Mouseover`, …) ask of that unit |
| **Conditions** | Everything the user put on the action: unit conditions, combat, spec, switches and the rest |
| **Fallback** | A box inside the Resolved Unit menu. Ticked, the action casts on you as §3-4 says. Its wording is a draft (`falling-back-to-yourself.md` §3); this document just says "the fallback" |
| **Tail** | An action of type `Give Key Back`, `WoW Binding` or `Nothing`. Once a press reaches one, the key looks at no further Debind action |
| **Screen order** | The order of a key's actions as the overview tab shows it, decided by importance, whether the action has conditions, layer, and where the user moved it (`ordering.md`). It is the only order the user knows, and any order that differs from it is wrong (2026-09-15, owner) |

## 1. The named unit

**A named unit is one the user picked, themselves, as where the cast goes.** The unit is named when an action's **setting** or
a key the user **holds** picks it; it is not named when where the mouse happened to be, or what happens to be targeted, picks
it. A setting and a held key cannot happen by accident; the mouse position and the current target can (2026-10-12, owner).

| Where the unit comes from | Named | Why |
|---|---|---|
| A unit picked under Target | Named | A setting. That unit on every press. `Target` (the current target) picked here is "always my current target", so it is named too |
| Target `Mouseover`, `Unit Frame` | Named | A setting. The mouse decides which unit, but "this action goes to what is under the mouse" was the user's choice. With no unit there, the press is swallowed (§3-1) |
| Target `Always Ask` | Named | A setting. The user picked the targeting cursor |
| A held Self Cast Key or Focus Cast Key, with that row set to `Cast on yourself` / `Cast on your focus` | Named | A key. One extra key held on purpose, on every press, and the row has fixed what that key means |
| A held cast key with that row set to `Cast on the usual target` | Not named | The key is held, but the row says "for this action, ignore that key". The game places the unit |
| Hover Cast `Cast on the unit you point at`, on a pointing press | Not named | The mouse. The value says what to do while pointing, not which unit this press goes to, and whether the mouse was over a unit can be an accident on any given press |
| Hover Cast `Cast on the usual target`, on a pointing press | Not named | The game places it |
| A plain press (Normal Cast) | Not named | The current target is game state, not a setting of the action. Auto Self Cast is the game's too |
| The Resolved Unit condition | Picks no unit | A condition asks; it does not send |

**A bare left or right click on a unit frame is on the "pointed unit" line.** A click is pressed, but this document counts it as
the mouse, not as a key. No setting picked the unit, and that such a button only stands on unit frames is the client's doing, not
the user's statement. So the fallback stands there (§6 #87). The other line ("a unit is named when the press can only exist
over it") was considered; it would move bare clicks and actions with Normal Cast off to the named side. It was dropped because
the user would have to infer it from the Normal Cast value and the kind of mouse button together, and the same Hover Cast value
would mean a named unit or not depending on Normal Cast (2026-10-12).

## 2. Rules

Six lines. Every other section is the procedure that turns these six into the answer for one press.

1. **In screen order, the first action whose conditions hold runs.** One action per press. When an action in front does not
   take the press (it is not on that press, or sits it out because its conditions fail), the next action's turn comes.
2. **A named unit stays.** Nothing moves a named unit, and when a named unit fails the conditions, the press ends for this
   action: the next action's turn, and no fallback.
3. **Target comes before the cast keys.** On an action with a unit picked under Target, a held cast key does not move the unit.
   A cast key is **a statement about actions that left their unit open**. That is the client's definition (a `[@focus]` macro
   does not move when the Self Cast Key is held), and `SELF_CAST_KEY_DESC` says the same ("sends an action with no target of its
   own to you"). A user who picked a Target had the choice not to; picking one was choosing "regardless of the keys". The action
   still keeps its turn on a held press, and goes to that unit (§3-2).
4. **A held key comes before pointing.** A press with a cast key held is that key's press even while pointing at a unit. Holding
   the Self Cast Key over a unit frame casts on you (2026-09-15, owner). The client looks at Mouseover Cast first; we put the
   named thing (the key) before the unnamed one (the mouse). Rules 3 and 4 are two results of one principle.
5. **A held key's press stays a held key's press.** A press with the Self Cast Key held asks only the actions' "with the Self
   Cast Key held" answers, and when no action takes it, it does not fall through to the bare key: it ends there. This keeps the
   press from going somewhere the person holding the modifier did not aim (2026-09-17, owner).
6. **The fallback stands only behind an unnamed unit.** On an action that has it ticked, when an unnamed unit (the usual target,
   the pointed unit) fails the Resolved Unit conditions, the press does not go to the next action: it goes **to you**. The
   conditions are not asked again of you (§3-4).

Rules 2 to 6 **do not follow the client.** The client sends a Focus Cast Key press whose focus does not suit the spell to you
through Auto Self Cast (measured 2026-10-12: a hostile focus and ALT-G self-heals; no focus and ALT-G does nothing), and it
looks at Mouseover Cast before the Focus Cast Key. We follow the owner's line: holding ALT is the user making their intent
explicit. What a player expects with no explanation may differ (in the reader tests all four expected a held Self Cast Key to
move a Target `Focus` action to themselves, and from the fallback's label alone all four expected the fallback under a held
cast key too). That expectation is the label's job, not the rule's: a Target value that reads "always on …", and a cast key
row that reads "with this key held, on …".

## 3. One action's answer

For one press, one action answers one of three ways. **"Runs, on this unit"**, **"sits out"** (it does not take the press, so
the next action's turn comes), or **"swallows"** (it takes the press but has no unit, so nothing happens). The answer is decided
by the situation at the moment of the press and the action's settings.

### 3-1. An action with a unit picked under Target

**On every press it goes to that unit.** The Resolved Unit is that unit. When the conditions fail, it sits out. No fallback
(rule 2).

| Target | When the unit is not there |
|---|---|
| `Player`, `Pet`, `Target`, `Focus`, a role unit, a custom target | It does not sit out. The cast goes to that unit and the game says there is no target |
| `Mouseover`, `Unit Frame` | A press with nothing pointed at is **swallowed**. These are treated exactly like any other picked unit, with no exception for the two (2026-09-15, owner). To pass such a press to the next action, put an [exists] condition on that unit |
| `Always Ask` | The cast goes out to the targeting cursor. The Resolved Unit is asked as if no Target were picked (§3-3) |

The Cast Options rows do not change the unit, but they do decide **which presses the action stands on**. `Skip this action`
sits that press out, Hover Cast's `Skip this action` sits out while pointing, and Normal Cast unticked sits out the plain press
with nothing pointed at. While a Target is picked the menu shows `Cast on the unit you point at` and `Cast on the usual target`
as the same thing: both are that unit.

### 3-2. An action with no unit picked

| Press | That row's value | Answer | Resolved Unit |
|---|---|---|---|
| Self Cast Key held | `Cast on yourself` | On you | You |
| | `Cast on the usual target` | The usual target. If it fails, the fallback (§3-4) | Current target |
| | `Skip this action` | Sits out | |
| Focus Cast Key held | `Cast on your focus` | On your focus. With no focus, or a focus that fails, sits out | Focus |
| | `Cast on the usual target` | The usual target. If it fails, the fallback | Current target |
| | `Skip this action` | Sits out | |
| Pointing press (no key held) | `Cast on the unit you point at` | On the pointed unit. If it fails, **the plain press's answer** (the row below). With Normal Cast unticked, straight to the fallback | Pointed unit |
| | `Cast on the usual target` | The usual target. If it fails, the fallback. Stands on the pointing press even with Normal Cast unticked | Current target |
| | `Skip this action` | Sits out. Presses with a cast key held are untouched | |
| Plain press (no key, nothing pointed at) | Normal Cast ticked | The usual target. If it fails, the fallback | Current target |
| | Normal Cast unticked | Sits out | |

**On a pointing press, when the pointed unit fails, the usual target is tried first.** That is what the macro
`[@mouseover,help,nodead][]` does: when the mouseover fails, `[]` looks at the current target. The fallback comes after that.

**With both cast keys held, it is the Self Cast Key's press.** Unless no action on that key stands on the Self Cast Key's
press; then it is the Focus Cast Key's press (2026-10-07, owner). This is how the game does not ask the Self Cast Key on a
button with `checkselfcast` off, and it holds when the game's settings give both keys the same modifier.

**A cast key turned off in the settings tab is the same as not held.** Its press is a plain press (a pointing press if pointing),
and the action row's value means nothing. Hover Cast has nothing to turn off: the settings tab holds only the mode (default
`Unit Frames`), and each action holds one of the three values. The default `Cast on the usual target` means that to someone who
never thought about Hover Cast, the key is that action wherever the mouse is.

**What is held is read at the moment of the cast.** With the game's "cast on key release" on, a key held at press or at release
counts. Pressing the key, then holding a cast key and releasing, is that key's press. WoW's action buttons do the same
(measured 2026-10-07).

**Types that cannot carry a unit** (a macro, a mount, a pet command with no target) follow the same table. The press's unit is
handed to them; whether they use it is the action's business (2026-09-15, owner). A tail carries no unit.

### 3-3. Where the conditions are asked

The conditions the user put on an action **apply to every press of that action**: presses with a cast key held and pointing
presses alike (§6 #9). To leave only the pointing press out, the tool is Hover Cast's `Skip this action`, not a condition.

| Condition | Asked of |
|---|---|
| Resolved Unit | **The unit this action goes to** on that press (the last column of §3-1 and §3-2). On a press that goes to the usual target, the current target |
| The `Unit Frame` row | The unit of the frame under the mouse. With no frame under the mouse, only [does not exist] holds |
| The `Mouseover` row | The unit under the mouse. Over a unit frame, that frame's unit |
| Other unit rows (`Target`, `Focus`, …) | That unit |
| Conditions outside units | The situation |

Role and frame type can be measured only over a unit frame; where they cannot be measured, they hold. When a unit row and the
Resolved Unit both land on the same unit, both must hold.

**Hover Cast's `Skip this action` is not a condition.** Sitting out while pointing is made by the value, so it counts neither in
screen order's "has conditions" nor in the row's condition mark. The picked value is visible in the menu. The same thing can be
written as a [does not exist] condition on that unit, which also removes the presses with a cast key held and does count in the
order (2026-10-04, owner).

### 3-4. The fallback: when the conditions fail, cast on yourself

A box inside the Resolved Unit menu. On an action that has it ticked, when an **unnamed unit** fails the Resolved Unit
conditions, the press does not sit out: it goes **to you**. The other conditions still apply. The Resolved Unit conditions are
not asked again of you.

| Press | Where the fallback stands |
|---|---|
| Plain press | After the usual target fails |
| Pointing press | After the pointed unit fails and the usual target fails. With Normal Cast unticked, after the pointed unit fails |
| A cast key held, that row `Cast on the usual target` | After the usual target fails |
| A cast key held, that row `Cast on yourself` / `Cast on your focus` | **Does not stand.** A named unit |
| An action with a unit picked under Target | **Does not stand.** A named unit |
| A unit frame click | As the pointing press. Bare left and right clicks included |

**Why on you, and not `[]`** (2026-10-12, owner). On a spell like Penance, which heals a friend and damages an enemy, a user who
put [Friendly] on it to say "this key heals only" would, with the condition dropped and the cast sent as `[]`, hit the enemy
they have targeted: an enemy is a valid target for that spell, so Auto Self Cast does not take it. Sent to you, the unit is
fixed and the cast cannot reach the enemy, and we need not know whether a spell is helpful or harmful. Whether the spell can be
used on you we still do not know, but that is the same promise and the same limit as `Cast on yourself`.

**Why the conditions are not asked again of you.** The conditions the user set describe the unit they were aiming at, not
themselves. The fallback of a heal with [Friendly][Tank] goes to you even if you are not a tank. On a damage spell with
[Enemy] and the fallback ticked, the cast goes to you, the game refuses it, and the press is swallowed. That combination is the
user's.

**The fallback does not remove the condition.** An action with the fallback ticked still has a Resolved Unit condition, so it
stands in screen order as a conditioned action (2026-10-11, owner: it has to count as a condition). The price: an unconditioned
attack spell placed under a heal with the fallback never runs on a plain press, and the window shows nothing
(`falling-back-when-the-resolved-unit-fails.md` §3-4). An action with no reaction picked at all under Resolved Unit is marked
as an issue but kept on the key, because the fallback can run.

### 3-5. An action on no press at all

Hover Cast `Skip this action` with Normal Cast unticked sits out whether pointing or not. Such an action then stands on no held
press either (2026-10-04, 2026-10-05, owner): a cast key's answer is a variant of the action aimed elsewhere, and an action with
no press to vary has no meaning for it. To want something "only with a modifier", put a row on that modifier key (`CTRL-X`).
Reached by values alone, it is an issue on Cast Options; reached by a value and a condition that collide (Hover Cast
`Skip this action` with [exists] or a reaction on that unit, or Normal Cast unticked with [does not exist] on that unit), it is
a contradiction issue painted on that unit row and on Cast Options (on the key, for a bare click). With the issue, the action
stays on the key and passes every press to the next action like an action whose conditions never hold. It is closed by
changing the value, or by disabling the action.

**A disabled action is on no key.** It keeps its conditions and its place, and a key holding only such actions is not taken by
Debind, so the game's binding runs. It gets a dimmed reason line instead of an issue: the user said "not in use", so there is
nothing to fix (2026-09-18, owner).

## 4. One key's answer

Take key `K`'s actions in screen order and, by the kind of press, ask each for its §3 answer in turn. **The first action that
answers "runs" runs.** When none does, the "end" below applies.

| Press | Answer asked | End |
|---|---|---|
| Self Cast Key held | Each action's "with the Self Cast Key held" | Follows the bare key |
| Focus Cast Key held (the Self Cast Key not held, or no action on the key answering it) | Each action's "with the Focus Cast Key held" | Follows the bare key |
| Pointing press, plain press | Each action's answer for that press | The key's end |
| Unit frame click | Each mouse button action's frame-path answer (§5) | The frame's own handling |

**Following the bare key.** When no action takes a held key's press. If the bare key is ours right now, nothing happens. If the
bare key has been handed to the game right now, the press goes to the game too: the game's binding for that combination, or
failing that, the bare key's. So even while the bare key's action would hold, a held key's press does not fall to it (rule 5).
When no action on the key stands on a held key's press at all, Debind does not take that combination (2026-10-07, owner): if WoW
or another addon has a binding on it, that runs; if not, the client drops it to the bare key, which does not take held presses,
and nothing happens. Even on a key with held-key answers, a binding WoW or another addon has on that combination takes it; the
setting that used to override those was taken out on 2026-10-10.

**The key's end.** With "When no action runs" set to `Key is given back`, the key is handed to the game and whatever else is
bound to it runs; with `Press does nothing` (the default), nothing happens (`keys-given-back.md`). Giving back can misfire on a
press that lands after the situation changed and before the key followed (`giving-keys-back-when-no-action-runs.md`).

**When a tail wins, the key ends there.** `Give Key Back` hands the key to the game, `WoW Binding` issues its command, `Nothing`
does nothing. The actions under it are not used for that press. A tail has no held-key answers, so a held key's press never
reaches one.

## 5. Unit frame clicks

A mouse button pressed over a unit frame. Its path differs from the other presses.

- **Held keys are not read** (2026-09-15, 2026-10-04, owner). A click with a modifier held is that very click, and the Self and
  Focus Cast Key answers do not take part. What a frame's modified click does differs from frame to frame and the values read
  from it cannot be trusted, so a separate held-click answer could not respect it.
- **The pointing and plain answers of mouse button actions are asked.** An action with a `Unit Frame` [does not exist] condition
  does not stand on the frame path. A mouse button action on `Cast on the usual target` goes to the usual target on a frame
  click too; to leave the click to the frame, the value is Hover Cast `Skip this action` (in `Unit Frames` mode).
- **When nothing holds, the click goes to the frame's own handling.** When a tail wins, `Give Key Back` lets the click through to
  the frame, while `WoW Binding` and `Nothing` block it (2026-10-04, 2026-10-05, owner). Letting it through runs whatever the
  frame has on that click without the user choosing it, so letting go is `Give Key Back`'s job alone.
- **A bare left or right click ignores the Cast Options values**: it stands as Hover Cast `Cast on the unit you point at` in
  `Unit Frames` mode with Normal Cast unticked (2026-09-17, owner). Binding something to that key means a frame click. The key
  is not taken, so a click outside frames goes to the world. The menu locks those rows and the tooltip says why; it is not an
  issue, because changing the value would not be read on that key and the user would have no way to close it. A
  `Unit Frame` or `Mouseover` [does not exist] condition leaves that key with no press to take, which is a contradiction issue.
- **A mouse click outside a unit frame is a keyboard press** (2026-09-15, owner).

## 6. Problems and answers

Each row is one headless test. Unless stated: no Target picked, no conditions, a keyboard key, settings tab mode `Unit Frames`,
both cast keys on in the account, fallback off. **"Default" is an action with Hover Cast set to `Cast on the unit you point
at`**, because the table measures pointing presses; a new action's own default is `Cast on the usual target`. "Next" means this
action sits the press out and the next action's turn comes; with this action alone on the key, it is §4's "end". A row's test
checks whether this action runs on that press or not. Whether the key is then given to the game is checked by
`judgmentloop_spec` N1, N5 and N6. The numbers match the original document. Rows 73 to 89 changed their answers when the
fallback moved from `[]` to you; rows from 90 on are new.

| # | Action | Press | Answer |
|---|---|---|---|
| 1 | Default | Pointing at a unit frame | This action, on that frame's unit |
| 2 | Default | Pointing at a world unit | This action, usual target. In `Unit Frames` mode a world unit is not pointed at |
| 3 | Default, settings tab `Mouseover` | Pointing at a world unit | This action, on that unit |
| 4 | Default, action mode `Mouseover`, settings tab `Unit Frames` | Pointing at a world unit | This action, on that unit |
| 5 | Hover Cast `Cast on the usual target` | Pointing at a unit frame | This action, usual target |
| 6 | `Unit Frame` [does not exist] | Pointing at a unit frame | Next |
| 7 | `Unit Frame` [does not exist] | Nothing pointed at | This action, usual target |
| 8 | `Mouseover` [does not exist], settings tab `Mouseover` | Pointing at a world unit | Next |
| 9 | `Unit Frame` [does not exist] | Self Cast Key held, pointing at a unit frame | Next. **Conditions apply to held presses too.** To leave only the pointing press out while keeping the held ones, use Hover Cast `Skip this action` (#52) |
| 10 | Normal Cast unticked | Nothing pointed at | Next |
| 11 | Normal Cast unticked | Pointing at a unit frame | This action, on that frame's unit |
| 12 | `Unit Frame` [exists] | Nothing pointed at | Next |
| 13 | `Unit Frame` [exists] | Pointing at a unit frame | This action, on that frame's unit |
| 14 | Hover Cast `Skip this action` | Pointing at a unit frame | Next |
| 15 | `Unit Frame` [does not exist], settings tab `Mouseover` | Pointing at a world unit | This action, on that unit |
| 16 | Target `Focus` | Pointing at a unit frame | This action, on your focus |
| 17 | Target `Focus` | Self Cast Key held | This action, on your focus (rule 3) |
| 18 | Target `Mouseover`, settings tab `Unit Frames`, default action X in front | Pointing at a world unit | X, usual target. To X a world unit is not pointed at, so its plain answer runs. This action gets no turn |
| 19 | 18 with this action's mode `Mouseover` | Pointing at a world unit | X, usual target. Screen order puts X first |
| 20 | Target `Unit Frame` | Nothing pointed at | This action. No unit, so nothing happens and the press is swallowed |
| 21 | Default | Self Cast Key held | This action, on you |
| 22 | Default | Focus Cast Key held | This action, on your focus |
| 23 | Default | Both held | This action, on you |
| 24 | Self Cast Key row `Skip this action` | Self Cast Key held | Next |
| 25 | Self Cast Key row `Cast on the usual target` | Self Cast Key held | This action, usual target |
| 26 | Default, Focus Cast Key off in the settings tab | Focus Cast Key held | As if not held. The plain press's answer |
| 27 | A (default), B (Hover Cast `Cast on the usual target`), order A, B | Pointing at a unit frame | A, on that frame's unit |
| 28 | 27 in order B, A | Pointing at a unit frame | B, usual target. Screen order puts B first and B stands on the pointing press too |
| 29 | 27 in order B, A | Nothing pointed at | B, usual target |
| 30 | A (account layer, `Unit Frame` [exists]), B (character layer, [in combat]) | In combat, pointing at a unit frame | B, on that frame's unit. Both have conditions, so the layer decides and B comes first |
| 31 | 30 with B's Hover Cast `Cast on the usual target` | In combat, pointing at a unit frame | B, usual target |
| 32 | 30 with B's Hover Cast `Skip this action` | In combat, pointing at a unit frame | A, on that frame's unit |
| 33 | Mouse button, default | Unit frame click | This action, on that frame's unit |
| 34 | Mouse button, Hover Cast `Cast on the usual target` | Unit frame click | This action, usual target |
| 35 | Mouse button, default | Click outside frames | This action, usual target |
| 36 | Mouse button, `Unit Frame` [Enemy] | Click on a hostile frame | This action, on that unit |
| 37 | Mouse button, `Unit Frame` [Enemy] | Click on a friendly frame | Next |
| 38 | Mouse button, default | Unit frame click with the Self Cast Key held | Same as 33. A frame click does not read held keys |
| 39 | A macro (a type that cannot carry a unit) | Pointing at a unit frame | This action, handed that frame's unit. Whether the macro uses it is its own business |
| 40 | Target `Always Ask`, Resolved Unit [Friendly] | Pointing at a friendly frame, current target hostile | This action, to the targeting cursor. The Resolved Unit is asked of the frame's unit and holds |
| 41 | Hover Cast `Skip this action`, Normal Cast unticked | Any press, held ones included | Next. This action is on no press. Issue on Cast Options |
| 42 | 41's action alone on the key | Any press | With "When no action runs" set to `Key is given back`, whatever else is bound to the key. With the default, the key is ours and nothing happens |
| 43 | 41's action disabled | Any press | Next. With this action alone on the key, the game's binding runs. A dimmed reason line, no issue |
| 44 | Bare left click, default | Unit frame click, even with the Self Cast Key held | This action, on that frame's unit. No issue |
| 45 | 44 | Click outside frames | The key is not taken. Even with Normal Cast ticked the click goes to the world |
| 46 | Bare right click, mode `Mouseover` or settings tab `Mouseover` | Unit frame click | Same as 44. The key is not taken |
| 47 | Bare left click, Hover Cast `Skip this action` | Unit frame click | Same as 44. This key does not read the value |
| 48 | Bare left click, `Unit Frame` [does not exist] | Unit frame click | Next. The click goes to the frame's own handling. **Issue**, on the key and on that unit row |
| 49 | Bare left click, `Mouseover` [does not exist] | Unit frame click | Same as 48. Over a frame, `Mouseover` is that unit too |
| 50 | Hover Cast `Skip this action` | Nothing pointed at | This action, usual target |
| 51 | Hover Cast `Skip this action`, settings tab `Mouseover` | Pointing at a world unit | Next |
| 52 | Hover Cast `Skip this action` | Self Cast Key held, pointing at a unit frame | This action, on you. Sitting out while pointing does not reach held presses |
| 53 | Hover Cast `Cast on the usual target`, Normal Cast unticked | Pointing at a unit frame | This action, usual target |
| 54 | 53 | Nothing pointed at | Next |
| 55 | A (Hover Cast `Cast on the usual target`), B (default), order A, B | Pointing at a unit frame | A, usual target |
| 56 | Mouse button, Hover Cast `Skip this action` | Unit frame click | Next. The click goes to the frame's own handling |
| 57 | Mouse button, Hover Cast `Skip this action` | Click outside frames | This action, usual target |
| 58 | Mouse button, mode `Mouseover` | Unit frame click | This action, on that frame's unit |
| 59 | Mouse button, A (Hover Cast `Cast on the usual target`, importance raised to go first), then B (default, `Unit Frame` [Enemy]) | Click on a hostile frame | A, usual target. B cannot win on this key |
| 60 | 59 in order B, A | Click on a hostile frame | B, on that frame's unit |
| 61 | 59 in order B, A | Click on a friendly frame | A, usual target |
| 62 | Hover Cast `Skip this action`, `Unit Frame` [Enemy] | Any press, held ones included | Next. On no press. Contradiction issue, on Cast Options and the `Unit Frame` row |
| 63 | Default, `Unit Frame` [does not exist], Normal Cast unticked | Any press, held ones included | Next. Same as 62 |
| 64 | Mouse button, `Give Key Back` | Unit frame click | `Give Key Back` wins. The click goes to the frame's own handling |
| 65 | Mouse button, `WoW Binding` | Unit frame click | `WoW Binding` wins. Nothing happens, and the click does not reach the frame |
| 66 | Mouse button, `Nothing` | Unit frame click | Same as 65 |
| 67 | Default, Resolved Unit [does not exist], Normal Cast unticked | Any press, held ones included | Next. On a pointing press the Resolved Unit is the pointed unit, so [does not exist] has nowhere to stand. Same as 62; the painted row is Resolved Unit |
| 68 | Self Cast Key row `Skip this action` | Both held | This action, on your focus. No action on the key answers the Self Cast Key, so it is the Focus Cast Key's press |
| 69 | 68, the game's Self Cast Key and Focus Cast Key both ALT (the game's default) | ALT held | Same as 68 |
| 70 | Default, the game's "cast on key release" | Press, then hold the Self Cast Key and release | This action, on you |
| 71 | Default, "cast on key release" | Press with the Focus Cast Key held, add the Self Cast Key, release | This action, on you. Both are held at release |
| 72 | Self Cast Key row `Skip this action`, "cast on key release" | Press, then hold the Self Cast Key and release | Next |
| 73 | Hover Cast `Cast on the usual target`, Resolved Unit [Friendly], fallback on | Nothing pointed at, current target hostile | This action, on you |
| 74 | 73 | Pointing at a hostile frame, current target hostile | This action, on you. The pointing press goes to the usual target too (#5), and when that fails, the fallback |
| 75 | 73 with the fallback off | Nothing pointed at, current target hostile | Next |
| 76 | 73 with the Self Cast Key and Focus Cast Key rows on `Cast on the usual target` | Self Cast Key held / Focus Cast Key held, current target hostile | This action, on you, in each case. The usual target is not a named unit |
| 77 | 73 | Focus Cast Key held, focus hostile | Next. The focus is a named unit, so no fallback (rule 2) |
| 78 | Default, Resolved Unit [Friendly], fallback on | Pointing at a hostile frame, current target hostile | This action, on you. The pointed unit fails, the usual target fails, the fallback |
| 79 | 78 | Pointing at a friendly frame | This action, on that frame's unit |
| 80 | Hover Cast `Skip this action`, Resolved Unit [Friendly], fallback on | Pointing at a friendly frame, current target hostile | Next. Sitting out while pointing applies to the fallback too |
| 81 | Hover Cast `Cast on the usual target`, Normal Cast unticked, Resolved Unit [Friendly], fallback on | Pointing at a hostile frame, current target hostile | This action, on you |
| 82 | 81 | Nothing pointed at, current target hostile | Next. Normal Cast is unticked, so the action is not on the plain press |
| 83 | Default, Normal Cast unticked, Resolved Unit [Friendly], fallback on | Pointing at a hostile frame | This action, on you. The pointed unit is not a named unit (§1) |
| 84 | 73 with Target `Target` | Nothing pointed at, current target hostile | Next. An action with a picked Target has no fallback |
| 85 | 73 with Target `Always Ask` | Nothing pointed at, current target hostile | Next. `Always Ask` is picked too |
| 86 | Mouse button, 73 | Click on a hostile frame, current target hostile | This action, on you. A frame click falls back too when the usual target fails |
| 87 | Bare left click, Resolved Unit [Friendly], fallback on | Click on a hostile frame | This action, on you. The unit under a bare click is not a named unit (§1) |
| 88 | A ([in combat]), under it `Give Key Back` (Resolved Unit [Friendly], fallback on) | Out of combat, nothing pointed at, current target hostile | `Give Key Back` wins. A tail's fallback is the tail itself |
| 89 | 73 with no reaction picked under Resolved Unit, Self Cast Key row `Cast on the usual target` | Nothing pointed at / Self Cast Key held / Focus Cast Key held | This action, on you / this action, on you / next. **An issue** on the Resolved Unit row, but the action stays on the key |
| 90 | 78 | Pointing at a hostile frame, current target friendly | This action, usual target. The fallback comes after the usual target |
| 91 | Target `Focus`, Resolved Unit [Friendly], fallback on | Nothing pointed at, focus hostile | Next. An action with a picked Target has no fallback |
| 92 | 73 | Focus Cast Key held, no focus | Next. No fallback even with no focus |
| 93 | Default, Resolved Unit [Enemy], fallback on | Self Cast Key held | Next. You are not an enemy, and you are a named unit, so no fallback |
| 94 | Default, Resolved Unit [Friendly][Tank], fallback on, you are not a tank | Nothing pointed at, current target hostile | This action, on you. The conditions are not asked again of you |

## 7. The action menu's Cast Options

The four presses stand in one submenu of the action menu (2026-09-16, owner). **A value says "with this key held (with a unit
pointed at), what does this action do"**, never which target to pick. Wording follows `writing-user-facing-text.md`.

```
Cast Options
  Self Cast Key   ▸  ( ) Skip this action  (x) Cast on yourself               ( ) Cast on the usual target
  Focus Cast Key  ▸  ( ) Skip this action  (x) Cast on your focus             ( ) Cast on the usual target
  Hover Cast      ▸  ( ) Skip this action  ( ) Cast on the unit you point at  (x) Cast on the usual target
                     ---
                     (x) Use the mode in Debind's settings  ( ) Unit Frames  ( ) Mouseover
  [x] Normal Cast
```

- **Self Cast Key, Focus Cast Key.** The defaults are on you and on your focus. `Skip this action` sits that press out.
  `Cast on the usual target` ignores the key, goes to the usual target and keeps its turn; it exists because the game's placing
  cannot be picked under Target. Locked on an action with a picked Target. With the key off in the settings tab the value means
  nothing. There is no "follow the setting" value: with the account off the action value is meaningless, with it on the action
  value is everything (owner).
- **Hover Cast.** The default is `Cast on the usual target`: to a user who never thought about Hover Cast, the key is that
  action wherever the mouse is. `Cast on the unit you point at` goes to the pointed unit. `Skip this action` sits out while
  pointing. There is no "off" (2026-10-04, owner): the off that once existed did not stop the action on pointing presses, it
  yielded to actions with Hover Cast on regardless of order, which nobody could knowingly choose
  (`taking-off-out-of-hover-cast.md`). The mode only answers which unit counts as pointed at; an action stating its own mode makes
  "the setting is Unit Frames, but this one action on Mouseover" one setting.
- **Normal Cast.** A box, ticked by default. Unticked, the plain press is sat out, and the action runs only while pointing or
  holding a key. It replaces what the old "Unit Frame [exists]" condition did for "only while pointing"; the difference is that
  it passes the press on instead of swallowing it.
- **An action with a picked Target** goes to that unit whatever the value. The tooltip of `Cast on the unit you point at` says
  so: a target is picked, so it goes there.
- **A bare left or right click** has these rows locked, and the tooltip says why (§5).

It is a place set once and not reopened, and several actions can be changed at once (`editing-many-actions-at-once.md`), so a
value one level deeper costs little (owner).

**The game-automatic rows under Cast Options** (Auto Self Cast and the others) are not this document's. They switch a game
setting on or off for the duration of the press (`setting-the-clients-cast-automatics-per-action.md`) and change nothing about
which action goes to which unit.

## 8. What the help has to say

"Which action a key runs" (`ordering.md`) has to carry the rules of §2 and the per-press path of §4. "Which unit an action is
used on" (`targeting.md`) is §1 and §3. `cast-options.md` is §7. Once the fallback is in, "One key for a friend and an enemy"
in `setting-keys-up.md` (the two-action recipe) gets the one-action way through the fallback and the way through a macro action.
Wording follows `writing-user-facing-text.md`.

## 9. Coverage

Headless checks: every row of §6 (which action runs on which press, and on which unit), which unit each condition is asked of,
screen order, the four Cast Options rows adding and removing presses, tails letting a frame click through or blocking it, and
the migration (one test per row of the original document's §8). `/debtest` checks: for each kind of press, which action wins
and on which unit it goes out. Out of reach in principle: where the usual target lands (Auto Self Cast included), and the path by
which a frame click reaches the frame. Those are in `matching-the-clients-cast-targeting.md` §4.

## 10. What was not carried over from the original

- **Twins, tiers, originals, bindings.** The implementation's model. §3 and §4 here give the same answers without it. Building it
  that way is the business of `implementing-focus-and-self-cast.md`.
- **Our storage names and values** (the `casting` table, `"usual"`, `"skip"`, `normalCast = false`), **function and file
  names**, **issue codes**. Implementation. The client's names (`checkselfcast`, unit IDs) are the law outside and stay.
- **The migration table** (the original's §8). Done once, with a test per row. It stays in `which-action-a-key-runs.md`, and
  the code and tests that cite it still cite that document.
- **The solver dropping covered bindings** changes no answer: a covered binding is one that cannot win.
