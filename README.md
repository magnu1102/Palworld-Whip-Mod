# PalWhip + Field Boombox

## Download

### [Download the one-click installer: PalWhip-Setup.exe](https://github.com/magnu1102/Palworld-Whip-Mod/releases/latest/download/PalWhip-Setup.exe)

That EXE is the only download needed for a new installation or an update. Close
Palworld, run it, and approve the Windows administrator prompt. It discovers the
Steam installation, installs or reuses UE4SS and PalSchema, and installs both
mods. The installer is currently unsigned, so Windows may show an unknown
publisher warning.

Updates are in-place: do not uninstall first. User-edited configuration and the
entire installed `PalBoombox\music` folder are verified and preserved. Obsolete
mod-owned UI/runtime files from older releases are removed automatically.

## What is included

| Part | Purpose |
|---|---|
| `PalWhip` | UE4SS Lua logic for curing and restoring base pals |
| `PalWhipItem` | PalSchema weapon, recipe, and icon |
| `PalBoombox` | Silent-in-the-background spatial audio and world-object discovery |
| `PalBoomboxItem` | PalSchema item, native building registration, and icon |

## Field Boombox

The Field Boombox is now a real Palworld building, not a coordinate marker or a
Lua-spawned actor.

1. Craft a **Boombox** at a Primitive Workbench (20 Wood + 10 Stone).
2. Unlock **Field Boombox** in Technology at level 1 (0 Technology Points).
3. Open Palworld's normal build menu and place it like any other furniture.
4. Its synchronized sea-shanty playlist starts automatically after the
   completed replicated building appears.
5. Press **F8** to pause or resume and **F9** to start the next bundled song.
   Next Track seeks directly to the beginning of that song.
6. Use Palworld's normal dismantle mode to remove it and stop playback.

Palworld therefore owns placement preview, rotation, collision validation,
construction, replication, save persistence, damage, and dismantling. The
placeable uses a compact native electronic-furniture Blueprint with the custom
boombox icon. The mod never calls UE4SS actor-spawn functions.

There is no separate Pal Tools window and no hidden chat-message transport.
Normal world scans, synchronization, startup, and track changes are silent.
Only explicit local controls provide a concise in-game confirmation:

- **F5**: lower local listening volume by 25%
- **F6**: raise local listening volume by 25% (up to 300%)
- **F7**: crack the equipped Pal Whip
- **F8**: pause or resume the Field Boombox
- **F9**: seek to the beginning of the next track

Listening volume is saved per PC. Values above 100% use up to three synchronized
audio layers, so the boost is real rather than being clipped by WPF's 100%
`MediaPlayer.Volume` limit.

### Multiplayer behavior

Every player who should hear the music must install the same release. Palworld
replicates the placed Field Boombox to all clients. Each client discovers that
same completed `PalBoombox` build object and calculates spatial volume and stereo
pan from their own position and camera.

The nine bundled files and their reviewed durations form one deterministic UTC
playlist. This means all clients select the same track and seek position without
depending on chat delivery order, host/client authority, or a one-time placement
packet. A player joining later synchronizes automatically. Playback drift is
checked every 15 seconds and corrected only when it exceeds four seconds.

F8/F9 currently control the local listener. Shared pause/seek state requires a
cooked replicated Palworld LogicMod; UE4SS interface out-parameter rewriting is
not used because it is unsafe on Palworld 1.0.

If several Field Boomboxes exist, each player hears the nearest one. They all
carry the same synchronized station program, which keeps multiplayer behavior
deterministic while allowing radios at more than one base.

The bundled playlist contains:

- Blow The Man Down
- Bully In The Alley
- Drunken Sailor
- Leave Her Johnny
- Maggie May
- Sail the Raging Sea
- Roll Jordan Roll
- Down to the River to Pray
- Gonna See Miss Liza

The installer preserves personal files already in `PalBoombox\music`, but the
shared station intentionally plays only the preinstalled release manifest.
Additional shared soundtracks should be added to a future release so every
client receives the same file and timing metadata. The old external Windows file
picker has been removed.

### Spatial audio implementation

Palworld's Wwise runtime cannot decode arbitrary MP3 files. A hidden PowerShell
companion therefore uses Windows `MediaPlayer` for decoding. Lua scans the native
replicated build object once per second and stores only its numeric coordinates;
it never retains a transient Unreal object between ticks. At 10 Hz it writes
distance falloff, camera-relative stereo balance, track, and seek state.

The first 8 metres remain at full listening volume. Between 8 and 80 metres a
smoothstep curve lowers the distant signal earlier and reaches silence with a
zero-slope tail, avoiding an audible cliff at the outer boundary.

IPC snapshots contain matching `seq` and `commit` values. The companion ignores
a partially rewritten snapshot and continues using the last complete one. This
prevents file-read races from briefly stopping, changing, or desynchronizing
playback.

## Pal Whip

Craft the **Pal Whip** at a Primitive Workbench (5 Leather + 10 Wood), equip it,
stand near your base, and press **F7**. It can:

- clear Depression, Ulcer, Sprain, Fracture, Weakness, Cold, and related sickness;
- restore SAN to 100;
- heal to full HP (enabled by default);
- refill hunger (optional, disabled by default).

The whip is also a light melee weapon. Swinging it normally deals damage; the
restorative effect is the F7 crack action. Pal state is server-authoritative, so
in hosted co-op the host should perform the restorative crack.

## Configuration

Edit `PalWhip/Scripts/config.lua` or `PalBoombox/Scripts/config.lua` in the
installed UE4SS Mods folder, then restart the game. Existing configuration files
are preserved across installer updates, while missing new settings receive safe
defaults in Lua.

Important boombox defaults:

| Setting | Default | Meaning |
|---|---:|---|
| `VolumeDownKey` | `F5` | Lower local listening volume |
| `VolumeUpKey` | `F6` | Raise local listening volume |
| `PauseKey` | `F8` | Pause or resume local playback |
| `NextTrackKey` | `F9` | Seek local playback to the next track |
| `MasterVolume` | `1.5` | Initial 150% gain for a fresh install |
| `MaxVolume` | `3.0` | Maximum layered gain |
| `RefDistance` | `800` | Full-volume radius (8 m) |
| `MaxDistance` | `8000` | Inaudible distance (80 m) |
| `FadeExponent` | `0.65` | Shapes the smooth mid/outer-distance fade |
| `ShowControlFeedback` | `true` | Confirm explicit volume presses in game |
| `DebugLogging` | `false` | Enable UE4SS diagnostics only for troubleshooting |

Important whip defaults include `WhipKey = "F7"`, `Range = 9000`,
`ItemRequirement = "equipped"`, and toggles for sickness, SAN, HP, and hunger.
Routine lifecycle logging is disabled unless `DebugLogging` is enabled.

## Manual installation

The one-click installer is the supported path. For development or unusual
portable Steam layouts:

1. Install the Palworld experimental build of
   [UE4SS](https://github.com/Okaetsu/RE-UE4SS).
2. Install [PalSchema](https://okaetsu.github.io/PalSchema/).
3. Copy `PalWhip` and `PalBoombox` to
   `Pal\Binaries\Win64\ue4ss\Mods\`.
4. Copy `PalWhipItem` and `PalBoomboxItem` to
   `Pal\Binaries\Win64\ue4ss\Mods\PalSchema\mods\`.

Advanced users can run:

```powershell
.\install.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Palworld"
```

## Development checks

`tools/test_release.ps1` parses every PowerShell and Lua file, validates JSON,
checks the native-building and no-chat/no-spawn invariants, validates layered
gain and committed IPC, simulates an upgrade with personal music/configuration,
builds the installer, and inspects its embedded payload.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_release.ps1
```
