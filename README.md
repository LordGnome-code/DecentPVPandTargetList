# Decent PvP and Target List

A guild PvP addon for **WoW Forever** (interface 16001). It has no external library dependencies.

## Install

1. Copy the `DecentPVPandTargetList` folder, containing the `.toc` and `.lua`, into `World of Warcraft/_forever_/Interface/AddOns/`.
2. Restart the game or use `/reload`.
3. Open the addon with `/dptl` or `/targetlist`.
4. Join a guild to exchange rankings and target entries.

## Features

- Reads the character's lifetime honorable kill total from `GetPVPLifetimeStats()` and tracks daily and weekly honorable kill credits from Forever's `PLAYER_PVP_KILLS_CHANGED` event. The event may not provide the defeated player's name, so automatic daily/weekly tracking does not guess it; the manual **Record kill** action remains as an optional correction.
- Shows daily, weekly, and lifetime guild top 10 rankings.
- Automatically shares updated count snapshots with the guild when the client permits addon messaging. If a kill is credited during combat or messaging lockdown, its report is queued until combat ends and restrictions clear. **Share stats** remains available for a manual refresh.
- Provides a guild target board for enemy player names, reward amounts, and proof requirements.
- Rewards can be entered as gold, silver, and copper or as free-form text.
- Each character can maintain up to three active targets; only the character that created a target can remove it.
- Uses Horde red or Alliance blue accents, visible Kill Rankings/Guild Targets tabs, and a top-right Settings toggle.
- Offers a compact faction-colored layout and a distinct Blizzard-like rock frame, marble inset, and header artwork under Settings.
- Adds a standard sword Addon Compartment icon that toggles the main window. IconBag - Forever collects Addon Compartment entries into its icon drawer.

## Notes

Guild members need the addon enabled to exchange rankings and target changes. Rankings are personal snapshots received from each member; counts are not independently verified. The all-time value reflects the character's lifetime honorable kills reported by the game, while daily and weekly counts reflect credits observed by the addon and use each client's local calendar. Target records and kill counts are saved in the addon's SavedVariables file.
