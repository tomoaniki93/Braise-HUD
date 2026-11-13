-- =====================================================================
-- Braise / Signs.lua -- the three things the halo tells you besides
-- health and power
--
--   * cast arcs      your cast closes the circle at the bottom; the
--                    target's cast is a second arc just under it. The
--                    client drives the fill from a duration object, so
--                    secret cast times are fine.
--   * threat         a gauge at the top of the halo, in a group or with a
--                    pet: green to red as you climb the target's threat
--                    list, or the other way round in tank mode.
--   * combo points   pips on an arc under the character. Each one pops in;
--                    the row pulses when it is full.
--   * missing buffs  round icons at the top of the ring, out of combat,
--                    for class buffs and weapon enchants you should have.
--                    Display only: nothing here is clickable, the HUD stays
--                    click-through.
-- =====================================================================

local _, B = ...
local Signs = B.Module("Signs")
local T = B.T
local MEDIA = B.MEDIA

local rad, cos, sin = math.rad, math.cos, math.sin

-- =====================================================================
-- CAST ARCS
-- =====================================================================
-- The texture is a 60-degree slice of a circle of radius 180 whose apex
-- sits 5 units inside the frame edge.
local CAST_W, CAST_H, CAST_EDGE = 256, 64, 185

local casts = {}

--- Duration object of the unit's cast (or channel), nil when idle.
local function CastDuration(unit)
    if UnitCastingDuration then
        local d = UnitCastingDuration(unit)
        if d then return d, false end
    end
    if UnitChannelDuration then
        local d = UnitChannelDuration(unit)
        if d then return d, true end
    end
    return nil
end

--- Is the unit casting right now? Works with or without duration objects.
local function IsCasting(unit)
    if UnitCastingDuration or UnitChannelDuration then
        return CastDuration(unit) ~= nil
    end
    return UnitCastingInfo(unit) ~= nil or UnitChannelInfo(unit) ~= nil
end

-- k scales the slice outward (the target's arc is one ring further out);
-- textY is where the spell name goes.
local function MakeCast(unit, k, textY, key, label)
    local c = { unit = unit }

    c.frame = CreateFrame("Frame", nil, B.anchor)
    c.frame:SetSize(CAST_W * k, CAST_H * k)
    c.frame:SetFrameStrata("LOW")
    c.frame:SetAlpha(0)
    c.frame:Hide()

    function c.SetOffset(off)
        c.off = off
        local ox, oy = B.Off(key)
        c.frame:ClearAllPoints()
        c.frame:SetPoint("BOTTOM", B.anchor, "CENTER", ox, -CAST_EDGE * k - off + oy)
        if c.text then
            c.text:ClearAllPoints()
            c.text:SetPoint("CENTER", B.anchor, "CENTER", ox, textY + oy)
        end
    end
    c.SetOffset(0)

    local file = "ArcB"
    c.bg = c.frame:CreateTexture(nil, "BACKGROUND")
    c.bg:SetTexture(MEDIA .. file)
    c.bg:SetAllPoints()
    c.bg:SetVertexColor(0.5, 0.5, 0.5, 0.40)

    c.bar = CreateFrame("StatusBar", nil, c.frame)
    c.bar:SetAllPoints()
    c.bar:SetStatusBarTexture(MEDIA .. file)
    c.bar:SetMinMaxValues(0, 1)
    c.bar:SetValue(0)

    c.flash = c.frame:CreateTexture(nil, "OVERLAY")
    c.flash:SetTexture(MEDIA .. "ArcGlowB")
    c.flash:SetAllPoints()
    c.flash:SetBlendMode("ADD")
    c.flash:SetAlpha(0)

    c.text = B.Text(c.frame, 10, true)
    c.text:SetWidth(170)
    c.text:SetWordWrap(false)
    c.label = label
    c.SetOffset(0)

    -- Handle: a strip along the bottom of the arc, clear of the other one.
    B.Movable(key, label, function(h)
        h:SetSize(CAST_W * k * 0.62, 22)
        h:SetPoint("BOTTOM", c.frame, "BOTTOM")
    end, function() c.SetOffset(c.off or 0) end)

    -- While shown: drive the bar by hand when the client has no timer API,
    -- and notice a cast that ended without a STOP event (dead target,
    -- lost event).
    c.frame:SetScript("OnUpdate", function(self, dt)
        if c.manual and c.active then c.bar:SetValue(GetTime() * 1000) end
        self.acc = (self.acc or 0) + dt
        if self.acc < 0.3 then return end
        self.acc = 0
        if c.active and not IsCasting(unit) then Signs.FinishCast(c, true) end
    end)

    casts[unit] = c
    return c
end

local function HideCast(c)
    c.active = false
    if not Signs.preview then B.Fade(c.frame, 0, 0.15) end
end

local function BeginCast(c)
    local unit, bar = c.unit, c.bar
    local d, channel = CastDuration(unit)

    if d and bar.SetTimerDuration and Enum and Enum.StatusBarTimerDirection then
        -- A timer still running from the previous cast must be released first.
        if c.timer and bar.ResetTimer then bar:ResetTimer() end
        local dir = channel and Enum.StatusBarTimerDirection.RemainingTime
                             or Enum.StatusBarTimerDirection.ElapsedTime
        bar:SetReverseFill(false)
        bar:SetTimerDuration(d, Enum.StatusBarInterpolation.Immediate, dir)
        c.timer, c.manual = true, false
        -- The name may be secret: straight to the widget.
        if channel then c.text:SetText((UnitChannelInfo(unit))) else c.text:SetText((UnitCastingInfo(unit))) end
    else
        local name, _, _, s, e = UnitCastingInfo(unit)
        channel = false
        if not name then
            name, _, _, s, e = UnitChannelInfo(unit)
            channel = true
        end
        s, e = B.Num(s), B.Num(e)
        if not name or not s or not e or e <= s then return false end
        bar:SetMinMaxValues(s, e)
        bar:SetReverseFill(channel)
        bar:SetValue(GetTime() * 1000)
        c.timer, c.manual = false, true
        c.text:SetText(name)
    end

    if unit == "player" then
        bar:SetStatusBarColor(B.StateColor())
    else
        bar:SetStatusBarColor(1.00, 0.74, 0.26)
    end
    c.text:SetTextColor(0.95, 0.92, 0.86)
    return true
end

local function StartCast(c)
    local ok, shown = pcall(BeginCast, c)
    if not ok or not shown then
        if c.active then HideCast(c) end
        return
    end
    local fresh = not c.active
    c.active = true
    c.frame.acc = 0
    B.StopTween(c.flash)
    c.flash:SetAlpha(0)
    B.Fade(c.frame, 1, 0.15)
    if fresh then
        B.Tween(c, 0.3, 12, 0, c.SetOffset, B.Ease.outBack)
    end
end

--- ok = the cast went through; otherwise it was interrupted or failed.
function Signs.FinishCast(c, ok)
    if not c.active then return end
    c.active = false
    if ok then
        local r, g, b = 1, 1, 1
        c.flash:SetVertexColor(r, g, b)
        B.Tween(c.flash, 0.4, 0.9, 0, function(a) c.flash:SetAlpha(a) end)
        B.Fade(c.frame, 0, 0.4, B.Ease.inCubic)
    else
        c.bar:SetStatusBarColor(0.95, 0.25, 0.20)
        c.text:SetTextColor(0.95, 0.35, 0.30)
        c.text:SetText(T("Interrompu", "Interrupted"))
        B.Fade(c.frame, 0, 0.8, B.Ease.inCubic)
    end
end

local CAST_START = {
    UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_DELAYED = true, UNIT_SPELLCAST_CHANNEL_UPDATE = true,
}
local CAST_STOP = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true }

local function OnCastEvent(_, event, unit)
    if event == "PLAYER_TARGET_CHANGED" then
        local c = casts.target
        if B.db.cast and B.Flag(UnitExists("target")) and IsCasting("target") then
            c.active = false            -- a different caster: slide in again
            StartCast(c)
        elseif c.active or c.frame:IsShown() then
            HideCast(c)
        end
        return
    end
    local c = casts[unit]
    if not c or not B.db.cast then return end
    if CAST_START[event] then
        StartCast(c)
    elseif CAST_STOP[event] then
        Signs.FinishCast(c, true)
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        Signs.FinishCast(c, false)
    elseif event == "UNIT_SPELLCAST_FAILED" then
        -- Also fires for a key pressed during a cast: only a real stop counts.
        if c.active and not IsCasting(unit) then Signs.FinishCast(c, false) end
    end
end

local function BuildCasts()
    MakeCast("player", 1, -163, "castPlayer", T("Ton incantation", "Your cast"))             -- name inside the curve
    MakeCast("target", 1.17, -232, "castTarget", T("Incantation de la cible", "Target cast")) -- name under its arc
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
                         "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
                         "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
                         "UNIT_SPELLCAST_CHANNEL_UPDATE" }) do
        ev:RegisterUnitEvent(e, "player", "target")
    end
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:SetScript("OnEvent", OnCastEvent)
end

-- =====================================================================
-- THREAT
-- =====================================================================
-- Shown in combat against an attackable target, when someone else could
-- be holding it: in a group, or with a pet out. Solo it would only ever
-- say "you have aggro".
--   level 0 calm, 1 getting close, 2 about to change hands, 3 alarm
local THREAT_COLORS = {
    [0] = { 0.45, 0.86, 0.52 }, [1] = { 0.96, 0.82, 0.28 },
    [2] = { 1.00, 0.55, 0.15 }, [3] = { 0.96, 0.22, 0.18 },
}
local threat

local function BuildThreat()
    threat = CreateFrame("Frame", nil, B.anchor)
    threat:SetSize(CAST_W, CAST_H)
    function threat.Place()
        local ox, oy = B.Off("threat")
        threat:ClearAllPoints()
        threat:SetPoint("TOP", B.anchor, "CENTER", ox, CAST_EDGE + oy)
        if threat.text then
            threat.text:ClearAllPoints()
            threat.text:SetPoint("CENTER", B.anchor, "CENTER", ox, 163 + oy)
        end
    end
    B.Movable("threat", T("Menace", "Threat"), function(h)
        h:SetSize(CAST_W * 0.62, 22)
        h:SetPoint("TOP", threat, "TOP")
    end, function() threat.Place() end)
    threat:SetAlpha(0)
    threat:Hide()

    local bg = threat:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(MEDIA .. "ArcT")
    bg:SetAllPoints()
    bg:SetVertexColor(0.5, 0.5, 0.5, 0.40)

    threat.bar = CreateFrame("StatusBar", nil, threat)
    threat.bar:SetAllPoints()
    threat.bar:SetStatusBarTexture(MEDIA .. "ArcT")
    threat.bar:SetMinMaxValues(0, 100)
    threat.bar:SetValue(0)

    threat.glow = threat:CreateTexture(nil, "OVERLAY")
    threat.glow:SetTexture(MEDIA .. "ArcGlowT")
    threat.glow:SetAllPoints()
    threat.glow:SetBlendMode("ADD")
    threat.glow:SetAlpha(0)
    threat.pulse = threat.glow:CreateAnimationGroup()
    threat.pulse:SetLooping("BOUNCE")
    threat.beat = threat.pulse:CreateAnimation("Alpha")
    threat.beat:SetFromAlpha(0.15); threat.beat:SetToAlpha(1); threat.beat:SetSmoothing("IN_OUT")

    threat.text = B.Text(threat, 10, true)
    threat.Place()
end

local function WriteThreatPct(pct)
    threat.text:SetFormattedText("%d%%", pct)
end

local function UpdateThreat()
    if not threat then return end
    local db = B.db
    local status, pct, _
    local show = db.threat and B.inCombat and UnitDetailedThreatSituation
        and B.Flag(UnitExists("target")) and B.Flag(UnitCanAttack("player", "target"))
        and (B.Flag(IsInGroup()) or B.Flag(UnitExists("pet")))
    if show then
        _, status, pct = UnitDetailedThreatSituation("player", "target")
        status = B.Num(status)
        show = status ~= nil            -- nil: not on this target's threat list
    end
    if not show then
        if threat.level then
            threat.level = nil
            threat.pulse:Stop()
            if not Signs.preview then B.Fade(threat, 0, 0.3) end
        end
        return
    end

    -- 0 below the tank, 1 above the tank but not targeted yet,
    -- 2 targeted but someone is higher, 3 targeted and on top.
    local level, label
    local p = B.Num(pct)
    if db.tankMode then
        if status == 3 then level = 0
        elseif status == 2 then level, label = 2, T("FRAGILE", "SLIPPING")
        else level, label = 3, T("PERDU", "LOST") end
    else
        if status >= 2 then level, label = 3, "AGGRO"
        elseif status == 1 then level = 2
        elseif p and p >= 70 then level = 1
        else level = 0 end
    end

    local c = THREAT_COLORS[level]
    threat.bar:SetStatusBarColor(c[1], c[2], c[3])
    threat.glow:SetVertexColor(c[1], c[2], c[3])
    threat.text:SetTextColor(c[1], c[2], c[3])
    if type(pct) == "number" then threat.bar:SetValue(pct) else threat.bar:SetValue(100) end
    if label or type(pct) ~= "number" then
        threat.text:SetText(label or "")
    elseif not pcall(WriteThreatPct, pct) then
        threat.text:SetText("")
    end

    if level ~= threat.level then
        local rising = threat.level ~= nil and level > threat.level
        if threat.level == nil then B.Fade(threat, 1, 0.3) end
        threat.level = level
        threat.pulse:Stop()
        B.StopTween(threat.glow)
        if level >= 2 then
            threat.beat:SetDuration(level == 3 and 0.28 or 0.55)    -- the alarm beats faster
            threat.pulse:Play()
        elseif rising then
            B.Tween(threat.glow, 0.6, 0.9, 0, function(a) threat.glow:SetAlpha(a) end)
        else
            threat.glow:SetAlpha(0)
        end
    end
end

-- =====================================================================
-- COMBO POINTS
-- =====================================================================
local PT = (Enum and Enum.PowerType) or {}
local ENERGY = PT.Energy or 3
-- The classes that build combo points.
local CLASS_POINTS = {
    ROGUE = PT.ComboPoints or 4,
    DRUID = PT.ComboPoints or 4,        -- cat form only
}
local PIP_MAX, PIP_RADIUS, PIP_STEP, PIP_SIZE = 8, 102, 13, 11

local pips = {}
local pipHolder, pipGlow
local pipCount, pipTotal = 0, 0

local function BuildPips()
    pipHolder = CreateFrame("Frame", nil, B.Halo.root)
    pipHolder:SetSize(2, 2)
    pipHolder:SetPoint("CENTER")
    pipHolder:SetAlpha(0)
    pipHolder:Hide()

    -- Glows live on their own frame so the "full" pulse touches only them.
    pipGlow = CreateFrame("Frame", nil, pipHolder)
    pipGlow:SetSize(2, 2)
    pipGlow:SetPoint("CENTER")
    pipGlow.ag = pipGlow:CreateAnimationGroup()
    pipGlow.ag:SetLooping("BOUNCE")
    local al = pipGlow.ag:CreateAnimation("Alpha")
    al:SetFromAlpha(1); al:SetToAlpha(0.35); al:SetDuration(0.45); al:SetSmoothing("IN_OUT")

    for i = 1, PIP_MAX do
        local p = {}
        p.track = pipHolder:CreateTexture(nil, "BACKGROUND")
        p.track:SetTexture(MEDIA .. "Ember")
        p.track:SetVertexColor(0.5, 0.5, 0.5, 0.45)
        p.track:SetSize(PIP_SIZE - 3, PIP_SIZE - 3)
        p.dot = pipHolder:CreateTexture(nil, "ARTWORK")
        p.dot:SetTexture(MEDIA .. "Ember")
        p.dot:SetAlpha(0)
        p.glow = pipGlow:CreateTexture(nil, "ARTWORK")
        p.glow:SetTexture(MEDIA .. "Glow")
        p.glow:SetBlendMode("ADD")
        p.glow:SetSize(30, 30)
        p.glow:SetAlpha(0)
        pips[i] = p
    end
end

local function LayoutPips(total)
    for i, p in ipairs(pips) do
        local used = i <= total
        p.track:SetShown(used)
        p.dot:SetShown(used)
        p.glow:SetShown(used)
        if used then
            local a = rad(270 + (i - (total + 1) / 2) * PIP_STEP)
            local x, y = cos(a) * PIP_RADIUS, sin(a) * PIP_RADIUS
            for _, t in ipairs({ p.track, p.dot, p.glow }) do
                t:ClearAllPoints()
                t:SetPoint("CENTER", pipHolder, "CENTER", x, y)
            end
        end
    end
end

local function SetPip(p, on, r, g, b)
    if on == p.on then
        if on then p.dot:SetVertexColor(r, g, b); p.glow:SetVertexColor(r, g, b) end
        return
    end
    p.on = on
    if on then
        p.dot:SetVertexColor(r, g, b)
        p.glow:SetVertexColor(r, g, b)
        -- Pop: oversized and bright, settling to rest.
        B.Tween(p, 0.35, 0, 1, function(k)
            local s = B.Lerp(PIP_SIZE * 2.2, PIP_SIZE, k)
            p.dot:SetSize(s, s)
            p.dot:SetAlpha(B.Lerp(0.4, 1, k))
            p.glow:SetAlpha(B.Lerp(1, 0.45, k))
        end, B.Ease.outBack)
    else
        local a0, g0 = p.dot:GetAlpha(), p.glow:GetAlpha()
        B.Tween(p, 0.25, 0, 1, function(k)
            p.dot:SetAlpha(B.Lerp(a0, 0, k))
            p.glow:SetAlpha(B.Lerp(g0, 0, k))
        end)
    end
end

local playerClass

local function UpdateCombo()
    if not pipHolder then return end
    local ptype = CLASS_POINTS[playerClass]
    local total = ptype and B.Num(UnitPowerMax("player", ptype))
    local cur = ptype and B.Num(UnitPower("player", ptype))
    local show = B.db.combo and total and cur and total > 0
        and not B.Flag(UnitIsDeadOrGhost("player"))
        and (playerClass ~= "DRUID" or B.Num((UnitPowerType("player"))) == ENERGY)
    if not show then
        if pipHolder:IsShown() and pipHolder.want ~= 0 then
            pipHolder.want = 0
            B.Fade(pipHolder, 0, 0.3)
        end
        return
    end

    total = math.min(PIP_MAX, total)
    if total ~= pipTotal then
        pipTotal = total
        LayoutPips(total)
    end
    local r, g, b = B.Color(true)
    for i = 1, total do SetPip(pips[i], i <= cur, r, g, b) end
    pipCount = cur

    if cur >= total then
        if not pipGlow.ag:IsPlaying() then pipGlow.ag:Play() end
    else
        pipGlow.ag:Stop()
    end
    if pipHolder.want ~= 1 then
        pipHolder.want = 1
        B.Fade(pipHolder, 1, 0.3)
    end
end

-- =====================================================================
-- MISSING BUFFS
-- =====================================================================
-- Same rules as TomoModForever's reminder: spells match by name, so every
-- rank and the group versions count.
--   cast    spells the player may know, best first (rank 1 ids)
--   match   other spells whose aura satisfies the rule
--   weapon  a temporary weapon enchant is expected instead
--   known   spells that prove the rule applies when nothing is castable
local RULES = {
    MAGE    = { { cast = { 1459 }, match = { 23028 } }, { cast = { 6117, 7302, 168 } } },
    PRIEST  = { { cast = { 1243 }, match = { 21562 } }, { cast = { 588 } } },
    DRUID   = { { cast = { 1126 }, match = { 21849 } }, { cast = { 16864 } } },
    WARLOCK = { { cast = { 706, 687 } } },
    SHAMAN  = { { cast = { 324 } }, { weapon = true, cast = { 8232, 8024, 8033, 8017 } } },
    PALADIN = { { cast = { 465, 7294, 19746, 19876, 19888, 19891, 20218 } },
                { cast = { 19740, 19742, 20217, 1038, 19977, 20911 },
                  match = { 25782, 25894, 25898, 25895, 25890, 25899 } } },
    HUNTER  = { { cast = { 13165, 13163, 20043, 13159, 5118, 13161 } }, { cast = { 19506 } } },
    ROGUE   = { { weapon = true, known = { 2842 } } },
}
local WEAPON_ICON = "Interface\\Icons\\INV_Sword_04"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local BUFF_MAX, BUFF_RADIUS, BUFF_STEP, BUFF_SIZE = 4, 128, 15, 22

local buffHolder
local buffIcons = {}
local scanQueued = false

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
end

local function SpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
end

local function Known(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, v = pcall(C_SpellBook.IsSpellKnown, id)
        if ok and v then return true end
    end
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    return false
end

--- Readable names of the player's buffs, or nil if they cannot be read.
local function BuffNames()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    local names = {}
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not a then break end
        if type(a.name) == "string" and not B.Secret(a.name) then names[a.name] = true end
    end
    return names
end

local function HasWeaponEnchant()
    if not GetWeaponEnchantInfo or not GetInventoryItemID then return true end
    if not GetInventoryItemID("player", 16) then return true end      -- nothing to enchant
    local hasMain, _, _, _, hasOff = GetWeaponEnchantInfo()
    if not hasMain then return false end
    local offID = GetInventoryItemID("player", 17)
    if offID and not hasOff and C_Item and C_Item.GetItemInfo then
        local _, _, _, _, _, _, _, _, equipLoc = C_Item.GetItemInfo(offID)
        if equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONOFFHAND" then return false end
    end
    return true
end

--- Icons of the buffs currently missing.
local function MissingBuffs()
    local out = {}
    local names = BuffNames()
    if not names then return out end
    for _, rule in ipairs(RULES[playerClass] or {}) do
        local castID
        for _, id in ipairs(rule.cast or {}) do
            if Known(id) then castID = id break end
        end
        local applies = castID ~= nil
        if not applies and rule.known then
            for _, id in ipairs(rule.known) do
                if Known(id) then applies = true break end
            end
        end
        if applies then
            local ok = false
            if rule.weapon then
                ok = HasWeaponEnchant()
            else
                for _, list in ipairs({ rule.cast or {}, rule.match or {} }) do
                    for _, id in ipairs(list) do
                        local n = SpellName(id)
                        if n and names[n] then ok = true break end
                    end
                    if ok then break end
                end
            end
            if not ok and #out < BUFF_MAX then
                out[#out + 1] = (not rule.weapon and castID and SpellIcon(castID))
                    or (rule.weapon and WEAPON_ICON) or 134400
            end
        end
    end
    return out
end

local function BuildBuffs()
    buffHolder = CreateFrame("Frame", nil, B.anchor)
    buffHolder:SetSize(2, 2)
    buffHolder:SetPoint("CENTER")
    buffHolder:SetAlpha(0)
    buffHolder:Hide()

    for i = 1, BUFF_MAX do
        local f = CreateFrame("Frame", nil, buffHolder)
        f:SetSize(BUFF_SIZE, BUFF_SIZE)
        f:Hide()

        f.glow = f:CreateTexture(nil, "BACKGROUND")
        f.glow:SetTexture(MEDIA .. "Glow")
        f.glow:SetBlendMode("ADD")
        f.glow:SetPoint("CENTER")
        f.glow:SetSize(BUFF_SIZE * 2.4, BUFF_SIZE * 2.4)
        f.pulse = f.glow:CreateAnimationGroup()
        f.pulse:SetLooping("BOUNCE")
        local al = f.pulse:CreateAnimation("Alpha")
        al:SetFromAlpha(0.9); al:SetToAlpha(0.25); al:SetDuration(0.9); al:SetSmoothing("IN_OUT")

        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetAllPoints()
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.icon:SetDesaturated(true)             -- a ghost of the buff, not the buff
        f.icon:SetVertexColor(1, 1, 1, 0.9)
        if f.CreateMaskTexture then
            local mask = f:CreateMaskTexture()
            mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(f.icon)
            f.icon:AddMaskTexture(mask)
        end

        -- Scaling a frame scales its anchor offsets too: divide them back.
        function f.Place(s)
            f:SetScale(s)
            f:ClearAllPoints()
            f:SetPoint("CENTER", buffHolder, "CENTER", f.x / s, f.y / s)
        end
        buffIcons[i] = f
    end
end

local function ShowBuffs(list)
    local n = #list
    local r, g, b = B.Color(false)
    for i, f in ipairs(buffIcons) do
        local icon = list[i]
        if icon then
            local a = rad(90 - (i - (n + 1) / 2) * BUFF_STEP)
            f.x, f.y = cos(a) * BUFF_RADIUS, sin(a) * BUFF_RADIUS
            f.icon:SetTexture(icon)
            f.glow:SetVertexColor(r, g, b)
            if not f:IsShown() then
                f:Show()
                f.pulse:Play()
                B.Tween(f, 0.4, 0.4, 1, f.Place, B.Ease.outBack)     -- pop in
            else
                B.StopTween(f)
                f.Place(1)
            end
        elseif f:IsShown() then
            B.StopTween(f)
            f.pulse:Stop()
            f:Hide()
        end
    end
    if n > 0 then
        B.Fade(buffHolder, 1, 0.4)
    elseif buffHolder:IsShown() then
        B.Fade(buffHolder, 0, 0.3)
    end
end

local function ScanBuffs()
    scanQueued = false
    if not buffHolder then return end
    if not B.db.buffs or B.inCombat or B.Flag(UnitIsDeadOrGhost("player")) then
        if buffHolder:IsShown() then B.Fade(buffHolder, 0, 0.25) end
        return
    end
    local ok, list = pcall(MissingBuffs)
    ShowBuffs(ok and list or {})
end

--- Coalesce bursts of aura events into one scan.
local function QueueScan()
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(0.4, ScanBuffs)
end

-- =====================================================================
-- Module hooks
-- =====================================================================
function Signs:Init()
    local _, class = UnitClass("player")
    playerClass = class

    BuildCasts()
    BuildThreat()
    BuildPips()
    BuildBuffs()

    local ev = CreateFrame("Frame")
    ev:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    ev:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    ev:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    ev:RegisterUnitEvent("UNIT_AURA", "player")
    ev:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    ev:RegisterEvent("SPELLS_CHANGED")
    ev:RegisterUnitEvent("UNIT_THREAT_SITUATION_UPDATE", "player")
    ev:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", "target")
    ev:RegisterUnitEvent("UNIT_PET", "player")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:SetScript("OnEvent", function(_, event)
        if event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE"
            or event == "UNIT_PET" or event == "GROUP_ROSTER_UPDATE" then
            UpdateThreat()
        elseif event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED" or event == "SPELLS_CHANGED" then
            if not B.inCombat then QueueScan() end
        else
            UpdateCombo()
        end
    end)
end

--- Move mode: show the cast arcs and the threat gauge even when idle.
function Signs:SetPreview(on)
    Signs.preview = on
    if not threat then return end
    for _, c in pairs(casts) do
        if on then
            if not c.active then
                c.text:SetText(c.label)
                c.text:SetTextColor(0.80, 0.77, 0.72)
                c.bar:SetValue(0)
            end
            B.Fade(c.frame, 1, 0.2)
        elseif not c.active then
            B.Fade(c.frame, 0, 0.2)
        end
    end
    if on then
        if not threat.level then
            threat.text:SetText(T("Menace", "Threat"))
            threat.text:SetTextColor(0.80, 0.77, 0.72)
            threat.bar:SetValue(0)
        end
        B.Fade(threat, 1, 0.2)
    elseif not threat.level then
        B.Fade(threat, 0, 0.2)
    end
end

function Signs:Refresh()
    if not pipHolder then return end
    UpdateCombo()
    UpdateThreat()
    QueueScan()
    if not B.db.cast then
        for _, c in pairs(casts) do
            if c.active or c.frame:IsShown() then HideCast(c) end
        end
    end
end

function Signs:CombatStart()
    if not pipHolder then return end
    UpdateCombo()
    UpdateThreat()
    ScanBuffs()         -- hides the reminders
end

function Signs:CombatEnd()
    if not pipHolder then return end
    UpdateCombo()
    UpdateThreat()
    QueueScan()
end
