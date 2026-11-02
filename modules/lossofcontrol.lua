pfUI:RegisterModule("lossofcontrol", function ()
  -- 5.x's loss of control alert. ClassicAPI's C_LossOfControl builds the
  -- effects from the player's debuffs and from the school lockout of an
  -- interrupt.
  local strings = L["lossofcontrol"]

  -- how much each effect takes away; the alert shows the strongest one
  local PRIORITY = {
    STUN = 3, FEAR = 3, CONFUSE = 3, CHARM = 3, POSSESS = 3, PACIFYSILENCE = 3,
    SILENCE = 2, SCHOOL_INTERRUPT = 2, PACIFY = 2,
    DISARM = 1, ROOT = 1,
  }

  -- the lockout packet does not name the interrupting spell
  local INTERRUPT_ICON = "Interface\\Icons\\Ability_Kick"

  local function IsStronger(data, best)
    local priority, bestPriority = PRIORITY[data.locType], PRIORITY[best.locType]
    if priority ~= bestPriority then return priority > bestPriority end
    return (data.timeRemaining or math.huge) > (best.timeRemaining or math.huge)
  end

  local frame = CreateFrame("Frame", "pfLossOfControl", UIParent)
  frame:SetSize(220, 48)
  frame:SetPoint("CENTER", 0, 120)
  frame:SetFrameStrata("HIGH")
  frame:Hide()

  frame.icon = CreateFrame("Frame", nil, frame)
  frame.icon:SetSize(48, 48)
  frame.icon:SetPoint("LEFT", 0, 0)
  CreateBackdrop(frame.icon, nil, true)

  frame.icon.tex = frame.icon:CreateTexture(nil, "ARTWORK")
  HandleIcon(frame.icon, frame.icon.tex)

  frame.cd = CreateCooldown(frame.icon, "timer", C.cooldown, "lossofcontrol_timers")
  frame.cd:SetAllPoints(frame.icon.tex)

  frame.label = frame:CreateFontString(nil, "OVERLAY")
  frame.label:SetFont(pfUI.font_default, 20, "OUTLINE")
  frame.label:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
  frame.label:SetPoint("LEFT", frame.icon, "RIGHT", 8, 0)

  frame.Refresh = function(self)
    local best
    for i = 1, C_LossOfControl.GetActiveLossOfControlDataCount() do
      local data = C_LossOfControl.GetActiveLossOfControlData(i)
      if not best or IsStronger(data, best) then best = data end
    end

    if not best then
      if pfUI.unlock and pfUI.unlock:IsShown() then return end
      self:Hide()
      return
    end

    if best.locType == "SCHOOL_INTERRUPT" then
      self.label:SetText(format(strings.LOSS_OF_CONTROL_DISPLAY_INTERRUPT_SCHOOL, C_Spell.GetSchoolString(best.lockoutSchool)))
      self.icon.tex:SetTexture(INTERRUPT_ICON)
    else
      self.label:SetText(strings["LOSS_OF_CONTROL_DISPLAY_" .. best.locType])
      self.icon.tex:SetTexture(best.iconTexture)
    end

    CooldownFrame_SetTimer(self.cd, best.startTime or 0, best.duration or 0, best.startTime and 1 or 0)
    self:Show()
  end

  -- a refreshed debuff (UNIT_AURA_DELTA) or a second kick on the same school
  -- (SPELL_UPDATE_COOLDOWN) changes the timer without a loss of control event
  frame:SetScript("OnShow", function()
    this:RegisterUnitEvent("UNIT_AURA_DELTA", "player")
    this:RegisterEvent("SPELL_UPDATE_COOLDOWN")
  end)
  frame:SetScript("OnHide", function()
    this:UnregisterAllEvents()
  end)
  frame:SetScript("OnEvent", function()
    this:Refresh()
  end)

  pfUI.events:RegisterFrameEventAndCallback("LOSS_OF_CONTROL_ADDED", function() frame:Refresh() end)
  pfUI.events:RegisterFrameEventAndCallback("LOSS_OF_CONTROL_UPDATE", function() frame:Refresh() end)

  UpdateMovable(frame)
  pfUI.lossofcontrol = frame
end)
