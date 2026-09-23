<!--
**A help page in format only** (2026-09-23, owner). It is baked and drawn like the rest because it uses the same window, but it is skimmed once: what changed, and which page to look up. A mechanism explained here is explained twice, and the second copy is the one nobody updates.

**So a section is a sentence or two and a link.** The urge to teach the thing on the spot is what has to be resisted every time this page is edited.

**A link may not be the subject of a sentence** (review, 2026-09-23). `[](hover-cast.md)` bakes to that page's title, so "[](hover-cast.md) is that row on its own" comes out as "What is Hover Cast? is that row on its own". The link goes at the end of a clause that does not need it as a subject.

**What earns an entry**: something the reader will meet on screen or in their own keys. Not what moved inside the addon, and not something new they would go and find on their own.

**When this page opens is not written here**, it is `showing-the-changelog-on-login.md`.

**The title says what the page is and which release it covers** (2026-09-23, owner). It goes to the dropdown, where it stands in one list with pages that are about the addon itself, and a title describing what changed reads there as another one of those. *What's New* is the client's own wording for this (`GAMEMENU_NEW_BUTTON`, `SPLASH_BASE_HEADER`).

What that costs is a number that goes stale on its own, so raising it is on the release list (`cutting-a-release.md`) beside `Constants.CHANGELOG_VERSION`, which is what decides whose login opens this page.

**This page uses section headings** (`writing-a-help-page.md`). No control on screen opens it, and the headings are the whole skim path, so each one says what changed rather than naming a feature.

**The key that stopped working comes first** (2026-09-22, owner, `0-DIARY.md`). That reader is looking at a keybinding that does nothing and has no reason to think it is a setting. This page is what hands them the question.

**The conversion has a heading of its own, and the heading is what the converted reader is looking for** (review, 2026-09-23). It was headed `Hover Cast starts off` once, which told that reader their click casting had come back off; it was then folded into the Cast Options section, which left them nothing to stop at on a skim. They are the one reader here whose setup changed without them touching it.

**Value names are read off the menu, never off the design notes.** This page said once that Off was one word on all three Cast Options rows; the menu says `Skip this action` on the two key rows (`CASTING_SKIP`).

**The unit frame limit stands in the body** (2026-09-23, owner). Debind reaches the frames of addons it knows by name, and a sentence saying every unit frame promises what no list of packs can keep.

**Two marks were an entry here and both came out** (2026-09-23, owner on the second). `BINDING_ISSUE_NOTHING_RUNS` is met only by a reader who has just set it and is looking at the row that explains it. The bare click one is not new: v3.5.2 already raised `NOT_SUPPORTED_MOUSE_BUTTON` on the same action (`ActionHoverIsOn` folded [when the unit doesn't exist] to false there too).

**The root `CHANGELOG.md` is the long form of the same release and is not the source.** Its 4.0 section holds entries this page deliberately leaves out.
-->

# What's New in 4.0

# A key with nothing to run no longer goes to WoW

Press a key whose actions all fail their conditions and the key does nothing. Until this update WoW's own binding for that key ran, so an action bar key still pressed its button. To catch those presses again, leave the last action on the key without conditions, and which one is last is in [](ordering.md).

# Use WoW's Own Binding is retired

It does nothing on a press and cannot be added any more. One saved on a key reads *Needs fixing* in the *Overview* tab and still holds that key, so an action under it does not run either. Every other *Binding Command* action is in the same state, except one that pressed an action bar button, which was moved across and works as it did.

# The order on a key no longer counts conditions

An action with conditions used to be tried before one without, and one that ran over a unit frame stood above both. Neither step is there now, so nothing about an action's conditions moves it in the list. The keys whose order moved on this character are marked in the *Overview* tab, where *Run Order Changed* says how many, and the order they are in now is in [](ordering.md).

> *Use the old run order* in Debind's settings puts the old order back for the whole account.

An action set to *Hover Cast* still runs ahead of the others while you point at a unit. That is decided at the press now, so the list no longer shows it above them.

# What each press does is set on the action

*Cast Options* in an action's right-click menu sets what that action does on each kind of press. It holds four rows, *Self Cast Key*, *Focus Cast Key*, *Hover Cast* and *Normal Cast*, and everything you already have does what it did. The four are gone through in [](cast-options.md).

# Unit frame actions now use Hover Cast

*Hover Cast* sends an action to the unit you point at while you are pointing at one, and leaves it where it would go otherwise. An action that carried a *Unit Frame* condition now carries *Hover Cast* on *Unit Frames* instead and works as it did, and an action you make from now on starts with it set to *Off*. That row has a page of its own, [](hover-cast.md).

# A unit picked under Target now holds on every press

Pick a unit under *Target* and the action goes there on every press that runs it. Neither cast key moves it, the unit you point at does not move it, and Auto Self Cast no longer sends the spell back to you when the unit you picked cannot take it. With nothing picked there a held cast key comes before the unit you point at, which is the other way round from WoW's own settings, and the order in full is in [](targeting.md).

# An action can be turned off

*Turn this action off* is new, in the action's right-click menu. The action stops running and keeps the key it is on, its conditions and its place in the order.

# Debind works on more of your unit frames

Debind now binds its keys on a frame another addon is hover casting on, and on the frames it used to leave to Clique. That addon keeps doing what it did, and where you have the same key bound in both, Debind's is what fires. This reaches the addons Debind knows by name, which *Unit Frame Support* in Debind's settings lists.
