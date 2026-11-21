-- SuperWoW integration: group members on the minimap
-- https://github.com/balakethelock/SuperWoW

pfUI:RegisterModule("superwow", function ()
  if not TrackUnit or C.unitframes.track_group ~= "1" then return end

  local function TrackGroup()
    for i = 1, 4 do
      local unit = "party" .. i
      if UnitExists(unit) and UnitIsConnected(unit) then
        TrackUnit(unit)
      end
    end

    for i = 1, 40 do
      local unit = "raid" .. i
      if UnitExists(unit) and UnitIsConnected(unit) and not UnitIsUnit(unit, "player") then
        TrackUnit(unit)
      end
    end
  end

  pfUI.events:RegisterFrameEventAndCallback("GROUP_ROSTER_UPDATE", TrackGroup)
  pfUI.events:RegisterFrameEventAndCallback("PLAYER_ENTERING_WORLD", TrackGroup)
end)
