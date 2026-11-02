-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

-- Every pfUI cooldown is a Cooldown frame from CreateCooldown. The settings
-- of the feature it belongs to pick its timers: none, numbers, sweep or both.
-- Settings -> Cooldown (C.cooldown) sets one font and one formatter for them
-- all. The numbers are the frame's own countdown (ClassicAPI): the engine
-- ticks them, gated by the countdownForCooldowns cvar. Other addons' Cooldown
-- frames take the "foreign" timers as their timers start.

local function ShowNumbers(mode)
  return mode == "text" or mode == "both"
end

local function ShowSweep(mode)
  return mode == "sweep" or mode == "both"
end

-- every cooldown CreateCooldown made, for UpdateCooldowns
local cooldowns = {}

local function ColorCode(color)
  local r, g, b = pfUI.api.GetStringColor(color)
  return pfUI.api.rgbhex(r, g, b)
end

-- The formatter behind every pfUI time: the number in its unit's color,
-- rounded up, with a unit (m/h/d) once the unit below passes 99. Cooldown
-- frames share it instead of copying it, so new breakpoints reach every
-- countdown on its next update.
local formatter

local function UpdateFormatter()
  local up = Enum.NumericRuleFormatRounding.Up
  local tenths = C.cooldown.milliseconds == "1"

  formatter:SetBreakpoints({
    { threshold = 0, step = tenths and .1 or 1, rounding = up, format = ColorCode(C.cooldown.lowcolor) .. (tenths and "%.1f" or "%d") .. "|r" },
    { threshold = 5, step = 1, rounding = up, format = ColorCode(C.cooldown.normalcolor) .. "%d|r" },
    { threshold = 99, format = ColorCode(C.cooldown.minutecolor) .. "%d|rm", components = { { div = 60, step = 1, rounding = up } } },
    { threshold = 5940, format = ColorCode(C.cooldown.hourcolor) .. "%d|rh", components = { { div = 3600, step = 1, rounding = up } } },
    { threshold = 356400, format = ColorCode(C.cooldown.daycolor) .. "%d|rd", components = { { div = 86400, step = 1, rounding = up } } },
  })
end

local function GetFormatter()
  if not formatter then
    formatter = C_StringUtil.CreateNumericRuleFormatter()
    UpdateFormatter()
  end
  return formatter
end

-- [ GetCooldownFontSize ] --
-- 'height'   [number]   the height of the frame the numbers sit on
-- return     [number]   the font size of cooldown numbers on that frame
function pfUI.api.GetCooldownFontSize(height)
  local size = tonumber(C.cooldown.font_size)
  if C.cooldown.dynamicsize == "1" and height > 0 then
    size = math.max(height * .64, size)
  end
  return size
end

-- sizes the numbers to the height of the frame the cooldown covers
local function UpdateFont(cooldown, height)
  cooldown:GetCountdownFontString():SetFont(pfUI.media[C.cooldown.font], pfUI.api.GetCooldownFontSize(height), "OUTLINE")
end

-- a pfUI cooldown covers its parent, so it resizes with it; a hidden one is
-- laid out, and this runs, as it shows
local function OnSizeChanged(cooldown, width, height)
  UpdateFont(cooldown, height)
end

-- applies its timers setting to one of pfUI's cooldowns
local function SetupCooldown(cooldown)
  local kind = cooldown.pfCooldownKind
  local mode = cooldown.pfCooldownConfig[cooldown.pfCooldownKey]
  local sweep = ShowSweep(mode) and not cooldown.pfTimeLeftOnly

  cooldown:SetHideCountdownNumbers(not ShowNumbers(mode))
  cooldown:SetDrawSwipe(sweep)
  cooldown:SetDrawBling(sweep)
  cooldown:SetReverse(kind == "aura")
  cooldown:SetMinimumCountdownDuration(kind == "spell" and tonumber(C.cooldown.threshold) * 1000 or 0)
  cooldown:SetCountdownFormatter(GetFormatter())
  UpdateFont(cooldown, cooldown:GetParent():GetUnscaledHeight())
end

-- applies the "foreign" timers to another addon's cooldown. They only take
-- the numbers or the sweep away, which the addon may have set up itself, so
-- turning one back on needs a reload.
local function SetupForeign(cooldown)
  local mode = C.cooldown.foreign_timers

  if not ShowSweep(mode) then
    cooldown:SetDrawSwipe(false)
    cooldown:SetDrawBling(false)
  end

  -- omnicc's flag for cooldowns that want no numbers
  if not ShowNumbers(mode) or cooldown.noCooldownCount then
    cooldown:SetHideCountdownNumbers(true)
    return
  end

  cooldown:SetMinimumCountdownDuration(tonumber(C.cooldown.threshold) * 1000)
  cooldown:SetCountdownFormatter(GetFormatter())
  UpdateFont(cooldown, (cooldown:GetParent() or cooldown):GetUnscaledHeight())
end

-- runs as a pfUI cooldown's timer starts: a timer with a total brings back
-- the sweep a time-left-only one took away
local function StartTimer(cooldown, timeleftOnly)
  if cooldown.pfTimeLeftOnly ~= timeleftOnly then
    cooldown.pfTimeLeftOnly = timeleftOnly
    SetupCooldown(cooldown)
  end
end

-- every timer, pfUI's or another addon's, Cooldown frame or 1.12 indicator
-- Model, is started through CooldownFrame_SetTimer
hooksecurefunc("CooldownFrame_SetTimer", function(cooldown)
  -- the Models have no numbers and keep the stock timer
  if not cooldown:IsObjectType("Cooldown") then return end

  if cooldown.pfCooldownKind then
    StartTimer(cooldown, nil)
  else
    SetupForeign(cooldown)
  end
end)

-- [ CreateCooldown ] --
-- Creates one of pfUI's cooldowns: a Cooldown frame over all of 'parent'.
-- Start it with CooldownFrame_SetTimer.
-- 'parent'   [frame]    the frame the cooldown covers
-- 'kind'     [string]   what it times: "spell" (spells and items: the sweep
--                       fills, no numbers for the global cooldown), "aura"
--                       (the sweep drains) or "timer" (the sweep fills)
-- 'config'   [table]    the settings that hold its timers
-- 'key'      [string]   the timers setting in 'config': "off", "text",
--                       "sweep" or "both"
-- 'name'     [string]   optional frame name
-- return     [frame]    the Cooldown frame
function pfUI.api.CreateCooldown(parent, kind, config, key, name)
  local cooldown = CreateFrame("Cooldown", name, parent, "CooldownFrameTemplate")
  cooldown.pfCooldownKind = kind
  cooldown.pfCooldownConfig = config
  cooldown.pfCooldownKey = key
  cooldown:SetScript("OnSizeChanged", OnSizeChanged)
  table.insert(cooldowns, cooldown)
  SetupCooldown(cooldown)
  return cooldown
end

-- [ SetCooldownTimeLeft ] --
-- Starts a cooldown from its time left alone, for timers that report no
-- total (weapon enchants): the numbers show, the sweep stays off until a
-- timer with a total starts.
-- 'cooldown'   [frame]    a cooldown from CreateCooldown
-- 'timeleft'   [number]   the seconds left
function pfUI.api.SetCooldownTimeLeft(cooldown, timeleft)
  StartTimer(cooldown, true)
  cooldown:SetCooldown(GetTime(), timeleft)
end

-- [ UpdateCooldowns ] --
-- Applies changed cooldown settings to every pfUI cooldown.
function pfUI.api.UpdateCooldowns()
  if formatter then UpdateFormatter() end
  for _, cooldown in ipairs(cooldowns) do
    SetupCooldown(cooldown)
  end
end

-- [ GetAuraTimer ] --
-- The cooldown start and duration of an aura from C_UnitAuras, 0, 0 when it
-- has none. Talent-extended auras run past their Spell.dbc base duration, and
-- a start in the future would hold the timer until then, so the start is
-- capped to now.
-- 'duration'         [number]   the aura's duration
-- 'expirationTime'   [number]   the aura's expiration time
-- return             [number]   start, duration
function pfUI.api.GetAuraTimer(duration, expirationTime)
  if expirationTime <= 0 then return 0, 0 end

  local now = GetTime()
  local start, dur = expirationTime - duration, duration
  if start > now or dur <= 0 then
    start, dur = now, expirationTime - now
  end

  if dur <= 0 then return 0, 0 end
  return start, dur
end

-- [ GetTimeFormatter ] --
-- The formatter cooldown numbers use, for other timers to show time the same
-- way. Hold it rather than a copy: a settings change updates it in place.
-- return        [formatter]   a NumericRuleFormatter
function pfUI.api.GetTimeFormatter()
  return GetFormatter()
end
