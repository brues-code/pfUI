pfUI:RegisterModule("hunterbar", function ()
  if UnitClassBase("player") ~= "HUNTER" or C.bars.hunterbar == "0" then return end

  -- The bar follows the target's range: page 2 (ranged) once the target is
  -- out of melee range and in shot range, page 1 (melee) once it is in melee
  -- range and too close to shoot. In between, in the dead zone, the page
  -- stays as it is, so it doesn't flip back and forth.
  --
  -- ClassicAPI's swing range checks report both ranges as they change. The
  -- ranged check is Auto Shot's: the same range row as Arcane Shot (8-35 yd),
  -- with the same Hawk Eye and ranged-weapon bonuses. The melee check is the
  -- server's auto-attack reach, the one Raptor Strike swings with. It is
  -- Wing Clip's reach, but measured flat, without the height difference,
  -- and without the extra 2.67 yd Wing Clip gets while both units move.
  -- Either check gives no answer (nil) without an attackable target or a
  -- weapon for it, and then the page stays as it is.
  local MELEE = Enum.PlayerSwingType.MainHand
  local RANGED = Enum.PlayerSwingType.Ranged

  pfUI.hunterbar = CreateFrame("Frame", "pfHunterBar", UIParent)

  -- the page we last forced, so a range change doesn't force it again
  pfUI.hunterbar.lastPage = nil

  local function SetPage(page)
    if pfUI.hunterbar.lastPage == page then return end
    pfUI.hunterbar.lastPage = page
    _G.CURRENT_ACTIONBAR_PAGE = page
    ChangeActionBarPage()
  end

  local function Update()
    local melee = C_SwingTimer.IsTargetWithinSwingRange(MELEE)
    local ranged = C_SwingTimer.IsTargetWithinSwingRange(RANGED)

    if melee == false and ranged == true then
      SetPage(2)
    elseif melee == true and ranged == false then
      SetPage(1)
    end
  end

  -- the range event fires only on a change, so the login reads the state once
  C_SwingTimer.EnableRangeCheck(MELEE, true)
  C_SwingTimer.EnableRangeCheck(RANGED, true)
  pfUI.hunterbar:RegisterEvent("PLAYER_SWING_RANGE_UPDATE")
  pfUI.hunterbar:RegisterEvent("PLAYER_ENTERING_WORLD")
  pfUI.hunterbar:SetScript("OnEvent", Update)
end)
