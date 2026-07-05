-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

-- [[ Constants ]]--
EVENTS_MINIMAP_ZONE_UPDATE = {"PLAYER_ENTERING_WORLD", "MINIMAP_ZONE_CHANGED"}

MICRO_BUTTONS = {
  'CharacterMicroButton', 'SpellbookMicroButton', 'TalentMicroButton',
  'QuestLogMicroButton', 'SocialsMicroButton', 'WorldMapMicroButton',
  'MainMenuMicroButton', 'HelpMicroButton',
}

NAMEPLATE_OBJECTORDER = { "border", "glow", "name", "level", "levelicon", "raidicon" }

NAMEPLATE_FRAMETYPE = "Button"

MINIMAP_TRACKING_FRAME = _G.MiniMapTrackingFrame

FRIENDS_NAME_LOCATION = "ButtonTextNameLocation"

COOLDOWN_FRAME_TYPE = "Model"
LOOT_BUTTON_FRAME_TYPE = "LootButton"

PLAYER_BUFF_START_ID = -1

ACTIONBAR_SECURE_TEMPLATE_BAR = nil
ACTIONBAR_SECURE_TEMPLATE_BUTTON = nil
UNITFRAME_SECURE_TEMPLATE = nil

--[[ Vanilla API Extensions ]]--
-- Safe post-hook helper. The global `hooksecurefunc` belongs to ClassicAPI
-- (its C implementation); this wrapper only adds pfUI's missing-target guard:
-- ClassicAPI errors when target[name] isn't a function, whereas a lot of our
-- call sites hook optional/late-loaded frames and rely on a silent no-op.
-- Normalizes the string form, skips when the target is absent, then delegates
-- to the C version (uncapped args, callback-pcall, taint parity).
function pfUI.hooksecurefunc(tbl, name, func)
  if type(tbl) == "string" then tbl, name, func = _G, tbl, name end
  if not tbl or type(tbl[name]) ~= "function" then return end
  return _G.hooksecurefunc(tbl, name, func)
end

do -- GetItemInfo
  local name, link, rarity, minlevel, itype, isubtype, stack
  function GetItemInfo(item)
    if not item then return end
    name, link, rarity, minlevel, itype, isubtype, stack = _G.GetItemInfo(item)
    return name, link, rarity, nil, minlevel, itype, isubtype, stack
  end
end

do -- RunMacroText
  local obj = { ["GetText"] = function(self) return self.text end }
  obj = setmetatable(obj, {__index = function(tab,key)
    local value = function() return end
    rawset(tab,key,value)
    return value
  end})

  function RunMacroText(text)
    obj.text = text
    ChatEdit_ParseText(obj, 1)
  end
end