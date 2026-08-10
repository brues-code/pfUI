pfUI:RegisterModule("socialmod", function ()
  local playerdb = _G.pfUI_playerDB
  pfUI.socialmod = CreateFrame("Frame", "pfSocialMod", UIParent)
  pfUI.socialmod:RegisterEvent("CHAT_MSG_SYSTEM")
  pfUI.socialmod:SetScript("OnEvent", function()
    local name = cmatch(arg1, _G.ERR_FRIEND_ONLINE_SS)
    name = name or cmatch(arg1, _G.ERR_FRIEND_OFFLINE_S)
    if name and playerdb[name] and playerdb[name].cname then
      playerdb[name].lastseen = date("%a %d-%b-%Y")
    end
  end)
  do -- add colors to guild list
    hooksecurefunc("GuildStatus_Update", function()
      local playerzone = GetRealZoneText()
      local off = FauxScrollFrame_GetOffset(GuildListScrollFrame)
      for i=1, GUILDMEMBERS_TO_DISPLAY, 1 do
        local name, _, _, level, class, zone, _, _, online = GetGuildRosterInfo(off + i)
        class = L["class"][class]

        if name then
          if class then
            local color = PFUI_CLASS_COLORS[class]
            local classicon = _G["GuildFrameButton"..i].classicon
            local coords = CLASS_ICON_TCOORDS[class]

            -- do we have classicons? (skin enabled?)
            if classicon then
              _G["GuildFrameButton"..i.."Class"]:SetTextColor(0,0,0,0)

              if coords then
                classicon:Show()
                classicon:SetTexCoord(unpack(coords))
              else
                classicon:Hide()
              end

              if online then
                _G["GuildFrameButton"..i.."Name"]:SetTextColor(color.r,color.g,color.b,1)
              else
                _G["GuildFrameButton"..i.."Name"]:SetTextColor(color.r,color.g,color.b,.5)
              end
            else
              if online then
                _G["GuildFrameButton"..i.."Class"]:SetTextColor(color.r,color.g,color.b,1)
              else
                _G["GuildFrameButton"..i.."Class"]:SetTextColor(color.r,color.g,color.b,.5)
              end
            end
          end

          if level then
            local color = GetDifficultyColor(level)
            if online then
              _G["GuildFrameButton"..i.."Level"]:SetTextColor(color.r + .2, color.g + .2, color.b + .2, 1)
            else
              _G["GuildFrameButton"..i.."Level"]:SetTextColor(color.r + .2, color.g + .2, color.b + .2, .5)
            end
          end

          if zone and zone == playerzone then
            if online then
              _G["GuildFrameButton"..i.."Zone"]:SetTextColor(.5, 1, 1, 1)
            else
              _G["GuildFrameButton"..i.."Zone"]:SetTextColor(.5, 1, 1, .5)
            end
          end
        end
      end
    end)
  end

  do -- add colors to friend list
    hooksecurefunc("FriendsList_Update", function()
      if GetNumFriends() == 0 then return end

      local playerzone  = GetRealZoneText()
      local off = FauxScrollFrame_GetOffset(FriendsFrameFriendsScrollFrame)

      for i=1, FRIENDS_TO_DISPLAY do
        local info = C_FriendList.GetFriendInfoByIndex(off + i)
        if not info or not info.name or info.name == _G.UNKNOWN then break end
        local name = info.name
        local friendName = _G["FriendsFrameFriendButton"..i.."ButtonTextName"]
        local friendLoc = _G["FriendsFrameFriendButton"..i..FRIENDS_NAME_LOCATION]
        local friendInfo = _G["FriendsFrameFriendButton"..i.."ButtonTextInfo"]
        local caption = friendName or friendLoc

        if info.connected then
          local ccolor = PFUI_CLASS_COLORS[info.classFilename]
          local status = info.afk and CHAT_FLAG_AFK or info.dnd and CHAT_FLAG_DND or ""
          local zone = ( info.area == playerzone and "|cffffffff" or "|cffcccccc" ) .. info.area .. "|r"
          local cname = ccolor:WrapTextInColorCode(name)
          if playerdb[name] then
            playerdb[name].lastseen = date("%a %d-%b-%Y")
            playerdb[name].cname = cname
          end

          if friendName then
            friendName:SetText(cname)
            friendLoc:SetText(format(TEXT(FRIENDS_LIST_TEMPLATE), zone, status))
          else
            friendLoc:SetText(format(TEXT(FRIENDS_LIST_TEMPLATE), cname, zone, status))
          end

          friendInfo:SetText(format(TEXT(FRIENDS_LEVEL_TEMPLATE), info.level, info.className))
          caption:SetVertexColor(1,1,1,.9)
          friendInfo:SetVertexColor(1,1,1,.9)
        else
          if playerdb[name] and playerdb[name].cname and playerdb[name].level and playerdb[name].lastseen then
            caption:SetText(format(TEXT(FRIENDS_LIST_OFFLINE_TEMPLATE), playerdb[name].cname))
            friendInfo:SetText(format(TEXT(FRIENDS_LEVEL_TEMPLATE), playerdb[name].level, playerdb[name].lastseen))
          else
            caption:SetText(format(TEXT(FRIENDS_LIST_OFFLINE_TEMPLATE), name.."|r"))
            friendInfo:SetText(TEXT(UNKNOWN))
          end

          caption:SetVertexColor(1,1,1,.4)
          friendInfo:SetVertexColor(1,1,1,.4)
        end
      end
    end)
  end

  do -- add colors to who list
    hooksecurefunc("WhoList_Update", function()
      local num, max = C_FriendList.GetNumWhoResults()
      local off = FauxScrollFrame_GetOffset(WhoListScrollFrame)

      local playerzone  = GetRealZoneText()
      local playerrace  = UnitRace("player")
      local playerguild = GetGuildInfo("player")

      if num + 1 >= MAX_WHOS_FROM_SERVER then
        WhoFrameTotals:SetText("|cffffffff" .. format(GetText("WHO_FRAME_TOTAL_TEMPLATE", nil, num), max).."  |cffaaaaaa"..format(WHO_FRAME_SHOWN_TEMPLATE, MAX_WHOS_FROM_SERVER))
      else
        WhoFrameTotals:SetText("|cffffffff" .. format(GetText("WHO_FRAME_TOTAL_TEMPLATE", nil, num), num).."  |cffaaaaaa"..format(WHO_FRAME_SHOWN_TEMPLATE, num))
      end

      for i=1, WHOS_TO_DISPLAY do
        local info = C_FriendList.GetWhoInfo(off + i)
        if info then
          -- filename is the class token, so no L["class"] reversal is needed
          local class = info.filename

          _G["WhoFrameButton"..i.."Name"]:SetTextColor(NORMAL_FONT_COLOR:GetRGB())

          if (UIDropDownMenu_GetSelectedID(WhoFrameDropDown) == 1) then
            if (info.area == playerzone) then
              _G["WhoFrameButton"..i.."Variable"]:SetTextColor(.5, 1, 1)
            else
              _G["WhoFrameButton"..i.."Variable"]:SetTextColor(1, 1, 1)
            end

          elseif (UIDropDownMenu_GetSelectedID(WhoFrameDropDown) == 2) then
            if (info.fullGuildName == playerguild) then
              _G["WhoFrameButton"..i.."Variable"]:SetTextColor(.5, 1, 1)
            else
              _G["WhoFrameButton"..i.."Variable"]:SetTextColor(1, 1, 1)
            end

          elseif (UIDropDownMenu_GetSelectedID(WhoFrameDropDown) == 3) then
            if (info.raceStr == playerrace) then
              _G["WhoFrameButton"..i.."Variable"]:SetTextColor(.5, 1, 1)
            else
              _G["WhoFrameButton"..i.."Variable"]:SetTextColor(1, 1, 1)
            end
          end

          if class then
            local classicon = _G["WhoFrameButton"..i].classicon
            local coords = CLASS_ICON_TCOORDS[class]
            local color = PFUI_CLASS_COLORS[class]

            -- do we have classicons? (skin enabled?)
            if classicon then
              _G["WhoFrameButton"..i.."Class"]:SetTextColor(0,0,0,0)
              _G["WhoFrameButton"..i.."Name"]:SetTextColor(color.r,color.g,color.b,1)

              if coords then
                classicon:Show()
                classicon:SetTexCoord(unpack(coords))
              else
                classicon:Hide()
              end
            else
              _G["WhoFrameButton"..i.."Class"]:SetTextColor(color.r,color.g,color.b,1)
            end
          end

          local color = GetDifficultyColor(info.level)
          _G["WhoFrameButton"..i.."Level"]:SetTextColor(color.r, color.g, color.b)
        end
      end
    end)
  end
end)
