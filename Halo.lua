-- =====================================================================
-- Braise / Halo.lua -- the halo around the character
--
--        health  (           )  power
--                 '  rings  '
--                    0:42
--
--   * two arcs: health on the left, power on the right. Each is a
--     vertical StatusBar wearing an arc texture, so the client crops the
--     arc itself and secret values never pass through Lua arithmetic.
--   * two rings turning in opposite directions; slow when idle, fast in
--     combat.
--   * idle: the halo dims to the chosen opacity and breathes. It wakes up
--     on its own when you target an enemy or are missing health.
--   * combat start: arcs snap in, flash, rings pop. Combat end: everything
--     eases back, and a recap card slides in (duration, XP, fights left
--     to the next level).
-- =====================================================================

local _, B = ...
local Halo = B.Module("Halo")
local T = B.T
local MEDIA = B.MEDIA

-- Geometry, in screen units. The arc textures are a slice of a circle of
-- radius 190 whose centre sits 195.5 from the texture's outer edge.
local ARC_W, ARC_H, ARC_CENTER = 64, 256, 195.5
local DASH_SIZE, TRI_SIZE = 272, 276

local TARGET_K = 1.17          -- the target arc is the same slice, one ring further out
local PET_K = 0.83             -- and the pet's one ring further in, so a little thinner

local INTERP = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local ScaleTo100 = CurveConstants and CurveConstants.ScaleTo100

local root, breath, rings, texts
local arcL, arcR, tgt, pet, tot
local hpText, pwText, timerText, ticker
local card, mover

-- ---------------------------------------------------------------------
-- Building blocks
-- ---------------------------------------------------------------------
local function MakeArc(side, parent, k)
    local a = {}
    k = k or 1
    local file = side < 0 and "ArcL" or "ArcR"
    a.side = side

    a.frame = CreateFrame("Frame", nil, parent)
    a.frame:SetSize(ARC_W * k, ARC_H * k)

    a.bg = a.frame:CreateTexture(nil, "BACKGROUND")
    a.bg:SetTexture(MEDIA .. file)
    a.bg:SetAllPoints()
    a.bg:SetVertexColor(0.5, 0.5, 0.5, 0.40) -- mid-grey track: reads on dark and bright scenes alike

    a.bar = CreateFrame("StatusBar", nil, a.frame)
    a.bar:SetAllPoints()
    a.bar:SetOrientation("VERTICAL")
    a.bar:SetStatusBarTexture(MEDIA .. file)
    a.bar:SetMinMaxValues(0, 1)
    a.bar:SetValue(1)

    -- Additive glows: one flashes on combat start, one carries the
    -- low-health warning (left arc only).
    a.flash = a.frame:CreateTexture(nil, "OVERLAY")
    a.flash:SetTexture(MEDIA .. (side < 0 and "ArcGlowL" or "ArcGlowR"))
    a.flash:SetAllPoints()
    a.flash:SetBlendMode("ADD")
    a.flash:SetAlpha(0)

    function a.SetOffset(off)
        a.frame:ClearAllPoints()
        if side < 0 then
            a.frame:SetPoint("LEFT", parent, "CENTER", -ARC_CENTER * k - off, 0)
        else
            a.frame:SetPoint("RIGHT", parent, "CENTER", ARC_CENTER * k + off, 0)
        end
    end
    a.SetOffset(0)
    return a
end

local function SetBar(bar, value)
    if INTERP then bar:SetValue(value, INTERP) else bar:SetValue(value) end
end

local function MakeRing(file, size, degrees)
    local r = {}
    r.tex = rings:CreateTexture(nil, "ARTWORK")
    r.tex:SetTexture(MEDIA .. file)
    r.tex:SetBlendMode("ADD")
    r.tex:SetSize(size, size)
    r.tex:SetPoint("CENTER")
    r.ag = r.tex:CreateAnimationGroup()
    r.ag:SetLooping("REPEAT")
    r.rot = r.ag:CreateAnimation("Rotation")
    r.rot:SetDegrees(degrees)
    r.rot:SetDuration(60)
    return r
end

local function Text(parent, size, bold)   -- shared with Signs.lua as B.Text
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(bold and B.FONT_BOLD or B.FONT, size, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetTextColor(0.95, 0.92, 0.86)
    return fs
end

B.Text = Text

-- ---------------------------------------------------------------------
-- Health and power
-- ---------------------------------------------------------------------
local HP_STOPS = {
    { 0.00, 1.00, 0.20, 0.16 },
    { 0.30, 1.00, 0.48, 0.18 },
    { 0.60, 0.96, 0.84, 0.36 },
    { 1.00, 0.50, 0.90, 0.52 },
}
local hpCurve

local function HealthColor(unit)
    unit = unit or "player"
    if UnitHealthPercent and C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor then
        if not hpCurve then
            hpCurve = C_CurveUtil.CreateColorCurve()
            for _, s in ipairs(HP_STOPS) do hpCurve:AddPoint(s[1], CreateColor(s[2], s[3], s[4], 1)) end
        end
        local ok, col = pcall(UnitHealthPercent, unit, true, hpCurve)
        if ok and col and col.GetRGBA then return col:GetRGBA() end
    end
    local cur, mx = B.Num(UnitHealth(unit)), B.Num(UnitHealthMax(unit))
    if cur and mx and mx > 0 then
        local p = math.max(0, math.min(1, cur / mx))
        for i = 2, #HP_STOPS do
            local a, b = HP_STOPS[i - 1], HP_STOPS[i]
            if p <= b[1] then
                local k = (p - a[1]) / (b[1] - a[1])
                return B.Lerp(a[2], b[2], k), B.Lerp(a[3], b[3], k), B.Lerp(a[4], b[4], k), 1
            end
        end
    end
    local s = HP_STOPS[#HP_STOPS]
    return s[2], s[3], s[4], 1
end

local function WriteHealthPct()
    hpText:SetFormattedText("%d%%", UnitHealthPercent("player", true, ScaleTo100))
end

local function WritePowerPct(pt)
    pwText:SetFormattedText("%d%%", UnitPowerPercent("player", pt, false, ScaleTo100))
end

local function UpdateHealth()
    if not arcL then return end
    local cur, mx = UnitHealth("player"), UnitHealthMax("player")
    arcL.bar:SetMinMaxValues(0, mx)
    SetBar(arcL.bar, cur)
    arcL.bar:SetStatusBarColor(HealthColor())
    arcL.danger:SetVertexColor(B.DangerRGBA())

    if B.db.texts then
        if UnitHealthPercent then
            -- The percentage may be secret: it goes straight to the widget.
            if not pcall(WriteHealthPct) then hpText:SetText("") end
        else
            local c, m = B.Num(cur), B.Num(mx)
            if c and m and m > 0 then hpText:SetFormattedText("%d%%", c / m * 100) else hpText:SetText("") end
        end
    end
end

local function PowerRGB(pt, token)
    local c = PowerBarColor and (PowerBarColor[token] or PowerBarColor[pt])
    -- Blizzard's mana blue is too dark for a thin arc.
    if pt == 0 or not (c and c.r) then return 0.30, 0.62, 1.00 end
    return c.r, c.g, c.b
end

local function UpdatePower()
    if not arcR then return end
    local pt, token = UnitPowerType("player")
    local cur, mx = UnitPower("player", pt), UnitPowerMax("player", pt)
    arcR.bar:SetMinMaxValues(0, mx)
    SetBar(arcR.bar, cur)

    arcR.bar:SetStatusBarColor(PowerRGB(pt, token))

    if B.db.texts then
        -- Mana reads better as a percentage; everything else as a value.
        if not (pt == 0 and UnitPowerPercent and pcall(WritePowerPct, pt)) then
            pwText:SetFormattedText("%d", cur)
        end
    end
end

-- ---------------------------------------------------------------------
-- Target arc
-- ---------------------------------------------------------------------
local function WriteTargetPct()
    tgt.pct:SetFormattedText("%d%%", UnitHealthPercent("target", true, ScaleTo100))
end

local function WriteTargetPowerPct(pt)
    tgt.pwText:SetFormattedText("%d%%", UnitPowerPercent("target", pt, false, ScaleTo100))
end

local function UpdateTargetPower(instant)
    if not tgt or not tgt.on then return end
    local pt, token = UnitPowerType("target")
    local cur, mx = UnitPower("target", pt), UnitPowerMax("target", pt)
    -- Many creatures have no resource at all: no arc for them.
    local known = B.Num(mx)
    local has = not (known and known <= 0)
    tgt.pw.frame:SetShown(has)
    tgt.pwText:SetShown(has)
    if not has then return end
    tgt.pw.bar:SetMinMaxValues(0, mx)
    if instant then tgt.pw.bar:SetValue(cur) else SetBar(tgt.pw.bar, cur) end
    tgt.pw.bar:SetStatusBarColor(PowerRGB(pt, token))
    if not (pt == 0 and UnitPowerPercent and pcall(WriteTargetPowerPct, pt)) then
        tgt.pwText:SetFormattedText("%d", cur)
    end
end

local function TargetColor(unit)
    unit = unit or "target"
    if B.Flag(UnitIsDead(unit)) then return 0.55, 0.55, 0.55 end
    if B.Flag(UnitIsPlayer(unit)) then
        local _, class = UnitClass(unit)
        local c = class and not B.Secret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then return c.r, c.g, c.b end
    end
    if B.Flag(UnitIsTapDenied(unit)) then return 0.60, 0.60, 0.60 end
    local reaction = B.Num(UnitReaction(unit, "player"))
    if reaction then
        if reaction <= 3 then return 0.95, 0.28, 0.22 end
        if reaction == 4 then return 0.96, 0.82, 0.28 end
        return 0.40, 0.88, 0.48
    end
    if B.Flag(UnitCanAttack("player", unit)) then return 0.95, 0.28, 0.22 end
    return 0.40, 0.88, 0.48
end

-- ---------------------------------------------------------------------
-- Target of target
-- ---------------------------------------------------------------------
-- A name and a hairline health bar above the target's name. When the
-- target turns on you it says so, in the combat colour, with a pop.
local TOT_Y = 221

local function WriteToTName()
    tot.name:SetFormattedText("> %s", UnitName("targettarget"))
end

local function UpdateToT()
    if not tot or not tot.on then return end
    local cur, mx = UnitHealth("targettarget"), UnitHealthMax("targettarget")
    tot.bar:SetMinMaxValues(0, mx)
    tot.bar:SetValue(cur)

    local me = B.Flag(UnitIsUnit("targettarget", "player"))
    local r, g, b
    if me then
        r, g, b = B.Color(true)
        tot.name:SetText("> " .. T("TOI", "YOU"))
    else
        r, g, b = TargetColor("targettarget")
        if not pcall(WriteToTName) then tot.name:SetText("") end
    end
    tot.name:SetTextColor(r, g, b)
    tot.bar:SetStatusBarColor(r, g, b)

    if me and not tot.me then
        B.Tween("tot.pop", 0.45, 1.5, 1, tot.Place, B.Ease.outBack)
    end
    tot.me = me
end

--- Called when the target, or the target's target, changes.
local function ToTChanged()
    if not tot then return end
    local want = B.db.tot and B.Flag(UnitExists("targettarget"))
    if want then
        if not tot.on then
            tot.on = true
            tot.me = nil
            B.Fade(tot, 1, 0.25)
        end
        UpdateToT()
    elseif tot.on then
        tot.on = false
        B.Fade(tot, 0, 0.25)
    end
end

local function BuildToT()
    tot = CreateFrame("Frame", nil, root)
    tot:SetSize(120, 20)
    tot:SetAlpha(0)
    tot:Hide()
    -- Scaling a frame scales its anchor offsets too: divide them back.
    function tot.Place(s)
        tot:SetScale(s)
        tot:ClearAllPoints()
        tot:SetPoint("CENTER", root, "CENTER", 0, TOT_Y / s)
    end
    tot.Place(1)

    tot.name = Text(tot, 10, true)
    tot.name:SetPoint("TOP")
    tot.name:SetWidth(200)
    tot.name:SetWordWrap(false)

    local track = tot:CreateTexture(nil, "BACKGROUND")
    track:SetTexture(B.WHITE)
    track:SetVertexColor(0.5, 0.5, 0.5, 0.40)
    track:SetSize(90, 3)
    track:SetPoint("BOTTOM")
    tot.bar = CreateFrame("StatusBar", nil, tot)
    tot.bar:SetStatusBarTexture(B.WHITE)
    tot.bar:SetAllPoints(track)
    tot.bar:SetMinMaxValues(0, 1)
    tot.bar:SetValue(1)

    -- No event reports the health of "targettarget": poll while shown.
    tot:SetScript("OnUpdate", function(self, dt)
        self.acc = (self.acc or 0) + dt
        if self.acc < 0.2 then return end
        self.acc = 0
        if tot.on then ToTChanged() end
    end)
end

local function UpdateTarget(instant)
    if not tgt or not tgt.on then return end
    local cur, mx = UnitHealth("target"), UnitHealthMax("target")
    tgt.hp.bar:SetMinMaxValues(0, mx)
    -- A new target must not ease in from the previous target's health.
    if instant then tgt.hp.bar:SetValue(cur) else SetBar(tgt.hp.bar, cur) end
    local r, g, b = TargetColor()
    tgt.hp.bar:SetStatusBarColor(r, g, b)
    tgt.name:SetTextColor(r, g, b)

    if UnitHealthPercent then
        if not pcall(WriteTargetPct) then tgt.pct:SetText("") end
    else
        local c, m = B.Num(cur), B.Num(mx)
        if c and m and m > 0 then tgt.pct:SetFormattedText("%d%%", c / m * 100) else tgt.pct:SetText("") end
    end
end

--- Called when the target changes or the option is toggled.
local function TargetChanged(flash)
    if not tgt then return end
    local want = B.db.target and B.Flag(UnitExists("target"))
    if want then
        tgt.name:SetText(UnitName("target") or "")
        local r, g, b = TargetColor()
        tgt.hp.flash:SetVertexColor(r, g, b)
        tgt.pw.flash:SetVertexColor(r, g, b)
        if not tgt.on then
            -- Acquired: both arcs slide in from outside.
            tgt.on = true
            B.Fade(tgt, 1, 0.3)
            B.Tween("tgt.in", 0.45, 34, 0, tgt.SetOffset, B.Ease.outBack)
        end
        UpdateTarget(true)
        UpdateTargetPower(true)
        if flash then
            B.Tween("tgt.flash", 0.7, 0.9, 0, function(a)
                tgt.hp.flash:SetAlpha(a)
                tgt.pw.flash:SetAlpha(a)
            end)
        end
    elseif tgt.on then
        tgt.on = false
        B.Fade(tgt, 0, 0.3)
        B.Tween("tgt.in", 0.3, 0, 22, tgt.SetOffset, B.Ease.inCubic)
    end
end

local function BuildTarget()
    tgt = CreateFrame("Frame", nil, root)
    tgt:SetSize(2, 2)
    tgt:SetPoint("CENTER")
    tgt:SetAlpha(0)
    tgt:Hide()
    -- Same sides as the player's arcs: health left, power right.
    tgt.hp = MakeArc(-1, tgt, TARGET_K)
    tgt.pw = MakeArc(1, tgt, TARGET_K)
    function tgt.SetOffset(off)
        tgt.hp.SetOffset(off)
        tgt.pw.SetOffset(off)
    end

    -- Name centred above the halo; values at the upper ends of the arcs,
    -- mirroring the player's values at the lower ends.
    tgt.name = Text(tgt, 12, true)
    tgt.name:SetPoint("BOTTOM", tgt, "CENTER", 0, 194)             -- above the threat gauge
    tgt.name:SetWidth(240)
    tgt.name:SetJustifyH("CENTER")
    tgt.name:SetWordWrap(false)
    tgt.pct = Text(tgt, 11, true)
    tgt.pct:SetPoint("CENTER", tgt, "CENTER", -180, 166)
    tgt.pct:SetTextColor(0.80, 0.77, 0.72)
    tgt.pwText = Text(tgt, 11, true)
    tgt.pwText:SetPoint("CENTER", tgt, "CENTER", 180, 166)
    tgt.pwText:SetTextColor(0.80, 0.77, 0.72)
end

-- ---------------------------------------------------------------------
-- Pet arcs
-- ---------------------------------------------------------------------
local function UpdatePet(instant)
    if not pet or not pet.on then return end
    local cur, mx = UnitHealth("pet"), UnitHealthMax("pet")
    pet.hp.bar:SetMinMaxValues(0, mx)
    if instant then pet.hp.bar:SetValue(cur) else SetBar(pet.hp.bar, cur) end
    if B.Flag(UnitIsDead("pet")) then
        pet.hp.bar:SetStatusBarColor(0.55, 0.55, 0.55)
    else
        pet.hp.bar:SetStatusBarColor(HealthColor("pet"))
    end

    local pt, token = UnitPowerType("pet")
    local pcur, pmax = UnitPower("pet", pt), UnitPowerMax("pet", pt)
    pet.pw.bar:SetMinMaxValues(0, pmax)
    if instant then pet.pw.bar:SetValue(pcur) else SetBar(pet.pw.bar, pcur) end
    pet.pw.bar:SetStatusBarColor(PowerRGB(pt, token))
end

--- Called when the pet appears, changes or leaves, or the option is toggled.
local function PetChanged()
    if not pet then return end
    local want = B.db.pet and B.Flag(UnitExists("pet"))
    if want then
        if not pet.on then
            -- Summoned: the arcs open outward from the centre.
            pet.on = true
            B.Fade(pet, 1, 0.3)
            B.Tween("pet.in", 0.45, -26, 0, pet.SetOffset, B.Ease.outBack)
        end
        UpdatePet(true)
    elseif pet.on then
        pet.on = false
        B.Fade(pet, 0, 0.3)
        B.Tween("pet.in", 0.3, 0, -18, pet.SetOffset, B.Ease.inCubic)
    end
end

local function BuildPet()
    pet = CreateFrame("Frame", nil, root)
    pet:SetSize(2, 2)
    pet:SetPoint("CENTER")
    pet:SetAlpha(0)
    pet:Hide()
    pet.hp = MakeArc(-1, pet, PET_K)
    pet.pw = MakeArc(1, pet, PET_K)
    function pet.SetOffset(off)
        pet.hp.SetOffset(off)
        pet.pw.SetOffset(off)
    end
end

-- ---------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------
local function StateAlpha()
    local db = B.db
    if mover and mover:IsShown() then return 1 end
    if B.Flag(UnitIsDeadOrGhost("player")) then return 0.15 end
    if B.inCombat then return 1 end
    local idle = db.oocAlpha or 0.35
    if B.Flag(UnitExists("target")) then return math.max(idle, 0.8) end
    local cur, mx = B.Num(UnitHealth("player")), B.Num(UnitHealthMax("player"))
    if cur and mx and cur < mx then return math.max(idle, 0.6) end
    return idle
end

local function ApplyRings(instant)
    local r, g, b = B.StateColor()
    local hot = B.inCombat
    rings.dash.tex:SetVertexColor(r, g, b)
    rings.tri.tex:SetVertexColor(r, g, b)
    rings.dash.rot:SetDuration(hot and 16 or 80)
    rings.tri.rot:SetDuration(hot and 9 or 46)
    if B.db.ring then
        rings:Show()
        if not rings.dash.ag:IsPlaying() then rings.dash.ag:Play() end
        if not rings.tri.ag:IsPlaying() then rings.tri.ag:Play() end
        B.Fade(rings, hot and 0.6 or 0.22, instant and 0 or 0.6)
    else
        rings.dash.ag:Stop()
        rings.tri.ag:Stop()
        rings:Hide()
    end
end

local function ApplyState(dur)
    local db = B.db
    local dead = B.Flag(UnitIsDeadOrGhost("player"))

    arcL.frame:SetShown(db.halo)
    arcR.frame:SetShown(db.halo)
    texts:SetShown(db.halo and db.texts)
    arcL.bar:GetStatusBarTexture():SetDesaturated(dead)
    arcR.bar:GetStatusBarTexture():SetDesaturated(dead)

    B.Fade(root, StateAlpha(), dur or 0.5, B.Ease.inOut)

    -- Breathe only when truly idle.
    if B.inCombat or dead then
        breath.ag:Stop()
    elseif not breath.ag:IsPlaying() then
        breath.ag:Play()
    end
end

-- ---------------------------------------------------------------------
-- Combat timer
-- ---------------------------------------------------------------------
local function FormatTime(sec)
    sec = math.max(0, math.floor(sec + 0.5))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function StartTimer()
    if not B.db.timer then return end
    timerText:SetText("0:00")
    timerText:SetTextColor(B.Color(true))
    B.Fade(timerText, 1, 0.3)
    ticker.acc = 0
    ticker:Show()
end

local function StopTimer(duration)
    ticker:Hide()
    if timerText:IsShown() then
        timerText:SetText(FormatTime(duration))
        B.Fade(timerText, 0, 1.6, B.Ease.inCubic)
    end
end

-- ---------------------------------------------------------------------
-- Recap card
-- ---------------------------------------------------------------------
local CARD_W, CARD_H, CARD_Y = 300, 58, -276

local function BuildCard()
    card = CreateFrame("Frame", nil, B.anchor)
    card:SetSize(CARD_W, CARD_H)
    card:SetPoint("CENTER", B.anchor, "CENTER", 0, CARD_Y)
    card:SetFrameStrata("MEDIUM")
    card:SetAlpha(0)
    card:Hide()

    local bg = card:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.045, 0.04, 0.88)

    card.line = card:CreateTexture(nil, "ARTWORK")
    card.line:SetTexture(B.WHITE)
    card.line:SetHeight(1)
    card.line:SetPoint("TOP")

    card.title = Text(card, 9, true)
    card.title:SetPoint("TOPLEFT", 12, -10)
    card.title:SetText(T("COMBAT TERMINÉ", "FIGHT OVER"))

    card.time = Text(card, 22, true)
    card.time:SetPoint("TOPLEFT", 11, -22)

    card.xp = Text(card, 14, true)
    card.xp:SetPoint("TOPRIGHT", -12, -12)

    card.sub = Text(card, 10)
    card.sub:SetPoint("TOPRIGHT", -12, -33)
    card.sub:SetWidth(CARD_W - 110)         -- never reaches the duration on the left
    card.sub:SetJustifyH("RIGHT")
    card.sub:SetWordWrap(false)
    card.sub:SetTextColor(0.66, 0.63, 0.58)

    card.track = card:CreateTexture(nil, "ARTWORK")
    card.track:SetTexture(B.WHITE)
    card.track:SetVertexColor(1, 1, 1, 0.08)
    card.track:SetHeight(2)
    card.track:SetPoint("BOTTOMLEFT")
    card.track:SetPoint("BOTTOMRIGHT")

    card.fill = card:CreateTexture(nil, "OVERLAY")
    card.fill:SetTexture(B.WHITE)
    card.fill:SetHeight(2)
    card.fill:SetPoint("BOTTOMLEFT")
end

local function HideCard(dur)
    if not card or not card:IsShown() then return end
    card.gen = (card.gen or 0) + 1
    B.Fade(card, 0, dur or 0.25)
end

function Halo:Recap(data)
    if not B.db.recap or not card or B.inCombat then return end
    if (data.duration or 0) < 3 then return end

    local r, g, b = B.Color(false)
    card.line:SetVertexColor(r, g, b)
    card.title:SetTextColor(r, g, b)
    card.fill:SetVertexColor(r, g, b)
    card.time:SetText(FormatTime(data.duration))

    local xp = data.xp or 0
    local hasBar = data.after ~= nil
    if xp > 0 then
        card.xp:SetText("+" .. (BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or xp) .. " XP")
        if data.leveled then
            card.sub:SetText(T("Niveau gagné !", "Level gained!"))
        elseif data.cur and data.max and data.max > data.cur then
            local n = math.ceil((data.max - data.cur) / xp)
            if n <= 1 then
                card.sub:SetText(T("1 combat avant le niveau", "1 more fight to level"))
            else
                card.sub:SetFormattedText(T("~%d combats avant le niveau", "~%d more fights to level"), n)
            end
        else
            card.sub:SetText("")
        end
    else
        card.xp:SetText("")
        card.sub:SetText(T("aucune expérience", "no experience"))
        hasBar = false
    end
    card.track:SetShown(hasBar)
    card.fill:SetShown(hasBar)

    card.gen = (card.gen or 0) + 1
    local gen = card.gen
    card:Show()
    B.Tween(card, 0.45, card:GetAlpha(), 1, function(a) card:SetAlpha(a) end)
    B.Tween("card.y", 0.45, CARD_Y - 18, CARD_Y, function(y)
        card:ClearAllPoints()
        card:SetPoint("CENTER", B.anchor, "CENTER", 0, y)
    end)
    B.Tween("card.line", 0.6, 1, CARD_W, function(w) card.line:SetWidth(w) end, B.Ease.inOut)
    if hasBar then
        local from = (data.leveled or not data.before) and 0 or data.before
        if xp > 0 and data.max and data.max > 0 and not data.leveled then
            from = math.max(0, data.after - xp / data.max)     -- also right for the demo
        end
        B.Tween("card.fill", 1.1, from, data.after, function(p)
            card.fill:SetWidth(math.max(1, CARD_W * p))
        end, B.Ease.inOut)
    end

    C_Timer.After(5.5, function()
        if card.gen == gen then B.Fade(card, 0, 0.8, B.Ease.inCubic) end
    end)
end

-- ---------------------------------------------------------------------
-- Click zones
-- ---------------------------------------------------------------------
-- The arcs behave like unit frames: left-click targets the unit,
-- right-click opens its menu, hovering shows its tooltip. Each arc is
-- covered by a chain of small secure buttons that follow its curve, so the
-- zones stay as thin as the arcs and the world remains clickable between
-- them. Secure frames cannot be shown or hidden in combat: the target's
-- zones are driven by the client (RegisterUnitWatch), and option changes
-- made during a fight are applied when it ends.
local CLICK_SEGMENTS, CLICK_PAD = 6, 5
local clicks = { player = {}, target = {}, pet = {}, targettarget = {} }

local function MakeClick(unit, level)
    local btn = CreateFrame("Button", nil, B.anchor, "SecureUnitButtonTemplate")
    btn:SetAttribute("unit", unit)
    btn:SetAttribute("*type1", "target")
    btn:SetAttribute("*type2", "togglemenu")
    btn:RegisterForClicks("AnyUp")
    btn:SetFrameLevel(B.anchor:GetFrameLevel() + level)
    btn:SetScript("OnEnter", function()
        if GameTooltip_SetDefaultAnchor then
            GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
            GameTooltip:SetUnit(unit)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    table.insert(clicks[unit], btn)
    return btn
end

--- Cover one side arc of the given radius with buttons.
local function ClickArc(unit, side, radius, level)
    local half = math.deg(math.asin((ARC_H / 2 - 6) / 190))     -- half-angle of the slice
    local step = half * 2 / CLICK_SEGMENTS
    for i = 1, CLICK_SEGMENTS do
        local a0 = math.rad(-half + (i - 1) * step)
        local a1 = math.rad(-half + i * step)
        local x0, x1 = radius * math.cos(a0), radius * math.cos(a1)
        local y0, y1 = radius * math.sin(a0), radius * math.sin(a1)
        local xmin, xmax = math.min(x0, x1) - CLICK_PAD, math.max(x0, x1, i == CLICK_SEGMENTS / 2 and radius or 0) + CLICK_PAD
        local btn = MakeClick(unit, level)
        btn:SetSize(xmax - xmin, math.abs(y1 - y0))
        if side < 0 then
            btn:SetPoint("BOTTOMRIGHT", B.anchor, "CENTER", -xmin, math.min(y0, y1))
        else
            btn:SetPoint("BOTTOMLEFT", B.anchor, "CENTER", xmin, math.min(y0, y1))
        end
    end
end

local function BuildClicks()
    if clicks.built then return end
    clicks.built = true
    ClickArc("player", -1, 190, 2)
    ClickArc("player", 1, 190, 2)
    -- The target's zones sit above the player's where the two overlap.
    ClickArc("target", -1, 190 * TARGET_K, 4)
    ClickArc("target", 1, 190 * TARGET_K, 4)
    ClickArc("pet", -1, 190 * PET_K, 3)
    ClickArc("pet", 1, 190 * PET_K, 3)
    local name = MakeClick("target", 4)
    name:SetSize(200, 18)
    name:SetPoint("BOTTOM", B.anchor, "CENTER", 0, 192)
    local totName = MakeClick("targettarget", 4)
    totName:SetSize(140, 20)
    totName:SetPoint("CENTER", B.anchor, "CENTER", 0, TOT_Y)
end

function Halo:ApplyClicks()
    if not clicks.built or InCombatLockdown() then return end
    local db = B.db
    local on = db.click and not (mover and mover:IsShown())
    for _, btn in ipairs(clicks.player) do
        btn:SetShown(on and db.halo)
    end
    for unit, key in pairs({ target = "target", pet = "pet", targettarget = "tot" }) do
        for _, btn in ipairs(clicks[unit]) do
            if on and db[key] then
                RegisterUnitWatch(btn)      -- shown only while the unit exists
            else
                UnregisterUnitWatch(btn)
                btn:Hide()
            end
        end
    end
end

-- ---------------------------------------------------------------------
-- Mover
-- ---------------------------------------------------------------------
local function BuildMover()
    mover = CreateFrame("Frame", nil, B.anchor)
    mover:SetSize(430, 300)
    mover:SetPoint("CENTER")
    mover:SetFrameStrata("DIALOG")
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:Hide()

    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.79, 0.64, 0.32, 0.10)
    for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
                         { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
        local e = mover:CreateTexture(nil, "BORDER")
        e:SetColorTexture(0.79, 0.64, 0.32, 0.7)
        e:SetPoint(p[1]); e:SetPoint(p[2])
        if p[3] then e:SetWidth(p[3]) else e:SetHeight(p[4]) end
    end
    local label = Text(mover, 11, true)
    label:SetPoint("TOP", 0, -10)
    label:SetText(T("Glisser pour déplacer - clic droit pour verrouiller",
                    "Drag to move - right-click to lock"))

    mover:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        B.anchor:SetMovable(true)
        B.anchor:StartMoving()
    end)
    mover:SetScript("OnDragStop", function()
        B.anchor:StopMovingOrSizing()
        local ax, ay = B.anchor:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if ax and ux then
            local sa, su = B.anchor:GetEffectiveScale(), UIParent:GetEffectiveScale()
            B.db.x = math.floor((ax * sa - ux * su) / su + 0.5)
            B.db.y = math.floor((ay * sa - uy * su) / su + 0.5)
        end
        B.ApplyAnchor()
        B.Call("Refresh")
    end)
    mover:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Halo:ToggleMover() end
    end)
end

function Halo:ToggleMover()
    if InCombatLockdown() then
        B.Print(T("le halo ne peut pas être déplacé en combat.", "the halo cannot be moved in combat."))
        return
    end
    if not mover then BuildMover() end
    mover:SetShown(not mover:IsShown())
    Halo:ApplyClicks()
    ApplyState(0.3)
end

-- ---------------------------------------------------------------------
-- Module hooks
-- ---------------------------------------------------------------------
function Halo:Init()
    root = CreateFrame("Frame", nil, B.anchor)
    root:SetSize(2, 2)
    root:SetPoint("CENTER")
    root:SetAlpha(0)
    Halo.root = root

    breath = CreateFrame("Frame", nil, root)
    breath:SetSize(2, 2)
    breath:SetPoint("CENTER")
    breath.ag = breath:CreateAnimationGroup()
    breath.ag:SetLooping("BOUNCE")
    local al = breath.ag:CreateAnimation("Alpha")
    al:SetFromAlpha(1); al:SetToAlpha(0.55); al:SetDuration(2.8); al:SetSmoothing("IN_OUT")

    arcL = MakeArc(-1, breath)
    arcR = MakeArc(1, breath)
    BuildTarget()
    BuildPet()
    BuildToT()
    arcL.danger = arcL.frame:CreateTexture(nil, "OVERLAY")
    arcL.danger:SetTexture(MEDIA .. "ArcGlowL")
    arcL.danger:SetAllPoints()
    arcL.danger:SetBlendMode("ADD")
    arcL.danger:SetVertexColor(1, 0, 0, 0)

    rings = CreateFrame("Frame", nil, root)
    rings:SetSize(2, 2)
    rings:SetPoint("CENTER")
    rings:SetAlpha(0)
    rings.dash = MakeRing("RingDash", DASH_SIZE, -360)
    rings.tri  = MakeRing("RingTri", TRI_SIZE, 360)

    texts = CreateFrame("Frame", nil, root)
    texts:SetSize(2, 2)
    texts:SetPoint("CENTER")
    hpText = Text(texts, 12, true)
    -- Inside the halo, clear of the target arcs' lower ends.
    hpText:SetPoint("CENTER", texts, "CENTER", -122, -138)
    pwText = Text(texts, 12, true)
    pwText:SetPoint("CENTER", texts, "CENTER", 122, -138)

    timerText = Text(root, 11, true)
    timerText:SetPoint("CENTER", root, "CENTER", 0, -195)       -- between the two cast arcs
    timerText:SetAlpha(0)
    timerText:Hide()

    ticker = CreateFrame("Frame")
    ticker:Hide()
    ticker:SetScript("OnUpdate", function(self, dt)
        self.acc = (self.acc or 0) + dt
        if self.acc < 0.2 then return end
        self.acc = 0
        timerText:SetText(FormatTime(GetTime() - (B.combatT0 or GetTime())))
    end)

    BuildCard()
    BuildClicks()
    Halo:ApplyClicks()

    local ev = CreateFrame("Frame")
    ev:RegisterUnitEvent("UNIT_HEALTH", "player", "target")
    ev:RegisterUnitEvent("UNIT_MAXHEALTH", "player", "target")
    ev:RegisterUnitEvent("UNIT_FACTION", "target")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:RegisterUnitEvent("UNIT_TARGET", "target")
    ev:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    ev:RegisterUnitEvent("UNIT_POWER_UPDATE", "target")
    ev:RegisterUnitEvent("UNIT_MAXPOWER", "player", "target")
    ev:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player", "target")
    -- RegisterUnitEvent takes two units at most: the pet gets its own frame.
    local pev = CreateFrame("Frame")
    for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
        pev:RegisterUnitEvent(e, "pet")
    end
    pev:RegisterUnitEvent("UNIT_PET", "player")
    pev:SetScript("OnEvent", function(_, event)
        if event == "UNIT_PET" then PetChanged() else UpdatePet() end
    end)

    ev:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_TARGET" then
            ToTChanged()
        elseif event == "PLAYER_TARGET_CHANGED" then
            TargetChanged(true)
            ToTChanged()
        elseif unit == "target" then
            if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_FACTION" then
                UpdateTarget()
            else
                UpdateTargetPower()
            end
        elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            UpdateHealth()
            -- Missing health wakes the halo up; only worth checking when idle.
            if not B.inCombat then
                local want = StateAlpha()
                if math.abs(want - (root.want or -1)) > 0.01 then
                    root.want = want
                    B.Fade(root, want, 0.5, B.Ease.inOut)
                end
            end
        else
            UpdatePower()
        end
    end)
end

function Halo:Refresh()
    if not root then return end
    Halo:ApplyClicks()
    UpdateHealth()
    UpdatePower()
    TargetChanged()
    UpdateTarget()
    UpdateTargetPower()
    PetChanged()
    ToTChanged()
    ApplyRings()
    ApplyState()
    root.want = StateAlpha()
    if B.inCombat and not ticker:IsShown() then StartTimer() end
    if not B.db.timer then
        ticker:Hide()
        timerText:Hide()
    end
end

function Halo:CombatStart()
    if not root then return end
    HideCard(0.2)
    ApplyState(0.25)
    ApplyRings()
    StartTimer()

    if B.db.transitions then
        local r, g, b = B.Color(true)
        -- Arcs snap in from outside and flash.
        B.Tween("arcs.in", 0.5, 46, 0, function(off)
            arcL.SetOffset(off)
            arcR.SetOffset(off)
        end, B.Ease.outBack)
        arcL.flash:SetVertexColor(r, g, b)
        arcR.flash:SetVertexColor(r, g, b)
        B.Tween("arcs.flash", 0.9, 1, 0, function(a)
            arcL.flash:SetAlpha(a)
            arcR.flash:SetAlpha(a)
        end, B.Ease.outCubic)
        if B.db.ring then
            B.Tween("rings.pop", 0.6, 1.3, 1, function(s) rings:SetScale(s) end, B.Ease.outBack)
        end
    end
end

function Halo:CombatEnd(duration)
    if not root then return end
    StopTimer(duration)
    ApplyRings()
    ApplyState(1.4)
    root.want = StateAlpha()
    if B.db.transitions then
        -- A small exhale: the arcs drift out and settle back.
        B.Tween("arcs.in", 1.2, 0, 1, function(p)
            local off = math.sin(p * math.pi) * 12
            arcL.SetOffset(off)
            arcR.SetOffset(off)
        end, B.Ease.inOut)
    end
end
