<img width="512" height="512" alt="raid_loot_suite_transparent" src="https://github.com/user-attachments/assets/66171f51-57c8-4c76-abd5-d5f9cdb768e3" />

Always download zip from the code to use the latest addon version

RAID LOOT SUITE  v2.1.1  -  by Saranwrap
World of Warcraft 3.3.5a (ChromieCraft / WotLK private servers)
Loot history, soft reserves, SR / MS / OS rolls, loot council and a loot queue.
(Formerly "Raid Loot Tracker".)


INSTALL
  Copy the "RaidLootSuite" folder into  World of Warcraft\Interface\AddOns\
  (the .toc must be at  Interface\AddOns\RaidLootSuite\RaidLootSuite.toc)
  Keep the "textures" folder inside it (window and minimap logo).
  After adding the new logo files, restart the game (a /reload does not load new image files).

UPGRADING FROM RAID LOOT TRACKER (keep your history)
  1. Exit the game completely.
  2. Delete the old  Interface\AddOns\RaidLootTracker  folder.
  3. In  WTF\Account\<ACCOUNT>\SavedVariables\  rename
       RaidLootTracker.lua  ->  RaidLootSuite.lua
  4. Start the game. Chat confirms how many items were carried over.


MAIN WINDOW
  One window with tabs:
    Loot Session | Soft Reserves | Loot Council | History | Loot Tables
  Title bar: name, version and author, "?" (how the loot session works),
  Settings, and X (or Escape) to close.
  Drag the title bar to move it, drag the bottom-right corner to resize it
  (size is remembered, double-click the corner for the default size).
  /rls opens it on the last tab you used.
  Minimap button   left-click: open / close   shift-click: History tab
                   right-click: menu (every tab, settings, test mode).
                   Hover it for queue / SR counts.
  Hover any item in the game (bags, loot window, chat links) to see who
  soft reserved it. Most rows have a right-click menu with quick actions.


COMMANDS
  /rls                         open / close the main window
  /rls session                 Loot Session tab (queue, rolls, council)
  /rls sr                      Soft Reserves tab
  /rls council                 Loot Council tab (choose the members)
  /rls history                 History tab
  /rls tables                  Loot Tables tab
  /rls queue [item]            add an item to the loot queue
  /rls timer <seconds>         roll timer (5-120 s)
  /rls export | import         export / import the history
  /rls options                 Settings
  /rls add [item] Player [MS|OS] Boss   add a history entry by hand
  /rls minimap                 show / hide the minimap button
  /rls test                    test mode on / off (see TEST MODE)
  /rls testentry               add a sample entry to the loot history
  /rls clear                   delete all history
  /raidloot also works.


LOOT SESSION TAB  (/rls session)
  A bigger window shows more queue items and more players.
  Queue (left)
    - As master looter, opening a boss corpse/chest adds its items to the
      queue (once per corpse) and posts them in raid chat:
      "Loot from <Boss>: [item] [item] ...". Both can be turned off in
      Settings (trash loot is never posted).
    - Add anything by hand: shift-click an item into the box, or type an ID.
    - Each item shows its status: Waiting, Rolling, Council vote, Tie -
      reroll, No rolls, Awarded, Delivered, Disenchant, Skipped.
    - Soft reserved items show "SR: names" under the item.
    - Right-click an item: start roll / council, end roll, disenchant, skip,
      back to waiting, link in chat, remove, and "Give to" > Group 1-8 >
      player to hand it straight to someone (announced as "given by the loot
      master", saved in the history, given with Master Loot if the loot
      window is open). Shift-click: link in chat.
    - "Clear finished" removes awarded / delivered / disenchanted / skipped.

  Selected item (right)
    Roll        starts a roll, announced in raid warning
    Council     starts a loot council vote
    End now     ends the roll early
    Award       gives the item to the player selected in the list
                (or right-click a player > Award)
    Disenchant  marks it for disenchant (recorded as "Disenchanted")
    Skip        skips it
    Remove      removes it from the queue
    Roll timer  box at the top right: seconds for the next roll (5-120,
                default 10), type a number and press Enter. Same as /rls timer 30.
    One item can be rolled / voted at a time.

  How rolls work
    - Soft reserved by players in the raid -> only they can roll (/roll 100).
      Only one SR'er in the raid -> they get it right away.
    - Otherwise MS = /roll 100, OS = /roll 99. Any MS roll beats any OS roll.
    - Only the first roll of each player counts. Other ranges are ignored.
    - When the timer ends the winner is announced. A tie starts an automatic
      reroll between the tied players (spec is kept).
    - Countdown in chat for the last 5 seconds: "Roll for [item] ends in 5",
      then 4, 3, 2, 1 (raid chat by default, can be changed or turned off).
    - With "Give with Master Loot" on and the loot window open, the item is
      handed to the winner automatically.
    - The status turns to "Delivered" when the winner actually receives it.

  Loot council
    - Raiders answer MS / OS / Pass with the popup, by whispering you
      "ms", "os" or "pass", or by rolling. SR'ers are listed automatically.
    - You decide who is on the council: Loot Council tab (or /rls council). Tick raid members, "Leader + assists" in one
      click, or add a name of someone not in the raid yet. You are always on
      it. Changes apply right away, also to a vote in progress.
    - Council members see the candidates and click Vote. Click again to take
      the vote back. Votes are counted in the list, hover a player to see who
      voted for them.
    - You pick the player and press Award.
    - Council members need Raid Loot Suite to vote. Raiders without it can
      still whisper or roll.

  Raiders with the addon
    A popup shows the item with MS / OS / Pass buttons (SR roll for SR'ers,
    reroll for tied players). The buttons do the /roll for them.

  Awards are written to the loot history with SR / MS / OS and a note
  (roll result, "Council", "Disenchant"). Changing the winner later updates
  the same history entry.


SOFT RESERVES TAB  (/rls sr)
  Three views:
    By item     each item once: how many reserved it, who (grey = not in
                your raid, "(won)" = already got it), and its queue status
                or winner. Most contested items first.
    By player   each player once: their reserves and count (1/1), grey when
                not in your raid.
    Edit list   one line per reserve: click to edit, x to delete.
  Search box filters by player or item. "Only my raid" hides players who are
  not in your group. Right-click a row in By item / By player: add another
  player or item, remove a reserve, add the item to the loot queue.
  - Add: player name + item (shift-click, item ID or exact name), Add.
    Clicking an item row fills the item, a player row fills the player.
  - Edit: in Edit list, click a row, change it, Save. "Clear" cancels.
  - Delete: x in Edit list, or right-click > Remove. "Clear all" empties it.
  - Import: softres.it CSV export, with or without its header line (paste
    with Ctrl+V). The class from softres.it is used to colour names. Or one
    per line:
      Player: [item]     Player - Item name     Player, 49623
    Tick "Replace the current list" to start fresh, otherwise it is added.
  - Players whisper you:  sr [item]  (save),  sr  (check),  sr clear  (remove)
  - Announce posts the list in raid chat, one line per item.
  - Players not in your raid are shown in grey and ignored for rolls.


SETTINGS  (Settings button in the title bar, /rls options)
  Two pages: "Loot session" and "History & window". Press Back (same button)
  to return to the tab you were on.
  Loot session:
  Roll timer (5-120 s, default 10), MS and OS roll numbers (100 / 99),
  soft reserves per player (1-3, for whisper "sr"; you can always add more
  by hand), where roll starts are announced (Raid Warning / Raid / only me)
  and where winners and the countdown are announced (Raid by default),
  auto-queue, post boss loot in raid chat, give with Master Loot, countdown
  on / off, whisper SR, whisper MS/OS, and "Choose council members".
  Raid warning needs leader or assist, otherwise raid chat is used.
  History & window: minimum item quality, raid instances only, trash drops,
  chat line when loot is recorded, minimap button, window opacity.


TEST MODE  (Settings > Loot session > "Test mode", minimap menu, /rls test)
  Try everything alone, no raid needed:
  - Six fake raiders join (Tanktest, Healtest, Magetest, Roguetest,
    Hunttest, Dktest). Up to 4 test items are taken from your gear / bags.
  - Ready-made soft reserves: item 1 = SR roll between you and 2 raiders,
    item 2 = one SR'er (wins right away), item 3 = MS / OS roll, item 4 =
    council. Each test item says what it shows.
  - Fake raiders roll, answer the council, and the fake raiders on the
    council vote (Tanktest and Healtest are put on it; change it with the
    Council button). You get the raider popup too, so you can roll with it.
  - Awards go into the loot history (boss "Test Boss", note "test") and are
    marked delivered, like a real raid. Leaving test mode asks if you want
    to remove those history entries or keep them.
  - Soft Reserves > "Fake whisper": Roguetest whispers you, one step per
    click: sr [item], sr (check), sr [other item] (limit), sr clear.
  - Nothing is sent to chat or other players (messages show in your chat
    as [Test]) and Master Loot is not used.
  - Stop test (or /reload) removes every test item, test soft reserve and
    fake council member.
    Your real soft reserves and queue are kept.

LOOT TABLES TAB  (/rls tables)
  Every Wrath raid: Naxxramas, Obsidian Sanctum, Eye of Eternity, Vault of
  Archavon, Onyxia, Ulduar, Trial of the Crusader, Icecrown Citadel, Ruby
  Sanctum.
  - Pick the raid (top left) and the mode: 10, 25, and 10 HC / 25 HC where
    the raid has a heroic mode.
  - Left: the bosses, then "Trash mobs" (epic and better) and "Patterns &
    recipes" (with the boss or trash they come from).
  - Each item shows its type, item level and drop chance. HM = only in hard
    mode (Ulduar hard modes, Sartharion with drakes up...). "SR 2" = two
    players soft reserved it. Trash chances are per mob killed.
  - Search box: finds an item or type (e.g. "trinket", "plate", "pattern")
    in every boss of the raid.
  - Hover: item tooltip. Shift-click: link. Ctrl-click: try it on.
    Right-click: link, add to the loot queue, add a soft reserve.
  The chances are worked out from the AzerothCore world database (the core
  ChromieCraft runs on). ChromieCraft can change its own loot, so treat
  them as a guide. Faction items (Trial of the Crusader) are listed for
  both Alliance and Horde.

HISTORY TAB  (/rls history, minimap shift-click)
  Records item, boss, winner, date + time, raid and size/difficulty.
  - Winners come from "<player> receives loot: [item]" lines.
  - If you open the boss corpse/chest, drops show "Pending..." until looted.
  - Default: epic and up, raid instances only, trash included (boss "Trash").
    Emblems, Abyss Crystals and Frozen Orbs are ignored. See Settings.
  Search box, Raid / Period filters, sortable columns.
  Row: hover = tooltip, shift-click = link in chat, ctrl-click = dressing
  room, right-click = edit winner / boss / note, mark as SR, delete.
  Tag: left-click cycles none > MS > OS > SR, right-click adds a note.

  Export: CSV (Excel / Google Sheets), plain text or Discord. Exports what
  is currently shown, so filters apply.
  Import: paste Excel / Google Sheets cells WITH the header row, CSV, this
  addon's exports, or simple lines  Item -> Player  /  Boss | Item -> Player MS
  Use 2026-10-01 style dates to be safe. Rows already there are skipped.
  Outside the game: Tools\savedvariables_to_csv.py makes a CSV from
    WTF\Account\<ACCOUNT>\SavedVariables\RaidLootSuite.lua  (Python 3)


SAVED DATA
  WTF\Account\<ACCOUNT>\SavedVariables\RaidLootSuite.lua, shared by all your
  characters. Written on logout, /reload or normal exit; a crash loses that
  session's changes. A roll or vote in progress does not survive a /reload
  (the item goes back to "Waiting").


LIMITS
  - The boss is detected from skull-level units. Where nobody dies (Gunship,
    Valithria, Ulduar keepers) the last boss fought is used.
  - Loot handed out more than 15 minutes after a kill, without the loot
    window, may be filed as "Trash" or the wrong boss.
