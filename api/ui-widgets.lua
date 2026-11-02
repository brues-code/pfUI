-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

do -- statusbars
  -- native StatusBar methods the bar overrides
  local statusbar = CreateFrame("StatusBar")
  local SetValue, SetMinMaxValues = statusbar.SetValue, statusbar.SetMinMaxValues
  local SetOrientation, SetFrameLevel = statusbar.SetOrientation, statusbar.SetFrameLevel

  -- SmoothStatusBarMixin animates the bar through SetValue, so this is the
  -- shown value; SetSmoothedValue sets the target
  local handlers = {
    ["SetValue"] = function(self, val)
      local smin, smax = self:GetMinMaxValues()
      val = Clamp(val, smin, smax)
      SetValue(self, val)

      -- the background fills the missing part, all of an empty range
      self.bg:SetValue(smax > smin and (smax - val) / (smax - smin) or 1)
    end,

    -- the fill keeps its share of the bar, so a new range doesn't make it
    -- jump before the smoothed value moves on from there
    ["SetMinMaxValues"] = function(self, smin, smax)
      local oldmin, oldmax = self:GetMinMaxValues()
      local share = oldmax > oldmin and (self:GetValue() - oldmin) / (oldmax - oldmin) or 0
      SetMinMaxValues(self, smin, smax)
      self:SetValue(smin + share * (smax - smin))
    end,

    ["SetStatusBarBackgroundColor"] = function(self, r, g, b, a)
      self.bg:SetColorFill(r, g, b, a)
    end,

    ["SetOrientation"] = function(self, orientation)
      SetOrientation(self, orientation)
      self.bg:SetOrientation(orientation)
    end,

    -- the background stays one level below the fill, under anything else
    -- drawn on the fill's frame
    ["SetFrameLevel"] = function(self, level)
      SetFrameLevel(self, level)
      self.bg:SetFrameLevel(level - 1)
    end,
  }

  function pfUI.api.CreateStatusBar(name, parent)
    local f = CreateFrame("StatusBar", name, parent)
    SetMinMaxValues(f, 0, 100)
    SetValue(f, 0)

    f.bg = CreateFrame("StatusBar", nil, f)
    f.bg:SetFrameLevel(f:GetFrameLevel() - 1)
    f.bg:SetAllPoints(f)
    f.bg:SetReverseFill(true)
    f.bg:SetMinMaxValues(0, 1)
    f.bg:SetValue(1)

    return Mixin(f, SmoothStatusBarMixin, handlers)
  end
end

-- [ pfUIMenuStyleMixin ]
-- Style for ClassicAPI's menus: pfUI's backdrop behind the entries. A dropdown
-- takes it as its menuMixin, and a context menu takes it from the menuMixin
-- field of its owner.
_G.pfUIMenuStyleMixin = CreateFromMixins(MenuStyleMixin)

-- Menus share pooled frames that clear their backdrop on release, so the
-- backdrop goes on the frame itself.
function pfUIMenuStyleMixin:Generate()
  CreateBackdrop(self, nil, true)
end

do
  local inset = { left = 4, top = 4, right = 4, bottom = 4 }
  function pfUIMenuStyleMixin:GetInset()
    return inset
  end

  -- room for a submenu arrow or a color swatch, as in the stock styles
  local padding = { width = 10, height = 0 }
  function pfUIMenuStyleMixin:GetChildExtentPadding()
    return padding
  end
end

-- [ CreateMenuDivider ]
-- Adds a divider to a pfUIMenuStyleMixin menu: a 1px line in the border
-- color in place of the stock divider art. The style itself cannot do this,
-- as menu entries draw their own art.
-- 'description'  [table]   the menu description to add the divider to
-- returns:       [table]   the divider's element description
do
  local function SkinDivider(frame)
    frame.divider:SetHeight(1)
    frame.divider:SetColorTexture(GetStringColor(pfUI_config.appearance.border.color))
  end

  function pfUI.api.CreateMenuDivider(description)
    local divider = description:CreateDivider()
    divider:AddInitializer(SkinDivider)
    return divider
  end
end

-- [ pfUIDropdownTemplate ]
-- Mixin of the template in ui-widgets.xml: a dropdown that shows its selection
-- as text, with pfUI's arrow box at the right.
_G.pfUIDropdownMixin = CreateFromMixins(ButtonStateBehaviorMixin, DropdownSelectionTextMixin)

function pfUIDropdownMixin:OnLoad()
  self.Text:SetFont(pfUI.font_default, pfUI_config.global.font_size - 1, "OUTLINE")
  CreateBackdrop(self.Arrow, nil, true)
  self.Arrow.Icon:SetTexture(pfUI.media["img:down"])
  self.Arrow.Icon:SetVertexColor(.8, .8, .8)
  self.Arrow.Icon:SetAlpha(.8)

  ButtonStateBehaviorMixin.OnLoad(self)
  DropdownSelectionTextMixin.OnLoad(self)
end

-- the arrow box takes the class color while the cursor is over the dropdown
function pfUIDropdownMixin:OnButtonStateChanged()
  if self:IsOver() then
    self.Arrow:SetBackdropBorderColor(PFUI_CLASS_COLORS[UnitClassBase("player")]:GetRGB())
  else
    self.Arrow:SetBackdropBorderColor(GetStringColor(pfUI_config.appearance.border.color))
  end
end

-- [ pfUIScrollingEditBoxTemplate ]
-- Mixin of the template in ui-widgets.xml: ClassicAPI's scrolling edit box
-- with pfUI's scroll bar beside it.
_G.pfUIScrollingEditBoxMixin = {}

function pfUIScrollingEditBoxMixin:InitScrollBar()
  local scrollBox = self:GetScrollBox()
  scrollBox:ClearAllPoints()
  scrollBox:SetPoint("TOPLEFT")
  scrollBox:SetPoint("BOTTOMRIGHT", self.ScrollBar, "BOTTOMLEFT")
  ScrollUtil.RegisterScrollBoxWithScrollBar(scrollBox, self.ScrollBar)
end

-- The edit box takes its font from a font object and sets that object again
-- on every SetText, so a font path goes through a font object of the frame's own.
function pfUIScrollingEditBoxMixin:SetFont(font, size, flags)
  if not self.font then
    self.font = CreateFont(self:GetName() .. "Font")
    self:GetEditBox().fontName = self.font
  end
  self.font:SetFont(font, size, flags)
  self:SetFontObject(self.font)
end

-- [ CreateTextBox ]
-- Creates and returns a default pfUI skinned EditBox
function pfUI.api.CreateTextBox(name, parent)
  local f = CreateFrame("EditBox", name, parent)
  f:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  f:SetAutoFocus(false)
  f:SetTextInsets(5, 5, 5, 5)
  f:SetFontObject(GameFontNormal)
  CreateBackdrop(f, nil, true)
  return f
end

-- [ EnableModelControls ]
-- Gives a modelframe the controls of 4.3.4's ModelWithControlsTemplate:
-- left-drag turns it, the mouse wheel zooms toward the face and right-drag
-- pans it. Zoom and pan reset each time the frame is shown.
-- 'frame'    [frame]         the modelframe that should be used
do
  local ZOOM_STEP, MAX_ZOOM = .15, .7

  -- 4.3.4's pan speed and bounds for each player model (ModelFrames.lua)
  local PAN_SETTINGS = {
    HumanMale      = { panMaxLeft = -.4, panMaxRight = .4, panMaxTop = 1.2, panMaxBottom = -.3, panValue = 38 },
    HumanFemale    = { panMaxLeft = -.3, panMaxRight = .3, panMaxTop = 1.2, panMaxBottom = -.2, panValue = 45 },
    OrcMale        = { panMaxLeft = -.7, panMaxRight = .8, panMaxTop = 1.2, panMaxBottom = -.3, panValue = 30 },
    OrcFemale      = { panMaxLeft = -.4, panMaxRight = .3, panMaxTop = 1.2, panMaxBottom = -.3, panValue = 37 },
    DwarfMale      = { panMaxLeft = -.4, panMaxRight = .6, panMaxTop = .9,  panMaxBottom = -.2, panValue = 44 },
    DwarfFemale    = { panMaxLeft = -.3, panMaxRight = .3, panMaxTop = .9,  panMaxBottom = -.2, panValue = 47 },
    NightElfMale   = { panMaxLeft = -.5, panMaxRight = .5, panMaxTop = 1.5, panMaxBottom = -.4, panValue = 30 },
    NightElfFemale = { panMaxLeft = -.4, panMaxRight = .4, panMaxTop = 1.4, panMaxBottom = -.4, panValue = 33 },
    ScourgeMale    = { panMaxLeft = -.4, panMaxRight = .4, panMaxTop = 1.1, panMaxBottom = -.3, panValue = 35 },
    ScourgeFemale  = { panMaxLeft = -.3, panMaxRight = .4, panMaxTop = 1.1, panMaxBottom = -.3, panValue = 36 },
    TaurenMale     = { panMaxLeft = -.7, panMaxRight = .9, panMaxTop = 1.1, panMaxBottom = -.5, panValue = 31 },
    TaurenFemale   = { panMaxLeft = -.5, panMaxRight = .6, panMaxTop = 1.3, panMaxBottom = -.4, panValue = 32 },
    GnomeMale      = { panMaxLeft = -.3, panMaxRight = .3, panMaxTop = .5,  panMaxBottom = -.2, panValue = 52 },
    GnomeFemale    = { panMaxLeft = -.3, panMaxRight = .3, panMaxTop = .5,  panMaxBottom = -.2, panValue = 60 },
    TrollMale      = { panMaxLeft = -.5, panMaxRight = .6, panMaxTop = 1.3, panMaxBottom = -.4, panValue = 27 },
    TrollFemale    = { panMaxLeft = -.4, panMaxRight = .4, panMaxTop = 1.5, panMaxBottom = -.4, panValue = 31 },
    GoblinMale     = { panMaxLeft = -.3, panMaxRight = .4, panMaxTop = .7,  panMaxBottom = -.2, panValue = 43 },
    GoblinFemale   = { panMaxLeft = -.3, panMaxRight = .3, panMaxTop = .7,  panMaxBottom = -.3, panValue = 43 },
    BloodElfMale   = { panMaxLeft = -.5, panMaxRight = .4, panMaxTop = 1.3, panMaxBottom = -.3, panValue = 36 },
    BloodElfFemale = { panMaxLeft = -.3, panMaxRight = .2, panMaxTop = 1.2, panMaxBottom = -.3, panValue = 38 },
  }

  local function OnUpdate()
    if this.rotating then
      local x = GetCursorPosition()
      this.rotation = this.rotation + (x - this.cursorX) * .025
      this.cursorX = x
      this:SetRotation(this.rotation, false)
    elseif this.panning then
      local settings = this.panning
      local x, y = GetCursorPosition()
      local scale = UIParent:GetEffectiveScale()
      local modelScale = this:GetModelScale()
      -- moves the model with the cursor at any zoom (4.3.4's formula)
      local ratio = settings.panValue * 2 ^ ((1 + this.zoom) * 2) * scale / modelScale
      local bound = scale * modelScale
      this:SetPosition(this.panX,
        Clamp(this.panY + (x - this.cursorX) / ratio, settings.panMaxLeft * bound, settings.panMaxRight * bound),
        Clamp(this.panZ + (y - this.cursorY) / ratio, settings.panMaxBottom * bound, settings.panMaxTop * bound))
    end
  end

  local function OnMouseDown()
    this.cursorX, this.cursorY = GetCursorPosition()
    if arg1 == "LeftButton" then
      this.rotating = true
    elseif arg1 == "RightButton" then
      local _, race = UnitRace("player")
      this.panning = PAN_SETTINGS[race .. (UnitSex("player") == 2 and "Male" or "Female")]
      this.panX, this.panY, this.panZ = this:GetPosition()
    end
  end

  local function OnMouseUp()
    this.rotating, this.panning = nil, nil
  end

  local function OnMouseWheel()
    this.zoom = Clamp(this.zoom + arg1 * ZOOM_STEP, 0, MAX_ZOOM)
    this:SetPortraitZoom(this.zoom)
  end

  local function OnShow()
    this.zoom = 0
    this:SetPortraitZoom(0)
    this:SetPosition(0, 0, 0)
  end

  function pfUI.api.EnableModelControls(frame)
    frame.zoom = 0
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:HookScript("OnUpdate", OnUpdate)
    frame:HookScript("OnMouseDown", OnMouseDown)
    frame:HookScript("OnMouseUp", OnMouseUp)
    frame:HookScript("OnMouseWheel", OnMouseWheel)
    frame:HookScript("OnShow", OnShow)
  end
end

local function SetHighlightEnter()
  if this.locked then return end
  (this.backdrop or this):SetBackdropBorderColor(this.cr,this.cg,this.cb,(this.ca or 1))
end

local function SetHighlightLeave()
  if this.locked then return end
  (this.backdrop or this):SetBackdropBorderColor(this.rr,this.rg,this.rb,(this.ra or 1))
end

function pfUI.api.SetHighlight(frame, cr, cg, cb)
  if not frame then return end
  if not cr or not cg or not cb then
    cr, cg, cb = PFUI_CLASS_COLORS[UnitClassBase('player')]:GetRGB()
  end

  frame.cr, frame.cg, frame.cb = cr, cg, cb, ca
  frame.rr, frame.rg, frame.rb, frame.ra = GetStringColor(pfUI_config.appearance.border.color)

  if not frame.pfEnterLeave then
    frame:HookScript("OnEnter", SetHighlightEnter, LE_SCRIPT_BINDING_TYPE_INTRINSIC_POSTCALL)
    frame:HookScript("OnLeave", SetHighlightLeave, LE_SCRIPT_BINDING_TYPE_INTRINSIC_POSTCALL)
    frame.pfEnterLeave = true
  end
end

function pfUI.api.HandleIcon(frame, icon)
  if not frame or not icon then return end

  SetAllPointsOffset(icon, frame, 3)
  icon:SetTexCoord(.08, .92, .08, .92)
end

-- [ Skin Button ]
-- Applies pfUI skin to buttons:
-- 'button'            [frame/string]  the button that should be skinned.
-- 'cr'                [int]           mouseover color (red), defaults to classcolor.
-- 'cg'                [int]           mouseover color (green), defaults to classcolor.
-- 'cb'                [int]           mouseover color (blue), defaults to classcolor.
-- 'icon'              [texture]       the button icon that should be skinned.
-- 'disableHighlight'  [bool]          disable mouseover highlight.
function pfUI.api.SkinButton(button, cr, cg, cb, icon, disableHighlight)
  local b = _G[button]
  if not b then b = button end
  if not b then return end
  if not cr or not cg or not cb then
    cr, cg, cb = PFUI_CLASS_COLORS[UnitClassBase('player')]:GetRGB()
  end
  pfUI.api.CreateBackdrop(b, nil, true)
  b:SetNormalTexture("")
  b:SetHighlightTexture("")
  b:SetPushedTexture("")
  b:SetDisabledTexture("")

  if b.SetCheckedTexture and b:GetCheckedTexture() then
    b:GetCheckedTexture():SetColorTexture(cr, cg, cb, .25)
  end

  if not disableHighlight then
    SetHighlight(b, cr, cg, cb)
  end

  if icon then
    HandleIcon(b, icon)
    b:SetPushedTexture(nil)
  end

  b:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")

  b.LockHighlight = function()
    b:SetBackdropBorderColor(cr,cg,cb,1)
    b.locked = true
  end

  b.UnlockHighlight = function()
    if not MouseIsOverHitRect(b) then
      b:SetBackdropBorderColor(GetStringColor(pfUI_config.appearance.border.color))
    end
    b.locked = false
  end
end

-- [ Skin Collapse Button ]
-- Applies pfUI skin to collapse/expand buttons:
-- 'button'   [frame/string]  the button that should be skinned.
function pfUI.api.SkinCollapseButton(button, all)
  local b = _G[button]
  if not b then b = button end
  if not b then return end
  local name = b:GetName() .. "CollapseButton"
  local size = 10

  b.icon = _G[name] or CreateFrame("Button", name, b)
  if all then size = 14 end
  b.icon:SetSize(size, size)
  b.icon:SetPoint("LEFT", 2, 2)
  CreateBackdrop(b.icon)
  b.icon:EnableMouse(false)
  b.icon.text = b.icon:CreateFontString(nil, "OVERLAY")
  b.icon.text:SetFontObject(GameFontWhite)
  b.icon.text:SetPoint("CENTER", -1, 0)
  b:SetNormalTexture(nil)
  b.SetNormalTexture = function(self, tex)
    if not tex or tex == "" then
      self.icon:Hide()
    else
      self.icon.text:SetText(strfind(tex, "MinusButton") and "-" or "+")
      self.icon:Show()
    end
  end

  local highlight = _G[b:GetName().."Highlight"]
  if highlight then
    highlight:SetTexture("")
    highlight.SetTexture = function(self, tex) return end
  end
end

-- [ Skin Rotate Button]
-- Applies pfUI skin to rotation buttons like in character pane:
-- 'button'     [frame/string]  the button that should be skinned.
function pfUI.api.SkinRotateButton(button)
  pfUI.api.CreateBackdrop(button)

  local cr, cg, cb = PFUI_CLASS_COLORS[UnitClassBase('player')]:GetRGB()

  local btnW, btnH = button:GetSize()
  button:SetSize(btnW - 18, btnH - 18)

  button:GetNormalTexture():SetTexCoord(0.3, 0.29, 0.3, 0.65, 0.69, 0.29, 0.69, 0.65)
  button:GetPushedTexture():SetTexCoord(0.3, 0.29, 0.3, 0.65, 0.69, 0.29, 0.69, 0.65)

  button:GetHighlightTexture():SetColorTexture(cr, cg, cb, .25)

  button:GetPushedTexture():SetAllPoints(button:GetNormalTexture())
  button:GetHighlightTexture():SetAllPoints(button:GetNormalTexture())
end

-- [ Skin Close Button ]
-- Applies pfUI close skin to buttons and can also be positioned
-- 'button'      [frame]    the button that should be skinned.
-- 'parentFrame' [frame]    will anchor to the top right of the parent.
-- 'offsetX'     [integer]  offsets the button horizontally
-- 'offsetY'     [integer]  offsets the button vertically
function pfUI.api.SkinCloseButton(button, parentFrame, offsetX, offsetY)
  if not button then return end

  SkinButton(button, 1, .25, .25)

  button:SetSize(15, 15)

  if parentFrame then
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", offsetX, offsetY)
  end

  button.texture = button:CreateTexture("pfQuestionDialogCloseTex")
  button.texture:SetTexture(pfUI.media["img:close"])
  button.texture:ClearAllPoints()
  button.texture:SetAllPoints(button)
  button.texture:SetVertexColor(1,.25,.25,1)
end

local function ArrowButtonOnEnable()
  this.icon:SetVertexColor(.8,.8,.8,1)
end

local function ArrowButtonOnDisable()
  this.icon:SetVertexColor(.2,.2,.2,1)
end

function pfUI.api.SkinArrowButton(button, dir, size)
  if not button then return end

  SkinButton(button)

  button:SetHitRectInsets(-3,-3,-3,-3)

  button:SetNormalTexture(nil)
  button:SetPushedTexture(nil)
  button:SetHighlightTexture(nil)
  button:SetDisabledTexture(nil)

  if size then
    button:SetSize(size, size)
  end

  if not button.icon then
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAlpha(.8)
    SetAllPointsOffset(button.icon, button, 3)
  end

  button.icon:SetTexture(pfUI.media["img:"..dir])

  -- the icon dims while the button is disabled
  if not button.pfArrowHooked then
    button:HookScript("OnEnable", ArrowButtonOnEnable)
    button:HookScript("OnDisable", ArrowButtonOnDisable)
    button.pfArrowHooked = true
  end

  if button:IsEnabled() > 0 then
    button.icon:SetVertexColor(.8,.8,.8,1)
  else
    button.icon:SetVertexColor(.2,.2,.2,1)
  end
end

function pfUI.api.SkinScrollbar(frame, always)
  local parent = frame:GetParent()
  local name = frame:GetName()
  local up = _G[name .. "ScrollUpButton"]
  local down = _G[name .. "ScrollDownButton"]
  local thumb = frame:GetThumbTexture()

  pfUI.api.SkinArrowButton(up, "up")
  pfUI.api.SkinArrowButton(down, "down")

  if not frame.bg then
    frame.bg = CreateFrame("Frame", nil, frame)
    frame.bg:SetPoint("TOPLEFT", up, "BOTTOMLEFT", 0, -3)
    frame.bg:SetPoint("BOTTOMRIGHT", down, "TOPRIGHT", 0, 3)
    CreateBackdrop(frame.bg, nil, true)
  end

  if not frame.thumb then
    thumb:SetTexture(nil)
    frame.thumb = frame.bg:CreateTexture(nil, "ARTWORK")
    frame.thumb:SetColorTexture(.8,.8,.8,.8)
    frame.thumb:SetPoint("TOPLEFT", thumb, "TOPLEFT", 1, -4)
    frame.thumb:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", -1, 4)
  end

  -- always show parent frame
  if always then
    RunNextFrame(function()
      parent:HookScript("OnHide", function() this:Show() end)
    end)
  end
end

-- [ CenterFrame ]
-- Clears points and centers a frame
-- 'frame'           [frame] the frame that should be centered.
-- 'relativeFrame'   [frame] frame that should be used for centering if not use ui parent.
function pfUI.api.CenterFrame(frame, relativeFrame)
  frame:ClearAllPoints()
  if relativeFrame then
    frame:SetPoint("CENTER", relativeFrame, "CENTER", 0, 0)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

-- [ StripTextures ]
-- Strips all textures off a frame.
-- 'frame'     [frame]   the frame that should be stripped.
-- 'layer'     [string]  texture layer.
function pfUI.api.StripTextures(frame, hide, layer)
  if not frame then return end
  for _,v in ipairs({frame:GetRegions()}) do
    if v.SetTexture then
      local check = true
      if layer and v:GetDrawLayer() ~= layer then check = false end

      if check then
        if hide then
          v:Hide()
        else
          v:SetTexture(nil)
        end
      end
    end
  end
end

function pfUI.api.SetAllPointsOffset(frame, parent, offset)
  frame:SetPoint("TOPLEFT", parent, "TOPLEFT", offset, -offset)
  frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -offset, offset)
end

function pfUI.api.SkinCheckbox(frame, size)
  if not frame then return end
  frame:SetNormalTexture("")
  frame:SetPushedTexture("")
  frame:SetHighlightTexture("")
  if size then
    frame:SetSize(size, size)
  end
  CreateBackdrop(frame)
  SetAllPointsOffset(frame.backdrop, frame, 4)

  if frame.backdrop_border then
    -- make sure the blizzard border doesn't overlap the checkmark
    frame.backdrop_border:SetFrameLevel(frame.backdrop:GetFrameLevel())
  end
end

function pfUI.api.SkinDropDown(frame, cr, cg, cb, useSmall)
  if not frame then return end
  StripTextures(frame)
  CreateBackdrop(frame)
  frame.backdrop:SetPoint("TOPLEFT", 15, -1)
  frame.backdrop:SetPoint("BOTTOMRIGHT", -15, 6)

  local button = _G[frame:GetName() .. "Button"]
  button:SetNormalTexture(nil)
  button:SetPushedTexture(nil)
  button:SetHighlightTexture(nil)
  button:SetDisabledTexture(nil)
  button:SetAllPoints(frame.backdrop)

  CreateBackdrop(button)

  button.backdrop:ClearAllPoints()
  button.backdrop:SetSize(18, 18)
  button.backdrop:SetPoint("RIGHT", frame.backdrop, "RIGHT", -2, 0)

  if not button.icon then
    button.icon = button:CreateTexture(nil, "OVERLAY")
    button.icon:SetTexture(pfUI.media["img:down"])
    button.icon:SetVertexColor(1,.9,.1)
    button.icon:SetAlpha(.8)
    SetAllPointsOffset(button.icon, button.backdrop, 5)
  end

  if not cr or not cg or not cb then
    cr, cg, cb = PFUI_CLASS_COLORS[UnitClassBase('player')]:GetRGB()
  end

  SetHighlight(button, cr, cg, cb)

  if not useSmall then
    -- fix small width
    button:Click() -- open list
    local list_width = DropDownList1:GetWidth()
    if frame:GetWidth() < list_width then
      UIDropDownMenu_SetWidth(list_width, frame)
    end
    CloseDropDownMenus()
  end

  button:HookScript("OnClick", function()
    local DropDownListWidth = DropDownList1:GetWidth()
    local DropDownFrameWidth = frame.backdrop:GetUnscaledWidth()
    if DropDownListWidth < DropDownFrameWidth then
      local diff = DropDownFrameWidth - DropDownListWidth
      DropDownList1:SetWidth(DropDownList1:GetWidth() + diff)
      for i=1, UIDROPDOWNMENU_MAXBUTTONS do
        _G["DropDownList1Button" .. i]:SetWidth(_G["DropDownList1Button" .. i]:GetWidth() + diff)
      end
    end

    DropDownList1:SetPoint("TOPLEFT", frame.backdrop, "BOTTOMLEFT", 0, -4)
  end)

  frame.button = button
end

function pfUI.api.SkinTab(frame, fixed)
  if not frame then return end
  frame:SetHeight(20)
  StripTextures(frame)
  CreateBackdrop(frame)

  if not fixed then
    frame:SetScript("OnShow", function()
      this:SetWidth(this:GetTextWidth() + 20)
      if this.GetFontString and this:GetFontString() then
        this:GetFontString():SetPoint("CENTER", 0, 0)
      end
    end)
  end
end

function pfUI.api.SkinSlider(frame)
  local orientation = frame:GetOrientation()
  local thumb = frame:GetThumbTexture()

  CreateBackdrop(frame, nil, true)
  thumb:SetColorTexture(1, .82, 0)

  for i,region in ipairs({frame:GetRegions()}) do
    if region:GetObjectType() == 'FontString' then
      local point, anchor, anchorPoint, x, y = region:GetPoint()
      if orientation == 'VERTICAL' then
        if string.find(anchorPoint, "TOP") then -- top text
          region:ClearAllPoints()
          region:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
        elseif string.find(anchorPoint, "BOTTOM") then -- bottom text
          region:ClearAllPoints()
          region:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
        end
        anchor:SetHeight(anchor:GetHeight() - 4)
      else
        if string.find(anchorPoint, 'BOTTOM') then
          region:SetPoint(point, anchor, anchorPoint, x, y - 6)
        elseif string.find(anchorPoint, 'TOP') then
          region:SetPoint(point, anchor, anchorPoint, x, y + 2)
        end
      end
    end
  end

  if orientation == 'VERTICAL' then
    frame:SetWidth(10)
    thumb:SetHeight(22)
    thumb:SetWidth(frame:GetWidth())
  else
    frame:SetHeight(10)
    thumb:SetHeight(frame:GetHeight())
    thumb:SetWidth(17)
  end
end

-- [ Question Dialog ]
-- Shows the pfUI user dialog popup. A call while it is shown closes it.
-- 'text'       [string]        text that will be displayed.
-- 'yes'        [function]      function that is triggered on 'Okay' button.
-- 'no'         [function]      function that is triggered on 'Cancel' button.
--                              either can be { caption, function }.
-- 'editbox'    [bool]          if set, a inputfield will be shown. it can be.
--                              accessed with "this:GetParent().input".
-- 'onclose'    [function]      runs once the dialog has closed.
do
  local padding = 15
  local question

  local function QuestionOnHide()
    -- onclose may show the next question in this frame, so it runs once
    -- the hide is over
    if this.onclose then
      RunNextFrame(this.onclose)
      this.onclose = nil
    end
  end

  -- the answer runs with 'this' on its button, where it finds the input
  local function AnswerOnClick()
    if this.answer then this.answer() end
    this:GetParent():Hide()
  end

  local function CreateQuestion()
    local _, border = GetBorderSize()

    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:SetScript("OnHide", QuestionOnHide)
    f:Hide()

    CreateBackdrop(f, nil, nil, .85)
    CreateBackdropShadow(f)

    f.text = f:CreateFontString(nil, "LOW", "GameFontWhite")
    f.text:SetPoint("TOP", 0, -padding)

    f.input = CreateFrame("EditBox", nil, f)
    CreateBackdrop(f.input)
    f.input:SetTextColor(.2,1,.8,1)
    f.input:SetJustifyH("CENTER")
    f.input:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", border, -padding)
    f.input:SetPoint("TOPRIGHT", f.text, "BOTTOMRIGHT", -border, -padding)
    f.input:SetHeight(20)
    f.input:SetFontObject(GameFontNormal)
    f.input:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    f.input:SetAutoFocus(true)

    f.yes = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    SkinButton(f.yes)
    f.yes:SetSize(100, 22)
    f.yes:SetScript("OnClick", AnswerOnClick)

    f.no = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    SkinButton(f.no)
    f.no:SetSize(100, 22)
    f.no:SetScript("OnClick", AnswerOnClick)

    f.close = CreateFrame("Button", nil, f)
    f.close:SetPoint("TOPRIGHT", -border, -border)
    CreateBackdrop(f.close)
    f.close:SetSize(10, 10)
    f.close.texture = f.close:CreateTexture()
    f.close.texture:SetTexture(pfUI.media["img:close"])
    f.close.texture:SetAllPoints(f.close)
    f.close.texture:SetVertexColor(1,.25,.25,1)
    f.close:SetScript("OnEnter", function()
      this.backdrop:SetBackdropBorderColor(1,.25,.25,1)
    end)
    f.close:SetScript("OnLeave", function()
      CreateBackdrop(this)
    end)
    f.close:SetScript("OnClick", function()
      this:GetParent():Hide()
    end)

    return f
  end

  function pfUI.api.CreateQuestionDialog(text, yes, no, editbox, onclose)
    question = question or CreateQuestion()

    -- do not allow multiple instances of question dialogs
    if question:IsShown() then
      question:Hide()
      return
    end

    local yescap, nocap = YES, NO
    if type(yes) == "table" then yescap, yes = yes[1], yes[2] end
    if type(no) == "table" then nocap, no = no[1], no[2] end

    question.onclose = onclose
    question.yes.answer = yes
    question.yes:SetText(yescap)
    question.no.answer = no
    question.no:SetText(nocap)

    -- the dialog is as wide as the longest line of text, and at least 200
    question.text:SetText(text or "Are you sure?")
    local width = math.max(200, question.text:GetUnboundedStringWidth())
    question.text:SetWidth(width)
    question:SetWidth(width + 2*padding)

    -- the buttons go below the input field when it is shown
    local _, border = GetBorderSize()
    local above = editbox and question.input or question.text
    question.input:SetShown(editbox)
    question.input:SetText("")
    question.yes:ClearAllPoints()
    question.yes:SetPoint("TOPRIGHT", above, "BOTTOM", -3*border, -padding)
    question.no:ClearAllPoints()
    question.no:SetPoint("TOPLEFT", above, "BOTTOM", 3*border, -padding)

    local height = padding + question.text:GetStringHeight() + padding + question.no:GetHeight() + padding
    if editbox then height = height + question.input:GetHeight() + padding end
    question:SetHeight(height)

    question:ClearAllPoints()
    question:SetPoint("CENTER", 0, 0)
    question:Show()
  end
end


-- [ Question Dialog ]
-- Creates a pfUI infobox popup window:
-- 'text'       [string]        text that will be displayed.
-- 'time'       [number]        time in seconds till the popup will be faded
-- 'parent'     [frame]         frame which will be used as parent for the dialog (defaults to UIParent)
-- 'height'     [number]        manual height of the popup (defaults to 100)
function pfUI.api.CreateInfoBox(text, time, parent, height)
  if not text then return end
  if not time then time = 5 end
  if not parent then parent = UIParent end
  if not height then height = 100 end

  local infobox = pfInfoBox
  if not infobox then
    infobox = CreateFrame("Button", "pfInfoBox", UIParent)
    infobox:Hide()

    infobox.fade = infobox:CreateAnimationGroup()
    local fade = infobox.fade:CreateAnimation("Alpha")
    fade:SetChange(-1)
    fade:SetDuration(.3)
    infobox.fade:SetScript("OnFinished", function()
      infobox:Hide()
      infobox:SetAlpha(1)
    end)

    infobox:SetScript("OnUpdate", function()
      if infobox.duration:HasExpired() then
        if not infobox.fade:IsPlaying() then infobox.fade:Play() end
      elseif MouseIsOverHitRect(this) then
        this:SetAlpha(max(0.4, this:GetAlpha() - .1))
      else
        this:SetAlpha(min(1, this:GetAlpha() + .1))
      end
    end)

    infobox:SetScript("OnClick", function()
      this:Hide()
    end)

    infobox.text = infobox:CreateFontString("Status", "HIGH", "GameFontNormal")
    infobox.text:ClearAllPoints()
    infobox.text:SetFontObject(GameFontWhite)

    infobox.timeout = CreateFrame("StatusBar", nil, infobox)
    infobox.timeout:SetStatusBarTexture(pfUI.media["img:bar"])
    infobox.timeout:SetStatusBarColor(.3,1,.8,1)
    infobox.duration = C_DurationUtil.CreateDuration()
    infobox.timeout:SetTimerDuration(infobox.duration, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.RemainingTime)

    infobox:ClearAllPoints()
    infobox.text:SetAllPoints(infobox)
    infobox.text:SetFont(pfUI.font_default, 14, "OUTLINE")

    pfUI.api.CreateBackdrop(infobox)
    infobox:SetPoint("TOP", 0, -25)

    infobox.timeout:ClearAllPoints()
    infobox.timeout:SetPoint("TOPLEFT", infobox, "TOPLEFT", 3, -3)
    infobox.timeout:SetPoint("TOPRIGHT", infobox, "TOPRIGHT", -3, 3)
    infobox.timeout:SetHeight(2)
  end

  infobox.text:SetText(text)
  infobox.duration:SetTimeFromStart(GetTime(), time)

  infobox:SetSize(infobox.text:GetStringWidth() + 50, height)
  infobox:SetParent(parent)

  infobox:SetFrameStrata("FULLSCREEN_DIALOG")
  infobox.fade:Stop()
  infobox:Show()
end

function pfUI.api.SkinMoneyInputFrame(frame)
  local gold_editbox = _G[frame:GetName().."Gold"]
  StripTextures(gold_editbox, true, "BACKGROUND")
  CreateBackdrop(gold_editbox, nil, true)
  local goldIcon = GetNoNameObject(gold_editbox, "Texture", nil, "MoneyIcons")
  goldIcon:Show()
  goldIcon:ClearAllPoints()
  goldIcon:SetPoint("LEFT", gold_editbox, "RIGHT", 2, 0)

  local silver_editbox = _G[frame:GetName().."Silver"]
  StripTextures(silver_editbox, true, "BACKGROUND")
  CreateBackdrop(silver_editbox, nil, true)
  silver_editbox:ClearAllPoints()
  silver_editbox:SetPoint("LEFT", goldIcon, "RIGHT", 2, 0)
  local silverIcon = GetNoNameObject(silver_editbox, "Texture", nil, "MoneyIcons")
  silverIcon:Show()
  silverIcon:ClearAllPoints()
  silverIcon:SetPoint("LEFT", silver_editbox, "RIGHT", 2, 0)

  local copper_editbox = _G[frame:GetName().."Copper"]
  StripTextures(copper_editbox, true, "BACKGROUND")
  CreateBackdrop(copper_editbox, nil, true)
  copper_editbox:ClearAllPoints()
  copper_editbox:SetPoint("LEFT", silverIcon, "RIGHT", 2, 0)
  local copperIcon = GetNoNameObject(copper_editbox, "Texture", nil, "MoneyIcons")
  copperIcon:Show()
  copperIcon:ClearAllPoints()
  copperIcon:SetPoint("LEFT", copper_editbox, "RIGHT", 2, 0)
end

-- Shared icon picker widget. Builds a name field, a "currently selected"
-- preview, and a 10x8 icon grid backed by IconDataProviderMixin with an
-- All/Spells/Items filter and a name search. Used by the macro icon picker
-- and the equipment manager's name/icon popup. The widgets attach to
-- `parent`; the caller owns the surrounding frame, its OK/Cancel buttons,
-- and the save flow. Selection is tracked by texture PATH (not index) so it
-- survives filter changes -- a spell icon you picked still saves after you
-- switch the filter to "Items" and it drops out of the visible grid.
--
--   name          global-name prefix for the icon grid and editboxes
--   parent        the popup frame to attach the widgets to
--   extraType     IconDataProviderExtraType.* seed (Spellbook / Equipment)
--   nameLabelText header shown above the name field
--
-- Returns a handle:
--   .editbox                 name EditBox (caller wires enter/escape)
--   .search                  search EditBox
--   .GetIcon()               current selected texture path
--   .SetIcon(path)           set selection (nil -> question mark)
--   .Refresh()               ensure provider, redraw grid + preview
--   .SetIconAreaShown(shown) show/hide the grid, filter, search, and labels
function pfUI.api.CreateIconPicker(name, parent, extraType, nameLabelText)
  local QUESTION_MARK = "INTERFACE\\ICONS\\INV_MISC_QUESTIONMARK"

  local ICON_GRID_COLS = 10
  local ICON_GRID_ROWS = 8
  local ICON_BTN_SIZE  = 36
  local ICON_BTN_PAD   = 6

  local provider = nil
  local selectedIconPath = QUESTION_MARK
  local currentFilter = "all"
  local searchText = ""
  local filtered = nil  -- provider indices matching the search, or nil when empty
  local RefreshIconGrid, RebuildFilter

  local function EnsureProvider()
    if not provider then
      provider = CreateAndInitFromMixin(IconDataProviderMixin, extraType)
    end
  end

  -- Normalize a texture to an uppercase basename so matching works across
  -- sources: GetMacroInfo / stored set icons return "Interface\Icons\<name>"
  -- while provider paths are uppercase-prefixed for base icons and
  -- mixed-case for spellbook extras.
  local function IconKey(path)
    if type(path) ~= "string" then return path end
    return string.gsub(string.upper(path), "^.*[\\/]", "")
  end

  parent.nameLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  parent.nameLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -20)
  parent.nameLabel:SetText(nameLabelText)

  parent.editbox = CreateFrame("EditBox", name.."Name", parent, "InputBoxTemplate")
  parent.editbox:SetSize(280, 20)
  parent.editbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -38)
  parent.editbox:SetAutoFocus(false)
  parent.editbox:SetMaxLetters(16)
  CreateBackdrop(parent.editbox)

  parent.selectedLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  parent.selectedLabel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, -14)
  parent.selectedLabel:SetText(ICON_SELECTION_TITLE_CURRENT)
  parent.selectedLabel:SetTextColor(1, 0.82, 0)

  parent.selectedPreview = CreateFrame("Frame", nil, parent)
  parent.selectedPreview:SetSize(42, 42)
  parent.selectedPreview:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, -30)
  CreateBackdrop(parent.selectedPreview)
  parent.selectedPreview.tex = parent.selectedPreview:CreateTexture(nil, "ARTWORK")
  parent.selectedPreview.tex:SetAllPoints(parent.selectedPreview)
  parent.selectedPreview.tex:SetTexCoord(.08, .92, .08, .92)

  parent.iconLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  parent.iconLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -86)
  parent.iconLabel:SetText(MACRO_POPUP_CHOOSE_ICON)

  -- Icon grid: the template keeps 5px around the grid and its 7px scroll bar,
  -- and the grid leaves 4px before the bar
  local gridWidth = ICON_GRID_COLS * (ICON_BTN_SIZE + ICON_BTN_PAD) - ICON_BTN_PAD
  local gridHeight = ICON_GRID_ROWS * (ICON_BTN_SIZE + ICON_BTN_PAD) - ICON_BTN_PAD
  local grid = CreateFrame("Frame", name.."Icons", parent, "pfUIScrollBoxListTemplate")
  grid:SetPoint("TOPLEFT", parent, "TOPLEFT", 9, -111)
  grid:SetSize(gridWidth + 4 + 7 + 10, gridHeight + 10)

  -- Filter dropdown: All / Spells / Items
  local function IsFilter(value)
    return currentFilter == value
  end
  local function ApplyFilter(value)
    currentFilter = value
    if provider then
      if value == "spells" then provider:SetIconTypes({ IconDataProviderIconType.Spell })
      elseif value == "items" then provider:SetIconTypes({ IconDataProviderIconType.Item })
      else provider:SetIconTypes(nil) end
      RebuildFilter()
      RefreshIconGrid()
    end
  end
  local filterDropdown = CreateFrame("DropdownButton", nil, parent, "pfUIDropdownTemplate")
  filterDropdown:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, -84)
  filterDropdown:SetWidth(140)
  CreateBackdrop(filterDropdown, nil, true)
  filterDropdown:SetupMenu(function(dropdown, rootDescription)
    rootDescription:CreateRadio(ICON_FILTER_ALL, IsFilter, ApplyFilter, "all")
    rootDescription:CreateRadio(ICON_FILTER_SPELL, IsFilter, ApplyFilter, "spells")
    rootDescription:CreateRadio(ICON_FILTER_ITEM, IsFilter, ApplyFilter, "items")
  end)

  -- the selected icon gets a gold border in the grid and shows in the preview
  local function UpdateSelection()
    grid.ScrollBox:ReinitializeFrames()
    parent.selectedPreview.tex:SetTexture(selectedIconPath)
  end

  local function IconOnClick()
    local path = provider:GetIconByIndex(this.iconIndex)
    if path then selectedIconPath = path end
    UpdateSelection()
  end

  local function IconOnEnter()
    local path = provider:GetIconByIndex(this.iconIndex)
    if type(path) == "string" then
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:SetText(IconKey(path), 1, 1, 1)
      GameTooltip:Show()
    end
  end

  local function InitIconButton(btn, icon)
    -- one-time setup of a pooled button
    if not btn.texture then
      CreateBackdrop(btn)
      btn.texture = btn:CreateTexture(nil, "ARTWORK")
      btn.texture:SetAllPoints(btn)
      btn.texture:SetTexCoord(.08, .92, .08, .92)
      btn:SetScript("OnClick", IconOnClick)
      btn:SetScript("OnEnter", IconOnEnter)
      btn:SetScript("OnLeave", GameTooltip_Hide)
    end

    btn.iconIndex = icon.index
    local path = provider:GetIconByIndex(icon.index)
    btn.texture:SetTexture(path)
    if IconKey(path) == IconKey(selectedIconPath) then
      btn.backdrop:SetBackdropBorderColor(1, 0.82, 0, 1)
    else
      btn.backdrop:SetBackdropBorderColor(pfUI.cache.er, pfUI.cache.eg, pfUI.cache.eb, pfUI.cache.ea)
    end
  end

  local view = CreateScrollBoxListGridView(ICON_GRID_COLS, 0, 0, 0, 4, ICON_BTN_PAD, ICON_BTN_PAD)
  view:SetElementSize(ICON_BTN_SIZE, ICON_BTN_SIZE)
  view:SetElementInitializer("Button", InitIconButton)
  ScrollUtil.InitScrollBoxListWithScrollBar(grid.ScrollBox, grid.ScrollBar, view)

  -- Rebuild the search-filtered index list (provider indices whose icon
  -- basename contains the search text); nil when the search box is empty.
  function RebuildFilter()
    EnsureProvider()
    if searchText == "" then
      filtered = nil
      return
    end
    filtered = {}
    for i = 1, provider:GetNumIcons() do
      local path = provider:GetIconByIndex(i)
      if type(path) == "string" and string.find(IconKey(path), searchText, 1, true) then
        table.insert(filtered, i)
      end
    end
  end

  -- one grid entry per provider index the filter lets through, scrolled to the top
  function RefreshIconGrid()
    EnsureProvider()
    if filtered then
      grid.ScrollBox:SetDataProvider(CreateDataProviderWithAssignedKey(filtered, "index"))
    else
      grid.ScrollBox:SetDataProvider(CreateDataProviderByIndexCount(provider:GetNumIcons()))
    end
    parent.selectedPreview.tex:SetTexture(selectedIconPath)
  end

  -- Search box (bottom-left) filters the grid by icon name.
  parent.searchLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  parent.searchLabel:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 16, 18)
  parent.searchLabel:SetText(SEARCH)

  parent.search = CreateFrame("EditBox", name.."Search", parent, "InputBoxTemplate")
  parent.search:SetSize(180, 20)
  parent.search:SetPoint("LEFT", parent.searchLabel, "RIGHT", 10, 0)
  parent.search:SetAutoFocus(false)
  CreateBackdrop(parent.search)
  parent.search:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  parent.search:SetScript("OnTextChanged", function()
    searchText = strupper(strtrim(this:GetText()))
    RebuildFilter()
    RefreshIconGrid()
  end)

  -- Release the provider when the popup closes so its icon cache GCs, and
  -- the grid's entries that index into it.
  parent:HookScript("OnHide", function()
    if provider then provider:Release(); provider = nil end
    grid.ScrollBox:RemoveDataProvider()
  end)

  local handle = { editbox = parent.editbox, search = parent.search }
  function handle.GetIcon() return selectedIconPath end
  function handle.SetIcon(path) selectedIconPath = path or QUESTION_MARK end
  function handle.Refresh() RefreshIconGrid() end
  function handle.SetIconAreaShown(shown)
    grid:SetShown(shown)
    parent.iconLabel:SetShown(shown)
    parent.selectedLabel:SetShown(shown)
    parent.selectedPreview:SetShown(shown)
    filterDropdown:SetShown(shown)
    parent.searchLabel:SetShown(shown)
    parent.search:SetShown(shown)
  end
  return handle
end
