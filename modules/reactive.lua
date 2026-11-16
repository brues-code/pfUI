-- Reactive Spell Indicator using C_Spell.IsSpellUsable
-- Shows when reactive abilities like Overpower, Revenge, Execute are usable
pfUI:RegisterModule("reactive", function ()
  if C.unitframes.reactive_indicator ~= "1" then return end

  -- Reactive spells by class
  local reactiveSpells = {
    WARRIOR = {
      7384, -- Overpower
      6572, -- Revenge
      5283, -- Execute
    },
    ROGUE = {
      76, -- Riposte
    },
    HUNTER = {
      1495, -- Mongoose Bite
      19306, -- Counterattack
    },
  }

  local spells = reactiveSpells[UnitClassBase("player")]
  if not spells then return end

  local size = tonumber(C.unitframes.reactive_size) or 28

  pfUI.reactive = CreateFrame("Frame", "pfReactiveIndicator", UIParent)
  pfUI.reactive:SetFrameStrata("HIGH")
  local spellCount = table.getn(spells)
  pfUI.reactive:SetSize(size * spellCount + 4 * (spellCount - 1), size)
  pfUI.reactive:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
  pfUI.reactive:Hide()

  pfUI.reactive.icons = {}
  for i, spell in ipairs(spells) do
    local icon = CreateFrame("Frame", nil, pfUI.reactive)
    icon:SetSize(size, size)
    icon:SetPoint("LEFT", pfUI.reactive, "LEFT", (i-1) * (size + 4), 0)

    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints(icon)
    icon.texture:SetTexture(C_Spell.GetSpellTexture(spell))
    icon.texture:SetTexCoord(.08, .92, .08, .92)

    icon.glow = icon:CreateTexture(nil, "OVERLAY")
    icon.glow:SetPoint("TOPLEFT", icon, "TOPLEFT", -4, 4)
    icon.glow:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 4, -4)
    icon.glow:SetTexture(pfUI.media["img:glow"])
    icon.glow:SetVertexColor(1, 1, 0, 0.8)

    CreateBackdrop(icon)
    icon:Hide()
    icon.spellName = C_Spell.GetSpellName(spell)
    pfUI.reactive.icons[i] = icon
  end

  UpdateMovable(pfUI.reactive)

  -- the client fires ACTIONBAR_UPDATE_USABLE whenever a spell's usability
  -- changes, reactive procs included
  local function Update()
    local anyVisible = false
    for _, icon in ipairs(pfUI.reactive.icons) do
      local usable = C_Spell.IsSpellUsable(icon.spellName)
      icon:SetShown(usable)
      anyVisible = anyVisible or usable
    end
    pfUI.reactive:SetShown(anyVisible)
  end

  pfUI.events:RegisterFrameEventAndCallback("ACTIONBAR_UPDATE_USABLE", Update)
  Update()
end)
