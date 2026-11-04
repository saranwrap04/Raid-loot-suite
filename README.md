<p align="center"><img src="images/logo.png" width="128" alt="Raid Loot Suite"></p>

# Raid Loot Suite

Loot history, soft reserves, SR / MS / OS rolls, loot council, an active loot queue and raid loot tables for **World of Warcraft 3.3.5a** (ChromieCraft / AzerothCore).

**Version 2.7.2** - by Saranwrap

## Features

- **Loot session**: a queue of the items to hand out, with a status for each (Waiting, Rolling, Council vote, Tie, No rolls, Awarded, Delivered, Disenchant, Skipped). As master looter, the boss loot is added to the queue and posted in raid chat for you
- **Rolls**: MS (`/roll 100`), OS (`/roll 99`) and SR, with a countdown in chat, automatic rerolls on ties, announced winners and Master Loot delivery. Raiders with the addon get an MS / OS / Pass popup that does the roll for them; raiders without it just type `/roll`
- **Soft reserves**: edit them in game, import a softres.it CSV or plain lines (`Player: [item]`), let players whisper `sr [item]`, announce the list in raid chat. Hover any item in the game to see who reserved it
- **Loot council**: raiders answer by popup, whisper or roll; council members vote and you award the winner
- **History**: item, boss, winner, date and time, raid and difficulty, recorded automatically. Search, filter, edit, tag as MS / OS / SR / DE / LC, delete by raid, raid night, day or age, and **sync** what other raid members recorded
- **Export / import**: CSV (Excel, Google Sheets), plain text or Discord
- **Loot tables**: every raid boss with its loot in 10 / 25 (and heroic), drop chances, hard modes, trash and patterns
- **Test mode**: fake raiders, nothing sent to chat, to try everything alone first
- Flat dark look with a gold accent; settings in a side-bar page

## Install

1. Close the game.
2. Copy the `RaidLootSuite` folder into `Interface\AddOns` and keep its name.
3. Start the game and type `/rls`.

**Updating:** close the game, delete the old `RaidLootSuite` folder completely, then copy in the new one. The game only loads new files after a full restart, not after `/reload`.

## Commands

| Command | What it does |
| --- | --- |
| `/rls` | Open / close the window |
| `/rls session`, `sr`, `council`, `history`, `tables` | Open a tab |
| `/rls queue [item]` | Add an item to the loot queue |
| `/rls timer <seconds>` | Roll timer (5-120) |
| `/rls sync` | Get the loot history recorded by the raid |
| `/rls export`, `import` | Export / import the history |
| `/rls add [item] Player [MS\|OS] Boss` | Add a history entry by hand |
| `/rls options` | Settings |
| `/rls minimap` | Show / hide the minimap button |
| `/rls test` | Test mode on / off |
| `/rls delete`, `clear` | Delete part of / all the history |
| `/rls help` | List the commands in chat |

`/raidloot` works too.

## Notes

- Drop chances are worked out from the AzerothCore world database. The server can change its loot, so treat them as a guide.
- A roll or vote in progress does not survive a `/reload`.
- `Tools\savedvariables_to_csv.py` makes a CSV from the saved file outside the game (Python 3).
- SavedVariables: `RaidLootSuiteDB` (the old `RaidLootTrackerDB` data is kept).

## Links

- GitHub: [github.com/saranwrap04/Raid-loot-suite](https://github.com/saranwrap04/Raid-loot-suite)
- Warperia: [warperia.com/addon-wotlk/raid-loot-suite](https://warperia.com/addon-wotlk/raid-loot-suite/)

## Author

Saranwrap - [github.com/saranwrap04](https://github.com/saranwrap04)
