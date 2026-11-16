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

  -- [ target indicators ]
  -- Text on the right edge of the frame, one per third: distance on top,
  -- "BEHIND" in the middle, "NO LOS" at the bottom. Each polls while the
  -- target frame is shown, as none of them has an event.
  local fontSize = tonumber(C.unitframes.indicator_font_size) or (C.global.font_size + 2)
  local third = pfUI.uf.target:GetHeight() / 3

  local function CreateIndicator(name, offset, interval, update)
    local f = CreateFrame("Frame", name, pfUI.uf.target)
    f:SetAllPoints(pfUI.uf.target)
    f:SetFrameLevel(pfUI.uf.target:GetFrameLevel() + 10)

    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFont(pfUI.font_default, fontSize, "OUTLINE")
    f.text:SetPoint("RIGHT", f, "RIGHT", -1, offset)
    f.text:Hide()

    local lastCheck = 0
    f:SetScript("OnUpdate", function()
      if GetTime() - lastCheck < interval then return end
      lastCheck = GetTime()
      update(this.text)
    end)
    return f
  end

  if C.unitframes.los_indicator == "1" then
    local los = CreateIndicator("pfLoSIndicator", -third, 0.2, function(text)
      -- nil without a target
      text:SetShown(UnitInLineOfSight("target") == false)
    end)
    los.text:SetTextColor(1, 0.3, 0.3, 1)
    los.text:SetText(T["NO LOS"])
  end

  -- UnitXP_SP3 is the only source of facing
  if C.unitframes.behind_indicator == "1" and _G.UnitXP then
    local behind = CreateIndicator("pfBehindIndicator", 0, 0.1, function(text)
      local success, isBehind = pcall(UnitXP, "behind", "player", "target")
      text:SetShown(success and isBehind)
    end)
    behind.text:SetTextColor(0.3, 1, 0.3, 1)
    behind.text:SetText(T["BEHIND"])
  end

  -- [ target distance ]
  -- Center-to-center yards from ClassicAPI, colored by range band. Shown on
  -- the target frame, or in a movable frame of its own.
  if C.unitframes.distance_indicator == "1" then
    local suffix = C.unitframes.hide_distance_yd == "1" and "" or T[" yd"]
    local bands = {
      {  5, 0.3, 0.5, 1.0 },  -- melee (blue)
      {  8, 0.4, 0.7, 1.0 },  -- close (light blue)
      { 20, 0.4, 0.9, 1.0 },  -- short range (sky blue)
      { 30, 0.0, 1.0, 0.0 },  -- mid range (green)
      { 35, 0.8, 1.0, 0.0 },  -- yellow-green
      { 41, 1.0, 1.0, 0.0 },  -- yellow
    }

    -- returns whether the target has a known position
    local function UpdateDistance(text)
      local distSq, checked = UnitDistanceSquared("target")
      if not checked then return false end

      local distance = math.sqrt(distSq)
      local r, g, b = 1.0, 0.2, 0.2
      for _, band in ipairs(bands) do
        if distance <= band[1] then
          r, g, b = band[2], band[3], band[4]
          break
        end
      end
      text:SetTextColor(r, g, b, 1)
      text:SetFormattedText("%.1f%s", distance, suffix)
      return true
    end

    if C.unitframes.distance_hook_portrait == "1" then
      CreateIndicator("pfDistanceIndicator", third, 0.1, function(text)
        text:SetShown(UpdateDistance(text))
      end)
    else
      local f = CreateFrame("Frame", "pfRangeDisplay", UIParent)
      f:SetWidth(90)
      f:SetHeight(20)
      f:SetFrameStrata("MEDIUM")
      f:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
      CreateBackdrop(f, nil, true)
      CreateBackdropShadow(f)
      UpdateMovable(f)

      f.text = f:CreateFontString(nil, "OVERLAY")
      f.text:SetFont(pfUI.font_default, C.global.font_size + 2, "OUTLINE")
      f.text:SetPoint("CENTER", f, "CENTER")

      local lastCheck = 0
      f:SetScript("OnUpdate", function()
        if GetTime() - lastCheck < 0.05 then return end
        lastCheck = GetTime()
        if not UpdateDistance(this.text) then
          this.text:SetTextColor(1, 1, 1, 1)
          this.text:SetText("--")
        end
        this.text:SetAlpha(UnitInLineOfSight("target") == false and 0.5 or 1.0)
      end)

      local function UpdateShown() f:SetShown(UnitExists("target")) end
      pfUI.events:RegisterFrameEventAndCallback("PLAYER_TARGET_CHANGED", UpdateShown)
      UpdateShown()
    end
  end
end)
