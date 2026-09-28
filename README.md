# XPBar

A minimal standalone experience bar addon for **World of Warcraft: Forever** (1.60.1, interface `16001`). No libraries, no XML, no WeakAuras — two files.

## Credits

**This is an AI-generated port of the [Luxthos Experience Bar](https://wago.io/LuxthosExperienceBar) WeakAura.**

**All layout and visual design credit goes to the original authors, Luxthos & Daemoos** ([twitch.tv/luxthos](https://www.twitch.tv/luxthos)). The bar's structure — the stacked segment order, the colour choices, the text arrangement and wording, and the XP/hour and time-played readouts — is theirs. This addon reimplements that design as a standalone addon so it runs without WeakAuras installed.

The code itself was written by Claude (Anthropic) via Claude Code. It is a reimplementation, not a copy of the WeakAura's Lua.

This project is not affiliated with or endorsed by Luxthos, Daemoos, or Blizzard Entertainment.

## Design taken from the original

| Element | Value |
|---|---|
| Completed quest XP | `\|cFFFF9700` orange |
| Rested XP | `\|cFF4F90FF` blue |
| Segment order | fill → completed quests → incomplete quests → rested |
| Font | Friz Quadrata, outlined |
| Layout | level left, `cur / total (remaining)` centre, percentage right |

The current XP fill is purple, which is this addon's own choice rather than the original's.

## Features

- Purple XP fill with stacked segments for completed quests, in-progress quests and the rested pool
- `Level N` / `cur / total (remaining)` / `pct% (pct% incl. pending quests)` inside the bar
- `Leveling in: <time> (<n> XP/Hour)` and `Completed: n% - Rested: n%` below the bar
- `Time this level` and `Time this session` above the bar
- Hover tooltip with the full breakdown
- Hidden at max level (unless unlocked, so it can still be positioned)
- Draggable, with position saved per account

## Install

Copy the `XPBar` folder into:

```
World of Warcraft/_classic_beta_/Interface/AddOns/XPBar/
```

so that `XPBar.toc` and `XPBar.lua` sit directly inside it.

The TOC declares `## Interface: 16001, 120100`, so it also loads on Midnight.

## Commands

| Command | Effect |
|---|---|
| `/xpbar unlock` | enable dragging |
| `/xpbar lock` | disable dragging (default) |
| `/xpbar reset` | restore the default top-centre position |
| `/xpbar debug` | print raw XP, quest and session values |

## Implementation notes

- Every colour uses `SetColorTexture` and the font comes from `GameFontNormal:GetFont()`. Hardcoded art paths such as `Interface\TargetingFrame\UI-StatusBar` do not resolve on this client and render invisible.
- Quest XP uses the `C_QuestLog` namespace (`GetNumQuestLogEntries`, `GetInfo`, `ReadyForTurnIn`, `IsComplete`) plus `GetQuestLogRewardXP`, never the removed legacy quest log globals.
- Nothing reads combat state, so the addon is unaffected by the Midnight secret-values restrictions.
- `RequestTimePlayed()` is called once at login for the time-played lines. The game prints "Total time played" to chat as a result; the original WeakAura behaves the same way.
