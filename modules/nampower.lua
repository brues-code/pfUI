-- Nampower integration module
-- Provides spell queue indicator and enhanced cast information
-- Requires Nampower DLL: https://gitea.com/avitasia/nampower

pfUI:RegisterModule("nampower", function ()
  -- Only load if Nampower is available
  if not GetNampowerVersion then return end

  local rawborder, border = GetBorderSize()

  -- Spell Queue Indicator
  -- Shows the currently queued spell icon near the castbar
  if C.unitframes.spellqueue == "1" then
    local size = tonumber(C.unitframes.spellqueuesize) or 32

    pfUI.spellqueue = CreateFrame("Frame", "pfSpellQueue", UIParent)
    pfUI.spellqueue:SetFrameStrata("HIGH")
    pfUI.spellqueue:SetWidth(size)
    pfUI.spellqueue:SetHeight(size)
    pfUI.spellqueue:Hide()

    -- Position near player castbar if available
    if pfUI.castbar and pfUI.castbar.player then
      pfUI.spellqueue:SetPoint("LEFT", pfUI.castbar.player, "RIGHT", border*3, 0)
    else
      pfUI.spellqueue:SetPoint("CENTER", UIParent, "CENTER", 100, -100)
    end

    pfUI.spellqueue.icon = pfUI.spellqueue:CreateTexture("OVERLAY")
    pfUI.spellqueue.icon:SetAllPoints(pfUI.spellqueue)
    pfUI.spellqueue.icon:SetTexCoord(.08, .92, .08, .92)

    UpdateMovable(pfUI.spellqueue)
    CreateBackdrop(pfUI.spellqueue)
    CreateBackdropShadow(pfUI.spellqueue)

    -- Event codes from Nampower
    local ON_SWING_QUEUED = 0
    local ON_SWING_QUEUE_POPPED = 1
    local NORMAL_QUEUED = 2
    local NORMAL_QUEUE_POPPED = 3
    local NON_GCD_QUEUED = 4
    local NON_GCD_QUEUE_POPPED = 5

    local queue = CreateFrame("Frame")
    queue:RegisterEvent("SPELL_QUEUE_EVENT")
    queue:RegisterEvent("PLAYER_LOGOUT")
    queue:SetScript("OnEvent", function()
      -- Handle shutdown to prevent crash 132
      if event == "PLAYER_LOGOUT" then
        this:UnregisterAllEvents()
        this:SetScript("OnEvent", nil)
        return
      end
      
      local eventCode = arg1
      local spellId = arg2

      if eventCode == NORMAL_QUEUED or eventCode == NON_GCD_QUEUED or eventCode == ON_SWING_QUEUED then
        local texture = C_Spell.GetSpellTexture(spellId)
        if texture then
          pfUI.spellqueue.icon:SetTexture(texture)
          pfUI.spellqueue:Show()
        end
      elseif eventCode == NORMAL_QUEUE_POPPED or eventCode == NON_GCD_QUEUE_POPPED or eventCode == ON_SWING_QUEUE_POPPED then
        pfUI.spellqueue:Hide()
      end
    end)
  end

  -- NOTE: Buff tracking removed - was dead code (data collected but never used for display)

  -- Reactive Spell Indicator using C_Spell.IsSpellUsable
  -- Shows when reactive abilities like Overpower, Revenge, Execute are usable
  if C.unitframes.reactive_indicator == "1" then
    local size = tonumber(C.unitframes.reactive_size) or 28
    local _, class = UnitClass("player")

    -- Reactive spells by class
    local reactiveSpells = {
      WARRIOR = {
        { name = "Overpower", texture = "Interface\\Icons\\Ability_MeleeDamage" },
        { name = "Revenge", texture = "Interface\\Icons\\Ability_Warrior_Revenge" },
        { name = "Execute", texture = "Interface\\Icons\\INV_Sword_48" },
      },
      ROGUE = {
        { name = "Riposte", texture = "Interface\\Icons\\Ability_Warrior_Challange" },
      },
      HUNTER = {
        { name = "Mongoose Bite", texture = "Interface\\Icons\\Ability_Hunter_SwiftStrike" },
        { name = "Counterattack", texture = "Interface\\Icons\\Ability_Warrior_Challange" },
      },
    }

    local spells = reactiveSpells[class]
    if spells then
      pfUI.reactive = CreateFrame("Frame", "pfReactiveIndicator", UIParent)
      pfUI.reactive:SetFrameStrata("HIGH")
      local spellCount = table.getn(spells)
      pfUI.reactive:SetWidth(size * spellCount + 4 * (spellCount - 1))
      pfUI.reactive:SetHeight(size)
      pfUI.reactive:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
      pfUI.reactive:Hide()

      pfUI.reactive.icons = {}
      for i, spell in ipairs(spells) do
        local icon = CreateFrame("Frame", nil, pfUI.reactive)
        icon:SetWidth(size)
        icon:SetHeight(size)
        icon:SetPoint("LEFT", pfUI.reactive, "LEFT", (i-1) * (size + 4), 0)

        icon.texture = icon:CreateTexture(nil, "ARTWORK")
        icon.texture:SetAllPoints(icon)
        icon.texture:SetTexture(spell.texture)
        icon.texture:SetTexCoord(.08, .92, .08, .92)

        icon.glow = icon:CreateTexture(nil, "OVERLAY")
        icon.glow:SetPoint("TOPLEFT", icon, "TOPLEFT", -4, 4)
        icon.glow:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 4, -4)
        icon.glow:SetTexture(pfUI.media["img:glow"])
        icon.glow:SetVertexColor(1, 1, 0, 0.8)

        CreateBackdrop(icon)
        icon:Hide()
        icon.spellName = spell.name
        pfUI.reactive.icons[i] = icon
      end

      UpdateMovable(pfUI.reactive)

      pfUI.reactive:SetScript("OnUpdate", function()
        local anyVisible = false
        for _, icon in ipairs(this.icons) do
          local usable = C_Spell.IsSpellUsable(icon.spellName)
          if usable then
            icon:Show()
            anyVisible = true
          else
            icon:Hide()
          end
        end
        if anyVisible then
          this:Show()
        else
          this:Hide()
        end
      end)
    end
  end

  -- /disenchantall slash command (DisenchantAll is Nampower-provided)
  if DisenchantAll then
    _G.SLASH_PFDISENCHANTALL1 = "/disenchantall"
    _G.SLASH_PFDISENCHANTALL2 = "/dea"
    SlashCmdList["PFDISENCHANTALL"] = function()
      DisenchantAll()
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: Disenchanting all eligible items...")
    end
  end

  -- Druid Secondary Mana Bar
  -- Shows base mana when druid is in shapeshift form (Bear/Cat uses Rage/Energy)
  -- Uses Nampower's GetUnitField to get base mana values
  -- Fully self-contained: uses its own config settings from C.unitframes.druidmana*
    if GetUnitField and pfUI.uf and pfUI_config.unitframes.druidmanabar == "1" then
    local rawborder, default_border = GetBorderSize("unitframes")
    local DC = C.unitframes -- druid mana config lives here as druidmana* keys

    -- Shared helper: create a druid mana bar on a unit frame
    local function CreateDruidManaBar(parent, unit)
      if not parent then return nil end

      local parentConfig = parent.config

      -- Read own config values
      local dmHeight = tonumber(DC.druidmanaheight) or 10
      local dmWidth = DC.druidmanawidth or "-1"
      local dmOffX = tonumber(DC.druidmanaoffx) or 0
      local dmOffY = tonumber(DC.druidmanaoffy) or 0
      local dmSpace = tonumber(DC.druidmanaspace) or -3
      local dmTexture = DC.druidmanatexture or "Interface\\AddOns\\pfUI\\img\\bar"

      local bar = CreateFrame("StatusBar", "pfDruidMana_" .. unit, parent)
      bar:SetFrameStrata(parent:GetFrameStrata())
      bar:SetFrameLevel(parent:GetFrameLevel() + 5)
      bar:SetStatusBarTexture(pfUI.media[dmTexture] or dmTexture)

      -- Bar color: use same manacolor logic as the normal power bar
      local manacolor = parentConfig.defcolor == "0" and parentConfig.manacolor or C.unitframes.manacolor
      local r, g, b, a = pfUI.api.strsplit(",", manacolor)
      bar:SetStatusBarColor(tonumber(r) or .25, tonumber(g) or .25, tonumber(b) or 1, tonumber(a) or 1)

      -- Size: own width/height, fallback to parent power bar width if -1
      local width = dmWidth ~= "-1" and tonumber(dmWidth) or nil
      if width then
        bar:SetWidth(width)
      end
      bar:SetHeight(dmHeight)

      -- Position below the power bar with own spacing + offsets
      local spacing = -2 * default_border - dmSpace
      if width then
        -- Fixed width: use single point with offset
        bar:SetPoint("TOP", parent.power, "BOTTOM", dmOffX, spacing + dmOffY)
      else
        -- Auto width: anchor to both sides of power bar
        bar:SetPoint("TOPLEFT", parent.power, "BOTTOMLEFT", dmOffX, spacing + dmOffY)
        bar:SetPoint("TOPRIGHT", parent.power, "BOTTOMRIGHT", dmOffX, spacing + dmOffY)
      end
      bar:Hide()

      CreateBackdrop(bar)
      CreateBackdropShadow(bar)

      -- Font settings (same logic as power bar)
      local fontname = pfUI.font_unit
      local fontsize = tonumber(pfUI_config.global.font_unit_size)
      local fontstyle = pfUI_config.global.font_unit_style

      if parentConfig.customfont == "1" then
        fontname = pfUI.media[parentConfig.customfont_name]
        fontsize = tonumber(parentConfig.customfont_size)
        fontstyle = parentConfig.customfont_style
      end

      -- Text color (always mana-colored)
      local tr, tg, tb = ManaBarColor[0].r, ManaBarColor[0].g, ManaBarColor[0].b
      if C.unitframes.pastel == "1" then
        tr, tg, tb = (tr + .75) * .5, (tg + .75) * .5, (tb + .75) * .5
      end

      -- Single center text showing current/max
      bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      bar.text:SetFontObject(GameFontWhite)
      bar.text:SetFont(fontname, fontsize, fontstyle)
      bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
      bar.text:SetJustifyH("CENTER")
      bar.text:SetTextColor(tr, tg, tb, 1)

      return bar
    end

    -- Shared helper: update druid mana bar values and text
    local function UpdateDruidManaBar(bar, unit)
      if not UnitExists(unit) then
        bar:Hide()
        return
      end

      -- For non-player units, only show if the target is a Druid
      if unit ~= "player" then
        local _, unitClass = UnitClass(unit)
        if unitClass ~= "DRUID" then
          bar:Hide()
          return
        end
      end

      local powerType = UnitPowerType(unit)

      -- Only show when NOT using mana (i.e., in Bear/Cat form)
      if powerType == 0 then
        bar:Hide()
        return
      end

      -- Get base mana using Nampower's GetUnitField
      local baseMana, baseMaxMana
      local guid = UnitGUID(unit)

      if guid then
        baseMana = GetUnitField(guid, "power1")
        baseMaxMana = GetUnitField(guid, "maxPower1")
      end

      -- Round down power values (Nampower can return decimals)
      if baseMana then baseMana = math.floor(baseMana) end
      if baseMaxMana then baseMaxMana = math.floor(baseMaxMana) end

      if type(baseMana) ~= "number" or type(baseMaxMana) ~= "number" or baseMaxMana == 0 then
        bar:Hide()
        return
      end

      -- Update bar
      bar:SetMinMaxValues(0, baseMaxMana)
      bar:SetValue(baseMana)

      -- Always show current/max
      bar.text:SetText(string.format("%s/%s", Abbreviate(baseMana), Abbreviate(baseMaxMana)))

      bar:Show()
    end

    -- ===== Player Druid Mana Bar =====
    local _, playerClass = UnitClass("player")
    if pfUI.uf.player and playerClass == "DRUID" then
      local playerMana = CreateDruidManaBar(pfUI.uf.player, "player")

      if playerMana then
        playerMana:RegisterEvent("UNIT_MANA")
        playerMana:RegisterEvent("UNIT_MAXMANA")
        playerMana:RegisterEvent("UNIT_DISPLAYPOWER")
        playerMana:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        playerMana:RegisterEvent("PLAYER_LOGOUT")
        playerMana:SetScript("OnEvent", function()
          if event == "PLAYER_LOGOUT" then
            this:UnregisterAllEvents()
            this:SetScript("OnEvent", nil)
            return
          end
          if arg1 == nil or arg1 == "player" then
            UpdateDruidManaBar(playerMana, "player")
          end
        end)

        -- Initial update
        UpdateDruidManaBar(playerMana, "player")
      end
    end

    -- ===== Target Druid Mana Bar =====
    if pfUI.uf.target then
      local targetMana = CreateDruidManaBar(pfUI.uf.target, "target")

      if targetMana then
        targetMana:RegisterEvent("UNIT_MANA")
        targetMana:RegisterEvent("UNIT_MAXMANA")
        targetMana:RegisterEvent("UNIT_DISPLAYPOWER")
        targetMana:RegisterEvent("PLAYER_TARGET_CHANGED")
        targetMana:RegisterEvent("PLAYER_LOGOUT")
        targetMana:SetScript("OnEvent", function()
          if event == "PLAYER_LOGOUT" then
            this:UnregisterAllEvents()
            this:SetScript("OnEvent", nil)
            return
          end
          if event == "PLAYER_TARGET_CHANGED" or arg1 == nil or arg1 == "target" then
            UpdateDruidManaBar(targetMana, "target")
          end
        end)

        -- Initial update
        UpdateDruidManaBar(targetMana, "target")
      end
    end
  end
end)