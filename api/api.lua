-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

-- [ DLL Detection Helpers ]
-- Detects presence of various DLL extensions for enhanced functionality

-- [ HasSuperWoW ]
-- Returns true if SuperWoW DLL is active
-- SuperWoW provides: UNIT_CASTEVENT, UnitPosition, SetMouseoverUnit, SpellInfo, etc.
function pfUI.api.HasSuperWoW()
  return SUPERWOW_VERSION or (SetAutoloot and SpellInfo)
end

-- [ HasUnitXP ]
-- Returns true if UnitXP_SP3 DLL is active
-- UnitXP provides: distance, line of sight, behind detection, targeting helpers
function pfUI.api.HasUnitXP()
  local success = pcall(UnitXP, "nop", "nop")
  return success
end

-- [ HasNampower ]
-- Returns true if Nampower DLL is active
-- Nampower provides: spell queuing, GetCastInfo, GetSpellIdCooldown, IsSpellInRange, etc.
function pfUI.api.HasNampower()
  return GetNampowerVersion and true or false
end

-- [ GetUnitDistance ]
-- Returns distance to unit using best available method
-- 'unit1'    [string]    first unit (default: "player")
-- 'unit2'    [string]    second unit
-- returns:   [number]    distance in yards, or nil if unavailable
function pfUI.api.GetUnitDistance(unit1, unit2)
  if not unit2 then
    unit2 = unit1
    unit1 = "player"
  end

  if not UnitExists(unit2) then return nil end

  -- Try UnitXP first (most accurate)
  if pfUI.api.HasUnitXP() then
    local success, distance = pcall(UnitXP, "distanceBetween", unit1, unit2)
    if success and distance then return distance end
  end

  -- Try SuperWoW UnitPosition
  if pfUI.api.HasSuperWoW() and UnitPosition then
    local x1, y1, z1 = UnitPosition(unit1)
    local x2, y2, z2 = UnitPosition(unit2)
    if x1 and y1 and z1 and x2 and y2 and z2 then
      return ((x2 - x1)^2 + (y2 - y1)^2 + (z2 - z1)^2)^0.5
    end
  end

  return nil
end

-- [ UnitIsBehind ]
-- Returns true if unit1 is behind unit2
-- Requires UnitXP_SP3
function pfUI.api.UnitIsBehind(unit1, unit2)
  if not pfUI.api.HasUnitXP() then return nil end
  if not unit2 then
    unit2 = unit1
    unit1 = "player"
  end
  local success, behind = pcall(UnitXP, "behind", unit1, unit2)
  if success then return behind end
  return nil
end

-- Client API shortcuts
gfind = string.gmatch or string.gfind
mod = math.mod or mod

-- [ strsplit ]
-- ClassicAPI's strsplit, taken from the ClassicAPI table, which no addon can
-- overwrite. Third-party addons replace the global strsplit / string.split
-- (e.g. BigWigs' SpellRequests makes string:split return a table), and bare
-- strsplit calls inside the pfUI environment resolve to this copy.
pfUI.api.strsplit = ClassicAPI.strsplit

-- [ checkversion ]
-- Compares a given version (major,minor,fix) and compares it to the current
-- 'chkmajor'   [number]        the major number to check
-- 'chkminor'   [number]        the minor number to check
-- 'chkfix'     [number]        the fix number to check
--
-- return:      [boolean]       true when the current version is smaller or equal
--                              to the given value, otherwise returns nil.
local major, minor, fix = nil, nil, nil
function pfUI.api.checkversion(chkmajor, chkminor, chkfix)
  if not major and not minor and not fix then
    -- load and convert current version
    major, minor, fix = pfUI.api.strsplit(".", tostring(pfUI_config.version))
    major, minor, fix = tonumber(major) or 0, tonumber(minor) or 0, tonumber(fix) or 0
  end

  local chkversion = chkmajor + chkminor/100 + chkfix/10000
  local curversion = major + minor/100 + fix/10000
  return curversion <= chkversion and true or nil
end

-- [ UnitInRange ]
-- Returns whether a party/raid member is nearby, by the configured range check.
-- unit         [string]        A unit to query (string, unitID)
-- return:      [bool]          "1" if in range otherwise "nil"
function pfUI.api.UnitInRange(unit)
  if not UnitExists(unit) or not UnitIsVisible(unit) then
    return nil
  elseif CheckInteractDistance(unit, 4) then
    return 1
  end

  -- master switch: with the 40y check off, a visible unit beyond interact
  -- range counts as in range (nothing fades). Invisible units already
  -- returned nil above, matching the pre-collapse behavior.
  if C.unitframes.rangecheck == "0" then return 1 end

  -- UnitXP precise mode: direct distance check against the configured range
  if C.unitframes.rangecheck_mode == "unitxp" and _G.UnitXP then
    local threshold = tonumber(C.unitframes.rangecheck_distance) or 40
    local success, distance = pcall(_G.UnitXP, "distanceBetween", "player", unit)
    if success and distance then
      return distance <= threshold and 1 or nil
    end
    -- fallthrough to the 40y check if UnitXP fails
  end

  -- ClassicAPI's 40y check, _G-qualified since the bare name is this function
  -- inside the pfUI environment. A unit it can't place (outside the client's
  -- sync range) counts as in range.
  local inRange, checked = _G.UnitInRange(unit)
  return (inRange or not checked) and 1 or nil
end

-- [ UnitHasBuff ]
-- Returns whether a unit has the named buff or not.
-- unit         [string]        A unit to query (string, unitID)
-- name         [string]        The localized name of the buff.
-- return:      [bool]          true if unit has buff otherwise "nil"
function pfUI.api.UnitHasBuff(unit, name)
  return C_UnitAuras.GetAuraDataBySpellName(unit, name, "HELPFUL") ~= nil or nil
end

-- [ ScanAuraSlots ]
-- Fills `buf` with the slot ids of the auras on `unit` that match `filter` and
-- returns how many (buf[1..n]; entries past n are cleared), so a module can
-- keep one buffer and refill it every refresh. Read each aura with
-- C_UnitAuras.UnitAuraBySlot(unit, buf[i]) (positional, no table) or
-- GetAuraDataBySlot. One enumeration walks the aura array once, where a
-- by-index loop (UnitAura(unit, i)) re-walks it from the start for every i.
-- Uses GetAuraSlots' fill-a-table form (table as the 5th argument) instead of
-- its vararg return: Lua 5.0 builds an `arg` table for every vararg call, so
-- collecting the returns in a Lua helper would allocate once per scan.
-- unit         [string]        unit token
-- filter       [string]        aura filter ("HELPFUL", "HARMFUL|PLAYER", ...)
-- buf          [table]         reusable buffer, filled in place
-- max          [number]        optional cap on the slot count (nil = all)
-- return:      [number]        count of slot ids written to buf
function pfUI.api.ScanAuraSlots(unit, filter, buf, max)
  local _, n = C_UnitAuras.GetAuraSlots(unit, filter, max, nil, buf)
  return n
end

-- [ IsPlayerGuid ]
-- Returns whether a GUID or unit token refers to the local player.
-- guid         [string]        A unit GUID (or unitID) to test.
-- return:      [bool]          true if it is the player otherwise "false"
pfUI.api.IsPlayerGuid = _G.IsPlayerGuid

-- [ GetUnbuffedRoster ]
-- Returns a comma-joined, colored list of group members missing the named aura.
-- name         [string]        the localized aura name to check for
-- return:      [string]        comma-joined list, empty string if everyone has it
function pfUI.api.GetUnbuffedRoster(name)
  local missing = {}
  local function check(unit)
    if UnitName(unit) and not pfUI.api.UnitHasBuff(unit, name) then
      table.insert(missing, GetUnitColor(unit) .. UnitName(unit) .. "|r")
    end
  end

  if IsInRaid() then
    for i=1,40 do check("raid"..i) end
  else
    check("player")
    for i=1,4 do check("party"..i) end
  end

  return table.concat(missing, ", ")
end

-- [[ GetUnitColor ]]
-- Returns an escape string for the unit aswell as the RGB values
-- unit         [string]        the unitstring
-- return:      [table]         string, r, g, b
function pfUI.api.GetUnitColor(unitstr)
  local class = UnitClassBase(unitstr)
  local classColor = PFUI_CLASS_COLORS[class]
  return classColor:GenerateHexColorMarkup(), classColor:GetRGB()
end

-- [ GetRaceIcon ]
-- Builds an inline race icon texture from the shared races atlas.
-- 'raceKey'    [string]        englishRace key (e.g. "NightElf")
-- 'sex'        [int]           unit sex (3 = female)
-- return:      [string]        inline texture escape, or an empty string
function pfUI.api.GetRaceIcon(raceKey, sex)
  if not raceKey then return "" end
  local gender = sex == 3 and "FEMALE" or "MALE"
  local coords = RACE_ICON_TCOORDS[strupper(raceKey) .. "_" .. gender]
  if not coords then return "" end
  return string.format(
    "|TInterface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races:0:0:0:0:512:512:%d:%d:%d:%d|t",
    coords[1] * 512, coords[2] * 512, coords[3] * 512, coords[4] * 512)
end

-- inline faction emblems (cropped from the target-frame PvP banners)
local FACTION_ICON = {
  Alliance = "|TInterface\\TargetingFrame\\UI-PVP-Alliance:0:0:0:0:64:64:5:37:3:35|t",
  Horde    = "|TInterface\\TargetingFrame\\UI-PVP-Horde:0:0:0:0:64:64:5:37:3:35|t",
}

-- [ GetFactionIcon ]
-- Resolves an inline faction emblem from the englishRace key stored in L["race"].
-- 'raceKey'    [string]        englishRace key (e.g. "Orc")
-- return:      [string]        inline texture escape, or an empty string
function pfUI.api.GetFactionIcon(raceKey)
  local info = raceKey and L["race"][raceKey]
  if not info then return "" end
  return FACTION_ICON[info.faction] or ""
end

-- [ strvertical ]
-- Creates vertical text using linebreaks. Multibyte char friendly.
-- 'str'        [string]        String to columnize.
-- return:      [string]        the string tranformed to a column.
function pfUI.api.strvertical(str)
  local _, len = string.gsub(str,"[^\128-\193]", "")
  if (len == string.len(str)) then
    return string.gsub(str, "(.)", "%1\n")
  else
    return string.gsub(str,"([%z\1-\127\194-\244][\128-\191]*)", "%1\n")
  end
end

-- [ round ]
-- Rounds a float number into specified places after comma.
-- 'input'      [float]         the number that should be rounded.
-- 'places'     [int]           amount of places after the comma.
-- returns:     [float]         rounded number.
function pfUI.api.round(input, places)
  if not places then places = 0 end
  if type(input) == "number" and type(places) == "number" then
    local pow = 1
    for i = 1, places do pow = pow * 10 end
    return floor(input * pow + 0.5) / pow
  end
end

-- [ GetServerEpoch ]
-- Returns a Unix epoch (seconds) representing the current server wall
-- clock, packed in the player's local timezone so that date(fmt, epoch)
-- prints server-time strings regardless of where the player sits.
-- Returns nil before login; date(fmt, nil) silently falls back to local time.
pfUI.api.GetServerEpoch = C_DateAndTime.GetServerTimeLocal

-- [ GetSlashCommands ]
-- Lists all registeres slash commands
-- 'text'       [string]        optional, a specific command to find
-- return:      [list]          a list of all matching slash commands
function pfUI.api.GetSlashCommands(text)
  local cmds
  for k, v in pairs(_G) do
    if strfind(k, "^SLASH_") and (not text or v == text) then
      cmds = cmds or {}
      cmds[k] = v
    end
  end

  return cmds
end

-- [ RegisterSlashCommand ]
-- Lists all registeres slash commands
-- 'name'       [string]      name of the command
-- 'cmds'       [table]       table containing all slash command strings
-- 'func'       [function]    the function that should be assigned
-- 'force'      [boolean]     force assign the command even if aleady provided
--                            by another function/addon.
function pfUI.api.RegisterSlashCommand(name, cmds, func, force)
  local counter = 1

  for _, cmd in pairs(cmds) do
    if force or not pfUI.api.GetSlashCommands(cmd) then
      _G["SLASH_"..name..counter] = cmd
      counter = counter + 1
    end
  end

  _G.SlashCmdList[name] = func
end

-- [ GetCaptures ]
-- Returns the indexes of a given regex pattern
-- 'pat'        [string]         unformatted pattern
-- returns:     [numbers]        capture indexes
local capture_cache = {}
function pfUI.api.GetCaptures(pat)
  local r = capture_cache

  if not r[pat] then
    for a, b, c, d, e in gfind(gsub(pat, "%((.+)%)", "%1"), gsub(pat, "%d%$", "%%(.-)$")) do
      r[pat] = { a, b, c, d, e}
    end

    r[pat] = r[pat] or {}
  end

  return r[pat][1], r[pat][2], r[pat][3], r[pat][4], r[pat][5]
end

-- [ SanitizePattern ]
-- Sanitizes and convert patterns into gfind compatible ones.
-- 'pattern'    [string]         unformatted pattern
-- returns:     [string]         simplified gfind compatible pattern
local sanitize_cache = {}
function pfUI.api.SanitizePattern(pattern)
  if not sanitize_cache[pattern] then
    local ret = pattern
    -- escape magic characters
    ret = gsub(ret, "([%+%-%*%(%)%?%[%]%^])", "%%%1")
    -- remove capture indexes
    ret = gsub(ret, "%d%$","")
    -- catch all characters
    ret = gsub(ret, "(%%%a)","%(%1+%)")
    -- convert all %s to .+
    ret = gsub(ret, "%%s%+",".+")
    -- set priority to numbers over strings
    ret = gsub(ret, "%(.%+%)%(%%d%+%)","%(.-%)%(%%d%+%)")
    -- cache it
    sanitize_cache[pattern] = ret
  end

  return sanitize_cache[pattern]
end

-- [ cmatch ]
-- Same as string.match but aware of capture indexes (up to 5)
-- 'str'        [string]         input string that should be matched
-- 'pat'        [string]         unformatted pattern
-- returns:     [strings]        matched string in capture order
function pfUI.api.cmatch(str, pat)
  -- idx* = the logical %N index of each physical capture slot (nil when the
  -- pattern has no %N$ markers); val* = the matched values in physical order.
  local idx1, idx2, idx3, idx4, idx5 = GetCaptures(pat)
  local _, _, val1, val2, val3, val4, val5 = string.find(str, pfUI.api.SanitizePattern(pat))

  -- reorder the physical matches into logical (%1..%5) order
  local out1 = idx5 == 1 and val5 or idx4 == 1 and val4 or idx3 == 1 and val3 or idx2 == 1 and val2 or val1
  local out2 = idx5 == 2 and val5 or idx4 == 2 and val4 or idx3 == 2 and val3 or idx1 == 2 and val1 or val2
  local out3 = idx5 == 3 and val5 or idx4 == 3 and val4 or idx1 == 3 and val1 or idx2 == 3 and val2 or val3
  local out4 = idx5 == 4 and val5 or idx1 == 4 and val1 or idx3 == 4 and val3 or idx2 == 4 and val2 or val4
  local out5 = idx1 == 5 and val1 or idx4 == 5 and val4 or idx3 == 5 and val3 or idx2 == 5 and val2 or val5

  return out1, out2, out3, out4, out5
end

-- [ GetItemLinkByName ]
-- Returns an itemLink for the given itemname
-- 'name'       [string]         name of the item
-- returns:     [string]         entire itemLink for the given item
local itemLinkCache = {}
local itemLinkMisses = {}
local ITEMLINK_MAX_SCANS = 2
function pfUI.api.GetItemLinkByName(name)
  -- GetInboxItem() hands us a nil name for attachment-less mail
  if not name then return end
  -- cache successful resolutions so repeated lookups (e.g. per inbox click) are free
  if itemLinkCache[name] then return itemLinkCache[name] end

  -- Failures have to be counted, not just retried. An unresolvable name walks
  -- the entire id range and finds nothing -- a visible hitch on every tooltip
  -- hover. Allow a couple of attempts (rendering the tooltip caches the item,
  -- so the next hover usually resolves), then stop scanning for that name.
  local misses = itemLinkMisses[name] or 0
  if misses >= ITEMLINK_MAX_SCANS then return end

  -- Octo/Turtle custom items live well past the 25818 vanilla ceiling
  for itemID = 1, 61000 do
    local itemName = C_Item.GetItemNameByID(itemID)
    if itemName and itemName == name then
      local _, itemLink = C_Item.GetItemInfo(itemID)
      itemLinkCache[name] = itemLink
      return itemLink
    end
  end

  itemLinkMisses[name] = misses + 1
end

-- [ FindItem ]
-- Returns the bag and slot position of an item based on the name.
-- 'item'       [string]         name of the item
-- returns:     [int]            bag
--              [int]            slot
function pfUI.api.FindItem(item)
  for bag = 4, 0, -1 do
    for slot = 1, GetContainerNumSlots(bag) do
      local query = C_Item.GetItemName(ItemLocation:CreateFromBagAndSlot(bag, slot))
      if query and query ~= "" and string.lower(query) == string.lower(item) then
        return bag, slot
      end
    end
  end
  return nil
end

-- [ GetBagFamily ]
-- Returns information about the type of a bag such as Soul Bags or Quivers.
-- Available bagtypes are "BAG", "KEYRING", "SOULBAG", "QUIVER" and "SPECIAL"
-- 'bag'        [int]        the bag id
-- returns:     [string]     the type of the bag, e.g "QUIVER"
function pfUI.api.GetBagFamily(bag)
  if bag == -2 then return "KEYRING" end
  if bag == 0 then return "BAG" end -- backpack
  if bag == -1 then return "BAG" end -- bank

  local id = GetInventoryItemID("player", ContainerIDToInventoryID(bag))
  if id then
    -- classID 1 = Container (bags), 11 = Quiver
    -- Container subclasses: 0 = Bag (default), 1 = Soul Bag, 2+ = specialty (herb/enchanting/etc.)
    -- Quiver subclasses: 2 = Quiver (arrows), 3 = Ammo Pouch (bullets)
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
    if classID == 1 then
      if subClassID == 0 then return "BAG" end
      if subClassID == 1 then return "SOULBAG" end
      return "SPECIAL"
    elseif classID == 11 then
      return "QUIVER"
    end
  end

  return nil
end

-- [ Abbreviate ]
-- Abbreviates a number from 1234 to 1.23k, as the unitframes.abbrevnum
-- setting asks: "0" full numbers, "1" 2 decimals (4250 -> 4.25k),
-- "2" 1 decimal rounded down (4250 -> 4.2k)
-- 'number'     [number]           the number that should be abbreviated
-- 'returns:    [string]           the abbreviated value
local function CreateAbbreviateFormatter(step, rounding)
  local Down = Enum.NumericRuleFormatRounding.Down
  local formatter = C_StringUtil.CreateNumericRuleFormatter()
  formatter:SetBreakpoints({
    { threshold = 0,       format = "%d",  components = { { step = 1, rounding = Down } } },
    { threshold = 1000,    format = "%gk", components = { { div = 1000,    step = step, rounding = rounding } } },
    { threshold = 1000000, format = "%gm", components = { { div = 1000000, step = step, rounding = rounding } } },
  })
  return formatter
end

local abbreviateFormatters = {
  ["1"] = CreateAbbreviateFormatter(0.01, Enum.NumericRuleFormatRounding.Nearest),
  ["2"] = CreateAbbreviateFormatter(0.1, Enum.NumericRuleFormatRounding.Down),
}

function pfUI.api.Abbreviate(number)
  local formatter = abbreviateFormatters[pfUI_config.unitframes.abbrevnum]
  if not formatter then return math.floor(number) end
  if number < 0 then return "-" .. formatter:FormatNumber(-number) end
  return formatter:FormatNumber(number)
end

-- [ SendChatMessageWide ]
-- Sends a message to widest audience the player can broadcast to
-- 'msg'        [string]          the message to send
function pfUI.api.SendChatMessageWide(msg)
  local channel = "SAY"
  if IsInRaid() then
    if ( IsRaidLeader() or IsRaidOfficer() ) then
      channel = "RAID_WARNING"
    else
    channel = "RAID"
    end
  elseif UnitExists("party1") then
    channel = "PARTY"
  end
  SendChatMessage(msg,channel)
end

-- [ CopyText ]
-- Copies text to the clipboard and says so in the colour of a UI_INFO_MESSAGE
-- 'text'       [string]          the text to copy
function pfUI.api.CopyText(text)
  CopyToClipboard(text)
  UIErrorsFrame:AddMessage(T["Copied to clipboard"], 1, 1, 0, 1)
end

-- [ GroupInfoByName ]
-- Gets the unit id by name
-- 'name'       [string]          party or raid member
-- 'group'      [string]          "raid" or "party"
-- returns:     [table]           {name='name',unitId='unitId',Id=Id,lclass='lclass',class='class'}
do -- create a scope so we don't have to worry about upvalue collisions
  local party, raid, unitinfo = {}, {}, {}
  party[0] = "player" -- fake unit
  for i=1, MAX_PARTY_MEMBERS do
    party[i] = "party"..i
  end
  for i=1, MAX_RAID_MEMBERS do
    raid[i] = "raid"..i
  end
  function pfUI.api.GroupInfoByName(name,group)
    unitinfo = pfUI.api.wipe(unitinfo)
    if group == "party" then
      for i=0, MAX_PARTY_MEMBERS do
        local unitName = UnitName(party[i])
        if unitName == name then
          local lclass,class = UnitClass(party[i])
          if not (lclass and class) then
            lclass,class = _G.UNKNOWN, "UNKNOWN"
          end
          unitinfo.name,unitinfo.unitId,unitinfo.Id,unitinfo.lclass,unitinfo.class =
            unitName,party[i],i,lclass,class
          return unitinfo
        end
      end
    elseif group == "raid" then
      for i=1, MAX_RAID_MEMBERS do
        local unitName = UnitName(raid[i])
        if unitName == name then
          local lclass,class = UnitClass(raid[i])
          if not (lclass and class) then
            lclass,class = _G.UNKNOWN, "UNKNOWN"
          end
          unitinfo.name,unitinfo.unitId,unitinfo.Id,unitinfo.lclass,unitinfo.class =
            unitName,raid[i],i,lclass,class
          return unitinfo
        end
      end
    end
    -- fallback for GetMasterLootCandidate not updating immediately for leavers
    unitinfo.lclass,unitinfo.class = _G.UNKNOWN, "UNKNOWN"
    return unitinfo
  end
end

-- [ HookScript ]
-- Securely post-hooks a script handler.
-- 'f'          [frame]             the frame which needs a hook
-- 'script'     [string]            the handler to hook
-- 'func'       [function]          the function that should be added
function HookScript(f, script, func)
  f:HookScript(script, func)
end

function hooksecurefunc(tbl, name, func)
  if type(tbl) == "string" then tbl, name, func = _G, tbl, name end
  if not tbl or type(tbl[name]) ~= "function" then return end
  return _G.hooksecurefunc(tbl, name, func)
end

-- [ HookAddon ]
-- Runs a function once an addon has loaded, but never before PLAYER_LOGIN.
-- Module and skin bodies run inside pfUI's own ADDON_LOADED, so an addon that
-- is already loaded there would otherwise run its hook before later pfUI
-- modules exist and before the addon's own VARIABLES_LOADED setup. A
-- load-on-demand addon runs its hook on its ADDON_LOADED. Hooks for addons
-- that are not installed are dropped. Hooks on the same addon run in no
-- particular order.
-- 'addon'      [string]            addon name
-- 'func'       [function]          function that should run
function pfUI.api.HookAddon(addon, func)
  if not C_AddOns.DoesAddOnExist(addon) then return end
  EventUtil.ContinueOnPlayerLogin(function()
    EventUtil.ContinueOnAddOnLoaded(addon, func)
  end)
end

-- [ HookAddonOrVariable ]
-- Compatibility shim for pfUI plugins (e.g. pfUI-addonskinner) that still
-- call the pre-rewrite API. Routes addon names through HookAddon, and keeps
-- the legacy "or variable" fallback for callers that pass a global name.
-- Pending variable hooks share one ADDON_LOADED/PLAYER_LOGIN listener on
-- pfUI.events, which unregisters once every hook has run.
local variableHooks, variableHandles = {}, nil

local function DrainVariableHooks()
  local ready = {}
  for name in pairs(variableHooks) do
    if _G[name] then table.insert(ready, name) end
  end
  -- run after the scan: a hook may queue another and grow the table
  for _, name in ipairs(ready) do
    local funcs = variableHooks[name]
    variableHooks[name] = nil
    for _, func in ipairs(funcs) do func() end
  end
  if variableHandles and not next(variableHooks) then
    for _, handle in ipairs(variableHandles) do handle:Unregister() end
    variableHandles = nil
  end
end

function pfUI.api.HookAddonOrVariable(addon, func)
  if C_AddOns.DoesAddOnExist(addon) then
    return pfUI.api.HookAddon(addon, func)
  end
  if IsLoggedIn() and _G[addon] then return func() end

  variableHooks[addon] = variableHooks[addon] or {}
  table.insert(variableHooks[addon], func)

  if not variableHandles then
    variableHandles = {
      pfUI.events:RegisterFrameEventAndCallbackWithHandle("ADDON_LOADED", DrainVariableHooks),
      pfUI.events:RegisterFrameEventAndCallbackWithHandle("PLAYER_LOGIN", DrainVariableHooks),
    }
  end
end
_G.HookAddonOrVariable = pfUI.api.HookAddonOrVariable

-- [ Create Gold String ]
-- Transforms a amount of copper into a fully fledged gold string
-- 'money'      [int]           the amount of coppy (GetMoney())
-- return:      [string]        a colorized string which is split into
--                              gold,silver and copper values.
function pfUI.api.CreateGoldString(money)
  if type(money) ~= "number" then return "-" end

  return "|cffffffff" .. _G.GetCoinTextureString(money) .. "|r"
end

-- [ Enable Movable ]
-- Set all necessary functions to make a already existing frame movable.
-- 'name'       [frame/string]  Name of the Frame that should be movable
-- 'blacklist'  [table]         A list of frames that should be deactivated for mouse usage
local function OnDragStart() this:StartMoving() end
local function OnDragStop() this:StopMovingOrSizing() end
function pfUI.api.EnableMovable(name, blacklist)
  if blacklist then
    for _, disable in pairs(blacklist) do
      _G[disable]:EnableMouse(false)
    end
  end

  local frame = name
  if type(name) == "string" then frame = _G[name] end
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", OnDragStart)
  frame:SetScript("OnDragStop", OnDragStop)
end

-- [ Copy Table ]
-- By default a table assignment only will be a reference instead of a copy.
-- This is used to create a replicate of the actual table.
-- 'src'        [table]        the table that should be copied.
-- return:      [table]        the replicated table.
function pfUI.api.CopyTable(src)
  local lookup_table = {}
  local function _copy(src)
    if type(src) ~= "table" then
      return src
    elseif lookup_table[src] then
      return lookup_table[src]
    end
    local new_table = {}
    lookup_table[src] = new_table
    for index, value in pairs(src) do
      new_table[_copy(index)] = _copy(value)
    end
    return setmetatable(new_table, getmetatable(src))
  end
  return _copy(src)
end

-- [ Wipe Table ]
-- Empties a table and returns it.
-- 'src'      [table]         the table that should be emptied.
-- return:    [table]         the emptied table.
-- Delegates to ClassicAPI's table.wipe, which also resets the Lua 5.0 getn
-- length (luaL_setn(t,0)) so table.insert on a wiped table resumes at [1].
-- Append to wiped arrays with table.insert -- NOT the t[table.getn(t)+1]=v
-- idiom, which needs an unmanaged length counter and won't work here.
function pfUI.api.wipe(src)
  return table.wipe(src)
end

-- [ Load Movable ]
-- Loads the positions of a Frame.
-- 'frame'      [frame]        the frame that should be positioned.
-- 'init'       [bool]         treats the current position as initial data
function pfUI.api.LoadMovable(frame, init)
  -- update position data
  if not frame.posdata or init then
    frame.posdata = { scale = frame:GetScale(), pos = {} }
    for i=1,frame:GetNumPoints() do
      frame.posdata.pos[i] = { frame:GetPoint(i) }
    end
  end

  if pfUI_config["position"][frame:GetName()] then
    if pfUI_config["position"][frame:GetName()]["parent"] then
      frame:SetParent(_G[pfUI_config["position"][frame:GetName()]["parent"]])
    end

    if pfUI_config["position"][frame:GetName()]["scale"] then
      frame:SetScale(pfUI_config["position"][frame:GetName()].scale)
    end

    if pfUI_config["position"][frame:GetName()]["xpos"] then
      local anchor = pfUI_config["position"][frame:GetName()]["anchor"] or "TOPLEFT"
      frame:ClearAllPoints()
      frame:SetPoint(anchor, pfUI_config["position"][frame:GetName()].xpos, pfUI_config["position"][frame:GetName()].ypos)
    end
  elseif frame.posdata and frame.posdata.pos[1] then
    frame:ClearAllPoints()
    frame:SetScale(frame.posdata.scale)

    for id, point in pairs(frame.posdata.pos) do
      local a, b, c, d, e = unpack(point)
      -- skip if anchoring to itself (would cause WoW error)
      if a and b and b ~= frame and b ~= frame:GetName() then
        frame:SetPoint(a,b,c,d,e)
      elseif a and (not b or b == frame or b == frame:GetName()) then
        frame:SetPoint(a,d,e)
      end
    end
  end
end

-- [ Save Movable ]
-- Save the positions of a Frame.
-- 'frame'      [frame]        the frame that should be saved.
function pfUI.api.SaveMovable(frame, scale)
  local anchor, _, _, xpos, ypos = frame:GetPoint()
  C.position[frame:GetName()] = C.position[frame:GetName()] or {}
  C.position[frame:GetName()]["xpos"] = round(xpos)
  C.position[frame:GetName()]["ypos"] = round(ypos)
  C.position[frame:GetName()]["anchor"] = anchor
  C.position[frame:GetName()]["parent"] = frame:GetParent() and frame:GetParent():GetName() or nil
  if scale then
    C.position[frame:GetName()]["scale"] = frame:GetScale()
  end
end

-- [ Update Movable ]
-- Loads and update the configured position of the specified frame.
-- It also creates an entry in the movables table.
-- 'frame'      [frame]        the frame that should be updated.
-- 'init'       [bool]         treats the current position as initial data
function pfUI.api.UpdateMovable(frame, init)
  local name = frame:GetName()

  if pfUI_config.global.offscreen == "0" then
    frame:SetClampedToScreen(true)
  end

  if not pfUI.movables[name] then
    pfUI.movables[name] = frame
  end

  LoadMovable(frame, init)
end

-- [ Remove Movable ]
-- Removes a Frame from the movable list.
-- 'frame'      [frame]        the frame that should be removed.
function pfUI.api.RemoveMovable(frame)
  local name = frame:GetName()
  pfUI.movables[name] = nil
end

-- [ AlignToPosition ]
-- Sets a frame to the selected anchor
-- 'frame'      [frame]     the frame that should be aligned
-- 'anchor'     [frame]     the frame where it should be aligned to
-- 'position'   [string]    where it should appear, takes the following:
--                          "TOP", "RIGHT", "BOTTOM", "LEFT"
local alignments = {
  --         frame corners                anchor corners                spacing x/y
  TOP    = { "BOTTOMLEFT", "BOTTOMRIGHT", "TOPLEFT",    "TOPRIGHT",     0,  1 },
  RIGHT  = { "TOPLEFT",    "BOTTOMLEFT",  "TOPRIGHT",   "BOTTOMRIGHT",  1,  0 },
  BOTTOM = { "TOPLEFT",    "TOPRIGHT",    "BOTTOMLEFT", "BOTTOMRIGHT",  0, -1 },
  LEFT   = { "TOPRIGHT",   "BOTTOMRIGHT", "TOPLEFT",    "BOTTOMLEFT",  -1,  0 },
}

function pfUI.api.AlignToPosition(frame, anchor, position, spacing)
  if frame == anchor then return end
  frame:ClearAllPoints()

  local align = anchor and alignments[position]
  if not align then
    -- no usable anchor: stretch along the right screen edge
    frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT")
    frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT")
    return
  end

  local point1, point2, rel1, rel2, dx, dy = unpack(align)
  local x, y = dx * (spacing or 0), dy * (spacing or 0)
  frame:SetPoint(point1, anchor, rel1, x, y)
  frame:SetPoint(point2, anchor, rel2, x, y)
end

-- Splits the screen into a 3x3 grid and returns the cell that (x, y) falls in
-- as a row ("TOP", "" or "BOTTOM") and a column ("LEFT", "" or "RIGHT").
local function GetScreenCell(x, y, scale)
  local w = GetScreenWidth()  / scale / 3
  local h = GetScreenHeight() / scale / 3
  local row = y > 2 * h and "TOP" or y < h and "BOTTOM" or ""
  local col = x < w and "LEFT" or x > 2 * w and "RIGHT" or ""
  return row, col
end

-- [ SetAutoPoint ]
-- Automatically places the frame according to screen position of the parent.
-- 'frame'      [frame]        the frame that should be moved.
-- 'parent'     [frame]        the frame's anchor point
-- 'spacing'    [number]       the padding that should be used between the
--                             frame and its parent frame
function pfUI.api.SetAutoPoint(frame, parent, spacing)
  local x, y = parent:GetCenter()
  if not x then return end

  -- open the frame toward the screen center
  local row, col = GetScreenCell(x, y, 1)
  local off = spacing or 0

  frame:ClearAllPoints()
  if row == "TOP" then
    frame:SetPoint("TOP" .. col, parent, "BOTTOM" .. col, 0, -off)
  elseif row == "" and col == "LEFT" then
    frame:SetPoint("LEFT", parent, "RIGHT", off, 0)
  elseif row == "" and col == "RIGHT" then
    frame:SetPoint("RIGHT", parent, "LEFT", -off, 0)
  else
    frame:SetPoint("BOTTOM" .. col, parent, "TOP" .. col, 0, off)
  end
end

-- [ GetBestAnchor ]
-- Returns the best anchor of a frame, based on its position
-- 'self'       [frame]        the frame that should be checked
-- returns:     [string]       the name of the best anchor
function pfUI.api.GetBestAnchor(self)
  local x, y = self:GetCenter()
  if not x then return end

  local row, col = GetScreenCell(x, y, self:GetScale())
  local anchor = row .. col
  return anchor ~= "" and anchor or "CENTER"
end

-- [ ConvertFrameAnchor ]
-- Converts a frame anchor into another one while preserving the frame position
-- 'self'       [frame]        the frame that should get another anchor.
-- 'anchor'     [string]       the new anchor that shall be used
-- returns:     anchor, x, y   can directly be used in SetPoint()
function pfUI.api.ConvertFrameAnchor(self, anchor)
  local scale = self:GetScale()
  local w, h = GetScreenWidth() / scale, GetScreenHeight() / scale

  -- offsets from the matching point of the screen, axis by axis
  local x, y = self:GetCenter()
  x, y = x - w / 2, y - h / 2

  if anchor:find("LEFT") then
    x = self:GetLeft()
  elseif anchor:find("RIGHT") then
    x = self:GetRight() - w
  end

  if anchor:find("TOP") then
    y = self:GetTop() - h
  elseif anchor:find("BOTTOM") then
    y = self:GetBottom()
  end

  return anchor, round(x, 2), round(y, 2)
end

-- [ GetStringColor ]
-- Queries the pfUI setting strings and extract its color codes
-- returns r,g,b,a as strings
local color_cache = setmetatable({}, {
  __index = function(t, k)
    local color = { pfUI.api.strsplit(",", k) }
    rawset(t, k, color)
    return color
  end
})
function pfUI.api.GetStringColor(colorstr)
  return unpack(color_cache[colorstr])
end

-- [ GetStringColorObject ]
-- Like GetStringColor, but returns a cached ColorMixin instead of raw values.
-- The object is a shared per-string singleton, so treat it as read-only.
-- returns a ColorMixin
local color_object_cache = setmetatable({}, {
  __index = function(t, k)
    local r,g,b,a = pfUI.api.GetStringColor(k)
    local color = CreateColor(tonumber(r), tonumber(g), tonumber(b), tonumber(a))
    rawset(t, k, color)
    return color
  end
})
function pfUI.api.GetStringColorObject(colorstr)
  return color_object_cache[colorstr]
end

-- [ rgbhex ]
-- Returns color format from color info
-- 'r'          [table | number]  color table or r color component
-- 'g'          [number]          optional g color component
-- 'b'          [number]          optional b color component
-- 'a'          [number]          optional alpha component
-- returns color string in the form of '|caarrggbb'
local rgbhex_cache = {}
function pfUI.api.rgbhex(r, g, b, a)
  local _r, _g, _b, _a
  if type(r) == "table" then
    if r.r then
      _r, _g, _b, _a = r.r, r.g, r.b, (r.a or 1)
    elseif r[3] ~= nil then
      _r, _g, _b, _a = r[1], r[2], r[3], (r[4] or 1)
    end
  elseif tonumber(r) then
    _r, _g, _b, _a = r, g, b, (a or 1)
  end

  if _r and _g and _b and _a then
    local key = ((Round(_r*255)*256 + Round(_g*255))*256 + Round(_b*255))*256 + Round(_a*255)
    local hex = rgbhex_cache[key]
    if not hex then
      hex = "|c" .. C_ColorUtil.GenerateTextColorCode({ r = _r, g = _g, b = _b, a = _a })
      rgbhex_cache[key] = hex
    end
    return hex
  end

  return ""
end

-- [ GetBorderSize ]
-- Returns the configure value of a border and its pixel scaled version.
-- 'pref' allows to specifiy a custom border (i.e unitframes, panel)
function pfUI.api.GetBorderSize(pref)
  if not pfUI.borders then pfUI.borders = {} end

  -- set to default border if accessing a wrong border type
  if not pref or not pfUI_config.appearance.border[pref] or pfUI_config.appearance.border[pref] == "-1" then
    pref = "default"
  end

  if pfUI.borders[pref] then
    -- return already cached values
    return pfUI.borders[pref][1], pfUI.borders[pref][2]
  else
    -- add new borders to the pfUI tree
    local raw = tonumber(pfUI_config.appearance.border[pref])
    if raw == -1 then raw = 3 end

    local scaled = raw * GetPerfectPixel()
    pfUI.borders[pref] = { raw, scaled }

    return raw, scaled
  end
end

-- The scale UIParent ends up with: one UI unit per screen pixel when pixel
-- perfect, else the game's own. The game applies its scale only after the
-- add-ons and their saved variables are loaded (CGGameUI::Initialize ends in
-- OnDisplaySizeChanged), so at load time it is worked out from the same
-- options and rules: uiScale while useUiScale is on and it is at least 0.64,
-- else 768 over the window height kept within 0.9 and 1. Windows narrower
-- than 4:3 cap either at 3/4 of their aspect.
local function GetUIScale()
  if pfUI_config.global.pixelperfect == "1" then return PixelUtil.GetPixelToUIUnitFactor() end

  local width, height = GetPhysicalScreenSize()
  local aspect = GetCVar("widescreen") == "1" and width / height or 4/3
  local function fit(scale)
    return aspect < 4/3 and math.min(scale, aspect * .75) or scale
  end

  if GetCVar("useUiScale") == "1" then
    local scale = fit(tonumber(GetCVar("uiScale")))
    if scale >= .64 then return scale end
  end

  return math.max(fit(height > 768 and 768 / height or 1), .9)
end

-- [ UpdateUIScale ]
-- Gives UIParent the pixel perfect scale when enabled, else leaves the game's
-- own. The engine puts its own scale back on every window resize and scale
-- option change, so this runs again on each UI_SCALE_CHANGED. Borders keep
-- the pixel size they were built with, so a change of it offers a reload once.
function pfUI.api.UpdateUIScale()
  if pfUI_config.global.pixelperfect == "1" then
    UIParent:SetScale(PixelUtil.GetPixelToUIUnitFactor())
  end

  if not pfUI.pixel or pfUI.scaleprompt then return end
  if math.abs(PixelUtil.GetPixelToUIUnitFactor() / UIParent:GetScale() - pfUI.pixel) < .0001 then return end

  pfUI.scaleprompt = true
  CreateQuestionDialog(T["The UI-Scale has changed. Reload the UI to redraw the borders?"], ReloadUI)
end

-- [ GetPerfectPixel ]
-- Returns the size of one physical pixel in UIParent units.
function pfUI.api.GetPerfectPixel()
  if pfUI.pixel then return pfUI.pixel end

  pfUI.pixel = PixelUtil.GetPixelToUIUnitFactor() / GetUIScale()

  pfUI.backdrop = {
    bgFile = "Interface\\BUTTONS\\WHITE8X8", tile = false, tileSize = 0,
    edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = pfUI.pixel,
    insets = {left = -pfUI.pixel, right = -pfUI.pixel, top = -pfUI.pixel, bottom = -pfUI.pixel},
  }

  pfUI.backdrop_thin = {
    bgFile = "Interface\\BUTTONS\\WHITE8X8", tile = false, tileSize = 0,
    edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = pfUI.pixel,
    insets = {left = 0, right = 0, top = 0, bottom = 0},
  }

  return pfUI.pixel
end

-- [ Create Backdrop ]
-- Creates a pfUI compatible frame as backdrop element
-- 'f'          [frame]         the frame which should get a backdrop.
-- 'inset'      [int]           backdrop inset, defaults to border size.
-- 'legacy'     [bool]          use legacy backdrop instead of creating frames.
-- 'transp'     [number]        set default transparency
local backdrop, b, level, rawborder, border, br, bg, bb, ba, er, eg, eb, ea
function pfUI.api.CreateBackdrop(f, inset, legacy, transp, backdropSetting)
  -- exit if now frame was given
  if not f then return end

  -- load raw and pixel perfect scaled border
  rawborder, border = GetBorderSize()

  -- load custom border if existing
  if inset then
    rawborder = inset / GetPerfectPixel()
    border = inset
  end

  -- detect if blizzard backdrops shall be used
  local blizz = C.appearance.border.force_blizz == "1" and true or nil
  backdrop = blizz and pfUI.backdrop_blizz_full or rawborder == 1 and pfUI.backdrop_thin or pfUI.backdrop
  border = blizz and math.max(border, 3) or border

  -- get the color settings
  br, bg, bb, ba = pfUI.api.GetStringColor(pfUI_config.appearance.border.background)
  er, eg, eb, ea = pfUI.api.GetStringColor(pfUI_config.appearance.border.color)

  if transp and transp < tonumber(ba) then ba = transp end

  -- use legacy backdrop handling
  if legacy then
    if backdropSetting then f:SetBackdrop(backdropSetting) end
    f:SetBackdrop(backdrop)
    f:SetBackdropColor(br, bg, bb, ba)
    f:SetBackdropBorderColor(er, eg, eb , ea)
  else
    -- increase clickable area if available
    if f.SetHitRectInsets then
      f:SetHitRectInsets(-border,-border,-border,-border)
    end

    -- use new backdrop behaviour
    if not f.backdrop then
      if f:GetBackdrop() then f:SetBackdrop(nil) end

      local b = CreateFrame("Frame", nil, f)
      level = f:GetFrameLevel()
      if level < 1 then
        b:SetFrameLevel(level)
      else
        b:SetFrameLevel(level - 1)
      end

      f.backdrop = b
    end

    f.backdrop:SetPoint("TOPLEFT", f, "TOPLEFT", -border, border)
    f.backdrop:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", border, -border)
    f.backdrop:SetBackdrop(backdrop)
    f.backdrop:SetBackdropColor(br, bg, bb, ba)
    f.backdrop:SetBackdropBorderColor(er, eg, eb , ea)

    if blizz then
      if not f.backdrop_border then
        local border = CreateFrame("Frame", nil, f.backdrop)
        border:SetFrameLevel(level + 2)
        f.backdrop_border = border

        local hookSetBackdropBorderColor = f.backdrop.SetBackdropBorderColor
        f.backdrop.SetBackdropBorderColor = function(self, r, g, b, a)
          f.backdrop_border:SetBackdropBorderColor(r, g, b, a)
          hookSetBackdropBorderColor(f.backdrop, r, g, b, a)
        end
      end

      f.backdrop_border:SetAllPoints(f.backdrop)
      f.backdrop_border:SetBackdrop(pfUI.backdrop_blizz_border)
      f.backdrop_border:SetBackdropBorderColor(er, eg, eb , ea)
    end
  end
end

-- [ Create FontString ]
-- Get-or-create a FontString attached to `f` as the named field. Idempotent —
-- subsequent calls return the existing FontString. Defaults to pfUI's typical
-- font style: default font at config size, OUTLINE flag, OVERLAY layer.
-- 'f'      [frame]   parent frame
-- 'key'    [string]  field name on `f` to stash the FontString (e.g. "scoreText")
-- 'layer'  [string]  draw layer. Defaults to "OVERLAY".
-- 'size'   [int]     font size. Defaults to C.global.font_size.
-- 'flags'  [string]  font flags. Defaults to "OUTLINE".
-- 'font'   [string]  font path. Defaults to pfUI.font_default.
function pfUI.api.CreateFontString(f, key, layer, size, flags, font)
  if not f or not key then return end
  if f[key] then return f[key] end

  local fs = f:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFont(font or pfUI.font_default, size or C.global.font_size, flags or "OUTLINE")
  f[key] = fs
  return fs
end

-- [ Create Shadow ]
-- Creates a pfUI compatible frame as shadow element
-- 'f'          [frame]         the frame which should get a backdrop.
function pfUI.api.CreateBackdropShadow(f)
  -- exit if now frame was given
  if not f then return end

  if f.backdrop_shadow or pfUI_config.appearance.border.shadow ~= "1" then
    return
  end

  local anchor = f.backdrop or f
  f.backdrop_shadow = CreateFrame("Frame", nil, anchor)
  f.backdrop_shadow:SetFrameStrata("BACKGROUND")
  f.backdrop_shadow:SetFrameLevel(1)
  f.backdrop_shadow:SetPoint("TOPLEFT", anchor, "TOPLEFT", -5, 5)
  f.backdrop_shadow:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 5, -5)
  f.backdrop_shadow:SetBackdrop(pfUI.backdrop_shadow)
  f.backdrop_shadow:SetBackdropBorderColor(0, 0, 0, tonumber(pfUI_config.appearance.border.shadow_intensity))
end

-- [ Set Castbar Shield ]
-- Colors a castbar for a cast that none of the player's own interrupts or
-- silences can stop. The bar and the icon's border both take the shield color,
-- so the state still reads on a bar configured without an icon. The fill also
-- gets diagonal stripes, tiled at the image's own size so they keep their
-- spacing as the fill grows or shrinks. They sit on OVERLAY, under the bar's
-- text on the same layer. Not shielded restores the normal cast/channel color
-- and the configured border.
-- 'bar'        [frame]     the castbar statusbar
-- 'icon'       [frame]     the icon frame, or nil for a bar without one
-- 'shielded'   [bool]      whether the cast is uninterruptible
-- 'isChannel'  [bool]      selects the unshielded color
function pfUI.api.SetCastbarShield(bar, icon, shielded, isChannel)
  if shielded then
    bar:SetStatusBarColor(pfUI.api.GetStringColor(C.appearance.castbar.shieldcolor))
  else
    bar:SetStatusBarColor(pfUI.api.GetStringColor(C.appearance.castbar[isChannel and "channelcolor" or "castbarcolor"]))
  end

  if shielded and not bar.shieldstripes then
    bar.shieldstripes = bar:CreateTexture(nil, "OVERLAY")
    bar.shieldstripes:SetTexture(pfUI.media["img:stripes"])
    bar.shieldstripes:SetHorizTile(true)
    bar.shieldstripes:SetVertTile(true)
    bar.shieldstripes:SetVertexColor(1, 1, 1, .3)
    bar.shieldstripes:SetAllPoints(bar:GetStatusBarTexture())
  end
  if bar.shieldstripes then
    bar.shieldstripes:SetShown(shielded)
  end

  local iconborder = icon and icon.backdrop
  if not iconborder then return end

  if shielded then
    iconborder:SetBackdropBorderColor(pfUI.api.GetStringColor(C.appearance.castbar.shieldcolor))
  else
    iconborder:SetBackdropBorderColor(pfUI.api.GetStringColor(C.appearance.border.color))
  end
end

-- [ Bar Layout Options ] --
-- 'barsize'  size of bar in number of buttons
-- returns:   array of options as strings for pfUI.gui.bar: every grid
--            that fits the bar exactly, plus common uneven ones
function pfUI.api.BarLayoutOptions(barsize)
  assert(barsize > 0 and barsize <= NUM_ACTIONBAR_BUTTONS,"BarLayoutOptions: barsize "..tostring(barsize).." is invalid")
  local options, seen = {}, {}
  local function add(option)
    if not seen[option] then table.insert(options, option); seen[option] = true end
  end
  for cols = 1, barsize do
    if barsize % cols == 0 then
      add(string.format("%d x %d", cols, barsize / cols))
    end
  end
  for _, option in ipairs({
    "1 x 12", "1 x 10", "2 x 10", "2 x 5", "3 x 10", "3 x 5", "3 x 3",
    "5 x 3", "10 x 3", "5 x 2", "10 x 2", "10 x 1", "12 x 1"
  }) do add(option) end
  table.sort(options, function(a, b)
    local _, _, ac, ar = string.find(a, "(%d+)%s*x%s*(%d+)")
    local _, _, bc, br = string.find(b, "(%d+)%s*x%s*(%d+)")
    ac, ar = tonumber(ac) or 1, tonumber(ar) or 1
    bc, br = tonumber(bc) or 1, tonumber(br) or 1
    local ah = ac >= ar and 0 or 1
    local bh = bc >= br and 0 or 1
    if ah ~= bh then return ah < bh end
    if ah == 0 then if ac ~= bc then return ac > bc end; return ar < br
    else if ar ~= br then return ar > br end; return ac < bc end
  end)
  return options
end

-- 'formfactor' has to be a "cols x rows" string; the actionbar module resets
-- a stored layout that isn't one before it lays out a bar
local function ResolveBarLayout(barsize, formfactor, uneven)
  local _, _, a, b = string.find(formfactor, "(%d+)%s*x%s*(%d+)")
  local cols, rows = tonumber(a), tonumber(b)
  cols = math.min(NUM_ACTIONBAR_BUTTONS, math.max(1, cols))
  rows = math.min(NUM_ACTIONBAR_BUTTONS, math.max(1, rows))
  local orientation = string.upper(uneven or "DOWN")
  local mode = (orientation == "LEFT" or orientation == "RIGHT") and "cols" or "rows"
  if mode == "rows" then
    cols = math.max(1, math.min(cols, barsize))
    rows = math.max(1, math.ceil(barsize / cols))
  else
    rows = math.max(1, math.min(rows, barsize))
    cols = math.max(1, math.ceil(barsize / rows))
  end
  return cols, rows, mode, orientation
end

-- [ Bar Layout Size ] --
-- 'bar'        frame reference,
-- 'barsize'    integer number of buttons,
-- 'formfactor' string formfactor in cols x rows,
-- 'padding'    the spacing between buttons
function pfUI.api.BarLayoutSize(bar,barsize,formfactor,iconsize,bordersize,padding,uneven,fillmode)
  assert(barsize > 0 and barsize <= NUM_ACTIONBAR_BUTTONS,"BarLayoutSize: barsize "..tostring(barsize).." is invalid")
  local cols, rows = ResolveBarLayout(barsize, formfactor, uneven)
  local width = (iconsize + bordersize*2+padding) * cols + padding
  local height = (iconsize + bordersize*2+padding) * rows + padding
  bar._size = {width,height}
  return bar._size
end

-- [ Bar Button Anchor ] --
-- 'button'       frame reference
-- 'basename'     name of button frame without index
-- 'buttonindex'  index number of button on bar
-- 'formfactor'   string formfactor in cols x rows
-- 'iconsize'     size of the button
-- 'bordersize'   default bordersize
-- 'padding'      the spacing between buttons
function pfUI.api.BarButtonAnchor(button,basename,buttonindex,barsize,formfactor,iconsize,bordersize,padding,uneven,fillmode)
  assert(barsize > 0 and barsize <= NUM_ACTIONBAR_BUTTONS,"BarButtonAnchor: barsize "..tostring(barsize).." is invalid")
  local cols, rows, mode, orientation = ResolveBarLayout(barsize, formfactor, uneven)

  -- fillmode: remap buttonindex to slotindex (grid position in native fill order)
  -- only needed when fill direction differs from layout mode
  local slotindex = buttonindex
  if fillmode == "row" and mode == "cols" then
    local full = math.floor(barsize / rows)
    local rem = barsize - full * rows
    local n = 0
    for r = 1, rows do
      local w = full + ((r <= rem) and 1 or 0)
      if n + w >= buttonindex then
        local c = buttonindex - n
        slotindex = (c - 1) * rows + r
        break
      end
      n = n + w
    end
  elseif fillmode == "col" and mode == "rows" then
    local full = math.floor(barsize / cols)
    local rem = barsize - full * cols
    local n = 0
    for c = 1, cols do
      local h = full + ((c <= rem) and 1 or 0)
      if n + h >= buttonindex then
        local r = buttonindex - n
        slotindex = (r - 1) * cols + c
        break
      end
      n = n + h
    end
  end

  local parent = button:GetParent()
  local step = iconsize + bordersize*2 + padding
  local row, col
  if mode == "cols" then
    col = math.ceil(slotindex / rows)
    row = slotindex - ((col-1) * rows)
  else
    row = math.ceil(slotindex / cols)
    col = slotindex - ((row-1) * cols)
  end
  if mode == "cols" and orientation == "LEFT" then
    local final_col = math.ceil(barsize / rows)
    local count = barsize - (final_col - 1) * rows
    if count > 0 and count < rows then
      if col == final_col then col = 1 else col = col + 1 end
    end
  elseif mode == "rows" and orientation == "UP" then
    local final_row = math.ceil(barsize / cols)
    local count = barsize - (final_row - 1) * cols
    if count > 0 and count < cols then
      if row == final_row then row = 1 else row = row + 1 end
    end
  end
  local x = bordersize + padding + (col - 1) * step
  local y = -bordersize - padding - (row - 1) * step
  if slotindex == 1 then
    button._anchor = {"TOPLEFT", parent, "TOPLEFT", x, y}
  else
    button._anchor = {"TOPLEFT", parent, "TOPLEFT", x, y}
    if mode == "cols" then
      local final_col = math.ceil(barsize / rows)
      local count = barsize - (final_col - 1) * rows
      local target_col = (orientation == "LEFT") and 1 or cols
      if count > 0 and count < rows and col == target_col and row == 1 then
        button._anchor[5] = button._anchor[5] - (rows - count) * step / 2
      end
    else
      local final_row = math.ceil(barsize / cols)
      local count = barsize - (final_row - 1) * cols
      local target_row = (orientation == "UP") and 1 or rows
      if count > 0 and count < cols and row == target_row and col == 1 then
        button._anchor[4] = button._anchor[4] + (cols - count) * step / 2
      end
    end
  end
  return button._anchor
end

-- [ MouseIsOverHitRect ] --
-- Like frame:IsMouseOver(), but tests the frame's hit rect, the area the
-- engine uses for mouse focus and OnEnter/OnLeave. CreateBackdrop widens
-- that rect by the border, so plain IsMouseOver misses a band around it.
-- 'frame'      the frame to test
-- return       true when the cursor is inside the frame's hit rect
function pfUI.api.MouseIsOverHitRect(frame)
  if not frame.GetHitRectInsets then return frame:IsMouseOver() end
  local left, right, top, bottom = frame:GetHitRectInsets()
  return frame:IsMouseOver(-top, bottom, left, -right)
end

-- [ Enable Autohide ] --
-- 'frame'  the frame that should be hidden
function pfUI.api.EnableAutohide(frame, timeout, combat)
  if not frame then return end
  local timeout = timeout

  frame.hover = frame.hover or CreateFrame("Frame", frame:GetName() .. "Autohide", frame)
  frame.hover:SetParent(frame)
  frame.hover:SetAllPoints(frame)
  frame.hover.parent = frame
  frame.hover:Show()

  if not frame.hover.fade then
    frame.hover.fade = frame:CreateAnimationGroup()
    frame.hover.fade:SetToFinalAlpha(true)
    local fade = frame.hover.fade:CreateAnimation("Alpha")
    fade:SetChange(-1)
    fade:SetDuration(1)
  end

  if combat then
    frame.hover:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame.hover:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame.hover:SetScript("OnEvent", function()
      if event == "PLAYER_REGEN_DISABLED" then
        this.fade:Stop()
        this.parent:SetAlpha(1)
        this.activeTo = "keep"
      elseif event == "PLAYER_REGEN_ENABLED" then
        this.activeTo = GetTime() + timeout
      end
    end)
  end

  frame.hover:SetScript("OnUpdate", function()
    -- throttle to 0.05s
    if (this.tick or 0) > GetTime() then return end
    this.tick = GetTime() + 0.05

    if this.activeTo == "keep" then return end

    if this:IsMouseOver(10, -10, -10, 10) then
      this.activeTo = GetTime() + timeout
      this.fade:Stop()
      this.parent:SetAlpha(1)
    elseif this.activeTo then
      if this.activeTo < GetTime() and this.parent:GetAlpha() > 0 and not this.fade:IsPlaying() then
        this.fade:Play()
      end
    else
      this.activeTo = GetTime() + timeout
    end
  end)
end

-- [ Disable Autohide ] --
-- 'frame'  the frame that should get the autohide removed
function pfUI.api.DisableAutohide(frame)
  if not frame then return end
  if not frame.hover then return end

  frame.hover:SetScript("OnEvent", nil)
  frame.hover:SetScript("OnUpdate", nil)
  frame.hover:Hide()
  frame.hover.fade:Stop()
  frame:SetAlpha(1)
end

-- [ GetColorGradient ] --
-- 'perc'     percentage (0-1)
-- return r,g,b and hexcolor
local gradientcolors = {}
function pfUI.api.GetColorGradient(perc)
  if not perc or perc ~= perc then perc = 0 end -- NaN guard: NaN ~= NaN is true in Lua
  perc = perc > 1 and 1 or perc
  perc = perc < 0 and 0 or perc
  perc = floor(perc*100)/100

  local index = perc
  if not gradientcolors[index] then
    local r1, g1, b1, r2, g2, b2

    if perc <= 0.5 then
      perc = perc * 2
      r1, g1, b1 = 1, 0, 0
      r2, g2, b2 = 1, 1, 0
    else
      perc = perc * 2 - 1
      r1, g1, b1 = 1, 1, 0
      r2, g2, b2 = 0, 1, 0
    end

    local r = round(r1 + (r2 - r1) * perc, 4)
    local g = round(g1 + (g2 - g1) * perc, 4)
    local b = round(b1 + (b2 - b1) * perc, 4)
    local h = pfUI.api.rgbhex(r,g,b)

    gradientcolors[index] = {}
    gradientcolors[index].r = r
    gradientcolors[index].g = g
    gradientcolors[index].b = b
    gradientcolors[index].h = h
  end

  return gradientcolors[index].r,
    gradientcolors[index].g,
    gradientcolors[index].b,
    gradientcolors[index].h
end

-- [ GetNoNameObject ] --
-- Finds the first unnamed region or child of a frame that matches the filters
-- 'frame'      [frame]        parent frame
-- 'objtype'    [string]       "Texture", "FontString" or "Button"
-- 'layer'      [string]       draw layer of a region (optional)
-- 'arg1'       [string]       substring of the texture path (Texture, Button)
--                             or the text (FontString) (optional)
-- 'arg2'       [string]       substring of a button's text (optional)
-- return object

-- a missing value or filter counts as a match
local function Matches(value, needle)
  return not needle or not value or value:find(needle, 1, true)
end

function pfUI.api.GetNoNameObject(frame, objtype, layer, arg1, arg2)
  -- A nil/non-frame parent otherwise dies on frame:GetRegions()/:GetChildren()
  -- below, where the message would name this line, shared by every caller;
  -- level 2 names the offending skin instead.
  if type(frame) ~= "table" or not frame.GetRegions then
    error("GetNoNameObject: invalid parent frame", 2)
  end

  local isRegion = objtype == "Texture" or objtype == "FontString"
  local objects = isRegion and { frame:GetRegions() } or { frame:GetChildren() }

  for _, object in ipairs(objects) do
    if object:GetObjectType() == objtype and (not layer or object:GetDrawLayer() == layer) then
      if objtype == "Texture" then
        local texture = object:GetTexture()
        if texture ~= "Interface\\BUTTONS\\WHITE8X8" and Matches(texture, arg1) then return object end
      elseif objtype == "FontString" then
        if Matches(object:GetText(), arg1) then return object end
      elseif objtype == "Button" then
        local normal = object:GetNormalTexture()
        if normal and Matches(normal:GetTexture(), arg1) and Matches(object:GetText(), arg2) then return object end
      end
    end
  end
end

-- [ TryMemoizedFuncLoadstringForSpellCasts ]
-- Memoizes lua function strings for spell casts to improve performance.
-- Supports both string functions and direct function values.
-- 'funcOrStr'  [function|string]  Either a function or a lua string to execute
-- return:      [function|nil]     The function to execute, or nil on error
local memoizedFuncs = {}
function pfUI.api.TryMemoizedFuncLoadstringForSpellCasts(funcOrStr)
  -- If it's already a function, return it directly
  if type(funcOrStr) == "function" then
    return funcOrStr
  end
  
  -- If it's a string, try to memoize it
  if type(funcOrStr) == "string" then
    -- Check if we've already compiled this string
    if memoizedFuncs[funcOrStr] then
      return memoizedFuncs[funcOrStr]
    end
    
    -- Try to compile the string
    local func = loadstring(funcOrStr)
    if func then
      memoizedFuncs[funcOrStr] = func
      return func
    end
  end
  
  return nil
end