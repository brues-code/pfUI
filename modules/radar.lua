pfUI:RegisterModule("radar", function ()
  -- DBM-style range radar: the group around you, turned so that your facing
  -- points up. ClassicAPI's UnitPosition reads every visible unit.
  local SIZE = 150
  local RADIUS = SIZE / 2
  -- the range ring sits at two thirds of the radius, so the radar shows half
  -- a range past it
  local RING = RADIUS / 1.5
  local RANGES = { 5, 8, 10, 15, 20, 25, 30, 40 }
  -- about one storey; see Locate for what counts as another floor
  local FLOOR = 5
  -- alpha of units out of sight
  local DIM = .3
  -- the nearest members inside the range, listed under the radar
  local LINES = 5
  local LINE_HEIGHT = C.global.font_size + 4

  local _, border = GetBorderSize()
  local abs, sqrt = math.abs, math.sqrt
  local UnitPosition = ClassicAPI.UnitPosition

  local radar = CreateFrame("Frame", "pfRadar", UIParent)
  radar:SetSize(SIZE, SIZE)
  radar:SetPoint("CENTER", 350, 100)
  radar:SetFrameStrata("MEDIUM")
  radar:EnableMouse(true)
  radar:EnableMouseWheel(true)
  radar:Hide()
  CreateBackdrop(radar)
  CreateBackdropShadow(radar)
  UpdateMovable(radar)

  -- the range ring: a disc in the ring color under a 2px smaller disc in the
  -- background color, which lets a little of the tint through
  local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
  radar.ring = radar:CreateTexture(nil, "BACKGROUND")
  radar.ring:SetTexture(DISC)
  radar.ring:SetSize(RING * 2 + 2, RING * 2 + 2)
  radar.ring:SetPoint("CENTER", 0, 0)

  radar.zone = radar:CreateTexture(nil, "BORDER")
  radar.zone:SetTexture(DISC)
  radar.zone:SetSize(RING * 2 - 2, RING * 2 - 2)
  radar.zone:SetPoint("CENTER", 0, 0)
  local r, g, b = GetStringColor(C.appearance.border.background)
  radar.zone:SetVertexColor(r, g, b, .85)

  radar.player = radar:CreateTexture(nil, "OVERLAY")
  radar.player:SetAtlas("MinimapArrow")
  radar.player:SetSize(24, 24)
  radar.player:SetPoint("CENTER", 0, 0)

  radar.title = radar:CreateFontString(nil, "OVERLAY")
  radar.title:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
  radar.title:SetPoint("TOPLEFT", 4, -4)

  radar.count = radar:CreateFontString(nil, "OVERLAY")
  radar.count:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
  radar.count:SetPoint("TOPRIGHT", -4, -4)
  radar.count:SetTextColor(1, .2, .2)

  radar.names = CreateFrame("Frame", nil, radar)
  radar.names:SetPoint("TOPLEFT", radar, "BOTTOMLEFT", 0, -border * 3)
  radar.names:SetPoint("TOPRIGHT", radar, "BOTTOMRIGHT", 0, -border * 3)
  radar.names:Hide()
  CreateBackdrop(radar.names)
  CreateBackdropShadow(radar.names)

  local range, scale

  local function SetRange(yards)
    range = yards
    scale = RING / yards
    C.radar.range = tostring(yards)
    radar.title:SetText(T["Radar"] .. " (" .. yards .. " yd)")
  end
  SetRange(tonumber(C.radar.range))

  local function IsRange(yards)
    return yards == range
  end

  local function GenerateMenu(owner, rootDescription)
    rootDescription:CreateTitle(T["Radar"])
    for _, yards in ipairs(RANGES) do
      rootDescription:CreateRadio(yards .. " yd", IsRange, SetRange, yards)
    end
    CreateMenuDivider(rootDescription)
    rootDescription:CreateButton(HIDE, function() radar:Hide() end)
  end

  radar.menuMixin = pfUIMenuStyleMixin
  local function OpenMenu()
    MenuUtil.CreateContextMenu(radar, GenerateMenu)
  end

  -- blips and list rows: left click targets, right click opens the menu
  local function TargetOrMenu()
    if arg1 == "RightButton" then
      OpenMenu()
    else
      TargetUnit(this.unit)
    end
  end

  -- unit -> true while terrain blocks the line of sight
  local blocked = {}
  local hovered

  local function ShowTooltip(blip)
    local unit = blip.unit
    GameTooltip:SetOwner(blip, "ANCHOR_RIGHT")
    if UnitIsPlayer(unit) then
      GameTooltip:SetText(UnitName(unit), PFUI_CLASS_COLORS[UnitClassBase(unit)]:GetRGB())
    else
      GameTooltip:SetText(UnitName(unit), UnitSelectionColor(unit))
    end
    GameTooltip:AddLine(format("%.1f yd", sqrt(blip.distSq)), 1, 1, 1)
    if blocked[unit] then
      GameTooltip:AddLine(T["Out of line of sight"], 1, .3, .3)
    end
    if blip.level then
      GameTooltip:AddLine(blip.level > 0 and T["Above you"] or T["Below you"], .6, .6, .6)
    end
    GameTooltip:Show()
  end

  -- a unit on the radar: hover for its tooltip, click to target it
  local function CreateBlip(size, layer)
    local blip = CreateFrame("Button", nil, radar)
    blip:SetSize(size, size)
    blip:SetFrameLevel(radar:GetFrameLevel() + layer)
    blip:SetHitRectInsets(-2, -2, -2, -2)
    blip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    blip:Hide()

    blip.icon = blip:CreateTexture(nil, "ARTWORK")
    blip.icon:SetAllPoints(blip)

    -- sits above or below a unit on another floor; the triangle fills the
    -- middle half of img\up and img\down
    blip.arrow = blip:CreateTexture(nil, "OVERLAY")
    blip.arrow:SetSize(10, 5)

    blip:SetScript("OnClick", TargetOrMenu)
    blip:SetScript("OnEnter", function()
      hovered = this
      ShowTooltip(this)
    end)
    blip:SetScript("OnLeave", function()
      hovered = nil
      GameTooltip:Hide()
    end)
    return blip
  end

  local dots = {}
  local function GetDot(i)
    if not dots[i] then
      dots[i] = CreateBlip(8, 1)
      dots[i].icon:SetTexture(pfUI.media["img:circleraid"])
    end
    return dots[i]
  end

  -- above the dots
  local markers = {}
  for i = 1, 8 do
    markers[i] = CreateBlip(14, 2)
    markers[i].icon:SetAtlas("UI-RaidTargetingIcon_" .. i)
  end

  local rows = {}
  for i = 1, LINES do
    local row = CreateFrame("Button", nil, radar.names)
    row:SetPoint("TOPLEFT", 4, -2 - (i - 1) * LINE_HEIGHT)
    row:SetPoint("TOPRIGHT", -4, -2 - (i - 1) * LINE_HEIGHT)
    row:SetHeight(LINE_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", TargetOrMenu)

    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
    row.name:SetPoint("LEFT", 0, 0)
    row.dist = row:CreateFontString(nil, "OVERLAY")
    row.dist:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
    row.dist:SetPoint("RIGHT", 0, 0)
    rows[i] = row
  end

  -- the LINES nearest members inside the range, nearest first
  local nearUnit, nearDistSq = {}, {}
  local function AddNear(listed, unit, distSq)
    if listed == LINES and distSq >= nearDistSq[LINES] then return listed end
    local i = listed < LINES and listed + 1 or LINES
    while i > 1 and nearDistSq[i - 1] > distSq do
      nearUnit[i], nearDistSq[i] = nearUnit[i - 1], nearDistSq[i - 1]
      i = i - 1
    end
    nearUnit[i], nearDistSq[i] = unit, distSq
    return listed < LINES and listed + 1 or LINES
  end

  -- the player's position and facing, read once per refresh
  local py, px, pz, facing

  -- where a unit shows on the radar in pixels, its squared distance, and 1
  -- or -1 on a floor above or below you. nil past the edge. The world turns
  -- clockwise by the facing, so ahead is up.
  local function Locate(unit)
    if not py or not facing then return end
    if UnitIsUnit(unit, "player") or UnitIsDeadOrGhost(unit) then return end

    local uy, ux, uz = UnitPosition(unit)
    if not uy then return end

    local west, north, up = uy - py, ux - px, uz - pz
    local x, y = Vector2D_RotateDirection(-facing, -west, north)
    x, y = x * scale, y * scale
    if abs(x) >= RADIUS or abs(y) >= RADIUS then return end

    -- another floor is a storey up or down and steeper than 45 degrees, which
    -- no walkable slope is, so units up a hill don't count
    local level
    if abs(up) > FLOOR and up * up > west * west + north * north then
      level = up > 0 and 1 or -1
    end
    return x, y, Vector3D_GetLengthSquared(west, north, up), level
  end

  local function Place(blip, unit, x, y, distSq, level, checkLoS)
    if checkLoS then blocked[unit] = UnitInLineOfSight(unit) == false end
    blip.unit, blip.distSq, blip.level = unit, distSq, level
    blip:SetPoint("CENTER", x, y)
    blip:SetAlpha(blocked[unit] and DIM or 1)
    if level then
      blip.arrow:SetTexture(pfUI.media[level > 0 and "img:up" or "img:down"])
      blip.arrow:SetTexCoord(0, 1, .25, .75)
      blip.arrow:ClearAllPoints()
      if level > 0 then
        blip.arrow:SetPoint("BOTTOM", blip, "TOP", 0, 1)
      else
        blip.arrow:SetPoint("TOP", blip, "BOTTOM", 0, -1)
      end
    end
    blip.arrow:SetShown(level ~= nil)
    blip:Show()
  end

  function radar:Refresh(checkLoS)
    py, px, pz = UnitPosition("player")
    facing = GetPlayerFacing()
    local shown, inRange, listed = 0, 0, 0

    local raid = IsInRaid()
    local prefix = raid and "raid" or "party"
    for i = 1, raid and GetNumRaidMembers() or GetNumPartyMembers() do
      local unit = prefix .. i
      local x, y, distSq, level = Locate(unit)
      if x then
        -- inside the range always means inside the radar
        if distSq <= range * range then
          inRange = inRange + 1
          listed = AddNear(listed, unit, distSq)
        end

        -- a marked member shows the marker instead of a dot
        if not GetRaidTargetIndex(unit) then
          shown = shown + 1
          local dot = GetDot(shown)
          dot.icon:SetVertexColor(PFUI_CLASS_COLORS[UnitClassBase(unit)]:GetRGB())
          Place(dot, unit, x, y, distSq, level, checkLoS)
        end
      end
    end

    for i = shown + 1, #dots do dots[i]:Hide() end

    -- markN resolves to whatever unit wears marker N, mobs included
    for i = 1, 8 do
      local unit = "mark" .. i
      local x, y, distSq, level = Locate(unit)
      if x then
        Place(markers[i], unit, x, y, distSq, level, checkLoS)
      else
        markers[i]:Hide()
      end
    end

    for i = 1, LINES do
      local row = rows[i]
      if i <= listed then
        local unit = nearUnit[i]
        local marker = GetRaidTargetIndex(unit)
        local name = UnitName(unit)
        if marker then
          -- the markup's own tint is white, so the text color leaves it alone
          name = name .. " " .. CreateAtlasMarkup("UI-RaidTargetingIcon_" .. marker, 14, 14)
        end
        row.name:SetText(name)
        row.name:SetTextColor(PFUI_CLASS_COLORS[UnitClassBase(unit)]:GetRGB())
        row.dist:SetFormattedText("%.1f", sqrt(nearDistSq[i]))
        row.unit = unit
      end
      row:SetShown(i <= listed)
    end
    self.names:SetHeight(listed * LINE_HEIGHT + 4)
    self.names:SetShown(listed > 0)

    if inRange > 0 then
      self.ring:SetVertexColor(1, .2, .2)
      self.count:SetText(inRange)
    else
      self.ring:SetVertexColor(.2, 1, .2)
      self.count:SetText("")
    end

    -- keep the hovered tooltip's distance current
    if hovered then
      if hovered:IsShown() then
        ShowTooltip(hovered)
      else
        hovered = nil
        GameTooltip:Hide()
      end
    end
  end

  -- line of sight traces run at a slower rate than the positions
  local throttle, losThrottle = 0, 1
  radar:SetScript("OnUpdate", function()
    throttle = throttle + arg1
    losThrottle = losThrottle + arg1
    if throttle < .05 then return end
    throttle = 0

    local checkLoS = losThrottle >= .25
    if checkLoS then losThrottle = 0 end
    this:Refresh(checkLoS)
  end)

  radar:SetScript("OnMouseUp", function()
    if arg1 == "RightButton" then OpenMenu() end
  end)

  -- the wheel steps through the ranges, up zooms in
  radar:SetScript("OnMouseWheel", function()
    local yards = range
    if arg1 > 0 then
      for i = #RANGES, 1, -1 do
        if RANGES[i] < range then yards = RANGES[i] break end
      end
    else
      for i = 1, #RANGES do
        if RANGES[i] > range then yards = RANGES[i] break end
      end
    end
    SetRange(yards)
  end)

  -- /radar toggles, /radar <yards> sets the range and shows
  pfUI.api.RegisterSlashCommand("PFRADAR", { "/radar", "/pfradar" }, function(msg)
    local yards = tonumber(msg)
    if yards and yards > 0 then
      SetRange(yards)
      radar:Show()
    else
      radar:SetShown(not radar:IsShown())
    end
  end)

  pfUI.radar = radar
end)
