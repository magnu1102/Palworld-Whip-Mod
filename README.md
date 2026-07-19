# PalWhip 🔥🪢

## ⬇️ Download

### **[Download PalWhip-Setup.exe](https://github.com/magnu1102/Palworld-Whip-Mod/releases/latest/download/PalWhip-Setup.exe)**

This is the only file needed for both new installations and updates. Close Palworld,
double-click the downloaded EXE, and accept the Windows administrator prompt. Existing
settings and custom music are preserved. The installer is not code-signed, so Windows may
show an “unknown publisher” SmartScreen warning. GitHub's automatically generated
“Source code” archives are for developers and do not provide the one-click installer.

A Palworld mod with exactly one job: **craft a whip, crack it, and get your base pals back to normal.**

Depressed? Ulcer? Sprained ankle? Fractured? Weakened? Slacking with zero SAN?
Craft the **Pal Whip**, press the whip key (default **F7**) near your base, and every one of
*your* pals around you is instantly — with a satisfying crack sound:

- **Cured of sickness** — Depression, Ulcer, Sprain, Fracture, Weakness, Cold, etc.
- **Restored to full sanity (SAN 100)** — no more moping around the base
- **Healed to full HP** (optional, on by default)
- **Fed to a full stomach** (optional, off by default)

No game files are modified; uninstall by deleting two folders.

Also on board: **PalBoombox** — a craftable boombox that plays sea shanties with real
spatial audio (see [The Boombox](#the-boombox-)).

## The mod parts

| Folder | Framework | What it does |
|---|---|---|
| `PalWhip/` | UE4SS (Lua) | The whip crack: keybind, curing logic, sound, inventory check |
| `PalWhipItem/` | [PalSchema](https://okaetsu.github.io/PalSchema/) (JSON) | The craftable **Pal Whip** item: icon, name, crafting recipe |
| `PalBoombox/` | UE4SS (Lua) + audio companion | Placeable boombox with spatial shanty playback |
| `PalBoomboxItem/` | PalSchema (JSON) | The craftable **Boombox** item: icon, recipe |

The Pal Whip is a real **equippable melee weapon** with a custom icon, craftable at the
**Primitive Workbench** (5× Leather + 10× Wood). Put it on your weapon wheel, hold it in
your hands, and the whip key cracks it; without it equipped you get told to go get it.
(`ItemRequirement` in the Lua config relaxes this to `"inventory"` or `"none"` — the
latter is pure-hotkey mode for players who skip PalSchema.)

> **Heads-up:** the whip is also a functioning light melee weapon (25 attack). Swinging it
> at your own pals *hurts them* like any weapon would — the healing crack is the whip key,
> not the swing.

## Download and one-click install

Download **[PalWhip-Setup.exe](https://github.com/magnu1102/Palworld-Whip-Mod/releases/latest/download/PalWhip-Setup.exe)**,
close Palworld, and double-click it. Accept the Windows administrator prompt and the installer handles everything else: it finds
Steam and Palworld, downloads UE4SS and PalSchema from their official GitHub releases when
needed, applies the required settings, and installs all four mod parts. It is safe to run
again when updating—the installer preserves your configuration and every existing music
file, verifies those files are byte-for-byte unchanged, and skips dependencies already
present. No uninstall is needed.

For an unusual portable installation that Steam discovery cannot find, advanced users can
run `install.ps1 -GamePath "D:\path\to\Palworld"` from PowerShell.

**Updating an existing install:** close Palworld and double-click the newer
`PalWhip-Setup.exe`. Do not uninstall first. The updater replaces mod code and item
definitions while retaining both config files and all existing music, including files whose
names overlap a bundled track.

## Manual installation

1. **Install UE4SS for Palworld** (the experimental build required by current Palworld):
   - Easiest: subscribe to *UE4SS Experimental (Palworld)* on the Steam Workshop, **or**
   - Manual: follow the [PalMods UE4SS guide](https://www.palmods.gg/guides/modding/ue4ss).
2. **Install [PalSchema](https://www.nexusmods.com/palworld/mods/3037)** (also on the Steam
   Workshop) — it lives in `Pal\Binaries\Win64\ue4ss\Mods\PalSchema`.
3. Copy **`PalWhip`** and **`PalBoombox`** into `Pal\Binaries\Win64\ue4ss\Mods\`
   (older UE4SS builds use `Pal\Binaries\Win64\Mods\`; the included `enabled.txt`
   auto-enables them — if your UE4SS uses `mods.txt`, add `PalWhip : 1` etc.).
4. Copy **`PalWhipItem`** and **`PalBoomboxItem`** into
   `Pal\Binaries\Win64\ue4ss\Mods\PalSchema\mods\`.
5. Launch the game. Craft the **Pal Whip** at a Primitive Workbench, walk into your base,
   press **F7**:
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
| `ItemRequirement` | `"equipped"` | `"equipped"` (in hand) / `"inventory"` (carried) / `"none"` |
| `WhipItemId` | `"PalWhip"` | Item id (must match `PalWhipItem/items/palwhip.json`) |
| `PlaySound` | `true` | Play a sound on crack |
| `SoundID` | `""` | Row name from the game's `DT_SoundID` table (tried first if set) |
| `SoundEventName` | `""` | Exact loaded Wwise `AkAudioEvent` name to play |
| `SoundEventPatterns` | whip, … | Fallback: first loaded event whose name contains a pattern |
| `SoundDumpKey` | `"F8"` | Prints all loaded sound event names to the UE4SS console |

Changes apply after a game restart, or hot-reload mods with **Ctrl+R** in the UE4SS console.

### Picking the perfect crack sound

Palworld uses Wwise audio, and its sound event names aren't publicly documented, so PalWhip
discovers them at runtime: by default it plays the first loaded event matching one of the
`SoundEventPatterns`. To pick your favorite:

1. In-game, press **F8** — every loaded sound event name is printed to the UE4SS console.
2. Put the exact name into `SoundEventName` in `config.lua` and hot-reload (**Ctrl+R**).

### Tweaking the item

Edit [PalWhipItem/items/palwhip.json](PalWhipItem/items/palwhip.json) — recipe materials,
price, weight, attack, durability, name, description. The icon is
[PalWhipItem/resources/images/whip.png](PalWhipItem/resources/images/whip.png); replace it
with any PNG you like (it's referenced as `$resource/PalWhipItem/whip`). The icon in this
repo is generated by [tools/make_icon.ps1](tools/make_icon.ps1).

### Choosing the in-hand model

Palworld has no whip mesh, so the Pal Whip borrows a vanilla melee weapon actor via the
item's `actorClass` — model, grip, swing animations and all. Default is the wooden club.
Swap the `actorClass` line for any of these (paths extracted from the game's pak index):

| Look | `actorClass` |
|---|---|
| Wooden club (default) | `/Game/Pal/Blueprint/Weapon/BP_Bat.BP_Bat` |
| Stun baton | `/Game/Pal/Blueprint/Weapon/BP_ElecBaton.BP_ElecBaton` |
| Meat cleaver | `/Game/Pal/Blueprint/Weapon/BP_MeatCutterKnife.BP_MeatCutterKnife` |
| Sword | `/Game/Pal/Blueprint/Weapon/BP_Sword.BP_Sword` |
| Katana | `/Game/Pal/Blueprint/Weapon/BP_Katana.BP_Katana` |
| Spear | `/Game/Pal/Blueprint/Weapon/BP_Spear.BP_Spear` |

A *true* whip mesh with its own crack animation would need a custom Blueprint + skeletal
mesh packaged with the [Palworld Modding Kit](https://pwmodding.wiki/docs/category/palworld-modding-kit)
(UE 5.1) into a `_P` patch pak — the `actorClass` field is exactly where such a Blueprint
would plug in later.

## The Boombox 📻

Craft the **Boombox** at a Primitive Workbench (20× Wood + 10× Stone), then:

- **F6** — open the unified **Pal Tools** panel. It has clickable controls for cracking
  the whip, placing/picking up the boombox, changing tracks, adding music, and raising or
  lowering your local listening volume. A one-time in-game hint introduces this menu.
- **F9** — set the boombox down where you stand / pick it back up. The music stays at
  that spot: walk away and it fades with distance; turn your camera and it pans between
  your left and right ear. The in-world radio prop is temporarily disabled because actor
  spawning crashes the July 2026 Palworld/UE4SS build; audio placement still works.
- **F10** — next track.
- **F11** — open a Windows music picker over the game. Select one or more `.mp3`, `.wav`,
  or `.wma` files and PalBoombox copies them into its music folder automatically.

In hosted co-op, players with PalBoombox installed receive the position, track, and start
time through tagged global chat events, seek to the same playback point, and hear one
shared source from that world position. The visible replicated prop is disabled for
stability until its native actor-spawn path can be replaced.
The release ships with six full recordings selected for the shared boombox:

- *Sail the Raging Sea (Sea Shanty)*
- *Bully In The Alley (Sea Shanty)*
- *Leave Her Johnny (Sea Shanty)*
- *Maggie May (Sea Shanty)*
- *Blow The Man Down (Sea Shanty)*
- *Drunken Sailor (Sea Shanty)*

Those defaults are installed on every machine, so they synchronize without any manual
copying. Other custom tracks are still matched by filename and must exist in every
listener's `music` folder; the current chat transport sends playback commands, not audio
bytes.

**Add your own music:** press F11 in-game and select as many `.mp3`, `.wav`, or `.wma`
files as you want. The picker safely copies them into the installed `PalBoombox\music\`
folder. Identical files are skipped; different songs with the same filename get a numbered
suffix instead of overwriting anything. F10 cycles through every available track
alphabetically when sharing is disabled. In the default multiplayer mode, F9/F10 use only
the six bundled filenames guaranteed to exist for everyone; personal files remain preserved
but are excluded from the shared playlist. Advanced users who install identical custom
filenames on every PC can disable `UseOnlyBundledTracksInMultiplayer`. Personal imports are
never included in GitHub release packages.

### How the spatial audio works

Palworld's Wwise audio engine can't play arbitrary files, so PalBoombox does it outside
the game: the Lua mod samples your position and camera yaw ~10×/second, computes
inverse-square distance falloff plus a camera-relative stereo pan (with a slight muffle
for sounds behind you), and streams `volume`/`balance` values over a file-based IPC
channel (`PalBoombox\ipc\`) to a tiny companion process
([boombox_companion.ps1](PalBoombox/companion/boombox_companion.ps1) — pure PowerShell,
WPF `MediaPlayer`, zero dependencies). The companion loops the track, follows the
volume/pan stream, auto-starts when you first place the boombox, and exits itself when
Palworld closes.

Boombox config lives in [PalBoombox/Scripts/config.lua](PalBoombox/Scripts/config.lua):
keys, master volume, falloff distances (`RefDistance`/`MaxDistance`), pan strength,
item requirement, companion auto-start, multiplayer sharing, and whether the one-time
Pal Tools hint is shown. The F6 volume buttons change and remember a per-player listening
volume from 0% through 200% boost without forcing another player's PC louder. The unsafe native marker path has been
removed completely.

## How it works

- **Item**: PalSchema registers `PalWhip` as a `Weapon` static item (`Weapon` /
  `WeaponMelee`, Rank 1 → craftable at the Primitive Workbench) whose `actorClass` reuses
  a vanilla melee weapon Blueprint for the held model and animations, plus a
  `DT_ItemRecipeDataTable` row for the recipe and a custom icon imported from the PNG.
- **Crack**: on keypress the Lua mod checks what you're holding
  (`ShooterComponent.GetHasWeapon` → `ownItemID.StaticId`, falling back to an inventory
  check via `PalUtility.GetLocalInventoryData` → `CountItemNum`), plays a sound
  (`PalSoundUtility.PlaySoundByActor` for `SoundID`, else
  `PlayAkEventSoundByActor` with a discovered `AkAudioEvent`), then finds all loaded
  `PalCharacter` actors, filters to owned non-player pals in range, and resets the status
  fields on each pal's `PalIndividualCharacterParameter.SaveParameter`:
  `WorkerSick → None`, `SanityValue → 100`, `HP → GetMaxHP()`, `FullStomach → max`.

Ordinary game-API calls are guarded with `pcall`, so renamed fields generally degrade to a
logged error. Native access violations occur below Lua and cannot be caught this way; the
actor-spawn path that caused such a crash has therefore been removed, not merely hidden.

## Multiplayer (hosted co-op)

- **The whip cure is host-side.** Pal status lives on the host's machine, so the *host*
  cracking the whip cures the base for everyone — friends see the effects instantly.
  A friend pressing F7 on their own machine does nothing real (client-side state isn't
  authoritative).
- **Items need everyone.** Item definitions are looked up locally, so every player in the
  session should use `PalWhip-Setup.exe`—otherwise the whip/boombox items appear broken
  to players without the mods, and they can't craft them.
- **Boombox audio is synchronized between modded players.** The host broadcasts the
  position, track, and start time; each player's local companion provides their spatial
  audio. For a host and two friends, install the same current release on all three PCs.
  Each player then hears the same placed source, with volume and stereo pan calculated
  independently from that player's position and camera direction.
- **Music files are still local.** The six bundled recordings are installed for everyone
  and are the only tracks selected in shared mode by default. Preserved personal or legacy
  files therefore cannot split the session into different listener combinations. Additional
  tracks require the same filename on every PC and an explicit config opt-out from the
  bundled-only shared playlist.
- **One shared boombox is active at a time.** This version is designed as a single communal
  music source, not several independently playing radios. The sync path is implemented but
  still needs a live three-client gameplay pass after each Palworld update.

## Notes & limitations

- Pal state lives on the server; on a dedicated server the mods must be installed
  server-side.
- Works on the pals near *you* — stand in (or near) your base when you crack the whip.
- The wielded model is a borrowed vanilla melee weapon (see "Choosing the in-hand model"),
  not a bespoke whip mesh — that would require a custom asset pak.
- If you crafted a Pal Whip with the pre-weapon version of this mod (when it was a
  `Generic` item), drop/discard the old one and craft a fresh whip after updating.
- Verified against PalSchema's documented item/recipe/resource formats and the game's
  dumped SDK headers as of mid-2026. If a patch breaks a field name, check the UE4SS
  console for `[PalWhip]` messages.

## Repo layout

```
PalWhip/                       # UE4SS Lua mod (whip)
├── enabled.txt
└── Scripts/main.lua, config.lua
PalWhipItem/                   # PalSchema mod (whip item + icon)
├── items/palwhip.json
└── resources/images/whip.png
PalBoombox/                    # UE4SS Lua mod (boombox)
├── enabled.txt
├── Scripts/main.lua, config.lua
├── companion/boombox_companion.ps1   # spatial audio player process
├── music/*.mp3                # six preinstalled release recordings
└── ipc/                       # runtime state files (mod <-> companion)
PalBoomboxItem/                # PalSchema mod (boombox item + icon)
├── items/palboombox.json
└── resources/images/boombox-v2.png
tools/make_icon.ps1            # regenerates the whip icon
tools/make_boombox_icon.ps1    # regenerates the boombox icon
tools/make_shanties.py         # generates legacy WAV migration-test fixtures
installer/                     # self-extracting EXE bootstrapper source + manifest
package.ps1                    # builds PalWhip-Setup.exe for sharing
```
