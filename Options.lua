-- =====================================================================
-- Braise / Options.lua -- settings panel (/braise)
--
-- Built on first use. Flat, dark, one column; every control animates
-- (switch knobs slide, the panel eases in) and every change is applied
-- live through B.Call("Refresh").
-- =====================================================================

local _, B = ...
local Options = B.Module("Options")
local T = B.T

local PAD, ROW, INNER, GAP = 18, 28, 320, 30
local W = PAD * 2 + INNER * 2 + GAP      -- two columns
local X = PAD                             -- left edge of the column being built
local BG     = { 0.055, 0.050, 0.045 }
local BRONZE = { 0.545, 0.420, 0.247 }
local TEXT   = { 0.95, 0.92, 0.86 }
local MUTED  = { 0.60, 0.57, 0.52 }

local panel
local refreshers = {}

local function Apply()
    B.ApplyAnchor()
    B.ApplyUnitFrames()
    B.Call("Refresh")
end

local function Label(parent, size, bold, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(bold and B.FONT_BOLD or B.FONT, size, "")
    color = color or TEXT
    fs:SetTextColor(color[1], color[2], color[3])
    return fs
end

local function Solid(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(B.WHITE)
    t:SetVertexColor(r, g, b, a or 1)
    return t
end

-- ---------------------------------------------------------------------
-- Widgets
-- ---------------------------------------------------------------------
local function Section(y, text)
    local row = CreateFrame("Frame", nil, panel)
    row:SetPoint("TOPLEFT", X, y - 4)
    row:SetSize(INNER, 16)
    local fs = Label(row, 9, true, BRONZE)
    fs:SetPoint("LEFT")
    fs:SetText(string.upper(text))
    local line = Solid(row, "ARTWORK", BRONZE[1], BRONZE[2], BRONZE[3], 0.35)
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetPoint("RIGHT")
    return y - 26
end

local function Toggle(y, key, text)
    local row = CreateFrame("Button", nil, panel)
    row:SetPoint("TOPLEFT", X, y)
    row:SetSize(INNER, ROW)

    local label = Label(row, 12)
    label:SetPoint("LEFT")
    label:SetWidth(INNER - 42)          -- never runs under the switch
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(text)

    local track = Solid(row, "ARTWORK", 1, 1, 1, 0.10)
    track:SetSize(30, 14)
    track:SetPoint("RIGHT")
    local knob = Solid(row, "OVERLAY", 1, 1, 1)
    knob:SetSize(10, 10)

    local function Paint(p)            -- p: 0 = off, 1 = on
        local r, g, b = B.Color(false)
        track:SetVertexColor(B.Lerp(1, r, p), B.Lerp(1, g, p), B.Lerp(1, b, p), B.Lerp(0.10, 0.55, p))
        knob:SetVertexColor(B.Lerp(MUTED[1], 1, p), B.Lerp(MUTED[2], 1, p), B.Lerp(MUTED[3], 1, p))
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", track, "LEFT", B.Lerp(2, 18, p), 0)
    end

    row.p = 0
    local function Set(on, animate)
        local to = on and 1 or 0
        B.Tween(row, animate and 0.18 or 0, row.p, to, function(p)
            row.p = p
            Paint(p)
        end)
    end

    row:SetScript("OnClick", function()
        B.db[key] = not B.db[key]
        Set(B.db[key], true)
        Apply()
    end)
    row:SetScript("OnEnter", function() label:SetTextColor(1, 1, 1) end)
    row:SetScript("OnLeave", function() label:SetTextColor(TEXT[1], TEXT[2], TEXT[3]) end)

    refreshers[#refreshers + 1] = function() Set(B.db[key], false) end
    return y - ROW
end

local function Slider(y, key, text, lo, hi, step, fmt)
    local row = CreateFrame("Frame", nil, panel)
    row:SetPoint("TOPLEFT", X, y)
    row:SetSize(INNER, 38)
    row:EnableMouse(true)

    local label = Label(row, 12)
    label:SetPoint("TOPLEFT", 0, -3)
    label:SetText(text)
    local value = Label(row, 11, true, MUTED)
    value:SetPoint("TOPRIGHT", 0, -4)

    local track = Solid(row, "ARTWORK", 1, 1, 1, 0.10)
    track:SetHeight(3)
    track:SetPoint("BOTTOMLEFT", 0, 8)
    track:SetPoint("BOTTOMRIGHT", 0, 8)
    local fill = Solid(row, "OVERLAY", 1, 1, 1)
    fill:SetHeight(3)
    fill:SetPoint("LEFT", track, "LEFT")
    local thumb = Solid(row, "OVERLAY", 1, 1, 1)
    thumb:SetSize(4, 13)

    local function Show()
        local v = B.db[key]
        local p = math.max(0, math.min(1, (v - lo) / (hi - lo)))
        local w = math.max(1, INNER * p)
        local r, g, b = B.Color(false)
        fill:SetVertexColor(r, g, b)
        fill:SetWidth(w)
        thumb:ClearAllPoints()
        thumb:SetPoint("CENTER", track, "LEFT", w, 0)
        value:SetFormattedText(fmt, v)
    end

    local function FromCursor()
        local x = GetCursorPosition() / row:GetEffectiveScale()
        local left, width = row:GetLeft(), INNER
        if not left or not width or width <= 0 then return end
        local p = math.max(0, math.min(1, (x - left) / width))
        local v = lo + p * (hi - lo)
        v = math.floor(v / step + 0.5) * step
        if v ~= B.db[key] then
            B.db[key] = v
            Show()
            Apply()
        end
    end

    row:SetScript("OnMouseDown", function(self)
        FromCursor()
        self:SetScript("OnUpdate", FromCursor)
    end)
    row:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    row:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

    refreshers[#refreshers + 1] = Show
    return y - 42
end

local function ThemePicker(y)
    local row = CreateFrame("Frame", nil, panel)
    row:SetPoint("TOPLEFT", X, y)
    row:SetSize(INNER, 34)

    local name = Label(row, 12)
    name:SetPoint("RIGHT")

    local buttons = {}
    local function Show()
        for _, btn in ipairs(buttons) do
            local on = btn.key == B.db.theme
            local was = B.db.theme
            B.db.theme = btn.key                    -- borrow B.Color for this swatch
            local r, g, b = B.Color(false)
            local hr, hg, hb = B.Color(true)
            B.db.theme = was
            btn.a:SetVertexColor(r, g, b)
            btn.b:SetVertexColor(hr, hg, hb)
            btn.ring:SetVertexColor(1, 1, 1, on and 0.9 or 0)
            if on then name:SetText(T(btn.th.fr, btn.th.en)) end
        end
    end

    for i, th in ipairs(B.themes) do
        local btn = CreateFrame("Button", nil, row)
        btn:SetSize(26, 26)
        btn:SetPoint("LEFT", (i - 1) * 34, 0)
        btn.key, btn.th = th.key, th
        btn.ring = Solid(btn, "BACKGROUND", 1, 1, 1, 0)
        btn.ring:SetPoint("TOPLEFT", -2, 2)
        btn.ring:SetPoint("BOTTOMRIGHT", 2, -2)
        local back = Solid(btn, "BORDER", BG[1], BG[2], BG[3])
        back:SetPoint("TOPLEFT", -1, 1)
        back:SetPoint("BOTTOMRIGHT", 1, -1)
        btn.a = Solid(btn, "ARTWORK", 1, 1, 1)
        btn.a:SetPoint("TOPLEFT")
        btn.a:SetPoint("BOTTOMRIGHT", btn, "BOTTOM", 0, 0)
        btn.b = Solid(btn, "ARTWORK", 1, 1, 1)
        btn.b:SetPoint("TOPLEFT", btn, "TOP", 0, 0)
        btn.b:SetPoint("BOTTOMRIGHT")
        btn:SetScript("OnClick", function()
            B.db.theme = th.key
            Options:Sync()
            Apply()
        end)
        buttons[i] = btn
    end

    refreshers[#refreshers + 1] = Show
    return y - 40
end

local function Button(parent, text, width, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, 24)
    local bg = Solid(btn, "BACKGROUND", 1, 1, 1, 0.07)
    bg:SetAllPoints()
    local fs = Label(btn, 11, true)
    fs:SetPoint("CENTER")
    fs:SetText(text)
    btn:SetScript("OnEnter", function()
        local r, g, b = B.Color(false)
        B.Tween(btn, 0.15, 0, 1, function(p)
            bg:SetVertexColor(B.Lerp(1, r, p), B.Lerp(1, g, p), B.Lerp(1, b, p), B.Lerp(0.07, 0.45, p))
        end)
    end)
    btn:SetScript("OnLeave", function()
        B.StopTween(btn)
        bg:SetVertexColor(1, 1, 1, 0.07)
    end)
    btn:SetScript("OnClick", onClick)
    return btn
end

-- ---------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------
local function Build()
    panel = CreateFrame("Frame", "BraiseOptions", UIParent)
    panel:SetWidth(W)
    panel:SetPoint("RIGHT", UIParent, "CENTER", -250, 0)      -- beside the halo; clamped on narrow screens
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:Hide()
    tinsert(UISpecialFrames, "BraiseOptions")      -- Escape closes it

    local bg = Solid(panel, "BACKGROUND", BG[1], BG[2], BG[3], 0.96)
    bg:SetAllPoints()
    for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", false }, { "BOTTOMLEFT", "BOTTOMRIGHT", false },
                         { "TOPLEFT", "BOTTOMLEFT", true }, { "TOPRIGHT", "BOTTOMRIGHT", true } }) do
        local e = Solid(panel, "BORDER", BRONZE[1], BRONZE[2], BRONZE[3], 0.8)
        e:SetPoint(p[1]); e:SetPoint(p[2])
        if p[3] then e:SetWidth(1) else e:SetHeight(1) end
    end

    local title = Label(panel, 18, true, { 1, 0.82, 0 })
    title:SetPoint("TOPLEFT", PAD, -16)
    title:SetText("Braise")
    local tag = Label(panel, 10, false, MUTED)
    tag:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 2)
    tag:SetText(T("le HUD qui respire", "the HUD that breathes"))

    local close = CreateFrame("Button", nil, panel)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -10, -12)
    local x = Label(close, 14, true, MUTED)
    x:SetPoint("CENTER")
    x:SetText("x")
    close:SetScript("OnEnter", function() x:SetTextColor(1, 1, 1) end)
    close:SetScript("OnLeave", function() x:SetTextColor(MUTED[1], MUTED[2], MUTED[3]) end)
    close:SetScript("OnClick", function() Options:Toggle() end)

    -- Left column
    X = PAD
    local y = -50
    y = Section(y, T("Thème", "Theme"))
    y = ThemePicker(y)

    y = Section(y, T("Halo", "Halo"))
    y = Toggle(y, "halo",   T("Arcs de vie et de ressource", "Health and power arcs"))
    y = Toggle(y, "texts",  T("Valeurs sous les arcs", "Values under the arcs"))
    y = Toggle(y, "target", T("Arcs de la cible (vie et ressource)", "Target arcs (health and power)"))
    y = Toggle(y, "pet",    T("Arcs du familier (vie et ressource)", "Pet arcs (health and power)"))
    y = Toggle(y, "tot",    T("Cible de la cible", "Target of target"))
    y = Toggle(y, "ring",   T("Anneaux tournants", "Rotating rings"))
    y = Slider(y, "scale",    T("Taille", "Size"), 0.6, 1.6, 0.05, "%.2f")
    y = Slider(y, "oocAlpha", T("Opacité hors combat", "Opacity out of combat"), 0, 1, 0.05, "%.2f")

    y = Section(y, T("Cadres d'unité", "Unit frames"))
    y = Toggle(y, "click", T("Clic sur les arcs (cibler, menu)", "Click on the arcs (target, menu)"))
    y = Toggle(y, "hidePlayer", T("Masquer le cadre du joueur", "Hide the player frame"))
    y = Toggle(y, "hideTarget", T("Masquer le cadre de la cible", "Hide the target frame"))
    y = Toggle(y, "hidePet",    T("Masquer le cadre du familier", "Hide the pet frame"))
    y = Toggle(y, "hideToT",    T("Masquer le cadre cible de la cible", "Hide the target-of-target frame"))
    local bottom = y

    -- Right column
    X = PAD + INNER + GAP
    y = -50
    y = Section(y, T("Signes", "Signs"))
    y = Toggle(y, "cast",  T("Arcs d'incantation (toi, cible)", "Cast arcs (you, target)"))
    y = Toggle(y, "hideCastTarget", T("Masquer la barre Blizzard (cible)", "Hide Blizzard's bar (target)"))
    y = Toggle(y, "hideCastPlayer", T("Masquer la barre Blizzard (toi)", "Hide Blizzard's bar (you)"))
    y = Toggle(y, "combo", T("Points de combo", "Combo points"))
    y = Toggle(y, "buffs", T("Buffs manquants (hors combat)", "Missing buffs (out of combat)"))
    y = Toggle(y, "threat",   T("Jauge de menace (groupe, familier)", "Threat gauge (group or pet)"))
    y = Toggle(y, "tankMode", T("Je suis tank (menace inversée)", "I am the tank (threat reversed)"))
    y = Toggle(y, "timer", T("Chrono de combat", "Combat timer"))
    y = Toggle(y, "recap", T("Récap de fin de combat", "After-combat recap"))

    y = Section(y, T("Ambiance", "Ambience"))
    y = Toggle(y, "embers",      T("Braises", "Embers"))
    y = Toggle(y, "classEmbers", T("Braises : mouvement de classe", "Embers: class-style motion"))
    y = Toggle(y, "vignette",    T("Bords d'écran (chaleur, vie basse)", "Screen edges (heat, low health)"))
    y = Toggle(y, "transitions", T("Transitions de combat", "Combat transitions"))
    y = Toggle(y, "levelup",     T("Animation de montée de niveau", "Level-up animation"))
    y = Slider(y, "emberAmount", T("Quantité de braises", "Ember amount"), 0.2, 1.3, 0.1, "%.1f")

    X = PAD
    y = math.min(y, bottom)
    y = y - 8
    local bw = (W - PAD * 2 - 16) / 3
    local b1 = Button(panel, T("Tester", "Test"), bw, function() B.Demo() end)
    b1:SetPoint("TOPLEFT", PAD, y)
    local b2 = Button(panel, T("Déplacer", "Move"), bw, function() B.Halo:ToggleMover() end)
    b2:SetPoint("LEFT", b1, "RIGHT", 8, 0)
    local b3 = Button(panel, T("Par défaut", "Defaults"), bw, function()
        B.Reset()
        Options:Sync()
    end)
    b3:SetPoint("LEFT", b2, "RIGHT", 8, 0)

    panel:SetHeight(-y + 24 + PAD)
end

function Options:Sync()
    for _, fn in ipairs(refreshers) do fn() end
end

function Options:Toggle()
    if not panel then Build() end
    if panel:IsShown() and panel.open then
        panel.open = false
        B.Fade(panel, 0, 0.15)
        return
    end
    panel.open = true
    panel:SetAlpha(0)
    panel:Show()
    Options:Sync()
    B.Tween(panel, 0.25, 0, 1, function(a) panel:SetAlpha(a) end)
end
