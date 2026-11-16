# Decent PvP and Target List

A guild PvP addon for **WoW Forever** (interface 16001). It has no external library dependencies.

## Install

1. Copy the `DecentPVPandTargetList` folder, containing the `.toc` and `.lua`, into `World of Warcraft/_forever_/Interface/AddOns/`.
2. Restart the game or use `/reload`.
3. Open the addon with `/dptl` or `/targetlist`.
4. Choose Guild, Party, or Raid in Settings to exchange rankings and target entries with members using the same channel.

## Features

- Reads the character's lifetime honorable kill total from `GetPVPLifetimeStats()` and tracks daily and weekly honorable kill credits automatically from Forever's `PLAYER_PVP_KILLS_CHANGED` event.
- Shows daily, weekly, and lifetime guild top 10 rankings.
- Combines the Decent PvP Rank tracker in the **DecentPVP** tab, with Rank Points, Honor, Matches, Info, and Guild Kills subtabs.
- Automatically shares updated count snapshots over the selected addon-message channel when the client permits sending. If a kill is credited during combat or messaging lockdown, its report is queued until combat ends and restrictions clear. **Share stats** remains available for a manual refresh.
- Provides a guild target board for enemy player names, race and class portraits, reward amounts, and proof requirements.
- Rewards can be entered as gold, silver, and copper or as free-form text.
- Each character can maintain up to three active targets; only the character that created a target can cancel it. A member can enter a name to credit, then record and remove an eliminated target.
- The **Target Kills** subtab shows daily, weekly, and lifetime target eliminations and coin rewards by credited player.
- Uses Horde red or Alliance blue accents, centered main tabs and title, and a top-right Settings toggle. The window can be resized down to 450 × 410 pixels, and its page contents scale up or down with the window.
- Offers a compact faction-colored layout and a distinct Blizzard-like rock frame, marble inset, and header artwork under Settings.
- Adds a Troll head icon that toggles the main window. IconBag - Forever collects Addon Compartment entries into its icon drawer.

## Notes

Members in the selected channel need the addon enabled to exchange rankings and target changes. Rankings are personal snapshots received from each member; counts are not independently verified. The all-time value reflects the character's lifetime honorable kills reported by the game. Daily counts use the client calendar; weekly counts roll over at the game's weekly reset (Tuesday on Forever). Target records and kill counts are saved in the addon's SavedVariables files.
