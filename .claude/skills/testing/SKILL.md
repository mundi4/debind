---
name: testing
description: How to test a change in this WoW addon. Load this before deciding how to verify any code you write or change here - which of the three layers (headless specs, static checks, in-game DebindTest) can actually catch the mistake, how to write a test in each, and what the checks cannot see. Triggers - writing or changing Lua in Debind/ or DebindTest/, adding a secure snippet, touching bindings/solver/profile code, being asked whether a change works, or reporting a change as done.
---

Read `devdocs/testing.md` before choosing how to verify a change.

The short version, so you know whether you need the full document:

- **Three layers see different things.** `npm test` (headless, pure logic), `npm run check`
  (static, includes the snippet golden), `/debtest` (in the game, the only layer that sees the
  restricted environment). Pick the cheapest layer that could catch the mistake you are capable of
  making here.
- **`npm run check` passing is not "it works."** It cannot see the game. Never report a UI or
  in-game change as done before someone has run `/debtest`.
- **Failures in the secure layer are quiet.** A snippet that fails to compile does not error - it
  never attaches, and one key stops working.

The full document covers how to add a headless spec, the two golden rules for probes, the in-game
kit's API (`Wait`, `AddTeardown`, `SetMockState`, `CreateTestUnitFrame`, `PressKey`/`LastWinner`,
`RequestReload`), why waiting is not optional, and the rules that came from real failures.
