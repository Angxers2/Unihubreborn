# Universal Hub LITE

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Angxers2/Unihubreborn/main/UniversalHubLite.lua"))()
```

First run downloads the icons and fonts from `assets/` with a progress bar.
Every run after that finds them on disk and starts straight away.

Press **T** for the command bar, or `!cmds` for the full list.

## Overrides

Set before executing to point at a fork:

```lua
getgenv().UHUB_ASSETS = "https://raw.githubusercontent.com/you/fork/main/assets/"
getgenv().UHUB_SOURCE = "https://raw.githubusercontent.com/you/fork/main/UniversalHubLite.lua"
```
