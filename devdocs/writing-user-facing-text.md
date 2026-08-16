# Writing user-facing text — what the words may say, and what the locale files demand

Everything that reaches a person through `L[...]`: the window, tooltips, dialogs, chat output, and
whatever a slash command prints back. Read this before adding or rewording a string.

Code comments are the other side of the same coin and are **not** covered here — CLAUDE.md's 용어
section draws that line, and it is the one rule from there worth repeating: a comment must use the
code's names, and a string must not.

---

## Who is reading it

Someone who has never seen the code and never will. They know keys, actions, classes, specs, and
characters, because those are theirs. They do not know about snippets, attributes, handlers,
rebuilds, layers-as-a-data-structure, or the restricted environment, and a sentence that only makes
sense once you know one of those is a broken sentence no matter how accurate it is.

**Say it in the game's words, not ours.** When the client already has a name for the thing, take
that name — `Locales/koKR.lua`'s header carries the worked examples, and they are not cosmetic:

* WoW's Korean client says **개체**, never "유닛". And to a Korean player 프레임 is frames per second
  — "프레임 안 나온다", "프레임 쩐다" is how the word is actually used. So a unit frame is a
  **개체창** (`UNITFRAME_LABEL`), and "유닛 프레임" is wrong even though every addon user in an
  English forum would recognise it. (The 프레임 half is about the reader's ear, not the client's
  usage — the client does say 프레임 for a UI frame in the settings panels, which is not where
  anyone picks the word up.)
* `stance` is **태세** (`TUTORIAL61_WARRIOR = "방어 태세"`). 자세 is `detailed` in that client.
* `reaction` has **no client word at all**, and that is itself the answer. No GlobalString key
  carries the concept; the client names the values instead — 우호적 / 적대적 / 중립적
  (`COLORBLIND_FRIENDLY` / `_HOSTILE` / `_NEUTRAL`). Naming the values beats coining an abstract
  noun for the axis, because 반응 in Korean reads closer to "responsiveness" than to where a unit
  stands toward you. `L["CONDITION_REACTIONS"]` is 반응 today and predates this.

  **That entry is also how a note goes stale.** `koKR.lua`'s header justified 반응 by citing
  `OPTION_TOOLTIP_USE_COLORBLIND_MODE`, which said "unit reactions" when it was written and, as of
  12.1.0, says "Adds additional information to tooltips and several other interfaces." The word is
  gone from the client. It could be checked at all only because the note named the key — a note
  saying "the client uses this word" without one cannot be re-verified by anybody.

Check the client's own strings before inventing a word. They are on disk, one file per locale:
`reference/globalstrings/{enUS,koKR,ruRU}.lua`, refreshed by `npm run globalstrings`, with
`SOURCE.txt` beside them naming the build. If the addon coins its own word instead, the game and the
addon end up calling one thing two things, in front of a user who has no way to know they are the
same.

**Look up the key, not the word — in that order.**

1. Find the **key** whose English value carries the concept you mean, in `enUS.lua` or in
   `reference/wow-ui-source/`. Confirm it by where the interface code uses it. An English word does
   not pin a concept down either: two keys can hold the same word for different things, and a word
   the client used for one thing years ago can belong to another now.
2. Read **that key** in `koKR.lua` and `ruRU.lua`.

The key is the identity; the words on both sides are only its values. The three files are
line-for-line parallel, so the second step is exact — `UNITFRAME_LABEL` is line 22679 in all three
and reads "Unit Frames" / "개체창" / "Рамки портретов".

**Never grep a locale file for a word you guessed.** That is the same search run backwards, and it
lands on homonyms instead of on the concept: 자세 appears 44 times in `koKR.lua` and nearly every one
is 자세한/자세히, "detailed". A hit proves the word exists somewhere, which was never the question.

**When the client owns the whole sentence, take the sentence.** `L["BIND_MODE_UNBIND_HINT"] =
ESCAPE_TO_UNBIND` and `L["OVERVIEW_NO_KEY"] = NOT_BOUND` are assignments in **enUS only** — every
other client already holds those words in its own language, so there is nothing left to translate
and the game changing its wording carries us along. The consequence: no locale file may
hand-translate them into a second wording that can then disagree with the client inside one window.

---

## Register, in Korean

Sentences that **ask or instruct** use 해요체 — "켜 주세요", not "켜십시오". This is a game addon,
not a government form, and 하십시오체 does not sound like the distance this addon keeps from its
user. Statements of fact ("~합니다", "~없습니다") are unaffected; the rule is about the asking.

`koKR.lua` does not fully obey this yet — "십시오" survives in about fourteen places
(`BIND_MODE_OVERLAY`, `CUSTOM_STATE_EDIT_VALUE`, `CUSTOM_TARGET_HELP_MESSAGE_*` and others as of
2026-08-14). **That is debt, not precedent.** Write new strings the right way, and do not sweep the
old ones unless asked — the owner intends to go through them.

---

## Length is a property of the position, not of the string

| where | budget |
|---|---|
| tooltips | long is fine — see below |
| chat output | one line, it scrolls away |
| buttons, tabs, column headers, labels | short, and shorter than you think |
| empty-list text | say **what fills it**, not that it is empty |

**A tooltip is where discovery lives.** The user hovered — they asked for this text and are ready
to read it. Never trim a tooltip for length; trim it only when a sentence is not carrying meaning.
`GameTooltip_AddInstructionLine` wraps by default, so a long sentence makes the tooltip taller, not
wider. The cost that actually matters is **the number of instruction lines**: a follow-on clause
about the same gesture stays on that gesture's line instead of standing up a new one.

Do not use "anything invisible on screen belongs in a HelpTip, not a tooltip" as a rule. A HelpTip
fires once and is dismissed forever; anything a user may want to look up again has to live in the
tooltip too, even if a balloon also says it.

---

## Colour

Use the **client's colour names** — `|cnRED_FONT_COLOR:...|r`. The only raw hex in the locale files
is `_MESSAGE_PREFIX`, which is the addon's own colour and the one thing that is ours to pick. The
rest belong to the game and should change when the game changes them. Mixing the two forms once
left the addon with several different reds all meaning "bad".

---

## Where the strings live

Three files, loaded in this order by `Debind/locales.xml`:

```
Locales/enUS.lua    creates the table; every key must exist here
Locales/koKR.lua    returns early unless GetLocale() matches; overwrites what it translates
Locales/ruRU.lua    same
```

That order is the fallback mechanism. A key translated nowhere still comes out **in English**,
because enUS already wrote it. A key missing from **enUS** is the bad case: the table's `__index`
returns the key itself, so the screen shows `ORDER_DESC` with no error anywhere. That has shipped.

`DebindShare` has no locale files of its own — it reads the same table through `DebindPrivate.L`,
so its strings go in `Debind/Locales/` with everything else.

**ruRU is a translator's file** (ZamestoTV). We leave new keys out of it; we do not
machine-translate into it.

**Do not propose going back to the translator.** Not to ask for the missing keys, not to ask for a
reword, not "while we are at it". A volunteer decides their own timing, and a queue that grows is
the expected state of that file, not a problem to escalate. English is a working answer for every
key in it, which is what the load order above already makes true.

---

## enUS is the only file that has to be complete

**Every key exists in `enUS.lua`, and the enUS wording is where the work goes.** koKR and ruRU are
neither important nor urgent. They are behind and they are meant to be.

So **when no wording comes to mind for a locale, leave the key out of it** and let the fallback
carry English into that window. Do not machine-translate to fill the hole, do not park an
approximate line there intending to come back, and do not register the absence anywhere. An English
line in a Korean window is visibly untranslated and costs the reader nothing; a Korean line that
describes the wrong behaviour reads as authoritative and no check can see it.

**Which keys a locale is behind on is a question asked by hand, when the owner decides to ask it**
— `npm run check:locales -- --missing` lists them. The plain run prints the count and passes. There
is no list to add a key to: the check used to demand a line per untranslated key, which meant a
second edit for every new string and told nobody anything the count does not already say.

---

## What `npm run check:locales` enforces

It reads the three files as text and compares them to enUS. It fails on:

* **stale keys** — present in a locale, gone from enUS. Harmless on screen, which is the problem:
  the next person assumes the string is still in use and edits it;
* **duplicate keys** in one file;
* **placeholder mismatches**, including argument *order*.

All three are about what a locale **does** carry. What it does not carry is printed as a count and
does not fail the run — that is the fallback working. A key missing from **enUS** is the absence
that matters, and this check is the wrong place to look for it: enUS is the yardstick here, so
nothing compares the code's `L[...]` reads against the table.

**The placeholder rules**, which apply to enUS first:

* Two placeholders of the same conversion in one string must be **numbered** (`%1$s`, `%2$s`).
  Unnumbered, a translation that swaps them produces `%s%s` either way, `format()` does not fail,
  and the screen simply shows the two values in each other's place. Different conversions (`%s` and
  `%d`) need no numbers, since a swap is visible on its own.
* Numbered and unnumbered forms may not be mixed in one string.
* A locale may legitimately need a **different order or an extra argument** — Korean often does,
  where English can point at something the tooltip title already said. That goes in
  `EXTRA_SPECS_OK`, whose value is the full expected placeholder string for that locale (**not** a
  waiver), plus a line naming the call site that passes the argument.

---

## When behaviour changes, the strings that describe it change in the same edit

This is the failure this file exists for, because **no check can see it**. The key exists, the Lua
parses, the placeholders line up, and the sentence is a lie. `BIND_MODE_STOP_HINT` went on saying
"press Escape when you are done" after Escape had been given a different job.

Three habits that keep it from happening:

* **Reuse only when the rule is the same.** Fitting an existing string into a new position because
  it is nearly right produces a garment that does not fit. Taking a client global is real reuse —
  the game's rule and ours are the same rule. Two of our own screens sharing one key is real reuse
  when they genuinely say one thing (`CUSTOM_STATES_DESC` is passed explicitly to the condition
  menu so a twin key cannot drift); pasting a sentence sideways is not.
* **Do not quote another control's label inside a string.** The moment a sentence spells out what a
  button says, renaming that button leaves the sentence pointing at something that is not there. A
  line already died this way.
* **One thing has one name per screen.** `BULK_MENU_TITLE` and `BULK_SELECTED_COUNT` deliberately
  use the same word for the same set.

Ask of every string the one question its position has to answer — for a button, "what happens when
I press this" — and delete whatever answers a different one.

---

## Leave the reasoning in `enUS.lua`

The comments above the keys in that file are load-bearing: why this wording and not the obvious one,
what the sentence must keep saying, which other string it is deliberately unlike. They are the
reason a later edit does not quietly undo a decision. Write new ones in English, above the key, and
when you touch an old Korean one rewrite the whole comment rather than leaving it half-translated.

`npm run check` cannot see any of this — it cannot even see the game. A string change is verified by
reloading and looking at it.
