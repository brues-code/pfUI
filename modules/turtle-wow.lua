-- Turtle WoW only: loaded from init\turtle.xml, which only pfUI_Turtle.toc pulls in.
pfUI:RegisterModule("turtle-wow", function ()
  -- Manage Turtle WoW's GroupUI (Turtle_GroupUI addon) vs pfUI frames.
  --
  -- Turtle uses GroupClusterFrame1-8 for BOTH party AND raid display,
  -- and GroupPetsClusterFrame for pets only. GroupFrame_Toggle() controls
  -- the entire system via the GROUP_ENABLED global.
  --
  -- Logic:
  --   pfUI UF disabled (disable=="1")  -> don't touch Turtle at all
  --   In party (no raid):
  --     pfUI group visible=="1"        -> disable Turtle GroupUI, pfUI handles party
  --     pfUI group visible=="0"        -> enable Turtle GroupUI for party
  --   In raid:
  --     pfUI raid visible=="1"         -> disable Turtle GroupUI, pfUI handles raid
  --     pfUI raid visible=="0"         -> enable Turtle GroupUI for raid

  if C.unitframes.disable == "1" then
    -- pfUI unit frames are completely off, let Turtle handle everything
  else
    -- Set GROUP_REPLACE_PARTY early so Turtle's own init can use it
    GROUP_REPLACE_PARTY = "1"

    -- Hide Turtle GroupUI frames and disable mouse when pfUI handles group/raid.
    -- When pfUI does NOT handle them, we simply don't interfere - Turtle manages itself.
    -- Important: Do NOT unregister events - Turtle needs RAID_ROSTER_UPDATE etc.
    -- to react when group converts to raid (and vice versa).
    local function DisableTurtleGroupFrames()
      for i = 1, 8 do
        local f = _G["GroupClusterFrame"..i]
        if f then
          f:Hide()
          f:EnableMouse(false)
          for _, child in pairs({f:GetChildren()}) do
            child:EnableMouse(false)
          end
        end
      end
      if GroupPetsClusterFrame then
        GroupPetsClusterFrame:Hide()
        GroupPetsClusterFrame:EnableMouse(false)
      end
    end

    -- Check if pfUI is handling group or raid for the current situation
    local function pfUIHandlesGroupOrRaid()
      local disabled = C["disabled"] or {}
      if IsInRaid() then
        if not C.unitframes.raid then return false end
        -- Hide Turtle frames if: pfUI raid module is active, OR player disabled visibility
        if disabled["raid"] == "1" then
          return C.unitframes.raid.visible ~= "1"
        end
        return C.unitframes.raid.visible == "1"
      else
        if not C.unitframes.group then return false end
        if disabled["group"] == "1" then
          return C.unitframes.group.visible ~= "1"
        end
        return C.unitframes.group.visible == "1"
      end
    end

    HookAddonOrVariable("GroupFrame", function()
      -- After Turtle's own init, hide frames if pfUI handles them
      hooksecurefunc("GroupFrame_Toggle", function()
        if pfUIHandlesGroupOrRaid() then
          DisableTurtleGroupFrames()
        end
      end)

      -- After every group/raid update, re-hide if pfUI handles them
      hooksecurefunc("GroupFrame_Update", function()
        if pfUIHandlesGroupOrRaid() then
          DisableTurtleGroupFrames()
        end
      end)
    end)
  end

  local delay = CreateFrame("Frame")
  delay:SetScript("OnUpdate", function()
    this:Hide()

    -- correct positions of new game menu layout
    if GameMenuButtonShop and (GameMenuButtonPFUI or GameMenuButtonPFUIAddOns) then
      -- calculate new offset for the shop button
      local offset = 0
      local offset = GameMenuButtonPFUI and offset + 22 or offset
      local offset = GameMenuButtonPFUIAddOns and offset + 22 or offset
      local offset = offset > 0 and offset + 22 or offset

      -- move pfUI and addons to top position
      GameMenuButtonShop:ClearAllPoints()
      GameMenuButtonShop:SetPoint("TOP", 0, -offset)

      -- restore turtle wow's custom menu layout
      GameMenuButtonOptions:ClearAllPoints()
      GameMenuButtonOptions:SetPoint("TOP", GameMenuButtonShop, "BOTTOM", 0, -16)

      -- apply pfUI skin to the new shop button
      if pfUI.skin["Game Menu"] and pfUI_config["disabled"]["skin_Game Menu"] ~= "1" then
        local font = GameMenuButtonShop:GetFontString()
        font:SetTextColor(1,1,1,1)
        SkinButton(GameMenuButtonShop)
      end
    end

    -- apply chat styles to hardcore chat
    if pfUI.chat and pfUI.chat.left then
      -- read and parse chat bracket settings
      local left = "|r" .. string.sub(C.chat.text.bracket, 1, 1)
      local right = string.sub(C.chat.text.bracket, 2, 2) .. "|r"
      local default = " " .. "%s" .. "|r:" .. "\32"
      _G.CHAT_HARDCORE_GET = left .. "H" .. right .. default
    end

    -- remove ignore dropdown menu from chat
    if pfUI.chat then
      for index, value in ipairs(UnitPopupMenus["FRIEND"]) do
        if value == "IGNORE_PLAYER" then
          table.remove(UnitPopupMenus["FRIEND"], index)
          break
        end
      end
    end

    -- disable some new spells from tracking frame
    if pfUI.tracking then
      pfUI.tracking.invalidSpells["Earthshaker Slam"] = true

      -- reload spells and menu
      pfUI.tracking:RefreshSpells()
      pfUI.tracking:RefreshMenu()
    end

    -- disable turtle wow's map window implementation
    if pfUI.map and not Cartographer and not METAMAP_TITLE then
      _G.WorldMapFrame_Maximize()
      pfUI.map.loader:GetScript("OnEvent")()

      _G.WorldMapFrame_Minimize = function() return end
      _G.WorldMapFrame_Maximize = function() return end

      _G.WorldMapFrameMaximizeButton.Show = function() return end
      _G.WorldMapFrameMaximizeButton:Hide()

      _G.WorldMapFrameMinimizeButton.Show = function() return end
      _G.WorldMapFrameMinimizeButton:Hide()

      WorldMapFrameTitle.Show = function() return end
      WorldMapFrameTitle:Hide()
    end

    if pfUI.panel and pfPanelWidgetClock then
      pfPanelWidgetClock.Tooltip = function()
        GameTooltip:ClearLines()
        GameTooltip_SetDefaultAnchor(GameTooltip, this)
        local servertime, zonetime, time
        local zh, zm = GetGameTime()
        local sh, sm = zh, zm

        -- convert custom zonetime to servertime
        SetMapToCurrentZone()
        if GetCurrentMapContinent() == 1 then
          sh = sh + 12
          sh = sh >= 24 and sh - 24 or sh
        end
        
        -- perform am/pm calculations
        if C.global.twentyfour == "0" then
          local zn, sn = " AM", " AM"

          if zh == 0 then
            zh = 12
          elseif zh == 12 then
            zn = " PM"
          elseif zh > 12 then
            zh = zh - 12
            zn = " PM"
          end

          if sh == 0 then
            sh = 12
          elseif sh == 12 then
            sn = " PM"
          elseif sh > 12 then
            sh = sh - 12
            sn = " PM"
          end

          time = date("%I:%M %p")
          servertime = string.format("%.2d:%.2d %s", sh, sm, sn)
          zonetime = string.format("%.2d:%.2d %s", zh, zm, zn)
        else
          time = date("%H:%M")
          servertime = string.format("%.2d:%.2d", sh, sm)
          zonetime = string.format("%.2d:%.2d", zh, zm)
        end
        
        
        -- pick color for zone time based on day/night
        local zoneColor
        if zh >= 6 and zh < 18 then
          zoneColor = "|cffffbb00"  -- orange (day)
        else
          zoneColor = "|cff0074FF"  -- blue (night)
        end

        -- create the tooltip
        GameTooltip:AddLine("|cff555555" .. T["Time"])
        GameTooltip:AddDoubleLine(T["Localtime"],  "|cffffffff" .. time)
        GameTooltip:AddDoubleLine(T["Servertime"], "|cffffffff".. servertime)
        GameTooltip:AddDoubleLine(T["Zonetime"],  zoneColor .. zonetime)
        GameTooltip:AddLine(" ")
        if TimeManagerFrame then
          GameTooltip:AddDoubleLine(T["Left Click"], "|cffffffff" .. T["Show/Hide TimeManager"])
        else
          GameTooltip:AddDoubleLine(T["Left Click"], "|cffffffff" .. T["Show/Hide Timer"])
          GameTooltip:AddDoubleLine(T["Right Click"], "|cffffffff" .. T["Reset Timer"])
        end
        GameTooltip:Show()
      end
    end

    -- skin title dropdown menu
    -- taken from: https://github.com/doorknob6/pfUI-turtle/blob/master/skins/turtle/character.lua
    if TWTitles and pfUI.skin["Character"] and pfUI_config["disabled"]["skin_Character"] ~= "1" then
      CharacterLevelText:SetPoint("TOP", CharacterNameText, "BOTTOM", 0, -2)
      SkinDropDown(TWTitles)
      TWTitles:SetPoint("TOP", CharacterGuildText, "BOTTOM", 0, -2)
      TWTitlesText:SetPoint("LEFT", TWTitles.backdrop, "LEFT", 6, 2)
      CharacterResistanceFrame:SetPoint("TOP", TWTitles, "BOTTOM", 0, 0)
    end
  end)

  -- Synthetic Steady Shot cast bar. The engine treats Steady Shot as
  -- instant, but the arrow doesn't actually fire until the next ranged
  -- swing (~1.4s baseline). Drive a synthetic entry off Nampower's
  -- SPELL_QUEUE_EVENT so hunters see a tickdown matching the swing wait.
  -- castbar.lua reads pfUI.synthetic_casts[unit] as a fallback when
  -- C_Spell.UnitCastingInfo returns nil.
  pfUI_locale["enUS"]["customcast"]["TRUESHOT"] = "Steady Shot"
  pfUI_locale["zhCN"]["customcast"]["TRUESHOT"] = "稳固射击"
  pfUI.synthetic_casts = pfUI.synthetic_casts or {}

  local steadyShotName = L["customcast"]["TRUESHOT"]
  local STEADY_SHOT_ICON = "Interface\\Icons\\Ability_hunter_steadyshot"
  local STEADY_SHOT_DURATION_MS = 1400  -- not haste-scaled; close enough for the visual cue
  local ON_SWING_QUEUED, ON_SWING_QUEUE_POPPED = 0, 1

  local steadyShot = CreateFrame("Frame")
  steadyShot:RegisterEvent("SPELL_QUEUE_EVENT")
  steadyShot:SetScript("OnEvent", function()
    if event ~= "SPELL_QUEUE_EVENT" then return end
    local eventCode, spellId = arg1, arg2
    if eventCode ~= ON_SWING_QUEUED and eventCode ~= ON_SWING_QUEUE_POPPED then return end
    if C_Spell.GetSpellName(spellId) ~= steadyShotName then return end
    if eventCode == ON_SWING_QUEUED then
      local now = GetTime() * 1000
      pfUI.synthetic_casts["player"] = {
        name    = steadyShotName,
        icon    = STEADY_SHOT_ICON,
        startMs = now,
        endMs   = now + STEADY_SHOT_DURATION_MS,
        spellID = spellId,
      }
    else
      pfUI.synthetic_casts["player"] = nil
    end
  end)

  -- add skin to twow's talent inspect frame
  if pfUI.skin["Inspect"] and pfUI_config["disabled"]["skin_Inspect"] ~= "1" then
    local initialized = false

    HookAddonOrVariable("Blizzard_InspectUI", function()
      hooksecurefunc("InspectFrame_Show", function()
        -- break if theres nothing left to do
        if initialized then return end

        local _, border = GetBorderSize()

        -- adjust the inspect frame's Talents tab
        SkinTab(InspectFrameTab3)
        InspectFrameTab3:ClearAllPoints()
        InspectFrameTab3:SetPoint("LEFT", InspectFrameTab2, "RIGHT", border*2 + 1, 0)
        -- reload text position
        InspectFrameTab3:Hide()
        InspectFrameTab3:Show()

        -- the talent tree frame is created lazily; skin it once it exists
        if TWTalentFrame then
          StripTextures(InspectTalentsFrame)
          StripTextures(TWTalentFrame)
          StripTextures(TWTalentFrameScrollFrame)
          SkinScrollbar(TWTalentFrameScrollFrameScrollBar)

          -- skin + position the talent-tree tabs
          for i = 1, 3 do
            local tab = _G["TWTalentFrameTab"..i]
            if tab then
              SkinTab(tab)
              tab:ClearAllPoints()
              local lastTab = _G["TWTalentFrameTab"..(i-1)]
              if lastTab then
                tab:SetPoint("LEFT", lastTab, "RIGHT", border*2 + 1, 0)
              else
                tab:SetPoint("TOPLEFT", TWTalentFrameScrollFrame, "TOPLEFT", 2, tab:GetHeight() + 4)
              end
            end
          end

          -- skin each talent button
          for i = 1, (MAX_NUM_TALENTS or 100) do
            local talent = _G["TWTalentFrameTalent"..i]
            if talent then
              StripTextures(talent)
              SkinButton(talent, nil, nil, nil, _G["TWTalentFrameTalent"..i.."IconTexture"])
              local rank = _G["TWTalentFrameTalent"..i.."Rank"]
              if rank then
                rank:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
              end
            end
          end

          -- only run once the talent frame has actually been skinned
          initialized = true
        end
      end)
    end)
  end

  -- rearrange twow's profession window additions
  HookAddonOrVariable("Blizzard_TradeSkillUI", function()
    if TradeSkillSkillCheckButton and pfUI.skin["Profession"] and pfUI_config["disabled"]["skin_Profession"] ~= "1" then
      SkinCheckbox(TradeSkillSkillCheckButton)
      TradeSkillSkillCheckButton:SetWidth(24)
      TradeSkillSkillCheckButton:SetHeight(24)

      SkinCheckbox(TradeSkillMatsCheckButton)
      TradeSkillMatsCheckButton:SetWidth(24)
      TradeSkillMatsCheckButton:SetHeight(24)

      TradeSkillSearchBox:DisableDrawLayer("BACKGROUND")
      CreateBackdrop(TradeSkillSearchBox, nil, nil, 1)

      TradeSkillSkillCheckButton:SetPoint("TOPLEFT", 500, -2)
      TradeSkillMatsCheckButton:SetPoint("TOPLEFT", 400, -2)

      TradeSkillSearchBox:ClearAllPoints()
      TradeSkillSearchBox:SetPoint("TOP", TradeSkillFrame, "BOTTOM", 0, -8)
    end
  end)

  if C.disabled["macroicons"] == "1" then
    HookAddonOrVariable("Blizzard_MacroUI", function()
      if type(UpdateMacroIconFilenames) ~= "function" then return end
      function _G.UpdateMacroIconFilenames()
        wipe(MACRO_ICON_FILENAMES)
        local provider = CreateAndInitFromMixin(IconDataProviderMixin, IconDataProviderExtraType.Spellbook)
        local seen = {}
        for i = 1, provider:GetNumIcons() do
          -- uppercase, prefix-stripped basename, matching Blizzard's original
          local icon = string.gsub(string.upper(provider:GetIconByIndex(i)), "INTERFACE\\ICONS\\", "")
          if not seen[icon] then
            seen[icon] = true
            table.insert(MACRO_ICON_FILENAMES, icon)
          end
        end
        provider:Release()
      end
    end)
  end
end)