# Decent PvP and Target List

A guild PvP addon for **WoW Forever**, written for the Wrath-era 3.3.5 interface. It has no external library dependencies.

## Install

1. Copy the `DecentPVPandTargetList` folder, containing the `.toc` and `.lua`, into `World of Warcraft/_forever_/Interface/AddOns/`.
2. Restart the game or use `/reload`.
3. Open the addon with `/dptl` or `/targetlist`.
4. Join a guild to exchange rankings and target entries.

## Features

- Counts hostile player kills caused by your character from the combat log.
- Shows daily, weekly, and lifetime guild top 10 rankings.
- Shares each player's own count snapshot with guild members every five minutes, and when a new kill is recorded. It does not poll or transmit every few seconds.
- Provides a guild target board for enemy player names, reward amounts, and proof requirements.
- Rewards can be entered as gold, silver, and copper or as free-form text.
- Each character can maintain up to three active targets; only the character that created a target can remove it.
- Offers a compact Normal layout and a Blizzard-like dialog layout under Settings.

## Notes

Guild members need the addon enabled for their kills and target changes to be shared. Rankings are personal snapshots received from each member; the addon does not claim that snapshots are independently verified. Daily and weekly counts use the local calendar on each player's client. Target records and kill counts are saved in `WTF/Account/<account>/SavedVariables/DecentPVPandTargetList.lua`.
