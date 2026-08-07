pfUI:RegisterModule("hunterbar", function ()
  if UnitClassBase("player") ~= "HUNTER" or C.bars.hunterbar == "0" then return end

  -- Wing Clip (any rank) and Arcane Shot (any rank) spell IDs.
  -- C_Spell.IsSpellInRange works with any spell ID, no actionbar slot needed.
  local WINGCLIP_ID  = 2974   -- melee range indicator (~5 yd)
  local ARCANESHOT_ID = 3044  -- ranged range indicator (~35 yd)

  -- Hysteresis: only swap TO ranged bar when Arcane Shot is actually in range.
  -- Only swap BACK to melee bar when Wing Clip is actually in range.
  -- This prevents rapid bar-flipping in the transition zone.

  local THROTTLE = 0.02  -- seconds between range checks (was every frame)

  pfUI.hunterbar = CreateFrame("Frame", "pfHunterBar", UIParent)

  -- track which page we last forced so we don't spam ChangeActionBarPage()
  pfUI.hunterbar.lastPage = nil
  pfUI.hunterbar.elapsed = 0

  -- Idle until there's a live, attackable target. A hidden frame runs no
  -- OnUpdate, so the range polling only ticks while it can matter.
  pfUI.hunterbar:Hide()

  pfUI.hunterbar:SetScript("OnUpdate", function()
    this.elapsed = this.elapsed + arg1
    if this.elapsed < THROTTLE then return end
    this.elapsed = 0

    -- Target died or turned unattackable without a target-change event
    -- (it dropped to a corpse); stop ticking until the next target.
    if not UnitExists("target") or not UnitCanAttack("player", "target") then
      this:Hide()
      return
    end

    -- C_Spell.IsSpellInRange returns true / false / nil (rangeless). The
    -- explicit == true / == false tests leave the bar unchanged on nil.
    local wingclipInRange   = C_Spell.IsSpellInRange(WINGCLIP_ID,   "target")
    local arcaneshotInRange = C_Spell.IsSpellInRange(ARCANESHOT_ID, "target")

    -- swap to ranged bar: out of melee range AND arcane shot (8yd) in range
    if wingclipInRange == false and arcaneshotInRange == true then
      if this.lastPage ~= 2 then
        this.lastPage = 2
        _G.CURRENT_ACTIONBAR_PAGE = 2
        ChangeActionBarPage()
      end

    -- swap to melee bar: in melee range AND arcane shot (8yd) out of range
    elseif wingclipInRange == true and arcaneshotInRange == false then
      if this.lastPage ~= 1 then
        this.lastPage = 1
        _G.CURRENT_ACTIONBAR_PAGE = 1
        ChangeActionBarPage()
      end
    end
  end)

  -- Start ticking only when we gain an attackable target.
  pfUI.hunterbar:RegisterEvent("PLAYER_TARGET_CHANGED")
  pfUI.hunterbar:RegisterEvent("PLAYER_ENTERING_WORLD")
  pfUI.hunterbar:SetScript("OnEvent", function()
    if UnitExists("target") and UnitCanAttack("player", "target") then
      this.elapsed = THROTTLE  -- run the first check on the next frame
      this:Show()
    else
      this:Hide()
    end
  end)
end)