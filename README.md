<img width="390" height="332" alt="raid_loot_suite_logo" src="https://github.com/user-attachments/assets/81bcb55f-03a5-4200-b5bd-11cfc530f546" />


# RAID LOOT SUITE v2.3.1

## Loot history, soft reserves, SR / MS / OS rolls, loot council and raid loot tables (WoW 3.3.5a).
By Saranwrap


### INSTALL
  1. Close the game.
  2. Click **Code > Download ZIP**, then extract the zip into `<WoW folder>\Interface\AddOns\`.
     You get a folder named `Raid-loot-suite-main`: keep that name, it is the one the addon loads from.
  3. Start the game.


### QUICK START
  /rls           open / close the window
  Minimap button: left-click open / close, shift-click History, right-click menu.
  Settings: button in the title bar (press Back to return).
  Try everything alone first: Settings > Test mode (fake raiders, nothing sent to chat).


### THE WINDOW
  Tabs: Loot Session | Soft Reserves | Loot Council | History | Loot Tables
  Drag the title bar to move it, drag the bottom-right corner to resize it
  (double-click the corner for the default size). /rls opens the last tab used.
  Hover any item in the game to see who soft reserved it.
  Most rows have a right-click menu with quick actions.


### LOOT SESSION
  **Queue (left)**
  - As master looter, opening the boss corpse/chest adds its items to the queue and posts
    "Loot from <Boss>: [item] [item]..." in raid chat (both can be turned off in Settings).
  - Add any item by hand: shift-click it into the box, or type its ID.
  - Status per item: Waiting, Rolling, Council vote, Tie, No rolls, Awarded, Delivered,
    Disenchant, Skipped. "SR: names" shows under soft reserved items.
  - Right-click an item: roll, council, end roll, disenchant, skip, back to waiting,
    link in chat, remove, Give to > Group 1-8 > player.
  - Clear finished: removes awarded, delivered, disenchanted and skipped items.

  **Selected item (right)**
  Roll / Council     start a roll or a council vote
  End now            end the roll and pick the winner
  Award              give it to the selected player (or right-click a player)
  Disenchant         give it to the disenchanter, saved as DE
  Skip / Remove      skip it / remove it from the queue
  Roll timer         seconds for the next roll (5-120, default 10), or /rls timer 30

  **Rolls**
  - MS = /roll 100, OS = /roll 99, SR = /roll 100. Any MS roll beats any OS roll.
  - Soft reserved by players in the raid: only they roll. One SR'er: they get it.
  - The timer ends the roll, with a 5-4-3-2-1 countdown in chat. The winner is announced
    and gets the item with Master Loot when the loot window is open.
  - Ties reroll automatically between the tied players. Only the first roll counts.
  - Nobody rolled and a disenchanter is set: it goes to the disenchanter.
  - Status turns to Delivered when the winner receives the item.

  **Raiders**
  - With Raid Loot Suite: a popup with MS / OS / Pass. The buttons do the /roll for them
    (also in a council vote), so everybody sees the rolls in chat.
  - Without it: they read the raid chat and type /roll 100 or /roll 99 (council: whisper
    ms / os / pass, or roll). Their rolls count the same way.

  **Loot council**
  - Raiders answer with the popup, a whisper (ms / os / pass) or a roll.
  - Council members see the answers and click Vote (click again to take it back).
    Hover a player to see who voted for them. You select the player and press Award.
  - Council members need Raid Loot Suite to vote.


### SOFT RESERVES
  - Views: By item (who reserved it, queue status / winner), By player (their reserves),
    Edit list (one line per reserve: click to edit, x to delete).
  - Search box and "Only my raid" filter. Grey = not in your raid, (won) = already got it.
  - Add: player + item (shift-click, item ID or exact name), then Add.
  - Import: softres.it CSV export (with or without its header line), or one per line:
      Player: [item]     Player - Item name     Player, 49623
  - Players can whisper you: sr [item] (save), sr (check), sr clear (remove).
  - Announce: posts the list in raid chat, one line per item.


### LOOT COUNCIL
  Tick who can vote (you are always on it), "Leader + assists" in one click, or add a name
  of someone not in the raid yet. Changes apply right away, also to a vote in progress.


### HISTORY
  Records item, boss, winner, date and time, raid and size/difficulty.
  - Winners come from "<player> receives loot" lines. Drops seen in the loot window show
    "Pending..." until someone loots them.
  - Default: epic and better, inside raids, trash included. Emblems, Abyss Crystals and
    Frozen Orbs are ignored (Settings > History & window).
  - Search, Raid and Period filters, click a column title to sort.
  - Row: hover = tooltip, shift-click = link, ctrl-click = try on,
    right-click = edit winner / boss / note, mark as MS / OS / SR / DE, delete.
  - Tag: left-click cycles none > MS > OS > SR > DE, right-click adds a note.
  - Sync: gets the loot other raid members recorded in the last 7 days and fills in what
    you missed (disconnected, too far away). They need Raid Loot Suite. It also runs once
    after a login or /reload in a raid.
  - Export: CSV (Excel / Google Sheets), plain text or Discord (what is shown, filters apply).
  - Import: Excel / Google Sheets cells with the header row, CSV, this addon's exports, or
    lines like  Item -> Player  /  Boss | Item -> Player MS
  - Outside the game: Tools\savedvariables_to_csv.py makes a CSV from the saved file (Python 3).


### LOOT TABLES
  Every raid boss with its loot in 10 / 25 (and 10 / 25 heroic where the raid has it),
  plus "Trash mobs" (epics and better) and "Patterns & recipes".
  - Each item: type, item level, drop chance. HM = hard mode only.
    A (blue) / H (red) = Alliance / Horde only.
  - Click a column title to sort (click again to reverse).
  - Search box: an item or a type ("trinket", "plate", "pattern") in the whole raid.
  - Right-click an item: link, add to the loot queue, add a soft reserve.
  Drop chances are worked out from the AzerothCore world database (the core ChromieCraft
  runs on). The server can change its loot, so treat them as a guide.


### SETTINGS
  Loot session: test mode, roll timer, announce channels (roll start, winners, countdown),
  auto-queue, post boss loot in raid chat, give with Master Loot, countdown, whisper SR,
  whisper MS / OS, disenchanter (+ give no-roll items to the disenchanter), council members.
  History & window: minimum quality, raids only, trash drops, chat line when loot is
  recorded, minimap button, sync after login, window opacity, links.
  Raid warning needs leader or assist, otherwise raid chat is used.


### TEST MODE  (Settings, minimap menu or /rls test)
  Six fake raiders, a few test items from your gear and ready-made soft reserves.
  Fake raiders roll, answer the council and vote. "Fake whisper" in Soft Reserves tests
  the whisper commands. Nothing is sent to chat, Master Loot is not used. Awards go into
  the history as "Test Boss" (you are asked if you want to keep them when the test stops).


### COMMANDS
  /rls                          open / close the window
  /rls session | sr | council   open a tab
  /rls history | tables         open a tab
  /rls queue [item]             add an item to the loot queue
  /rls timer <seconds>          roll timer (5-120)
  /rls sync                     get the loot history recorded by the raid
  /rls export | import          export / import the history
  /rls options                  settings
  /rls add [item] Player [MS|OS] Boss   add a history entry by hand
  /rls minimap                  show / hide the minimap button
  /rls test                     test mode on / off
  /rls testentry                add a sample entry to the history
  /rls clear                    delete all history
  /rls help                     list the commands in chat
  /raidloot works too.


### SAVED DATA
  WTF\Account\<ACCOUNT>\SavedVariables\RaidLootSuite.lua (shared by your characters).
  Written on logout, /reload or exit; a crash loses that session's changes.
  A roll or vote in progress does not survive a /reload.


### LINKS
  GitHub:   https://github.com/saranwrap04/Raid-loot-suite
  Warperia: https://warperia.com/addon-wotlk/raid-loot-suite/

<img width="1078" height="740" alt="Screenshot 2026-10-05 090416" src="https://github.com/user-attachments/assets/fe6024e5-eda1-4b0b-8f6b-9b52260c01e1" />
<img width="1078" height="739" alt="Screenshot 2026-10-05 090507" src="https://github.com/user-attachments/assets/ba09fac9-0ff2-4604-8076-7f544345309a" />
<img width="1079" height="739" alt="Screenshot 2026-10-05 090517" src="https://github.com/user-attachments/assets/d2ff915f-e988-4866-8bd7-be4142eaafa6" />
<img width="1078" height="739" alt="Screenshot 2026-10-05 090527" src="https://github.com/user-attachments/assets/b7fa12bc-f50a-429b-aa93-77da5bde5b84" />
<img width="1080" height="738" alt="Screenshot 2026-10-05 090538" src="https://github.com/user-attachments/assets/8b65af67-a64d-4fca-afda-c73f015e4570" />
<img width="1079" height="738" alt="Screenshot 2026-10-05 090548" src="https://github.com/user-attachments/assets/9f19c713-5218-4f38-81be-0a24739e1818" />
<img width="1080" height="737" alt="Screenshot 2026-10-05 090556" src="https://github.com/user-attachments/assets/f41a5b91-5c7e-4164-9e48-3d9d8515f84f" />
<img width="678" height="294" alt="Screenshot 2026-10-05 090620" src="https://github.com/user-attachments/assets/e12f3d2c-bbda-47eb-bb0a-ccf174d04de2" />
<img width="395" height="138" alt="Screenshot 2026-10-05 090440" src="https://github.com/user-attachments/assets/596a20f6-aeb5-4eb4-a1da-a4c8cecf524d" />
<img width="397" height="141" alt="Screenshot 2026-10-05 090456" src="https://github.com/user-attachments/assets/3b1146f1-89bb-4a62-bdd0-20e1c9763cda" />
