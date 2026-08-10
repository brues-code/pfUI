-- Friend notes
-- Client-side notes for friends via ClassicAPI's C_FriendList note API
-- (SetFriendNotes / GetFriendInfo(.notes)). Adds an "Edit Note" entry to the
-- friend right-click menu (the "FRIEND" UnitPopup) and shows the note in a
-- tooltip when you hover a friend in the list.
pfUI:RegisterModule("friendnotes", function ()
  local EDIT_TOKEN = "PFUI_FRIEND_NOTE"

  -- Note editor. In 1.12 StaticPopup, OnAccept runs with `this` = the OK
  -- button (the dialog is this:GetParent()); the friend name arrives as the
  -- data argument passed to StaticPopup_Show.
  StaticPopupDialogs["PFUI_FRIEND_NOTE_EDIT"] = {
    text = SET_FRIENDNOTE_LABEL,
    button1 = SAVE,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 128,
    OnAccept = function(name)
      C_FriendList.SetFriendNotes(name, _G[this:GetParent():GetName().."EditBox"]:GetText())
    end,
    EditBoxOnEnterPressed = function(name)
      C_FriendList.SetFriendNotes(name, this:GetText())
      this:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function() this:GetParent():Hide() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
  }

  local function OpenNoteEditor(name)
    if not name or name == "" then return end
    local info = C_FriendList.GetFriendInfo(name)
    local dialog = StaticPopup_Show("PFUI_FRIEND_NOTE_EDIT", name, nil, name)
    if not dialog then return end
    local editbox = _G[dialog:GetName().."EditBox"]
    editbox:SetText((info and info.notes) or "")
    editbox:HighlightText()
    editbox:SetFocus()
  end

  -- Add "Edit Note" to the friend right-click menu, just before Cancel.
  UnitPopupButtons[EDIT_TOKEN] = { text = SET_NOTE, dist = 0 }
  local friendMenu = UnitPopupMenus["FRIEND"]
  table.insert(friendMenu, table.getn(friendMenu), EDIT_TOKEN)

  UnitPopupMenus["PFUI_FRIENDNOTE"] = { EDIT_TOKEN, "CANCEL" }
  local function OfflineNoteDropDown_Initialize()
    UnitPopup_ShowMenu(_G[UIDROPDOWNMENU_OPEN_MENU], "PFUI_FRIENDNOTE", nil, FriendsDropDown.name)
  end
  local FriendsFrame_ShowDropdown_orig = FriendsFrame_ShowDropdown
  _G.FriendsFrame_ShowDropdown = function(name, connected)
    if connected then return FriendsFrame_ShowDropdown_orig(name, connected) end
    HideDropDownMenu(1)
    FriendsDropDown.initialize = OfflineNoteDropDown_Initialize
    FriendsDropDown.displayMode = "MENU"
    FriendsDropDown.name = name
    ToggleDropDownMenu(1, nil, FriendsDropDown, "cursor")
  end

  -- Route our entry to the editor and close the menu; delegate the rest. A
  -- bare assignment lands on pfUI.env, so set the global explicitly.
  local UnitPopup_OnClick_orig = UnitPopup_OnClick
  _G.UnitPopup_OnClick = function()
    if this and this.value == EDIT_TOKEN then
      local dropdown = _G[UIDROPDOWNMENU_INIT_MENU]
      local name = dropdown and dropdown.name
      CloseDropDownMenus()
      OpenNoteEditor(name)
      return
    end
    return UnitPopup_OnClick_orig()
  end

  -- Show the note in a tooltip while hovering a friend in the list. Friend
  -- buttons carry their friend index via SetID (see FriendsFrame_Update).
  local function FriendButton_OnEnter()
    local index = this:GetID()
    if not index or index < 1 then return end
    local info = C_FriendList.GetFriendInfoByIndex(index)
    if not info or not info.notes or info.notes == "" then return end
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(info.name or "")
    GameTooltip:AddLine(info.notes, 1, 1, 1, 1)
    GameTooltip:Show()
  end

  for i = 1, FRIENDS_TO_DISPLAY do
    local button = _G["FriendsFrameFriendButton"..i]
    if button then
      button:HookScript("OnEnter", FriendButton_OnEnter)
      button:HookScript("OnLeave", GameTooltip_Hide)
    end
  end
end)
