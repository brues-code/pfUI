pfUI:RegisterModule("player", function ()
  -- do not go further on disabled UFs
  if C.unitframes.disable == "1" then return end

  PlayerFrame:Hide()
  PlayerFrame:UnregisterAllEvents()

  pfUI.uf.player = pfUI.uf:CreateUnitFrame("Player", nil, C.unitframes.player)

  pfUI.uf.player:UpdateFrameSize()
  pfUI.uf.player:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOM", -75, 125)
  UpdateMovable(pfUI.uf.player)

  -- infoTopCenterText: used to display haste / spell power above health bar
  local playerFrame = pfUI.uf.player
  if not playerFrame.infoTopCenterText then
    playerFrame.infoTopCenterText = playerFrame.texts:CreateFontString(nil, "OVERLAY")
    playerFrame.infoTopCenterText:SetFontObject(GameFontWhite)
    local cfg = playerFrame.config
    local fontname, fontsize, fontstyle
    if cfg.customfont == "1" then
      fontname = pfUI.media[cfg.customfont_name]
      fontsize = tonumber(cfg.customfont_size)
      fontstyle = cfg.customfont_style
    else
      fontname = pfUI.font_unit
      fontsize = tonumber(C.global.font_unit_size)
      fontstyle = C.global.font_unit_style
    end
    playerFrame.infoTopCenterText:SetFont(fontname, fontsize, fontstyle)
    playerFrame.infoTopCenterText:SetJustifyH("CENTER")
    playerFrame.infoTopCenterText:SetPoint("TOPLEFT", playerFrame.hp.bar, "TOPLEFT", 0, 0)
    playerFrame.infoTopCenterText:SetPoint("TOPRIGHT", playerFrame.hp.bar, "TOPRIGHT", 0, 0)
    playerFrame.infoTopCenterText:SetHeight(14)
  end

  local myclass = UnitClassBase("player")
  playerFrame.myclass = myclass
  playerFrame.isSpellCaster = myclass ~= "WARRIOR" and myclass ~= "ROGUE" and myclass ~= "HUNTER"

  -- Convert "r,g,b,a" config color string to a 6-char hex string, or nil if unset
  local cfgColorToHexTable = setmetatable({}, {
    __index = function (t, colorStr)
      if not colorStr or colorStr == "" then return nil end
      local r, g, b = GetStringColor(colorStr)
      if not r or not g or not b then return nil end
      local hex = C_ColorUtil.GenerateTextColorCode({ r=r, g = g, b=b})
      rawset(t, colorStr, hex)
      return hex
    end
  })

  -- SP school colors indexed by GetSpellBonusDamage's 1-based school order
  -- (1=phys, 2=holy, 3=fire, 4=nature, 5=frost, 6=shadow, 7=arcane)
  local spColors = { "FFFFFFFF", "FFFFFF80", "FFFF8000", "FF4DFF4D", "FF80FFFF", "FF9482C9", "FFFFFFFF" }

  -- Default SP school per class used as tiebreaker when multiple schools are equal
  local spDefaultSchool = {
    PALADIN = 2, PRIEST  = 2,
    SHAMAN  = 4, DRUID   = 4,
    MAGE    = 7, WARLOCK = 6,
  }

  -- Compute and cache the haste/SP text; called from OnUpdate, throttled to 0.25s
  local function UpdateInfoText()
    local cfg = playerFrame.config
    if not cfg then
      return
    end
    -- display_haste: "0"=hidden, "1"=show cast-speed haste (UnitSpellHaste,
    -- from UNIT_MOD_CAST_SPEED). Talent/spell-specific cast-time reductions
    -- show up in the actual cast bar via C_Spell.UnitCastingInfo; folding them
    -- in here too was mixing two different concepts into one number.
    local isSpellCaster = playerFrame.isSpellCaster
    local showHaste = isSpellCaster and cfg.display_haste == "1"
    local showSP    = isSpellCaster and cfg.display_spellpower == "1"

    if not showHaste and not showSP then
      playerFrame.infoTopCenterText:SetText("")
      return
    end

    local parts = {}

    if showHaste then
      local hex = cfgColorToHexTable[cfg.display_haste_color] or "FFFFFFFF"
      table.insert(parts, string.format("|c%s%.1f%%|r", hex, UnitSpellHaste("player")))
    end

    if showSP then
      local school = spDefaultSchool[myclass] or 2
      local maxSP = GetSpellBonusDamage(school) or 0
      for i = 2, 7 do  -- skip physical (1)
        local v = GetSpellBonusDamage(i) or 0
        if v > maxSP then maxSP, school = v, i end
      end

      if maxSP > 0 then
        local hex = (cfg.display_sp_color_override == "1" and cfgColorToHexTable[cfg.display_sp_color]) or spColors[school]
        table.insert(parts, string.format("|c%s+%d SP|r", hex, maxSP))
      end
    end

    playerFrame.infoTopCenterText:SetText(table.concat(parts, "    "))
  end

  -- Keep a reference to the generic UF UpdateConfig so we can chain it
  local genericUpdateConfig = pfUI.uf.UpdateConfig

  function playerFrame:UpdateConfig()
    genericUpdateConfig(self)
    UpdateInfoText()
  end

  -- Add throttle to player frame OnUpdate
  -- Throttle the unit frame's existing OnUpdate to ~20 FPS so the per-frame
  -- work stays cheap.
  if pfUI.uf.player:GetScript("OnUpdate") then
    local originalOnUpdate = pfUI.uf.player:GetScript("OnUpdate")
    pfUI.uf.player:SetScript("OnUpdate", function()
      if (this.throttleTick or 0) > GetTime() then return end
      this.throttleTick = GetTime() + 0.05
      originalOnUpdate()
    end)
  end

  -- Haste / spell-power overlay text — refreshes 4×/sec on its own ticker,
  -- independent of the unit frame's OnUpdate cadence.
  C_Timer.NewTicker(0.25, UpdateInfoText)

  -- Replace default's RESET_INSTANCES button with an always working one
  UnitPopupButtons["RESET_INSTANCES_FIX"] = { text = RESET_INSTANCES, dist = 0 }
  for id, text in pairs(UnitPopupMenus["SELF"]) do
    if text == "RESET_INSTANCES" then
      UnitPopupMenus["SELF"][id] = "RESET_INSTANCES_FIX"
    end
  end

  hooksecurefunc("UnitPopup_OnClick", function()
    local button = this.value
    if button == "RESET_INSTANCES_FIX" then
      StaticPopup_Show("CONFIRM_RESET_INSTANCES")
    end
  end)
end)
