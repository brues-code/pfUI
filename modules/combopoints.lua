pfUI:RegisterModule("combopoints", function ()
  local rawborder, border = GetBorderSize()

  -- Hide Blizzard combo point frame and unregister all events to prevent it from popping up again
  ComboFrame:Hide()
  ComboFrame:UnregisterAllEvents()

  local class = UnitClassBase("player")
  local combo_width = C["unitframes"]["combowidth"]
  local combo_height = C["unitframes"]["comboheight"]
  pfUI.combopoints = {}

  for point = 1, 5 do
    pfUI.combopoints[point] = CreateFrame("Frame", "pfCombo" .. point, UIParent)
    pfUI.combopoints[point]:SetFrameStrata("HIGH")
    pfUI.combopoints[point]:SetWidth(combo_width)
    pfUI.combopoints[point]:SetHeight(combo_height)
    pfUI.combopoints[point]:Hide()

    if pfUI.uf.target then
      pfUI.combopoints[point]:SetPoint("TOPLEFT", pfUI.uf.target, "TOPRIGHT", border*3, -(point - 1) * (combo_height + border*3))
    else
      pfUI.combopoints[point]:SetPoint("CENTER", UIParent, "CENTER", (point - 3) * (combo_width + border*3), 10 )
    end

    pfUI.combopoints[point].tex = pfUI.combopoints[point]:CreateTexture(nil, "OVERLAY")
    pfUI.combopoints[point].tex:SetAllPoints(pfUI.combopoints[point])

    if point < 3 then
      pfUI.combopoints[point].tex:SetColorTexture(1, .3, .3, .75)
    elseif point < 4 then
      pfUI.combopoints[point].tex:SetColorTexture(1, 1, .3, .75)
    else
      pfUI.combopoints[point].tex:SetColorTexture(.3, 1, .3, .75)
    end

    UpdateMovable(pfUI.combopoints[point])
    CreateBackdrop(pfUI.combopoints[point])
    CreateBackdropShadow(pfUI.combopoints[point])
  end

  function pfUI.combopoints:DisplayNum(num)
    for point=1, num do
      pfUI.combopoints[point]:Show()
    end

    for point=num+1, 5 do
      pfUI.combopoints[point]:Hide()
    end
  end

  -- combo
  if class == "DRUID" or class == "ROGUE" then
    local combo = CreateFrame("Frame")
    combo:RegisterEvent("PLAYER_COMBO_POINTS")
    combo:RegisterEvent("PLAYER_TARGET_CHANGED")
    combo:RegisterEvent("PLAYER_ENTERING_WORLD")
    combo:SetScript("OnEvent", function()
      pfUI.combopoints:DisplayNum(GetComboPoints("target"))
    end)

  -- reck
  elseif class == "PALADIN" then
    -- The points show the extra attacks Reckoning has stored. On Turtle it
    -- procs on a block, at any rank, so the combat log's procs are counted
    -- rather than the blocks. Each proc adds the attacks it reports, up to
    -- the server's cap of 5, and other extra attacks (Hand of Justice) join
    -- the same store. The next swing uses them all: right away while
    -- auto-attacking a target in reach, else once the auto-attack starts.
    -- The server also empties the store on death, on stopping the
    -- auto-attack and on a loading screen.
    local MAX_EXTRA_ATTACKS = 5
    local stored = 0

    local function SetStored(count)
      stored = count
      pfUI.combopoints:DisplayNum(stored)
    end

    local function Reset()
      if stored > 0 then SetStored(0) end
    end

    -- the callback takes the owner, then the event's values
    pfUI.events:RegisterFrameEventAndCallback("COMBAT_LOG_EVENT_UNFILTERED", function(_, _, subevent, _, sourceGUID, _, _, _, destGUID, _, _, _, _, _, _, amount)
      if subevent == "SPELL_EXTRA_ATTACKS" and IsPlayerGuid(destGUID) then
        SetStored(min(MAX_EXTRA_ATTACKS, stored + amount))
      elseif (subevent == "SWING_DAMAGE" or subevent == "SWING_MISSED") and IsPlayerGuid(sourceGUID) then
        Reset()
      end
    end)

    pfUI.events:RegisterFrameEventAndCallback("PLAYER_DEAD", Reset)
    pfUI.events:RegisterFrameEventAndCallback("PLAYER_LEAVE_COMBAT", Reset)
    pfUI.events:RegisterFrameEventAndCallback("PLAYER_ENTERING_WORLD", Reset)
  end
end)
