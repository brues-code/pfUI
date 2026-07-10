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

  local _, myclass = UnitClass("player")
  playerFrame.myclass = myclass
  playerFrame.isSpellCaster = myclass ~= "WARRIOR" and myclass ~= "ROGUE" and myclass ~= "HUNTER"

  -- Convert "r,g,b,a" config color string to a 6-char hex string, or nil if unset
  local function cfgColorToHex(colorStr)
    if not colorStr or colorStr == "" then return nil end
    local r, g, b = strsplit(",", colorStr)
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if not r or not g or not b then return nil end
    return string.format("%02X%02X%02X", r * 255, g * 255, b * 255)
  end

  -- SP school colors indexed by GetSpellPower("net") return order
  -- (1=phys, 2=holy, 3=fire, 4=nature, 5=frost, 6=shadow, 7=arcane)
  local spColors = { "FFFFFF", "FFFF80", "FF8000", "4DFF4D", "80FFFF", "9482C9", "FFFFFF" }

  -- Default SP school per class used as tiebreaker when multiple schools are equal
  local spDefaultSchool = {
    PALADIN = 2, PRIEST  = 2,
    SHAMAN  = 4, DRUID   = 4,
    MAGE    = 7, WARLOCK = 6,
  }

  -- Compute and cache the haste/SP text; called from OnUpdate, throttled to 0.25s
  local function UpdateInfoText()
    if not GetUnitField then return end -- do nothing for older nampower

    local cfg = playerFrame.config
    if not cfg then
      return
    end
    -- display_haste: "0"=hidden, "1"=show modCastSpeed (gear haste). Talent-
    -- side cast-time reductions show up in the actual cast bar via
    -- C_Spell.UnitCastingInfo; double-folding them into this overlay was
    -- mixing two different concepts into one number.
    local showHaste = cfg.display_haste == "1"
    local showSP = cfg.display_spellpower == "1"

    local isSpellCaster = playerFrame.isSpellCaster
    if (not showHaste or not isSpellCaster) and not showSP then
      playerFrame.infoTopCenterText:SetText("")
      return
    end

    local haste = GetUnitField("player", "modCastSpeed")
    local text = ""

    if showHaste and isSpellCaster and haste then
      local hasteHex = cfgColorToHex(cfg.display_haste_color) or "FFFFFF"
      text = string.format("|cff%s%.1f%%|r", hasteHex, (1 / haste - 1) * 100)
    end

    if showSP and isSpellCaster then
      local schools = { GetSpellPower("net") }
      local defSchool = spDefaultSchool[myclass] or 2
      local maxSP = schools[defSchool] or 0
      local maxColor = spColors[defSchool]
      for i = 2, 7 do  -- skip physical (1)
        local v = schools[i] or 0
        if v > maxSP then
          maxSP = v
          maxColor = spColors[i]
        end
      end
      if maxSP > 0 then
        local spHex = (cfg.display_sp_color_override == "1" and cfgColorToHex(cfg.display_sp_color)) or maxColor
        if text ~= "" then text = text .. "    " end
        text = text .. string.format("|cff%s+%d SP|r", spHex, maxSP)
      end
    end

    playerFrame.infoTopCenterText:SetText(text)
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
