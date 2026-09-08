pfUI:RegisterModule("marktracking", function ()
  local rawborder, border = GetBorderSize()

  local markerOrder = { 8, 7, 6, 5, 4, 3, 2, 1 } -- skull, cross, square, moon, triangle, diamond, circle, star
  local markerTokens = {}  -- [i] = "markN"
  local markerIndex = {}   -- ["markN"] = i, for the event handler's arg1

  local markerConfigKeys = {
    "raidmarkercolor_star",
    "raidmarkercolor_circle",
    "raidmarkercolor_diamond",
    "raidmarkercolor_triangle",
    "raidmarkercolor_moon",
    "raidmarkercolor_square",
    "raidmarkercolor_cross",
    "raidmarkercolor_skull",
  }

  local markerColors = {}
  for i, markKey in ipairs(markerConfigKeys) do
    markerTokens[i] = "mark" .. i
    markerIndex[markerTokens[i]] = i
    local r, g, b, a = GetStringColor(C.unitframes[markKey])
    markerColors[i] = { tonumber(r), tonumber(g), tonumber(b), tonumber(a) }
  end

  local FALLBACK_INTERVAL = 1.0  -- safety net for units that come into range after marker was set
  local isUnlocked = false
  local ROW_HEIGHT = tonumber(C.unitframes.raidmarkerheight) or 14
  local BAR_WIDTH = tonumber(C.unitframes.raidmarkerwidth) or 80
  local GROW = C.unitframes.raidmarkergrow or "down"
  local rm_texture = C.unitframes.raidmarkertexture or "Interface\\AddOns\\pfUI\\img\\bar"
  local rm_fontsize = tonumber(C.unitframes.raidmarkerfontsize) or 12
  local rm_showpct = C.unitframes.raidmarkershowpct ~= "0"
  local rm_showname = C.unitframes.raidmarkershowname ~= "0"
  local rm_showportrait = C.unitframes.raidmarkershowportrait ~= "0"
  local PORTRAIT_SIZE = ROW_HEIGHT

  -- Cache for shortened names: markerIndex -> { name, short }
  local nameCache = {}

  local function ShortenName(name, row)
    if not name or name == "" then return "" end
    local barWidth = row.health:GetWidth()
    if barWidth < 1 then barWidth = BAR_WIDTH end
    local available = barWidth - 4
    if rm_showpct then available = available - 32 end
    if available < 10 then return nil end
    row.nametext:SetText(name)
    if row.nametext:GetStringWidth() <= available then return name end
    for len = strlen(name) - 1, 1, -1 do
      local short = strsub(name, 1, len) .. "."
      row.nametext:SetText(short)
      if row.nametext:GetStringWidth() <= available then return short end
    end
    return strsub(name, 1, 1) .. "."
  end

  local TOTAL_ROW_WIDTH = BAR_WIDTH + 20 + (rm_showportrait and (PORTRAIT_SIZE + 2) or 0)

  -- Container frame
    -- Migrate position from old frame name (RaidMarkers -> MarkTracking)
  if C.position and C.position["pfMarkerTracker"] and not C.position["pfMarkTracking"] then
    C.position["pfMarkTracking"] = C.position["pfMarkerTracker"]
  end

pfUI.marktracking = CreateFrame("Frame", "pfMarkTracking", UIParent)
  pfUI.marktracking:SetFrameStrata("MEDIUM")
  if GROW == "up" then
    pfUI.marktracking:SetPoint("BOTTOM", UIParent, "CENTER", 0, 0)
  else
    pfUI.marktracking:SetPoint("TOP", UIParent, "CENTER", 0, 0)
  end
  pfUI.marktracking:SetSize(TOTAL_ROW_WIDTH, 8 * (ROW_HEIGHT + 1) + border * 2 - 1)
  pfUI.marktracking:Hide()

  CreateBackdrop(pfUI.marktracking)
  CreateBackdropShadow(pfUI.marktracking)
  UpdateMovable(pfUI.marktracking)

  pfUI.marktracking:SetScript("OnMouseUp", function()
    if pfUI.unlock and pfUI.unlock:IsShown() then
      this:StopMovingOrSizing()
      local _, _, _, x, y = this:GetPoint()
      this:ClearAllPoints()
      this:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", math.floor(x + 0.5), math.floor(y + 0.5))
      C.position["pfMarkTracking"] = C.position["pfMarkTracking"] or {}
      C.position["pfMarkTracking"]["anchor"] = "BOTTOMRIGHT"
      C.position["pfMarkTracking"]["xpos"] = math.floor(x + 0.5)
      C.position["pfMarkTracking"]["ypos"] = math.floor(y + 0.5)
    end
  end)

  -- Create 8 marker rows
  pfUI.marktracking.rows = {}
  for idx = 1, 8 do
    local i = markerOrder[idx]

    local row = CreateFrame("Button", nil, pfUI.marktracking)
    row:SetSize(TOTAL_ROW_WIDTH, ROW_HEIGHT)
    row:Hide()

    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetAttribute("type1", "target")
    row:SetAttribute("type2", "menu")

    -- raid icon
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_HEIGHT, ROW_HEIGHT)
    row.icon:SetPoint("LEFT", row, "LEFT", 1, 0)
    local markTex = C.unitframes.blizzard_raidicons == "1" and "Interface\\TargetingFrame\\UI-RaidTargetingIcons" or pfUI.media["img:raidicons"]
    row.icon:SetTexture(markTex)
    SetRaidTargetIconTexture(row.icon, i)

    -- portrait (right side)
    row.portrait = row:CreateTexture(nil, "ARTWORK")
    row.portrait:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
    row.portrait:SetPoint("RIGHT", row, "RIGHT", -1, 0)
    row.portrait:SetTexCoord(.1, .9, .1, .9)
    if not rm_showportrait then row.portrait:Hide() end

    -- health bar
    row.health = CreateFrame("StatusBar", nil, row)
    row.health:SetPoint("LEFT", row.icon, "RIGHT", 2, 0)
    if rm_showportrait then
      row.health:SetPoint("RIGHT", row.portrait, "LEFT", -2, 0)
    else
      row.health:SetPoint("RIGHT", row, "RIGHT", -1, 0)
    end
    row.health:SetHeight(ROW_HEIGHT)
    row.health:SetMinMaxValues(0, 1)
    row.health:SetValue(1)
    row.health:SetStatusBarTexture(rm_texture)
    local c = markerColors[i]
    row.health:SetStatusBarColor(c[1] * 0.5, c[2] * 0.5, c[3] * 0.5, c[4] or 0.9)

    -- name text (left)
    row.nametext = row.health:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nametext:SetPoint("LEFT", row.health, "LEFT", 2, 0)
    row.nametext:SetFont(pfUI.font_default, rm_fontsize, "OUTLINE")
    row.nametext:SetTextColor(1, 1, 1, 1)
    row.nametext:SetJustifyH("LEFT")
    row.nametext:SetText("")
    if not rm_showname then row.nametext:Hide() end

    -- hp text (right)
    row.hptext = row.health:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.hptext:SetPoint("RIGHT", row.health, "RIGHT", -2, 0)
    row.hptext:SetFont(pfUI.font_default, rm_fontsize, "OUTLINE")
    row.hptext:SetTextColor(1, 1, 1, 1)
    row.hptext:SetJustifyH("RIGHT")
    row.hptext:SetText("")
    if not rm_showpct then row.hptext:Hide() end

    CreateBackdrop(row.health)

    row.markerIndex = i
    row.label = "mark"  -- enables /pfcast mouseover support via GetMouseFocus()
    row.id = i
    pfUI.marktracking.rows[i] = row
  end

  local function UpdateDisplay()
    if isUnlocked then return end
    local anyActive = false
    local visibleCount = 0
    local prevRow

    for idx = 1, 8 do
      local i = markerOrder[idx]
      local row = pfUI.marktracking.rows[i]
      local token = markerTokens[i]

      if UnitExists(token) and not UnitIsDead(token) then
        local hp, maxhp = UnitHealth(token), UnitHealthMax(token)
        row:SetAttribute('unit', token)

        if hp and maxhp and maxhp > 0 and hp > 0 then
          local pct = hp / maxhp
          row.health:SetValue(pct)

          if rm_showname then
            local name = UnitName(token)
            local cached = nameCache[i]
            if not cached or cached.name ~= name then
              local short = ShortenName(name, row)
              if short then
                nameCache[i] = { name = name, short = short }
              end
            end
            row.nametext:SetText(nameCache[i] and nameCache[i].short or "")
          end

          if rm_showpct then
            row.hptext:SetText(math.ceil(pct * 100) .. "%")
          end

          if rm_showportrait then
            SetPortraitTexture(row.portrait, token)
          end

          row:ClearAllPoints()
          if GROW == "up" then
            if prevRow then
              row:SetPoint("BOTTOM", prevRow, "TOP", 0, 1)
            else
              row:SetPoint("BOTTOM", pfUI.marktracking, "BOTTOM", 0, border)
            end
          else
            if prevRow then
              row:SetPoint("TOP", prevRow, "BOTTOM", 0, -1)
            else
              row:SetPoint("TOP", pfUI.marktracking, "TOP", 0, -border)
            end
          end
          row:Show()
          SetRaidTargetIconTexture(row.icon, i)
          prevRow = row
          anyActive = true
          visibleCount = visibleCount + 1
        else
          row:Hide()
        end
      else
        nameCache[i] = nil
        row:Hide()
      end
    end

    if anyActive then
      pfUI.marktracking:SetHeight(visibleCount * (ROW_HEIGHT + 1) + border * 2 - 1)
      pfUI.marktracking:Show()
    elseif not (pfUI.unlock and pfUI.unlock:IsShown()) then
      pfUI.marktracking:Hide()
    end
  end

  -- Fast per-row refresh for a single mark's UNIT_HEALTH/UNIT_MAXHEALTH: moves
  -- just the bar + hp text. If the mark's visibility flips (comes into range,
  -- dies, hp crosses 0) the visible rows re-pack, so hand off to UpdateDisplay.
  local function UpdateRow(i)
    if isUnlocked then return end
    local row = pfUI.marktracking.rows[i]
    if not row then return end
    local token = markerTokens[i]
    local hp, maxhp = UnitHealth(token), UnitHealthMax(token)
    local shouldShow = UnitExists(token) and not UnitIsDead(token)
                       and hp and maxhp and maxhp > 0 and hp > 0 and true or false
    if shouldShow ~= (row:IsShown() and true or false) then
      UpdateDisplay()
      return
    end
    if not shouldShow then return end
    local pct = hp / maxhp
    row.health:SetValue(pct)
    if rm_showpct then row.hptext:SetText(math.ceil(pct * 100) .. "%") end
  end

  -- Unlock mode: show fixed 1-row placeholder so positioning works correctly
  if pfUI.unlock then
    local origShow = pfUI.unlock:GetScript("OnShow")
    pfUI.unlock:SetScript("OnShow", function()
      if origShow then origShow() end
      isUnlocked = true
      -- hide all rows, show container at 1-row height as drag handle
      for i = 1, 8 do
        pfUI.marktracking.rows[i]:Hide()
      end
      pfUI.marktracking:SetHeight(ROW_HEIGHT + border * 2)
      pfUI.marktracking:Show()
    end)

    local origHide = pfUI.unlock:GetScript("OnHide")
    pfUI.unlock:SetScript("OnHide", function()
      if origHide then origHide() end
      isUnlocked = false
      UpdateDisplay()
    end)
  end

  -- Event-driven scanner frame
  local scanner = CreateFrame("Frame")

  -- Fallback poll: catches units that come into range AFTER a marker was set
  -- (no event fires for that case, so we need this safety net). UpdateDisplay
  -- is a full eight-row rebuild, so it exists only while grouped -- raid markers
  -- are a group feature and there is nothing to discover alone. The group events
  -- below start and cancel it, so outside a group there is no timer queued at
  -- all rather than one waking every second to return early.
  --
  -- Deliberately NOT keyed on a mark being visible: a marker set on a unit that
  -- is out of range shows no row, and that is exactly what this poll catches.
  local poll
  local function UpdatePoll()
    local grouped = IsInGroup()
    if grouped and not poll then
      poll = C_Timer.NewTicker(FALLBACK_INTERVAL, UpdateDisplay)
    elseif not grouped and poll then
      poll:Cancel()
      poll = nil
    end
  end

  -- RAID_TARGET_UPDATE: a raid marker was set/cleared -> full refresh
  -- PLAYER_ENTERING_WORLD: login/reload/zone -> full refresh
  -- PARTY_MEMBERS_CHANGED/RAID_ROSTER_UPDATE: joined or left a group -> the rows
  --   can change, and the fallback poll starts or stops with it
  -- UNIT_HEALTH/UNIT_MAXHEALTH: filtered to the eight mark tokens, so arg1 is
  --   always "markN" and we refresh just that row (UpdateRow) instead of
  --   rescanning all eight.
  scanner:RegisterEvent("RAID_TARGET_UPDATE")
  scanner:RegisterEvent("PLAYER_ENTERING_WORLD")
  scanner:RegisterEvent("PARTY_MEMBERS_CHANGED")
  scanner:RegisterEvent("RAID_ROSTER_UPDATE")
  scanner:RegisterUnitEvent("UNIT_HEALTH", "mark1", "mark2", "mark3", "mark4", "mark5", "mark6", "mark7", "mark8")
  scanner:RegisterUnitEvent("UNIT_MAXHEALTH", "mark1", "mark2", "mark3", "mark4", "mark5", "mark6", "mark7", "mark8")

  scanner:SetScript("OnEvent", function()
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
      -- arg1 is one of the eight tokens we registered for, so this is a lookup
      -- rather than a parse -- string.match would allocate a capture and
      -- tonumber would parse it, on every health tick of every marked unit.
      local i = arg1 and markerIndex[arg1]
      if i then UpdateRow(i) end
      return
    end
    if event ~= "RAID_TARGET_UPDATE" then UpdatePoll() end
    UpdateDisplay()
  end)
end)