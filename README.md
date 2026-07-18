# PalWhip 🔥🪢

A tiny Palworld mod with exactly one job: **crack the whip and get your base pals back to normal.**

Depressed? Ulcer? Sprained ankle? Fractured? Weakened? Slacking with zero SAN?
Press the whip key and every one of *your* pals around you is instantly:

- **Cured of sickness** — Depression, Ulcer, Sprain, Fracture, Weakness, Cold, etc.
- **Restored to full sanity (SAN 100)** — no more moping around the base
- **Healed to full HP** (optional, on by default)
- **Fed to a full stomach** (optional, off by default)

It's a [UE4SS](https://docs.ue4ss.com/) Lua mod — no game files are modified and it can be
removed at any time by deleting one folder.

> **Design note:** the "whip" is a hotkey (default **F7**), not a literal inventory item.
> Adding a real craftable whip weapon would require repacking game assets (.pak/.utoc) in an
> Unreal Engine project. The hotkey approach does the same job, survives game updates far
> better, and installs in one minute.

## Installation

1. **Install UE4SS for Palworld** (the experimental build required by current Palworld):
   - Easiest: subscribe to *UE4SS Experimental (Palworld)* on the Steam Workshop, **or**
   - Manual: follow the [PalMods UE4SS guide](https://www.palmods.gg/guides/modding/ue4ss) /
     [pwmodding.wiki](https://pwmodding.wiki/docs/category/lua-modding) and drop UE4SS into
     `Palworld\Pal\Binaries\Win64\`.
2. **Copy the `PalWhip` folder** from this repo into your UE4SS `Mods` directory:
   - Newer UE4SS builds: `Palworld\Pal\Binaries\Win64\ue4ss\Mods\PalWhip`
   - Older UE4SS builds: `Palworld\Pal\Binaries\Win64\Mods\PalWhip`
3. That's it for recent UE4SS versions — the included `enabled.txt` auto-enables the mod.
   If your UE4SS uses `mods.txt`, add this line to it:
   ```
   PalWhip : 1
   ```
4. Launch the game, walk into your base, press **F7**. You'll get a chat message like:
   ```
   *CRACK* 4 pal(s) snapped back to normal. Back to work!
   ```

## Configuration

Edit [PalWhip/Scripts/config.lua](PalWhip/Scripts/config.lua):

| Option | Default | Meaning |
|---|---|---|
| `WhipKey` | `"F7"` | The whip key ([key names](https://docs.ue4ss.com/lua-api/table-definitions/key.html)) |
| `Range` | `9000` | Effect radius in cm (90 m ≈ a whole base). `0` = all loaded pals |
| `OwnedOnly` | `true` | Only whip pals that have an owner (skip wild pals) |
| `CureSickness` | `true` | Clear Depression/Ulcer/Sprain/Fracture/Weakness/Cold... |
| `RestoreSanity` | `true` | SAN back to 100 |
| `HealHP` | `true` | HP back to full |
| `FillStomach` | `false` | Also refill hunger |
| `Cooldown` | `1.0` | Seconds between cracks |
| `Announce` | `true` | Show the in-game chat message |

Changes apply after a game restart, or hot-reload mods with **Ctrl+R** in the UE4SS console.

## How it works

On keypress the mod finds all loaded `PalCharacter` actors, filters them to owned,
non-player pals within range of you, and resets the status fields on each pal's
`PalIndividualCharacterParameter.SaveParameter`:

- `WorkerSick` → `None` (this is the field behind all the base "sickness" statuses)
- `SanityValue` → `100`
- `HP` → `GetMaxHP()` (optional)
- `FullStomach` → `MaxFullStomach` (optional)

Every game-API access is wrapped in `pcall`, so if a Palworld update renames a field the
mod degrades gracefully (skips that fix and logs) instead of crashing the game.

## Notes & limitations

- **Single player / host only.** Pal state lives on the server, so on a dedicated server
  the mod must be installed server-side; pressing the key as a pure client does nothing.
- Works on the pals near *you* — stand in (or near) your base when you crack the whip.
- No game assets are touched; uninstall by deleting the `PalWhip` folder.
- Tested against the Palworld 1.x + UE4SS experimental combination current as of mid-2026.
  If a patch breaks a field name, check the UE4SS console log for `[PalWhip]` messages.

## Repo layout

```
PalWhip/
├── enabled.txt          # auto-enable marker for UE4SS
└── Scripts/
    ├── main.lua         # the mod
    └── config.lua       # user settings
```
