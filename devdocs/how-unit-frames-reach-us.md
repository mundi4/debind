# How a unit frame reaches us

Read this before changing anything that picks up, refuses, or gives back a unit frame: the doors in
`ClickCastTable.lua` and `FrameRegistry.lua`, the header protocol in `SecureBindings.lua`, and the
three switches that decide which of them are open.

It describes the code as it stands in the working tree on 2026-09-08, which includes the Clique
coexistence work (`legacy/coexisting-with-clique.md`). Everything said here about somebody else's
addon was read out of that addon's own source on the same day, at whatever version is installed on
this board, and none of it is a promise anybody made us.

---

## 1. One funnel, seven doors

Every frame ends up in `DebindPrivate.RegisterFrame` (`FrameRegistry.lua`). Nothing else writes a
row in `ccframes`, and nothing else wraps a frame. What differs between the doors is only how a
frame is found and which switch that door asks first.

| Door | Where | What opens it | Asks |
|---|---|---|---|
| **Table** | `ClickCastTable.lua` | an addon writes `ClickCastFrames[frame] = true` | stand aside |
| **Our header** | `SecureBindings.lua` (`clickcast_register`) | an addon gives its group header our `ClickCastHeader` and the header registers each child from the restricted environment | nothing, but the attribute is blanked while we stand aside, and the global is ours only while Clique is absent |
| **Clique's header** | `ClickCastTable.AttachCliqueHeader` | the same protocol, run against Clique's header; we read Clique's `export_register` attribute off its own frame | only attached when Clique is installed and we are not standing aside |
| **Name** | `FrameRegistry.TakeNamedFrame` | a frame whose name matches `KNOWN_PACK_FRAMES` passes one of the calls a unit frame makes on its way into somebody's click casting | stand aside; the pack box answers at the funnel |
| **Header children** | `FrameRegistry.CollectHeaderChildren` | a `SecureGroupHeaderTemplate` header lays out, and its `child<i>` attributes are walked | stand aside, then per child: its pack box for a listed name, take unregistered otherwise |
| **oUF** | `FrameRegistry.CollectOUFFrames` | any addon declaring `X-oUF` in its TOC has an `objects` list, and its tail is taken on every `PLAYER_ENTERING_WORLD` | stand aside, then per frame: its pack box for a listed name, take unregistered otherwise |
| **Blizzard's own** | `FrameRegistry.UpdateBlizzardFrames`, the `CompactUnitFrame_SetUpFrame` hook | the client's own unit frames and compact frames | nothing but the seven per frame boxes |

The hooks that feed the name door are `SecureHandlerWrapScript`, `SecureHandlerSetFrameRef`,
`RegisterStateDriver`, `RegisterAttributeDriver`, `SecureUnitButton_OnLoad`, `RegisterUnitWatch`
and `UnitFrame_Initialize`. The last three are installed only if the global exists. A pack is free
to skip any single one of them, which is why there are seven.

**Every hook in both files is installed at file scope, whatever the switches say.** The switches
are only readable from `InitDB` onward, so a hook that was not installed at load could not be
installed later without a reload. Each door asks at its own first line instead.

## 2. The switches

| Switch | Written | Read | Absent means |
|---|---|---|---|
| `StandsAsideForClique()` | `db.workAlongsideClique`, option row `Use Alongside Clique`, `REQUIRES_RELOAD` | `Profile.lua`, copied in `InitDB` | Clique installed and the option unticked is "stand aside". Before `InitDB` the answer is "stand aside" |
| `TakesUnregisteredFrames()` | `db.takeUnregisteredFrames`, `REQUIRES_RELOAD` | same | on. Before `InitDB` the answer is "take" |
| `TakesPackFrames(addon)` | `db.packFrames[addon]`, one box per installed known pack | asked once inside `RegisterFrame` | on |
| `Options.blizzframes[category]` | seven boxes | `registerBlizzardFrame` | on |

`StandsAsideForClique()` is false whenever Clique is not installed, whatever the option says.
`CliqueDetected` itself is now asked in exactly two places: whether to load `DebindCliqueFake`
(`Public.lua`) and whether to build the option row (`Options.lua`).

**The pack switch is asked in `RegisterFrame` and nowhere else**, so it covers every door at once,
the header door included. A frame whose name matches no row in `KNOWN_PACK_FRAMES` is not any
pack's, and what decides those is `TakesUnregisteredFrames` at the door.

**A pack box that is on is the whole answer for that pack** (`legacy/making-the-pack-box-own-its-addon.md`).
The doors nobody hands a frame through, and the holder question in §4, ask
`TakesUnofferedFrame(frame)` of each frame: a listed name is its pack box's whatever the wider option
says, and only a name no row covers is the wider option's. So `Use Unit Frames Addons Keep to
Themselves` decides the addons we cannot name, and nothing else.

## 3. What the funnel does

`RegisterFrame(button, type)`, in order:

1. Pack switch. A frame belonging to a pack the reader turned off gets no row at all.
2. `ccframes[button] == false` means we already wrote the frame off; return.
3. An existing row settles it, unless the row's `frameType` is `unknown` or the caller can say
   something the row does not. `unknown` never closes the question, because a frame library
   commonly registers from its styling pass and writes the unit attribute after it.
4. Refusals, each of which writes `false` and is remembered for the session: not protected,
   forbidden, anchoring restricted, no `RegisterForClicks`.
5. Combat: the call goes into `FrameQueue` with its arguments, `QueuedFrameOp` records the last
   word for that frame, and the first entry of a fight puts one line in chat. The queue drains in
   arrival order at `PLAYER_REGEN_ENABLED`.
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

`UnregisterFrame` honours a deregistration from anywhere, with two exceptions. An `hd` row is the
header door's, and only the header takes it back. And a frame `TakesUnofferedFrame` answers yes
for is not let go at all, whoever asks (`KeepsFrameOnRelease`): an addon reclaiming a frame has
decided to run it itself, which is what a listed pack's box covers for that pack and what
`Use Unit Frames Addons Keep to Themselves` covers for every other name. With that option off, a
name no row covers is let go on its owner's word.

## 4. The table door, in detail

`ClickCastFrames` is the global every click casting aware unit frame addon writes into. Two shapes
are possible and `AttachClickCastFrames` decides between them on every pass:

- **The name is free**, meaning the global is a plain table, absent, or carries a metatable with no
  `__newindex`. We put our own table there, with `__newindex` registering and deregistering and
  `__index` answering out of a store kept beside the table. Whatever was in the old table is
  adopted. Answering reads back matters: an addon takes a frame back with
  `if ClickCastFrames[frame] then ClickCastFrames[frame] = nil end`, and a table that answers nil
  never sees that write.
- **Somebody is holding it**, meaning a `__newindex` is already there. We do not take the name.
  We wrap that metatable's `__newindex` and `__index`, run the holder's original first, and ask the
  holder what it decided for each frame (`AskHolder`). A holder that answered for a frame is
  standing on it; a holder that filed the write and dropped it left the frame with nobody on it.
  A frame the holder kept is registered too when `TakesUnofferedFrame` says so: always for a
  listed pack whose box is on, and otherwise while `Use Unit Frames Addons Keep to Themselves` is
  on, since two engines on one frame is handled by `Reassemble`. Off, only what the holder dropped
  and the listed packs come to us.
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

`AskHolderAgain` re-asks the holder about every frame we stood down on and every non `hd` row we
hold, at `PLAYER_ENTERING_WORLD` and `PLAYER_REGEN_ENABLED`. That is the only thing that hears a
holder's decision move without a write: its own hover casting being switched off, for instance.

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
hands a frame through. A frame on the name list is its pack box's at every one of them; a frame no
row names stands behind `Use Unit Frames Addons Keep to Themselves`:

- the **name** door, if the frame's name matches a `KNOWN_PACK_FRAMES` row and the frame passes one
  of the seven hooked calls;
- the **header children** door, if the frames are children of a real `SecureGroupHeaderTemplate` or
  `SecureGroupPetHeaderTemplate` header;
- the **oUF** door, if the pack ships oUF and declares `X-oUF`.

An addon that matches none of the three is invisible to us, and there is no fourth way. See §7.

### 5.3 The addon holds the Clique name and shows nothing through it

Three sub cases, and they differ only in what `__index` answers:

- **A proxy that answers for its own frames.** `HolderAnswer` reads through the metatable's
  original `__index`, never through our wrapper, so what comes back is the holder's own opinion. A
  truthy answer is "this frame is mine".
- **A proxy that answers nothing** (a `__newindex` and no `__index`). `HolderAnswer` returns nil
  for every frame, so every frame that passes through the table reads as dropped and we take all
  of them. Clique has this shape, but Clique is not asked at all (§5.5): its frames are ours by
  rule, not by what its proxy happens to answer.
- **A proxy locked with `__metatable`.** We never touch it. The table door is closed for that
  session and only the other doors can reach anything.

In every one of the three, frames the holder keeps in an upvalue store and never puts in the table
are invisible to `pairs`, so a frame registered into a foreign proxy before we wrapped it is heard
only if a later write or a later `AskHolder` reaches it.

### 5.4 Clique is installed and `Use Alongside Clique` is off

This is the default, and it is what every Clique user had before the option existed.

- `DebindCliqueFake` does not load. `_G.Clique`, `_G.ClickCastHeader` and `ClickCastUnitTemplate`
  are Clique's.
- Table door, name door, header children door and oUF door all return at their first line.
- `ApplyStandAsideForClique` (`SecureBindings.lua`) blanks our `clickcast_register` and
  `clickcast_unregister`, and gives `GetHoveredUnit` a fallback: our own `States.unitframe` first,
  and only where we hold no row Clique's header `danglingButton`, which yields a unit token and
  nothing else: no frame type, no reaction, no role.
- **Blizzard's own frames are still ours.** Blizzard handed its unit frames to nobody; Clique picks
  them up itself and so do we, and both of us going through `ClickCastFrames` on the way is
  Clique's implementation rather than a door the frame came in by. So hover bindings, the hover
  twin and `frameTypes` conditions all work over those seven, and nothing is graded as blocked by
  Clique any more.
- The UI follows the doors: the pack boxes and `Use Unit Frames Addons Keep to Themselves` are
  greyed with `Cannot be used with Clique!`, while the seven Blizzard boxes, the click edge and
  the `Use Alongside Clique` row itself stay live.

### 5.5 Clique is installed and `Use Alongside Clique` is on

- `DebindCliqueFake` still does not load, so the three Clique names stay Clique's. Our own header
  door is therefore unreachable, and addons wiring a header to `Clique.header` wire it to Clique.
- The **table door** attaches to Clique's proxy as a holder, from `InitDB` (the file-scope pass
  answered "stand aside" because the option was not readable yet). Clique as the holder is not
  asked what it kept: a frame written into Clique's table was handed to somebody, so every one of
  them is ours as well whatever the wider option says (`AskHolder`). Clique is recognised by its
  table, read off the global in `InitDB` (`RememberCliqueTable`): Clique installs it at its own
  `ADDON_LOADED`, ahead of ours, and a pack that later puts its proxy over it is a different
  holder and is asked like any other. Frames written before the attach sit in `Clique.ccframes`
  and nowhere else, and `AttachCliqueHeader` sweeps that list.
- The **Clique header door** replaces ours: `AttachCliqueHeader` hooks `OnAttributeChanged` on
  Clique's header and reads `export_register` and `export_unregister`, which is how Clique itself
  gets the registration out of the restricted environment, and hands the name to our own
  `OnClickCastRegister`, so the row is the header's and is written a tick later. Frames already in
  `Clique.hccframes` when we attach are taken then, since that is the window we were not
  listening in.
- The name, header children and oUF doors are open.
- Both engines end up on one frame. We take the top and replay what was above us, so Clique's
  bodies still run. If we are pushed off repeatedly, `StandDown` leaves that frame to Clique. The
  tooltip says "should still" for exactly that reason: it is the intent, not a guarantee.

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
  their own tokens would read as something else. The `nil` it writes for each frame on the way
  into this state reaches `UnregisterFrame` and changes nothing while its pack box is on, so the
  rows from the engine-off state simply stay.
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
and the proxy shape are internal to that addon. If either changes, our door goes quiet with nothing
raised, and what is left is the same board as the option being off.

### An addon we have never seen

It reaches us if it does any one of: writing into `ClickCastFrames`, speaking the header protocol,
building its frames on a real secure group header, shipping oUF with `X-oUF` declared. If it does
none of those, and its frame names match no row, nothing reaches us at all. Adding a row to
`KNOWN_PACK_FRAMES` is the whole of what taking a new pack costs.

## 7. The holes

Each of these is understood and none of them raises anything.

1. **A holder that keeps its store in an upvalue and never writes into the table** hides every
   registration it received before we wrapped its metatable. `pairs` over such a proxy yields
   nothing, so no later pass can recover them; only a fresh write or an `AskHolderAgain` sweep over
   frames we already know about can reach one.
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
7. **A holder's decision moving is only heard at two events** plus a foreign wrap. Between them, a
   frame the holder let go stays unregistered by us and a frame it took stays ours.
8. **`export_register` is Clique's internal wiring.** A rename leaves the Clique header door silent.
9. **`clickcast_register` cannot carry a nameless frame.** `CallMethod` scrubs its arguments to
   strings, numbers and booleans, so a header with no name of its own makes children with no names
   and none of them can come through that door. Clique has the same limit. `CollectHeaderChildren`
   reaches those by object and needs no name.
10. **A pack that runs its own engine, offers nothing, uses no secure group header and no oUF, and
    whose names we do not know, is unreachable.** No hook can be made to answer for it: the test
    would have to be right about an addon we have never seen.
11. **Two engines on one frame is an intent, not a guarantee.** A pack that re-wraps because it was
    wrapped over spends the reassembly budget and we step off that frame, once with a chat line.

## 8. What holds this true

`tests/frames_spec.lua` and `tests/holder_spec.lua` carry the headless half: the doors opening and
closing on each switch, the holder machinery against a proxy of every shape above, the read back
through both our own table and a holder's, the hand over, the re-ask, and the Clique header door
including what was already in `hccframes` at attach time.

What only the game can answer: whether the holder machinery attaches to the real Clique proxy,
whether the `export_register` hook actually fires, and whether two engines both run on one frame.
Those are in `/debtest`.

What neither can see: another addon changing the shape we read. Every third party detail in §6 is
that addon's internal wiring, and none of it was promised to us.
