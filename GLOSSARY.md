# XPBar

An experience bar for World of Warcraft: Forever that shows progress through the current level, plus XP the player has earned but not yet collected.

## Language

### Level progress

**XP to level**:
The XP still needed to reach the next level.
_Avoid_: remaining, headroom

### Quest XP

**Turn-in XP**:
The reward XP of quests in the log that are ready to hand in.
_Avoid_: pending, completed, completed quest XP

**In-progress quest XP**:
The reward XP of quests in the log whose objectives are not yet done.
_Avoid_: incomplete, incomplete quests

**Rested pool**:
Bonus XP the player has banked by resting, which doubles kill XP until it is spent.
_Avoid_: exhaustion, rested bonus

### Time

**Session**:
The time since the player last logged in or reloaded the UI; loading screens do not end it.
_Avoid_: playtime

**Session XP**:
All XP earned during the Session, including XP carried across a level-up.
_Avoid_: gained XP

**Time this level**:
Played time since the player reached their current level.
_Avoid_: level time
