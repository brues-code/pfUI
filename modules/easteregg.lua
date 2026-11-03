pfUI:RegisterModule("easteregg", function ()
  local today = date("%m%d")

  -- A full screen scene for the time the player is AFK on a holiday. The
  -- night fades in, and a click or coming back clears AFK and hides it.
  local function CreateScene(name, greeting, info)
    local scene = CreateFrame("Button", name, WorldFrame)
    scene:SetFrameStrata("DIALOG")
    scene:SetAllPoints()
    scene:Hide()

    scene.night = scene:CreateTexture(nil, "BACKGROUND")
    scene.night:SetColorTexture(0,0,0,1)
    scene.night:SetGradientAlpha("VERTICAL", 0,0,0,.5, 0,0,0,1)
    scene.night:SetAllPoints()

    scene.stext = scene:CreateFontString(nil, "ARTWORK", "GameFontWhite")
    scene.stext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    scene.stext:SetPoint("TOP", 0, -380)
    scene.stext:SetText("|cff33ffccShagu|cffffffff wishes you a")

    scene.text = scene:CreateFontString(nil, "ARTWORK", "GameFontWhite")
    scene.text:SetFont(pfUI.media["font:BigNoodleTitling.ttf"], 38)
    scene.text:SetPoint("TOP", 0, -400)
    scene.text:SetText(greeting)

    local exit = "|cff444444<Click> or '/afk' to exit"
    scene.dtext = scene:CreateFontString(nil, "ARTWORK", "GameFontWhite")
    scene.dtext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    scene.dtext:SetPoint("TOP", 0, -430)
    scene.dtext:SetText(info and info .. "\n\n" .. exit or exit)

    -- Fade the night in. The scene keeps an alpha of 1, which comes back
    -- when the fade ends.
    scene.dusk = scene:CreateAnimationGroup()
    local fade = scene.dusk:CreateAnimation("Alpha")
    fade:SetToAlpha(1)
    fade:SetDuration(.8)

    scene:SetScript("OnShow", function()
      this.dusk:Play()
    end)

    -- start over on the next AFK
    scene:SetScript("OnHide", function()
      this:StopAnimating()
    end)

    -- /afk toggles, so send it only while AFK is still set
    scene:SetScript("OnClick", function()
      if IsChatAFK() then SendChatMessage("", "AFK") end
      this:Hide()
    end)

    scene:RegisterEvent("PLAYER_FLAGS_CHANGED")
    scene:SetScript("OnEvent", function()
      this:SetShown(UnitIsAFK('player'))
    end)

    return scene
  end

  -- happy valentine's day
  if today == "0214" then
    local valentine = CreateScene("pfValentine", "happy valentine's day!")
    valentine.text:SetTextColor(1, .4, .6)

    -- a rosy glow around the screen edges
    local glow = CreateFrame("Frame", nil, valentine)
    glow:SetAllPoints()
    glow:SetBackdrop({ edgeFile = pfUI.media["img:glow"], edgeSize = 32 })
    glow:SetBackdropBorderColor(1, .3, .5, 1)

    -- A heart is a square turned onto its corner with a round lobe on each
    -- upper edge. The client's minimap mask is a plain white disc, so it
    -- tints into a lobe without a texture of our own. Smaller hearts are
    -- farther away, so they are darker and rise slower.
    local hearts = {}
    for i = 1, 40 do
      local width = math.random(10, 28)
      local side = width / 1.7
      local shade = .4 + width / 28 * .6
      local r, g, b = shade, shade * math.random() * .4, shade * (.2 + math.random() * .3)

      local heart = CreateFrame("Frame", nil, valentine)
      heart:SetSize(width, width)
      heart.width = width

      local tip = heart:CreateTexture(nil, "ARTWORK")
      tip:SetColorTexture(1, 1, 1)
      tip:SetVertexColor(r, g, b)
      tip:SetSize(side, side)
      tip:SetPoint("CENTER", 0, -side * .07)
      tip:SetRotation(math.pi / 4)

      for _, x in ipairs({ -1, 1 }) do
        local lobe = heart:CreateTexture(nil, "ARTWORK")
        lobe:SetTexture("Textures\\MinimapMask")
        lobe:SetVertexColor(r, g, b)
        lobe:SetSize(side, side)
        lobe:SetPoint("CENTER", x * side * .354, side * .28)
      end

      -- like the snow, but up from below the screen
      heart.float = heart:CreateAnimationGroup()
      heart.float:SetLooping("REPEAT")
      heart.float:SetIgnoreFramerateThrottle(true)
      heart.path = heart.float:CreateAnimation("Path")
      heart.path:SetCurve("SMOOTH")
      heart.points = {}
      for point = 1, 6 do
        heart.points[point] = heart.path:CreateControlPoint()
      end
      hearts[i] = heart
    end

    local function LetThemFloat()
      local width, height = valentine:GetWidth(), valentine:GetHeight()
      for _, heart in ipairs(hearts) do
        local rise = height + heart.width
        local duration = rise / (20 + heart.width * 2)
        local sway = math.random(-30, 30)

        heart:ClearAllPoints()
        heart:SetPoint("TOP", valentine, "BOTTOMLEFT", math.random() * width, 0)

        heart.path:SetDuration(duration)
        heart.path:SetStartDelay(math.random() * duration)
        for point, control in ipairs(heart.points) do
          control:SetOffset(point % 2 == 1 and sway or -sway, rise * point / 6)
        end
        heart.float:Play()
      end
    end

    -- Cupid hovers by the side, turned towards the middle
    local cupid = CreateFrame("PlayerModel", nil, valentine)
    cupid:SetSize(260, 260)
    cupid:SetPoint("BOTTOMRIGHT", -60, 60)
    cupid:SetScript("OnShow", function()
      this:SetDisplayInfo(15990)
      this:SetFacing(-.5)
    end)
    cupid:Hide()

    valentine.dusk:SetScript("OnFinished", function()
      LetThemFloat()
      cupid:Show()
    end)

    valentine:HookScript("OnHide", function()
      cupid:Hide()
    end)
  end

  -- happy hallow's end
  if today == "1031" then
    local halloween = CreateScene("pfHallowsEnd", "happy hallow's end!")
    halloween.text:SetTextColor(1, .5, 0)

    -- Candlelight glows in from the screen edges. It flickers in uneven
    -- steps of { duration, alpha } that end where they began, so the loop
    -- never jumps.
    local candle = CreateFrame("Frame", nil, halloween)
    candle:SetAllPoints()
    candle:SetBackdrop({ edgeFile = pfUI.media["img:glow"], edgeSize = 32 })
    candle:SetBackdropBorderColor(1, .5, .1, 1)

    candle.flicker = candle:CreateAnimationGroup()
    candle.flicker:SetLooping("REPEAT")
    local steps = {
      { .18, .75 }, { .09, .85 }, { .22, .65 }, { .14, .95 }, { .3, .85 },
      { .11, .7 }, { .2, .9 }, { .16, .6 }, { .26, .85 }, { .12, 1 },
    }
    local from = 1
    for order, step in ipairs(steps) do
      local duration, alpha = unpack(step)
      local fade = candle.flicker:CreateAnimation("Alpha")
      fade:SetOrder(order)
      fade:SetDuration(duration)
      fade:SetFromAlpha(from)
      fade:SetToAlpha(alpha)
      fade:SetSmoothing("IN_OUT")
      from = alpha
    end

    -- Once the night has fallen, undead rise along the bottom one after
    -- another, a different few on every AFK. They are creature displays, so
    -- they need no creature cache. A model frame aims its camera at the
    -- middle of the model's bounds, so the frame size alone sets how big one
    -- is. Bounds that reach far above the body, like the lich's, leave it
    -- standing too low, so it is left out.
    local undead = {
      158,   -- skeleton
      201,   -- green skeleton
      1245,  -- skeleton mage
      137,   -- ghoul
      18114, -- white-handed ghoul
      1200,  -- zombie
      1201,  -- green zombie
      1202,  -- sea-green zombie
      915,   -- banshee
      10690, -- green banshee
      146,   -- ghost
      4629,  -- shade
      7533,  -- gargoyle
      7534,  -- black gargoyle
      7854,  -- blue gargoyle
    }

    local function Rise()
      this:SetDisplayInfo(this.display)
      this:SetFacing(this.facing)
    end

    local risen = {}
    local rising = halloween:CreateAnimationGroup()
    for i = 1, 7 do
      local size = math.random(180, 240)
      local model = CreateFrame("PlayerModel", nil, halloween)
      model:SetSize(size, size)
      model:SetPoint("BOTTOM", halloween, "BOTTOM", (i - 4) * 150 + math.random(-20, 20), math.random(-10, 20))
      model.facing = (math.random() - .5) * .8
      model:SetScript("OnShow", Rise)
      model:Hide()
      risen[i] = model

      local rise = rising:CreateAnimation()
      rise:SetOrder(i)
      rise:SetDuration(.3)
      rise:SetScript("OnFinished", function() model:Show() end)
    end

    halloween.dusk:SetScript("OnFinished", function()
      -- shuffle as many undead to the front as there are models
      for i, model in ipairs(risen) do
        local j = math.random(i, #undead)
        undead[i], undead[j] = undead[j], undead[i]
        model.display = undead[i]
      end

      candle.flicker:Play()
      rising:Play()
    end)

    halloween:HookScript("OnHide", function()
      for _, model in ipairs(risen) do
        model:Hide()
      end
    end)
  end

  -- merry x-mas!
  if today == "1224" or today == "1225" then
    local title = (UnitFactionGroup("player") == "Horde") and PVP_RANK_18_0 or PVP_RANK_18_1
    local oldflag = _G.CHAT_FLAG_AFK

    local pvpking = CreateFrame("Frame", "pfPvPKing", UIParent)
    pvpking:Hide()

    pvpking:RegisterEvent("PLAYER_FLAGS_CHANGED")
    pvpking:SetScript("OnEvent", function()
      if UnitIsAFK('player') then
        _G.CHAT_FLAG_AFK = title .. " "
        this.time = GetTime()
        this:Show()
      end
    end)

    pvpking:SetScript("OnUpdate", function()
      if this.time + 1 < GetTime() then
        _G.CHAT_FLAG_AFK = oldflag
        this:Hide()
      end
    end)

    _G.MARKED_AFK           = "You are now |cff33ffcc" .. title .. "|r (AFK)."
    _G.MARKED_AFK_MESSAGE   = "You are now |cff33ffcc" .. title .. "|r (AFK): %s"
    _G.CLEARED_AFK          = "You are no longer |cff33ffcc" .. title .. "|r (AFK).\n|cff33ffccShagu|cffffffff wishes you a merry christmas. Thanks for using |cff33ffccpf|cffffffffUI|cffffffff!|r"

    local snow = CreateScene("pfSnowfall", "merry christmas!")
    snow.text:SetTextColor(1, .25, .25)

    -- Flakes fall past the screen for good and sway on the way down. Before
    -- each fall a flake waits above the screen for a while, which spreads
    -- them out.
    local flakes = {}
    for i = 1, 200 do
      local flake = snow:CreateTexture(nil, "OVERLAY")
      flake.fall = flake:CreateAnimationGroup()
      flake.fall:SetLooping("REPEAT")
      flake.fall:SetIgnoreFramerateThrottle(true)
      flake.path = flake.fall:CreateAnimation("Path")
      flake.path:SetCurve("SMOOTH")
      flake.points = {}
      for point = 1, 6 do
        flake.points[point] = flake.path:CreateControlPoint()
      end
      flakes[i] = flake
    end

    local function LetItSnow()
      local width, height = snow:GetWidth(), snow:GetHeight()
      for _, flake in ipairs(flakes) do
        -- bigger flakes are closer, so they are brighter and fall faster
        local size = math.random(2, 5)
        local fall = height + size
        local duration = fall / (40 + size * 20)
        local sway = math.random(-20, 20)

        flake:SetSize(size, size)
        flake:SetColorTexture(1, 1, 1, .3 + size * .14)
        flake:ClearAllPoints()
        flake:SetPoint("BOTTOM", snow, "TOPLEFT", math.random() * width, 0)

        flake.path:SetDuration(duration)
        flake.path:SetStartDelay(math.random() * duration)
        for point, control in ipairs(flake.points) do
          control:SetOffset(point % 2 == 1 and sway or -sway, -fall * point / 6)
        end
        flake.fall:Play()
      end
    end

    -- Snow piles up at the bottom for as long as the player stays AFK. The
    -- drift plays a shrink backwards, so it grows to its full height over
    -- ten minutes and keeps it once the group ends.
    local pile = snow:CreateTexture(nil, "ARTWORK")
    pile:SetPoint("BOTTOMLEFT", 0, 0)
    pile:SetPoint("BOTTOMRIGHT", 0, 0)
    pile:SetHeight(120)
    pile:SetColorTexture(1, 1, 1, 1)
    pile:SetGradientAlpha("VERTICAL", 1,1,1,.9, 1,1,1,0)
    pile:Hide()

    pile.grow = pile:CreateAnimationGroup()
    local grow = pile.grow:CreateAnimation("Scale")
    grow:SetOrigin("BOTTOM", 0, 0)
    grow:SetScale(1, .01)
    grow:SetDuration(600)

    snow.dusk:SetScript("OnFinished", function()
      LetItSnow()
      pile:Show()
      pile.grow:Play(true)
    end)

    snow:HookScript("OnHide", function()
      pile:Hide()
    end)
  end

  -- happy new year
  if today == "1231" or today == "0101" then
    local fireworks = CreateScene("pfFireworks", "happy new year!",
      "Another year with |cff33ffccpf|rUI has passed.\nThanks for continuing to use it!")

    -- Each explosion grows by 100px and fades out over 5/3s, then goes back
    -- to the pool.
    local explosions = CreateTexturePool(fireworks, "OVERLAY")

    local function Explode(x, y, size, r, g, b, a)
      local tex = explosions:Acquire()
      if not tex.burst then
        tex.burst = tex:CreateAnimationGroup()
        tex.burst:SetIgnoreFramerateThrottle(true)
        tex.burst.grow = tex.burst:CreateAnimation("Scale")
        tex.burst.grow:SetDuration(5/3)
        local fade = tex.burst:CreateAnimation("Alpha")
        fade:SetChange(-1)
        fade:SetDuration(5/3)
        tex.burst:SetScript("OnFinished", function() explosions:Release(tex) end)
      end

      tex:SetPoint("CENTER", fireworks, "TOPLEFT", x, y)
      tex:SetSize(size, size)
      tex:SetColorTexture(r, g, b, a)
      tex.burst.grow:SetScale((size + 100) / size, (size + 100) / size)
      tex:Show()
      tex.burst:Play()
    end

    fireworks:HookScript("OnHide", function()
      explosions:ReleaseAll()
    end)

    -- create random amount of fireworks at random positions
    fireworks:SetScript("OnUpdate", function()
      if this.dusk:IsPlaying() then return end

      -- let the "happy new year" blink
      local r,g,b = this.text:GetTextColor()
      this.text:SetTextColor(r+(math.random()-.5)/10, g+(math.random()-.5)/10, b+(math.random()-.5)/10,1)

      if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + math.random() - .2 end

      local x,y = math.random(1, this:GetWidth()), -1*math.random(1, this:GetHeight())

      -- create the base explosion
      Explode(x, y, 25, 1, 1, 1, .5)

      -- create random amount of colored explosions
      for i=1, math.random(20) do
        Explode(x+(math.random(0,100)-50), y+(math.random(0,100)-50), 2, math.random(), math.random(), math.random(), 1)
      end
    end)
  end
end)
