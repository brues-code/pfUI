pfUI:RegisterModule("focus", function ()
  -- do not go further on disabled UFs
  if C.unitframes.disable == "1" then return end

  pfUI.uf.focus = pfUI.uf:CreateUnitFrame("Focus", nil, C.unitframes.focus, .2)
  pfUI.uf.focus:UpdateFrameSize()
  pfUI.uf.focus:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", 220, 220)
  UpdateMovable(pfUI.uf.focus)
  pfUI.uf.focus:Hide()

  pfUI.uf.focustarget = pfUI.uf:CreateUnitFrame("FocusTarget", nil, C.unitframes.focustarget, .2)
  pfUI.uf.focustarget:UpdateFrameSize()
  pfUI.uf.focustarget:SetPoint("BOTTOMLEFT", pfUI.uf.focus, "TOP", 0, 10)
  UpdateMovable(pfUI.uf.focustarget)
  pfUI.uf.focustarget:Hide()

  -- PLAYER_FOCUS_CHANGED drives immediate refresh on focus assign / clear.
  -- The frame's 0.2s tick keeps health/power/aura data fresh between events.
  local refresher = CreateFrame("Frame")
  refresher:RegisterEvent("PLAYER_FOCUS_CHANGED")
  refresher:SetScript("OnEvent", function()
    pfUI.uf.focus.instantRefresh = true
    pfUI.uf:RefreshUnit(pfUI.uf.focus, "all")
    pfUI.uf.focustarget.instantRefresh = true
    pfUI.uf:RefreshUnit(pfUI.uf.focustarget, "all")
  end)
end)

SLASH_PFFOCUS1, SLASH_PFFOCUS2 = '/focus', '/pffocus'
function SlashCmdList.PFFOCUS(msg)
  if msg == "" then
    FocusUnit("target")
    return
  end

  -- Resolve name → unit via short target-swap, capturing focus during the swap.
  local prevGUID = UnitGUID("target")
  local prevPlayer = UnitIsUnit("target", "player")

  -- Suppress "Unknown unit" errors during targeting attempts (fired async)
  UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")

  -- Try exact match first, then prefix match via /tar
  TargetByName(msg, true)
  if not UnitExists("target") then
    SlashCmdList.TARGET(msg)
  end

  if UnitExists("target") then
    FocusUnit("target")
  end

  -- Re-enable errors next frame
  local restore = CreateFrame("Frame")
  restore:SetScript("OnUpdate", function()
    UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
    restore:SetScript("OnUpdate", nil)
  end)

  if prevGUID and prevGUID ~= "0x0000000000000000" then
    TargetUnit(prevGUID)
  elseif prevPlayer then
    TargetUnit("player")
  else
    ClearTarget()
  end
end

SLASH_PFCLEARFOCUS1, SLASH_PFCLEARFOCUS2 = '/clearfocus', '/pfclearfocus'
function SlashCmdList.PFCLEARFOCUS(msg)
  ClearFocus()
end

SLASH_PFCASTFOCUS1, SLASH_PFCASTFOCUS2 = '/castfocus', '/pfcastfocus'
function SlashCmdList.PFCASTFOCUS(msg)
  local focusGUID = UnitGUID("focus")
  if not focusGUID or focusGUID == "0x0000000000000000" then
    UIErrorsFrame:AddMessage(SPELL_FAILED_BAD_TARGETS, 1, 0, 0)
    return
  end

  local func = pfUI.api.TryMemoizedFuncLoadstringForSpellCasts(msg)

  -- GUID-based cast (Nampower) - no target toggle needed
  if not func then
    CastSpellByName(msg, focusGUID)
    return
  end

  -- Lua-function cast: short target swap via GUID
  local prevGUID = UnitGUID("target")
  local prevPlayer = UnitIsUnit("target", "player")

  TargetUnit(focusGUID)
  if UnitGUID("target") ~= focusGUID then
    if prevGUID and prevGUID ~= "0x0000000000000000" then
      TargetUnit(prevGUID)
    elseif prevPlayer then
      TargetUnit("player")
    else
      TargetLastTarget()
    end
    UIErrorsFrame:AddMessage(SPELL_FAILED_BAD_TARGETS, 1, 0, 0)
    return
  end

  func()

  if prevGUID and prevGUID ~= "0x0000000000000000" then
    TargetUnit(prevGUID)
  elseif prevPlayer then
    TargetUnit("player")
  else
    TargetLastTarget()
  end
end

SLASH_PFSWAPFOCUS1, SLASH_PFSWAPFOCUS2 = '/swapfocus', '/pfswapfocus'
function SlashCmdList.PFSWAPFOCUS(msg)
  local targetGUID = UnitGUID("target")
  local oldFocusGUID = UnitGUID("focus")

  if targetGUID and targetGUID ~= "0x0000000000000000" then
    FocusUnit("target")
    if oldFocusGUID and oldFocusGUID ~= "0x0000000000000000" then
      TargetUnit(oldFocusGUID)
    end
  end
end
