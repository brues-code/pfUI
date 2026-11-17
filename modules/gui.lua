pfUI:RegisterModule("gui", function ()
  local Reload, CreateConfig, CreateGUIEntry

  -- the width of the navigation on the left of the window
  local NAV_WIDTH = 160

  -- the row template of each type of setting (gui_rows.xml)
  local templates = {
    number   = "pfUIConfigTextRowTemplate",
    text     = "pfUIConfigTextRowTemplate",
    checkbox = "pfUIConfigCheckboxRowTemplate",
    dropdown = "pfUIConfigDropdownRowTemplate",
    color    = "pfUIConfigColorRowTemplate",
    list     = "pfUIConfigListRowTemplate",
    buttons  = "pfUIConfigButtonsRowTemplate",
    header   = "pfUIConfigHeaderRowTemplate",
    warning  = "pfUIConfigWarningRowTemplate",
    -- the head of a variant page
    picker   = "pfUIConfigPickerRowTemplate",
    -- the search results: the page of the settings under it, and a row on a
    -- frame page, which only links to its page
    breadcrumb = "pfUIConfigLinkRowTemplate",
    link     = "pfUIConfigLinkRowTemplate",
  }

  -- the height of the rows on a list page that are not 22 high
  local extents = {
    header  = 45,
    warning = 50,
    picker  = 40,
    breadcrumb = 30,
  }

  -- Stores that read and write game state the way a config table holds a
  -- value. CreateConfig takes their names as a category.
  local stores = {
    CVAR = setmetatable({}, {
      __index = function(_, cvar) return tostring(GetCVar(cvar)) end,
      __newindex = function(_, cvar, value) SetCVar(cvar, value) end,
    }),
    -- the globals of the interface options, saved through their frame
    GVAR = setmetatable({}, {
      __index = function(_, name) return tostring(_G[name] or 0) end,
      __newindex = function(_, name, value)
        UIOptionsFrame_Load()
        _G[name] = value == "1" and 1 or nil
        UIOptionsFrame_Save()
      end,
    }),
    -- globals that hold "1" or "0"
    UVAR = setmetatable({}, {
      __index = function(_, name) return _G[name] end,
      __newindex = function(_, name, value) _G[name] = value end,
    }),
  }

  -- a cvar row resets to the game's default
  pfUI:SetConfigDefaults(stores.CVAR, setmetatable({}, {
    __index = function(_, cvar) return GetCVarDefault(cvar) end,
  }))

  -- the function that applies the settings of a unit frame or a module, by
  -- the frame's label or the module's name
  local U = setmetatable({}, { __index = function(tab,key)
    local ufunc
    -- search pfUI.uf.frames first - these are the active unit frames
    if pfUI.uf and pfUI.uf.frames then
      for _, f in ipairs(pfUI.uf.frames) do
        if f.label == key and f.id == "" then
          ufunc = function()
            for _, fr in ipairs(pfUI.uf.frames) do
              if fr.label == key then
                fr:UpdateConfig()
              end
            end
          end
          break
        end
      end
    end
    -- fallback to pfUI[key] for non-unitframe modules
    if not ufunc then
      if type(pfUI[key]) == "table" and pfUI[key].UpdateConfig then
        ufunc = function() return pfUI[key]:UpdateConfig() end
      elseif pfUI.uf and type(pfUI.uf[key]) == "table" and pfUI.uf[key].UpdateConfig then
        ufunc = function() return pfUI.uf[key]:UpdateConfig() end
      end
    end
    if ufunc then
      rawset(tab,key,ufunc)
      return ufunc
    end
  end})

  function Reload()
    CreateQuestionDialog(T["Some settings need to reload the UI to take effect.\nDo you want to reload now?"], function()
      pfUI.gui.settingChanged = nil
      ReloadUI()
    end)
  end

  -- [[ Pages ]]
  -- A list page shows settings that its build function adds; a frame page
  -- holds frames that its populate function makes. Each has an id, and sits
  -- in the navigation under its category, or is the category's own page.
  local pages, order, categories = {}, {}, {}

  -- the page in the window, and whether the search results show instead
  local current, searching

  -- the categories, with their pages under them
  local tree = CreateTreeDataProvider()

  -- the rows that CreateConfig made on frame pages, for the search
  local searchRows = {}

  -- [ Builder ]
  -- The methods that a list page's build function adds its settings with.
  -- An updater of nil means that a change takes a reload; nop means that the
  -- setting is read where it is used.
  local Builder = {}
  Builder.__index = Builder

  -- `opts` takes `min`, `max` and `step` (a number becomes a slider),
  -- `requires` (the key of a switch in the same table, "!key" for one that
  -- must be off) and `preview` ("font" or "texture", on a dropdown).
  local function AddSetting(self, setting, opts)
    for field, value in pairs(opts or {}) do setting[field] = value end
    table.insert(self.settings, setting)
  end

  local function Value(kind)
    return function(self, label, tbl, key, update, opts)
      AddSetting(self, { type = kind, label = label, table = tbl, key = key, update = update }, opts)
    end
  end

  Builder.Checkbox = Value("checkbox")
  Builder.Number = Value("number")
  Builder.Text = Value("text")
  Builder.Color = Value("color")
  Builder.List = Value("list")

  function Builder:Dropdown(label, tbl, key, values, update, opts)
    AddSetting(self, { type = "dropdown", label = label, table = tbl, key = key, values = values, update = update }, opts)
  end

  function Builder:Header(label)
    table.insert(self.settings, { type = "header", label = label })
  end

  function Builder:Spacer()
    table.insert(self.settings, { type = "spacer" })
  end

  -- each argument is a { label, onClick } pair
  function Builder:Buttons(...)
    table.insert(self.settings, { type = "buttons", buttons = { ... } })
  end

  -- The settings of a list page, built the first time they are needed. A
  -- variant page has a set for each variant: `variant` names one, else the
  -- one the page shows.
  local function GetSettings(page, variant)
    variant = variant or page.variant or ""
    page.settings = page.settings or {}
    if not page.settings[variant] then
      local p = setmetatable({ settings = {} }, Builder)
      page.build(p, page.variant and variant, page.variantLabels and page.variantLabels[variant])
      page.settings[variant] = p.settings

      -- the settings of a page with a module dim while it is disabled
      if page.module then
        for _, setting in ipairs(p.settings) do
          if setting.key then setting.module = page.module end
        end
      end
    end
    return page.settings[variant]
  end

  local function AddToNavigation(page, category, title)
    local entry = categories[category]
    if not entry then
      entry = { title = category, pages = {} }
      entry.node = tree:Insert(entry)
      entry.node:SetCollapsed(true)
      categories[category] = entry
    end

    page.category = entry
    if title then
      page.title = title
      page.node = entry.node:Insert(page)
      table.insert(entry.pages, page)
    else
      page.title = category
      entry.page = page
    end

    pages[page.id] = page
    table.insert(order, page)
  end

  -- [[ Window ]]
  pfUI.gui = CreateFrame("Frame", "pfConfigGUI", UIParent)
  pfUI.gui:SetMovable(true)
  pfUI.gui:EnableMouse(true)
  pfUI.gui:RegisterForDrag("LeftButton")
  pfUI.gui:SetWidth(720)
  pfUI.gui:SetHeight(480)
  pfUI.gui:SetFrameStrata("DIALOG")
  pfUI.gui:SetPoint("CENTER", 0, 0)
  pfUI.gui:Hide()

  pfUI.gui:SetScript("OnShow", function(self)
    -- a plugin may have set settingChanged since
    self:UpdateReloadBanner()

    -- exit unlock mode
    if pfUI.unlock and pfUI.unlock:IsShown() then
      pfUI.unlock:Hide()
    end

    -- exit hoverbind mode
    if pfUI.hoverbind and pfUI.hoverbind:IsShown() then
      pfUI.hoverbind:Hide()
    end

    if not current then
      self:OpenPage(order[1].id)
    end
  end)

  pfUI.gui:SetScript("OnHide", function(self)
    if ColorPickerFrame and ColorPickerFrame:IsShown() then
      ColorPickerFrame:Hide()
    end
  end)

  pfUI.gui:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)

  pfUI.gui:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
  end)

  CreateBackdrop(pfUI.gui, nil, true, .85)
  CreateBackdropShadow(pfUI.gui)
  table.insert(UISpecialFrames, "pfConfigGUI")

  -- The grip in the bottom right corner resizes the window, from its first
  -- size up to the screen's. The client's layout cache keeps the size, as it
  -- keeps the place the window was dragged to.
  -- The engine holds the bounds while sizing, so the corner stays under the
  -- cursor; the template's own check only puts a size back after the fact.
  pfUI.gui:SetResizable(true)
  pfUI.gui:SetClampedToScreen(true)
  pfUI.gui:SetResizeBounds(720, 480, GetScreenWidth(), GetScreenHeight())
  pfUI.gui.resize = CreateFrame("Button", nil, pfUI.gui, "PanelResizeButtonTemplate")
  pfUI.gui.resize:SetPoint("BOTTOMRIGHT", -3, 3)
  pfUI.gui.resize:Init(pfUI.gui, 720, 480, GetScreenWidth(), GetScreenHeight())

  -- decorations
  pfUI.gui.title = pfUI.gui:CreateFontString(nil, "ARTWORK", "GameFontWhite")
  pfUI.gui.title:SetPoint("TOPLEFT", pfUI.gui, "TOPLEFT", 8, -8)
  pfUI.gui.title:SetJustifyH("LEFT")
  pfUI.gui.title:SetFont(pfUI.media["font:Hooge.ttf"], 10)
  pfUI.gui.title:SetText("|cff33ffccpf|rUI")

  pfUI.gui.version = pfUI.gui:CreateFontString(nil, "ARTWORK", "GameFontWhite")
  pfUI.gui.version:SetPoint("LEFT", pfUI.gui.title, "RIGHT", 0, 0)
  pfUI.gui.version:SetJustifyH("LEFT")
  pfUI.gui.version:SetFont(pfUI.media["font:Myriad-Pro.ttf"], 10)
  pfUI.gui.version:SetText("|cff555555[|r" .. pfUI.version.string.. "|cff555555]|r")

  pfUI.gui.close = CreateFrame("Button", "pfQuestionDialogClose", pfUI.gui)
  pfUI.gui.close:SetPoint("TOPRIGHT", -7, -7)
  CreateBackdrop(pfUI.gui.close)
  pfUI.gui.close:SetHeight(10)
  pfUI.gui.close:SetWidth(10)
  pfUI.gui.close.texture = pfUI.gui.close:CreateTexture("pfQuestionDialogCloseTex")
  pfUI.gui.close.texture:SetTexture(pfUI.media["img:close"])
  pfUI.gui.close.texture:ClearAllPoints()
  pfUI.gui.close.texture:SetAllPoints(pfUI.gui.close)
  pfUI.gui.close.texture:SetVertexColor(1,.25,.25,1)

  pfUI.gui.close:SetScript("OnEnter", function(self)
    self.backdrop:SetBackdropBorderColor(1,.25,.25,1)
  end)

  pfUI.gui.close:SetScript("OnLeave", function(self)
    CreateBackdrop(self)
  end)

  pfUI.gui.close:SetScript("OnClick", function(self)
    self:GetParent():Hide()
  end)

  -- [ Reload banner ]
  -- The settings without an updater that changed since the UI loaded, with
  -- the value each had then. A setting that goes back to it drops out.
  local reloads, reloadCount = {}, 0
  local NOVALUE = {}

  local banner = CreateFrame("Frame", nil, pfUI.gui)
  banner:SetPoint("RIGHT", pfUI.gui.close, "LEFT", -10, 0)
  banner:SetHeight(16)
  banner:Hide()

  banner.button = CreateFrame("Button", nil, banner, "UIPanelButtonTemplate")
  banner.button:SetPoint("RIGHT", 0, 0)
  banner.button:SetSize(90, 16)
  banner.button:SetText(RELOADUI)
  banner.button:SetScript("OnClick", function() ReloadUI() end)
  SkinButton(banner.button)

  banner.text = banner:CreateFontString(nil, "ARTWORK", "GameFontWhite")
  banner.text:SetFont(pfUI.font_default, C.global.font_size)
  banner.text:SetPoint("RIGHT", banner.button, "LEFT", -8, 0)
  banner.text:SetTextColor(1,.67,.67,1)
  banner:SetWidth(400)

  function pfUI.gui:UpdateReloadBanner()
    -- a plugin that sets settingChanged counts as one more
    local count = reloadCount + (self.settingChanged and 1 or 0)
    banner.text:SetFormattedText(T["Changes that need a reload: %d"], count)
    banner:SetShown(count > 0)
  end

  -- Counts a change to tbl[key] that applies after a reload; `old` is the
  -- value before it.
  function pfUI.gui:NoteReload(tbl, key, old)
    reloads[tbl] = reloads[tbl] or {}
    local loaded = reloads[tbl][key]
    local value = tbl[key]

    if loaded == nil then
      reloads[tbl][key] = old == nil and NOVALUE or old
      reloadCount = reloadCount + 1
    elseif loaded == value or (loaded == NOVALUE and value == nil) then
      reloads[tbl][key] = nil
      reloadCount = reloadCount - 1
    end

    self:UpdateReloadBanner()
  end

  -- the navigation on the left and the open page right of it
  local body = CreateFrame("Frame", nil, pfUI.gui)
  body:SetPoint("TOPLEFT", 7, -25)
  body:SetPoint("BOTTOMRIGHT", -7, 37)
  CreateBackdrop(body)

  -- [ Navigation ]
  -- A category opens its own page or its first one, and shows the pages
  -- under it. The others close.
  local nav = CreateFrame("Frame", nil, body, "pfUIScrollBoxListTemplate")
  nav:SetPoint("TOPLEFT", 0, 0)
  nav:SetPoint("BOTTOMLEFT", 0, 0)
  nav:SetWidth(NAV_WIDTH)

  -- The open page and its category show in pfUI's color, a page whose
  -- module is disabled in grey.
  local function UpdateNavButton(button)
    local entry = button.node:GetData()
    local open = not searching and current
    local page = entry.pages and entry.page or entry
    local disabled = page and page.module and C.disabled[page.module] == "1"
    local alpha = disabled and .4 or 1

    if open and (entry == open or entry == open.category) then
      button.text:SetTextColor(.2,1,.8,alpha)
      button.bg:SetColorTexture(1,1,1,1)
      button.bg:SetGradientAlpha("HORIZONTAL", 0,0,0,0, 1,1,1,.05)
    else
      button.text:SetTextColor(1,1,1,alpha)
      button.bg:SetColorTexture(0,0,0,0)
    end
  end

  local function NavButtonOnMouseDown()
    pfUI.gui.search:ClearFocus()
  end

  local function NavButtonOnClick(button)
    local entry = button.node:GetData()
    local page = entry.pages and (entry.page or entry.pages[1]) or entry
    pfUI.gui:OpenPage(page.id)
  end

  local function InitNavButton(button, node)
    -- one-time setup of a pooled button
    if not button.text then
      button.bg = button:CreateTexture(nil, "BACKGROUND")
      button.bg:SetAllPoints()

      button.text = button:CreateFontString(nil, "ARTWORK", "GameFontWhite")
      button.text:SetFont(pfUI.font_default, C.global.font_size)
      button.text:SetPoint("LEFT", 8, 0)
      button.text:SetPoint("RIGHT", -4, 0)
      button.text:SetJustifyH("LEFT")

      button:SetScript("OnMouseDown", NavButtonOnMouseDown)
      button:SetScript("OnClick", NavButtonOnClick)
    end

    button.node = node
    button.text:SetText(node:GetData().title)
    UpdateNavButton(button)
  end

  local navView = CreateScrollBoxListTreeListView(10, 0, 0, 0, 0, 0)
  navView:SetElementExtent(20)
  navView:SetElementInitializer("Button", InitNavButton)
  ScrollUtil.InitScrollBoxListWithScrollBar(nav.ScrollBox, nav.ScrollBar, navView)
  nav.ScrollBox:SetDataProvider(tree)

  -- the open page, or the search results
  local content = CreateFrame("Frame", nil, body)
  content:SetPoint("TOPLEFT", nav, "TOPRIGHT", 0, 0)
  content:SetPoint("BOTTOMRIGHT", 0, 0)
  content.bg = content:CreateTexture(nil, "BACKGROUND")
  content.bg:SetColorTexture(1,1,1,.05)
  content.bg:SetAllPoints()

  -- [ List pages ]
  -- All list pages share one list, which keeps rows only for the settings
  -- in view.
  local list = CreateFrame("Frame", nil, content, "pfUIScrollBoxListTemplate")
  SetAllPointsOffset(list, content, 2)
  list:Hide()

  -- [ Preview ]
  -- A page with a preview shows it in a box above its list. The page's
  -- preview table has its `GetHeight(variant)`, `Show(box, variant)`, which draws it in
  -- the box, `Hide()`, which takes it out again when the page goes,
  -- `Refresh()`, which draws it again after a change, and `parts`, which
  -- lead to their settings (see Preview parts).
  local previewBox = CreateFrame("Frame", nil, content)
  previewBox:SetPoint("TOPLEFT", 2, -2)
  previewBox:SetPoint("TOPRIGHT", -2, -2)
  previewBox:Hide()

  previewBox.bg = previewBox:CreateTexture(nil, "BACKGROUND")
  previewBox.bg:SetAllPoints()
  previewBox.bg:SetColorTexture(0, 0, 0, .35)

  previewBox.line = previewBox:CreateTexture(nil, "BORDER")
  previewBox.line:SetPoint("BOTTOMLEFT")
  previewBox.line:SetPoint("BOTTOMRIGHT")
  previewBox.line:SetHeight(1)
  previewBox.line:SetColorTexture(.2, 1, .8, .5)

  -- the list fills the content, or the room under the preview
  local function PlaceList(preview, variant)
    list:ClearAllPoints()
    if preview then
      previewBox:SetHeight(preview.GetHeight(variant))
      previewBox:Show()
      list:SetPoint("TOPLEFT", previewBox, "BOTTOMLEFT", 0, -2)
      list:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -2, 2)
    else
      previewBox:Hide()
      SetAllPointsOffset(list, content, 2)
    end
  end

  -- the settings that the last search result pointed at, as keys, and the
  -- rows on a frame page that it pointed at
  local highlighted, highlightedFrames = {}, {}

  local function StopFlash(group)
    group.flashes = group.flashes - 1
    if group.flashes <= 0 then group:Stop() end
  end

  local function SetHighlight(row, shown)
    if shown and not row.highlight then
      row.highlight = row:CreateTexture(nil, "OVERLAY")
      row.highlight:SetAllPoints()
      row.highlight:SetColorTexture(.2,1,.8,.2)

      -- a few blinks when a search result jumps to the row
      row.flash = row.highlight:CreateAnimationGroup()
      row.flash:SetLooping("BOUNCE")
      row.flash:SetScript("OnLoop", StopFlash)
      local fade = row.flash:CreateAnimation("Alpha")
      fade:SetFromAlpha(1)
      fade:SetToAlpha(0)
      fade:SetDuration(.25)
    end

    if row.highlight then
      row.highlight:SetShown(shown)
      if not shown then row.flash:Stop() end
    end
  end

  local function Flash(row)
    SetHighlight(row, true)
    row.flash.flashes = 6
    row.flash:Stop()
    row.flash:Play()
  end

  local function ClearHighlights()
    table.wipe(highlighted)
    for _, frame in ipairs(highlightedFrames) do
      SetHighlight(frame, false)
    end
    table.wipe(highlightedFrames)
  end

  local function InitRow(row, setting)
    row:Init(setting)
    SetHighlight(row, highlighted[setting] or false)
  end

  local listView = CreateScrollBoxListLinearView(0, 5, 0, 3, 1)
  listView:SetElementFactory(function(factory, setting)
    if setting.type == "number" and setting.min then
      factory("pfUIConfigSliderRowTemplate", InitRow)
    elseif templates[setting.type] then
      factory(templates[setting.type], InitRow)
    else
      factory("Frame", nop) -- a spacer
    end
  end)

  listView:SetElementExtentCalculator(function(index, setting)
    return extents[setting.type] or 22
  end)

  -- a row that scrolls out of view lets go of the cursor and the keyboard
  listView:SetElementResetter(function(row)
    if row.tex then row.tex:Hide() end
    if row.flash then row.flash:Stop() end
    if row.input and row.input.ClearFocus then row.input:ClearFocus() end
  end)

  ScrollUtil.InitScrollBoxListWithScrollBar(list.ScrollBox, list.ScrollBar, listView)

  -- An open dropdown would set the setting that its row shows next, so the
  -- menus close when the rows move. OnScroll also fires on every layout pass
  -- of the list, one of which can come while a dropdown opens its menu, and
  -- closing it then pulls the menu from under the dropdown (issue #86).
  local scrollOffset
  list.ScrollBox:RegisterCallback(BaseScrollBoxEvents.OnScroll, function()
    local offset = list.ScrollBox:GetDerivedScrollOffset()
    if offset == scrollOffset then return end
    scrollOffset = offset
    Menu.GetManager():CloseMenus()
  end, list)

  -- A change can show on other rows: in the entries a dropdown offers, or
  -- in a value that the change's updater set as well.
  pfUI.events:RegisterCallback("config:changed", function(_, tbl, key)
    -- the rows on the frame pages keep their default marks right as well
    for _, entry in ipairs(searchRows) do
      if entry.frame.UpdateState then entry.frame:UpdateState() end
    end

    -- a module switched on or off greys its pages in the navigation
    if tbl == C.disabled then
      nav.ScrollBox:ForEachFrame(UpdateNavButton)
    end

    -- the preview draws every change, its page's own and the general ones
    if previewBox:IsVisible() and current and current.preview then
      current.preview.Refresh()
    end

    if not list:IsVisible() then return end

    list.ScrollBox:ForEachFrame(function(row)
      local setting = row.setting
      -- the row that made the change shows it already
      if setting and row.Refresh and (setting.table ~= tbl or setting.key ~= key) then
        row:Refresh()
      end
      if row.UpdateState then row:UpdateState() end
    end)
  end)

  -- [ Opening pages ]
  -- hides the open page or the search results
  local function HideContent()
    if current and current.build and list:IsShown() and not searching then
      current.scroll = list.ScrollBox:GetScrollPercentage()
    end

    list:Hide()
    previewBox:Hide()
    if current and current.preview then current.preview.Hide() end

    if current and current.frame then
      current.frame:Hide()
    end
  end

  -- The switch of a page's module, named after its category, or after the
  -- page where the category's pages switch different modules.
  local function GetModuleSwitch(page)
    if not page.switch then
      local name = page.category.title
      for _, other in ipairs(page.category.pages) do
        if other.module and other.module ~= page.module then name = page.title end
      end

      -- the disabled list holds "1" for a module that is off
      pfUI:UpdateConfig("disabled", nil, page.module, "0")
      page.switch = { type = "checkbox", label = T["Enable"] .. " " .. name, table = C.disabled, key = page.module, invert = true }
    end
    return page.switch
  end

  local function ShowListPage(page)
    PlaceList(page.preview, page.variant)
    if page.preview then page.preview.Show(previewBox, page.variant) end
    list:Show()

    -- a variant page leads with its picker, a page with a module with its
    -- switch
    local variant = page.variant or ""
    page.providers = page.providers or {}
    if not page.providers[variant] then
      local rows = {}
      if page.variant then
        table.insert(rows, page.picker)
      end
      if page.module then
        table.insert(rows, GetModuleSwitch(page))
      end
      for _, setting in ipairs(GetSettings(page)) do
        table.insert(rows, setting)
      end
      page.providers[variant] = CreateDataProvider(rows)
    end

    list.ScrollBox:SetDataProvider(page.providers[variant])
    list.ScrollBox:SetScrollPercentage(page.scroll or 0, ScrollBoxConstants.NoScrollInterpolation)
  end

  local function ShowFramePage(page)
    if not page.frame then
      -- hidden until the Show below, which runs the content's OnShow
      page.frame = CreateFrame("Frame", nil, content)
      page.frame:SetAllPoints()
      page.frame:Hide()

      if page.populate then
        local scroll = CreateFrame("ScrollFrame", nil, page.frame, "pfUIScrollFrameTemplate")
        SetAllPointsOffset(scroll, page.frame, 2)
        page.frame.scroll = scroll

        local inner = scroll.Content
        inner.page = page
        -- the names that plugins knew the scroll frame and content by
        scroll.content = inner
        inner.parent = scroll

        -- the page fills itself the first time it shows, with `this` as
        -- its content
        inner:SetScript("OnShow", function()
          if inner.setup then return end
          inner.setup = true
          page.populate()
          scroll:UpdateScrollChildRect()
        end)
      end
    end

    page.frame:Show()
  end

  -- Opens a page by its id, in the window, and shows the window. A variant
  -- page shows `variant` if given, else the one it showed last.
  function pfUI.gui:OpenPage(id, variant)
    local page = pages[id]
    if not page then return end

    HideContent()
    searching = nil
    current = page

    if page.variant and variant and variant ~= page.variant then
      page.variant = variant
      page.scroll = 0
    end

    if page.build then
      ShowListPage(page)
    else
      ShowFramePage(page)
    end

    -- show the pages of the page's category only
    for _, entry in pairs(categories) do
      entry.node:SetCollapsed(entry ~= page.category, false, true)
    end
    tree:Invalidate()
    nav.ScrollBox:ForEachFrame(UpdateNavButton)
    nav.ScrollBox:ScrollToElementData(page.node or page.category.node, ScrollBoxConstants.AlignNearest)

    self:Show()
  end

  -- Adds a list page. `build(p)` adds its settings with the methods of
  -- Builder, the first time the page is needed. `opts` may hold `module`,
  -- a pfUI module the page leads with a switch for, and `preview` (see the
  -- preview box).
  function pfUI.gui:AddPage(id, category, title, build, opts)
    if pages[id] then return end
    opts = opts or {}
    AddToNavigation({ id = id, build = build, module = opts.module, preview = opts.preview }, category, title)
  end

  -- Copies the settings that a variant page shows from one variant to
  -- another: the keys of the variant's own table that both show. Each
  -- updater they name runs once afterwards.
  local function CopyVariant(page, from, to)
    local source, target = page.tableOf(from), page.tableOf(to)

    local shown = {}
    for _, setting in ipairs(GetSettings(page, from)) do
      if setting.table == source and setting.key then shown[setting.key] = true end
    end

    local updates = {}
    for _, setting in ipairs(GetSettings(page, to)) do
      local key = setting.key
      if setting.table == target and shown[key] and target[key] ~= source[key] then
        local old = target[key]
        target[key] = source[key]
        if setting.update then
          updates[setting.update] = true
        else
          pfUI.gui:NoteReload(target, key, old)
        end
      end
    end

    for update in pairs(updates) do update() end
    pfUI.events:TriggerEvent("config:changed", target)
  end

  -- Adds a list page that shows one of several variants of the same
  -- settings, picked at its top. `variants` holds { key, label } pairs,
  -- `tableOf(key)` returns the config table of a variant, and
  -- `build(p, key, label)` adds the settings of one. `opts` as in AddPage.
  function pfUI.gui:AddVariantPage(id, category, title, variants, tableOf, build, opts)
    if pages[id] then return end

    opts = opts or {}
    local page = { id = id, build = build, module = opts.module, preview = opts.preview,
      tableOf = tableOf, variant = variants[1][1], variantLabels = {} }
    local values = {}
    for _, entry in ipairs(variants) do
      page.variantLabels[entry[1]] = entry[2]
      table.insert(values, entry[1] .. ":" .. entry[2])
    end
    page.variants = variants

    -- The picker writes page.variant; the list changes once its menu closed.
    -- Its Copy From button offers the other variants.
    page.picker = { type = "picker", label = title, table = page, key = "variant", values = values }

    function page.picker.update()
      page.scroll = 0
      RunNextFrame(function()
        if current == page and not searching then ShowListPage(page) end
      end)
    end

    function page.picker.copy(button)
      button.menuMixin = pfUIMenuStyleMixin
      MenuUtil.CreateContextMenu(button, function(_, rootDescription)
        for _, entry in ipairs(variants) do
          if entry[1] ~= page.variant then
            rootDescription:CreateButton(entry[2], function() CopyVariant(page, entry[1], page.variant) end)
          end
        end
      end)
    end

    AddToNavigation(page, category, title)
  end

  -- Adds a frame page. `populate` makes its frames the first time it shows,
  -- with `this` as the page's content.
  function pfUI.gui:AddFramePage(id, category, title, populate)
    if pages[id] then return end
    AddToNavigation({ id = id, populate = populate }, category, title)
  end

  -- Adds a frame page for a thirdparty addon, which calls this as
  -- pfUI.gui.CreateGUIEntry. Without a title, the page is the category's
  -- own, and a category that is there already takes none.
  function CreateGUIEntry(category, title, populate)
    if not title and categories[category] then return end
    pfUI.gui:AddFramePage(category .. "/" .. (title or ""), category, title, populate)
  end

  -- Adds a row to the frame page that `this` holds, one line below the row
  -- before it. A button with `skip` goes left of the button before it, on
  -- the same line. Thirdparty addons call this as pfUI.gui.CreateConfig.
  function CreateConfig(ufunc, caption, category, config, widget, values, skip, named, type)
    -- this object placement
    if this.objectCount == nil then
      this.objectCount = 0
    elseif not skip then
      this.objectCount = this.objectCount + 1
      this.lineCount = 1
    end

    if skip then
      this.lineCount = (this.lineCount or 1) + 1
    end

    if not caption then return end

    widget = widget or "text"

    -- the setting that the row shows
    local store = stores[category]
    local setting = {
      type = widget,
      label = caption,
      table = store or category,
      key = config,
      values = values,
      -- a store applies what is written to it
      update = store and (ufunc or nop) or ufunc,
    }

    if widget == "text" then
      setting.type = (type and type ~= "number") and "text" or "number"
    elseif widget == "button" then
      setting.type = "buttons"
      setting.buttons = { { caption, values } }
    end

    local y = this.objectCount * -23 - 5
    local frame = CreateFrame("Frame", nil, this, templates[setting.type] or "pfUIConfigRowTemplate")
    frame:SetPoint("TOPLEFT", this, "TOPLEFT", 5, y)
    frame:SetPoint("TOPRIGHT", this, "TOPRIGHT", -15, y)
    frame:Init(setting)

    -- the fields that the rows had before they had templates
    frame.category = setting.table
    frame.config = config

    if widget == "button" then
      frame.button:ClearAllPoints()
      frame.button:SetPoint("TOPRIGHT", -((this.lineCount or 1) - 1) * 105, -5)
    elseif widget == "header" then
      this.objectCount = this.objectCount + 1
    elseif widget == "warning" then
      y = this.objectCount * -35
      frame:SetPoint("TOPLEFT", this, "TOPLEFT", 25, y)
      frame:SetPoint("TOPRIGHT", this, "TOPRIGHT", 5, y)
      this.objectCount = this.objectCount + 2
    end

    -- the search finds the row on its page
    if this.page and widget ~= "button" and widget ~= "header" then
      table.insert(searchRows, { page = this.page, label = caption, frame = frame })
    end

    return frame
  end

  -- [ Search ]
  -- Results show in the page list: under a breadcrumb for each page, the
  -- settings of a list page as live rows, and the rows of a frame page as
  -- links. A breadcrumb or a link opens the page and marks its results.

  -- opens the page of a breadcrumb or a link and flashes the rows it names
  local function PointAt(result)
    pfUI.gui.search:ClearFocus()
    ClearHighlights()
    pfUI.gui:OpenPage(result.page.id, result.variant)

    if result.settings then
      for _, setting in ipairs(result.settings) do
        highlighted[setting] = true
      end
      list.ScrollBox:ScrollToElementData(result.settings[1], ScrollBoxConstants.AlignCenter)
      list.ScrollBox:ForEachFrame(function(row)
        if highlighted[row.setting] then Flash(row) end
      end)
    else
      for _, frame in ipairs(result.frames) do
        table.insert(highlightedFrames, frame)
        Flash(frame)
      end
    end
  end

  -- [ Preview parts ]
  -- Pointing at a part of a preview outlines it, and clicking it leads to its
  -- settings on the open page. A preview lists its parts, topmost first, in
  -- `parts`: { region, target }, where the target is either `section`, the
  -- label of a header whose rows it means, or `keys`, a list of setting keys.
  local function TargetSettings(target)
    local found = {}
    local inside
    for _, setting in ipairs(GetSettings(current)) do
      if setting.type == "header" then
        inside = setting.label == target.section
        if inside then table.insert(found, setting) end
      elseif inside and setting.key then
        table.insert(found, setting)
      elseif target.keys and setting.key then
        for _, key in ipairs(target.keys) do
          if setting.key == key then table.insert(found, setting) end
        end
      end
    end
    return found
  end

  local function ShowTarget(target)
    local found = TargetSettings(target)
    if not found[1] then return end

    ClearHighlights()
    for _, setting in ipairs(found) do
      highlighted[setting] = true
    end
    list.ScrollBox:ScrollToElementData(found[1], ScrollBoxConstants.AlignBegin)
    list.ScrollBox:ForEachFrame(function(row)
      if highlighted[row.setting] then Flash(row) end
    end)
  end

  -- above the preview, under any controls a preview puts above it
  local picker = CreateFrame("Frame", nil, previewBox)
  picker:SetAllPoints()
  picker:SetFrameLevel(previewBox:GetFrameLevel() + 40)
  picker:EnableMouse(true)

  picker.outline = CreateFrame("Frame", nil, picker)
  picker.outline:SetFrameLevel(picker:GetFrameLevel() + 1)
  picker.outline:SetBackdrop({ edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1 })
  picker.outline:SetBackdropBorderColor(.2, 1, .8, 1)
  picker.outline:Hide()

  local function PartUnderMouse()
    local parts = current and current.preview and current.preview.parts
    if not parts then return end
    for _, part in ipairs(parts) do
      local region = part[1]
      if region:IsVisible() and region:IsMouseOver() then return part end
    end
  end

  local function UpdatePicker()
    local part = PartUnderMouse()
    if part == this.part then return end
    this.part = part
    if part then
      this.outline:ClearAllPoints()
      this.outline:SetPoint("TOPLEFT", part[1], "TOPLEFT", -1, 1)
      this.outline:SetPoint("BOTTOMRIGHT", part[1], "BOTTOMRIGHT", 1, -1)
      this.outline:Show()
    else
      this.outline:Hide()
    end
  end

  picker:SetScript("OnEnter", function()
    this:SetScript("OnUpdate", UpdatePicker)
  end)

  picker:SetScript("OnLeave", function()
    this:SetScript("OnUpdate", nil)
    this.part = nil
    this.outline:Hide()
  end)

  picker:SetScript("OnMouseUp", function()
    if this.part then ShowTarget(this.part[2]) end
  end)

  -- "Category » Page", and » Variant on a variant page
  local function Breadcrumb(page, variant)
    local path = "|cff33ffcc" .. page.category.title
    if page.title ~= page.category.title then
      path = path .. "|r » |cff33ffcc" .. page.title
    end
    if variant then
      path = path .. "|r » |cff33ffcc" .. page.variantLabels[variant]
    end
    return path .. "|r"
  end

  local function Matches(text, label, key)
    return (label and label:lower():find(text, 1, true))
      or (type(key) == "string" and key:lower():find(text, 1, true))
  end

  -- the results of the settings whose label or key has the text in it:
  -- those of every list page, and the rows of the frame pages built so far
  local function Search(text)
    local found = {}
    text = text:lower()

    -- the matching settings of a list page, or of one of its variants
    local function SearchSettings(page, variant)
      local crumb = { type = "breadcrumb", page = page, variant = variant, label = Breadcrumb(page, variant), onClick = PointAt }
      crumb.settings = {}
      for _, setting in ipairs(GetSettings(page, variant)) do
        if setting.key and Matches(text, setting.label, setting.key) then
          table.insert(crumb.settings, setting)
        end
      end
      if crumb.settings[1] then
        table.insert(found, crumb)
        for _, setting in ipairs(crumb.settings) do
          table.insert(found, setting)
        end
      end
    end

    for _, page in ipairs(order) do
      if page.variants then
        for _, entry in ipairs(page.variants) do
          SearchSettings(page, entry[1])
        end
      elseif page.build then
        SearchSettings(page)
      else
        local crumb = { type = "breadcrumb", page = page, label = Breadcrumb(page), onClick = PointAt }
        crumb.frames = {}
        local links = {}
        for _, row in ipairs(searchRows) do
          if row.page == page and Matches(text, row.label, row.frame.config) then
            table.insert(crumb.frames, row.frame)
            table.insert(links, { type = "link", page = page, label = row.label, frames = { row.frame }, onClick = PointAt })
          end
        end
        if links[1] then
          table.insert(found, crumb)
          for _, link in ipairs(links) do
            table.insert(found, link)
          end
        end
      end
    end

    return found
  end

  local function ShowResults(found)
    HideContent()
    searching = true
    PlaceList(nil)
    list:Show()
    list.ScrollBox:SetDataProvider(CreateDataProvider(found))
    nav.ScrollBox:ForEachFrame(UpdateNavButton)
  end

  -- builds the frame pages, so the search finds their rows
  local function BuildFramePages()
    for _, page in ipairs(order) do
      if page.populate and not page.frame then
        ShowFramePage(page)
        page.frame:Hide()
      end
    end
  end

  -- [ Buttons ]
  pfUI.gui.unlock = CreateFrame("Button", nil, pfUI.gui)
  pfUI.gui.unlock:SetPoint("TOPLEFT", body.backdrop, "BOTTOMLEFT", 0, -5)
  pfUI.gui.unlock:SetWidth(110)
  pfUI.gui.unlock:SetHeight(25)
  pfUI.gui.unlock:SetText(T["Unlock"])
  pfUI.gui.unlock:SetScript("OnClick", function()
    if pfUI.unlock then pfUI.unlock:Show() end
  end)
  SkinButton(pfUI.gui.unlock)

  pfUI.gui.hoverbind = CreateFrame("Button", nil, pfUI.gui)
  pfUI.gui.hoverbind:SetPoint("LEFT", pfUI.gui.unlock, "RIGHT", 5, 0)
  pfUI.gui.hoverbind:SetWidth(110)
  pfUI.gui.hoverbind:SetHeight(25)
  pfUI.gui.hoverbind:SetText(T["Hoverbind"])
  pfUI.gui.hoverbind:SetScript("OnClick", function()
    if pfUI.hoverbind then
      pfUI.hoverbind:Show()
    else
      message(T["Please enable the Hoverbind module to use this feature."])
    end
  end)
  SkinButton(pfUI.gui.hoverbind)

  pfUI.gui.share = CreateFrame("Button", nil, pfUI.gui)
  pfUI.gui.share:SetPoint("LEFT", pfUI.gui.hoverbind, "RIGHT", 5, 0)
  pfUI.gui.share:SetWidth(110)
  pfUI.gui.share:SetHeight(25)
  pfUI.gui.share:SetText(T["Share"])
  pfUI.gui.share:SetScript("OnClick", function()
    if pfShare then
      pfShare:Show()
      pfShareExport:Click()
    else
      message(T["Please enable the Share module to share your config."])
    end
  end)
  SkinButton(pfUI.gui.share)

  -- the box shows SEARCH while empty and clears with its X; Escape and Enter
  -- leave it
  pfUI.gui.search = CreateFrame("EditBox", "pfConfigGUISearch", pfUI.gui, "ClassicAPISearchBoxTemplate")
  pfUI.gui.search:SetPoint("LEFT", pfUI.gui.share, "RIGHT", 7, 0)
  -- right of it is the resize grip
  pfUI.gui.search:SetPoint("TOPRIGHT", body.backdrop, "BOTTOMRIGHT", -18, -5)
  pfUI.gui.search:SetHeight(25)
  StripTextures(pfUI.gui.search, nil, "BACKGROUND")
  CreateBackdrop(pfUI.gui.search, nil, true)

  pfUI.gui.search:HookScript("OnEditFocusGained", function(self)
    if not self.indexed then
      BuildFramePages()
      self.indexed = true
    end
  end)

  pfUI.gui.search:HookScript("OnTextChanged", function(self)
    local text = self:GetText()
    ClearHighlights()

    if text ~= "" then
      ShowResults(Search(text))
    elseif searching and current then
      pfUI.gui:OpenPage(current.id)
    end
  end)

  -- make some locals available to thirdparty
  pfUI.gui.Reload = Reload
  pfUI.gui.CreateConfig = CreateConfig
  pfUI.gui.CreateGUIEntry = CreateGUIEntry
  pfUI.gui.UpdaterFunctions = U

  -- the dropdown entries and the built-in pages (gui_pages.lua)
  pfUI.AddConfigPages(pfUI.gui, U, stores.CVAR, stores.UVAR)
end)
