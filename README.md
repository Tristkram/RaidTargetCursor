# Raid Target Cursor

Raid Target Cursor is a tiny World of Warcraft addon that lets you hard-target visible Blizzard party and raid frames with directional keybinds.

It was vibe-coded with Codex, then tested and adjusted in-game. The goal is practical: make friendly targeting feel like moving a cursor across the raid frames, without adding a visual overlay or a custom raid frame UI.

## Features

- Directional target movement: up, down, left, right.
- Self/reset binding that always targets the player.
- Works through WoW secure action buttons, so targeting can happen in combat.
- Builds its navigation map from visible Blizzard party/raid frames.
- Debounced rebuilds for better behavior with frame layout addons such as FrameSort.
- Slash commands for status, debug, manual rebuilds, map dumps, and diagnostics.

## Requirements

- World of Warcraft Retail.
- Blizzard party or raid frames must be visible.
- Keybinds must be assigned in the WoW Key Bindings menu under AddOns.

## Commands

```text
/rtc
/rtc status
/rtc rebuild
/rtc dump
/rtc frames
/rtc events
/rtc reset
/rtc debug
```

## Limitations

- This addon targets Blizzard party/raid frames only. It is not designed for fully custom raid frame addons.
- WoW does not allow secure targeting maps to be rewritten during combat. If someone joins, leaves, or frames are heavily rearranged during combat, the addon may use the previous map until combat ends.
- If a battleground or raid roster changes in combat, a key press may target an old `raidN`/`partyN`, a newly reassigned unit, or no one. The map refreshes after combat.
- Frame layout addons can move Blizzard frames asynchronously. Raid Target Cursor listens for common Blizzard layout updates and also delays roster rebuilds, but unusual layouts may still need `/rtc rebuild` out of combat.


## License

MIT. See `LICENSE`.
