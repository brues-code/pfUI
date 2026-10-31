-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libunitscan ]]--
-- A pfUI library that remembers the class, level and guild of every player it
-- sees: in the friends, guild, raid and party rosters, in /who results, and as
-- target, mouseover or nameplate. The data is persisted within pfUI_playerDB,
-- for the places that only have a player's name, such as chat links and
-- offline friends. Anything with a unit reads the unit itself instead.
--
-- External functions:
--   GetUnitInfo(name)
--     Returns information of the given player name. Returns nil if the player
--     was never seen.
--
--     class[String] - The class of the player
--     level[Number] - The level of the player
--     guild[String] - The guild name of the player
--

-- return instantly when another libunitscan is already active
if pfUI.api.libunitscan then return end

local players = {}

-- Feed (guid, name, classToken) into ClassicAPI's persistent name
-- cache when the unit's GUID is resolvable. Roster-style packets
-- (party / raid / inspect on glance) carry class inline, so the
-- engine often doesn't issue a separate name query and the DLL's
-- NameCache hook never fires for them — this is where we close that gap.
local function RememberByUnit(unit, name, class)
  if not (name and class) then return end
  local guid = UnitGUID(unit)
  if not guid then return end
  C_PlayerCache.RememberPlayer(guid, name, class, UnitRace(unit), UnitSex(unit))
end

function GetUnitInfo(name)
  local ret = players[name]
  if ret then
    return ret.class, ret.level, ret.guild
  end
end

local function AddData(name, class, level, guild)
  if not name then return end
  players[name] = players[name] or {}
  players[name].class = class or players[name].class
  players[name].level = level or players[name].level
  players[name].guild = guild or players[name].guild
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
    local name = UnitName("player")
    local class = UnitClassBase("player")
    local level = UnitLevel("player")
    local guild = GetGuildInfo("player")
    AddData(name, class, level, guild)
    RememberByUnit("player", name, class)

  elseif event == "FRIENDLIST_UPDATE" then
    for i = 1, GetNumFriends() do
      local info = C_FriendList.GetFriendInfoByIndex(i)
      if info then
        local level = info.level > 0 and info.level or nil
        AddData(info.name, info.classFilename, level)
      end
    end

  elseif event == "GUILD_ROSTER_UPDATE" then
    local guild = GetGuildInfo("player")
    local name, class, level, _
    for i = 1, GetNumGuildMembers() do
      name, _, _, level, class = GetGuildRosterInfo(i)
      class = L["class"][class] or nil
      AddData(name, class, level, guild)
    end

  elseif event == "RAID_ROSTER_UPDATE" then
    local name, class, level, unit, _
    for i = 1, GetNumRaidMembers() do
      unit = "raid" .. i
      name, _, _, level, class = GetRaidRosterInfo(i)
      class = L["class"][class] or nil
      AddData(name, class, level)
      RememberByUnit(unit, name, class)
    end

  elseif event == "PARTY_MEMBERS_CHANGED" then
    local name, class, level, unit, guild
    for i = 1, GetNumPartyMembers() do
      unit = "party" .. i
      class = UnitClassBase(unit)
      name = UnitName(unit)
      level = UnitLevel(unit)
      guild = GetGuildInfo(unit)
      AddData(name, class, level, guild)
      RememberByUnit(unit, name, class)
    end

  elseif event == "WHO_LIST_UPDATE" or event == "CHAT_MSG_SYSTEM" then
    for i = 1, C_FriendList.GetNumWhoResults() do
      local info = C_FriendList.GetWhoInfo(i)
      if info then
        AddData(info.fullName, info.filename, info.level, info.fullGuildName)
      end
    end

  elseif event == "UPDATE_MOUSEOVER_UNIT" or event == "PLAYER_TARGET_CHANGED" or event == "NAME_PLATE_UNIT_ADDED" then
    local scan = event == "PLAYER_TARGET_CHANGED" and "target"
              or event == "NAME_PLATE_UNIT_ADDED" and arg1
              or "mouseover"
    if UnitIsPlayer(scan) then
      local name = UnitName(scan)
      local class = UnitClassBase(scan)
      -- UnitLevel returns -1 for unknown levels, don't overwrite known values
      local level = UnitLevel(scan)
      level = level > 0 and level or nil
      AddData(name, class, level, GetGuildInfo(scan))
      RememberByUnit(scan, name, class)
    end
  end
end)

pfUI.api.libunitscan = libunitscan
