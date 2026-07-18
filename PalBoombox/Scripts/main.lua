-- PalBoombox - a placeable boombox with spatial audio sea shanties.
--
-- Press the place key to set the boombox down where you stand; it keeps
-- playing at that spot while you walk around. The mod tracks the player's
-- position and camera direction ~10x/second and streams volume + stereo
-- balance to a small audio companion process (PowerShell + WPF MediaPlayer)
-- over a file-based IPC channel, giving real distance falloff and panning.
--
-- UE4SS Lua mod. Client-side audio; works in single player / host.

local UEHelpers = require("UEHelpers")

local ok_cfg, config = pcall(require, "config")
if not ok_cfg or type(config) ~= "table" then config = {} end

local PLACE_KEY      = config.PlaceKey       or "F9"
local NEXT_KEY       = config.NextTrackKey   or "F10"
local REQUIRE_ITEM   = (config.RequireItem   ~= false)
local ITEM_ID        = config.ItemId         or "PalBoombox"
local MASTER_VOLUME  = config.MasterVolume   or 0.8
local REF_DIST       = config.RefDistance    or 800.0
local MAX_DIST       = config.MaxDistance    or 8000.0
local PAN_STRENGTH   = config.PanStrength    or 0.8
local AUTO_START     = (config.AutoStartCompanion ~= false)
local ANNOUNCE       = (config.Announce      ~= false)

local placed = false
local boomboxPos = nil          -- {X=, Y=, Z=}
local tracks = {}
local trackIndex = 1
local seq = 0
local basePath = nil            -- resolved mod folder path relative to game cwd
local lastCompanionStart = 0
local warnedNoCompanion = false

local function log(msg)
    print(string.format("[PalBoombox] %s\n", tostring(msg)))
end

local function tryGet(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

local function announce(context, text)
    if ANNOUNCE then
        pcall(function()
            local PalUtility = StaticFindObject("/Script/Pal.Default__PalUtility")
            if PalUtility and PalUtility:IsValid() then
                local ok = pcall(function() PalUtility:SendSystemAnnounce(context, text) end)
                if not ok then PalUtility:SendSystemAnnounce(context, FText(text)) end
            end
        end)
    end
    log(text)
end

-- ---------------------------------------------------------------------------
-- File IPC
-- ---------------------------------------------------------------------------

-- The game's working directory varies (Win64 or the game root), so probe for
-- the mod folder once and remember which prefix works.
local function resolveBasePath()
    if basePath then return basePath end
    local candidates = {
        "ue4ss/Mods/PalBoombox/",
        "Pal/Binaries/Win64/ue4ss/Mods/PalBoombox/",
        "Mods/PalBoombox/",
    }
    for _, candidate in ipairs(candidates) do
        local f = io.open(candidate .. "companion/boombox_companion.ps1", "r")
        if f then
            f:close()
            basePath = candidate
            log("Mod folder resolved to " .. candidate)
            return basePath
        end
    end
    log("WARNING: could not locate the PalBoombox folder from the game's working directory")
    return nil
end

local function writeState(fields)
    local base = resolveBasePath()
    if not base then return end
    seq = seq + 1
    fields.seq = seq
    local lines = {}
    for k, v in pairs(fields) do
        table.insert(lines, string.format("%s=%s", k, tostring(v)))
    end
    local f = io.open(base .. "ipc/state.txt", "w")
    if f then
        f:write(table.concat(lines, "\n"))
        f:close()
    end
end

-- Reads the companion heartbeat; returns alive (bool) and refreshes `tracks`.
local function readCompanion()
    local base = resolveBasePath()
    if not base then return false end
    local f = io.open(base .. "ipc/companion.txt", "r")
    if not f then return false end
    local alive = 0
    local found = {}
    for line in f:lines() do
        local k, v = line:match("^([%w_]+)=(.*)$")
        if k == "alive" then alive = tonumber(v) or 0 end
        if k == "track" then table.insert(found, v) end
    end
    f:close()
    if #found > 0 then tracks = found end
    return (os.time() - alive) < 8
end

local function startCompanion()
    local base = resolveBasePath()
    if not base then return end
    local now = os.time()
    if now - lastCompanionStart < 15 then return end
    lastCompanionStart = now
    local script = (base .. "companion/boombox_companion.ps1"):gsub("/", "\\")
    log("Starting audio companion...")
    os.execute(string.format(
        'start "" /min powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%s"',
        script))
end

local function ensureCompanion()
    if readCompanion() then return true end
    if AUTO_START then startCompanion() end
    return false
end

-- ---------------------------------------------------------------------------
-- Game queries
-- ---------------------------------------------------------------------------

local function getPawn()
    local pc = UEHelpers.GetPlayerController()
    if not pc or not pc:IsValid() then return nil end
    local pawn = tryGet(function() return pc.Pawn end)
    if pawn and pawn:IsValid() then return pawn, pc end
    return nil
end

local function hasBoomboxItem(pawn)
    if not REQUIRE_ITEM then return true end
    local ok, count = pcall(function()
        local PalUtility = StaticFindObject("/Script/Pal.Default__PalUtility")
        local inv = PalUtility:GetLocalInventoryData(pawn)
        if inv and inv:IsValid() then
            return inv:CountItemNum(FName(ITEM_ID))
        end
        return nil
    end)
    if ok and count ~= nil then return count > 0 end
    log("Could not check inventory for the Boombox item, allowing anyway")
    return true
end

-- Returns camera yaw in degrees (falls back to pawn yaw).
local function getListenerYaw(pawn, pc)
    local yaw = tryGet(function()
        return pc.PlayerCameraManager:GetCameraRotation().Yaw
    end)
    if yaw == nil then
        yaw = tryGet(function() return pawn:K2_GetActorRotation().Yaw end)
    end
    return yaw or 0.0
end

local function prettyTrackName(file)
    local name = file:gsub("%.%w+$", ""):gsub("_", " ")
    return (name:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

-- ---------------------------------------------------------------------------
-- Spatial update loop (runs while placed)
-- ---------------------------------------------------------------------------

local function spatialTick()
    if not placed or not boomboxPos then return true end -- true stops the loop

    local pawn, pc = getPawn()
    if not pawn then return false end

    local loc = tryGet(function() return pawn:K2_GetActorLocation() end)
    if not loc then return false end

    local dx = boomboxPos.X - loc.X
    local dy = boomboxPos.Y - loc.Y
    local dz = boomboxPos.Z - loc.Z
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

    -- Inverse-square-ish falloff with a hard cutoff.
    local volume = 0.0
    if dist < MAX_DIST then
        volume = MASTER_VOLUME / (1.0 + (dist / REF_DIST) ^ 2)
        volume = volume * (1.0 - dist / MAX_DIST) ^ 0.3 -- ease to zero at the edge
    end

    -- Pan: angle of the boombox relative to the camera's facing direction.
    -- UE yaw and atan2(dy,dx) share the same convention (0 = +X, + toward +Y),
    -- so balance = sin(relative angle): +1 fully right, -1 fully left.
    local balance = 0.0
    if dist > 50 then
        local yaw = getListenerYaw(pawn, pc)
        local rel = math.rad(math.deg(math.atan(dy, dx)) - yaw)
        balance = math.sin(rel) * PAN_STRENGTH
        -- Slightly muffle sounds behind the listener.
        volume = volume * (0.85 + 0.15 * math.cos(rel))
    end

    writeState({
        playing = 1,
        track = tracks[trackIndex] or "",
        volume = string.format("%.3f", volume),
        balance = string.format("%.3f", balance),
    })
    return false
end

-- ---------------------------------------------------------------------------
-- Key handlers
-- ---------------------------------------------------------------------------

local function toggleBoombox()
    local pawn = getPawn()
    if not pawn then
        log("No player pawn found (not in game yet?)")
        return
    end

    if placed then
        placed = false
        boomboxPos = nil
        writeState({ playing = 0 })
        announce(pawn, "Boombox picked up. The sea falls silent.")
        return
    end

    if not hasBoomboxItem(pawn) then
        announce(pawn, "You need a Boombox in your inventory to set one down!")
        return
    end

    ensureCompanion()
    if #tracks == 0 then
        readCompanion()
    end
    if #tracks == 0 then
        if not warnedNoCompanion then
            warnedNoCompanion = true
            announce(pawn, "Boombox: audio companion is starting, try again in a few seconds...")
        else
            announce(pawn, "Boombox: no tracks found (is the companion running and the music folder populated?)")
        end
        return
    end

    local loc = tryGet(function() return pawn:K2_GetActorLocation() end)
    if not loc then return end
    boomboxPos = { X = loc.X, Y = loc.Y, Z = loc.Z }
    placed = true

    announce(pawn, string.format("Boombox set down - now playing: %s",
        prettyTrackName(tracks[trackIndex] or "?")))

    LoopAsync(100, function()
        return spatialTick()
    end)
end

local function nextTrack()
    readCompanion()
    if #tracks == 0 then
        log("No tracks available yet")
        return
    end
    trackIndex = (trackIndex % #tracks) + 1
    local pawn = getPawn()
    if placed then
        -- state is refreshed by the spatial loop; announce the change
        if pawn then
            announce(pawn, "Now playing: " .. prettyTrackName(tracks[trackIndex]))
        end
    else
        if pawn then
            announce(pawn, "Next up: " .. prettyTrackName(tracks[trackIndex]))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

local function bind(keyName, fallback, fn)
    local key = Key[keyName]
    if key == nil then
        log(string.format("Unknown key '%s', falling back to %s", tostring(keyName), fallback))
        key = Key[fallback]
    end
    RegisterKeyBind(key, {}, function()
        ExecuteInGameThread(fn)
    end)
end

bind(PLACE_KEY, "F9", toggleBoombox)
bind(NEXT_KEY, "F10", nextTrack)

-- Make sure any stale state from a previous session doesn't keep playing.
writeState({ playing = 0 })

log(string.format("Loaded. %s places/picks up the boombox, %s switches tracks.",
    PLACE_KEY, NEXT_KEY))
