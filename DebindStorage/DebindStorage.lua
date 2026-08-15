local _, DebindStorage = ...;

--- Debind's internals, caught as this addon loads.
---
--- Debind parks its private table on `_G` for the length of the `LoadAddOn` call and takes it back
--- down the moment that call returns, so this line runs inside the only window where the global
--- exists. Reading it later would find nothing. `DebindCliqueFake` reaches across the same way.
DebindStorage.DebindPrivate = DebindPrivate;

--- And back the other way, in the same instant.
---
--- **The two panels live in Debind now and this addon is still load on demand**, so they are read
--- at login and this is not. They cannot hold a local to this table; they read `DebindPrivate.Store`
--- at the moment of the call, and the moment this line runs is what makes that answer.
---
--- `Store` names the job and not the addon, so the folder is free to be renamed without a call site
--- moving (`devdocs/building-export-import.md`).
DebindPrivate.Store = DebindStorage;
