# Decent PvP and Target List

A guild PvP addon for **WoW Forever** (interface 16001). It has no external library dependencies.

## Install

1. Copy the `DecentPVPandTargetList` folder, containing the `.toc` and `.lua`, into `World of Warcraft/_forever_/Interface/AddOns/`.
2. Restart the game or use `/reload`.
3. Open the addon with `/dptl` or `/targetlist`.
4. Join a guild to exchange rankings and target entries.

## Features

- Tracks daily, weekly, and lifetime kills with a manual **Record kill** action after combat. Forever restricts combat-event access, so the addon does not inspect combat logs.
- Shows daily, weekly, and lifetime guild top 10 rankings.
- Shares each player's own count snapshot only when they click **Share stats** or **Record kill**, and only when the client reports addon messaging is allowed. It does not send on a timer or from combat events.
- Provides a guild target board for enemy player names, reward amounts, and proof requirements.
- Rewards can be entered as gold, silver, and copper or as free-form text.
- Each character can maintain up to three active targets; only the character that created a target can remove it.
- Uses Horde red or Alliance blue accents, visible Kill Rankings/Guild Targets tabs, and a top-right Settings toggle.
- Offers a compact faction-colored layout and a distinct Blizzard-like rock frame, marble inset, and header artwork under Settings.
- Adds a standard sword Addon Compartment icon that toggles the main window. IconBag - Forever collects Addon Compartment entries into its icon drawer.

## Notes

Guild members need the addon enabled and must click a sharing action for their stats and target changes to be shared. Rankings are personal snapshots received from each member; counts are self-reported and not independently verified. Daily and weekly counts use the local calendar on each player's client. Target records and kill counts are saved in the addon's SavedVariables file.
