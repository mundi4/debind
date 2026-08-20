# When a change takes effect — what runs before the call returns, and what waits for a later frame

Written while cutting the fixed waits out of `/debtest`, but it is not about the tests. It is
about **when a thing you just did becomes true**, which is the question behind "I set it and read
back the old value" in a test, in the UI, and at a `/dump` in the game.

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
-> `DebindPrivate.Units`, `OnSwitchChanged`, the DebindTest probes) has landed by the time the
`SecureHandlerExecute` that ran the snippet returns.

**Attribute writes fire `_onattributechanged` inline.** A `self:SetAttribute(...)` from inside a
snippet runs the handler then and there, and it nests — the handler's own writes fire their
handlers before it continues.

**Bindings from the restricted environment are real bindings immediately.**
`HANDLE:SetBindingClick` / `SetBinding` / `ClearBinding` call `SetOverrideBindingClick` and friends
directly, so `GetBindingAction(key, true)` answers with the new binding on the next line.

**`DebindPrivate.UpdateBindings()` finishes everything, including the state pass.** Its tail (the
"execute UpdateBindings with forceAll set" block) sets `state-unitexists` on the driver itself,
which by the above runs `_onattributechanged` -> recompute every measured state -> the
`UpdateBindings` snippet -> the actual bindings. Nothing is left over for the poll to finish. This
is why a test can call `UpdateBindings()` and compare `GetBindingAction` on the next line, and why
`SetMockState` (which ends in a rebuild) needs nothing after it.

---

## Deferred — needs at least one more frame

**A *queued* rebuild.** `QueueUpdateBindings` sets `updateBindingsQueued` and hands the work to
`C_Timer.After(0)`, so it lands next frame. Ask `DebindPrivate.IsUpdateBindingsQueued()`. Note the
flag is cleared **before** the rebuild runs, so "queue is empty" does not mean "the rebuild has
finished" — that is why `/debtest`'s `WaitForIdle` gives up one frame after the flag clears.

Direct `DebindPrivate.UpdateBindings()` does not go through this. Only `QueueUpdateBindings` does.

**Blizzard's state driver poll — the only genuine clock in the system.**
`SecureStateDriverManager` (`Blizzard_FrameXML/SecureStateDriver.lua`) runs on an OnUpdate throttled
to `STATE_DRIVER_UPDATE_THROTTLE`, default `0.2`, settable through its `updatetime` attribute —
which Debind writes (`ApplyOptions("stateDriverUpdateThrottle")`, clamped to at most 0.2, and only
lowered while a hover/mouseover axis is actually measured).

Two things about it are worth knowing:

* **Events on its own list reset the timer to zero**, so the next frame resolves everything —
  `MODIFIER_STATE_CHANGED`, `UPDATE_MOUSEOVER_UNIT`, `UNIT_FACTION`, and the rest Debind registers
  in `UpdateBindings.lua`. That is why some changes look instant in the game and the same change
  looks slow when a test makes it happen without an event.
* **This poll is what drives Debind's whole state pass.** `Debind.lua` calls
  `RegisterUnitWatch(BindingDriver, true)` — not because the driver has a unit, but because a
  watched frame gets `state-unitexists` written on every pass. Blizzard writes the unit's existence
  (`false` here) and Debind's `_onattributechanged` writes `0` back, so the two never agree and the
  handler fires every single tick.

So: anything that is only noticed by that poll — a unit appearing or going away under a cursor that
never moved, a real world state changing with no event behind it — costs up to `updatetime` and
nothing can shorten it.

---

## What this means for `/debtest`

There is **no fixed-duration wait left in `DebindTest.lua`**, and it is worth keeping it that way.
Every one that used to be there (thirty-odd `Wait(0.4)`) was waiting for something that had already
happened; the file's header comment justified them with four claims about asynchrony, three of
which were wrong. The sweep tests alone were spending ~15s each on it.

The helpers, and what each is actually for:

| | waits for |
|---|---|
| `WaitUntil(pred, limit)` | the primitive — asks `pred` **before** the first yield, so an already-true condition costs nothing |
| `WaitForIdle()` | a queued rebuild, plus one frame for the one that just ran |
| `WaitForMembership()` / `WaitForWinner()` / `WaitForEvalAnswer()` | a snippet's answer. Already there in practice; the wait is what makes "no answer at all" cost the limit instead of hanging |
| `WaitForHoverSlot(filled)` | the hover mirror. Free after `HoverEnter`/`HoverLeave`; a real wait after `SetFrameUnit`, where only the poll notices |

Two traps to keep in mind when writing one of these:

**Do not wait for the thing you are about to assert.** `WaitUntil(binding == expected)` followed by
`if binding ~= expected then Fail` still fails correctly, but it can only fail by timing out, and
where the expected value is also the *current* value the wait returns instantly and the assertion
proves nothing. `WaitForHoverSlot` asks whether the slot is filled and deliberately not *which
unit*, for exactly this reason.

**Waiting can be the weaker test.** In "hover slot survives a rebuild", the poll picks a wiped slot
back up within a tick — so giving the test any time at all lets it read the recovered value and
pass over the bug. That assertion runs with no yield between the rebuild and the read.
