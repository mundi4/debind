# How a unit frame reaches us

Read this before changing anything that picks up or refuses a unit frame: the doors in
`ClickCastTable.lua` and `FrameRegistry.lua`, the header protocol in `SecureBindings.lua`, and the
one blacklist that decides which frames they leave alone.

It describes the code as it stands in the working tree on 2026-09-09, which includes taking every
unit frame with one blacklist (`legacy/taking-every-unit-frame-with-one-blacklist.md`). Everything
said here about somebody else's addon was read out of that addon's own source on 2026-09-08, at
whatever version is installed on this board, and none of it is a promise anybody made us.

---

## 1. One funnel, seven doors

Every frame ends up in `DebindPrivate.RegisterFrame` (`FrameRegistry.lua`). Nothing else writes a
row in `ccframes`, and nothing else wraps a frame. **No door asks anything of its own**: the
blacklist is read once, inside the funnel, so what differs between the doors is only how a frame is
found.

| Door | Where | What opens it |
|---|---|---|
| **Table** | `ClickCastTable.lua` | an addon writes `ClickCastFrames[frame] = true` |
| **Our header** | `SecureBindings.lua` (`clickcast_register`) | an addon gives its group header our `ClickCastHeader` and the header registers each child from the restricted environment. The global is ours only while Clique is absent |
| **Clique's header** | `ClickCastTable.AttachCliqueHeader` | the same protocol, run against Clique's header; we read Clique's `export_register` attribute off its own frame. Attached whenever Clique is installed |
| **Name** | `FrameRegistry.TakeNamedFrame` | a frame whose name matches `KNOWN_PACK_FRAMES` passes one of the calls a unit frame makes on its way into somebody's click casting |
| **Header children** | `FrameRegistry.CollectHeaderChildren` | a `SecureGroupHeaderTemplate` header lays out, and its `child<i>` attributes are walked |
| **oUF** | `FrameRegistry.CollectOUFFrames` | any addon declaring `X-oUF` in its TOC has an `objects` list, and its tail is taken on every `PLAYER_ENTERING_WORLD` |
| **Blizzard's own** | `FrameRegistry.UpdateBlizzardFrames`, the `CompactUnitFrame_SetUpFrame` hook | the client's own unit frames and compact frames, behind the seven boxes |

The hooks that feed the name door are `SecureHandlerWrapScript`, `SecureHandlerSetFrameRef`,
`RegisterStateDriver`, `RegisterAttributeDriver`, `SecureUnitButton_OnLoad`, `RegisterUnitWatch`
and `UnitFrame_Initialize`. The last three are installed only if the global exists. A pack is free
to skip any single one of them, which is why there are seven.

**Every hook in both files is installed at file scope**, before any profile can be read.

## 2. The blacklist

**Every unit frame is ours.** The reader's only lever is naming one to be left alone, and there are
two lists of names to do it with:

| Box | Written | Read | Absent means |
|---|---|---|---|
| `Options.blizzframes[category]` | the client's seven windows, one box each | `registerBlizzardFrame` | ours |
| `TakesPackFrames(addon)` | `db.packFrames[addon]`, one box per installed known pack | asked once inside `RegisterFrame` | ours |

Both store `false` for "leave alone" and nothing at all for "ours", and both say `REQUIRES_RELOAD`:
which frames get picked up is decided as each one is built, so the values are read once at login
(`InitDB`) and a frame already wired stays wired.

**The pack box is asked in `RegisterFrame` and nowhere else**, so it covers every door at once, the
header door included. A frame whose name matches no row in `KNOWN_PACK_FRAMES` is not any pack's and
there is nothing left that could turn it away.

`CliqueDetected` is asked in exactly two places: whether to load `DebindCliqueFake` (`Public.lua`)
and whether to attach to Clique's table and header (`InitDB`).

## 3. What the funnel does

`RegisterFrame(button, type)`, in order:

1. The pack box. A frame belonging to a pack the reader ticked gets no row at all.
2. `ccframes[button] == false` means we already wrote the frame off; return.
3. An existing row settles it, unless the row's `frameType` is `unknown` or the caller can say
   something the row does not. `unknown` never closes the question, because a frame library
   commonly registers from its styling pass and writes the unit attribute after it.
4. Refusals, each of which writes `false` and is remembered for the session: not protected,
   forbidden, anchoring restricted, no `RegisterForClicks`.
5. Combat: the call goes into `FrameQueue` with its arguments, and the first entry of a fight puts
   one line in chat. The queue drains in arrival order at `PLAYER_REGEN_ENABLED`. It holds
   registrations and nothing else.
6. The kind. Being told beats reading: a header child is `group` because its header said so
   (`_headerChildren`), then `KNOWN_PACK_FRAMES` rows that carry a kind, then the frame's `unit`
   attribute, and `player` alone gets a second question off the name. Failing everything, `unknown`.
7. `InitFrame` on the restricted side, `OnEnter` and `OnLeave` wrapped once, the row written, and
   `UpdateRegisteredClicks` for the routing attributes, the `OnClick` wrapper, `AnyUp`/`AnyDown`
   plus the wheel, and `SetPropagateMouseMotion` down the children.

Wrapping is always **on top of whatever is already there**: `Reassemble` unwraps down to our own
header, hands what it took to the restricted side, and puts ours back outermost, so the other
addon's bodies still run. If another wrap of that frame arrives while our reassembly of it is still
on the stack, somebody is wrapping over us because we wrapped: `StandDown` drops our row for that
frame and says so once in chat, and the other addon keeps the frame. Nothing is counted. Clique
unwraps and rewraps every frame it holds on every loading screen, and a count cannot tell that
from a fight; a per-session budget of eight stood us down from every Blizzard frame on the third
loading screen.

**A deregistration arriving from outside means nothing, and there is no `UnregisterFrame`.** Being
ours is the blacklist's answer and not the frame owner's, and the blacklist only changes with a
reload, so nothing can turn "this frame is ours" into "it is not" inside a session. Five ways in
still exist and all five are inert: a `nil` write into our own table, a `nil` write behind a holder,
Clique's `export_unregister`, the header protocol's `clickcast_unregister` (an empty body kept
because a header calls it by name), and `DebindPublic:UnregisterFrame` (an empty function kept for
the same reason).

**`StandDown` is the one thing that takes a row back**, and it is ours to call. `hd` on a row says
the header door wrote it, which is what `hccframes` is the name-keyed shape of.

## 4. The table door, in detail

`ClickCastFrames` is the global every click casting aware unit frame addon writes into. Two shapes
are possible and `AttachClickCastFrames` decides between them on every pass:

- **The name is free**, meaning the global is a plain table, absent, or carries a metatable with no
  `__newindex`. We put our own table there, with `__newindex` registering and `__index` answering
  out of a store kept beside the table. Whatever was in the old table is adopted. Answering reads
  back still matters: an addon takes a frame back with
  `if ClickCastFrames[frame] then ClickCastFrames[frame] = nil end`, and a table that answers nil
  leaves that addon's own bookkeeping on the frame.
- **Somebody is holding it**, meaning a `__newindex` is already there. We do not take the name. We
  wrap that metatable's `__newindex` and nothing else, run the holder's original first, and register
  whatever it was handed. **The holder is not asked what it decided**: every unit frame is ours
  whoever else is standing on it, and `Reassemble` is what makes two engines on one frame safe. What
  is already in that table when we meet it is walked once, for a proxy that files its writes in the
  table itself.
  The rows we were already holding are written into the holder's table once (`HandOver`), because a
  holder builds its store by walking the table it finds and our store is beside the table, not in
  it, so `pairs` shows it nothing.
- **The name is locked** with `__metatable`. We leave it completely alone. The lock is probed with
  `pcall(setmetatable, previous, getmetatable(previous))` rather than recognised by shape, because
  `__metatable` can be set to anything including an ordinary looking table.

When the name is checked: at file scope, at `PLAYER_LOGIN` in the same tick as the event (a holder
that takes the name does it from its own handler for that event), at `PLAYER_ENTERING_WORLD`, at
`PLAYER_REGEN_ENABLED`, and one tick after any foreign `SecureHandlerWrapScript` or
`SecureHandlerUnwrapScript` (`QueueNameCheck`, one check per tick). The last of those is what
shortens the window where a holder puts up its proxy mid session.

## 5. The situations

### 5.1 The addon speaks the Clique protocol and Clique is not installed

`DebindCliqueFake` loads (`Public.lua` opens it only when Clique is absent) and puts up three
things under Clique's names: the `ClickCastUnitTemplate` virtual template, `_G.Clique` answering
`RegisterUnitFrame` / `UnregisterUnitFrame` and exposing `ccframes` and `hccframes`, and
`_G.ClickCastHeader` pointing at our `BindingDriver`. The table door is ours as well
(`ClickCastTable.lua`, which is in `Debind/` and not in the fake).

So all three of the ways an addon can talk to Clique arrive: the table, the `Clique:Register...`
calls, and the header protocol. That last one is the reason `ClickCastHeader` is set at load time
and must not move: an addon decides whether to give its header a `clickcast_header` at the moment
it builds the header.

### 5.2 The addon has Clique support off, or runs its own engine and offers nothing

Nothing is written anywhere, and no protocol is spoken. What reaches us is the three doors nobody
hands a frame through, and the only thing that turns one of their frames away is a pack box:

- the **name** door, if the frame's name matches a `KNOWN_PACK_FRAMES` row and the frame passes one
  of the seven hooked calls;
- the **header children** door, if the frames are children of a real `SecureGroupHeaderTemplate` or
  `SecureGroupPetHeaderTemplate` header;
- the **oUF** door, if the pack ships oUF and declares `X-oUF`.

An addon that matches none of the three is invisible to us, and there is no fourth way. See §7.

### 5.3 The addon holds the Clique name and shows nothing through it

What its `__index` answers no longer matters, because nothing asks it. Two sub cases are left:

- **A proxy with a `__newindex`,** whatever else it carries. We wrap that one metamethod, its
  original runs first, and every write it is handed comes to us as a registration.
- **A proxy locked with `__metatable`.** We never touch it. The table door is closed for that
  session and only the other doors can reach anything.

In both, frames the holder keeps in an upvalue store and never puts in the table are invisible to
`pairs`, so a frame registered into a foreign proxy before we wrapped it is heard only if a later
write reaches it.

### 5.4 Clique is installed

There is no other case: the switch that used to make one is gone.

- `DebindCliqueFake` does not load, so `_G.Clique`, `_G.ClickCastHeader` and
  `ClickCastUnitTemplate` stay Clique's. Our own header door is therefore unreachable, and addons
  wiring a header to `Clique.header` wire it to Clique.
- `GetHoveredUnit` has one shape and reads `States.unitframe`, because every frame Clique holds is
  one we hold too.
- **Blizzard's own frames are ours**, as they always were: Blizzard handed its unit frames to
  nobody, Clique picks them up itself and so do we, and both of us going through `ClickCastFrames`
  on the way is Clique's implementation rather than a door the frame came in by.
- The **table door** attaches to Clique's proxy as a holder, from `InitDB`. Frames written before
  the attach sit in `Clique.ccframes` and nowhere else, and `AttachCliqueHeader` sweeps that list.
- The **Clique header door** replaces ours: `AttachCliqueHeader` hooks `OnAttributeChanged` on
  Clique's header and reads `export_register`, which is how Clique itself gets the registration out
  of the restricted environment, and hands the name to our own `OnClickCastRegister`, so the row is
  the header's and is written a tick later. `export_unregister` is not listened to. Frames already
  in `Clique.hccframes` when we attach are taken then, since that is the window we were not
  listening in.
- The name, header children and oUF doors are open.
- Both engines end up on one frame. We take the top and replay what was above us, so Clique's
  bodies still run. If a fight over the top starts, `StandDown` leaves that frame to Clique: two
  engines on one frame is the intent, not a guarantee.

## 6. Addon by addon

Read on 2026-09-08 from the copies installed on this board.

### Blizzard's own frames

Never handed to anybody. `UpdateBlizzardFrames` registers `PlayerFrame`, `PetFrame`, `TargetFrame`,
`TargetFrameToT`, `FocusFrame`, `FocusFrameToT`, the party member frames and the boss frames; the
`CompactUnitFrame_SetUpFrame` hook picks up compact party, raid and arena frames by name pattern.
Neither asks about Clique, and both are behind the seven boxes only. A frame carrying
`ignoreCUFNameRequirement` is skipped, which is the nameplate and two preview frames, because
`GetName` raises on them.

### EllesmereUI

Two addons, and they behave differently.

`EllesmereUIRaidFrames` carries a click casting engine of its own with an on and off switch.

- **Engine off.** `CC_RegisterFrame` records the frame as its own and hands it to whoever holds the
  table (`AddFrameToClickCast`, writing `true`). It never installs its proxy in this state, so the
  name is ours and the frames come in through the table door. Deregistration is a real `nil` write,
  which our `__index` makes visible.
- **Engine on.** It installs a proxy over `ClickCastFrames` once (`SetupClickCastFramesHook`) with
  a `__newindex` and an `__index` answering out of its own `registeredFrames`, adopting the old
  table by `pairs`. Its own frames are no longer offered through the table at all, so they reach us
  by the header children door: its group, flat and party headers are real
  `SecureGroupHeaderTemplate` frames. The standalone ones are on the name list already
  (`erfpartyselfbutton`, `erffriendlyboss%d+`, `erfextraframe%d+`), each pinned to `group` because
  their own tokens would read as something else. The `nil` it writes for each frame on the way into
  this state means nothing to us, so the rows from the engine-off state simply stay.
- Note that its adoption walk is `pairs(oldCCF)`, and our table yields nothing to `pairs`. What
  covers this is `HandOver`, which rewrites our rows into the new proxy the first time we meet it.
  Until that pass runs, EUI does not know about frames we were holding.
- With Clique installed its panel greys the engine's switch, but only the switch: `CC_Init` still
  runs the engine and installs the proxy when the saved setting is already on. So a board can
  have EllesmereUI's proxy sitting over Clique's table, which is why Clique is told apart by its
  table and not by being installed.

`EllesmereUIUnitFrames` writes every frame it builds straight into `ClickCastFrames` and holds no
name. The `ellesmereuiunitframes_` row on the name list is the backup path.

### Grid2

Writes `ClickCastFrames[button] = true` for each button it creates (`GridGroupHeaders.lua`), and
where `Clique` exists it also gives its header a `clickcast_header` pointing at `Clique.header` and
spawns its buttons from `ClickCastUnitTemplate` (`GridLayout.lua`). So:

- With Clique absent, both the table door and our header door carry the same frames, and either one
  alone would do.
- With Clique installed, the header protocol goes to Clique and we hear it back through
  `export_register`, while the table writes come through Clique's proxy as the holder.
- Its secure headers are `SecureGroupHeaderTemplate`, so the header children door reaches them too,
  and `grid2layoutheader%d+unitbutton%d+` is on the name list. Its insecure header variants are
  neither, and are covered by the table writes only.
- It calls `Clique:UpdateRegisteredClicks(frame)` when it exists. Our stand in answers that through
  `DebindPublic`.

### VuhDo

Registers nothing unless `IS_CLIQUE_COMPAT_MODE` is set, and that mode also refuses to run when
Clique is not loaded (`VUHDO_initCliqueSupport` prints a warning and returns). With compat mode on
it writes each `Vd<panel>H<button>` frame plus its `Tg` and `Tot` companions into
`ClickCastFrames`, and hands its own secure header a reference to `ClickCastHeader` so it can run
Clique's `setup_onenter` and `setup_onleave` bodies itself.

With compat mode off, which is what most boards run, the table stays empty of VuhDo frames and the
name door is the whole of it: the `^vd%d+h%d+` row, pinned to `group`, matching the panel buttons
and their `Tg` and `Tot` companions. VuhDo calls `RegisterUnitWatch` on its buttons and passes them
through `SetFrameRef` into its own key setup header, and both are hooked.

### Clique

Its own shape, since we now stand next to it: `ClickCastFrames` becomes a `__newindex` only proxy
with no lock; the header is `CliqueHeaderFrame` under `ClickCastHeader`; `clickcast_register`
writes the child into `export_register` and its own `OnAttributeChanged` picks it up into
`hccframes`; Blizzard frames are picked up by writing them into its own table. `export_register`
and the proxy shape are internal to that addon. If either changes, that door goes quiet with
nothing raised, and Clique's frames reach us only through the three doors nobody hands one through.

### An addon we have never seen

It reaches us if it does any one of: writing into `ClickCastFrames`, speaking the header protocol,
building its frames on a real secure group header, shipping oUF with `X-oUF` declared. If it does
none of those, and its frame names match no row, nothing reaches us at all. Adding a row to
`KNOWN_PACK_FRAMES` is the whole of what taking a new pack costs.

## 7. The holes

Each of these is understood and none of them raises anything.

1. **A holder that keeps its store in an upvalue and never writes into the table** hides every
   registration it received before we wrapped its metatable. `pairs` over such a proxy yields
   nothing, so no later pass can recover them; only a fresh write can reach one.
2. **A name locked with `__metatable`** closes the table door for the session. Nothing retries,
   because there is nothing to retry against.
3. **Between a holder installing its proxy and our next name check**, registrations go to a table
   we are not listening to. The window is one tick when the holder wraps anything
   (`QueueNameCheck`), and otherwise lasts until `PLAYER_ENTERING_WORLD` or
   `PLAYER_REGEN_ENABLED`.
4. **The reverse direction has the same window.** A new holder adopts by `pairs`, our store is not
   in the table, and `HandOver` runs on our next pass rather than on theirs. Until then that holder
   does not know about the frames we hold.
5. **A refusal is permanent.** `ccframes[button] = false` is written for an unprotected, forbidden,
   anchor restricted or unclickable frame and never revisited, so a frame that becomes eligible
   later stays written off for the session.
6. **`AttachClickCastFrames` itself has no combat guard.** Its own callers guard, but the three
   event paths do not; registering under lockdown queues the frame and puts one line in chat. That
   is the visible face of logging in during a fight.
7. **Stepping off a frame is not remembered.** `StandDown` writes `nil` rather than the `false` a
   refusal writes, so the next door that reaches that frame registers it again. No new wrapper goes
   on -- `_wrapped` and `_hoverWrapped` still say we wrapped it -- so no new fight starts either,
   and what comes back is the row on the wrappers that were already there.
8. **`export_register` is Clique's internal wiring.** A rename leaves the Clique header door silent.
9. **`clickcast_register` cannot carry a nameless frame.** `CallMethod` scrubs its arguments to
   strings, numbers and booleans, so a header with no name of its own makes children with no names
   and none of them can come through that door. Clique has the same limit. `CollectHeaderChildren`
   reaches those by object and needs no name.
10. **A pack that runs its own engine, offers nothing, uses no secure group header and no oUF, and
    whose names we do not know, is unreachable.** No hook can be made to answer for it: the test
    would have to be right about an addon we have never seen.
11. **Two engines on one frame is an intent, not a guarantee.** A pack that re-wraps inside our own
    wrap is a fight, and we step off that frame, once with a chat line.

## 8. What holds this true

`tests/frames_spec.lua` and `tests/holder_spec.lua` carry the headless half: every door taking a
listed name and a name no row covers alike, the pack box turning away its own pack at each of them,
the five outside deregistrations leaving the row standing, the combat queue, the holder machinery
against a proxy of every shape above, the hand over, and the Clique header door including what was
already in `hccframes` at attach time. `tests/options_spec.lua` carries the one list and its
polarity; `tests/migration_spec.lua` carries the two orphaned keys being swept out.

What only the game can answer: whether the holder machinery attaches to the real Clique proxy,
whether the `export_register` hook actually fires, and whether the frames Clique holds carry our
wiring as well. Those are in `/debtest`.

What neither can see: another addon changing the shape we read. Every third party detail in §6 is
that addon's internal wiring, and none of it was promised to us.
