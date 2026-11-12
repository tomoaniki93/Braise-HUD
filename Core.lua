-- =====================================================================
-- Braise / Core.lua
--
-- Braise is a small living HUD for WoW: Forever. Out of combat it idles:
-- two thin arcs breathe around the character, a dashed ring turns slowly,
-- a few embers drift up. Entering combat ignites it; leaving combat calms
-- it down and slides in a short recap of the fight.
--
-- This file owns everything the three modules share:
--   * saved variables, themes, the fr/en text helper
--   * the tween driver (one OnUpdate for every eased value in the addon)
--   * the anchor frame the halo and the effects hang from
--   * the combat / experience state machine and the module dispatcher
--   * secret-value helpers (Forever runs the Midnight client: health and
--     power may be secret in combat, so they are never compared or added
--     in Lua, only handed to widgets and C-side curves)
-- =====================================================================

local ADDON, B = ...
Braise = B

B.MEDIA     = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
B.FONT      = B.MEDIA .. "Poppins-Medium.ttf"
B.FONT_BOLD = B.MEDIA .. "Poppins-SemiBold.ttf"
B.WHITE     = "Interface\\Buttons\\WHITE8x8"

local IS_FR = GetLocale() == "frFR"
function B.T(fr, en) return IS_FR and fr or en end
local T = B.T

-- ---------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------
B.defaults = {
    halo        = true,   -- the two arcs
    target      = true,   -- outer arcs for the target
    pet         = true,   -- inner arcs for the pet
    tot         = true,   -- target of target, above the target's name
    cast        = true,   -- cast arcs (player bottom, target top)
    combo       = true,   -- combo point pips
    buffs       = true,   -- missing-buff reminders
    click       = true,   -- arcs take clicks: left targets, right opens the unit menu
    hidePlayer  = false,  -- hide the player unit frame
    hideTarget  = false,  -- hide the target unit frame
    hidePet     = false,  -- hide the pet unit frame
    hideToT     = true,   -- hide the target-of-target unit frame
    hideCastTarget = true,  -- hide Blizzard's cast bar under the target frame
    hideCastPlayer = false, -- hide Blizzard's own cast bar
    texts       = true,   -- health / power numbers under the arcs
    ring        = true,   -- rotating rings
    embers      = true,   -- drifting particles
    classEmbers = true,   -- embers move the way the class does (colours come from the theme)
    threat      = true,   -- threat gauge at the top of the halo
    tankMode    = false,  -- threat reads the other way round: holding aggro is good
    vignette    = true,   -- screen-edge heat and low-health heartbeat
    transitions = true,   -- shockwave + blades on combat start / end
    timer       = true,   -- combat timer under the halo
    recap       = true,   -- after-combat card
    levelup     = true,   -- level-up fanfare
    scale       = 1.0,
    oocAlpha    = 0.35,   -- halo opacity when idle
    emberAmount = 1.0,
    x           = 0,
    y           = 0,
    theme       = "classe",
    version     = 2,
}

-- accent: idle colour. hot: combat colour.
B.themes = {
    { key = "braise", fr = "Braise", en = "Ember",  accent = { 0.79, 0.64, 0.32 }, hot = { 1.00, 0.42, 0.14 } },
    { key = "givre",  fr = "Givre",  en = "Frost",  accent = { 0.62, 0.82, 1.00 }, hot = { 0.30, 0.62, 1.00 } },
    { key = "seve",   fr = "Sève",   en = "Sap",    accent = { 0.62, 0.85, 0.48 }, hot = { 0.96, 0.84, 0.26 } },
    { key = "classe", fr = "Classe", en = "Class",  accent = { 1, 1, 1 },          hot = { 1, 1, 1 } },   -- palette from B.CLASS_FX
}

function B.Theme()
    local key = B.db and B.db.theme
    for _, th in ipairs(B.themes) do
        if th.key == key then return th end
    end
    return B.themes[1]
end

-- ---------------------------------------------------------------------
-- Secret values
-- ---------------------------------------------------------------------
local issecretvalue = issecretvalue
function B.Secret(v) return issecretvalue ~= nil and issecretvalue(v) end

--- A number Lua may do arithmetic on, or nil.
function B.Num(v)
    if type(v) ~= "number" or B.Secret(v) then return nil end
    return v
end

--- A boolean Lua may branch on (a secret boolean reads as false).
function B.Flag(v)
    if B.Secret(v) then return false end
    return v and true or false
end

-- ---------------------------------------------------------------------
-- Tweens: one driver frame, keyed so a new tween replaces the old one
-- ---------------------------------------------------------------------
B.Ease = {
    linear   = function(p) return p end,
    outCubic = function(p) p = 1 - p; return 1 - p * p * p end,
    inCubic  = function(p) return p * p * p end,
    inOut    = function(p) return p < 0.5 and 4 * p * p * p or 1 - ((-2 * p + 2) ^ 3) / 2 end,
    outBack  = function(p) local c = 1.70158; p = p - 1; return 1 + (c + 1) * p * p * p + c * p * p end,
}

local active = {}
local driver = CreateFrame("Frame")
driver:Hide()

--- Drive fn(value) from `from` to `to` over `dur` seconds.
function B.Tween(key, dur, from, to, fn, ease, done)
    if not dur or dur <= 0 then
        active[key] = nil
        fn(to)
        if done then done() end
        return
    end
    local tw = active[key] or {}
    tw.t, tw.d, tw.a, tw.b = 0, dur, from, to
    tw.fn, tw.e, tw.done = fn, ease or B.Ease.outCubic, done
    active[key] = tw
    fn(from)
    driver:Show()
end

function B.StopTween(key) active[key] = nil end

driver:SetScript("OnUpdate", function(_, dt)
    local finished
    for key, tw in pairs(active) do
        tw.t = tw.t + dt
        local p = tw.t / tw.d
        if p >= 1 then
            active[key] = nil
            tw.fn(tw.b)
            if tw.done then
                finished = finished or {}
                finished[#finished + 1] = tw.done
            end
        else
            tw.fn(tw.a + (tw.b - tw.a) * tw.e(p))
        end
    end
    if finished then
        for i = 1, #finished do finished[i]() end
    end
    if not next(active) then driver:Hide() end
end)

--- Fade a frame from its current alpha; hides it when it reaches 0.
function B.Fade(frame, to, dur, ease)
    if to > 0 then frame:Show() end
    B.Tween(frame, dur, frame:GetAlpha(), to, function(a) frame:SetAlpha(a) end, ease, function()
        if to <= 0 then frame:Hide() end
    end)
end

function B.Lerp(a, b, p) return a + (b - a) * p end

-- ---------------------------------------------------------------------
-- Anchor: everything centred on the character hangs from this frame
-- ---------------------------------------------------------------------
local anchor = CreateFrame("Frame", "BraiseAnchor", UIParent)
anchor:SetSize(2, 2)
anchor:SetPoint("CENTER")
anchor:SetFrameStrata("LOW")
B.anchor = anchor

function B.ApplyAnchor()
    local db = B.db
    -- The click zones are secure frames anchored here, which makes the
    -- anchor itself untouchable in combat: wait for the fight to end.
    if InCombatLockdown() then
        B.anchorPending = true
        return
    end
    B.anchorPending = nil
    local s = math.max(0.4, math.min(2, db.scale or 1))
    anchor:SetScale(s)
    anchor:ClearAllPoints()
    -- Offsets are stored in UIParent units; SetPoint reads them in the
    -- frame's own scale, hence the division.
    anchor:SetPoint("CENTER", UIParent, "CENTER", (db.x or 0) / s, (db.y or 0) / s)
end

-- ---------------------------------------------------------------------
-- Unit frames: the arcs can stand in for the player and target frames
-- ---------------------------------------------------------------------
-- Blizzard's frames and TomoModForever's are secure, so they are never
-- hidden or reparented: they are made transparent (allowed at any time)
-- and stop taking the mouse (only outside combat, hence the retry when
-- combat ends).
local UNIT_FRAMES = {
    hidePlayer = { "PlayerFrame", "TomoMod_UF_player" },
    hideTarget = { "TargetFrame", "TomoMod_UF_target" },
    hidePet    = { "PetFrame", "TomoMod_UF_pet" },
    hideToT    = { "TargetFrameToT", "TomoMod_UF_targettarget" },
}
local touched = {}      -- frame -> its alpha before Braise hid it

function B.ApplyUnitFrames()
    local locked = InCombatLockdown()
    for key, names in pairs(UNIT_FRAMES) do
        local hide = B.db[key]
        for _, name in ipairs(names) do
            local f = rawget(_G, name)
            if type(f) == "table" and f.SetAlpha and (hide or touched[f]) then
                if hide then
                    if not touched[f] then touched[f] = f:GetAlpha() end
                    if touched[f] <= 0 then touched[f] = 1 end
                    f:SetAlpha(0)
                    if not locked then f:EnableMouse(false) end
                else
                    f:SetAlpha(touched[f])
                    if not locked then
                        f:EnableMouse(true)
                        touched[f] = nil
                    end
                end
            end
        end
    end
    B.ApplyCastBars()
end

-- Blizzard's cast bars are ordinary frames that show themselves on every
-- cast: a hook on OnShow sends them straight back, for as long as the
-- option is on. Turning it off needs nothing undone.
local CAST_BARS = { hideCastTarget = "TargetFrameSpellBar", hideCastPlayer = "PlayerCastingBarFrame" }
local hookedBars = {}

function B.ApplyCastBars()
    for key, name in pairs(CAST_BARS) do
        local bar = rawget(_G, name)
        if type(bar) == "table" and bar.HookScript and B.db[key] then
            if not hookedBars[bar] then
                hookedBars[bar] = true
                bar:HookScript("OnShow", function(self)
                    if B.db[key] then self:Hide() end
                end)
            end
            bar:Hide()
        end
    end
end

-- Colours ---------------------------------------------------------------
local classRGB
local function ClassColor()
    if classRGB then return classRGB end
    local _, class = UnitClass("player")
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    classRGB = c and { c.r, c.g, c.b } or { 0.79, 0.64, 0.32 }
    return classRGB
end

-- Each class has its own palette (idle, combat), used by every accent of
-- the HUD, and its own way of moving embers. speed > 1 is quicker, drift widens the sideways wander, rise
-- stretches the climb, size scales the particle.
B.CLASS_FX = {
    WARRIOR     = { idle = { 0.86, 0.42, 0.24 }, hot = { 1.00, 0.26, 0.10 }, speed = 1.35, drift = 0.6, rise = 1.15, size = 0.9 },  -- forge sparks
    PALADIN     = { idle = { 1.00, 0.86, 0.50 }, hot = { 1.00, 0.72, 0.82 }, speed = 0.85, drift = 0.3, rise = 1.25, size = 1.15 }, -- motes of light, straight up
    HUNTER      = { idle = { 0.62, 0.82, 0.42 }, hot = { 0.74, 0.95, 0.36 }, speed = 1.00, drift = 2.4, rise = 0.75, size = 0.9 },  -- carried by the wind
    ROGUE       = { idle = { 0.92, 0.84, 0.36 }, hot = { 1.00, 0.92, 0.30 }, speed = 1.60, drift = 1.6, rise = 0.80, size = 0.75 }, -- quick glints
    PRIEST      = { idle = { 0.96, 0.95, 0.90 }, hot = { 1.00, 0.94, 0.70 }, speed = 0.70, drift = 0.5, rise = 1.10, size = 1.35 }, -- slow, soft, large
    SHAMAN      = { idle = { 0.30, 0.56, 1.00 }, hot = { 0.45, 0.78, 1.00 }, speed = 1.80, drift = 1.9, rise = 0.60, size = 0.8 },  -- static, short and jumpy
    MAGE        = { idle = { 0.56, 0.82, 1.00 }, hot = { 0.74, 0.60, 1.00 }, speed = 0.90, drift = 1.0, rise = 1.00, size = 1.0 },  -- arcane frost
    WARLOCK     = { idle = { 0.62, 0.44, 0.90 }, hot = { 0.56, 1.00, 0.30 }, speed = 0.95, drift = 1.5, rise = 1.00, size = 1.05 }, -- shadow, then fel
    DRUID       = { idle = { 0.98, 0.58, 0.20 }, hot = { 0.55, 0.92, 0.38 }, speed = 0.80, drift = 2.0, rise = 0.85, size = 1.1 },  -- drifting leaves
    MONK        = { idle = { 0.36, 0.92, 0.66 }, hot = { 0.30, 1.00, 0.72 }, speed = 1.05, drift = 1.7, rise = 0.95, size = 0.95 }, -- jade mist
    DEATHKNIGHT = { idle = { 0.56, 0.80, 0.92 }, hot = { 0.82, 0.16, 0.22 }, speed = 0.80, drift = 0.7, rise = 0.90, size = 1.1 },
    DEMONHUNTER = { idle = { 0.66, 0.30, 0.86 }, hot = { 0.62, 1.00, 0.24 }, speed = 1.40, drift = 1.2, rise = 1.10, size = 0.9 },
    EVOKER      = { idle = { 0.30, 0.72, 0.62 }, hot = { 0.40, 0.92, 0.78 }, speed = 1.00, drift = 1.3, rise = 1.10, size = 1.0 },
}

--- r, g, b of the theme. hot = combat colour. The "classe" theme reads
--- the class palette above.
function B.Color(hot)
    local th = B.Theme()
    if th.key == "classe" then
        local _, class = UnitClass("player")
        local fx = class and B.CLASS_FX[class]
        if fx then
            local c = hot and fx.hot or fx.idle
            return c[1], c[2], c[3]
        end
    end
    if th.key == "classe" then
        local c = ClassColor()
        if hot then
            return B.Lerp(c[1], 1, 0.25), B.Lerp(c[2], 1, 0.25), B.Lerp(c[3], 1, 0.25)
        end
        return c[1], c[2], c[3]
    end
    local c = hot and th.hot or th.accent
    return c[1], c[2], c[3]
end

--- Theme colour for the current state.
function B.StateColor() return B.Color(B.inCombat) end

-- ---------------------------------------------------------------------
-- Modules
-- ---------------------------------------------------------------------
B.modules = {}
function B.Module(name)
    local m = {}
    B.modules[#B.modules + 1] = m
    B[name] = m
    return m
end

function B.Call(method, ...)
    for _, m in ipairs(B.modules) do
        local fn = m[method]
        if fn then fn(m, ...) end
    end
end

-- ---------------------------------------------------------------------
-- Experience tracker (vanilla levelling: XP is the number that matters)
-- ---------------------------------------------------------------------
local xp = { total = 0 }

local function TrackXP()
    local cur, mx = B.Num(UnitXP("player")), B.Num(UnitXPMax("player"))
    local lvl = B.Num(UnitLevel("player"))
    if not cur or not mx or not lvl then return end
    if xp.last and xp.level then
        if lvl == xp.level then
            if cur > xp.last then xp.total = xp.total + (cur - xp.last) end
        elseif lvl > xp.level then
            xp.total = xp.total + math.max(0, xp.lastMax - xp.last) + cur
        end
    end
    xp.last, xp.lastMax, xp.level = cur, mx, lvl
end

local function XPProgress()
    local cur, mx = B.Num(UnitXP("player")), B.Num(UnitXPMax("player"))
    if not cur or not mx or mx <= 0 then return nil end
    return cur / mx, cur, mx
end

-- ---------------------------------------------------------------------
-- Combat state
-- ---------------------------------------------------------------------
local fight = {}

local function StartCombat(simulated)
    if B.inCombat then return end
    B.inCombat = true
    B.combatT0 = GetTime()
    TrackXP()
    fight.xp0 = xp.total
    fight.level = xp.level
    fight.before = XPProgress()
    fight.simulated = simulated
    B.Call("CombatStart")
end

local function EndCombat(fakeDuration, fakeXP)
    if not B.inCombat then return end
    B.inCombat = false
    local duration = fakeDuration or (GetTime() - (B.combatT0 or GetTime()))
    B.Call("CombatEnd", duration)
    -- The kill's XP usually lands a moment after combat drops.
    C_Timer.After(0.7, function()
        if B.inCombat then return end
        TrackXP()
        local after, cur, mx = XPProgress()
        B.Call("Recap", {
            duration = duration,
            xp       = fakeXP or (xp.total - (fight.xp0 or xp.total)),
            before   = fight.before,
            after    = after,
            cur      = cur,
            max      = mx,
            leveled  = fight.level ~= nil and xp.level ~= nil and xp.level > fight.level,
        })
    end)
end

--- A scripted fight, for /braise test and the options panel.
function B.Demo()
    if InCombatLockdown() or B.inCombat then return end
    StartCombat(true)
    C_Timer.After(4.5, function()
        if fight.simulated and not InCombatLockdown() then
            EndCombat(42, 380)
        end
    end)
end

-- ---------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")

local function Init()
    BraiseDB = type(BraiseDB) == "table" and BraiseDB or {}
    -- 1.4-1.6 had class colours as a switch that overrode the theme; they
    -- are now a theme of their own. Keep what the player was seeing.
    if BraiseDB.theme ~= nil and BraiseDB.version == nil and BraiseDB.classEmbers == true then
        BraiseDB.theme = "classe"
    end
    for k, v in pairs(B.defaults) do
        if type(BraiseDB[k]) ~= type(v) then BraiseDB[k] = v end
    end
    B.db = BraiseDB
    B.ApplyAnchor()
    B.Call("Init")
    B.ApplyUnitFrames()

    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_XP_UPDATE")
    events:RegisterEvent("PLAYER_LEVEL_UP")
    events:RegisterEvent("PLAYER_DEAD")
    events:RegisterEvent("PLAYER_ALIVE")
    events:RegisterEvent("PLAYER_UNGHOST")
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("UI_SCALE_CHANGED")
end

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            events:UnregisterEvent("ADDON_LOADED")
            Init()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        fight.simulated = nil
        B.inCombat = InCombatLockdown() and true or false
        if B.inCombat then B.combatT0 = GetTime() end
        TrackXP()
        B.Call("Refresh")
        B.ApplyUnitFrames()
        -- Other addons build their unit frames around login; catch them too.
        C_Timer.After(2, B.ApplyUnitFrames)
    elseif event == "PLAYER_REGEN_DISABLED" then
        if fight.simulated then      -- a real fight interrupts the demo
            fight.simulated = nil
            B.inCombat = false
        end
        StartCombat(false)
    elseif event == "PLAYER_REGEN_ENABLED" then
        EndCombat()
        B.ApplyUnitFrames()
        if B.anchorPending then B.ApplyAnchor() end
        B.Halo:ApplyClicks()
    elseif event == "PLAYER_XP_UPDATE" then
        TrackXP()
    elseif event == "PLAYER_LEVEL_UP" then
        if B.db.levelup then B.Call("LevelUp", tonumber(arg1) or UnitLevel("player")) end
    else
        B.Call("Refresh")
    end
end)

-- ---------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------
local PREFIX = "|cffFFD100Braise|r "

function B.Print(msg) print(PREFIX .. msg) end

function B.Reset()
    for k, v in pairs(B.defaults) do B.db[k] = v end
    B.ApplyAnchor()
    B.ApplyUnitFrames()
    B.Call("Refresh")
end

SLASH_BRAISE1 = "/braise"
SLASH_BRAISE2 = "/brz"
SlashCmdList["BRAISE"] = function(msg)
    msg = string.lower(strtrim(msg or ""))
    if msg == "test" then
        B.Demo()
    elseif msg == "level" or msg == "niveau" then
        B.Call("LevelUp", (B.Num(UnitLevel("player")) or 1) + 1)
    elseif msg == "move" or msg == "bouger" then
        B.Halo:ToggleMover()
    elseif msg == "reset" then
        B.Reset()
        B.Print(T("réglages remis à zéro.", "settings reset."))
    elseif msg == "help" or msg == "aide" then
        B.Print(T("commandes :", "commands:"))
        print("  /braise - " .. T("ouvrir les réglages", "open the settings"))
        print("  /braise test - " .. T("jouer un combat de démonstration", "play a demo fight"))
        print("  /braise level - " .. T("jouer l'animation de niveau", "play the level-up animation"))
        print("  /braise move - " .. T("déplacer le halo", "move the halo"))
        print("  /braise reset - " .. T("réglages par défaut", "default settings"))
    else
        B.Options:Toggle()
    end
end

function Braise_OnAddonCompartmentClick()
    B.Options:Toggle()
end
