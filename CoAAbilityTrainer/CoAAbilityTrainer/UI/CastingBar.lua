-- ============================================================
-- CoAAbilityTrainer - Casting Bar
-- Sleek cast and channel bar that matches the WeakAuras design
-- ============================================================

CoAAT_CastingBar = {}

local BAR_W = 264
local BAR_H = 18
local _frame = nil

local castSpellName = nil
local castStartTime = 0
local castEndTime = 0
local castDuration = 0
local isChanneling = false
local isCasting = false

function CoAAT_CastingBar.Build(parent)
    local f = CreateFrame("Frame", "CoAATCastingBar", parent)
    f:SetSize(BAR_W, BAR_H)
    f:SetPoint("CENTER", parent, "CENTER", 0, 0)
    
    -- Background
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0.04, 0.04, 0.08, 0.85)
    f._bg = bg

    -- Border Backdrop (1px thin outline)
    local function makeBorderLine(p, w, h, x, y)
        local l = f:CreateTexture(nil, "OVERLAY")
        l:SetSize(w, h)
        l:SetTexture(0, 0, 0, 0.8)
        l:SetPoint(p, f, p, x, y)
    end
    makeBorderLine("TOPLEFT", BAR_W + 2, 1, -1, 1)
    makeBorderLine("BOTTOMLEFT", BAR_W + 2, 1, -1, -1)
    makeBorderLine("TOPLEFT", 1, BAR_H + 2, -1, 1)
    makeBorderLine("TOPRIGHT", 1, BAR_H + 2, 1, 1)

    -- Left Spell Icon
    local iconFrame = CreateFrame("Frame", nil, f)
    iconFrame:SetSize(BAR_H, BAR_H)
    iconFrame:SetPoint("RIGHT", f, "LEFT", -6, 0)
    
    local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f._iconTex = iconTex

    local iconBorder = iconFrame:CreateTexture(nil, "BACKGROUND")
    iconBorder:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", -1, 1)
    iconBorder:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 1, -1)
    iconBorder:SetTexture(0, 0, 0, 0.8)

    -- Progress Fill
    local fill = f:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", f, "LEFT", 0, 0)
    fill:SetPoint("TOP", f, "TOP", 0, 0)
    fill:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
    fill:SetTexture(1.0, 0.45, 0.0, 0.9) -- Orange
    f._fill = fill

    -- Spark Overlay
    local spark = f:CreateTexture(nil, "OVERLAY")
    spark:SetSize(8, BAR_H + 4)
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD")
    f._spark = spark

    -- Spell Name Left
    local nameText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameText:SetPoint("LEFT", f, "LEFT", 8, 0)
    nameText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    nameText:SetText("")
    f._nameText = nameText

    -- Time text Right
    local timeText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeText:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    timeText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    timeText:SetText("")
    f._timeText = timeText

    f:Hide()
    _frame = f

    -- Hook events
    f:RegisterEvent("UNIT_SPELLCAST_START")
    f:RegisterEvent("UNIT_SPELLCAST_DELAYED")
    f:RegisterEvent("UNIT_SPELLCAST_STOP")
    f:RegisterEvent("UNIT_SPELLCAST_FAILED")
    f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    f:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    f:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
    f:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")

    f:SetScript("OnEvent", function(self, event, unit, ...)
        if unit ~= "player" then return end
        
        if event == "UNIT_SPELLCAST_START" then
            local name, _, _, icon, startTime, endTime = UnitCastingInfo("player")
            if name then
                castSpellName = name
                castStartTime = startTime / 1000
                castEndTime = endTime / 1000
                castDuration = castEndTime - castStartTime
                isCasting = true
                isChanneling = false
                f._fill:SetTexture(1.0, 0.45, 0.0, 0.9) -- Orange
                f._nameText:SetText(name)
                if f._iconTex and icon then
                    f._iconTex:SetTexture(icon)
                end
                f:Show()
            end
        elseif event == "UNIT_SPELLCAST_DELAYED" then
            local name, _, _, _, startTime, endTime = UnitCastingInfo("player")
            if name then
                castStartTime = startTime / 1000
                castEndTime = endTime / 1000
                castDuration = castEndTime - castStartTime
            end
        elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
            local name, _, _, icon, startTime, endTime = UnitChannelInfo("player")
            if name then
                castSpellName = name
                castStartTime = startTime / 1000
                castEndTime = endTime / 1000
                castDuration = castEndTime - castStartTime
                isCasting = false
                isChanneling = true
                f._fill:SetTexture(0.0, 0.75, 1.0, 0.9) -- Cyan
                f._nameText:SetText(name)
                if f._iconTex and icon then
                    f._iconTex:SetTexture(icon)
                end
                f:Show()
            end
        elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
            local name, _, _, _, startTime, endTime = UnitChannelInfo("player")
            if name then
                castStartTime = startTime / 1000
                castEndTime = endTime / 1000
                castDuration = castEndTime - castStartTime
            end
        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
            if isCasting then
                isCasting = false
                f:Hide()
            end
        elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            if isChanneling then
                isChanneling = false
                f:Hide()
            end
        end
    end)

    f:SetScript("OnUpdate", function(self, dt)
        if not (isCasting or isChanneling) then return end
        
        local currentTime = GetTime()
        if isCasting then
            local elapsed = currentTime - castStartTime
            local pct = math.min(1.0, elapsed / castDuration)
            self._fill:SetWidth(math.max(1, BAR_W * pct))
            self._timeText:SetText(string.format("%.1fs", math.max(0, castEndTime - currentTime)))
            
            if pct > 0 and pct < 1 then
                self._spark:ClearAllPoints()
                self._spark:SetPoint("CENTER", self._fill, "RIGHT", 0, 0)
                self._spark:Show()
            else
                self._spark:Hide()
            end

            if pct >= 1.0 then
                isCasting = false
                self:Hide()
            end
        elseif isChanneling then
            local remaining = castEndTime - currentTime
            local pct = math.min(1.0, remaining / castDuration)
            self._fill:SetWidth(math.max(1, BAR_W * pct))
            self._timeText:SetText(string.format("%.1fs", math.max(0, remaining)))
            
            if pct > 0 and pct < 1 then
                self._spark:ClearAllPoints()
                self._spark:SetPoint("CENTER", self._fill, "RIGHT", 0, 0)
                self._spark:Show()
            else
                self._spark:Hide()
            end

            if pct <= 0 then
                isChanneling = false
                self:Hide()
            end
        end
    end)

    return f
end
