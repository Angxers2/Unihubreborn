local env = typeof(getgenv) == "function" and getgenv() or _G
env.UHUB_DEPRECATED_LOADER = true
env.UHUB_SOURCE = "https://universalhub.cc/lite/stable.lua"
loadstring(game:HttpGet("https://universalhub.cc/lite/stable.lua"))()

