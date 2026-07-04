# pfUI - ClassicAPI Edition

[![Octo WoW](https://img.shields.io/badge/Octo%20WoW-1.18.1-brightgreen.svg)](https://octowow.st/)
[![ClassicAPI](https://img.shields.io/badge/ClassicAPI-Required-purple.svg)](https://github.com/brues-code/ClassicAPI)
[![SuperWoW](https://img.shields.io/badge/SuperWoW-Required-purple.svg)](https://github.com/balakethelock/SuperWoW)
[![Nampower](https://img.shields.io/badge/Nampower-Required-purple.svg)](https://github.com/brues-code/nampower)
[![UnitXP](https://img.shields.io/badge/UnitXP__SP3-Optional-yellow.svg)](https://codeberg.org/konaka/UnitXP_SP3)

**A pfUI fork specifically optimized for ClassicAPI on [Octo WoW](https://octowow.st/) which requires Nampower and SuperWoW with optional UnitXP_SP3 DLL integration.**

This version includes significant performance improvements and DLL-enhanced features.

## Installation
1. Download **[Latest Version](https://github.com/brues-code/pfUI/releases/latest)**
2. Unpack the Zip file
4. Copy "pfUI" into Wow-Directory\Interface\AddOns
5. Restart Wow

## Optional DLL Enhancements

Since pfUI 6.0.0 includes integrations with client-side DLLs for enhanced functionality. These DLLs are permitted on Octo WoW:

### [ClassicAPI](https://github.com/brues-code/ClassicAPI)

Provides:
- C_UnitAuras - Replaces over 3k lines of hand-rolled aura tracking
- C_Spell - Replaces thousands of hardcoded spell names for each locale and powers castbar
- Instant Bag Sorting
- C_EquipmentSet
- Focus
- Plenty other functions

### [SuperWoW](https://github.com/balakethelock/SuperWoW)

Provides:
- UnitPosition for distance calculations
- SetMouseoverUnit for improved targeting

### [Nampower](https://github.com/brues-code/nampower)

Provides:
- Spell queue indicator
- GCD indicator
- Reactive spell detection
- Enhanced cast information

### [UnitXP_SP3](https://codeberg.org/konaka/UnitXP_SP3)

Provides:
- Line of Sight detection
- Behind detection
- Accurate distance calculations
- OS notifications

Use `/pfdll` in-game to check which DLLs are detected.

## Commands

    /pfui         Open the configuration GUI
    /pfdll        Show DLL detection status (SuperWoW, Nampower, UnitXP)
    /pfbehind     Test Behind/LOS detection on current target
    /clickthrough Toggle clickthrough mode (or /ct)
    /share        Open the configuration import/export dialog
    /gm           Open the ticket Dialog
    /rl           Reload the whole UI
    /farm         Toggles the Farm-Mode
    /pfcast       Same as /cast but for mouseover units
    /focus        Creates a Focus-Frame for the current target
    /castfocus    Same as /cast but for focus frame
    /clearfocus   Clears the Focus-Frame
    /swapfocus    Toggle Focus and Target-Frame
    /pftest       Toggle pfUI Unitframe Test Mode
    /abp          Addon Button Panel

## Languages
pfUI supports and contains language specific code for the following gameclients.
* English (enUS)
* Korean (koKR)
* French (frFR)
* German (deDE)
* Chinese (zhCN)
* Spanish (esES)
* Russian (ruRU)

## Recommended Addons
* [pfQuest](https://shagu.org/pfQuest) A simple database and quest helper
* [SuperCleveRoidMacros](https://github.com/brues-code/SuperCleveRoidMacros) Supports modern macro formats

## Plugins
* [pfUI-eliteoverlay](https://shagu.org/pfUI-eliteoverlay) Add elite dragons to unitframes
* [pfUI-fonts](https://shagu.org/pfUI-fonts) Additional fonts for pfUI
* [pfUI-CustomMedia](https://github.com/mrrosh/pfUI-CustomMedia) Additional textures for pfUI
* [pfUI-Gryphons](https://github.com/mrrosh/pfUI-Gryphons) Add back the gryphons to your actionbars

## FAQ
**What does "pfUI" stand for?**  
The term "*pfui!*" is german and simply stands for "*pooh!*", because I'm not a
big fan of creating configuration UI's, especially not via the Wow-API
(you might have noticed that in ShaguUI).

**How can I donate?**  
[You can buy me a coffee if you'd like](https://buymeacoffee.com/brues)

**How do I report a Bug?**  
Please provide as much information as possible in the [Bugtracker](https://github.com/brues-code/pfUI/issues).
If there is an error message, provide the full content of it. Just telling that "there is an error" won't help any of us.
Please consider adding additional information such as: since when did you got the error,
does it still happen using a clean configuration, what other addons are loaded and which version you're running.
When playing with a non-english client, the language might be relevant too. If possible, explain how people can reproduce the issue.

**Where is the happiness indicator for pets?**  
The pet happiness is shown as the color of your pet's frame. Depending on your skin, this can either be the text or the background color of your pet's healthbar:

- Green = Happy
- Yellow = Content
- Red = Unhappy

Since version 4.0.7 there is also an additional icon that can be enabled from the pet unit frame options.

**Can I use Clique with pfUI?**  
This addon already includes support for clickcasting. If you still want to make use of clique, all pfUI's unitframes are already compatible to Clique-TBC. For Vanilla, a pfUI compatible version can be found [Here](https://github.com/shagu/Clique/archive/master.zip). If you want to keep your current version of Clique, you'll have to apply this [Patch](https://github.com/shagu/Clique/commit/a5ee56c3f803afbdda07bae9cd330e0d4a75d75a).

**Where is the Experience Bar?**  
The experience bar shows up on mouseover and whenever you gain experience, next to left chatframe by default. There's also an option to make it stay visible all the time.

**How do I show the Damage- and Threatmeter Dock?**  
If you enabled the "dock"-feature for your external (third-party) meters such as DPSMate or KTM, then you'll be able to toggle between them and the Right Chat by clicking on the ">" symbol on the bottom-right panel.

**Why is my chat always resetting to only 3 lines of text?**  
This happens if "Simple Chat" is enabled in blizzards interface settings (Advanced Options).
Paste the following command into your chat to disable that option: `/run SIMPLE_CHAT="0"; pfUI.chat.SetupPositions(); ReloadUI()`

**How can I enable mouseover cast?**  
On Vanilla, create a macro with "/pfcast SPELLNAME". If you also want to see the cooldown, You might want to add "/run if nil then CastSpellByName("SPELLNAME") end" on top of the macro.

**Everything from scratch?! Are you insane?**  
Most probably, yes.

---

## 🤝 Credits & Acknowledgments

- **Shagu** - Original pfUI creator ([https://github.com/shagu/pfUI](https://github.com/shagu/pfUI))
- **me0wg4ming** - pfUI fork maintainer and Turtle WoW enhancements
- **jrc13245** - Nampower, UnitXP, and BGScore module integration ([https://github.com/jrc13245/](https://github.com/jrc13245/))
- **SuperWoW Team** - SuperWoW framework development
- **avitasia** - Nampower DLL development
- **konaka** - UnitXP_SP3 DLL development
- **Turtle WoW Team** - For the amazing Vanilla+ experience
- **Community** - Bug reports, feature suggestions, and testing

---

## 📄 License

Same as original pfUI - free to use and modify.

---
