-- =====================================================================
-- Braise / Fx.lua -- ambience
--
--   * embers     a pool of particles rising around the character: few,
--                slow and gold when idle; many, fast and hot in combat
--   * vignette   screen edges warm up in combat, and beat red when
--                health runs low (alpha comes from a C-side curve, so it
--                works on secret health)
--   * pulses     shockwave + two blades on combat start, a contracting
--                wave on combat end
--   * level-up   rays, double shockwave, big number, ember fountain
--
-- Every looping effect is an AnimationGroup (runs client-side, no Lua per
-- frame); one-shot eases go through B.Tween.
-- =====================================================================

local _, B = ...
local Fx = B.Module("Fx")
local T = B.T

local random, floor = math.random, math.floor
local MEDIA = B.MEDIA

-- ---------------------------------------------------------------------
-- Low-health colour, evaluated client-side
-- ---------------------------------------------------------------------
local DR, DG, DB = 0.90, 0.08, 0.04
local dangerCurve

--- r, g, b, a of the low-health warning. May be secret: only ever pass
--- the result straight to SetVertexColor.
function B.DangerRGBA()
    if UnitHealthPercent and C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor then
        if not dangerCurve then
            dangerCurve = C_CurveUtil.CreateColorCurve()
            dangerCurve:AddPoint(0.00, CreateColor(DR, DG, DB, 1))
            dangerCurve:AddPoint(0.18, CreateColor(DR, DG, DB, 0.9))
            -- Fades to black as well as to transparent: every texture
            -- using it is additive, so it vanishes even if alpha is ignored.
            dangerCurve:AddPoint(0.38, CreateColor(0, 0, 0, 0))
            dangerCurve:AddPoint(1.00, CreateColor(0, 0, 0, 0))
        end
        local ok, col = pcall(UnitHealthPercent, "player", true, dangerCurve)
        if ok and col and col.GetRGBA then return col:GetRGBA() end
    end
    local cur, mx = B.Num(UnitHealth("player")), B.Num(UnitHealthMax("player"))
    if cur and mx and mx > 0 then
        local p = cur / mx
        local a = p < 0.38 and math.min(1, (0.38 - p) / 0.2) or 0
        return DR * a, DG * a, DB * a, a
    end
    return 0, 0, 0, 0
end

-- ---------------------------------------------------------------------
-- Vignette
-- ---------------------------------------------------------------------
local heat, danger, dangerPulse
local heatTex, dangerTex = {}, {}

-- Edge.tga is opaque on its left side and fades to the right; the four
-- screen edges are that one texture mirrored or turned a quarter.
local function EdgeSet(parent, list, blend)
    local coords = {
        LEFT   = { 0, 0, 0, 1, 1, 0, 1, 1 },
        RIGHT  = { 1, 0, 1, 1, 0, 0, 0, 1 },
        TOP    = { 0, 0, 1, 0, 0, 1, 1, 1 },
        BOTTOM = { 1, 0, 0, 0, 1, 1, 0, 1 },
    }
    for side, c in pairs(coords) do
        local t = parent:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(MEDIA .. "Edge")
        t:SetTexCoord(unpack(c))
        t:SetBlendMode(blend)
        t.side = side
        list[#list + 1] = t
    end
end

local function LayoutEdges(list, wRatio, hRatio)
    local w, h = UIParent:GetWidth() * wRatio, UIParent:GetHeight() * hRatio
    for _, t in ipairs(list) do
        t:ClearAllPoints()
        if t.side == "LEFT" then
            t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT"); t:SetWidth(w)
        elseif t.side == "RIGHT" then
            t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT"); t:SetWidth(w)
        elseif t.side == "TOP" then
            t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(h)
        else
            t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT"); t:SetHeight(h)
        end
    end
end

local function BuildVignette()
    heat = CreateFrame("Frame", nil, UIParent)
    heat:SetAllPoints(UIParent)
    heat:SetFrameStrata("BACKGROUND")
    heat:SetAlpha(0)
    heat:Hide()
    EdgeSet(heat, heatTex, "ADD")

    danger = CreateFrame("Frame", nil, UIParent)
    danger:SetAllPoints(UIParent)
    danger:SetFrameStrata("BACKGROUND")
    danger:SetAlpha(0)
    danger:Hide()
    dangerPulse = CreateFrame("Frame", nil, danger)
    dangerPulse:SetAllPoints(danger)
    EdgeSet(dangerPulse, dangerTex, "ADD")

    -- Heartbeat: quick rise, slow fall, short rest.
    local ag = dangerPulse:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local up = ag:CreateAnimation("Alpha")
    up:SetFromAlpha(0.5); up:SetToAlpha(1); up:SetDuration(0.16); up:SetOrder(1)
    local down = ag:CreateAnimation("Alpha")
    down:SetFromAlpha(1); down:SetToAlpha(0.5); down:SetDuration(0.55); down:SetOrder(2)
    down:SetSmoothing("OUT"); down:SetEndDelay(0.25)
    danger.beat = ag
end

local function UpdateDanger()
    if not danger or not danger:IsShown() then return end
    local r, g, b, a = B.DangerRGBA()
    for _, t in ipairs(dangerTex) do t:SetVertexColor(r, g, b, a) end
end

local function SetDangerActive(on)
    if on then
        UpdateDanger()
        if not danger.beat:IsPlaying() then danger.beat:Play() end
        B.Fade(danger, 1, 0.4)
        UpdateDanger()
    else
        B.Tween(danger, 0.8, danger:GetAlpha(), 0, function(a) danger:SetAlpha(a) end, nil, function()
            danger.beat:Stop()
            danger:Hide()
        end)
    end
end

-- ---------------------------------------------------------------------
-- Embers
-- ---------------------------------------------------------------------
local POOL = 24
local holder
local embers = {}

local PLAIN = { speed = 1, drift = 1, rise = 1, size = 1 }
local classFx

local function Launch(e, burst)
    local hot = burst or B.inCombat
    local fx = B.db.classEmbers and classFx or PLAIN     -- motion only; colours follow the theme
    local r, g, b = B.Color(hot)
    local w = random() * 0.4
    local peak = hot and (0.65 + random() * 0.35) or (0.3 + random() * 0.3)
    e.tex:SetVertexColor(B.Lerp(r, 1, w), B.Lerp(g, 1, w), B.Lerp(b, 1, w), peak)

    local size = (hot and random(4, 9) or random(3, 6)) * fx.size
    e.tex:SetSize(size, size)
    e.tex:ClearAllPoints()
    e.tex:SetPoint("CENTER", holder, "CENTER", random(-150, 150), random(-150, -50))

    local dur   = (hot and (0.9 + random() * 1.0) or (2.8 + random() * 2.6)) / fx.speed
    local delay = burst and random() * 0.3 or random() * (hot and 0.7 or 2.4)
    local dx    = random(-28, 28) * fx.drift
    local dy    = (hot and random(110, 230) or random(45, 105)) * fx.rise

    -- Two legs: fade in over the first quarter of the climb, out over the rest.
    e.moveA:SetOffset(dx * 0.25, dy * 0.25); e.moveA:SetDuration(dur * 0.25); e.moveA:SetStartDelay(delay)
    e.fadeA:SetDuration(dur * 0.25);         e.fadeA:SetStartDelay(delay)
    e.moveB:SetOffset(dx * 0.75, dy * 0.75); e.moveB:SetDuration(dur * 0.75)
    e.fadeB:SetDuration(dur * 0.75)

    e.ag:Stop()
    e.ag:Play()
end

local function BuildEmbers()
    holder = CreateFrame("Frame", nil, B.anchor)
    holder:SetSize(2, 2)
    holder:SetPoint("CENTER")
    for i = 1, POOL do
        local e = {}
        e.tex = holder:CreateTexture(nil, "ARTWORK")
        e.tex:SetTexture(MEDIA .. "Ember")
        e.tex:SetBlendMode("ADD")
        e.tex:SetAlpha(0)
        e.ag = e.tex:CreateAnimationGroup()
        e.moveA = e.ag:CreateAnimation("Translation"); e.moveA:SetOrder(1)
        e.fadeA = e.ag:CreateAnimation("Alpha");       e.fadeA:SetOrder(1)
        e.fadeA:SetFromAlpha(0); e.fadeA:SetToAlpha(1)
        e.moveB = e.ag:CreateAnimation("Translation"); e.moveB:SetOrder(2)
        e.fadeB = e.ag:CreateAnimation("Alpha");       e.fadeB:SetOrder(2)
        e.fadeB:SetFromAlpha(1); e.fadeB:SetToAlpha(0)
        e.ag:SetScript("OnFinished", function()
            if e.live then Launch(e) end
        end)
        embers[i] = e
    end
end

local function UpdateEmbers()
    local db = B.db
    local count = 0
    if db.embers and not B.Flag(UnitIsDeadOrGhost("player")) then
        count = floor((B.inCombat and 18 or 7) * (db.emberAmount or 1) + 0.5)
        count = math.min(POOL, count)
    end
    for i, e in ipairs(embers) do
        e.live = i <= count
        if e.live and not e.ag:IsPlaying() then Launch(e) end
    end
end

local function Burst(n)
    if not B.db.embers then return end
    for i = 1, math.min(POOL, n) do Launch(embers[i], true) end
end

-- ---------------------------------------------------------------------
-- Pulses (shockwave, blades)
-- ---------------------------------------------------------------------
local fx
local shock, calm, bladeL, bladeR

local function MakePulse(parent, file, size)
    local p = {}
    p.tex = parent:CreateTexture(nil, "ARTWORK")
    p.tex:SetTexture(MEDIA .. file)
    p.tex:SetBlendMode("ADD")
    p.tex:SetSize(size, size)
    p.tex:SetPoint("CENTER")
    p.tex:SetAlpha(0)
    p.ag = p.tex:CreateAnimationGroup()
    p.scale = p.ag:CreateAnimation("Scale")
    p.alpha = p.ag:CreateAnimation("Alpha")
    return p
end

local function PlayPulse(p, s0, s1, a0, dur, smoothing, r, g, b, delay)
    p.tex:SetVertexColor(r, g, b)
    p.scale:SetScaleFrom(s0, s0); p.scale:SetScaleTo(s1, s1)
    p.scale:SetDuration(dur); p.scale:SetSmoothing(smoothing); p.scale:SetStartDelay(delay or 0)
    p.alpha:SetFromAlpha(a0); p.alpha:SetToAlpha(0)
    p.alpha:SetDuration(dur); p.alpha:SetSmoothing("IN"); p.alpha:SetStartDelay(delay or 0)
    p.ag:Stop()
    p.ag:Play()
end

local function MakeBlade(dir)
    local b = {}
    b.tex = fx:CreateTexture(nil, "OVERLAY")
    b.tex:SetTexture(MEDIA .. "Blade")
    b.tex:SetBlendMode("ADD")
    b.tex:SetSize(300, 10)
    b.tex:SetPoint("CENTER", fx, "CENTER", dir * 110, 0)
    b.tex:SetAlpha(0)
    b.ag = b.tex:CreateAnimationGroup()
    local mv = b.ag:CreateAnimation("Translation")
    mv:SetOffset(dir * 190, 0); mv:SetDuration(0.5); mv:SetSmoothing("OUT")
    local al = b.ag:CreateAnimation("Alpha")
    al:SetFromAlpha(1); al:SetToAlpha(0); al:SetDuration(0.5); al:SetSmoothing("IN")
    return b
end

local function BuildPulses()
    fx = CreateFrame("Frame", nil, B.anchor)
    fx:SetSize(2, 2)
    fx:SetPoint("CENTER")
    fx:SetFrameStrata("MEDIUM")
    shock  = MakePulse(fx, "Wave", 360)
    calm   = MakePulse(fx, "Wave", 360)
    bladeL = MakeBlade(-1)
    bladeR = MakeBlade(1)
end

-- ---------------------------------------------------------------------
-- Level-up
-- ---------------------------------------------------------------------
local lv

local function BuildLevelUp()
    lv = CreateFrame("Frame", nil, UIParent)
    lv:SetSize(2, 2)
    lv:SetPoint("CENTER", UIParent, "CENTER", 0, 170)
    lv:SetFrameStrata("HIGH")
    lv:SetAlpha(0)
    lv:Hide()

    lv.glow = lv:CreateTexture(nil, "BACKGROUND")
    lv.glow:SetTexture(MEDIA .. "Glow")
    lv.glow:SetBlendMode("ADD")
    lv.glow:SetSize(320, 320)
    lv.glow:SetPoint("CENTER")
    lv.glow:SetAlpha(0.35)

    lv.rays = lv:CreateTexture(nil, "BORDER")
    lv.rays:SetTexture(MEDIA .. "Rays")
    lv.rays:SetBlendMode("ADD")
    lv.rays:SetSize(440, 440)
    lv.rays:SetPoint("CENTER")
    lv.spin = lv.rays:CreateAnimationGroup()
    lv.spin:SetLooping("REPEAT")
    local rot = lv.spin:CreateAnimation("Rotation")
    rot:SetDegrees(-360); rot:SetDuration(26)

    lv.waveA = MakePulse(lv, "Wave", 380)
    lv.waveB = MakePulse(lv, "Wave", 380)

    -- The number sits in its own frame so it can be scaled.
    lv.box = CreateFrame("Frame", nil, lv)
    lv.box:SetSize(2, 2)
    lv.box:SetPoint("CENTER")
    lv.label = lv.box:CreateFontString(nil, "OVERLAY")
    lv.label:SetFont(B.FONT_BOLD, 13, "")
    lv.label:SetPoint("BOTTOM", lv.box, "CENTER", 0, 30)
    lv.label:SetShadowOffset(1, -1); lv.label:SetShadowColor(0, 0, 0, 0.9)
    lv.label:SetText(T("N I V E A U", "L E V E L"))
    lv.num = lv.box:CreateFontString(nil, "OVERLAY")
    lv.num:SetFont(B.FONT_BOLD, 64, "")
    lv.num:SetPoint("CENTER", lv.box, "CENTER", 0, -6)
    lv.num:SetShadowOffset(2, -2); lv.num:SetShadowColor(0, 0, 0, 0.9)
    lv.num:SetTextColor(0.95, 0.92, 0.86)
end

function Fx:LevelUp(level)
    if not lv then return end
    local r, g, b = B.Color(false)
    lv.rays:SetVertexColor(r, g, b)
    lv.glow:SetVertexColor(r, g, b)
    lv.label:SetTextColor(r, g, b)
    lv.num:SetText(level or "")

    lv.gen = (lv.gen or 0) + 1
    local gen = lv.gen
    lv:Show()
    lv.spin:Play()
    B.Tween(lv, 0.3, lv:GetAlpha(), 1, function(a) lv:SetAlpha(a) end)
    B.Tween(lv.box, 0.55, 0.35, 1, function(s) lv.box:SetScale(s) end, B.Ease.outBack)
    PlayPulse(lv.waveA, 0.2, 1.5, 0.9, 0.8, "OUT", r, g, b)
    PlayPulse(lv.waveB, 0.2, 1.9, 0.6, 1.1, "OUT", 1, 1, 1, 0.18)
    Burst(POOL)

    C_Timer.After(3.0, function()
        if lv.gen ~= gen then return end
        B.Tween(lv, 0.9, lv:GetAlpha(), 0, function(a) lv:SetAlpha(a) end, B.Ease.inCubic, function()
            if lv.gen ~= gen then return end
            lv.spin:Stop()
            lv:Hide()
        end)
    end)
end

-- ---------------------------------------------------------------------
-- Module hooks
-- ---------------------------------------------------------------------
function Fx:Init()
    local _, class = UnitClass("player")
    classFx = B.CLASS_FX[class] or PLAIN
    BuildVignette()
    BuildEmbers()
    BuildPulses()
    BuildLevelUp()

    local ev = CreateFrame("Frame")
    ev:RegisterUnitEvent("UNIT_HEALTH", "player")
    ev:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    ev:SetScript("OnEvent", UpdateDanger)
end

function Fx:Refresh()
    local db = B.db
    LayoutEdges(heatTex, 0.16, 0.20)
    LayoutEdges(dangerTex, 0.24, 0.30)
    local r, g, b = B.Color(true)
    for _, t in ipairs(heatTex) do t:SetVertexColor(r, g, b) end

    local dead = B.Flag(UnitIsDeadOrGhost("player"))
    if db.vignette and B.inCombat and not dead then
        B.Fade(heat, 0.16, 0.5)
        SetDangerActive(true)
    else
        B.Fade(heat, 0, 0.5)
        if danger:IsShown() then SetDangerActive(false) end
    end
    UpdateEmbers()
end

function Fx:CombatStart()
    local db = B.db
    local r, g, b = B.Color(true)
    if db.transitions then
        PlayPulse(shock, 0.3, 1.45, 0.85, 0.6, "OUT", r, g, b)
        bladeL.tex:SetVertexColor(r, g, b); bladeL.ag:Stop(); bladeL.ag:Play()
        bladeR.tex:SetVertexColor(r, g, b); bladeR.ag:Stop(); bladeR.ag:Play()
        Burst(14)
    end
    if db.vignette then
        for _, t in ipairs(heatTex) do t:SetVertexColor(r, g, b) end
        heat:Show()
        -- Flash, then settle to a low steady glow.
        B.Tween(heat, 0.18, heat:GetAlpha(), 0.5, function(a) heat:SetAlpha(a) end, B.Ease.outCubic, function()
            if B.inCombat then B.Fade(heat, 0.16, 0.9, B.Ease.inOut) end
        end)
        SetDangerActive(true)
    end
    UpdateEmbers()
end

function Fx:CombatEnd()
    local db = B.db
    if db.transitions then
        local r, g, b = B.Color(false)
        PlayPulse(calm, 1.35, 0.45, 0.5, 0.9, "IN_OUT", r, g, b)
    end
    B.Fade(heat, 0, 1.2, B.Ease.inOut)
    if danger:IsShown() then SetDangerActive(false) end
    UpdateEmbers()
end
