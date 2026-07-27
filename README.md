# Universal Hub LITE

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Angxers2/Unihubreborn/main/UniversalHubLite.lua"))()
```

`raw.githubusercontent.com` answers with `cache-control: max-age=300`, so for
up to five minutes after a push the CDN can still hand out the previous file.
A `?v=` query string does **not** get around this — measured: two different
values both come back `x-cache: HIT` with the same etag. Nothing in the URL
defeats it.

So if an update seems not to have landed, wait a few minutes and execute
again. To check what is actually published rather than what a CDN node is
holding, ask the API, which is not cached:

```
gh api repos/Angxers2/Unihubreborn/contents/UniversalHubLite.lua --jq .size
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
