-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libunitscan ]]--
-- A pfUI library that remembers the level of every player it sees: in the
-- friends, guild, raid and party rosters, in /who results, and as target,
-- mouseover or nameplate. The levels are persisted within pfUI_playerDB, for
-- the places that only have a player's name, such as chat links and offline
-- friends. Anything with a unit reads the unit itself instead. A player's
-- class comes from C_PlayerCache.GetPlayerInfoByName, not from here.
--
-- External functions:
--   GetPlayerLevel(name)
--     Returns the last seen level of the given player name, or nil if it was
--     never seen.
--

-- return instantly when another libunitscan is already active
if pfUI.api.libunitscan then return end

local players = {}

function GetPlayerLevel(name)
  local entry = players[name]
  return entry and entry.level
end

-- UnitLevel returns -1 for unknown levels, don't overwrite known values
local function AddLevel(name, level)
  if not name or not level or level <= 0 then return end
  local entry = players[name]
  if entry then
    entry.level = level
  else
    players[name] = { level = level }
  end
end

local libunitscan = CreateFrame("Frame", "pfUnitScan", UIParent)
libunitscan:RegisterEvent("PLAYER_ENTERING_WORLD")
libunitscan:RegisterEvent("FRIENDLIST_UPDATE")
libunitscan:RegisterEvent("GUILD_ROSTER_UPDATE")
libunitscan:RegisterEvent("RAID_ROSTER_UPDATE")
libunitscan:RegisterEvent("PARTY_MEMBERS_CHANGED")
libunitscan:RegisterEvent("PLAYER_TARGET_CHANGED")
libunitscan:RegisterEvent("WHO_LIST_UPDATE")
libunitscan:RegisterEvent("CHAT_MSG_SYSTEM")
libunitscan:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
libunitscan:RegisterEvent("NAME_PLATE_UNIT_ADDED")
libunitscan:SetScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" then

    -- load pfUI_playerDB
    players = pfUI_playerDB

    -- update own character details
    AddLevel(UnitName("player"), UnitLevel("player"))

  elseif event == "FRIENDLIST_UPDATE" then
    for i = 1, GetNumFriends() do
      local info = C_FriendList.GetFriendInfoByIndex(i)
      if info then
        AddLevel(info.name, info.level)
      end
    end

  elseif event == "GUILD_ROSTER_UPDATE" then
    local name, level, _
    for i = 1, GetNumGuildMembers() do
      name, _, _, level = GetGuildRosterInfo(i)
      AddLevel(name, level)
    end

  elseif event == "RAID_ROSTER_UPDATE" then
    local name, level, _
    for i = 1, GetNumRaidMembers() do
      name, _, _, level = GetRaidRosterInfo(i)
      AddLevel(name, level)
    end

  elseif event == "PARTY_MEMBERS_CHANGED" then
    for i = 1, GetNumPartyMembers() do
      AddLevel(UnitName("party" .. i), UnitLevel("party" .. i))
    end

  elseif event == "WHO_LIST_UPDATE" or event == "CHAT_MSG_SYSTEM" then
    for i = 1, C_FriendList.GetNumWhoResults() do
      local info = C_FriendList.GetWhoInfo(i)
      if info then
        AddLevel(info.fullName, info.level)
      end
    end

  elseif event == "UPDATE_MOUSEOVER_UNIT" or event == "PLAYER_TARGET_CHANGED" or event == "NAME_PLATE_UNIT_ADDED" then
    local scan = event == "PLAYER_TARGET_CHANGED" and "target"
              or event == "NAME_PLATE_UNIT_ADDED" and arg1
              or "mouseover"
    if UnitIsPlayer(scan) then
      AddLevel(UnitName(scan), UnitLevel(scan))
    end
  end
end)

pfUI.api.libunitscan = libunitscan
