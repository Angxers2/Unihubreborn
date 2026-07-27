# Universal Hub LITE

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Angxers2/Unihubreborn/main/UniversalHubLite.lua?v="..tick()))()
```

The `?v=`..`tick()` is not decoration. `raw.githubusercontent.com` answers with
`cache-control: max-age=300`, so for five minutes after a push the CDN keeps
serving the *previous* file — and executing in that window silently runs the
old build, which looks exactly like the update not having worked. A unique
query string is a different cache key, so this always reaches the origin.

`!rexec` and the re-run after a teleport already stamp their own fetches; this
line is the one place the script cannot do it for you.

First run downloads the icons and fonts from `assets/` with a progress bar.
Every run after that finds them on disk and starts straight away.

Press **T** for the command bar, or `!cmds` for the full list.

## Overrides

Set before executing to point at a fork:

```lua
getgenv().UHUB_ASSETS = "https://raw.githubusercontent.com/you/fork/main/assets/"
getgenv().UHUB_SOURCE = "https://raw.githubusercontent.com/you/fork/main/UniversalHubLite.lua"
```
