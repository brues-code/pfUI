pfUI:RegisterModule("target", function ()
  -- do not go further on disabled UFs
  if C.unitframes.disable == "1" then return end

  -- Hide Blizzard target frame and unregister all events to prevent it from popping up again
  TargetFrame:Hide()
  TargetFrame:UnregisterAllEvents()

  pfUI.uf.target = pfUI.uf:CreateUnitFrame("Target", nil, C.unitframes.target)
  pfUI.uf.target:UpdateFrameSize()
  pfUI.uf.target:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", 75, 125)
  UpdateMovable(pfUI.uf.target)

  -- "NO LOS" in the bottom third of the frame, below unitxp's behind indicator
  if C.unitframes.los_indicator == "1" then
    local los = CreateFrame("Frame", "pfLoSIndicator", pfUI.uf.target)
    los:SetAllPoints(pfUI.uf.target)
    los:SetFrameLevel(pfUI.uf.target:GetFrameLevel() + 10)

    los.text = los:CreateFontString(nil, "OVERLAY")
    los.text:SetFont(pfUI.font_default, tonumber(C.unitframes.indicator_font_size) or (C.global.font_size + 2), "OUTLINE")
    los.text:SetPoint("RIGHT", los, "RIGHT", -1, -pfUI.uf.target:GetHeight() / 3)
    los.text:SetTextColor(1, 0.3, 0.3, 1)
    los.text:SetText(T["NO LOS"])
    los.text:Hide()

    local lastCheck = 0
    los:SetScript("OnUpdate", function()
      if GetTime() - lastCheck < 0.2 then return end
      lastCheck = GetTime()

      -- nil without a target
      this.text:SetShown(UnitInLineOfSight("target") == false)
    end)
  end
end)
