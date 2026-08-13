local _, DebindShare = ...;

--- Debind's internals, caught as this addon loads.
---
--- Debind parks its private table on `_G` for the length of the `LoadAddOn` call and takes it back
--- down the moment that call returns, so this line runs inside the only window where the global
--- exists. Reading it later would find nothing. `DebindCliqueFake` reaches across the same way.
DebindShare.DebindPrivate = DebindPrivate;
