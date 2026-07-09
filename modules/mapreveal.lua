pfUI:RegisterModule("mapreveal", function ()
  if Cartographer then return end
  if METAMAP_TITLE then return end

  pfUI.mapreveal = {}
  function pfUI.mapreveal:UpdateConfig()
    WorldMapFrame_Update()
  end

  pfUI.mapreveal.onmap = CreateFrame("CheckButton", "pfUI_mapreveal_onmap", WorldMapFrame, "UICheckButtonTemplate")
  pfUI.mapreveal.onmap:SetNormalTexture("")
  pfUI.mapreveal.onmap:SetPushedTexture("")
  pfUI.mapreveal.onmap:SetHighlightTexture("")
  pfUI.mapreveal.onmap.text = _G["pfUI_mapreveal_onmapText"]
  CreateBackdrop(pfUI.mapreveal.onmap, nil, true)
  pfUI.mapreveal.onmap:SetWidth(14)
  pfUI.mapreveal.onmap:SetHeight(14)
  pfUI.mapreveal.onmap:SetPoint("LEFT", WorldMapZoomOutButton, "RIGHT", 20, 0)
  pfUI.mapreveal.onmap.text:SetPoint("LEFT", pfUI.mapreveal.onmap, "RIGHT", 2, 0)
  pfUI.mapreveal.onmap.text:SetText(T["Reveal Unexplored Areas"])
  pfUI.mapreveal.onmap:SetScript("OnShow", function()
    this:SetChecked(C.appearance.worldmap.mapreveal == "1")
  end)
  pfUI.mapreveal.onmap:SetScript("OnClick", function ()
    if this:GetChecked() then
      C.appearance.worldmap.mapreveal = "1"
    else
      C.appearance.worldmap.mapreveal = "0"
    end
    pfUI.mapreveal:UpdateConfig()
  end)

  local explores = {}
  local explorecaches = {}
  local alreadyknown = {} -- per-zone accumulator: { [zone] = { [texName] = true } }

  -- Own texture pool - separate from Blizzard's WorldMapOverlay textures
  local pfOverlays = {}
  local pfOverlayMax = 0

  local function pfGetOverlay(idx)
    if not pfOverlays[idx] then
      pfOverlays[idx] = WorldMapDetailFrame:CreateTexture("pfReveal"..idx, "BORDER")
    end
    return pfOverlays[idx]
  end

  local exploreEnter = function()
    WorldMapTooltip:ClearLines()
    WorldMapTooltip:SetOwner(this, "ANCHOR_TOP")
    WorldMapTooltip:AddLine(T["Exploration Point"]..":", .3, 1, .8)
    WorldMapTooltip:AddLine(this.name, 1, 1, 1)
    WorldMapTooltip:Show()

    if not explorecaches[this.name] then return end
    if C.appearance.worldmap.mapreveal == "0" then return end
    for texture in pairs(explorecaches[this.name]) do
      texture:SetVertexColor(1,1,1,1)
    end
  end

  local exploreLeave = function()
    WorldMapTooltip:Hide()
    if not explorecaches[this.name] then return end
    if C.appearance.worldmap.mapreveal == "0" then return end
    local r,g,b,a = GetStringColor(C.appearance.worldmap.mapreveal_color)
    for texture in pairs(explorecaches[this.name]) do
      texture:SetVertexColor(r,g,b,a)
    end
  end

  local function pfWorldMapFrame_Update()
    -- clear stale caches
    for k in pairs(explorecaches) do explorecaches[k] = nil end

    -- hide all our textures from last frame
    for i = 1, pfOverlayMax do
      pfOverlays[i]:Hide()
    end

    local r,g,b,a = GetStringColor(C.appearance.worldmap.mapreveal_color)
    local mapFileName = GetMapInfo()
    if not mapFileName then mapFileName = "World" end

    local numOverlays = GetNumMapOverlays()

    -- accumulate explored overlays per zone (never clear, only add)
    if not alreadyknown[mapFileName] then alreadyknown[mapFileName] = {} end
    for i = 1, numOverlays do
      local texName = GetMapOverlayInfo(i)
      if texName then alreadyknown[mapFileName][string.upper(texName)] = true end
    end

    local zoneKnown = alreadyknown[mapFileName]

    -- hide explore icons
    for _, frame in pairs(explores) do frame:Hide() end

    -- ClassicAPI: full overlay list for the viewed zone (explored + unexplored),
    -- read straight from WorldMapOverlay.dbc. Replaces the hand-measured pfMapOverlayData.
    local zoneData = C_Map.GetMapOverlays() or {}
    local textureCount = 0

    for i, overlay in ipairs(zoneData) do
      local name          = overlay.textureName   -- bare, e.g. "DRYGULCHRAVINE"
      local textureName   = overlay.texturePath   -- full engine path (for SetTexture)
      local textureWidth  = overlay.textureWidth
      local textureHeight = overlay.textureHeight
      local offsetX       = overlay.offsetX
      local offsetY       = overlay.offsetY

      -- explore magnifying glass icon
      explores[i] = explores[i] or CreateFrame("Frame", nil, WorldMapDetailFrame)
      local explore = explores[i]
      explore:SetWidth(16)
      explore:SetHeight(16)
      explore:SetPoint("TOPLEFT", "WorldMapDetailFrame", "TOPLEFT", offsetX + textureWidth/2, -offsetY - textureHeight/2)
      explore:SetScript("OnEnter", exploreEnter)
      explore:SetScript("OnLeave", exploreLeave)
      explore:EnableMouse(true)
      explore:SetFrameLevel(255)
      explore.name = mapFileName .. " (" .. name .. ")"
      explore.tex = explore.tex or explore:CreateTexture("", "OVERLAY")
      explore.tex:SetBlendMode("ADD")
      explore.tex:SetTexCoord(.08, .92, .08, .92)
      explore.tex:SetAllPoints()

      -- `alreadyknown` stores the FULL paths GetMapOverlayInfo returns,
      -- so compare with the full path, not the bare name.
      if C.appearance.worldmap.mapexploration == "1" and not zoneKnown[string.upper(textureName)] then
        explore.tex:SetTexture("Interface\\WorldMap\\WorldMap-MagnifyingGlass")
        explore:Show()
      else
        explore:Hide()
      end

      -- render overlay texture tiles on BORDER draw layer
      -- Blizzard's explored overlays on ARTWORK draw on top of BORDER
      --
      -- overlay.tiles is pre-resolved by ClassicAPI: per-tile file /
      -- draw size / texcoords / canvas position, with Octo's data
      -- quirks (sliver columns the DBC rect rounds away, foreign tiles
      -- appended to the number sequence, upscaled re-exports) already
      -- disambiguated from the actual BLP dimensions. No 256px grid
      -- math here — deriving the grid from textureWidth/Height is
      -- exactly what shears quirky overlays (e.g. Icepoint's Kaneq'nuun).
      if C.appearance.worldmap.mapreveal == "1" then
        for _, tile in ipairs(overlay.tiles) do
          textureCount = textureCount + 1
          local tex = pfGetOverlay(textureCount)

          tex:SetWidth(tile.width)
          tex:SetHeight(tile.height)
          tex:SetTexCoord(0, tile.texCoordX, 0, tile.texCoordY)
          tex:ClearAllPoints()
          tex:SetPoint("TOPLEFT", "WorldMapDetailFrame", "TOPLEFT", tile.offsetX, -tile.offsetY)
          tex:SetTexture(tile.file)

          explorecaches[name] = explorecaches[name] or {}
          explorecaches[name][tex] = true

          tex:SetVertexColor(r,g,b,a)
          tex:Show()
        end
      end
    end

    pfOverlayMax = math.max(pfOverlayMax, textureCount)
  end

  -- hook WorldMapFrame_Update
  local origUpdate = _G.WorldMapFrame_Update
  _G.WorldMapFrame_Update = function(...)
    origUpdate(unpack(arg))
    pfWorldMapFrame_Update()
  end

end)