#!/usr/bin/env python3
"""
Raid Loot Suite (by Saranwrap) - export without launching the game.

Reads WTF/Account/<ACCOUNT>/SavedVariables/RaidLootSuite.lua and writes
RaidLootSuite.csv next to this script (or to the path given as 2nd argument).
The CSV copy inside the file is refreshed every time you log out or /reload.

Usage:
    python savedvariables_to_csv.py "C:/WoW/WTF/Account/MYACCOUNT/SavedVariables/RaidLootSuite.lua"
"""
import os, re, sys

def unescape(s):
    return re.sub(r'\\(.)', lambda m: {'n': '\n', 't': '\t'}.get(m.group(1), m.group(1)), s)

def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "RaidLootSuite.csv")
    text = open(src, encoding="utf-8", errors="replace").read()
    m = re.search(r'\["csvExport"\]\s*=\s*\{', text)
    if not m:
        print("No CSV data found. Log in once with the addon enabled, then log out or /reload."); sys.exit(2)
    lines = []
    for raw in text[m.end():].splitlines():
        if re.match(r'^\s*\},?\s*$', raw):
            break
        sm = re.match(r'^\s*"((?:[^"\\]|\\.)*)"', raw)
        if sm:
            lines.append(unescape(sm.group(1)))
    # utf-8-sig so Excel opens accents correctly
    with open(out, "w", encoding="utf-8-sig", newline="") as f:
        f.write("\r\n".join(lines) + "\r\n")
    print(f"Wrote {max(len(lines) - 1, 0)} entries to {out}")

if __name__ == "__main__":
    main()
