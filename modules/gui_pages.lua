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
  -- the ranges of the number settings that show as sliders
  local FONTSIZE = { min = 6, max = 32 }
  local ICONSIZE = { min = 4, max = 64 }
  local OFFSET   = { min = -100, max = 100 }
  local SPACING  = { min = 0, max = 20 }
  local COUNT    = { min = 1, max = 40 }

  -- one opts table from several
  local function Opts(...)
    local opts = {}
    for _, part in ipairs(arg) do
      for field, value in pairs(part) do opts[field] = value end
    end
    return opts
  end
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
    ["luaerrors"] = {
      "default:" .. T["Error Window Or BugSack"],
      "chat:" .. T["Print To Chat"],
      "hide:" .. T["Hide Errors"],
    },
    ["uierrors"] = {
      "full:" .. T["All Lines"],
      "single:" .. T["Single Line"],
      "hide:" .. T["Hidden"],
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
    ["flyout"] = {
      "TOP:" .. T["Up"],
      "BOTTOM:" .. T["Down"],
      "LEFT:" .. T["Left"],
      "RIGHT:" .. T["Right"],
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
    ["uf_hoverhighlight"] = {
      "0:" .. T["Disabled"],
      "tint:" .. T["Tint"],
      "border:" .. T["Border"],
      "glow:" .. T["Glow"]
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
  -- file the client can't load, so only offer it where it exists. Loading the
  -- font takes tens of ms, so the test waits for the window's first opening,
  -- before any page builds its font dropdowns.
  local fontchecked
  gui:HookScript("OnShow", function()
    if fontchecked then return end
    fontchecked = true
    if gui:CreateFontString():SetFont("Fonts\\FZLBJW.TTF", 12) then
      table.insert(D.fonts, "Fonts\\FZLBJW.TTF:Noto Sans SC")
    end
  end)

  D.loot_rarity = {}
  for i=0, getn(_G.ITEM_QUALITY_COLORS)-2  do
    local entry = string.format("%d:%s", i, string.format("%s%s%s", _G.ITEM_QUALITY_COLORS[i].hex, _G[string.format("ITEM_QUALITY%d_DESC",i)], FONT_COLOR_CODE_CLOSE))
    table.insert(D.loot_rarity, entry)
  end

  for _, theme in ipairs(pfUI.uf.colorthemes) do
    table.insert(D.uf_color, theme.id .. ":" .. T[theme.name])
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
    -- the page's contents keep their size and stay centred in a wider window
    local about = CreateFrame("Frame", nil, this)
    about:SetSize(546, 360)
    about:SetPoint("TOP")

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
    draw(about, x,     -y-2*p, x+p,      -y-7*p, .2, 1, .8, 1)
    draw(about, x+p,   -y-2*p, x+2*p,    -y-3*p, .2, 1, .8, 1)
    draw(about, x+p,   -y-4*p, x+2*p,    -y-5*p, .2, 1, .8, 1)
    draw(about, x+2*p, -y,     x+3*p,    -y-5*p, .2, 1, .8, 1)
    draw(about, x+3*p, -y,     x+4*p,    -y-1*p, .2, 1, .8, 1)
    draw(about, x+p,   -y-2*p, x+4*p,    -y-3*p, .2, 1, .8, 1)
    draw(about, x+4*p, -y,     x+5*p,    -y-5*p, 1,  1, 1,  1)
    draw(about, x+5*p, -y-4*p, x+5*p+p,  -y-5*p, 1,  1, 1,  1)
    draw(about, x+6*p, -y,     x+7*p,    -y-p,   1,  1, 1,  1)
    draw(about, x+6*p, -y-2*p, x+7*p,    -y-5*p, 1,  1, 1,  1)

    -- version
    about.versionc = about:CreateFontString("Status", "LOW", "GameFontWhite")
    about.versionc:SetFont(pfUI.font_default, C.global.font_size)
    about.versionc:SetPoint("TOPLEFT", 185, -170)
    about.versionc:SetWidth(200)
    about.versionc:SetJustifyH("LEFT")
    about.versionc:SetText(GAME_VERSION_LABEL .. ":")

    about.version = about:CreateFontString("Status", "LOW", "GameFontWhite")
    about.version:SetFont(pfUI.font_default, C.global.font_size)
    about.version:SetPoint("TOPRIGHT", about, "TOPLEFT", 360, -170)
    about.version:SetWidth(200)
    about.version:SetJustifyH("RIGHT")

    about.update = about:CreateFontString("Status", "LOW", "GameFontWhite")
    about.update:SetFont(pfUI.font_default, C.global.font_size)
    about.update:SetPoint("TOPLEFT", 185, -140)
    about.update:SetPoint("TOPRIGHT", about, "TOPLEFT", 360, -140)
    about.update:SetJustifyH("CENTER")
    about.update:SetTextColor(.2,1,.8)

    about.screenc = about:CreateFontString("Status", "LOW", "GameFontWhite")
    about.screenc:SetFont(pfUI.font_default, C.global.font_size)
    about.screenc:SetPoint("TOPLEFT", 185, -200)
    about.screenc:SetWidth(200)
    about.screenc:SetJustifyH("LEFT")
    about.screenc:SetText(RESOLUTION .. ":")

    about.screen = about:CreateFontString("Status", "LOW", "GameFontWhite")
    about.screen:SetFont(pfUI.font_default, C.global.font_size)
    about.screen:SetPoint("TOPRIGHT", about, "TOPLEFT", 360, -200)
    about.screen:SetWidth(200)
    about.screen:SetJustifyH("RIGHT")

    about.scalec = about:CreateFontString("Status", "LOW", "GameFontWhite")
    about.scalec:SetFont(pfUI.font_default, C.global.font_size)
    about.scalec:SetPoint("TOPLEFT", 185, -220)
    about.scalec:SetWidth(200)
    about.scalec:SetJustifyH("LEFT")
    about.scalec:SetText(T["Scaling"] .. ":")

    about.scale = about:CreateFontString("Status", "LOW", "GameFontWhite")
    about.scale:SetFont(pfUI.font_default, C.global.font_size)
    about.scale:SetPoint("TOPRIGHT", about, "TOPLEFT", 360, -220)
    about.scale:SetWidth(200)
    about.scale:SetJustifyH("RIGHT")

    about.clientc = about:CreateFontString("Status", "LOW", "GameFontWhite")
    about.clientc:SetFont(pfUI.font_default, C.global.font_size)
    about.clientc:SetPoint("TOPLEFT", 185, -250)
    about.clientc:SetWidth(200)
    about.clientc:SetJustifyH("LEFT")
    about.clientc:SetText(T["Gameclient"] .. ":")

    about.client = about:CreateFontString("Status", "LOW", "GameFontWhite")
    about.client:SetFont(pfUI.font_default, C.global.font_size)
    about.client:SetPoint("TOPRIGHT", about, "TOPLEFT", 360, -250)
    about.client:SetWidth(200)
    about.client:SetJustifyH("RIGHT")

    about.langc = about:CreateFontString("Status", "LOW", "GameFontWhite")
    about.langc:SetFont(pfUI.font_default, C.global.font_size)
    about.langc:SetPoint("TOPLEFT", 185, -270)
    about.langc:SetWidth(200)
    about.langc:SetJustifyH("LEFT")
    about.langc:SetText(LANGUAGE .. ":")
    about.lang = about:CreateFontString("Status", "LOW", "GameFontWhite")
    about.lang:SetFont(pfUI.font_default, C.global.font_size)
    about.lang:SetPoint("TOPRIGHT", about, "TOPLEFT", 360, -270)
    about.lang:SetWidth(200)
    about.lang:SetJustifyH("RIGHT")

    -- the values, read again each time the page shows
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

    local f = CreateFrame("Frame", nil, about)
    f:SetScript("OnShow", Refresh)
    Refresh()

    local donate = CreateFrame("Button", nil, about)
    donate:SetPoint("TOPLEFT", 115, -335)
    donate:SetWidth(100)
    donate:SetHeight(20)
    donate:SetText(T["Donate"])
    donate:SetScript("OnClick", function()
      CopyText("https://buymeacoffee.com/brues")
    end)
    SkinButton(donate)

    local github = CreateFrame("Button", nil, about)
    github:SetPoint("TOPLEFT", 225, -335)
    github:SetWidth(100)
    github:SetHeight(20)
    github:SetText(T["GitHub"])
    github:SetScript("OnClick", function()
      CopyText(GetAddOnMetadata(pfUI.name, "X-Website"))
    end)
    SkinButton(github)

    local website = CreateFrame("Button", nil, about)
    website:SetPoint("TOPLEFT", 335, -335)
    website:SetWidth(100)
    website:SetHeight(20)
    website:SetText(T["Website"])
    website:SetScript("OnClick", function()
      CopyText(GetAddOnMetadata(pfUI.name, "X-Website"))
    end)
    SkinButton(website)
  end)

  gui:AddPage("general.interface", T["General"], T["Interface"], function(p)
    p:Header(T["General"])
    p:Dropdown(LANGUAGE, C.global, "language", D.languages)
    p:Checkbox(T["Enable Offscreen Frame Positions"], C.global, "offscreen")
    p:Checkbox(T["Highlight Settings That Require Reload"], C.gui, "reloadmarker")

    p:Header(T["Scale"])
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

    p:Header(T["Numbers & Names"])
    p:Dropdown(T["Abbreviate Numbers"], C.unitframes, "abbrevnum", D.abbrevnum)
    p:Checkbox(T["Abbreviate Unit Names"], C.unitframes, "abbrevname")

    p:Header(T["Errors & Notifications"])
    p:Dropdown(T["Lua Errors"], C.global, "luaerrors", D.luaerrors, pfUI.UpdateLuaErrors)
    p:Dropdown(T["Error Messages"], C.global, "uierrors", D.uierrors, pfUI.UpdateErrorMessages)
    p:Checkbox(T["Enable OS Notifications"], C.global, "notify", nop)
  end)

  gui:AddPage("general.fonts", T["General"], T["Fonts"], function(p)
    -- add invisible font to disable combat messages
    local combatfonts = CopyTable(D.fonts)
    table.insert(combatfonts, "Interface\\AddOns\\pfUI\\fonts\\AdobeBlank.ttf:Invisible")

    p:Header(T["General"])
    p:Checkbox(T["Use Original Game Fonts"], C.global, "font_blizzard")
    p:Checkbox(T["Enable Region Compatible Font"], C.global, "force_region")
    p:Dropdown(T["Standard Text Font"], C.global, "font_default", D.fonts, nil, { preview = "font" })
    p:Number(T["Standard Text Font Size"], C.global, "font_size", nil, FONTSIZE)

    p:Header(T["Unit Frames"])
    p:Dropdown(T["Unit Frame Text Font"], C.global, "font_unit", D.fonts, nil, { preview = "font" })
    p:Number(T["Unit Frame Text Size"], C.global, "font_unit_size", nil, FONTSIZE)
    p:Dropdown(T["Unit Frame Text Style"], C.global, "font_unit_style", D.fontstyle)

    p:Header(T["World"])
    p:Dropdown(T["3D World Unit Font"], C.global, "font_unit_name", D.fonts, nil, { preview = "font" })
    p:Dropdown(T["Scrolling Combat Text Font"], C.global, "font_combat", combatfonts)
  end)

  gui:AddPage("general.appearance", T["General"], T["Appearance"], function(p)
    p:Header(T["Colors"])
    p:Color(T["Background Color"], C.appearance.border, "background")
    p:Color(T["Border Color"], C.appearance.border, "color")

    p:Header(T["Shadow"])
    p:Checkbox(T["Enable Frame Shadow"], C.appearance.border, "shadow")
    p:Dropdown(T["Frame Shadow Intensity"], C.appearance.border, "shadow_intensity", D.uf_debuff_indicator_size)

    p:Header(T["Borders"])
    p:Checkbox(T["Force Blizzard Borders (|cffffaaaaExperimental|r)"], C.appearance.border, "force_blizz")
    p:Dropdown(T["Global Border Size"], C.appearance.border, "default", D.border)
    p:Dropdown(T["Action Bar Border Size"], C.appearance.border, "actionbars", D.border)
    p:Dropdown(T["Unit Frame Border Size"], C.appearance.border, "unitframes", D.border)
    p:Dropdown(T["Panel Border Size"], C.appearance.border, "panels", D.border)
    p:Dropdown(T["Chat Border Size"], C.appearance.border, "chat", D.border)
    p:Dropdown(T["Bags Border Size"], C.appearance.border, "bags", D.border)
    p:Dropdown(T["Nameplate Border Size"], C.appearance.border, "nameplates", D.border, U["nameplates"])

    p:Header(T["Screen Glow"])
    p:Checkbox(T["Enable Combat Glow Effects On Screen Edges"], C.appearance.infight, "screen", U["infight"])
    p:Checkbox(T["Enable Aggro Glow Effects On Screen Edges"], C.appearance.infight, "aggro", U["infight"])
    p:Checkbox(T["Enable Low Health Glow Effects On Screen Edges"], C.appearance.infight, "health", U["infight"])
    p:Dropdown(T["Screen Edge Glow Intensity"], C.appearance.infight, "intensity", D.glowintensity, U["infight"])
  end)

  gui:AddPage("general.cooldown", T["General"], T["Cooldown"], function(p)
    p:Header(T["Text"])
    p:Checkbox(COUNTDOWN_FOR_COOLDOWNS_TEXT, CVars, "countdownForCooldowns", nop)
    p:Dropdown(T["Font"], C.cooldown, "font", D.fonts, UpdateCooldowns, { preview = "font" })
    p:Number(FONT_SIZE, C.cooldown, "font_size", nil, FONTSIZE)
    p:Checkbox(T["Scale Font Size With Icon"], C.cooldown, "dynamicsize")
    p:Number(T["Hide Numbers On Spell Cooldowns Up To (Seconds)"], C.cooldown, "threshold", UpdateCooldowns)
    p:Checkbox(T["Show Tenths Below 5 Seconds"], C.cooldown, "milliseconds", UpdateCooldowns)

    p:Header(T["Colors"])
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

  gui:AddPage("general.profiles", T["General"], T["Profiles"], function(p)
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

  gui:AddPage("general.screenshot", T["General"], T["Screenshot"], function(p)
    p:Header(T["Take A Screenshot On"])
    p:Number(T["Timer In Minutes"], C.screenshot, "interval")
    p:Checkbox(PLAYER_LEVEL_UP, C.screenshot, "levelup")
    p:Checkbox(T["PvP Rank"], C.screenshot, "pvprank")
    p:Checkbox(T["Reputation Level"], C.screenshot, "faction")
    p:Checkbox(T["Honorable Kill"], C.screenshot, "hk")
    p:Dropdown(T["Battleground Statistics"], C.screenshot, "battleground", D.screenshot_battle)
    p:Dropdown(T["Item Looted"], C.screenshot, "loot", D.screenshot_loot)
    p:Header(T["Options"])
    p:Checkbox(T["Show Description"], C.screenshot, "caption")
    p:Dropdown(T["Description Font"], C.screenshot, "caption_font", D.fonts, nil, { preview = "font" })
    p:Number(T["Description Font Size"], C.screenshot, "caption_size", nil, FONTSIZE)
    p:Checkbox(T["Hide All UI Elements"], C.screenshot, "hideui")
  end, { module = "screenshot" })

  gui:AddPage("general.gmmode", T["General"], T["GM-Mode"], function(p)
    p:Checkbox(T["Disable GM-Mode"], C.gm, "disable")
    p:Dropdown(T["Selected Core"], C.gm, "server", D.gmserver_text)
  end, { module = "gm" })

  gui:AddPage("unitframes.general", T["Unit Frames"], T["General"], function(p)
    p:Header(T["Frames"])
    p:Checkbox(T["Disable pfUI Unit Frames"], C.unitframes, "disable")
    p:Dropdown(T["Unit Frame Layout"], C.unitframes, "layout", D.uf_layout)
    p:Checkbox(T["Animate Health And Power Bars"], C.unitframes, "animatebars")
    p:Dropdown(T["Raid Mark Icon Style"], C.unitframes, "blizzard_raidicons", function() return {"1:" .. T["Original Blizzard"], "0:" .. T["pfUI Design"]} end)

    p:Header(T["Portraits"])
    p:Dropdown(T["Portrait Style"], C.unitframes, "portraitstyle", D.uf_portrait_style)
    p:Number(T["Portrait Alpha"], C.unitframes, "portraitalpha")
    p:Checkbox(T["Enable 2D Portraits As Fallback"], C.unitframes, "portraittexture")

    p:Header(T["Range"])
    p:Checkbox(T["Enable 40y-Range Check"], C.unitframes, "rangecheck")
    p:Dropdown(T["Range Check Mode"], C.unitframes, "rangecheck_mode", D.uf_rangecheck_mode)
    p:Number(T["UnitXP Range Threshold (yards)"], C.unitframes, "rangecheck_distance")

    p:Header(T["Health Point Estimation"])
    p:Checkbox(T["Estimate Enemy Health Points"], C.global, "libhealth")
    p:Dropdown(T["Threshold To Trust Health Estimation"], C.global, "libhealth_hit", D.uf_rangecheckinterval)
    p:Dropdown(T["Required Damage In Percent"], C.global, "libhealth_dmg", D.percent_small)

    p:Header(T["Health Colors"])
    p:Checkbox(T["Enable Pastel Colors"], C.unitframes, "pastel")
    p:Dropdown(T["Health Bar Color"], C.unitframes, "custom", D.uf_color)
    p:Color(T["Custom Health Bar Color"], C.unitframes, "customcolor")
    p:Checkbox(T["Fade To Custom Color"], C.unitframes, "customfade")
    p:Checkbox(T["Use Custom Color On Full Health"], C.unitframes, "customfullhp")
    p:Checkbox(T["Use Custom Color Health Bar Background"], C.unitframes, "custombg")
    p:Color(T["Custom Health Bar Background Color"], C.unitframes, "custombgcolor")

    p:Header(T["Power Colors"])
    p:Color(T["Mana Color"], C.unitframes, "manacolor")
    p:Color(T["Rage Color"], C.unitframes, "ragecolor")
    p:Color(T["Energy Color"], C.unitframes, "energycolor")
    p:Color(T["Focus Color"], C.unitframes, "focuscolor")
    p:Checkbox(T["Use Custom Color Power Bar Background"], C.unitframes, "custompbg")
    p:Color(T["Custom Power Bar Background Color"], C.unitframes, "custompbgcolor")
  end)

  gui:AddPage("unitframes.groups", T["Unit Frames"], T["Group & Raid"], function(p)
    p:Checkbox(T["Show Self In Group Frames"], C.unitframes, "selfingroup")
    p:Checkbox(T["Show Self In Raid Frames When Solo"], C.unitframes, "selfinraid")
    p:Checkbox(T["Use Raid Frames To Display Group Members"], C.unitframes, "raidforgroup")
    p:Checkbox(T["Hide Group Frames While In Raid"], C.unitframes.group, "hide_in_raid")
    p:Dropdown(T["Max Amount Of Raid Frames"], C.unitframes, "maxraid", D.maxraid)
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
    [9] = { "boss",        BOSS },
    [10] = { "group",      GROUP },
    [11] = { "grouptarget", T["Group-Target"]},
    [12] = { "grouppet",   T["Group-Pet"] },
    [13] = { "raid",       RAID },
    [14] = { "raidpet",    T["Raid-Pet"] },
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

  -- The unit frames page draws the picked frame above its settings: real
  -- pfUI unit frames that show the player with that frame's config, fitted
  -- into the preview box. A raid or raid pet frame shows a full grid of
  -- them, a party frame its target and pet frames beside it. Each frame has
  -- its own set, made the first time it is picked, so no frame's layout
  -- carries over into another's, as none does between the real frames.
  --
  -- A row of buttons in the box picks the state the frames show: the player
  -- as they are, or a sample (api/unitframes.lua) of a state they are not in.
  local unitPreview = {}
  local previewSets, previewSet, previewBox, stateBar = {}, nil, nil, nil

  local function SampleAura(spellId, count, dispelType, duration, timeleft, mine)
    return { name = C_Spell.GetSpellName(spellId), icon = C_Spell.GetSpellTexture(spellId),
      count = count, dispelType = dispelType, duration = duration,
      expirationTime = GetTime() + timeleft, mine = mine }
  end

  -- the health of the combat sample's frames, so a grid isn't all alike
  local COMBAT_HEALTH = { .45, .8, .25, 1, .6, .9, .35, .7 }

  -- A state's sample(i) is what frame `i` of a set shows, nil for the
  -- player as they are. Live keeps only the first frame live: the others
  -- would repeat the player's marks and auras, so they stand in with the
  -- player's health and power alone.
  local unitStates = {
    { label = T["Live"], sample = function(i)
      if i == 1 then return nil end
      return { health = UnitHealth("player") / UnitHealthMax("player"),
        power = UnitPowerMax("player") > 0 and UnitPower("player") / UnitPowerMax("player") or 0,
        buffs = {}, debuffs = {} }
    end },
    { label = T["Combat"], sample = function(i)
      return { health = COMBAT_HEALTH[math.mod(i - 1, 8) + 1], power = .6, combat = true,
        leader = i == 1, raidicon = i == 1 and 8 or i == 2 and 7 or nil,
        buffs = {
          SampleAura(139, 0, "Magic", 15, 11, true),     -- Renew
          SampleAura(1243, 0, "Magic", 1800, 1500),      -- Power Word: Fortitude
          SampleAura(1459, 0, "Magic", 1800, 900),       -- Arcane Intellect
          SampleAura(1126, 0, "Magic", 1800, 1200),      -- Mark of the Wild
        },
        debuffs = {
          SampleAura(589, 0, "Magic", 18, 9),            -- Shadow Word: Pain
          SampleAura(980, 0, "Curse", 24, 20),           -- Curse of Agony
          SampleAura(2818, 3, "Poison", 12, 7),          -- Deadly Poison
          SampleAura(772, 0, nil, 9, 3),                 -- Rend
        } }
    end },
    { label = DEAD, sample = function()
      return { health = 0, power = 0, dead = true, buffs = {}, debuffs = {} }
    end },
    { label = PLAYER_OFFLINE, sample = function()
      return { health = 1, power = 1, offline = true, buffs = {}, debuffs = {} }
    end },
  }
  local unitState = unitStates[1]

  local function UpdateStateBar()
    for _, button in ipairs(stateBar.buttons) do
      if button.state == unitState then
        button:SetTextColor(.2, 1, .8, 1)
      else
        button:SetTextColor(.6, .6, .6, 1)
      end
    end
  end

  local function CreateStateBar(box)
    stateBar = CreateFrame("Frame", nil, box)
    -- over the config window's part picker
    stateBar:SetFrameLevel(box:GetFrameLevel() + 50)
    stateBar:SetPoint("TOPLEFT", 6, -6)
    stateBar:SetSize(1, 18)
    stateBar.buttons = {}

    local last
    for i, state in ipairs(unitStates) do
      local button = CreateFrame("Button", nil, stateBar)
      button:SetSize(64, 18)
      if last then
        button:SetPoint("LEFT", last, "RIGHT", 4, 0)
      else
        button:SetPoint("LEFT", stateBar, "LEFT", 0, 0)
      end
      button:SetText(state.label)
      SkinButton(button)
      button.state = state
      button:SetScript("OnClick", function()
        unitState = this.state
        UpdateStateBar()
        unitPreview.Refresh()
      end)
      stateBar.buttons[i] = button
      last = button
    end
  end

  function unitPreview.GetHeight(variant)
    return C.unitframes[variant].raidlayout and 200 or 130
  end

  -- the set's frame `i`, made on first use
  local function GetPreviewFrame(set, i, config)
    if not set.frames[i] then
      set.frames[i] = pfUI.uf:CreateUnitFrame("Player", nil, config, nil, set.holder)
    end
    return set.frames[i]
  end

  local function DrawPreviewFrame(f, i)
    f.previewHidden = nil
    f.sample = unitState.sample(i)
    f:UpdateConfig()
    f:UpdateFrameSize()
    f:EnableEvents()
    pfUI.uf:RefreshUnit(f, "all")
  end

  local function HidePreviewFrame(f)
    f.previewHidden = true
    f:UpdateVisibility()
  end

  -- Each layout draws the set's frames, places them in its holder and
  -- returns the size they take.

  -- the grid, as full as the raid size allows
  local function LayoutRaid(set, config)
    local count = math.min(tonumber(C.unitframes.maxraid), 40)
    local first = GetPreviewFrame(set, 1, config)
    DrawPreviewFrame(first, 1)
    local grid = pfUI.uf:GetRaidGrid(config, first, count)
    count = math.min(count, grid.x * grid.y)

    local cols, rows = 0, 0
    for i = 1, count do
      local f = GetPreviewFrame(set, i, config)
      if i > 1 then DrawPreviewFrame(f, i) end
      local col, row = pfUI.uf:GetRaidGridCell(grid, i)
      cols, rows = math.max(cols, col), math.max(rows, row)
    end
    for i = count + 1, table.getn(set.frames) do
      HidePreviewFrame(set.frames[i])
    end

    -- placed once the holder has its scale, which the pixel snap reads
    set.place = function()
      for i = 1, count do
        pfUI.uf:PlaceInRaidGrid(set.frames[i], grid, i, set.holder)
      end
    end
    return cols * (grid.w + grid.pad) - grid.pad, rows * (grid.h + grid.pad) - grid.pad
  end

  -- the party frame, with the target and pet frames the group shows
  local function LayoutGroup(set, config)
    local frame = GetPreviewFrame(set, 1, config)
    DrawPreviewFrame(frame, 1)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", set.holder, "TOPLEFT", 0, 0)

    local target, pet
    if C.unitframes.grouptarget.visible == "1" then
      target = GetPreviewFrame(set, 2, C.unitframes.grouptarget)
      DrawPreviewFrame(target, 2)
      target:ClearAllPoints()
    elseif set.frames[2] then
      HidePreviewFrame(set.frames[2])
    end
    if C.unitframes.grouppet.visible == "1" then
      pet = GetPreviewFrame(set, 3, C.unitframes.grouppet)
      DrawPreviewFrame(pet, 3)
      pet:ClearAllPoints()
    elseif set.frames[3] then
      HidePreviewFrame(set.frames[3])
    end
    pfUI.uf:AttachGroupUnits(frame, target, pet)

    -- the target hangs from the top, the pet from the bottom
    local _, border = GetBorderSize("unitframes")
    local width, height = frame:GetWidth(), frame:GetHeight()
    local side = 0
    if target then
      side = target:GetWidth()
      height = math.max(height, target:GetHeight())
    end
    if pet then
      side = math.max(side, pet:GetWidth())
      height = math.max(height, pet:GetHeight() + border)
    end
    if side > 0 then width = width + 3*border + side end
    return width, height
  end

  local function LayoutSingle(set, config)
    local frame = GetPreviewFrame(set, 1, config)
    DrawPreviewFrame(frame, 1)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", set.holder, "TOPLEFT", 0, 0)
    return frame:GetWidth(), frame:GetHeight()
  end

  -- the parts of a frame that lead to their settings, topmost first
  local function AddParts(parts, f)
    for _, icons in ipairs({ { f.buffs, T["Buffs"] }, { f.debuffs, T["Debuffs"] } }) do
      if icons[1] then
        for _, icon in ipairs(icons[1]) do
          table.insert(parts, { icon, { section = icons[2] } })
        end
      end
    end
    if f.castbar then table.insert(parts, { f.castbar, { section = T["Castbar"] } }) end
    table.insert(parts, { f.portrait, { keys = { "portrait", "portraitwidth", "portraitheight" } } })
    table.insert(parts, { f.power, { section = T["Powerbar"] } })
    table.insert(parts, { f.hp, { section = T["Healthbar"] } })
  end

  function unitPreview.Refresh()
    local set = previewSet
    local config = C.unitframes[set.variant]
    set.place = nil
    local width, height
    if config.raidlayout then
      width, height = LayoutRaid(set, config)
    elseif set.variant == "group" then
      width, height = LayoutGroup(set, config)
    else
      width, height = LayoutSingle(set, config)
    end

    -- the frames at their own size, or smaller when they would not fit under
    -- the state buttons
    local holder = set.holder
    holder:SetSize(width, height)
    holder:SetScale(1)
    local room = math.min((previewBox:GetWidth() - 40) / width, (previewBox:GetHeight() - 50) / height)
    if room > 0 then holder:SetScale(math.min(1, room)) end
    if set.place then set.place() end

    -- a party set's target and pet frames have settings of their own
    unitPreview.parts = {}
    for i, f in ipairs(set.frames) do
      if not f.previewHidden and (set.variant ~= "group" or i == 1) then
        AddParts(unitPreview.parts, f)
      end
    end
  end

  function unitPreview.Hide()
    if not previewSet then return end
    previewSet.holder:Hide()
    stateBar:Hide()
  end

  function unitPreview.Show(box, variant)
    previewBox = box
    if not stateBar then CreateStateBar(box) end
    unitPreview.Hide()

    if not previewSets[variant] then
      local holder = CreateFrame("Frame", nil, box)
      holder:SetPoint("CENTER", box, "CENTER", 0, -12)
      previewSets[variant] = { variant = variant, holder = holder, frames = {} }
    end
    previewSet = previewSets[variant]
    previewSet.holder:Show()
    stateBar:Show()
    UpdateStateBar()
    unitPreview.Refresh()
  end

  gui:AddVariantPage("unitframes.frames", T["Unit Frames"], T["Frames"], unitframeSettings, function(c)
    return C.unitframes[c]
  end, function(p, c, t)
      -- link Update tables
      U.ttarget     = U["targettarget"]
      U.tttarget    = U["targettargettarget"]
      U.ptarget     = U["pettarget"]
      U.grouptarget = U["group"]
      U.grouppet    = U["group"]
      U.raidpet     = U["raid"]

      local f = C.unitframes[c]

      p:Header(T["Frame"])
      p:Checkbox(T["Display Frame"] .. ": " .. t, f, "visible", U[c])
      p:Number(T["Health Bar Width"], f, "width", U[c])
      p:Number(T["Health Bar Height"], f, "height", U[c])
      p:Number(T["UnitFrame Spacing"], f, "pspace", U[c])

      if c == "raid" or c == "raidpet" then
        p:Header(T["Layout"])
        p:Dropdown(T["Raid Layout"], f, "raidlayout", D.uf_raidlayout, U["raid"])
        p:Dropdown(T["Raid Fill Direction"], f, "raidfill", D.orientation, U["raid"])
        if c == "raid" then
          p:Checkbox(T["Grow Right To Left"], f, "raidgrowleft", U["raid"])
        end
        p:Number(T["Raid Padding"], f, "raidpadding", U["raid"], SPACING)
        p:Checkbox(T["Collapse Empty Slots"], f, "collapse", U["raid"])
        if c == "raid" then
          p:Checkbox(T["Display Raid Group Label"], f, "raidgrouplabel", U["raid"])
          p:Number(T["Group Label X-Offset"], f, "grouplabelxoff", U["raid"], Opts(OFFSET, { requires = "raidgrouplabel" }))
          p:Number(T["Group Label Y-Offset"], f, "grouplabelyoff", U["raid"], Opts(OFFSET, { requires = "raidgrouplabel" }))
        end
      end

      p:Header(T["Visibility"])
      p:Dropdown(T["Default Transparency"], f, "alpha_visible", D.percent_small, U[c])
      p:Checkbox(T["Enable Range Fading"], f, "faderange", U[c])
      p:Dropdown(T["Out Of Range Transparency"], f, "alpha_outrange", D.percent_small, U[c])
      p:Dropdown(T["Offline Transparency"], f, "alpha_offline", D.percent_small, U[c])
      p:Checkbox(T["Enable Aggro Glow"], f, "glowaggro", U[c])
      p:Checkbox(T["Enable Combat Glow"], f, "glowcombat", U[c])
      p:Dropdown(T["Mouseover Highlight"], f, "hoverhighlight", D.uf_hoverhighlight, U[c])
      p:Color(T["Mouseover Highlight Color"], f, "hovercolor", U[c])

      p:Header(T["Portrait"])
      p:Dropdown(T["Portrait Position"], f, "portrait", D.uf_portrait_position, U[c])
      p:Number(T["Portrait Width"], f, "portraitwidth", U[c])
      p:Number(T["Portrait Height"], f, "portraitheight", U[c])

      p:Header(T["Healthbar"])
      p:Dropdown(T["Health Bar Texture"], f, "bartexture", D.uf_bartexture, U[c], { preview = "texture" })
      p:Checkbox(T["Invert Health Bar"], f, "invert_healthbar", U[c])
      p:Checkbox(T["Enable Vertical Health Bar"], f, "verticalbar", U[c])
      p:Color(T["Heal Color"], f, "healcolor", U[c])
      p:Dropdown(T["Display Overheal"], f, "overhealperc", D.uf_overheal, U[c])

      p:Header(T["Powerbar"])
      p:Dropdown(T["Power Bar Texture"], f, "pbartexture", D.uf_bartexture, U[c], { preview = "texture" })
      p:Number(T["Power Bar Width"], f, "pwidth", U[c])
      p:Number(T["Power Bar Height"], f, "pheight", U[c])
      p:Dropdown(T["Power Bar Anchor"], f, "panchor", D.uf_powerbar_position, U[c])
      p:Number(T["Power Bar X-Offset"], f, "poffx", U[c], OFFSET)
      p:Number(T["Power Bar Y-Offset"], f, "poffy", U[c], OFFSET)

      p:Header(T["Health Text"])
      p:Dropdown(T["Left Text"], f, "txthpleft", D.uf_texts, U[c])
      p:Number(T["Left Text X Offset"], f, "txthpleftoffx", U[c], OFFSET)
      p:Number(T["Left Text Y Offset"], f, "txthpleftoffy", U[c], OFFSET)
      p:Dropdown(T["Center Text"], f, "txthpcenter", D.uf_texts, U[c])
      p:Number(T["Center Text X Offset"], f, "txthpcenteroffx", U[c], OFFSET)
      p:Number(T["Center Text Y Offset"], f, "txthpcenteroffy", U[c], OFFSET)
      p:Dropdown(T["Right Text"], f, "txthpright", D.uf_texts, U[c])
      p:Number(T["Right Text X Offset"], f, "txthprightoffx", U[c], OFFSET)
      p:Number(T["Right Text Y Offset"], f, "txthprightoffy", U[c], OFFSET)

      p:Header(T["Power Text"])
      p:Dropdown(T["Left Text"], f, "txtpowerleft", D.uf_texts, U[c])
      p:Number(T["Left Text X Offset"], f, "txtpowerleftoffx", U[c], OFFSET)
      p:Number(T["Left Text Y Offset"], f, "txtpowerleftoffy", U[c], OFFSET)
      p:Dropdown(T["Center Text"], f, "txtpowercenter", D.uf_texts, U[c])
      p:Number(T["Center Text X Offset"], f, "txtpowercenteroffx", U[c], OFFSET)
      p:Number(T["Center Text Y Offset"], f, "txtpowercenteroffy", U[c], OFFSET)
      p:Dropdown(T["Right Text"], f, "txtpowerright", D.uf_texts, U[c])
      p:Number(T["Right Text X Offset"], f, "txtpowerrightoffx", U[c], OFFSET)
      p:Number(T["Right Text Y Offset"], f, "txtpowerrightoffy", U[c], OFFSET)

      p:Header(T["Text Colors"])
      p:Checkbox(T["Automatic Health Text Color"], f, "healthcolor", U[c])
      p:Checkbox(T["Automatic Power Text Color"], f, "powercolor", U[c])
      p:Checkbox(T["Automatic Level Text Color"], f, "levelcolor", U[c])
      p:Checkbox(T["Automatic Class Text Color"], f, "classcolor", U[c])

      if c == "group" or c == "raid" or c == "boss" then
        p:Header(T["Castbar"])
        p:Checkbox(T["Enable Castbars"], f, "castbar", U[c])
        p:Number(T["Castbar Height"], f, "castbarheight", U[c], { requires = "castbar" })
        p:Checkbox(T["Show Spell Name"], f, "castbartext", U[c], { requires = "castbar" })
      end

      p:Header(T["Buffs"])
      p:Dropdown(T["Buff Position"], f, "buffs", D.uf_buff_position, U[c])
      p:Number(T["Buff Size"], f, "buffsize", U[c], ICONSIZE)
      p:Number(T["Own Buff Size"], f, "ownbuffsize", U[c], ICONSIZE)
      p:Number(T["Buff Limit"], f, "bufflimit", U[c], COUNT)
      p:Number(T["Buffs Per Row"], f, "buffperrow", U[c], COUNT)
      p:Number(T["Buff X-Offset"], f, "buffoffx", U[c], OFFSET)
      p:Number(T["Buff Y-Offset"], f, "buffoffy", U[c], OFFSET)
      p:Number(T["Buff X-Spacing"], f, "buffspacingx", U[c], SPACING)
      p:Number(T["Buff Y-Spacing"], f, "buffspacingy", U[c], SPACING)
      p:Dropdown(T["Buff And Debuff Timers"], f, "aura_timers", D.cooldown_timers, UpdateCooldowns)

      p:Header(T["Debuffs"])
      p:Dropdown(T["Debuff Position"], f, "debuffs", D.uf_buff_position, U[c])
      p:Number(T["Debuff Size"], f, "debuffsize", U[c], ICONSIZE)
      p:Number(T["Own Debuff Size"], f, "owndebuffsize", U[c], ICONSIZE)
      p:Number(T["Debuff Limit"], f, "debufflimit", U[c], COUNT)
      p:Number(T["Debuffs Per Row"], f, "debuffperrow", U[c], COUNT)
      p:Number(T["Debuff X-Offset"], f, "debuffoffx", U[c], OFFSET)
      p:Number(T["Debuff Y-Offset"], f, "debuffoffy", U[c], OFFSET)
      p:Number(T["Debuff X-Spacing"], f, "debuffspacingx", U[c], SPACING)
      p:Number(T["Debuff Y-Spacing"], f, "debuffspacingy", U[c], SPACING)

      p:Header(T["Buff/Debuff Indicators"])
      p:Checkbox(T["Enable Indicators"], f, "buff_indicator", U[c])
      p:Checkbox(T["Show Buff Indicators"], f, "show_buffs", U[c], { requires = "buff_indicator" })
      p:Checkbox(T["Show Hots Indicators"], f, "show_hots", U[c], { requires = "buff_indicator" })
      p:Checkbox(T["Show Hots of all Classes"], f, "all_hots", U[c], { requires = "buff_indicator" })
      p:Checkbox(T["Show Procs Indicators"], f, "show_procs", U[c], { requires = "buff_indicator" })
      p:Checkbox(T["Show Procs of all Classes"], f, "all_procs", U[c], { requires = "buff_indicator" })
      p:Checkbox(T["Show Totems Indicators"], f, "show_totems", U[c], { requires = "buff_indicator" })
      p:List(T["Show Custom Indicators"], f, "custom_indicator", U[c], { requires = "buff_indicator" })
      p:Dropdown(T["Indicator Position"], f, "indicator_pos", D.positions, U[c], { requires = "buff_indicator" })
      p:Number(T["Indicator Size"], f, "indicator_size", U[c], Opts(ICONSIZE, { requires = "buff_indicator" }))
      p:Dropdown(T["Indicator Spacing"], f, "indicator_spacing", D.spacing, U[c], { requires = "buff_indicator" })
      p:Checkbox(T["Show Stacks"], f, "indicator_stacks", U[c], { requires = "buff_indicator" })
      p:Dropdown(T["Indicator Timers"], f, "indicator_timers", D.cooldown_timers, UpdateCooldowns, { requires = "buff_indicator" })

      p:Header(T["Dispel Indicators"])
      p:Dropdown(T["Show Dispel Indicators"], f, "debuff_indicator", D.uf_debuff_indicator, U[c])
      p:Checkbox(T["Only Class Dispellable"], f, "debuff_ind_class", U[c])
      p:Dropdown(T["Indicator Position"], f, "debuff_ind_pos", D.positions, U[c])
      p:Dropdown(T["Indicator Size"], f, "debuff_ind_size", D.uf_debuff_indicator_size, U[c])

      p:Header(T["Combat/Aggro Indicators"])
      p:Checkbox(T["Display Aggro Indicator"], f, "squareaggro", U[c])
      p:Checkbox(T["Display Combat Indicator"], f, "squarecombat", U[c])
      p:Dropdown(T["Indicator Position"], f, "squarepos", D.positions, U[c])
      p:Number(T["Indicator Size"], f, "squaresize", U[c], ICONSIZE)

      p:Header(T["Icons"])
      p:Checkbox(T["Show Leader Icon"], f, "leadericon", U[c])
      p:Checkbox(T["Show Loot Icon"], f, "looticon", U[c])
      if c == "player" then
        p:Checkbox(T["Show Resting"], f, "showRest")
      end
      if c == "pet" then
        p:Dropdown(T["Show Happiness Icon"], f, "happinessicon", D.uf_happiness, U[c])
        p:Number(T["Happiness Icon Size"], f, "happinesssize", U[c], ICONSIZE)
      end
      p:Checkbox(T["Show PvP-Flag"], f, "showPVP", U[c])
      p:Number(T["PVP Flag Size"], f, "pvpiconsize", U[c], Opts(ICONSIZE, { requires = "showPVP" }))
      p:Dropdown(T["PvP Flag Position"], f, "pvpiconalign", D.positions, U[c], { requires = "showPVP" })
      p:Number(T["PvP Flag X-Offset"], f, "pvpiconoffx", U[c], Opts(OFFSET, { requires = "showPVP" }))
      p:Number(T["PvP Flag Y-Offset"], f, "pvpiconoffy", U[c], Opts(OFFSET, { requires = "showPVP" }))
      p:Checkbox(T["Show Raid Mark"], f, "raidicon", U[c])
      p:Number(T["Raid Mark Size"], f, "raidiconsize", U[c], Opts(ICONSIZE, { requires = "raidicon" }))
      p:Dropdown(T["Raid Mark Position"], f, "raidiconalign", D.positions, U[c], { requires = "raidicon" })
      p:Number(T["Raid Mark X-Offset"], f, "raidiconoffx", U[c], Opts(OFFSET, { requires = "raidicon" }))
      p:Number(T["Raid Mark Y-Offset"], f, "raidiconoffy", U[c], Opts(OFFSET, { requires = "raidicon" }))

      p:Header(T["Combat Text"])
      p:Checkbox(T["Show Combat Text"], f, "hitindicator", U[c])
      p:Dropdown(T["Combat Text Font"], f, "hitindicatorfont", D.fonts, U[c], Opts({ preview = "font" }, { requires = "hitindicator" }))
      p:Number(T["Combat Text Size"], f, "hitindicatorsize", U[c], Opts(FONTSIZE, { requires = "hitindicator" }))

      p:Header(T["Overwrite Fonts"])
      p:Checkbox(T["Use Custom Font Settings"], f, "customfont", U[c])
      p:Dropdown(T["Custom Font Name"], f, "customfont_name", D.fonts, U[c], Opts({ preview = "font" }, { requires = "customfont" }))
      p:Number(T["Custom Font Size"], f, "customfont_size", U[c], Opts(FONTSIZE, { requires = "customfont" }))
      p:Dropdown(T["Custom Font Style"], f, "customfont_style", D.fontstyle, U[c], { requires = "customfont" })

      p:Header(T["Overwrite Colors"])
      p:Checkbox(T["Inherit Default Colors"], f, "defcolor", U[c])
      p:Dropdown(T["Health Bar Color"], f, "custom", D.uf_color, U[c], { requires = "!defcolor" })
      p:Color(T["Custom Health Bar Color"], f, "customcolor", U[c], { requires = "!defcolor" })
      p:Checkbox(T["Fade To Custom Color"], f, "customfade", U[c], { requires = "!defcolor" })
      p:Checkbox(T["Use Custom Color On Full Health"], f, "customfullhp", U[c], { requires = "!defcolor" })
      p:Checkbox(T["Use Custom Color Health Bar Background"], f, "custombg", U[c], { requires = "!defcolor" })
      p:Color(T["Custom Health Bar Background Color"], f, "custombgcolor", U[c], { requires = "!defcolor" })
      p:Color(T["Mana Color"], f, "manacolor", U[c], { requires = "!defcolor" })
      p:Color(T["Rage Color"], f, "ragecolor", U[c], { requires = "!defcolor" })
      p:Color(T["Energy Color"], f, "energycolor", U[c], { requires = "!defcolor" })
      p:Color(T["Focus Color"], f, "focuscolor", U[c], { requires = "!defcolor" })
      p:Checkbox(T["Use Custom Color Power Bar Background"], f, "custompbg", U[c], { requires = "!defcolor" })
      p:Color(T["Custom Power Bar Background Color"], f, "custompbgcolor", U[c], { requires = "!defcolor" })

      if c == "player" then
        p:Header(T["Energy/Mana Ticks"])
        p:Checkbox(T["Enable Energy Ticks"], f, "energy")
        p:Checkbox(T["Enable Mana Ticks"], f, "manatick")
        p:Checkbox(T["Show Five Second Rule"], f, "showfsr")
        p:Dropdown(T["Five Second Rule Style"], f, "fsrstyle", function() return {"0:" .. T["Separate Bar"], "1:" .. T["Overlay"]} end, nil, { requires = "showfsr" })
        p:Number(T["Five Second Rule Height"], f, "fsrheight", nil, { requires = "showfsr" })
        p:Color(T["Five Second Rule Color"], C.appearance.castbar, "fsrcolor")

        p:Header(T["Druid Mana Bar"])
        p:Checkbox(T["Show Druid Mana Bar"], C.unitframes, "druidmanabar")
        p:Checkbox(T["Show Druid Mana Bar Text"], C.unitframes, "druidmanatext")
        p:Number(T["Druid Mana Bar Width (-1 = auto)"], C.unitframes, "druidmanawidth")
        p:Number(T["Druid Mana Bar Height"], C.unitframes, "druidmanaheight")
        p:Number(T["Druid Mana Bar Spacing"], C.unitframes, "druidmanaspace")
        p:Number(T["Druid Mana Bar X-Offset"], C.unitframes, "druidmanaoffx", nil, OFFSET)
        p:Number(T["Druid Mana Bar Y-Offset"], C.unitframes, "druidmanaoffy", nil, OFFSET)
        p:Dropdown(T["Druid Mana Bar Texture"], C.unitframes, "druidmanatexture", D.uf_bartexture, nil, { preview = "texture" })

        p:Header(T["Player SP/Haste Display"])
        p:Checkbox(T["Haste Display"], f, "display_haste")
        p:Color(T["Haste Display Color"], f, "display_haste_color", nil, { requires = "display_haste" })
        p:Checkbox(T["Display Spell Power"], f, "display_spellpower")
        p:Checkbox(T["Use Custom Spell Power Color (unchecked = biggest school color)"], f, "display_sp_color_override", nil, { requires = "display_spellpower" })
        p:Color(T["Spell Power Color"], f, "display_sp_color", nil, { requires = "display_sp_color_override" })
      end

      if c == "target" then
        p:Header(T["Combo Points"])
        p:Number(T["Combopoint Width"], C.unitframes, "combowidth")
        p:Number(T["Combopoint Height"], C.unitframes, "comboheight")

        p:Header(T["Target Indicators"])
        p:Checkbox(T["Show Line of Sight Indicator"], C.unitframes, "los_indicator")
        p:Checkbox(T["Show Behind Indicator"], C.unitframes, "behind_indicator")
        p:Checkbox(T["Show Distance of Target"], C.unitframes, "distance_indicator")
        p:Checkbox(T["Hide yd characters"], C.unitframes, "hide_distance_yd")
        p:Checkbox(T["Hook Distance to Portrait Frame"], C.unitframes, "distance_hook_portrait")
        p:Number(T["Target Indicator Font Size"], C.unitframes, "indicator_font_size", nil, FONTSIZE)
      end
  end, { preview = unitPreview })

  -- The nameplates page draws sample plates (nameplates.lua) above its
  -- settings. The module loads after this file, and not at all while it is
  -- switched off, so the preview looks it up as it goes.
  local platePreview = {}

  function platePreview.GetHeight()
    return 120
  end

  function platePreview.Show(box)
    if not pfUI.nameplates then return end
    pfUI.nameplates:ShowPreview(box)
    platePreview.parts = pfUI.nameplates.previewParts
  end

  function platePreview.Hide()
    if pfUI.nameplates then pfUI.nameplates:HidePreview() end
  end

  function platePreview.Refresh()
    if not pfUI.nameplates then return end
    pfUI.nameplates:RefreshPreview()
    platePreview.parts = pfUI.nameplates.previewParts
  end

  gui:AddPage("nameplates", T["Nameplates"], nil, function(p)
    p:Header(T["Visibility"])
    p:Checkbox(T["Show On Hostile Units"], C.nameplates, "showhostile", U["nameplates"])
    p:Checkbox(T["Show On Friendly Units"], C.nameplates, "showfriendly", U["nameplates"])
    p:Checkbox(T["Disable Hostile Nameplates In Friendly Zones"], C.nameplates, "disable_hostile_in_friendly", U["nameplates"])
    p:Checkbox(T["Disable Friendly Nameplates In Friendly Zones"], C.nameplates, "disable_friendly_in_friendly", U["nameplates"])
    p:Checkbox(T["Enable Overlap"], C.nameplates, "overlap", U["nameplates"])
    p:Checkbox(T["Replace Totems With Icons"], C.nameplates, "totemicons", U["nameplates"])

    p:Header(T["Healthbar"])
    p:Number(T["Nameplate Width"], C.nameplates, "width", U["nameplates"])
    p:Number(T["Healthbar Height"], C.nameplates, "heighthealth", U["nameplates"])
    p:Dropdown(T["Healthbar Texture"], C.nameplates, "healthtexture", D.uf_bartexture, U["nameplates"], { preview = "texture" })
    p:Checkbox(T["Vertical Healthbar"], C.nameplates, "verticalhealth", U["nameplates"])
    p:Number(T["Vertical Offset (|cffffaaaaExperimental|r)"], C.nameplates, "vertical_offset", U["nameplates"])
    p:Number(T["Healthbar Vertical Offset"], C.nameplates.health, "offset", U["nameplates"])

    p:Header(T["Healthbar Visibility"])
    p:Checkbox(T["Hide Healthbar On Enemy NPCs"], C.nameplates, "enemynpc", U["nameplates"])
    p:Checkbox(T["Hide Healthbar On Enemy Players"], C.nameplates, "enemyplayer", U["nameplates"])
    p:Checkbox(T["Hide Healthbar On Neutral NPCs"], C.nameplates, "neutralnpc", U["nameplates"])
    p:Checkbox(T["Hide Healthbar On Friendly NPCs"], C.nameplates, "friendlynpc", U["nameplates"])
    p:Checkbox(T["Hide Healthbar On Friendly Players"], C.nameplates, "friendlyplayer", U["nameplates"])
    p:Checkbox(T["Hide Healthbar On Critters"], C.nameplates, "critters", U["nameplates"])
    p:Checkbox(T["Hide Healthbar On Totems"], C.nameplates, "totems", U["nameplates"])
    p:Checkbox(T["Always Show On Units With Missing HP"], C.nameplates, "fullhealth", U["nameplates"])
    p:Checkbox(T["Always Show On Target Units"], C.nameplates, "target", U["nameplates"])

    p:Header(T["Text"])
    p:Checkbox(T["Use Unit Fonts"], C.nameplates, "use_unitfonts", U["nameplates"])
    p:Dropdown(T["Font Style"], C.nameplates.name, "fontstyle", D.fontstyle, U["nameplates"])
    p:Dropdown(T["Name Text Position"], C.nameplates, "nametextpos", D.textalign, U["nameplates"])
    p:Checkbox(T["Show Guild Name"], C.nameplates, "showguildname", U["nameplates"])
    p:Checkbox(T["Show Health Points"], C.nameplates, "showhp", U["nameplates"])
    p:Dropdown(T["Health Text Position"], C.nameplates, "hptextpos", D.textalign, U["nameplates"])
    p:Dropdown(T["Health Text Format"], C.nameplates, "hptextformat", D.hpformat, U["nameplates"])

    p:Header(T["Colors"])
    p:Checkbox(T["Enable Class Colors On Enemies"], C.nameplates, "enemyclassc", U["nameplates"])
    p:Checkbox(T["Enable Class Colors On Friends"], C.nameplates, "friendclassc", U["nameplates"])
    p:Checkbox(T["Enable Class Colors On Friends Name"], C.nameplates, "friendclassnamec", U["nameplates"])
    p:Checkbox(T["Red Name Text On Infight Units"], C.nameplates, "namefightcolor", U["nameplates"])

    p:Header(T["Outlines"])
    p:Checkbox(T["Blue Border On Friendly Players"], C.nameplates, "outfriendly", U["nameplates"])
    p:Checkbox(T["Green Border On Friendly NPCs"], C.nameplates, "outfriendlynpc", U["nameplates"])
    p:Checkbox(T["Yellow Border On Neutral Units"], C.nameplates, "outneutral", U["nameplates"])
    p:Checkbox(T["Red Border On Enemy Units"], C.nameplates, "outenemy", U["nameplates"])

    p:Header(TARGET)
    p:Dropdown(T["Inactive Nameplate Alpha"], C.nameplates, "notargalpha", D.percent_small, U["nameplates"])
    p:Checkbox(T["Border Around Target Unit"], C.nameplates, "targethighlight", U["nameplates"])
    p:Color(T["Border Color Around Target Unit"], C.nameplates, "highlightcolor", U["nameplates"])
    p:Checkbox(T["Draw Glow Around Target Nameplate"], C.nameplates, "targetglow", U["nameplates"])
    p:Color(T["Glow Color Around Target Nameplate"], C.nameplates, "glowcolor", U["nameplates"])
    p:Checkbox(T["Zoom Target Nameplate"], C.nameplates, "targetzoom", U["nameplates"])
    p:Dropdown(T["Target Nameplate Zoom Factor"], C.nameplates, "targetzoomval", D.percent_small, U["nameplates"])

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
    p:Number(T["Debuff Icon Size"], C.nameplates, "debuffsize", U["nameplates"], ICONSIZE)
    p:Checkbox(T["Show Debuff Stacks"], C.nameplates.debuffs, "showstacks", U["nameplates"])
    p:Dropdown(T["Debuff Timers"], C.nameplates, "debuff_timers", D.cooldown_timers, UpdateCooldowns)

    p:Dropdown(T["Filter Mode"], C.nameplates.debuffs, "filter", D.buffbarfilter, U["nameplates"])
    p:List(T["Blacklist"], C.nameplates.debuffs, "blacklist", U["nameplates"])
    p:List(T["Whitelist"], C.nameplates.debuffs, "whitelist", U["nameplates"])

    p:Header(T["Combo Points"])
    p:Checkbox(T["Enable Combo Point Display"], C.nameplates, "cpdisplay", U["nameplates"])

    p:Header(T["Raid Icon"])
    p:Dropdown(T["Raid Icon Position"], C.nameplates, "raidiconpos", D.positions, U["nameplates"])
    p:Number(T["Raid Icon X-Offset"], C.nameplates, "raidiconoffx", U["nameplates"], OFFSET)
    p:Number(T["Raid Icon Y-Offset"], C.nameplates, "raidiconoffy", U["nameplates"], OFFSET)
    p:Number(T["Raid Icon Size"], C.nameplates, "raidiconsize", U["nameplates"], ICONSIZE)

    p:Header(T["Mouse"])
    p:Checkbox(T["Enable Clickthrough"], C.nameplates, "clickthrough", U["nameplates"])
    p:Checkbox(T["Enable Mouselook With Right Click"], C.nameplates, "rightclick", U["nameplates"])
    p:Number(T["Right Click Auto Attack Threshold"], C.nameplates, "clickthreshold", U["nameplates"])

    p:Header(T["Combat State"])
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
  end, { module = "nameplates", preview = platePreview })

  gui:AddPage("actionbar.general", T["Actionbar"], T["General"], function(p)
    p:Header(T["Behavior"])
    p:Checkbox(T["Trigger Actions On Key Down"], C.bars, "keydown", U["bars"])
    p:Checkbox(T["Self Cast: Alt Key"], C.bars, "altself", U["bars"])
    p:Checkbox(T["Self Cast: Right Click"], C.bars, "rightself", U["bars"])
    p:Checkbox(T["Lock Actionbars"], UVars, "LOCK_ACTIONBAR", U["bars"])
    p:Checkbox(T["Always Allow Drag Via Shift Key"], C.bars, "shiftdrag", U["bars"])

    p:Header(T["Highlights"])
    p:Checkbox(T["Highlight Equipped Items"], C.bars, "showequipped", U["bars"])
    p:Color(T["Equipped Item Color"], C.bars, "eqcolor", U["bars"])
    p:Checkbox(T["Highlight Out Of Range Spells"], C.bars, "glowrange", U["bars"])
    p:Color(T["Out Of Range Color"], C.bars, "rangecolor", U["bars"])
    p:Checkbox(T["Highlight Out Of Mana Spells"], C.bars, "showoom", U["bars"])
    p:Color(T["Out Of Mana Color"], C.bars, "oomcolor", U["bars"])
    p:Checkbox(T["Highlight Not Usable Spells"], C.bars, "showna", U["bars"])
    p:Color(T["Not Usable Color"], C.bars, "nacolor", U["bars"])
    p:Checkbox(T["Highlight Proc And Reactive Spells"], C.bars, "procglow", U["bars"])

    p:Header(T["Animation"])
    p:Dropdown(T["Button Animation"], C.bars, "animation", D.actionbuttonanimations, U["bars"])
    p:Dropdown(T["Button Animation Trigger"], C.bars, "animmode", D.animationmode, U["bars"])
    p:Checkbox(T["Show Animation On Hidden Bars"], C.bars, "animalways", U["bars"])

    p:Header(T["Text"])
    p:Dropdown(T["Cooldown Timers"], C.bars, "timers", D.cooldown_timers, UpdateCooldowns)
    p:Checkbox(T["Show Reagent Count"], C.bars, "reagents", U["bars"])
    p:Dropdown(T["Font"], C.bars, "font", D.fonts, U["bars"], { preview = "font" })
    p:Number(T["Font Padding"], C.bars, "font_offset", U["bars"], OFFSET)
    p:Number(T["Macro Text Size"], C.bars, "macro_size", U["bars"], FONTSIZE)
    p:Color(T["Macro Text Color"], C.bars, "macro_color", U["bars"])
    p:Number(T["Item Count Text Size"], C.bars, "count_size", U["bars"], FONTSIZE)
    p:Color(T["Item Count Text Color"], C.bars, "count_color", U["bars"])
    p:Number(T["Keybind Text Size"], C.bars, "bind_size", U["bars"], FONTSIZE)
    p:Color(T["Keybind Text Color"], C.bars, "bind_color", U["bars"])

    p:Header(T["Auto Paging"])
    p:Checkbox(T["Switch Pages On Alt Key Press"], C.bars, "pagemasteralt", U["bars"])
    p:Checkbox(T["Switch Pages On Shift Key Press"], C.bars, "pagemastershift", U["bars"])
    p:Checkbox(T["Switch Pages On Ctrl Key Press"], C.bars, "pagemasterctrl", U["bars"])
    p:Checkbox(T["Switch Pages On Druid Stealth"], C.bars, "druidstealth", U["bars"])
    p:Checkbox(T["Switch Pages On Priest Shadowform"], C.bars, "priestshadow", U["bars"])
    p:Checkbox(T["Range Based Hunter Paging"], C.bars, "hunterbar")
  end, { module = "actionbar" })

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

  local actionbars = {}
  for _, data in ipairs(barnames) do
    table.insert(actionbars, { "bar" .. data[1], data[2] })
  end

  gui:AddVariantPage("actionbar.bars", T["Actionbar"], T["Bars"], actionbars, function(bar)
    return C.bars[bar]
  end, function(p, bar)
    local id = tonumber(bar:sub(4))
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

      p:Header(T["Buttons"])
      p:Checkbox(T["Enable"], C.bars["bar"..id], "enable", U["bars"])

      if id ~= 11 and id ~= 12 then
        p:Dropdown(T["Buttons"], C.bars["bar"..id], "buttons", D.actionbarbuttons, U["bars"], { requires = "enable" })
        if id ~= 1 then
          p:Checkbox(T["Pageable"], C.bars["bar"..id], "pageable", U["bars"], { requires = "enable" })
        end
      end

      p:Number(T["Icon Size"], C.bars["bar"..id], "icon_size", U["bars"], Opts(ICONSIZE, { requires = "enable" }))
      p:Number(T["Spacing"], C.bars["bar"..id], "spacing", U["bars"], Opts(SPACING, { requires = "enable" }))

      p:Header(T["Layout"])
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
      p:Dropdown(T["Layout"], C.bars["bar"..id], "formfactor", formfactors, layout_ufunc, { requires = "enable" })
      p:Dropdown(T["Layout Uneven Orientation"], C.bars["bar"..id], "uneven", uneven_options, U["bars"], { requires = "enable" })
      p:Dropdown(T["Fill Order"], C.bars["bar"..id], "fillmode", function()
        return {"auto:" .. T["Auto"], "row:" .. T["Row-first (1,2,3 / 4,5,6)"], "col:" .. T["Column-first (1,3,5 / 2,4,6)"]}
      end, U["bars"], { requires = "enable" })

      p:Header(DISPLAY)
      p:Checkbox(T["Bar Background"], C.bars["bar"..id], "background", U["bars"], { requires = "enable" })
      p:Checkbox(T["Show Hotkey Text"], C.bars["bar"..id], "showkeybind", U["bars"], { requires = "enable" })

      if id ~= 11 and id ~= 12 then
        p:Checkbox(T["Show Macro Text"], C.bars["bar"..id], "showmacro", U["bars"], { requires = "enable" })
        p:Checkbox(T["Show Item Count Text"], C.bars["bar"..id], "showcount", U["bars"], { requires = "enable" })
      end

      if id ~= 11 then
        p:Checkbox(T["Show Empty Buttons"], C.bars["bar"..id], "showempty", U["bars"], { requires = "enable" })
      end

      if id == 12 then
        p:Checkbox(T["Auto-Castable Action Indicator"], C.bars, "showcastable", U["bars"])
      end

      p:Header(T["Auto Hide"])
      p:Checkbox(T["Enable Autohide"], C.bars["bar"..id], "autohide", U["bars"], { requires = "enable" })
      p:Number(T["Autohide Timeout"], C.bars["bar"..id], "hide_time", U["bars"], { requires = "autohide" })
      p:Checkbox(T["Show In Combat"], C.bars["bar"..id], "hide_combat", U["bars"], { requires = "enable" })
  end, { module = "actionbar" })

  gui:AddPage("actionbar.gryphons", T["Actionbar"], T["Gryphons"], function(p)
    p:Dropdown(T["Texture"], C.bars.gryphons, "texture", D.gryphons, U["gryphons"])
    p:Color(COLOR, C.bars.gryphons, "color", U["gryphons"])
    p:Dropdown(T["Left Anchor"], C.bars.gryphons, "anchor_left", D.xpanchors, U["gryphons"])
    p:Dropdown(T["Right Anchor"], C.bars.gryphons, "anchor_right", D.xpanchors, U["gryphons"])
    p:Number(T["Size"], C.bars.gryphons, "size", U["gryphons"])
    p:Number(T["Horizontal Offset"], C.bars.gryphons, "offset_h", U["gryphons"], OFFSET)
    p:Number(T["Vertical Offset"], C.bars.gryphons, "offset_v", U["gryphons"], OFFSET)
  end, { module = "gryphons" })

  gui:AddPage("castbar.general", T["Castbar"], T["General"], function(p)
    p:Header(T["Appearance"])
    p:Dropdown(T["Castbar Texture"], C.appearance.castbar, "texture", D.uf_bartexture, nil, { preview = "texture" })
    p:Color(T["Casting Color"], C.appearance.castbar, "castbarcolor")
    p:Color(T["Channeling Color"], C.appearance.castbar, "channelcolor")
    p:Color(T["Uninterruptible Color"], C.appearance.castbar, "shieldcolor")

    p:Header(T["Text"])
    p:Checkbox(T["Use Unit Fonts"], C.castbar, "use_unitfonts")
    p:Dropdown(T["Timer Decimals"], C.unitframes, "castbardecimals", D.castbardecimals)
  end, { module = "castbar" })

  local castbars = {
    { "player", T["Player"], T["Disable Player Castbar"] },
    { "target", TARGET,      T["Disable Target Castbar"] },
    { "focus",  T["Focus"],  T["Disable Focus Castbar"] },
  }

  gui:AddVariantPage("castbar.bars", T["Castbar"], T["Bars"], castbars, function(unit)
    return C.castbar[unit]
  end, function(p, unit)
    local c = C.castbar[unit]
    p:Header(T["Castbar"])
    for _, entry in ipairs(castbars) do
      if entry[1] == unit then p:Checkbox(entry[3], c, "hide_pfui") end
    end
    if unit == "player" then
      p:Checkbox(T["Disable Blizzard Castbar"], c, "hide_blizz")
    end
    p:Number(T["Castbar Width"], c, "width", nil, { requires = "!hide_pfui" })
    p:Number(T["Castbar Height"], c, "height", nil, { requires = "!hide_pfui" })

    p:Header(T["Spell"])
    p:Checkbox(T["Show Spell Icon"], c, "showicon", nil, { requires = "!hide_pfui" })
    p:Checkbox(T["Show Spell Name"], c, "showname", nil, { requires = "!hide_pfui" })
    p:Checkbox(T["Show Rank"], c, "showrank", nil, { requires = "!hide_pfui" })
    p:Dropdown(T["Spell Name Alignment"], c, "namealign", D.castbaralign, nil, { requires = "!hide_pfui" })
    p:Number(T["Spell Name X Offset"], c, "txtleftoffx", nil, Opts(OFFSET, { requires = "!hide_pfui" }))
    p:Number(T["Spell Name Y Offset"], c, "txtleftoffy", nil, Opts(OFFSET, { requires = "!hide_pfui" }))
    if unit == "player" then
      p:Checkbox(T["Merge Tradeskill Casts"], c, "mergetradeskill", nil, { requires = "!hide_pfui" })
    end

    p:Header(T["Timer"])
    p:Checkbox(T["Show Timer"], c, "showtimer", nil, { requires = "!hide_pfui" })
    p:Checkbox(T["Show Lag"], c, "showlag", nil, { requires = "!hide_pfui" })
    p:Dropdown(T["Timer Alignment"], c, "timealign", D.castbaralign, nil, { requires = "!hide_pfui" })
    p:Number(T["Timer X Offset"], c, "txtrightoffx", nil, Opts(OFFSET, { requires = "!hide_pfui" }))
    p:Number(T["Timer Y Offset"], c, "txtrightoffy", nil, Opts(OFFSET, { requires = "!hide_pfui" }))
  end, { module = "castbar" })

  gui:AddPage("buffs.icons", T["Buffs"], T["Buff/Debuff Icons"], function(p)
    p:Header(DISPLAY)
    p:Checkbox(T["Enable Buff Display"], C.buffs, "buffs", U["buff"])
    p:Checkbox(T["Enable Debuff Display"], C.buffs, "debuffs", U["buff"])
    p:Checkbox(T["Enable Weapon Buff Display"], C.buffs, "weapons", U["buff"])
    p:Checkbox(T["Separate Weapon Buffs"], C.buffs, "separateweapons", U["buff"])

    p:Header(T["Layout"])
    p:Number(T["Buff Size"], C.buffs, "size", U["buff"], ICONSIZE)
    p:Number(T["Buff Spacing"], C.buffs, "spacing", U["buff"], SPACING)
    p:Number(T["Number Of Buffs Per Row"], C.buffs, "buffrowsize", U["buff"], COUNT)
    p:Number(T["Number Of Debuffs Per Row"], C.buffs, "debuffrowsize", U["buff"], COUNT)
    p:Number(T["Number Of Weapon Buffs Per Row"], C.buffs, "wepbuffrowsize", U["buff"], COUNT)

    p:Header(T["Text"])
    p:Dropdown(T["Duration Timers"], C.buffs, "timers", D.cooldown_timers, UpdateCooldowns)
    p:Checkbox(T["Show Duration Inside Buff"], C.buffs, "textinside", U["buff"])
    p:Number(T["Stack Count Font Size"], C.buffs, "fontsize", U["buff"], FONTSIZE)
  end, { module = "buff" })

  gui:AddPage("buffs.totems", T["Buffs"], T["Totem Bar"], function(p)
    p:Header(T["Layout"])
    p:Dropdown(T["Totem Direction"], C.totems, "direction", D.orientation, U["totems"])
    p:Dropdown(T["Flyout Direction"], C.totems, "flyout", D.flyout, U["totems"])
    p:Number(T["Icon Size"], C.totems, "iconsize", U["totems"], ICONSIZE)
    p:Dropdown(T["Spacing"], C.totems, "spacing", D.spacing, U["totems"])
    p:Checkbox(T["Show Background"], C.totems, "showbg", U["totems"])

    p:Header(T["Behavior"])
    p:Checkbox(T["Only Show Active Totems"], C.totems, "onlyactive", U["totems"])
    p:Number(T["Expiry Warning (Seconds)"], C.totems, "expirywarn", U["totems"])
    p:Checkbox(T["Announce Killed Totems"], C.totems, "killalert", U["totems"])
    p:Dropdown(T["Duration Timers"], C.totems, "timers", D.cooldown_timers, UpdateCooldowns)
  end, { module = "totems" })

  local buffbars = {
    { "pbuff",   T["Player Buff Bar"] },
    { "pdebuff", T["Player Debuff Bar"] },
    { "tdebuff", T["Target Debuff Bar"] },
  }

  gui:AddVariantPage("buffs.bars", T["Buffs"], T["Buff Bars"], buffbars, function(bar)
    return C.buffbar[bar]
  end, function(p, bar)
    local c = C.buffbar[bar]
    p:Checkbox(T["Enable Bar"], c, "enable")

    p:Header(T["Layout"])
    p:Number(T["Buffbar Width"], c, "width", nil, { requires = "enable" })
    p:Number(T["Buffbar Height"], c, "height", nil, { requires = "enable" })
    p:Dropdown(T["Sort Order"], c, "sort", D.buffbarsort, nil, { requires = "enable" })
    p:Checkbox(T["Use Unit Fonts"], c, "use_unitfonts", nil, { requires = "enable" })

    p:Header(T["Colors"])
    p:Color(T["Background Color"], c, "color", nil, { requires = "enable" })
    p:Color(T["Border Color"], c, "bordercolor", nil, { requires = "enable" })
    p:Color(T["Text Color"], c, "textcolor", nil, { requires = "enable" })
    p:Checkbox(T["Automatic Background Color"], c, "dtypebg", nil, { requires = "enable" })
    p:Checkbox(T["Automatic Border Color"], c, "dtypeborder", nil, { requires = "enable" })
    p:Checkbox(T["Automatic Text Color"], c, "dtypetext", nil, { requires = "enable" })
    p:Checkbox(bar == "pbuff" and T["Color Buff Stacks"] or T["Color Debuff Stacks"], c, "colorstacks", nil, { requires = "enable" })

    p:Header(FILTER)
    if bar == "tdebuff" then
      p:Checkbox(T["Show Only Own Debuffs"], c, "selfdebuff", nil, { requires = "enable" })
    end
    p:Dropdown(T["Filter Mode"], c, "filter", D.buffbarfilter, nil, { requires = "enable" })
    p:Number(T["Time Threshold"], c, "threshold", nil, { requires = "enable" })
    p:List(T["Whitelist"], c, "whitelist", nil, { requires = "enable" })
    p:List(T["Blacklist"], c, "blacklist", nil, { requires = "enable" })
  end, { module = "buffwatch" })

  gui:AddPage("combat.swingtimer", T["Combat"], T["Swing Timer"], function(p)
    p:Header(T["Size"])
    p:Number(T["Width"], C.unitframes, "swingtimerwidth")
    p:Number(T["Height"], C.unitframes, "swingtimerheight")
    p:Dropdown(T["Texture"], C.unitframes, "swingtimertexture", D.uf_bartexture, nil, { preview = "texture" })
    p:Number(FONT_SIZE, C.unitframes, "swingtimerfontsize", nil, FONTSIZE)

    p:Header(DISPLAY)
    p:Checkbox(T["Show Offhand Bar"], C.unitframes, "swingtimeroffhand")
    p:Checkbox(T["Show Ranged Bar"], C.unitframes, "swingtimerranged")
    p:Checkbox(T["Show Timer Text"], C.unitframes, "swingtimertext")
    p:Checkbox(T["Show MH/OH Labels"], C.unitframes, "swingtimerlabel")
    p:Checkbox(T["Show Attack Speed"], C.unitframes, "swingtimerattackspeed")
    p:Checkbox(T["Show On Next Attack Queue Color"], C.unitframes, "swingtimerhsqueue")

    p:Header(T["Colors"])
    p:Color(T["Mainhand Bar Color"], C.unitframes, "swingtimermhcolor")
    p:Color(T["Offhand Bar Color"], C.unitframes, "swingtimerohcolor")
    p:Color(T["Ranged Bar Color"], C.unitframes, "swingtimerrangedcolor")
    p:Color(T["Ranged Warn Color (Hunter)"], C.unitframes, "swingtimerrangedwarncolor")
    p:Color(T["Out Of Range Color"], C.unitframes, "swingtimeroutrangecolor")
  end, { module = "swingtimer" })

  gui:AddPage("combat.marktracking", T["Combat"], T["Mark Tracking"], function(p)
    p:Header(T["Size"])
    p:Number(T["Width"], C.unitframes, "raidmarkerwidth")
    p:Number(T["Height"], C.unitframes, "raidmarkerheight")
    p:Dropdown(T["Grow Direction"], C.unitframes, "raidmarkergrow", D.raidmarker_grow)
    p:Dropdown(T["Texture"], C.unitframes, "raidmarkertexture", D.uf_bartexture, nil, { preview = "texture" })
    p:Number(FONT_SIZE, C.unitframes, "raidmarkerfontsize", nil, FONTSIZE)

    p:Header(DISPLAY)
    p:Checkbox(T["Show Name"], C.unitframes, "raidmarkershowname")
    p:Checkbox(T["Show Percent HP"], C.unitframes, "raidmarkershowpct")
    p:Checkbox(T["Show Portrait"], C.unitframes, "raidmarkershowportrait")

    p:Header(T["Colors"])
    p:Color(T["Star Color"], C.unitframes, "raidmarkercolor_star")
    p:Color(T["Circle Color"], C.unitframes, "raidmarkercolor_circle")
    p:Color(T["Diamond Color"], C.unitframes, "raidmarkercolor_diamond")
    p:Color(T["Triangle Color"], C.unitframes, "raidmarkercolor_triangle")
    p:Color(T["Moon Color"], C.unitframes, "raidmarkercolor_moon")
    p:Color(T["Square Color"], C.unitframes, "raidmarkercolor_square")
    p:Color(T["Cross Color"], C.unitframes, "raidmarkercolor_cross")
    p:Color(T["Skull Color"], C.unitframes, "raidmarkercolor_skull")
  end, { module = "marktracking" })

  gui:AddPage("combat.reactive", T["Combat"], T["Reactive Spells"], function(p)
    p:Checkbox(T["Show Reactive Spell Indicator"], C.unitframes, "reactive_indicator")
    p:Number(T["Reactive Indicator Size"], C.unitframes, "reactive_size", nil, ICONSIZE)
  end, { module = "reactive" })

  gui:AddPage("combat.nampower", T["Combat"], T["Nampower"], function(p)
    p:Checkbox(T["Show Spell Queue Indicator"], C.unitframes, "spellqueue")
    p:Number(T["Spell Queue Icon Size"], C.unitframes, "spellqueuesize", nil, ICONSIZE)
  end, { module = "nampower" })

  gui:AddPage("chat", CHAT_LABEL, nil, function(p)
    -- a nop updater skips the reload prompt; the nop settings below
    -- are read by AddMessage on every chat line
    p:Header(T["Windows"])
    p:Checkbox(T["Enable \"Loot & Spam\" Chat Window"], C.chat.right, "enable")
    p:Number(T["Left Chat Width"], C.chat.left, "width")
    p:Number(T["Left Chat Height"], C.chat.left, "height")
    p:Number(T["Right Chat Width"], C.chat.right, "width")
    p:Number(T["Right Chat Height"], C.chat.right, "height")
    p:Number(T["Inputbox Width"], C.chat.text, "input_width")
    p:Number(T["Inputbox Height"], C.chat.text, "input_height")
    p:Checkbox(T["Hide Combat Log"], C.chat.global, "combathide")
    p:Number(T["Maximum Number Of Chat Lines"], C.chat.global, "maxlines")
    p:Checkbox(T["Enable Sticky Chat"], C.chat.global, "sticky")

    p:Header(T["Appearance"])
    p:Checkbox(T["Enable Frame Shadow"], C.chat.global, "frameshadow")
    p:Checkbox(T["Enable Custom Colors"], C.chat.global, "custombg", U["chat"])
    p:Color(T["Chat Background Color"], C.chat.global, "background", U["chat"])
    p:Color(T["Chat Border Color"], C.chat.global, "border", U["chat"])

    p:Header(T["Tabs"])
    p:Checkbox(T["Enable Chat Dock Background"], C.chat.global, "tabdock")
    p:Checkbox(T["Only Show Chat Dock On Mouseover"], C.chat.global, "tabmouse")
    p:Checkbox(T["Enable Chat Tab Flashing"], C.chat.global, "chatflash")

    p:Header(T["Text"])
    p:Checkbox(T["Enable Text Shadow"], C.chat.text, "outline")
    p:Text(T["Chat Default Brackets"], C.chat.text, "bracket")
    p:Checkbox(T["Hide Channel Names"], C.chat.text, "channelnumonly", nop)
    p:Checkbox(T["Enable Chat History"], C.chat.text, "history")
    p:Checkbox(T["Show Items On Mouseover"], C.chat.text, "mouseover")
    p:Checkbox(T["Enable URL Detection"], C.chat.text, "detecturl", nop)
    p:Checkbox(T["Generate Playerlinks"], C.chat.text, "playerlinks")

    p:Header(T["Timestamps"])
    p:Checkbox(T["Enable Timestamps"], C.chat.text, "time")
    p:Text(T["Timestamp Format"], C.chat.text, "timeformat", nop)
    p:Text(T["Timestamp Brackets"], C.chat.text, "timebracket")
    p:Color(T["Timestamp Color"], C.chat.text, "timecolor")
    -- read each time chat copy opens, so no reload
    p:Checkbox(T["Show Timestamps In Chat Copy"], C.chat.text, "copytime", nop)

    p:Header(T["Names"])
    p:Checkbox(T["Enable Class Colors"], C.chat.text, "classcolor", nop)
    p:Checkbox(T["Colorize Unknown Classes"], C.chat.text, "tintunknown", nop)
    p:Color(T["Unknown Class Color"], C.chat.text, "unknowncolor")
    local _, playerRace = UnitRace("player")
    p:Checkbox(T["Show Faction Icons"] .. " " .. GetFactionIcon(playerRace), C.chat.text, "factionicons", nop)
    p:Checkbox(T["Show Race Icons"] .. " " .. GetRaceIcon(playerRace, UnitSex("player")), C.chat.text, "raceicons", nop)
    p:Checkbox(T["Enable Player Levels"], C.chat.text, "playerlevel", nop)

    p:Header(T["Whispers"])
    p:Checkbox(T["Enable Custom Incoming Whispers Layout"], C.chat.global, "whispermod")
    p:Color(T["Incoming Whispers Color"], C.chat.global, "whisper")

    p:Header(T["Fade & Scroll"])
    p:Checkbox(T["Enable Chat Fade"], C.chat.global, "fadeout")
    p:Number(T["Seconds Before Chat Fade"], C.chat.global, "fadetime")
    p:Number(T["Mousewheel Scroll Speed"], C.chat.global, "scrollspeed", nop)

    p:Header(T["Chat Bubbles"])
    p:Checkbox(T["Enable Chat Bubbles"], CVars, "chatBubbles", nop)
    p:Checkbox(T["Enable Party Chat Bubbles"], CVars, "chatBubblesParty", nop)
    p:Checkbox(T["Enable Chat Bubble Borders"], C.chat.bubbles, "borders")
    p:Number(T["Chat Bubble Transparency"], C.chat.bubbles, "alpha")
  end, { module = "chat" })

  gui:AddPage("panel", T["Panel"], nil, function(p)
    p:Header(T["Texts"])
    p:Dropdown(T["Left Panel: Left"], C.panel.left, "left", D.panel_values)
    p:Dropdown(T["Left Panel: Center"], C.panel.left, "center", D.panel_values)
    p:Dropdown(T["Left Panel: Right"], C.panel.left, "right", D.panel_values)
    p:Dropdown(T["Right Panel: Left"], C.panel.right, "left", D.panel_values)
    p:Dropdown(T["Right Panel: Center"], C.panel.right, "center", D.panel_values)
    p:Dropdown(T["Right Panel: Right"], C.panel.right, "right", D.panel_values)
    p:Dropdown(T["Other Panel: Minimap"], C.panel.other, "minimap", D.panel_values)
    p:Checkbox(T["Use Unit Fonts"], C.panel, "use_unitfonts")
    p:Checkbox(T["Show FPS and Latency Colors"], C.panel, "fpscolors", U["panel"])
    p:Checkbox(T["Only Count Bagspace On Regular Bags"], C.panel.bag, "ignorespecial")

    p:Header(T["Clock"])
    p:Checkbox(T["Enable 24h Clock"], C.global, "twentyfour")
    p:Checkbox(T["Enable Seconds"], C.panel, "seconds")
    p:Checkbox(T["Servertime"], C.global, "servertime")

    p:Header(T["Micro Bar"])
    p:Checkbox(T["Enable Micro Bar"], C.panel.micro, "enable")

    p:Header(T["Auto Hide"])
    p:Checkbox(T["Enable Autohide For Left Chat Panel"], C.panel, "hide_leftchat")
    p:Checkbox(T["Enable Autohide For Right Chat Panel"], C.panel, "hide_rightchat")
    p:Checkbox(T["Enable Autohide For Minimap Panel"], C.panel, "hide_minimap")
    p:Checkbox(T["Enable Autohide For Microbar Panel"], C.panel, "hide_microbar")
  end, { module = "panel" })

  gui:AddPage("xpbar.xp", XPBAR_LABEL, T["Experience Bar"], function(p)
    p:Header(DISPLAY)
    p:Checkbox(T["Always Show"], C.panel.xp, "xp_always", U["xpbar"])
    p:Number(T["Hide Timeout"], C.panel.xp, "xp_timeout", U["xpbar"])
    p:Dropdown(T["Display Mode"], C.panel.xp, "xp_display", D.xp_display, U["xpbar"])
    p:Checkbox(T["Don't overlap rested"], C.panel.xp, "dont_overlap", U["xpbar"])

    p:Header(T["Layout"])
    p:Number(T["Width"], C.panel.xp, "xp_width", U["xpbar"])
    p:Number(T["Height"], C.panel.xp, "xp_height", U["xpbar"])
    p:Dropdown(T["Orientation"], C.panel.xp, "xp_mode", D.orientation, U["xpbar"])
    p:Dropdown(T["Frame Anchor"], C.panel.xp, "xp_anchor", D.xpanchors, U["xpbar"])
    p:Dropdown(T["Aligned Position"], C.panel.xp, "xp_position", D.xp_position, U["xpbar"])
    p:Dropdown(T["Bar Texture"], C.panel.xp, "texture", D.uf_bartexture, U["xpbar"], { preview = "texture" })

    p:Header(T["Text"])
    p:Checkbox(T["Show Text"], C.panel.xp, "xp_text", U["xpbar"])
    p:Number(T["Vertical Text Offset"], C.panel.xp, "xp_text_off_y", U["xpbar"], OFFSET)
    p:Checkbox(T["Only Show On Mouse Over"], C.panel.xp, "xp_text_mouse", U["xpbar"])

    p:Header(T["Colors"])
    p:Color(T["Experience Color"], C.panel.xp, "xp_color", U["xpbar"])
    p:Color(T["Rested Color"], C.panel.xp, "rest_color", U["xpbar"])
  end, { module = "xpbar" })

  gui:AddPage("xpbar.rep", XPBAR_LABEL, T["Reputation Bar"], function(p)
    p:Header(DISPLAY)
    p:Checkbox(T["Always Show"], C.panel.xp, "rep_always", U["xpbar"])
    p:Number(T["Hide Timeout"], C.panel.xp, "rep_timeout", U["xpbar"])
    p:Dropdown(T["Display Mode"], C.panel.xp, "rep_display", D.xp_display, U["xpbar"])

    p:Header(T["Layout"])
    p:Number(T["Width"], C.panel.xp, "rep_width", U["xpbar"])
    p:Number(T["Height"], C.panel.xp, "rep_height", U["xpbar"])
    p:Dropdown(T["Orientation"], C.panel.xp, "rep_mode", D.orientation, U["xpbar"])
    p:Dropdown(T["Frame Anchor"], C.panel.xp, "rep_anchor", D.xpanchors, U["xpbar"])
    p:Dropdown(T["Aligned Position"], C.panel.xp, "rep_position", D.xp_position, U["xpbar"])

    p:Header(T["Text"])
    p:Checkbox(T["Show Text"], C.panel.xp, "rep_text", U["xpbar"])
    p:Number(T["Vertical Text Offset"], C.panel.xp, "rep_text_off_y", U["xpbar"], OFFSET)
    p:Checkbox(T["Only Show On Mouse Over"], C.panel.xp, "rep_text_mouse", U["xpbar"])
  end, { module = "xpbar" })

  gui:AddPage("minimap.minimap", MINIMAP_LABEL, MINIMAP_LABEL, function(p)
    p:Header(T["Size"])
    p:Number(T["Minimap Size (|cffffaaaaExperimental|r)"], C.appearance.minimap, "size", U["minimap"])
    p:Number(T["Minimap Player Arrow Scale"], C.appearance.minimap, "arrowscale", U["minimap"])

    p:Header(T["Text"])
    p:Dropdown(T["Zone Text On Minimap"], C.appearance.minimap, "zonetext", D.minimap_zone_visibility)
    p:Dropdown(T["Coordinates On Minimap"], C.appearance.minimap, "coordstext", D.minimap_cords_visibility)
    p:Dropdown(T["Coordinates Location"], C.appearance.minimap, "coordsloc", D.minimap_cords_position)

    p:Header(T["Icons"])
    p:Checkbox(T["Show PvP Icon"], C.unitframes.player, "showPVPMinimap")
    p:Checkbox(T["Show Inactive Tracking"], C.appearance.minimap, "tracking_pulse")
    p:Number(T["Tracking Icon Size"], C.appearance.minimap, "tracking_size", nil, ICONSIZE)
    p:Checkbox(T["Track Group on Minimap"], C.unitframes, "track_group")
  end, { module = "minimap" })

  gui:AddPage("minimap.addonbuttons", MINIMAP_LABEL, T["Addon Buttons"], function(p)
    p:Checkbox(T["Enable Addon Button Frame"], C.abuttons, "enable")
    p:Dropdown(T["Addon Buttons Panel Position"], C.abuttons, "position", D.addonbuttons_position, U["addonbuttons"])
    p:Checkbox(T["Show Addon Buttons On Login"], C.abuttons, "showdefault", U["addonbuttons"])
    p:Number(T["Number Of Buttons Per Row/Column"], C.abuttons, "rowsize", U["addonbuttons"], COUNT)
    p:Number(T["Button Spacing"], C.abuttons, "spacing", U["addonbuttons"], SPACING)
    p:Checkbox(T["Hide When Entering Combat"], C.abuttons, "hideincombat", U["addonbuttons"])
  end, { module = "addonbuttons" })

  gui:AddPage("minimap.worldmap", MINIMAP_LABEL, T["World Map"], function(p)
    p:Color(T["Map Reveal Color"], C.appearance.worldmap, "mapreveal_color", U["mapreveal"])
    p:Checkbox(T["Map Exploration Points"], C.appearance.worldmap, "mapexploration", U["mapreveal"])
    p:Dropdown(T["Map Group/Raid Circle Size"], C.appearance.worldmap, "groupcircles", D.mapcircle, U["mapcolors"])
    p:Checkbox(T["Colorize player name on WorldMap and BattlefieldMinimap"], C.appearance.worldmap, "colornames", U["mapcolors"])
    p:Dropdown(T["Map Tooltip Scale"], C.appearance.worldmap, "tooltipsize", D.maptooltip, U["map"])
  end)

  gui:AddPage("tooltip", T["Tooltip"], nil, function(p)
    p:Header(T["General"])
    p:Dropdown(T["Tooltip Position"], C.tooltip, "position", D.tooltip_position)
    p:Dropdown(T["Tooltip Text Font"], C.tooltip, "font_tooltip", D.fonts, nil, { preview = "font" })
    p:Number(T["Tooltip Text Font Size"], C.tooltip, "font_tooltip_size", nil, FONTSIZE)
    p:Dropdown(T["Cursor Tooltip Align"], C.tooltip, "cursoralign", D.tooltip_align)
    p:Number(T["Cursor Tooltip Offset"], C.tooltip, "cursoroffset")
    p:Number(T["Custom Transparency"], C.tooltip, "alpha")
    p:Dropdown(T["Status Bar Texture"], C.tooltip.statusbar, "texture", D.uf_bartexture, nil, { preview = "texture" })

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
  end, { module = "tooltip" })

  gui:AddPage("bags", T["Bags & Bank"], nil, function(p)
    p:Header(T["Layout"])
    p:Checkbox(T["Enable Movable Bags"], C.appearance.bags, "movable")
    p:Checkbox(T["Anchor Bags Above Chat"], C.appearance.bags, "abovechat")
    p:Checkbox(T["Hide Chat When Bags Are Opened"], C.appearance.bags, "hidechat")
    p:Number(T["Bagslots Per Row"], C.appearance.bags, "bagrowlength", nil, COUNT)
    p:Number(T["Bankslots Per Row"], C.appearance.bags, "bankrowlength", nil, COUNT)
    p:Number(T["Item Slot Size"], C.appearance.bags, "icon_size", nil, ICONSIZE)

    p:Header(ITEMS)
    p:Checkbox(T["Disable Item Quality Color For \"Common\" Items"], C.appearance.bags, "borderlimit")
    p:Checkbox(T["Enable Item Quality Color For Equipment Only"], C.appearance.bags, "borderonlygear")
    p:Checkbox(T["Highlight Unusable Items"], C.appearance.bags, "unusable")
    p:Color(T["Unusable Item Color"], C.appearance.bags, "unusable_color")
    p:Checkbox(T["Highlight New Items"], C.appearance.bags, "newitem")
    p:Color(T["New Item Color"], C.appearance.bags, "newitem_color")
    p:Dropdown(T["Cooldown Timers"], C.appearance.bags, "timers", D.cooldown_timers, UpdateCooldowns)

    p:Header(T["Automation"])
    p:Checkbox(T["Auto Sort When Opening Bags"], C.appearance.bags, "autoSortOnOpen")
    p:Checkbox(T["Auto Sell Grey Items"], C.global, "autosell")
    p:Checkbox(T["Auto Repair Items"], C.global, "autorepair")
  end, { module = "bags" })

  gui:AddPage("loot", LOOT, nil, function(p)
    p:Header(T["Window"])
    p:Checkbox(T["Enable Auto-Resize Loot Frame"], C.loot, "autoresize")
    p:Checkbox(T["Enable Loot Window On MouseCursor"], C.loot, "mousecursor")
    p:Checkbox(T["Disable Loot Confirmation Dialog (Without Group)"], C.loot, "autopickup")
    p:Checkbox(T["Enable Advanced Master Loot Menu"], C.loot, "advancedloot")

    p:Header(T["Rolls"])
    p:Dropdown(T["Random Roll Announcement Rarity"], C.loot, "rollannouncequal", D.loot_rarity)
    p:Checkbox(T["Detailed Random Roll Announcement"], C.loot, "rollannounce")
    p:Checkbox(T["Use Item Rarity Color For Loot-Roll Timer"], C.loot, "raritytimer")
  end, { module = "loot" })

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
  end, { module = "equipmentmanager" })

  gui:AddPage("character.reputation", CHARACTER, REPUTATION, function(p)
    p:Checkbox(T["Show Reputation Remaining"], C.character.reputation, "repRequired")
  end)

  gui:AddPage("thirdparty.integrations", T["Thirdparty"], T["Integrations"], function(p)
    p:Header(T["Meters"])
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

    p:Header(T["Other Addons"])
    p:Checkbox("WIM", C.thirdparty.wim, "enable")
    p:Checkbox("HealComm", C.thirdparty.healcomm, "enable")
    p:Checkbox("SortBags", C.thirdparty.sortbags, "enable")
    p:Checkbox("MrPlow", C.thirdparty.mrplow, "enable")
    p:Checkbox("BetterCharacterStats", C.thirdparty.bcs, "enable")
    p:Checkbox("Crafty", C.thirdparty.crafty, "enable")
    p:Checkbox("CleverMacro", C.thirdparty.clevermacro, "enable")
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
