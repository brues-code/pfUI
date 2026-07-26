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
    pfUI.spellqueue:SetSize(size, size)
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
      
      local eventCode, spellId = arg1, arg2

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
    local class = UnitClassBase("player")

    -- Reactive spells by class
    local reactiveSpells = {
      WARRIOR = {
        7384, -- Overpower
        6572, -- Revenge
        5283, -- Execute
      },
      ROGUE = {
        76, -- Riposte
      },
      HUNTER = {
        1495, -- Mongoose Bite
        19306, -- Counterattack
      },
    }

    local spells = reactiveSpells[class]
    if spells then
      pfUI.reactive = CreateFrame("Frame", "pfReactiveIndicator", UIParent)
      pfUI.reactive:SetFrameStrata("HIGH")
      local spellCount = table.getn(spells)
      pfUI.reactive:SetSize(size * spellCount + 4 * (spellCount - 1), size)
      pfUI.reactive:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
      pfUI.reactive:Hide()

      pfUI.reactive.icons = {}
      for i, spell in ipairs(spells) do
        local icon = CreateFrame("Frame", nil, pfUI.reactive)
        icon:SetSize(size, size)
        icon:SetPoint("LEFT", pfUI.reactive, "LEFT", (i-1) * (size + 4), 0)

        icon.texture = icon:CreateTexture(nil, "ARTWORK")
        icon.texture:SetAllPoints(icon)
        icon.texture:SetTexture(C_Spell.GetSpellTexture(spell))
        icon.texture:SetTexCoord(.08, .92, .08, .92)

        icon.glow = icon:CreateTexture(nil, "OVERLAY")
        icon.glow:SetPoint("TOPLEFT", icon, "TOPLEFT", -4, 4)
        icon.glow:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 4, -4)
        icon.glow:SetTexture(pfUI.media["img:glow"])
        icon.glow:SetVertexColor(1, 1, 0, 0.8)

        CreateBackdrop(icon)
        icon:Hide()
        icon.spellName = C_Spell.GetSpellName(spell)
        pfUI.reactive.icons[i] = icon
      end

      UpdateMovable(pfUI.reactive)

      pfUI.reactive:SetScript("OnUpdate", function()
        local anyVisible = false
        for _, icon in ipairs(this.icons) do
          local usable = C_Spell.IsSpellUsable(icon.spellName)
          icon:SetShown(usable)
          anyVisible = anyVisible or usable
        end
        this:SetShown(anyVisible)
      end)
    end
  end

  -- /disenchantall slash command (DisenchantAll is Nampower-provided)
  if DisenchantAll then
    pfUI.api.RegisterSlashCommand("PFDISENCHANTALL", { "/disenchantall", "/dea" }, function(msg)
      -- DisenchantAll(itemIdOrName | quality, [includeSoulbound]).
      -- Quality is a string keyword ("greens", "blues", "purples", or pipe-
      -- combined). Numbers are interpreted as item IDs, not quality levels.
      -- Default to "greens" — the typical disenchant-farming target.
      local arg = (msg and msg ~= "") and msg or "greens"
      local target = tonumber(arg) or arg
      DisenchantAll(target)
      print("|cff33ffccpfUI|r: DisenchantAll(" .. tostring(target) .. ")")
    end, true)
  end

end)