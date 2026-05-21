-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

-- return instantly when another libspell is already active
if pfUI.api.libspell then return end

local libspell = {}

-- [ GetSpellMaxRank ]
-- Returns the maximum rank of a players spell.
-- 'name'       [string]            spellname to query
-- return:      [string],[number]   maximum rank in characters and the number
--                                  e.g "Rank 1" and "1"
local spellmaxrank = {}
function libspell.GetSpellMaxRank(name)
  local cache = spellmaxrank[name]
  if cache then return cache[1], cache[2] end
  local name = string.lower(name)

  local rank = { 0, nil}
  for i = 1, GetNumSpellTabs() do
    local _, _, offset, num = GetSpellTabInfo(i)
    local bookType = BOOKTYPE_SPELL
    for id = offset + 1, offset + num do
      local spellName, spellRank = GetSpellName(id, bookType)
      if name == string.lower(spellName) then
        if not rank[2] then rank[2] = spellRank end

        local _, _, numRank = string.find(spellRank, " (%d+)$")
        if numRank and tonumber(numRank) > rank[1] then
          rank = { tonumber(numRank), spellRank}
        end
      end
    end
  end

  spellmaxrank[name] = { rank[2], rank[1] }
  return rank[2], rank[1]
end

-- [ GetSpellIndex ]
-- Returns the spellbook index and bookid of the given spell.
-- 'name'       [string]            spellname to query
-- 'rank'       [string]            rank to query (optional)
-- return:      [number],[string]   spell index and spellbook id
local spellindex = {}
function libspell.GetSpellIndex(name, rank)
  if not name then return end
  name = string.lower(name)
  local cache = spellindex[name..(rank and ("("..rank..")") or "")]
  if cache then return cache[1], cache[2] end

  if not rank then rank = libspell.GetSpellMaxRank(name) end

  for i = 1, GetNumSpellTabs() do
    local _, _, offset, num = GetSpellTabInfo(i)
    local bookType = BOOKTYPE_SPELL
    for id = offset + 1, offset + num do
      local spellName, spellRank = GetSpellName(id, bookType)
      if rank and rank == spellRank and name == string.lower(spellName) then
        spellindex[name.."("..rank..")"] = { id, bookType }
        return id, bookType
      elseif not rank and name == string.lower(spellName) then
        spellindex[name] = { id, bookType }
        return id, bookType
      end
    end
  end

  spellindex[name..(rank and ("("..rank..")") or "")] = { nil }
  return nil
end

-- [ GetSpellInfo ]
-- Returns several information about a spell.
-- 'index'      [string/number]     Spellname or Index of a spell in the spellbook
-- 'bookType'   [string]            Type of spellbook (optional)
-- return:
--              [string]            Name of the spell
--              [string]            Secondary text associated with the spell
--                                  (e.g."Rank 5", "Racial", etc.)
--              [string]            Path to an icon texture for the spell
--              [number]            Casting time of the spell in milliseconds
--              [number]            Minimum range from the target required to cast the spell
--              [number]            Maximum range from the target at which you can cast the spell
--              [number]            The numeric spell-id of the spell
--              [number]            The type of the spellbook that the spell is in
local spellinfo = {}
function libspell.GetSpellInfo(index, bookType)
  local cache = spellinfo[index]
  if cache then return cache[1], cache[2], cache[3], cache[4], cache[5], cache[6], cache[7], cache[8] end

  local slot
  if type(index) == "string" then
    local _, _, sname, srank = string.find(index, '(.+)%((.+)%)')
    local name = sname or index
    local rank = srank or libspell.GetSpellMaxRank(name)
    slot, bookType = libspell.GetSpellIndex(name, rank)
  else
    if not bookType or (bookType ~= BOOKTYPE_SPELL and bookType ~= BOOKTYPE_PET) then
      return nil
    end
    slot = index
  end

  if not slot or not bookType then return nil end

  -- ClassicAPI's GetSpellInfo returns: name, rank, icon, cost, isFunnel, powerType,
  -- castTime(ms), minRange, maxRange, spellID. Keep libspell's historical positional
  -- shape (castingTime at 4, ranges at 5/6, slot+bookType at 7/8).
  local name, rank, icon, _, _, _, castingTime, minRange, maxRange = GetSpellInfo(slot, bookType)

  spellinfo[index] = { name, rank, icon, castingTime, minRange, maxRange, slot, bookType }
  return name, rank, icon, castingTime, minRange, maxRange, slot, bookType
end

-- Reset all spell caches whenever new spells are learned/unlearned
local resetcache = CreateFrame("Frame")
resetcache:RegisterEvent("LEARNED_SPELL_IN_TAB")
resetcache:SetScript("OnEvent", function()
  spellmaxrank, spellindex, spellinfo = {}, {}, {}
end)

-- add libspell to pfUI API
pfUI.api.libspell = libspell
