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
  }

  -- the height of the rows on a list page that are not 22 high
  local extents = {
    header  = 45,
    warning = 50,
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

  local function Value(kind)
    return function(self, label, tbl, key, update)
      table.insert(self.settings, { type = kind, label = label, table = tbl, key = key, update = update })
    end
  end

  Builder.Checkbox = Value("checkbox")
  Builder.Number = Value("number")
  Builder.Text = Value("text")
  Builder.Color = Value("color")
  Builder.List = Value("list")

  function Builder:Dropdown(label, tbl, key, values, update)
    table.insert(self.settings, { type = "dropdown", label = label, table = tbl, key = key, values = values, update = update })
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

  -- the settings of a list page, built the first time they are needed
  local function GetSettings(page)
    if not page.settings then
      local p = setmetatable({ settings = {} }, Builder)
      page.build(p)
      page.settings = p.settings
    end
    return page.settings
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
    -- the reload question counts the changes since the window opened
    self.settingChanged = nil

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

    if self.settingChanged then
      self:Reload()
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

  -- the open page and its category show in pfUI's color
  local function UpdateNavButton(button)
    local entry = button.node:GetData()
    local open = not searching and current
    if open and (entry == open or entry == open.category) then
      button.text:SetTextColor(.2,1,.8,1)
      button.bg:SetColorTexture(1,1,1,1)
      button.bg:SetGradientAlpha("HORIZONTAL", 0,0,0,0, 1,1,1,.05)
    else
      button.text:SetTextColor(1,1,1,1)
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

  -- the setting that the last search result pointed at
  local highlighted

  local function SetHighlight(row, shown)
    if shown and not row.highlight then
      row.highlight = row:CreateTexture(nil, "OVERLAY")
      row.highlight:SetAllPoints()
      row.highlight:SetColorTexture(.2,1,.8,.2)
    end

    if row.highlight then
      row.highlight:SetShown(shown)
    end
  end

  local function InitRow(row, setting)
    row:Init(setting)
    SetHighlight(row, setting == highlighted)
  end

  local listView = CreateScrollBoxListLinearView(0, 5, 0, 3, 1)
  listView:SetElementFactory(function(factory, setting)
    if templates[setting.type] then
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
    if row.input and row.input.ClearFocus then row.input:ClearFocus() end
  end)

  ScrollUtil.InitScrollBoxListWithScrollBar(list.ScrollBox, list.ScrollBar, listView)

  -- an open dropdown would set the setting that its row shows next
  list.ScrollBox:RegisterCallback(BaseScrollBoxEvents.OnScroll, function()
    Menu.GetManager():CloseMenus()
  end, list)

  -- A change can show on other rows: in the entries a dropdown offers, or
  -- in a value that the change's updater set as well.
  pfUI.events:RegisterCallback("config:changed", function(_, tbl, key)
    if not list:IsVisible() then return end

    list.ScrollBox:ForEachFrame(function(row)
      local setting = row.setting
      -- the row that made the change shows it already
      if setting and row.Refresh and (setting.table ~= tbl or setting.key ~= key) then
        row:Refresh()
      end
    end)
  end)

  -- [ Search results ]
  local results = CreateFrame("Frame", nil, content, "pfUIScrollBoxListTemplate")
  SetAllPointsOffset(results, content, 2)
  results:Hide()

  -- the frame-page row that the last search result pointed at
  local highlightedFrame

  -- opens the page of a search result and marks the result's row
  local function PointAt(result)
    pfUI.gui:OpenPage(result.page.id)

    if highlightedFrame then
      SetHighlight(highlightedFrame, false)
      highlightedFrame = nil
    end

    if result.setting then
      highlighted = result.setting
      list.ScrollBox:ScrollToElementData(highlighted, ScrollBoxConstants.AlignCenter)
      list.ScrollBox:ForEachFrame(function(row)
        SetHighlight(row, row.setting == highlighted)
      end)
    else
      highlightedFrame = result.frame
      SetHighlight(highlightedFrame, true)
    end
  end

  local function SearchResultOnClick(button)
    pfUI.gui.search:ClearFocus()
    PointAt(button.result)
  end

  local function SearchResultOnEnter(button)
    button.tex:Show()
  end

  local function SearchResultOnLeave(button)
    button.tex:Hide()
  end

  local function InitSearchResult(button, result)
    -- one-time setup of a pooled row
    if not button.text then
      button:SetScript("OnClick", SearchResultOnClick)
      button:SetScript("OnEnter", SearchResultOnEnter)
      button:SetScript("OnLeave", SearchResultOnLeave)

      button.text = button:CreateFontString(nil, "ARTWORK", "GameFontWhite")
      button.text:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
      button.text:SetAllPoints()
      button.text:SetJustifyH("LEFT")

      button.tex = button:CreateTexture(nil, "BACKGROUND")
      button.tex:SetColorTexture(1,1,1,.05)
      button.tex:SetAllPoints()
      button.tex:Hide()
    end

    button.result = result

    -- the categories and the page, then the setting
    local page = result.page
    local path = "|cff33ffcc" .. page.category.title .. "|r » "
    if page.title ~= page.category.title then
      path = path .. "|cff33ffcc" .. page.title .. "|r » "
    end
    button.text:SetText(path .. "|cffffffff" .. result.label)
  end

  local resultsView = CreateScrollBoxListLinearView(0, 0, 0, 0, 5)
  resultsView:SetElementExtent(20)
  resultsView:SetElementInitializer("Button", InitSearchResult)
  ScrollUtil.InitScrollBoxListWithScrollBar(results.ScrollBox, results.ScrollBar, resultsView)

  -- [ Opening pages ]
  -- hides the open page or the search results
  local function HideContent()
    if current and current.build and list:IsShown() then
      current.scroll = list.ScrollBox:GetScrollPercentage()
    end

    list:Hide()
    results:Hide()

    if current and current.frame then
      current.frame:Hide()
    end
  end

  local function ShowListPage(page)
    list:Show()
    page.provider = page.provider or CreateDataProvider(GetSettings(page))
    list.ScrollBox:SetDataProvider(page.provider)
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

  -- Opens a page by its id, in the window, and shows the window.
  function pfUI.gui:OpenPage(id)
    local page = pages[id]
    if not page then return end

    HideContent()
    searching = nil
    current = page

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
  -- Builder, the first time the page is needed.
  function pfUI.gui:AddPage(id, category, title, build)
    if pages[id] then return end
    AddToNavigation({ id = id, build = build }, category, title)
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
  -- the settings whose label has the text in it: those of every list page,
  -- then the rows on the frame pages that have been built
  local function Search(text)
    local found = {}
    text = text:lower()

    for _, page in ipairs(order) do
      if page.build then
        for _, setting in ipairs(GetSettings(page)) do
          if setting.label and setting.type ~= "header" and setting.label:lower():find(text, 1, true) then
            table.insert(found, { page = page, label = setting.label, setting = setting })
          end
        end
      end
    end

    for _, row in ipairs(searchRows) do
      if row.label:lower():find(text, 1, true) then
        table.insert(found, row)
      end
    end

    return found
  end

  local function ShowResults(found)
    HideContent()
    searching = true
    results:Show()
    results.ScrollBox:SetDataProvider(CreateDataProvider(found))
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

  pfUI.gui.search = CreateFrame("EditBox", nil, pfUI.gui)
  pfUI.gui.search:SetPoint("LEFT", pfUI.gui.share, "RIGHT", 5, 0)
  pfUI.gui.search:SetPoint("TOPRIGHT", body.backdrop, "BOTTOMRIGHT", 0, -5)
  pfUI.gui.search:SetHeight(25)
  pfUI.gui.search:SetAutoFocus(false)
  pfUI.gui.search:SetTextInsets(5, 5, 5, 5)
  pfUI.gui.search:SetTextColor(.2,1,.8,1)
  pfUI.gui.search:SetJustifyH("CENTER")
  pfUI.gui.search:SetFontObject(GameFontNormal)
  pfUI.gui.search:SetText(SEARCH .. "...")
  CreateBackdrop(pfUI.gui.search, nil, true)

  pfUI.gui.search:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    if self:GetText() == "" then
      self:SetText(SEARCH .. "...")
    end
  end)

  pfUI.gui.search:SetScript("OnEditFocusGained", function(self)
    if not self.indexed then
      BuildFramePages()
      self.indexed = true
    end

    if self:GetText() == SEARCH .. "..." then
      self:SetText("")
    end
  end)

  pfUI.gui.search:SetScript("OnTextChanged", function(self)
    local text = self:GetText()
    if text == SEARCH .. "..." then return end

    highlighted = nil
    if highlightedFrame then
      SetHighlight(highlightedFrame, false)
      highlightedFrame = nil
    end

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
