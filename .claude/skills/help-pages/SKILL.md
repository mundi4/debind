---
name: help-pages
description: How to write or edit an in-game help page in docs/ingamehelp/. Load this before touching any file there - which two standing documents set the rules, how to check a claim before it ships, how to get a page reviewed by a blank agent, and which check sees what. Triggers - adding or editing a page under docs/ingamehelp/, being asked to fix help text, moving a topic between pages, or changing a user-facing string that a help page also states.
---

Read `devdocs/writing-a-help-page.md` for the format and `devdocs/writing-user-facing-text.md` for
the words. Both, before writing anything. The second one is where the anthropomorphism rule, the
"use the word the client already has" rule and the tooltip rules live.

What those two do not carry, and what this file is for:

## Before loading this, put it to the owner

**Say which page you would take next and what you think it needs, and wait.** No strong opinion
back means go, and the rest of this file applies. An opinion back means the scope changes, and what
they add is context you did not have; take it in before writing, not after.

Deciding the scope alone and arriving with a rewritten page spends their review on work they would
have shaped differently. The two questions below are the ones to put to them.

## First: does this help have to exist

Two questions, and they come before everything else here.

- **Would a reader take this for granted without being told?** Help that states the obvious costs
  the reader the time it takes to find out it said nothing.
- **Would one line on a page that already exists do it better?** A page is an entry in the list and
  a button on the settings tab, and a title standing there tells the reader there is something
  separate to learn. Where there is not, it splits an answer they were about to find whole.

**Ask them of the page in front of you, not only of the page you are about to write.** Opening a
page to fix its wording without asking whether it should exist is how a page that should have been
one sentence gets polished for an hour. Answer them again every time.

They decide a paragraph inside a page the same way. Most of what looks like a missing page is a
missing sentence somewhere else.

## Read the whole page before you touch it

Not the paragraph you are inserting next to. A page is six or eight paragraphs and one thread runs
through them; deciding where a new block goes without holding the whole page is how a block lands
between two paragraphs that were finishing each other's sentence.

**Never explain a paragraph's position in a comment.** Where a paragraph sits is taste. If the
placement needs defending, the page is wrong, not under-documented.

## Check every claim, and never from a comment

`devdocs/which-action-a-key-runs.md` is the source for what a press reaches and in what order.
Read the section, not a summary of it.

**A page can promise behaviour the code stopped doing.** `targeting.md` said Auto Self Cast applied
in one case only, citing a snippet that had been deleted months earlier; nothing caught it, because
no check reads English. When a page states a rule, find the code or the section that decides it.

**An HTML comment in a page is evidence of nothing.** Comments go stale exactly like the body.

## Decide the content first, then rewrite whole

Patching review findings one at a time gives a page that answers a reviewer instead of a reader.
Settle what belongs on the page, what stays out and how the hard part is worded, and only then
write it.

**When an aside grows, split the page before you look for somewhere to put it.**
`devdocs/writing-a-help-page.md` says this and it is the rule most often skipped, because appending
is easier than deciding.

## Have it reviewed by a blank agent

A page that reads fine to whoever wrote it is the normal outcome. Send it out.

The prompt has to stand alone, because the agent must not read this repo: give it the context a
player has, the exact labels as they appear on screen, the ground truth for what each control does,
the house rules, and the page. Ask for **factual errors first** and say that a false finding costs
more than a missed one. Ask whether a reader could do the thing the page teaches after one read;
that question finds what "is it clear" does not.

Review again after fixing. Every round of this found something real.

## Checks

`npm run check:help` compares `Debind/Locales/Help/*.lua` against the source and fails on unbalanced
tags, a missing title and a link to a page that does not exist.

**A page with stray text in it either stops the build or ships.** `npm run help` writes nothing
while any page fails, so one broken page freezes every other page's edits out of the game. A stray
block whose markers happen to balance passes the check and is baked into the shipped string instead.
Neither is visible from the game until someone opens the page.

`docs/ingamehelp/index.md` decides the order and which pages exist; a page missing from it never
opens, and adding one puts a new button on the settings tab.

`.zzz/ingame-help.md` holds the topics that still need a page.
