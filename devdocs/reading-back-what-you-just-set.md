# Reading back what you just set: what is true before the call returns, and what waits for a later frame

Written while cutting the fixed waits out of `/debtest`, but it is not about the tests. It is
about **when a thing you just did becomes true**, which is the question behind "I set it and read
back the old value" in a test, in the UI, and at a `/dump` in the game.

This is not the question of when an option the user changed reaches the game. That one is about
rebuilds and combat lockdown, and it is answered in `testing-a-change.md` and in the code around
`QueueUpdateBindings`. This file is about a single call and the frame it runs in.

The short answer is that almost all of it is synchronous, including the parts that look like they
could not be. Two things are not.

---

## Synchronous — true by the time the call returns

**`SecureHandlerExecute(frame, body)`** runs the body before it returns. Same for
`RunAttribute` / `RunFor` inside one.

**`CallMethod` is not a queue.** `HANDLE:CallMethod`
(`Blizzard_RestrictedAddOnEnvironment/RestrictedFrames.lua`) is `securecall(pcall, ...)` straight
onto the method — the Blizzard comment above it says it exists to avoid the overhead of hooking
`OnAttributeChanged`. So anything a snippet mirrors out to the insecure side (`OnSpecialUnitChanged`
-> `DebindPrivate.Units`, `OnSwitchChanged`, the DebindDev probes) has landed by the time the
`SecureHandlerExecute` that ran the snippet returns.

**Attribute writes fire `_onattributechanged` inline.** A `self:SetAttribute(...)` from inside a
snippet runs the handler then and there, and it nests — the handler's own writes fire their
handlers before it continues.

**Bindings from the restricted environment are real bindings immediately.**
`HANDLE:SetBindingClick` / `SetBinding` / `ClearBinding` call `SetOverrideBindingClick` and friends
directly, so `GetBindingAction(key, true)` answers with the new binding on the next line.

**`DebindPrivate.UpdateBindings()` finishes everything.** It runs every snippet it built through
`SecureHandlerExecute` on the way out, and by the above that means the bindings are real before it
returns. Nothing is left over for a later frame to finish. This is why a test can call
`UpdateBindings()` and compare `GetBindingAction` on the next line, and why `SetMockState` (which
ends in a rebuild) needs nothing after it.

---

## Deferred — needs at least one more frame

**A *queued* rebuild.** `QueueUpdateBindings` sets `updateBindingsQueued` and hands the work to
`C_Timer.After(0)`, so it lands next frame. Ask `DebindPrivate.IsUpdateBindingsQueued()`. Note the
flag is cleared **before** the rebuild runs, so "queue is empty" does not mean "the rebuild has
finished" — that is why `/debtest`'s `WaitForIdle` gives up one frame after the flag clears.

Direct `DebindPrivate.UpdateBindings()` does not go through this. Only `QueueUpdateBindings` does.

**Blizzard's state driver poll — the only genuine clock in the system.**
`SecureStateDriverManager` (`Blizzard_FrameXML/SecureStateDriver.lua`) runs on an OnUpdate throttled
to `STATE_DRIVER_UPDATE_THROTTLE`, default `0.2`, settable through its `updatetime` attribute.
**Debind does not write it** (2026-09-19): the attribute is shared with every other addon, and
every moment of ours that the manager carries arrives as an event, which zeroes its timer anyway.
A stored `stateDriverUpdateThrottle` from the build that had a slider for it is read by nothing.

Two things about it are worth knowing:

* **Events on its own list reset the timer to zero**, so the next frame resolves everything. What
  Debind registers there is the bar and pet battle events behind Keys Given Back
  (`CollectDriverEvents`), and those are what make the `state-giveback` attribute driver resolve
  promptly.
* **Nothing of Debind's rides the poll itself.** The driver was registered with
  `RegisterUnitWatch(BindingDriver, true)` until the state pass went, which is what got
  `state-unitexists` written on every tick; now every condition is measured at the press and the
  frame is registered nowhere.

**The lockdown itself, after `PLAYER_REGEN_DISABLED`.** The event arrives first and **the lockdown
has not begun when it does** — this is not the flag lagging behind the restriction, the two move
together. Measured 2026-09-09 with a one-shot probe: in the handler
`InCombatLockdown()` answers false *and* a `SetAttribute` on a secure action button still lands; at
the next `OnUpdate` the flag answers true and the same write is refused. Logging in during a fight
is the same shape from the other side — 160ms and no frame at all between the event and the first
one that answers true (`Events.lua`, `PLAYER_LOGIN`).

Two things follow.

* **A handler for that event may not ask the flag whether a fight is on.** It gets a truthful "not
  locked", which is a different question, and that drew the switch toggle enabled at the moment it
  had to go dead (`SwitchesUI.lua`, `DebindSwitchesPanelMixin:OnEvent`). The event is the answer. Blizzard reads
  the flag inside no regen handler of its own.
* **Protected work started from that handler still lands.** The window is real, not a race won by
  luck: the restriction is measurably off for the whole of the dispatch.

**A refused protected call does not raise.** It fires `ADDON_ACTION_BLOCKED` and the call quietly
does nothing, so `pcall` around one answers "ok" either way. Writing a value and reading it straight
back is the only oracle.

So: anything that is only noticed by that poll — a state the manager resolves with no event behind
it — costs up to `updatetime` and nothing can shorten it. Nothing of Debind's is in that class any
more: a condition is measured at the press, and the attribute driver behind Keys Given Back moves
on events the manager is registered for.

---

## Where the test side of this lives

`devdocs/testing-a-change.md` owns what `/debtest` does about it: the wait helpers, what each one
waits on, and the two ways a wait makes a test weaker. It used to be repeated here as well, and two
copies of one table is one copy too many. Read this file for what is true when, and that one before
adding a wait.
