-- PalWhip - crack the whip and get your base pals back to work.
-- Cures sickness (Depression, Ulcer, Sprain, Fracture, Weakness, Cold...),
-- restores sanity, and optionally heals HP / hunger for all of your pals
-- around you when you press the whip key.
--
-- UE4SS Lua mod. Runs on the host / single player.

local UEHelpers = require("UEHelpers")

local ok_cfg, config = pcall(require, "config")
if not ok_cfg or type(config) ~= "table" then
    config = {}
end

-- Defaults in case config.lua is missing or partially edited.
local WHIP_KEY      = config.WhipKey       or "F7"
local RANGE         = config.Range         or 9000.0
local OWNED_ONLY    = (config.OwnedOnly    ~= false)
local CURE_SICKNESS = (config.CureSickness ~= false)
local RESTORE_SAN   = (config.RestoreSanity ~= false)
local HEAL_HP       = (config.HealHP       ~= false)
local FILL_STOMACH  = (config.FillStomach  == true)
local COOLDOWN      = config.Cooldown      or 1.0
local ANNOUNCE      = (config.Announce     ~= false)

local lastCrack = 0.0

local function log(msg)
    print(string.format("[PalWhip] %s\n", tostring(msg)))
end

-- Safe field read: returns nil instead of erroring when a property is missing.
local function tryGet(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

local function guidIsZero(guid)
    if guid == nil then return true end
    local a = tryGet(function() return guid.A end)
    local b = tryGet(function() return guid.B end)
    local c = tryGet(function() return guid.C end)
    local d = tryGet(function() return guid.D end)
    return (a or 0) == 0 and (b or 0) == 0 and (c or 0) == 0 and (d or 0) == 0
end

local function announce(context, text)
    if not ANNOUNCE then return end
    pcall(function()
        local PalUtility = StaticFindObject("/Script/Pal.Default__PalUtility")
        if PalUtility and PalUtility:IsValid() then
            -- Plain Lua strings auto-convert to FString; fall back to FText
            -- in case the signature differs on this game version.
            local ok = pcall(function() PalUtility:SendSystemAnnounce(context, text) end)
            if not ok then
                PalUtility:SendSystemAnnounce(context, FText(text))
            end
        end
    end)
    log(text)
end

-- Returns the individual character parameter object for a pal actor, or nil.
local function getParam(pal)
    return tryGet(function()
        local comp = pal.CharacterParameterComponent
        if comp and comp:IsValid() then
            local param = comp.IndividualParameter
            if param and param:IsValid() then
                return param
            end
        end
        return nil
    end)
end

-- Applies the whip to one pal. Returns true if anything was fixed.
local function whipPal(param)
    local touched = false
    local save = tryGet(function() return param.SaveParameter end)
    if save == nil then return false end

    if CURE_SICKNESS then
        local sick = tryGet(function() return save.WorkerSick end)
        if sick ~= nil and sick ~= 0 then
            pcall(function() save.WorkerSick = 0 end) -- EPalBaseCampWorkerSickType::None
            touched = true
        end
    end

    if RESTORE_SAN then
        local san = tryGet(function() return save.SanityValue end)
        if san ~= nil and san < 100.0 then
            -- Prefer the game's setter so runtime state stays consistent,
            -- fall back to writing the save field directly.
            local usedSetter = pcall(function() param:SetSanityValue(100.0) end)
            if not usedSetter then
                pcall(function() save.SanityValue = 100.0 end)
            end
            touched = true
        end
    end

    if HEAL_HP then
        pcall(function()
            local maxHp = param:GetMaxHP()
            if save.HP.Value < maxHp.Value then
                save.HP.Value = maxHp.Value
                touched = true
            end
        end)
    end

    if FILL_STOMACH then
        pcall(function()
            local maxStomach = save.MaxFullStomach
            if maxStomach and maxStomach > 0 and save.FullStomach < maxStomach then
                save.FullStomach = maxStomach
                touched = true
            end
        end)
    end

    return touched
end

local function crackWhip()
    local now = os.clock()
    if now - lastCrack < COOLDOWN then return end
    lastCrack = now

    local pc = UEHelpers.GetPlayerController()
    if not pc or not pc:IsValid() then
        log("No player controller found (not in game yet?)")
        return
    end
    local pawn = tryGet(function() return pc.Pawn end)
    if not pawn or not pawn:IsValid() then
        log("No player pawn found")
        return
    end

    local ploc = tryGet(function() return pawn:K2_GetActorLocation() end)
    local rangeSq = RANGE > 0 and (RANGE * RANGE) or nil

    local pals = FindAllOf("PalCharacter") or {}
    local cured, seen = 0, 0

    for _, pal in ipairs(pals) do
        if pal and pal:IsValid() and pal ~= pawn then
            local param = getParam(pal)
            if param then
                local save = tryGet(function() return param.SaveParameter end)
                local isPlayer = save and tryGet(function() return save.IsPlayer end)
                if save and isPlayer ~= true then
                    -- Ownership filter: skip wild pals unless configured otherwise.
                    local ownedOk = true
                    if OWNED_ONLY then
                        local owner = tryGet(function() return save.OwnerPlayerUId end)
                        ownedOk = not guidIsZero(owner)
                    end

                    -- Range filter.
                    local rangeOk = true
                    if rangeSq and ploc then
                        local loc = tryGet(function() return pal:K2_GetActorLocation() end)
                        if loc then
                            local dx, dy, dz = loc.X - ploc.X, loc.Y - ploc.Y, loc.Z - ploc.Z
                            rangeOk = (dx * dx + dy * dy + dz * dz) <= rangeSq
                        end
                    end

                    if ownedOk and rangeOk then
                        seen = seen + 1
                        if whipPal(param) then
                            cured = cured + 1
                        end
                    end
                end
            end
        end
    end

    if cured > 0 then
        announce(pawn, string.format("*CRACK* %d pal(s) snapped back to normal. Back to work!", cured))
    else
        announce(pawn, string.format("*CRACK* %d pal(s) in range - all already working hard.", seen))
    end
end

-- Register the whip key.
local keyEnum = Key[WHIP_KEY]
if keyEnum == nil then
    log(string.format("Unknown key '%s' in config.lua, falling back to F7", tostring(WHIP_KEY)))
    keyEnum = Key.F7
    WHIP_KEY = "F7"
end

RegisterKeyBind(keyEnum, {}, function()
    ExecuteInGameThread(crackWhip)
end)

log(string.format("Loaded. Press %s to crack the whip (range %.0f, owned-only: %s).",
    WHIP_KEY, RANGE, tostring(OWNED_ONLY)))
