# Universal Hub LITE

The original GitHub loadstring has been deprecated. Please use the new
Universal Hub loader:

```lua
loadstring(game:HttpGet("https://universalhub.cc/lite/"))()
```

The former `raw.githubusercontent.com` loadstring still runs the stable build,
but it now shows a one-time migration prompt with a button that copies the new
loader. The custom domain avoids GitHub raw-CDN delays and is the supported URL
going forward.

First run downloads the icons and fonts from `assets/` with a progress bar.
Every run after that finds them on disk and starts straight away.

Press **T** for the command bar, or `!cmds` for the full list.

## Overrides

Set before executing to point at a fork:

```lua
getgenv().UHUB_ASSETS = "https://raw.githubusercontent.com/you/fork/main/assets/"
getgenv().UHUB_SOURCE = "https://raw.githubusercontent.com/you/fork/main/UniversalHubLite.lua"
```
