-- The rows of the config GUI: one template in gui_rows.xml for each row
-- type, each with a mixin from this file. row:Init(setting) shows a
-- setting, a table with these fields:
--
--   type     "number", "text", "checkbox", "dropdown", "color", "list",
--            "buttons", "header", "warning" or "link"
--   label    the caption
--   table    the table that holds the value: a config table, or a store
--            that reads and writes game state the same way
--   key      the key of the value in that table
--   values   the entries of a dropdown as "value:label" strings, or a
--            function that returns them
--   buttons  the { label, onClick } pairs of a buttons row
--   onClick  what a "link" row runs when clicked, given the setting
--   update   applies a change; changes to a setting without one take
--            effect after a reload
--
-- The widgets read the setting that is bound when an event comes, so a row
-- can show another setting after its next Init.
setfenv(1, pfUI:GetEnvironment())

-- Stores the value of a setting, then applies it, or counts it among the
-- changes that wait for a reload.
local function Write(setting, value)
  local old = setting.table[setting.key]
  if old == value then return end
  setting.table[setting.key] = value

  if setting.update then
    setting.update()
  else
    pfUI.gui:NoteReload(setting.table, setting.key, old)
  end

  pfUI.events:TriggerEvent("config:changed", setting.table, setting.key)
end

-- Whether two values are the same setting: a cvar can read "1.000" for "1".
local function Same(a, b)
  return a == b or (tonumber(a) ~= nil and tonumber(a) == tonumber(b))
end

-- the value of a setting in words, for the reset menu
local function Describe(setting, value)
  if setting.type == "checkbox" then
    return value == "1" and YES or NO
  elseif setting.type == "color" then
    local r, g, b = strsplit(",", value)
    return CreateColor(tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1):WrapTextInColorCode("||||||")
  elseif setting.type == "dropdown" then
    local values = setting.values
    if type(values) == "function" then values = values() end
    for _, entry in pairs(values or {}) do
      local entryValue, text = strsplit(":", entry)
      if entryValue == value then return text or entryValue end
    end
  elseif setting.type == "list" then
    return (value:gsub("^#", ""):gsub("#", ", "))
  end
  return value
end

-- backdrop shadows show on the wrong strata inside the config window
local function HideShadow(frame)
  if frame.backdrop_shadow then frame.backdrop_shadow:Hide() end
end

-- [ pfUIConfigRowMixin ]
-- A caption on a row that lights up while the cursor is over it. The
-- widgets on the row pass their mouse motion on to it.
local RowMixin = {}
_G.pfUIConfigRowMixin = RowMixin

function RowMixin:OnLoad()
  self.caption:SetFont(pfUI.font_default, C.global.font_size)
end

function RowMixin:OnEnter()
  self.tex:Show()
end

function RowMixin:OnLeave()
  self.tex:Hide()
end

function RowMixin:Init(setting)
  self.setting = setting

  local caption = setting.label
  if not setting.update and C.gui.reloadmarker == "1" then
    caption = caption .. " [|cffffaaaa!|r]"
  end
  self.caption:SetText(caption)

  self:Refresh()
  self:UpdateState()
end

-- shows the value of the setting on the widget
function RowMixin:Refresh()
end

-- Whether the switch a setting depends on is on: `requires` names a key of
-- the setting's table that must be "1", or with a leading "!" must not be;
-- `module` names a pfUI module that must not be disabled.
local function IsEnabled(setting)
  if setting.module and C.disabled[setting.module] == "1" then return false end

  local requires = setting.requires
  if not requires then return true end
  if requires:sub(1, 1) == "!" then
    return setting.table[requires:sub(2)] ~= "1"
  end
  return setting.table[requires] == "1"
end

-- the widgets of a row that take the mouse
local WIDGETS = { "input", "slider", "color", "add", "del" }

-- The mark at the left edge of a setting that is not at its default, and
-- the dimmed look and closed widgets of a setting whose switch is off.
function RowMixin:UpdateState()
  local setting = self.setting
  local default = setting.key and pfUI:GetConfigDefault(setting.table, setting.key)
  self.changed:SetShown(default ~= nil and not Same(self:GetValue(), default))

  local enabled = IsEnabled(setting)
  self:SetAlpha(enabled and 1 or .35)
  for _, key in ipairs(WIDGETS) do
    if self[key] then self[key]:EnableMouse(enabled) end
  end
end

function RowMixin:GetValue()
  return self.setting.table[self.setting.key]
end

function RowMixin:SetValue(value)
  Write(self.setting, value)
end

-- a right-click offers to put the setting back to its default
function RowMixin:OnMouseUp(button)
  local setting = self.setting
  if button ~= "RightButton" or not setting or not setting.key then return end

  local default = pfUI:GetConfigDefault(setting.table, setting.key)
  if default == nil then return end

  local row = self
  self.menuMixin = pfUIMenuStyleMixin
  MenuUtil.CreateContextMenu(self, function(_, rootDescription)
    rootDescription:CreateTitle(setting.label)
    local reset = rootDescription:CreateButton(T["Reset to Default"] .. " (" .. Describe(setting, default) .. ")", function()
      Write(setting, default)
      -- the change event skips the row that made the change
      if row.setting == setting then
        row:Refresh()
        row:UpdateState()
      end
    end)
    reset:SetEnabled(not Same(setting.table[setting.key], default))
  end)
end

-- [ pfUIConfigTextRowMixin ]
-- An edit box. A "number" setting takes only numbers: while the text is not
-- one, it turns red and the value stays as it was.
local TextRowMixin = CreateFromMixins(RowMixin)
_G.pfUIConfigTextRowMixin = TextRowMixin

function TextRowMixin:OnLoad()
  RowMixin.OnLoad(self)

  local input = self.input
  CreateBackdrop(input, nil, true)
  HideShadow(input)
  input:SetFontObject(GameFontNormal)
  input:SetTextInsets(5, 5, 5, 5)
  input:SetTextColor(.2,1,.8,1)
  input:SetJustifyH("RIGHT")

  local row = self
  input:SetScript("OnEscapePressed", function() row.input:ClearFocus() end)
  input:SetScript("OnTextChanged", function() row:OnTextChanged() end)
end

function TextRowMixin:Refresh()
  self.input:SetText(self:GetValue() or "")
end

function TextRowMixin:OnTextChanged()
  if not self.setting then return end

  local text = self.input:GetText()
  if self.setting.type == "number" and not tonumber(text) then
    self.input:SetTextColor(1,.3,.3,1)
  else
    self.input:SetTextColor(.2,1,.8,1)
    self:SetValue(text)
  end
end

-- [ pfUIConfigSliderRowMixin ]
-- A number with `min`, `max` and `step`: the slider sets it, and the edit
-- box takes any number, past the ends too.
local SliderRowMixin = CreateFromMixins(TextRowMixin)
_G.pfUIConfigSliderRowMixin = SliderRowMixin

function SliderRowMixin:OnLoad()
  TextRowMixin.OnLoad(self)
  self.input:SetWidth(44)
  SkinSlider(self.slider)

  local row = self
  self.slider:SetScript("OnValueChanged", function()
    if row.syncing or not row.setting then return end
    local step = row.setting.step or 1
    local text = tostring(round(row.slider:GetValue() / step) * step)
    if text ~= row:GetValue() then
      row.input:SetText(text)
    end
  end)
end

-- moves the slider to the setting's value without writing it back
function SliderRowMixin:SyncSlider()
  local setting = self.setting
  self.syncing = true
  self.slider:SetMinMaxValues(setting.min, setting.max)
  self.slider:SetValueStep(setting.step or 1)
  self.slider:SetValue(tonumber(self:GetValue()) or setting.min)
  self.syncing = nil
end

function SliderRowMixin:Refresh()
  TextRowMixin.Refresh(self)
  self:SyncSlider()
end

function SliderRowMixin:OnTextChanged()
  TextRowMixin.OnTextChanged(self)
  if self.setting then self:SyncSlider() end
end

-- [ pfUIConfigCheckboxRowMixin ]
-- A checkbox for a "1" or "0" value, ticked for "1", or for "0" when the
-- setting is `invert`ed.
local CheckboxRowMixin = CreateFromMixins(RowMixin)
_G.pfUIConfigCheckboxRowMixin = CheckboxRowMixin

function CheckboxRowMixin:OnLoad()
  RowMixin.OnLoad(self)

  local input = self.input
  input:SetNormalTexture("")
  input:SetPushedTexture("")
  input:SetHighlightTexture("")
  CreateBackdrop(input, nil, true)
  HideShadow(input)

  local row = self
  input:SetScript("OnClick", function()
    local on = row.input:GetChecked() and true or false
    row:SetValue(on ~= (row.setting.invert or false) and "1" or "0")
  end)
end

function CheckboxRowMixin:Refresh()
  self.input:SetChecked((self:GetValue() == "1") ~= (self.setting.invert or false))
end

-- A font object for each font file a dropdown previews. Menu entries share
-- pooled font strings that may not take SetFont, but take a font object.
local previewFonts = {}
local function GetPreviewFont(path)
  if not previewFonts[path] then
    local font = CreateFont("pfUIConfigPreviewFont" .. (#previewFonts + 1))
    font:SetFont(path, C.global.font_size + 2)
    previewFonts[#previewFonts + 1] = font
    previewFonts[path] = font
  end
  return previewFonts[path]
end

-- [ pfUIConfigDropdownRowMixin ]
-- A dropdown of the setting's values.
local DropdownRowMixin = CreateFromMixins(RowMixin)
_G.pfUIConfigDropdownRowMixin = DropdownRowMixin

function DropdownRowMixin:OnLoad()
  RowMixin.OnLoad(self)
  self.input:SetWidth(180)

  local row = self
  local function IsSelected(value)
    return row:GetValue() == value
  end

  local function SetSelected(value)
    row:SetValue(value)
  end

  self.input:SetupMenu(function(dropdown, rootDescription)
    if not row.setting then return end

    local values = row.setting.values
    if type(values) == "function" then values = values() end

    local preview = row.setting.preview
    for _, entry in pairs(values or {}) do
      -- "value:label", or the value alone
      local value, text = strsplit(":", entry)
      local radio = rootDescription:CreateRadio(text or value, IsSelected, SetSelected, value)

      -- a font or bar texture setting shows each choice as it looks
      if preview == "font" then
        radio:AddInitializer(function(button)
          button.fontString:SetFontObject(GetPreviewFont(value))
          button.fontString:SetTextToFit(text or value)
          -- every entry as tall as a plain one, so the boxes line up
          button.fontString:SetHeight(20)
        end)
      elseif preview == "texture" then
        radio:AddInitializer(function(button)
          local strip = button:AttachTexture()
          strip:SetTexture(value)
          strip:SetVertexColor(.8, .8, .8)
          strip:SetSize(80, 10)
          strip:SetPoint("LEFT", button.fontString, "RIGHT", 8, 0)
        end)
      end
    end
  end)
end

function DropdownRowMixin:Refresh()
  self.input:GenerateMenu()
end

-- [ pfUIConfigColorRowMixin ]
-- A swatch that opens the color picker. The swatch follows the picker while
-- it is open, and the color is saved when the picker closes with Okay.
local ColorRowMixin = CreateFromMixins(RowMixin)
_G.pfUIConfigColorRowMixin = ColorRowMixin

-- the numbers of an "r,g,b,a" value, or white
local function ParseColor(value)
  local r, g, b, a = strsplit(",", value or "")
  r, g, b, a = tonumber(r), tonumber(g), tonumber(b), tonumber(a)
  if not r or not g or not b or not a then return 1, 1, 1, 1 end
  return r, g, b, a
end

function ColorRowMixin:OnLoad()
  RowMixin.OnLoad(self)

  local color = self.color
  CreateBackdrop(color)
  HideShadow(color)
  color.prev = color.backdrop:CreateTexture(nil, "OVERLAY")
  color.prev:SetAllPoints(color)

  local row = self
  color:SetScript("OnClick", function() row:OpenColorPicker() end)
end

function ColorRowMixin:Refresh()
  self.color.prev:SetColorTexture(ParseColor(self:GetValue()))
end

function ColorRowMixin:OpenColorPicker()
  local row, setting = self, self.setting
  local cr, cg, cb, ca = ParseColor(self:GetValue())

  -- the swatch follows the picker while the row shows this setting
  local function Preview(r, g, b, a)
    if row.setting == setting then
      row.color.prev:SetColorTexture(r, g, b, a)
    end
  end

  function ColorPickerFrame.func()
    local r, g, b = ColorPickerFrame:GetColorRGB()
    local a = 1 - OpacitySliderFrame:GetValue()
    r, g, b, a = round(r, 3), round(g, 3), round(b, 3), round(a, 3)
    Preview(r, g, b, a)

    -- the Okay button hides the picker, then calls this
    if not this:GetParent():IsShown() then
      Write(setting, r .. "," .. g .. "," .. b .. "," .. a)
    end
  end

  function ColorPickerFrame.cancelFunc()
    Preview(cr, cg, cb, ca)
  end

  ColorPickerFrame.opacityFunc = ColorPickerFrame.func
  ColorPickerFrame.element = self.color
  ColorPickerFrame.opacity = 1 - ca
  ColorPickerFrame.hasOpacity = 1
  ColorPickerFrame:SetColorRGB(cr, cg, cb)
  ColorPickerFrame:SetFrameStrata("DIALOG")
  ShowUIPanel(ColorPickerFrame)
end

-- [ pfUIConfigListRowMixin ]
-- A list of "#"-separated entries: the dropdown picks one, "-" removes it
-- and "+" asks for a new one.
local ListRowMixin = CreateFromMixins(RowMixin)
_G.pfUIConfigListRowMixin = ListRowMixin

local function SkinListButton(button, text, r, g, b)
  SkinButton(button)
  button:GetFontString():SetPoint("CENTER", 1, 0)
  button:SetText(text)
  button:SetTextColor(r, g, b, 1)
end

function ListRowMixin:OnLoad()
  RowMixin.OnLoad(self)
  SkinListButton(self.del, "-", 1, .5, .5)
  SkinListButton(self.add, "+", .5, 1, .5)
  self.input:SetWidth(140)

  local row = self
  self.del:SetScript("OnClick", function() row:RemoveSelected() end)
  self.add:SetScript("OnClick", function() row:AddEntry() end)

  local function IsSelected(index)
    return index == row.selected
  end

  local function Select(index)
    row.selected = index
  end

  self.input:SetupMenu(function(dropdown, rootDescription)
    if not row.setting then return end

    for index, entry in ipairs({ strsplit("#", row:GetValue() or "") }) do
      if entry ~= "" then
        rootDescription:CreateRadio(entry, IsSelected, Select, index)
      end
    end
  end)
end

function ListRowMixin:Refresh()
  self.selected = nil
  self.input:GenerateMenu()
end

function ListRowMixin:RemoveSelected()
  if not self.selected then return end

  local list = ""
  for index, entry in ipairs({ strsplit("#", self:GetValue() or "") }) do
    if index ~= self.selected and entry ~= "" then
      list = list .. "#" .. entry
    end
  end

  self.selected = nil
  self:SetValue(list)
  self.input:GenerateMenu()
end

function ListRowMixin:AddEntry()
  local row, setting = self, self.setting
  CreateQuestionDialog(T["New entry:"], function()
    -- this: the button of the dialog, whose edit box holds the entry
    local entry = this:GetParent().input:GetText()
    Write(setting, (setting.table[setting.key] or "") .. "#" .. entry)
    if row.setting == setting then row.input:GenerateMenu() end
  end, false, true)
end

-- [ pfUIConfigButtonsRowMixin ]
-- Buttons in a line from the right, without a caption.
local ButtonsRowMixin = {}
_G.pfUIConfigButtonsRowMixin = ButtonsRowMixin

function ButtonsRowMixin:Init(setting)
  self.setting = setting
  self.buttons = self.buttons or {}

  for index, data in ipairs(setting.buttons) do
    local button = self.buttons[index]
    if not button then
      button = CreateFrame("Button", nil, self, "UIPanelButtonTemplate")
      CreateBackdrop(button, nil, true)
      SkinButton(button)
      HideShadow(button)
      button:SetWidth(100)
      button:SetHeight(20)
      button:SetPoint("TOPRIGHT", -(index - 1) * 105, -5)
      button:SetPropagateMouseMotion(true)
      self.buttons[index] = button
    end

    button:SetText(data[1])
    button:SetTextColor(1,1,1,1)
    button:SetScript("OnClick", data[2])
    button:Show()
  end

  for index = #setting.buttons + 1, #self.buttons do
    self.buttons[index]:Hide()
  end

  -- the first button, where the rows of CreateConfig always had it
  self.button = self.buttons[1]
end

-- [ pfUIConfigHeaderRowMixin ]
-- A section title in pfUI's color, at the bottom of a taller row.
local HeaderRowMixin = {}
_G.pfUIConfigHeaderRowMixin = HeaderRowMixin

function HeaderRowMixin:OnLoad()
  self.caption:SetFont(pfUI.font_default, C.global.font_size)
  self.caption:SetTextColor(.2,1,.8,1)
end

function HeaderRowMixin:Init(setting)
  self.setting = setting
  self.caption:SetText(setting.label)
end

-- [ pfUIConfigWarningRowMixin ]
-- A caption in a box with a red border.
local WarningRowMixin = CreateFromMixins(RowMixin)
_G.pfUIConfigWarningRowMixin = WarningRowMixin

function WarningRowMixin:OnLoad()
  RowMixin.OnLoad(self)
  self:SetHeight(50)
  CreateBackdrop(self, nil, true)
  self:SetBackdropBorderColor(1,.5,.5)
  self.caption:SetJustifyH("CENTER")
  self.caption:SetJustifyV("MIDDLE")
end

-- [ pfUIConfigPickerRowMixin ]
-- The dropdown that picks the variant a page shows, as the page's head, with
-- a button that runs the setting's copy(button).
local PickerRowMixin = CreateFromMixins(DropdownRowMixin)
_G.pfUIConfigPickerRowMixin = PickerRowMixin

function PickerRowMixin:OnLoad()
  DropdownRowMixin.OnLoad(self)
  self.caption:SetFont(pfUI.font_default, C.global.font_size + 4)
  self.caption:SetTextColor(.2,1,.8,1)

  -- the variant sits in a box right after the title, its name at the left
  local input = self.input
  input:ClearAllPoints()
  input:SetPoint("LEFT", self.caption, "RIGHT", 12, 0)
  input:SetWidth(160)
  input.Text:SetJustifyH("LEFT")
  input.Text:SetPoint("LEFT", 6, 0)
  CreateBackdrop(input, nil, true)
  HideShadow(input)

  CreateBackdrop(self.copy, nil, true)
  SkinButton(self.copy)
  HideShadow(self.copy)
  self.copy:SetText(T["Copy From"] .. "...")
  self.copy:SetTextColor(1,1,1,1)

  local row = self
  self.copy:SetScript("OnClick", function(button) row.setting.copy(button) end)
end

-- [ pfUIConfigLinkRowMixin ]
-- A caption that runs the setting's onClick.
local LinkRowMixin = CreateFromMixins(RowMixin)
_G.pfUIConfigLinkRowMixin = LinkRowMixin

function LinkRowMixin:Init(setting)
  self.setting = setting
  self.caption:SetText(setting.label)
end

function LinkRowMixin:OnClick()
  self.setting.onClick(self.setting)
end
