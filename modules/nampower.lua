-- Nampower integration: the spell queue indicator and /disenchantall
-- Requires Nampower DLL: https://github.com/brues-code/nampower

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

    pfUI.spellqueue.icon = pfUI.spellqueue:CreateTexture(nil, "OVERLAY")
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

    pfUI.events:RegisterFrameEventAndCallback("SPELL_QUEUE_EVENT", function(_, eventCode, spellId)
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
