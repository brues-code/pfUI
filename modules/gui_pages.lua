-- The built-in pages of the config GUI, and the entries of their dropdowns.
setfenv(1, pfUI:GetEnvironment())

-- Puts the dropdown entries in gui.dropdowns and adds the built-in pages.
-- The gui module calls this once from its body, so the dropdowns are there
-- before thirdparty modules load. A page builds its settings the first time
-- it is needed.
--   gui    pfUI.gui, the config window
--   U      the updaters of the modules and unit frames, by name
--   CVars  reads and writes cvars the way a config table holds values
--   UVars  the same for globals that hold "1" or "0"
function pfUI.AddConfigPages(gui, U, CVars, UVars)
  -- [[ Static Dropdowns ]] --
  local D = {
    ["languages"] = {
      -- "deDE:German",
      -- "enGB:British English",
      "enUS:English",
      "esES:Spanish",
      --"esMX:Spanish (Latin American)",
      "frFR:French",
      "koKR:Korean",
      "ruRU:Russian",
      "zhCN:Chinese (Simplified)",
      "zhTW:Chinese (Traditional)",
      -- http://wowprogramming.com/docs/api/GetLocale
    },
    ["fonts"] = {
      "Interface\\AddOns\\pfUI\\fonts\\BigNoodleTitling.ttf:BigNoodleTitling",
      "Interface\\AddOns\\pfUI\\fonts\\Continuum.ttf:Continuum",
      "Interface\\AddOns\\pfUI\\fonts\\DieDieDie.ttf:DieDieDie",
      "Interface\\AddOns\\pfUI\\fonts\\Expressway.ttf:Expressway",
      "Interface\\AddOns\\pfUI\\fonts\\Homespun.ttf:Homespun",
      "Interface\\AddOns\\pfUI\\fonts\\Hooge.ttf:Hooge",
      "Interface\\AddOns\\pfUI\\fonts\\Myriad-Pro.ttf:Myriad-Pro",
      "Interface\\AddOns\\pfUI\\fonts\\PT-Sans-Narrow-Bold.ttf:PT-Sans-Narrow-Bold",
      "Interface\\AddOns\\pfUI\\fonts\\PT-Sans-Narrow-Regular.ttf:PT-Sans-Narrow-Regular"
    },
    ["border"] = {
      "-1:" .. T["Default"],
      "0:" .. NONE,
      "1:1 " .. T["Pixel"],
      "2:2 " .. T["Pixel"],
      "3:3 " .. T["Pixel"],
      "4:4 " .. T["Pixel"],
      "5:5 " .. T["Pixel"],
    },
    ["fontstyle"] = {
      "NONE:" .. NONE,
      "OUTLINE:" .. T["Outline"],
      "THICKOUTLINE:" .. T["Thick Outline"],
      "MONOCHROME:" .. T["Monochrome"],
    },
    ["spacing"] = {
      "0:0" .. NONE,
      "1:1 " .. T["Pixel"],
      "2:2 " .. T["Pixel"],
      "3:3 " .. T["Pixel"],
      "4:4 " .. T["Pixel"],
      "5:5 " .. T["Pixel"],
      "6:6 " .. T["Pixel"],
      "7:7 " .. T["Pixel"],
      "8:8 " .. T["Pixel"],
      "9:9 " .. T["Pixel"],
    },
    ["maxraid"] = {
      "5:5",
      "10:10",
      "15:15",
      "20:20",
      "25:25",
      "30:30",
      "35:35",
      "40:40",
    },
    ["abbrevnum"] = {
      "0:" .. T["Full Numbers (4250)"],
      "1:" .. T["Abbreviate 2 Decimals (4.25k)"],
      "2:" .. T["Abbreviate 1 Decimal (4.2k)"],
    },
    ["castbardecimals"] = {
      "1:" .. T["1 Decimal (2.1)"],
      "2:" .. T["2 Decimals (2.14)"],
    },
    ["castbaralign"] = {
      "LEFT:" .. T["Left"],
      "CENTER:" .. T["Center"],
      "RIGHT:" .. T["Right"],
    },
    ["orientation"] = {
      "HORIZONTAL:" .. T["Horizontal"],
      "VERTICAL:" .. T["Vertical"],
    },
    ["xpanchors"] = {
      "__NONONIL__:" .. T["No Anchor"],
      "pfChatLeft:" .. T["Left Chat Frame"],
      "pfChatRight:" .. T["Right Chat Frame"],
      "pfActionBarMain:" .. T["Main Actionbar"],
      "pfActionBarTop:" .. T["Top Actionbar"],
      "pfActionBarLeft:" .. T["Left Actionbar"],
      "pfActionBarRight:" .. T["Right Actionbar"],
      "pfActionBarVertical:" .. T["Vertical Actionbar"],
      "pfExperienceBar:" .. T["Experience Bar"],
      "pfReputationBar:" .. T["Reputation Bar"],
      "pfPlayer:" .. T["Player Unitframe"],
      "pfMinimap:" .. MINIMAP_LABEL,
      "pfPanelMinimap:" .. T["Minimap Panel"],
    },
    ["uf_bartexture"] = {
      "Interface\\AddOns\\pfUI\\img\\bar:pfUI",
      "Interface\\AddOns\\pfUI\\img\\bar_tukui:TukUI",
      "Interface\\AddOns\\pfUI\\img\\bar_elvui:ElvUI",
      "Interface\\AddOns\\pfUI\\img\\bar_gradient:Gradient",
      "Interface\\AddOns\\pfUI\\img\\bar_striped:Striped",
      "Interface\\TargetingFrame\\UI-StatusBar:Wow Status",
      "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar:Wow Skill"
    },
    ["uf_rangecheckinterval"] = {
      "1:" .. T["Very Fast"],
      "2:" .. T["Fast"],
      "4:" .. T["Medium"],
      "8:" .. T["Slow"],
      "16:" .. T["Very Slow"],
    },
    ["uf_rangecheck_mode"] = {
      "vanilla:ClassicAPI (UnitInRange)",
      "unitxp:" .. T["UnitXP (Precise)"],
    },
    ["uf_raidlayout"] = {
      "1x40:" .. "1x40",
      "2x20:" .. "2x20",
      "4x10:" .. "4x10",
      "5x8:" ..  "5x8",
      "8x5:" ..  "8x5",
      "10x4:" .. "10x4",
      "20x2:" .. "20x2",
      "40x1:" .. "40x1",
    },
    ["uf_powerbar_position"] = {
      "TOPLEFT:" .. T["Left"],
      "TOP:" .. T["Center"],
      "TOPRIGHT:" .. T["Right"]
    },
    ["uf_portrait_style"] = {
      "3d:" .. T["3D"],
      "2d:" .. T["2D"],
      "classround:" .. T["Class Icon (Round)"],
      "classsquare:" .. T["Class Icon (Square)"]
    },
    ["uf_portrait_position"] = {
      "bar:" .. T["Healthbar Embedded"],
      "left:" .. T["Left"],
      "right:" .. T["Right"],
      "off:" .. T["Disabled"]
    },
    ["uf_happiness"] = {
      "0:" .. T["Disabled"],
      "1:" .. T["Face"],
      "2:" .. T["Rank"]
    },
    ["uf_buff_position"] = {
      "TOPLEFT:" .. T["Top Left"],
      "TOPRIGHT:" .. T["Top Right"],
      "BOTTOMLEFT:" .. T["Bottom Left"],
      "BOTTOMRIGHT:" .. T["Bottom Right"],
      "off:" .. T["Disabled"]
    },
    ["cooldown_timers"] = {
      "off:" .. NONE,
      "text:" .. T["Numbers"],
      "sweep:" .. T["Sweep"],
      "both:" .. T["Numbers And Sweep"]
    },
    ["uf_debuff_indicator"] = {
      "0:" .. T["Disabled"],
      "1:" .. T["Legacy"],
      "2:" .. T["Glow"],
      "3:" .. T["Square"],
      "4:" .. T["Icon"]
    },
    ["uf_debuff_indicator_size"] = {
      ".10:10%",
      ".25:25%",
      ".35:35%",
      ".50:50%",
      ".65:65%",
      ".75:75%",
      ".90:90%",
    },
    ["percent_small"] = {
      "0:0%",
      ".05:5%",
      ".10:10%",
      ".15:15%",
      ".20:20%",
      ".25:25%",
      ".30:30%",
      ".35:35%",
      ".40:40%",
      ".45:45%",
      ".50:50%",
      ".55:55%",
      ".60:60%",
      ".65:65%",
      ".70:70%",
      ".75:75%",
      ".80:80%",
      ".85:85%",
      ".90:90%",
      ".95:95%",
      "1:100%",
    },
    ["uf_overheal"] = {
      "0:0%",
      "10:10%",
      "20:20%",
      "30:30%",
      "40:40%",
      "50:50%",
      "60:60%",
      "70:70%",
      "80:80%",
      "90:90%",
      "100:100%",
    },
    ["uf_layout"] = {
      "default:" .. T["Default"],
      "tukui:TukUI"
    },
    ["raidmarker_grow"] = {
      "down:" .. T["Down"],
      "up:" .. T["Up"],
    },
    ["uf_color"] = {
      "0:" .. CLASS,
      "1:" .. T["Custom"],
      "2:" .. HEALTH,
    },
    ["uf_texts"] = {
      "none:" .. DISABLE,
      "unit:" .. T["Unit String"],
      "unitrev:" .. T["Unit String (Reverse)"],
      "name:" .. NAME,
      "nameshort:" .. T["Name (Short)"],
      "ownername:" .. T["Owner Name"],
      "level:" .. LEVEL,
      "class:" .. CLASS,
      "namehealth:" .. T["Name | Health Missing"],
      "namehealthbreak:" .. T["Name (Linebreak) -Health Missing"],
      "shortnamehealth:" .. T["Name (Short) | Health Missing"],
      "healthdyn:" .. T["Health - Auto"],
      "health:" .. T["Health - Current"],
      "healthmax:" .. T["Health - Max"],
      "healthperc:" .. T["Health - Percentage"],
      "healthmiss:" .. T["Health - Missing"],
      "healthminmax:" .. T["Health - Min/Max"],
      "powerdyn:" .. T["Mana - Auto"],
      "power:" .. T["Mana - Current"],
      "powermax:" .. T["Mana - Max"],
      "powerperc:" .. T["Mana - Percentage"],
      "powermiss:" .. T["Mana - Missing"],
      "powerminmax:" .. T["Mana - Min/Max"],
    },
    ["hpformat"] = {
      "percent:" .. T["Percent"],
      "cur:" .. T["Current HP"],
      "curperc:" .. T["Current HP | Percent"],
      "curmax:" .. T["Current HP - Max HP"],
      "curmaxs:" .. T["Current HP / Max HP"],
      "curmaxperc:" .. T["Current HP - Max HP | Percent"],
      "curmaxpercs:" .. T["Current HP / Max HP | Percent"],
      "deficit:" .. T["Deficit"],
    },
    ["panel_values"] = {
      "none:" .. DISABLE,
      "time:" .. T["Clock"],
      "fps:" .. T["FPS & Ping"],
      "exp:" .. T["XP Percentage"],
      "gold:" .. GOLD,
      "friends:" .. T["Friends Online"],
      "guild:" .. T["Guild Online"],
      "durability:" .. T["Item Durability"],
      "zone:" .. T["Zone Name"],
      "combat:" .. T["Combat Timer"],
      "ammo:" .. T["Ammo Counter"],
      "soulshard:" .. T["Soulshard Counter"],
      "bindlocation:" .. T["Hearth"],
      "thistletea:" .. T["Thistle Tea"],
      "flashpowder:" .. T["Flash Powder"],
      "blindpowder:" .. T["Blinding Powder"],
      "bagspace:" .. T["Bagspace"]
    },
    ["tooltip_position"] = {
      "bottom:" .. T["Bottom"],
      "chat:" .. T["Above Right Chat"],
      "cursor:" .. T["Cursor"],
      "free:" .. T["Custom"]
    },
    ["tooltip_align"] = {
      "native:" .. T["Native"],
      "top:" .. T["Top"],
      "left:" .. T["Left"],
      "right:" .. T["Right"]
    },
    ["debuffposition"] = {
      "TOP:" .. T["Top"],
      "BOTTOM:" .. T["Bottom"],
    },
    ["gmserver_text"] = {
      "elysium:" .. T["Elysium Based Core"],
    },
    ["buffbarfilter"] = {
      "none:"      .. NONE,
      "whitelist:" .. T["Whitelist"],
      "blacklist:" .. T["Blacklist"],
    },
    ["buffbarsort"] = {
      "asc:" .. T["Ascending"],
      "desc:" .. T["Descending"],
    },
    ["minimap_cords_position"] = {
      "topleft:" .. T["Top Left"],
      "topright:" .. T["Top Right"],
      "bottomleft:" .. T["Bottom Left"],
      "bottomright:" .. T["Bottom Right"],
    },
    ["minimap_cords_visibility"] = {
      "mouseover:" .. T["Mouseover"],
      "on:" .. T["Enable"],
      "off:" .. DISABLE
    },
    ["minimap_zone_visibility"] = {
      "mouseover:" .. T["Mouseover"],
      "on:" .. T["Enable"],
      "off:" .. DISABLE
    },
    ["positions"] = {
      "TOPLEFT:" .. T["Top Left"],
      "TOP:" .. T["Top"],
      "TOPRIGHT:" .. T["Top Right"],
      "LEFT:" .. T["Left"],
      "CENTER:" .. T["Center"],
      "RIGHT:" .. T["Right"],
      "BOTTOMLEFT:" .. T["Bottom Left"],
      "BOTTOM:" .. T["Bottom"],
      "BOTTOMRIGHT:" .. T["Bottom Right"],
    },
    ["actionbuttonanimations"] = {
      "none:" .. NONE,
      "zoomfade:" .. T["Zoom & Fade"],
      "shrinkreturn:" .. T["Shrink & Return"],
      "elasticzoom:" .. T["Elastic Zoom"],
      "wobblezoom:" .. T["Wobble Zoom"],
    },
    ["animationmode"] = {
      "keypress:" .. T["On Key Press"],
      "statechange:" .. T["On State Change"]
    },
    ["actionbarbuttons"] = {
      "1","2","3","4","5","6","7","8","9","10","11","12"
    },
    ["addonbuttons_position"] = {
      "bottom:" .. T["Bottom"],
      "left:" .. T["Left"],
      "top:" .. T["Top"],
      "right:" .. T["Right"]
    },
    ["xp_display"] = {
      "XPFLEX:" .. T["Automatic"],
      "XP:" .. T["Experience"],
      "REP:" .. T["Tracked Reputation"],
      "FLEX:" .. T["Last Reputation"],
      "PETXP:" .. T["Pet Experience"],
      "DISABLED:" .. T["Disabled"],
    },
    ["xp_position"] = {
      "BOTTOM:" .. T["Bottom"],
      "LEFT:" .. T["Left"],
      "TOP:" .. T["Top"],
      "RIGHT:" .. T["Right"]
    },
    ["glowintensity"] = {
      "8:" .. T["Tiny"],
      "16:" .. T["Small"],
      "32:" .. T["Medium"],
      "64:" .. T["Large"],
      "128:" .. T["Huge"],
    },
    ["mapcircle"] = {
      "5:" .. T["Tiny"],
      "3:" .. T["Small"],
      "1:" .. T["Medium"],
      "-1:" .. T["Large"],
      "-3:" .. T["Huge"],
    },
    ["maptooltip"] = {
      ".10:10%",
      ".20:20%",
      ".30:30%",
      ".40:40%",
      ".50:50%",
      ".60:60%",
      ".70:70%",
      ".80:80%",
      ".90:90%",
      "1:100%",
      "0:" .. T["World Map Scale"],
    },
    ["textalign"] = {
      "LEFT:" .. T["Left"],
      "CENTER:" .. T["Center"],
      "RIGHT:" .. T["Right"],
    },
    ["gryphons"] = {
      "None:"..NONE,
      "Gryphon:"..T["Gryphon"],
      "Lion:"..T["Lion"],
    }
  }

  -- add locale dependent client fonts to the list
  if GetLocale() == "enUS" or GetLocale() == "frFR" or GetLocale() == "deDE" or GetLocale() == "ruRU" then
    table.insert(D.fonts, "Fonts\\ARIALN.TTF:ARIALN")
    table.insert(D.fonts, "Fonts\\FRIZQT__.TTF:FRIZQT")
    table.insert(D.fonts, "Fonts\\MORPHEUS.TTF:MORPHEUS")
    table.insert(D.fonts, "Fonts\\SKURRI.TTF:SKURRI")
  elseif GetLocale() == "koKR" then
    table.insert(D.fonts, "Fonts\\2002.TTF:2002")
    table.insert(D.fonts, "Fonts\\2002B.TTF:2002B")
    table.insert(D.fonts, "Fonts\\ARIALN.TTF:ARIALN")
    table.insert(D.fonts, "Fonts\\FRIZQT__.TTF:FRIZQT")
    table.insert(D.fonts, "Fonts\\K_Damage.TTF:K_Damage")
    table.insert(D.fonts, "Fonts\\K_Pagetext.TTF:K_Pagetext")
  elseif GetLocale() == "zhCN" then
    table.insert(D.fonts, "Fonts\\ARIALN.TTF:ARIALN")
    table.insert(D.fonts, "Fonts\\FRIZQT__.TTF:FRIZQT")
    table.insert(D.fonts, "Fonts\\FZBWJW.TTF:FZBWJW")
    table.insert(D.fonts, "Fonts\\FZJZJW.TTF:FZJZJW")
    table.insert(D.fonts, "Fonts\\FZXHJW.TTF:FZXHJW")
    table.insert(D.fonts, "Fonts\\FZXHLJW.TTF:FZXHLJW")
  end

  -- Turtle WoW's patch-5.mpq ships Noto Sans SC as FZLBJW.TTF, but some
  -- installs replace FRIZQT__.TTF with it instead. SetFont returns nil for a
  -- file the client can't load, so only offer it where it exists.
  if gui:CreateFontString():SetFont("Fonts\\FZLBJW.TTF", 12) then
    table.insert(D.fonts, "Fonts\\FZLBJW.TTF:Noto Sans SC")
  end

  D.loot_rarity = {}
  for i=0, getn(_G.ITEM_QUALITY_COLORS)-2  do
    local entry = string.format("%d:%s", i, string.format("%s%s%s", _G.ITEM_QUALITY_COLORS[i].hex, _G[string.format("ITEM_QUALITY%d_DESC",i)], FONT_COLOR_CODE_CLOSE))
    table.insert(D.loot_rarity, entry)
  end

  D.screenshot_battle = {
    "0:".._G.NONE,
    "1:"..T["Won"],
    "2:"..T["Ended"],
  }
  D.screenshot_loot = {"0:".._G.NONE}
  for i=3, 5 do
    local entry = string.format("%d:%s", i, string.format("%s%s%s", _G.ITEM_QUALITY_COLORS[i].hex, _G[string.format("ITEM_QUALITY%d_DESC",i)], FONT_COLOR_CODE_CLOSE))
      table.insert(D.screenshot_loot, entry)
  end

  gui.dropdowns = D

  gui:AddFramePage("about", T["About"], nil, function()
    -- read data
    local lang = UNKNOWN
    for _, entry in pairs(D.languages) do
      local short, full = strsplit(":", entry)
      if short == C.global.language then
        lang = full
      end
    end

    -- draw pfUI logo
    local function draw(p, fx, fy, tx, ty, r, g, b, a)
      local t = p:CreateTexture(nil, "OVERLAY")
      t:SetColorTexture(r,g,b,a)
      t:SetPoint("TOPLEFT", fx, fy)
      t:SetPoint("BOTTOMRIGHT", p, "TOPLEFT", tx, ty)
    end

    local x, y, p = 235, 55, 10  -- startx, starty, pencilsize
    draw(this, x,     -y-2*p, x+p,      -y-7*p, .2, 1, .8, 1)
    draw(this, x+p,   -y-2*p, x+2*p,    -y-3*p, .2, 1, .8, 1)
    draw(this, x+p,   -y-4*p, x+2*p,    -y-5*p, .2, 1, .8, 1)
    draw(this, x+2*p, -y,     x+3*p,    -y-5*p, .2, 1, .8, 1)
    draw(this, x+3*p, -y,     x+4*p,    -y-1*p, .2, 1, .8, 1)
    draw(this, x+p,   -y-2*p, x+4*p,    -y-3*p, .2, 1, .8, 1)
    draw(this, x+4*p, -y,     x+5*p,    -y-5*p, 1,  1, 1,  1)
    draw(this, x+5*p, -y-4*p, x+5*p+p,  -y-5*p, 1,  1, 1,  1)
    draw(this, x+6*p, -y,     x+7*p,    -y-p,   1,  1, 1,  1)
    draw(this, x+6*p, -y-2*p, x+7*p,    -y-5*p, 1,  1, 1,  1)

    -- version
    this.versionc = this:CreateFontString("Status", "LOW", "GameFontWhite")
    this.versionc:SetFont(pfUI.font_default, C.global.font_size)
    this.versionc:SetPoint("TOPLEFT", 185, -170)
    this.versionc:SetWidth(200)
    this.versionc:SetJustifyH("LEFT")
    this.versionc:SetText(GAME_VERSION_LABEL .. ":")

    this.version = this:CreateFontString("Status", "LOW", "GameFontWhite")
    this.version:SetFont(pfUI.font_default, C.global.font_size)
    this.version:SetPoint("TOPRIGHT", this, "TOPLEFT", 360, -170)
    this.version:SetWidth(200)
    this.version:SetJustifyH("RIGHT")

    this.update = this:CreateFontString("Status", "LOW", "GameFontWhite")
    this.update:SetFont(pfUI.font_default, C.global.font_size)
    this.update:SetPoint("TOPLEFT", 185, -140)
    this.update:SetPoint("TOPRIGHT", this, "TOPLEFT", 360, -140)
    this.update:SetJustifyH("CENTER")
    this.update:SetTextColor(.2,1,.8)

    this.screenc = this:CreateFontString("Status", "LOW", "GameFontWhite")
    this.screenc:SetFont(pfUI.font_default, C.global.font_size)
    this.screenc:SetPoint("TOPLEFT", 185, -200)
    this.screenc:SetWidth(200)
    this.screenc:SetJustifyH("LEFT")
    this.screenc:SetText(RESOLUTION .. ":")

    this.screen = this:CreateFontString("Status", "LOW", "GameFontWhite")
    this.screen:SetFont(pfUI.font_default, C.global.font_size)
    this.screen:SetPoint("TOPRIGHT", this, "TOPLEFT", 360, -200)
    this.screen:SetWidth(200)
    this.screen:SetJustifyH("RIGHT")

    this.scalec = this:CreateFontString("Status", "LOW", "GameFontWhite")
    this.scalec:SetFont(pfUI.font_default, C.global.font_size)
    this.scalec:SetPoint("TOPLEFT", 185, -220)
    this.scalec:SetWidth(200)
    this.scalec:SetJustifyH("LEFT")
    this.scalec:SetText(T["Scaling"] .. ":")

    this.scale = this:CreateFontString("Status", "LOW", "GameFontWhite")
    this.scale:SetFont(pfUI.font_default, C.global.font_size)
    this.scale:SetPoint("TOPRIGHT", this, "TOPLEFT", 360, -220)
    this.scale:SetWidth(200)
    this.scale:SetJustifyH("RIGHT")

    this.clientc = this:CreateFontString("Status", "LOW", "GameFontWhite")
    this.clientc:SetFont(pfUI.font_default, C.global.font_size)
    this.clientc:SetPoint("TOPLEFT", 185, -250)
    this.clientc:SetWidth(200)
    this.clientc:SetJustifyH("LEFT")
    this.clientc:SetText(T["Gameclient"] .. ":")

    this.client = this:CreateFontString("Status", "LOW", "GameFontWhite")
    this.client:SetFont(pfUI.font_default, C.global.font_size)
    this.client:SetPoint("TOPRIGHT", this, "TOPLEFT", 360, -250)
    this.client:SetWidth(200)
    this.client:SetJustifyH("RIGHT")

    this.langc = this:CreateFontString("Status", "LOW", "GameFontWhite")
    this.langc:SetFont(pfUI.font_default, C.global.font_size)
    this.langc:SetPoint("TOPLEFT", 185, -270)
    this.langc:SetWidth(200)
    this.langc:SetJustifyH("LEFT")
    this.langc:SetText(LANGUAGE .. ":")
    this.lang = this:CreateFontString("Status", "LOW", "GameFontWhite")
    this.lang:SetFont(pfUI.font_default, C.global.font_size)
    this.lang:SetPoint("TOPRIGHT", this, "TOPLEFT", 360, -270)
    this.lang:SetWidth(200)
    this.lang:SetJustifyH("RIGHT")

    -- the values, read again each time the page shows
    local about = this
    local function Refresh()
      local localversion  = tonumber(pfUI.version.major*10000 + pfUI.version.minor*100 + pfUI.version.fix)
      local remoteversion = tonumber(pfUI_init.updateavailable) or 0
      if localversion < remoteversion then
        about.update:SetText("|cffffffff[|r!|cffffffff] " .. T["A new version is available"])
      end

      about.version:SetText(pfUI.version.string)
      about.screen:SetText(GetCVar("gxResolution"))
      about.scale:SetText(round(UIParent:GetEffectiveScale(),2))
      about.client:SetText(GetBuildInfo() .. " (" .. GetLocale() .. ")")
      about.lang:SetText(lang)
    end

    local f = CreateFrame("Frame", nil, this)
    f:SetScript("OnShow", Refresh)
    Refresh()

    local donate = CreateFrame("Button", nil, this)
    donate:SetPoint("TOPLEFT", 115, -335)
    donate:SetWidth(100)
    donate:SetHeight(20)
    donate:SetText(T["Donate"])
    donate:SetScript("OnClick", function()
      CopyText("https://buymeacoffee.com/brues")
    end)
    SkinButton(donate)

    local github = CreateFrame("Button", nil, this)
    github:SetPoint("TOPLEFT", 225, -335)
    github:SetWidth(100)
    github:SetHeight(20)
    github:SetText(T["GitHub"])
    github:SetScript("OnClick", function()
      CopyText(GetAddOnMetadata(pfUI.name, "X-Website"))
    end)
    SkinButton(github)

    local website = CreateFrame("Button", nil, this)
    website:SetPoint("TOPLEFT", 335, -335)
    website:SetWidth(100)
    website:SetHeight(20)
    website:SetText(T["Website"])
    website:SetScript("OnClick", function()
      CopyText(GetAddOnMetadata(pfUI.name, "X-Website"))
    end)
    SkinButton(website)
  end)

  gui:AddPage("settings.general", T["Settings"], T["General"], function(p)
    p:Header(T["Profile"])
    p:Dropdown(T["Select profile"], C.global, "profile", function()
      local values = {}
      for name, config in pairs(pfUI_profiles) do table.insert(values, name) end
      table.sort(values)
      return values
    end, nop)

    p:Buttons(
      { T["Load profile"], function()
        if C.global.profile and pfUI_profiles[C.global.profile] then
          CreateQuestionDialog(T["Load profile"] .. " '|cff33ffcc" .. C.global.profile .. "|r'?", function()
            local selp = C.global.profile
            local rchat = C.chat.right.enable

            -- load profile
            _G["pfUI_config"] = CopyTable(pfUI_profiles[C.global.profile])

            -- restore values
            pfUI:UpdateConfig("global", nil, "profile", selp)
            pfUI:UpdateConfig("chat", "right", "enable", rchat)

            -- add default values
            pfUI:LoadConfig()

            ReloadUI()
          end)
        end
      end },

      { T["Delete profile"], function()
        if C.global.profile and pfUI_profiles[C.global.profile] then
          CreateQuestionDialog(T["Delete profile"] .. " '|cff33ffcc" .. C.global.profile .. "|r'?", function()
            pfUI_profiles[C.global.profile] = nil
            this:GetParent():Hide()
          end)
        end
      end },

      { T["Save profile"], function()
        if C.global.profile and pfUI_profiles[C.global.profile] then
          CreateQuestionDialog(T["Save current settings to profile"] .. " '|cff33ffcc" .. C.global.profile .. "|r'?", function()
            if pfUI_profiles[C.global.profile] then
              pfUI_profiles[C.global.profile] = CopyTable(C)
            end
            this:GetParent():Hide()
          end)
        end
      end },

      { T["Create Profile"], function()
        CreateQuestionDialog(T["Please enter a name for the new profile.\nExisting profiles sharing the same name will be overwritten."],
        function()
          local profile = this:GetParent().input:GetText()
          local bad = string.gsub(profile,"([%w%s]+)","")
          if bad~="" then
            message("\"" .. bad .. "\" " .. T["is not allowed in profile name"])
          else
            profile = (string.gsub(profile,"^%s*(.-)%s*$", "%1"))
            if profile and profile ~= "" then
              pfUI_profiles[profile] = CopyTable(C)
              this:GetParent():Hide()
            end
          end
        end, false, true)
      end }
    )

    -- add invisible font to disable combat messages
    local combatfonts = CopyTable(D.fonts)
    table.insert(combatfonts, "Interface\\AddOns\\pfUI\\fonts\\AdobeBlank.ttf:Invisible")

    p:Header(T["Settings"])
    p:Dropdown(LANGUAGE, C.global, "language", D.languages)
    -- the game's own scale options, as in its Video Options; the list keeps
    -- a value set there that is none of these steps
    p:Checkbox(T["Use UI-Scale"], CVars, "useUiScale", nop)
    p:Dropdown(T["UI-Scale"], CVars, "uiScale", function()
      local current = GetCVar("uiScale")
      local values, found = {}, nil
      for _, scale in ipairs({ .64, .65, .7, .75, .8, .85, .9, .95, 1, 1.1, 1.2, 1.3, 1.4, 1.5 }) do
        if math.abs(scale - tonumber(current)) < .001 then
          found = true
          table.insert(values, current .. ":" .. scale)
        else
          table.insert(values, tostring(scale))
        end
      end
      if not found then table.insert(values, 1, current .. ":" .. round(tonumber(current), 2)) end
      return values
    end, nop)
    p:Checkbox(string.format(T["Pixel Perfect UI-Scale: %s (Overrides UI-Scale)"], round(PixelUtil.GetPixelToUIUnitFactor(), 2)), C.global, "pixelperfect")
    p:Checkbox(T["Use Original Game Fonts"], C.global, "font_blizzard")
    p:Checkbox(T["Enable Region Compatible Font"], C.global, "force_region")
    p:Dropdown(T["Standard Text Font"], C.global, "font_default", D.fonts)
    p:Number(T["Standard Text Font Size"], C.global, "font_size")
    p:Dropdown(T["3D World Unit Font"], C.global, "font_unit_name", D.fonts)
    p:Dropdown(T["Scrolling Combat Text Font"], C.global, "font_combat", combatfonts)
    p:Checkbox(T["Enable Offscreen Frame Positions"], C.global, "offscreen")
    p:Checkbox(T["Display Addon Errors In Chat"], C.global, "errors")
    p:Checkbox(T["Use Single Line UIErrors Frame"], C.global, "errors_limit")
    p:Checkbox(T["Disable Errors in UIErrors Frame"], C.global, "errors_hide")
    p:Checkbox(T["Highlight Settings That Require Reload"], C.gui, "reloadmarker")
    p:Dropdown(T["Abbreviate Numbers"], C.unitframes, "abbrevnum", D.abbrevnum)
    p:Dropdown(T["Castbar Timer Decimals"], C.unitframes, "castbardecimals", D.castbardecimals)
    p:Checkbox(T["Abbreviate Unit Names"], C.unitframes, "abbrevname")
    p:Header(T["Health Point Estimation"])
    p:Checkbox(T["Estimate Enemy Health Points"], C.global, "libhealth")
    p:Dropdown(T["Threshold To Trust Health Estimation"], C.global, "libhealth_hit", D.uf_rangecheckinterval)
    p:Dropdown(T["Required Damage In Percent"], C.global, "libhealth_dmg", D.percent_small)

    -- Delete / Reset
    p:Header(T["Delete / Reset"])
    p:Buttons(
      { T["|cffff5555EVERYTHING"], function()
        CreateQuestionDialog(T["Do you really want to reset |cffffaaaaEVERYTHING|r?\n\nThis will reset:\n - Current Configuration\n - Current Frame Positions\n - Firstrun Wizard\n - Addon Cache\n - Saved Profiles"],
          function()
            _G["pfUI_init"] = {}
            _G["pfUI_config"] = pfUI.api.CopyTable(pfUI_profiles["Modern"])
            _G["pfUI_playerDB"] = {}
            _G["pfUI_profiles"] = {}
            _G["pfUI_cache"] = {}
            pfUI:LoadConfig()
            this:GetParent():Hide()
            pfUI.gui:Reload()
          end)
      end },

      { T["Configuration"], function()
        CreateQuestionDialog(T["Do you really want to reset your configuration?\nThis also includes frame positions"],
          function()
            _G["pfUI_config"] = pfUI.api.CopyTable(pfUI_profiles["Modern"])
            _G["pfUI_init"] = {}
            pfUI:LoadConfig()
            this:GetParent():Hide()
            pfUI.gui:Reload()
          end)
      end },

      { T["Cache"], function()
        CreateQuestionDialog(T["Do you really want to reset the Cache?"],
          function()
            _G["pfUI_playerDB"] = {}
            _G["pfUI_cache"] = {}
            this:GetParent():Hide()
            pfUI.gui:Reload()
          end)
      end },

      { T["Firstrun"], function()
        _G["pfUI_init"] = {}
        pfUI.gui:Hide()
        pfUI.firstrun:NextStep()
      end }
    )
  end)

  gui:AddPage("settings.appearance", T["Settings"], T["Appearance"], function(p)
    p:Color(T["Background Color"], C.appearance.border, "background")
    p:Color(T["Border Color"], C.appearance.border, "color")
    p:Color(T["Map Reveal Color"], C.appearance.worldmap, "mapreveal_color", U["mapreveal"])
    p:Checkbox(T["Map Exploration Points"], C.appearance.worldmap, "mapexploration", U["mapreveal"])
    p:Dropdown(T["Map Group/Raid Circle Size"], C.appearance.worldmap, "groupcircles", D.mapcircle, U["mapcolors"])
    p:Checkbox(T["Colorize player name on WorldMap and BattlefieldMinimap"], C.appearance.worldmap, "colornames", U["mapcolors"])
    p:Dropdown(T["Map Tooltip Scale"], C.appearance.worldmap, "tooltipsize", D.maptooltip, U["map"])
    p:Spacer()
    p:Checkbox(T["Enable Frame Shadow"], C.appearance.border, "shadow")
    p:Dropdown(T["Frame Shadow Intensity"], C.appearance.border, "shadow_intensity", D.uf_debuff_indicator_size)
    p:Spacer()
    p:Checkbox(T["Force Blizzard Borders (|cffffaaaaExperimental|r)"], C.appearance.border, "force_blizz")
    p:Spacer()
    p:Dropdown(T["Global Border Size"], C.appearance.border, "default", D.border)
    p:Dropdown(T["Action Bar Border Size"], C.appearance.border, "actionbars", D.border)
    p:Dropdown(T["Unit Frame Border Size"], C.appearance.border, "unitframes", D.border)
    p:Dropdown(T["Panel Border Size"], C.appearance.border, "panels", D.border)
    p:Dropdown(T["Chat Border Size"], C.appearance.border, "chat", D.border)
    p:Dropdown(T["Bags Border Size"], C.appearance.border, "bags", D.border)
    p:Dropdown(T["Nameplate Border Size"], C.appearance.border, "nameplates", D.border, U["nameplates"])
    p:Spacer()
    p:Checkbox(T["Enable Combat Glow Effects On Screen Edges"], C.appearance.infight, "screen", U["infight"])
    p:Checkbox(T["Enable Aggro Glow Effects On Screen Edges"], C.appearance.infight, "aggro", U["infight"])
    p:Checkbox(T["Enable Low Health Glow Effects On Screen Edges"], C.appearance.infight, "health", U["infight"])
    p:Dropdown(T["Screen Edge Glow Intensity"], C.appearance.infight, "intensity", D.glowintensity, U["infight"])
  end)

  gui:AddPage("settings.cooldown", T["Settings"], T["Cooldown"], function(p)
    p:Checkbox(COUNTDOWN_FOR_COOLDOWNS_TEXT, CVars, "countdownForCooldowns", nop)
    p:Dropdown(T["Font"], C.cooldown, "font", D.fonts, UpdateCooldowns)
    p:Number(FONT_SIZE, C.cooldown, "font_size")
    p:Checkbox(T["Scale Font Size With Icon"], C.cooldown, "dynamicsize")
    p:Number(T["Hide Numbers On Spell Cooldowns Up To (Seconds)"], C.cooldown, "threshold", UpdateCooldowns)
    p:Checkbox(T["Show Tenths Below 5 Seconds"], C.cooldown, "milliseconds", UpdateCooldowns)
    p:Color(T["Cooldown Color (5 Seconds Or Less)"], C.cooldown, "lowcolor", UpdateCooldowns)
    p:Color(T["Cooldown Color (Seconds)"], C.cooldown, "normalcolor", UpdateCooldowns)
    p:Color(T["Cooldown Color (Minutes)"], C.cooldown, "minutecolor", UpdateCooldowns)
    p:Color(T["Cooldown Color (Hours)"], C.cooldown, "hourcolor", UpdateCooldowns)
    p:Color(T["Cooldown Color (Days)"], C.cooldown, "daycolor", UpdateCooldowns)

    -- the timers of cooldowns no other page covers. Other addons' cooldowns
    -- only lose numbers or sweep (see api/cooldown.lua), so giving them
    -- back takes a reload
    local timers = D.cooldown_timers
    p:Header(T["Timers"])
    p:Dropdown(T["Spellbook And Character"], C.cooldown, "blizzard_timers", timers, UpdateCooldowns)
    p:Dropdown(T["Loss Of Control"], C.cooldown, "lossofcontrol_timers", timers, UpdateCooldowns)
    p:Dropdown(T["Other Addons"], C.cooldown, "foreign_timers", timers)
  end)

  gui:AddPage("settings.screenshot", T["Settings"], T["Screenshot"], function(p)
    p:Number(T["Timer In Minutes"], C.screenshot, "interval")
    p:Checkbox(PLAYER_LEVEL_UP, C.screenshot, "levelup")
    p:Checkbox(T["PvP Rank"], C.screenshot, "pvprank")
    p:Checkbox(T["Reputation Level"], C.screenshot, "faction")
    p:Checkbox(T["Honorable Kill"], C.screenshot, "hk")
    p:Dropdown(T["Battleground Statistics"], C.screenshot, "battleground", D.screenshot_battle)
    p:Dropdown(T["Item Looted"], C.screenshot, "loot", D.screenshot_loot)
    p:Header(T["Options"])
    p:Checkbox(T["Show Description"], C.screenshot, "caption")
    p:Dropdown(T["Description Font"], C.screenshot, "caption_font", D.fonts)
    p:Number(T["Description Font Size"], C.screenshot, "caption_size")
    p:Checkbox(T["Hide All UI Elements"], C.screenshot, "hideui")
  end)

  gui:AddPage("settings.gmmode", T["Settings"], T["GM-Mode"], function(p)
    p:Checkbox(T["Disable GM-Mode"], C.gm, "disable")
    p:Dropdown(T["Selected Core"], C.gm, "server", D.gmserver_text)
  end)

  gui:AddPage("unitframes.general", T["Unit Frames"], T["General"], function(p)
    p:Checkbox(T["Disable pfUI Unit Frames"], C.unitframes, "disable")
    p:Checkbox(T["Animate Health And Power Bars"], C.unitframes, "animatebars")
    p:Number(T["Portrait Alpha"], C.unitframes, "portraitalpha")
    p:Dropdown(T["Portrait Style"], C.unitframes, "portraitstyle", D.uf_portrait_style)
    p:Checkbox(T["Enable 2D Portraits As Fallback"], C.unitframes, "portraittexture")
    p:Dropdown(T["Unit Frame Layout"], C.unitframes, "layout", D.uf_layout)
    p:Number(T["Combopoint Width"], C.unitframes, "combowidth")
    p:Number(T["Combopoint Height"], C.unitframes, "comboheight")
    p:Checkbox(T["Show Resting"], C.unitframes.player, "showRest")
    p:Dropdown(T["Raid Mark Icon Style"], C.unitframes, "blizzard_raidicons", function() return {"1:" .. T["Original Blizzard"], "0:" .. T["pfUI Design"]} end)

    p:Header(T["Swing Timer"])
    p:Number(T["Swing Timer Width"], C.unitframes, "swingtimerwidth")
    p:Number(T["Swing Timer Height"], C.unitframes, "swingtimerheight")
    p:Dropdown(T["Swing Timer Texture"], C.unitframes, "swingtimertexture", D.uf_bartexture)
    p:Number(T["Swing Timer Font Size"], C.unitframes, "swingtimerfontsize")
    p:Checkbox(T["Show Timer Text"], C.unitframes, "swingtimertext")
    p:Checkbox(T["Show MH/OH Labels"], C.unitframes, "swingtimerlabel")
    p:Checkbox(T["Show Offhand Bar"], C.unitframes, "swingtimeroffhand")
    p:Checkbox(T["Show Ranged Bar"], C.unitframes, "swingtimerranged")
    p:Color(T["Mainhand Bar Color"], C.unitframes, "swingtimermhcolor")
    p:Color(T["Offhand Bar Color"], C.unitframes, "swingtimerohcolor")
    p:Color(T["Ranged Bar Color"], C.unitframes, "swingtimerrangedcolor")
    p:Color(T["Ranged Warn Color (Hunter)"], C.unitframes, "swingtimerrangedwarncolor")
    p:Color(T["Out Of Range Color"], C.unitframes, "swingtimeroutrangecolor")
    p:Checkbox(T["Show On Next Attack Queue Color"], C.unitframes, "swingtimerhsqueue")
    p:Checkbox(T["Show Attack Speed"], C.unitframes, "swingtimerattackspeed")

    p:Header(T["Mark Tracking"])
    p:Number(T["Raid Marker Width"], C.unitframes, "raidmarkerwidth")
    p:Number(T["Raid Marker Height"], C.unitframes, "raidmarkerheight")
    p:Dropdown(T["Raid Marker Grow"], C.unitframes, "raidmarkergrow", D.raidmarker_grow)
    p:Dropdown(T["Raid Marker Texture"], C.unitframes, "raidmarkertexture", D.uf_bartexture)
    p:Number(T["Raid Marker Font Size"], C.unitframes, "raidmarkerfontsize")
    p:Checkbox(T["Show Name"], C.unitframes, "raidmarkershowname")
    p:Checkbox(T["Show Percent HP"], C.unitframes, "raidmarkershowpct")
    p:Checkbox(T["Show Portrait"], C.unitframes, "raidmarkershowportrait")
    p:Color(T["Star Color"], C.unitframes, "raidmarkercolor_star")
    p:Color(T["Circle Color"], C.unitframes, "raidmarkercolor_circle")
    p:Color(T["Diamond Color"], C.unitframes, "raidmarkercolor_diamond")
    p:Color(T["Triangle Color"], C.unitframes, "raidmarkercolor_triangle")
    p:Color(T["Moon Color"], C.unitframes, "raidmarkercolor_moon")
    p:Color(T["Square Color"], C.unitframes, "raidmarkercolor_square")
    p:Color(T["Cross Color"], C.unitframes, "raidmarkercolor_cross")
    p:Color(T["Skull Color"], C.unitframes, "raidmarkercolor_skull")

    p:Header(T["Font Options"])
    p:Dropdown(T["Unit Frame Text Font"], C.global, "font_unit", D.fonts)
    p:Number(T["Unit Frame Text Size"], C.global, "font_unit_size")
    p:Dropdown(T["Unit Frame Text Style"], C.global, "font_unit_style", D.fontstyle)

    p:Header(T["Group Options"])
    p:Checkbox(T["Enable 40y-Range Check"], C.unitframes, "rangecheck")
    p:Dropdown(T["Range Check Mode"], C.unitframes, "rangecheck_mode", D.uf_rangecheck_mode)
    p:Number(T["UnitXP Range Threshold (yards)"], C.unitframes, "rangecheck_distance")
    p:Checkbox(T["Show Self In Raid Frames When Solo"], C.unitframes, "selfinraid")
    p:Checkbox(T["Show Self In Group Frames"], C.unitframes, "selfingroup")
    p:Checkbox(T["Use Raid Frames To Display Group Members"], C.unitframes, "raidforgroup")
    p:Checkbox(T["Hide Group Frames While In Raid"], C.unitframes.group, "hide_in_raid")
    p:Dropdown(T["Max Amount Of Raid Frames"], C.unitframes, "maxraid", D.maxraid)

    p:Header(T["Colors"])
    p:Checkbox(T["Enable Pastel Colors"], C.unitframes, "pastel")
    p:Dropdown(T["Health Bar Color"], C.unitframes, "custom", D.uf_color)
    p:Color(T["Custom Health Bar Color"], C.unitframes, "customcolor")
    p:Checkbox(T["Fade To Custom Color"], C.unitframes, "customfade")
    p:Checkbox(T["Use Custom Color On Full Health"], C.unitframes, "customfullhp")
    p:Checkbox(T["Enable Custom Color Health Bar Background"], C.unitframes, "custombg")
    p:Color(T["Custom Health Bar Background Color"], C.unitframes, "custombgcolor")
    p:Checkbox(T["Enable Custom Color Power Bar Background"], C.unitframes, "custompbg")
    p:Color(T["Custom Power Bar Background Color"], C.unitframes, "custompbgcolor")
    p:Color(T["Mana Color"], C.unitframes, "manacolor")
    p:Color(T["Rage Color"], C.unitframes, "ragecolor")
    p:Color(T["Energy Color"], C.unitframes, "energycolor")
    p:Color(T["Focus Color"], C.unitframes, "focuscolor")

    p:Header(T["Druid Settings"])
    p:Checkbox(T["Show Druid Mana Bar"], C.unitframes, "druidmanabar")
    p:Checkbox(T["Show Druid Mana Bar Text"], C.unitframes, "druidmanatext")
    p:Number(T["Druid Mana Bar Height"], C.unitframes, "druidmanaheight")
    p:Number(T["Druid Mana Bar Width (-1 = auto)"], C.unitframes, "druidmanawidth")
    p:Number(T["Druid Mana Bar X-Offset"], C.unitframes, "druidmanaoffx")
    p:Number(T["Druid Mana Bar Y-Offset"], C.unitframes, "druidmanaoffy")
    p:Number(T["Druid Mana Bar Spacing"], C.unitframes, "druidmanaspace")
    p:Dropdown(T["Druid Mana Bar Texture"], C.unitframes, "druidmanatexture", D.uf_bartexture)


    p:Header(T["Target Indicators"])
    p:Number(T["Target Indicator Font Size"], C.unitframes, "indicator_font_size")
    p:Checkbox(T["Show Line of Sight Indicator"], C.unitframes, "los_indicator")

    p:Header(T["SuperWoW Settings"])
    p:Checkbox(T["Track Group on Minimap"], C.unitframes, "track_group")

    p:Header(T["Nampower Settings"])
    p:Checkbox(T["Show Spell Queue Indicator"], C.unitframes, "spellqueue")
    p:Number(T["Spell Queue Icon Size"], C.unitframes, "spellqueuesize")
    p:Checkbox(T["Show Reactive Spell Indicator"], C.unitframes, "reactive_indicator")
    p:Number(T["Reactive Indicator Size"], C.unitframes, "reactive_size")

    p:Header(T["UnitXP Settings"])
    p:Checkbox(T["Show Behind Indicator"], C.unitframes, "behind_indicator")
    p:Checkbox(T["Show Distance of Target"], C.unitframes, "distance_indicator")
    p:Checkbox(T["Hide yd characters"], C.unitframes, "hide_distance_yd")
    p:Checkbox(T["Hook Distance to Portrait Frame"], C.unitframes, "distance_hook_portrait")
    p:Checkbox(T["Enable OS Notifications"], C.unitframes, "unitxp_notify")
  end)

  -- Shared Unit- and Groupframes
  local unitframeSettings = {
    --      config,        text
    [1] = { "player",      T["Player"] },
    [2] = { "target",      TARGET },
    [3] = { "ttarget",     T["Target-Target"]},
    [4] = { "tttarget",    T["Target-Target-Target"]},
    [5] = { "pet",         PET },
    [6] = { "ptarget",     T["Pet-Target"]},
    [7] = { "focus",       T["Focus"] },
    [8] = { "focustarget", T["Focus-Target"] },
    [9] = { "group",       GROUP },
    [10] = { "grouptarget", T["Group-Target"]},
    [11] = { "grouppet",   T["Group-Pet"] },
    [12] = { "raid",       RAID },
    [13] = { "raidpet",    T["Raid-Pet"] },
  }

  gui:AddPage("unitframes.clickcast", T["Unit Frames"], T["Click Casting"], function(p)
    for id, data in ipairs(unitframeSettings) do
      p:Checkbox(T["Enable"] .. " " .. data[2] .. " " .. T["Click Casting"], C.unitframes[data[1]], "clickcast", U[data[1]])
    end

    p:Header(T["Left Mouse Button"])
    p:Text(T["Click Action"], C.unitframes, "clickcast")
    p:Text(T["Shift-Click Action"], C.unitframes, "clickcast_shift")
    p:Text(T["Alt-Click Action"], C.unitframes, "clickcast_alt")
    p:Text(T["Ctrl-Click Action"], C.unitframes, "clickcast_ctrl")

    p:Header(T["Right Mouse Button"])
    p:Text(T["Click Action"], C.unitframes, "clickcast2")
    p:Text(T["Shift-Click Action"], C.unitframes, "clickcast2_shift")
    p:Text(T["Alt-Click Action"], C.unitframes, "clickcast2_alt")
    p:Text(T["Ctrl-Click Action"], C.unitframes, "clickcast2_ctrl")

    p:Header(T["Middle Mouse Button"])
    p:Text(T["Click Action"], C.unitframes, "clickcast3")
    p:Text(T["Shift-Click Action"], C.unitframes, "clickcast3_shift")
    p:Text(T["Alt-Click Action"], C.unitframes, "clickcast3_alt")
    p:Text(T["Ctrl-Click Action"], C.unitframes, "clickcast3_ctrl")

    p:Header(KEY_BUTTON4)
    p:Text(T["Click Action"], C.unitframes, "clickcast4")
    p:Text(T["Shift-Click Action"], C.unitframes, "clickcast4_shift")
    p:Text(T["Alt-Click Action"], C.unitframes, "clickcast4_alt")
    p:Text(T["Ctrl-Click Action"], C.unitframes, "clickcast4_ctrl")

    p:Header(KEY_BUTTON5)
    p:Text(T["Click Action"], C.unitframes, "clickcast5")
    p:Text(T["Shift-Click Action"], C.unitframes, "clickcast5_shift")
    p:Text(T["Alt-Click Action"], C.unitframes, "clickcast5_alt")
    p:Text(T["Ctrl-Click Action"], C.unitframes, "clickcast5_ctrl")
  end)

  for id, data in ipairs(unitframeSettings) do
    local c = data[1]
    local t = data[2]

    gui:AddPage("unitframes." .. c, T["Unit Frames"], t, function(p)
      -- link Update tables
      U.ttarget     = U["targettarget"]
      U.tttarget    = U["targettargettarget"]
      U.ptarget     = U["pettarget"]
      U.grouptarget = U["group"]
      U.grouppet    = U["group"]
      U.raidpet     = U["raid"]

      -- build config entries
      p:Checkbox(T["Display Frame"] .. ": " .. t, C.unitframes[c], "visible", U[c])
      p:Dropdown(T["Default Transparency"], C.unitframes[c], "alpha_visible", D.percent_small, U[c])
      p:Dropdown(T["Out Of Range Transparency"], C.unitframes[c], "alpha_outrange", D.percent_small, U[c])
      p:Dropdown(T["Offline Transparency"], C.unitframes[c], "alpha_offline", D.percent_small, U[c])
      p:Checkbox(T["Enable Range Fading"], C.unitframes[c], "faderange", U[c])
      p:Checkbox(T["Enable Aggro Glow"], C.unitframes[c], "glowaggro", U[c])
      p:Checkbox(T["Enable Combat Glow"], C.unitframes[c], "glowcombat", U[c])
      p:Dropdown(T["Portrait Position"], C.unitframes[c], "portrait", D.uf_portrait_position, U[c])
      p:Number(T["Portrait Width"], C.unitframes[c], "portraitwidth", U[c])
      p:Number(T["Portrait Height"], C.unitframes[c], "portraitheight", U[c])
      p:Dropdown(T["Health Bar Texture"], C.unitframes[c], "bartexture", D.uf_bartexture, U[c])
      p:Dropdown(T["Power Bar Texture"], C.unitframes[c], "pbartexture", D.uf_bartexture, U[c])
      p:Number(T["UnitFrame Spacing"], C.unitframes[c], "pspace", U[c])
      p:Checkbox(T["Show PvP-Flag"], C.unitframes[c], "showPVP", U[c])
      p:Number(T["PVP Flag Size"], C.unitframes[c], "pvpiconsize", U[c])
      p:Dropdown(T["PvP Flag Position"], C.unitframes[c], "pvpiconalign", D.positions, U[c])
      p:Number(T["PvP Flag X-Offset"], C.unitframes[c], "pvpiconoffx", U[c])
      p:Number(T["PvP Flag Y-Offset"], C.unitframes[c], "pvpiconoffy", U[c])
      p:Checkbox(T["Show Loot Icon"], C.unitframes[c], "looticon", U[c])
      p:Checkbox(T["Show Leader Icon"], C.unitframes[c], "leadericon", U[c])
      if c == "pet" then
        p:Dropdown(T["Show Happiness Icon"], C.unitframes[c], "happinessicon", D.uf_happiness, U[c])
        p:Number(T["Happiness Icon Size"], C.unitframes[c], "happinesssize", U[c])
      end
      p:Checkbox(T["Show Raid Mark"], C.unitframes[c], "raidicon", U[c])
      p:Dropdown(T["Raid Mark Position"], C.unitframes[c], "raidiconalign", D.positions, U[c])
      p:Number(T["Raid Mark X-Offset"], C.unitframes[c], "raidiconoffx", U[c])
      p:Number(T["Raid Mark Y-Offset"], C.unitframes[c], "raidiconoffy", U[c])
      p:Number(T["Raid Mark Size"], C.unitframes[c], "raidiconsize", U[c])
      p:Color(T["Heal Color"], C.unitframes[c], "healcolor", U[c])
      p:Dropdown(T["Display Overheal"], C.unitframes[c], "overhealperc", D.uf_overheal, U[c])

      if c == "raid" then
        p:Checkbox(T["Display Raid Group Label"], C.unitframes[c], "raidgrouplabel", U["raid"])
        p:Number(T["Group Label X-Offset"], C.unitframes[c], "grouplabelxoff", U["raid"])
        p:Number(T["Group Label Y-Offset"], C.unitframes[c], "grouplabelyoff", U["raid"])

        p:Header(T["Layout"])
        p:Number(T["Raid Padding"], C.unitframes[c], "raidpadding", U["raid"])
        p:Dropdown(T["Raid Layout"], C.unitframes[c], "raidlayout", D.uf_raidlayout, U["raid"])
        p:Dropdown(T["Raid Fill Direction"], C.unitframes[c], "raidfill", D.orientation, U["raid"])
        p:Checkbox(T["Grow Right To Left"], C.unitframes[c], "raidgrowleft", U["raid"])
        p:Checkbox(T["Collapse Empty Slots"], C.unitframes[c], "collapse", U["raid"])
      elseif c == "raidpet" then
        p:Header(T["Layout"])
        p:Number(T["Raid Padding"], C.unitframes[c], "raidpadding", U["raid"])
        p:Dropdown(T["Raid Layout"], C.unitframes[c], "raidlayout", D.uf_raidlayout, U["raid"])
        p:Dropdown(T["Raid Fill Direction"], C.unitframes[c], "raidfill", D.orientation, U["raid"])
        p:Checkbox(T["Collapse Empty Slots"], C.unitframes[c], "collapse", U["raid"])
      end

      p:Header(T["Healthbar"])
      p:Number(T["Health Bar Width"], C.unitframes[c], "width", U[c])
      p:Number(T["Health Bar Height"], C.unitframes[c], "height", U[c])
      p:Dropdown(T["Left Text"], C.unitframes[c], "txthpleft", D.uf_texts, U[c])
      p:Number(T["Left Text X Offset"], C.unitframes[c], "txthpleftoffx", U[c])
      p:Number(T["Left Text Y Offset"], C.unitframes[c], "txthpleftoffy", U[c])
      p:Dropdown(T["Center Text"], C.unitframes[c], "txthpcenter", D.uf_texts, U[c])
      p:Number(T["Center Text X Offset"], C.unitframes[c], "txthpcenteroffx", U[c])
      p:Number(T["Center Text Y Offset"], C.unitframes[c], "txthpcenteroffy", U[c])
      p:Dropdown(T["Right Text"], C.unitframes[c], "txthpright", D.uf_texts, U[c])
      p:Number(T["Right Text X Offset"], C.unitframes[c], "txthprightoffx", U[c])
      p:Number(T["Right Text Y Offset"], C.unitframes[c], "txthprightoffy", U[c])
      p:Checkbox(T["Invert Health Bar"], C.unitframes[c], "invert_healthbar", U[c])
      p:Checkbox(T["Enable Vertical Health Bar"], C.unitframes[c], "verticalbar", U[c])

      p:Header(T["Powerbar"])
      p:Number(T["Power Bar Height"], C.unitframes[c], "pheight", U[c])
      p:Number(T["Power Bar Width"], C.unitframes[c], "pwidth", U[c])
      p:Number(T["Power Bar X-Offset"], C.unitframes[c], "poffx", U[c])
      p:Number(T["Power Bar Y-Offset"], C.unitframes[c], "poffy", U[c])
      p:Dropdown(T["Left Text"], C.unitframes[c], "txtpowerleft", D.uf_texts, U[c])
      p:Number(T["Left Text X Offset"], C.unitframes[c], "txtpowerleftoffx", U[c])
      p:Number(T["Left Text Y Offset"], C.unitframes[c], "txtpowerleftoffy", U[c])
      p:Dropdown(T["Center Text"], C.unitframes[c], "txtpowercenter", D.uf_texts, U[c])
      p:Number(T["Center Text X Offset"], C.unitframes[c], "txtpowercenteroffx", U[c])
      p:Number(T["Center Text Y Offset"], C.unitframes[c], "txtpowercenteroffy", U[c])
      p:Dropdown(T["Right Text"], C.unitframes[c], "txtpowerright", D.uf_texts, U[c])
      p:Number(T["Right Text X Offset"], C.unitframes[c], "txtpowerrightoffx", U[c])
      p:Number(T["Right Text Y Offset"], C.unitframes[c], "txtpowerrightoffy", U[c])
      p:Dropdown(T["Power Bar Anchor"], C.unitframes[c], "panchor", D.uf_powerbar_position, U[c])

      if c == "player" then
        p:Header(T["Energy/Mana Ticks"])
        p:Checkbox(T["Enable Energy Ticks"], C.unitframes[c], "energy")
        p:Checkbox(T["Enable Mana Ticks"], C.unitframes[c], "manatick")
        p:Checkbox(T["Show Five Second Rule"], C.unitframes[c], "showfsr")
        p:Dropdown(T["Five Second Rule Style"], C.unitframes[c], "fsrstyle", function() return {"0:" .. T["Separate Bar"], "1:" .. T["Overlay"]} end)
        p:Number(T["Five Second Rule Height"], C.unitframes[c], "fsrheight")
      end

      p:Header(T["Combat Text"])
      p:Checkbox(T["Show Combat Text"], C.unitframes[c], "hitindicator", U[c])
      p:Dropdown(T["Combat Text Font"], C.unitframes[c], "hitindicatorfont", D.fonts, U[c])
      p:Number(T["Combat Text Size"], C.unitframes[c], "hitindicatorsize", U[c])

      p:Header(T["Text Colors"])
      p:Checkbox(T["Automatic Health Text Color"], C.unitframes[c], "healthcolor", U[c])
      p:Checkbox(T["Automatic Power Text Color"], C.unitframes[c], "powercolor", U[c])
      p:Checkbox(T["Automatic Level Text Color"], C.unitframes[c], "levelcolor", U[c])
      p:Checkbox(T["Automatic Class Text Color"], C.unitframes[c], "classcolor", U[c])

      p:Header(T["Buffs"])
      p:Dropdown(T["Buff And Debuff Timers"], C.unitframes[c], "aura_timers", D.cooldown_timers, UpdateCooldowns)
      p:Dropdown(T["Buff Position"], C.unitframes[c], "buffs", D.uf_buff_position, U[c])
      p:Number(T["Buff Size"], C.unitframes[c], "buffsize", U[c])
      p:Number(T["Buff Limit"], C.unitframes[c], "bufflimit", U[c])
      p:Number(T["Buffs Per Row"], C.unitframes[c], "buffperrow", U[c])
      p:Number(T["Own Buff Size"], C.unitframes[c], "ownbuffsize", U[c])
      p:Number(T["Buff X-Offset"], C.unitframes[c], "buffoffx", U[c])
      p:Number(T["Buff Y-Offset"], C.unitframes[c], "buffoffy", U[c])
      p:Number(T["Buff X-Spacing"], C.unitframes[c], "buffspacingx", U[c])
      p:Number(T["Buff Y-Spacing"], C.unitframes[c], "buffspacingy", U[c])

      p:Header(T["Debuffs"])
      p:Dropdown(T["Debuff Position"], C.unitframes[c], "debuffs", D.uf_buff_position, U[c])
      p:Number(T["Debuff Size"], C.unitframes[c], "debuffsize", U[c])
      p:Number(T["Debuff Limit"], C.unitframes[c], "debufflimit", U[c])
      p:Number(T["Debuffs Per Row"], C.unitframes[c], "debuffperrow", U[c])
      p:Number(T["Own Debuff Size"], C.unitframes[c], "owndebuffsize", U[c])
      p:Number(T["Debuff X-Offset"], C.unitframes[c], "debuffoffx", U[c])
      p:Number(T["Debuff Y-Offset"], C.unitframes[c], "debuffoffy", U[c])
      p:Number(T["Debuff X-Spacing"], C.unitframes[c], "debuffspacingx", U[c])
      p:Number(T["Debuff Y-Spacing"], C.unitframes[c], "debuffspacingy", U[c])

      if c ~= "player" then
      end

      p:Header(T["Combat/Aggro Indicators"])
      p:Checkbox(T["Display Aggro Indicator"], C.unitframes[c], "squareaggro", U[c])
      p:Checkbox(T["Display Combat Indicator"], C.unitframes[c], "squarecombat", U[c])
      p:Dropdown(T["Indicator Position"], C.unitframes[c], "squarepos", D.positions, U[c])
      p:Number(T["Indicator Size"], C.unitframes[c], "squaresize", U[c])

      p:Header(T["Buff/Debuff Indicators"])
      p:Checkbox(T["Enable Indicators"], C.unitframes[c], "buff_indicator", U[c])
      p:Checkbox(T["Show Stacks"], C.unitframes[c], "indicator_stacks", U[c])
      p:Dropdown(T["Indicator Timers"], C.unitframes[c], "indicator_timers", D.cooldown_timers, UpdateCooldowns)
      p:Number(T["Indicator Size"], C.unitframes[c], "indicator_size", U[c])
      p:Dropdown(T["Indicator Spacing"], C.unitframes[c], "indicator_spacing", D.spacing, U[c])
      p:Dropdown(T["Indicator Position"], C.unitframes[c], "indicator_pos", D.positions, U[c])
      p:List(T["Show Custom Indicators"], C.unitframes[c], "custom_indicator", U[c])
      p:Checkbox(T["Show Buff Indicators"], C.unitframes[c], "show_buffs", U[c])
      p:Checkbox(T["Show Hots Indicators"], C.unitframes[c], "show_hots", U[c])
      p:Checkbox(T["Show Hots of all Classes"], C.unitframes[c], "all_hots", U[c])
      p:Checkbox(T["Show Procs Indicators"], C.unitframes[c], "show_procs", U[c])
      p:Checkbox(T["Show Procs of all Classes"], C.unitframes[c], "all_procs", U[c])
      p:Checkbox(T["Show Totems Indicators"], C.unitframes[c], "show_totems", U[c])

      p:Header(T["Dispel Indicators"])
      p:Dropdown(T["Show Dispel Indicators"], C.unitframes[c], "debuff_indicator", D.uf_debuff_indicator, U[c])
      p:Checkbox(T["Only Class Dispellable"], C.unitframes[c], "debuff_ind_class", U[c])
      p:Dropdown(T["Indicator Position"], C.unitframes[c], "debuff_ind_pos", D.positions, U[c])
      p:Dropdown(T["Indicator Size"], C.unitframes[c], "debuff_ind_size", D.uf_debuff_indicator_size, U[c])

      p:Header(T["Overwrite Fonts"])
      p:Checkbox(T["Use Custom Font Settings"], C.unitframes[c], "customfont", U[c])
      p:Dropdown(T["Custom Font Name"], C.unitframes[c], "customfont_name", D.fonts, U[c])
      p:Number(T["Custom Font Size"], C.unitframes[c], "customfont_size", U[c])
      p:Dropdown(T["Custom Font Style"], C.unitframes[c], "customfont_style", D.fontstyle, U[c])

      p:Header(T["Overwrite Colors"])
      p:Checkbox(T["Inherit Default Colors"], C.unitframes[c], "defcolor", U[c])
      p:Dropdown(T["Health Bar Color"], C.unitframes[c], "custom", D.uf_color, U[c])
      p:Color(T["Custom Health Bar Color"], C.unitframes[c], "customcolor", U[c])
      p:Checkbox(T["Fade To Custom Color"], C.unitframes[c], "customfade", U[c])
      p:Checkbox(T["Use Custom Color On Full Health"], C.unitframes[c], "customfullhp", U[c])
      p:Color(T["Custom Health Bar Background Color"], C.unitframes[c], "custombgcolor", U[c])
      p:Checkbox(T["Use Custom Color Health Bar Background"], C.unitframes[c], "custombg", U[c])
      p:Color(T["Custom Power Bar Background Color"], C.unitframes[c], "custompbgcolor", U[c])
      p:Checkbox(T["Use Custom Color Power Bar Background"], C.unitframes[c], "custompbg", U[c])
      p:Color(T["Mana Color"], C.unitframes[c], "manacolor", U[c])
      p:Color(T["Rage Color"], C.unitframes[c], "ragecolor", U[c])
      p:Color(T["Energy Color"], C.unitframes[c], "energycolor", U[c])
      p:Color(T["Focus Color"], C.unitframes[c], "focuscolor", U[c])

      if c == "player" then
        p:Header(T["Player SP/Haste Display"])
        p:Checkbox(T["Haste Display"], C.unitframes[c], "display_haste")
        p:Color(T["Haste Display Color"], C.unitframes[c], "display_haste_color")
        p:Checkbox(T["Display Spell Power"], C.unitframes[c], "display_spellpower")
        p:Checkbox(T["Use Custom Spell Power Color (unchecked = biggest school color)"], C.unitframes[c], "display_sp_color_override")
        p:Color(T["Spell Power Color"], C.unitframes[c], "display_sp_color")
      end
    end)
  end

  gui:AddPage("character.inventory", CHARACTER, T["Inventory"], function(p)
    p:Checkbox(T["Show Durability"], C.character.inventory, "durability")
    p:Checkbox(T["Always Show Equipment Slot Flyouts"], C.character.inventory, "equipflyout")
  end)

  gui:AddPage("character.equipmentmanager", CHARACTER, EQUIPMENT_MANAGER, function(p)
    p:Header(T["Automatic Set Switching"])
    p:Checkbox(T["Enable Automatic Set Switching"], C.equipmentmanager, "autoswitch", U["equipmentmanager"])
    p:Checkbox(T["Announce Automatic Set Switches In Chat"], C.equipmentmanager, "announce", U["equipmentmanager"])
    p:Header(T["Items Not In Any Set"])
    p:Dropdown(T["Minimum Item Quality"], C.equipmentmanager, "unusedquality", {
      "0:" .. ITEM_QUALITY0_DESC,
      "1:" .. ITEM_QUALITY1_DESC,
      "2:" .. ITEM_QUALITY2_DESC,
      "3:" .. ITEM_QUALITY3_DESC,
      "4:" .. ITEM_QUALITY4_DESC,
    }, U["equipmentmanager"])
    p:Checkbox(T["Include Bank Items"], C.equipmentmanager, "unusedbank", U["equipmentmanager"])
  end)

  gui:AddPage("character.reputation", CHARACTER, REPUTATION, function(p)
    p:Checkbox(T["Show Reputation Remaining"], C.character.reputation, "repRequired")
  end)

  gui:AddPage("bags", T["Bags & Bank"], nil, function(p)
    p:Checkbox(T["Disable Item Quality Color For \"Common\" Items"], C.appearance.bags, "borderlimit")
    p:Checkbox(T["Enable Item Quality Color For Equipment Only"], C.appearance.bags, "borderonlygear")
    p:Checkbox(T["Highlight Unusable Items"], C.appearance.bags, "unusable")
    p:Color(T["Unusable Item Color"], C.appearance.bags, "unusable_color")
    p:Checkbox(T["Highlight New Items"], C.appearance.bags, "newitem")
    p:Color(T["New Item Color"], C.appearance.bags, "newitem_color")
    p:Checkbox(T["Enable Movable Bags"], C.appearance.bags, "movable")
    p:Checkbox(T["Anchor Bags Above Chat"], C.appearance.bags, "abovechat")
    p:Checkbox(T["Hide Chat When Bags Are Opened"], C.appearance.bags, "hidechat")
    p:Number(T["Bagslots Per Row"], C.appearance.bags, "bagrowlength")
    p:Number(T["Bankslots Per Row"], C.appearance.bags, "bankrowlength")
    p:Number(T["Item Slot Size"], C.appearance.bags, "icon_size")
    p:Dropdown(T["Cooldown Timers"], C.appearance.bags, "timers", D.cooldown_timers, UpdateCooldowns)
    p:Checkbox(T["Auto Sell Grey Items"], C.global, "autosell")
    p:Checkbox(T["Auto Repair Items"], C.global, "autorepair")
    p:Checkbox(T["Auto Sort When Opening Bags"], C.appearance.bags, "autoSortOnOpen")
  end)

  gui:AddPage("loot", LOOT, nil, function(p)
    p:Checkbox(T["Enable Auto-Resize Loot Frame"], C.loot, "autoresize")
    p:Checkbox(T["Disable Loot Confirmation Dialog (Without Group)"], C.loot, "autopickup")
    p:Checkbox(T["Enable Loot Window On MouseCursor"], C.loot, "mousecursor")
    p:Checkbox(T["Enable Advanced Master Loot Menu"], C.loot, "advancedloot")
    p:Dropdown(T["Random Roll Announcement Rarity"], C.loot, "rollannouncequal", D.loot_rarity)
    p:Checkbox(T["Detailed Random Roll Announcement"], C.loot, "rollannounce")
    p:Checkbox(T["Use Item Rarity Color For Loot-Roll Timer"], C.loot, "raritytimer")
  end)

  gui:AddPage("minimap.minimap", MINIMAP_LABEL, MINIMAP_LABEL, function(p)
    p:Number(T["Minimap Size (|cffffaaaaExperimental|r)"], C.appearance.minimap, "size", U["minimap"])
    p:Number(T["Minimap Player Arrow Scale"], C.appearance.minimap, "arrowscale", U["minimap"])
    p:Dropdown(T["Zone Text On Minimap"], C.appearance.minimap, "zonetext", D.minimap_zone_visibility)
    p:Dropdown(T["Coordinates On Minimap"], C.appearance.minimap, "coordstext", D.minimap_cords_visibility)
    p:Dropdown(T["Coordinates Location"], C.appearance.minimap, "coordsloc", D.minimap_cords_position)
    p:Checkbox(T["Show PvP Icon"], C.unitframes.player, "showPVPMinimap")
    p:Checkbox(T["Show Inactive Tracking"], C.appearance.minimap, "tracking_pulse")
    p:Number(T["Tracking Icon Size"], C.appearance.minimap, "tracking_size")
    p:Checkbox(T["Hide Addon Buttons On Combat"], C.appearance.minimap, "addon_buttons")
  end)

  gui:AddPage("minimap.addonbuttons", MINIMAP_LABEL, T["Addon Buttons"], function(p)
    p:Checkbox(T["Enable Addon Button Frame"], C.abuttons, "enable")
    p:Dropdown(T["Addon Buttons Panel Position"], C.abuttons, "position", D.addonbuttons_position, U["addonbuttons"])
    p:Checkbox(T["Show Addon Buttons On Login"], C.abuttons, "showdefault", U["addonbuttons"])
    p:Number(T["Number Of Buttons Per Row/Column"], C.abuttons, "rowsize", U["addonbuttons"])
    p:Number(T["Button Spacing"], C.abuttons, "spacing", U["addonbuttons"])
    p:Checkbox(T["Hide When Entering Combat"], C.abuttons, "hideincombat", U["addonbuttons"])
  end)

  gui:AddPage("buffs.icons", T["Buffs"], T["Buff/Debuff Icons"], function(p)
    p:Checkbox(T["Enable Buff Display"], C.buffs, "buffs", U["buff"])
    p:Checkbox(T["Enable Debuff Display"], C.buffs, "debuffs", U["buff"])
    p:Checkbox(T["Enable Weapon Buff Display"], C.buffs, "weapons", U["buff"])
    p:Checkbox(T["Seperate Weapon Buffs"], C.buffs, "separateweapons", U["buff"])
    p:Number(T["Buff Size"], C.buffs, "size", U["buff"])
    p:Number(T["Buff Spacing"], C.buffs, "spacing", U["buff"])
    p:Number(T["Number Of Weapon Buffs Per Row"], C.buffs, "wepbuffrowsize", U["buff"])
    p:Number(T["Number Of Buffs Per Row"], C.buffs, "buffrowsize", U["buff"])
    p:Number(T["Number Of Debuffs Per Row"], C.buffs, "debuffrowsize", U["buff"])
    p:Dropdown(T["Duration Timers"], C.buffs, "timers", D.cooldown_timers, UpdateCooldowns)
    p:Checkbox(T["Show Duration Inside Buff"], C.buffs, "textinside", U["buff"])
    p:Number(T["Stack Count Font Size"], C.buffs, "fontsize", U["buff"])
  end)

  gui:AddPage("buffs.totems", T["Buffs"], T["Totem Icons"], function(p)
    p:Dropdown(T["Totem Direction"], C.totems, "direction", D.orientation, U["totems"])
    p:Number(T["Icon Size"], C.totems, "iconsize", U["totems"])
    p:Dropdown(T["Spacing"], C.totems, "spacing", D.spacing, U["totems"])
    p:Checkbox(T["Show Background"], C.totems, "showbg", U["totems"])
    p:Dropdown(T["Duration Timers"], C.totems, "timers", D.cooldown_timers, UpdateCooldowns)
  end)

  gui:AddPage("buffs.pbuff", T["Buffs"], T["Player Buff Bar"], function(p)
    p:Checkbox(T["Enable Bar"], C.buffbar.pbuff, "enable")
    p:Checkbox(T["Use Unit Fonts"], C.buffbar.pbuff, "use_unitfonts")
    p:Dropdown(T["Sort Order"], C.buffbar.pbuff, "sort", D.buffbarsort)
    p:Color(T["Background Color"], C.buffbar.pbuff, "color")
    p:Color(T["Border Color"], C.buffbar.pbuff, "bordercolor")
    p:Color(T["Text Color"], C.buffbar.pbuff, "textcolor")
    p:Checkbox(T["Automatic Background Color"], C.buffbar.pbuff, "dtypebg")
    p:Checkbox(T["Automatic Border Color"], C.buffbar.pbuff, "dtypeborder")
    p:Checkbox(T["Automatic Text Color"], C.buffbar.pbuff, "dtypetext")
    p:Checkbox(T["Color Buff Stacks"], C.buffbar.pbuff, "colorstacks")
    p:Number(T["Buffbar Width"], C.buffbar.pbuff, "width")
    p:Number(T["Buffbar Height"], C.buffbar.pbuff, "height")
    p:Dropdown(T["Filter Mode"], C.buffbar.pbuff, "filter", D.buffbarfilter)
    p:Number(T["Time Threshold"], C.buffbar.pbuff, "threshold")
    p:List(T["Whitelist"], C.buffbar.pbuff, "whitelist")
    p:List(T["Blacklist"], C.buffbar.pbuff, "blacklist")
  end)

  gui:AddPage("buffs.pdebuff", T["Buffs"], T["Player Debuff Bar"], function(p)
    p:Checkbox(T["Enable Bar"], C.buffbar.pdebuff, "enable")
    p:Checkbox(T["Use Unit Fonts"], C.buffbar.pdebuff, "use_unitfonts")
    p:Dropdown(T["Sort Order"], C.buffbar.pdebuff, "sort", D.buffbarsort)
    p:Color(T["Background Color"], C.buffbar.pdebuff, "color")
    p:Color(T["Border Color"], C.buffbar.pdebuff, "bordercolor")
    p:Color(T["Text Color"], C.buffbar.pdebuff, "textcolor")
    p:Checkbox(T["Automatic Background Color"], C.buffbar.pdebuff, "dtypebg")
    p:Checkbox(T["Automatic Border Color"], C.buffbar.pdebuff, "dtypeborder")
    p:Checkbox(T["Automatic Text Color"], C.buffbar.pdebuff, "dtypetext")
    p:Checkbox(T["Color Debuff Stacks"], C.buffbar.pdebuff, "colorstacks")
    p:Number(T["Buffbar Width"], C.buffbar.pdebuff, "width")
    p:Number(T["Buffbar Height"], C.buffbar.pdebuff, "height")
    p:Dropdown(T["Filter Mode"], C.buffbar.pdebuff, "filter", D.buffbarfilter)
    p:Number(T["Time Threshold"], C.buffbar.pdebuff, "threshold")
    p:List(T["Whitelist"], C.buffbar.pdebuff, "whitelist")
    p:List(T["Blacklist"], C.buffbar.pdebuff, "blacklist")
  end)

  gui:AddPage("buffs.tdebuff", T["Buffs"], T["Target Debuff Bar"], function(p)
    p:Checkbox(T["Enable Bar"], C.buffbar.tdebuff, "enable")
    p:Checkbox(T["Use Unit Fonts"], C.buffbar.tdebuff, "use_unitfonts")
    p:Dropdown(T["Sort Order"], C.buffbar.tdebuff, "sort", D.buffbarsort)
    p:Color(T["Background Color"], C.buffbar.tdebuff, "color")
    p:Color(T["Border Color"], C.buffbar.tdebuff, "bordercolor")
    p:Color(T["Text Color"], C.buffbar.tdebuff, "textcolor")
    p:Checkbox(T["Automatic Background Color"], C.buffbar.tdebuff, "dtypebg")
    p:Checkbox(T["Automatic Border Color"], C.buffbar.tdebuff, "dtypeborder")
    p:Checkbox(T["Automatic Text Color"], C.buffbar.tdebuff, "dtypetext")
    p:Checkbox(T["Color Debuff Stacks"], C.buffbar.tdebuff, "colorstacks")
    p:Number(T["Buffbar Width"], C.buffbar.tdebuff, "width")
    p:Number(T["Buffbar Height"], C.buffbar.tdebuff, "height")
    p:Checkbox(T["Show Only Own Debuffs"], C.buffbar.tdebuff, "selfdebuff")
    p:Dropdown(T["Filter Mode"], C.buffbar.tdebuff, "filter", D.buffbarfilter)
    p:Number(T["Time Threshold"], C.buffbar.tdebuff, "threshold")
    p:List(T["Whitelist"], C.buffbar.tdebuff, "whitelist")
    p:List(T["Blacklist"], C.buffbar.tdebuff, "blacklist")
  end)

  gui:AddPage("actionbar.general", T["Actionbar"], T["General"], function(p)
    p:Checkbox(T["Trigger Actions On Key Down"], C.bars, "keydown", U["bars"])
    p:Checkbox(T["Self Cast: Alt Key"], C.bars, "altself", U["bars"])
    p:Checkbox(T["Self Cast: Right Click"], C.bars, "rightself", U["bars"])
    p:Dropdown(T["Button Animation"], C.bars, "animation", D.actionbuttonanimations, U["bars"])
    p:Dropdown(T["Button Animation Trigger"], C.bars, "animmode", D.animationmode, U["bars"])
    p:Dropdown(T["Cooldown Timers"], C.bars, "timers", D.cooldown_timers, UpdateCooldowns)
    p:Checkbox(T["Show Animation On Hidden Bars"], C.bars, "animalways", U["bars"])
    p:Checkbox(T["Show Reagent Count"], C.bars, "reagents", U["bars"])
    p:Checkbox(T["Highlight Equipped Items"], C.bars, "showequipped", U["bars"])
    p:Color(T["Equipped Item Color"], C.bars, "eqcolor", U["bars"])
    p:Checkbox(T["Highlight Out Of Range Spells"], C.bars, "glowrange", U["bars"])
    p:Color(T["Out Of Range Color"], C.bars, "rangecolor", U["bars"])
    p:Checkbox(T["Highlight Out Of Mana Spells"], C.bars, "showoom", U["bars"])
    p:Color(T["Out Of Mana Color"], C.bars, "oomcolor", U["bars"])
    p:Checkbox(T["Highlight Not Usable Spells"], C.bars, "showna", U["bars"])
    p:Color(T["Not Usable Color"], C.bars, "nacolor", U["bars"])
    p:Checkbox(T["Highlight Proc And Reactive Spells"], C.bars, "procglow", U["bars"])
    p:Checkbox(T["Lock Actionbars"], UVars, "LOCK_ACTIONBAR", U["bars"])
    p:Checkbox(T["Always Allow Drag Via Shift Key"], C.bars, "shiftdrag", U["bars"])

    p:Header(T["Font Options"])
    p:Dropdown(T["Font"], C.bars, "font", D.fonts, U["bars"])
    p:Number(T["Font Padding"], C.bars, "font_offset", U["bars"])
    p:Number(T["Macro Text Size"], C.bars, "macro_size", U["bars"])
    p:Color(T["Macro Text Color"], C.bars, "macro_color", U["bars"])
    p:Number(T["Item Count Text Size"], C.bars, "count_size", U["bars"])
    p:Color(T["Item Count Text Color"], C.bars, "count_color", U["bars"])
    p:Number(T["Keybind Text Size"], C.bars, "bind_size", U["bars"])
    p:Color(T["Keybind Text Color"], C.bars, "bind_color", U["bars"])

    p:Header(T["Auto Paging"])
    p:Checkbox(T["Switch Pages On Alt Key Press"], C.bars, "pagemasteralt", U["bars"])
    p:Checkbox(T["Switch Pages On Shift Key Press"], C.bars, "pagemastershift", U["bars"])
    p:Checkbox(T["Switch Pages On Ctrl Key Press"], C.bars, "pagemasterctrl", U["bars"])
    p:Checkbox(T["Switch Pages On Druid Stealth"], C.bars, "druidstealth", U["bars"])
    p:Checkbox(T["Switch Pages On Priest Shadowform"], C.bars, "priestshadow", U["bars"])
    p:Checkbox(T["Range Based Hunter Paging"], C.bars, "hunterbar")
  end)

  gui:AddPage("actionbar.gryphons", T["Actionbar"], T["Gryphons"], function(p)
    p:Dropdown(T["Texture"], C.bars.gryphons, "texture", D.gryphons, U["gryphons"])
    p:Color(COLOR, C.bars.gryphons, "color", U["gryphons"])
    p:Dropdown(T["Left Anchor"], C.bars.gryphons, "anchor_left", D.xpanchors, U["gryphons"])
    p:Dropdown(T["Right Anchor"], C.bars.gryphons, "anchor_right", D.xpanchors, U["gryphons"])
    p:Number(T["Size"], C.bars.gryphons, "size", U["gryphons"])
    p:Number(T["Horizontal Offset"], C.bars.gryphons, "offset_h", U["gryphons"])
    p:Number(T["Vertical Offset"], C.bars.gryphons, "offset_v", U["gryphons"])
  end)

  -- Shared Actionbar Settings
  local barnames = {
    -- default
    {1, T["Main Actionbar"]},
    {6, T["Top Actionbar"]},
    {5, T["Left Actionbar"]},
    {3, T["Right Actionbar"]},
    {4, T["Vertical Actionbar"]},

    -- special
    {2, T["Paging Actionbar"]},
    {7, T["Stance Bar 1"]},
    {8, T["Stance Bar 2"]},
    {9, T["Stance Bar 3"]},
    {10, T["Stance Bar 4"]},

    -- class
    {11, T["Shapeshift Bar"]},
    {12, T["Pet Actionbar"]},
  }

  for _, data in pairs(barnames) do
    local id, caption = data[1], data[2]
    local formfactors = function()
      return BarLayoutOptions(tonumber(C.bars["bar"..id].buttons) or id < 11 and NUM_ACTIONBAR_BUTTONS or id > 11 and NUM_SHAPESHIFT_SLOTS or NUM_PET_ACTION_SLOTS)
    end
    local uneven_options = function()
      local formfactor = tostring(C.bars["bar"..id].formfactor or "")
      local _, _, cols, rows = string.find(formfactor, "(%d+)%s*x%s*(%d+)")
      cols, rows = tonumber(cols), tonumber(rows)

      if cols == 3 and rows == 3 then
        return { "Up:" .. T["Up"], "Down:" .. T["Down"], "Left:" .. T["Left"], "Right:" .. T["Right"] }
      elseif cols and cols <= 3 then
        return { "Up:" .. T["Up"], "Down:" .. T["Down"] }
      elseif rows and rows <= 3 then
        return { "Left:" .. T["Left"], "Right:" .. T["Right"] }
      end

      return { "Up:" .. T["Up"], "Down:" .. T["Down"], "Left:" .. T["Left"], "Right:" .. T["Right"] }
    end

    gui:AddPage("actionbar.bar" .. id, T["Actionbar"], caption, function(p)
      p:Checkbox(T["Enable"], C.bars["bar"..id], "enable", U["bars"])

      if id ~= 11 and id ~= 12 then
        p:Dropdown(T["Buttons"], C.bars["bar"..id], "buttons", D.actionbarbuttons, U["bars"])
        if id ~= 1 then
          p:Checkbox(T["Pageable"], C.bars["bar"..id], "pageable", U["bars"])
        end
      end

      if id == 12 then
        p:Checkbox(T["Auto-Castable Action Indicator"], C.bars, "showcastable", U["bars"])
      end

      p:Number(T["Icon Size"], C.bars["bar"..id], "icon_size", U["bars"])
      p:Dropdown(T["Spacing"], C.bars["bar"..id], "spacing", D.actionbarbuttons, U["bars"])
      -- a new layout keeps an uneven orientation that fits it; the page
      -- shows the change, as it refreshes its rows after each one
      local layout_ufunc = function()
        local formfactor = tostring(C.bars["bar"..id].formfactor or "")
        local _, _, cols, rows = string.find(formfactor, "(%d+)%s*x%s*(%d+)")
        cols, rows = tonumber(cols), tonumber(rows)
        local is_square = cols == 3 and rows == 3
        local is_vertical = cols and cols <= 3 and not is_square
        local is_horizontal = rows and rows <= 3 and not is_square
        local uneven = C.bars["bar"..id].uneven
        if is_vertical then
          if uneven ~= "Up" and uneven ~= "Down" then C.bars["bar"..id].uneven = "Down" end
        elseif is_horizontal then
          if uneven ~= "Left" and uneven ~= "Right" then C.bars["bar"..id].uneven = "Left" end
        end
        if U["bars"] then U["bars"]() end
      end
      p:Dropdown(T["Layout"], C.bars["bar"..id], "formfactor", formfactors, layout_ufunc)
      p:Dropdown(T["Layout Uneven Orientation"], C.bars["bar"..id], "uneven", uneven_options, U["bars"])
      p:Dropdown(T["Fill Order"], C.bars["bar"..id], "fillmode", function()
        return {"auto:" .. T["Auto"], "row:" .. T["Row-first (1,2,3 / 4,5,6)"], "col:" .. T["Column-first (1,3,5 / 2,4,6)"]}
      end, U["bars"])
      p:Checkbox(T["Bar Background"], C.bars["bar"..id], "background", U["bars"])
      p:Checkbox(T["Show Hotkey Text"], C.bars["bar"..id], "showkeybind", U["bars"])

      if id ~= 11 and id ~= 12 then
        p:Checkbox(T["Show Macro Text"], C.bars["bar"..id], "showmacro", U["bars"])
        p:Checkbox(T["Show Item Count Text"], C.bars["bar"..id], "showcount", U["bars"])
      end

      if id ~= 11 then
        p:Checkbox(T["Show Empty Buttons"], C.bars["bar"..id], "showempty", U["bars"])
      end

      p:Checkbox(T["Enable Autohide"], C.bars["bar"..id], "autohide", U["bars"])
      p:Number(T["Autohide Timeout"], C.bars["bar"..id], "hide_time", U["bars"])
      p:Checkbox(T["Show In Combat"], C.bars["bar"..id], "hide_combat", U["bars"])
    end)
  end

  gui:AddPage("panel", T["Panel"], nil, function(p)
    p:Checkbox(T["Use Unit Fonts"], C.panel, "use_unitfonts")
    p:Dropdown(T["Left Panel: Left"], C.panel.left, "left", D.panel_values)
    p:Dropdown(T["Left Panel: Center"], C.panel.left, "center", D.panel_values)
    p:Dropdown(T["Left Panel: Right"], C.panel.left, "right", D.panel_values)
    p:Dropdown(T["Right Panel: Left"], C.panel.right, "left", D.panel_values)
    p:Dropdown(T["Right Panel: Center"], C.panel.right, "center", D.panel_values)
    p:Dropdown(T["Right Panel: Right"], C.panel.right, "right", D.panel_values)
    p:Dropdown(T["Other Panel: Minimap"], C.panel.other, "minimap", D.panel_values)
    p:Checkbox(T["Only Count Bagspace On Regular Bags"], C.panel.bag, "ignorespecial")
    p:Checkbox(T["Enable Micro Bar"], C.panel.micro, "enable")
    p:Checkbox(T["Enable 24h Clock"], C.global, "twentyfour")
    p:Checkbox(T["Enable Seconds"], C.panel, "seconds")
    p:Checkbox(T["Servertime"], C.global, "servertime")
    p:Checkbox(T["Show FPS and Latency Colors"], C.panel, "fpscolors", U["panel"])

    p:Header(T["Auto Hide"])
    p:Checkbox(T["Enable Autohide For Left Chat Panel"], C.panel, "hide_leftchat")
    p:Checkbox(T["Enable Autohide For Right Chat Panel"], C.panel, "hide_rightchat")
    p:Checkbox(T["Enable Autohide For Minimap Panel"], C.panel, "hide_minimap")
    p:Checkbox(T["Enable Autohide For Microbar Panel"], C.panel, "hide_microbar")
  end)

  gui:AddPage("xpbar.xp", XPBAR_LABEL, T["Experience Bar"], function(p)
    p:Checkbox(T["Always Show"], C.panel.xp, "xp_always", U["xpbar"])
    p:Dropdown(T["Display Mode"], C.panel.xp, "xp_display", D.xp_display, U["xpbar"])
    p:Number(T["Hide Timeout"], C.panel.xp, "xp_timeout", U["xpbar"])
    p:Number(T["Width"], C.panel.xp, "xp_width", U["xpbar"])
    p:Number(T["Height"], C.panel.xp, "xp_height", U["xpbar"])
    p:Dropdown(T["Orientation"], C.panel.xp, "xp_mode", D.orientation, U["xpbar"])
    p:Dropdown(T["Frame Anchor"], C.panel.xp, "xp_anchor", D.xpanchors, U["xpbar"])
    p:Dropdown(T["Aligned Position"], C.panel.xp, "xp_position", D.xp_position, U["xpbar"])
    p:Checkbox(T["Don't overlap rested"], C.panel.xp, "dont_overlap", U["xpbar"])

    p:Header(T["Text"])
    p:Checkbox(T["Show Text"], C.panel.xp, "xp_text", U["xpbar"])
    p:Number(T["Vertical Text Offset"], C.panel.xp, "xp_text_off_y", U["xpbar"])
    p:Checkbox(T["Only Show On Mouse Over"], C.panel.xp, "xp_text_mouse", U["xpbar"])

    p:Header(T["Colors"])
    p:Color(T["Experience Color"], C.panel.xp, "xp_color", U["xpbar"])
    p:Color(T["Rested Color"], C.panel.xp, "rest_color", U["xpbar"])
    p:Dropdown(T["Bar Texture"], C.panel.xp, "texture", D.uf_bartexture, U["xpbar"])
  end)

  gui:AddPage("xpbar.rep", XPBAR_LABEL, T["Reputation Bar"], function(p)
    p:Checkbox(T["Always Show"], C.panel.xp, "rep_always", U["xpbar"])
    p:Dropdown(T["Display Mode"], C.panel.xp, "rep_display", D.xp_display, U["xpbar"])
    p:Number(T["Hide Timeout"], C.panel.xp, "rep_timeout", U["xpbar"])
    p:Number(T["Width"], C.panel.xp, "rep_width", U["xpbar"])
    p:Number(T["Height"], C.panel.xp, "rep_height", U["xpbar"])
    p:Dropdown(T["Orientation"], C.panel.xp, "rep_mode", D.orientation, U["xpbar"])
    p:Dropdown(T["Frame Anchor"], C.panel.xp, "rep_anchor", D.xpanchors, U["xpbar"])
    p:Dropdown(T["Aligned Position"], C.panel.xp, "rep_position", D.xp_position, U["xpbar"])

    p:Header(T["Text"])
    p:Checkbox(T["Show Text"], C.panel.xp, "rep_text", U["xpbar"])
    p:Number(T["Vertical Text Offset"], C.panel.xp, "rep_text_off_y", U["xpbar"])
    p:Checkbox(T["Only Show On Mouse Over"], C.panel.xp, "rep_text_mouse", U["xpbar"])
  end)

  gui:AddPage("tooltip", T["Tooltip"], nil, function(p)
    p:Header(T["General"])
    p:Dropdown(T["Tooltip Position"], C.tooltip, "position", D.tooltip_position)
    p:Dropdown(T["Tooltip Text Font"], C.tooltip, "font_tooltip", D.fonts)
    p:Number(T["Tooltip Text Font Size"], C.tooltip, "font_tooltip_size")
    p:Dropdown(T["Cursor Tooltip Align"], C.tooltip, "cursoralign", D.tooltip_align)
    p:Number(T["Cursor Tooltip Offset"], C.tooltip, "cursoroffset")
    p:Number(T["Custom Transparency"], C.tooltip, "alpha")
    p:Dropdown(T["Status Bar Texture"], C.tooltip.statusbar, "texture", D.uf_bartexture)

    p:Header(ITEMS)
    p:Checkbox(T["Always Show Item Comparison"], C.tooltip.compare, "showalways")
    p:Checkbox(T["Always Show Extended Vendor Values"], C.tooltip.vendor, "showalways")
    p:Checkbox(T["Show Related Quest On Questitems"], C.tooltip.questitem, "showquest", U["questitem"])
    p:Checkbox(T["Show Required Questitem Count"], C.tooltip.questitem, "showcount", U["questitem"])
    p:Checkbox(T["Show Item IDs"], C.tooltip, "itemid")

    p:Header(SPELLS)
    p:Checkbox(T["Show Aura Caster"], C.tooltip, "aurasource")
    p:Checkbox(T["Show Spell IDs"], C.tooltip, "spellid")

    p:Header(T["Units"])
    p:Checkbox(T["Enable Extended Guild Information"], C.tooltip, "extguild")
    p:Checkbox(T["Always Show Health In Percent"], C.tooltip, "alwaysperc")
    p:Checkbox(T["Show Movement Speed"], C.tooltip, "movespeed")
    p:Checkbox(T["Show Unit Buffs"], C.tooltip, "showbuffs")
    p:Dropdown(T["Unit Buff Timers"], C.tooltip, "aura_timers", D.cooldown_timers, UpdateCooldowns)
    p:Checkbox(T["Show Unit IDs"], C.tooltip, "unitid")
  end)

  gui:AddPage("castbar.general", T["Castbar"], T["General"], function(p)
    p:Checkbox(T["Use Unit Fonts"], C.castbar, "use_unitfonts")
    p:Color(T["Casting Color"], C.appearance.castbar, "castbarcolor")
    p:Color(T["Channeling Color"], C.appearance.castbar, "channelcolor")
    p:Color(T["Uninterruptible Color"], C.appearance.castbar, "shieldcolor")
    p:Color(T["Five Second Rule Color"], C.appearance.castbar, "fsrcolor")
    p:Dropdown(T["Castbar Texture"], C.appearance.castbar, "texture", D.uf_bartexture)
    p:Checkbox(T["Disable Blizzard Castbar"], C.castbar.player, "hide_blizz")
  end)

  gui:AddPage("castbar.player", T["Castbar"], T["Player"], function(p)
    p:Checkbox(T["Disable Player Castbar"], C.castbar.player, "hide_pfui")
    p:Number(T["Castbar Width"], C.castbar.player, "width")
    p:Number(T["Castbar Height"], C.castbar.player, "height")
    p:Checkbox(T["Show Spell Icon"], C.castbar.player, "showicon")
    p:Checkbox(T["Show Spell Name"], C.castbar.player, "showname")
    p:Dropdown(T["Spell Name Alignment"], C.castbar.player, "namealign", D.castbaralign)
    p:Number(T["Spell Name X Offset"], C.castbar.player, "txtleftoffx")
    p:Number(T["Spell Name Y Offset"], C.castbar.player, "txtleftoffy")
    p:Checkbox(T["Show Timer"], C.castbar.player, "showtimer")
    p:Dropdown(T["Timer Alignment"], C.castbar.player, "timealign", D.castbaralign)
    p:Number(T["Timer X Offset"], C.castbar.player, "txtrightoffx")
    p:Number(T["Timer Y Offset"], C.castbar.player, "txtrightoffy")
    p:Checkbox(T["Show Lag"], C.castbar.player, "showlag")
    p:Checkbox(T["Show Rank"], C.castbar.player, "showrank")
    p:Checkbox(T["Merge Tradeskill Casts"], C.castbar.player, "mergetradeskill")
  end)

  gui:AddPage("castbar.target", T["Castbar"], TARGET, function(p)
    p:Checkbox(T["Disable Target Castbar"], C.castbar.target, "hide_pfui")
    p:Number(T["Castbar Width"], C.castbar.target, "width")
    p:Number(T["Castbar Height"], C.castbar.target, "height")
    p:Checkbox(T["Show Spell Icon"], C.castbar.target, "showicon")
    p:Checkbox(T["Show Spell Name"], C.castbar.target, "showname")
    p:Dropdown(T["Spell Name Alignment"], C.castbar.target, "namealign", D.castbaralign)
    p:Number(T["Spell Name X Offset"], C.castbar.target, "txtleftoffx")
    p:Number(T["Spell Name Y Offset"], C.castbar.target, "txtleftoffy")
    p:Checkbox(T["Show Timer"], C.castbar.target, "showtimer")
    p:Dropdown(T["Timer Alignment"], C.castbar.target, "timealign", D.castbaralign)
    p:Number(T["Timer X Offset"], C.castbar.target, "txtrightoffx")
    p:Number(T["Timer Y Offset"], C.castbar.target, "txtrightoffy")
    p:Checkbox(T["Show Lag"], C.castbar.target, "showlag")
    p:Checkbox(T["Show Rank"], C.castbar.target, "showrank")
  end)

  gui:AddPage("castbar.focus", T["Castbar"], T["Focus"], function(p)
    p:Checkbox(T["Disable Focus Castbar"], C.castbar.focus, "hide_pfui")
    p:Number(T["Castbar Width"], C.castbar.focus, "width")
    p:Number(T["Castbar Height"], C.castbar.focus, "height")
    p:Checkbox(T["Show Spell Icon"], C.castbar.focus, "showicon")
    p:Checkbox(T["Show Spell Name"], C.castbar.focus, "showname")
    p:Dropdown(T["Spell Name Alignment"], C.castbar.focus, "namealign", D.castbaralign)
    p:Number(T["Spell Name X Offset"], C.castbar.focus, "txtleftoffx")
    p:Number(T["Spell Name Y Offset"], C.castbar.focus, "txtleftoffy")
    p:Checkbox(T["Show Timer"], C.castbar.focus, "showtimer")
    p:Dropdown(T["Timer Alignment"], C.castbar.focus, "timealign", D.castbaralign)
    p:Number(T["Timer X Offset"], C.castbar.focus, "txtrightoffx")
    p:Number(T["Timer Y Offset"], C.castbar.focus, "txtrightoffy")
    p:Checkbox(T["Show Lag"], C.castbar.focus, "showlag")
    p:Checkbox(T["Show Rank"], C.castbar.focus, "showrank")
  end)

  gui:AddPage("chat", CHAT_LABEL, nil, function(p)
    -- a nop updater skips the reload prompt; the nop settings below
    -- are read by AddMessage on every chat line
    p:Checkbox(T["Enable \"Loot & Spam\" Chat Window"], C.chat.right, "enable")
    p:Number(T["Inputbox Width"], C.chat.text, "input_width")
    p:Number(T["Inputbox Height"], C.chat.text, "input_height")
    p:Checkbox(T["Enable Text Shadow"], C.chat.text, "outline")
    p:Checkbox(T["Enable Chat History"], C.chat.text, "history")
    p:Checkbox(T["Show Items On Mouseover"], C.chat.text, "mouseover")
    p:Text(T["Chat Default Brackets"], C.chat.text, "bracket")
    p:Checkbox(T["Enable Timestamps"], C.chat.text, "time")
    p:Text(T["Timestamp Format"], C.chat.text, "timeformat", nop)
    p:Text(T["Timestamp Brackets"], C.chat.text, "timebracket")
    p:Color(T["Timestamp Color"], C.chat.text, "timecolor")
    -- read each time chat copy opens, so no reload
    p:Checkbox(T["Show Timestamps In Chat Copy"], C.chat.text, "copytime", nop)
    p:Checkbox(T["Hide Channel Names"], C.chat.text, "channelnumonly", nop)
    p:Checkbox(T["Generate Playerlinks"], C.chat.text, "playerlinks")
    p:Checkbox(T["Enable URL Detection"], C.chat.text, "detecturl", nop)
    p:Checkbox(T["Enable Class Colors"], C.chat.text, "classcolor", nop)
    local _, playerRace = UnitRace("player")
    p:Checkbox(T["Show Faction Icons"] .. " " .. GetFactionIcon(playerRace), C.chat.text, "factionicons", nop)
    p:Checkbox(T["Show Race Icons"] .. " " .. GetRaceIcon(playerRace, UnitSex("player")), C.chat.text, "raceicons", nop)
    p:Checkbox(T["Enable Player Levels"], C.chat.text, "playerlevel", nop)
    p:Checkbox(T["Colorize Unknown Classes"], C.chat.text, "tintunknown", nop)
    p:Color(T["Unknown Class Color"], C.chat.text, "unknowncolor")
    p:Number(T["Left Chat Width"], C.chat.left, "width")
    p:Number(T["Left Chat Height"], C.chat.left, "height")
    p:Number(T["Right Chat Width"], C.chat.right, "width")
    p:Number(T["Right Chat Height"], C.chat.right, "height")
    p:Checkbox(T["Hide Combat Log"], C.chat.global, "combathide")
    p:Checkbox(T["Enable Chat Dock Background"], C.chat.global, "tabdock")
    p:Checkbox(T["Only Show Chat Dock On Mouseover"], C.chat.global, "tabmouse")
    p:Checkbox(T["Enable Chat Tab Flashing"], C.chat.global, "chatflash")
    p:Checkbox(T["Enable Frame Shadow"], C.chat.global, "frameshadow")
    p:Checkbox(T["Enable Custom Colors"], C.chat.global, "custombg", U["chat"])
    p:Color(T["Chat Background Color"], C.chat.global, "background", U["chat"])
    p:Color(T["Chat Border Color"], C.chat.global, "border", U["chat"])
    p:Checkbox(T["Enable Custom Incoming Whispers Layout"], C.chat.global, "whispermod")
    p:Color(T["Incoming Whispers Color"], C.chat.global, "whisper")
    p:Checkbox(T["Enable Sticky Chat"], C.chat.global, "sticky")
    p:Number(T["Maximum Number Of Chat Lines"], C.chat.global, "maxlines")
    p:Checkbox(T["Enable Chat Fade"], C.chat.global, "fadeout")
    p:Number(T["Seconds Before Chat Fade"], C.chat.global, "fadetime")
    p:Number(T["Mousewheel Scroll Speed"], C.chat.global, "scrollspeed", nop)
    p:Checkbox(T["Enable Chat Bubbles"], CVars, "chatBubbles", nop)
    p:Checkbox(T["Enable Party Chat Bubbles"], CVars, "chatBubblesParty", nop)
    p:Checkbox(T["Enable Chat Bubble Borders"], C.chat.bubbles, "borders")
    p:Number(T["Chat Bubble Transparency"], C.chat.bubbles, "alpha")
  end)

  gui:AddPage("nameplates", T["Nameplates"], nil, function(p)
    p:Checkbox(T["Show On Hostile Units"], C.nameplates, "showhostile", U["nameplates"])
    p:Checkbox(T["Show On Friendly Units"], C.nameplates, "showfriendly", U["nameplates"])
    p:Checkbox(T["Disable Hostile Nameplates In Friendly Zones"], C.nameplates, "disable_hostile_in_friendly", U["nameplates"])
    p:Checkbox(T["Disable Friendly Nameplates In Friendly Zones"], C.nameplates, "disable_friendly_in_friendly", U["nameplates"])
    p:Number(T["Vertical Offset (|cffffaaaaExperimental|r)"], C.nameplates, "vertical_offset", U["nameplates"])
    p:Dropdown(T["Inactive Nameplate Alpha"], C.nameplates, "notargalpha", D.percent_small, U["nameplates"])
    p:Checkbox(T["Draw Glow Around Target Nameplate"], C.nameplates, "targetglow", U["nameplates"])
    p:Color(T["Glow Color Around Target Nameplate"], C.nameplates, "glowcolor", U["nameplates"])
    p:Checkbox(T["Red Name Text On Infight Units"], C.nameplates, "namefightcolor", U["nameplates"])
    p:Checkbox(T["Zoom Target Nameplate"], C.nameplates, "targetzoom", U["nameplates"])
    p:Dropdown(T["Target Nameplate Zoom Factor"], C.nameplates, "targetzoomval", D.percent_small, U["nameplates"])
    p:Number(T["Nameplate Width"], C.nameplates, "width", U["nameplates"])
    p:Checkbox(T["Enable Class Colors On Enemies"], C.nameplates, "enemyclassc", U["nameplates"])
    p:Checkbox(T["Enable Class Colors On Friends"], C.nameplates, "friendclassc", U["nameplates"])
    p:Checkbox(T["Enable Class Colors On Friends Name"], C.nameplates, "friendclassnamec", U["nameplates"])
    p:Checkbox(T["Enable Combo Point Display"], C.nameplates, "cpdisplay", U["nameplates"])
    p:Checkbox(T["Enable Clickthrough"], C.nameplates, "clickthrough", U["nameplates"])
    p:Checkbox(T["Enable Overlap"], C.nameplates, "overlap", U["nameplates"])
    p:Checkbox(T["Enable Mouselook With Right Click"], C.nameplates, "rightclick", U["nameplates"])
    p:Number(T["Right Click Auto Attack Threshold"], C.nameplates, "clickthreshold", U["nameplates"])
    p:Checkbox(T["Use Unit Fonts"], C.nameplates, "use_unitfonts", U["nameplates"])
    p:Dropdown(T["Font Style"], C.nameplates.name, "fontstyle", D.fontstyle, U["nameplates"])
    p:Checkbox(T["Replace Totems With Icons"], C.nameplates, "totemicons", U["nameplates"])
    p:Checkbox(T["Show Guild Name"], C.nameplates, "showguildname", U["nameplates"])

    p:Header(T["Raid Icon"])
    p:Dropdown(T["Raid Icon Position"], C.nameplates, "raidiconpos", D.positions, U["nameplates"])
    p:Number(T["Raid Icon X-Offset"], C.nameplates, "raidiconoffx", U["nameplates"])
    p:Number(T["Raid Icon Y-Offset"], C.nameplates, "raidiconoffy", U["nameplates"])
    p:Number(T["Raid Icon Size"], C.nameplates, "raidiconsize", U["nameplates"])

    p:Header(T["Castbar"])
    p:Checkbox(T["Enable Castbars"], C.nameplates, "showcastbar", U["nameplates"])
    p:Checkbox(T["Only Show Target Castbar"], C.nameplates, "targetcastbar", U["nameplates"])
    p:Checkbox(T["Enable Spellname"], C.nameplates, "spellname", U["nameplates"])
    p:Number(T["Castbar Height"], C.nameplates, "heightcast", U["nameplates"])

    p:Header(T["Debuffs"])
    p:Checkbox(T["Enable Debuffs"], C.nameplates, "showdebuffs", U["nameplates"])
    p:Checkbox(T["Show Debuffs on Hostile"], C.nameplates, "showdebuffs_hostile", U["nameplates"])
    p:Checkbox(T["Show Debuffs on Friendly"], C.nameplates, "showdebuffs_friendly", U["nameplates"])
    p:Checkbox(T["Only Show Your Debuffs"], C.nameplates, "owndebuffs", U["nameplates"])
    p:Dropdown(T["Debuff Position"], C.nameplates.debuffs, "position", D.debuffposition, U["nameplates"])
    p:Number(T["Debuff Icon Offset"], C.nameplates, "debuffoffset", U["nameplates"])
    p:Number(T["Debuff Icon Size"], C.nameplates, "debuffsize", U["nameplates"])
    p:Checkbox(T["Show Debuff Stacks"], C.nameplates.debuffs, "showstacks", U["nameplates"])
    p:Dropdown(T["Debuff Timers"], C.nameplates, "debuff_timers", D.cooldown_timers, UpdateCooldowns)

    p:Dropdown(T["Filter Mode"], C.nameplates.debuffs, "filter", D.buffbarfilter, U["nameplates"])
    p:List(T["Blacklist"], C.nameplates.debuffs, "blacklist", U["nameplates"])
    p:List(T["Whitelist"], C.nameplates.debuffs, "whitelist", U["nameplates"])

    p:Header(T["Outlines"])
    p:Checkbox(T["Blue Border On Friendly Players"], C.nameplates, "outfriendly", U["nameplates"])
    p:Checkbox(T["Green Border On Friendly NPCs"], C.nameplates, "outfriendlynpc", U["nameplates"])
    p:Checkbox(T["Yellow Border On Neutral Units"], C.nameplates, "outneutral", U["nameplates"])
    p:Checkbox(T["Red Border On Enemy Units"], C.nameplates, "outenemy", U["nameplates"])
    p:Checkbox(T["Border Around Target Unit"], C.nameplates, "targethighlight", U["nameplates"])
    p:Color(T["Border Color Around Target Unit"], C.nameplates, "highlightcolor", U["nameplates"])

    p:Header(T["Healthbar"])
    p:Number(T["Healthbar Vertical Offset"], C.nameplates.health, "offset", U["nameplates"])
    p:Number(T["Healthbar Height"], C.nameplates, "heighthealth", U["nameplates"])
    p:Dropdown(T["Healthbar Texture"], C.nameplates, "healthtexture", D.uf_bartexture, U["nameplates"])
    p:Checkbox(T["Show Health Points"], C.nameplates, "showhp", U["nameplates"])
    p:Dropdown(T["Health Text Position"], C.nameplates, "hptextpos", D.textalign, U["nameplates"])
    p:Dropdown(T["Name Text Position"], C.nameplates, "nametextpos", D.textalign, U["nameplates"])
    p:Dropdown(T["Health Text Format"], C.nameplates, "hptextformat", D.hpformat, U["nameplates"])
    p:Checkbox(T["Hide Healthbar On Enemy NPCs"], C.nameplates, "enemynpc", U["nameplates"])
    p:Checkbox(T["Hide Healthbar On Enemy Players"], C.nameplates, "enemyplayer", U["nameplates"])
    p:Checkbox(T["Hide Healthbar On Neutral NPCs"], C.nameplates, "neutralnpc", U["nameplates"])
    p:Checkbox(T["Hide Healthbar On Friendly NPCs"], C.nameplates, "friendlynpc", U["nameplates"])
    p:Checkbox(T["Hide Healthbar On Friendly Players"], C.nameplates, "friendlyplayer", U["nameplates"])
    p:Checkbox(T["Hide Healthbar On Critters"], C.nameplates, "critters", U["nameplates"])
    p:Checkbox(T["Hide Healthbar On Totems"], C.nameplates, "totems", U["nameplates"])
    p:Checkbox(T["Always Show On Units With Missing HP"], C.nameplates, "fullhealth", U["nameplates"])
    p:Checkbox(T["Always Show On Target Units"], C.nameplates, "target", U["nameplates"])
    p:Checkbox(T["Vertical Healthbar"], C.nameplates, "verticalhealth", U["nameplates"])

    p:Header(T["Nampower Settings"])
    p:Checkbox(T["Overwrite Border Color With Combat State"], C.nameplates, "outcombatstate", U["nameplates"])
    p:Checkbox(T["Overwrite Health Color With Combat State"], C.nameplates, "barcombatstate", U["nameplates"])
    p:Checkbox(T["Overwrite If Unit Is Attacking You"], C.nameplates, "ccombatthreat", U["nameplates"])
    p:Checkbox(T["Overwrite If Unit Is Attacking Off-Tank"], C.nameplates, "ccombatofftank", U["nameplates"])
    p:Checkbox(T["Overwrite If Unit Is Attacking Others"], C.nameplates, "ccombatnothreat", U["nameplates"])
    p:Checkbox(T["Overwrite If Unit Is Attacking No One"], C.nameplates, "ccombatstun", U["nameplates"])
    p:Checkbox(T["Overwrite If Unit Is Casting"], C.nameplates, "ccombatcasting", U["nameplates"])
    p:Color(T["Unit Is Attacking You Color"], C.nameplates, "combatthreat", U["nameplates"])
    p:Color(T["Unit Is Attacking Off-Tank Color"], C.nameplates, "combatofftank", U["nameplates"])
    p:Color(T["Unit Is Attacking Others Color"], C.nameplates, "combatnothreat", U["nameplates"])
    p:Color(T["Unit Is Attacking No One Color"], C.nameplates, "combatstun", U["nameplates"])
    p:Color(T["Unit Is Casting Color"], C.nameplates, "combatcasting", U["nameplates"])
    p:List(T["Off-Tank Names"], C.nameplates, "combatofftanks", U["nameplates"])
  end)

  gui:AddPage("thirdparty.integrations", T["Thirdparty"], T["Integrations"], function(p)
    p:Checkbox(T["Show Meters By Default"], C.thirdparty, "showmeter")
    p:Checkbox(T["Use Chat Colors for Meters"], C.thirdparty, "chatbg")
    p:Checkbox("ShaguDPS (" .. T["Skin"] .. ")", C.thirdparty.shagudps, "skin")
    p:Checkbox("ShaguDPS (" .. T["Dock"] .. ")", C.thirdparty.shagudps, "dock")
    p:Checkbox("GreedMeter (" .. T["Dock"] .. ")", C.thirdparty.greedmeter, "dock")
    p:Checkbox("CombatLedger (" .. T["Dock"] .. ")", C.thirdparty.combatledger, "dock")
    p:Checkbox("DPSMate (" .. T["Skin"] .. ")", C.thirdparty.dpsmate, "skin")
    p:Checkbox("DPSMate (" .. T["Dock"] .. ")", C.thirdparty.dpsmate, "dock")
    p:Checkbox("SWStats (" .. T["Skin"] .. ")", C.thirdparty.swstats, "skin")
    p:Checkbox("SWStats (" .. T["Dock"] .. ")", C.thirdparty.swstats, "dock")
    p:Checkbox("KLH Threat Meter (" .. T["Skin"] .. ")", C.thirdparty.ktm, "skin")
    p:Checkbox("KLH Threat Meter (" .. T["Dock"] .. ")", C.thirdparty.ktm, "dock")
    p:Checkbox("TW Threatmeter (" .. T["Skin"] .. ")", C.thirdparty.twt, "skin")
    p:Checkbox("TW Threatmeter (" .. T["Dock"] .. ")", C.thirdparty.twt, "dock")
    p:Checkbox("WIM", C.thirdparty.wim, "enable")
    p:Checkbox("HealComm", C.thirdparty.healcomm, "enable")
    p:Checkbox("SortBags", C.thirdparty.sortbags, "enable")
    p:Checkbox("MrPlow", C.thirdparty.mrplow, "enable")
    p:Checkbox("BetterCharacterStats", C.thirdparty.bcs, "enable")
    p:Checkbox("Crafty", C.thirdparty.crafty, "enable")
    p:Checkbox("CleverMacro", C.thirdparty.clevermacro, "enable")
    p:Checkbox("SuperCleveRoidMacros", C.thirdparty.supercleveroidmacros, "enable")
    p:Checkbox("FlightMap", C.thirdparty.flightmap, "enable")
    p:Checkbox("TheoryCraft", C.thirdparty.theorycraft, "enable")
    p:Checkbox("SuperMacro", C.thirdparty.supermacro, "enable")
    p:Checkbox("AtlasLoot", C.thirdparty.atlasloot, "enable")
    p:Checkbox("MyRolePlay", C.thirdparty.myroleplay, "enable")
    p:Checkbox("DruidManaBar", C.thirdparty.druidmana, "enable")
    p:Checkbox("NoteIt", C.thirdparty.noteit, "enable")
  end)

  gui:AddPage("components.modules", T["Components"], T["Modules"], function(p)
    table.sort(pfUI.modules)
    for i,m in pairs(pfUI.modules) do
      if m ~= "gui" then
        -- create disabled entry if not existing and display
        pfUI:UpdateConfig("disabled", nil, m, "0")
        p:Checkbox(T["Disable Module"] .. " " .. m, C.disabled, m)
      end
    end
  end)

  gui:AddPage("components.skins", T["Components"], T["Skins"], function(p)
    table.sort(pfUI.skins)
    for i,m in pairs(pfUI.skins) do
      -- create disabled entry if not existing and display
      pfUI:UpdateConfig("disabled", nil, "skin_" .. m, "0")
      p:Checkbox(T["Disable Skin"] .. " " .. m, C.disabled, "skin_" .. m)
    end
  end)
end
