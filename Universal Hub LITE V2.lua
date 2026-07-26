-- ════════════════════════════════════════════════════════════════════════
--  UNIVERSAL HUB LITE V2 — UI CORE
-- ════════════════════════════════════════════════════════════════════════

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

-- ── Workspace layout ────────────────────────────────────────────────────
-- All runtime files live under workspace/unihub/<sub>/<name>. Falls back to
-- flat "unihub_<name>" when the executor has no folder support.
WS = { ROOT = "unihub", ok = false }

function WS.init()
    -- Retry: executor filesystems lag right after inject, and a single failed
    -- probe would strand the session in flat mode.
    for attempt = 1, 4 do
        local success = pcall(function()
            if not makefolder then error("no makefolder") end
            if not (isfolder and isfolder(WS.ROOT)) then makefolder(WS.ROOT) end
            for _, d in ipairs({ "state", "logs", "art", "art/icons" }) do
                local p = WS.ROOT .. "/" .. d
                if not (isfolder and isfolder(p)) then makefolder(p) end
            end
            writefile(WS.ROOT .. "/state/probe.txt", "ok")
            WS.ok = isfile and isfile(WS.ROOT .. "/state/probe.txt") or false
        end)
        if not success then WS.ok = false end
        if WS.ok then break end
        task.wait(0.5)
    end
    print(WS.ok and "[UHub] workspace ready (unihub/)"
                or  "[UHub] no folder support - flat unihub_* files")
end

function WS.path(sub, name)
    if WS.ok then return WS.ROOT .. "/" .. sub .. "/" .. name end
    return "unihub_" .. name
end

WS.init()

-- ── Design tokens ───────────────────────────────────────────────────────
-- Global, not local: the main chunk has a 200-local cap and this script is
-- already large. Musicbot hit that ceiling and solved it the same way.
UI = {}

UI.accent      = Color3.fromRGB(237,   1,  64)   -- sampled from the Lite V2 mark
UI.accentHi    = Color3.fromRGB(255,  60, 105)
UI.accentDim   = Color3.fromRGB(160,   0,  43)
UI.glassFill   = Color3.fromRGB( 20,  20,  26)
UI.cardFill    = Color3.fromRGB( 18,  18,  24)
UI.textPrimary = Color3.fromRGB(244, 245, 248)
UI.textMuted   = Color3.fromRGB(142, 145, 156)
UI.ok          = Color3.fromRGB( 34, 197,  94)
UI.warn        = Color3.fromRGB(245, 158,  11)
UI.err         = Color3.fromRGB(239,  68,  68)

UI.IMG      = 42    -- icon / headshot size
UI.H        = 58    -- holder height; idle is an H x H square
UI.EXP_W    = 380   -- expanded bar + card width
UI.CHIP_H   = 44
UI.CHIP_GAP = 8
UI.MENU_GAP = 8
UI.HOLD_S   = 5     -- seconds a notification stays expanded

-- Type scale (one place, so the whole system resizes together)
UI.T_TITLE  = 17
UI.T_SUB    = 14
UI.T_ROW    = 13.5
UI.T_SMALL  = 11.5
UI.T_EYEBROW = 10

-- ── Themes ──────────────────────────────────────────────────────────────
-- Accent-only themes. The U-Lite mark ships in a matching tint per theme
-- (art/icons/icon_<id>.png), so switching re-skins the corner mark too.
UI.THEMES = {
    crimson  = { name = "Crimson",   p = Color3.fromRGB(237,   1,  64) },
    sunset   = { name = "Sunset",    p = Color3.fromRGB(249, 168,  37) },
    lime     = { name = "Lime",      p = Color3.fromRGB(132, 204,  22) },
    forest   = { name = "Forest",    p = Color3.fromRGB( 34, 197,  94) },
    cyan     = { name = "Cyan",      p = Color3.fromRGB( 34, 211, 238) },
    ocean    = { name = "Ocean",     p = Color3.fromRGB( 59, 130, 246) },
    indigo   = { name = "Indigo",    p = Color3.fromRGB( 99, 102, 241) },
    purple   = { name = "Purple",    p = Color3.fromRGB(168,  85, 247) },
    rosegold = { name = "Rose Gold", p = Color3.fromRGB(244, 114, 182) },
    mono     = { name = "Mono",      p = Color3.fromRGB(228, 228, 231) },
}
UI.THEME_ORDER = { "crimson","sunset","lime","forest","cyan","ocean",
                   "indigo","purple","rosegold","mono" }
UI.themeId = "crimson"

local function lift(c, k)   -- toward white
    return Color3.new(c.R + (1 - c.R) * k, c.G + (1 - c.G) * k, c.B + (1 - c.B) * k)
end
local function drop(c, k)   -- toward black
    return Color3.new(c.R * k, c.G * k, c.B * k)
end

function UI.setTheme(id)
    local t = UI.THEMES[id]
    if not t then return false end
    UI.themeId   = id
    UI.accent    = t.p
    UI.accentHi  = lift(t.p, 0.28)
    UI.accentDim = drop(t.p, 0.62)
    return true
end

-- Theme-matched corner mark, falling back to the default if the file is
-- missing (loadAsset returns "" and callers skip, so this never errors).
function UI.markFile()
    local f = WS.path("art/icons", "icon_" .. UI.themeId .. ".png")
    if typeof(isfile) == "function" and not isfile(f) then
        return WS.path("art/icons", "icon.png")
    end
    return f
end

-- ── Opacity ─────────────────────────────────────────────────────────────
-- 1.0 = the designed glass, lower = more see-through. Applied to the bar and
-- every card panel; the base values live here so there is one source of truth.
UI.OPACITY = 1
UI.BASE_BAR_T  = 0.24
UI.BASE_CARD_T = 0.12
-- Big reading surfaces (modal, script hub, picker) sit more solid than the
-- small corner cards: a glanceable card can afford to show the game through
-- it, a panel you read rows of text in cannot.
UI.BASE_PANEL_T = 0.03

function UI.barT()  return 1 - (1 - UI.BASE_BAR_T)  * UI.OPACITY end
function UI.cardT() return 1 - (1 - UI.BASE_CARD_T) * UI.OPACITY end
-- The opacity slider still applies, it just starts from a solider base.
function UI.panelT() return 1 - (1 - UI.BASE_PANEL_T) * UI.OPACITY end

function UI.setOpacity(v)
    UI.OPACITY = math.clamp(v, 0.25, 1)
    local tf = TweenInfo.new(0.15)
    if Bar and Bar.bar and Bar.expanded then
        TweenService:Create(Bar.bar, tf, { BackgroundTransparency = UI.barT() }):Play()
    end
    for _, c in ipairs({ CmdBar, Info, Perf, Settings, Profile }) do
        if c and c.panel and c.clip and c.clip.Visible then
            TweenService:Create(c.panel, tf, { BackgroundTransparency = UI.cardT() }):Play()
            c.panel:SetAttribute("_shownT", UI.cardT())
        end
    end
    if Modal and Modal.panel then
        TweenService:Create(Modal.panel, tf, { BackgroundTransparency = UI.panelT() }):Play()
        Modal.panel:SetAttribute("_shownT", UI.panelT())
    end
    for _, chip in ipairs((Bar and Bar.chips) or {}) do
        pcall(function()
            TweenService:Create(chip, tf, { BackgroundTransparency = UI.barT() }):Play()
        end)
    end
end


-- ════════════════════════════════════════════════════════════════════════
--  ASSETS
--  Icons and fonts are not embedded in this file -- they are PNGs and TTFs
--  fetched once from the repo and written into the executor's workspace.
--  After the first run they are local and nothing is downloaded again.
-- ════════════════════════════════════════════════════════════════════════
Assets = { done = false }

-- Raw file host for the assets folder. Override before executing to point
-- at a fork or a local mirror:  getgenv().UHUB_ASSETS = "https://.../assets/"
Assets.BASE = (getgenv and getgenv().UHUB_ASSETS)
    or "https://raw.githubusercontent.com/Angxers2/Unihub/main/assets/"

-- Where a manifest entry lands. "@name" means workspace ROOT, which is the
-- only place a custom font can be loaded from; everything else is relative
-- to the hub's own folder.
function Assets.localPath(dest)
    local root = dest:match("^@(.+)$")
    if root then return root end
    local sub, name = dest:match("^(.*)/([^/]+)$")
    return WS.path(sub, name)
end

-- Executors spell HTTP differently and any of them can be missing. Binary
-- comes back as a raw byte string, which writefile takes as-is.
function Assets.get(url)
    local ok, body = pcall(function() return game:HttpGet(url, true) end)
    if ok and type(body) == "string" and #body > 0 then return body end
    ok, body = pcall(function()
        local req = (syn and syn.request) or (http and http.request) or request
        if not req then error("no request()") end
        local r = req({ Url = url, Method = "GET" })
        return r and r.Body
    end)
    return (ok and type(body) == "string" and #body > 0) and body or nil
end

-- A 404 page is a perfectly valid string, and writing it as "icon.png"
-- would leave every glyph quietly broken with a file that exists. Check the
-- magic bytes instead of trusting the transfer.
function Assets.looksRight(dest, body)
    if not body or #body < 8 then return false end
    if dest:sub(-4) == ".png" then
        return body:sub(1, 4) == "\137PNG"
    end
    if dest:sub(-4) == ".ttf" then
        local h = body:sub(1, 4)
        return h == "\0\1\0\0" or h == "true" or h == "ttcf" or h == "OTTO"
    end
    return true
end

function Assets.have(dest)
    local p = Assets.localPath(dest)
    local ok, yes = pcall(function() return isfile and isfile(p) end)
    return ok and yes == true
end

function Assets.missing()
    local out = {}
    for _, e in ipairs(Assets.MANIFEST) do
        if not Assets.have(e[2]) then out[#out + 1] = e end
    end
    return out
end

-- Downloads sequentially and reports progress. Sequential on purpose:
-- Roblox's HTTP has a request budget and firing a hundred at once gets the
-- back half throttled or dropped, which is worse than waiting.
function Assets.fetch(list, onProgress)
    local okCount, failed = 0, {}
    for i, e in ipairs(list) do
        local body = Assets.get(Assets.BASE .. e[1])
        if body and Assets.looksRight(e[2], body) then
            local wrote = pcall(function()
                writefile(Assets.localPath(e[2]), body)
            end)
            if wrote then okCount = okCount + 1 else failed[#failed + 1] = e[1] end
        else
            failed[#failed + 1] = e[1]
        end
        if onProgress then pcall(onProgress, i, #list, e[1]) end
    end
    return okCount, failed
end

-- True when there is nothing left to fetch. Callers use this to decide
-- whether the splash needs a progress bar at all.
function Assets.ready()
    if not (typeof(writefile) == "function" and typeof(isfile) == "function") then
        -- No filesystem: the hub still runs, it just has no custom glyphs
        -- or font. Say so once rather than failing to start.
        return true, "no file access"
    end
    return #Assets.missing() == 0
end

-- Generated from assets/ by tools/gen_manifest.py -- do not hand-edit.
-- { remote path under Assets.BASE, local path to write }
Assets.MANIFEST = {
    -- Icons live under the workspace art folder.
    { "icons/icon.png", "art/icons/icon.png" },
    { "icons/icon_crimson.png", "art/icons/icon_crimson.png" },
    { "icons/icon_cyan.png", "art/icons/icon_cyan.png" },
    { "icons/icon_forest.png", "art/icons/icon_forest.png" },
    { "icons/icon_indigo.png", "art/icons/icon_indigo.png" },
    { "icons/icon_lime.png", "art/icons/icon_lime.png" },
    { "icons/icon_mono.png", "art/icons/icon_mono.png" },
    { "icons/icon_ocean.png", "art/icons/icon_ocean.png" },
    { "icons/icon_purple.png", "art/icons/icon_purple.png" },
    { "icons/icon_rosegold.png", "art/icons/icon_rosegold.png" },
    { "icons/icon_sunset.png", "art/icons/icon_sunset.png" },
    { "icons/logo.png", "art/icons/logo.png" },
    { "icons/sb_mark.png", "art/icons/sb_mark.png" },
    { "icons/sb_scriptblox.png", "art/icons/sb_scriptblox.png" },
    { "icons/shadow.png", "art/icons/shadow.png" },
    { "icons/st_accessibility.png", "art/icons/st_accessibility.png" },
    { "icons/st_activity.png", "art/icons/st_activity.png" },
    { "icons/st_anchor.png", "art/icons/st_anchor.png" },
    { "icons/st_aperture.png", "art/icons/st_aperture.png" },
    { "icons/st_apple.png", "art/icons/st_apple.png" },
    { "icons/st_arrow-up.png", "art/icons/st_arrow-up.png" },
    { "icons/st_box.png", "art/icons/st_box.png" },
    { "icons/st_brain.png", "art/icons/st_brain.png" },
    { "icons/st_calendar.png", "art/icons/st_calendar.png" },
    { "icons/st_camera.png", "art/icons/st_camera.png" },
    { "icons/st_chevron-right.png", "art/icons/st_chevron-right.png" },
    { "icons/st_circle-check.png", "art/icons/st_circle-check.png" },
    { "icons/st_circle-x.png", "art/icons/st_circle-x.png" },
    { "icons/st_clock.png", "art/icons/st_clock.png" },
    { "icons/st_cloud-fog.png", "art/icons/st_cloud-fog.png" },
    { "icons/st_coffee.png", "art/icons/st_coffee.png" },
    { "icons/st_copy.png", "art/icons/st_copy.png" },
    { "icons/st_corner-down-right.png", "art/icons/st_corner-down-right.png" },
    { "icons/st_cpu.png", "art/icons/st_cpu.png" },
    { "icons/st_crosshair.png", "art/icons/st_crosshair.png" },
    { "icons/st_dices.png", "art/icons/st_dices.png" },
    { "icons/st_disc-3.png", "art/icons/st_disc-3.png" },
    { "icons/st_drama.png", "art/icons/st_drama.png" },
    { "icons/st_eye.png", "art/icons/st_eye.png" },
    { "icons/st_flag.png", "art/icons/st_flag.png" },
    { "icons/st_footprints.png", "art/icons/st_footprints.png" },
    { "icons/st_gamepad-2.png", "art/icons/st_gamepad-2.png" },
    { "icons/st_gauge.png", "art/icons/st_gauge.png" },
    { "icons/st_gem.png", "art/icons/st_gem.png" },
    { "icons/st_ghost.png", "art/icons/st_ghost.png" },
    { "icons/st_glasses.png", "art/icons/st_glasses.png" },
    { "icons/st_globe.png", "art/icons/st_globe.png" },
    { "icons/st_hand.png", "art/icons/st_hand.png" },
    { "icons/st_hard-drive.png", "art/icons/st_hard-drive.png" },
    { "icons/st_headphones.png", "art/icons/st_headphones.png" },
    { "icons/st_heart.png", "art/icons/st_heart.png" },
    { "icons/st_image.png", "art/icons/st_image.png" },
    { "icons/st_info.png", "art/icons/st_info.png" },
    { "icons/st_keyboard.png", "art/icons/st_keyboard.png" },
    { "icons/st_lightbulb.png", "art/icons/st_lightbulb.png" },
    { "icons/st_list.png", "art/icons/st_list.png" },
    { "icons/st_lock.png", "art/icons/st_lock.png" },
    { "icons/st_map-pin.png", "art/icons/st_map-pin.png" },
    { "icons/st_maximize.png", "art/icons/st_maximize.png" },
    { "icons/st_memory-stick.png", "art/icons/st_memory-stick.png" },
    { "icons/st_mic.png", "art/icons/st_mic.png" },
    { "icons/st_minimize.png", "art/icons/st_minimize.png" },
    { "icons/st_moon.png", "art/icons/st_moon.png" },
    { "icons/st_mouse-pointer-2.png", "art/icons/st_mouse-pointer-2.png" },
    { "icons/st_move.png", "art/icons/st_move.png" },
    { "icons/st_music.png", "art/icons/st_music.png" },
    { "icons/st_person-standing.png", "art/icons/st_person-standing.png" },
    { "icons/st_plane.png", "art/icons/st_plane.png" },
    { "icons/st_radio.png", "art/icons/st_radio.png" },
    { "icons/st_refresh-cw.png", "art/icons/st_refresh-cw.png" },
    { "icons/st_rotate-cw.png", "art/icons/st_rotate-cw.png" },
    { "icons/st_ruler.png", "art/icons/st_ruler.png" },
    { "icons/st_scan-eye.png", "art/icons/st_scan-eye.png" },
    { "icons/st_search.png", "art/icons/st_search.png" },
    { "icons/st_server.png", "art/icons/st_server.png" },
    { "icons/st_settings-2.png", "art/icons/st_settings-2.png" },
    { "icons/st_shield.png", "art/icons/st_shield.png" },
    { "icons/st_shirt.png", "art/icons/st_shirt.png" },
    { "icons/st_skull.png", "art/icons/st_skull.png" },
    { "icons/st_sliders-horizontal.png", "art/icons/st_sliders-horizontal.png" },
    { "icons/st_smile.png", "art/icons/st_smile.png" },
    { "icons/st_snowflake.png", "art/icons/st_snowflake.png" },
    { "icons/st_sparkles.png", "art/icons/st_sparkles.png" },
    { "icons/st_star-fill.png", "art/icons/st_star-fill.png" },
    { "icons/st_star.png", "art/icons/st_star.png" },
    { "icons/st_sun.png", "art/icons/st_sun.png" },
    { "icons/st_terminal.png", "art/icons/st_terminal.png" },
    { "icons/st_trash-2.png", "art/icons/st_trash-2.png" },
    { "icons/st_triangle-alert.png", "art/icons/st_triangle-alert.png" },
    { "icons/st_unlock.png", "art/icons/st_unlock.png" },
    { "icons/st_user-round.png", "art/icons/st_user-round.png" },
    { "icons/st_user-x.png", "art/icons/st_user-x.png" },
    { "icons/st_users-round.png", "art/icons/st_users-round.png" },
    { "icons/st_users.png", "art/icons/st_users.png" },
    { "icons/st_video.png", "art/icons/st_video.png" },
    { "icons/st_wand-2.png", "art/icons/st_wand-2.png" },
    { "icons/st_wifi.png", "art/icons/st_wifi.png" },
    { "icons/st_wind.png", "art/icons/st_wind.png" },
    { "icons/st_wrench.png", "art/icons/st_wrench.png" },
    { "icons/st_x.png", "art/icons/st_x.png" },
    { "icons/st_zap.png", "art/icons/st_zap.png" },
    { "icons/wx_cloud-drizzle.png", "art/icons/wx_cloud-drizzle.png" },
    { "icons/wx_cloud-fog.png", "art/icons/wx_cloud-fog.png" },
    { "icons/wx_cloud-lightning.png", "art/icons/wx_cloud-lightning.png" },
    { "icons/wx_cloud-moon.png", "art/icons/wx_cloud-moon.png" },
    { "icons/wx_cloud-rain.png", "art/icons/wx_cloud-rain.png" },
    { "icons/wx_cloud-snow.png", "art/icons/wx_cloud-snow.png" },
    { "icons/wx_cloud-sun.png", "art/icons/wx_cloud-sun.png" },
    { "icons/wx_cloud.png", "art/icons/wx_cloud.png" },
    { "icons/wx_moon.png", "art/icons/wx_moon.png" },
    { "icons/wx_sun.png", "art/icons/wx_sun.png" },
    -- Fonts must sit at workspace ROOT: the executor maps root to
    -- rbxasset://models/LivePackages/, which is the only place a
    -- custom FontFace can be loaded from.
    { "fonts/Manrope-Bold.ttf", "@Manrope-Bold.ttf" },
    { "fonts/Manrope-ExtraBold.ttf", "@Manrope-ExtraBold.ttf" },
    { "fonts/Manrope-Light.ttf", "@Manrope-Light.ttf" },
    { "fonts/Manrope-Medium.ttf", "@Manrope-Medium.ttf" },
    { "fonts/Manrope-Regular.ttf", "@Manrope-Regular.ttf" },
    { "fonts/Manrope-SemiBold.ttf", "@Manrope-SemiBold.ttf" },
}

-- ── Asset loading ───────────────────────────────────────────────────────
-- Executors expose different custom-asset functions; try each. Returns ""
-- on failure so callers can skip a glyph instead of erroring.
function UI.loadAsset(filename)
    for _, fn in ipairs({ getcustomasset, getsynasset, getcustomassetfile }) do
        if typeof(fn) == "function" then
            local ok, id = pcall(fn, filename)
            if ok and type(id) == "string" and id ~= "" then return id end
        end
    end
    return ""
end

function UI.icon(name)
    return UI.loadAsset(WS.path("art/icons", name))
end

-- ── Manrope ─────────────────────────────────────────────────────────────
-- Builds the family JSON from the ttf content ids at workspace ROOT (the
-- executor maps root -> rbxasset://models/LivePackages/). Leaves UI.font nil
-- if the executor can't do custom fonts; applyFont then falls back to Gotham.
function UI.loadFont()
    pcall(function()
        local weights = {
            { name = "Light",     weight = 300, file = "Manrope-Light.ttf"     },
            { name = "Regular",   weight = 400, file = "Manrope-Regular.ttf"   },
            { name = "Medium",    weight = 500, file = "Manrope-Medium.ttf"    },
            { name = "SemiBold",  weight = 600, file = "Manrope-SemiBold.ttf"  },
            { name = "Bold",      weight = 700, file = "Manrope-Bold.ttf"      },
            { name = "ExtraBold", weight = 800, file = "Manrope-ExtraBold.ttf" },
        }
        local faces = {}
        for _, w in ipairs(weights) do
            local id = UI.loadAsset(w.file)
            if id ~= "" then
                faces[#faces + 1] = {
                    name = w.name, weight = w.weight,
                    style = "normal", assetId = id,
                }
            end
        end
        if #faces == 0 or typeof(writefile) ~= "function" then return end
        writefile("Manrope.json", HttpService:JSONEncode({
            name = "Manrope", faces = faces,
        }))
        local fam = UI.loadAsset("Manrope.json")
        if fam ~= "" then UI.font = fam end
    end)
end

function UI.applyFont(label, weight)
    -- Only text objects carry a font. Callers that walk a subtree and font
    -- everything would otherwise hit an ImageLabel and throw.
    if not (label and (label:IsA("TextLabel") or label:IsA("TextButton")
                       or label:IsA("TextBox"))) then
        return
    end
    weight = weight or Enum.FontWeight.SemiBold
    if UI.font then
        label.FontFace = Font.new(UI.font, weight, Enum.FontStyle.Normal)
    else
        local map = {
            [Enum.FontWeight.Light]     = Enum.Font.Gotham,
            [Enum.FontWeight.Regular]   = Enum.Font.Gotham,
            [Enum.FontWeight.Medium]    = Enum.Font.GothamMedium,
            [Enum.FontWeight.SemiBold]  = Enum.Font.GothamSemibold,
            [Enum.FontWeight.Bold]      = Enum.Font.GothamBold,
            [Enum.FontWeight.ExtraBold] = Enum.Font.GothamBlack,
        }
        label.Font = map[weight] or Enum.Font.GothamSemibold
    end
end

-- Tried at load time for the common case: the fonts are already on disk
-- from a previous run. On a first run they are not there yet, so the splash
-- calls this again once the download finishes.
UI.loadFont()

-- ── Glass ───────────────────────────────────────────────────────────────
-- The shared treatment: rounded + vertical colour/alpha gradient + a top
-- sheen. Every bar, chip and card goes through this, which is what makes
-- the system read as one thing. Returns the sheen so callers fade it with
-- the element.
function UI.glassify(frame, radius)
    radius = radius or 12
    local cor = Instance.new("UICorner", frame)
    cor.CornerRadius = UDim.new(0, radius)

    local g = Instance.new("UIGradient", frame)
    g.Rotation = 90
    g.Color = ColorSequence.new(Color3.fromRGB(46, 46, 58), Color3.fromRGB(15, 15, 19))
    g.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.0),
        NumberSequenceKeypoint.new(1, 0.18),
    })

    local sheen = Instance.new("Frame")
    sheen.Name = "Sheen"
    sheen.Size = UDim2.fromScale(1, 1)
    sheen.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    sheen.BackgroundTransparency = 1
    sheen.BorderSizePixel = 0
    sheen.ZIndex = (frame.ZIndex or 1) + 1
    sheen.Parent = frame
    local sc = Instance.new("UICorner", sheen)
    sc.CornerRadius = UDim.new(0, radius)
    local sg = Instance.new("UIGradient", sheen)
    sg.Rotation = 90
    sg.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0.0, 0.78),
        NumberSequenceKeypoint.new(0.5, 1.0),
        NumberSequenceKeypoint.new(1.0, 1.0),
    })
    return sheen
end

-- A faint accent bloom across the top of a panel. Same idea as the button
-- gradient -- lit from above, quiet enough to read as light rather than as
-- decoration -- but at panel scale so a dialogue feels lit, not painted.
function UI.accentWash(frame, strength)
    strength = strength or 0.88
    local w = Instance.new("Frame")
    w.Name = "AccentWash"
    w.Size = UDim2.fromScale(1, 1)
    w.BackgroundColor3 = UI.accent
    w.BackgroundTransparency = strength
    w.BorderSizePixel = 0
    w.ZIndex = (frame.ZIndex or 1) + 1
    w.Parent = frame
    local c = Instance.new("UICorner", w)
    c.CornerRadius = UDim.new(0, 14)
    local g = Instance.new("UIGradient", w)
    g.Rotation = 90
    g.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0.0, 0.0),
        NumberSequenceKeypoint.new(0.55, 1.0),
        NumberSequenceKeypoint.new(1.0, 1.0),
    })
    return w
end

-- ── Drop shadow ─────────────────────────────────────────────────────────
-- A 9-slice sibling rendered underneath `target`, mirroring its fade so it
-- rides whatever tween the target runs. `gate` can veto visibility.
function UI.dropShadow(target, grow, z, gate)
    local isImg = target:IsA("ImageLabel") or target:IsA("ImageButton")
    local prop = isImg and "ImageTransparency" or "BackgroundTransparency"

    local sh = Instance.new("ImageLabel")
    sh.Name = target.Name .. "Shadow"
    sh.AnchorPoint = Vector2.new(0.5, 0.5)
    sh.BackgroundTransparency = 1
    sh.Image = UI.icon("shadow.png")
    sh.ScaleType = Enum.ScaleType.Slice
    sh.SliceCenter = Rect.new(52, 52, 76, 76)
    sh.ImageTransparency = 1
    sh.ZIndex = z
    sh.Parent = target.Parent

    local function track()
        sh.Position = UDim2.new(
            0, target.AbsolutePosition.X - target.Parent.AbsolutePosition.X + target.AbsoluteSize.X / 2,
            0, target.AbsolutePosition.Y - target.Parent.AbsolutePosition.Y + target.AbsoluteSize.Y / 2 + 2)
        sh.Size = UDim2.fromOffset(target.AbsoluteSize.X + grow, target.AbsoluteSize.Y + grow)
    end
    local function fade()
        if gate and not gate() then sh.ImageTransparency = 1 return end
        local base = isImg and target[prop] or 0.5
        sh.ImageTransparency = math.clamp(base + 0.35, 0, 1)
    end

    target:GetPropertyChangedSignal("AbsolutePosition"):Connect(track)
    target:GetPropertyChangedSignal("AbsoluteSize"):Connect(track)
    target:GetPropertyChangedSignal(prop):Connect(fade)
    if isImg then target:GetPropertyChangedSignal("Image"):Connect(fade) end
    track() fade()
    return sh
end

-- ── Geometry ────────────────────────────────────────────────────────────
-- Positional hit-testing instead of MouseEnter/MouseLeave bookkeeping.
-- Elements tween out from under a stationary cursor and fire bogus Leave
-- events; that is the open/close oscillation bug class.
function UI.mouseInside(el, pad)
    if not el or not el.Visible then return false end
    pad = pad or 0
    local m = UserInputService:GetMouseLocation()
    local inset = game:GetService("GuiService"):GetGuiInset()
    local mx, my = m.X - inset.X, m.Y - inset.Y
    local p, s = el.AbsolutePosition, el.AbsoluteSize
    return mx >= p.X - pad and mx <= p.X + s.X + pad
       and my >= p.Y - pad and my <= p.Y + s.Y + pad
end

-- Raw-screen Y of an element's bottom edge. AbsolutePosition is inset-origin
-- but our ScreenGui is IgnoreGuiInset (raw origin), so the inset must be
-- added back -- otherwise every drawer lands ~36px too high, ON the bar.
-- The height an element is heading FOR, not the one it is rendering right
-- now. Every resize in this UI is a tween and every caller reflows the
-- instant it starts one, so measuring the live size lays the cards out
-- against the height the bar is *leaving* -- which is how the action tray
-- came to grow down over the card underneath it. Whoever starts a resize
-- stamps the destination here; layout reads it.
function UI.setTargetH(el, h)
    if el then el:SetAttribute("_th", h) end
end

function UI.targetH(el)
    if not el then return 0 end
    return el:GetAttribute("_th") or el.Size.Y.Offset
end

function UI.bottomY(el)
    -- Callers can run while the bar is between states (splash, theme
    -- rebuild, post-unexecute). Returning 0 lets them lay out harmlessly
    -- instead of throwing halfway through a reflow.
    if not el then return 0 end
    local inset = game:GetService("GuiService"):GetGuiInset()
    return el.AbsolutePosition.Y + inset.Y + UI.targetH(el)
end

-- ── Touch / mobile ──────────────────────────────────────────────────────
-- Mobile breaks three assumptions this UI was built on: there is no key to
-- press, there is no hover, and there is no Mouse.Hit to pick a world point
-- with. Each is handled at the point it matters rather than by forking the
-- whole interface.
UI.touch = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

-- Screen point -> world point. On desktop Mouse.Hit already answers this;
-- on touch there is no mouse, so raycast the camera ray manually.
function UI.worldPointAt(screenPos)
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local ray = cam:ViewportPointToRay(screenPos.X, screenPos.Y)
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = { LocalPlayer.Character }
    local hit = workspace:Raycast(ray.Origin, ray.Direction * 5000, rp)
    return hit and hit.Position or (ray.Origin + ray.Direction * 500)
end

-- Fires cb(worldPosition) for a tap or a click, whichever this device has.
-- Returns a connection-like table with :Disconnect().
function UI.onWorldPick(cb)
    local conns = {}
    if UI.touch then
        table.insert(conns, UserInputService.TouchTapInWorld:Connect(function(pos, processed)
            if processed then return end          -- tapped our own UI
            local p = UI.worldPointAt(pos)
            if p then cb(p) end
        end))
    else
        local mouse = LocalPlayer:GetMouse()
        table.insert(conns, UserInputService.InputBegan:Connect(function(i, processed)
            if processed then return end
            if i.UserInputType == Enum.UserInputType.MouseButton1 then
                if mouse.Hit then cb(mouse.Hit.Position) end
            end
        end))
    end
    return {
        Disconnect = function()
            for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
            conns = {}
        end,
        Connected = true,
    }
end

-- Hover is a desktop-only affordance. On touch, wire the same open/close to
-- a tap on an invisible button covering the element instead.
function UI.hoverOrTap(guiObject, onEnter, onLeave, isOpenFn)
    if not UI.touch then
        if onEnter then guiObject.MouseEnter:Connect(onEnter) end
        if onLeave then guiObject.MouseLeave:Connect(onLeave) end
        return nil
    end
    local btn = Instance.new("TextButton")
    btn.Name = "TapZone"
    btn.Size = UDim2.fromScale(1, 1)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.ZIndex = 60
    btn.Parent = guiObject
    btn.MouseButton1Click:Connect(function()
        if isOpenFn and isOpenFn() then
            if onLeave then onLeave() end
        else
            if onEnter then onEnter() end
        end
    end)
    return btn
end

-- ── Content fading ──────────────────────────────────────────────────────
-- Snapshots each element's "shown" transparency into a _shownT attribute on
-- first call, so restoring is exact instead of assuming 0.
function UI.fadeContent(panel, out, tween)
    local tf = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    for _, d in ipairs(panel:GetDescendants()) do
        local prop
        if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
            prop = "TextTransparency"
        elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
            prop = "ImageTransparency"
        elseif d:IsA("Frame") and d.Name ~= "Sheen"
              and d.Name ~= "AccentWash" and d.Name ~= "AccentEdge" then
            prop = "BackgroundTransparency"
        elseif d:IsA("UIStroke") then
            prop = "Transparency"
        end
        if prop then
            if d:GetAttribute("_shownT") == nil then
                d:SetAttribute("_shownT", d[prop])
            end
            local target = out and 1 or d:GetAttribute("_shownT")
            if tween then
                TweenService:Create(d, tf, { [prop] = target }):Play()
            else
                d[prop] = target
            end
        end
    end
end

-- ── Drawer ──────────────────────────────────────────────────────────────
-- An invisible clip sits flush with the bar's bottom edge; the glass panel
-- starts tucked UP inside it (hidden behind the bar) and tweens down into
-- view, so it emerges from underneath instead of popping on top.
function UI.makeDrawer(name, w, h, parentGui)
    local clip = Instance.new("Frame")
    clip.Name = name .. "Clip"
    clip.AnchorPoint = Vector2.new(1, 0)
    clip.Size = UDim2.fromOffset(w, h + 12)
    clip.BackgroundTransparency = 1
    clip.BorderSizePixel = 0
    clip.ClipsDescendants = true
    clip.Visible = false
    clip.ZIndex = 40
    clip.Parent = parentGui

    local p = Instance.new("Frame")
    p.Name = name
    p.AnchorPoint = Vector2.new(1, 0)
    p.Position = UDim2.new(1, 0, 0, -h)
    p.Size = UDim2.fromOffset(w, h)
    UI.setTargetH(p, h)
    p.BackgroundColor3 = UI.cardFill
    p.BackgroundTransparency = UI.cardT()
    p.BorderSizePixel = 0
    p.ZIndex = 41
    p.Parent = clip
    UI.glassify(p, 12)
    -- Same accent treatment as the modal, applied here so every card picks it
    -- up rather than each one remembering to ask.
    UI.accentWash(p, 0.93)
    return clip, p
end

-- Slides IN FROM THE RIGHT. The panel parks fully outside the clip's right
-- edge and travels left into place; the clip's ClipsDescendants hides the
-- parked state. Reads as the card coming out of the screen edge rather than
-- dropping out from under the bar.
function UI.openDrawerAtY(clip, p, screenY)
    local w = p.Size.X.Offset
    clip:SetAttribute("_closing", false)
    clip.Position = UDim2.new(1, -14, 0, screenY)
    clip.Visible = true
    p.Position = UDim2.new(1, w + 46, 0, 10)
    p.BackgroundTransparency = UI.cardT()
    TweenService:Create(p,
        TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        { Position = UDim2.new(1, 0, 0, 10) }):Play()
    UI.fadeContent(p, false)
    local sheen = p:FindFirstChild("Sheen")
    if sheen then
        sheen.BackgroundTransparency = 1
        TweenService:Create(sheen, TweenInfo.new(0.34),
            { BackgroundTransparency = 0 }):Play()
    end
end

-- Guarded by _closing so the several hide triggers can't restart the tween
-- and stutter the dissolve.
function UI.closeDrawer(clip, p)
    if not clip or not clip.Visible or clip:GetAttribute("_closing") then return end
    clip:SetAttribute("_closing", true)
    UI.fadeContent(p, true, true)
    local sheen = p:FindFirstChild("Sheen")
    if sheen then
        TweenService:Create(sheen, TweenInfo.new(0.18),
            { BackgroundTransparency = 1 }):Play()
    end
    local w = p.Size.X.Offset
    local t = TweenService:Create(p,
        TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
        { Position = UDim2.new(1, w + 46, 0, 10), BackgroundTransparency = 1 })
    t.Completed:Connect(function()
        if clip:GetAttribute("_closing") then clip.Visible = false end
        clip:SetAttribute("_closing", false)
    end)
    t:Play()
end

-- Tiny uppercase section label ("COMMANDS", "PLAYERS").
function UI.eyebrow(parent, text)
    local e = Instance.new("TextLabel")
    e.Name = "Eyebrow"
    e.Position = UDim2.new(0, 14, 0, 10)
    e.Size = UDim2.new(1, -28, 0, 12)
    e.BackgroundTransparency = 1
    e.Text = text
    e.TextColor3 = UI.textMuted
    e.TextXAlignment = Enum.TextXAlignment.Left
    e.TextSize = UI.T_EYEBROW
    e.ZIndex = 42
    e.Parent = parent
    UI.applyFont(e, Enum.FontWeight.Bold)
    return e
end

-- ── Headshots ───────────────────────────────────────────────────────────
-- Roster-first (instant, no API call), API fallback for offline names.
-- rbxthumb is built in and never fails the way the old headshot-thumbnail
-- HTTP URLs did.
function UI.headshotFor(username)
    local uid
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower() == (username or ""):lower() then uid = p.UserId break end
    end
    if not uid then
        pcall(function() uid = Players:GetUserIdFromNameAsync(username) end)
    end
    if uid then
        return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(uid) .. "&w=150&h=150"
    end
    return ""
end

-- ── Soft-gradient button ────────────────────────────────────────────────
-- The recipe from the design spec, expressed in Roblox terms:
--   linear-gradient(180deg, ...)  -> UIGradient, Rotation 90
--   box-shadow 0 0 0 1px <ring>   -> UIStroke one step darker than the fill
--   inset 0 1px 0 rgba(255,..,.9) -> a 1px top lip frame
-- Light is the shipped treatment: white -> grey fill, 300-weight ink, so it
-- reads clearly against the dark glass without competing with the accent.
UI.BTN = {
    light = {
        top = Color3.fromRGB(255, 255, 255),
        mid = Color3.fromRGB(237, 237, 242),
        bot = Color3.fromRGB(226, 226, 234),
        ring = Color3.fromRGB(201, 201, 212),
        ink = Color3.fromRGB(21, 21, 27),
        weight = Enum.FontWeight.Light,
        lip = 0.10,
    },
    accent = {
        top = Color3.fromRGB(255,  92, 130),
        mid = Color3.fromRGB(237,   1,  64),
        bot = Color3.fromRGB(201,   1,  58),
        ring = Color3.fromRGB(122,   0,  37),
        ink = Color3.fromRGB(255, 255, 255),
        weight = Enum.FontWeight.Medium,
        lip = 0.65,
    },
    ghost = {
        top = Color3.fromRGB(255, 255, 255),
        mid = Color3.fromRGB(255, 255, 255),
        bot = Color3.fromRGB(255, 255, 255),
        ring = Color3.fromRGB(255, 255, 255),
        ink = Color3.fromRGB(215, 217, 226),
        weight = Enum.FontWeight.Regular,
        lip = 1,
        flat = 0.94,   -- translucent instead of gradient-filled
    },
}

-- What gradButton will size a label to, without building one. Callers need
-- this BEFORE the buttons exist, to work out how much room the text beside
-- them may have.
function UI.btnWidth(label, hasIcon)
    local x = 11 + (hasIcon and 21 or 0)
    local tw
    local ok, sz = pcall(function()
        return game:GetService("TextService"):GetTextSize(
            label, 14, Enum.Font.GothamSemibold, Vector2.new(4000, 100))
    end)
    tw = (ok and sz and sz.X) or (#label * 7)
    return math.ceil(x + tw + 12)
end

function UI.gradButton(parent, label, iconFile, style)
    local sp = UI.BTN[style or "light"] or UI.BTN.light

    local b = Instance.new("TextButton")
    b.Name = "Btn"
    b.AutoButtonColor = false
    b.Text = ""
    b.BackgroundColor3 = sp.mid
    b.BackgroundTransparency = sp.flat or 0
    b.BorderSizePixel = 0
    b.Size = UDim2.fromOffset(10, 32)      -- width set by the caller
    b.ZIndex = 8
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)

    if not sp.flat then
        local g = Instance.new("UIGradient", b)
        g.Rotation = 90
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.0, sp.top),
            ColorSequenceKeypoint.new(0.6, sp.mid),
            ColorSequenceKeypoint.new(1.0, sp.bot),
        })
    end

    local ring = Instance.new("UIStroke", b)
    ring.Color = sp.ring
    ring.Thickness = 1
    ring.Transparency = sp.flat and 0.88 or 0.15

    -- the glossy inset lip along the top edge
    if not sp.flat then
        local lip = Instance.new("Frame")
        lip.Name = "Lip"
        lip.Position = UDim2.new(0, 3, 0, 1)
        lip.Size = UDim2.new(1, -6, 0, 1)
        lip.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        lip.BackgroundTransparency = sp.lip
        lip.BorderSizePixel = 0
        lip.ZIndex = 9
        lip.Parent = b
    end

    local x = 11
    if iconFile then
        local ic = Instance.new("ImageLabel")
        ic.AnchorPoint = Vector2.new(0, 0.5)
        ic.Position = UDim2.new(0, x, 0.5, 0)
        ic.Size = UDim2.fromOffset(15, 15)
        ic.BackgroundTransparency = 1
        ic.Image = UI.icon(iconFile)
        ic.ImageColor3 = sp.ink
        ic.ZIndex = 9
        ic.Parent = b
        x = x + 21
    end

    local t = Instance.new("TextLabel")
    t.AnchorPoint = Vector2.new(0, 0.5)
    t.Position = UDim2.new(0, x, 0.5, 0)
    t.Size = UDim2.new(1, -x - 11, 1, 0)
    t.BackgroundTransparency = 1
    t.Text = label
    t.TextColor3 = sp.ink
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.TextSize = 13.5
    t.ZIndex = 9
    t.Parent = b
    UI.applyFont(t, sp.weight)

    -- Real text measurement, not a per-character guess. GetTextSize needs a
    -- legacy Enum.Font (it cannot take a FontFace), so measure against the
    -- Gotham fallback -- close enough to Manrope, and it IS what renders if
    -- the custom font failed to load.
    local tw
    local ok, sz = pcall(function()
        return game:GetService("TextService"):GetTextSize(
            label, 13.5, Enum.Font.GothamMedium, Vector2.new(1000, 100))
    end)
    tw = (ok and sz and sz.X) or (#label * 7)
    b.Size = UDim2.fromOffset(math.ceil(x + tw + 12), 32)

    -- Gradient styles brighten toward their top stop; flat (ghost) styles
    -- are already white, so brightening does nothing -- they lift by becoming
    -- less transparent instead.
    b.MouseEnter:Connect(function()
        if sp.flat then
            TweenService:Create(b, TweenInfo.new(0.15),
                { BackgroundTransparency = math.max(0, sp.flat - 0.08) }):Play()
        else
            TweenService:Create(b, TweenInfo.new(0.15),
                { BackgroundColor3 = sp.top }):Play()
        end
    end)
    b.MouseLeave:Connect(function()
        if sp.flat then
            TweenService:Create(b, TweenInfo.new(0.15),
                { BackgroundTransparency = sp.flat }):Play()
        else
            TweenService:Create(b, TweenInfo.new(0.15),
                { BackgroundColor3 = sp.mid }):Play()
        end
    end)
    return b
end

-- Chip buttons are the same component at a lesser size: a follow-up is a
-- lesser event than the headline, and identically sized buttons would
-- compete with it. Everything inside gradButton is vertically centred, so
-- only the height and the glyph/type sizes move -- the horizontal layout is
-- untouched.
function UI.smallButton(b)
    b.Size = UDim2.fromOffset(math.max(48, b.Size.X.Offset - 6), 26)
    for _, d in ipairs(b:GetDescendants()) do
        if d:IsA("ImageLabel") then
            d.Size = UDim2.fromOffset(13, 13)
        elseif d:IsA("TextLabel") then
            d.TextSize = math.max(10, d.TextSize - 1)
        end
    end
    return b
end

-- Grey a gradient button out without rebuilding it. Each part has its own
-- resting transparency (the ghost style is a near-transparent white, not an
-- opaque one), so snapshot the designed value per part and offset from that
-- -- hardcoding a number here is what made the ghost button render solid.
function UI.dimButton(b, on)
    local add = on and 0.5 or 0
    local function part(d, prop)
        if d:GetAttribute("_t0") == nil then d:SetAttribute("_t0", d[prop]) end
        d[prop] = math.min(1, d:GetAttribute("_t0") + add)
    end
    part(b, "BackgroundTransparency")
    for _, d in ipairs(b:GetDescendants()) do
        if d:IsA("TextLabel") then part(d, "TextTransparency")
        elseif d:IsA("ImageLabel") then part(d, "ImageTransparency")
        elseif d:IsA("UIStroke") then part(d, "Transparency")
        elseif d:IsA("Frame") then part(d, "BackgroundTransparency") end
    end
    -- Active = false stops the hover tweens fighting the dim.
    b.Active = not on
    b.AutoButtonColor = false
end

-- ════════════════════════════════════════════════════════════════════════
--  BAR — the corner pill
-- ════════════════════════════════════════════════════════════════════════
Bar = {
    mode      = "idle",
    expanded  = false,
    connected = true,
    OFFLINE_T = 0.62,
    ONLINE_T  = 0.0,
    chips     = {},
}

function Bar.build()
    if Bar.gui then Bar.gui:Destroy() end
    local IMG, H = UI.IMG, UI.H

    local parent = (typeof(gethui) == "function" and gethui())
                or game:GetService("CoreGui")
    local sg = Instance.new("ScreenGui")
    sg.Name = "UHubLiteMini"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.DisplayOrder = 9999
    pcall(function() sg.Parent = parent end)
    Bar.gui = sg

    -- Right-edge pinned, so expanding grows LEFT and anything anchored to
    -- the left edge travels with it. ClipsDescendants genuinely clips the
    -- text away at idle rather than merely hiding it.
    local holder = Instance.new("Frame")
    holder.Name = "Holder"
    holder.AnchorPoint = Vector2.new(1, 0)
    holder.Position = UDim2.new(1, -14, 0, 14)
    holder.Size = UDim2.fromOffset(H, H)
    UI.setTargetH(holder, H)
    holder.BackgroundTransparency = 1
    holder.ClipsDescendants = true
    holder.Parent = sg
    Bar.holder = holder

    -- Fixed-height top row. Everything in the bar proper is centred against
    -- THIS, not the holder, so growing the holder for the action tray leaves
    -- the icon and text exactly where they were.
    local row = Instance.new("Frame")
    row.Name = "Row"
    row.Position = UDim2.new(0, 0, 0, 0)
    row.Size = UDim2.new(1, 0, 0, H)
    row.BackgroundTransparency = 1
    row.ZIndex = 3
    row.Parent = holder
    Bar.row = row

    local bar = Instance.new("Frame")
    bar.Name = "Bar"
    bar.Size = UDim2.fromScale(1, 1)
    bar.BackgroundColor3 = UI.glassFill
    bar.BackgroundTransparency = 1
    bar.BorderSizePixel = 0
    bar.ZIndex = 2
    bar.Parent = holder
    Bar.bar = bar
    Bar.sheen = UI.glassify(bar, 12)
    UI.accentWash(bar, 0.94)   -- wash only; an edge reads as clutter this small

    local hs = Instance.new("ImageLabel")
    hs.Name = "Headshot"
    hs.AnchorPoint = Vector2.new(0, 0.5)
    hs.Position = UDim2.new(0, 7, 0.5, 0)
    hs.Size = UDim2.fromOffset(IMG, IMG)
    hs.BackgroundTransparency = 1
    hs.ImageTransparency = 1
    hs.ZIndex = 4
    hs.Parent = row
    local hc = Instance.new("UICorner", hs)
    hc.CornerRadius = UDim.new(1, 0)
    Bar.headshot = hs

    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.AnchorPoint = Vector2.new(0, 0.5)
    icon.Position = UDim2.new(0, 7, 0.5, 0)
    icon.Size = UDim2.fromOffset(IMG, IMG)
    icon.BackgroundTransparency = 1
    icon.ScaleType = Enum.ScaleType.Fit
    icon.Image = UI.loadAsset(UI.markFile())
    icon.ImageTransparency = 1
    icon.ZIndex = 5
    icon.Parent = row
    local icc = Instance.new("UICorner", icon)
    icc.CornerRadius = UDim.new(0, 8)
    Bar.icon = icon

    local textX = 7 + IMG + 11
    Bar.textX = textX

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.AnchorPoint = Vector2.new(0, 1)
    title.Position = UDim2.new(0, textX, 0.5, 0)
    title.Size = UDim2.new(1, -textX - 14, 0, 24)
    title.BackgroundTransparency = 1
    title.TextColor3 = UI.textPrimary
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextYAlignment = Enum.TextYAlignment.Bottom
    title.TextSize = UI.T_TITLE
    title.TextTruncate = Enum.TextTruncate.AtEnd
    title.TextTransparency = 1
    title.Text = ""
    title.ZIndex = 4
    title.Parent = row
    UI.applyFont(title, Enum.FontWeight.Bold)
    Bar.titleLabel = title

    local sub = Instance.new("TextLabel")
    sub.Name = "Sub"
    sub.AnchorPoint = Vector2.new(0, 0)
    sub.Position = UDim2.new(0, textX, 0.5, 1)
    sub.Size = UDim2.new(1, -textX - 14, 0, 19)
    sub.BackgroundTransparency = 1
    sub.TextColor3 = UI.accent
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.TextYAlignment = Enum.TextYAlignment.Top
    sub.TextSize = UI.T_SUB
    sub.TextTruncate = Enum.TextTruncate.AtEnd
    sub.TextTransparency = 1
    sub.Text = ""
    sub.ZIndex = 4
    sub.Parent = row
    UI.applyFont(sub, Enum.FontWeight.SemiBold)
    Bar.subLabel = sub

    -- Status glyph sits INLINE at the head of the subtitle, never over the
    -- brand mark -- the icon is the identity and stays put.
    local glyph = Instance.new("ImageLabel")
    glyph.Name = "Glyph"
    glyph.AnchorPoint = Vector2.new(0, 0.5)
    glyph.Position = UDim2.new(0, textX, 0.5, 1 + 19 / 2)
    glyph.Size = UDim2.fromOffset(14, 14)
    glyph.BackgroundTransparency = 1
    glyph.ImageTransparency = 1
    glyph.ZIndex = 6
    glyph.Parent = row
    Bar.glyph = glyph

    -- Mini target headshot for the detail line (!goto John -> John's face).
    -- Hidden unless the command actually targets someone.
    local subIcon = Instance.new("ImageLabel")
    subIcon.Name = "SubIcon"
    subIcon.AnchorPoint = Vector2.new(0, 0.5)
    subIcon.Position = UDim2.new(0, textX, 0.5, 1 + 19 / 2)
    subIcon.Size = UDim2.fromOffset(17, 17)
    subIcon.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    subIcon.BackgroundTransparency = 1
    subIcon.ImageTransparency = 1
    subIcon.ZIndex = 6
    subIcon.Parent = row
    Instance.new("UICorner", subIcon).CornerRadius = UDim.new(1, 0)
    Bar.subIcon = subIcon

    -- Chip stack, right-aligned under the bar.
    local stack = Instance.new("Frame")
    stack.Name = "Stack"
    stack.AnchorPoint = Vector2.new(1, 0)
    stack.Position = UDim2.new(1, -14, 0, 14 + H + 6)
    stack.Size = UDim2.fromOffset(UI.EXP_W, 240)
    stack.BackgroundTransparency = 1
    stack.Parent = sg
    Bar.stack = stack
    Bar.chips = {}

    -- Action tray: lives under the row, height 0 until a notification with
    -- actions expands it.
    local tray = Instance.new("Frame")
    tray.Name = "Tray"
    tray.Position = UDim2.new(0, 0, 0, H)
    tray.Size = UDim2.new(1, 0, 0, 0)
    tray.BackgroundTransparency = 1
    tray.ClipsDescendants = true
    tray.ZIndex = 3
    tray.Parent = holder
    Bar.tray = tray

    -- Touch has no keybind, so the command bar needs a visible way in. This
    -- sits under the pill and is the single most useful control on mobile.
    if UI.touch then
        local kb = Instance.new("ImageButton")
        kb.Name = "TouchCmd"
        kb.AnchorPoint = Vector2.new(1, 0)
        kb.Position = UDim2.new(1, -14, 0, 14 + H + 8)
        kb.Size = UDim2.fromOffset(H, H)
        kb.BackgroundColor3 = UI.glassFill
        kb.BackgroundTransparency = 0.24
        kb.AutoButtonColor = false
        kb.Image = UI.icon("st_terminal.png")
        kb.ImageColor3 = UI.accent
        kb.ImageRectSize = Vector2.new(0, 0)
        kb.ScaleType = Enum.ScaleType.Fit
        kb.ZIndex = 25
        kb.Parent = sg
        UI.glassify(kb, 12)
        -- shrink the glyph inside the tappable square
        local pad = Instance.new("UIPadding", kb)
        pad.PaddingTop = UDim.new(0, 15); pad.PaddingBottom = UDim.new(0, 15)
        pad.PaddingLeft = UDim.new(0, 15); pad.PaddingRight = UDim.new(0, 15)
        kb.MouseButton1Click:Connect(function() CmdBar.toggle() end)
        Bar.touchCmd = kb
    end

    -- Transparent hit-catcher that GROWS with the bar, so the cursor stays
    -- inside while expanded (no open/close flicker).
    local hit = Instance.new("ImageButton")
    hit.Name = "Hit"
    -- Row height only, NOT the whole holder: at ZIndex 20 a full-size catcher
    -- sits over the action tray and eats every button click.
    hit.Size = UDim2.new(1, 0, 0, H)
    hit.BackgroundTransparency = 1
    hit.ImageTransparency = 1
    hit.AutoButtonColor = false
    hit.ZIndex = 20
    hit.Parent = holder
    Bar.hit = hit

    return sg
end

function Bar.setText(title, sub)
    if Bar.titleLabel then Bar.titleLabel.Text = title or "" end
    if Bar.subLabel then Bar.subLabel.Text = sub or "" end
end

-- Expand. useHeadshot crossfades icon -> requester headshot.
function Bar.open(useHeadshot)
    if not Bar.holder then return end
    -- Any expanded state shows the brand mark or a headshot in that slot, so
    -- retire the badge first rather than letting it sit on top.
    if Badge and Badge.shown then
        Badge.token = (Badge.token or 0) + 1
        Badge.shown = nil
        Badge.hide()
    end
    local ti = TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local tf = TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    UI.setTargetH(Bar.holder, UI.H)
    TweenService:Create(Bar.holder, ti,
        { Size = UDim2.fromOffset(UI.EXP_W, UI.H) }):Play()
    TweenService:Create(Bar.bar, tf, { BackgroundTransparency = UI.barT() }):Play()
    if Bar.sheen then
        TweenService:Create(Bar.sheen, tf, { BackgroundTransparency = 0 }):Play()
    end

    if useHeadshot then
        TweenService:Create(Bar.icon, tf, { ImageTransparency = 1 }):Play()
        TweenService:Create(Bar.headshot, tf, { ImageTransparency = 0 }):Play()
    else
        TweenService:Create(Bar.headshot, tf, { ImageTransparency = 1 }):Play()
        TweenService:Create(Bar.icon, tf, { ImageTransparency = 0 }):Play()
    end

    -- Text lands AFTER the bar has room; simultaneous reads as cramped.
    task.delay(0.10, function()
        TweenService:Create(Bar.titleLabel, tf, { TextTransparency = 0 }):Play()
        TweenService:Create(Bar.subLabel, tf, { TextTransparency = 0 }):Play()
    end)

    Bar.expanded = true
end

function Bar.close()
    if not Bar.holder then return end
    Bar.expanded = false
    Bar.mode = "idle"
    if Notify and Notify.collapseTray then Notify.collapseTray() end

    local ti = TweenInfo.new(0.40, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
    local tf = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    TweenService:Create(Bar.titleLabel, tf, { TextTransparency = 1 }):Play()
    TweenService:Create(Bar.subLabel, tf, { TextTransparency = 1 }):Play()
    TweenService:Create(Bar.headshot, tf, { ImageTransparency = 1 }):Play()
    TweenService:Create(Bar.glyph, tf, { ImageTransparency = 1 }):Play()
    if Bar.subIcon then
        TweenService:Create(Bar.subIcon, tf,
            { ImageTransparency = 1, BackgroundTransparency = 1 }):Play()
    end
    Bar.glyphOn, Bar.subIconOn = false, false

    local iconT = Bar.connected and Bar.ONLINE_T or Bar.OFFLINE_T
    TweenService:Create(Bar.icon, TweenInfo.new(0.34),
        { ImageTransparency = iconT }):Play()
    TweenService:Create(Bar.bar, TweenInfo.new(0.28),
        { BackgroundTransparency = 1 }):Play()
    if Bar.sheen then
        TweenService:Create(Bar.sheen, TweenInfo.new(0.28),
            { BackgroundTransparency = 1 }):Play()
    end
    UI.setTargetH(Bar.holder, UI.H)
    TweenService:Create(Bar.holder, ti,
        { Size = UDim2.fromOffset(UI.H, UI.H) }):Play()
end

-- Clean fade-in of the icon on execute.
function Bar.fadeIn()
    if not Bar.icon then return end
    Bar.icon.ImageTransparency = 1
    TweenService:Create(Bar.icon,
        TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { ImageTransparency = Bar.ONLINE_T }):Play()
end

-- ════════════════════════════════════════════════════════════════════════
--  NOTIFICATIONS — the bar IS the notification
-- ════════════════════════════════════════════════════════════════════════
Notify = { token = 0 }

Notify.glyphFor = {
    success = "st_circle-check.png",
    error   = "st_circle-x.png",
    warning = "st_triangle-alert.png",
    info    = "st_info.png",
}

Notify.colorFor = {
    success = UI.ok,
    error   = UI.err,
    warning = UI.warn,
    info    = UI.accent,
}

-- Is anything belonging to the notification hovered? Positional, so a tween
-- moving out from under a stationary cursor can't produce a false negative.
function Notify.hovered()
    return UI.mouseInside(Bar.holder, 4)
        or (#Bar.chips > 0 and UI.mouseInside(Bar.stack, 4))
end

-- Slide a chip into its slot under the bar.
function Notify.addChip(title, detail, status, actions)
    if not Bar.stack then return end
    -- Accumulate real heights: a chip carrying buttons is taller than one
    -- that is not, so a fixed slot pitch would overlap them.
    local slotY = 0
    for _, c in ipairs(Bar.chips) do
        slotY = slotY + c.Size.Y.Offset + UI.CHIP_GAP
    end
    local hasActions = actions and #actions > 0
    local chipH = UI.CHIP_H + (hasActions and 34 or 0)

    local chip = Instance.new("Frame")
    chip.Name = "Chip"
    chip.AnchorPoint = Vector2.new(1, 0)
    chip.Position = UDim2.new(1, 0, 0, slotY - 20)
    chip.Size = UDim2.fromOffset(UI.EXP_W - 26, chipH)
    chip.BackgroundColor3 = UI.glassFill
    chip.BackgroundTransparency = 1
    chip.BorderSizePixel = 0
    chip.ZIndex = 2
    chip.Parent = Bar.stack
    local chipSheen = UI.glassify(chip, 12)

    local arrow = Instance.new("ImageLabel")
    arrow.AnchorPoint = Vector2.new(0, 0.5)
    arrow.Position = UDim2.new(0, 11, 0, UI.CHIP_H / 2)
    arrow.Size = UDim2.fromOffset(15, 15)
    arrow.BackgroundTransparency = 1
    arrow.Image = UI.icon("st_corner-down-right.png")
    arrow.ImageColor3 = UI.accent
    arrow.ImageTransparency = 1
    arrow.ZIndex = 4
    arrow.Parent = chip

    local g = Instance.new("ImageLabel")
    g.AnchorPoint = Vector2.new(0, 0.5)
    g.Position = UDim2.new(0, 36, 0, UI.CHIP_H / 2)
    g.Size = UDim2.fromOffset(18, 18)
    g.BackgroundTransparency = 1
    g.Image = UI.icon(Notify.glyphFor[status] or Notify.glyphFor.info)
    g.ImageColor3 = Notify.colorFor[status] or UI.accent
    g.ImageTransparency = 1
    g.ZIndex = 4
    g.Parent = chip

    local tx = Instance.new("TextLabel")
    tx.AnchorPoint = Vector2.new(0, 0.5)
    tx.Position = UDim2.new(0, 62, 0, UI.CHIP_H / 2)
    tx.Size = UDim2.new(1, -74, 0, UI.CHIP_H)
    tx.BackgroundTransparency = 1
    tx.Text = (detail and detail ~= "") and detail or title
    tx.TextColor3 = Color3.fromRGB(224, 225, 230)
    tx.TextXAlignment = Enum.TextXAlignment.Left
    tx.TextSize = UI.T_ROW
    tx.TextTruncate = Enum.TextTruncate.AtEnd
    tx.TextTransparency = 1
    tx.ZIndex = 4
    tx.Parent = chip
    UI.applyFont(tx, Enum.FontWeight.SemiBold)

    -- A follow-up's buttons belong to the follow-up. They used to go into
    -- the bar's single shared tray, which meant the second notification of a
    -- burst drew its button on top of the first one's -- same frame, same x
    -- offsets -- so an Unmute button appeared to mutate into a Goto one
    -- while sitting next to the wrong message.
    local made = {}
    if hasActions then
        local GAP, total = 6, 0
        for _, a in ipairs(actions) do
            local b = UI.gradButton(chip, a.label, a.icon, a.style or "ghost")
            UI.smallButton(b)
            b.ZIndex = 5
            made[#made + 1] = { b, a }
            total = total + b.Size.X.Offset + GAP
        end
        local x = (UI.EXP_W - 26) - 12 - total + GAP
        for _, m in ipairs(made) do
            local b, a = m[1], m[2]
            local restY = UI.CHIP_H + 1
            b:SetAttribute("_y", restY)
            b.Position = UDim2.new(0, x, 0, restY + 8)   -- rises into place
            x = x + b.Size.X.Offset + GAP
            Notify.hideButton(b)
            b.MouseButton1Click:Connect(function()
                -- Only this chip goes; the rest of the burst is still
                -- readable and its buttons still work.
                Notify.hideButton(b)
                b.Active = false
                if a.run then task.delay(0.05, function() pcall(a.run) end) end
            end)
        end
    end

    table.insert(Bar.chips, chip)

    local ts = TweenInfo.new(0.36, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local tf = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    -- Buttons ride in with the chip rather than after a delay: the chip is
    -- itself the follow-up, so there is nothing left to wait for.
    for i, m in ipairs(made) do
        task.delay(0.10 + (i - 1) * 0.06, function()
            if m[1] and m[1].Parent then Notify.revealButton(m[1]) end
        end)
    end
    TweenService:Create(chip, ts, {
        Position = UDim2.new(1, 0, 0, slotY),
        BackgroundTransparency = 0.24,
    }):Play()
    TweenService:Create(chipSheen, tf, { BackgroundTransparency = 0 }):Play()
    TweenService:Create(arrow, tf, { ImageTransparency = 0 }):Play()
    TweenService:Create(g, tf, { ImageTransparency = 0 }):Play()
    TweenService:Create(tx, tf, { TextTransparency = 0 }):Play()
end

-- Slide every chip back up under the bar, fade, destroy.
function Notify.clearChips()
    local chips = Bar.chips
    Bar.chips = {}
    for _, c in ipairs(chips) do
        pcall(function()
            local ts = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
            local tf = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            local y = c.Position.Y.Offset
            TweenService:Create(c, ts, {
                Position = UDim2.new(1, 0, 0, y - 20),
                BackgroundTransparency = 1,
            }):Play()
            for _, d in ipairs(c:GetDescendants()) do
                if d:IsA("TextLabel") then
                    TweenService:Create(d, tf, { TextTransparency = 1 }):Play()
                elseif d:IsA("ImageLabel") then
                    TweenService:Create(d, tf, { ImageTransparency = 1 }):Play()
                elseif d:IsA("Frame") then
                    TweenService:Create(d, tf, { BackgroundTransparency = 1 }):Play()
                end
            end
        end)
        task.delay(0.32, function() pcall(function() c:Destroy() end) end)
    end
end

-- Hover-aware collapse: re-arms while hovered, collapses on leave.
function Notify.armCollapse(token, hold)
    task.delay(hold, function()
        if Notify.token ~= token then return end
        if Notify.hovered() then
            Notify.armCollapse(token, 0.5)
        else
            Notify.clearChips()
            Bar.close()
        end
    end)
end

-- The detail line is [status glyph] [target headshot] [text], any of which
-- may be absent. One function owns the geometry so the pieces can never
-- overlap or leave a gap.
function Notify.layoutSub()
    local x = Bar.textX
    if Bar.glyphOn then x = x + 20 end
    if Bar.subIconOn then
        Bar.subIcon.Position = UDim2.new(0, x, 0.5, 1 + 19 / 2)
        x = x + 23
    end
    Bar.subLabel.Position = UDim2.new(0, x, 0.5, 1)
    Bar.subLabel.Size = UDim2.new(1, -x - 14, 0, 19)
end

function Notify.showGlyph(status)
    local id = status and UI.icon(Notify.glyphFor[status] or Notify.glyphFor.info) or ""
    if id == "" then
        Bar.glyphOn = false
        Bar.glyph.ImageTransparency = 1
        Notify.layoutSub()
        return
    end
    Bar.glyphOn = true
    Bar.glyph.Image = id
    Bar.glyph.ImageColor3 = Notify.colorFor[status] or UI.accent
    Notify.layoutSub()
    TweenService:Create(Bar.glyph,
        TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { ImageTransparency = 0 }):Play()
end

-- Resolve a username to a circular headshot on the detail line. Roster-first,
-- so it is instant for anyone in the server; nil clears it.
function Notify.showSubIcon(username)
    if not Bar.subIcon then return end
    local img = username and UI.headshotFor(username) or ""
    if img == "" then
        Bar.subIconOn = false
        Bar.subIcon.ImageTransparency = 1
        Bar.subIcon.BackgroundTransparency = 1
        Notify.layoutSub()
        return
    end
    Bar.subIconOn = true
    Bar.subIcon.Image = img
    Notify.layoutSub()
    TweenService:Create(Bar.subIcon,
        TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { ImageTransparency = 0, BackgroundTransparency = 0.35 }):Play()
end

-- ── Action tray ─────────────────────────────────────────────────────────
-- Buttons appear 1.5s AFTER the toast lands: the message reads first, then
-- the actions arrive. Tray height is measured from the buttons, so two and
-- three actions each expand to exactly their own height.
Notify.TRAY_DELAY = 1.5

function Notify.clearTray()
    if Notify.trayTween then Notify.trayTween:Cancel() Notify.trayTween = nil end
    if Bar.tray then
        for _, c in ipairs(Bar.tray:GetChildren()) do pcall(function() c:Destroy() end) end
        Bar.tray.Size = UDim2.new(1, 0, 0, 0)
    end
    if Bar.holder and not Bar.expanded then return end
end

-- Hide/reveal a button WITHOUT assuming what "visible" means for it. Each
-- style has its own resting transparencies (the ghost button is deliberately
-- a near-transparent white, not an opaque one), so snapshot the designed
-- value per element and restore exactly that. Hardcoding 0 here is what made
-- the ghost button render as solid white with unreadable text.
local function eachPart(b, fn)
    fn(b, "BackgroundTransparency")
    for _, d in ipairs(b:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then fn(d, "TextTransparency")
        elseif d:IsA("ImageLabel") then fn(d, "ImageTransparency")
        elseif d:IsA("UIStroke") then fn(d, "Transparency")
        elseif d:IsA("Frame") then fn(d, "BackgroundTransparency") end
    end
end

function Notify.hideButton(b)
    eachPart(b, function(d, prop)
        if d:GetAttribute("_t") == nil then d:SetAttribute("_t", d[prop]) end
        d[prop] = 1
    end)
end

function Notify.revealButton(b)
    local tf = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    -- Rises to where the button actually lives. Hardcoding 0 was fine while
    -- the tray was the only host; a chip's buttons sit below its text row and
    -- would have flown up onto it.
    local restY = b:GetAttribute("_y") or 0
    TweenService:Create(b, tf,
        { Position = UDim2.new(0, b.Position.X.Offset, 0, restY) }):Play()
    eachPart(b, function(d, prop)
        local shown = d:GetAttribute("_t") or 0
        TweenService:Create(d, tf, { [prop] = shown }):Play()
    end)
end

-- actions: { {label=, icon=, style=, run=function() end}, ... }
function Notify.buildTray(actions, token)
    if not (Bar.tray and actions and #actions > 0) then return end

    local PAD_X, PAD_B, GAP = 14, 13, 8
    local x = PAD_X
    for i, a in ipairs(actions) do
        local style = a.style or (i == 1 and "light" or "ghost")
        local b = UI.gradButton(Bar.tray, a.label, a.icon, style)
        b.Position = UDim2.new(0, x, 0, 0)
        Notify.hideButton(b)
        x = x + b.Size.X.Offset + GAP

        b.MouseButton1Click:Connect(function()
            -- Both, so neither a pending tray reveal nor a pending collapse
            -- from this burst can still fire after it is torn down.
            Notify.token = Notify.token + 1
            Notify.burst = (Notify.burst or 0) + 1
            Notify.collapseTray()
            Notify.clearChips()
            Bar.close()
            -- Run AFTER the collapse: an action that raises its own
            -- notification would otherwise be shut by our own teardown.
            task.delay(0.34, function()
                if a.run then pcall(a.run) end
            end)
        end)
    end

    local h = 32 + PAD_B
    local ti = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    Notify.trayTween = TweenService:Create(Bar.tray, ti, { Size = UDim2.new(1, 0, 0, h) })
    Notify.trayTween:Play()
    UI.setTargetH(Bar.holder, UI.H + h)
    TweenService:Create(Bar.holder, ti,
        { Size = UDim2.fromOffset(UI.EXP_W, UI.H + h) }):Play()
    Cards.reflow(true)   -- anything stacked below glides down with it

    -- staggered fade + rise, 70ms apart
    local i = 0
    for _, b in ipairs(Bar.tray:GetChildren()) do
        if b:IsA("TextButton") then
            local delay = 0.06 + i * 0.07
            b.Position = UDim2.new(0, b.Position.X.Offset, 0, 8)
            task.delay(delay, function()
                if Notify.burst ~= token then return end
                Notify.revealButton(b)
            end)
            i = i + 1
        end
    end
end

function Notify.collapseTray()
    if not Bar.tray then return end
    if Notify.trayTween then Notify.trayTween:Cancel() Notify.trayTween = nil end
    local ti = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
    TweenService:Create(Bar.tray, ti, { Size = UDim2.new(1, 0, 0, 0) }):Play()
    -- Give the space back, or the cards stay parked where the buttons were.
    if Bar.holder and UI.targetH(Bar.holder) > UI.H then
        UI.setTargetH(Bar.holder, UI.H)
        TweenService:Create(Bar.holder, ti,
            { Size = UDim2.fromOffset(Bar.holder.Size.X.Offset, UI.H) }):Play()
        Cards.reflow(true)
    end
    task.delay(0.3, function()
        if Bar.tray then
            for _, c in ipairs(Bar.tray:GetChildren()) do pcall(function() c:Destroy() end) end
        end
    end)
end

-- ── The frozen public API ───────────────────────────────────────────────
-- ~100 call sites depend on this exact shape. Do not change it.
Notifications = {}

function Notifications:Notify(title, message, status, duration, actions, target)
    title    = title or "Universal Hub"
    message  = message or ""
    status   = status or "info"
    duration = duration or 4

    -- Self-heal: a notification can fire before startup has built the bar
    -- (the re-execute guard does exactly that). Never swallow it silently.
    if not Bar.holder then
        Bar.build()
        Bar.icon.ImageTransparency = Bar.ONLINE_T
    end

    Notify.token = Notify.token + 1
    local myToken = Notify.token

    local isFollowUp = (Bar.mode == "notify")
    if isFollowUp then
        -- Its buttons go WITH it, not into the bar's shared tray.
        Notify.addChip(title, message, status, actions)
    else
        Notify.burst = (Notify.burst or 0) + 1
        Bar.mode = "notify"
        Bar.setText(title, message)
        Bar.subLabel.TextColor3 = Notify.colorFor[status] or UI.accent
        -- The brand mark stays; the glyph goes inline on the subtitle line.
        Notify.showGlyph(status)
        Notify.showSubIcon(target)
        Bar.open(false)
    end

    -- Actions arrive after the message has had time to read. Only the
    -- headline uses the tray; a follow-up already put its buttons on its own
    -- chip above.
    --
    -- Guarded on the BURST, not the token. The token bumps on every
    -- notification, so a follow-up landing inside the 1.5s delay used to
    -- cancel the headline's buttons outright -- they simply never appeared.
    if actions and #actions > 0 and not isFollowUp then
        local myBurst = Notify.burst
        task.delay(Notify.TRAY_DELAY, function()
            if Notify.burst ~= myBurst or Bar.mode ~= "notify" then return end
            Notify.buildTray(actions, myBurst)
        end)
    end

    local hold = math.max(duration, UI.HOLD_S)
    if actions and #actions > 0 then hold = math.max(hold, Notify.TRAY_DELAY + 6) end
    Notify.armCollapse(myToken, hold)
end

function Notifications:Success(title, message, duration, actions, target)
    return self:Notify(title, message, "success", duration, actions, target)
end

function Notifications:Error(title, message, duration, actions, target)
    return self:Notify(title, message, "error", duration, actions, target)
end

function Notifications:Warning(title, message, duration, actions, target)
    return self:Notify(title, message, "warning", duration, actions, target)
end

function Notifications:Info(title, message, duration, actions, target)
    return self:Notify(title, message, "info", duration, actions, target)
end

-- Rest of your script continues here...


if getgenv().UniversalHubRunning then
    -- Notify auto-builds the bar for this, so tear it back down once the
    -- toast has collapsed -- otherwise a dead pill lingers with no handlers.
    Notifications:Warning("Universal Hub Lite",
        "Already running - rejoin to re-execute", 6)
    task.delay(8, function()
        pcall(function() if Bar.gui then Bar.gui:Destroy() end end)
    end)
    return
end

getgenv().UniversalHubRunning = true

-- ════════════════════════════════════════════════════════════════════════
--  SPLASH — 2 seconds, not 11
-- ════════════════════════════════════════════════════════════════════════
Splash = {}

function Splash.play(onDone)
    local sg = Instance.new("ScreenGui")
    sg.Name = "UHubLiteSplash"
    sg.IgnoreGuiInset = true
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 10000
    pcall(function()
        sg.Parent = (typeof(gethui) == "function" and gethui())
                 or game:GetService("CoreGui")
    end)

    local blur = Instance.new("BlurEffect")
    blur.Size = 0
    blur.Parent = game:GetService("Lighting")

    local logo = Instance.new("ImageLabel")
    logo.AnchorPoint = Vector2.new(0.5, 0.5)
    logo.Position = UDim2.new(0.5, 0, 0.5, 0)
    logo.Size = UDim2.new(0.48, 0, 0.48, 0)
    logo.BackgroundTransparency = 1
    logo.ScaleType = Enum.ScaleType.Fit
    logo.Image = UI.icon("logo.png")
    logo.ImageTransparency = 1
    logo.Parent = sg

    local inInfo  = TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    local outInfo = TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.In)

    TweenService:Create(logo, inInfo, {
        ImageTransparency = 0,
        Size = UDim2.new(0.52, 0, 0.52, 0),
    }):Play()
    TweenService:Create(blur, inInfo, { Size = 14 }):Play()

    -- ── First run: fetch the assets before anything is drawn with them ──
    local need = (Assets and Assets.missing and Assets.missing()) or {}
    local canWrite = typeof(writefile) == "function"

    -- The splash draws logo.png, which on a first run has not arrived yet.
    -- Fetch it first so the wordmark appears within a second instead of the
    -- screen sitting empty for the whole download.
    for i, e in ipairs(need) do
        if e[1] == "icons/logo.png" then
            table.remove(need, i)
            table.insert(need, 1, e)
            break
        end
    end

    local bar, barFill, barText
    if #need > 0 and canWrite then
        barText = Instance.new("TextLabel")
        barText.AnchorPoint = Vector2.new(0.5, 0)
        barText.Position = UDim2.new(0.5, 0, 0.62, 0)
        barText.Size = UDim2.fromOffset(400, 18)
        barText.BackgroundTransparency = 1
        barText.Text = "Downloading assets  0 / " .. #need
        barText.TextColor3 = Color3.fromRGB(226, 228, 236)
        barText.TextSize = 14
        barText.TextTransparency = 1
        -- Manrope is one of the things being downloaded, so this one label
        -- has to use a stock font or the splash has nothing to render with.
        barText.Font = Enum.Font.GothamMedium
        barText.Parent = sg

        bar = Instance.new("Frame")
        bar.AnchorPoint = Vector2.new(0.5, 0)
        bar.Position = UDim2.new(0.5, 0, 0.62, 26)
        bar.Size = UDim2.fromOffset(260, 4)
        bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        bar.BackgroundTransparency = 0.85
        bar.BorderSizePixel = 0
        bar.Parent = sg
        Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

        barFill = Instance.new("Frame")
        barFill.Size = UDim2.new(0, 0, 1, 0)
        barFill.BackgroundColor3 = UI.accent
        barFill.BorderSizePixel = 0
        barFill.Parent = bar
        Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

        TweenService:Create(barText, inInfo, { TextTransparency = 0.15 }):Play()
    end

    local function finish()
        TweenService:Create(logo, outInfo, { ImageTransparency = 1 }):Play()
        TweenService:Create(blur, outInfo, { Size = 0 }):Play()
        if barText then
            TweenService:Create(barText, outInfo, { TextTransparency = 1 }):Play()
            TweenService:Create(bar, outInfo, { BackgroundTransparency = 1 }):Play()
            TweenService:Create(barFill, outInfo, { BackgroundTransparency = 1 }):Play()
        end
        task.delay(0.5, function()
            pcall(function() sg:Destroy() end)
            pcall(function() blur:Destroy() end)
            -- Fonts arrive with the assets, so the family has to be built
            -- AFTER the download rather than at load time.
            pcall(UI.loadFont)
            if onDone then onDone() end
        end)
    end

    if #need > 0 and canWrite then
        task.spawn(function()
            local okCount, failed = Assets.fetch(need, function(i, total, remote)
                if remote == "icons/logo.png" then
                    -- It exists on disk as of this callback, so it can be
                    -- loaded now rather than after everything else.
                    local id = UI.icon("logo.png")
                    if id ~= "" then logo.Image = id end
                end
                if not barFill then return end
                barFill.Size = UDim2.new(i / total, 0, 1, 0)
                barText.Text = "Downloading assets  " .. i .. " / " .. total
            end)
            Assets.done = true
            if #failed > 0 then
                -- Named, not swallowed: a missing glyph with no explanation
                -- looks like the script is broken.
                task.delay(1.2, function()
                    Notifications:Info("Universal Hub Lite",
                        #failed .. " of " .. #need .. " assets failed to download"
                        .. "  \194\183  re-execute to retry", 6)
                end)
            end
            -- Hold the splash briefly at 100% so it does not vanish the
            -- instant the last file lands.
            task.wait(0.35)
            finish()
        end)
    else
        task.delay(1.2, finish)
    end
end






local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Variables
local savedPosition = nil
local clickTpKey = nil
local isInfJumpEnabled = false
local isSpinning = false
local spinConnection = nil
local spinSpeed = 0
local viewedPlayer = nil
local viewConnection = nil
local clickTpConnection = nil
local flyConnection = nil
local noClipConnection = nil
local isFlying = false
_G.CmdBarKeybind = Enum.KeyCode.T





-- Function to find a player by partial name (case-insensitive)
-- ── Player tokens ───────────────────────────────────────────────────────
-- Words that stand in for a player argument. One table, consulted by the
-- resolver AND the suggestion list, so a command does not have to know these
-- exist to accept them -- anything routing through findPlayer/resolveTargets
-- gets "all", "random" and the rest for free.
-- scope "one": resolves to a single player, so it fits ANY player command --
-- "goto random" is a real thing to want.
-- scope "many": only for commands that can act on a crowd. "goto all" is
-- nonsense, so those tokens are offered and accepted only where a command
-- has opted in.
PlayerTokens = {
    { key = "random", label = "Random player", icon = "st_dices.png",
      desc = "One at random, not you", scope = "one" },
    { key = "nearest", label = "Nearest player", icon = "st_map-pin.png",
      desc = "Whoever is closest to you", scope = "one" },
    { key = "me",     label = "You",           icon = "st_user-round.png",
      desc = "Yourself", scope = "many" },
    { key = "all",    label = "All players",   icon = "st_users.png",
      desc = "Everyone in the server, you included", scope = "many" },
    { key = "others", label = "Everyone else", icon = "st_users-round.png",
      desc = "Everyone except you", scope = "many" },
}

PlayerTokens.byKey = {}
for _, t in ipairs(PlayerTokens) do PlayerTokens.byKey[t.key] = t end
-- A couple of spellings people reach for anyway.
PlayerTokens.alias = { everyone = "all", ["@a"] = "all", rand = "random",
                       rnd = "random", closest = "nearest", self = "me" }

-- Alias -> canonical command, so per-command wording does not have to be
-- repeated for "mute", "mutevc" and "vcmute".
function PlayerTokens.canon(cmd)
    cmd = tostring(cmd or ""):lower()
    local gi = CmdBar and CmdBar.aliasOf and CmdBar.aliasOf[cmd]
    local g = gi and CmdBar.aliasGroups and CmdBar.aliasGroups[gi]
    return (g and g[1]) or cmd
end

-- A token's generic wording is not always honest. "You / Yourself" is fine
-- for hitbox, but on a mute it hides what actually happens -- muting
-- yourself is your MICROPHONE, not your ears, and a row reading "You" leaves
-- you guessing which.
PlayerTokens.copy = {
    ["mutevc|me"]      = { "Your mic",      "Mute yourself so nobody hears you" },
    ["unmutevc|me"]    = { "Your mic",      "Unmute yourself so people hear you again" },
    ["mutevc|all"]     = { "Everyone",      "Every voice in the server, your mic included" },
    ["unmutevc|all"]   = { "Everyone",      "Every voice in the server, your mic included" },
    ["mutevc|others"]  = { "Everyone else", "Every voice but yours -- your mic stays on" },
    ["unmutevc|others"]= { "Everyone else", "Every voice but yours" },
}

function PlayerTokens.textFor(cmd, t)
    local o = PlayerTokens.copy[PlayerTokens.canon(cmd) .. "|" .. t.key]
    if o then return o[1], o[2] end
    return t.label, t.desc
end

-- What you can actually type for a token. The key first, then its aliases,
-- so the row can say so -- a label reading "All players" does not tell you
-- the word is "all", and guessing is the whole problem.
function PlayerTokens.spellings(key)
    local out = { key }
    for alias, target in pairs(PlayerTokens.alias) do
        if target == key then out[#out + 1] = alias end
    end
    -- pairs() order is undefined, so sort or the row text changes per render
    table.sort(out, function(a, b)
        if #a ~= #b then return #a < #b end
        return a < b
    end)
    return out
end

-- Commands that can act on a crowd. Everything else gets the "one" tokens
-- only, so "goto all" stays as invalid as it should be.
PlayerTokens.crowdCmds = {
    mutevc = true, unmutevc = true, mute = true, unmute = true,
    freeze = true, unfreeze = true, thaw = true,
    hitbox = true, whisper = true, pm = true,
}

function PlayerTokens.crowd(cmd)
    return PlayerTokens.crowdCmds[tostring(cmd or ""):lower()] == true
end

-- Display order, most useful first. It differs by command kind: "all" is the
-- headline for a mute and does not exist for a goto. Whatever is cut when
-- the list is capped is cut from the end, so this decides what survives.
PlayerTokens.ORDER_CROWD = { "all", "random", "others", "nearest", "me" }
PlayerTokens.ORDER_ONE   = { "random", "nearest" }

-- Tokens this command will actually take, minus any a real player has taken
-- the name of.
function PlayerTokens.forCommand(cmd)
    local order = PlayerTokens.crowd(cmd) and PlayerTokens.ORDER_CROWD
                                          or PlayerTokens.ORDER_ONE
    local out = {}
    for _, key in ipairs(order) do
        local t = PlayerTokens.byKey[key]
        if t and not PlayerTokens.shadowed(key) then out[#out + 1] = t end
    end
    return out
end

-- Somebody in the server is genuinely called this. A real player is a
-- concrete target and the token is a convenience, so the player wins and the
-- token stops existing for as long as they are here -- for the resolver AND
-- the suggestion list, or the list would offer a row you cannot select.
function PlayerTokens.shadowed(word)
    word = tostring(word or ""):lower()
    for _, p in ipairs(Players:GetPlayers()) do
        -- You never shadow a token. "me" already means you, so letting your
        -- own name kill it is circular, and you are not offered as a target
        -- anyway -- if you happen to be called "random", the token is the
        -- more useful reading.
        if p ~= LocalPlayer
           and (p.Name:lower() == word or p.DisplayName:lower() == word) then
            return p
        end
    end
    return nil
end

function PlayerTokens.resolve(word, cmd)
    word = tostring(word or ""):lower()
    if PlayerTokens.shadowed(word) then return nil end
    word = PlayerTokens.alias[word] or word
    -- The alias could also be shadowed: "rand" resolving to "random" must
    -- still lose to a player actually called rand.
    if PlayerTokens.shadowed(word) then return nil end
    local t = PlayerTokens.byKey[word]
    if not t then return nil end
    -- A crowd token typed at a single-target command is not a target, it is
    -- a typo -- let it fall through to the name lookup and fail honestly.
    if t.scope == "many" and cmd and not PlayerTokens.crowd(cmd) then return nil end
    return t
end

-- Every target a token names. Returns a LIST, always -- a single player is a
-- list of one, so callers do not need two code paths.
function PlayerTokens.expand(word, cmd)
    local tok = PlayerTokens.resolve(word, cmd)
    if not tok then return nil end

    if tok.key == "me" then return { LocalPlayer }, tok end

    local others = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then others[#others + 1] = p end
    end

    if tok.key == "all" then
        local all = { LocalPlayer }
        for _, p in ipairs(others) do all[#all + 1] = p end
        return all, tok
    end
    if tok.key == "others" then return others, tok end
    if tok.key == "random" then
        if #others == 0 then return {}, tok end
        -- Deterministic seeding would give the same "random" pick every time
        -- in a session, so seed off the clock.
        local n = math.floor((os.clock() * 1000) % #others) + 1
        return { others[n] }, tok
    end
    if tok.key == "nearest" then
        local best, bestD
        for _, p in ipairs(others) do
            local d = CmdBar and CmdBar.distanceTo and CmdBar.distanceTo(p.Name)
                      or math.huge
            if not bestD or d < bestD then best, bestD = p, d end
        end
        return best and { best } or {}, tok
    end
    return nil
end

local function findPlayer(nameSegment, cmd)
    if not nameSegment or nameSegment == "" then return nil end

    -- Tokens first, but resolve() has already stepped aside for a real
    -- player of the same name, so the exact-name loop below still wins.
    local list = PlayerTokens.expand(nameSegment, cmd)
    if list then return list[1] end     -- single-target callers take the first

    nameSegment = nameSegment:lower()
    for _, player in pairs(Players:GetPlayers()) do
        if player.Name:lower():sub(1, #nameSegment) == nameSegment or
           player.DisplayName:lower():sub(1, #nameSegment) == nameSegment then
            return player
        end
    end
    return nil
end

-- What a command should actually act on. A token expands to however many it
-- names, a name to one, and nothing to you -- so "unmutevc" bare unmutes
-- yourself. Opt-in: findPlayer still returns nil for an empty argument, so
-- the ~100 commands built on it keep erroring rather than silently
-- retargeting themselves.
function resolveTargets(word, cmd)
    if not word or word == "" then return { LocalPlayer }, nil end
    local list, tok = PlayerTokens.expand(word, cmd)
    if list then return list, tok end
    local p = findPlayer(word, cmd)
    return p and { p } or {}, nil
end

-- NoClip function
local function setNoClip(enabled)
    if noClipConnection and noClipConnection.Connected then
        noClipConnection:Disconnect()
        noClipConnection = nil
    end
    
    if not enabled then
        return
    end
    
    
    noClipConnection = RunService.Stepped:Connect(function()
        local character = LocalPlayer.Character
        if not character then return end
        
        for _, part in pairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

-- Improved Fly function using CFrame
-- ── Fly ─────────────────────────────────────────────────────────────────
-- Ported from the musicbot fly: velocity is EASED rather than snapped, and
-- the styled animations are picked from the resulting speed, so the pose
-- visibly walks idle -> slow -> medium -> fast on the way up and back down
-- as you slow. Each animation carries its own lean; the body is never
-- tilted in code. Stopping descends and plays a one-shot ground-hit.
local FLY = {
    anims = {
        idle   = 73559727995551,
        slow   = 92365791487740,
        medium = 114833664438028,
        fast   = 117803396402998,
        land   = 79698004825744,
    },
    accelTau = 0.32,   -- velocity ease; bigger = gentler ramp, lets tiers cycle
    fade     = 0.28,   -- animation crossfade
    bobAmp   = 0.25, bobFreq = 2.2,   -- subtle idle float
    -- hysteresis: separate thresholds up vs down so the tier cannot flicker
    up   = { idle = 4,   slow = 26, medium = 62 },
    down = { slow = 2.5, medium = 18, fast = 46 },
    landSpeed = 26, landTrigger = 5, landTimeout = 2.6,
}

local flyTracks, flyTier, flyVel = nil, "idle", Vector3.new(0, 0, 0)
local flyPhase, flyLandStart, flySpeed = "idle", 0, 50

local function flyLoadTracks(humanoid)
    local tracks = {}
    for name, id in pairs(FLY.anims) do
        pcall(function()
            local a = Instance.new("Animation")
            a.AnimationId = "rbxassetid://" .. tostring(id)
            local t = humanoid:LoadAnimation(a)
            t.Priority = Enum.AnimationPriority.Action
            t.Looped = (name ~= "land")
            tracks[name] = t
        end)
    end
    return tracks
end

-- One step at a time, with hysteresis, so it walks through the poses
-- instead of snapping between them.
local function flyTierFor(speed)
    local t = flyTier
    if t == "idle"   and speed > FLY.up.idle     then return "slow"   end
    if t == "slow"   and speed > FLY.up.slow     then return "medium" end
    if t == "medium" and speed > FLY.up.medium   then return "fast"   end
    if t == "fast"   and speed < FLY.down.fast   then return "medium" end
    if t == "medium" and speed < FLY.down.medium then return "slow"   end
    if t == "slow"   and speed < FLY.down.slow   then return "idle"   end
    return t
end

local function flySetTier(name)
    if flyTier == name or not flyTracks then return end
    local prev, nxt = flyTracks[flyTier], flyTracks[name]
    if nxt  then nxt:Play(FLY.fade) end
    if prev then prev:Stop(FLY.fade) end
    flyTier = name
end

local function flyCleanup()
    if flyConnection then flyConnection:Disconnect() flyConnection = nil end
    workspace.Gravity = 196.2
    setNoClip(false)
    local char = LocalPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum.PlatformStand = false end
    local animate = char and char:FindFirstChild("Animate")
    if animate then animate.Disabled = false end
    isFlying = false
    flyPhase = "idle"
    flyTier  = "idle"
    flyVel   = Vector3.new(0, 0, 0)
end

-- ── Animation control (ported from musicbot) ────────────────────────────
-- Disable the default Animate script while a custom track plays, or it
-- immediately overrides it; re-enable when the track stops.
function playAnimation(animationId, timePosition, speed)
    pcall(function()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        local animate = char:FindFirstChild("Animate")
        if animate then animate.Disabled = false end
        for _, t in pairs(hum:GetPlayingAnimationTracks()) do t:Stop() end
        if animate then animate.Disabled = true end

        local a = Instance.new("Animation")
        a.AnimationId = "rbxassetid://" .. tostring(animationId)
        local track = hum:LoadAnimation(a)
        track:Play()
        if timePosition then track.TimePosition = timePosition end
        if speed then track:AdjustSpeed(speed) end
        track.Stopped:Connect(function()
            if animate then animate.Disabled = false end
        end)
    end)
end

function stopAnimation()
    pcall(function()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local animate = char and char:FindFirstChild("Animate")
        if animate then animate.Disabled = false end
        if hum then
            for _, t in pairs(hum:GetPlayingAnimationTracks()) do t:Stop() end
        end
    end)
end

-- ── Attachment behaviours (ported from musicbot) ────────────────────────
-- headsit / backpack / drag / attach / stare / copydance. Each is a single
-- RenderStepped or Heartbeat loop that re-anchors the character against a
-- target every frame, plus one stop path that also clears the body movers.
-- All of them share stopAllAttach() so two can never fight over the root.
local getRootPart = function(char)
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
end

isHeadSitting, headSitConnection, headSitTarget = false, nil, nil
isBackpacking, backpackConnection, backpackTarget = false, nil, nil
isDragging, dragConnection, dragTarget = false, nil, nil
isAttached, attachConnection, attachTarget = false, nil, nil
isStaring, stareConnection, stareTarget = false, nil, nil
isCopyDancing, danceConnections, danceTarget = false, {}, nil

local ATTACH_OFFSET = CFrame.new(0, 0, -2)
local DRAG_ANIM_ID  = 10714360343

function stopHeadSit()
    isHeadSitting, headSitTarget = false, nil
    if headSitConnection then headSitConnection:Disconnect() headSitConnection = nil end
    local char = LocalPlayer.Character
    local root = getRootPart(char)
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if root then
        local st = root:FindFirstChild("HeadSitStabilizer")
        if st then st:Destroy() end
    end
    if hum then hum.Sit = false end
end

function startHeadSit(target)
    stopAllAttach()
    local char = LocalPlayer.Character
    local root = getRootPart(char)
    if not (target and target.Character and root) then return false end
    if not target.Character:FindFirstChild("Head") then return false end

    isHeadSitting, headSitTarget = true, target

    -- Without this the character spins freely while parented to a moving head.
    local stab = Instance.new("BodyAngularVelocity")
    stab.Name = "HeadSitStabilizer"
    stab.AngularVelocity = Vector3.new(0, 0, 0)
    stab.MaxTorque = Vector3.new(50000, 50000, 50000)
    stab.P = 1250
    stab.Parent = root

    headSitConnection = RunService.Heartbeat:Connect(function()
        if not (isHeadSitting and headSitTarget and Players:FindFirstChild(headSitTarget.Name)) then
            stopHeadSit() return
        end
        pcall(function()
            local head = headSitTarget.Character and headSitTarget.Character:FindFirstChild("Head")
            local lroot = getRootPart(LocalPlayer.Character)
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if head and lroot and hum then
                hum.Sit = true
                lroot.CFrame = head.CFrame * CFrame.new(0, 2, 0)
                lroot.Velocity = Vector3.new(0, 0, 0)
            end
        end)
    end)
    return true
end

function stopBackpacking()
    isBackpacking, backpackTarget = false, nil
    if backpackConnection then backpackConnection:Disconnect() backpackConnection = nil end
    local root = getRootPart(LocalPlayer.Character)
    if root then
        local bv = root:FindFirstChild("BackpackVelocity")
        if bv then bv:Destroy() end
    end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum.Sit = false end
end

function startBackpacking(target)
    stopAllAttach()
    local char = LocalPlayer.Character
    local root = getRootPart(char)
    if not (target and target.Character and root) then return false end

    isBackpacking, backpackTarget = true, target

    local bv = Instance.new("BodyVelocity")
    bv.Name = "BackpackVelocity"
    bv.MaxForce = Vector3.new(0, math.huge, 0)   -- hold height only
    bv.Velocity = Vector3.new(0, 0, 0)
    bv.Parent = root

    backpackConnection = RunService.RenderStepped:Connect(function()
        if not (isBackpacking and backpackTarget and Players:FindFirstChild(backpackTarget.Name)) then
            stopBackpacking() return
        end
        local troot = backpackTarget.Character and getRootPart(backpackTarget.Character)
        local lroot = getRootPart(LocalPlayer.Character)
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if troot and lroot and hum then
            hum.Sit = true
            lroot.CFrame = troot.CFrame * CFrame.new(0, 0.5, 1.2) * CFrame.Angles(0, math.rad(180), 0)
            lroot.Velocity = Vector3.new(0, 0, 0)
        end
    end)
    return true
end

function stopDragging()
    isDragging, dragTarget = false, nil
    if dragConnection then dragConnection:Disconnect() dragConnection = nil end
    local root = getRootPart(LocalPlayer.Character)
    if root then
        local bv = root:FindFirstChild("DragVelocity")
        if bv then bv:Destroy() end
    end
    stopAnimation()
end

function startDragging(target)
    stopAllAttach()
    local char = LocalPlayer.Character
    local root = getRootPart(char)
    if not (target and target.Character and root) then return false end

    isDragging, dragTarget = true, target
    playAnimation(DRAG_ANIM_ID, 0.5, 0)   -- frozen pose, speed 0

    local bv = Instance.new("BodyVelocity")
    bv.Name = "DragVelocity"
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Velocity = Vector3.new(0, 0, 0)
    bv.Parent = root

    dragConnection = RunService.RenderStepped:Connect(function()
        if not (isDragging and dragTarget and Players:FindFirstChild(dragTarget.Name)) then
            stopDragging() return
        end
        local tchar = dragTarget.Character
        local lroot = getRootPart(LocalPlayer.Character)
        if tchar and lroot then
            local hand = tchar:FindFirstChild("RightHand") or tchar:FindFirstChild("Right Arm")
            if hand then
                lroot.CFrame = hand.CFrame * CFrame.new(0, -2.5, 1)
                    * CFrame.Angles(math.rad(-115), math.rad(180), 0)
            else
                local troot = getRootPart(tchar)
                if troot then
                    lroot.CFrame = troot.CFrame * CFrame.new(0, -1.5, 2)
                        * CFrame.Angles(math.rad(-90), math.rad(180), 0)
                end
            end
            lroot.Velocity = Vector3.new(0, 0, 0)
        end
    end)
    return true
end

function stopAttaching()
    isAttached, attachTarget = false, nil
    if attachConnection then attachConnection:Disconnect() attachConnection = nil end
end

function startAttaching(target)
    stopAllAttach()
    if not (target and target.Character) then return false end
    isAttached, attachTarget = true, target
    attachConnection = RunService.RenderStepped:Connect(function()
        if not (isAttached and attachTarget and Players:FindFirstChild(attachTarget.Name)) then
            stopAttaching() return
        end
        local troot = attachTarget.Character and getRootPart(attachTarget.Character)
        local lroot = getRootPart(LocalPlayer.Character)
        if troot and lroot then lroot.CFrame = troot.CFrame * ATTACH_OFFSET end
    end)
    return true
end

function stopStaring()
    isStaring, stareTarget = false, nil
    if stareConnection then stareConnection:Disconnect() stareConnection = nil end
end

function startStaring(target)
    stopStaring()
    if not target then return false end
    isStaring, stareTarget = true, target
    stareConnection = RunService.RenderStepped:Connect(function()
        if not (isStaring and stareTarget and Players:FindFirstChild(stareTarget.Name)) then
            stopStaring() return
        end
        local troot = stareTarget.Character and getRootPart(stareTarget.Character)
        local lroot = getRootPart(LocalPlayer.Character)
        if troot and lroot then
            -- yaw only, so the character does not tip when they are above or below
            lroot.CFrame = CFrame.new(lroot.Position,
                Vector3.new(troot.Position.X, lroot.Position.Y, troot.Position.Z))
        end
    end)
    return true
end

-- !copydance -- mirrors whatever the target is currently playing, in phase.
-- (musicbot calls this !dance; renamed here so it reads as what it does.)
function stopCopyDance()
    isCopyDancing, danceTarget = false, nil
    for _, c in ipairs(danceConnections) do pcall(function() c:Disconnect() end) end
    danceConnections = {}
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        for _, t in pairs(hum:GetPlayingAnimationTracks()) do pcall(function() t:Stop() end) end
    end
end

function startCopyDance(target)
    stopCopyDance()
    if not (target and target.Character and LocalPlayer.Character) then return false end
    local thum = target.Character:FindFirstChildOfClass("Humanoid")
    local lhum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not (thum and lhum) then return false end

    isCopyDancing, danceTarget = true, target
    for _, t in pairs(lhum:GetPlayingAnimationTracks()) do pcall(function() t:Stop() end) end

    local function sync(track)
        if not (isCopyDancing and LocalPlayer.Character) then return end
        local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        -- skip the default idle, or the bot just stands there copying nothing
        if string.find(track.Animation.AnimationId, "507768375") then return end
        local a = hum:LoadAnimation(track.Animation)
        a:Play(0.1, 1, track.Speed)
        a.TimePosition = track.TimePosition      -- join in phase
        task.spawn(function()
            track.Stopped:Wait()
            pcall(function() a:Stop() a:Destroy() end)
        end)
    end

    for _, t in pairs(thum:GetPlayingAnimationTracks()) do sync(t) end
    table.insert(danceConnections, thum.AnimationPlayed:Connect(function(t)
        if isCopyDancing then sync(t) end
    end))
    return true
end

-- Only one attachment behaviour may own the root at a time.
function stopAllAttach()
    stopHeadSit() stopBackpacking() stopDragging() stopAttaching()
    pcall(function() for _, f in ipairs(ESP.FEATURES) do ESP.cfg[f.key] = false end ESP.sync() end)
end

flyForceStop = flyCleanup   -- immediate, no landing (used by unexecute)

local function toggleFly(speed)
    if isFlying then
        -- Descend and play the ground-hit rather than dropping control
        -- instantly; flyPhase drives the landing branch of the loop.
        if flyPhase ~= "landing" then
            flyPhase = "landing"
            flyLandStart = tick()
        end
        return
    end

    flySpeed = tonumber(speed) or 50
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not (hrp and hum) then return end

    workspace.Gravity = 0
    hum.PlatformStand = true
    setNoClip(true)
    isFlying  = true
    flyPhase  = "flying"
    flyTier   = "idle"
    flyVel    = Vector3.new(0, 0, 0)

    -- The styled animations own the look, so silence the default Animate.
    local animate = char:FindFirstChild("Animate")
    if animate then animate.Disabled = true end
    flyTracks = flyLoadTracks(hum)
    if flyTracks and flyTracks.idle then flyTracks.idle:Play(0.15) end

    flyConnection = RunService.RenderStepped:Connect(function(dt)
        if not isFlying then flyCleanup() return end
        local lchar = LocalPlayer.Character
        local root  = lchar and lchar:FindFirstChild("HumanoidRootPart")
        local lhum  = lchar and lchar:FindFirstChildOfClass("Humanoid")
        if not (root and lhum) then flyCleanup() return end

        -- ── landing ──
        if flyPhase == "landing" then
            local rp = RaycastParams.new()
            rp.FilterType = Enum.RaycastFilterType.Exclude
            rp.FilterDescendantsInstances = { lchar }
            local hit = workspace:Raycast(root.Position, Vector3.new(0, -300, 0), rp)
            local standY = hit and (hit.Position.Y + lhum.HipHeight + root.Size.Y * 0.5) or nil

            local horiz = Vector3.new(flyVel.X, 0, flyVel.Z)
                :Lerp(Vector3.new(0, 0, 0), 1 - math.exp(-dt / 0.15))
            local vy
            if standY then
                vy = math.clamp((standY - root.Position.Y) * 5, -FLY.landSpeed, 6)
                if (root.Position.Y - standY) <= FLY.landTrigger and flyTier ~= "land" then
                    flySetTier("land")
                end
            else
                vy = -FLY.landSpeed
            end
            flyVel = Vector3.new(horiz.X, vy, horiz.Z)
            root.Velocity = flyVel

            local grounded = standY and (root.Position.Y - standY) <= 0.6
            if grounded or (tick() - flyLandStart > FLY.landTimeout) then
                local landTrack = flyTracks and flyTracks.land
                if flyTracks then
                    for n, t in pairs(flyTracks) do
                        if n ~= "land" then pcall(function() t:Stop(0.1) end) end
                    end
                end
                flyCleanup()
                -- let the get-up finish, then hand animation back
                if landTrack then
                    task.delay(0.9, function() pcall(function() landTrack:Stop(0.2) end) end)
                end
                flyTracks = nil
            end
            return
        end

        -- ── flying ──
        local dir = Vector3.new(0, 0, 0)
        local look, right = Camera.CFrame.LookVector, Camera.CFrame.RightVector
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + look end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - look end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - right end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + right end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0, 1, 0) end

        local want = (dir.Magnitude > 0) and (dir.Unit * flySpeed) or Vector3.new(0, 0, 0)
        -- exponential ease -- frame-rate independent, and the gradual ramp is
        -- exactly what lets the animation tiers cycle instead of snapping
        flyVel = flyVel:Lerp(want, 1 - math.exp(-dt / FLY.accelTau))

        local bob = 0
        if flyVel.Magnitude < 1 then
            bob = math.sin(tick() * FLY.bobFreq) * FLY.bobAmp
        end
        root.Velocity = flyVel + Vector3.new(0, bob, 0)

        flySetTier(flyTierFor(Vector3.new(flyVel.X, 0, flyVel.Z).Magnitude))
    end)
end

-- Toggle view player function
local function viewPlayer(player)
    if viewConnection and viewConnection.Connected then
        viewConnection:Disconnect()
        viewConnection = nil
        Camera.CameraSubject = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        viewedPlayer = nil
        return
    end
    
    if not player then
        return
    end
    
    local character = player.Character
    if not character then
        return
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end
    
    Camera.CameraSubject = humanoid
    viewedPlayer = player
    
    -- Create connection to handle when player leaves or dies
    viewConnection = player.CharacterRemoving:Connect(function()
        Camera.CameraSubject = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        viewConnection:Disconnect()
        viewConnection = nil
        viewedPlayer = nil
    end)
end

-- Infinite Jump function
local function toggleInfJump()
    isInfJumpEnabled = not isInfJumpEnabled
    if isInfJumpEnabled then
        UserInputService.JumpRequest:Connect(function()
            if isInfJumpEnabled and LocalPlayer.Character then
                LocalPlayer.Character:FindFirstChildOfClass("Humanoid"):ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
    else
    end
end

-- Click Teleport function
local function setupClickTeleport(key)
    if clickTpConnection and clickTpConnection.Connected then
        clickTpConnection:Disconnect()
        clickTpConnection = nil
        clickTpKey = nil
        return
    end
    
    local keyCode = Enum.KeyCode[key]
    if not keyCode then
        return
    end
    
    clickTpKey = keyCode

    -- Touch devices have no key to hold and no Mouse.Hit, so the whole
    -- hold-key-then-click model is replaced by a straight toggle: while
    -- click-teleport is on, a tap in the world moves you there.
    if UI.touch then
        clickTpConnection = UI.onWorldPick(function(pos)
            local ch = LocalPlayer.Character
            local root = ch and ch:FindFirstChild("HumanoidRootPart")
            if root then root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) end
        end)
        return
    end

    -- Create the connections for click teleporting
    clickTpConnection = UserInputService.InputBegan:Connect(function(input)
        if input.KeyCode == clickTpKey then
            local mouse = LocalPlayer:GetMouse()
            
            -- Create a connection for when the mouse is clicked while key is held
            local mouseConnection
            mouseConnection = UserInputService.InputBegan:Connect(function(mouseInput)
                if mouseInput.UserInputType == Enum.UserInputType.MouseButton1 then
                    local character = LocalPlayer.Character
                    if character then
                        local rootPart = character:FindFirstChild("HumanoidRootPart")
                        if rootPart then
                            local targetPos = mouse.Hit.Position
                            rootPart.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
                        end
                    end
                end
            end)
            
            -- Remove the connection when key is released
            local keyReleasedConnection
            keyReleasedConnection = UserInputService.InputEnded:Connect(function(endInput)
                if endInput.KeyCode == clickTpKey then
                    mouseConnection:Disconnect()
                    keyReleasedConnection:Disconnect()
                end
            end)
        end
    end)
end

-- Spin function
local function toggleSpin(speed)
    if isSpinning then
        if spinConnection and spinConnection.Connected then
            spinConnection:Disconnect()
        end
        isSpinning = false
        return
    end
    
    spinSpeed = tonumber(speed) or 10
    isSpinning = true
    
    local character = LocalPlayer.Character
    if not character then return end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return end
    
    local angle = 0
    spinConnection = RunService.Heartbeat:Connect(function(dt)
        if not isSpinning or not character or not character:FindFirstChild("HumanoidRootPart") then
            if spinConnection then spinConnection:Disconnect() end
            isSpinning = false
            return
        end
        
        angle = angle + math.rad(spinSpeed * dt * 60)
        rootPart.CFrame = CFrame.new(rootPart.Position) * CFrame.Angles(0, angle, 0)
    end)
end

-- Bang function (just placeholder as requested)
local function toggleBang(targetPlayer)
    if not targetPlayer then
        return
    end
    
    -- Implementation would go here
end

-- Set time of day function
local function setTimeOfDay(timeString)
    if not game:GetService("Lighting") then
        return
    end
    
    local times = {
        ["night"] = 0,
        ["midnight"] = 0,
        ["morning"] = 6,
        ["day"] = 12,
        ["noon"] = 12,
        ["afternoon"] = 15,
        ["evening"] = 18
    }
    
    local timeValue = times[timeString:lower()]
    if timeValue then
        game:GetService("Lighting").TimeOfDay = timeValue .. ":00:00"
    else
        local hourValue = tonumber(timeString)
        if hourValue and hourValue >= 0 and hourValue < 24 then
            game:GetService("Lighting").TimeOfDay = math.floor(hourValue) .. ":00:00"
        else
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════
--  USAGE
--  What you actually reach for, so the suggestion lists can lead with it
--  instead of with whatever order the tables happen to be written in.
--  One counter serves the command bar and quickjoin both.
-- ════════════════════════════════════════════════════════════════════════
Usage = { cmds = {}, games = {}, dirty = false, lastSave = 0 }

-- Writing the config on every keystroke-run would hammer the filesystem, so
-- coalesce: mark dirty, flush at most every few seconds, and flush for real
-- on teardown.
Usage.SAVE_EVERY = 4

function Usage.flush(force)
    if not Usage.dirty then return end
    if not force and (os.clock() - Usage.lastSave) < Usage.SAVE_EVERY then return end
    Usage.dirty, Usage.lastSave = false, os.clock()
    pcall(UI.saveConfig)
end

function Usage.bump(kind, key)
    key = tostring(key or ""):lower()
    if key == "" then return end
    local t = Usage[kind]
    if not t then return end
    local e = t[key]
    if e then
        e.n = (e.n or 0) + 1
    else
        e = { n = 1 }
        t[key] = e
    end
    -- os.time is UTC epoch seconds: not a clock anyone reads, but a total
    -- order across sessions, which is all "last played" needs.
    e.at = os.time()
    Usage.dirty = true
    Usage.flush(false)
end

function Usage.count(kind, key)
    local e = Usage[kind] and Usage[kind][tostring(key or ""):lower()]
    return e and e.n or 0
end

function Usage.at(kind, key)
    local e = Usage[kind] and Usage[kind][tostring(key or ""):lower()]
    return e and e.at or 0
end

-- The single most recent key of a kind, or nil. Ties on time go to the more
-- used one, so a rapid pair does not flip between renders.
function Usage.last(kind)
    local best, bestAt, bestN = nil, 0, 0
    for k, e in pairs(Usage[kind] or {}) do
        local at, n = e.at or 0, e.n or 0
        if at > bestAt or (at == bestAt and n > bestN) then
            best, bestAt, bestN = k, at, n
        end
    end
    return best
end

-- Deterministic shuffle from a caller-supplied seed. With no history there
-- is nothing to rank by, and a fixed order would show the same six commands
-- forever -- but re-shuffling per keystroke would make the list jump, so the
-- seed is held for the life of the burst.
function Usage.shuffle(list, seed)
    local r = Random.new(seed or 1)
    for i = #list, 2, -1 do
        local j = r:NextInteger(1, i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

function Usage.load(raw)
    if type(raw) ~= "table" then return end
    for _, kind in ipairs({ "cmds", "games" }) do
        local src = raw[kind]
        if type(src) == "table" then
            local clean = {}
            for k, e in pairs(src) do
                if type(k) == "string" and type(e) == "table" and tonumber(e.n) then
                    clean[k:lower()] = { n = tonumber(e.n), at = tonumber(e.at) or 0 }
                end
            end
            Usage[kind] = clean
        end
    end
end

function Usage.save()
    return { cmds = Usage.cmds, games = Usage.games }
end

-- ════════════════════════════════════════════════════════════════════════
--  SERVER HOP  (!serverhop / !shop)
--  Was "any server with a free slot, at random". Now the same dynamic
--  tokens the player and game arguments use, so you can say which KIND of
--  server you want rather than rolling until you get one.
-- ════════════════════════════════════════════════════════════════════════
ServerHop = { PAGES = 3 }

ServerTokens = {
    { key = "low",    label = "Emptiest server",  icon = "st_ghost.png",
      desc = "Fewest players in it" },
    { key = "high",   label = "Fullest server",   icon = "st_users.png",
      desc = "Most players, still with a free slot" },
    { key = "random", label = "Random server",    icon = "st_dices.png",
      desc = "Any server with room" },
    { key = "last",   label = "Last server",      icon = "st_corner-down-right.png",
      desc = "The one you hopped away from" },
    { key = "packed", label = "Nearly full",       icon = "st_users-round.png",
      desc = "A slot or two left, for a busy one" },
    { key = "smooth", label = "Best performance", icon = "st_gauge.png",
      desc = "Highest frame rate of the ones found" },
    { key = "tiny",   label = "Nearly empty",     icon = "st_moon.png",
      desc = "Under five players, for a quiet one" },
}

ServerTokens.byKey = {}
for _, t in ipairs(ServerTokens) do ServerTokens.byKey[t.key] = t end

ServerTokens.alias = {
    empty = "low", quiet = "low", small = "low", least = "low",
    full = "high", busy = "high", big = "high", most = "high",
    rand = "random", any = "random",
    fps = "smooth", fast = "smooth", best = "smooth",
    solo = "tiny", alone = "tiny", dead = "tiny",
    crowded = "packed", nearlyfull = "packed", almostfull = "packed",
    popular = "packed",
    back = "last", previous = "last", prev = "last",
}

function ServerTokens.resolve(word)
    word = tostring(word or ""):lower()
    word = ServerTokens.alias[word] or word
    return ServerTokens.byKey[word]
end

-- Same shape as PlayerTokens.spellings: the label says what it does, the
-- spellings say what to type.
function ServerTokens.spellings(key)
    local out = { key }
    for alias, target in pairs(ServerTokens.alias) do
        if target == key then out[#out + 1] = alias end
    end
    table.sort(out, function(a, b)
        if #a ~= #b then return #a < #b end
        return a < b
    end)
    return out
end

function commandNeedsServer(cmd)
    cmd = tostring(cmd or ""):lower()
    return cmd == "serverhop" or cmd == "shop" or cmd == "hop"
end

-- ── Fetching ────────────────────────────────────────────────────────────
-- One page is 100 servers, which is a poor sample to pick "the emptiest"
-- from. Walk a few, and stop early if the cursor runs out.
function ServerHop.fetch(pages)
    local out, cursor = {}, nil
    for _ = 1, (pages or ServerHop.PAGES) do
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId
                    .. "/servers/Public?sortOrder=Asc&limit=100"
        if cursor then url = url .. "&cursor=" .. cursor end

        local ok, body = pcall(function() return game:HttpGet(url) end)
        if not ok then break end
        local okJ, site = pcall(function() return HttpService:JSONDecode(body) end)
        if not (okJ and type(site) == "table" and type(site.data) == "table") then break end

        for _, v in ipairs(site.data) do out[#out + 1] = v end
        cursor = site.nextPageCursor
        if not cursor then break end
    end
    return out
end

-- Somewhere you can actually go: room for you, and not the one you are in.
function ServerHop.eligible(servers)
    local out = {}
    for _, v in ipairs(servers) do
        local playing, max = tonumber(v.playing) or 0, tonumber(v.maxPlayers) or 0
        if v.id and v.id ~= game.JobId and max > playing then
            out[#out + 1] = { id = v.id, playing = playing, max = max,
                              fps = tonumber(v.fps) or 0 }
        end
    end
    return out
end

ServerHop.TINY = 5
-- "Nearly full" is about the free slots, not the head count: a 12-player
-- server with 2 spare is packed, a 30-player one with 20 spare is not.
ServerHop.PACKED = 3

-- Returns the chosen server and a phrase describing WHY, so the toast can
-- say "emptiest, 2 players" rather than just "hopping".
function ServerHop.pick(key, list)
    if #list == 0 then return nil end
    key = key or "random"

    local function best(better)
        local top = list[1]
        for _, s in ipairs(list) do if better(s, top) then top = s end end
        return top
    end

    if key == "low" then
        return best(function(a, b) return a.playing < b.playing end), "emptiest"
    elseif key == "high" then
        return best(function(a, b) return a.playing > b.playing end), "fullest"
    elseif key == "smooth" then
        -- fps is 0 when the API does not report it; that must not read as
        -- the smoothest server in the list.
        local rated = {}
        for _, s in ipairs(list) do if s.fps > 0 then rated[#rated + 1] = s end end
        if #rated == 0 then
            return list[math.random(1, #list)], "random, no frame rates reported"
        end
        local top = rated[1]
        for _, s in ipairs(rated) do if s.fps > top.fps then top = s end end
        return top, string.format("%.0f fps", top.fps)
    elseif key == "packed" then
        local tight = {}
        for _, s in ipairs(list) do
            if (s.max - s.playing) <= ServerHop.PACKED then tight[#tight + 1] = s end
        end
        if #tight > 0 then
            -- Random among them rather than THE fullest, which is what
            -- "high" is for -- this spreads you across the busy ones
            -- instead of everyone piling into the same server.
            local s = tight[math.random(1, #tight)]
            return s, (s.max - s.playing) .. " slots left"
        end
        return best(function(a, b) return a.playing > b.playing end),
               "none that full, took the fullest"
    elseif key == "tiny" then
        local small = {}
        for _, s in ipairs(list) do
            if s.playing <= ServerHop.TINY then small[#small + 1] = s end
        end
        if #small > 0 then
            return small[math.random(1, #small)], "under " .. (ServerHop.TINY + 1)
        end
        -- Nothing that quiet exists; the emptiest is the honest answer, and
        -- the toast says so rather than silently doing something else.
        return best(function(a, b) return a.playing < b.playing end),
               "none that quiet, took the emptiest"
    end
    return list[math.random(1, #list)], "random"
end

-- ── Live token state ────────────────────────────────────────────────────
-- A filter that cannot improve on where you already are is worth saying so
-- BEFORE it is used. "Emptiest" when you are already in the emptiest server
-- is a hop to nowhere, and the row should look like one.
--
-- The counts come from a cached snapshot: the suggestion list re-renders on
-- every keystroke and cannot make a network call per frame, so the fetch is
-- kicked off in the background and the list redrawn when it lands.
ServerHop.SNAP_TTL = 20

-- The server you came from is a fact about ONE game. Bucketed by place, so
-- hopping in another game does not erase where you were in this one.
ServerHop.prevBy = {}

function ServerHop.rememberPrev()
    ServerHop.prevBy[tostring(game.PlaceId)] = { job = game.JobId, at = os.time() }
    -- Ten games is more than anyone revisits; the oldest is the one nobody
    -- misses.
    local keys = {}
    for k, v in pairs(ServerHop.prevBy) do
        keys[#keys + 1] = { k = k, at = (v and v.at) or 0 }
    end
    table.sort(keys, function(a, b) return a.at > b.at end)
    for i = 11, #keys do ServerHop.prevBy[keys[i].k] = nil end
end

function ServerHop.prevHere()
    local e = ServerHop.prevBy[tostring(game.PlaceId)]
    if e and type(e.job) == "string" and e.job ~= "" then return e end
    return nil
end

function ServerHop.here()
    local now, max = 0, 0
    pcall(function() now, max = #Players:GetPlayers(), Players.MaxPlayers end)
    return { playing = now, max = max, fps = (Perf and Perf.fps) or 0 }
end

function ServerHop.snapshot(onReady)
    local s = ServerHop.snap
    if s and (os.clock() - s.at) < ServerHop.SNAP_TTL then return s end
    if ServerHop.fetching then return s end     -- one in flight is enough
    ServerHop.fetching = true
    task.spawn(function()
        local list = ServerHop.eligible(ServerHop.fetch(1))   -- one page is
        ServerHop.fetching = false                            -- enough to rank
        ServerHop.snap = { at = os.clock(), list = list }
        if onReady then pcall(onReady) end
    end)
    return s
end

-- How many servers beat where you are, by whatever the token cares about.
-- Returns count, and a phrase for the row.
function ServerTokens.stateFor(key)
    local snap = ServerHop.snap
    if not snap then return nil, "checking\226\128\166" end
    local me, list = ServerHop.here(), snap.list

    if key == "last" then
        local p = ServerHop.prevHere()
        if not p then return 0, "none in this game yet" end
        if p.job == game.JobId then return 0, "you are in it" end
        return 1, "the one you came from"
    end

    if #list == 0 then return 0, "no servers found" end
    if key == "random" then return #list, #list .. " to choose from" end

    local n = 0
    if key == "low" then
        for _, s in ipairs(list) do if s.playing < me.playing then n = n + 1 end end
        return n, n > 0 and (n .. " emptier") or "already the emptiest"
    elseif key == "high" then
        for _, s in ipairs(list) do if s.playing > me.playing then n = n + 1 end end
        return n, n > 0 and (n .. " fuller") or "already the fullest"
    elseif key == "tiny" then
        for _, s in ipairs(list) do
            if s.playing <= ServerHop.TINY then n = n + 1 end
        end
        if me.playing <= ServerHop.TINY and n == 0 then return 0, "already this quiet" end
        return n, n > 0 and (n .. " under " .. (ServerHop.TINY + 1)) or "none that quiet"
    elseif key == "packed" then
        for _, s in ipairs(list) do
            if (s.max - s.playing) <= ServerHop.PACKED then n = n + 1 end
        end
        if (me.max - me.playing) <= ServerHop.PACKED and n == 0 then
            return 0, "already nearly full"
        end
        return n, n > 0 and (n .. " nearly full") or "none that full"
    elseif key == "smooth" then
        -- No reading of your own frame rate yet means no comparison to make,
        -- so say that rather than claiming every server is better.
        if me.fps <= 0 then return #list, "open !stats to compare" end
        for _, s in ipairs(list) do if s.fps > me.fps then n = n + 1 end end
        return n, n > 0 and (n .. " smoother") or "already the smoothest"
    end
    return nil
end

-- One hop, one cancel window. Shared so the "last server" jump and a
-- filtered pick cannot drift apart on how long you get to change your mind.
function ServerHop.hopTo(jobId, detail)
    if not jobId or jobId == "" then
        Notifications:Error("Universal Hub Lite", "No server to hop to", 4)
        return
    end
    -- Same window as quickjoin: a hop is just as irreversible, and the
    -- Cancel button needs just as long to finish appearing.
    ServerHop.cancelled = false
    Notifications:Success("Universal Hub Lite",
        "Hopping in " .. QuickJoin.DELAY .. "s  \194\183  " .. detail,
        QuickJoin.DELAY + 2, {
        { label = "Cancel", icon = "st_x.png", style = "ghost", run = function()
            ServerHop.cancelled = true
            Notifications:Info("Universal Hub Lite", "Hop cancelled", 3)
        end },
    })

    local burst = Notify.burst
    task.spawn(function()
        for left = QuickJoin.DELAY, 1, -1 do
            if ServerHop.cancelled then return end
            if Notify.burst ~= burst or Bar.mode ~= "notify" then return end
            pcall(function()
                Bar.subLabel.Text = "Hopping in " .. left .. "s  \194\183  " .. detail
                Notify.layoutSub()
            end)
            task.wait(1)
        end
    end)

    task.delay(QuickJoin.DELAY, function()
        if ServerHop.cancelled then return end
        -- Recorded as we leave, not on arrival: the teleport takes the
        -- session with it, so there is no "after" to write it in.
        ServerHop.rememberPrev()
        pcall(UI.saveConfig)
        pcall(function()
            game:GetService("TeleportService")
                :TeleportToPlaceInstance(game.PlaceId, jobId, LocalPlayer)
        end)
    end)
end

function ServerHop.go(word)
    local tok = ServerTokens.resolve(word)
    -- A word we do not know is a typo, not a silent fallback to random.
    if word and word ~= "" and not tok then
        Notifications:Error("Universal Hub Lite",
            "No server filter called \"" .. tostring(word) .. "\"", 4)
        return
    end

    -- "last" names a specific server, so there is nothing to search for.
    if tok and tok.key == "last" then
        local p = ServerHop.prevHere()
        if not p then
            Notifications:Error("Universal Hub Lite",
                "You have not hopped in this game yet", 4)
            return
        end
        if p.job == game.JobId then
            Notifications:Info("Universal Hub Lite", "You are already in it", 3.5)
            return
        end
        ServerHop.hopTo(p.job, "back to your last server")
        return
    end

    -- Deliberately silent while it looks. Announcing the search and then
    -- the result is two notifications for one action -- the second lands as
    -- a follow-up chip under the first, which reads as the thing popping up
    -- twice. The hop toast speaks when there is something to say.
    task.spawn(function()
        local list = ServerHop.eligible(ServerHop.fetch())
        if #list == 0 then
            Notifications:Error("Universal Hub Lite",
                "No server with a free slot -- try again in a moment", 4.5)
            return
        end

        local s, why = ServerHop.pick(tok and tok.key or "random", list)
        if not s then
            Notifications:Error("Universal Hub Lite", "Could not pick a server", 4)
            return
        end

        ServerHop.hopTo(s.id,
            ("%s  \194\183  %d/%d players"):format(why, s.playing, s.max))
    end)
end

-- ── Where you left off ──────────────────────────────────────────────────
-- The manual !savepos is a bookmark you chose. This is different: the spot
-- you were standing in when the session ended, captured as you go, so the
-- resume prompt can offer it without you having thought to save anything.
Pos = { EVERY = 5, WRITE_EVERY = 30, lastWrite = 0, running = false }

function Pos.capture()
    local ch = LocalPlayer and LocalPlayer.Character
    local root = ch and ch:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local h = ch:FindFirstChildOfClass("Humanoid")
    -- Not while dead: the corpse falls, and "where you left off" would end
    -- up being the void rather than where you were playing.
    if h and h.Health <= 0 then return false end

    local p = root.Position
    -- Ignore the spawn-in frames: 0,0,0 is where a character sits for a
    -- moment before the game places it, and offering that sends you into
    -- the skybox.
    if math.abs(p.X) < 1 and math.abs(p.Y) < 1 and math.abs(p.Z) < 1 then
        return false
    end
    UI.leftOff = { place = game.PlaceId, x = p.X, y = p.Y, z = p.Z }
    return true
end

function Pos.start()
    if Pos.running then return end
    Pos.running = true
    task.spawn(function()
        while Pos.running do
            task.wait(Pos.EVERY)
            if not Pos.running then break end
            if Pos.capture() and (os.clock() - Pos.lastWrite) >= Pos.WRITE_EVERY then
                Pos.lastWrite = os.clock()
                pcall(UI.saveConfig)
            end
        end
    end)
end

function Pos.stop()
    Pos.running = false
    -- One last write, so the final position is the one that gets offered
    -- rather than whatever was current thirty seconds ago.
    pcall(function() if Pos.capture() then UI.saveConfig() end end)
end

-- ── Quick join ──────────────────────────────────────────────────────────
-- Curated place ids. Roblox blocks HttpGet to its own domains, so these
-- cannot be looked up by name at runtime -- the table IS the index. If a
-- game relaunches under a new place id, fix it here; !quickjoin also takes
-- a raw id so a stale entry is never a dead end.
QuickJoin = { games = {
    { id = 142823291,   name = "Murder Mystery 2",        keys = {"mm2","murdermystery","murdermystery2"} },
    { id = 606849621,   name = "Jailbreak",               keys = {"jailbreak","jb"} },
    { id = 155615604,   name = "Prison Life",             keys = {"prisonlife","prison","pl"} },
    { id = 920587237,   name = "Adopt Me!",               keys = {"adoptme","adopt","am"} },
    { id = 189707,      name = "Natural Disaster Survival",keys = {"ntd","naturaldisaster","disaster","nds"} },
    { id = 4924922222,  name = "Brookhaven RP",           keys = {"brookhaven","bh","brook"} },
    { id = 2753915549,  name = "Blox Fruits",             keys = {"bloxfruits","bf","fruits"} },
    { id = 6516141723,  name = "Doors",                   keys = {"doors"} },
    { id = 286090429,   name = "Arsenal",                 keys = {"arsenal"} },
    { id = 1537690962,  name = "Bee Swarm Simulator",     keys = {"beeswarm","bss","bee"} },
    { id = 1962086868,  name = "Tower of Hell",           keys = {"towerofhell","toh","tower"} },
    { id = 893973440,   name = "Flee the Facility",       keys = {"flee","ftf","fleethefacility"} },
    { id = 370731277,   name = "MeepCity",                keys = {"meepcity","meep"} },
    { id = 735030788,   name = "Royale High",             keys = {"royalehigh","rh","royale"} },
    { id = 192800,      name = "Work at a Pizza Place",   keys = {"pizza","waapp","pizzaplace"} },
    { id = 4623386862,  name = "Piggy",                   keys = {"piggy"} },
    { id = 3851622790,  name = "Break In (Story)",        keys = {"breakin","bi"} },
    { id = 13864661000, name = "Break In 2 (Story)",      keys = {"breakin2","bi2"} },
    { id = 2788229376,  name = "Da Hood",                 keys = {"dahood","dh"} },
    { id = 9872472334,  name = "Evade",                   keys = {"evade"} },
    { id = 13772394625, name = "Blade Ball",              keys = {"bladeball","bb"} },
} }

QuickJoin.index = {}
for _, g in ipairs(QuickJoin.games) do
    QuickJoin.index[g.name:lower()] = g
    for _, k in ipairs(g.keys) do QuickJoin.index[k] = g end
end

-- ── Learning games it has not seen ──────────────────────────────────────
-- The curated table cannot know about the place you are standing in. Add it
-- on the way past, so the game you actually play is quickjoinable next time
-- without anyone editing a table.
QuickJoin.learned = {}

-- Alias candidates, best first. Initials carry a trailing number because
-- that is how these games are known -- "Murder Mystery 2" is mm2, not mm.
function QuickJoin.aliasesFor(name)
    local words, digits = {}, nil
    for w in tostring(name or ""):gmatch("[%w']+") do
        local lw = w:lower()
        if lw:match("^%d+$") then digits = lw else words[#words + 1] = lw end
    end
    if #words == 0 then return {} end

    local initials = ""
    for _, w in ipairs(words) do initials = initials .. w:sub(1, 1) end

    local flat = table.concat(words)
    local out, seen = {}, {}
    -- Deduped here rather than left to the caller: for a one-word title the
    -- first word and the flattened name are the same string, and a list that
    -- repeats itself makes every consumer dedupe again. Anything under two
    -- characters is dropped -- a one-letter alias collides with everything.
    local function add(v)
        if v and #v >= 2 and #v <= 20 and not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end
    if digits then
        add(initials .. digits)
        add(words[1] .. digits)
    end
    add(initials)
    add(words[1])
    add(flat .. (digits or ""))
    return out
end

-- Only aliases nobody else has claimed. A learned game silently stealing
-- "mm2" would break the curated entry it was meant to sit beside.
function QuickJoin.freeAliases(name)
    local out, seen = {}, {}
    for _, a in ipairs(QuickJoin.aliasesFor(name)) do
        if not QuickJoin.index[a] and not seen[a] then
            seen[a] = true
            out[#out + 1] = a
        end
    end
    return out
end

function QuickJoin.add(id, name, learned)
    id = tonumber(id)
    if not (id and id > 0) or not name or name == "" then return nil end
    for _, g in ipairs(QuickJoin.games) do
        if g.id == id then return g end          -- already known
    end
    local keys = QuickJoin.freeAliases(name)
    if #keys == 0 then
        -- Nothing unclaimed left; the raw id still works, and a game with no
        -- typeable alias is worse than no entry at all.
        return nil
    end
    local g = { id = id, name = name, keys = keys, learned = learned ~= false }
    QuickJoin.games[#QuickJoin.games + 1] = g
    QuickJoin.index[name:lower()] = g
    for _, k in ipairs(keys) do QuickJoin.index[k] = g end
    if g.learned then
        QuickJoin.learned[#QuickJoin.learned + 1] =
            { id = id, name = name, keys = keys }
    end
    return g
end

-- Called once at startup. GetProductInfo is already cached by About.
function QuickJoin.learnCurrent()
    task.spawn(function()
        local info = About and About.place()
        local nm = info and info.Name
        if not nm then return end
        local g = QuickJoin.add(game.PlaceId, nm, true)
        if g then UI.saveConfig() end
    end)
end

-- ── Dynamic ordering ────────────────────────────────────────────────────
-- Last played first, then most played, then the rest. The curated table
-- order means nothing to you; what you actually join does.
function QuickJoin.tagFor(g)
    local key = g.keys[1]
    if QuickJoin.lastKey and key == QuickJoin.lastKey then return "last played", true end
    local n = Usage.count("games", key)
    if n >= 3 then return "top played", false end
    if n > 0 then return "played " .. n .. (n == 1 and " time" or " times"), false end
    if g.learned then return "this game", false end
    return nil
end

function QuickJoin.rankOf(g)
    local key = g.keys[1]
    if QuickJoin.lastKey and key == QuickJoin.lastKey then return 0 end
    if Usage.count("games", key) > 0 then return 1 end
    return 2
end

function QuickJoin.sort(list)
    local rank, n, at = {}, {}, {}
    for _, m in ipairs(list) do
        local g = m.game
        rank[m] = g and QuickJoin.rankOf(g) or 2
        n[m] = g and Usage.count("games", g.keys[1]) or 0
        at[m] = g and Usage.at("games", g.keys[1]) or 0
    end
    table.sort(list, function(a, b)
        if rank[a] ~= rank[b] then return rank[a] < rank[b] end
        if n[a] ~= n[b] then return n[a] > n[b] end        -- more played first
        if at[a] ~= at[b] then return at[a] > at[b] end    -- then more recent
        return (a.text or "") < (b.text or "")
    end)
    return list
end

-- Mirrors commandNeedsPlayer: which commands take a game as their argument.
function commandNeedsGame(cmd)
    cmd = tostring(cmd or ""):lower()
    return cmd == "quickjoin" or cmd == "qj" or cmd == "join"
end

-- Exact only, unlike find(). A partial token has to complete first, exactly
-- as a partial username does, or Enter would fire on "qj m".
function QuickJoin.exact(q)
    q = tostring(q or ""):lower():gsub("%s+", "")
    return (q ~= "" and QuickJoin.index[q]) or nil
end

-- rbxthumb://type=GameIcon resolves against the UNIVERSE, not the place, so
-- handing it a place id silently serves the generic placeholder instead of
-- failing -- which is why every tile looked like an unset game. Place ids
-- are what we have, and GetProductInfo turns one into the icon's actual
-- asset id, so resolve through that instead.
--
-- That call is a network round trip, so it cannot happen inline while rows
-- are being built. apply() is invoked now if the answer is already cached,
-- and later if it is not.
UI.placeIcons = {}

function UI.placeIcon(placeId, apply)
    placeId = tonumber(placeId)
    if not (placeId and placeId > 0 and apply) then return end
    local hit = UI.placeIcons[placeId]
    if hit ~= nil then
        if hit then pcall(apply, "rbxassetid://" .. tostring(hit)) end
        return
    end
    task.spawn(function()
        local ok, info = pcall(function()
            return game:GetService("MarketplaceService"):GetProductInfo(placeId)
        end)
        local id = ok and type(info) == "table" and tonumber(info.IconImageAssetId)
        -- 0 means the place genuinely has no icon; cache that too, or every
        -- render re-asks the network for the same nothing.
        if not id or id == 0 then id = false end
        UI.placeIcons[placeId] = id
        if id then pcall(apply, "rbxassetid://" .. tostring(id)) end
    end)
end

function QuickJoin.icon(g, apply)
    if not g then return end
    UI.placeIcon(g.id, apply)
end

function QuickJoin.find(q)
    q = tostring(q or ""):lower():gsub("%s+", "")
    if q == "" then return nil end
    if QuickJoin.index[q] then return QuickJoin.index[q] end
    -- prefix, then substring, so "jail" and "hood" both land
    for _, g in ipairs(QuickJoin.games) do
        for _, k in ipairs(g.keys) do
            if k:sub(1, #q) == q then return g end
        end
        if g.name:lower():gsub("%s+", ""):find(q, 1, true) then return g end
    end
    return nil
end

-- How long you get to change your mind. Must clear the tray reveal, or the
-- Cancel button is still animating in when the teleport fires.
QuickJoin.DELAY = math.max(5, math.ceil((Notify and Notify.TRAY_DELAY or 1.5) + 2))

function QuickJoin.go(q)
    local raw = tonumber(q)
    if raw and raw > 0 then
        -- A bare place id gets the same window: it is the easiest one to
        -- mistype, and there is no name to sanity-check it against.
        QuickJoin.cancelled = false
        Notifications:Info("Universal Hub Lite",
            "Joining place " .. raw .. " in " .. QuickJoin.DELAY .. "s",
            QuickJoin.DELAY + 2, {
            { label = "Cancel", icon = "st_x.png", style = "ghost", run = function()
                QuickJoin.cancelled = true
                Notifications:Info("Universal Hub Lite", "Join cancelled", 3)
            end },
        })
        task.delay(QuickJoin.DELAY, function()
            if QuickJoin.cancelled then return end
            pcall(function()
                game:GetService("TeleportService"):Teleport(raw, LocalPlayer)
            end)
        end)
        return true
    end

    local g = QuickJoin.find(q)
    if not g then return false end
    if g.id == game.PlaceId then
        Notifications:Warning("Universal Hub Lite", "Already in " .. g.name, 4)
        return true
    end
    -- The Cancel button is not even on screen until TRAY_DELAY plus its
    -- stagger and reveal tween -- about 1.8s. Teleporting at 1.2s meant the
    -- button flashed up after the teleport had already been issued, so there
    -- was never a moment you could actually click it. Derived from the tray
    -- timing rather than guessed, so it cannot drift out of sync again.
    QuickJoin.cancelled = false
    local burst = Notify.burst

    Notifications:Success("Universal Hub Lite",
        "Joining " .. g.name .. " in " .. QuickJoin.DELAY .. "s", QuickJoin.DELAY + 2, {
        { label = "Cancel", icon = "st_x.png", style = "ghost", run = function()
            QuickJoin.cancelled = true
            Notifications:Info("Universal Hub Lite", "Join cancelled", 3)
        end },
    })

    -- Tick the subtitle down. Five silent seconds after "Joining X" reads as
    -- a hang; a counter reads as a window you are being given.
    task.spawn(function()
        for left = QuickJoin.DELAY, 1, -1 do
            if QuickJoin.cancelled then return end
            -- Something else took the bar: stop writing over it.
            if Notify.burst ~= burst or Bar.mode ~= "notify" then return end
            pcall(function()
                Bar.subLabel.Text = "Joining " .. g.name .. " in " .. left .. "s"
                Notify.layoutSub()
            end)
            task.wait(1)
        end
    end)

    -- Counted at the moment you commit, not on arrival: the teleport takes
    -- the session with it, so there is no "after" in which to record it.
    Usage.bump("games", g.keys[1])
    QuickJoin.lastKey = g.keys[1]
    Usage.flush(true)

    task.delay(QuickJoin.DELAY, function()
        if QuickJoin.cancelled then return end
        pcall(function()
            game:GetService("TeleportService"):Teleport(g.id, LocalPlayer)
        end)
    end)
    return true
end

-- ── Persistence across teleports ────────────────────────────────────────
-- Re-runs the hub after a rejoin or server hop. queue_on_teleport is an
-- executor global with no standard name, so try the known spellings.
Persist = { enabled = true }

Persist.queue = (typeof(queue_on_teleport) == "function" and queue_on_teleport)
    or (syn and syn.queue_on_teleport)
    or (fluxus and fluxus.queue_on_teleport)

-- Where to re-fetch from. Override with getgenv().UHUB_SOURCE before
-- executing if you host it elsewhere; otherwise this is the URL used.
Persist.url = (getgenv and getgenv().UHUB_SOURCE)
    or "https://raw.githubusercontent.com/Angxers2/Unihub/main/Unihub%20LITE%20V2.lua"

function Persist.arm()
    if not (Persist.enabled and Persist.queue) then return false end
    local ok = pcall(function()
        Persist.queue("loadstring(game:HttpGet('" .. Persist.url .. "'))()")
    end)
    return ok
end

function Persist.init()
    if Persist.started then return end
    Persist.started = true
    -- Fires for rejoin, server hop and any in-game place teleport.
    pcall(function()
        LocalPlayer.OnTeleport:Connect(function(state)
            if state == Enum.TeleportState.Started
            or state == Enum.TeleportState.InProgress then
                Persist.arm()
            end
        end)
    end)
end

function Persist.status()
    if not Persist.queue then return "unsupported" end
    return Persist.enabled and "on" or "off"
end

-- ── Unload ──────────────────────────────────────────────────────────────
-- Full teardown so the script can be re-executed cleanly: stop every active
-- toggle, drop the render/input connections, destroy the UI, and clear the
-- single-instance flag. Defined here so it closes over the toggle state
-- locals above. Every step is pcall'd -- a failure in one must not strand
-- the rest, or the user is left with a half-dead script and no UI.
function unexecuteHub()
    -- 1. Active toggles, via their own stop paths so world state is restored.
    pcall(function() if isFlying and flyForceStop then flyForceStop() end end)
    pcall(function() setNoClip(false) end)
    pcall(function() if isSpinning then toggleSpin() end end)
    pcall(function() stopAllAttach() end)
    pcall(function() stopStaring() end)
    pcall(function() stopCopyDance() end)
    pcall(function() if viewedPlayer then viewPlayer(nil) end end)
    pcall(function() isInfJumpEnabled = false end)
    pcall(function() _G.isOrbiting = false end)
    pcall(function()
        if _G.BangAnim then _G.BangAnim:Stop() _G.BangAnim = nil end
    end)

    -- 2. Connections held in file-scope locals.
    for _, c in ipairs({ flyConnection, noClipConnection, spinConnection,
                         viewConnection, clickTpConnection }) do
        pcall(function() if c then c:Disconnect() end end)
    end
    flyConnection, noClipConnection = nil, nil
    spinConnection, viewConnection, clickTpConnection = nil, nil, nil

    -- 3. UI render loops, then the GUI itself (which owns every card clip).
    pcall(function()
        if Info and Info.clockLoop then
            Info.clockLoop:Disconnect()
            Info.clockLoop = nil
        end
        if Perf and Perf.loop then
            Perf.loop:Disconnect()
            Perf.loop = nil
        end
    end)
    -- Drawing objects live outside the GUI: destroying Bar.gui does not
    -- touch them, so an un-stopped ESP renders forever with no way back.
    pcall(function() if ESP and ESP.stop then ESP.stop() end end)
    -- Counts are coalesced, so the last few would be lost without this.
    pcall(function() if Usage and Usage.flush then Usage.flush(true) end end)
    pcall(function() if Pos and Pos.stop then Pos.stop() end end)
    -- Leaving someone muted with no UI left to unmute them is a trap.
    pcall(function() if Voice and Voice.stop then Voice.stop() end end)
    -- A RenderStepped loop and a pile of AudioAnalyzers both outlive the
    -- GUI that made them.
    pcall(function()
        if Activity and Activity.hide then Activity.hide() end
        if Activity and Activity.loop then
            Activity.loop:Disconnect() Activity.loop = nil
        end
        for uid, an in pairs((Voice and Voice._an) or {}) do
            pcall(function() an:Destroy() end)
            Voice._an[uid] = nil
        end
    end)
    -- Its own ScreenGui, so destroying Bar.gui leaves it floating.
    pcall(function() if ScriptHub and ScriptHub.hide then ScriptHub.hide() end end)
    pcall(function() if Badge and Badge.stopMotion then Badge.stopMotion() end end)
    pcall(function() if Badge and Badge.spin then Badge.spin:Cancel() end end)
    pcall(function()
        -- Reset card state; the clips themselves die with Bar.gui below.
        for _, c in ipairs({ CmdBar, Info, Perf, Settings, Profile }) do
            if c then c.open = false end
        end
        if Settings then Settings.expanded, Settings.typing, Settings.dragging = false, false, false end
        if Badge then Badge.frame, Badge.shown = nil, nil end
    end)
    pcall(function()
        if Bar and Bar.gui then Bar.gui:Destroy() end
        if Bar then Bar.gui, Bar.holder, Bar.chips = nil, nil, {} end
    end)

    -- 4. Restore camera + character defaults the script may have changed.
    pcall(function()
        local cam = workspace.CurrentCamera
        if cam then cam.FieldOfView = 70 end
    end)

    -- 5. Release the single-instance lock last, so a re-execute is clean.
    getgenv().UniversalHubRunning = false
    print("[UHub] unloaded - safe to re-execute")
end

-- ════════════════════════════════════════════════════════════════════════
--  INFINITE YIELD COMPATIBILITY LAYER
--  IY command bodies are self-contained Roblox code apart from a dozen
--  helpers. Providing those here lets the bodies be used as-written instead
--  of rewritten by hand -- far less room for transcription mistakes.
--  Commands already answered by LITE are NOT imported.
-- ════════════════════════════════════════════════════════════════════════
Lighting = game:GetService("Lighting")

function getRoot(character)
    if not character then return nil end
    return character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("UpperTorso")
end

function notify(title, text)
    IY.notified = true          -- suppress the generic confirmation below
    Notifications:Info(tostring(title or "Universal Hub Lite"),
                       tostring(text or ""), 4)
end

-- IY's getstring(i, args) joins everything from index i onward.
function getstring(startIdx, args)
    local out = {}
    for i = startIdx, #args do out[#out + 1] = tostring(args[i]) end
    return table.concat(out, " ")
end

-- IY's getPlayer returns a list of player NAMES, not Player objects.
function getPlayer(name, speaker)
    speaker = speaker or LocalPlayer
    if name == nil or name == "" then return { speaker.Name } end
    local n = tostring(name):lower()
    if n == "all" then
        local t = {}
        for _, p in ipairs(Players:GetPlayers()) do t[#t + 1] = p.Name end
        return t
    elseif n == "others" then
        local t = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= speaker then t[#t + 1] = p.Name end
        end
        return t
    elseif n == "me" then
        return { speaker.Name }
    elseif n == "random" then
        local ps = Players:GetPlayers()
        return { ps[math.random(1, #ps)].Name }
    end
    local hit = findPlayer(name)
    return hit and { hit.Name } or {}
end

function r15(player)
    player = player or LocalPlayer
    local ok, res = pcall(function()
        local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        return h and h.RigType == Enum.HumanoidRigType.R15
    end)
    return ok and res or false
end

function isNumber(x) return tonumber(x) ~= nil end

function respawn(player)
    player = player or LocalPlayer
    pcall(function()
        local m = Instance.new("Model", workspace)
        Instance.new("Humanoid", m)
        local p = Instance.new("Part", m)
        p.Name = "Head"; p.CanCollide = false; p.Anchored = true
        p.CFrame = CFrame.new(9e9, 9e9, 9e9)
        player.Character = m
        task.wait()
        player.Character = nil
        m:Destroy()
    end)
end

function refresh(player)
    player = player or LocalPlayer
    pcall(function()
        local root = getRoot(player.Character)
        local pos = root and root.CFrame
        respawn(player)
        if pos then
            player.CharacterAdded:Wait()
            task.wait(0.35)
            local r2 = getRoot(player.Character)
            if r2 then r2.CFrame = pos end
        end
    end)
end

-- ── IY globals the imported bodies expect ───────────────────────────────
floatName      = "FloatPart"     -- name IY gives its float platform
tweenSpeed     = 1               -- studs/sec for the tween* commands
gotopartDelay  = 0.1             -- seconds between hops in gotopart*
COREGUI        = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")

-- IY indexes services as Services.Foo; proxy straight to GetService.
Services = setmetatable({}, {
    __index = function(_, k)
        local ok, sv = pcall(function() return game:GetService(k) end)
        return ok and sv or nil
    end,
})

function toClipboard(v)
    v = tostring(v)
    local ok = pcall(function() setclipboard(v) end)
    notify("Copied", ok and v or "clipboard unavailable")
end

-- Send to the game's chat, handling both the modern and legacy systems.
function chatMessage(str)
    str = tostring(str)
    pcall(function()
        local TCS = game:GetService("TextChatService")
        if TCS and TCS.ChatVersion == Enum.ChatVersion.TextChatService then
            TCS.TextChannels.RBXGeneral:SendAsync(str)
        else
            game:GetService("ReplicatedStorage")
                .DefaultChatSystemChatEvents.SayMessageRequest:FireServer(str, "All")
        end
    end)
end

-- Some IY bodies chain into another command. processCommand is a local
-- declared further down the file, so it is bound at startup instead of
-- captured here (it would be nil at this point).
function execCmd(str)
    if IY.exec then IY.exec(tostring(str)) end
end

-- ── Imported command table ──────────────────────────────────────────────
-- Dispatched from processCommand's fallback, so LITE's own branches always
-- win and nothing here can shadow an existing command.
IY = { cmds = {}, alias = {}, desc = {} }

function IY.shift(a)
    -- LITE's args[1] is the command word; IY bodies expect args[1] to be the
    -- FIRST PARAMETER. Without this every imported command is off by one.
    local t = {}
    for i = 2, #a do t[#t + 1] = a[i] end
    return t
end


-- Names that read badly when merely capitalised. Only the compounds
-- need this; the rest fall through to IY.label's rules.
IY.labels = {
    ["antilag"] = "Anti-lag",
    ["appearanceid"] = "Appearance ID",
    ["blockhats"] = "Hats blocked",
    ["blockhead"] = "Head blocked",
    ["blocktool"] = "Tool blocked",
    ["breakvelocity"] = "Velocity broken",
    ["bringpart"] = "Brought part",
    ["bringpartclass"] = "Brought part class",
    ["camdistance"] = "Camera distance",
    ["chardeleteclass"] = "Class deleted",
    ["chatage"] = "Account age",
    ["chatjoindate"] = "Join date",
    ["clearcharappearance"] = "Appearance cleared",
    ["clearhats"] = "Hats cleared",
    ["copyanimationid"] = "Animation ID copied",
    ["copyappearanceid"] = "Appearance ID copied",
    ["copyposition"] = "Position copied",
    ["copytools"] = "Tools copied",
    ["ctrllock"] = "Ctrl lock",
    ["deleteclass"] = "Class deleted",
    ["deletehats"] = "Hats deleted",
    ["deleteinvisparts"] = "Invisible parts deleted",
    ["deleteselectedtool"] = "Tool deleted",
    ["deletevelocity"] = "Velocity deleted",
    ["destroyheight"] = "Destroy height",
    ["drophats"] = "Hats dropped",
    ["droppabletools"] = "Tools droppable",
    ["droptools"] = "Tools dropped",
    ["equiptools"] = "Tools equipped",
    ["firstp"] = "First person",
    ["freezeanims"] = "Animations frozen",
    ["fullbright"] = "Fullbright",
    ["getposition"] = "Position",
    ["globalshadows"] = "Global shadows",
    ["gotocamera"] = "Went to camera",
    ["gotomodel"] = "Went to model",
    ["gotopart"] = "Went to part",
    ["gotopartclass"] = "Went to part class",
    ["gotopartdelay"] = "Goto part delay",
    ["headsize"] = "Head size",
    ["headthrow"] = "Head throw",
    ["hipheight"] = "Hip height",
    ["hitboxes"] = "Hitboxes shown",
    ["joindate"] = "Join date",
    ["jpower"] = "Jump power",
    ["lockws"] = "Walkspeed locked",
    ["loopanimation"] = "Animation looping",
    ["maxslopeangle"] = "Max slope angle",
    ["maxzoom"] = "Max zoom",
    ["minzoom"] = "Min zoom",
    ["mousesensitivity"] = "Mouse sensitivity",
    ["muteallvoices"] = "All voices muted",
    ["nilchar"] = "Character nil'd",
    ["noanim"] = "Animations off",
    ["noarms"] = "Arms removed",
    ["nobgui"] = "Billboard GUIs off",
    ["noface"] = "Face removed",
    ["nofog"] = "Fog off",
    ["nolegs"] = "Legs removed",
    ["nolimbs"] = "Limbs removed",
    ["nolocate"] = "Locate off",
    ["noprompts"] = "Proximity prompts off",
    ["noroot"] = "Root removed",
    ["norotate"] = "Rotation locked",
    ["nosit"] = "Sitting blocked",
    ["notifyping"] = "Ping",
    ["notools"] = "Tools removed",
    ["pulsetp"] = "Pulse teleport",
    ["reanim"] = "Reanimated",
    ["refreshanimations"] = "Animations refreshed",
    ["removeads"] = "Ads removed",
    ["removeterrain"] = "Terrain removed",
    ["replaceroot"] = "Root replaced",
    ["screenshot"] = "Screenshot",
    ["showprompts"] = "Proximity prompts on",
    ["sitwalk"] = "Sit walk",
    ["stopanimations"] = "Animations stopped",
    ["strengthen"] = "Strengthened",
    ["thirdp"] = "Third person",
    ["togglefs"] = "Fullscreen",
    ["tpposition"] = "Teleported",
    ["tweengoto"] = "Tweened to player",
    ["tweenspeed"] = "Tween speed",
    ["tweentpposition"] = "Tweened to position",
    ["unctrllock"] = "Ctrl lock off",
    ["unequiptools"] = "Tools unequipped",
    ["unfreezeanims"] = "Animations resumed",
    ["unglobalshadows"] = "Global shadows off",
    ["unhitboxes"] = "Hitboxes hidden",
    ["unlockws"] = "Walkspeed unlocked",
    ["unmuteallvoices"] = "All voices unmuted",
    ["unnilchar"] = "Character restored",
    ["unnorotate"] = "Rotation unlocked",
    ["unnosit"] = "Sitting allowed",
    ["unweaken"] = "Weaken off",
    ["usetools"] = "Using tools",
    ["vehiclegoto"] = "Went to vehicle",
    ["walktopos"] = "Walking to position",
    ["wallwalk"] = "Wall walk",
    ["weaken"] = "Weakened",
    ["whisper"] = "Whispered",
}

-- Human label for the confirmation toast. "un"/"no" prefixes read far
-- better as a trailing "off" than as "Un hitboxes".
function IY.label(name)
    local n = tostring(name)
    if IY.labels[n] then return IY.labels[n] end
    local function cap(w) return w:sub(1, 1):upper() .. w:sub(2) end

    for _, p in ipairs({ "un", "no" }) do
        local rest = n:sub(1, #p) == p and n:sub(#p + 1) or nil
        -- only when the remainder is itself a command, so "notools" splits
        -- but "night" does not
        if rest and #rest > 2 and (IY.cmds[rest] or IY.alias[rest]) then
            return cap(rest) .. " off"
        end
    end
    if n:sub(1, 4) == "stop" and #n > 6 then return "Stop " .. n:sub(5) end
    return cap(n)
end

function IY.run(command, rawArgs)
    local key = IY.alias[command] or command
    local fn = IY.cmds[key]
    if not fn then return false end

    char = LocalPlayer.Character            -- IY bodies read this global
    IY.notified = false
    local ok, err = pcall(fn, IY.shift(rawArgs), LocalPlayer)

    if not ok then
        -- Surface the failure instead of dying silently. These bodies come
        -- from another script; some will not survive contact with this one.
        Notifications:Error("Universal Hub Lite",
            IY.label(key) .. " failed", 4)
        warn("[UHub] " .. tostring(command) .. ": " .. tostring(err))
        return true
    end

    -- Most IY bodies never call notify(), so without this the imported
    -- commands would run completely silently.
    if not IY.notified then
        -- Detail line: what ran, then the description -- repeating the bare
        -- command name told the user nothing they had not just typed.
        local detail = IY.label(key)
        local target = nil

        if IY.needsPlayer[key] and rawArgs[2] then
            local hit = findPlayer(rawArgs[2])
            if hit then
                target = hit.Name
                detail = detail .. "  \194\183  " .. hit.DisplayName
            end
        elseif rawArgs[2] then
            detail = detail .. "  \194\183  " .. tostring(rawArgs[2])
        end

        -- Deliberately NOT the description: that explains what the command
        -- does, which the user just chose. It belongs in the suggestion row
        -- and the command list, before the fact -- not in the confirmation.

        -- Offer the reverse where one exists, so a toggle can be undone from
        -- the toast the same way the native commands allow.
        local actions
        local opp = IY.opposite[key]
        if opp then
            local rest = {}
            for i = 2, #rawArgs do rest[#rest + 1] = rawArgs[i] end
            -- "freeze random" picked ONE person. Undoing with the raw token
            -- would roll again and unfreeze somebody else entirely, so pin
            -- the undo to whoever it actually hit. Only for the tokens that
            -- resolve to one -- "all" and "others" re-expand correctly, and
            -- pinning those would undo a single player out of the crowd.
            local tok = rest[1] and PlayerTokens.resolve(rest[1], key)
            if target and tok and tok.scope == "one" then rest[1] = target end
            actions = { {
                label = IY.label(opp), icon = "st_refresh-cw.png", style = "light",
                run = function()
                    IY.run(opp, { "!" .. opp, table.unpack(rest) })
                end,
            } }
        end

        Notifications:Success("Universal Hub Lite", detail, 3.5, actions, target)
    end
    return true
end

IY.cmds["age"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	local ages = {}
	for i,v in pairs(players) do
		local p = Players[v]
		table.insert(ages, p.Name.."'s age is: "..p.AccountAge)
	end
	notify('Account Age',table.concat(ages, ',\n'))
end
IY.cmds["ambient"] = function(args, speaker)
	Lighting.Ambient = Color3.new(args[1],args[2],args[3])
	Lighting.OutdoorAmbient = Color3.new(args[1],args[2],args[3])
end
IY.cmds["anchor"] = function(args, speaker)
    getRoot(speaker.Character).Anchored = true
end
IY.cmds["animspeed"] = function(args, speaker)
	local Char = speaker.Character
	local Hum = Char:FindFirstChildOfClass("Humanoid") or Char:FindFirstChildOfClass("AnimationController")

	for i,v in next, Hum:GetPlayingAnimationTracks() do
		v:AdjustSpeed(tonumber(args[1] or 1))
	end
end
IY.cmds["antilag"] = function(args, speaker)
	local Terrain = workspace:FindFirstChildWhichIsA("Terrain")
	Terrain.WaterWaveSize = 0
	Terrain.WaterWaveSpeed = 0
	Terrain.WaterReflectance = 0
	Terrain.WaterTransparency = 1
	Lighting.GlobalShadows = false
	Lighting.FogEnd = 9e9
	Lighting.FogStart = 9e9
	settings().Rendering.QualityLevel = 1
	for _, v in pairs(game:GetDescendants()) do
		if v:IsA("BasePart") then
			v.CastShadow = false
			v.Material = "Plastic"
			v.Reflectance = 0
			v.BackSurface = "SmoothNoOutlines"
			v.BottomSurface = "SmoothNoOutlines"
			v.FrontSurface = "SmoothNoOutlines"
			v.LeftSurface = "SmoothNoOutlines"
			v.RightSurface = "SmoothNoOutlines"
			v.TopSurface = "SmoothNoOutlines"
		elseif v:IsA("Decal") then
			v.Transparency = 1
			v.Texture = ""
		elseif v:IsA("ParticleEmitter") or v:IsA("Trail") then
			v.Lifetime = NumberRange.new(0)
		end
	end
	for _, v in pairs(Lighting:GetDescendants()) do
		if v:IsA("PostEffect") then
			v.Enabled = false
		end
	end
	workspace.DescendantAdded:Connect(function(child)
		task.spawn(function()
			if child:IsA("ForceField") or child:IsA("Sparkles") or child:IsA("Smoke") or child:IsA("Fire") or child:IsA("Beam") then
				RunService.Heartbeat:Wait()
				child:Destroy()
			elseif child:IsA("BasePart") then
				child.CastShadow = false
			end
		end)
	end)
end
IY.cmds["appearanceid"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	for i,v in pairs(players) do
		local aid = tostring(Players[v].CharacterAppearanceId)
		notify('Appearance ID',aid)
	end
end
IY.cmds["blockhats"] = function(args, speaker)
	for _,v in pairs(speaker.Character:FindFirstChildOfClass('Humanoid'):GetAccessories()) do
		for i,c in pairs(v:GetDescendants()) do
			if c:IsA("SpecialMesh") then
				c:Destroy()
			end
		end
	end
end
IY.cmds["blockhead"] = function(args, speaker)
	speaker.Character.Head:FindFirstChildOfClass("SpecialMesh"):Destroy()
end
IY.cmds["blocktool"] = function(args, speaker)
	for _,v in pairs(speaker.Character:GetChildren()) do
		if v:IsA("Tool") or v:IsA("HopperBin") then
			for i,c in pairs(v:GetDescendants()) do
				if c:IsA("SpecialMesh") then
					c:Destroy()
				end
			end
		end
	end
end
IY.cmds["breakvelocity"] = function(args, speaker)
	local BeenASecond, V3 = false, Vector3.new(0, 0, 0)
	delay(1, function()
		BeenASecond = true
	end)
	while not BeenASecond do
		for _, v in ipairs(speaker.Character:GetDescendants()) do
			if v:IsA("BasePart") then
				v.Velocity, v.RotVelocity = V3, V3
			end
		end
		wait()
	end
end
IY.cmds["brightness"] = function(args, speaker)
	Lighting.Brightness = args[1]
end
IY.cmds["bringpart"] = function(args, speaker)
	for i,v in pairs(workspace:GetDescendants()) do
		if v.Name:lower() == getstring(1, args):lower() and v:IsA("BasePart") then
			v.CFrame = getRoot(speaker.Character).CFrame
		end
	end
end
IY.cmds["bringpartclass"] = function(args, speaker)
	for i,v in pairs(workspace:GetDescendants()) do
		if v.ClassName:lower() == getstring(1, args):lower() and v:IsA("BasePart") then
			v.CFrame = getRoot(speaker.Character).CFrame
		end
	end
end
IY.cmds["camdistance"] = function(args, speaker)
	local camMax = speaker.CameraMaxZoomDistance
	local camMin = speaker.CameraMinZoomDistance
	if camMax < tonumber(args[1]) then
		camMax = args[1]
	end
	speaker.CameraMaxZoomDistance = args[1]
	speaker.CameraMinZoomDistance = args[1]
	wait()
	speaker.CameraMaxZoomDistance = camMax
	speaker.CameraMinZoomDistance = camMin
end
IY.cmds["chardeleteclass"] = function(args, speaker)
	for i,v in pairs(speaker.Character:GetDescendants()) do
		if v.ClassName:lower() == getstring(1, args):lower() then
			v:Destroy()
		end
	end
	notify('Item(s) Deleted','Deleted items with ClassName ' ..getstring(1, args))
end
IY.cmds["chat"] = function(args, speaker)
	local cString = getstring(1, args)
	chatMessage(cString)
end
IY.cmds["chatage"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	local ages = {}
	for i,v in pairs(players) do
		local p = Players[v]
		table.insert(ages, p.Name.."'s age is: "..p.AccountAge)
	end
	local chatString = table.concat(ages, ', ')
	chatMessage(chatString)
end
IY.cmds["chatjoindate"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	local dates = {}
	for i,v in pairs(players) do
		local p = Players[v]

		local secondsOld = p.AccountAge * 24 * 60 * 60
		local now = os.time()
		local dateJoined  = p.Name .. " joined: " .. os.date("%m/%d/%y", now - secondsOld)

		table.insert(dates, dateJoined)
	end
	local chatString = table.concat(dates, ', ')
	chatMessage(chatString)
end
IY.cmds["clearcharappearance"] = function(args, speaker)
	speaker:ClearCharacterAppearance()
end
IY.cmds["clearhats"] = function(args, speaker)
	if firetouchinterest then
		local Player = Players.LocalPlayer
		local Character = Player.Character
		local Old = getRoot(Character).CFrame
		local Hats = {}

		for _, child in ipairs(workspace:GetChildren()) do
			if child:IsA("Accessory") then
				table.insert(Hats, child)
			end
		end

		for _, accessory in ipairs(Character:FindFirstChildOfClass("Humanoid"):GetAccessories()) do
			accessory:Destroy()
		end

		for i = 1, #Hats do
			repeat RunService.Heartbeat:wait() until Hats[i]
			firetouchinterest(Hats[i].Handle,getRoot(Character),0)
			repeat RunService.Heartbeat:wait() until Character:FindFirstChildOfClass("Accessory")
			Character:FindFirstChildOfClass("Accessory"):Destroy()
			repeat RunService.Heartbeat:wait() until not Character:FindFirstChildOfClass("Accessory")
		end

		execCmd("reset")

		Player.CharacterAdded:Wait()

		for i = 1,20 do 
			RunService.Heartbeat:Wait()
			if getRoot(Player.Character) then
				getRoot(Player.Character).Humanoid.RootPart.CFrame = Old
			end
		end
	else
		notify("Incompatible Exploit","Your exploit does not support this command (missing firetouchinterest)")
	end
end
IY.cmds["clickdelete"] = function(args, speaker)
	if speaker == Players.LocalPlayer then
		notify('Click Delete','Go to Settings > Keybinds > Add to set up click delete')
	end
end
IY.cmds["copyanimationid"] = function(args, speaker)
	local copyAnimId = function(player)
		local found = "Animations Copied"

		for _, v in pairs(player.Character:FindFirstChildWhichIsA("Humanoid"):GetPlayingAnimationTracks()) do
			local animationId = v.Animation.AnimationId
			local assetId = animationId:find("rbxassetid://") and animationId:match("%d+")

			if not string.find(animationId, "507768375") and not string.find(animationId, "180435571") then
				if assetId then
					local success, result = pcall(function()
						return MarketplaceService:GetProductInfo(tonumber(assetId)).Name
					end)
					local name = success and result or "Failed to get name"
					found = found .. "\n\nName: " .. name .. "\nAnimation Id: " .. animationId
				else
					found = found .. "\n\nAnimation Id: " .. animationId
				end
			end
		end

		if found ~= "Animations Copied" then
			toClipboard(found)
		else
			notify("Animations", "No animations to copy")
		end
	end

	if args[1] then
		copyAnimId(Players[getPlayer(args[1], speaker)[1]])
	else
		copyAnimId(speaker)
	end
end
IY.cmds["copyappearanceid"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	for i,v in pairs(players) do
		local aid = tostring(Players[v].CharacterAppearanceId)
		toClipboard(aid)
	end
end
IY.cmds["copyposition"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	for i,v in pairs(players)do
		local char = Players[v].Character
		local pos = char and (getRoot(char) or char:FindFirstChildWhichIsA("BasePart"))
		pos = pos and pos.Position
		if not pos then
			return notify('Getposition Error','Missing character')
		end
		local roundedPos = math.round(pos.X) .. ", " .. math.round(pos.Y) .. ", " .. math.round(pos.Z)
		toClipboard(roundedPos)
	end
end
IY.cmds["copytools"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	for i,v in pairs(players)do
		task.spawn(function()
			for i,v in pairs(Players[v]:FindFirstChildOfClass("Backpack"):GetChildren()) do
				if v:IsA('Tool') or v:IsA('HopperBin') then
					v:Clone().Parent = speaker:FindFirstChildOfClass("Backpack")
				end
			end
		end)
	end
end
IY.cmds["creeper"] = function(args, speaker)
	if r15(speaker) then
		speaker.Character.Head:FindFirstChildOfClass("SpecialMesh"):Destroy()
		speaker.Character.LeftUpperArm:Destroy()
		speaker.Character.RightUpperArm:Destroy()
		speaker.Character:FindFirstChildOfClass("Humanoid"):RemoveAccessories()
	else
		speaker.Character.Head:FindFirstChildOfClass("SpecialMesh"):Destroy()
		speaker.Character["Left Arm"]:Destroy()
		speaker.Character["Right Arm"]:Destroy()
		speaker.Character:FindFirstChildOfClass("Humanoid"):RemoveAccessories()
	end
end
IY.cmds["ctrllock"] = function(args, speaker)
	local mouseLockController = speaker.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("CameraModule"):WaitForChild("MouseLockController")
	local boundKeys = mouseLockController:FindFirstChild("BoundKeys")

	if boundKeys then
		boundKeys.Value = "LeftControl"
	else
		boundKeys = Instance.new("StringValue")
		boundKeys.Name = "BoundKeys"
		boundKeys.Value = "LeftControl"
		boundKeys.Parent = mouseLockController
	end
end
IY.cmds["day"] = function(args, speaker)
	Lighting.ClockTime = 14
end
IY.cmds["delete"] = function(args, speaker)
	for i,v in pairs(workspace:GetDescendants()) do
		if v.Name:lower() == getstring(1, args):lower() then
			v:Destroy()
		end
	end
	notify('Item(s) Deleted','Deleted ' ..getstring(1, args))
end
IY.cmds["deleteclass"] = function(args, speaker)
	for i,v in pairs(workspace:GetDescendants()) do
		if v.ClassName:lower() == getstring(1, args):lower() then
			v:Destroy()
		end
	end
	notify('Item(s) Deleted','Deleted items with ClassName ' ..getstring(1, args))
end
IY.cmds["deletehats"] = function(args, speaker)
	for i,v in next, speaker.Character:GetDescendants() do
		if v:IsA("Accessory") then
			for i,p in next, v:GetDescendants() do
				if p:IsA("Weld") then
					p:Destroy()
				end
			end
		end
	end
end
IY.cmds["deleteinvisparts"] = function(args, speaker)
	for i,v in pairs(workspace:GetDescendants()) do
		if v:IsA("BasePart") and v.Transparency == 1 and v.CanCollide then
			v:Destroy()
		end
	end
end
IY.cmds["deleteselectedtool"] = function(args, speaker)
	for i,v in pairs(speaker.Character:GetDescendants()) do
		if v:IsA('Tool') or v:IsA('HopperBin') then
			v:Destroy()
		end
	end
end
IY.cmds["deletevelocity"] = function(args, speaker)
	for i,v in pairs(speaker.Character:GetDescendants()) do
		if v:IsA("BodyVelocity") or v:IsA("BodyGyro") or v:IsA("RocketPropulsion") or v:IsA("BodyThrust") or v:IsA("BodyAngularVelocity") or v:IsA("AngularVelocity") or v:IsA("BodyForce") or v:IsA("VectorForce") or v:IsA("LineForce") then
			v:Destroy()
		end
	end
end
IY.cmds["destroyheight"] = function(args, speaker)
	local dh = args[1] or -500
	if isNumber(dh) then
		workspace.FallenPartsDestroyHeight = dh
	end
end
IY.cmds["disablestate"] = function(args, speaker)
	local x = args[1]
	if not tonumber(x) then
		local x = Enum.HumanoidStateType[args[1]]
	end
	speaker.Character:FindFirstChildOfClass("Humanoid"):SetStateEnabled(x, false)
end
IY.cmds["drophats"] = function(args, speaker)
	if speaker.Character then
		for _,v in pairs(speaker.Character:FindFirstChildOfClass('Humanoid'):GetAccessories()) do
			v.Parent = workspace
		end
	end
end
IY.cmds["droppabletools"] = function(args, speaker)
	if speaker.Character then
		for _,obj in pairs(speaker.Character:GetChildren()) do
			if obj:IsA("Tool") then
				obj.CanBeDropped = true
			end
		end
	end
	if speaker:FindFirstChildOfClass("Backpack") then
		for _,obj in pairs(speaker:FindFirstChildOfClass("Backpack"):GetChildren()) do
			if obj:IsA("Tool") then
				obj.CanBeDropped = true
			end
		end
	end
end
IY.cmds["droptools"] = function(args, speaker)
	for i,v in pairs(Players.LocalPlayer.Backpack:GetChildren()) do
		if v:IsA("Tool") then
			v.Parent = Players.LocalPlayer.Character
		end
	end
	wait()
	for i,v in pairs(Players.LocalPlayer.Character:GetChildren()) do
		if v:IsA("Tool") then
			v.Parent = workspace
		end
	end
end
IY.cmds["enablestate"] = function(args, speaker)
	local x = args[1]
	if not tonumber(x) then
		local x = Enum.HumanoidStateType[args[1]]
	end
	speaker.Character:FindFirstChildOfClass("Humanoid"):SetStateEnabled(x, true)
end
IY.cmds["equiptools"] = function(args, speaker)
	for i,v in pairs(speaker:FindFirstChildOfClass("Backpack"):GetChildren()) do
		if v:IsA("Tool") or v:IsA("HopperBin") then
			v.Parent = speaker.Character
		end
	end
end
IY.cmds["firstp"] = function(args, speaker)
	speaker.CameraMode = "LockFirstPerson"
end
IY.cmds["freeze"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	if players ~= nil then
		for i,v in pairs(players) do
			task.spawn(function()
				for i, x in next, Players[v].Character:GetDescendants() do
					if x:IsA("BasePart") and not x.Anchored then
						x.Anchored = true
					end
				end
			end)
		end
	end
end
IY.cmds["freezeanims"] = function(args, speaker)
	local Humanoid = speaker.Character:FindFirstChildOfClass("Humanoid") or speaker.Character:FindFirstChildOfClass("AnimationController")
	local ActiveTracks = Humanoid:GetPlayingAnimationTracks()
	for _, v in pairs(ActiveTracks) do
		v:AdjustSpeed(0)
	end
end
IY.cmds["friend"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	for i,v in pairs(players)do
		speaker:RequestFriendship(Players[v])
	end
end
IY.cmds["fullbright"] = function(args, speaker)
	Lighting.Brightness = 2
	Lighting.ClockTime = 14
	Lighting.FogEnd = 100000
	Lighting.GlobalShadows = false
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
end
IY.cmds["getposition"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	for i,v in pairs(players)do
		local char = Players[v].Character
		local pos = char and (getRoot(char) or char:FindFirstChildWhichIsA("BasePart"))
		pos = pos and pos.Position
		if not pos then
			return notify('Getposition Error','Missing character')
		end
		local roundedPos = math.round(pos.X) .. ", " .. math.round(pos.Y) .. ", " .. math.round(pos.Z)
		notify('Current Position',roundedPos)
	end
end
IY.cmds["globalshadows"] = function(args, speaker)
	Lighting.GlobalShadows = true
end
IY.cmds["gotocamera"] = function(args, speaker)
	getRoot(speaker.Character).CFrame = workspace.Camera.CFrame
end
IY.cmds["gotomodel"] = function(args, speaker)
	for i,v in pairs(workspace:GetDescendants()) do
		if v.Name:lower() == getstring(1, args):lower() and v:IsA("Model") then
			if speaker.Character:FindFirstChildOfClass('Humanoid') and speaker.Character:FindFirstChildOfClass('Humanoid').SeatPart then
				speaker.Character:FindFirstChildOfClass('Humanoid').Sit = false
				wait(.1)
			end
			wait(gotopartDelay)
			getRoot(speaker.Character).CFrame = v:GetModelCFrame()
		end
	end
end
IY.cmds["gotopart"] = function(args, speaker)
	for i,v in pairs(workspace:GetDescendants()) do
		if v.Name:lower() == getstring(1, args):lower() and v:IsA("BasePart") then
			if speaker.Character:FindFirstChildOfClass('Humanoid') and speaker.Character:FindFirstChildOfClass('Humanoid').SeatPart then
				speaker.Character:FindFirstChildOfClass('Humanoid').Sit = false
				wait(.1)
			end
			wait(gotopartDelay)
			getRoot(speaker.Character).CFrame = v.CFrame
		end
	end
end
IY.cmds["gotopartclass"] = function(args, speaker)
	for i,v in pairs(workspace:GetDescendants()) do
		if v.ClassName:lower() == getstring(1, args):lower() and v:IsA("BasePart") then
			if speaker.Character:FindFirstChildOfClass('Humanoid') and speaker.Character:FindFirstChildOfClass('Humanoid').SeatPart then
				speaker.Character:FindFirstChildOfClass('Humanoid').Sit = false
				wait(.1)
			end
			wait(gotopartDelay)
			getRoot(speaker.Character).CFrame = v.CFrame
		end
	end
end
IY.cmds["gotopartdelay"] = function(args, speaker)
	local gtpDelay = args[1] or 0.1
	if isNumber(gtpDelay) then
		gotopartDelay = gtpDelay
	end
end
IY.cmds["grippos"] = function(args, speaker)
	for i,v in pairs(speaker.Character:GetDescendants()) do
		if v:IsA("Tool") then
			v.Parent = speaker:FindFirstChildOfClass("Backpack")
			v.GripPos = Vector3.new(args[1],args[2],args[3])
			v.Parent = speaker.Character
		end
	end
end
IY.cmds["headsize"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	for i,v in pairs(players) do
		if Players[v] ~= speaker and Players[v].Character:FindFirstChild('Head') then
			local sizeArg = tonumber(args[2])
			local Size = Vector3.new(sizeArg,sizeArg,sizeArg)
			local Head = Players[v].Character:FindFirstChild('Head')
			if Head:IsA("BasePart") then
				Head.CanCollide = false
				if not args[2] or sizeArg == 1 then
					Head.Size = Vector3.new(2,1,1)
				else
					Head.Size = Size
				end
			end
		end
	end
end
IY.cmds["headthrow"] = function(args, speaker)
	if not r15(speaker) then
		local AnimationId = "35154961"
		local Anim = Instance.new("Animation")
		Anim.AnimationId = "rbxassetid://"..AnimationId
		local k = speaker.Character:FindFirstChildOfClass('Humanoid'):LoadAnimation(Anim)
		k:Play(0)
		k:AdjustSpeed(1)
	else
		notify('R6 Required','This command requires the r6 rig type')
	end
end
IY.cmds["hipheight"] = function(args, speaker)
	local hipHeight = args[1] or (r15(speaker) and 2.1 or 0)
	if isNumber(hipHeight) then
		speaker.Character:FindFirstChildWhichIsA("Humanoid").HipHeight = hipHeight
	end
end
IY.cmds["hitbox"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	local transparency = args[3] and tonumber(args[3]) or 0.4
	for i,v in pairs(players) do
		if Players[v] ~= speaker and getRoot(Players[v].Character) then
			local sizeArg = tonumber(args[2])
			local Size = Vector3.new(sizeArg,sizeArg,sizeArg)
			local Root = getRoot(Players[v].Character)
			if Root:IsA("BasePart") then
				Root.CanCollide = false
				if not args[2] or sizeArg == 1 then
					Root.Size = Vector3.new(2,1,1)
					Root.Transparency = transparency
				else
					Root.Size = Size
					Root.Transparency = transparency
				end
			end
		end
	end
end
IY.cmds["hitboxes"] = function(args, speaker)
    settings():GetService("RenderSettings").ShowBoundingBoxes = true
end
IY.cmds["inspect"] = function(args, speaker)
	for _, v in ipairs(getPlayer(args[1], speaker)) do
		GuiService:CloseInspectMenu()
		GuiService:InspectPlayerFromUserId(Players[v].UserId)
	end
end
IY.cmds["joindate"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	local dates = {}
	for i,v in pairs(players) do
		local p = Players[v]

		local secondsOld = p.AccountAge * 24 * 60 * 60
		local now = os.time()
		local dateJoined  = p.Name .. " joined: " .. os.date("%m/%d/%y", now - secondsOld)

		table.insert(dates, dateJoined)
	end
	notify('Join Date (Month/Day/Year)',table.concat(dates, ',\n'))
end
IY.cmds["jpower"] = function(args, speaker)
	local jpower = args[1] or 50
	if isNumber(jpower) then
		if speaker.Character:FindFirstChildOfClass('Humanoid').UseJumpPower then
			speaker.Character:FindFirstChildOfClass('Humanoid').JumpPower = jpower
		else
			speaker.Character:FindFirstChildOfClass('Humanoid').JumpHeight  = jpower
		end
	end
end
IY.cmds["lay"] = function(args, speaker)
	local humanoid = speaker.Character:FindFirstChildWhichIsA("Humanoid")
	humanoid.Sit = true
	task.wait(0.1)
	humanoid.RootPart.CFrame = humanoid.RootPart.CFrame * CFrame.Angles(math.pi * 0.5, 0, 0)
	for _, v in ipairs(humanoid:GetPlayingAnimationTracks()) do
		v:Stop()
	end
end
IY.cmds["light"] = function(args, speaker)
	local light = Instance.new("PointLight")
	light.Parent = getRoot(speaker.Character)
	light.Range = 30
	if args[1] then
		light.Brightness = args[2]
		light.Range = args[1]
	else
		light.Brightness = 5
	end
end
IY.cmds["lockws"] = function(args, speaker)
	for i,v in pairs(workspace:GetDescendants()) do
		if v:IsA("BasePart") then
			v.Locked = true
		end
	end
end
IY.cmds["loopanimation"] = function(args, speaker)
	local Char = speaker.Character
	local Human = Char and Char.FindFirstChildWhichIsA(Char, "Humanoid")
	for _, v in ipairs(Human.GetPlayingAnimationTracks(Human)) do
		v.Looped = true
	end
end
IY.cmds["maxslopeangle"] = function(args, speaker)
	local sangle = args[1] or 89
	if isNumber(sangle) then
		speaker.Character:FindFirstChildWhichIsA("Humanoid").MaxSlopeAngle = sangle
	end
end
IY.cmds["maxzoom"] = function(args, speaker)
	speaker.CameraMaxZoomDistance = args[1]
end
IY.cmds["minzoom"] = function(args, speaker)
	speaker.CameraMinZoomDistance = args[1]
end
IY.cmds["mousesensitivity"] = function(args, speaker)
	UserInputService.MouseDeltaSensitivity = args[1]
end
IY.cmds["muteallvoices"] = function(args, speaker)
	Services.VoiceChatInternal:SubscribePauseAll(true)
end
IY.cmds["naked"] = function(args, speaker)
	for i,v in pairs(speaker.Character:GetDescendants()) do
		if v:IsA("Clothing") or v:IsA("ShirtGraphic") then
			v:Destroy()
		end
	end
end
IY.cmds["night"] = function(args, speaker)
	Lighting.ClockTime = 0
end
IY.cmds["nilchar"] = function(args, speaker)
	if speaker.Character ~= nil then
		speaker.Character.Parent = nil
	end
end
IY.cmds["noanim"] = function(args, speaker)
	speaker.Character.Animate.Disabled = true
end
IY.cmds["noarms"] = function(args, speaker)
	if r15(speaker) then
		for i,v in pairs(speaker.Character:GetChildren()) do
			if v:IsA("BasePart") and
				v.Name == "RightUpperArm" or
				v.Name == "LeftUpperArm" then
				v:Destroy()
			end
		end
	else
		for i,v in pairs(speaker.Character:GetChildren()) do
			if v:IsA("BasePart") and
				v.Name == "Right Arm" or
				v.Name == "Left Arm" then
				v:Destroy()
			end
		end
	end
end
IY.cmds["nobgui"] = function(args, speaker)
	for i,v in pairs(speaker.Character:GetDescendants())do
		if v:IsA("BillboardGui") or v:IsA("SurfaceGui") then
			v:Destroy()
		end
	end
end
IY.cmds["noclickdetectorlimits"] = function(args, speaker)
	for i,v in ipairs(workspace:GetDescendants()) do
		if v:IsA("ClickDetector") then
			v.MaxActivationDistance = math.huge
		end
	end
end
IY.cmds["noface"] = function(args, speaker)
	for i,v in pairs(speaker.Character:GetDescendants()) do
		if v:IsA("Decal") and v.Name == 'face' then
			v:Destroy()
		end
	end
end
IY.cmds["nofog"] = function(args, speaker)
	Lighting.FogEnd = 100000
	for i,v in pairs(Lighting:GetDescendants()) do
		if v:IsA("Atmosphere") then
			v:Destroy()
		end
	end
end
IY.cmds["nolegs"] = function(args, speaker)
	if r15(speaker) then
		for i,v in pairs(speaker.Character:GetChildren()) do
			if v:IsA("BasePart") and
				v.Name == "RightUpperLeg" or
				v.Name == "LeftUpperLeg" then
				v:Destroy()
			end
		end
	else
		for i,v in pairs(speaker.Character:GetChildren()) do
			if v:IsA("BasePart") and
				v.Name == "Right Leg" or
				v.Name == "Left Leg" then
				v:Destroy()
			end
		end
	end
end
IY.cmds["nolimbs"] = function(args, speaker)
	if r15(speaker) then
		for i,v in pairs(speaker.Character:GetChildren()) do
			if v:IsA("BasePart") and
				v.Name == "RightUpperLeg" or
				v.Name == "LeftUpperLeg" or
				v.Name == "RightUpperArm" or
				v.Name == "LeftUpperArm" then
				v:Destroy()
			end
		end
	else
		for i,v in pairs(speaker.Character:GetChildren()) do
			if v:IsA("BasePart") and
				v.Name == "Right Leg" or
				v.Name == "Left Leg" or
				v.Name == "Right Arm" or
				v.Name == "Left Arm" then
				v:Destroy()
			end
		end
	end
end
IY.cmds["nolocate"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	if args[1] then
		for i,v in pairs(players) do
			for i,c in pairs(COREGUI:GetChildren()) do
				if c.Name == Players[v].Name..'_LC' then
					c:Destroy()
				end
			end
		end
	else
		for i,c in pairs(COREGUI:GetChildren()) do
			if string.sub(c.Name, -3) == '_LC' then
				c:Destroy()
			end
		end
	end
end
IY.cmds["noprompts"] = function(args, speaker)
	COREGUI.PurchasePromptApp.Enabled = false
end
IY.cmds["noproximitypromptlimits"] = function(args, speaker)
	for i,v in pairs(workspace:GetDescendants()) do
		if v:IsA("ProximityPrompt") then
			v.MaxActivationDistance = math.huge
		end
	end
end
IY.cmds["norender"] = function(args, speaker)
	RunService:Set3dRenderingEnabled(false)
end
IY.cmds["noroot"] = function(args, speaker)
	if speaker.Character ~= nil then
		local char = Players.LocalPlayer.Character
		char.Parent = nil
		char.Humanoid.RootPart:Destroy()
		char.Parent = workspace
	end
end
IY.cmds["norotate"] = function(args, speaker)
	speaker.Character:FindFirstChildOfClass('Humanoid').AutoRotate  = false
end
IY.cmds["nosit"] = function(args, speaker)
	speaker.Character:FindFirstChildWhichIsA("Humanoid"):SetStateEnabled(Enum.HumanoidStateType.Seated, false)
end
IY.cmds["notifyping"] = function(args, speaker)
	notify("Ping", math.round(speaker:GetNetworkPing() * 1000) .. "ms")
end
IY.cmds["notools"] = function(args, speaker)
	for i,v in pairs(speaker:FindFirstChildOfClass("Backpack"):GetDescendants()) do
		if v:IsA('Tool') or v:IsA('HopperBin') then
			v:Destroy()
		end
	end
	for i,v in pairs(speaker.Character:GetDescendants()) do
		if v:IsA('Tool') or v:IsA('HopperBin') then
			v:Destroy()
		end
	end
end
IY.cmds["offset"] = function(args, speaker)
    if #args < 3 then return end
    speaker.Character:TranslateBy(Vector3.new(tonumber(args[1]) or 0, tonumber(args[2]) or 0, tonumber(args[3]) or 0))
end
IY.cmds["pulsetp"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	for i,v in pairs(players)do
		if Players[v].Character ~= nil then
			local startPos = getRoot(speaker.Character).CFrame
			local seconds = args[2] or 1
			if speaker.Character:FindFirstChildOfClass('Humanoid') and speaker.Character:FindFirstChildOfClass('Humanoid').SeatPart then
				speaker.Character:FindFirstChildOfClass('Humanoid').Sit = false
				wait(.1)
			end
			getRoot(speaker.Character).CFrame = getRoot(Players[v].Character).CFrame + Vector3.new(3,1,0)
			wait(seconds)
			getRoot(speaker.Character).CFrame = startPos
		end
	end
	execCmd('breakvelocity')
end
IY.cmds["reanim"] = function(args, speaker)
	speaker.Character.Animate.Disabled = false
end
IY.cmds["rec"] = function(args, speaker)
	return COREGUI:ToggleRecording()
end
IY.cmds["refresh"] = function(args, speaker)
	refresh(speaker)
end
IY.cmds["refreshanimations"] = function(args, speaker)
	local Char = speaker.Character or speaker.CharacterAdded:Wait()
	local Human = Char and Char:WaitForChild('Humanoid', 15)
	local Animate = Char and Char:WaitForChild('Animate', 15)
	if not Human or not Animate then
		return notify('Refresh Animations', 'Failed to get Animate/Humanoid')
	end
	Animate.Disabled = true
	for _, v in ipairs(Human:GetPlayingAnimationTracks()) do
		v:Stop()
	end
	Animate.Disabled = false
end
IY.cmds["removeads"] = function(args, speaker)
	while wait() do
		pcall(function()
			for i, v in pairs(workspace:GetDescendants()) do
				if v:IsA("PackageLink") then
					if v.Parent:FindFirstChild("ADpart") then
						v.Parent:Destroy()
					end
					if v.Parent:FindFirstChild("AdGuiAdornee") then
						v.Parent.Parent:Destroy()
					end
				end
			end
		end)
	end
end
IY.cmds["removeterrain"] = function(args, speaker)
	workspace:FindFirstChildOfClass('Terrain'):Clear()
end
IY.cmds["render"] = function(args, speaker)
	RunService:Set3dRenderingEnabled(true)
end
IY.cmds["replaceroot"] = function(args, speaker)
	if speaker.Character ~= nil and getRoot(speaker.Character) then
		local Char = speaker.Character
		local OldParent = Char.Parent
		local HRP = Char and getRoot(Char)
		local OldPos = HRP.CFrame
		Char.Parent = game
		local HRP1 = HRP:Clone()
		HRP1.Parent = Char
		HRP = HRP:Destroy()
		HRP1.CFrame = OldPos
		Char.Parent = OldParent
	end
end
IY.cmds["reset"] = function(args, speaker)
	local humanoid = speaker.Character and speaker.Character:FindFirstChildWhichIsA("Humanoid")
	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Dead)
	else
		speaker.Character:BreakJoints()
	end
end
IY.cmds["respawn"] = function(args, speaker)
	respawn(speaker)
end
IY.cmds["scare"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	local oldpos = nil

	for _, v in pairs(players) do
		local root = speaker.Character and getRoot(speaker.Character)
		local target = Players[v]
		local targetRoot = target and target.Character and getRoot(target.Character)

		if root and targetRoot and target ~= speaker then
			oldpos = root.CFrame
			root.CFrame = targetRoot.CFrame + targetRoot.CFrame.lookVector * 2
			root.CFrame = CFrame.new(root.Position, targetRoot.Position)
			task.wait(0.5)
			root.CFrame = oldpos
		end
	end
end
IY.cmds["screenshot"] = function(args, speaker)
	return COREGUI:TakeScreenshot()
end
IY.cmds["showprompts"] = function(args, speaker)
	COREGUI.PurchasePromptApp.Enabled = true
end
IY.cmds["sit"] = function(args, speaker)
	speaker.Character:FindFirstChildWhichIsA("Humanoid").Sit = true
end
IY.cmds["sitwalk"] = function(args, speaker)
	local anims = speaker.Character.Animate
	local sit = anims.sit:FindFirstChildWhichIsA("Animation").AnimationId
	anims.idle:FindFirstChildWhichIsA("Animation").AnimationId = sit
	anims.walk:FindFirstChildWhichIsA("Animation").AnimationId = sit
	anims.run:FindFirstChildWhichIsA("Animation").AnimationId = sit
	anims.jump:FindFirstChildWhichIsA("Animation").AnimationId = sit
	speaker.Character:FindFirstChildWhichIsA("Humanoid").HipHeight = not r15(speaker) and -1.5 or 0.5
end
IY.cmds["stopanimations"] = function(args, speaker)
	local Char = speaker.Character
	local Hum = Char:FindFirstChildOfClass("Humanoid") or Char:FindFirstChildOfClass("AnimationController")

	for i,v in next, Hum:GetPlayingAnimationTracks() do
		v:Stop()
	end
end
IY.cmds["strengthen"] = function(args, speaker)
	for _, child in pairs(speaker.Character:GetDescendants()) do
		if child.ClassName == "Part" then
			if args[1] then
				child.CustomPhysicalProperties = PhysicalProperties.new(args[1], 0.3, 0.5)
			else
				child.CustomPhysicalProperties = PhysicalProperties.new(100, 0.3, 0.5)
			end
		end
	end
end
IY.cmds["stun"] = function(args, speaker)
	speaker.Character:FindFirstChildOfClass('Humanoid').PlatformStand = true
end
IY.cmds["thaw"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	if players ~= nil then
		for i,v in pairs(players) do
			task.spawn(function()
				for i, x in next, Players[v].Character:GetDescendants() do
					if x.Name ~= floatName and x:IsA("BasePart") and x.Anchored then
						x.Anchored = false
					end
				end
			end)
		end
	end
end
IY.cmds["thirdp"] = function(args, speaker)
	speaker.CameraMode = "Classic"
end
IY.cmds["thru"] = function(args, speaker)
    local root = getRoot(speaker.Character)
    local num = tonumber(args[1]) or 5
    local pos = root.CFrame.Position + (root.CFrame.LookVector * num)
    root.CFrame = CFrame.new(pos, pos + root.CFrame.LookVector)
end
IY.cmds["togglefs"] = function(args, speaker)
	return GuiService:ToggleFullscreen()
end
IY.cmds["tpposition"] = function(args, speaker)
	if #args < 3 then return end
	local tpX,tpY,tpZ = tonumber((args[1]:gsub(",", ""))),tonumber((args[2]:gsub(",", ""))),tonumber((args[3]:gsub(",", "")))
	local char = speaker.Character
	if char and getRoot(char) then
		getRoot(char).CFrame = CFrame.new(tpX,tpY,tpZ)
	end
end
IY.cmds["trip"] = function(args, speaker)
	local humanoid = speaker.Character and speaker.Character:FindFirstChildWhichIsA("Humanoid")
	local root = speaker.Character and getRoot(speaker.Character)
	if humanoid and root then
		humanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
		root.Velocity = root.CFrame.LookVector * 30
	end
end
IY.cmds["tweengoto"] = function(args, speaker)
    local character = speaker and speaker.Character
    local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")

    local oldState = humanoid and humanoid:GetStateEnabled(Enum.HumanoidStateType.Seated)
    if humanoid then humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false) end

    local players = getPlayer(args[1], speaker)
    for _, v in pairs(players) do
        if Players[v].Character ~= nil then
            if humanoid and humanoid.SeatPart then
                humanoid.Sit = false
                task.wait(0.1)
            end
            TweenService:Create(getRoot(speaker.Character), TweenInfo.new(tweenSpeed, Enum.EasingStyle.Linear), {
                CFrame = getRoot(Players[v].Character):GetPivot() + Vector3.new(3, 1, 0)
            }):Play()
        end
    end
    execCmd("breakvelocity")

    if type(oldState) == "boolean" then
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, oldState)
    end
end
IY.cmds["tweengotocamera"] = function(args, speaker)
	TweenService:Create(getRoot(speaker.Character), TweenInfo.new(tweenSpeed, Enum.EasingStyle.Linear), {CFrame = workspace.Camera.CFrame}):Play()
end
IY.cmds["tweengotomodel"] = function(args, speaker)
	for i,v in pairs(workspace:GetDescendants()) do
		if v.Name:lower() == getstring(1, args):lower() and v:IsA("Model") then
			if speaker.Character:FindFirstChildOfClass('Humanoid') and speaker.Character:FindFirstChildOfClass('Humanoid').SeatPart then
				speaker.Character:FindFirstChildOfClass('Humanoid').Sit = false
				wait(.1)
			end
			wait(gotopartDelay)
			TweenService:Create(getRoot(speaker.Character), TweenInfo.new(tweenSpeed, Enum.EasingStyle.Linear), {CFrame = v:GetModelCFrame()}):Play()
		end
	end
end
IY.cmds["tweengotopart"] = function(args, speaker)
	for i,v in pairs(workspace:GetDescendants()) do
		if v.Name:lower() == getstring(1, args):lower() and v:IsA("BasePart") then
			if speaker.Character:FindFirstChildOfClass('Humanoid') and speaker.Character:FindFirstChildOfClass('Humanoid').SeatPart then
				speaker.Character:FindFirstChildOfClass('Humanoid').Sit = false
				wait(.1)
			end
			wait(gotopartDelay)
			TweenService:Create(getRoot(speaker.Character), TweenInfo.new(tweenSpeed, Enum.EasingStyle.Linear), {CFrame = v.CFrame}):Play()
		end
	end
end
IY.cmds["tweengotopartclass"] = function(args, speaker)
	for i,v in pairs(workspace:GetDescendants()) do
		if v.ClassName:lower() == getstring(1, args):lower() and v:IsA("BasePart") then
			if speaker.Character:FindFirstChildOfClass('Humanoid') and speaker.Character:FindFirstChildOfClass('Humanoid').SeatPart then
				speaker.Character:FindFirstChildOfClass('Humanoid').Sit = false
				wait(.1)
			end
			wait(gotopartDelay)
			TweenService:Create(getRoot(speaker.Character), TweenInfo.new(tweenSpeed, Enum.EasingStyle.Linear), {CFrame = v.CFrame}):Play()
		end
	end
end
IY.cmds["tweenspeed"] = function(args, speaker)
	local newSpeed = args[1] or 1
	if tonumber(newSpeed) then
		tweenSpeed = tonumber(newSpeed)
	end
end
IY.cmds["tweentpposition"] = function(args, speaker)
	if #args < 3 then return end
	local tpX,tpY,tpZ = tonumber((args[1]:gsub(",", ""))),tonumber((args[2]:gsub(",", ""))),tonumber((args[3]:gsub(",", "")))
	local char = speaker.Character
	if char and getRoot(char) then
		TweenService:Create(getRoot(speaker.Character), TweenInfo.new(tweenSpeed, Enum.EasingStyle.Linear), {CFrame = CFrame.new(tpX,tpY,tpZ)}):Play()
	end
end
IY.cmds["unanchor"] = function(args, speaker)
    getRoot(speaker.Character).Anchored = false
end
IY.cmds["unctrllock"] = function(args, speaker)
	local mouseLockController = speaker.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("CameraModule"):WaitForChild("MouseLockController")
	local boundKeys = mouseLockController:FindFirstChild("BoundKeys")

	if boundKeys then
		boundKeys.Value = "LeftShift"
	else
		boundKeys = Instance.new("StringValue")
		boundKeys.Name = "BoundKeys"
		boundKeys.Value = "LeftShift"
		boundKeys.Parent = mouseLockController
	end
end
IY.cmds["unequiptools"] = function(args, speaker)
	speaker.Character:FindFirstChildOfClass('Humanoid'):UnequipTools()
end
IY.cmds["unflyfling"] = function(args, speaker)
	execCmd("unvehiclefly\\unwalkfling\\breakvelocity")
end
IY.cmds["unfreezeanims"] = function(args, speaker)
	local Humanoid = speaker.Character:FindFirstChildOfClass("Humanoid") or speaker.Character:FindFirstChildOfClass("AnimationController")
	local ActiveTracks = Humanoid:GetPlayingAnimationTracks()
	for _, v in pairs(ActiveTracks) do
		v:AdjustSpeed(1)
	end
end
IY.cmds["unfriend"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	for i,v in pairs(players)do
		speaker:RevokeFriendship(Players[v])
	end
end
IY.cmds["unglobalshadows"] = function(args, speaker)
	Lighting.GlobalShadows = false
end
IY.cmds["unhitboxes"] = function(args, speaker)
    settings():GetService("RenderSettings").ShowBoundingBoxes = false
end
IY.cmds["unlight"] = function(args, speaker)
	for i,v in pairs(speaker.Character:GetDescendants()) do
		if v.ClassName == "PointLight" then
			v:Destroy()
		end
	end
end
IY.cmds["unlockws"] = function(args, speaker)
	for i,v in pairs(workspace:GetDescendants()) do
		if v:IsA("BasePart") then
			v.Locked = false
		end
	end
end
IY.cmds["unmuteallvoices"] = function(args, speaker)
	Services.VoiceChatInternal:SubscribePauseAll(false)
end
IY.cmds["unnilchar"] = function(args, speaker)
	if speaker.Character ~= nil then
		speaker.Character.Parent = workspace
	end
end
IY.cmds["unnorotate"] = function(args, speaker)
	speaker.Character:FindFirstChildOfClass('Humanoid').AutoRotate  = true
end
IY.cmds["unnosit"] = function(args, speaker)
	speaker.Character:FindFirstChildWhichIsA("Humanoid"):SetStateEnabled(Enum.HumanoidStateType.Seated, true)
end
IY.cmds["unstun"] = function(args, speaker)
	speaker.Character:FindFirstChildOfClass('Humanoid').PlatformStand = false
end
IY.cmds["unweaken"] = function(args, speaker)
	for _, child in pairs(speaker.Character:GetDescendants()) do
		if child.ClassName == "Part" then
			child.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.5)
		end
	end
end
IY.cmds["usetools"] = function(args, speaker)
	local Backpack = speaker:FindFirstChildOfClass("Backpack")
	local amount = tonumber(args[1]) or 1
	local delay_ = tonumber(args[2]) or false
	for _, v in ipairs(Backpack:GetChildren()) do
		v.Parent = speaker.Character
		task.spawn(function()
			for _ = 1, amount do
				v:Activate()
				if delay_ then
					wait(delay_)
				end
			end
			v.Parent = Backpack
		end)
	end
end
IY.cmds["vehiclegoto"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	for i,v in pairs(players)do
		if Players[v].Character ~= nil then
			local seat = speaker.Character:FindFirstChildOfClass('Humanoid').SeatPart
			local vehicleModel = seat:FindFirstAncestorWhichIsA("Model")
			vehicleModel:MoveTo(getRoot(Players[v].Character).Position)
		end
	end
end
IY.cmds["walktopos"] = function(args, speaker)
	if speaker.Character:FindFirstChildOfClass('Humanoid') and speaker.Character:FindFirstChildOfClass('Humanoid').SeatPart then
		speaker.Character:FindFirstChildOfClass('Humanoid').Sit = false
		wait(.1)
	end
	speaker.Character:FindFirstChildOfClass('Humanoid').WalkToPoint = Vector3.new(args[1],args[2],args[3])
end
IY.cmds["wallwalk"] = function(args, speaker)
	loadstring(game:HttpGet("https://raw.githubusercontent.com/infyiff/backup/main/wallwalker.lua"))()
end
IY.cmds["weaken"] = function(args, speaker)
	for _, child in pairs(speaker.Character:GetDescendants()) do
		if child.ClassName == "Part" then
			if args[1] then
				child.CustomPhysicalProperties = PhysicalProperties.new(-args[1], 0.3, 0.5)
			else
				child.CustomPhysicalProperties = PhysicalProperties.new(0, 0.3, 0.5)
			end
		end
	end
end
IY.cmds["whisper"] = function(args, speaker)
	local players = getPlayer(args[1], speaker)
	for i,v in pairs(players)do
		task.spawn(function()
			local plrName = Players[v].Name
			local pmstring = getstring(2, args)
			chatMessage("/w "..plrName.." "..pmstring)
		end)
	end
end


-- Imported commands whose FIRST argument is a player. Detected from the
-- source (bodies calling getPlayer(args[1], ...)), so the player picker
-- fires for them exactly as it does for the native commands.
IY.playerCmds = {
    "age", "aid", "appearanceid", "caid", "chatage", "chatjoindate",
    "cjd", "copyanimationid", "copyanimid", "copyappearanceid", "copyemoteid", "copypos",
    "copyposition", "copytools", "examine", "fr", "freeze", "friend",
    "getpos", "getposition", "headsize", "hitbox", "inspect", "jd",
    "joindate", "nolocate", "notifypos", "notifyposition", "pm", "ptp",
    "pulsetp", "scare", "spook", "tgoto", "thaw", "tto",
    "tweengoto", "tweento", "unfr", "unfreeze", "unfriend", "unlocate",
    "vehiclegoto", "vehicletp", "vgoto", "vtp", "whisper",
}
IY.needsPlayer = {}
for _, n in ipairs(IY.playerCmds) do IY.needsPlayer[n] = true end


-- Opposite command, where one exists. Derived by matching un*/no*/stop*
-- against the imported set, plus a few IY calls its opposite something
-- else entirely (freeze/thaw). Drives the undo button on the toast.
IY.opposite = {
    ["anchor"] = "unanchor",
    ["ctrllock"] = "unctrllock",
    ["equiptools"] = "unequiptools",
    ["freeze"] = "thaw",
    ["freezeanims"] = "unfreezeanims",
    ["friend"] = "unfriend",
    ["globalshadows"] = "unglobalshadows",
    ["hitboxes"] = "unhitboxes",
    ["light"] = "unlight",
    ["lockws"] = "unlockws",
    ["muteallvoices"] = "unmuteallvoices",
    ["nilchar"] = "unnilchar",
    ["noprompts"] = "showprompts",
    ["norender"] = "render",
    ["nosit"] = "sit",
    ["render"] = "norender",
    ["sit"] = "nosit",
    ["strengthen"] = "unweaken",
    ["stun"] = "unstun",
    ["unanchor"] = "anchor",
    ["unctrllock"] = "ctrllock",
    ["unequiptools"] = "equiptools",
    ["unfreezeanims"] = "freezeanims",
    ["unfriend"] = "friend",
    ["unglobalshadows"] = "globalshadows",
    ["unhitboxes"] = "hitboxes",
    ["unlight"] = "light",
    ["unlockws"] = "lockws",
    ["unmuteallvoices"] = "muteallvoices",
    ["unnilchar"] = "nilchar",
    ["unnorotate"] = "norotate",
    ["unnosit"] = "nosit",
    ["unstun"] = "stun",
    ["unweaken"] = "weaken",
    ["weaken"] = "strengthen",
}

-- alias -> canonical, for IY.run
IY.alias["adblock"] = "removeads"
IY.alias["aid"] = "appearanceid"
IY.alias["autorotate"] = "unnorotate"
IY.alias["boostfps"] = "antilag"
IY.alias["bpc"] = "bringpartclass"
IY.alias["caid"] = "copyappearanceid"
IY.alias["cdc"] = "chardeleteclass"
IY.alias["chardeleteclassname"] = "chardeleteclass"
IY.alias["charremoveclass"] = "chardeleteclass"
IY.alias["charremoveclassname"] = "chardeleteclass"
IY.alias["cjd"] = "chatjoindate"
IY.alias["cleanhats"] = "clearhats"
IY.alias["clearchar"] = "clearcharappearance"
IY.alias["clrchar"] = "clearcharappearance"
IY.alias["clrtools"] = "notools"
IY.alias["copyanimid"] = "copyanimationid"
IY.alias["copyemoteid"] = "copyanimationid"
IY.alias["copypos"] = "copyposition"
IY.alias["dc"] = "deleteclass"
IY.alias["deleteclassname"] = "deleteclass"
IY.alias["deleteinvisibleparts"] = "deleteinvisparts"
IY.alias["deletetools"] = "notools"
IY.alias["dh"] = "destroyheight"
IY.alias["dip"] = "deleteinvisparts"
IY.alias["drophat"] = "drophats"
IY.alias["droptool"] = "droptools"
IY.alias["dst"] = "deleteselectedtool"
IY.alias["dtools"] = "notools"
IY.alias["dv"] = "deletevelocity"
IY.alias["examine"] = "inspect"
IY.alias["fb"] = "fullbright"
IY.alias["fr"] = "freeze"
IY.alias["fullbrightness"] = "fullbright"
IY.alias["getpos"] = "getposition"
IY.alias["gotocam"] = "gotocamera"
IY.alias["gpc"] = "gotopartclass"
IY.alias["gshadows"] = "globalshadows"
IY.alias["hheight"] = "hipheight"
IY.alias["jd"] = "joindate"
IY.alias["jp"] = "jpower"
IY.alias["jumppower"] = "jpower"
IY.alias["laydown"] = "lay"
IY.alias["lockworkspace"] = "lockws"
IY.alias["loopanim"] = "loopanimation"
IY.alias["lowgraphics"] = "antilag"
IY.alias["ms"] = "mousesensitivity"
IY.alias["msa"] = "maxslopeangle"
IY.alias["muteallvcs"] = "muteallvoices"
IY.alias["noautorotate"] = "norotate"
IY.alias["nobillboardgui"] = "nobgui"
IY.alias["nocdlimits"] = "noclickdetectorlimits"
IY.alias["noglobalshadows"] = "unglobalshadows"
IY.alias["nogshadows"] = "unglobalshadows"
IY.alias["nohats"] = "deletehats"
IY.alias["nolight"] = "unlight"
IY.alias["noname"] = "nobgui"
IY.alias["nonilchar"] = "unnilchar"
IY.alias["noplatformstand"] = "unstun"
IY.alias["nopplimits"] = "noproximitypromptlimits"
IY.alias["nopurchaseprompts"] = "noprompts"
IY.alias["nostun"] = "unstun"
IY.alias["noterrain"] = "removeterrain"
IY.alias["notifypos"] = "getposition"
IY.alias["notifyposition"] = "getposition"
IY.alias["ping"] = "notifyping"
IY.alias["platformstand"] = "stun"
IY.alias["pm"] = "whisper"
IY.alias["ptp"] = "pulsetp"
IY.alias["rarms"] = "noarms"
IY.alias["re"] = "refresh"
IY.alias["record"] = "rec"
IY.alias["refreshanim"] = "refreshanimations"
IY.alias["refreshanimation"] = "refreshanimations"
IY.alias["refreshanims"] = "refreshanimations"
IY.alias["remove"] = "delete"
IY.alias["removecdlimits"] = "noclickdetectorlimits"
IY.alias["removeclass"] = "deleteclass"
IY.alias["removeclassname"] = "deleteclass"
IY.alias["removeface"] = "noface"
IY.alias["removeforces"] = "deletevelocity"
IY.alias["removepplimits"] = "noproximitypromptlimits"
IY.alias["removeroot"] = "noroot"
IY.alias["removetools"] = "notools"
IY.alias["removevelocity"] = "deletevelocity"
IY.alias["replacerootpart"] = "replaceroot"
IY.alias["rhats"] = "deletehats"
IY.alias["rlegs"] = "nolegs"
IY.alias["rlimbs"] = "nolimbs"
IY.alias["rohg"] = "nobgui"
IY.alias["rroot"] = "noroot"
IY.alias["rterrain"] = "removeterrain"
IY.alias["rtools"] = "notools"
IY.alias["say"] = "chat"
IY.alias["scrnshot"] = "screenshot"
IY.alias["showpurchaseprompts"] = "showprompts"
IY.alias["spook"] = "scare"
IY.alias["stopanim"] = "stopanimations"
IY.alias["stopanims"] = "stopanimations"
IY.alias["tgoto"] = "tweengoto"
IY.alias["tgotocam"] = "tweengotocamera"
IY.alias["tgotomodel"] = "tweengotomodel"
IY.alias["tgotopart"] = "tweengotopart"
IY.alias["tgpc"] = "tweengotopartclass"
IY.alias["tocam"] = "gotocamera"
IY.alias["togglefullscreen"] = "togglefs"
IY.alias["tomodel"] = "gotomodel"
IY.alias["topart"] = "gotopart"
IY.alias["tppos"] = "tpposition"
IY.alias["tspeed"] = "tweenspeed"
IY.alias["tto"] = "tweengoto"
IY.alias["ttocam"] = "tweengotocamera"
IY.alias["ttomodel"] = "tweengotomodel"
IY.alias["ttopart"] = "tweengotopart"
IY.alias["ttppos"] = "tweentpposition"
IY.alias["tweengotocam"] = "tweengotocamera"
IY.alias["tweento"] = "tweengoto"
IY.alias["unbgui"] = "nobgui"
IY.alias["unbillboardgui"] = "nobgui"
IY.alias["unfr"] = "thaw"
IY.alias["unfreeze"] = "thaw"
IY.alias["ungshadows"] = "unglobalshadows"
IY.alias["unlocate"] = "nolocate"
IY.alias["unlockworkspace"] = "unlockws"
IY.alias["unmuteallvcs"] = "unmuteallvoices"
IY.alias["unplatformstand"] = "unstun"
IY.alias["unstrengthen"] = "unweaken"
IY.alias["vehicletp"] = "vehiclegoto"
IY.alias["vgoto"] = "vehiclegoto"
IY.alias["vtp"] = "vehiclegoto"
IY.alias["walkonwalls"] = "wallwalk"
IY.alias["walktoposition"] = "walktopos"

-- one-line descriptions, lifted from IY's own command list
IY.desc["age"] = "Tells you the age of a player"
IY.desc["ambient"] = "Changes ambient"
IY.desc["anchor"] = "Anchors your characters RootPart"
IY.desc["animspeed"] = "Changes the speed of your current animation"
IY.desc["antilag"] = "Lowers game quality to boost FPS"
IY.desc["appearanceid"] = "Notifies a players appearance ID"
IY.desc["blockhats"] = "Turns your hats into blocks"
IY.desc["blockhead"] = "Turns your head into a block"
IY.desc["blocktool"] = "Turns the currently selected tool into a block"
IY.desc["breakvelocity"] = "Sets your characters velocity to 0"
IY.desc["brightness"] = "Changes the brightness lighting property"
IY.desc["bringpart"] = "Moves a part or multiple parts to your character"
IY.desc["bringpartclass"] = "Moves a part or multiple parts to your character based on classname"
IY.desc["camdistance"] = "Changes camera distance from your player"
IY.desc["chardeleteclass"] = "Removes any part with a certain classname from your character"
IY.desc["chat"] = "Makes you chat a string (possible mute bypass)"
IY.desc["chatage"] = "Chats the age of a player"
IY.desc["chatjoindate"] = "Chats the date the player joined Roblox"
IY.desc["clearcharappearance"] = "Removes all accessory, shirt, pants, charactermesh, and bodycolors"
IY.desc["clearhats"] = "Clears hats in the workspace"
IY.desc["clickdelete"] = "Go to Settings > Keybinds > Add for click delete"
IY.desc["copyanimationid"] = "Copies your animation id or someone elses to your clipboard"
IY.desc["copyappearanceid"] = "Copies a players appearance ID to your clipboard"
IY.desc["copyposition"] = "Copies the coordinates of a character to your clipboard"
IY.desc["copytools"] = "Copies a players tools"
IY.desc["creeper"] = "Makes you look like a creeper"
IY.desc["ctrllock"] = "Binds Shiftlock to LeftControl"
IY.desc["day"] = "Changes the time to day for the client"
IY.desc["delete"] = "Removes any part with a certain name from the workspace (DOES NOT REPLICATE)"
IY.desc["deleteclass"] = "Removes any part with a certain classname from the workspace (DOES NOT REPLICATE)"
IY.desc["deletehats"] = "Deletes your hats"
IY.desc["deleteinvisparts"] = "Deletes invisible parts"
IY.desc["deleteselectedtool"] = "Removes any currently selected tools"
IY.desc["deletevelocity"] = "Removes any velocity / force instances in your character"
IY.desc["destroyheight"] = "Sets FallenPartsDestroyHeight"
IY.desc["disablestate"] = "Disables a humanoid state type"
IY.desc["drophats"] = "Drops your hats"
IY.desc["droppabletools"] = "Makes your tools droppable"
IY.desc["droptools"] = "Drops your tools"
IY.desc["enablestate"] = "Enables a humanoid state type"
IY.desc["equiptools"] = "Equips every tool in your inventory at once"
IY.desc["firstp"] = "Forces camera to go into first person"
IY.desc["freeze"] = "Freezes a player"
IY.desc["freezeanims"] = "Freezes your animations / pauses your animations - Does not work on default animations"
IY.desc["friend"] = "Sends a friend request to certain players"
IY.desc["fullbright"] = "Makes the map brighter / more visible"
IY.desc["getposition"] = "Infinite Yield command"
IY.desc["globalshadows"] = "Enables global shadows"
IY.desc["gotocamera"] = "Teleports you to the location of your camera"
IY.desc["gotomodel"] = "Moves your character to a model or multiple models"
IY.desc["gotopart"] = "Moves your character to a part or multiple parts"
IY.desc["gotopartclass"] = "Moves your character to a part or multiple parts based on classname"
IY.desc["gotopartdelay"] = "Adjusts how quickly you teleport to each part (default is 0.1)"
IY.desc["grippos"] = "Changes your current tools grip position"
IY.desc["headsize"] = "Expands the head size for players Head (default is 1)"
IY.desc["headthrow"] = "Simply makes you throw your head"
IY.desc["hipheight"] = "Adjusts hip height"
IY.desc["hitbox"] = "Expands the hitbox for players HumanoidRootPart (default is 1)"
IY.desc["hitboxes"] = "Shows all rendered bounding boxes"
IY.desc["inspect"] = "Opens InspectMenu for a certain player"
IY.desc["joindate"] = "Tells you the date the player joined Roblox"
IY.desc["jpower"] = "Change a players jump height (default is 50)"
IY.desc["lay"] = "Makes your character lay down"
IY.desc["light"] = "Gives your player dynamic light"
IY.desc["lockws"] = "Locks the whole workspace"
IY.desc["loopanimation"] = "Loops your current animation"
IY.desc["maxslopeangle"] = "Adjusts MaxSlopeAngle"
IY.desc["maxzoom"] = "Maximum camera zoom"
IY.desc["minzoom"] = "Minimum camera zoom"
IY.desc["mousesensitivity"] = "Sets your mouse sensitivity (affects first person and right click drag) (default is 1)"
IY.desc["muteallvoices"] = "Mutes voice chat for all players"
IY.desc["naked"] = "Removes your clothing"
IY.desc["night"] = "Changes the time to night for the client"
IY.desc["nilchar"] = "Sets your characters parent to nil"
IY.desc["noanim"] = "Disables your animations"
IY.desc["noarms"] = "Removes your arms"
IY.desc["nobgui"] = "Removes billboard and surface GUIs from your players (i.e. name GUIs at cafes)"
IY.desc["noclickdetectorlimits"] = "Sets all click detectors MaxActivationDistance to math.huge"
IY.desc["noface"] = "Removes your face"
IY.desc["nofog"] = "Removes fog"
IY.desc["nolegs"] = "Removes your legs"
IY.desc["nolimbs"] = "Removes your limbs"
IY.desc["nolocate"] = "Removes locate"
IY.desc["noprompts"] = "Prevents the game from showing you purchase/premium prompts"
IY.desc["noproximitypromptlimits"] = "Sets all proximity prompts MaxActivationDistance to math.huge"
IY.desc["norender"] = "Disable 3d Rendering to decrease the amount of CPU the client uses"
IY.desc["noroot"] = "Removes your characters HumanoidRootPart"
IY.desc["norotate"] = "Disables AutoRotate"
IY.desc["nosit"] = "Prevents your character from sitting"
IY.desc["notifyping"] = "Notify yourself your ping"
IY.desc["notools"] = "Removes tools from character and backpack"
IY.desc["offset"] = "Offsets you by certain coordinates"
IY.desc["pulsetp"] = "Teleports you to a player for a specified amount of time"
IY.desc["reanim"] = "Restores your animations"
IY.desc["rec"] = "Starts Roblox recorder"
IY.desc["refresh"] = "Respawns and brings you back to the same position"
IY.desc["refreshanimations"] = "Refreshes animations"
IY.desc["removeads"] = "Automatically removes ad billboards"
IY.desc["removeterrain"] = "Removes all terrain"
IY.desc["render"] = "Enable 3d Rendering"
IY.desc["replaceroot"] = "Replaces your characters HumanoidRootPart"
IY.desc["reset"] = "Resets your character normally"
IY.desc["respawn"] = "Respawns you"
IY.desc["scare"] = "Teleports in front of a player for half a second"
IY.desc["screenshot"] = "Takes a screenshot"
IY.desc["showprompts"] = "Allows the game to show purchase/premium prompts again"
IY.desc["sit"] = "Makes your character sit"
IY.desc["sitwalk"] = "Makes your character sit while still being able to walk"
IY.desc["stopanimations"] = "Stops running animations"
IY.desc["strengthen"] = "Makes your character more dense (CustomPhysicalProperties)"
IY.desc["stun"] = "Enables PlatformStand"
IY.desc["thaw"] = "Unfreezes a player"
IY.desc["thirdp"] = "Allows camera to go into third person"
IY.desc["thru"] = "Teleports you [num] studs ahead of where your character is facing"
IY.desc["togglefs"] = "Toggles fullscreen"
IY.desc["tpposition"] = "Teleports you to certain coordinates"
IY.desc["trip"] = "Makes your character fall over"
IY.desc["tweengoto"] = "Tween to a player (bypasses some anti cheats)"
IY.desc["tweengotocamera"] = "Tweens you to the location of your camera"
IY.desc["tweengotomodel"] = "Tweens your character to a model or multiple models"
IY.desc["tweengotopart"] = "Tweens your character to a part or multiple parts"
IY.desc["tweengotopartclass"] = "Tweens your character to a part or multiple parts based on classname"
IY.desc["tweenspeed"] = "Sets how fast all tween commands go (default is 1)"
IY.desc["tweentpposition"] = "Tween to coordinates (bypasses some anti cheats)"
IY.desc["unanchor"] = "Unanchors your characters RootPart"
IY.desc["unctrllock"] = "Re-binds Shiftlock to LeftShift"
IY.desc["unequiptools"] = "Unequips every tool you are currently holding at once"
IY.desc["unflyfling"] = "Disables the flyfling command"
IY.desc["unfreezeanims"] = "Unfreezes your animations / plays your animations"
IY.desc["unfriend"] = "Unfriends certain players"
IY.desc["unglobalshadows"] = "Disables global shadows"
IY.desc["unhitboxes"] = "Stops showing all rendered bounding boxes"
IY.desc["unlight"] = "Removes dynamic light from your player"
IY.desc["unlockws"] = "Unlocks the whole workspace"
IY.desc["unmuteallvoices"] = "Unmutes voice chat for all players"
IY.desc["unnilchar"] = "Sets your characters parent to workspace"
IY.desc["unnorotate"] = "Enables AutoRotate"
IY.desc["unnosit"] = "Disables nosit"
IY.desc["unstun"] = "Disables PlatformStand"
IY.desc["unweaken"] = "Sets your characters CustomPhysicalProperties to default"
IY.desc["usetools"] = "Activates all tools in your backpack at the same time"
IY.desc["vehiclegoto"] = "Go to a player while in a vehicle"
IY.desc["walktopos"] = "Makes you walk to a coordinate"
IY.desc["wallwalk"] = "Walk on walls"
IY.desc["weaken"] = "Makes your character less dense"
IY.desc["whisper"] = "Makes you whisper a string to someone (possible mute bypass)"


local prefix = "!"

-- ── Config persistence ──────────────────────────────────────────────────
-- Must live BELOW `local prefix`: defined above it, the `prefix` in these
-- bodies would bind to a nil global and a saved prefix would never load.
function UI.saveConfig()
    pcall(function()
        if typeof(writefile) ~= "function" then return end
        writefile(WS.path("state", "config.txt"), HttpService:JSONEncode({
            theme = UI.themeId, opacity = UI.OPACITY, prefix = prefix,
            key = (_G.CmdBarKeybind and _G.CmdBarKeybind.Name) or "T",
            persist = Persist and Persist.enabled,
            guideSeen = UI.guideSeen and true or false,
            -- Saved scripts are the one thing here worth surviving a rejoin.
            hubFavs = (ScriptHub and ScriptHub.favs) or nil,
            -- What to offer running again next time you join a game.
            hubRecent = ScriptHub and ScriptHub.packHistory() or nil,
            hubAskResume = UI.askResume ~= false,
            usage = Usage and Usage.save() or nil,
            qjLast = QuickJoin and QuickJoin.lastKey or nil,
            hopPrev = ServerHop and ServerHop.prevBy or nil,
            lastPos = UI.savedPos,
            leftOff = UI.leftOff,
            qjLearned = (QuickJoin and #QuickJoin.learned > 0)
                        and QuickJoin.learned or nil,
        }))
    end)
end

function UI.loadConfig()
    pcall(function()
        local p = WS.path("state", "config.txt")
        if not (typeof(isfile) == "function" and isfile(p)) then return end
        local raw = readfile(p)
        local d = HttpService:JSONDecode(raw)
        if type(d) ~= "table" then return end
        if d.theme and UI.THEMES[d.theme] then UI.setTheme(d.theme) end
        if tonumber(d.opacity) then UI.OPACITY = math.clamp(tonumber(d.opacity), 0.25, 1) end
        if type(d.prefix) == "string" and #d.prefix == 1 then prefix = d.prefix end
        if type(d.guideSeen) == "boolean" then UI.guideSeen = d.guideSeen end
        -- Config is a file on disk anyone can edit, so every saved script is
        -- checked before it reaches a row that would try to run it.
        if type(d.hubFavs) == "table" and ScriptHub then
            local clean = {}
            for _, f in ipairs(d.hubFavs) do
                if type(f) == "table" and type(f.title) == "string"
                   and type(f.source) == "string" and f.source ~= "" then
                    clean[#clean + 1] = {
                        title = f.title, source = f.source,
                        gameName = tostring(f.gameName or "Universal"),
                        placeId = tonumber(f.placeId) or 0,
                        universal = f.universal ~= false,
                        key = f.key == true, patched = f.patched == true,
                        verified = f.verified == true,
                    }
                end
            end
            ScriptHub.favs = clean
        end
        if type(d.hubAskResume) == "boolean" then UI.askResume = d.hubAskResume end
        if Usage then Usage.load(d.usage) end
        -- Same place-tagging rule as the manual bookmark: coordinates from
        -- another game are three numbers that drop you inside a wall.
        if type(d.leftOff) == "table" and tonumber(d.leftOff.x)
           and tonumber(d.leftOff.place) == game.PlaceId then
            UI.leftOff = { place = tonumber(d.leftOff.place),
                           x = tonumber(d.leftOff.x), y = tonumber(d.leftOff.y),
                           z = tonumber(d.leftOff.z) }
        end
        if type(d.lastPos) == "table" and tonumber(d.lastPos.x)
           and tonumber(d.lastPos.place) == game.PlaceId then
            UI.savedPos = { place = tonumber(d.lastPos.place),
                            x = tonumber(d.lastPos.x), y = tonumber(d.lastPos.y),
                            z = tonumber(d.lastPos.z) }
            -- Restored into the session variable too, so !topos works on a
            -- fresh join without going through the prompt.
            savedPosition = CFrame.new(UI.savedPos.x, UI.savedPos.y, UI.savedPos.z)
        end
        if type(d.qjLast) == "string" then QuickJoin.lastKey = d.qjLast end
        if type(d.hopPrev) == "table" and ServerHop then
            local by = {}
            for place, e in pairs(d.hopPrev) do
                if type(place) == "string" and type(e) == "table"
                   and type(e.job) == "string" and e.job ~= "" then
                    by[place] = { job = e.job, at = tonumber(e.at) or 0 }
                end
            end
            ServerHop.prevBy = by
        end
        -- Learned games are replayed through add(), so they go through the
        -- same collision check as the first time -- the curated table may
        -- have grown since and claimed an alias one of them was using.
        if type(d.qjLearned) == "table" and QuickJoin then
            for _, e in ipairs(d.qjLearned) do
                if type(e) == "table" and tonumber(e.id) and type(e.name) == "string" then
                    QuickJoin.add(tonumber(e.id), e.name, true)
                end
            end
        end
        -- Same validation as the favourites: this comes off disk and every
        -- entry is a candidate for being executed.
        if type(d.hubRecent) == "table" and ScriptHub then
            local hist = {}
            for place, bucket in pairs(d.hubRecent) do
                if type(place) == "string" and type(bucket) == "table"
                   and type(bucket.items) == "table" then
                    local clean = {}
                    for _, f in ipairs(bucket.items) do
                        if type(f) == "table" and type(f.title) == "string"
                           and type(f.source) == "string" and f.source ~= "" then
                            clean[#clean + 1] = {
                                title = f.title, source = f.source,
                                gameName = tostring(f.gameName or "Universal"),
                                placeId = tonumber(f.placeId) or 0,
                                universal = f.universal ~= false,
                            }
                        end
                    end
                    if #clean > 0 then
                        hist[place] = { at = tonumber(bucket.at) or 0, items = clean }
                    end
                end
            end
            ScriptHub.history = hist
            -- This place's bucket becomes the live list; the rest stay in
            -- the map so another game's history is not lost by playing here.
            local mine = hist[ScriptHub.placeKey()]
            ScriptHub.ran = (mine and mine.items) or {}
        end
        if type(d.persist) == "boolean" and Persist then Persist.enabled = d.persist end
        if type(d.key) == "string" and Enum.KeyCode[d.key] then
            _G.CmdBarKeybind = Enum.KeyCode[d.key]
        end
    end)
end

-- Reusable command processing function
local function processCommand(msg)
    -- Split by space
    local args = string.split(msg, " ")
    -- Check if the first argument has a command prefix
    if #args > 0 and string.sub(args[1], 1, 1) == prefix then
        -- Remove the prefix from the command
        local command = string.sub(args[1], 2):lower()
        -- Process commands
        if command == "fly" then
            local speed = tonumber(args[2]) or 50
            toggleFly(speed)
            Badge.set("fly")
            Notifications:Success("Universal Hub Lite",
                "Fly enabled  \194\183  speed " .. (args[2] and tostring(args[2]) or "50"), 4.5, {
                    { label = "Stop fly", icon = "st_plane.png", style = "light",
                      run = function()
                          if isFlying then toggleFly() end
                          Badge.set("idle")
                      end },
                })

           
        elseif command == "unfly" then
            if isFlying then
                toggleFly()
                Notifications:Success("Universal Hub Lite", "Stopped Flying", 4.5)
                Badge.set("idle")

            else
                Notifications:Error("Universal Hub Lite", "User Is Not Flying", 4.5)
            end

        elseif command == "fov" then
            local camera = workspace.CurrentCamera
            local fovValue = tonumber(args[2]) or 70
        
            if camera and fovValue then
                camera.FieldOfView = math.clamp(fovValue, 1, 120)
                Notifications:Success("Universal Hub Lite", "Fov Set To " .. (args[2] and tostring(args[2]) or "70"), 4.5)
            end
        

        elseif command == "rj" or command == "rejoin" then
            
            Notifications:Success("Universal Hub Lite", "Rejoining Please Wait ...", 4.5)

            task.wait(4.5)
        
        game:GetService("TeleportService"):Teleport(game.PlaceId, game:GetService("Players").LocalPlayer)


        elseif command == "uhub" then
            
            Notifications:Success("Universal Hub Lite", "Executing Universal Hub V3 Please Wait ...", 4.5)
            task.wait(4.5)
            loadstring(game:HttpGet("https://raw.githubusercontent.com/Angxers2/Unihub/main/Unihub%20V3.0.lua",true))()
            
        elseif command == "noclip" then
            setNoClip(true)
            Badge.set("noclip")
            Notifications:Success("Universal Hub Lite", "Noclip active", 4.5, {
                { label = "Turn off", icon = "st_ghost.png", style = "light",
                  run = function() setNoClip(false) Badge.set("idle") end },
            })

        elseif command == "clip" then
            setNoClip(false)
            Badge.set("idle")
            Notifications:Success("Universal Hub Lite", "NoClip Deactivated !", 4.5)

        elseif command == "walkspeed" or command == "ws" then
            local speed = tonumber(args[2]) or 16
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                LocalPlayer.Character.Humanoid.WalkSpeed = speed
                Notifications:Success("Universal Hub Lite", "Walkspeed Set To: " .. (args[2] and tostring(args[2]) or "16"), 4.5)

            end
            
        elseif command == "jump" then
            local height = tonumber(args[2]) or 50
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                LocalPlayer.Character.Humanoid.JumpPower = height
                Notifications:Success("Universal Hub Lite", "JumpPower Set To: " .. (args[2] and tostring(args[2]) or "50"), 4.5)
              end
            
        elseif command == "view" or command == "unview" then
            -- Naming a target while already viewing SWITCHES to them. It used
            -- to stop instead, so the second "view <someone>" of a session
            -- silently did the opposite of what it says and dropped the
            -- button with it.
            local wanted = args[2] and findPlayer(args[2], command) or nil
            if command == "unview" or not args[2] then
                viewPlayer(nil) -- This will disconnect the current view
                Badge.set("idle")
                Notifications:Success("Universal Hub Lite", "Stopped Viewing", 4.5)

            elseif not wanted then
                Notifications:Error("Universal Hub Lite",
                    "No one matched \"" .. tostring(args[2]) .. "\"", 4)

            else
                local target = wanted
                viewPlayer(target)
                Badge.set("view")
                Notifications:Success("Universal Hub Lite", "Viewing " .. target.Name, 4.5, {
                    { label = "Stop viewing", icon = "st_eye.png", style = "light",
                      run = function() viewPlayer(nil) Badge.set("idle") end },
                }, target.Name)

            end
            
        elseif command == "infjump" then
            toggleInfJump()
            Badge.set(isInfJumpEnabled and "infjump" or "idle")
            Notifications:Success("Universal Hub Lite",
                isInfJumpEnabled and "Infinite jump on" or "Infinite jump off", 4.5,
                isInfJumpEnabled and {
                    { label = "Turn off", icon = "st_arrow-up.png", style = "light",
                      run = function() toggleInfJump() Badge.set("idle") end },
                } or nil)

            
        elseif command == "goto" or command == "tp" or command == "to" then
            local target = findPlayer(args[2])
            if target and target.Character and LocalPlayer.Character then
                local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
                local localHRP = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if targetHRP and localHRP then
                    -- Remember where we were so the toast can offer a way back.
                    local backCF = localHRP.CFrame
                    localHRP.CFrame = targetHRP.CFrame * CFrame.new(0, 0, 3) -- 3 studs behind
                    Notifications:Success("Universal Hub Lite",
                        "Teleported to " .. target.Name, 4.5, {
                            { label = "Go back", icon = "st_map-pin.png", style = "light",
                              run = function()
                                  local ch = LocalPlayer.Character
                                  local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                                  if hrp then hrp.CFrame = backCF end
                              end },
                        }, target.Name)

                end
            else
                Notifications:Error("Universal Hub Lite", "Player not found or not loaded !", 4.5)

            end
            
        elseif command == "bypassvc" or command == "bvc" or command == "rvc" then
            Notifications:Success("Universal Hub Lite", "Bypassing Voice Chat Will Take A Moment ...", 4.5)

            local VoiceChatInternal = cloneref and cloneref(game:GetService("VoiceChatInternal")) or game:GetService("VoiceChatInternal")
            local VoiceChatService = cloneref and cloneref(game:GetService("VoiceChatService")) or game:GetService("VoiceChatService")
    
            VoiceChatInternal:Leave()
            wait(0.2)
            VoiceChatService:rejoinVoice()
            wait(0.1)
            VoiceChatService:joinVoice()
            wait(0.3)
            VoiceChatInternal:Leave()
            wait(0.3)
            VoiceChatService:rejoinVoice()
            VoiceChatService:joinVoice()
       
            
        elseif command == "infyield" or command == "ify" then
            Notifications:Success("Universal Hub Lite", "Executing Infinite Yield Please Wait ...", 4.5)
            task.wait(4.5)
            loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
            
        elseif command == "savepos" then
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                savedPosition = LocalPlayer.Character.HumanoidRootPart.CFrame
                -- Kept across a rejoin, but tagged with the place: a
                -- position from another game is not a position, it is three
                -- numbers that will drop you inside a wall.
                local p = savedPosition.Position
                UI.savedPos = { place = game.PlaceId, x = p.X, y = p.Y, z = p.Z }
                UI.saveConfig()
                Notifications:Success("Universal Hub Lite",
                    ("Saved position  \194\183  %d, %d, %d"):format(p.X, p.Y, p.Z), 4.5)

            end
            
        elseif command == "topos" then
            if savedPosition and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                LocalPlayer.Character.HumanoidRootPart.CFrame = savedPosition
                Notifications:Success("Universal Hub Lite", "Teleported To Saved Position " .. tostring(savedPosition), 4.5)
            else
                Notifications:Error("Universal Hub Lite", "No position saved or character not loaded !", 4.5)

            end
            
        elseif command == "clicktp" then
            local key = args[2]
            if key then
                setupClickTeleport(key:upper())
                Notifications:Success("Universal Hub Lite", "ClickTP Activated With Key: " .. key, 4.5)

            else
                Notifications:Error("Universal Hub Lite", "Please specify a key, e.g. !ClickTp K", 4.5)

            end
            
        elseif command == "spin" then
            local speed = tonumber(args[2]) or 10
            toggleSpin(speed)
            Badge.set("spin")
            Notifications:Success("Universal Hub Lite",
                "Spin on  \194\183  speed " .. (args[2] and tostring(args[2]) or "10"), 4.5, {
                    { label = "Stop spin", icon = "st_rotate-cw.png", style = "light",
                      run = function()
                          if isSpinning then toggleSpin() end
                          Badge.set("idle")
                      end },
                })

            
        elseif command == "unspin" then
            if isSpinning then
                toggleSpin()
                Badge.set("idle")
            Notifications:Success("Universal Hub Lite", "Stopped Spinning !", 4.5)
            else
            Notifications:Error("Universal Hub Lite", "Not Currently Spinning !", 4.5)

            end
            
        elseif command == "bang" then
            -- Check if args[2] is a number (changing speed of existing bang)
            if tonumber(args[2]) then
                local newSpeed = tonumber(args[2])
                
                -- If there's an active bang animation, just change its speed
                if _G.BangingActive and _G.BangAnimation then
                    _G.BangAnimation:AdjustSpeed(newSpeed)
                    Notifications:Success("Universal Hub Lite", "Bang speed changed to: " .. tostring(newSpeed), 4.5)
                else
                    Notifications:Error("Universal Hub Lite", "No active banging to change speed!", 4.5)
                end
                return
            end
            
            -- Otherwise, find the target player to bang
            local target = findPlayer(args[2])
            
            if not target then
                return Notifications:Error("Universal Hub Lite", "Error Target Not Found !", 4.5)
            end
            
            -- Get animation speed from args[3] or use default
            local bangSpeed = tonumber(args[3]) or 3
            -- Every other toggle offers its own off switch from the toast;
            -- this one was the odd one out. Routed through processCommand so
            -- the teardown stays in one place rather than being duplicated
            -- here and drifting from unbang.
            Notifications:Success("Universal Hub Lite",
                "Banging: " .. tostring(target) .. " With Speed : " .. tostring(bangSpeed), 5, {
                    { label = "Stop", icon = "st_user-x.png", style = "light",
                      run = function() processCommand(prefix .. "unbang") end },
                }, target.Name)
            
            -- Stop any existing bang animation first
            if _G.BangingActive then
                -- Stop the animation
                if _G.BangAnimation then
                    _G.BangAnimation:Stop(0.5)
                end
                
                -- Disconnect the loop
                if _G.BangLoop then
                    _G.BangLoop:Disconnect()
                end
                
                -- Disconnect the died event
                if _G.BangDied then
                    _G.BangDied:Disconnect()
                end
                
                -- Clean up animation
                if _G.BangAnim then
                    _G.BangAnim:Destroy()
                end
            end
            
            -- Global variables to track state
            _G.BangingActive = true
            
            local Players = game:GetService("Players")
            local RunService = game:GetService("RunService")
            local localPlayer = Players.LocalPlayer
            
            -- Utility functions to get the root part of a character
            local function getRoot(character)
                return character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("UpperTorso")
            end
            
            local humanoid = localPlayer.Character:FindFirstChildWhichIsA("Humanoid")
            if not humanoid then
                return Notifications:Error("Universal Hub Lite", "Humanoid not found!", 4.5)
            end
            
            -- Determine animation based on the character rig type (R6 or R15)
            _G.BangAnim = Instance.new("Animation")
            _G.BangAnim.AnimationId = humanoid.RigType == Enum.HumanoidRigType.R15 and "rbxassetid://5918726674" or "rbxassetid://148840371"
            
            -- Load and play the bang animation
            _G.BangAnimation = humanoid:LoadAnimation(_G.BangAnim)
            _G.BangAnimation:Play(0.1, 1, 1)
            _G.BangAnimation:AdjustSpeed(bangSpeed)  -- Use the speed from args[3]
            
            -- Define offset to position behind the target player
            local bangOffset = CFrame.new(0, 0, 1.1)
            
            -- Connect to the humanoid's Died event to clean up
            _G.BangDied = humanoid.Died:Connect(function()
                if _G.BangAnimation then _G.BangAnimation:Stop() end
                if _G.BangAnim then _G.BangAnim:Destroy() end
                if _G.BangDied then _G.BangDied:Disconnect() end
                if _G.BangLoop then _G.BangLoop:Disconnect() end
                _G.BangingActive = false
            end)
            
            -- Continuously position localPlayer behind targetPlayer while playing animation
            _G.BangLoop = RunService.Stepped:Connect(function()
                if not _G.BangingActive then
                    -- Stop the bang effect if toggle is off
                    if _G.BangAnimation then _G.BangAnimation:Stop() end
                    if _G.BangAnim then _G.BangAnim:Destroy() end
                    if _G.BangLoop then _G.BangLoop:Disconnect() end
                    if _G.BangDied then _G.BangDied:Disconnect() end
                    return
                end
                
                pcall(function()
                    local targetRoot = getRoot(target.Character)
                    local localRoot = getRoot(localPlayer.Character)
                    if targetRoot and localRoot then
                        localRoot.CFrame = targetRoot.CFrame * bangOffset
                    end
                end)
            end)
        
        elseif command == "unbang" then
            if _G.BangingActive then
                -- Stop the animation
                if _G.BangAnimation then
                    _G.BangAnimation:Stop(0.5)
                end
                
                -- Disconnect the loop
                if _G.BangLoop then
                    _G.BangLoop:Disconnect()
                end
                
                -- Disconnect the died event
                if _G.BangDied then
                    _G.BangDied:Disconnect()
                end
                
                -- Clean up animation
                if _G.BangAnim then
                    _G.BangAnim:Destroy()
                end
                
                -- Reset the global state
                _G.BangingActive = false
                Notifications:Success("Universal Hub Lite", "Banging stopped successfully", 4.5)
            else
                Notifications:Error("Universal Hub Lite", "No active banging to stop", 4.5)
            end
        
            
        elseif command == "settime" or command == "tod" then
            local timeArg = args[2] or "day"
            setTimeOfDay(timeArg)
            Notifications:Success("Universal Hub Lite", "Time Of Day Set To: " .. tostring(timeArg), 4.5)

        elseif command == "exbp" or command == "extendbaseplate" then 
            
            Notifications:Success("Universal Hub Lite", "Extending Baseplate (Game May Lag A Bit) ... ", 4.5)
            task.wait(4.5)
            local Workspace = game:GetService("Workspace");
            local Players = game:GetService("Players");
            local Player = Players.LocalPlayer
            local Terrain = Workspace.Terrain

            Terrain:FillBlock(CFrame.new(66, -10, 72.5), Vector3.new(10000, 16, 10000), Enum.Material.Asphalt)

        elseif command == "prefix" or command == "pfx" and args[2] then

            prefix = args[2] and tostring(args[2]) or "!"
            Notifications:Success("Universal Hub Lite", "Prefix Set To " .. (args[2] and tostring(args[2]) or "!"), 4.5)
           
            
        elseif command == "fpsboost" then
            local Terrain = workspace:FindFirstChildOfClass('Terrain')
        if Terrain then
            Terrain.WaterWaveSize = 0
            Terrain.WaterWaveSpeed = 0
            Terrain.WaterReflectance = 0
            Terrain.WaterTransparency = 0
        end

        local Lighting = game:GetService("Lighting")
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        settings().Rendering.QualityLevel = 1

        -- Modify all parts to improve FPS
        for i, v in pairs(game:GetDescendants()) do
            if v:IsA("Part") or v:IsA("UnionOperation") or v:IsA("MeshPart") or v:IsA("CornerWedgePart") or v:IsA("TrussPart") then
                v.Material = "Plastic"
                v.Reflectance = 0
            elseif v:IsA("Decal") then
                v.Transparency = 1
            elseif v:IsA("ParticleEmitter") or v:IsA("Trail") then
                v.Lifetime = NumberRange.new(0)
            elseif v:IsA("Explosion") then
                v.BlastPressure = 1
                v.BlastRadius = 1
            end
        end

        -- Disable unnecessary lighting effects
        for i, v in pairs(Lighting:GetDescendants()) do
            if v:IsA("BlurEffect") or v:IsA("SunRaysEffect") or v:IsA("ColorCorrectionEffect") or v:IsA("BloomEffect") or v:IsA("DepthOfFieldEffect") then
                v.Enabled = false
            end
        end

        -- Monitor new descendants and destroy specific items to keep FPS boost intact
        local RunService = game:GetService("RunService")
        workspace.DescendantAdded:Connect(function(child)
            task.spawn(function()
                if child:IsA('ForceField') or child:IsA('Sparkles') or child:IsA('Smoke') or child:IsA('Fire') then
                    RunService.Heartbeat:Wait()
                    child:Destroy()
                end
            end)
        end)  -- <-- End the DescendantAdded connection here
       
        Notifications:Success("Universal Hub Lite", "FPS Boost Activated", 4.5)


        elseif command == "uesp" then 
            Notifications:Success("Universal Hub Lite", "Executing Unamed ESP Please Wait ...", 4.5)
            task.wait(4.5)
            loadstring(game:HttpGet('https://raw.githubusercontent.com/ic3w0lf22/Unnamed-ESP/master/UnnamedESP.lua'))()

        elseif command == "emotes" then
            Notifications:Success("Universal Hub Lite", "Executing Free Emotes Script Press , To Toggle ... ", 5.5)
            task.wait(2)
            loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/Gi7331/scripts/main/Emote.lua"))()

        elseif command == "sbroken" then 
            Notifications:Success("Universal Hub Lite", "Executing SystemBroken Please Wait ... ", 4.5)
            task.wait(4.5)
            loadstring(game:HttpGet("https://raw.githubusercontent.com/H20CalibreYT/SystemBroken/main/script"))()

        elseif command == "shop" or command == "serverhop" or command == "hop" then
            ServerHop.go(args[2])

        elseif command == "antiafk" or command == "antidle" then
            Notifications:Success("Universal Hub Lite", "Anti Idle Activated !", 4.5)
            local vu = game:GetService("VirtualUser")
            game:GetService("Players").LocalPlayer.Idled:Connect(function()
                vu:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
                wait(1)
                vu:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
            end)  -- ✅ This line was missing

        elseif command == "CopyUser" or command == "copyuser" then 
            local target = findPlayer(args[2])
            if not target then 
                Notifications:Success("Universal Hub Lite", "Target Not Found!", 4.5)
                return
            end
            Notifications:Success("Universal Hub Lite", "Copied username", 4.5, nil, target.Name)
            setclipboard(tostring(target.Name))
        
        elseif command == "CopyDisplay" or command == "copydisplay" then
            local target = findPlayer(args[2])
            if not target then 
                Notifications:Success("Universal Hub Lite", "Target Not Found!", 4.5)
                return
            end
            Notifications:Success("Universal Hub Lite", "Copied " .. tostring(target.DisplayName), 4.5, nil, target.Name)
            setclipboard(tostring(target.DisplayName))
        
        elseif command == "CopyUserId" or command == "copyuserid" or command == "copyid" then 
            local target = findPlayer(args[2])
            if not target then 
                Notifications:Success("Universal Hub Lite", "Target Not Found!", 4.5)
                return
            end
            Notifications:Success("Universal Hub Lite", "Copied " .. tostring(target.UserId), 4.5, nil, target.Name)
            setclipboard(tostring(target.UserId))
-- This part should be inside an existing if-elseif structure
elseif command == "Orbit" or command == "orbit" then
    -- Remove the fixed orbit radius and use the argument for speed.
    _G.isOrbiting = false
    _G.orbitSpeed = tonumber(args[3]) or 1  -- Set orbit speed from args[3], default to 1 if not provided.
    if _G.orbitSpeed < 1 then _G.orbitSpeed = 1 end
    if _G.orbitSpeed > 5 then _G.orbitSpeed = 5 end
    
    _G.orbitTarget = function(targetPlayer)  -- Pass targetPlayer as an argument
        local angle = 0
        while _G.isOrbiting and targetPlayer do
            local targetPos = targetPlayer.Character.HumanoidRootPart.Position
            local orbitPos = targetPos + Vector3.new(
                math.cos(angle) * 5,  -- Fixed radius of 5 (or another value you prefer)
                0,
                math.sin(angle) * 5
            )
            game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(orbitPos, targetPos)
            angle = angle + _G.orbitSpeed * 0.1
            game:GetService("RunService").Heartbeat:Wait()
        end
    end

    local targetPlayer = findPlayer(args[2]) -- Find the target player

    if targetPlayer then
        _G.isOrbiting = true  -- Set the orbiting state to true
        Badge.set("orbit")
        Notifications:Success("Universal Hub Lite",
            "Orbiting " .. targetPlayer.Name .. "  \194\183  speed " .. _G.orbitSpeed, 4.5, {
                { label = "Stop orbit", icon = "st_rotate-cw.png", style = "light",
                  run = function() _G.isOrbiting = false Badge.set("idle") end },
            }, targetPlayer.Name)
        spawn(function() _G.orbitTarget(targetPlayer) end) -- Start the orbiting function in a new thread, passing targetPlayer
    else
        Notifications:Error("Universal Hub Lite", "Target player not found!", 4.5)  -- Notify if no player is found
    end

elseif command == "Unorbit" or command == "unorbit" then
    -- Stop the orbiting
    _G.isOrbiting = false
    Notifications:Success("Universal Hub Lite", "Orbiting Stopped", 4.5)
    Badge.set("idle")

elseif command == "ShowImg" or command == "showimg" then 
    local targetPlayer = findPlayer(args[2]) -- Find the target player

    -- Check if targetPlayer is found
    if not targetPlayer then
        Notifications:Error("Universal Hub Lite", "Target player not found!", 4.5)  -- Notify if no player found
        return
    end

    local ScreenGui = Instance.new("ScreenGui")
    local Frame = Instance.new("Frame")
    local UICorner = Instance.new("UICorner")
    local ImageButton = Instance.new("ImageButton")
    local ImageLabel = Instance.new("ImageLabel")

    -- ScreenGui Properties
    ScreenGui.Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui")
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    -- Frame Properties
    Frame.Parent = ScreenGui
    Frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    Frame.BackgroundTransparency = 0.5
    Frame.BorderColor3 = Color3.fromRGB(0, 0, 0)
    Frame.BorderSizePixel = 0
    Frame.Position = UDim2.new(0.635, 0, 0.43, 0)
    Frame.Size = UDim2.new(0, 187, 0, 196)
    Frame.Active = true
    Frame.Draggable = true  -- Makes the frame draggable

    UICorner.CornerRadius = UDim.new(0, 35)
    UICorner.Parent = Frame

    -- Exit Button (ImageButton)
    ImageButton.Parent = Frame
    ImageButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    ImageButton.BackgroundTransparency = 1
    ImageButton.BorderSizePixel = 0
    ImageButton.Position = UDim2.new(0.84, 0, 0.05, 0)
    ImageButton.Size = UDim2.new(0, 23, 0, 22)
    ImageButton.Image = "rbxassetid://75885882003801"

    -- Player Image Display (ImageLabel)
    ImageLabel.Parent = Frame
    ImageLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    ImageLabel.BackgroundTransparency = 1
    ImageLabel.Position = UDim2.new(0.12, 0, 0.16, 0)
    ImageLabel.Size = UDim2.new(0, 143, 0, 143)

    -- Check if the targetPlayer is set and not the local player
    if targetPlayer and targetPlayer ~= game.Players.LocalPlayer then
        -- If there is a valid targetPlayer, show their image
        ImageLabel.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. targetPlayer.UserId .. "&width=420&height=420&format=png"
    else
        -- If no targetPlayer or the local player is the target, show the default image
        ImageLabel.Image = "rbxassetid://122802938843781"
    end

    -- Exit Button with Fade-out Effect
    ImageButton.MouseButton1Click:Connect(function()
        for transparency = 0.5, 1, 0.05 do
            Frame.BackgroundTransparency = transparency
            ImageLabel.ImageTransparency = transparency
            ImageButton.ImageTransparency = transparency  -- Fade the button as well
            wait(0.05)
        end
        ScreenGui:Destroy()  -- Remove the GUI after fading out
    end)

elseif command == "Headless" or command == "headless" then
    local character = game.Players.LocalPlayer.Character
    if character then
        local head = character:FindFirstChild("Head")
        if head then
            -- Make the headless
            head.Transparency = 1
            local face = head:FindFirstChild("face")
            if face then
                face.Transparency = 1
            end
            Notifications:Success("Universal Hub Lite", "Headless on  \194\183  client-side", 4.5, {
                { label = "Undo", icon = "st_user-x.png", style = "light",
                  run = function()
                      local ch = game.Players.LocalPlayer.Character
                      local hd = ch and ch:FindFirstChild("Head")
                      if hd then
                          hd.Transparency = 0
                          local fa = hd:FindFirstChild("face")
                          if fa then fa.Transparency = 0 end
                      end
                  end },
            })
        end
    end

elseif command == "Unheadless" or command == "unheadless" or command == "noheadless" then
    local character = game.Players.LocalPlayer.Character
    if character then
        local head = character:FindFirstChild("Head")
        if head then
            -- Make the head visible again
            head.Transparency = 0
            local face = head:FindFirstChild("face")
            if face then
                face.Transparency = 0
            end
            Notifications:Success("Universal Hub Lite", "Headless Disabled (Client-Side)", 4.5)
        end
    end

elseif command == "CopyInv" or command == "copyinv" then
    -- Copy the invite link to the clipboard
    setclipboard("https://discord.gg/ZNfKFyuUEd")
    Notifications:Success("Universal Hub Lite", "Invite Link Copied To Clipboard !", 4.5)

elseif command == "CopyWebLink" or command == "copywebsitelink" or command == "copyweblink" then
    -- Copy the website link to the clipboard
    setclipboard("https://angxers2.github.io/Unihub/")
    Notifications:Success("Universal Hub Lite", "Website Link Copied To Clipboard!", 4.5)



elseif command == "ShowStats" or command == "Stats" or command == "stats" or command == "showstats" then
    Perf.toggle()

elseif command == "CmdBarKeybind" or command == "barkeybind" or command == "cmdbarkeybind" or command == "cmdbarbind" or command == "barbind" then
    local keybind = args[2]
    local keycode = Enum.KeyCode[keybind:upper()] -- Make it case-insensitive

    if keycode then
        _G.CmdBarKeybind = keycode
        UI.saveConfig()
        Notifications:Success("Universal Hub Lite", "Command Bar Keybind set to " .. keycode.Name, 4.5)
    else
        Notifications:Error("Universal Hub Lite", "Invalid keybind: " .. tostring(keybind), 4.5)
    end



elseif command == "Cmds" or command == "cmds" or command == "Commands" or command == "commands" then
    CmdList.show()

elseif command == "info" or command == "about" or command == "version" or command == "ver" then
    About.show()

elseif command == "activity" or command == "act" or command == "watch" then
    Activity.show(args[2])

elseif command == "notify" or command == "unotify" or command == "unnotify"
    or command == "notifyoff" then
    -- !notify turns it on, the rest turn it off. Same handler, because the
    -- state lives in one place and a second one would drift.
    Activity.notifying = (command == "notify")
    if Activity.notifyBtn then Activity.paintNotify(Activity.notifyBtn) end
    Notifications:Success("Universal Hub Lite", Activity.notifying
        and "Notifying for every activity event"
        or "Activity notifications off", 3.5)

elseif command == "mutevc" or command == "mute" or command == "vcmute" then
    Voice.apply(args[2], true)

elseif command == "unmutevc" or command == "unmute" or command == "vcunmute" then
    Voice.apply(args[2], false)

elseif command == "resume" or command == "runlast" then
    if #((ScriptHub and ScriptHub.ran) or {}) == 0 then
        Notifications:Info("Universal Hub Lite",
            "Nothing to resume -- run something from !scripthub first", 4)
    else
        -- Asking for it explicitly turns the prompt back on: you would not
        -- type this if you wanted it to stay off.
        if UI.askResume == false then
            UI.askResume = true
            UI.saveConfig()
        end
        Resume.show()
    end

elseif command == "scripthub" or command == "hub" or command == "scripts" then
    ScriptHub.show()

elseif command == "esp" or command == "espmenu" or command == "chams" then
    ESP.show()

elseif command == "unesp" or command == "noesp" then
    for _, f in ipairs(ESP.FEATURES) do ESP.cfg[f.key] = false end
    ESP.sync()
    Notifications:Success("Universal Hub Lite", "ESP off", 3)

elseif command == "headsit" or command == "hs" then
    local t = findPlayer(args[2])
    if not t then
        Notifications:Error("Universal Hub Lite", "Target player not found", 4)
    elseif startHeadSit(t) then
        Notifications:Success("Universal Hub Lite", "Sitting on " .. t.Name, 4.5, {
            { label = "Get off", icon = "st_user-x.png", style = "light",
              run = function() stopHeadSit() end },
        }, t.Name)
    else
        Notifications:Error("Universal Hub Lite", "Could not sit on them", 4)
    end

elseif command == "unheadsit" or command == "uhs" or command == "stopheadsit" then
    stopHeadSit()
    Notifications:Success("Universal Hub Lite", "Stopped headsit", 4)

elseif command == "backpack" or command == "bp" then
    local t = findPlayer(args[2])
    if not t then
        Notifications:Error("Universal Hub Lite", "Target player not found", 4)
    elseif startBackpacking(t) then
        Notifications:Success("Universal Hub Lite", "Riding " .. t.Name, 4.5, {
            { label = "Get off", icon = "st_user-x.png", style = "light",
              run = function() stopBackpacking() end },
        }, t.Name)
    else
        Notifications:Error("Universal Hub Lite", "Could not backpack them", 4)
    end

elseif command == "unbackpack" or command == "ubp" or command == "stopbackpack" then
    stopBackpacking()
    Notifications:Success("Universal Hub Lite", "Stopped backpack", 4)

elseif command == "drag" then
    local t = findPlayer(args[2])
    if not t then
        Notifications:Error("Universal Hub Lite", "Target player not found", 4)
    elseif startDragging(t) then
        Notifications:Success("Universal Hub Lite", "Dragged by " .. t.Name, 4.5, {
            { label = "Break free", icon = "st_user-x.png", style = "light",
              run = function() stopDragging() end },
        }, t.Name)
    else
        Notifications:Error("Universal Hub Lite", "Could not attach to them", 4)
    end

elseif command == "undrag" or command == "udr" or command == "stopdrag" then
    stopDragging()
    Notifications:Success("Universal Hub Lite", "Stopped drag", 4)

elseif command == "attach" then
    local t = findPlayer(args[2])
    if not t then
        Notifications:Error("Universal Hub Lite", "Target player not found", 4)
    elseif startAttaching(t) then
        Notifications:Success("Universal Hub Lite", "Attached to " .. t.Name, 4.5, {
            { label = "Detach", icon = "st_user-x.png", style = "light",
              run = function() stopAttaching() end },
        }, t.Name)
    else
        Notifications:Error("Universal Hub Lite", "Could not attach", 4)
    end

elseif command == "unattach" or command == "ua" or command == "detach" then
    stopAttaching()
    Notifications:Success("Universal Hub Lite", "Detached", 4)

elseif command == "stare" or command == "lookat" then
    local t = findPlayer(args[2])
    if not t then
        Notifications:Error("Universal Hub Lite", "Target player not found", 4)
    elseif startStaring(t) then
        Notifications:Success("Universal Hub Lite", "Staring at " .. t.Name, 4.5, {
            { label = "Stop staring", icon = "st_eye.png", style = "light",
              run = function() stopStaring() end },
        }, t.Name)
    else
        Notifications:Error("Universal Hub Lite", "Could not stare", 4)
    end

elseif command == "unstare" or command == "stopstare" then
    stopStaring()
    Notifications:Success("Universal Hub Lite", "Stopped staring", 4)

elseif command == "copydance" or command == "cd" then
    local t = findPlayer(args[2])
    if not t then
        Notifications:Error("Universal Hub Lite", "Target player not found", 4)
    elseif startCopyDance(t) then
        Notifications:Success("Universal Hub Lite", "Copying " .. t.Name, 4.5, {
            { label = "Stop", icon = "st_footprints.png", style = "light",
              run = function() stopCopyDance() end },
        }, t.Name)
    else
        Notifications:Error("Universal Hub Lite", "Could not copy them", 4)
    end

elseif command == "uncopydance" or command == "ucd" or command == "stopcopydance" then
    stopCopyDance()
    Notifications:Success("Universal Hub Lite", "Stopped copying", 4)

elseif command == "profile" or command == "prof" or command == "whois"
    or command == "playerinfo" or command == "pinfo" then
    local t = findPlayer(args[2]) or LocalPlayer
    if Profile.show(t) then
        Bar.mode = "menu"       -- the card IS the answer; no toast over it
    else
        Notifications:Error("Universal Hub Lite", "Could not read that profile", 4)
    end

elseif command == "unprofile" or command == "closeprofile" then
    Profile.hide()

elseif command == "quickjoin" or command == "qj" or command == "join" then
    local q = table.concat(args, " ", 2)
    if q == "" then
        local names = {}
        for _, g in ipairs(QuickJoin.games) do names[#names + 1] = g.keys[1] end
        Notifications:Info("Universal Hub Lite",
            "Try: " .. table.concat(names, ", ", 1, math.min(6, #names)) .. " ...", 6)
    elseif not QuickJoin.go(q) then
        Notifications:Error("Universal Hub Lite", "No game matching '" .. q .. "'", 4)
    end

elseif command == "keepuhub" or command == "autoexec" or command == "persist" then
    if not Persist.queue then
        Notifications:Error("Universal Hub Lite",
            "Executor has no queue_on_teleport", 4.5)
    else
        Persist.enabled = not Persist.enabled
        UI.saveConfig()
        Settings.renderCollapsed()
        Notifications:Success("Universal Hub Lite",
            Persist.enabled and "Will re-run after teleports"
                             or "Will not re-run after teleports", 4)
    end

elseif command == "guide" or command == "help" or command == "tutorial" then
    Guide.show(false)

elseif command == "tour" or command == "walkthrough" then
    Tour.start()

elseif command == "stopall" then
    stopAllAttach() stopStaring() stopCopyDance() Profile.hide()
    if isSpinning then toggleSpin() end
    _G.isOrbiting = false
    if isFlying and flyForceStop then flyForceStop() end
    setNoClip(false)
    Badge.set("idle")
    Notifications:Success("Universal Hub Lite", "Everything stopped", 4)

elseif command == "Unexecute" or command == "unexecute" or command == "unexec"
    or command == "unload" then
    Notifications:Warning("Universal Hub Lite", "Unloading...", 2)
    -- Let the toast play, then tear everything down so the script can be
    -- executed again cleanly.
    task.delay(1.6, function()
        pcall(unexecuteHub)
    end)

else
    -- Imported Infinite Yield commands live in a table, checked only after
    -- every native branch has been tried.
    if not IY.run(command, args) then
        Notifications:Warning("Universal Hub Lite",
            "Unknown command: " .. tostring(command), 3)
        print("Unknown command:", command)
    end
end
end
end

-- Bound HERE, not up in the IY block: processCommand is a file-scope local
-- declared below it, so a closure created earlier would resolve the name as
-- a nil global and every chained IY command would silently no-op.
IY.exec = function(str) processCommand(prefix .. tostring(str)) end

print([[
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@JrrrrrrrQ@@@@@@@@@@@@@@@$xrrrrrrrB@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@-      .}@@@@@@@@@@@@@@@B`       #@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@-.      }@@@@@@@@@@@@@@@B`.      #@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@-   .   }@@@@@@@@@@@@@@@B`.     .#@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@- .     }@@@@@@@@@@@@@@@B`.      #@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@-      .}@@@@@@@@@@@@@@@B`       #@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@-       }@@@@@@@@@@@@@@@B`  .  . #@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@-      .}@@@@@@@@@@@@@@@B`       #@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@-       }@@@@@@@@@@@@@@@B`   .   #@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@-      .}@@@@@@@@@@@@@@@B`  .    #@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@-.      }@@@@@@@@@@@@@@@B`       #@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@-       }@@@@@@@@@@@@@@@B`       #@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@-       }@@@@@@@@@@@@@@@B`   .   #@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@-       }@@@@@@@@@@@@@@@B`       #@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@] . ..  -@@@@@@@@@@@@@@@B`     . M@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@j      .:@@@@@@@@@@@@@@@C.      ^@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@$..      !@@@@@@@@@@@@@d      . 1@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@/.        0@@@@@@@@@M]        '*@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@|          '>1|)];.  .      .h@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@Z   .         .           iB@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@O`                   .~$@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@Y<`           .;1*@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@$*hkkaM@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@(   'o@@@@@@@0   .a@@@@X` . :@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@I   -@@@@@@$^  .|@@ai.     :@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@Q  . p@@@@@z   `@@M.  I#.  :@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@[  ._@@@@$"   Z@@M"Y@@W.  :@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@a.   Z@@@f   <@@@@@@@@W.  :@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@z   <@@@"  'M@@@@@@@@W. .:@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@$'   0@}   f@@@@@@@@@W.  :@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@a.  lB`  I@@@@@@@@@@W'  :@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@-   ;   m@@@@@@@@@@W.  :@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@"     }@@@@@@@@@@@W.  :@@a@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@v''''`#@@@@@@@@@@@W`''I@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
]])

-- Get required services
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local TweenService = game:GetService("TweenService")

-- This should match your existing prefix variable from your main script
-- (prefix is declared once, above processCommand -- CmdBar must use that
--  same local or a !prefix change would silently break every command)


-- List of all commands and aliases for autocomplete
local commandList = {
    "fly", "unfly", "fov", "rj", "rejoin", "uhub", "noclip", "clip",
    "walkspeed", "ws", "jump", "view", "unview", "infjump", "goto", "tp",
    "to", "bypassvc", "bvc", "rvc", "infyield", "ify", "savepos", "topos",
    "clicktp", "spin", "unspin", "bang", "unbang", "settime", "tod", "exbp",
    "extendbaseplate", "prefix", "pfx", "fpsboost", "uesp", "emotes", "sbroken", "shop",
    "serverhop", "hop", "antiafk", "antidle", "copyuser", "copydisplay", "copyuserid", "copyid", "orbit",
    "unorbit", "showimg", "headless", "unheadless", "noheadless", "copyinv", "copyweblink", "copywebsitelink",
    "showstats", "stats", "cmds", "commands", "info", "about", "version", "ver", "esp", "espmenu", "chams", "unesp", "noesp", "scripthub", "hub", "scripts", "resume", "runlast",
    "mutevc", "mute", "vcmute", "unmutevc", "unmute", "vcunmute", "activity", "act", "watch", "notify", "unotify", "unnotify", "notifyoff", "cmdbarkeybind", "barkeybind", "cmdbarbind", "barbind",
    "unexecute", "unexec", "unload", "headsit", "hs", "unheadsit", "uhs", "backpack",
    "bp", "unbackpack", "ubp", "drag", "undrag", "udr", "attach", "unattach",
    "ua", "detach", "stare", "lookat", "unstare", "copydance", "cd", "uncopydance",
    "ucd", "stopall", "age", "ambient", "anchor", "animspeed", "appearanceid", "blockhats",
    "blockhead", "blocktool", "breakvelocity", "brightness", "bringpart", "bringpartclass", "camdistance", "chardeleteclass",
    "clearcharappearance", "clickdelete", "copytools", "creeper", "ctrllock", "day", "delete", "deleteclass",
    "deletehats", "deleteinvisparts", "deleteselectedtool", "deletevelocity", "destroyheight", "disablestate", "drophats", "droppabletools",
    "droptools", "enablestate", "equiptools", "firstp", "freeze", "freezeanims", "friend", "fullbright",
    "getposition", "globalshadows", "gotocamera", "grippos", "headsize", "headthrow", "hipheight", "hitbox",
    "joindate", "jpower", "lay", "light", "lockws", "loopanimation", "maxslopeangle", "maxzoom",
    "minzoom", "mousesensitivity", "naked", "night", "nilchar", "noanim", "noarms", "nobgui",
    "noclickdetectorlimits", "noface", "nofog", "nolegs", "nolimbs", "noproximitypromptlimits", "norender", "noroot",
    "norotate", "nosit", "notifyping", "notools", "offset", "reanim", "refresh", "refreshanimations",
    "removeads", "removeterrain", "render", "replaceroot", "reset", "respawn", "scare", "sit",
    "sitwalk", "stopanimations", "stun", "thirdp", "thru", "tpposition", "trip", "unanchor",
    "unctrllock", "unequiptools", "unfreezeanims", "unfriend", "unglobalshadows", "unlight", "unlockws", "unnilchar",
    "unnorotate", "unnosit", "unstun", "usetools", "vehiclegoto", "walktopos", "aid", "bpc",
    "charremoveclass", "chardeleteclassname", "charremoveclassname", "cdc", "clearchar", "clrchar", "remove", "removeclass",
    "deleteclassname", "removeclassname", "dc", "nohats", "rhats", "deleteinvisibleparts", "dip", "dst",
    "dv", "removevelocity", "removeforces", "dh", "drophat", "droptool", "fr", "fb",
    "fullbrightness", "getpos", "notifypos", "notifyposition", "gshadows", "gotocam", "tocam", "hheight",
    "jd", "jumppower", "jp", "laydown", "lockworkspace", "loopanim", "msa", "ms",
    "rarms", "unbgui", "nobillboardgui", "unbillboardgui", "noname", "rohg", "nocdlimits", "removecdlimits",
    "removeface", "rlegs", "rlimbs", "nopplimits", "removepplimits", "removeroot", "rroot", "noautorotate",
    "ping", "rtools", "clrtools", "removetools", "deletetools", "dtools", "re", "refreshanimation",
    "refreshanims", "refreshanim", "adblock", "rterrain", "noterrain", "replacerootpart", "spook", "stopanims",
    "stopanim", "platformstand", "tppos", "nogshadows", "ungshadows", "noglobalshadows", "nolight", "unlockworkspace",
    "nonilchar", "autorotate", "nostun", "unplatformstand", "noplatformstand", "vgoto", "vtp", "vehicletp",
    "walktoposition", "antilag", "chat", "chatage", "chatjoindate", "clearhats", "copyanimationid", "copyappearanceid",
    "copyposition", "gotomodel", "gotopart", "gotopartclass", "gotopartdelay", "hitboxes", "inspect", "muteallvoices",
    "nolocate", "noprompts", "pulsetp", "rec", "screenshot", "showprompts", "strengthen", "thaw",
    "togglefs", "tweengoto", "tweengotocamera", "tweengotomodel", "tweengotopart", "tweengotopartclass", "tweenspeed", "tweentpposition",
    "unflyfling", "unhitboxes", "unmuteallvoices", "unweaken", "wallwalk", "weaken", "whisper", "boostfps",
    "lowgraphics", "say", "cjd", "cleanhats", "copyanimid", "copyemoteid", "caid", "copypos",
    "tomodel", "topart", "gpc", "examine", "muteallvcs", "unlocate", "nopurchaseprompts", "ptp",
    "record", "scrnshot", "showpurchaseprompts", "unfreeze", "unfr", "togglefullscreen", "tgoto", "tto",
    "tweento", "tweengotocam", "tgotocam", "ttocam", "tgotomodel", "ttomodel", "tgotopart", "ttopart",
    "tgpc", "tspeed", "ttppos", "unmuteallvcs", "unstrengthen", "walkonwalls", "pm", "profile",
    "prof", "whois", "playerinfo", "pinfo", "unprofile", "closeprofile", "quickjoin", "qj",
    "join", "keepuhub", "autoexec", "persist", "guide", "help", "tutorial", "tour",
    "walkthrough"
}

-- Commands that require player arguments
local playerCommands = {
    "activity", "act", "watch",
    "mutevc", "mute", "vcmute", "unmutevc", "unmute", "vcunmute",
    "goto", "tp", "to", "view", "bang", "orbit", "showimg", "copyuser", "copydisplay",
    "copyuserid", "copyid", "headsit", "hs", "backpack", "bp", "drag", "attach",
    "stare", "lookat", "copydance", "cd", "profile", "prof", "whois",
    "playerinfo", "pinfo"
}

-- Helper function to check if command needs player argument
local function commandNeedsPlayer(cmd)
    cmd = (cmd or ""):lower()
    for _, playerCmd in ipairs(playerCommands) do
        if cmd == playerCmd then return true end
    end
    -- imported commands count too, else the picker only worked for native ones
    if IY and IY.needsPlayer then
        if IY.needsPlayer[cmd] then return true end
        local canon = IY.alias and IY.alias[cmd]
        if canon and IY.needsPlayer[canon] then return true end
    end
    return false
end

-- Helper function to find matching players
local function getMatchingPlayers(nameSegment)
    if not nameSegment or nameSegment == "" then return {} end
    nameSegment = nameSegment:lower()
    
    local matches = {}
    local addedPlayers = {}
    
    for _, player in pairs(Players:GetPlayers()) do
        local userName = player.Name:lower()
        local displayName = player.DisplayName:lower()
        
        if displayName:sub(1, #nameSegment) == nameSegment then
            if not addedPlayers[player.Name] then
                table.insert(matches, {
                    name = player.Name,
                    display = player.DisplayName,
                    matchType = "display",
                    matchedOn = player.DisplayName
                })
                addedPlayers[player.Name] = true
            end
        elseif userName:sub(1, #nameSegment) == nameSegment then
            if not addedPlayers[player.Name] then
                table.insert(matches, {
                    name = player.Name,
                    display = player.DisplayName,
                    matchType = "username",
                    matchedOn = player.Name
                })
                addedPlayers[player.Name] = true
            end
        end
    end
    return matches
end

-- ════════════════════════════════════════════════════════════════════════
--  COMMAND BAR CARD
-- ════════════════════════════════════════════════════════════════════════
CmdBar = {
    open = false,
    rows = {},
    matches = {},
    selected = 1,
    ROW_H = 36,
    ROW_H_PLAYER = 48,
    MAX_ROWS = 6,
}

-- Value arguments, and the default each command actually falls back to when
-- you omit one. Keyed by every alias, since the hint is looked up off what
-- was typed, not off a canonical name.
--
-- A string is a hint for the first argument. A table is one entry per
-- argument slot, so a command shaped "orbit <player> <speed>" can stay quiet
-- for the player -- which has a picker -- and hint the speed after it. false
-- means "this slot has one, but not a hint we give".
CmdBar.argHints = {
    fly = "50", walkspeed = "16", ws = "16", jump = "50", fov = "70",
    settime = "night", tod = "night", prefix = "!", pfx = "!",
    animspeed = "1", sethealth = "100", gravity = "196",
    cmdbarkeybind = "T", barkeybind = "T", cmdbarbind = "T", barbind = "T",
    quickjoin = "mm2", qj = "mm2", join = "mm2",

    -- player first, value second
    orbit   = { false, "1" },      -- args[3] -> _G.orbitSpeed, default 1
    bang    = { false, "3" },      -- args[3] -> AdjustSpeed, default 3
    hitbox  = { false, "10" },
    whisper = { false, "hello" },
    pm      = { false, "hello" },
    mutevc  = { "all" }, mute = { "all" },
    unmutevc = { "all" }, unmute = { "all" },
}

-- Which argument slot is the caret sitting in, and does it have a hint?
-- Only fires on an EMPTY slot: "fly" or "fly 2" show nothing, "fly " does,
-- or the hint would render underneath what you are typing.
function CmdBar.hintFor(text)
    text = tostring(text or "")
    if text:sub(-1) ~= " " then return nil end     -- mid-token
    local parts = {}
    for w in text:gmatch("%S+") do parts[#parts + 1] = w end
    if #parts == 0 then return nil end

    local spec = CmdBar.argHints[parts[1]:lower()]
    if not spec then return nil end

    -- parts[1] is the command, so the slot being opened is #parts.
    local slot = #parts
    local hint = (type(spec) == "table") and spec[slot] or (slot == 1 and spec)
    if type(hint) ~= "string" then return nil end

    -- Past the first slot, only hint once the earlier argument is real: the
    -- suggestion list is still offering players for "orbit garba ", and a
    -- speed hint next to it would be describing a command that cannot run.
    if slot > 1 and commandNeedsPlayer(parts[1]:lower())
       and not CmdBar.isPlayerName(parts[2] or "") then
        return nil
    end
    return hint
end

-- Lucide glyph per command. Anything unlisted falls back to st_zap.
-- "goto" is a reserved word, so it is keyed as goto_ and mapped in glyphFor.
CmdBar.glyphs = {
    activity = "st_activity.png", act = "st_activity.png", watch = "st_activity.png",
    notify = "st_zap.png", unotify = "st_zap.png", unnotify = "st_zap.png",
    notifyoff = "st_zap.png",
    hop = "st_server.png",
    resume = "st_refresh-cw.png", runlast = "st_refresh-cw.png",
    mutevc = "st_mic.png", mute = "st_mic.png", vcmute = "st_mic.png",
    unmutevc = "st_mic.png", unmute = "st_mic.png", vcunmute = "st_mic.png",
    scripthub = "st_list.png", hub = "st_list.png", scripts = "st_list.png",
    esp = "st_scan-eye.png", espmenu = "st_scan-eye.png",
    chams = "st_ghost.png", unesp = "st_scan-eye.png", noesp = "st_scan-eye.png",
    showstats = "st_gauge.png", stats = "st_gauge.png",
    info = "st_info.png", about = "st_info.png", version = "st_info.png",
    fly = "st_plane.png", unfly = "st_plane.png",
    noclip = "st_ghost.png", clip = "st_ghost.png",
    jump = "st_arrow-up.png", infjump = "st_arrow-up.png",
    view = "st_eye.png", unview = "st_eye.png",
    spin = "st_rotate-cw.png", unspin = "st_rotate-cw.png",
    orbit = "st_rotate-cw.png", unorbit = "st_rotate-cw.png",
    bang = "st_footprints.png", unbang = "st_footprints.png",
    rj = "st_refresh-cw.png", rejoin = "st_refresh-cw.png",
    shop = "st_server.png", serverhop = "st_server.png",
    fov = "st_video.png",
    settime = "st_clock.png", tod = "st_clock.png",
    antiafk = "st_coffee.png", antidle = "st_coffee.png",
    copyuser = "st_copy.png", copydisplay = "st_copy.png",
    copyuserid = "st_copy.png", copyid = "st_copy.png",
    copyinv = "st_copy.png", copyweblink = "st_copy.png",
    copywebsitelink = "st_copy.png",
    showimg = "st_image.png",
    headless = "st_user-x.png", unheadless = "st_user-x.png",
    noheadless = "st_user-x.png",
    cmdbarkeybind = "st_keyboard.png", barkeybind = "st_keyboard.png",
    cmdbarbind = "st_keyboard.png", barbind = "st_keyboard.png",
    cmds = "st_list.png", commands = "st_list.png",
    unexecute = "st_circle-x.png", unexec = "st_circle-x.png",
    unload = "st_circle-x.png",
    headsit = "st_users.png", hs = "st_users.png",
    unheadsit = "st_users.png", uhs = "st_users.png",
    backpack = "st_users.png", bp = "st_users.png",
    unbackpack = "st_users.png", ubp = "st_users.png",
    drag = "st_footprints.png", undrag = "st_footprints.png", udr = "st_footprints.png",
    attach = "st_users.png", unattach = "st_users.png", ua = "st_users.png",
    detach = "st_users.png",
    stare = "st_eye.png", lookat = "st_eye.png", unstare = "st_eye.png",
    copydance = "st_footprints.png", cd = "st_footprints.png",
    uncopydance = "st_footprints.png", ucd = "st_footprints.png",
    stopall = "st_circle-x.png",
    profile = "st_users.png", prof = "st_users.png", whois = "st_users.png",
    playerinfo = "st_users.png", pinfo = "st_users.png",
    unprofile = "st_x.png", closeprofile = "st_x.png",
    quickjoin = "st_server.png", qj = "st_server.png", join = "st_server.png",
    guide = "st_info.png", help = "st_info.png", tutorial = "st_info.png",
    tour = "st_chevron-right.png", walkthrough = "st_chevron-right.png",
    keepuhub = "st_refresh-cw.png", autoexec = "st_refresh-cw.png",
    persist = "st_refresh-cw.png",
    -- imported Infinite Yield commands
    ["adblock"] = "st_trash-2.png",
    ["age"] = "st_user-x.png",
    ["aid"] = "st_user-x.png",
    ["ambient"] = "st_lightbulb.png",
    ["anchor"] = "st_anchor.png",
    ["animspeed"] = "st_person-standing.png",
    ["antilag"] = "st_wrench.png",
    ["appearanceid"] = "st_user-x.png",
    ["autorotate"] = "st_snowflake.png",
    ["blockhats"] = "st_box.png",
    ["blockhead"] = "st_box.png",
    ["blocktool"] = "st_shirt.png",
    ["boostfps"] = "st_wrench.png",
    ["bpc"] = "st_zap.png",
    ["breakvelocity"] = "st_snowflake.png",
    ["brightness"] = "st_lightbulb.png",
    ["bringpart"] = "st_zap.png",
    ["bringpartclass"] = "st_zap.png",
    ["caid"] = "st_user-x.png",
    ["camdistance"] = "st_camera.png",
    ["cdc"] = "st_trash-2.png",
    ["chardeleteclass"] = "st_trash-2.png",
    ["chardeleteclassname"] = "st_trash-2.png",
    ["charremoveclass"] = "st_trash-2.png",
    ["charremoveclassname"] = "st_trash-2.png",
    ["chat"] = "st_shirt.png",
    ["chatage"] = "st_shirt.png",
    ["chatjoindate"] = "st_shirt.png",
    ["cjd"] = "st_shirt.png",
    ["cleanhats"] = "st_shirt.png",
    ["clearchar"] = "st_trash-2.png",
    ["clearcharappearance"] = "st_trash-2.png",
    ["clearhats"] = "st_shirt.png",
    ["clickdelete"] = "st_trash-2.png",
    ["clrchar"] = "st_trash-2.png",
    ["clrtools"] = "st_shirt.png",
    ["copyanimationid"] = "st_person-standing.png",
    ["copyanimid"] = "st_person-standing.png",
    ["copyappearanceid"] = "st_user-x.png",
    ["copyemoteid"] = "st_person-standing.png",
    ["copypos"] = "st_person-standing.png",
    ["copyposition"] = "st_person-standing.png",
    ["copytools"] = "st_shirt.png",
    ["creeper"] = "st_person-standing.png",
    ["ctrllock"] = "st_lock.png",
    ["day"] = "st_lightbulb.png",
    ["dc"] = "st_trash-2.png",
    ["delete"] = "st_trash-2.png",
    ["deleteclass"] = "st_trash-2.png",
    ["deleteclassname"] = "st_trash-2.png",
    ["deletehats"] = "st_shirt.png",
    ["deleteinvisibleparts"] = "st_scan-eye.png",
    ["deleteinvisparts"] = "st_scan-eye.png",
    ["deleteselectedtool"] = "st_shirt.png",
    ["deletetools"] = "st_shirt.png",
    ["deletevelocity"] = "st_snowflake.png",
    ["destroyheight"] = "st_trash-2.png",
    ["dh"] = "st_trash-2.png",
    ["dip"] = "st_scan-eye.png",
    ["disablestate"] = "st_wrench.png",
    ["drophat"] = "st_shirt.png",
    ["drophats"] = "st_shirt.png",
    ["droppabletools"] = "st_shirt.png",
    ["droptool"] = "st_shirt.png",
    ["droptools"] = "st_shirt.png",
    ["dst"] = "st_shirt.png",
    ["dtools"] = "st_shirt.png",
    ["dv"] = "st_snowflake.png",
    ["enablestate"] = "st_wrench.png",
    ["equiptools"] = "st_shirt.png",
    ["examine"] = "st_user-x.png",
    ["fb"] = "st_lightbulb.png",
    ["firstp"] = "st_camera.png",
    ["fr"] = "st_snowflake.png",
    ["freeze"] = "st_snowflake.png",
    ["freezeanims"] = "st_person-standing.png",
    ["friend"] = "st_user-x.png",
    ["fullbright"] = "st_lightbulb.png",
    ["fullbrightness"] = "st_lightbulb.png",
    ["getpos"] = "st_person-standing.png",
    ["getposition"] = "st_person-standing.png",
    ["globalshadows"] = "st_cloud-fog.png",
    ["gotocam"] = "st_camera.png",
    ["gotocamera"] = "st_camera.png",
    ["gotomodel"] = "st_move.png",
    ["gotopart"] = "st_move.png",
    ["gotopartclass"] = "st_move.png",
    ["gotopartdelay"] = "st_person-standing.png",
    ["gpc"] = "st_move.png",
    ["grippos"] = "st_shirt.png",
    ["gshadows"] = "st_cloud-fog.png",
    ["headsize"] = "st_box.png",
    ["headthrow"] = "st_person-standing.png",
    ["hheight"] = "st_move.png",
    ["hipheight"] = "st_move.png",
    ["hitbox"] = "st_box.png",
    ["hitboxes"] = "st_box.png",
    ["inspect"] = "st_user-x.png",
    ["jd"] = "st_user-x.png",
    ["joindate"] = "st_user-x.png",
    ["jp"] = "st_move.png",
    ["jpower"] = "st_move.png",
    ["jumppower"] = "st_move.png",
    ["lay"] = "st_person-standing.png",
    ["laydown"] = "st_person-standing.png",
    ["light"] = "st_lightbulb.png",
    ["lockworkspace"] = "st_snowflake.png",
    ["lockws"] = "st_snowflake.png",
    ["loopanim"] = "st_person-standing.png",
    ["loopanimation"] = "st_person-standing.png",
    ["lowgraphics"] = "st_wrench.png",
    ["maxslopeangle"] = "st_move.png",
    ["maxzoom"] = "st_camera.png",
    ["minzoom"] = "st_camera.png",
    ["mousesensitivity"] = "st_shirt.png",
    ["ms"] = "st_shirt.png",
    ["msa"] = "st_move.png",
    ["muteallvcs"] = "st_mic.png",
    ["muteallvoices"] = "st_mic.png",
    ["naked"] = "st_scan-eye.png",
    ["night"] = "st_moon.png",
    ["nilchar"] = "st_refresh-cw.png",
    ["noanim"] = "st_person-standing.png",
    ["noarms"] = "st_box.png",
    ["noautorotate"] = "st_snowflake.png",
    ["nobgui"] = "st_scan-eye.png",
    ["nobillboardgui"] = "st_scan-eye.png",
    ["nocdlimits"] = "st_crosshair.png",
    ["noclickdetectorlimits"] = "st_crosshair.png",
    ["noface"] = "st_scan-eye.png",
    ["nofog"] = "st_lightbulb.png",
    ["noglobalshadows"] = "st_cloud-fog.png",
    ["nogshadows"] = "st_cloud-fog.png",
    ["nohats"] = "st_shirt.png",
    ["nolegs"] = "st_box.png",
    ["nolight"] = "st_lightbulb.png",
    ["nolimbs"] = "st_box.png",
    ["nolocate"] = "st_scan-eye.png",
    ["noname"] = "st_scan-eye.png",
    ["nonilchar"] = "st_refresh-cw.png",
    ["noplatformstand"] = "st_snowflake.png",
    ["nopplimits"] = "st_scan-eye.png",
    ["noprompts"] = "st_scan-eye.png",
    ["noproximitypromptlimits"] = "st_scan-eye.png",
    ["nopurchaseprompts"] = "st_scan-eye.png",
    ["norender"] = "st_scan-eye.png",
    ["noroot"] = "st_box.png",
    ["norotate"] = "st_snowflake.png",
    ["nosit"] = "st_person-standing.png",
    ["nostun"] = "st_snowflake.png",
    ["noterrain"] = "st_trash-2.png",
    ["notifyping"] = "st_user-x.png",
    ["notifypos"] = "st_person-standing.png",
    ["notifyposition"] = "st_person-standing.png",
    ["notools"] = "st_shirt.png",
    ["offset"] = "st_move.png",
    ["ping"] = "st_user-x.png",
    ["platformstand"] = "st_snowflake.png",
    ["pm"] = "st_terminal.png",
    ["ptp"] = "st_move.png",
    ["pulsetp"] = "st_move.png",
    ["rarms"] = "st_box.png",
    ["re"] = "st_refresh-cw.png",
    ["reanim"] = "st_person-standing.png",
    ["rec"] = "st_camera.png",
    ["record"] = "st_camera.png",
    ["refresh"] = "st_refresh-cw.png",
    ["refreshanim"] = "st_person-standing.png",
    ["refreshanimation"] = "st_person-standing.png",
    ["refreshanimations"] = "st_person-standing.png",
    ["refreshanims"] = "st_person-standing.png",
    ["remove"] = "st_trash-2.png",
    ["removeads"] = "st_trash-2.png",
    ["removecdlimits"] = "st_crosshair.png",
    ["removeclass"] = "st_trash-2.png",
    ["removeclassname"] = "st_trash-2.png",
    ["removeface"] = "st_scan-eye.png",
    ["removeforces"] = "st_snowflake.png",
    ["removepplimits"] = "st_scan-eye.png",
    ["removeroot"] = "st_box.png",
    ["removeterrain"] = "st_trash-2.png",
    ["removetools"] = "st_shirt.png",
    ["removevelocity"] = "st_snowflake.png",
    ["render"] = "st_scan-eye.png",
    ["replaceroot"] = "st_box.png",
    ["replacerootpart"] = "st_box.png",
    ["reset"] = "st_refresh-cw.png",
    ["respawn"] = "st_scan-eye.png",
    ["rhats"] = "st_shirt.png",
    ["rlegs"] = "st_box.png",
    ["rlimbs"] = "st_box.png",
    ["rohg"] = "st_scan-eye.png",
    ["rroot"] = "st_box.png",
    ["rterrain"] = "st_trash-2.png",
    ["rtools"] = "st_shirt.png",
    ["say"] = "st_shirt.png",
    ["scare"] = "st_person-standing.png",
    ["screenshot"] = "st_camera.png",
    ["scrnshot"] = "st_camera.png",
    ["showprompts"] = "st_scan-eye.png",
    ["showpurchaseprompts"] = "st_scan-eye.png",
    ["sit"] = "st_person-standing.png",
    ["sitwalk"] = "st_person-standing.png",
    ["spook"] = "st_person-standing.png",
    ["stopanim"] = "st_person-standing.png",
    ["stopanimations"] = "st_person-standing.png",
    ["stopanims"] = "st_person-standing.png",
    ["strengthen"] = "st_box.png",
    ["stun"] = "st_snowflake.png",
    ["tgoto"] = "st_move.png",
    ["tgotocam"] = "st_camera.png",
    ["tgotomodel"] = "st_move.png",
    ["tgotopart"] = "st_move.png",
    ["tgpc"] = "st_move.png",
    ["thaw"] = "st_snowflake.png",
    ["thirdp"] = "st_camera.png",
    ["thru"] = "st_move.png",
    ["tocam"] = "st_camera.png",
    ["togglefs"] = "st_wrench.png",
    ["togglefullscreen"] = "st_wrench.png",
    ["tomodel"] = "st_move.png",
    ["topart"] = "st_move.png",
    ["tppos"] = "st_person-standing.png",
    ["tpposition"] = "st_person-standing.png",
    ["trip"] = "st_person-standing.png",
    ["tspeed"] = "st_move.png",
    ["tto"] = "st_move.png",
    ["ttocam"] = "st_camera.png",
    ["ttomodel"] = "st_move.png",
    ["ttopart"] = "st_move.png",
    ["ttppos"] = "st_person-standing.png",
    ["tweengoto"] = "st_move.png",
    ["tweengotocam"] = "st_camera.png",
    ["tweengotocamera"] = "st_camera.png",
    ["tweengotomodel"] = "st_move.png",
    ["tweengotopart"] = "st_move.png",
    ["tweengotopartclass"] = "st_move.png",
    ["tweenspeed"] = "st_move.png",
    ["tweento"] = "st_move.png",
    ["tweentpposition"] = "st_person-standing.png",
    ["unanchor"] = "st_anchor.png",
    ["unbgui"] = "st_scan-eye.png",
    ["unbillboardgui"] = "st_scan-eye.png",
    ["unctrllock"] = "st_lock.png",
    ["unequiptools"] = "st_shirt.png",
    ["unflyfling"] = "st_move.png",
    ["unfr"] = "st_snowflake.png",
    ["unfreeze"] = "st_snowflake.png",
    ["unfreezeanims"] = "st_person-standing.png",
    ["unfriend"] = "st_user-x.png",
    ["unglobalshadows"] = "st_cloud-fog.png",
    ["ungshadows"] = "st_cloud-fog.png",
    ["unhitboxes"] = "st_box.png",
    ["unlight"] = "st_lightbulb.png",
    ["unlocate"] = "st_scan-eye.png",
    ["unlockworkspace"] = "st_snowflake.png",
    ["unlockws"] = "st_snowflake.png",
    ["unmuteallvcs"] = "st_mic.png",
    ["unmuteallvoices"] = "st_mic.png",
    ["unnilchar"] = "st_refresh-cw.png",
    ["unnorotate"] = "st_snowflake.png",
    ["unnosit"] = "st_person-standing.png",
    ["unplatformstand"] = "st_snowflake.png",
    ["unstrengthen"] = "st_box.png",
    ["unstun"] = "st_snowflake.png",
    ["unweaken"] = "st_box.png",
    ["usetools"] = "st_shirt.png",
    ["vehiclegoto"] = "st_move.png",
    ["vehicletp"] = "st_move.png",
    ["vgoto"] = "st_move.png",
    ["vtp"] = "st_move.png",
    ["walkonwalls"] = "st_move.png",
    ["walktopos"] = "st_move.png",
    ["walktoposition"] = "st_move.png",
    ["wallwalk"] = "st_move.png",
    ["weaken"] = "st_box.png",
    ["whisper"] = "st_terminal.png",
}

-- Why this command is near the top. Only for the ones that earned it: a
-- count on every row would be noise.
function CmdBar.cmdTagFor(cmd)
    local n = Usage.count("cmds", cmd)
    if n >= 5 then return "most used", true end
    if n > 0 then return "used " .. n .. (n == 1 and " time" or " times"), false end
    return nil
end

function CmdBar.glyphFor(cmd)
    local key = (cmd == "goto") and "goto_" or cmd
    return UI.icon(CmdBar.glyphs[key] or "st_zap.png")
end

-- ── Alias grouping ──────────────────────────────────────────────────────
-- commandList is a flat list of every alias, so "rj" and "rejoin" used to
-- render as two unrelated rows. Group them: one row per command, canonical
-- name as the label, the rest shown as muted aliases. Typing any alias still
-- matches, and completing inserts the canonical name.
CmdBar.aliasGroups = {
    { "fly" }, { "unfly" },
    { "noclip" }, { "clip" },
    { "walkspeed", "ws" }, { "jump" }, { "infjump" },
    { "goto", "tp", "to" },
    { "view" }, { "unview" }, { "fov" },
    { "spin" }, { "unspin" },
    { "orbit" }, { "unorbit" },
    { "bang" }, { "unbang" },
    { "headless" }, { "unheadless", "noheadless" },
    { "rejoin", "rj" }, { "serverhop", "shop", "hop" },
    { "savepos" }, { "topos" }, { "clicktp" },
    { "settime", "tod" }, { "extendbaseplate", "exbp" }, { "fpsboost" },
    { "prefix", "pfx" }, { "antiafk", "antidle" },
    { "bypassvc", "bvc", "rvc" },
    { "cmdbarkeybind", "barkeybind", "cmdbarbind", "barbind" },
    { "uhub" }, { "infyield", "ify" }, { "uesp" }, { "emotes" }, { "sbroken" },
    { "showstats", "stats" }, { "cmds", "commands" },
    { "info", "about", "version", "ver" },
    { "esp", "espmenu", "chams" }, { "unesp", "noesp" },
    { "scripthub", "hub", "scripts" }, { "resume", "runlast" },
    { "mutevc", "mute", "vcmute" }, { "unmutevc", "unmute", "vcunmute" },
    { "activity", "act", "watch" },
    { "notify" }, { "unotify", "unnotify", "notifyoff" },
    { "unexecute", "unexec", "unload" },
    { "headsit", "hs" }, { "unheadsit", "uhs", "stopheadsit" },
    { "backpack", "bp" }, { "unbackpack", "ubp", "stopbackpack" },
    { "drag" }, { "undrag", "udr", "stopdrag" },
    { "attach" }, { "unattach", "ua", "detach" },
    { "stare", "lookat" }, { "unstare", "stopstare" },
    { "copydance", "cd" }, { "uncopydance", "ucd", "stopcopydance" },
    { "stopall" },
    { "profile", "prof", "whois", "playerinfo", "pinfo" },
    { "unprofile", "closeprofile" },
    { "quickjoin", "qj", "join" },
    { "guide", "help", "tutorial" },
    { "tour", "walkthrough" },
    { "keepuhub", "autoexec", "persist" },
    -- imported from Infinite Yield
    { "age" },
    { "ambient" },
    { "anchor" },
    { "animspeed" },
    { "antilag", "boostfps", "lowgraphics" },
    { "appearanceid", "aid" },
    { "blockhats" },
    { "blockhead" },
    { "blocktool" },
    { "breakvelocity" },
    { "brightness" },
    { "bringpart" },
    { "bringpartclass", "bpc" },
    { "camdistance" },
    { "chardeleteclass", "cdc", "chardeleteclassname", "charremoveclass", "charremoveclassname" },
    { "chat", "say" },
    { "chatage" },
    { "chatjoindate", "cjd" },
    { "clearcharappearance", "clearchar", "clrchar" },
    { "clearhats", "cleanhats" },
    { "clickdelete" },
    { "copyanimationid", "copyanimid", "copyemoteid" },
    { "copyappearanceid", "caid" },
    { "copyposition", "copypos" },
    { "copytools" },
    { "creeper" },
    { "ctrllock" },
    { "day" },
    { "delete", "remove" },
    { "deleteclass", "dc", "deleteclassname", "removeclass", "removeclassname" },
    { "deletehats", "nohats", "rhats" },
    { "deleteinvisparts", "deleteinvisibleparts", "dip" },
    { "deleteselectedtool", "dst" },
    { "deletevelocity", "dv", "removeforces", "removevelocity" },
    { "destroyheight", "dh" },
    { "disablestate" },
    { "drophats", "drophat" },
    { "droppabletools" },
    { "droptools", "droptool" },
    { "enablestate" },
    { "equiptools" },
    { "firstp" },
    { "freeze", "fr" },
    { "freezeanims" },
    { "friend" },
    { "fullbright", "fb", "fullbrightness" },
    { "getposition", "getpos", "notifypos", "notifyposition" },
    { "globalshadows", "gshadows" },
    { "gotocamera", "gotocam", "tocam" },
    { "gotomodel", "tomodel" },
    { "gotopart", "topart" },
    { "gotopartclass", "gpc" },
    { "gotopartdelay" },
    { "grippos" },
    { "headsize" },
    { "headthrow" },
    { "hipheight", "hheight" },
    { "hitbox" },
    { "hitboxes" },
    { "inspect", "examine" },
    { "joindate", "jd" },
    { "jpower", "jp", "jumppower" },
    { "lay", "laydown" },
    { "light" },
    { "lockws", "lockworkspace" },
    { "loopanimation", "loopanim" },
    { "maxslopeangle", "msa" },
    { "maxzoom" },
    { "minzoom" },
    { "mousesensitivity", "ms" },
    { "muteallvoices", "muteallvcs" },
    { "naked" },
    { "night" },
    { "nilchar" },
    { "noanim" },
    { "noarms", "rarms" },
    { "nobgui", "nobillboardgui", "noname", "rohg", "unbgui", "unbillboardgui" },
    { "noclickdetectorlimits", "nocdlimits", "removecdlimits" },
    { "noface", "removeface" },
    { "nofog" },
    { "nolegs", "rlegs" },
    { "nolimbs", "rlimbs" },
    { "nolocate", "unlocate" },
    { "noprompts", "nopurchaseprompts" },
    { "noproximitypromptlimits", "nopplimits", "removepplimits" },
    { "norender" },
    { "noroot", "removeroot", "rroot" },
    { "norotate", "noautorotate" },
    { "nosit" },
    { "notifyping", "ping" },
    { "notools", "clrtools", "deletetools", "dtools", "removetools", "rtools" },
    { "offset" },
    { "pulsetp", "ptp" },
    { "reanim" },
    { "rec", "record" },
    { "refresh", "re" },
    { "refreshanimations", "refreshanim", "refreshanimation", "refreshanims" },
    { "removeads", "adblock" },
    { "removeterrain", "noterrain", "rterrain" },
    { "render" },
    { "replaceroot", "replacerootpart" },
    { "reset" },
    { "respawn" },
    { "scare", "spook" },
    { "screenshot", "scrnshot" },
    { "showprompts", "showpurchaseprompts" },
    { "sit" },
    { "sitwalk" },
    { "stopanimations", "stopanim", "stopanims" },
    { "strengthen" },
    { "stun", "platformstand" },
    { "thaw", "unfr", "unfreeze" },
    { "thirdp" },
    { "thru" },
    { "togglefs", "togglefullscreen" },
    { "tpposition", "tppos" },
    { "trip" },
    { "tweengoto", "tgoto", "tto", "tweento" },
    { "tweengotocamera", "tgotocam", "ttocam", "tweengotocam" },
    { "tweengotomodel", "tgotomodel", "ttomodel" },
    { "tweengotopart", "tgotopart", "ttopart" },
    { "tweengotopartclass", "tgpc" },
    { "tweenspeed", "tspeed" },
    { "tweentpposition", "ttppos" },
    { "unanchor" },
    { "unctrllock" },
    { "unequiptools" },
    { "unflyfling" },
    { "unfreezeanims" },
    { "unfriend" },
    { "unglobalshadows", "noglobalshadows", "nogshadows", "ungshadows" },
    { "unhitboxes" },
    { "unlight", "nolight" },
    { "unlockws", "unlockworkspace" },
    { "unmuteallvoices", "unmuteallvcs" },
    { "unnilchar", "nonilchar" },
    { "unnorotate", "autorotate" },
    { "unnosit" },
    { "unstun", "noplatformstand", "nostun", "unplatformstand" },
    { "unweaken", "unstrengthen" },
    { "usetools" },
    { "vehiclegoto", "vehicletp", "vgoto", "vtp" },
    { "walktopos", "walktoposition" },
    { "wallwalk", "walkonwalls" },
    { "weaken" },
    { "whisper", "pm" },
}

-- alias -> group index, built once.
CmdBar.aliasOf = {}
for gi, g in ipairs(CmdBar.aliasGroups) do
    for _, a in ipairs(g) do CmdBar.aliasOf[a] = gi end
end

function CmdBar.build()
    local h = 50 + CmdBar.MAX_ROWS * CmdBar.ROW_H + 14
    local clip, p = UI.makeDrawer("CmdBarPanel", UI.EXP_W, h, Bar.gui)
    CmdBar.clip, CmdBar.panel = clip, p
    CmdBar.fullH = h

    local prompt = Instance.new("ImageLabel")
    prompt.AnchorPoint = Vector2.new(0, 0.5)
    prompt.Position = UDim2.new(0, 14, 0, 26)
    prompt.Size = UDim2.fromOffset(16, 16)
    prompt.BackgroundTransparency = 1
    prompt.Image = UI.icon("st_terminal.png")
    prompt.ImageColor3 = UI.accent
    prompt.ZIndex = 42
    prompt.Parent = p

    local box = Instance.new("TextBox")
    box.Name = "Input"
    box.AnchorPoint = Vector2.new(0, 0.5)
    box.Position = UDim2.new(0, 36, 0, 26)
    box.Size = UDim2.new(1, -50, 0, 22)
    box.BackgroundTransparency = 1
    box.Text = ""
    box.PlaceholderText = "type a command"
    box.PlaceholderColor3 = UI.textMuted
    box.TextColor3 = UI.textPrimary
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.TextSize = UI.T_SUB + 2
    box.ClearTextOnFocus = false
    box.ZIndex = 42
    box.Parent = p
    UI.applyFont(box, Enum.FontWeight.SemiBold)
    CmdBar.box = box

    -- Ghost argument: sits where the argument would go, at low opacity, so a
    -- command that takes one says so before you guess. It shows the value the
    -- command actually falls back to, which doubles as the answer to "what is
    -- a sensible number here".
    local ghost = Instance.new("TextLabel")
    ghost.Name = "ArgHint"
    ghost.AnchorPoint = Vector2.new(0, 0.5)
    ghost.Position = UDim2.new(0, 36, 0, 26)
    ghost.Size = UDim2.new(0, 200, 0, 22)
    ghost.BackgroundTransparency = 1
    ghost.Text = ""
    ghost.TextColor3 = UI.textMuted
    ghost.TextTransparency = 0.55
    ghost.TextXAlignment = Enum.TextXAlignment.Left
    ghost.TextSize = box.TextSize
    ghost.Visible = false
    ghost.ZIndex = 41                  -- under the real text, never over it
    ghost.Parent = p
    UI.applyFont(ghost, Enum.FontWeight.SemiBold)
    CmdBar.ghost = ghost

    -- Inline avatar: sits immediately after the typed text once the argument
    -- resolves to a real player, so "goto wiwi" shows whose face you mean
    -- before you commit. Positioned by measuring the text, since a TextBox
    -- cannot contain an image.
    local inlineAv = Instance.new("ImageLabel")
    inlineAv.Name = "InlineAvatar"
    inlineAv.AnchorPoint = Vector2.new(0, 0.5)
    inlineAv.Position = UDim2.new(0, 36, 0, 26)
    inlineAv.Size = UDim2.fromOffset(20, 20)
    inlineAv.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    inlineAv.BackgroundTransparency = 1
    inlineAv.ImageTransparency = 1
    inlineAv.ZIndex = 43
    inlineAv.Parent = p
    -- Kept: a headshot wants a circle, a place icon wants a square, and one
    -- ImageLabel serves both.
    CmdBar.inlineCorner = Instance.new("UICorner", inlineAv)
    CmdBar.inlineCorner.CornerRadius = UDim.new(1, 0)
    CmdBar.inlineAv = inlineAv

    local rule = Instance.new("Frame")
    rule.Position = UDim2.new(0, 14, 0, 42)
    rule.Size = UDim2.new(1, -28, 0, 1)
    rule.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    rule.BackgroundTransparency = 0.88
    rule.BorderSizePixel = 0
    rule.ZIndex = 42
    rule.Parent = p

    local list = Instance.new("ScrollingFrame")
    list.Name = "List"
    list.Position = UDim2.new(0, 8, 0, 50)
    list.Size = UDim2.new(1, -16, 1, -58)
    list.BackgroundTransparency = 1
    list.BorderSizePixel = 0
    list.ScrollBarThickness = 3
    list.ScrollBarImageColor3 = UI.accent
    list.ScrollBarImageTransparency = 0.4
    list.CanvasSize = UDim2.new(0, 0, 0, 0)
    list.ZIndex = 42
    list.Parent = p
    CmdBar.list = list
end

function CmdBar.clearRows()
    for _, r in ipairs(CmdBar.rows) do pcall(function() r:Destroy() end) end
    CmdBar.rows = {}
end

-- One suggestion row. `player` is nil for plain command rows.
function CmdBar.makeRow(index, text, cmd, player, aliases, desc, game, token, words, dim)
    local isPlayer = player ~= nil
    local rowH = (isPlayer or game or token) and CmdBar.ROW_H_PLAYER or CmdBar.ROW_H
    local y = 0
    for _, r in ipairs(CmdBar.rows) do y = y + r.Size.Y.Offset + 2 end

    local row = Instance.new("TextButton")
    row.Name = "Row" .. index
    row.Position = UDim2.new(0, 0, 0, y + 4)
    row.Size = UDim2.new(1, 0, 0, rowH)
    row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    row.BackgroundTransparency = 1
    row.AutoButtonColor = false
    row.Text = ""
    row.BorderSizePixel = 0
    row.ZIndex = 43
    row.Parent = CmdBar.list
    local rc = Instance.new("UICorner", row)
    rc.CornerRadius = UDim.new(0, 8)

    if token then
        -- Token rows borrow the player-row shape so the list does not change
        -- rhythm halfway down: same tile, a glyph instead of a face.
        local tile = Instance.new("Frame")
        tile.AnchorPoint = Vector2.new(0, 0.5)
        tile.Position = UDim2.new(0, 8, 0.5, 0)
        tile.Size = UDim2.fromOffset(32, 32)
        tile.BackgroundColor3 = UI.accent
        tile.BackgroundTransparency = 0.82
        tile.BorderSizePixel = 0
        tile.ZIndex = 44
        tile.Parent = row
        Instance.new("UICorner", tile).CornerRadius = UDim.new(1, 0)

        local gl = Instance.new("ImageLabel")
        gl.AnchorPoint = Vector2.new(0.5, 0.5)
        gl.Position = UDim2.fromScale(0.5, 0.5)
        gl.Size = UDim2.fromOffset(17, 17)
        gl.BackgroundTransparency = 1
        gl.Image = UI.icon(token.icon)
        gl.ImageColor3 = UI.accent
        gl.ZIndex = 45
        gl.Parent = tile

        -- The label says what it does; the spellings say what to type. Both,
        -- because "All players" does not tell you the word is "all".
        local words = words or PlayerTokens.spellings(token.key)
        local tLabel, tDesc = PlayerTokens.textFor(cmd, token)
        local nm = Instance.new("TextLabel")
        nm.Position = UDim2.new(0, 50, 0, 7)
        nm.Size = UDim2.new(1, -60, 0, 18)
        nm.BackgroundTransparency = 1
        nm.RichText = true
        nm.Text = tLabel
            .. '   <font size="11" color="#7c7f8c">'
            .. table.concat(words, "  ") .. "</font>"
        nm.TextColor3 = Color3.fromRGB(238, 239, 244)
        nm.TextXAlignment = Enum.TextXAlignment.Left
        nm.TextSize = UI.T_ROW
        nm.TextTruncate = Enum.TextTruncate.AtEnd
        nm.ZIndex = 44
        nm.Parent = row
        UI.applyFont(nm, Enum.FontWeight.SemiBold)

        local ds = Instance.new("TextLabel")
        ds.Position = UDim2.new(0, 50, 0, 26)
        ds.Size = UDim2.new(1, -60, 0, 15)
        ds.BackgroundTransparency = 1
        ds.Text = tDesc
        ds.TextColor3 = UI.textMuted
        ds.TextXAlignment = Enum.TextXAlignment.Left
        ds.TextSize = UI.T_SMALL
        ds.TextTruncate = Enum.TextTruncate.AtEnd
        ds.ZIndex = 44
        ds.Parent = row
        UI.applyFont(ds, Enum.FontWeight.Regular)
    elseif game then
        -- Square, lightly rounded: a place icon is not a face, and rounding
        -- it to a circle reads as one at this size.
        local th = Instance.new("ImageLabel")
        th.AnchorPoint = Vector2.new(0, 0.5)
        th.Position = UDim2.new(0, 8, 0.5, 0)
        th.Size = UDim2.fromOffset(32, 32)
        th.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        th.BackgroundTransparency = 0.4
        th.ZIndex = 44
        th.Parent = row
        Instance.new("UICorner", th).CornerRadius = UDim.new(0, 8)
        -- Rows are rebuilt on every keystroke, so the row may be gone by the
        -- time the lookup lands.
        QuickJoin.icon(game, function(img)
            if th and th.Parent then th.Image = img end
        end)

        -- Same treatment as the player rows: the order is deliberate, so
        -- say what it is ordering by.
        local gTag, gHot = QuickJoin.tagFor(game)
        local gTagW = 0
        if gTag then
            local tl = Instance.new("TextLabel")
            tl.AnchorPoint = Vector2.new(1, 0.5)
            tl.Position = UDim2.new(1, -12, 0.5, 0)
            tl.Size = UDim2.fromOffset(96, 16)
            tl.BackgroundTransparency = 1
            tl.Text = gTag
            tl.TextColor3 = gHot and UI.accent or UI.textMuted
            tl.TextXAlignment = Enum.TextXAlignment.Right
            tl.TextSize = UI.T_SMALL
            tl.TextTruncate = Enum.TextTruncate.AtEnd
            tl.ZIndex = 44
            tl.Parent = row
            UI.applyFont(tl, gHot and Enum.FontWeight.SemiBold
                                  or Enum.FontWeight.Regular)
            gTagW = 104
        end

        local nm = Instance.new("TextLabel")
        nm.Position = UDim2.new(0, 50, 0, 7)
        nm.Size = UDim2.new(1, -60 - gTagW, 0, 18)
        nm.BackgroundTransparency = 1
        nm.Text = game.name
        nm.TextColor3 = Color3.fromRGB(238, 239, 244)
        nm.TextXAlignment = Enum.TextXAlignment.Left
        nm.TextSize = UI.T_ROW
        nm.TextTruncate = Enum.TextTruncate.AtEnd
        nm.ZIndex = 44
        nm.Parent = row
        UI.applyFont(nm, Enum.FontWeight.SemiBold)

        local ks = Instance.new("TextLabel")
        ks.Position = UDim2.new(0, 50, 0, 26)
        ks.Size = UDim2.new(1, -60 - gTagW, 0, 15)
        ks.BackgroundTransparency = 1
        ks.Text = table.concat(game.keys, "  \194\183  ")
        ks.TextColor3 = UI.textMuted
        ks.TextXAlignment = Enum.TextXAlignment.Left
        ks.TextSize = UI.T_SMALL
        ks.TextTruncate = Enum.TextTruncate.AtEnd
        ks.ZIndex = 44
        ks.Parent = row
        UI.applyFont(ks, Enum.FontWeight.Regular)
    elseif isPlayer then
        local hs = Instance.new("ImageLabel")
        hs.AnchorPoint = Vector2.new(0, 0.5)
        hs.Position = UDim2.new(0, 8, 0.5, 0)
        hs.Size = UDim2.fromOffset(32, 32)
        hs.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        hs.BackgroundTransparency = 0.4
        hs.ZIndex = 44
        hs.Parent = row
        local hc = Instance.new("UICorner", hs)
        hc.CornerRadius = UDim.new(1, 0)
        local img = UI.headshotFor(player.name)
        if img ~= "" then hs.Image = img end

        -- Says WHY this row sits where it does. Without it a friend at the
        -- top of the list just looks like an arbitrary shuffle.
        local tag, isFriend = CmdBar.tagFor(player.name)
        local tagW = 0
        if tag then
            local tl = Instance.new("TextLabel")
            tl.AnchorPoint = Vector2.new(1, 0.5)
            tl.Position = UDim2.new(1, -12, 0.5, 0)
            tl.Size = UDim2.fromOffset(88, 16)
            tl.BackgroundTransparency = 1
            tl.Text = tag
            tl.TextColor3 = isFriend and UI.accent or UI.textMuted
            tl.TextXAlignment = Enum.TextXAlignment.Right
            tl.TextSize = UI.T_SMALL
            tl.TextTruncate = Enum.TextTruncate.AtEnd
            tl.ZIndex = 44
            tl.Parent = row
            UI.applyFont(tl, isFriend and Enum.FontWeight.SemiBold
                                      or Enum.FontWeight.Regular)
            tagW = 96      -- the name has to yield this much or they collide
        end

        local nm = Instance.new("TextLabel")
        nm.Position = UDim2.new(0, 50, 0, 7)
        nm.Size = UDim2.new(1, -60 - tagW, 0, 18)
        nm.BackgroundTransparency = 1
        nm.Text = player.display
        nm.TextColor3 = Color3.fromRGB(238, 239, 244)
        nm.TextXAlignment = Enum.TextXAlignment.Left
        nm.TextSize = UI.T_ROW
        nm.TextTruncate = Enum.TextTruncate.AtEnd
        nm.ZIndex = 44
        nm.Parent = row
        UI.applyFont(nm, Enum.FontWeight.SemiBold)

        local un = Instance.new("TextLabel")
        un.Position = UDim2.new(0, 50, 0, 26)
        un.Size = UDim2.new(1, -60 - tagW, 0, 15)
        un.BackgroundTransparency = 1
        un.Text = "@" .. player.name
        un.TextColor3 = UI.textMuted
        un.TextXAlignment = Enum.TextXAlignment.Left
        un.TextSize = UI.T_SMALL
        un.TextTruncate = Enum.TextTruncate.AtEnd
        un.ZIndex = 44
        un.Parent = row
        UI.applyFont(un, Enum.FontWeight.Regular)
    else
        local g = Instance.new("ImageLabel")
        g.AnchorPoint = Vector2.new(0, 0.5)
        g.Position = UDim2.new(0, 10, 0.5, 0)
        g.Size = UDim2.fromOffset(16, 16)
        g.BackgroundTransparency = 1
        g.Image = CmdBar.glyphFor(cmd)
        g.ImageColor3 = Color3.fromRGB(200, 202, 212)
        g.ZIndex = 44
        g.Parent = row

        local nm = Instance.new("TextLabel")
        nm.AnchorPoint = Vector2.new(0, 0.5)
        nm.Position = UDim2.new(0, 38, 0.5, 0)
        nm.Size = UDim2.new(1, -48, 1, 0)
        nm.BackgroundTransparency = 1
        nm.RichText = true
        nm.Text = text .. (aliases
            and ('   <font size="11" color="#7c7f8c">' .. aliases .. '</font>')
            or "")

        local cTag, cHot = CmdBar.cmdTagFor(cmd)
        if cTag then
            local tl = Instance.new("TextLabel")
            tl.AnchorPoint = Vector2.new(1, 0.5)
            tl.Position = UDim2.new(1, -10, 0.5, 0)
            tl.Size = UDim2.fromOffset(84, 15)
            tl.BackgroundTransparency = 1
            tl.Text = cTag
            tl.TextColor3 = cHot and UI.accent or UI.textMuted
            tl.TextXAlignment = Enum.TextXAlignment.Right
            tl.TextSize = UI.T_EYEBROW
            tl.TextTruncate = Enum.TextTruncate.AtEnd
            tl.ZIndex = 44
            tl.Parent = row
            UI.applyFont(tl, cHot and Enum.FontWeight.Bold
                                  or Enum.FontWeight.Regular)
        end

        if desc and desc ~= "" then
            local dl = Instance.new("TextLabel")
            dl.AnchorPoint = Vector2.new(1, 0.5)
            dl.Position = UDim2.new(1, cTag and -98 or -10, 0.5, 0)
            dl.Size = UDim2.new(0.52, cTag and -88 or 0, 1, 0)
            dl.BackgroundTransparency = 1
            dl.Text = desc
            dl.TextColor3 = Color3.fromRGB(122, 125, 136)
            dl.TextXAlignment = Enum.TextXAlignment.Right
            dl.TextSize = UI.T_SMALL
            dl.TextTruncate = Enum.TextTruncate.AtEnd
            dl.ZIndex = 44
            dl.Parent = row
            UI.applyFont(dl, Enum.FontWeight.Regular)
            nm.Size = UDim2.new(0.48, -48, 1, 0)   -- yield room for it
        end
        nm.TextColor3 = Color3.fromRGB(232, 233, 238)
        nm.TextXAlignment = Enum.TextXAlignment.Left
        nm.TextSize = UI.T_ROW
        nm.TextTruncate = Enum.TextTruncate.AtEnd
        nm.ZIndex = 44
        nm.Parent = row
        UI.applyFont(nm, Enum.FontWeight.Medium)
    end

    -- A filter that cannot improve on where you already are reads as
    -- unavailable rather than being hidden: hiding it would leave you
    -- wondering where it went, and the note explains why it is greyed.
    if dim then
        for _, d in ipairs(row:GetDescendants()) do
            if d:IsA("TextLabel") then d.TextTransparency = 0.55
            elseif d:IsA("ImageLabel") then d.ImageTransparency = 0.6
            elseif d:IsA("Frame") and d.Name ~= "Rail" then
                d.BackgroundTransparency = math.min(1, d.BackgroundTransparency + 0.35)
            end
        end
    end

    row.MouseEnter:Connect(function()
        CmdBar.selected = index
        CmdBar.paintSelection()
    end)
    row.MouseButton1Click:Connect(function()
        CmdBar.selected = index
        CmdBar.accept()
        -- A click means "run this". Commands that still need a player
        -- argument just fill in and wait for the second pick.
        if not (player == nil and game == nil and token == nil
                and commandNeedsPlayer(cmd)) then
            CmdBar.execute()
        else
            pcall(function() CmdBar.box:CaptureFocus() end)
        end
    end)

    table.insert(CmdBar.rows, row)
    return row
end

function CmdBar.paintSelection()
    for i, r in ipairs(CmdBar.rows) do
        local on = (i == CmdBar.selected)
        TweenService:Create(r, TweenInfo.new(0.12), {
            BackgroundColor3 = on and UI.accent or Color3.fromRGB(255, 255, 255),
            BackgroundTransparency = on and 0.86 or 1,
        }):Play()
    end
end

-- matches: array of { text = string, cmd = string, player = table|nil }
function CmdBar.render(matches)
    CmdBar.clearRows()
    CmdBar.matches = matches
    CmdBar.selected = 1
    local total = 8
    for i, m in ipairs(matches) do
        if i > CmdBar.MAX_ROWS then break end
        local r = CmdBar.makeRow(i, m.text, m.cmd, m.player, m.aliases, m.desc, m.game, m.token, m.words, m.dim)
        total = total + r.Size.Y.Offset + 2
    end
    CmdBar.list.CanvasSize = UDim2.new(0, 0, 0, total)
    CmdBar.paintSelection()
end

-- Fill the box from the highlighted row. Records the exact resulting text in
-- CmdBar.completedText so FocusLost can tell "just completed" from "user
-- typed this" WITHOUT a boolean flag -- the Text-changed signal fires on this
-- very assignment, so any flag set here is immediately clobbered.
function CmdBar.accept()
    local m = CmdBar.matches[CmdBar.selected]
    if not m then return false end
    local t
    if m.token then
        local parts = {}
        for w in (CmdBar.box.Text or ""):gmatch("%S+") do parts[#parts + 1] = w end
        t = (parts[1] or m.cmd) .. " " .. m.token.key
    elseif m.game then
        local parts = {}
        for w in (CmdBar.box.Text or ""):gmatch("%S+") do parts[#parts + 1] = w end
        t = (parts[1] or m.cmd) .. " " .. m.game.keys[1]
    elseif m.player then
        local parts = {}
        for w in (CmdBar.box.Text or ""):gmatch("%S+") do parts[#parts + 1] = w end
        local head = parts[1] or m.cmd
        -- keep anything typed past the target, so completing the name in
        -- "whisper wi hey there" does not discard "hey there"
        local tail = {}
        for i = 3, #parts do tail[#tail + 1] = parts[i] end
        t = head .. " " .. m.player.name
        if #tail > 0 then t = t .. " " .. table.concat(tail, " ") end
    else
        t = m.cmd
        if commandNeedsPlayer(m.cmd) or commandNeedsGame(m.cmd) then t = t .. " " end
    end
    CmdBar.box.Text = t
    CmdBar.box.CursorPosition = #t + 1
    CmdBar.completedText = t
    return true
end

-- Is this token a real command (canonical name or any alias)?
function CmdBar.isCommand(w)
    w = (w or ""):lower()
    if w == "" then return false end
    if CmdBar.aliasOf[w] then return true end
    for _, c in ipairs(commandList) do
        if c == w then return true end
    end
    return false
end

function CmdBar.isGameName(w)
    return QuickJoin.exact(w) ~= nil
end

-- Does this resolve to someone actually in the server? Accepts a username or
-- a display name, case-insensitively, so a completed target counts as ready
-- to run and does not demand a third Enter.
function CmdBar.isPlayerName(w, cmd)
    w = (w or ""):lower()
    if w == "" then return false end
    -- A token is as resolved as a name: "mutevc all" should run on Enter.
    if PlayerTokens.resolve(w, cmd) then return true end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower() == w or p.DisplayName:lower() == w then return true end
    end
    return false
end

-- COMPLETE or RUN? Pure decision, no side effects, so the whole Enter
-- behaviour is testable without Roblox. Deliberately does NOT consider
-- "are there suggestions visible" -- that is true whenever the first token
-- matches, which is what previously clobbered typed arguments.
--   ""            -> "empty"
--   "fl"          -> "complete"   still typing the command name
--   "fly"         -> "run"        known command, no player needed
--   "fly 100"     -> "run"        argument already supplied
--   "goto"        -> "complete"   needs a target
--   "goto Ang"    -> "complete"   partial target
--   "goto Angx"   -> "run"        resolves to a real player
function CmdBar.decide(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return "empty" end

    local parts = {}
    for w in text:gmatch("%S+") do parts[#parts + 1] = w end
    local head = (parts[1] or ""):lower()

    if not CmdBar.isCommand(head) then return "complete" end
    if commandNeedsServer(head) then
        -- Bare "!shop" is valid -- it means any server -- so an empty
        -- argument runs rather than waiting for one.
        if #parts < 2 then return "run" end
        if not ServerTokens.resolve(parts[2]) then return "complete" end
        return "run"
    end
    if commandNeedsGame(head) then
        if #parts < 2 then return "complete" end
        if not CmdBar.isGameName(parts[2]) then return "complete" end
        return "run"
    end
    if not commandNeedsPlayer(head) then return "run" end

    -- Player commands: ONLY token 2 is the target. Everything after it is
    -- payload (whisper <player> <message...>), so it must not be fed to the
    -- name test -- that is what used to eat the message.
    if #parts < 2 then return "complete" end
    if not CmdBar.isPlayerName(parts[2], head) then return "complete" end
    return "run"
end

-- Run whatever is in the box.
function CmdBar.execute()
    -- Counted here rather than in processCommand: this is the path the
    -- suggestion list exists to serve, and chat-typed commands should not
    -- reorder a list the user never opened.
    do
        local head = (CmdBar.box.Text or ""):match("^%s*(%S+)")
        if head then Usage.bump("cmds", head:lower()) end
    end
    local text = (CmdBar.box.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    CmdBar.completedText = nil
    CmdBar.hide()
    if text ~= "" then
        processCommand(prefix .. text)
    end
end

function CmdBar.show()
    if CmdBar.open then return end
    CmdBar.open = true
    -- Ask before you type, not while you type: the friend lookups are web
    -- calls and the first suggestion list would otherwise rank everyone as
    -- a stranger.
    CmdBar.warmFriends()
    -- One seed per opening: the shuffle for an unused install must not
    -- re-roll on every keystroke.
    CmdBar.shuffleSeed = math.floor(os.clock() * 1000) % 100000 + 1
    -- Claim the top slot; anything already out glides down to make room.
    UI.openDrawerAtY(CmdBar.clip, CmdBar.panel, Cards.slotY(CmdBar.clip))
    Cards.reflow(true)
    task.delay(0.1, function() pcall(function() CmdBar.box:CaptureFocus() end) end)
end

function CmdBar.hide()
    if not CmdBar.open then return end
    CmdBar.open = false
    pcall(function() CmdBar.box:ReleaseFocus() end)
    CmdBar.box.Text = ""
    CmdBar.clearRows()
    CmdBar.inlineFor = nil
    if CmdBar.inlineAv then
        CmdBar.inlineAv.ImageTransparency = 1
        CmdBar.inlineAv.BackgroundTransparency = 1
    end
    UI.closeDrawer(CmdBar.clip, CmdBar.panel)
    Cards.reflow(true)   -- whatever is left rises into the freed slot
end

function CmdBar.toggle()
    if CmdBar.open then CmdBar.hide() else CmdBar.show() end
end

-- Show the avatar of whoever the current argument names, parked right after
-- the text. Measured with the Gotham fallback for the same reason the button
-- widths are -- GetTextSize cannot take a FontFace.
-- Park the ghost argument just past the typed text, measured rather than
-- guessed per character.
function CmdBar.syncHint()
    local g = CmdBar.ghost
    if not g then return end
    local text = CmdBar.box.Text or ""
    local hint = CmdBar.hintFor(text)
    if not hint then g.Visible = false return end

    local function widthOf(s)
        local ok, sz = pcall(function()
            return game:GetService("TextService"):GetTextSize(
                s, CmdBar.box.TextSize, Enum.Font.GothamSemibold, Vector2.new(4000, 100))
        end)
        return (ok and sz) and sz.X or 0
    end

    -- Measured in Gotham because GetTextSize cannot take a FontFace, but the
    -- box renders Manrope, which is narrower. The error grows with the text,
    -- and including the trailing space pushed the hint a full space past the
    -- caret. Measuring the committed text alone lands it on the caret, and
    -- the Gotham overshoot is what leaves the gap after the command.
    local w = widthOf((text:gsub("%s+$", "")))
    g.Position = UDim2.new(0, 36 + math.min(w, UI.EXP_W - 110), 0, 26)
    g.Text = hint
    g.Visible = true
end

function CmdBar.syncInlineAvatar()
    CmdBar.syncHint()
    local av = CmdBar.inlineAv
    if not av then return end
    local text = CmdBar.box.Text or ""
    local parts = {}
    for w in text:gmatch("%S+") do parts[#parts + 1] = w end
    local head, rest = parts[1], parts[2]
    local hasPayload = #parts > 2

    local hit, gameHit
    if head and rest and commandNeedsGame(head:lower()) then
        gameHit = QuickJoin.find(rest)
    end
    if head and rest and commandNeedsPlayer(head:lower()) then
        for _, pl in ipairs(Players:GetPlayers()) do
            local n, d = pl.Name:lower(), pl.DisplayName:lower()
            local r = rest:lower()
            if n == r or d == r or n:sub(1, #r) == r or d:sub(1, #r) == r then
                hit = pl break
            end
        end
    end

    -- One slot, two kinds of subject. The key is what changed-detection
    -- compares, so it has to be unique across both.
    local key, img, round
    if gameHit then
        key, round = "game:" .. tostring(gameHit.id), UDim.new(0, 6)
        -- The icon arrives whenever it arrives; the slot is already sized
        -- and positioned, so it just fills in.
        QuickJoin.icon(gameHit, function(src)
            if CmdBar.inlineFor == key then av.Image = src end
        end)
    elseif hit then
        key, img, round = "user:" .. hit.Name, UI.headshotFor(hit.Name), UDim.new(1, 0)
    end

    if not key then
        if CmdBar.inlineFor ~= nil then
            CmdBar.inlineFor = nil
            TweenService:Create(av, TweenInfo.new(0.12),
                { ImageTransparency = 1, BackgroundTransparency = 1 }):Play()
        end
        return
    end

    -- With no payload the avatar tucks in right after the name; with a
    -- message following it would land on top of that text, so it parks at
    -- the right edge instead.
    if hasPayload then
        av.AnchorPoint = Vector2.new(1, 0.5)
        av.Position = UDim2.new(1, -14, 0, 26)
    else
        local w = 0
        local ok, sz = pcall(function()
            return game:GetService("TextService"):GetTextSize(
                text, CmdBar.box.TextSize, Enum.Font.GothamSemibold, Vector2.new(4000, 100))
        end)
        if ok and sz then w = sz.X end
        av.AnchorPoint = Vector2.new(0, 0.5)
        av.Position = UDim2.new(0, 36 + math.min(w, UI.EXP_W - 110) + 8, 0, 26)
    end

    if CmdBar.inlineFor ~= key then
        CmdBar.inlineFor = key
        if CmdBar.inlineCorner then CmdBar.inlineCorner.CornerRadius = round end
        if img and img ~= "" then av.Image = img
        elseif gameHit then av.Image = "" end   -- cleared until the lookup lands
        TweenService:Create(av, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { ImageTransparency = 0, BackgroundTransparency = 0.35 }):Play()
    end
end

-- Studs from you to a player, math.huge when either side has no character
-- (loading, dead, or spectating). Sorting on that parks them at the bottom
-- without a second branch.
function CmdBar.distanceTo(name)
    local me = LocalPlayer and LocalPlayer.Character
        and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not me then return math.huge end
    local pl = Players:FindFirstChild(name)
    local them = pl and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
    if not them then return math.huge end
    return (me.Position - them.Position).Magnitude
end

-- IsFriendsWith is a web call that YIELDS. Called from a sort comparator it
-- would stall the command bar once per comparison, so the answer is cached
-- and the cache is warmed when the bar opens.
CmdBar.friendCache = {}

function CmdBar.isFriend(userId)
    local v = CmdBar.friendCache[userId]
    if v ~= nil then return v end
    CmdBar.friendCache[userId] = false      -- assume not until the check lands
    task.spawn(function()
        local ok, res = pcall(function()
            return LocalPlayer:IsFriendsWith(userId)
        end)
        CmdBar.friendCache[userId] = (ok and res) or false
    end)
    return false
end

function CmdBar.warmFriends()
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer then CmdBar.isFriend(pl.UserId) end
    end
end

-- Friends, then nearby, then everyone else. Join order -- what GetPlayers
-- hands back -- carries no meaning at all; a friend is who you meant even
-- across the map, and after that whoever you are pointing at.
function CmdBar.rankOf(name)
    local pl = Players:FindFirstChild(name)
    if pl and CmdBar.isFriend(pl.UserId) then return 0 end
    -- Anyone without a character cannot be "nearby": they are loading, dead
    -- or spectating, and distanceTo reports math.huge for them.
    if CmdBar.distanceTo(name) < math.huge then return 1 end
    return 2
end

-- Why this row is where it is. The ordering is deliberate, so the list has
-- to say what it is ordering by -- otherwise a friend at the top just looks
-- like an arbitrary shuffle.
--
-- Distance is reported past the "nearby" band rather than being dropped: a
-- row that says nothing reads as unknown, and 240 studs is not unknown.
CmdBar.NEARBY_STUDS = 100

function CmdBar.tagFor(name)
    local pl = Players:FindFirstChild(name)
    if pl and CmdBar.isFriend(pl.UserId) then return "friend", true end
    local d = CmdBar.distanceTo(name)
    if d == math.huge then return nil end          -- no character to measure
    if d <= CmdBar.NEARBY_STUDS then return "nearby", false end
    return math.floor(d) .. " studs", false
end

function CmdBar.sortByNearest(matches)
    local rank, dist = {}, {}
    for _, m in ipairs(matches) do
        local n = m.player and m.player.name
        rank[m] = n and CmdBar.rankOf(n) or 2
        dist[m] = n and CmdBar.distanceTo(n) or math.huge
    end
    table.sort(matches, function(a, b)
        if rank[a] ~= rank[b] then return rank[a] < rank[b] end
        if dist[a] ~= dist[b] then return dist[a] < dist[b] end
        return (a.text or "") < (b.text or "")   -- stable for exact ties
    end)
    return matches
end

-- Most-used first. With nothing typed the alphabetical-ish table order is
-- meaningless -- 400 commands and the same six every time -- so lead with
-- what you actually run.
--
-- With no history there is nothing to rank by, and a fixed order would show
-- the identical six forever. Shuffle instead, but from a seed held for the
-- life of the burst: re-rolling per keystroke would make the list jump under
-- the cursor.
function CmdBar.rankCommands(matches, seg)
    local anyUse = false
    local n = {}
    for _, m in ipairs(matches) do
        n[m] = Usage.count("cmds", m.cmd)
        if n[m] > 0 then anyUse = true end
    end

    if not anyUse then
        if seg == "" then Usage.shuffle(matches, CmdBar.shuffleSeed or 1) end
        return matches
    end

    -- Stable within equal counts, so a used command never swaps places with
    -- an unused one it happens to tie with.
    local order = {}
    for i, m in ipairs(matches) do order[m] = i end
    table.sort(matches, function(a, b)
        if n[a] ~= n[b] then return n[a] > n[b] end
        return order[a] < order[b]
    end)
    return matches
end

-- Match a token against what has been typed so far. Against ANY of its
-- spellings, not just the canonical key: "full" is how you reach "high" and
-- "everyone" is how you reach "all", and matching the key alone meant every
-- alias we advertise on the row found nothing.
local function tokenMatches(words, seg)
    if seg == "" then return true end
    for _, w in ipairs(words) do
        if w:sub(1, #seg) == seg then return true end
    end
    return false
end

-- Reuses commandList / commandNeedsPlayer / getMatchingPlayers unchanged.
function updateAutocomplete()
    if not CmdBar.open then return end
    local text = CmdBar.box.Text
    local parts = {}
    for w in text:gmatch("%S+") do table.insert(parts, w) end

    local matches = {}
    local head = (parts[1] or ""):lower()
    -- Only while token 2 is still being typed. Past that the user is writing
    -- the payload and player rows are just noise.
    local typingTarget = (#parts == 2 and text:sub(-1) ~= " ")
        or (#parts == 1 and text:sub(-1) == " ")

    if typingTarget and commandNeedsServer(head) then
        local seg = (parts[2] or ""):lower()
        -- Kick the fetch if the cache is cold and redraw when it lands: the
        -- list re-renders per keystroke and cannot wait on a network call.
        ServerHop.snapshot(function()
            if CmdBar.open then updateAutocomplete() end
        end)
        for _, t in ipairs(ServerTokens) do
            local words = ServerTokens.spellings(t.key)
            if tokenMatches(words, seg) then
                local n, note = ServerTokens.stateFor(t.key)
                table.insert(matches, {
                    text = t.label, cmd = head, token = t,
                    desc = note or t.desc,
                    -- n == 0 means this filter cannot improve on where you
                    -- already are. Still runnable, just visibly pointless.
                    dim = (n == 0),
                    words = words,
                })
            end
        end

    elseif typingTarget and commandNeedsGame(head) then
        local seg = (parts[2] or ""):lower():gsub("%s+", "")
        for _, g in ipairs(QuickJoin.games) do
            local hay = g.name:lower():gsub("%s+", "")
            local hit = (seg == "") or hay:find(seg, 1, true) ~= nil
            if not hit then
                for _, k in ipairs(g.keys) do
                    if k:sub(1, #seg) == seg then hit = true break end
                end
            end
            if hit then
                table.insert(matches, { text = g.name, cmd = head, game = g })
            end
        end
        QuickJoin.sort(matches)
    elseif typingTarget and commandNeedsPlayer(head) then
        local seg = parts[2] or ""
        local pool = (seg == "") and Players:GetPlayers() or nil
        if pool then
            for _, pl in ipairs(pool) do
                table.insert(matches, {
                    text = pl.DisplayName, cmd = head,
                    player = { name = pl.Name, display = pl.DisplayName },
                })
            end
        else
            for _, pl in ipairs(getMatchingPlayers(seg)) do
                table.insert(matches, { text = pl.display, cmd = head, player = pl })
            end
        end
        -- You are never the target: there is no orbiting yourself. Filtered
        -- from the SUGGESTIONS only -- typing your own name still resolves,
        -- because a few commands legitimately point at you and findPlayer
        -- has no idea this list exists.
        local others = {}
        for _, m in ipairs(matches) do
            if not (m.player and m.player.name == LocalPlayer.Name) then
                others[#others + 1] = m
            end
        end
        matches = others
        CmdBar.sortByNearest(matches)

        -- Tokens go on TOP, after the players are sorted -- they are the
        -- shortcuts you reach for deliberately, and burying them under the
        -- roster would defeat the point. Which ones appear depends on the
        -- command: "goto all" is nonsense, so goto never offers it.
        local toks = {}
        for _, t in ipairs(PlayerTokens.forCommand(head)) do
            if tokenMatches(PlayerTokens.spellings(t.key), seg:lower()) then
                local label, desc = PlayerTokens.textFor(head, t)
                table.insert(toks, {
                    text = label, cmd = head, token = t,
                    desc = desc, tokenLabel = label,
                })
            end
        end
        -- Capped while nothing is typed. Five tokens fill a six-row list and
        -- it reads as "tokens only", when the whole point is that names work
        -- too -- the list has to show both to say so. Typing any prefix
        -- lifts the cap, since by then you are clearly after a token.
        if seg == "" then
            local KEEP = 2
            while #toks > KEEP do table.remove(toks) end
        end
        for i = #toks, 1, -1 do table.insert(matches, 1, toks[i]) end
    else
        local seg = head
        local seen = {}
        -- One row per alias group; any alias in the group matches.
        for gi, g in ipairs(CmdBar.aliasGroups) do
            if not seen[gi] then
                for _, a in ipairs(g) do
                    if seg == "" or a:sub(1, #seg) == seg then
                        local alt = {}
                        for _, x in ipairs(g) do
                            if x ~= g[1] then alt[#alt + 1] = x end
                        end
                        table.insert(matches, {
                            text = g[1], cmd = g[1], player = nil,
                            aliases = (#alt > 0) and table.concat(alt, "  ") or nil,
                            desc = IY.desc[g[1]] or (NATIVE_DESC and NATIVE_DESC[g[1]]),
                        })
                        seen[gi] = true
                        break
                    end
                end
            end
        end
        -- Anything in commandList that no group claims (so nothing is lost).
        for _, c in ipairs(commandList) do
            if not CmdBar.aliasOf[c] and (seg == "" or c:sub(1, #seg) == seg) then
                table.insert(matches, { text = c, cmd = c, player = nil,
                    desc = IY.desc[c] or (NATIVE_DESC and NATIVE_DESC[c]) })
            end
        end
        CmdBar.rankCommands(matches, seg)
    end

    CmdBar.render(matches)
end

-- ── Input wiring ────────────────────────────────────────────────────────
-- Called from startup, after CmdBar.build() has created the TextBox.
function CmdBar.wire()
    CmdBar.box:GetPropertyChangedSignal("Text"):Connect(function()
        -- A user edit invalidates any pending completion; a programmatic
        -- write from accept() already set completedText to this exact value.
        if CmdBar.box.Text ~= CmdBar.completedText then
            CmdBar.completedText = nil
        end
        updateAutocomplete()
        CmdBar.syncInlineAvatar()
    end)

    CmdBar.box.InputBegan:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.Down then
            if #CmdBar.matches > 0 then
                CmdBar.selected = CmdBar.selected + 1
                if CmdBar.selected > math.min(#CmdBar.matches, CmdBar.MAX_ROWS) then
                    CmdBar.selected = 1
                end
                CmdBar.paintSelection()
            end
        elseif input.KeyCode == Enum.KeyCode.Up then
            if #CmdBar.matches > 0 then
                CmdBar.selected = CmdBar.selected - 1
                if CmdBar.selected < 1 then
                    CmdBar.selected = math.min(#CmdBar.matches, CmdBar.MAX_ROWS)
                end
                CmdBar.paintSelection()
            end
        elseif input.KeyCode == Enum.KeyCode.Escape then
            CmdBar.hide()
        end
    end)

    -- Enter decides between COMPLETE and RUN by asking whether the input is
    -- already runnable -- never by "are there suggestions on screen", which
    -- is always true while the first token matches and would clobber typed
    -- arguments ("fly 100" -> "fly").
    local function refocus()
        task.wait(0.05)
        pcall(function() CmdBar.box:CaptureFocus() end)
    end

    CmdBar.box.FocusLost:Connect(function(enterPressed)
        if not enterPressed then return end
        local d = CmdBar.decide(CmdBar.box.Text)
        if d == "empty" then
            CmdBar.hide()
        elseif d == "run" then
            CmdBar.execute()
        elseif CmdBar.accept() then
            refocus()
        else
            CmdBar.execute()   -- nothing to complete to; run it as typed
        end
    end)

end

-- Bound ONCE for the session. wire() runs on every UI build, and a theme
-- switch rebuilds -- so registering the keybind there stacked a second
-- handler and every press toggled twice, i.e. nothing happened. The handler
-- reads CmdBar dynamically, so it keeps working across rebuilds.
function CmdBar.bindKey()
    if CmdBar.keyBound then return end
    CmdBar.keyBound = true
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if CmdBar.capturing then return end          -- rebinding, swallow it
        if Tour and Tour.running then return end     -- tour owns the UI
        if input.KeyCode == _G.CmdBarKeybind then
            CmdBar.toggle()
            if CmdBar.open then updateAutocomplete() end
        end
    end)
end

-- ── Command catalogue (data only; rendered by CmdList) ──────────────────
commandCategories = {
    {
        name = "All",
        commands = {}
    },
    {
        name = "Player Manipulation",
        commands = {
            {cmd = "!fly", desc = "Enable fly mode", example = "!fly, !fly 100"},
            {cmd = "!unfly", desc = "Disable fly mode", example = "!unfly"},
            {cmd = "!walkspeed or !ws", desc = "Set player walk speed", example = "!walkspeed 25"},
            {cmd = "!jump", desc = "Set player jump power", example = "!jump 60"},
            {cmd = "!noclip", desc = "Enable NoClip mode", example = "!noclip"},
            {cmd = "!clip", desc = "Disable NoClip mode", example = "!clip"},
            {cmd = "!goto or !tp or !to", desc = "Teleport to another player", example = "!goto PlayerName"},
            {cmd = "!spin", desc = "Enable character spin", example = "!spin, !spin 20"},
            {cmd = "!unspin", desc = "Disable character spin", example = "!unspin"},
            {cmd = "!infjump", desc = "Enable infinite jump", example = "!infjump"},
            {cmd = "!bang", desc = "Play bang animation on player", example = "!bang TargetPlayer, !bang TargetPlayer 5"},
            {cmd = "!unbang", desc = "Stop bang animation", example = "!unbang"},
            {cmd = "!orbit", desc = "Orbit around a player", example = "!orbit TargetPlayer 2"},
            {cmd = "!unorbit", desc = "Stop orbiting player", example = "!unorbit"},
            {cmd = "!headless", desc = "Make player head invisible", example = "!headless"},
            {cmd = "!unheadless or !noheadless", desc = "Make player head visible", example = "!unheadless"},
            {cmd = "!headsit or !hs", desc = "Sit on another player's head", example = "!headsit PlayerName"},
            {cmd = "!unheadsit or !uhs", desc = "Get off their head", example = "!unheadsit"},
            {cmd = "!backpack or !bp", desc = "Ride on a player's back", example = "!backpack PlayerName"},
            {cmd = "!unbackpack or !ubp", desc = "Get off their back", example = "!unbackpack"},
            {cmd = "!drag", desc = "Be dragged along by a player's hand", example = "!drag PlayerName"},
            {cmd = "!undrag or !udr", desc = "Break free from the drag", example = "!undrag"},
            {cmd = "!attach", desc = "Stick to a player", example = "!attach PlayerName"},
            {cmd = "!unattach or !detach", desc = "Detach from the player", example = "!detach"},
            {cmd = "!stare or !lookat", desc = "Always face a player", example = "!stare PlayerName"},
            {cmd = "!unstare", desc = "Stop facing them", example = "!unstare"},
            {cmd = "!copydance or !cd", desc = "Mirror a player's animations in phase", example = "!copydance PlayerName"},
            {cmd = "!uncopydance or !ucd", desc = "Stop mirroring them", example = "!uncopydance"},
            {cmd = "!stopall", desc = "Stop every active behaviour at once", example = "!stopall"},
            {cmd = "!profile or !prof or !whois", desc = "Profile card: join date, account age, friends in this server, inline actions", example = "!profile PlayerName"},
            {cmd = "!unprofile", desc = "Close the profile card", example = "!unprofile"},
            {cmd = "!quickjoin or !qj or !join", desc = "Jump straight into a popular game by name, alias or place id", example = "!quickjoin jailbreak"},
            {cmd = "!keepuhub or !autoexec", desc = "Toggle re-running the hub after a rejoin or server hop (on by default)", example = "!keepuhub"},
            {cmd = "!guide or !help", desc = "Reopen the getting-started panel", example = "!guide"},
            {cmd = "!tour", desc = "Walkthrough that points at each part of the interface on screen", example = "!tour"}
        }
    },
    {
        name = "Camera Control",
        commands = {
            {cmd = "!fov", desc = "Change camera FOV", example = "!fov 90"},
            {cmd = "!view or !unview", desc = "View another player's camera", example = "!view OtherPlayer, !unview"}
        }
    },
    {
        name = "Teleportation",
        commands = {
            {cmd = "!rj or !rejoin", desc = "Rejoin the server", example = "!rj"},
            {cmd = "!savepos", desc = "Save current position", example = "!savepos"},
            {cmd = "!topos", desc = "Teleport to saved position", example = "!topos"},
            {cmd = "!clicktp", desc = "Click to teleport", example = "!clicktp K"},
            {cmd = "!shop or !serverhop or !hop", desc = "Hop to another server -- takes low, high, packed, random, smooth or tiny", example = "!shop low"}
        }
    },
    {
        name = "World",
        commands = {
            {cmd = "!settime or !tod", desc = "Set the time of day", example = "!settime morning, !tod 14"},
            {cmd = "!exbp or !extendbaseplate", desc = "Extend the baseplate", example = "!exbp"},
            {cmd = "!fpsboost", desc = "Boost client FPS", example = "!fpsboost"}
        }
    },
    {
        name = "Utility",
        commands = {
            {cmd = "!prefix or !pfx", desc = "Change command prefix", example = "!prefix ."},
            {cmd = "!antiafk or !antidle", desc = "Prevent AFK kick", example = "!antiafk"},
            {cmd = "!bypassvc or !bvc or !rvc", desc = "Attempt bypass voice chat", example = "!bypassvc"},
            {cmd = "!cmds", desc = "Show this command GUI", example = "!cmds"},
            {cmd = "!info or !about or !version or !ver", desc = "Show version, release date, executor and build info", example = "!info"},
            {cmd = "!notify / !unotify", desc = "Toggle a notification for every activity event, not just leaves and friends", example = "!unotify"},
            {cmd = "!activity or !act or !watch", desc = "Live panel for one player: mic level, distance, who is near them, recent chat", example = "!activity nearest"},
            {cmd = "!mutevc or !mute", desc = "Mute a player's voice for you -- takes a name, all, others, random or nothing for your own mic", example = "!mutevc all"},
            {cmd = "!unmutevc or !unmute", desc = "Undo a voice mute", example = "!unmutevc john"},
            {cmd = "!resume or !runlast", desc = "Re-run the scripts you last used from the hub", example = "!resume"},
            {cmd = "!scripthub or !hub or !scripts", desc = "Browse and run scripts from ScriptBlox, starting with this game", example = "!scripthub"},
            {cmd = "!esp or !espmenu or !chams", desc = "Open the ESP panel: boxes, tracers, names, health, distance, skeleton, chams", example = "!esp"},
            {cmd = "!unesp or !noesp", desc = "Turn every ESP feature off", example = "!unesp"},
            {cmd = "!unexecute or !unexec or !unload", desc = "Unload the hub and free it to be re-executed", example = "!unexecute"},
            {cmd = "!cmdbarkeybind or !barkeybind or !cmdbarbind or !barbind", desc = "Rebind the key that opens the command bar", example = "!cmdbarkeybind K"}
        }
    },
    {
        name = "Script Execution",
        commands = {
            {cmd = "!uhub", desc = "Execute UniHub script", example = "!uhub"},
            {cmd = "!infyield or !ify", desc = "Execute InfYield script", example = "!infyield"},
            {cmd = "!uesp", desc = "Execute Unnamed ESP script", example = "!uesp"},
            {cmd = "!emotes", desc = "Execute Emotes script", example = "!emotes"},
            {cmd = "!sbroken", desc = "Execute SBroken script", example = "!sbroken"},
            {cmd = "!showstats or !stats", desc = "Toggle the live performance card: FPS, ping, memory, players", example = "!stats"}
        }
    },
    {
        name = "Information",
        commands = {
            {cmd = "!CopyUser or !copyuser", desc = "Copy player username", example = "!copyuser TargetPlayer"},
            {cmd = "!CopyDisplay or !copydisplay", desc = "Copy player display name", example = "!copydisplay TargetPlayer"},
            {cmd = "!CopyUserId or !copyuserid or !copyid", desc = "Copy player user ID", example = "!copyuserid TargetPlayer"},
            {cmd = "!ShowImg or !showimg", desc = "Show player headshot image", example = "!showimg TargetPlayer"},
            {cmd = "!CopyInv or !copyinv", desc = "Copy Discord invite link", example = "!copyinv"},
            {cmd = "!CopyWebLink or !copywebsitelink or !copyweblink", desc = "Copy website link", example = "!copyweblink"}
        }
    }
}

-- Imported Infinite Yield commands become their own category, described
-- from IY's own command list rather than hand-written blurbs.
do
    local iy = { name = "Infinite Yield", commands = {} }
    local names = {}
    for n in pairs(IY.cmds) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
        local alt = {}
        for al, canon in pairs(IY.alias) do
            if canon == n then alt[#alt + 1] = al end
        end
        table.sort(alt)
        local label = "!" .. n
        if #alt > 0 then label = label .. " or !" .. table.concat(alt, " or !") end
        iy.commands[#iy.commands + 1] = {
            cmd = label,
            desc = IY.desc[n] or "Infinite Yield command",
            example = "!" .. n,
        }
    end
    commandCategories[#commandCategories + 1] = iy
end

-- Description lookup for native commands, derived from the catalogue above
-- rather than a second hand-maintained list -- one source, no drift.
NATIVE_DESC = {}
for _, cat in ipairs(commandCategories) do
    for _, e in ipairs(cat.commands) do
        for token in tostring(e.cmd):gmatch("!([%w]+)") do
            NATIVE_DESC[token:lower()] = e.desc
        end
    end
end

-- Add all to first category
for i=2, #commandCategories do
    for _, cmd in ipairs(commandCategories[i].commands) do
        table.insert(commandCategories[1].commands, cmd)
    end
end

-- ════════════════════════════════════════════════════════════════════════
--  ABOUT — the wordmark, then what this build, this game and this client
--  actually are. Three tabs, because one column of twenty-odd rows is a
--  wall rather than something you read.
--  Named About, not Info: Info is already the clock/weather card.
-- ════════════════════════════════════════════════════════════════════════
HUB = {
    version  = "2.0.0",
    released = "25 July 2026",
    channel  = "Lite",
    link     = "https://angxers2.github.io/Unihub/",
}

About = {
    W = 470, HERO_H = 116, ROW_H = 30, TAB_H = 30, GAP = 14,
    tab = "Script",
    TABS = { "Script", "Game", "You" },
    ROWS = 8,                      -- every tab pads to this, so nothing jumps
}

-- Executors disagree on this: some return a name, some name + version, some
-- do not define it at all. Every branch has to end in a string.
local function executorName()
    local ok, a, b = pcall(function()
        if identifyexecutor then return identifyexecutor() end
        if getexecutorname then return getexecutorname() end
        return nil
    end)
    if not ok or not a then return "Unknown" end
    if b and b ~= "" then return tostring(a) .. " " .. tostring(b) end
    return tostring(a)
end

local function clientVersion()
    local ok, v = pcall(function() return version() end)
    return (ok and v and v ~= "") and tostring(v) or "Unknown"
end

local function hms(secs)
    secs = math.floor(secs or 0)
    if secs < 60 then return secs .. "s" end
    if secs < 3600 then return string.format("%dm %ds", secs // 60, secs % 60) end
    return string.format("%dh %dm", secs // 3600, (secs % 3600) // 60)
end

local function uptime()
    return hms(os.clock() - (About.bootAt or os.clock()))
end

-- GetProductInfo is a network round trip. Called once and cached, since
-- nothing it returns changes while you are in the place.
function About.place()
    if About.placeInfo ~= nil then return About.placeInfo end
    local ok, info = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
    end)
    About.placeInfo = (ok and type(info) == "table") and info or false
    return About.placeInfo
end

-- GetProductInfo is already cached here, so the exact icon asset costs
-- nothing extra. rbxthumb is the fallback, and gets game.GameId -- the
-- UNIVERSE id -- because that is what GameIcon actually resolves against.
function About.gameIcon()
    local info = About.place()
    local id = info and tonumber(info.IconImageAssetId)
    if id and id ~= 0 then return "rbxassetid://" .. tostring(id) end
    return "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=150&h=150"
end

local function plr() return Players.LocalPlayer end

-- ── Row sets ────────────────────────────────────────────────────────────
function About.scriptRows()
    return {
        { icon = "st_box.png",        key = "Version",   value = HUB.version .. " (" .. HUB.channel .. ")" },
        { icon = "st_calendar.png",   key = "Released",  value = HUB.released },
        { icon = "st_terminal.png",   key = "Executor",  value = executorName() },
        { icon = "st_cpu.png",        key = "Client",    value = clientVersion() },
        { icon = "st_zap.png",        key = "Commands",  value = tostring(#commandList) .. " loaded" },
        { icon = "st_clock.png",      key = "Session",   value = uptime() },
        { icon = UI.touch and "st_hand.png" or "st_keyboard.png",
          key = "Input", value = UI.touch and "Touch" or "Keyboard + mouse" },
        { icon = "st_hard-drive.png", key = "Workspace", value = WS.ok and (WS.ROOT .. "/") or "flat files" },
    }
end

function About.gameRows()
    local info = About.place()
    local creator = "Unknown"
    if info and info.Creator and info.Creator.Name then
        creator = info.Creator.Name
        if info.Creator.CreatorType == "Group" then creator = creator .. " (group)" end
    end

    local now, max = 0, 0
    pcall(function() now, max = #Players:GetPlayers(), Players.MaxPlayers end)

    -- DistributedGameTime counts from server start, so it is the server's
    -- age rather than yours.
    local age = "Unknown"
    pcall(function() age = hms(workspace.DistributedGameTime) end)

    return {
        { icon = "st_gamepad-2.png", key = "Game",      value = (info and info.Name) or "Unknown" },
        { icon = "st_users.png",     key = "Creator",   value = creator },
        { icon = "st_users.png",     key = "Players",   value = tostring(now) .. " / " .. tostring(max) },
        { icon = "st_server.png",    key = "Server age", value = age },
        { icon = "st_map-pin.png",   key = "Place ID",  value = tostring(game.PlaceId), copy = true },
        { icon = "st_globe.png",     key = "Universe",  value = tostring(game.GameId), copy = true },
        { icon = "st_server.png",    key = "Job ID",    value = (game.JobId ~= "" and game.JobId or "Studio"), copy = true },
        { icon = "st_box.png",       key = "Place version", value = tostring(game.PlaceVersion) },
    }
end

function About.youRows()
    local p = plr()
    local member = "None"
    pcall(function()
        local m = tostring(p.MembershipType):gsub("Enum.MembershipType%.", "")
        if m ~= "None" then member = m end
    end)

    local locale = "Unknown"
    pcall(function()
        locale = game:GetService("LocalizationService").RobloxLocaleId
    end)

    local vp = "Unknown"
    pcall(function()
        local s = workspace.CurrentCamera.ViewportSize
        vp = math.floor(s.X) .. " x " .. math.floor(s.Y)
    end)

    local quality = "Unknown"
    pcall(function()
        quality = tostring(UserSettings():GetService("UserGameSettings").SavedQualityLevel)
                    :gsub("Enum.SavedQualitySetting%.", "")
    end)

    local team = "None"
    pcall(function() if p.Team then team = p.Team.Name end end)

    return {
        { icon = "st_users.png",    key = "Username",   value = "@" .. p.Name, copy = true },
        { icon = "st_smile.png",    key = "Display",    value = p.DisplayName },
        { icon = "st_scan-eye.png", key = "User ID",    value = tostring(p.UserId), copy = true },
        { icon = "st_calendar.png", key = "Account age", value = tostring(p.AccountAge) .. " days" },
        { icon = "st_gem.png",      key = "Membership", value = member },
        { icon = "st_flag.png",     key = "Team",       value = team },
        { icon = "st_globe.png",    key = "Locale",     value = locale },
        { icon = "st_maximize.png", key = "Viewport",   value = vp .. "  \194\183  " .. quality },
    }
end

function About.rowsFor(tab)
    if tab == "Game" then return About.gameRows() end
    if tab == "You" then return About.youRows() end
    return About.scriptRows()
end

function About.show()
    if Modal.open and Modal.owner == "about" then Modal.hide() return end
    About.tab = "Script"
    local bodyH = About.HERO_H + About.GAP + About.TAB_H + 10
                  + About.ROWS * About.ROW_H

    Modal.show{
        owner = "about",
        dismissOnBackdrop = false,
        width = About.W,
        title = "",                 -- the hero is the header
        bodyHeight = bodyH,
        actions = {
            { label = "Copy link", icon = "st_copy.png", style = "light",
              run = function()
                  pcall(function() setclipboard(HUB.link) end)
                  Notifications:Success("Universal Hub Lite", "Website link copied", 3)
              end },
            { label = "Commands", icon = "st_list.png", style = "ghost",
              run = function() CmdList.show() end },
            { label = "Close", icon = "st_x.png", style = "ghost" },
        },
        build = function(panel, headY, _, W)
            local PAD = 24

            -- ── Hero: swaps with the tab, because the wordmark says nothing
            -- about the place you are standing in.
            local hero = Instance.new("Frame")
            hero.Position = UDim2.new(0, PAD, 0, headY)
            hero.Size = UDim2.new(1, -PAD * 2, 0, About.HERO_H)
            hero.BackgroundTransparency = 1
            hero.ZIndex = 6
            hero.Parent = panel

            local mark = Instance.new("ImageLabel")
            mark.AnchorPoint = Vector2.new(0.5, 0.5)
            mark.Position = UDim2.fromScale(0.5, 0.5)
            mark.Size = UDim2.fromScale(1, 1)
            mark.BackgroundTransparency = 1
            mark.ScaleType = Enum.ScaleType.Fit
            mark.Image = UI.icon("logo.png")
            mark.ZIndex = 7
            mark.Parent = hero

            local thumb = Instance.new("ImageLabel")
            thumb.AnchorPoint = Vector2.new(0, 0.5)
            thumb.Position = UDim2.new(0, 0, 0.5, 0)
            thumb.Size = UDim2.fromOffset(84, 84)
            thumb.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
            thumb.BackgroundTransparency = 0.4
            thumb.Visible = false
            thumb.ZIndex = 7
            thumb.Parent = hero
            local tc = Instance.new("UICorner", thumb)

            local hTitle = Instance.new("TextLabel")
            hTitle.Position = UDim2.new(0, 100, 0.5, -22)
            hTitle.Size = UDim2.new(1, -100, 0, 26)
            hTitle.BackgroundTransparency = 1
            hTitle.TextColor3 = UI.textPrimary
            hTitle.TextXAlignment = Enum.TextXAlignment.Left
            hTitle.TextSize = 20
            hTitle.TextTruncate = Enum.TextTruncate.AtEnd
            hTitle.Visible = false
            hTitle.ZIndex = 7
            hTitle.Parent = hero
            UI.applyFont(hTitle, Enum.FontWeight.Bold)

            local hSub = Instance.new("TextLabel")
            hSub.Position = UDim2.new(0, 100, 0.5, 6)
            hSub.Size = UDim2.new(1, -100, 0, 18)
            hSub.BackgroundTransparency = 1
            hSub.TextColor3 = UI.textMuted
            hSub.TextXAlignment = Enum.TextXAlignment.Left
            hSub.TextSize = UI.T_ROW
            hSub.TextTruncate = Enum.TextTruncate.AtEnd
            hSub.Visible = false
            hSub.ZIndex = 7
            hSub.Parent = hero
            UI.applyFont(hSub, Enum.FontWeight.Medium)

            -- ── Tabs ───────────────────────────────────────────────────
            local tabY = headY + About.HERO_H + About.GAP
            local chips = {}
            local rowHolder

            local function paintTabs()
                for name, chip in pairs(chips) do
                    local on = (name == About.tab)
                    TweenService:Create(chip, TweenInfo.new(0.15), {
                        BackgroundColor3 = on and UI.accent or Color3.fromRGB(42, 44, 52),
                        BackgroundTransparency = on and 0 or 0.35,
                    }):Play()
                    local lb = chip:FindFirstChildWhichIsA("TextLabel")
                    if lb then
                        TweenService:Create(lb, TweenInfo.new(0.15), {
                            TextColor3 = on and Color3.fromRGB(255, 255, 255)
                                             or Color3.fromRGB(180, 182, 192) }):Play()
                    end
                end
            end

            local function paintHero()
                local isScript = (About.tab == "Script")
                mark.Visible = isScript
                thumb.Visible = not isScript
                hTitle.Visible = not isScript
                hSub.Visible = not isScript
                if isScript then return end

                if About.tab == "Game" then
                    tc.CornerRadius = UDim.new(0, 16)     -- a place icon is square
                    thumb.Image = About.gameIcon()
                    local info = About.place()
                    hTitle.Text = (info and info.Name) or "This game"
                    local now, max = 0, 0
                    pcall(function() now, max = #Players:GetPlayers(), Players.MaxPlayers end)
                    hSub.Text = tostring(now) .. " of " .. tostring(max) .. " players in this server"
                else
                    tc.CornerRadius = UDim.new(1, 0)      -- a face is round
                    local p = plr()
                    thumb.Image = UI.headshotFor(p.Name)
                    hTitle.Text = p.DisplayName
                    hSub.Text = "@" .. p.Name
                end
            end

            -- ── Rows ───────────────────────────────────────────────────
            local rowsY = tabY + About.TAB_H + 10

            local function renderRows()
                if rowHolder then pcall(function() rowHolder:Destroy() end) end
                rowHolder = Instance.new("Frame")
                rowHolder.Position = UDim2.new(0, PAD, 0, rowsY)
                rowHolder.Size = UDim2.new(1, -PAD * 2, 0, About.ROWS * About.ROW_H)
                rowHolder.BackgroundTransparency = 1
                rowHolder.ZIndex = 6
                rowHolder.Parent = panel

                for i, l in ipairs(About.rowsFor(About.tab)) do
                    local row = Instance.new("Frame")
                    row.Position = UDim2.new(0, 0, 0, (i - 1) * About.ROW_H)
                    row.Size = UDim2.new(1, 0, 0, About.ROW_H - 2)
                    row.BackgroundTransparency = 1
                    row.ZIndex = 6
                    row.Parent = rowHolder

                    local ic = Instance.new("ImageLabel")
                    ic.AnchorPoint = Vector2.new(0, 0.5)
                    ic.Position = UDim2.new(0, 0, 0.5, 0)
                    ic.Size = UDim2.fromOffset(15, 15)
                    ic.BackgroundTransparency = 1
                    ic.Image = UI.icon(l.icon)
                    ic.ImageColor3 = UI.accent
                    ic.ZIndex = 7
                    ic.Parent = row

                    local k = Instance.new("TextLabel")
                    k.AnchorPoint = Vector2.new(0, 0.5)
                    k.Position = UDim2.new(0, 26, 0.5, 0)
                    k.Size = UDim2.new(0, 120, 1, 0)
                    k.BackgroundTransparency = 1
                    k.Text = l.key
                    k.TextColor3 = UI.textMuted
                    k.TextXAlignment = Enum.TextXAlignment.Left
                    k.TextSize = UI.T_SMALL
                    k.ZIndex = 7
                    k.Parent = row
                    UI.applyFont(k, Enum.FontWeight.Medium)

                    -- Right-aligned so the values line up as a column
                    -- however long the executor names itself.
                    local v = Instance.new("TextLabel")
                    v.AnchorPoint = Vector2.new(1, 0.5)
                    v.Position = UDim2.new(1, l.copy and -24 or 0, 0.5, 0)
                    v.Size = UDim2.new(1, -(150 + (l.copy and 24 or 0)), 1, 0)
                    v.BackgroundTransparency = 1
                    v.RichText = true
                    v.Text = l.value
                    v.TextColor3 = Color3.fromRGB(232, 233, 238)
                    v.TextXAlignment = Enum.TextXAlignment.Right
                    v.TextSize = UI.T_ROW
                    v.TextTruncate = Enum.TextTruncate.AtEnd
                    v.ZIndex = 7
                    v.Parent = row
                    UI.applyFont(v, Enum.FontWeight.SemiBold)

                    -- IDs are the only values anyone actually wants out of
                    -- here, so only they get the button.
                    if l.copy then
                        local raw = l.value
                        local cp = Instance.new("ImageButton")
                        cp.AnchorPoint = Vector2.new(1, 0.5)
                        cp.Position = UDim2.new(1, 0, 0.5, 0)
                        cp.Size = UDim2.fromOffset(15, 15)
                        cp.BackgroundTransparency = 1
                        cp.AutoButtonColor = false
                        cp.Image = UI.icon("st_copy.png")
                        cp.ImageColor3 = Color3.fromRGB(255, 255, 255)
                        cp.ImageTransparency = 0.68     -- quiet until you go for it
                        cp.ZIndex = 8
                        cp.Parent = row
                        cp.MouseEnter:Connect(function()
                            TweenService:Create(cp, TweenInfo.new(0.12,
                                Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                                { ImageTransparency = 0, Size = UDim2.fromOffset(17, 17) }):Play()
                        end)
                        cp.MouseLeave:Connect(function()
                            TweenService:Create(cp, TweenInfo.new(0.14),
                                { ImageTransparency = 0.68, Size = UDim2.fromOffset(15, 15) }):Play()
                        end)
                        cp.MouseButton1Click:Connect(function()
                            pcall(function() setclipboard(tostring(raw):gsub("^@", "")) end)
                            -- confirm on the row; a toast would sit behind
                            -- the modal where you cannot see it
                            v.Text = '<font color="#7ee08a">copied</font>'
                            cp.Image = UI.icon("st_circle-check.png")
                            task.delay(1.1, function()
                                pcall(function()
                                    v.Text = raw
                                    cp.Image = UI.icon("st_copy.png")
                                end)
                            end)
                        end)
                    end
                end
            end

            local x = 0
            for _, name in ipairs(About.TABS) do
                local w = 26 + #name * 8
                local chip = Instance.new("TextButton")
                chip.Position = UDim2.new(0, PAD + x, 0, tabY)
                chip.Size = UDim2.fromOffset(w, About.TAB_H - 6)
                chip.AutoButtonColor = false
                chip.Text = ""
                chip.BackgroundColor3 = Color3.fromRGB(42, 44, 52)
                chip.BorderSizePixel = 0
                chip.ZIndex = 7
                chip.Parent = panel
                Instance.new("UICorner", chip).CornerRadius = UDim.new(1, 0)

                local lb = Instance.new("TextLabel")
                lb.Size = UDim2.fromScale(1, 1)
                lb.BackgroundTransparency = 1
                lb.Text = name
                lb.TextColor3 = Color3.fromRGB(180, 182, 192)
                lb.TextSize = UI.T_SMALL
                lb.ZIndex = 8
                lb.Parent = chip
                UI.applyFont(lb, Enum.FontWeight.SemiBold)

                chip.MouseButton1Click:Connect(function()
                    if About.tab == name then return end
                    About.tab = name
                    paintTabs() paintHero() renderRows()
                end)

                chips[name] = chip
                x = x + w + 8
            end

            paintTabs() paintHero() renderRows()
        end,
    }
end

-- ════════════════════════════════════════════════════════════════════════
--  COMMAND LIST  (modal)
--  ~200 commands is too much for a 380px drawer hanging off the corner, so
--  this is a proper panel: search, category chips, and a scrolling list --
--  same glass, accent edge and gradient buttons as the rest.
-- ════════════════════════════════════════════════════════════════════════
CmdList = { category = "All", rows = {}, chips = {},
            ROW_H = 52, W = 580, BODY_H = 400 }

function CmdList.categories()
    local out = {}
    for _, c in ipairs(commandCategories) do out[#out + 1] = c end
    return out
end

function CmdList.render()
    local list = CmdList.list
    if not list then return end
    for _, r in ipairs(CmdList.rows) do pcall(function() r:Destroy() end) end
    CmdList.rows = {}

    local cat = commandCategories[1]
    for _, c in ipairs(commandCategories) do
        if c.name == CmdList.category then cat = c break end
    end

    local term = (CmdList.search.Text or ""):lower()
    local y, shown = 0, 0

    for _, e in ipairs(cat.commands) do
        local hay = (e.cmd .. " " .. (e.desc or "")):lower()
        if term == "" or hay:find(term, 1, true) then
            local row = Instance.new("Frame")
            row.Position = UDim2.new(0, 0, 0, y)
            row.Size = UDim2.new(1, -8, 0, CmdList.ROW_H)
            row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            row.BackgroundTransparency = 0.955
            row.BorderSizePixel = 0
            row.ZIndex = 7
            row.Parent = list
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 9)

            local nm = Instance.new("TextLabel")
            nm.Position = UDim2.new(0, 12, 0, 8)
            nm.Size = UDim2.new(1, -24, 0, 17)
            nm.BackgroundTransparency = 1
            nm.Text = e.cmd
            nm.TextColor3 = UI.accent
            nm.TextXAlignment = Enum.TextXAlignment.Left
            nm.TextSize = UI.T_ROW
            nm.TextTruncate = Enum.TextTruncate.AtEnd
            nm.ZIndex = 8
            nm.Parent = row
            UI.applyFont(nm, Enum.FontWeight.SemiBold)

            local ds = Instance.new("TextLabel")
            ds.Position = UDim2.new(0, 12, 0, 26)
            ds.Size = UDim2.new(1, -24, 0, 16)
            ds.BackgroundTransparency = 1
            ds.Text = e.desc or ""
            ds.TextColor3 = Color3.fromRGB(198, 200, 210)
            ds.TextXAlignment = Enum.TextXAlignment.Left
            ds.TextSize = UI.T_SMALL
            ds.TextTruncate = Enum.TextTruncate.AtEnd
            ds.ZIndex = 8
            ds.Parent = row
            UI.applyFont(ds, Enum.FontWeight.Regular)

            -- clicking a row drops it into the command bar, ready to edit
            local hit = Instance.new("TextButton")
            hit.Size = UDim2.fromScale(1, 1)
            hit.BackgroundTransparency = 1
            hit.Text = ""
            hit.AutoButtonColor = false
            hit.ZIndex = 9
            hit.Parent = row
            hit.MouseEnter:Connect(function()
                TweenService:Create(row, TweenInfo.new(0.12),
                    { BackgroundTransparency = 0.9 }):Play()
            end)
            hit.MouseLeave:Connect(function()
                TweenService:Create(row, TweenInfo.new(0.15),
                    { BackgroundTransparency = 0.955 }):Play()
            end)
            hit.MouseButton1Click:Connect(function()
                local first = e.cmd:match("^!([%w]+)") or ""
                Modal.hide()
                task.delay(0.26, function()
                    CmdBar.show()
                    task.delay(0.12, function()
                        pcall(function()
                            CmdBar.box.Text = first .. " "
                            CmdBar.box.CursorPosition = #CmdBar.box.Text + 1
                        end)
                        pcall(updateAutocomplete)
                    end)
                end)
            end)

            CmdList.rows[#CmdList.rows + 1] = row
            y = y + CmdList.ROW_H + 6
            shown = shown + 1
        end
    end

    list.CanvasSize = UDim2.new(0, 0, 0, y)
    if CmdList.count then
        CmdList.count.Text = shown .. (shown == 1 and " command" or " commands")
    end
end

function CmdList.paintChips()
    for name, chip in pairs(CmdList.chips) do
        local on = (name == CmdList.category)
        TweenService:Create(chip, TweenInfo.new(0.15), {
            BackgroundColor3 = on and UI.accent or Color3.fromRGB(42, 44, 52),
            TextColor3 = on and Color3.fromRGB(255, 255, 255)
                             or Color3.fromRGB(178, 180, 190),
        }):Play()
    end
end

function CmdList.show()
    if Modal.open and Modal.owner == "cmds" then Modal.hide() return end
    CmdList.category = "All"

    Modal.show{
        owner = "cmds",
        width = CmdList.W,
        title = "Commands",
        subtitle = "Search, or pick a category. Click any row to load it.",
        bodyHeight = CmdList.BODY_H,
        actions = {
            { label = "Close", icon = "st_x.png", style = "ghost" },
        },
        build = function(panel, headY, bodyH, W)
            local PAD = 24

            local search = Instance.new("TextBox")
            search.Position = UDim2.new(0, PAD, 0, headY)
            search.Size = UDim2.new(1, -PAD * 2 - 110, 0, 32)
            search.BackgroundColor3 = Color3.fromRGB(42, 44, 52)
            search.Text = ""
            search.PlaceholderText = "search commands"
            search.PlaceholderColor3 = UI.textMuted
            search.TextColor3 = UI.textPrimary
            search.TextXAlignment = Enum.TextXAlignment.Left
            search.TextSize = UI.T_ROW
            search.ClearTextOnFocus = false
            search.ZIndex = 7
            search.Parent = panel
            UI.applyFont(search, Enum.FontWeight.Medium)
            Instance.new("UICorner", search).CornerRadius = UDim.new(0, 8)
            local ss = Instance.new("UIPadding", search)
            ss.PaddingLeft = UDim.new(0, 12)
            local sk = Instance.new("UIStroke", search)
            sk.Color = Color3.fromRGB(90, 92, 104); sk.Thickness = 1; sk.Transparency = 0.6
            search.Focused:Connect(function()
                TweenService:Create(sk, TweenInfo.new(0.15),
                    { Color = UI.accent, Transparency = 0.15 }):Play()
            end)
            search.FocusLost:Connect(function()
                TweenService:Create(sk, TweenInfo.new(0.15),
                    { Color = Color3.fromRGB(90, 92, 104), Transparency = 0.6 }):Play()
            end)
            CmdList.search = search

            local count = Instance.new("TextLabel")
            count.AnchorPoint = Vector2.new(1, 0.5)
            count.Position = UDim2.new(1, -PAD, 0, headY + 16)
            count.Size = UDim2.fromOffset(100, 18)
            count.BackgroundTransparency = 1
            count.Text = ""
            count.TextColor3 = UI.textMuted
            count.TextXAlignment = Enum.TextXAlignment.Right
            count.TextSize = UI.T_SMALL
            count.ZIndex = 7
            count.Parent = panel
            UI.applyFont(count, Enum.FontWeight.Regular)
            CmdList.count = count

            local chipRow = Instance.new("ScrollingFrame")
            chipRow.Position = UDim2.new(0, PAD, 0, headY + 42)
            chipRow.Size = UDim2.new(1, -PAD * 2, 0, 26)
            chipRow.BackgroundTransparency = 1
            chipRow.BorderSizePixel = 0
            chipRow.ScrollBarThickness = 0
            chipRow.ScrollingDirection = Enum.ScrollingDirection.X
            chipRow.ZIndex = 7
            chipRow.Parent = panel
            CmdList.chipRow = chipRow
            CmdList.chips = {}

            local x = 0
            for _, cat in ipairs(commandCategories) do
                local w = 20 + #cat.name * 7
                local chip = Instance.new("TextButton")
                chip.AnchorPoint = Vector2.new(0, 0.5)
                chip.Position = UDim2.new(0, x, 0.5, 0)
                chip.Size = UDim2.fromOffset(w, 23)
                chip.AutoButtonColor = false
                chip.Text = cat.name
                chip.TextSize = UI.T_SMALL
                chip.TextTruncate = Enum.TextTruncate.AtEnd
                chip.BackgroundColor3 = Color3.fromRGB(42, 44, 52)
                chip.TextColor3 = Color3.fromRGB(178, 180, 190)
                chip.ZIndex = 8
                chip.Parent = chipRow
                UI.applyFont(chip, Enum.FontWeight.SemiBold)
                Instance.new("UICorner", chip).CornerRadius = UDim.new(1, 0)
                chip.MouseButton1Click:Connect(function()
                    CmdList.category = cat.name
                    CmdList.paintChips()
                    CmdList.render()
                end)
                CmdList.chips[cat.name] = chip
                x = x + w + 6
            end
            chipRow.CanvasSize = UDim2.new(0, x, 0, 0)

            local list = Instance.new("ScrollingFrame")
            list.Position = UDim2.new(0, PAD, 0, headY + 78)
            list.Size = UDim2.new(1, -PAD * 2, 0, bodyH - 86)
            list.BackgroundTransparency = 1
            list.BorderSizePixel = 0
            list.ScrollBarThickness = 3
            list.ScrollBarImageColor3 = UI.accent
            list.ScrollBarImageTransparency = 0.35
            list.CanvasSize = UDim2.new(0, 0, 0, 0)
            list.ZIndex = 7
            list.Parent = panel
            CmdList.list = list

            search:GetPropertyChangedSignal("Text"):Connect(CmdList.render)
            CmdList.paintChips()
            CmdList.render()
        end,
    }
end

function CmdList.hide()
    if Modal.owner ~= "cmds" then return end
    Modal.hide()
end

-- ════════════════════════════════════════════════════════════════════════
--  ACTIVITY BADGE — a live glyph over the corner icon
-- ════════════════════════════════════════════════════════════════════════
Badge = { tweens = {}, shown = nil }

Badge.icons = {
    fly     = "st_plane.png",
    spin    = "st_rotate-cw.png",
    orbit   = "st_rotate-cw.png",
    noclip  = "st_ghost.png",
    view    = "st_eye.png",
    infjump = "st_arrow-up.png",
}

function Badge.build()
    if Badge.frame or not Bar.row then return end
    local cx = 7 + UI.IMG / 2

    local b = Instance.new("Frame")
    b.Name = "ActBadge"
    b.AnchorPoint = Vector2.new(0.5, 0.5)
    b.Position = UDim2.new(0, cx, 0.5, 0)
    b.Size = UDim2.fromOffset(UI.IMG, UI.IMG)
    b.BackgroundTransparency = 0.12
    b.BorderSizePixel = 0
    b.Visible = false
    b.ZIndex = (Bar.icon.ZIndex or 1) + 3
    b.Parent = Bar.row
    Badge.sheen = UI.glassify(b, 9)

    -- The working indicator lives in the glass itself: a bright head with a
    -- long soft tail orbits the border as the gradient rotates.
    local s = Instance.new("UIStroke")
    s.Color = UI.accent
    s.Thickness = 1.5
    s.Transparency = 0.15
    s.Parent = b
    local sg = Instance.new("UIGradient")
    sg.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0.00, 0.10),
        NumberSequenceKeypoint.new(0.30, 0.72),
        NumberSequenceKeypoint.new(0.70, 0.90),
        NumberSequenceKeypoint.new(1.00, 0.10),
    })
    sg.Parent = s

    -- Rotation renders subpixel-smooth; translating a small image a few px
    -- per frame snaps to the pixel grid and looks like a flipbook.
    local gw = Instance.new("Frame")
    gw.Name = "GlyphWrap"
    gw.AnchorPoint = Vector2.new(0.5, 0.5)
    gw.Position = UDim2.new(0.5, 0, 0.5, 0)
    gw.Size = UDim2.fromScale(1, 1)
    gw.BackgroundTransparency = 1
    gw.ZIndex = b.ZIndex + 2
    gw.Parent = b

    local g = Instance.new("ImageLabel")
    g.Name = "Glyph"
    g.AnchorPoint = Vector2.new(0.5, 0.5)
    g.Position = UDim2.new(0.5, 0, 0.5, 0)
    g.Size = UDim2.fromOffset(18, 18)
    g.BackgroundTransparency = 1
    g.ImageColor3 = Color3.fromRGB(245, 246, 250)
    g.ZIndex = b.ZIndex + 2
    g.Parent = gw

    Badge.frame, Badge.glyph, Badge.wrap, Badge.stroke = b, g, gw, s
    Badge.strokeGrad = sg
end

function Badge.stopMotion()
    for _, tw in ipairs(Badge.tweens) do pcall(function() tw:Cancel() end) end
    Badge.tweens = {}
    if Badge.glyph then
        Badge.glyph.Rotation = 0
        Badge.glyph.Size = UDim2.fromOffset(18, 18)
    end
    if Badge.wrap then Badge.wrap.Rotation = 0 end
end

function Badge.startMotion(kind)
    Badge.stopMotion()
    local g = Badge.glyph
    if not g then return end
    local lin = function(d)
        return TweenInfo.new(d, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1)
    end
    local osc = function(d)
        return TweenInfo.new(d, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
    end
    local tw = {}

    if kind == "spin" or kind == "orbit" then
        g.Rotation = 0
        tw[1] = TweenService:Create(g, lin(2.0), { Rotation = 360 })
    elseif kind == "fly" then
        g.Rotation = -10
        tw[1] = TweenService:Create(g, osc(1.3), { Rotation = 10 })
    elseif kind == "infjump" then
        g.Size = UDim2.fromOffset(17, 17)
        tw[1] = TweenService:Create(g, osc(0.5), { Size = UDim2.fromOffset(21, 21) })
    else
        g.Size = UDim2.fromOffset(17, 17)
        tw[1] = TweenService:Create(g, osc(1.1), { Size = UDim2.fromOffset(21, 21) })
    end

    for _, t in ipairs(tw) do t:Play() end
    Badge.tweens = tw
end

function Badge.show(kind)
    Badge.build()
    local b, g = Badge.frame, Badge.glyph
    if not b then return end
    local id = UI.icon(Badge.icons[kind] or "st_zap.png")
    if id == "" then return end
    g.Image = id
    Badge.stroke.Color = UI.accent

    b.Visible = true
    b.Size = UDim2.fromOffset(math.floor(UI.IMG * 0.7), math.floor(UI.IMG * 0.7))
    b.BackgroundTransparency = 1
    g.ImageTransparency = 1
    Badge.stroke.Transparency = 1
    Badge.sheen.BackgroundTransparency = 1

    TweenService:Create(b,
        TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Size = UDim2.fromOffset(UI.IMG, UI.IMG), BackgroundTransparency = 0.12 }):Play()
    TweenService:Create(g, TweenInfo.new(0.24), { ImageTransparency = 0 }):Play()
    TweenService:Create(Badge.stroke, TweenInfo.new(0.24), { Transparency = 0.15 }):Play()
    TweenService:Create(Badge.sheen, TweenInfo.new(0.3), { BackgroundTransparency = 0 }):Play()

    if Badge.spin then Badge.spin:Cancel() end
    Badge.strokeGrad.Rotation = 0
    Badge.spin = TweenService:Create(Badge.strokeGrad,
        TweenInfo.new(1.8, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
        { Rotation = 360 })
    Badge.spin:Play()

    Badge.startMotion(kind)
end

function Badge.hide()
    local b = Badge.frame
    if not b or not b.Visible then return end
    if Badge.spin then Badge.spin:Cancel() Badge.spin = nil end
    Badge.stopMotion()

    local t = TweenService:Create(b,
        TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Size = UDim2.fromOffset(math.floor(UI.IMG * 0.7), math.floor(UI.IMG * 0.7)),
            BackgroundTransparency = 1,
        })
    TweenService:Create(Badge.glyph, TweenInfo.new(0.18), { ImageTransparency = 1 }):Play()
    TweenService:Create(Badge.stroke, TweenInfo.new(0.18), { Transparency = 1 }):Play()
    TweenService:Create(Badge.sheen, TweenInfo.new(0.18), { BackgroundTransparency = 1 }):Play()
    t.Completed:Connect(function()
        if Badge.shown == nil then b.Visible = false end
    end)
    t:Play()
end

-- The badge is a 2-second FLASH, not a persistent state light: it confirms
-- the toggle, then the corner returns to the U-Lite mark.
Badge.HOLD = 2
Badge.token = 0

-- Waits for the bar to be idle before showing. A badge fired while a toast
-- is up would sit directly on top of the brand mark in the notification --
-- that overlap is the whole reason this is deferred rather than immediate.
function Badge.tryShow(kind, tok, waited)
    if Badge.token ~= tok then return end
    if Bar.mode ~= "idle" or Bar.expanded then
        if waited > 12 then return end          -- bail rather than queue forever
        task.delay(0.25, function() Badge.tryShow(kind, tok, waited + 0.25) end)
        return
    end
    Badge.shown = kind
    Badge.show(kind)
    task.delay(Badge.HOLD, function()
        if Badge.token ~= tok then return end
        Badge.shown = nil
        Badge.hide()
    end)
end

function Badge.set(kind)
    Badge.token = Badge.token + 1
    kind = kind or "idle"
    if kind == "idle" or not Badge.icons[kind] then
        Badge.shown = nil
        Badge.hide()
        return
    end
    Badge.tryShow(kind, Badge.token, 0)
end
-- ════════════════════════════════════════════════════════════════════════
--  TIME & WEATHER CARD
--  Clock + weather, same shape as the musicbot card but with no AI section
--  and no Python round-trip: location from ipinfo.io, weather from wttr.in
--  (both plain HTTP), and the time is read from the client's own clock.
-- ════════════════════════════════════════════════════════════════════════
Info = { H = 154, wx = nil, fetching = false, fetchedAt = 0 }

-- Clock source.
--
-- Roblox deviates from standard Lua here: os.time(table) interprets the table
-- as UTC, not local, so the usual difftime trick for finding the UTC offset
-- returns 0 and the clock renders UTC. Avoid os.time entirely -- os.date("*t")
-- already gives the client's LOCAL time, so read that and interpolate between
-- re-syncs with os.clock() for a smooth (sub-second) second hand.
Info.dayBase = nil      -- seconds into the local day at last sync
Info.clockBase = nil    -- os.clock() at that same instant
Info.SYNC_EVERY = 30

function Info.sync()
    local ok, t = pcall(function() return os.date("*t") end)
    if not (ok and type(t) == "table" and t.hour) then return end
    Info.dayBase = t.hour * 3600 + t.min * 60 + t.sec
    Info.clockBase = os.clock()
    Info.syncedAt = os.clock()
end

-- Seconds into the local day, as a float.
function Info.now()
    if not Info.dayBase then Info.sync() end
    if not Info.dayBase then return 0 end
    if (os.clock() - (Info.syncedAt or 0)) > Info.SYNC_EVERY then Info.sync() end
    return (Info.dayBase + (os.clock() - Info.clockBase)) % 86400
end

-- wttr.in condition text -> one of the wx_*.png glyphs.
-- ── Forecast ────────────────────────────────────────────────────────────
-- The next few 3-hour slots, plus a headline when something is coming that
-- would change what you do. "Rain in 2h" is worth a sentence; "cloudy later"
-- is not, so only precipitation earns the line.
Info.SLOTS = 4

-- Slots are on the 3-hour grid, so the first one AHEAD of now is the first
-- whose hour is greater than the current one -- not the nearest.
function Info.nextSlots(n)
    local wx = Info.wx
    if not (wx and wx.slots and #wx.slots > 0) then return {} end
    local nowH = math.floor((Info.now() or 0) / 3600)
    local out = {}
    for _, sl in ipairs(wx.slots) do
        if sl.hour > nowH then
            out[#out + 1] = sl
            if #out >= (n or Info.SLOTS) then break end
        end
    end
    return out
end

-- What is worth saying about the next few hours, or nil for nothing.
function Info.headline()
    local nowH = math.floor((Info.now() or 0) / 3600)
    for _, sl in ipairs(Info.nextSlots(4)) do
        local away = sl.hour - nowH
        local what
        if sl.snow >= 40 then what = "Snow"
        elseif sl.rain >= 40 then what = "Rain"
        elseif sl.desc:lower():find("thunder") then what = "Storms" end
        if what then
            if away <= 1 then return what .. " within the hour" end
            return what .. " in about " .. away .. "h"
        end
    end
    return nil
end

function Info.glyphFor(desc, isNight)
    local d = (desc or ""):lower()
    if d:find("thunder") or d:find("storm") then return "wx_cloud-lightning.png" end
    if d:find("snow") or d:find("sleet") or d:find("ice") or d:find("blizzard") then
        return "wx_cloud-snow.png"
    end
    if d:find("drizzle") then return "wx_cloud-drizzle.png" end
    if d:find("rain") or d:find("shower") then return "wx_cloud-rain.png" end
    if d:find("fog") or d:find("mist") or d:find("haze") then return "wx_cloud-fog.png" end
    if d:find("overcast") or d:find("cloudy") then
        if d:find("partly") then
            return isNight and "wx_cloud-moon.png" or "wx_cloud-sun.png"
        end
        return "wx_cloud.png"
    end
    if d:find("clear") or d:find("sunny") then
        return isNight and "wx_moon.png" or "wx_sun.png"
    end
    return "wx_cloud.png"
end

-- ipinfo.io -> lat,lon ; wttr.in -> current conditions. Cached 10 minutes.
function Info.fetch()
    if Info.fetching then return end
    if Info.wx and (tick() - Info.fetchedAt) < 600 then return end
    Info.fetching = true
    task.spawn(function()
        local wx
        pcall(function()
            local loc, city
            local okL, raw = pcall(function() return game:HttpGet("https://ipinfo.io/json") end)
            if okL and raw then
                local okJ, j = pcall(function() return HttpService:JSONDecode(raw) end)
                if okJ and type(j) == "table" then
                    loc = j.loc
                    city = j.city
                end
            end
            if not loc or loc == "" then return end

            local okW, wraw = pcall(function()
                return game:HttpGet("https://wttr.in/" .. loc .. "?format=j1")
            end)
            if not (okW and wraw) then return end
            local okD, wd = pcall(function() return HttpService:JSONDecode(wraw) end)
            if not (okD and type(wd) == "table" and wd.current_condition) then return end

            local c = wd.current_condition[1]
            if not c then return end
            wx = {
                tempC = tonumber(c.temp_C),
                tempF = tonumber(c.temp_F),
                desc  = (c.weatherDesc and c.weatherDesc[1] and c.weatherDesc[1].value) or "",
                humid = c.humidity,
                city  = city,
            }

            -- wttr gives eight 3-hour slots per day. Today's tail plus
            -- tomorrow's head, so an evening lookup does not run out of
            -- forecast at midnight and show nothing.
            local slots = {}
            for d = 1, math.min(2, #wd.weather) do
                for _, e in ipairs(wd.weather[d].hourly or {}) do
                    slots[#slots + 1] = {
                        hour = math.floor((tonumber(e.time) or 0) / 100)
                               + (d - 1) * 24,
                        code = tonumber(e.weatherCode) or 113,
                        temp = tonumber(e.tempC),
                        rain = tonumber(e.chanceofrain) or 0,
                        snow = tonumber(e.chanceofsnow) or 0,
                        desc = (e.weatherDesc and e.weatherDesc[1]
                                and e.weatherDesc[1].value) or "",
                    }
                end
            end
            wx.slots = slots
        end)
        Info.wx = wx
        Info.fetchedAt = tick()
        Info.fetching = false
        pcall(Info.refresh)
    end)
end

function Info.refresh()
    if not Info.wxText then return end
    local wx = Info.wx
    if not wx or not wx.tempC then
        Info.wxText.Text = "Weather unavailable"
        Info.wxIcon.ImageTransparency = 1
        Info.wxIcon:SetAttribute("_shownT", 1)
        return
    end
    local hour = math.floor(Info.now() / 3600)
    local night = (hour < 6 or hour >= 19)
    Info.wxText.Text = string.format("%d\194\176C  \194\183  %s", wx.tempC, wx.desc)
    Info.wxSub.Text = (wx.city and wx.city ~= "" and wx.city or "")
        .. (wx.humid and ("   humidity " .. wx.humid .. "%") or "")
    local id = UI.icon(Info.glyphFor(wx.desc, night))
    if id ~= "" then
        Info.wxIcon.Image = id
        Info.wxIcon.ImageTransparency = 0
        Info.wxIcon:SetAttribute("_shownT", 0)
    end

    if Info.fLine then
        local head = Info.headline()
        Info.fLine.Text = head or "Next few hours"
        Info.fLine.TextColor3 = head and UI.accent or UI.textMuted
    end
    if Info.fSlots then
        local nxt = Info.nextSlots(Info.SLOTS)
        for i, sl in ipairs(Info.fSlots) do
            local e = nxt[i]
            if e then
                local h = e.hour % 24
                local h12 = h % 12
                if h12 == 0 then h12 = 12 end
                sl.text.Text = string.format("%d%s %d\194\176",
                    h12, (h < 12) and "am" or "pm", e.temp or 0)
                local gid = UI.icon(Info.glyphFor(e.desc, h < 6 or h >= 19))
                if gid ~= "" then
                    sl.icon.Image = gid
                    sl.icon.ImageTransparency = 0.15
                    sl.icon:SetAttribute("_shownT", 0.15)
                end
            else
                sl.text.Text = ""
                sl.icon.ImageTransparency = 1
            end
        end
    end
end

function Info.build()
    local clip, p = UI.makeDrawer("InfoPanel", UI.EXP_W, Info.H, Bar.gui)
    Info.clip, Info.panel = clip, p

    -- Digital time (hero) -- thin Manrope, same as the musicbot card.
    local dig = Instance.new("TextLabel")
    dig.Name = "Digital"
    dig.Position = UDim2.new(0, 18, 0, 12)
    dig.Size = UDim2.new(0, 210, 0, 44)
    dig.BackgroundTransparency = 1
    dig.Text = "--:--:--"
    dig.TextColor3 = UI.textPrimary
    dig.TextXAlignment = Enum.TextXAlignment.Left
    dig.TextYAlignment = Enum.TextYAlignment.Bottom
    dig.TextSize = 38
    dig.ZIndex = 42
    dig.Parent = p
    UI.applyFont(dig, Enum.FontWeight.Light)
    Info.digital = dig

    local date = Instance.new("TextLabel")
    date.Name = "Date"
    date.Position = UDim2.new(0, 19, 0, 58)
    date.Size = UDim2.new(0, 210, 0, 18)
    date.BackgroundTransparency = 1
    date.Text = ""
    date.TextColor3 = UI.textMuted
    date.TextXAlignment = Enum.TextXAlignment.Left
    date.TextSize = UI.T_ROW
    date.ZIndex = 42
    date.Parent = p
    UI.applyFont(date, Enum.FontWeight.Medium)
    Info.date = date

    -- Weather row (bottom-left)
    local wIco = Instance.new("ImageLabel")
    wIco.Name = "WxIcon"
    wIco.Position = UDim2.new(0, 18, 0, 84)
    wIco.Size = UDim2.fromOffset(22, 22)
    wIco.BackgroundTransparency = 1
    wIco.ImageColor3 = UI.accent
    wIco.ImageTransparency = 1
    wIco.ZIndex = 42
    wIco.Parent = p
    Info.wxIcon = wIco

    local wTxt = Instance.new("TextLabel")
    wTxt.Name = "WxText"
    wTxt.Position = UDim2.new(0, 46, 0, 82)
    wTxt.Size = UDim2.new(0, 200, 0, 16)
    wTxt.BackgroundTransparency = 1
    wTxt.Text = "Fetching weather..."
    wTxt.TextColor3 = Color3.fromRGB(214, 216, 224)
    wTxt.TextXAlignment = Enum.TextXAlignment.Left
    wTxt.TextSize = UI.T_ROW
    wTxt.TextTruncate = Enum.TextTruncate.AtEnd
    wTxt.ZIndex = 42
    wTxt.Parent = p
    UI.applyFont(wTxt, Enum.FontWeight.SemiBold)
    Info.wxText = wTxt

    local wSub = Instance.new("TextLabel")
    wSub.Name = "WxSub"
    wSub.Position = UDim2.new(0, 46, 0, 98)
    wSub.Size = UDim2.new(0, 200, 0, 14)
    wSub.BackgroundTransparency = 1
    wSub.Text = ""
    wSub.TextColor3 = UI.textMuted
    wSub.TextXAlignment = Enum.TextXAlignment.Left
    wSub.TextSize = UI.T_SMALL
    wSub.TextTruncate = Enum.TextTruncate.AtEnd
    wSub.ZIndex = 42
    wSub.Parent = p
    UI.applyFont(wSub, Enum.FontWeight.Regular)
    Info.wxSub = wSub

    -- ── Next few hours ─────────────────────────────────────────────────
    -- One line: a headline only when something is coming that would change
    -- what you do, then the next four 3-hour slots as icon-over-hour.
    local fLine = Instance.new("TextLabel")
    fLine.Name = "Forecast"
    fLine.Position = UDim2.new(0, 18, 0, 116)
    fLine.Size = UDim2.new(1, -36, 0, 14)
    fLine.BackgroundTransparency = 1
    fLine.Text = ""
    fLine.TextColor3 = UI.accent
    fLine.TextXAlignment = Enum.TextXAlignment.Left
    fLine.TextSize = UI.T_SMALL
    fLine.TextTruncate = Enum.TextTruncate.AtEnd
    fLine.ZIndex = 42
    fLine.Parent = p
    UI.applyFont(fLine, Enum.FontWeight.SemiBold)
    Info.fLine = fLine

    Info.fSlots = {}
    for i = 1, Info.SLOTS do
        local x = 18 + (i - 1) * 62

        local ic = Instance.new("ImageLabel")
        ic.Position = UDim2.new(0, x, 0, 132)
        ic.Size = UDim2.fromOffset(15, 15)
        ic.BackgroundTransparency = 1
        ic.ImageColor3 = Color3.fromRGB(214, 216, 224)
        ic.ImageTransparency = 1
        ic.ZIndex = 42
        ic.Parent = p

        local tx = Instance.new("TextLabel")
        tx.Position = UDim2.new(0, x + 19, 0, 131)
        tx.Size = UDim2.fromOffset(42, 16)
        tx.BackgroundTransparency = 1
        tx.Text = ""
        tx.TextColor3 = UI.textMuted
        tx.TextXAlignment = Enum.TextXAlignment.Left
        tx.TextSize = UI.T_EYEBROW
        tx.ZIndex = 42
        tx.Parent = p
        UI.applyFont(tx, Enum.FontWeight.Medium)

        Info.fSlots[i] = { icon = ic, text = tx }
    end

    -- ── Analog clock (right) ────────────────────────────────────────────
    local R = 40
    local cx, cy = UI.EXP_W - 56, Info.H / 2
    local face = Instance.new("Frame")
    face.Name = "Clock"
    face.AnchorPoint = Vector2.new(0.5, 0.5)
    face.Position = UDim2.new(0, cx, 0, cy)
    face.Size = UDim2.fromOffset(R * 2, R * 2)
    face.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    face.BackgroundTransparency = 0.94
    face.BorderSizePixel = 0
    face.ZIndex = 42
    face.Parent = p
    Instance.new("UICorner", face).CornerRadius = UDim.new(1, 0)
    local fst = Instance.new("UIStroke", face)
    fst.Color = Color3.fromRGB(255, 255, 255)
    fst.Thickness = 1
    fst.Transparency = 0.82

    -- 12 hour ticks; cardinals longer and brighter.
    for i = 0, 11 do
        local tc = Instance.new("Frame")
        tc.AnchorPoint = Vector2.new(0.5, 0.5)
        tc.Position = UDim2.fromScale(0.5, 0.5)
        tc.Size = UDim2.fromOffset(R * 2, R * 2)
        tc.BackgroundTransparency = 1
        tc.Rotation = i * 30
        tc.ZIndex = 42
        tc.Parent = face
        local card = (i % 3 == 0)
        local tick_ = Instance.new("Frame")
        tick_.AnchorPoint = Vector2.new(0.5, 0)
        tick_.Position = UDim2.new(0.5, 0, 0, 5)
        tick_.Size = UDim2.fromOffset(card and 2 or 1, card and 7 or 5)
        tick_.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        tick_.BackgroundTransparency = card and 0.4 or 0.66
        tick_.BorderSizePixel = 0
        tick_.ZIndex = 42
        tick_.Parent = tc
        Instance.new("UICorner", tick_).CornerRadius = UDim.new(1, 0)
    end

    -- Roblox Rotation pivots about an element's GEOMETRIC CENTRE, not its
    -- AnchorPoint -- so a hand anchored at its base would still spin about
    -- its own middle. Fix: a face-sized container centred on the clock, with
    -- the hand pointing up from centre inside it; rotate the CONTAINER.
    local function hand(len, thick, col, z, tail)
        local cont = Instance.new("Frame")
        cont.AnchorPoint = Vector2.new(0.5, 0.5)
        cont.Position = UDim2.fromScale(0.5, 0.5)
        cont.Size = UDim2.fromOffset(R * 2, R * 2)
        cont.BackgroundTransparency = 1
        cont.ZIndex = z
        cont.Parent = face

        local h = Instance.new("Frame")
        h.AnchorPoint = Vector2.new(0.5, 1)
        h.Position = UDim2.fromScale(0.5, 0.5)
        h.Size = UDim2.fromOffset(thick, len)
        h.BackgroundColor3 = col
        h.BorderSizePixel = 0
        h.ZIndex = z
        h.Parent = cont
        Instance.new("UICorner", h).CornerRadius = UDim.new(1, 0)

        if tail then
            local tl = Instance.new("Frame")
            tl.AnchorPoint = Vector2.new(0.5, 0)
            tl.Position = UDim2.fromScale(0.5, 0.5)
            tl.Size = UDim2.fromOffset(thick, tail)
            tl.BackgroundColor3 = col
            tl.BorderSizePixel = 0
            tl.ZIndex = z
            tl.Parent = cont
            Instance.new("UICorner", tl).CornerRadius = UDim.new(1, 0)
        end
        return cont
    end

    Info.hHour = hand(R * 0.46, 3, Color3.fromRGB(238, 239, 244), 43)
    Info.hMin  = hand(R * 0.70, 2, Color3.fromRGB(238, 239, 244), 44)
    Info.hSec  = hand(R * 0.86, 1, UI.accent, 45, R * 0.24)

    local hub = Instance.new("Frame")
    hub.AnchorPoint = Vector2.new(0.5, 0.5)
    hub.Position = UDim2.fromScale(0.5, 0.5)
    hub.Size = UDim2.fromOffset(7, 7)
    hub.BackgroundColor3 = UI.accent
    hub.BorderSizePixel = 0
    hub.ZIndex = 46
    hub.Parent = face
    Instance.new("UICorner", hub).CornerRadius = UDim.new(1, 0)
    local hubr = Instance.new("UIStroke", hub)
    hubr.Color = UI.glassFill
    hubr.Thickness = 1
    hubr.Transparency = 0.3

    Info.startClock()
end

-- One render loop drives both clocks; it returns immediately when the card
-- is not visible, so it costs nothing at idle.
function Info.startClock()
    if Info.clockLoop then return end
    local lastSec = -1
    Info.clockLoop = RunService.RenderStepped:Connect(function()
        if not (Info.clip and Info.clip.Visible) then return end
        local day = Info.now()
        local h = math.floor(day / 3600)
        local m = math.floor((day % 3600) / 60)
        local s = day % 60                       -- float -> smooth sweep

        Info.hHour.Rotation = ((h % 12) + m / 60) * 30
        Info.hMin.Rotation  = (m + s / 60) * 6
        Info.hSec.Rotation  = s * 6

        local si = math.floor(s)
        if si ~= lastSec then
            lastSec = si
            local h12 = h % 12
            if h12 == 0 then h12 = 12 end
            Info.digital.Text = string.format("%d:%02d:%02d", h12, m, si)
            local ok, wd = pcall(function() return os.date("%A") end)
            Info.date.Text = (h < 12 and "AM" or "PM") .. (ok and ("  \194\183  " .. wd) or "")
        end
    end)
end

function Info.show()
    if not Info.panel or Info.open then return end
    Info.open = true
    Info.fetch()
    Info.refresh()
    UI.openDrawerAtY(Info.clip, Info.panel, Cards.slotY(Info.clip))
    Cards.reflow(true)
end

function Info.hide()
    if not Info.open then return end
    Info.open = false
    UI.closeDrawer(Info.clip, Info.panel)
    Cards.reflow(true)
end
-- ════════════════════════════════════════════════════════════════════════
--  PERFORMANCE CARD  (!stats)
--  Was a loadstring to a pastebin GUI in someone else's design language.
--  Native now: it starts in the drawer stack with the clock and settings,
--  and can be dragged off to sit anywhere, minimised to a strip, or closed.
--  Named Perf, not Stats: Stats is a Roblox service this reads from.
-- ════════════════════════════════════════════════════════════════════════
Perf = {
    open = false, min = false, detached = false,
    H = 168, MIN_H = 46,
    POINTS = 28,        -- samples held for the graph
    FILL = 56,          -- fill columns; 2px each, so the sawtooth is invisible
    GW = 112, GH = 44,  -- graph box
    samples = {}, cols = {}, segs = {},
}

-- Rolling 0.5s window. Instantaneous 1/dt jitters far too much to read as a
-- number; the graph is where the frame-to-frame variance belongs.
Perf.acc, Perf.frames, Perf.fps = 0, 0, 0

local function statsService()
    local ok, s = pcall(function() return game:GetService("Stats") end)
    return ok and s or nil
end

-- Each of these can be missing: Data Ping is absent in Studio and on some
-- clients, GetTotalMemoryUsageMb is not on every Roblox version.
function Perf.ping()
    local s = statsService()
    if not s then return nil end
    local ok, v = pcall(function()
        return s.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    return (ok and type(v) == "number") and v or nil
end

function Perf.memory()
    local s = statsService()
    if not s then return nil end
    local ok, v = pcall(function() return s:GetTotalMemoryUsageMb() end)
    return (ok and type(v) == "number") and v or nil
end

-- ── Chrome: minimise + close, top right ─────────────────────────────────
local function chromeButton(parent, iconFile, x, onClick)
    local b = Instance.new("TextButton")
    b.AnchorPoint = Vector2.new(1, 0)
    b.Position = UDim2.new(1, x, 0, 10)
    b.Size = UDim2.fromOffset(20, 20)
    b.AutoButtonColor = false
    b.Text = ""
    b.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    b.BackgroundTransparency = 0.92
    b.BorderSizePixel = 0
    b.ZIndex = 44
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)

    local ic = Instance.new("ImageLabel")
    ic.AnchorPoint = Vector2.new(0.5, 0.5)
    ic.Position = UDim2.new(0.5, 0, 0.5, 0)
    ic.Size = UDim2.fromOffset(11, 11)
    ic.BackgroundTransparency = 1
    ic.Image = UI.icon(iconFile)
    ic.ImageColor3 = Color3.fromRGB(214, 216, 224)
    ic.ZIndex = 45
    ic.Parent = b

    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), { BackgroundTransparency = 0.82 }):Play()
        TweenService:Create(ic, TweenInfo.new(0.12), { ImageColor3 = UI.accent }):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.14), { BackgroundTransparency = 0.92 }):Play()
        TweenService:Create(ic, TweenInfo.new(0.14),
            { ImageColor3 = Color3.fromRGB(214, 216, 224) }):Play()
    end)
    b.MouseButton1Click:Connect(onClick)
    return b, ic
end

function Perf.build()
    -- A theme change rebuilds the whole overlay, so the parked position and
    -- the collapsed height die with the old panel. Say so, rather than
    -- leaving a flag claiming a state the new instances do not have.
    Perf.detached, Perf.min = false, false
    local clip, p = UI.makeDrawer("PerfPanel", UI.EXP_W, Perf.H, Bar.gui)
    Perf.clip, Perf.panel = clip, p
    -- Dragging moves the panel out of the clip's bounds, so the clip must
    -- stop clipping the moment the card is free-floating.
    clip.ClipsDescendants = true

    UI.eyebrow(p, "PERFORMANCE")
    Perf.minBtn = chromeButton(p, "st_minimize.png", -40, function() Perf.setMin(not Perf.min) end)
    Perf.minIcon = Perf.minBtn:FindFirstChildWhichIsA("ImageLabel")
    chromeButton(p, "st_x.png", -14, function() Perf.hide() end)

    -- Everything that disappears when minimised lives in one frame, so the
    -- collapse is one Visible flip rather than a list to keep in sync.
    local body = Instance.new("Frame")
    body.Name = "Body"
    body.Position = UDim2.new(0, 0, 0, 0)
    body.Size = UDim2.fromScale(1, 1)
    body.BackgroundTransparency = 1
    body.ZIndex = 42
    body.Parent = p
    Perf.body = body

    -- Hero: same thin Manrope as the clock, so the two cards read as one
    -- family when they are stacked.
    local fps = Instance.new("TextLabel")
    fps.Name = "Fps"
    fps.Position = UDim2.new(0, 18, 0, 28)
    fps.Size = UDim2.new(0, 150, 0, 46)
    fps.BackgroundTransparency = 1
    fps.Text = "--"
    fps.TextColor3 = UI.textPrimary
    fps.TextXAlignment = Enum.TextXAlignment.Left
    fps.TextYAlignment = Enum.TextYAlignment.Bottom
    fps.TextSize = 38
    fps.ZIndex = 43
    fps.Parent = body
    UI.applyFont(fps, Enum.FontWeight.Light)
    Perf.fpsLabel = fps

    local unit = Instance.new("TextLabel")
    unit.Position = UDim2.new(0, 19, 0, 74)
    unit.Size = UDim2.new(0, 140, 0, 14)
    unit.BackgroundTransparency = 1
    unit.Text = "FRAMES PER SECOND"
    unit.TextColor3 = UI.textMuted
    unit.TextXAlignment = Enum.TextXAlignment.Left
    unit.TextSize = UI.T_EYEBROW
    unit.ZIndex = 43
    unit.Parent = body
    UI.applyFont(unit, Enum.FontWeight.Bold)

    -- ── Graph ──────────────────────────────────────────────────────────
    local g = Instance.new("Frame")
    g.Name = "Graph"
    g.AnchorPoint = Vector2.new(1, 0)
    g.Position = UDim2.new(1, -18, 0, 30)
    g.Size = UDim2.fromOffset(Perf.GW, Perf.GH)
    g.BackgroundTransparency = 1
    g.ZIndex = 43
    g.Parent = body
    Perf.graph = g

    -- Area fill: narrow columns under the line, faded out toward the floor
    -- by one gradient over the whole set. At 2px they read as a solid wash,
    -- not as bars.
    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.fromScale(1, 1)
    fill.BackgroundTransparency = 1
    fill.ZIndex = 43
    fill.Parent = g

    local colW = Perf.GW / Perf.FILL
    for i = 1, Perf.FILL do
        local c = Instance.new("Frame")
        c.AnchorPoint = Vector2.new(0, 1)
        c.Position = UDim2.new(0, math.floor((i - 1) * colW), 1, 0)
        c.Size = UDim2.fromOffset(math.ceil(colW) + 1, 1)
        c.BackgroundColor3 = UI.accent
        c.BorderSizePixel = 0
        c.ZIndex = 43
        c.Parent = fill
        -- One gradient PER COLUMN. UIGradient only tints the instance it is
        -- parented to -- it does not reach descendants -- so a single
        -- gradient on the container left every column at full opacity and
        -- the area read as a solid block with the line lost inside it.
        local cg = Instance.new("UIGradient", c)
        cg.Rotation = 90
        cg.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0.0, 0.62),
            NumberSequenceKeypoint.new(1.0, 1.0),
        })
        Perf.cols[i] = c
    end

    -- The line itself: one rotated segment per gap between samples.
    for i = 1, Perf.POINTS - 1 do
        local sg = Instance.new("Frame")
        sg.AnchorPoint = Vector2.new(0.5, 0.5)
        sg.Size = UDim2.fromOffset(1, 2)
        sg.BackgroundColor3 = UI.accent
        sg.BackgroundTransparency = 0.05
        sg.BorderSizePixel = 0
        sg.ZIndex = 45
        sg.Parent = g
        Perf.segs[i] = sg
    end

    -- Emphasised endpoint: where the eye should land is "now".
    local dot = Instance.new("Frame")
    dot.Name = "Head"
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.Size = UDim2.fromOffset(5, 5)
    dot.BackgroundColor3 = UI.accent
    dot.BorderSizePixel = 0
    dot.ZIndex = 46
    dot.Parent = g
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
    Perf.head = dot

    local base = Instance.new("Frame")
    base.AnchorPoint = Vector2.new(0, 1)
    base.Position = UDim2.new(0, 0, 1, 0)
    base.Size = UDim2.new(1, 0, 0, 1)
    base.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    base.BackgroundTransparency = 0.9
    base.BorderSizePixel = 0
    base.ZIndex = 43
    base.Parent = g

    local peak = Instance.new("TextLabel")
    peak.AnchorPoint = Vector2.new(1, 0)
    peak.Position = UDim2.new(1, -18, 0, 74)
    peak.Size = UDim2.new(0, 112, 0, 14)
    peak.BackgroundTransparency = 1
    peak.Text = ""
    peak.TextColor3 = UI.textMuted
    peak.TextXAlignment = Enum.TextXAlignment.Right
    peak.TextSize = UI.T_EYEBROW
    peak.ZIndex = 43
    peak.Parent = body
    UI.applyFont(peak, Enum.FontWeight.Bold)
    Perf.peakLabel = peak

    -- ── Bottom row: three cells across the card ────────────────────────
    Perf.cells = {}
    local defs = {
        { key = "ping",    icon = "st_wifi.png",         label = "PING" },
        { key = "memory",  icon = "st_memory-stick.png", label = "MEMORY" },
        { key = "players", icon = "st_users.png",        label = "PLAYERS" },
    }
    local cellW = (UI.EXP_W - 36) / #defs
    for i, d in ipairs(defs) do
        local x = 18 + (i - 1) * cellW

        local ic = Instance.new("ImageLabel")
        ic.Position = UDim2.new(0, x, 0, 116)
        ic.Size = UDim2.fromOffset(14, 14)
        ic.BackgroundTransparency = 1
        ic.Image = UI.icon(d.icon)
        ic.ImageColor3 = UI.accent
        ic.ZIndex = 43
        ic.Parent = body

        local val = Instance.new("TextLabel")
        val.Position = UDim2.new(0, x + 20, 0, 113)
        val.Size = UDim2.new(0, cellW - 24, 0, 20)
        val.BackgroundTransparency = 1
        val.Text = "--"
        val.TextColor3 = Color3.fromRGB(232, 233, 238)
        val.TextXAlignment = Enum.TextXAlignment.Left
        val.TextSize = UI.T_ROW
        val.TextTruncate = Enum.TextTruncate.AtEnd
        val.ZIndex = 43
        val.Parent = body
        UI.applyFont(val, Enum.FontWeight.SemiBold)

        local lab = Instance.new("TextLabel")
        lab.Position = UDim2.new(0, x, 0, 136)
        lab.Size = UDim2.new(0, cellW - 8, 0, 12)
        lab.BackgroundTransparency = 1
        lab.Text = d.label
        lab.TextColor3 = UI.textMuted
        lab.TextXAlignment = Enum.TextXAlignment.Left
        lab.TextSize = UI.T_EYEBROW
        lab.ZIndex = 43
        lab.Parent = body
        UI.applyFont(lab, Enum.FontWeight.Bold)

        Perf.cells[d.key] = val
    end

    -- Minimised strip: one line, shown only while collapsed.
    local mini = Instance.new("TextLabel")
    mini.Name = "Mini"
    mini.Position = UDim2.new(0, 18, 0, 24)
    mini.Size = UDim2.new(1, -100, 0, 16)
    mini.BackgroundTransparency = 1
    mini.Text = ""
    mini.TextColor3 = Color3.fromRGB(232, 233, 238)
    mini.TextXAlignment = Enum.TextXAlignment.Left
    mini.TextSize = UI.T_ROW
    mini.TextTruncate = Enum.TextTruncate.AtEnd
    mini.Visible = false
    mini.ZIndex = 43
    mini.Parent = p
    UI.applyFont(mini, Enum.FontWeight.SemiBold)
    Perf.mini = mini

    Perf.wireDrag()
    p.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
           or i.UserInputType == Enum.UserInputType.Touch then
            Perf.dragBegan(i)
        end
    end)
end

-- ── Graph drawing ───────────────────────────────────────────────────────
-- Scaled to the window's own peak plus headroom, so a locked 60fps session
-- reads as clearly as an uncapped one instead of pinning to the ceiling.
function Perf.pointY(v, top)
    return Perf.GH - math.clamp(v / top, 0, 1) * Perf.GH
end

function Perf.drawGraph()
    local n = #Perf.samples
    if n == 0 or not Perf.graph then return end

    local top, low = 1, math.huge
    for _, v in ipairs(Perf.samples) do
        if v > top then top = v end
        if v < low then low = v end
    end
    top = top * 1.12                       -- headroom, so the line never clips

    -- Sample value at graph position 0..1, holding the oldest value to the
    -- left while the window is still filling.
    local function at(t)
        local first = math.max(1, n - Perf.POINTS + 1)
        local have = n - first + 1
        local fx = 1 + t * (Perf.POINTS - 1)          -- 1 .. POINTS
        local shift = Perf.POINTS - have              -- empty slots on the left
        local idx = first + (fx - 1 - shift)
        if idx < first then return Perf.samples[first] end
        local i0 = math.floor(idx)
        local f = idx - i0
        local a = Perf.samples[i0] or Perf.samples[first]
        local b = Perf.samples[i0 + 1] or a
        return a + (b - a) * f
    end

    for i = 1, Perf.FILL do
        local t = (i - 0.5) / Perf.FILL
        local y = Perf.pointY(at(t), top)
        Perf.cols[i].Size = UDim2.fromOffset(Perf.cols[i].Size.X.Offset,
            math.max(1, math.floor(Perf.GH - y)))
    end

    local prevX, prevY
    for i = 1, Perf.POINTS do
        local t = (i - 1) / (Perf.POINTS - 1)
        local x, y = t * Perf.GW, Perf.pointY(at(t), top)
        if prevX then
            local dx, dy = x - prevX, y - prevY
            local len = math.max(1, math.sqrt(dx * dx + dy * dy))
            local sg = Perf.segs[i - 1]
            sg.Position = UDim2.fromOffset(
                math.floor((prevX + x) / 2), math.floor((prevY + y) / 2))
            sg.Size = UDim2.fromOffset(math.ceil(len) + 1, 2)
            sg.Rotation = math.deg(math.atan2(dy, dx))
        end
        prevX, prevY = x, y
    end

    Perf.head.Position = UDim2.fromOffset(math.floor(prevX), math.floor(prevY))
    Perf.peakLabel.Text = string.format("%d LOW  \194\183  %d PEAK",
        math.floor(low + 0.5), math.floor((top / 1.12) + 0.5))
end

function Perf.refresh()
    if not Perf.panel then return end
    local fpsText = (Perf.fps > 0) and tostring(math.floor(Perf.fps + 0.5)) or "--"
    Perf.fpsLabel.Text = fpsText

    local p = Perf.ping()
    local pingText = p and (tostring(math.floor(p + 0.5)) .. " ms") or "n/a"
    Perf.cells.ping.Text = pingText

    local m = Perf.memory()
    if m and m >= 1024 then
        Perf.cells.memory.Text = string.format("%.1f GB", m / 1024)
    else
        Perf.cells.memory.Text = m and (tostring(math.floor(m)) .. " MB") or "n/a"
    end

    local ok, now, max = pcall(function()
        return #Players:GetPlayers(), Players.MaxPlayers
    end)
    Perf.cells.players.Text = ok and (tostring(now) .. " / " .. tostring(max)) or "n/a"

    Perf.mini.Text = fpsText .. " FPS  \194\183  " .. pingText
end

function Perf.startLoop()
    if Perf.loop then return end
    local sinceRefresh = 0
    Perf.loop = RunService.RenderStepped:Connect(function(dt)
        -- Sample unconditionally so the graph is already populated when the
        -- card opens; only the drawing is gated on visibility.
        Perf.acc = Perf.acc + dt
        Perf.frames = Perf.frames + 1
        if Perf.acc >= 0.5 then
            Perf.fps = Perf.frames / Perf.acc
            Perf.acc, Perf.frames = 0, 0
            Perf.samples[#Perf.samples + 1] = Perf.fps
            while #Perf.samples > Perf.POINTS do table.remove(Perf.samples, 1) end
        end

        if not (Perf.clip and Perf.clip.Visible) then return end
        sinceRefresh = sinceRefresh + dt
        if sinceRefresh < 0.5 then return end
        sinceRefresh = 0
        Perf.refresh()
        if not Perf.min then Perf.drawGraph() end
    end)
end

-- ── Minimise ────────────────────────────────────────────────────────────
function Perf.setMin(on)
    if not Perf.panel or Perf.min == on then return end
    Perf.min = on
    local h = on and Perf.MIN_H or Perf.H
    local ti = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

    if on then Perf.body.Visible = false Perf.mini.Visible = true end
    Perf.minIcon.Image = UI.icon(on and "st_maximize.png" or "st_minimize.png")

    UI.setTargetH(Perf.panel, h)
    TweenService:Create(Perf.clip, ti, { Size = UDim2.fromOffset(UI.EXP_W, h + 12) }):Play()
    local tp = TweenService:Create(Perf.panel, ti, { Size = UDim2.fromOffset(UI.EXP_W, h) })
    tp:Play()
    if not on then
        tp.Completed:Connect(function()
            if not Perf.min then Perf.mini.Visible = false Perf.body.Visible = true end
        end)
    end
    Cards.reflow(true)
end

-- ── Drag ────────────────────────────────────────────────────────────────
-- Registered once, not per build: build() runs again on every theme change,
-- and a second copy of these handlers would move the card twice per pixel.
function Perf.wireDrag()
    if Perf.dragBound then return end
    Perf.dragBound = true
    local dragging, grab, origin = false, nil, nil

    local function clampTo(off)
        local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
                   or Vector2.new(1280, 720)
        -- clip is anchored to the right edge (scale 1), so X offsets are
        -- negative going left; keep a strip of the card on screen either way
        local minX = -(vp.X - 60)
        return Vector2.new(math.clamp(off.X, minX, -8),
                           math.clamp(off.Y, 8, math.max(8, vp.Y - 48)))
    end

    Perf.dragBegan = function(i)
        if not (Perf.clip and Perf.clip.Visible) then return end
        dragging = true
        grab = Vector2.new(i.Position.X, i.Position.Y)
        origin = Vector2.new(Perf.clip.Position.X.Offset, Perf.clip.Position.Y.Offset)
    end

    UserInputService.InputChanged:Connect(function(i)
        if not dragging then return end
        if i.UserInputType ~= Enum.UserInputType.MouseMovement
           and i.UserInputType ~= Enum.UserInputType.Touch then return end
        local d = Vector2.new(i.Position.X, i.Position.Y) - grab
        -- The first real movement detaches it: reflow must stop owning a
        -- card the user has parked somewhere deliberately.
        if not Perf.detached and d.Magnitude > 3 then
            Perf.detached = true
            Perf.clip:SetAttribute("_detached", true)
            Perf.clip.ClipsDescendants = false
            Cards.reflow(true)
        end
        if not Perf.detached then return end
        local off = clampTo(origin + d)
        Perf.clip.Position = UDim2.new(1, off.X, 0, off.Y)
    end)

    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
           or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

function Perf.show()
    if not Perf.panel or Perf.open then return end
    Perf.open = true
    Perf.startLoop()
    Perf.refresh()
    Perf.drawGraph()
    if Perf.detached then
        -- Already parked: reveal in place rather than sliding out of the bar.
        Perf.clip.Visible = true
        UI.fadeContent(Perf.panel, false, true)
    else
        UI.openDrawerAtY(Perf.clip, Perf.panel, Cards.slotY(Perf.clip))
        Cards.reflow(true)
    end
end

function Perf.hide()
    if not Perf.open then return end
    Perf.open = false
    if Perf.detached then
        Perf.clip.Visible = false
    else
        UI.closeDrawer(Perf.clip, Perf.panel)
    end
    Cards.reflow(true)
end

function Perf.toggle()
    if Perf.open then Perf.hide() else Perf.show() end
end

-- ════════════════════════════════════════════════════════════════════════
--  COLOUR PICKER
--  Saturation/value square over a hue rail, hex field, presets. Lives on
--  top of whatever called it rather than being a second Modal, since Modal
--  only holds one panel and opening a picker would dismiss the ESP list
--  underneath it.
-- ════════════════════════════════════════════════════════════════════════
Picker = { open = false, W = 248, SQ_W = 216, SQ_H = 132, h = 0, s = 0, v = 1 }

function Picker.toHex(c)
    return string.format("#%02X%02X%02X",
        math.floor(c.R * 255 + 0.5),
        math.floor(c.G * 255 + 0.5),
        math.floor(c.B * 255 + 0.5))
end

-- Accepts "#RRGGBB", "RRGGBB" and the three-digit short form. Returns nil
-- for anything else so the field can just refuse to apply it.
function Picker.fromHex(str)
    local t = tostring(str or ""):gsub("%s", ""):gsub("^#", "")
    if #t == 3 then t = t:sub(1,1):rep(2) .. t:sub(2,2):rep(2) .. t:sub(3,3):rep(2) end
    if #t ~= 6 or t:match("%X") then return nil end
    local n = tonumber(t, 16)
    if not n then return nil end
    return Color3.fromRGB(
        math.floor(n / 65536) % 256,
        math.floor(n / 256) % 256,
        n % 256)
end

function Picker.color()
    return Color3.fromHSV(Picker.h, Picker.s, Picker.v)
end

function Picker.close()
    if not Picker.open then return end
    Picker.open = false
    local gui = Picker.gui
    Picker.gui = nil
    if not gui then return end
    local panel = gui:FindFirstChild("PickerPanel", true)
    if panel then
        TweenService:Create(panel,
            TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
                Size = UDim2.fromOffset(Picker.W - 20, panel.Size.Y.Offset - 14),
                BackgroundTransparency = 1,
            }):Play()
        UI.fadeContent(panel, true, true)
    end
    task.delay(0.24, function() pcall(function() gui:Destroy() end) end)
end

-- Registered once. Picker.show runs every time a swatch is clicked, and a
-- second copy of these would move the marker at twice the cursor speed.
function Picker.bind()
    if Picker.bound then return end
    Picker.bound = true

    UserInputService.InputChanged:Connect(function(i)
        if not Picker.dragging then return end
        if i.UserInputType ~= Enum.UserInputType.MouseMovement
           and i.UserInputType ~= Enum.UserInputType.Touch then return end
        Picker.applyDrag(i)
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
           or i.UserInputType == Enum.UserInputType.Touch then
            Picker.dragging = nil
        end
    end)
end

function Picker.applyDrag(input)
    local el = (Picker.dragging == "sv") and Picker.sq or Picker.hue
    if not el then return end
    local pos = input and input.Position
    local mx = pos and pos.X or UserInputService:GetMouseLocation().X
    local my = pos and pos.Y or UserInputService:GetMouseLocation().Y
    local fx = math.clamp((mx - el.AbsolutePosition.X) / math.max(1, el.AbsoluteSize.X), 0, 1)
    local fy = math.clamp((my - el.AbsolutePosition.Y) / math.max(1, el.AbsoluteSize.Y), 0, 1)

    if Picker.dragging == "sv" then
        Picker.s, Picker.v = fx, 1 - fy
    else
        Picker.h = fx
    end
    Picker.sync()
end

-- One place writes every dependent value, so the hex field, the preview,
-- the square's hue backdrop and the caller can never disagree.
function Picker.sync()
    if not Picker.open then return end
    local c = Picker.color()
    Picker.sq.BackgroundColor3 = Color3.fromHSV(Picker.h, 1, 1)
    Picker.svDot.Position = UDim2.fromScale(Picker.s, 1 - Picker.v)
    Picker.svDot.BackgroundColor3 = c
    Picker.hueDot.Position = UDim2.new(Picker.h, 0, 0.5, 0)
    Picker.hueDot.BackgroundColor3 = Color3.fromHSV(Picker.h, 1, 1)
    Picker.preview.BackgroundColor3 = c
    if not Picker.typing then Picker.hex.Text = Picker.toHex(c) end
    if Picker.onChange then pcall(Picker.onChange, c) end
end

function Picker.show(startColor, onChange)
    Picker.close()
    Picker.bind()
    Picker.onChange = onChange
    Picker.h, Picker.s, Picker.v = Color3.toHSV(startColor or Color3.new(1, 1, 1))
    Picker.open = true

    local gui = Instance.new("ScreenGui")
    gui.Name = "UHubLitePicker"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 10002          -- above the modal it was opened from
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function()
        gui.Parent = (typeof(gethui) == "function" and gethui())
                  or game:GetService("CoreGui")
    end)
    Picker.gui = gui

    local dim = Instance.new("TextButton")
    dim.Size = UDim2.fromScale(1, 1)
    dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    dim.BackgroundTransparency = 1
    dim.BorderSizePixel = 0
    dim.AutoButtonColor = false
    dim.Text = ""
    dim.ZIndex = 1
    dim.Parent = gui
    dim.MouseButton1Click:Connect(function() Picker.close() end)
    TweenService:Create(dim, TweenInfo.new(0.2), { BackgroundTransparency = 0.5 }):Play()

    local H = 300
    local panel = Instance.new("Frame")
    panel.Name = "PickerPanel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.new(0.5, 0, 0.5, 0)
    panel.Size = UDim2.fromOffset(Picker.W - 20, H - 14)
    panel.BackgroundColor3 = UI.cardFill
    panel.BackgroundTransparency = 1
    panel.BorderSizePixel = 0
    panel.ZIndex = 5
    panel.Parent = gui
    UI.glassify(panel, 14)
    UI.accentWash(panel)

    local PAD = 16

    local preview = Instance.new("Frame")
    preview.Position = UDim2.new(0, PAD, 0, 16)
    preview.Size = UDim2.fromOffset(22, 22)
    preview.BackgroundColor3 = startColor or Color3.new(1, 1, 1)
    preview.BorderSizePixel = 0
    preview.ZIndex = 6
    preview.Parent = panel
    Instance.new("UICorner", preview).CornerRadius = UDim.new(0, 6)
    Picker.preview = preview

    -- Hex doubles as the readout and the input: type or paste a value and
    -- it applies, which is the only way to hit an exact colour by hand.
    local hex = Instance.new("TextBox")
    hex.AnchorPoint = Vector2.new(1, 0)
    hex.Position = UDim2.new(1, -PAD, 0, 16)
    hex.Size = UDim2.fromOffset(96, 22)
    hex.BackgroundColor3 = Color3.fromRGB(42, 44, 52)
    hex.BackgroundTransparency = 0.25
    hex.BorderSizePixel = 0
    hex.Text = Picker.toHex(startColor or Color3.new(1, 1, 1))
    hex.TextColor3 = UI.textPrimary
    hex.TextXAlignment = Enum.TextXAlignment.Center
    hex.TextSize = UI.T_SMALL
    hex.ClearTextOnFocus = false
    hex.ZIndex = 6
    hex.Parent = panel
    Instance.new("UICorner", hex).CornerRadius = UDim.new(0, 6)
    UI.applyFont(hex, Enum.FontWeight.SemiBold)
    Picker.hex = hex

    hex.Focused:Connect(function() Picker.typing = true end)
    hex.FocusLost:Connect(function()
        Picker.typing = false
        local c = Picker.fromHex(hex.Text)
        if c then
            Picker.h, Picker.s, Picker.v = Color3.toHSV(c)
        end
        Picker.sync()          -- valid: apply it; invalid: put the old value back
    end)

    -- ── Saturation / value square ──────────────────────────────────────
    -- Pure hue underneath, white faded left-to-right for saturation, black
    -- faded bottom-to-top for value. Two gradients beat shipping an image.
    local sq = Instance.new("Frame")
    sq.Position = UDim2.new(0, PAD, 0, 48)
    sq.Size = UDim2.fromOffset(Picker.SQ_W, Picker.SQ_H)
    sq.BackgroundColor3 = Color3.fromHSV(Picker.h, 1, 1)
    sq.BorderSizePixel = 0
    sq.ClipsDescendants = true
    sq.ZIndex = 6
    sq.Parent = panel
    Instance.new("UICorner", sq).CornerRadius = UDim.new(0, 8)
    Picker.sq = sq

    local sat = Instance.new("Frame")
    sat.Size = UDim2.fromScale(1, 1)
    sat.BackgroundColor3 = Color3.new(1, 1, 1)
    sat.BorderSizePixel = 0
    sat.ZIndex = 7
    sat.Parent = sq
    local sg = Instance.new("UIGradient", sat)
    sg.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })

    local val = Instance.new("Frame")
    val.Size = UDim2.fromScale(1, 1)
    val.BackgroundColor3 = Color3.new(0, 0, 0)
    val.BorderSizePixel = 0
    val.ZIndex = 8
    val.Parent = sq
    local vg = Instance.new("UIGradient", val)
    vg.Rotation = 90
    vg.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })

    local svDot = Instance.new("Frame")
    svDot.AnchorPoint = Vector2.new(0.5, 0.5)
    svDot.Position = UDim2.fromScale(Picker.s, 1 - Picker.v)
    svDot.Size = UDim2.fromOffset(12, 12)
    svDot.BackgroundColor3 = startColor or Color3.new(1, 1, 1)
    svDot.BorderSizePixel = 0
    svDot.ZIndex = 9
    svDot.Parent = sq
    Instance.new("UICorner", svDot).CornerRadius = UDim.new(1, 0)
    local svs = Instance.new("UIStroke", svDot)
    svs.Color = Color3.new(1, 1, 1)
    svs.Thickness = 2
    Picker.svDot = svDot

    local svHit = Instance.new("TextButton")
    svHit.Size = UDim2.fromScale(1, 1)
    svHit.BackgroundTransparency = 1
    svHit.AutoButtonColor = false
    svHit.Text = ""
    svHit.ZIndex = 10
    svHit.Parent = sq
    svHit.InputBegan:Connect(function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseButton1
           and i.UserInputType ~= Enum.UserInputType.Touch then return end
        Picker.dragging = "sv"
        Picker.applyDrag(i)
    end)

    -- ── Hue rail ───────────────────────────────────────────────────────
    local hue = Instance.new("Frame")
    hue.Position = UDim2.new(0, PAD, 0, 48 + Picker.SQ_H + 14)
    hue.Size = UDim2.fromOffset(Picker.SQ_W, 14)
    hue.BackgroundColor3 = Color3.new(1, 1, 1)
    hue.BorderSizePixel = 0
    hue.ZIndex = 6
    hue.Parent = panel
    Instance.new("UICorner", hue).CornerRadius = UDim.new(1, 0)
    local hg = Instance.new("UIGradient", hue)
    hg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
        ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
        ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
        ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
        ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
        ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
    })
    Picker.hue = hue

    local hueDot = Instance.new("Frame")
    hueDot.AnchorPoint = Vector2.new(0.5, 0.5)
    hueDot.Position = UDim2.new(Picker.h, 0, 0.5, 0)
    hueDot.Size = UDim2.fromOffset(14, 14)
    hueDot.BackgroundColor3 = Color3.fromHSV(Picker.h, 1, 1)
    hueDot.BorderSizePixel = 0
    hueDot.ZIndex = 8
    hueDot.Parent = hue
    Instance.new("UICorner", hueDot).CornerRadius = UDim.new(1, 0)
    local hs = Instance.new("UIStroke", hueDot)
    hs.Color = Color3.new(1, 1, 1)
    hs.Thickness = 2
    Picker.hueDot = hueDot

    local hueHit = Instance.new("TextButton")
    hueHit.AnchorPoint = Vector2.new(0.5, 0.5)
    hueHit.Position = UDim2.fromScale(0.5, 0.5)
    hueHit.Size = UDim2.new(1, 0, 0, 24)     -- taller than it looks, to grab
    hueHit.BackgroundTransparency = 1
    hueHit.AutoButtonColor = false
    hueHit.Text = ""
    hueHit.ZIndex = 9
    hueHit.Parent = hue
    hueHit.InputBegan:Connect(function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseButton1
           and i.UserInputType ~= Enum.UserInputType.Touch then return end
        Picker.dragging = "hue"
        Picker.applyDrag(i)
    end)

    -- ── Presets ────────────────────────────────────────────────────────
    local py = 48 + Picker.SQ_H + 40
    local sw = (Picker.SQ_W - 7 * 6) / 8
    for i, c in ipairs(ESP.PALETTE) do
        local chip = Instance.new("TextButton")
        chip.Position = UDim2.new(0, PAD + (i - 1) * (sw + 6), 0, py)
        chip.Size = UDim2.fromOffset(math.floor(sw), 18)
        chip.AutoButtonColor = false
        chip.Text = ""
        chip.BackgroundColor3 = c
        chip.BorderSizePixel = 0
        chip.ZIndex = 6
        chip.Parent = panel
        Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 5)
        chip.MouseButton1Click:Connect(function()
            Picker.h, Picker.s, Picker.v = Color3.toHSV(c)
            Picker.sync()
        end)
    end

    local done = UI.gradButton(panel, "Done", "st_circle-check.png", "light")
    done.AnchorPoint = Vector2.new(1, 0)
    done.Position = UDim2.new(1, -PAD, 0, py + 30)
    done.ZIndex = 7
    done.MouseButton1Click:Connect(function() Picker.close() end)

    TweenService:Create(panel,
        TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Size = UDim2.fromOffset(Picker.W, H),
            BackgroundTransparency = UI.panelT(),
        }):Play()
    UI.fadeContent(panel, true)
    task.delay(0.05, function()
        if Picker.gui == gui then UI.fadeContent(panel, false, true) end
    end)

    Picker.sync()
    return panel
end

-- ════════════════════════════════════════════════════════════════════════
--  ESP  (!esp)
--  Ported from Universal Hub MAIN. Same features -- boxes, tracers, names,
--  health, distance, skeleton, chams, team check, max distance -- but MAIN
--  kept every intermediate in a _G.Temp* scratch global and wired chams up
--  as a second system with its own PlayerAdded handlers. Here the state is
--  local, and one object owns both a player's drawings and their highlight
--  so they are created and destroyed together.
-- ════════════════════════════════════════════════════════════════════════
ESP = {
    on = false,
    objs = {}, conns = {},
    cfg = {
        boxes = false, tracers = false, names = false, health = false,
        distance = false, skeleton = false, chams = false,
        teamCheck = false, meters = false, maxDist = 1000,
    },
    colors = {
        box       = Color3.fromRGB(255, 255, 255),
        tracer    = Color3.fromRGB(0, 255, 255),
        name      = Color3.fromRGB(255, 255, 255),
        health    = Color3.fromRGB(0, 255, 0),
        healthLow = Color3.fromRGB(255, 0, 0),
        distance  = Color3.fromRGB(255, 255, 255),
        skeleton  = Color3.fromRGB(255, 255, 255),
        cham      = Color3.fromRGB(255, 255, 255),
        enemy     = Color3.fromRGB(255, 100, 100),
        team      = Color3.fromRGB(100, 255, 100),
    },
}

ESP.PALETTE = {
    Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 60, 60),
    Color3.fromRGB(255, 150, 40),  Color3.fromRGB(255, 225, 60),
    Color3.fromRGB(80, 235, 120),  Color3.fromRGB(0, 235, 235),
    Color3.fromRGB(90, 150, 255),  Color3.fromRGB(215, 110, 255),
}

ESP.FEATURES = {
    { key = "boxes",    color = "box",      icon = "st_scan-eye.png",
      label = "Boxes",    desc = "Rectangle around each player" },
    { key = "tracers",  color = "tracer",   icon = "st_move.png",
      label = "Tracers",  desc = "Line from the bottom of your screen to them" },
    { key = "names",    color = "name",     icon = "st_users.png",
      label = "Names",    desc = "Display name above the head" },
    { key = "health",   color = "health",   icon = "st_heart.png",
      label = "Health",   desc = "Percentage, shading red as it drops" },
    { key = "distance", color = "distance", icon = "st_ruler.png",
      label = "Distance", desc = "How far away they are" },
    { key = "skeleton", color = "skeleton", icon = "st_person-standing.png",
      label = "Skeleton", desc = "Lines along the limbs, R6 and R15" },
    { key = "chams",    color = "cham",     icon = "st_ghost.png",
      label = "Chams",    desc = "Highlight the whole body through walls" },
}

-- Drawing is executor-provided and not universal. Chams use Highlight and
-- work without it, so this gates the drawing features only.
function ESP.hasDrawing()
    if ESP._draw ~= nil then return ESP._draw end
    ESP._draw = pcall(function()
        local d = Drawing.new("Line")
        d:Remove()
    end)
    return ESP._draw
end

local function mkDraw(kind, props)
    local ok, d = pcall(function() return Drawing.new(kind) end)
    if not ok or not d then return nil end
    for k, v in pairs(props or {}) do pcall(function() d[k] = v end) end
    return d
end

local function toScreen(pos)
    local cam = workspace.CurrentCamera
    if not cam then return Vector2.new(), false end
    local v, on = cam:WorldToViewportPoint(pos)
    return Vector2.new(v.X, v.Y), on
end

-- R15 first: UpperTorso only exists there, so its presence is the rig test.
local SKEL_R15 = {
    { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" },
    { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" },
    { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" },
    { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" },
    { "RightLowerLeg", "RightFoot" },
}
local SKEL_R6 = {
    { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
    { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}
local MAX_BONES = #SKEL_R15

function ESP.colorFor(player)
    if ESP.cfg.teamCheck and player.Team and LocalPlayer.Team
       and player.Team == LocalPlayer.Team then
        return ESP.colors.team
    end
    return ESP.colors.enemy
end

-- ── Per-player object ───────────────────────────────────────────────────
local Obj = {}
Obj.__index = Obj

function Obj.new(player)
    local self = setmetatable({ player = player, d = {}, bones = {} }, Obj)
    if ESP.hasDrawing() then
        self.d.box = mkDraw("Square", { Thickness = 2, Filled = false, Transparency = 1 })
        self.d.tracer = mkDraw("Line", { Thickness = 2, Transparency = 1 })
        self.d.name = mkDraw("Text", { Size = 16, Center = true, Outline = true, Font = 2 })
        self.d.health = mkDraw("Text", { Size = 14, Center = true, Outline = true, Font = 2 })
        self.d.dist = mkDraw("Text", { Size = 14, Center = true, Outline = true, Font = 2 })
        for i = 1, MAX_BONES do
            self.bones[i] = mkDraw("Line", { Thickness = 1, Transparency = 1 })
        end
    end
    return self
end

function Obj:hideAll()
    for _, d in pairs(self.d) do pcall(function() d.Visible = false end) end
    for _, b in ipairs(self.bones) do pcall(function() b.Visible = false end) end
    if self.hl then self.hl.Enabled = false end
end

function Obj:destroy()
    for _, d in pairs(self.d) do pcall(function() d:Remove() end) end
    for _, b in ipairs(self.bones) do pcall(function() b:Remove() end) end
    if self.hl then pcall(function() self.hl:Destroy() end) end
    self.d, self.bones, self.hl = {}, {}, nil
end

-- Chams are a Highlight parented to the character, so it has to be rebuilt
-- whenever they respawn -- checking Adornee each frame is cheaper than
-- another CharacterAdded connection per player.
function Obj:cham(char, tint)
    if not ESP.cfg.chams then
        if self.hl then self.hl.Enabled = false end
        return
    end
    if not self.hl or self.hl.Parent ~= char then
        if self.hl then pcall(function() self.hl:Destroy() end) end
        self.hl = Instance.new("Highlight")
        self.hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        self.hl.Adornee = char
        self.hl.Parent = char
    end
    self.hl.Enabled = true
    self.hl.FillColor = ESP.colors.cham
    self.hl.OutlineColor = tint
    self.hl.FillTransparency = 0.55
    self.hl.OutlineTransparency = 0
end

function Obj:update()
    local char = self.player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (char and root and hum) then self:hideAll() return end

    -- MAIN indexed LocalPlayer.Character.HumanoidRootPart directly, which
    -- throws for the frames you spend dead.
    local meRoot = LocalPlayer.Character
        and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not meRoot then self:hideAll() return end

    local dist = (meRoot.Position - root.Position).Magnitude
    if dist > ESP.cfg.maxDist then self:hideAll() return end

    local rootPos, onScreen = toScreen(root.Position)
    if not onScreen then self:hideAll() return end

    local tint = ESP.colorFor(self.player)
    self:cham(char, tint)

    local headPos = toScreen(root.Position + Vector3.new(0, 2.5, 0))
    local legPos  = toScreen(root.Position - Vector3.new(0, 2.5, 0))
    local boxH = math.abs(headPos.Y - legPos.Y)
    local boxW = boxH * 0.6

    local d = self.d
    if d.box then
        if ESP.cfg.boxes then
            d.box.Size = Vector2.new(boxW, boxH)
            d.box.Position = Vector2.new(rootPos.X - boxW / 2, headPos.Y)
            d.box.Color = ESP.colors.box
            d.box.Visible = true
        else d.box.Visible = false end
    end

    if d.tracer then
        if ESP.cfg.tracers then
            local cam = workspace.CurrentCamera
            local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
            d.tracer.From = Vector2.new(vp.X / 2, vp.Y)
            d.tracer.To = Vector2.new(rootPos.X, legPos.Y)
            d.tracer.Color = ESP.colors.tracer
            d.tracer.Visible = true
        else d.tracer.Visible = false end
    end

    if d.name then
        if ESP.cfg.names then
            d.name.Text = self.player.DisplayName
            d.name.Position = Vector2.new(rootPos.X, headPos.Y - 20)
            -- Team check is meant to be legible at a glance, so it drives
            -- the name colour rather than only the box.
            d.name.Color = ESP.cfg.teamCheck and tint or ESP.colors.name
            d.name.Visible = true
        else d.name.Visible = false end
    end

    if d.health then
        if ESP.cfg.health and hum.MaxHealth > 0 then
            local pct = math.floor((hum.Health / hum.MaxHealth) * 100)
            d.health.Text = pct .. "%"
            d.health.Position = Vector2.new(rootPos.X, headPos.Y - 35)
            if pct > 75 then d.health.Color = ESP.colors.health
            elseif pct > 25 then d.health.Color = Color3.fromRGB(255, 255, 0)
            else d.health.Color = ESP.colors.healthLow end
            d.health.Visible = true
        else d.health.Visible = false end
    end

    if d.dist then
        if ESP.cfg.distance then
            d.dist.Text = ESP.cfg.meters
                and (math.floor(dist * 0.28) .. "m")
                or  (math.floor(dist) .. " studs")
            d.dist.Position = Vector2.new(rootPos.X, legPos.Y + 5)
            d.dist.Color = ESP.colors.distance
            d.dist.Visible = true
        else d.dist.Visible = false end
    end

    -- Skeleton: bones are a fixed pool sized to R15, reused for R6, so a rig
    -- change never allocates mid-frame.
    if ESP.cfg.skeleton and #self.bones > 0 then
        local pairsList = char:FindFirstChild("UpperTorso") and SKEL_R15 or SKEL_R6
        local n = 0
        for _, link in ipairs(pairsList) do
            local a, b = char:FindFirstChild(link[1]), char:FindFirstChild(link[2])
            if a and b then
                local pa, oa = toScreen(a.Position)
                local pb, ob = toScreen(b.Position)
                if oa and ob then
                    n = n + 1
                    local line = self.bones[n]
                    if line then
                        line.From, line.To = pa, pb
                        line.Color = ESP.colors.skeleton
                        line.Visible = true
                    end
                end
            end
        end
        for i = n + 1, #self.bones do self.bones[i].Visible = false end
    else
        for _, b in ipairs(self.bones) do b.Visible = false end
    end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────
function ESP.add(player)
    if player == LocalPlayer or ESP.objs[player] then return end
    ESP.objs[player] = Obj.new(player)
end

function ESP.remove(player)
    local o = ESP.objs[player]
    if o then o:destroy() ESP.objs[player] = nil end
end

function ESP.clear()
    for pl in pairs(ESP.objs) do ESP.remove(pl) end
end

function ESP.start()
    if ESP.on then return end
    ESP.on = true
    for _, pl in ipairs(Players:GetPlayers()) do ESP.add(pl) end
    ESP.conns.added = Players.PlayerAdded:Connect(ESP.add)
    ESP.conns.gone = Players.PlayerRemoving:Connect(ESP.remove)
    ESP.conns.step = RunService.RenderStepped:Connect(function()
        for pl, o in pairs(ESP.objs) do
            if pl.Parent then o:update() else ESP.remove(pl) end
        end
    end)
end

function ESP.stop()
    ESP.on = false
    for k, c in pairs(ESP.conns) do
        pcall(function() c:Disconnect() end)
        ESP.conns[k] = nil
    end
    ESP.clear()
end

-- Any feature on means the engine should be running; none means it should
-- not. One place decides, so no toggle has to remember to start or stop it.
function ESP.sync()
    local any = false
    for _, f in ipairs(ESP.FEATURES) do
        if ESP.cfg[f.key] then any = true break end
    end
    if any then ESP.start() else ESP.stop() end
end

function ESP.refresh()
    local was = ESP.on
    ESP.stop()
    if was then ESP.start() end
end

-- ── Modal ───────────────────────────────────────────────────────────────
ESP.W, ESP.BODY_H, ESP.ROW_H = 520, 360, 54

local function espSwitch(parent, y, get, set)
    local sw = Instance.new("TextButton")
    sw.AnchorPoint = Vector2.new(1, 0.5)
    sw.Position = UDim2.new(1, -14, 0, y)
    sw.Size = UDim2.fromOffset(34, 18)
    sw.AutoButtonColor = false
    sw.Text = ""
    sw.BackgroundColor3 = get() and UI.accent or Color3.fromRGB(52, 54, 62)
    sw.BorderSizePixel = 0
    sw.ZIndex = 9
    sw.Parent = parent
    Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0, 0.5)
    knob.Position = get() and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
    knob.Size = UDim2.fromOffset(14, 14)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.ZIndex = 10
    knob.Parent = sw
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    sw.MouseButton1Click:Connect(function()
        set(not get())
        local on = get()
        TweenService:Create(knob,
            TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
            { Position = on and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0) }):Play()
        TweenService:Create(sw, TweenInfo.new(0.18), {
            BackgroundColor3 = on and UI.accent or Color3.fromRGB(52, 54, 62) }):Play()
    end)
    return sw
end

-- Opens the picker on the colour it is currently showing, and repaints
-- itself live as that colour is dragged around.
local function espSwatch(parent, x, y, key)
    local b = Instance.new("TextButton")
    b.AnchorPoint = Vector2.new(1, 0.5)
    b.Position = UDim2.new(1, x, 0, y)
    b.Size = UDim2.fromOffset(18, 18)
    b.AutoButtonColor = false
    b.Text = ""
    b.BackgroundColor3 = ESP.colors[key]
    b.BorderSizePixel = 0
    b.ZIndex = 9
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
    local st = Instance.new("UIStroke", b)
    st.Color = Color3.fromRGB(255, 255, 255)
    st.Transparency = 0.75
    st.Thickness = 1

    b.MouseButton1Click:Connect(function()
        Picker.show(ESP.colors[key], function(c)
            ESP.colors[key] = c
            b.BackgroundColor3 = c
        end)
    end)
    return b
end

function ESP.show()
    if Modal.open and Modal.owner == "esp" then Modal.hide() return end

    Modal.show{
        owner = "esp",
        dismissOnBackdrop = false,
        width = ESP.W,
        title = "ESP",
        subtitle = ESP.hasDrawing()
            and "Everything renders on your client only."
            or  "No Drawing API on this executor -- chams only.",
        bodyHeight = ESP.BODY_H,
        actions = {
            { label = "Refresh", icon = "st_refresh-cw.png", style = "light",
              run = function() ESP.refresh() end },
            { label = "Clear", icon = "st_trash-2.png", style = "ghost",
              run = function()
                  for _, f in ipairs(ESP.FEATURES) do ESP.cfg[f.key] = false end
                  ESP.sync()
              end },
            { label = "Close", icon = "st_x.png", style = "ghost" },
        },
        build = function(panel, headY, bodyH, W)
            local PAD = 24

            local list = Instance.new("ScrollingFrame")
            list.Position = UDim2.new(0, PAD - 6, 0, headY)
            list.Size = UDim2.new(1, -(PAD - 6) * 2, 0, bodyH)
            list.BackgroundTransparency = 1
            list.BorderSizePixel = 0
            list.ScrollBarThickness = 3
            list.ScrollBarImageColor3 = UI.accent
            list.ScrollBarImageTransparency = 0.4
            list.CanvasSize = UDim2.new(0, 0, 0, 0)
            list.ZIndex = 7
            list.Parent = panel

            local y = 0
            local function row(icon, label, desc)
                local r = Instance.new("Frame")
                r.Position = UDim2.new(0, 0, 0, y)
                r.Size = UDim2.new(1, -8, 0, ESP.ROW_H - 4)
                r.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                r.BackgroundTransparency = 0.955
                r.BorderSizePixel = 0
                r.ZIndex = 8
                r.Parent = list
                Instance.new("UICorner", r).CornerRadius = UDim.new(0, 9)

                local ic = Instance.new("ImageLabel")
                ic.AnchorPoint = Vector2.new(0, 0.5)
                ic.Position = UDim2.new(0, 14, 0.5, 0)
                ic.Size = UDim2.fromOffset(16, 16)
                ic.BackgroundTransparency = 1
                ic.Image = UI.icon(icon)
                ic.ImageColor3 = UI.accent
                ic.ZIndex = 9
                ic.Parent = r

                local t = Instance.new("TextLabel")
                t.Position = UDim2.new(0, 42, 0, 8)
                t.Size = UDim2.new(1, -140, 0, 17)
                t.BackgroundTransparency = 1
                t.Text = label
                t.TextColor3 = Color3.fromRGB(238, 239, 244)
                t.TextXAlignment = Enum.TextXAlignment.Left
                t.TextSize = UI.T_ROW
                t.TextTruncate = Enum.TextTruncate.AtEnd
                t.ZIndex = 9
                t.Parent = r
                UI.applyFont(t, Enum.FontWeight.SemiBold)

                local s = Instance.new("TextLabel")
                s.Position = UDim2.new(0, 42, 0, 26)
                s.Size = UDim2.new(1, -140, 0, 15)
                s.BackgroundTransparency = 1
                s.Text = desc
                s.TextColor3 = UI.textMuted
                s.TextXAlignment = Enum.TextXAlignment.Left
                s.TextSize = UI.T_SMALL
                s.TextTruncate = Enum.TextTruncate.AtEnd
                s.ZIndex = 9
                s.Parent = r
                UI.applyFont(s, Enum.FontWeight.Regular)

                y = y + ESP.ROW_H
                return r
            end

            for _, f in ipairs(ESP.FEATURES) do
                local r = row(f.icon, f.label, f.desc)
                espSwatch(r, -60, (ESP.ROW_H - 4) / 2, f.color)
                espSwitch(r, (ESP.ROW_H - 4) / 2,
                    function() return ESP.cfg[f.key] end,
                    function(v) ESP.cfg[f.key] = v ESP.sync() end)
            end

            local tc = row("st_shield.png", "Team check",
                "Colour teammates apart from everyone else")
            espSwatch(tc, -60, (ESP.ROW_H - 4) / 2, "team")
            espSwatch(tc, -84, (ESP.ROW_H - 4) / 2, "enemy")
            espSwitch(tc, (ESP.ROW_H - 4) / 2,
                function() return ESP.cfg.teamCheck end,
                function(v) ESP.cfg.teamCheck = v end)

            local mt = row("st_ruler.png", "Metres",
                "Read distance in metres instead of studs")
            espSwitch(mt, (ESP.ROW_H - 4) / 2,
                function() return ESP.cfg.meters end,
                function(v) ESP.cfg.meters = v end)

            -- Max distance gets its own taller row: the slider needs the
            -- width, and the readout has to sit somewhere.
            local dr = Instance.new("Frame")
            dr.Position = UDim2.new(0, 0, 0, y)
            dr.Size = UDim2.new(1, -8, 0, 64)
            dr.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            dr.BackgroundTransparency = 0.955
            dr.BorderSizePixel = 0
            dr.ZIndex = 8
            dr.Parent = list
            Instance.new("UICorner", dr).CornerRadius = UDim.new(0, 9)
            y = y + 68

            local dl = Instance.new("TextLabel")
            dl.Position = UDim2.new(0, 14, 0, 10)
            dl.Size = UDim2.new(1, -28, 0, 17)
            dl.BackgroundTransparency = 1
            dl.Text = "Max distance"
            dl.TextColor3 = Color3.fromRGB(238, 239, 244)
            dl.TextXAlignment = Enum.TextXAlignment.Left
            dl.TextSize = UI.T_ROW
            dl.ZIndex = 9
            dl.Parent = dr
            UI.applyFont(dl, Enum.FontWeight.SemiBold)

            local dv = Instance.new("TextLabel")
            dv.AnchorPoint = Vector2.new(1, 0)
            dv.Position = UDim2.new(1, -14, 0, 10)
            dv.Size = UDim2.new(0, 120, 0, 17)
            dv.BackgroundTransparency = 1
            dv.Text = math.floor(ESP.cfg.maxDist) .. " studs"
            dv.TextColor3 = UI.accent
            dv.TextXAlignment = Enum.TextXAlignment.Right
            dv.TextSize = UI.T_SMALL
            dv.ZIndex = 9
            dv.Parent = dr
            UI.applyFont(dv, Enum.FontWeight.SemiBold)

            -- 100..5000 studs; below 100 nothing renders, above 5000 the
            -- whole map is in range and the slider stops meaning anything.
            local LO, HI = 100, 5000
            Settings.slider(dr, 14, 44, ESP.W - 100,
                (ESP.cfg.maxDist - LO) / (HI - LO), function(f)
                    ESP.cfg.maxDist = math.floor(LO + f * (HI - LO))
                    dv.Text = math.floor(ESP.cfg.maxDist) .. " studs"
                end)

            list.CanvasSize = UDim2.new(0, 0, 0, y + 8)
        end,
    }
end

-- ════════════════════════════════════════════════════════════════════════
--  VOICE  (!mutevc / !unmutevc)
--  Ported from musicbot. Most games are on the new Audio API now, where
--  every voice player carries an AudioDeviceInput and the legacy
--  VoiceChatInternal:SubscribePause / PublishPause DO NOTHING. Mute by
--  setting that device instead, and fall back to the legacy calls only when
--  no device exists, so it stays correct on both.
--
--  Client-side only: this changes what YOU hear, not what anyone else does.
-- ════════════════════════════════════════════════════════════════════════
Voice = { muted = {} }

function Voice.dev(p)
    return p and p:FindFirstChildWhichIsA("AudioDeviceInput")
end

-- What you hear FROM this player.
function Voice.hear(player, muted)
    if not player then return false end
    local d = Voice.dev(player)
    if d then
        pcall(function() d.Muted = muted end)
        pcall(function() d.Volume = muted and 0 or 1 end)
        Voice.muted[player.UserId] = muted or nil
        return true
    end
    pcall(function()
        game:GetService("VoiceChatInternal"):SubscribePause(player.UserId, muted)
    end)
    Voice.muted[player.UserId] = muted or nil
    return false
end

-- Your own microphone -- the publish side, so nobody hears YOU.
function Voice.mic(muted)
    local d = Voice.dev(LocalPlayer)
    if d then
        pcall(function() d.Muted = muted end)
        Voice.muted[LocalPlayer.UserId] = muted or nil
        return true
    end
    pcall(function() game:GetService("VoiceChatInternal"):PublishPause(muted) end)
    Voice.muted[LocalPlayer.UserId] = muted or nil
    return false
end

-- Muting yourself means your mic; muting anyone else means their voice.
function Voice.set(player, muted)
    if player == LocalPlayer then return Voice.mic(muted) end
    return Voice.hear(player, muted)
end

-- Re-apply on respawn: the AudioDeviceInput is rebuilt with the character,
-- so a muted player comes back audible without this.
function Voice.watch()
    if Voice.conn then return end
    Voice.conn = Players.PlayerAdded:Connect(function(p)
        p.CharacterAdded:Connect(function()
            task.wait(1)
            if Voice.muted[p.UserId] then Voice.set(p, true) end
        end)
    end)
    for _, p in ipairs(Players:GetPlayers()) do
        p.CharacterAdded:Connect(function()
            task.wait(1)
            if Voice.muted[p.UserId] then Voice.set(p, true) end
        end)
    end
end

function Voice.stop()
    for uid in pairs(Voice.muted) do
        local p = Players:GetPlayerByUserId(uid)
        if p then pcall(function() Voice.set(p, false) end) end
    end
    Voice.muted = {}
    if Voice.conn then pcall(function() Voice.conn:Disconnect() end) Voice.conn = nil end
end

-- One entry point for both commands. `word` is whatever was typed after the
-- command, which may be a name, a token, or nothing at all.
function Voice.apply(word, muted)
    Voice.watch()
    local targets, tok = resolveTargets(word, muted and "mutevc" or "unmutevc")
    if #targets == 0 then
        Notifications:Error("Universal Hub Lite",
            "No one matched \"" .. tostring(word) .. "\"", 4)
        return
    end

    local devices = 0
    for _, p in ipairs(targets) do
        if Voice.set(p, muted) then devices = devices + 1 end
    end

    local verb = muted and "Muted" or "Unmuted"
    local who
    if tok then
        who = tok.label:lower()
    elseif #targets == 1 then
        who = (targets[1] == LocalPlayer) and "your mic" or targets[1].DisplayName
    else
        who = #targets .. " players"
    end

    -- No AudioDeviceInput anywhere means the game is on the legacy API,
    -- where these calls are silently inert. Say so rather than claiming a
    -- mute that did not happen.
    if devices == 0 then
        Notifications:Info("Universal Hub Lite",
            verb .. " " .. who .. "  \194\183  no voice device found, this game may not use voice chat", 5)
        return
    end

    local target = (#targets == 1 and targets[1] ~= LocalPlayer)
                   and targets[1].Name or nil

    -- Undo the players it ACTUALLY hit, not the word that chose them:
    -- "mutevc random" re-run would pick somebody else and leave the first
    -- one muted with nothing offering to undo it.
    local hit = {}
    for _, p in ipairs(targets) do hit[#hit + 1] = p end

    Notifications:Success("Universal Hub Lite", verb .. " " .. who, 4, {
        { label = muted and "Unmute" or "Mute",
          icon = "st_mic.png", style = "light",
          run = function()
              for _, p in ipairs(hit) do
                  if p and p.Parent then Voice.set(p, not muted) end
              end
              Notifications:Success("Universal Hub Lite",
                  (muted and "Unmuted " or "Muted ") .. who, 3)
          end },
    }, target)
end

-- ════════════════════════════════════════════════════════════════════════
--  ACTIVITY  (!activity)
--  Everything observable about one player, live. Ported from musicbot's
--  voice work -- the RMS meter is its AudioAnalyzer trick -- plus a chat
--  log, proximity and state this script can see for itself.
--  Client-side observation only: it reads, it does not touch them.
-- ════════════════════════════════════════════════════════════════════════

-- Live mic loudness (0..~0.25) via a lazily-wired AudioAnalyzer. Raw mic
-- level, so it does NOT fall off with distance -- callers proximity-gate
-- themselves. One analyzer per player, kept, because wiring a new one per
-- frame would leak instances at frame rate.
Voice._an = Voice._an or {}

function Voice.rms(player)
    if not player then return 0 end
    local uid = player.UserId
    local a = Voice._an[uid]
    if not a then
        local d = Voice.dev(player)
        if not d then return 0 end
        local ok, res = pcall(function()
            local an = Instance.new("AudioAnalyzer")
            local w = Instance.new("Wire")
            w.SourceInstance, w.TargetInstance = d, an
            w.Parent, an.Parent = an, d
            return an
        end)
        if not ok or not res then return 0 end
        a = res
        Voice._an[uid] = a
    end
    local ok, lvl = pcall(function() return a.RmsLevel end)
    return (ok and lvl) or 0
end

function Voice.hasMic(player)
    return Voice.dev(player) ~= nil
end

-- ── Chat log ────────────────────────────────────────────────────────────
-- Kept per player so the panel can show what someone has been saying. Both
-- APIs are wired: TextChatService is what modern games use, player.Chatted
-- is what the legacy ones still fire, and a game can surprise you.
Chat = { log = {}, KEEP = 6, bound = false }

function Chat.note(userId, text)
    if not (userId and type(text) == "string" and text ~= "") then return end
    local l = Chat.log[userId]
    if not l then l = {} Chat.log[userId] = l end
    table.insert(l, 1, { text = text, at = os.clock() })
    while #l > Chat.KEEP do table.remove(l) end
end

function Chat.forPlayer(p)
    return (p and Chat.log[p.UserId]) or {}
end

function Chat.bind()
    if Chat.bound then return end
    Chat.bound = true

    local function watch(p)
        pcall(function()
            p.Chatted:Connect(function(msg) Chat.note(p.UserId, msg) end)
        end)
    end
    for _, p in ipairs(Players:GetPlayers()) do watch(p) end
    pcall(function() Players.PlayerAdded:Connect(watch) end)

    pcall(function()
        local tcs = game:GetService("TextChatService")
        tcs.MessageReceived:Connect(function(m)
            local src = m and m.TextSource
            if src and src.UserId then Chat.note(src.UserId, m.Text) end
        end)
    end)
end

-- ════════════════════════════════════════════════════════════════════════
Activity = {
    W = 470, HEAD_H = 96, ROW_H = 26, NEAR_H = 54, CHAT_H = 74,
    NEAR_STUDS = 60, SPEAK_RMS = 0.03, PEAK = 0.22,
}

function Activity.distance(p)
    return CmdBar.distanceTo(p.Name)
end

-- Who is standing with them, not with you -- the whole point is to see the
-- group they are in.
function Activity.near(target)
    local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    if not root then return {} end
    local out = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= target then
            local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            if r then
                local d = (r.Position - root.Position).Magnitude
                if d <= Activity.NEAR_STUDS then
                    out[#out + 1] = { player = p, dist = d }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end

-- What they are doing, from the humanoid. Cheap, and it is the difference
-- between "there" and "actually playing".
function Activity.doing(target)
    local ch = target.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not (ch and hum) then return "not spawned", false end
    if hum.Health <= 0 then return "dead", false end

    local st = hum:GetState()
    if st == Enum.HumanoidStateType.Seated then return "sitting", true end
    if st == Enum.HumanoidStateType.Freefall then return "falling", true end
    if st == Enum.HumanoidStateType.Jumping then return "jumping", true end
    if hum.MoveDirection.Magnitude > 0.1 then
        return (hum.WalkSpeed > 20) and "running" or "walking", true
    end
    return "standing still", true
end

-- Who in this server is a friend of THEIRS. IsFriendsWith yields, so it is
-- resolved once off-thread and cached -- asking per redraw would stall the
-- panel twice a second, once per player.
Activity.friendCache = {}

function Activity.resolveFriends(target)
    local key = target.UserId
    if Activity.friendCache[key] then return end
    Activity.friendCache[key] = {}
    task.spawn(function()
        local out = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= target then
                local ok, isF = pcall(function()
                    return target:IsFriendsWith(p.UserId)
                end)
                if ok and isF then out[#out + 1] = p end
            end
        end
        Activity.friendCache[key] = out
    end)
end

function Activity.friendsOf(target)
    return Activity.friendCache[target.UserId] or {}
end

function Activity.rows(target)
    local out = {}
    local function add(k, v) if v and v ~= "" then out[#out + 1] = { k, v } end end

    local d = Activity.distance(target)
    add("Distance", d < math.huge
        and (math.floor(d) .. " studs" .. (d <= CmdBar.NEARBY_STUDS and "  \194\183  nearby" or ""))
        or "unknown -- no character")

    local doing, alive = Activity.doing(target)
    add("Doing", doing)

    local ch = target.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if hum and alive and hum.MaxHealth > 0 then
        add("Health", math.floor((hum.Health / hum.MaxHealth) * 100) .. "%")
    end

    -- What they are holding says more about intent than anything else here.
    local tool = ch and ch:FindFirstChildOfClass("Tool")
    add("Holding", tool and tool.Name or "nothing")

    if target.Team then add("Team", target.Team.Name) end
    add("Account age", target.AccountAge .. " days")
    add("Voice", Voice.hasMic(target) and "on" or "not detected")
    return out
end

-- ── Event feed ──────────────────────────────────────────────────────────
-- Everything that happens to the player being watched, and to your friends
-- in the server, in one list. Chat is an event like any other -- splitting
-- "what they said" from "what they did" makes you read two lists to
-- reconstruct one sequence.
Activity.events = {}
Activity.KEEP = 40
-- Off by default. Someone in a crowded server generates an event every few
-- seconds, and a toast for each is a wall you cannot see the game through.
Activity.notifying = false

function Activity.push(icon, text, notify, target, kind)
    table.insert(Activity.events, 1, {
        icon = icon, text = text, at = os.clock(),
        -- Stamped when it happens, not when it is drawn: a log written an
        -- hour later must still say when things occurred.
        clock = Activity.stamp(), kind = kind,
    })
    while #Activity.events > Activity.KEEP do table.remove(Activity.events) end
    if Activity.feed then Activity.drawFeed() end
    -- Always for the two that matter -- the watched player leaving, a friend
    -- coming or going -- and for everything else only when asked.
    if notify or Activity.notifying then
        Notifications:Info("Activity", text, 4, nil, target)
    end
end

function Activity.since(at)
    local d = math.floor(os.clock() - (at or 0))
    if d < 5 then return "now" end
    if d < 60 then return d .. "s" end
    if d < 3600 then return math.floor(d / 60) .. "m" end
    return math.floor(d / 3600) .. "h"
end

-- ── Watching ────────────────────────────────────────────────────────────
-- Every connection is held so it can be cut. A panel that leaves listeners
-- behind reports on a player nobody is looking at any more.
Activity.conns = {}

local function hold(c) Activity.conns[#Activity.conns + 1] = c end

function Activity.unwatch()
    for _, c in ipairs(Activity.conns) do pcall(function() c:Disconnect() end) end
    Activity.conns = {}
    if Activity.loop then
        pcall(function() Activity.loop:Disconnect() end)
        Activity.loop = nil
    end
end

function Activity.watchChar(target, ch)
    if not ch then return end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    hold(hum.Died:Connect(function()
        Activity.push("st_skull.png", target.DisplayName .. " died", false, target.Name)
    end))
end

function Activity.watch(target)
    Activity.unwatch()
    Activity.events = {}
    Chat.bind()

    hold(target.CharacterAdded:Connect(function(ch)
        Activity.push("st_refresh-cw.png", target.DisplayName .. " respawned", false, target.Name)
        task.wait(0.5)
        Activity.watchChar(target, ch)
    end))
    Activity.watchChar(target, target.Character)

    hold(target.Chatted:Connect(function(msg)
        -- Stored as its own kind so the feed can set it apart: a line of
        -- speech among a list of state changes should not look like one.
        Activity.push("st_mic.png", msg, false, target.Name, "chat")
    end))

    -- Friends are worth a toast whether or not you are looking at the panel;
    -- the watched player leaving is worth one because the panel is about to
    -- become useless.
    hold(Players.PlayerRemoving:Connect(function(p)
        if p == target then
            Activity.push("st_user-x.png",
                target.DisplayName .. " left the game", true, nil)
        elseif CmdBar.isFriend(p.UserId) then
            Activity.push("st_user-x.png",
                p.DisplayName .. " (friend) left", true, nil)
        end
    end))
    hold(Players.PlayerAdded:Connect(function(p)
        -- isFriend answers from cache and kicks the lookup; ask a moment
        -- later so a brand-new player is not called a stranger.
        task.delay(1.5, function()
            if CmdBar.isFriend(p.UserId) then
                Activity.push("st_users.png",
                    p.DisplayName .. " (friend) joined", true, p.Name)
            end
        end)
        CmdBar.isFriend(p.UserId)
    end))

    Activity.push("st_eye.png", "Watching " .. target.DisplayName, false, target.Name)
end

-- ── Panel ───────────────────────────────────────────────────────────────
-- Floating, not modal: watching someone is something you do WHILE playing,
-- and a panel that takes the screen is a panel you close immediately.
Activity.W, Activity.MIN_W = 430, 300
Activity.HEAD_H2, Activity.MIN_H = 92, 40
Activity.BODY_H = 466

function Activity.hide()
    if not Activity.open then return end
    Activity.open = false
    Activity.unwatch()
    local gui, panel = Activity.gui, Activity.panel
    Activity.gui, Activity.panel, Activity.feed = nil, nil, nil
    if not gui then return end
    pcall(function()
        TweenService:Create(panel,
            TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
                Size = UDim2.fromOffset(Activity.W - 24, panel.Size.Y.Offset - 16),
                BackgroundTransparency = 1,
            }):Play()
        UI.fadeContent(panel, true, true)
    end)
    task.delay(0.26, function() pcall(function() gui:Destroy() end) end)
end

function Activity.setMin(on)
    if not Activity.panel or Activity.min == on then return end
    Activity.min = on
    local ti = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    if on then Activity.body.Visible = false end
    Activity.minIcon.Image = UI.icon(on and "st_maximize.png" or "st_minimize.png")

    -- Same reflow the hub does: the header has to shrink, not just be
    -- clipped, or the title and subtitle hang out of a 40px strip.
    Activity.sub.Visible = not on
    Activity.strip.Visible = on
    TweenService:Create(Activity.title, ti, {
        Position = UDim2.new(0, 24, 0, on and 10 or 18),
        TextSize = on and 15 or 19,
    }):Play()
    for _, b in ipairs(Activity.chrome) do
        TweenService:Create(b, ti, {
            Position = UDim2.new(1, b:GetAttribute("_x"), 0, on and 9 or 16),
            Size = UDim2.fromOffset(on and 22 or 24, on and 22 or 24),
        }):Play()
    end
    if Activity.grip then
        TweenService:Create(Activity.grip, ti,
            { Size = UDim2.new(1, -90, 0, on and Activity.MIN_H or 62) }):Play()
    end
    local t = TweenService:Create(Activity.panel, ti, {
        Size = UDim2.fromOffset(on and Activity.MIN_W or Activity.W,
            on and Activity.MIN_H or (Activity.HEAD_H2 + Activity.BODY_H)),
    })
    t:Play()
    if not on then
        t.Completed:Connect(function()
            if not Activity.min then Activity.body.Visible = true end
        end)
    end
end

function Activity.bindDrag()
    if Activity.dragBound then return end
    Activity.dragBound = true
    local grab, origin

    Activity.dragBegan = function(i)
        if not Activity.panel then return end
        Activity.dragging = true
        grab = Vector2.new(i.Position.X, i.Position.Y)
        origin = Vector2.new(Activity.panel.Position.X.Offset,
                             Activity.panel.Position.Y.Offset)
    end

    UserInputService.InputChanged:Connect(function(i)
        if not (Activity.dragging and Activity.panel) then return end
        if i.UserInputType ~= Enum.UserInputType.MouseMovement
           and i.UserInputType ~= Enum.UserInputType.Touch then return end
        local d = Vector2.new(i.Position.X, i.Position.Y) - grab
        local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
                   or Vector2.new(1280, 720)
        local x = math.clamp(origin.X + d.X, -(vp.X / 2) + 60, (vp.X / 2) - 60)
        local y = math.clamp(origin.Y + d.Y, -(vp.Y / 2) + 30, (vp.Y / 2) - 30)
        Activity.panel.Position = UDim2.new(0.5, x, 0.5, y)
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
           or i.UserInputType == Enum.UserInputType.Touch then
            Activity.dragging = false
        end
    end)
end

-- On reads as accent, off reads as any other ghost button. The state has to
-- be visible from the button itself: a toggle you cannot read is a guess.
function Activity.paintNotify(b)
    if not (b and b.Parent) then return end
    local lbl = b:FindFirstChildWhichIsA("TextLabel")
    local ic = b:FindFirstChildWhichIsA("ImageLabel")
    local on = Activity.notifying
    if lbl then lbl.Text = on and "Notifying" or "Notify" end
    if ic then ic.ImageColor3 = on and UI.accent or Color3.fromRGB(232, 233, 238) end
    b.BackgroundColor3 = on and UI.accent or Color3.fromRGB(255, 255, 255)
    b.BackgroundTransparency = on and 0.72 or 0.9
end

function Activity.drawFeed()
    local F = Activity.feed
    if not (F and F.Parent) then return end
    for _, c in ipairs(F:GetChildren()) do
        if not c:IsA("UIListLayout") then c:Destroy() end
    end
    if #Activity.events == 0 then
        local none = Instance.new("TextLabel")
        none.Size = UDim2.new(1, -8, 0, 18)
        none.BackgroundTransparency = 1
        none.Text = "nothing yet"
        none.TextColor3 = UI.textMuted
        none.TextXAlignment = Enum.TextXAlignment.Left
        none.TextSize = UI.T_SMALL
        none.ZIndex = 8
        none.Parent = F
        UI.applyFont(none, Enum.FontWeight.Regular)
        F.CanvasSize = UDim2.new(0, 0, 0, 20)
        return
    end

    local y = 0
    for _, e in ipairs(Activity.events) do
        local row = Instance.new("Frame")
        row.Position = UDim2.new(0, 0, 0, y)
        row.Size = UDim2.new(1, -8, 0, 20)
        row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        -- Chat gets a faint plate behind it so a conversation reads as a
        -- block rather than as scattered lines.
        row.BackgroundTransparency = (e.kind == "chat") and 0.965 or 1
        row.BorderSizePixel = 0
        row.ZIndex = 8
        row.Parent = F
        if e.kind == "chat" then
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
        end

        local ic = Instance.new("ImageLabel")
        ic.AnchorPoint = Vector2.new(0, 0.5)
        ic.Position = UDim2.new(0, 0, 0.5, 0)
        ic.Size = UDim2.fromOffset(12, 12)
        ic.BackgroundTransparency = 1
        ic.Image = UI.icon(e.icon)
        ic.ImageColor3 = UI.accent
        ic.ImageTransparency = 0.25
        ic.ZIndex = 9
        ic.Parent = row

        local tx = Instance.new("TextLabel")
        tx.Position = UDim2.new(0, 20, 0, 0)
        tx.Size = UDim2.new(1, -74, 1, 0)
        tx.BackgroundTransparency = 1
        tx.RichText = true
        tx.Text = (e.kind == "chat")
            and ('<font color="#8e919c">said</font>  \226\128\156' .. e.text .. '\226\128\157')
            or e.text
        tx.TextColor3 = (e.kind == "chat")
            and Color3.fromRGB(236, 237, 243) or Color3.fromRGB(206, 208, 218)
        tx.TextXAlignment = Enum.TextXAlignment.Left
        tx.TextSize = UI.T_SMALL
        tx.TextTruncate = Enum.TextTruncate.AtEnd
        tx.ZIndex = 9
        tx.Parent = row
        UI.applyFont(tx, (e.kind == "chat") and Enum.FontWeight.Medium
                                             or Enum.FontWeight.Regular)

        local ago = Instance.new("TextLabel")
        ago.AnchorPoint = Vector2.new(1, 0)
        ago.Position = UDim2.new(1, 0, 0, 0)
        ago.Size = UDim2.fromOffset(52, 20)
        ago.BackgroundTransparency = 1
        ago.Text = e.clock or Activity.since(e.at)
        ago.TextColor3 = UI.textMuted
        ago.TextXAlignment = Enum.TextXAlignment.Right
        ago.TextSize = UI.T_EYEBROW
        ago.ZIndex = 9
        ago.Parent = row
        UI.applyFont(ago, Enum.FontWeight.Regular)

        y = y + 20
    end
    F.CanvasSize = UDim2.new(0, 0, 0, y + 4)
end

-- Wall-clock stamp, from the same corrected clock the time card uses --
-- os.date would report UTC here, which is the bug that card already fixed.
function Activity.stamp()
    local ok, day = pcall(Info.now)
    if not ok or not day or day <= 0 then return "--:--:--" end
    local h = math.floor(day / 3600)
    local m = math.floor((day % 3600) / 60)
    local s = math.floor(day % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

function Activity.logText(target)
    local out = {
        "Universal Hub Lite - activity log",
        "Player : " .. target.DisplayName .. " (@" .. target.Name .. ")",
        "Game   : " .. tostring(game.PlaceId) .. "  server " .. tostring(game.JobId),
        "",
    }
    -- Oldest first in the file: a log reads forward, even though the panel
    -- shows newest at the top.
    for i = #Activity.events, 1, -1 do
        local e = Activity.events[i]
        out[#out + 1] = (e.clock or "--:--:--") .. "  " .. e.text
    end
    return table.concat(out, "\n")
end

function Activity.show(word)
    if Activity.open then Activity.hide() end
    local target = findPlayer(word, "activity")
    if not target then
        Notifications:Error("Universal Hub Lite",
            "No one matched \"" .. tostring(word or "") .. "\"", 4)
        return
    end

    Activity.open, Activity.min = true, false
    Activity.bindDrag()
    Activity.watch(target)

    local PAD = 20
    local H = Activity.HEAD_H2 + Activity.BODY_H

    local gui = Instance.new("ScreenGui")
    gui.Name = "UHubLiteActivity"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 9998
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function()
        gui.Parent = (typeof(gethui) == "function" and gethui())
                  or game:GetService("CoreGui")
    end)
    Activity.gui = gui

    local panel = Instance.new("Frame")
    panel.Name = "ActivityPanel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.new(0.5, 0, 0.5, 0)
    panel.Size = UDim2.fromOffset(Activity.W - 24, H - 16)
    panel.BackgroundColor3 = UI.cardFill
    panel.BackgroundTransparency = 1
    panel.BorderSizePixel = 0
    panel.ClipsDescendants = true
    panel.ZIndex = 5
    panel.Parent = gui
    UI.glassify(panel, 16)
    UI.accentWash(panel)
    Activity.panel = panel

    local title = Instance.new("TextLabel")
    title.Position = UDim2.new(0, 24, 0, 18)
    title.Size = UDim2.new(1, -110, 0, 24)
    title.BackgroundTransparency = 1
    title.Text = target.DisplayName
    title.TextColor3 = UI.textPrimary
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextSize = 19
    title.TextTruncate = Enum.TextTruncate.AtEnd
    title.ZIndex = 6
    title.Parent = panel
    UI.applyFont(title, Enum.FontWeight.Bold)
    Activity.title = title

    local sub = Instance.new("TextLabel")
    sub.Position = UDim2.new(0, 24, 0, 42)
    sub.Size = UDim2.new(1, -110, 0, 16)
    sub.BackgroundTransparency = 1
    sub.Text = "@" .. target.Name
    sub.TextColor3 = UI.textMuted
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.TextSize = UI.T_SMALL
    sub.ZIndex = 6
    sub.Parent = panel
    UI.applyFont(sub, Enum.FontWeight.Regular)
    Activity.sub = sub

    local strip = Instance.new("TextLabel")
    strip.AnchorPoint = Vector2.new(1, 0.5)
    strip.Position = UDim2.new(1, -80, 0, 20)
    strip.Size = UDim2.new(1, -190, 0, 16)
    strip.BackgroundTransparency = 1
    strip.Text = ""
    strip.TextColor3 = UI.textMuted
    strip.TextXAlignment = Enum.TextXAlignment.Right
    strip.TextSize = UI.T_SMALL
    strip.TextTruncate = Enum.TextTruncate.AtEnd
    strip.Visible = false
    strip.ZIndex = 6
    strip.Parent = panel
    UI.applyFont(strip, Enum.FontWeight.Medium)
    Activity.strip = strip

    local minBtn, minIcon = UI.chromeButton(panel, "st_minimize.png", -52,
        function() Activity.setMin(not Activity.min) end)
    Activity.minIcon = minIcon
    local closeBtn = UI.chromeButton(panel, "st_x.png", -20, function() Activity.hide() end)
    Activity.chrome = { minBtn, closeBtn }
    for _, b in ipairs(Activity.chrome) do b.Position = UDim2.new(1, b:GetAttribute("_x"), 0, 16) end

    local grip = Instance.new("TextButton")
    grip.Size = UDim2.new(1, -90, 0, 62)
    grip.BackgroundTransparency = 1
    grip.AutoButtonColor = false
    grip.Text = ""
    grip.ZIndex = 7
    grip.Parent = panel
    Activity.grip = grip
    grip.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
           or i.UserInputType == Enum.UserInputType.Touch then
            Activity.dragBegan(i)
        end
    end)

    local body = Instance.new("Frame")
    body.Position = UDim2.new(0, 0, 0, Activity.HEAD_H2)
    body.Size = UDim2.new(1, 0, 1, -Activity.HEAD_H2)
    body.BackgroundTransparency = 1
    body.ZIndex = 6
    body.Parent = panel
    Activity.body = body

    -- ── Headshot, with a ring that answers "are they talking" ──────────
    local hs = Instance.new("ImageLabel")
    hs.Position = UDim2.new(0, PAD, 0, 0)
    hs.Size = UDim2.fromOffset(56, 56)
    hs.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    hs.BackgroundTransparency = 0.4
    hs.Image = UI.headshotFor(target.Name)
    hs.ZIndex = 7
    hs.Parent = body
    Instance.new("UICorner", hs).CornerRadius = UDim.new(1, 0)
    local ring = Instance.new("UIStroke", hs)
    ring.Color = UI.accent
    ring.Thickness = 2
    ring.Transparency = 1

    -- ── Mic ────────────────────────────────────────────────────────────
    local mx = PAD + 68
    local micState = Instance.new("TextLabel")
    micState.Position = UDim2.new(0, mx, 0, 4)
    micState.Size = UDim2.new(1, -mx - PAD, 0, 14)
    micState.BackgroundTransparency = 1
    micState.Text = "checking voice\226\128\166"
    micState.TextColor3 = UI.textMuted
    micState.TextXAlignment = Enum.TextXAlignment.Left
    micState.TextSize = UI.T_EYEBROW
    micState.ZIndex = 7
    micState.Parent = body
    UI.applyFont(micState, Enum.FontWeight.Bold)

    -- Everything below is hidden outright when there is no device. A dead
    -- bar that can never move is worse than no bar: it reads as broken
    -- rather than as absent.
    local meter = Instance.new("Frame")
    meter.Position = UDim2.new(0, mx, 0, 22)
    meter.Size = UDim2.new(1, -mx - PAD, 0, 26)
    meter.BackgroundTransparency = 1
    meter.Visible = false
    meter.ZIndex = 7
    meter.Parent = body

    local track = Instance.new("Frame")
    track.Position = UDim2.new(0, 0, 0, 0)
    track.Size = UDim2.new(1, 0, 0, 8)
    track.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    track.BackgroundTransparency = 0.9
    track.BorderSizePixel = 0
    track.ClipsDescendants = true
    track.ZIndex = 7
    track.Parent = meter
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    fill.BorderSizePixel = 0
    fill.ZIndex = 8
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
    -- The gradient is the level: quiet reads as the theme accent, loud
    -- pushes through amber into red, so you can see HOW loud without
    -- reading a number.
    local fg = Instance.new("UIGradient", fill)
    fg.Color = ColorSequence.new(UI.accent)

    -- Peak hold: a line that jumps to the loudest moment and falls back
    -- slowly, so a single shout still leaves a mark you can see.
    local peak = Instance.new("Frame")
    peak.AnchorPoint = Vector2.new(0.5, 0)
    peak.Position = UDim2.new(0, 0, 0, 0)
    peak.Size = UDim2.fromOffset(2, 8)
    peak.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    peak.BackgroundTransparency = 0.35
    peak.BorderSizePixel = 0
    peak.Visible = false
    peak.ZIndex = 9
    peak.Parent = track

    local scaleLbl = Instance.new("TextLabel")
    scaleLbl.Position = UDim2.new(0, 0, 0, 12)
    scaleLbl.Size = UDim2.new(1, 0, 0, 12)
    scaleLbl.BackgroundTransparency = 1
    scaleLbl.Text = ""
    scaleLbl.TextColor3 = UI.textMuted
    scaleLbl.TextXAlignment = Enum.TextXAlignment.Left
    scaleLbl.TextSize = UI.T_EYEBROW
    scaleLbl.ZIndex = 7
    scaleLbl.Parent = meter
    UI.applyFont(scaleLbl, Enum.FontWeight.Regular)

    -- ── Facts ──────────────────────────────────────────────────────────
    local rowsY = 64
    local rowHolder = Instance.new("Frame")
    rowHolder.Position = UDim2.new(0, PAD, 0, rowsY)
    rowHolder.Size = UDim2.new(1, -PAD * 2, 0, 7 * 22)
    rowHolder.BackgroundTransparency = 1
    rowHolder.ZIndex = 7
    rowHolder.Parent = body

    -- ── Near them, then their friends ──────────────────────────────────
    local function band(y, text)
        local l = Instance.new("TextLabel")
        l.Position = UDim2.new(0, PAD, 0, y)
        l.Size = UDim2.new(1, -PAD * 2, 0, 14)
        l.BackgroundTransparency = 1
        l.Text = text
        l.TextColor3 = UI.textMuted
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextSize = UI.T_EYEBROW
        l.ZIndex = 7
        l.Parent = body
        UI.applyFont(l, Enum.FontWeight.Bold)

        local h = Instance.new("Frame")
        h.Position = UDim2.new(0, PAD, 0, y + 16)
        h.Size = UDim2.new(1, -PAD * 2, 0, 26)
        h.BackgroundTransparency = 1
        h.ZIndex = 7
        h.Parent = body
        return h, l
    end

    local nearY = rowsY + 7 * 22 + 6
    local nearHolder, nearLbl = band(nearY, "NEAR THEM")
    local friendY = nearY + 48
    local friendHolder, friendLbl = band(friendY, "THEIR FRIENDS HERE")

    -- ── Event log ──────────────────────────────────────────────────────
    local feedY = friendY + 48
    local feedLbl = Instance.new("TextLabel")
    feedLbl.Position = UDim2.new(0, PAD, 0, feedY)
    feedLbl.Size = UDim2.fromOffset(90, 14)
    feedLbl.BackgroundTransparency = 1
    feedLbl.Text = "EVENT LOG"
    feedLbl.TextColor3 = UI.textMuted
    feedLbl.TextXAlignment = Enum.TextXAlignment.Left
    feedLbl.TextSize = UI.T_EYEBROW
    feedLbl.ZIndex = 7
    feedLbl.Parent = body
    UI.applyFont(feedLbl, Enum.FontWeight.Bold)

    local function logBtn(label, icon, x, run)
        local b = UI.gradButton(body, label, icon, "ghost")
        UI.smallButton(b)
        b.AnchorPoint = Vector2.new(1, 0)
        b.Position = UDim2.new(1, x, 0, feedY - 6)
        b.ZIndex = 8
        b.MouseButton1Click:Connect(run)
        return b
    end
    -- Positioned after the other two, since the strip is laid out from the
    -- right edge inward and this one sits furthest left.
    local notifyBtn
    notifyBtn = logBtn("Notify", "st_zap.png", 0, function()
        Activity.notifying = not Activity.notifying
        Activity.paintNotify(notifyBtn)
        Notifications:Info("Activity", Activity.notifying
            and "Notifying for every event  \194\183  !unotify stops it"
            or "Only leaves and friends will notify", 3.5)
    end)

    local copyBtn = logBtn("Copy", "st_copy.png", -PAD, function()
        pcall(function() setclipboard(Activity.logText(target)) end)
        Notifications:Success("Activity",
            #Activity.events .. " events copied", 3)
    end)
    local saveBtn = logBtn("Save", "st_hard-drive.png",
        -PAD - copyBtn.Size.X.Offset - 6, function()
        local name = "activity-" .. target.Name .. "-"
                     .. Activity.stamp():gsub(":", "") .. ".txt"
        local path = WS.path("logs", name)
        local ok = pcall(function() writefile(path, Activity.logText(target)) end)
        if ok then
            Notifications:Success("Activity", "Saved to " .. path, 4.5)
        else
            Notifications:Error("Activity",
                "Could not write the log -- no file access", 4)
        end
    end)

    notifyBtn.Position = UDim2.new(1,
        -PAD - copyBtn.Size.X.Offset - 6 - saveBtn.Size.X.Offset - 6, 0, feedY - 6)
    Activity.notifyBtn = notifyBtn      -- so !notify can repaint it
    Activity.paintNotify(notifyBtn)

    local feed = Instance.new("ScrollingFrame")
    feed.Position = UDim2.new(0, PAD, 0, feedY + 18)
    feed.Size = UDim2.new(1, -PAD * 2, 1, -(feedY + 26))
    feed.BackgroundTransparency = 1
    feed.BorderSizePixel = 0
    feed.ScrollBarThickness = 3
    feed.ScrollBarImageColor3 = UI.accent
    feed.ScrollBarImageTransparency = 0.4
    feed.CanvasSize = UDim2.new(0, 0, 0, 0)
    feed.ZIndex = 7
    feed.Parent = body
    Activity.feed = feed
    Activity.drawFeed()

    -- ── Live ───────────────────────────────────────────────────────────
    local since, smooth, held, heldAt, wasSpeaking = 0, 0, 0, 0, false

    local function redraw()
        for _, c in ipairs(rowHolder:GetChildren()) do c:Destroy() end
        for i, kv in ipairs(Activity.rows(target)) do
            local y = (i - 1) * 22
            local k = Instance.new("TextLabel")
            k.Position = UDim2.new(0, 0, 0, y)
            k.Size = UDim2.fromOffset(104, 16)
            k.BackgroundTransparency = 1
            k.Text = kv[1]
            k.TextColor3 = UI.textMuted
            k.TextXAlignment = Enum.TextXAlignment.Left
            k.TextSize = UI.T_SMALL
            k.ZIndex = 8
            k.Parent = rowHolder
            UI.applyFont(k, Enum.FontWeight.Medium)

            local v = Instance.new("TextLabel")
            v.Position = UDim2.new(0, 108, 0, y)
            v.Size = UDim2.new(1, -108, 0, 16)
            v.BackgroundTransparency = 1
            v.Text = kv[2]
            v.TextColor3 = Color3.fromRGB(228, 229, 236)
            v.TextXAlignment = Enum.TextXAlignment.Left
            v.TextSize = UI.T_SMALL
            v.TextTruncate = Enum.TextTruncate.AtEnd
            v.ZIndex = 8
            v.Parent = rowHolder
            UI.applyFont(v, Enum.FontWeight.SemiBold)
        end

        -- One renderer for both strips: a row of faces with a fallback line.
        local function faces(holder, people, empty)
            for _, c in ipairs(holder:GetChildren()) do c:Destroy() end
            if #people == 0 then
                local none = Instance.new("TextLabel")
                none.Size = UDim2.new(1, 0, 0, 16)
                none.BackgroundTransparency = 1
                none.Text = empty
                none.TextColor3 = UI.textMuted
                none.TextXAlignment = Enum.TextXAlignment.Left
                none.TextSize = UI.T_SMALL
                none.ZIndex = 8
                none.Parent = holder
                UI.applyFont(none, Enum.FontWeight.Regular)
                return
            end
            for i, p in ipairs(people) do
                if i > 8 then break end
                local f = Instance.new("ImageLabel")
                f.Position = UDim2.new(0, (i - 1) * 32, 0, 0)
                f.Size = UDim2.fromOffset(26, 26)
                f.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
                f.BackgroundTransparency = 0.4
                f.Image = UI.headshotFor(p.Name)
                f.ZIndex = 8
                f.Parent = holder
                Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0)
            end
            if #people > 8 then
                local more = Instance.new("TextLabel")
                more.Position = UDim2.new(0, 8 * 32 + 4, 0, 4)
                more.Size = UDim2.fromOffset(40, 18)
                more.BackgroundTransparency = 1
                more.Text = "+" .. (#people - 8)
                more.TextColor3 = UI.textMuted
                more.TextXAlignment = Enum.TextXAlignment.Left
                more.TextSize = UI.T_SMALL
                more.ZIndex = 8
                more.Parent = holder
                UI.applyFont(more, Enum.FontWeight.SemiBold)
            end
        end

        local near = Activity.near(target)
        local flat = {}
        for _, n in ipairs(near) do flat[#flat + 1] = n.player end
        nearLbl.Text = "NEAR THEM" .. (#near > 0 and ("  " .. #near) or "")
        faces(nearHolder, flat, "no one within " .. Activity.NEAR_STUDS .. " studs")

        -- Resolved off-thread, so the first draw shows the fallback and the
        -- next one, half a second later, shows the faces.
        Activity.resolveFriends(target)
        local fr = Activity.friendsOf(target)
        friendLbl.Text = "THEIR FRIENDS HERE" .. (#fr > 0 and ("  " .. #fr) or "")
        faces(friendHolder, fr, "none of their friends are in this server")
        if Activity.min then
            Activity.strip.Text = (#Activity.events > 0
                and Activity.events[1].text or "watching")
        end
    end
    redraw()

    Activity.loop = RunService.RenderStepped:Connect(function(dt)
        if not (Activity.open and Activity.panel) then return end
        if not target.Parent then
            micState.Text = "LEFT THE GAME"
            meter.Visible = false
            return
        end

        local hasMic = Voice.hasMic(target)
        local muted = Voice.muted[target.UserId] == true
        -- Muted or device-less: one quiet line, no meter. The bar is not
        -- the headline here, it is one fact among several.
        meter.Visible = hasMic and not muted
        if not hasMic then
            micState.Text = "NOT IN VOICE CHAT"
            return
        elseif muted then
            micState.Text = "MUTED BY YOU"
            return
        end

        local lvl = Voice.rms(target)
        smooth = smooth + (lvl - smooth) * math.min(1, dt * 14)
        local frac = math.clamp(smooth / Activity.PEAK, 0, 1)
        fill.Size = UDim2.new(frac, 0, 1, 0)

        -- Hot end of the gradient rises with the level, so the bar changes
        -- colour as it fills rather than only getting longer.
        local hot = Color3.fromRGB(255, 255, 255):Lerp(
            Color3.fromRGB(255, 96, 72), math.clamp(frac * 1.4, 0, 1))
        fg.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, UI.accent),
            ColorSequenceKeypoint.new(1, UI.accent:Lerp(hot, math.clamp(frac * 1.2, 0, 1))),
        })

        if frac >= held then
            held, heldAt = frac, os.clock()
        elseif os.clock() - heldAt > 0.6 then
            held = math.max(frac, held - dt * 0.55)
        end
        peak.Visible = held > 0.02
        peak.Position = UDim2.new(held, 0, 0, 0)

        local speaking = lvl >= Activity.SPEAK_RMS
        if speaking ~= wasSpeaking then
            wasSpeaking = speaking
            TweenService:Create(ring, TweenInfo.new(0.18),
                { Transparency = speaking and 0.1 or 1 }):Play()
        end
        micState.Text = speaking and "SPEAKING" or "MICROPHONE"
        scaleLbl.Text = string.format("level %d%%   peak %d%%",
            math.floor(frac * 100), math.floor(held * 100))

        since = since + dt
        if since >= 0.5 then since = 0 redraw() end
    end)

    TweenService:Create(panel,
        TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Size = UDim2.fromOffset(Activity.W, H),
            BackgroundTransparency = UI.panelT(),
        }):Play()
    UI.fadeContent(panel, true)
    task.delay(0.06, function()
        if Activity.panel == panel then UI.fadeContent(panel, false, true) end
    end)
end

-- ════════════════════════════════════════════════════════════════════════
--  SCRIPT HUB  (!scripthub)
--  Same panel as the info and guide modals -- glass, accent wash, chips,
--  gradient buttons -- but floating rather than modal: no backdrop, so it
--  can sit open while you play, and draggable with a collapse and a close
--  in the corner.
--  Backed by ScriptBlox's public API. Opens on scripts for the game you
--  are actually in, since that is what you came for.
-- ════════════════════════════════════════════════════════════════════════
ScriptHub = {
    open = false, min = false,
    -- Collapsed shrinks in BOTH directions. Keeping the full width left a
    -- 560px bar holding a title and one line of text, mostly empty.
    W = 560, MIN_W = 372, HEAD_H = 108, BODY_H = 356, MIN_H = 40, ROW_H = 66,
    ran = {},
    tab = "Game",
    TABS = {
        { key = "Game",      label = "This game" },
        { key = "Universal", label = "Universal" },
        { key = "Trending",  label = "Trending" },
        { key = "Saved",     label = "Saved" },
    },
    cache = {}, rows = {}, favs = {},
    -- Run history is per GAME. A script for Blox Fruits is not something to
    -- offer in Adopt Me, so ScriptHub.ran is this place's bucket and
    -- ScriptHub.history holds the others untouched.
    ran = {}, history = {},
}

function ScriptHub.placeKey() return tostring(game.PlaceId) end

-- Fold this place's list back into the map. Called on the way to disk, so
-- the two can never disagree about what this game's history is.
function ScriptHub.packHistory()
    local h = {}
    for k, v in pairs(ScriptHub.history) do h[k] = v end
    if #ScriptHub.ran > 0 then
        h[ScriptHub.placeKey()] = { at = os.time(), items = ScriptHub.ran }
    else
        h[ScriptHub.placeKey()] = nil
    end

    -- Keep the config from growing forever: ten games is more than anyone
    -- revisits, and the oldest bucket is the one nobody misses.
    local keys = {}
    for k, v in pairs(h) do keys[#keys + 1] = { k = k, at = (v and v.at) or 0 } end
    table.sort(keys, function(a, b) return a.at > b.at end)
    for i = 11, #keys do h[keys[i].k] = nil end
    return h
end

-- The source line is what actually identifies a script -- two hubs can share
-- a title, and ScriptBlox ids are not in the search payload.
function ScriptHub.favKey(e)
    return tostring(e.title) .. "|" .. tostring(e.source)
end

-- Which scripts are live in THIS CLIENT SESSION.
--
-- Executed scripts outlive the hub, so re-executing Universal Hub must not
-- forget them -- but they die the moment you rejoin, whatever server you
-- land in. The first version keyed this on game.JobId, which was wrong:
-- !rejoin can drop you back into the SAME server, JobId matches, and the
-- flags came back for scripts the reload had already killed. JobId answers
-- "which server", not "did my session survive".
--
-- LocalPlayer answers the actual question. It is a fresh Instance on every
-- join and the same one across a re-execute, so identity comparison is
-- exactly the lifetime we want. Held in getgenv so it outlives the script
-- rather than the config, since a set of live scripts is not something to
-- write to disk in the first place.
function ScriptHub.liveSet()
    local ok, g = pcall(getgenv)
    if not (ok and type(g) == "table") then
        -- No shared environment: fall back to a plain table, which simply
        -- means a re-execute forgets. Better than claiming a script runs.
        ScriptHub._running = ScriptHub._running or {}
        return ScriptHub._running
    end
    local box = g.UHUB_RUNNING
    if type(box) ~= "table" or box.player ~= LocalPlayer then
        box = { player = LocalPlayer, keys = {} }
        g.UHUB_RUNNING = box
    end
    return box.keys
end

function ScriptHub.isRunning(e)
    return ScriptHub.liveSet()[ScriptHub.favKey(e)] == true
end

function ScriptHub.markRunning(e)
    ScriptHub.liveSet()[ScriptHub.favKey(e)] = true
end

function ScriptHub.isFav(e)
    local k = ScriptHub.favKey(e)
    for _, f in ipairs(ScriptHub.favs) do
        if ScriptHub.favKey(f) == k then return true end
    end
    return false
end

function ScriptHub.toggleFav(e)
    local k = ScriptHub.favKey(e)
    for i, f in ipairs(ScriptHub.favs) do
        if ScriptHub.favKey(f) == k then
            table.remove(ScriptHub.favs, i)
            ScriptHub.cache["Saved|"] = nil
            UI.saveConfig()
            return false
        end
    end
    -- Store a copy, not the row's own table: the row is destroyed on the
    -- next render and a saved script has to outlive the search that found it.
    table.insert(ScriptHub.favs, {
        title = e.title, source = e.source, gameName = e.gameName,
        placeId = e.placeId, universal = e.universal,
        key = e.key, patched = e.patched, verified = e.verified,
    })
    ScriptHub.cache["Saved|"] = nil
    UI.saveConfig()
    return true
end

ScriptHub.API = "https://scriptblox.com/api/script"

-- game:HttpGet takes a raw URL, so the query has to be escaped here or a
-- game with a space in its name produces a malformed request.
function ScriptHub.encode(str)
    return (tostring(str or ""):gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

-- Every executor spells this differently and any of them can be missing.
function ScriptHub.httpGet(url)
    local ok, body = pcall(function() return game:HttpGet(url, true) end)
    if ok and type(body) == "string" then return body end
    ok, body = pcall(function()
        local req = (syn and syn.request) or (http and http.request) or request
        if not req then error("no request()") end
        local r = req({ Url = url, Method = "GET" })
        return r and r.Body
    end)
    return (ok and type(body) == "string") and body or nil
end

-- ScriptBlox marks universal scripts and hubs with a gameId of -1 (or 0).
local function isUniversal(entry)
    local g = entry.game or {}
    local id = tonumber(g.gameId) or -1
    return entry.isUniversal == true or id <= 0
end

function ScriptHub.parse(body)
    if not body then return nil end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(body)
    end)
    if not (ok and type(data) == "table") then return nil end
    local list = data.result and data.result.scripts
    if type(list) ~= "table" then return nil end

    local out = {}
    for _, e in ipairs(list) do
        if type(e) == "table" and e.script and e.title then
            local g = e.game or {}
            out[#out + 1] = {
                title    = tostring(e.title),
                gameName = tostring(g.name or "Universal"),
                placeId  = tonumber(g.gameId) or 0,   -- ScriptBlox gives a PLACE id here
                source   = tostring(e.script),
                verified = e.verified == true,
                key      = e.key == true,
                patched  = e.isPatched == true,
                universal = isUniversal(e),
                views    = tonumber(e.views) or 0,
                -- Kept for the details panel. Everything the API hands back
                -- that a person could want to know before running a script.
                slug     = type(e.slug) == "string" and e.slug or nil,
                paid     = e.scriptType == "paid",
                created  = type(e.createdAt) == "string" and e.createdAt or nil,
                bumped   = type(e.lastBump) == "string" and e.lastBump or nil,
            }
        end
    end
    return out
end

-- Results per tab are fetched once and kept: every switch back would
-- otherwise be another round trip for a list that has not changed.
function ScriptHub.fetch(tab, query, done)
    local key = tab .. "|" .. tostring(query or "")
    -- Saved is local: no request, and searching it filters what is already
    -- here rather than going back out to ScriptBlox.
    if tab == "Saved" then
        if not query or query == "" then done(ScriptHub.favs) return end
        local q, out = query:lower(), {}
        for _, f in ipairs(ScriptHub.favs) do
            if f.title:lower():find(q, 1, true) then out[#out + 1] = f end
        end
        done(out)
        return
    end
    if ScriptHub.cache[key] then done(ScriptHub.cache[key]) return end

    task.spawn(function()
        local url
        if tab == "Trending" then
            url = ScriptHub.API .. "/fetch?page=1&max=20"
        else
            local q = query
            if not q or q == "" then
                if tab == "Game" then
                    local info = About.place()
                    q = (info and info.Name) or "roblox"
                else
                    q = "universal"
                end
            end
            url = ScriptHub.API .. "/search?q=" .. ScriptHub.encode(q) .. "&max=20"
        end

        local list = ScriptHub.parse(ScriptHub.httpGet(url))
        if not list then done(nil) return end

        -- The API searches titles, so a query for the current game still
        -- returns hubs and unrelated results. Filter to what the tab claims.
        local filtered = {}
        for _, e in ipairs(list) do
            local keep = true
            if tab == "Game" and query == nil then
                keep = (e.placeId == game.PlaceId) or e.universal
            elseif tab == "Universal" then
                keep = e.universal
            end
            if keep then filtered[#filtered + 1] = e end
        end
        -- A game nobody has written for would otherwise render as an empty
        -- panel that looks broken; show what the search did find instead.
        if #filtered == 0 then filtered = list end

        ScriptHub.cache[key] = filtered
        done(filtered)
    end)
end

-- ── Chrome ──────────────────────────────────────────────────────────────
-- Shared: the script hub and the activity panel both float, and a second
-- copy of this would drift from the first the moment either is restyled.
function UI.chromeButton(parent, iconFile, x, onClick)
    local b = Instance.new("TextButton")
    b.AnchorPoint = Vector2.new(1, 0)
    b.Position = UDim2.new(1, x, 0, 18)
    b.Size = UDim2.fromOffset(24, 24)
    b.AutoButtonColor = false
    b.Text = ""
    b.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    b.BackgroundTransparency = 0.92
    b.BorderSizePixel = 0
    b.ZIndex = 9
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)

    local ic = Instance.new("ImageLabel")
    ic.AnchorPoint = Vector2.new(0.5, 0.5)
    ic.Position = UDim2.fromScale(0.5, 0.5)
    ic.Size = UDim2.fromOffset(12, 12)
    ic.BackgroundTransparency = 1
    ic.Image = UI.icon(iconFile)
    ic.ImageColor3 = Color3.fromRGB(214, 216, 224)
    ic.ZIndex = 10
    ic.Parent = b

    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), { BackgroundTransparency = 0.82 }):Play()
        TweenService:Create(ic, TweenInfo.new(0.12), { ImageColor3 = UI.accent }):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.14), { BackgroundTransparency = 0.92 }):Play()
        TweenService:Create(ic, TweenInfo.new(0.14),
            { ImageColor3 = Color3.fromRGB(214, 216, 224) }):Play()
    end)
    -- The collapsed strip moves these up; remember the X they were placed at
    -- so the reflow does not have to re-derive it.
    b:SetAttribute("_x", x)
    b.MouseButton1Click:Connect(onClick)
    return b, ic
end

-- ── Details ─────────────────────────────────────────────────────────────
-- Clicking a row opens everything the API gave us about that script. It is
-- a panel INSIDE the list rather than another modal, so the row you opened
-- stays in view and closing it puts you back exactly where you were.
ScriptHub.DETAIL_H = 132

-- "2026-07-24T23:49:22.398Z" is not something anyone reads. Turn it into an
-- age, which is the thing that actually matters for a script.
function ScriptHub.ago(iso)
    if type(iso) ~= "string" then return nil end
    local y, mo, d = iso:match("^(%d+)-(%d+)-(%d+)")
    if not y then return nil end
    local okNow, now = pcall(function() return os.date("!*t") end)
    if not okNow or not now then return nil end

    -- Whole days between two dates, without a full calendar library: good
    -- enough to say "3 days ago", which is all this is for.
    local function toDays(yy, mm, dd)
        yy, mm, dd = tonumber(yy), tonumber(mm), tonumber(dd)
        if mm <= 2 then yy, mm = yy - 1, mm + 12 end
        return math.floor(365.25 * yy) + math.floor(30.6001 * (mm + 1)) + dd
    end
    local days = toDays(now.year, now.month, now.day) - toDays(y, mo, d)
    if days < 0 then return nil end
    if days == 0 then return "today" end
    if days == 1 then return "yesterday" end
    if days < 30 then return days .. " days ago" end
    if days < 365 then
        local m = math.floor(days / 30)
        return m .. (m == 1 and " month ago" or " months ago")
    end
    local yrs = math.floor(days / 365)
    return yrs .. (yrs == 1 and " year ago" or " years ago")
end

-- One row per fact, skipping anything the API did not give us -- a details
-- panel of "unknown" is worse than a shorter one.
function ScriptHub.detailRows(e)
    local out = {}
    local function add(k, v) if v and v ~= "" then out[#out + 1] = { k, v } end end

    add("Game", e.universal and "Universal -- works anywhere" or e.gameName)
    if e.views > 0 then
        add("Views", tostring(e.views))
    end
    add("Added", ScriptHub.ago(e.created))
    if e.bumped and e.bumped ~= e.created then
        add("Updated", ScriptHub.ago(e.bumped))
    end

    local flags = {}
    if e.verified then flags[#flags + 1] = "verified" end
    if e.key then flags[#flags + 1] = "key required" end
    if e.patched then flags[#flags + 1] = "patched" end
    if e.paid then flags[#flags + 1] = "paid" end
    add("Status", #flags > 0 and table.concat(flags, ", ") or "no flags")

    add("Source", (#e.source > 60) and (e.source:sub(1, 60) .. "\226\128\166") or e.source)
    return out
end

function ScriptHub.buildDetail(parent, e, width)
    local PAD = 14

    local sep = Instance.new("Frame")
    sep.Position = UDim2.new(0, PAD, 0, 0)
    sep.Size = UDim2.new(1, -PAD * 2, 0, 1)
    sep.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    sep.BackgroundTransparency = 0.9
    sep.BorderSizePixel = 0
    sep.ZIndex = 9
    sep.Parent = parent

    local rows = ScriptHub.detailRows(e)
    for i, kv in ipairs(rows) do
        local y = 10 + (i - 1) * 18

        local k = Instance.new("TextLabel")
        k.Position = UDim2.new(0, PAD, 0, y)
        k.Size = UDim2.fromOffset(70, 16)
        k.BackgroundTransparency = 1
        k.Text = kv[1]
        k.TextColor3 = UI.textMuted
        k.TextXAlignment = Enum.TextXAlignment.Left
        k.TextSize = UI.T_SMALL
        k.ZIndex = 9
        k.Parent = parent
        UI.applyFont(k, Enum.FontWeight.Medium)

        local v = Instance.new("TextLabel")
        v.Position = UDim2.new(0, PAD + 74, 0, y)
        v.Size = UDim2.new(1, -(PAD * 2 + 74 + 76), 0, 16)
        v.BackgroundTransparency = 1
        v.Text = kv[2]
        v.TextColor3 = Color3.fromRGB(224, 225, 230)
        v.TextXAlignment = Enum.TextXAlignment.Left
        v.TextSize = UI.T_SMALL
        v.TextTruncate = Enum.TextTruncate.AtEnd
        v.ZIndex = 9
        v.Parent = parent
        UI.applyFont(v, Enum.FontWeight.Regular)
    end

    -- The page it came from, for anything this panel cannot show.
    if e.slug then
        local link = UI.gradButton(parent, "Copy link", "st_copy.png", "ghost")
        UI.smallButton(link)
        link.AnchorPoint = Vector2.new(1, 1)
        link.Position = UDim2.new(1, -PAD, 1, -10)
        link.ZIndex = 10
        link.MouseButton1Click:Connect(function()
            pcall(function()
                setclipboard("https://scriptblox.com/script/" .. e.slug)
            end)
            Notifications:Success("Script Hub", "Page link copied", 3)
        end)
    end
end

-- ── Expanding a row ─────────────────────────────────────────────────────
-- Done by tweening the row that was clicked and sliding the ones below it,
-- NOT by re-rendering the list. A re-render destroys every row including
-- the one you just clicked, so there is nothing left to animate -- which is
-- why this used to snap open.
ScriptHub.EASE = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- Target heights, not rendered ones: reflow runs the instant the resize
-- tween starts, when Size still reports the height the row is leaving.
function ScriptHub.rowH(r)
    return r:GetAttribute("_h") or r.Size.Y.Offset
end

function ScriptHub.reflowRows(animate)
    local y = 0
    for _, r in ipairs(ScriptHub.rows) do
        if r and r.Parent then
            local target = UDim2.new(0, 0, 0, y)
            if animate then
                TweenService:Create(r, ScriptHub.EASE, { Position = target }):Play()
            else
                r.Position = target
            end
            y = y + ScriptHub.rowH(r) + 6
        end
    end
    if ScriptHub.list then
        ScriptHub.list.CanvasSize = UDim2.new(0, 0, 0, y + 6)
    end
end

function ScriptHub.collapseRow(r)
    if not (r and r.Parent and r:GetAttribute("_open")) then return end
    r:SetAttribute("_open", false)
    r:SetAttribute("_h", ScriptHub.ROW_H - 6)
    ScriptHub.openKey = nil

    local chev = r:FindFirstChild("Chevron")
    if chev then
        TweenService:Create(chev, ScriptHub.EASE, { Rotation = 0 }):Play()
    end
    TweenService:Create(r, ScriptHub.EASE, {
        Size = UDim2.new(1, -8, 0, ScriptHub.ROW_H - 6),
        BackgroundTransparency = 0.955,
    }):Play()

    -- The panel is destroyed only after the row has finished closing over
    -- it, or it vanishes before the animation reads as one.
    local det = r:FindFirstChild("Detail")
    if det then
        task.delay(0.3, function() pcall(function() det:Destroy() end) end)
    end
end

function ScriptHub.expandRow(r, e)
    if not (r and r.Parent) then return end
    -- One at a time: two open panels turn the list into a wall.
    for _, other in ipairs(ScriptHub.rows) do
        if other ~= r then ScriptHub.collapseRow(other) end
    end

    r:SetAttribute("_open", true)
    r:SetAttribute("_h", ScriptHub.ROW_H - 6 + ScriptHub.DETAIL_H)
    ScriptHub.openKey = ScriptHub.favKey(e)

    if not r:FindFirstChild("Detail") then
        local det = Instance.new("Frame")
        det.Name = "Detail"
        det.Position = UDim2.new(0, 0, 0, ScriptHub.ROW_H - 6)
        det.Size = UDim2.new(1, 0, 0, ScriptHub.DETAIL_H)
        det.BackgroundTransparency = 1
        det.ZIndex = 9
        det.Parent = r
        ScriptHub.buildDetail(det, e, 0)
        -- Fade the contents in behind the opening row rather than having
        -- them appear fully formed the moment there is room.
        UI.fadeContent(det, true)
        task.delay(0.08, function()
            if det and det.Parent then UI.fadeContent(det, false, true) end
        end)
    end

    local chev = r:FindFirstChild("Chevron")
    if chev then
        TweenService:Create(chev, ScriptHub.EASE, { Rotation = 90 }):Play()
    end
    TweenService:Create(r, ScriptHub.EASE, {
        Size = UDim2.new(1, -8, 0, ScriptHub.ROW_H - 6 + ScriptHub.DETAIL_H),
        BackgroundTransparency = 0.9,
    }):Play()
end

function ScriptHub.toggleRow(r, e)
    -- Explicit if/else. The and/or idiom is not a ternary when its first
    -- branch is nil: Lua falls through to the second because nil is falsy,
    -- so the toggle could never clear the key and the row re-opened itself
    -- on every click.
    if r:GetAttribute("_open") then
        ScriptHub.collapseRow(r)
    else
        ScriptHub.expandRow(r, e)
    end
    ScriptHub.reflowRows(true)
end

-- ── Rows ────────────────────────────────────────────────────────────────
function ScriptHub.renderRows(list)
    for _, r in ipairs(ScriptHub.rows) do pcall(function() r:Destroy() end) end
    ScriptHub.rows = {}
    local L = ScriptHub.list
    if not L then return end

    if list == nil then
        ScriptHub.setStatus("Could not reach ScriptBlox. Check your executor's HTTP support.")
        return
    end
    if #list == 0 then
        ScriptHub.setStatus(ScriptHub.tab == "Saved"
            and "No saved scripts yet. Star one to keep it."
            or "Nothing found.")
        return
    end
    ScriptHub.setStatus(nil)

    local y = 0
    for _, e in ipairs(list) do
        local row = Instance.new("Frame")
        row.Position = UDim2.new(0, 0, 0, y)
        row.Size = UDim2.new(1, -8, 0, ScriptHub.ROW_H - 6)
        row:SetAttribute("_h", ScriptHub.ROW_H - 6)
        row:SetAttribute("_open", false)
        -- The detail panel is built at full height and revealed by the row
        -- growing over it, so the row has to clip.
        row.ClipsDescendants = true
        row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        row.BackgroundTransparency = 0.955
        row.BorderSizePixel = 0
        row.ZIndex = 8
        row.Parent = L
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 9)

        -- ScriptBlox's own images are web URLs, which Roblox cannot render.
        -- Its gameId is a PLACE id though, so the game's real icon resolves
        -- through the same lookup quickjoin uses.
        local th = Instance.new("ImageLabel")
        th.AnchorPoint = Vector2.new(0, 0)
        th.Position = UDim2.new(0, 12, 0, 10)
        th.Size = UDim2.fromOffset(40, 40)
        th.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        th.BackgroundTransparency = 0.45
        th.ZIndex = 9
        th.Parent = row
        Instance.new("UICorner", th).CornerRadius = UDim.new(0, 9)

        -- Universal scripts and hubs have no game to take an icon from, and
        -- a row of identical globes reads as "broken", not "universal".
        -- Monogram the title instead: distinct per row, and obviously
        -- deliberate.
        local mono = Instance.new("TextLabel")
        mono.AnchorPoint = Vector2.new(0.5, 0.5)
        mono.Position = UDim2.fromScale(0.5, 0.5)
        mono.Size = UDim2.fromScale(1, 1)
        mono.BackgroundTransparency = 1
        mono.Text = e.title:sub(1, 1):upper()
        mono.TextColor3 = UI.accent
        mono.TextSize = 19
        mono.ZIndex = 10
        mono.Parent = th
        UI.applyFont(mono, Enum.FontWeight.Bold)

        -- The monogram is also the fallback for a place whose icon lookup
        -- comes back empty, so no row is ever left as a bare grey square.
        if not e.universal then
            UI.placeIcon(e.placeId, function(img)
                if th and th.Parent then
                    th.Image = img
                    if mono and mono.Parent then mono.Visible = false end
                end
            end)
        end

        -- Width the buttons will take, measured rather than guessed. The
        -- old -210 was a guess that also forgot the labels start 62px in,
        -- so the title ran 63px underneath the Run button.
        local TEXT_PAD = 62 + 12 + 18 + 8 + UI.btnWidth("Copy", true)
                         + 8 + UI.btnWidth("Running", true) + 12

        local title = Instance.new("TextLabel")
        title.Position = UDim2.new(0, 62, 0, 10)
        title.Size = UDim2.new(1, -TEXT_PAD, 0, 18)
        title.BackgroundTransparency = 1
        title.Text = e.title
        title.TextColor3 = Color3.fromRGB(238, 239, 244)
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.TextSize = UI.T_ROW
        title.TextTruncate = Enum.TextTruncate.AtEnd
        title.ZIndex = 9
        title.Parent = row
        UI.applyFont(title, Enum.FontWeight.SemiBold)

        -- Which game a script is for is the first thing you need off a row,
        -- so it is labelled rather than left as a bare name that could be
        -- mistaken for part of the title. Badges follow: "key required" and
        -- "patched" are the difference between a script that runs and one
        -- that wastes your time, so they belong here, not behind a hover.
        --
        -- Colours are wrapped per-badge rather than gsub'd over the finished
        -- string: a game literally called "Verified Hub" would otherwise
        -- come out half green.
        local function tint(hex, text)
            return '<font color="' .. hex .. '">' .. text .. "</font>"
        end
        local bits = { tint("#9a9daa", "Game:") .. " " .. e.gameName }
        if e.key then bits[#bits + 1] = tint("#ffcf5c", "key required") end
        if e.patched then bits[#bits + 1] = tint("#ff7a7a", "patched") end
        if e.verified then bits[#bits + 1] = tint("#7ee08a", "verified") end

        local sub = Instance.new("TextLabel")
        sub.Position = UDim2.new(0, 62, 0, 30)
        sub.Size = UDim2.new(1, -TEXT_PAD, 0, 16)
        sub.BackgroundTransparency = 1
        sub.RichText = true
        sub.Text = table.concat(bits, "  \194\183  ")
        sub.TextColor3 = UI.textMuted
        sub.TextXAlignment = Enum.TextXAlignment.Left
        sub.TextSize = UI.T_SMALL
        sub.TextTruncate = Enum.TextTruncate.AtEnd
        sub.ZIndex = 9
        sub.Parent = row
        UI.applyFont(sub, Enum.FontWeight.Regular)

        -- Star sits outside the button pair: saving is a different kind of
        -- act from running, and it should not sit where Run is muscle memory.
        local star = Instance.new("ImageButton")
        star.AnchorPoint = Vector2.new(1, 0)
        star.Position = UDim2.new(1, -12, 0, 21)
        star.Size = UDim2.fromOffset(18, 18)
        star.BackgroundTransparency = 1
        star.AutoButtonColor = false
        star.Image = UI.icon("st_star.png")
        star.ZIndex = 10
        star.Parent = row

        -- Lucide's star is stroke-only (fill="none"), so tinting it can never
        -- read as filled -- it just recolours the outline. Saved swaps to a
        -- genuinely filled glyph.
        local function paintStar()
            local on = ScriptHub.isFav(e)
            star.Image = UI.icon(on and "st_star-fill.png" or "st_star.png")
            star.ImageColor3 = on and UI.accent or Color3.fromRGB(255, 255, 255)
            star.ImageTransparency = on and 0 or 0.7
        end
        paintStar()
        star.MouseEnter:Connect(function()
            if not ScriptHub.isFav(e) then
                TweenService:Create(star, TweenInfo.new(0.12), { ImageTransparency = 0.25 }):Play()
            end
        end)
        star.MouseLeave:Connect(paintStar)
        star.MouseButton1Click:Connect(function()
            local added = ScriptHub.toggleFav(e)
            TweenService:Create(star, TweenInfo.new(0.16, Enum.EasingStyle.Back,
                Enum.EasingDirection.Out), { Size = UDim2.fromOffset(22, 22) }):Play()
            task.delay(0.16, function()
                pcall(function()
                    TweenService:Create(star, TweenInfo.new(0.14),
                        { Size = UDim2.fromOffset(18, 18) }):Play()
                end)
            end)
            paintStar()
            -- Unstarring from the Saved tab has to drop the row, or it sits
            -- there claiming to be saved when it is not.
            if not added and ScriptHub.tab == "Saved" then ScriptHub.load() end
        end)

        local src = e.source
        local copy = UI.gradButton(row, "Copy", "st_copy.png", "ghost")
        copy.AnchorPoint = Vector2.new(1, 0)
        copy.Position = UDim2.new(1, -38, 0, 14)
        copy.ZIndex = 10
        copy.MouseButton1Click:Connect(function()
            pcall(function() setclipboard(src) end)
            Notifications:Success("Script Hub", "Copied \"" .. e.title .. "\"", 3)
        end)

        -- Built at the LONGER label so the button keeps one width: sizing it
        -- to "Run" would make the row jump when it becomes "Running".
        local run = UI.gradButton(row, "Running", "st_zap.png", "light")
        run.AnchorPoint = Vector2.new(1, 0)
        run.Position = UDim2.new(1, -46 - copy.Size.X.Offset, 0, 14)
        run.ZIndex = 10

        local runLabel = run:FindFirstChildWhichIsA("TextLabel")
        local runIcon = run:FindFirstChildWhichIsA("ImageLabel")
        local function paintRun()
            local on = ScriptHub.isRunning(e)
            if runLabel then runLabel.Text = on and "Running" or "Run" end
            if runIcon then
                runIcon.Image = UI.icon(on and "st_circle-check.png" or "st_zap.png")
            end
            UI.dimButton(run, on)
        end
        paintRun()

        run.MouseButton1Click:Connect(function()
            -- Already live in this server; running it twice stacks a second
            -- copy of somebody else's GUI on top of the first.
            if ScriptHub.isRunning(e) then return end
            -- The API hands back either a loadstring one-liner or the source
            -- itself; compiling the string covers both.
            local okC, fn = pcall(loadstring, src)
            if not (okC and fn) then
                Notifications:Error("Script Hub", "That script would not compile", 4)
                return
            end
            local okR, err = pcall(fn)
            if okR then
                ScriptHub.noteRan(e)
                ScriptHub.markRunning(e)
                paintRun()
                Notifications:Success("Script Hub", "Ran \"" .. e.title .. "\"", 3.5)
            else
                Notifications:Error("Script Hub", tostring(err):sub(1, 90), 5)
            end
        end)

        -- The whole row opens it, minus the controls: those are ImageButtons
        -- and TextButtons, which sink the click before it reaches here.
        local hit = Instance.new("TextButton")
        hit.Position = UDim2.new(0, 0, 0, 0)
        hit.Size = UDim2.new(1, 0, 0, ScriptHub.ROW_H - 6)
        hit.BackgroundTransparency = 1
        hit.AutoButtonColor = false
        hit.Text = ""
        hit.ZIndex = 8            -- under the buttons, over the labels
        hit.Parent = row
        hit.MouseButton1Click:Connect(function()
            ScriptHub.toggleRow(row, e)
        end)

        local chev = Instance.new("ImageLabel")
        chev.Name = "Chevron"
        chev.AnchorPoint = Vector2.new(1, 0)
        chev.Position = UDim2.new(1, -12, 0, 44)
        chev.Size = UDim2.fromOffset(12, 12)
        chev.BackgroundTransparency = 1
        chev.Image = UI.icon("st_chevron-right.png")
        chev.ImageColor3 = UI.textMuted
        chev.ImageTransparency = 0.4
        chev.Rotation = 0
        chev.ZIndex = 9
        chev.Parent = row

        ScriptHub.rows[#ScriptHub.rows + 1] = row
        y = y + (ScriptHub.ROW_H - 6) + 6
    end
    L.CanvasSize = UDim2.new(0, 0, 0, y + 6)
end

function ScriptHub.setStatus(text)
    if not ScriptHub.status then return end
    ScriptHub.status.Visible = text ~= nil
    ScriptHub.status.Text = text or ""
end

function ScriptHub.load()
    -- Rows are NOT cleared up front. On a live search that would blank the
    -- list on every keystroke and flash it back; leaving the previous
    -- results up until the new ones arrive reads as filtering, not reloading.
    if #ScriptHub.rows == 0 then ScriptHub.setStatus("Searching\226\128\166") end

    -- Whatever was expanded belongs to the list being replaced.
    ScriptHub.openKey = nil

    local q = ScriptHub.search and ScriptHub.search.Text or ""
    if q == "" then q = nil end
    local want = ScriptHub.tab
    ScriptHub.fetch(want, q, function(list)
        -- The user can switch tabs or type on while a request is in flight.
        -- Dropping a stale answer is cheaper than cancelling the request,
        -- and without the query check a slow response to "mm" lands on top
        -- of the results for "mm2".
        if ScriptHub.tab ~= want or not ScriptHub.open then return end
        local now = ScriptHub.search and ScriptHub.search.Text or ""
        if now ~= (q or "") then return end
        ScriptHub.renderRows(list)
    end)
end

-- Live search, one request per pause rather than one per character. Enter
-- still works and skips the wait.
ScriptHub.DEBOUNCE = 0.35

function ScriptHub.onType()
    ScriptHub.typeToken = (ScriptHub.typeToken or 0) + 1
    local mine = ScriptHub.typeToken
    -- Saved is filtered locally, so there is nothing to wait for.
    if ScriptHub.tab == "Saved" then ScriptHub.load() return end
    task.delay(ScriptHub.DEBOUNCE, function()
        if ScriptHub.typeToken ~= mine or not ScriptHub.open then return end
        ScriptHub.load()
    end)
end

-- ── Panel ───────────────────────────────────────────────────────────────
-- What the collapsed strip reports. A hub you have minimised is one you
-- have already used, so the useful thing to show is what you ran from it.
-- What you ran THIS session. ScriptHub.ran is the persisted per-game
-- history, which is loaded from disk on join -- reading it here made the
-- collapsed strip claim scripts were run that belong to a previous session.
ScriptHub.session = {}

function ScriptHub.miniText()
    local n = #ScriptHub.session
    if n == 0 then return "Nothing run yet" end
    local last = ScriptHub.session[1].title
    if n == 1 then return "Ran  " .. last end
    return "Ran  " .. last .. "  \194\183  +" .. (n - 1) .. " more"
end

-- Holds ENTRIES, not titles: the resume prompt has to be able to run these
-- again next session, which needs the source, not a label.
function ScriptHub.noteRan(e)
    -- Most recent first, and no duplicates: running the same hub twice
    -- should not push everything else out of the list.
    local k = ScriptHub.favKey(e)
    for i, t in ipairs(ScriptHub.ran) do
        if ScriptHub.favKey(t) == k then table.remove(ScriptHub.ran, i) break end
    end
    local rec = {
        title = e.title, source = e.source, gameName = e.gameName,
        placeId = e.placeId, universal = e.universal,
    }
    table.insert(ScriptHub.ran, 1, rec)
    while #ScriptHub.ran > 8 do table.remove(ScriptHub.ran) end

    -- The session list is never loaded from disk, so the strip can only
    -- ever report things this run of the hub actually launched.
    for i, t in ipairs(ScriptHub.session) do
        if ScriptHub.favKey(t) == k then table.remove(ScriptHub.session, i) break end
    end
    table.insert(ScriptHub.session, 1, rec)
    while #ScriptHub.session > 8 do table.remove(ScriptHub.session) end
    if ScriptHub.mini then ScriptHub.mini.Text = ScriptHub.miniText() end
    UI.saveConfig()
end

function ScriptHub.setMin(on)
    if not ScriptHub.panel or ScriptHub.min == on then return end
    ScriptHub.min = on
    local h = on and ScriptHub.MIN_H or (ScriptHub.HEAD_H + ScriptHub.BODY_H)
    local ti = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    if on then ScriptHub.body.Visible = false end
    ScriptHub.minIcon.Image = UI.icon(on and "st_maximize.png" or "st_minimize.png")

    -- The header has to reflow, not just get clipped: at full size the title
    -- ends at 44px and the subtitle at 63, so any strip shorter than that
    -- had them spilling out of the panel.
    ScriptHub.sub.Visible = not on
    ScriptHub.mini.Visible = on
    if on then ScriptHub.mini.Text = ScriptHub.miniText() end
    TweenService:Create(ScriptHub.title, ti, {
        Position = UDim2.new(0, 24, 0, on and 10 or 20),
        TextSize = on and 15 or 20,
    }):Play()
    for _, b in ipairs(ScriptHub.chrome) do
        TweenService:Create(b, ti, {
            Position = UDim2.new(1, b:GetAttribute("_x"), 0, on and 9 or 18),
            Size = UDim2.fromOffset(on and 22 or 24, on and 22 or 24),
        }):Play()
    end

    -- The grip is 70px tall for the full header; left at that it would hang
    -- below a 40px strip and swallow clicks meant for the game.
    if ScriptHub.grip then
        TweenService:Create(ScriptHub.grip, ti,
            { Size = UDim2.new(1, -90, 0, on and ScriptHub.MIN_H or 70) }):Play()
    end

    local t = TweenService:Create(ScriptHub.panel, ti,
        { Size = UDim2.fromOffset(on and ScriptHub.MIN_W or ScriptHub.W, h) })
    t:Play()
    if not on then
        t.Completed:Connect(function()
            if not ScriptHub.min then ScriptHub.body.Visible = true end
        end)
    end
end

function ScriptHub.hide()
    if not ScriptHub.open then return end
    ScriptHub.open = false
    local gui, panel = ScriptHub.gui, ScriptHub.panel
    ScriptHub.gui, ScriptHub.panel = nil, nil
    if not gui then return end
    pcall(function()
        TweenService:Create(panel,
            TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
                Size = UDim2.fromOffset(ScriptHub.W - 24, panel.Size.Y.Offset - 16),
                BackgroundTransparency = 1,
            }):Play()
        UI.fadeContent(panel, true, true)
    end)
    task.delay(0.26, function() pcall(function() gui:Destroy() end) end)
end

-- Registered once. show() runs on every !scripthub, and a second copy of
-- these would drag the panel at twice the cursor speed.
function ScriptHub.bindDrag()
    if ScriptHub.dragBound then return end
    ScriptHub.dragBound = true
    local grab, origin

    ScriptHub.dragBegan = function(i)
        if not ScriptHub.panel then return end
        ScriptHub.dragging = true
        grab = Vector2.new(i.Position.X, i.Position.Y)
        origin = Vector2.new(ScriptHub.panel.Position.X.Offset,
                             ScriptHub.panel.Position.Y.Offset)
    end

    UserInputService.InputChanged:Connect(function(i)
        if not (ScriptHub.dragging and ScriptHub.panel) then return end
        if i.UserInputType ~= Enum.UserInputType.MouseMovement
           and i.UserInputType ~= Enum.UserInputType.Touch then return end
        local d = Vector2.new(i.Position.X, i.Position.Y) - grab
        local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
                   or Vector2.new(1280, 720)
        -- Keep a strip of the header on screen, or the panel can be dragged
        -- somewhere it can never be grabbed back from.
        local x = math.clamp(origin.X + d.X, -(vp.X / 2) + 60, (vp.X / 2) - 60)
        local y = math.clamp(origin.Y + d.Y, -(vp.Y / 2) + 30, (vp.Y / 2) - 30)
        ScriptHub.panel.Position = UDim2.new(0.5, x, 0.5, y)
    end)

    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
           or i.UserInputType == Enum.UserInputType.Touch then
            ScriptHub.dragging = false
        end
    end)
end

function ScriptHub.show()
    if ScriptHub.open then ScriptHub.hide() return end
    ScriptHub.open = true
    ScriptHub.min = false
    ScriptHub.tab = "Game"
    ScriptHub.bindDrag()

    local H = ScriptHub.HEAD_H + ScriptHub.BODY_H
    local PAD = 24

    local gui = Instance.new("ScreenGui")
    gui.Name = "UHubLiteScriptHub"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 9999            -- under the modal, over the game
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function()
        gui.Parent = (typeof(gethui) == "function" and gethui())
                  or game:GetService("CoreGui")
    end)
    ScriptHub.gui = gui

    -- No backdrop: this is a panel you keep open while you play, not a
    -- modal that takes the screen.
    local panel = Instance.new("Frame")
    panel.Name = "HubPanel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.new(0.5, 0, 0.5, 0)
    panel.Size = UDim2.fromOffset(ScriptHub.W - 24, H - 16)
    panel.BackgroundColor3 = UI.cardFill
    panel.BackgroundTransparency = 1
    panel.BorderSizePixel = 0
    -- Collapsing shrinks the panel past its own content; without this the
    -- list and subtitle hang out of the strip mid-tween.
    panel.ClipsDescendants = true
    panel.ZIndex = 5
    panel.Parent = gui
    UI.glassify(panel, 16)
    UI.accentWash(panel)
    ScriptHub.panel = panel

    local title = Instance.new("TextLabel")
    title.Position = UDim2.new(0, PAD, 0, 20)
    title.Size = UDim2.new(1, -PAD - 80, 0, 24)
    title.BackgroundTransparency = 1
    title.Text = "Script Hub"
    title.TextColor3 = UI.textPrimary
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextSize = 20
    title.ZIndex = 6
    title.Parent = panel
    UI.applyFont(title, Enum.FontWeight.Bold)

    local sub = Instance.new("TextLabel")
    sub.Position = UDim2.new(0, PAD, 0, 45)
    sub.Size = UDim2.new(1, -PAD - 80, 0, 18)
    sub.BackgroundTransparency = 1
    sub.Text = "Searching for this game\226\128\166"
    sub.TextColor3 = UI.textMuted
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.TextSize = UI.T_ROW
    sub.TextTruncate = Enum.TextTruncate.AtEnd
    sub.ZIndex = 6
    sub.Parent = panel
    UI.applyFont(sub, Enum.FontWeight.Regular)
    ScriptHub.title, ScriptHub.sub = title, sub
    task.spawn(function()
        local info = About.place()
        if sub and sub.Parent then
            sub.Text = "Scripts for " .. ((info and info.Name) or "this game")
        end
    end)

    -- Collapsed strip: sits on the title's line rather than under it, so the
    -- whole bar can be 40px instead of stacking two rows of text.
    local mini = Instance.new("TextLabel")
    mini.AnchorPoint = Vector2.new(1, 0)
    mini.Position = UDim2.new(1, -80, 0, 12)
    mini.Size = UDim2.new(1, -190, 0, 17)   -- 182px inside the 372px strip
    mini.BackgroundTransparency = 1
    mini.Text = ScriptHub.miniText()
    mini.TextColor3 = UI.textMuted
    mini.TextXAlignment = Enum.TextXAlignment.Right
    mini.TextSize = UI.T_SMALL
    mini.TextTruncate = Enum.TextTruncate.AtEnd
    mini.Visible = false
    mini.ZIndex = 6
    mini.Parent = panel
    UI.applyFont(mini, Enum.FontWeight.Medium)
    ScriptHub.mini = mini

    local minBtn, minIcon = UI.chromeButton(panel, "st_minimize.png", -52,
        function() ScriptHub.setMin(not ScriptHub.min) end)
    ScriptHub.minIcon = minIcon
    local closeBtn = UI.chromeButton(panel, "st_x.png", -20, function() ScriptHub.hide() end)
    ScriptHub.chrome = { minBtn, closeBtn }

    -- Header is the drag handle. The body is a scrolling list, so dragging
    -- from there would fight the scroll.
    local grip = Instance.new("TextButton")
    grip.Position = UDim2.new(0, 0, 0, 0)
    grip.Size = UDim2.new(1, -90, 0, 70)
    grip.BackgroundTransparency = 1
    grip.AutoButtonColor = false
    grip.Text = ""
    grip.ZIndex = 7
    grip.Parent = panel
    ScriptHub.grip = grip
    grip.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
           or i.UserInputType == Enum.UserInputType.Touch then
            ScriptHub.dragBegan(i)
        end
    end)

    local body = Instance.new("Frame")
    body.Name = "Body"
    body.Position = UDim2.new(0, 0, 0, 70)
    body.Size = UDim2.new(1, 0, 1, -70)
    body.BackgroundTransparency = 1
    body.ZIndex = 6
    body.Parent = panel
    ScriptHub.body = body

    -- Measure the chip row BEFORE sizing the search box. Reserving a guessed
    -- width is what pushed "Trending" out over the search field: three chips
    -- want 260px, not the 220 that was set aside for them.
    local chipW = 0
    for _, t in ipairs(ScriptHub.TABS) do
        chipW = chipW + (22 + #t.label * 7) + 6
    end

    local search = Instance.new("TextBox")
    search.Position = UDim2.new(0, PAD, 0, 0)
    search.Size = UDim2.new(1, -PAD * 2 - chipW - 12, 0, 30)
    search.BackgroundColor3 = Color3.fromRGB(42, 44, 52)
    search.BackgroundTransparency = 0.25
    search.BorderSizePixel = 0
    search.Text = ""
    -- Four chips leave 171px here, so the long placeholder no longer fits.
    search.PlaceholderText = "Search\226\128\166"
    search.PlaceholderColor3 = UI.textMuted
    search.TextColor3 = UI.textPrimary
    search.TextXAlignment = Enum.TextXAlignment.Left
    search.TextSize = UI.T_SMALL
    search.ClearTextOnFocus = false
    search.ZIndex = 7
    search.Parent = body
    Instance.new("UICorner", search).CornerRadius = UDim.new(0, 8)
    local sp = Instance.new("UIPadding", search)
    sp.PaddingLeft = UDim.new(0, 10)
    UI.applyFont(search, Enum.FontWeight.Medium)
    ScriptHub.search = search
    search:GetPropertyChangedSignal("Text"):Connect(ScriptHub.onType)
    -- Enter skips the debounce rather than being the only way to search.
    search.FocusLost:Connect(function(enter)
        if enter then
            ScriptHub.typeToken = (ScriptHub.typeToken or 0) + 1  -- cancel the pending one
            ScriptHub.load()
        end
    end)

    local chips = {}
    local function paintChips()
        for k, chip in pairs(chips) do
            local on = (k == ScriptHub.tab)
            TweenService:Create(chip, TweenInfo.new(0.15), {
                BackgroundColor3 = on and UI.accent or Color3.fromRGB(42, 44, 52),
                BackgroundTransparency = on and 0 or 0.35,
            }):Play()
            local lb = chip:FindFirstChildWhichIsA("TextLabel")
            if lb then
                TweenService:Create(lb, TweenInfo.new(0.15), {
                    TextColor3 = on and Color3.fromRGB(255, 255, 255)
                                     or Color3.fromRGB(180, 182, 192) }):Play()
            end
        end
    end

    local cx = 0
    for _, t in ipairs(ScriptHub.TABS) do
        local w = 22 + #t.label * 7
        local chip = Instance.new("TextButton")
        chip.AnchorPoint = Vector2.new(1, 0)
        chip.Position = UDim2.new(1, -PAD - cx, 0, 3)
        chip.Size = UDim2.fromOffset(w, 24)
        chip.AutoButtonColor = false
        chip.Text = ""
        chip.BackgroundColor3 = Color3.fromRGB(42, 44, 52)
        chip.BorderSizePixel = 0
        chip.ZIndex = 7
        chip.Parent = body
        Instance.new("UICorner", chip).CornerRadius = UDim.new(1, 0)

        local lb = Instance.new("TextLabel")
        lb.Size = UDim2.fromScale(1, 1)
        lb.BackgroundTransparency = 1
        lb.Text = t.label
        lb.TextColor3 = Color3.fromRGB(180, 182, 192)
        lb.TextSize = UI.T_SMALL
        lb.ZIndex = 8
        lb.Parent = chip
        UI.applyFont(lb, Enum.FontWeight.SemiBold)

        chip.MouseButton1Click:Connect(function()
            if ScriptHub.tab == t.key then return end
            ScriptHub.tab = t.key
            search.Text = ""
            -- Clearing the box fires the Text signal, which queues a
            -- debounced load. Bump the token so only this one runs.
            ScriptHub.typeToken = (ScriptHub.typeToken or 0) + 1
            paintChips()
            ScriptHub.load()
        end)
        chips[t.key] = chip
        cx = cx + w + 6
    end

    local list = Instance.new("ScrollingFrame")
    list.Position = UDim2.new(0, PAD - 6, 0, 42)
    list.Size = UDim2.new(1, -(PAD - 6) * 2, 1, -80)
    list.BackgroundTransparency = 1
    list.BorderSizePixel = 0
    list.ScrollBarThickness = 3
    list.ScrollBarImageColor3 = UI.accent
    list.ScrollBarImageTransparency = 0.4
    list.CanvasSize = UDim2.new(0, 0, 0, 0)
    list.ZIndex = 7
    list.Parent = body
    ScriptHub.list = list

    -- Whose scripts these are. Their MARK plus the name set in our own
    -- type, rather than their full lockup: that lockup is an icon and a
    -- wordmark side by side, and at any size that fits a footer row the
    -- wordmark comes out about five pixels tall and unreadable. The glyph
    -- is what carries the recognition; the name is what carries the words.
    local credit = Instance.new("Frame")
    credit.AnchorPoint = Vector2.new(1, 1)
    credit.Position = UDim2.new(1, -PAD, 1, -8)
    credit.Size = UDim2.fromOffset(160, 16)
    credit.BackgroundTransparency = 1
    credit.ZIndex = 7
    credit.Parent = body

    -- BOTH anchored to the right edge, so they sit adjacent whatever the
    -- text measures. Pinning the glyph to the frame's left instead put all
    -- the frame's slack between the two and the mark drifted away from the
    -- words. Text first, mark last: that is the order every "powered by"
    -- lockup uses.
    local by = Instance.new("TextLabel")
    by.AnchorPoint = Vector2.new(1, 0.5)
    by.Position = UDim2.new(1, -18, 0.5, 0)
    by.Size = UDim2.new(1, -18, 1, 0)
    by.BackgroundTransparency = 1
    by.RichText = true
    by.Text = 'powered by <font color="#c8cad4">ScriptBlox</font>'
    by.TextColor3 = UI.textMuted
    by.TextXAlignment = Enum.TextXAlignment.Right
    by.TextSize = UI.T_SMALL
    by.ZIndex = 7
    by.Parent = credit
    UI.applyFont(by, Enum.FontWeight.Medium)

    -- Square artwork, so a square frame -- Fit has nothing to letterbox.
    local mark = Instance.new("ImageLabel")
    mark.AnchorPoint = Vector2.new(1, 0.5)
    mark.Position = UDim2.new(1, 0, 0.5, 0)
    mark.Size = UDim2.fromOffset(14, 14)
    mark.BackgroundTransparency = 1
    mark.ScaleType = Enum.ScaleType.Fit
    mark.Image = UI.icon("sb_mark.png")
    mark.ImageColor3 = UI.accent
    mark.ImageTransparency = 0.15
    mark.ZIndex = 7
    mark.Parent = credit

    local status = Instance.new("TextLabel")
    status.AnchorPoint = Vector2.new(0.5, 0)
    status.Position = UDim2.new(0.5, 0, 0, 90)
    status.Size = UDim2.new(1, -PAD * 2, 0, 20)
    status.BackgroundTransparency = 1
    status.Text = ""
    status.TextColor3 = UI.textMuted
    status.TextSize = UI.T_ROW
    status.ZIndex = 8
    status.Parent = body
    UI.applyFont(status, Enum.FontWeight.Medium)
    ScriptHub.status = status

    paintChips()

    TweenService:Create(panel,
        TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Size = UDim2.fromOffset(ScriptHub.W, H),
            BackgroundTransparency = UI.panelT(),
        }):Play()
    UI.fadeContent(panel, true)
    task.delay(0.06, function()
        if ScriptHub.panel == panel then UI.fadeContent(panel, false, true) end
    end)

    ScriptHub.load()
end

-- ════════════════════════════════════════════════════════════════════════
--  RESUME PROMPT
--  You ran scripts from the hub last session; executed scripts do not
--  survive a rejoin. Offer them back rather than making you go and find
--  them again -- and offer to stop asking, because a prompt on every single
--  join is worse than no prompt at all.
-- ════════════════════════════════════════════════════════════════════════
Resume = { MAX = 4, ROW_H = 52, FOOT_H = 38 }

-- What a rejoin actually costs you, one entry per kind. Grouped rather than
-- listed flat: "four scripts and a position" is two decisions, not five.
function Resume.options()
    local out = {}

    local ran = (ScriptHub and ScriptHub.ran) or {}
    if #ran > 0 then
        out[#out + 1] = {
            key = "scripts", icon = "st_zap.png",
            label = "Run this game's last scripts",
            desc = (#ran == 1) and ran[1].title
                   or (#ran .. " scripts  \194\183  " .. ran[1].title .. " and others"),
            run = function() Resume.run(ran) end,
        }
    end

    -- Both are place-tagged; loadConfig already refuses to restore either
    -- from another game, because coordinates from elsewhere are three
    -- numbers that drop you inside a wall.
    local function goTo(p, said)
        return function()
            local ch = LocalPlayer.Character
            local root = ch and ch:FindFirstChild("HumanoidRootPart")
            if not root then
                Notifications:Error("Universal Hub Lite",
                    "No character to move yet", 3.5)
                return
            end
            root.CFrame = CFrame.new(p.x, p.y, p.z)
            Notifications:Success("Universal Hub Lite", said, 3)
        end
    end
    local function here(p) return p and tonumber(p.place) == game.PlaceId end

    -- Where you actually were, captured as you played -- no bookmark needed.
    local off = UI.leftOff
    if here(off) then
        out[#out + 1] = {
            key = "leftoff", icon = "st_footprints.png",
            label = "Go back to where you left off",
            desc = ("%d, %d, %d"):format(off.x, off.y, off.z),
            run = goTo(off, "Back where you left off"),
        }
    end

    -- The manual bookmark, but only when it is somewhere else -- offering
    -- two rows that go to the same spot is just noise.
    local p = UI.savedPos
    if here(p) then
        local far = true
        if here(off) then
            local dx, dy, dz = p.x - off.x, p.y - off.y, p.z - off.z
            far = (dx * dx + dy * dy + dz * dz) > (30 * 30)
        end
        if far then
            out[#out + 1] = {
                key = "position", icon = "st_map-pin.png",
                label = "Go to your saved position",
                desc = ("%d, %d, %d  \194\183  from !savepos"):format(p.x, p.y, p.z),
                run = goTo(p, "Back at your saved position"),
            }
        end
    end

    return out
end

function Resume.should()
    if UI.askResume == false then return false end
    return #Resume.options() > 0
end

function Resume.run(list)
    local ok, failed = 0, {}
    for _, e in ipairs(list) do
        -- Compile first: the stored source may be a loadstring one-liner or
        -- raw source, and one that no longer compiles must not take the rest
        -- of the batch down with it.
        local okC, fn = pcall(loadstring, e.source)
        if okC and fn and pcall(fn) then
            ok = ok + 1
            ScriptHub.markRunning(e)
        else
            failed[#failed + 1] = e.title
        end
    end

    if ok > 0 and #failed == 0 then
        Notifications:Success("Universal Hub Lite",
            ok == 1 and ("Ran " .. list[1].title) or ("Ran " .. ok .. " scripts"), 4)
    elseif ok > 0 then
        Notifications:Info("Universal Hub Lite",
            "Ran " .. ok .. ", " .. #failed .. " failed  \194\183  " .. failed[1], 5)
    else
        Notifications:Error("Universal Hub Lite",
            "Could not run " .. (failed[1] or "those scripts"), 5)
    end
end

-- Small square check, not the pill switch the settings use: this is a
-- one-off consent, not a setting you come back and flip.
function Resume.checkbox(parent, y, label, onChange)
    local state = false

    local box = Instance.new("TextButton")
    box.AnchorPoint = Vector2.new(0, 0.5)
    box.Position = UDim2.new(0, 0, 0, y)
    box.Size = UDim2.fromOffset(18, 18)
    box.AutoButtonColor = false
    box.Text = ""
    box.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    box.BackgroundTransparency = 0.9
    box.BorderSizePixel = 0
    box.ZIndex = 7
    box.Parent = parent
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 5)
    local stroke = Instance.new("UIStroke", box)
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Transparency = 0.72
    stroke.Thickness = 1

    local tx = Instance.new("TextButton")
    tx.AnchorPoint = Vector2.new(0, 0.5)
    tx.Position = UDim2.new(0, 26, 0, y)
    tx.Size = UDim2.new(1, -26, 0, 18)
    tx.BackgroundTransparency = 1
    tx.AutoButtonColor = false
    tx.Text = label
    tx.TextColor3 = UI.textMuted
    tx.TextXAlignment = Enum.TextXAlignment.Left
    tx.TextSize = UI.T_SMALL
    tx.ZIndex = 7
    tx.Parent = parent
    UI.applyFont(tx, Enum.FontWeight.Medium)

    -- Filled, not ticked: at 18px a check glyph is a smudge, and a solid
    -- block of the accent reads as "on" from further away than any mark.
    local function toggle()
        state = not state
        TweenService:Create(box, TweenInfo.new(0.14), {
            BackgroundColor3 = state and UI.accent or Color3.fromRGB(255, 255, 255),
            BackgroundTransparency = state and 0 or 0.9,
        }):Play()
        TweenService:Create(stroke, TweenInfo.new(0.14),
            { Transparency = state and 1 or 0.72 }):Play()
        TweenService:Create(tx, TweenInfo.new(0.14),
            { TextColor3 = state and Color3.fromRGB(232, 233, 238) or UI.textMuted }):Play()
        onChange(state)
    end
    -- The label is as clickable as the box: an 18px target is a miss waiting
    -- to happen.
    box.MouseButton1Click:Connect(toggle)
    tx.MouseButton1Click:Connect(toggle)
end

function Resume.show()
    local opts = Resume.options()
    if #opts == 0 then return end
    local single = (#opts == 1)
    local dontAsk = false

    local bodyH = #opts * Resume.ROW_H + Resume.FOOT_H

    Modal.show{
        owner = "resume",
        dismissOnBackdrop = false,
        width = 470,
        title = "Pick up where you left off?",
        subtitle = "From the last time you played THIS game. A rejoin clears all of it.",
        bodyHeight = bodyH,
        actions = {
            -- With one option there is no "all" to speak of, so the primary
            -- button just says what it does.
            { label = single and opts[1].label or "Do all",
              icon = single and opts[1].icon or "st_zap.png", style = "light",
              run = function()
                  for _, o in ipairs(opts) do pcall(o.run) end
              end },
            { label = "Not now", icon = "st_x.png", style = "ghost" },
        },
        build = function(panel, headY, _, W)
            local PAD = 24

            for i, o in ipairs(opts) do
                local y = headY + (i - 1) * Resume.ROW_H
                local row = Instance.new("Frame")
                row.Position = UDim2.new(0, PAD, 0, y)
                row.Size = UDim2.new(1, -PAD * 2, 0, Resume.ROW_H - 6)
                row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                row.BackgroundTransparency = 0.955
                row.BorderSizePixel = 0
                row.ZIndex = 6
                row.Parent = panel
                Instance.new("UICorner", row).CornerRadius = UDim.new(0, 9)

                local ic = Instance.new("ImageLabel")
                ic.AnchorPoint = Vector2.new(0, 0.5)
                ic.Position = UDim2.new(0, 14, 0.5, 0)
                ic.Size = UDim2.fromOffset(17, 17)
                ic.BackgroundTransparency = 1
                ic.Image = UI.icon(o.icon)
                ic.ImageColor3 = UI.accent
                ic.ZIndex = 7
                ic.Parent = row

                local nm = Instance.new("TextLabel")
                nm.Position = UDim2.new(0, 44, 0, 7)
                nm.Size = UDim2.new(1, -140, 0, 17)
                nm.BackgroundTransparency = 1
                nm.Text = o.label
                nm.TextColor3 = Color3.fromRGB(238, 239, 244)
                nm.TextXAlignment = Enum.TextXAlignment.Left
                nm.TextSize = UI.T_ROW
                nm.TextTruncate = Enum.TextTruncate.AtEnd
                nm.ZIndex = 7
                nm.Parent = row
                UI.applyFont(nm, Enum.FontWeight.SemiBold)

                local sb = Instance.new("TextLabel")
                sb.Position = UDim2.new(0, 44, 0, 25)
                sb.Size = UDim2.new(1, -140, 0, 15)
                sb.BackgroundTransparency = 1
                sb.Text = o.desc
                sb.TextColor3 = UI.textMuted
                sb.TextXAlignment = Enum.TextXAlignment.Left
                sb.TextSize = UI.T_SMALL
                sb.TextTruncate = Enum.TextTruncate.AtEnd
                sb.ZIndex = 7
                sb.Parent = row
                UI.applyFont(sb, Enum.FontWeight.Regular)

                -- Per-option, so "all" is the shortcut rather than the only
                -- way to take one of them.
                local one = UI.gradButton(row, "Do it", "st_zap.png", "ghost")
                UI.smallButton(one)
                one.AnchorPoint = Vector2.new(1, 0.5)
                one.Position = UDim2.new(1, -12, 0.5, 0)
                one.ZIndex = 8
                one.MouseButton1Click:Connect(function()
                    pcall(o.run)
                    UI.dimButton(one, true)
                end)
            end

            local foot = Instance.new("Frame")
            foot.Position = UDim2.new(0, PAD, 0, headY + #opts * Resume.ROW_H + 8)
            foot.Size = UDim2.new(1, -PAD * 2, 0, 20)
            foot.BackgroundTransparency = 1
            foot.ZIndex = 6
            foot.Parent = panel

            Resume.checkbox(foot, 10, "Don't ask me again in future games",
                function(on) dontAsk = on end)
        end,
    }

    -- Read on the way out rather than the moment it is ticked, so ticking it
    -- and then changing your mind before closing costs nothing.
    Modal.onHidden = function()
        if dontAsk then
            UI.askResume = false
            UI.saveConfig()
            Notifications:Info("Universal Hub Lite",
                "Will not ask again  \194\183  !resume turns it back on", 4)
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════
--  PROFILE CARD
--  Modelled on the musicbot profile card, but every value is read straight
--  off the client -- Roblox blocks HttpGet to its own domains, so anything
--  needing the web API (followers, RAP) simply is not available here.
-- ════════════════════════════════════════════════════════════════════════
-- Vertical layout, all measured from the panel top so the pieces cannot
-- overlap the way they did when the button row was pinned to H-44:
--   10  eyebrow
--   30  avatar (138 tall) | name 30, tags 51, stat rows from 72
--  182  friends strip (24)
--  216  action buttons (32)
--  262  panel height
Profile = {
    open = false,
    H = 290,
    Y_AVATAR = 30, AVATAR_H = 138,
    Y_ROWS   = 72, ROW_STEP = 20,
    Y_STRIP  = 182, STRIP_H = 52,
    Y_BTNS   = 244,
}

function Profile.fmtAge(days)
    if days >= 365 then
        local y = days / 365
        return string.format("%.1f yr", y):gsub("%.0 ", " ")
    elseif days >= 30 then
        return string.format("%d mo", math.floor(days / 30))
    end
    return days .. " d"
end

-- Their friends who are also in this server. IsFriendsWith is a client call
-- and yields, so the whole scan runs off the render thread.
function Profile.friendsHere(target)
    local out = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= target then
            local ok, isF = pcall(function() return target:IsFriendsWith(p.UserId) end)
            if ok and isF then out[#out + 1] = p end
        end
    end
    return out
end

-- copyValue is what lands on the clipboard when the row's button is used;
-- omit it and the row simply has no button (nothing useful to copy).
function Profile.row(parent, y, iconFile, value, unit, copyValue)
    local row = Instance.new("Frame")
    row.Position = UDim2.new(0, 0, 0, y)
    row.Size = UDim2.new(1, 0, 0, 20)
    row.BackgroundTransparency = 1
    row.ZIndex = 43
    row.Parent = parent

    local ic = Instance.new("ImageLabel")
    ic.AnchorPoint = Vector2.new(0, 0.5)
    ic.Position = UDim2.new(0, 0, 0.5, 0)
    ic.Size = UDim2.fromOffset(14, 14)
    ic.BackgroundTransparency = 1
    ic.Image = UI.icon(iconFile)
    ic.ImageColor3 = Color3.fromRGB(255, 255, 255)
    ic.ImageTransparency = 0.3
    ic.ZIndex = 44
    ic.Parent = row

    local tx = Instance.new("TextLabel")
    tx.AnchorPoint = Vector2.new(0, 0.5)
    tx.Position = UDim2.new(0, 22, 0.5, 0)
    tx.Size = UDim2.new(1, -22, 1, 0)
    tx.BackgroundTransparency = 1
    tx.RichText = true
    tx.Text = tostring(value) ..
        (unit and ('  <font size="11" color="#8e919c">' .. unit .. '</font>') or "")
    tx.TextColor3 = Color3.fromRGB(232, 233, 238)
    tx.TextXAlignment = Enum.TextXAlignment.Left
    tx.TextSize = UI.T_ROW
    tx.TextTruncate = Enum.TextTruncate.AtEnd
    tx.ZIndex = 44
    tx.Parent = row
    UI.applyFont(tx, Enum.FontWeight.SemiBold)

    if copyValue then
        tx.Size = UDim2.new(1, -44, 1, 0)      -- yield room for the button

        local cp = Instance.new("ImageButton")
        cp.AnchorPoint = Vector2.new(1, 0.5)
        cp.Position = UDim2.new(1, 0, 0.5, 0)
        cp.Size = UDim2.fromOffset(16, 16)
        cp.BackgroundTransparency = 1
        cp.AutoButtonColor = false
        cp.Image = UI.icon("st_copy.png")
        cp.ImageColor3 = Color3.fromRGB(255, 255, 255)
        cp.ImageTransparency = 0.68        -- quiet until you go for it
        cp.ZIndex = 45
        cp.Parent = row

        cp.MouseEnter:Connect(function()
            TweenService:Create(cp,
                TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                { ImageTransparency = 0, Size = UDim2.fromOffset(18, 18) }):Play()
        end)
        cp.MouseLeave:Connect(function()
            TweenService:Create(cp, TweenInfo.new(0.14),
                { ImageTransparency = 0.68, Size = UDim2.fromOffset(16, 16) }):Play()
        end)
        cp.MouseButton1Click:Connect(function()
            pcall(function() setclipboard(tostring(copyValue)) end)
            -- confirm on the row itself; a toast would close the card
            local was = tx.Text
            tx.Text = '<font color="#7ee08a">copied</font>'
            cp.Image = UI.icon("st_circle-check.png")
            cp.ImageColor3 = UI.ok
            task.delay(1.1, function()
                pcall(function()
                    tx.Text = was
                    cp.Image = UI.icon("st_copy.png")
                    cp.ImageColor3 = Color3.fromRGB(255, 255, 255)
                end)
            end)
        end)
    end
    return row
end

function Profile.build(target)
    -- rebuilt per target, so tear the previous one down first
    if Profile.clip then pcall(function() Profile.clip:Destroy() end) end
    Profile.clip, Profile.panel = nil, nil
    if not (target and Bar.gui) then return false end

    local isSelf   = (target == LocalPlayer)
    local age      = target.AccountAge or 0
    local joined   = os.date("%d %b %Y", os.time() - age * 86400)
    local premium  = (target.MembershipType == Enum.MembershipType.Premium)
    local friend   = false
    if not isSelf then
        pcall(function() friend = LocalPlayer:IsFriendsWith(target.UserId) end)
    end

    local char, myChar = target.Character, LocalPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local dist = (root and myRoot) and math.floor((root.Position - myRoot.Position).Magnitude) or nil
    local rig  = hum and (hum.RigType == Enum.HumanoidRigType.R15 and "R15" or "R6") or "-"

    local clip, p = UI.makeDrawer("ProfilePanel", UI.EXP_W, Profile.H, Bar.gui)
    Profile.clip, Profile.panel = clip, p
    Profile.target = target
    UI.eyebrow(p, "PROFILE")

    local x = Instance.new("ImageButton")
    x.Name = "Close"
    x.AnchorPoint = Vector2.new(1, 0.5)
    x.Position = UDim2.new(1, -12, 0, 16)
    x.Size = UDim2.fromOffset(16, 16)
    x.BackgroundTransparency = 1
    x.AutoButtonColor = false
    x.Image = UI.icon("st_x.png")
    x.ImageColor3 = Color3.fromRGB(255, 255, 255)
    x.ImageTransparency = 0.6
    x.ZIndex = 46
    x.Parent = p
    x.MouseEnter:Connect(function()
        TweenService:Create(x,
            TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { ImageTransparency = 0, Size = UDim2.fromOffset(18, 18) }):Play()
    end)
    x.MouseLeave:Connect(function()
        TweenService:Create(x, TweenInfo.new(0.14),
            { ImageTransparency = 0.6, Size = UDim2.fromOffset(16, 16) }):Play()
    end)
    x.MouseButton1Click:Connect(function() Profile.hide() end)

    -- full-body avatar on an inset backdrop
    local back = Instance.new("Frame")
    back.Position = UDim2.new(0, 16, 0, Profile.Y_AVATAR)
    back.Size = UDim2.fromOffset(104, Profile.AVATAR_H)
    back.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
    back.BackgroundTransparency = 0.35
    back.BorderSizePixel = 0
    back.ZIndex = 42
    back.Parent = p
    Instance.new("UICorner", back).CornerRadius = UDim.new(0, 10)

    local body = Instance.new("ImageLabel")
    body.Size = UDim2.fromScale(1, 1)
    body.BackgroundTransparency = 1
    body.Image = "rbxthumb://type=Avatar&id=" .. tostring(target.UserId) .. "&w=420&h=420"
    body.ScaleType = Enum.ScaleType.Fit
    body.ZIndex = 43
    body.Parent = back
    Instance.new("UICorner", body).CornerRadius = UDim.new(0, 10)

    local colX = 134
    local colW = UI.EXP_W - colX - 16

    local nameL = Instance.new("TextLabel")
    nameL.Position = UDim2.new(0, colX, 0, 30)
    nameL.Size = UDim2.new(0, colW, 0, 22)
    nameL.BackgroundTransparency = 1
    nameL.Text = target.DisplayName
    nameL.TextColor3 = UI.textPrimary
    nameL.TextXAlignment = Enum.TextXAlignment.Left
    nameL.TextSize = 17
    nameL.TextTruncate = Enum.TextTruncate.AtEnd
    nameL.ZIndex = 42
    nameL.Parent = p
    UI.applyFont(nameL, Enum.FontWeight.Bold)

    local tags = "@" .. target.Name
    if isSelf  then tags = tags .. '  <font color="#8e919c" size="11">YOU</font>' end
    if premium then tags = tags .. '  <font color="#f9a825" size="11">PREMIUM</font>' end
    if friend  then tags = tags .. '  <font color="#7ee08a" size="11">FRIEND</font>' end

    local subL = Instance.new("TextLabel")
    subL.Position = UDim2.new(0, colX, 0, 51)
    subL.Size = UDim2.new(0, colW, 0, 16)
    subL.BackgroundTransparency = 1
    subL.RichText = true
    subL.Text = tags
    subL.TextColor3 = UI.textMuted
    subL.TextXAlignment = Enum.TextXAlignment.Left
    subL.TextSize = UI.T_SMALL
    subL.TextTruncate = Enum.TextTruncate.AtEnd
    subL.ZIndex = 42
    subL.Parent = p
    UI.applyFont(subL, Enum.FontWeight.Regular)

    local cpName = Instance.new("ImageButton")
    cpName.AnchorPoint = Vector2.new(1, 0.5)
    cpName.Position = UDim2.new(0, colX + colW, 0, 40)
    cpName.Size = UDim2.fromOffset(17, 17)
    cpName.BackgroundTransparency = 1
    cpName.AutoButtonColor = false
    cpName.Image = UI.icon("st_copy.png")
    cpName.ImageTransparency = 0.68
    cpName.ZIndex = 45
    cpName.Parent = p
    cpName.MouseEnter:Connect(function()
        TweenService:Create(cpName, TweenInfo.new(0.12), { ImageTransparency = 0 }):Play()
    end)
    cpName.MouseLeave:Connect(function()
        TweenService:Create(cpName, TweenInfo.new(0.14), { ImageTransparency = 0.68 }):Play()
    end)
    cpName.MouseButton1Click:Connect(function()
        pcall(function() setclipboard(target.Name) end)
        cpName.Image = UI.icon("st_circle-check.png")
        cpName.ImageColor3 = UI.ok
        task.delay(1.1, function()
            pcall(function()
                cpName.Image = UI.icon("st_copy.png")
                cpName.ImageColor3 = Color3.fromRGB(255, 255, 255)
            end)
        end)
    end)

    local col = Instance.new("Frame")
    col.Position = UDim2.new(0, colX, 0, Profile.Y_ROWS)
    col.Size = UDim2.new(0, colW, 0, 5 * Profile.ROW_STEP)
    col.BackgroundTransparency = 1
    col.ZIndex = 42
    col.Parent = p

    local y = 0
    local function add(icon, val, unit, copyVal)
        if val == nil then return end
        Profile.row(col, y, icon, val, unit, copyVal)
        y = y + Profile.ROW_STEP
    end
    add("st_calendar.png", joined, "joined", joined)
    add("st_heart.png", Profile.fmtAge(age), "old", age .. " days")
    add("st_users.png", tostring(target.UserId), "id", target.UserId)
    if dist then add("st_map-pin.png", dist, "studs away") end
    add("st_person-standing.png", rig,
        hum and (math.floor(hum.WalkSpeed) .. " ws") or nil)

    -- friends also in this server
    local strip = Instance.new("Frame")
    strip.Position = UDim2.new(0, 16, 0, Profile.Y_STRIP)
    strip.Size = UDim2.new(1, -32, 0, Profile.STRIP_H)
    strip.BackgroundTransparency = 1
    strip.ZIndex = 42
    strip.Parent = p
    Profile.strip = strip

    local cap = Instance.new("TextLabel")
    cap.Position = UDim2.new(0, 0, 0, 0)
    cap.Size = UDim2.new(1, 0, 0, 12)
    cap.BackgroundTransparency = 1
    cap.Text = "FRIENDS HERE"
    cap.TextColor3 = UI.textMuted
    cap.TextXAlignment = Enum.TextXAlignment.Left
    cap.TextSize = 9
    cap.ZIndex = 43
    cap.Parent = strip
    UI.applyFont(cap, Enum.FontWeight.Bold)
    Profile.cap = cap

    -- IsFriendsWith yields, so resolve the strip off-thread and fill it in
    task.spawn(function()
        local fr = Profile.friendsHere(target)
        if not (Profile.strip and Profile.strip.Parent) then return end
        if #fr == 0 then
            cap.Text = "NO FRIENDS IN THIS SERVER"
            return
        end
        cap.Text = "FRIENDS HERE  \194\183  " .. #fr

        -- Two per row with their display name beside the headshot; a bare
        -- row of faces told you someone was here but not who.
        local COLS, CELL_W, CELL_H = 2, 168, 22
        local shown = math.min(#fr, 4)
        for i = 1, shown do
            local f = fr[i]
            local cx = ((i - 1) % COLS) * (CELL_W + 8)
            local cy = 16 + math.floor((i - 1) / COLS) * (CELL_H + 4)

            local cell = Instance.new("Frame")
            cell.Position = UDim2.new(0, cx, 0, cy)
            cell.Size = UDim2.fromOffset(CELL_W, CELL_H)
            cell.BackgroundTransparency = 1
            cell.ZIndex = 43
            cell.Parent = strip

            local hs = Instance.new("ImageLabel")
            hs.AnchorPoint = Vector2.new(0, 0.5)
            hs.Position = UDim2.new(0, 0, 0.5, 0)
            hs.Size = UDim2.fromOffset(20, 20)
            hs.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
            hs.BackgroundTransparency = 0.35
            hs.Image = UI.headshotFor(f.Name)
            hs.ZIndex = 44
            hs.Parent = cell
            Instance.new("UICorner", hs).CornerRadius = UDim.new(1, 0)

            local nm = Instance.new("TextLabel")
            nm.AnchorPoint = Vector2.new(0, 0.5)
            nm.Position = UDim2.new(0, 26, 0.5, 0)
            nm.Size = UDim2.new(1, -26, 1, 0)
            nm.BackgroundTransparency = 1
            nm.Text = f.DisplayName
            nm.TextColor3 = Color3.fromRGB(214, 216, 224)
            nm.TextXAlignment = Enum.TextXAlignment.Left
            nm.TextSize = UI.T_SMALL
            nm.TextTruncate = Enum.TextTruncate.AtEnd
            nm.ZIndex = 44
            nm.Parent = cell
            UI.applyFont(nm, Enum.FontWeight.Medium)
        end
        if #fr > shown then
            local more = Instance.new("TextLabel")
            more.AnchorPoint = Vector2.new(1, 0)
            more.Position = UDim2.new(1, 0, 0, 0)
            more.Size = UDim2.fromOffset(60, 12)
            more.BackgroundTransparency = 1
            more.Text = "+" .. (#fr - shown) .. " more"
            more.TextColor3 = UI.textMuted
            more.TextXAlignment = Enum.TextXAlignment.Right
            more.TextSize = 9
            more.ZIndex = 43
            more.Parent = strip
            UI.applyFont(more, Enum.FontWeight.Regular)
        end
    end)

    -- inline actions
    local bx = 16
    local function act(label, icon, style, fn)
        local b = UI.gradButton(p, label, icon, style)
        b.Position = UDim2.new(0, bx, 0, Profile.Y_BTNS)
        b.ZIndex = 45
        bx = bx + b.Size.X.Offset + 8
        b.MouseButton1Click:Connect(function()
            Profile.hide()
            task.delay(0.2, function() pcall(fn) end)
        end)
        return b
    end

    if not isSelf then
        act("Goto", "st_map-pin.png", "light", function()
            processCommand(prefix .. "goto " .. target.Name)
        end)
        act("View", "st_eye.png", "ghost", function()
            processCommand(prefix .. "view " .. target.Name)
        end)
    end
    act("Copy", "st_copy.png", "ghost", function()
        pcall(function() setclipboard(target.Name) end)
        Notifications:Success("Universal Hub Lite", "Copied @" .. target.Name, 3)
    end)
    return true
end

function Profile.show(target)
    -- Build in a pcall: a partially built card would otherwise be left
    -- parented and half-drawn, and the caller would never learn it failed.
    local ok, built = pcall(Profile.build, target)
    if not ok then
        warn("[UHub] profile: " .. tostring(built))
        if Profile.clip then pcall(function() Profile.clip:Destroy() end) end
        Profile.clip, Profile.panel, Profile.open = nil, nil, false
        return false
    end
    if not built then return false end
    Profile.open = true
    UI.openDrawerAtY(Profile.clip, Profile.panel, Cards.slotY(Profile.clip))
    Cards.reflow(true)
    return true
end

function Profile.hide()
    if not Profile.open then return end
    Profile.open = false
    UI.closeDrawer(Profile.clip, Profile.panel)
    Cards.reflow(true)
end

-- ════════════════════════════════════════════════════════════════════════
--  MODAL
--  A centred panel in the same language as the cards -- same glass, accent,
--  Manrope and gradient buttons -- but a real window rather than something
--  hanging off the corner pill. Built from a spec table so anything that
--  needs a proper dialogue can reuse it instead of hand-rolling one.
--
--    Modal.show{
--      title = "...", subtitle = "...",
--      rows  = { { icon = "st_terminal.png", title = "...", text = "..." } },
--      actions = { { label = "Got it", style = "light", run = fn } },
--    }
-- ════════════════════════════════════════════════════════════════════════
Modal = { open = false, owner = nil, W = 460 }

function Modal.hide(instant)
    if not Modal.open then return end
    Modal.open, Modal.owner = false, nil
    -- Fires once, on the way out, whatever dismissed it -- button, backdrop
    -- or another modal replacing it.
    local after = Modal.onHidden
    Modal.onHidden = nil
    if after then task.delay(0.05, function() pcall(after) end) end
    -- The picker is its own ScreenGui above the modal; dismissing the modal
    -- underneath would otherwise leave it floating with nothing behind it.
    if Picker and Picker.close then pcall(Picker.close) end
    local gui, panel, dim = Modal.gui, Modal.panel, Modal.dim
    Modal.gui, Modal.panel, Modal.dim = nil, nil, nil
    if not gui then return end
    if instant then pcall(function() gui:Destroy() end) return end

    local ti = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
    pcall(function()
        TweenService:Create(panel, ti, {
            Size = UDim2.fromOffset(panel.Size.X.Offset - 24, panel.Size.Y.Offset - 16),
            BackgroundTransparency = 1,
        }):Play()
        UI.fadeContent(panel, true, true)
        TweenService:Create(dim, TweenInfo.new(0.22), { BackgroundTransparency = 1 }):Play()
    end)
    task.delay(0.3, function() pcall(function() gui:Destroy() end) end)
end

function Modal.show(spec)
    Modal.hide(true)
    spec = spec or {}
    local rows = spec.rows or {}
    -- Compact the action list: a caller can hand us a table with a hole, and
    -- # on such a table is undefined while ipairs stops early -- reserving
    -- button height that then renders empty.
    local actions = {}
    for _, a in ipairs(spec.actions or {}) do actions[#actions + 1] = a end

    local gui = Instance.new("ScreenGui")
    gui.Name = "UHubLiteModal"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 10001
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function()
        gui.Parent = (typeof(gethui) == "function" and gethui())
                  or game:GetService("CoreGui")
    end)
    Modal.gui = gui

    -- Dim catches clicks outside so the panel reads as modal rather than
    -- as another floating card.
    local dim = Instance.new("TextButton")
    dim.Name = "Dim"
    dim.Size = UDim2.fromScale(1, 1)
    dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    dim.BackgroundTransparency = 1
    dim.BorderSizePixel = 0
    dim.AutoButtonColor = false
    dim.Text = ""
    dim.ZIndex = 1
    dim.Parent = gui
    Modal.dim = dim

    -- measure: header + rows + button strip
    local PAD, ROW_H, ROW_GAP = 24, 52, 8
    local headH = spec.subtitle and 74 or 56
    -- title = "" means the caller draws its own header in build()
    if spec.title == "" then headH = 20 end
    local bodyH = #rows * ROW_H + math.max(0, #rows - 1) * ROW_GAP
    local btnH  = (#actions > 0) and 54 or 0
    -- a caller may supply its own body instead of rows
    if spec.bodyHeight then bodyH = spec.bodyHeight end
    local H = headH + bodyH + btnH + PAD

    local W = spec.width or Modal.W
    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.new(0.5, 0, 0.5, 0)
    panel.Size = UDim2.fromOffset(W - 24, H - 16)   -- animates up to full
    panel.BackgroundColor3 = UI.cardFill
    panel.BackgroundTransparency = 1
    panel.BorderSizePixel = 0
    panel.ZIndex = 5
    panel.Parent = gui
    UI.glassify(panel, 16)
    UI.accentWash(panel)
    Modal.panel = panel

    local title = spec.title ~= "" and Instance.new("TextLabel") or nil
    if title then
    title.Position = UDim2.new(0, PAD, 0, 20)
    title.Size = UDim2.new(1, -PAD * 2, 0, 24)
    title.BackgroundTransparency = 1
    title.Text = spec.title or "Universal Hub Lite"
    title.TextColor3 = UI.textPrimary
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextSize = 20
    title.ZIndex = 6
    title.Parent = panel
    UI.applyFont(title, Enum.FontWeight.Bold)
    end

    if spec.subtitle then
        local sub = Instance.new("TextLabel")
        sub.Position = UDim2.new(0, PAD, 0, 46)
        sub.Size = UDim2.new(1, -PAD * 2, 0, 18)
        sub.BackgroundTransparency = 1
        sub.Text = spec.subtitle
        sub.TextColor3 = UI.textMuted
        sub.TextXAlignment = Enum.TextXAlignment.Left
        sub.TextSize = UI.T_ROW
        sub.TextWrapped = true
        sub.ZIndex = 6
        sub.Parent = panel
        UI.applyFont(sub, Enum.FontWeight.Regular)
    end

    for i, r in ipairs(rows) do
        local y = headH + (i - 1) * (ROW_H + ROW_GAP)
        local row = Instance.new("Frame")
        row.Position = UDim2.new(0, PAD, 0, y)
        row.Size = UDim2.new(1, -PAD * 2, 0, ROW_H)
        row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        row.BackgroundTransparency = 0.95
        row.BorderSizePixel = 0
        row.ZIndex = 6
        row.Parent = panel
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)

        local ic = Instance.new("ImageLabel")
        ic.AnchorPoint = Vector2.new(0, 0.5)
        ic.Position = UDim2.new(0, 14, 0.5, 0)
        ic.Size = UDim2.fromOffset(18, 18)
        ic.BackgroundTransparency = 1
        ic.Image = UI.icon(r.icon or "st_zap.png")
        ic.ImageColor3 = UI.accent
        ic.ZIndex = 7
        ic.Parent = row

        local rt = Instance.new("TextLabel")
        rt.Position = UDim2.new(0, 46, 0, 8)
        rt.Size = UDim2.new(1, -60, 0, 18)
        rt.BackgroundTransparency = 1
        rt.Text = r.title or ""
        rt.TextColor3 = Color3.fromRGB(238, 239, 244)
        rt.TextXAlignment = Enum.TextXAlignment.Left
        rt.TextSize = UI.T_ROW
        rt.TextTruncate = Enum.TextTruncate.AtEnd
        rt.ZIndex = 7
        rt.Parent = row
        UI.applyFont(rt, Enum.FontWeight.SemiBold)

        local rb = Instance.new("TextLabel")
        rb.Position = UDim2.new(0, 46, 0, 26)
        rb.Size = UDim2.new(1, -60, 0, 18)
        rb.BackgroundTransparency = 1
        rb.Text = r.text or ""
        rb.TextColor3 = UI.textMuted
        rb.TextXAlignment = Enum.TextXAlignment.Left
        rb.TextSize = UI.T_SMALL
        rb.TextTruncate = Enum.TextTruncate.AtEnd
        rb.ZIndex = 7
        rb.Parent = row
        UI.applyFont(rb, Enum.FontWeight.Regular)
    end

    -- Buttons right-aligned, primary last, using the same gradient treatment
    -- as the notification actions.
    if #actions > 0 then
        local made = {}
        local total = 0
        for _, a in ipairs(actions) do
            local b = UI.gradButton(panel, a.label, a.icon, a.style or "ghost")
            b.ZIndex = 8
            made[#made + 1] = { b, a }
            total = total + b.Size.X.Offset + 8
        end
        local x = W - PAD - total + 8
        for _, m in ipairs(made) do
            local b, a = m[1], m[2]
            b.Position = UDim2.new(0, x, 0, headH + bodyH + 12)
            x = x + b.Size.X.Offset + 8
            b.MouseButton1Click:Connect(function()
                Modal.hide()
                if a.run then task.delay(0.24, function() pcall(a.run) end) end
            end)
        end
    end

    -- Custom body: gets the panel plus the band it may use, so a caller can
    -- render anything without re-deriving the header height.
    if spec.build then pcall(spec.build, panel, headH, bodyH, W) end

    -- Fail open: disabling backdrop dismiss makes the buttons the only way
    -- out, so a caller that passes no buttons would trap the user in a panel
    -- with no route back to the game.
    if spec.dismissOnBackdrop ~= false or #actions == 0 then
        dim.MouseButton1Click:Connect(function() Modal.hide() end)
    end

    Modal.open = true
    Modal.owner = spec.owner
    Modal.onHidden = nil

    -- entrance: dim fades, panel eases up to full size
    local ti = TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    TweenService:Create(dim, TweenInfo.new(0.28), { BackgroundTransparency = 0.45 }):Play()
    panel.BackgroundTransparency = 1
    UI.fadeContent(panel, true)
    TweenService:Create(panel, ti, {
        Size = UDim2.fromOffset(W, H),
        BackgroundTransparency = UI.panelT(),
    }):Play()
    task.delay(0.06, function()
        if Modal.panel == panel then UI.fadeContent(panel, false, true) end
    end)
    return panel
end

-- ════════════════════════════════════════════════════════════════════════
--  TOUR
--  A guided walkthrough that points at the REAL interface: everything
--  except the current target is dimmed, the target gets a pulsing accent
--  ring, and a callout explains it. Steps also drive the UI -- the menu and
--  command bar genuinely open as you go, so what is being described is what
--  is on screen, not a picture of it.
-- ════════════════════════════════════════════════════════════════════════
Tour = { step = 0, running = false }

-- Raw-screen rect of a GuiObject. AbsolutePosition is inset-origin while
-- these overlays are IgnoreGuiInset, so the inset has to be added back --
-- the same correction UI.bottomY makes.
function UI.absRect(el)
    if not el then return nil end
    local inset = game:GetService("GuiService"):GetGuiInset()
    local p, s = el.AbsolutePosition, el.AbsoluteSize
    if s.X <= 0 or s.Y <= 0 then return nil end
    return p.X, p.Y + inset.Y, s.X, s.Y
end

function Tour.build()
    if Tour.gui then return end
    local gui = Instance.new("ScreenGui")
    gui.Name = "UHubLiteTour"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 10002
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function()
        gui.Parent = (typeof(gethui) == "function" and gethui())
                  or game:GetService("CoreGui")
    end)
    Tour.gui = gui

    -- Swallows every click and hover for the duration. The shade panels are
    -- Frames and do not absorb input, so without this the real cursor reaches
    -- the pill underneath and fires the ordinary hover handlers -- which then
    -- fight the tour's scripted ones. Sits below the shades so it is
    -- invisible, and below the callout so Next/Skip stay clickable.
    local block = Instance.new("TextButton")
    block.Name = "InputBlock"
    block.Size = UDim2.fromScale(1, 1)
    block.BackgroundTransparency = 1
    block.Text = ""
    block.AutoButtonColor = false
    block.Modal = true
    block.ZIndex = 1
    block.Parent = gui
    Tour.block = block

    -- Four panels around the target rather than one dim with a hole --
    -- Roblox has no cheap cutout, and four frames animate just as well.
    Tour.shade = {}
    for i = 1, 4 do
        local f = Instance.new("Frame")
        f.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        f.BackgroundTransparency = 1
        f.BorderSizePixel = 0
        f.ZIndex = 2
        f.Parent = gui
        Tour.shade[i] = f
    end

    -- Ring drawn ON the target, so you look at the thing, not at a diagram.
    local ring = Instance.new("Frame")
    ring.Name = "Ring"
    ring.BackgroundTransparency = 1
    ring.BorderSizePixel = 0
    ring.ZIndex = 4
    ring.Parent = gui
    Instance.new("UICorner", ring).CornerRadius = UDim.new(0, 14)
    local rs = Instance.new("UIStroke", ring)
    rs.Color = UI.accent
    rs.Thickness = 2
    rs.Transparency = 0.1
    Tour.ring, Tour.ringStroke = ring, rs

    -- A cursor the tour drives itself. Pointing at a control and describing
    -- it still leaves the user to work out the gesture; walking a pointer
    -- over and performing it removes that step. Touch gets a tap disc
    -- instead of an arrow, because a mouse pointer on a phone is a lie.
    local ripple = Instance.new("Frame")
    ripple.Name = "Ripple"
    ripple.AnchorPoint = Vector2.new(0.5, 0.5)
    ripple.Size = UDim2.fromOffset(10, 10)
    ripple.BackgroundTransparency = 1
    ripple.BorderSizePixel = 0
    ripple.ZIndex = 8
    ripple.Parent = gui
    Instance.new("UICorner", ripple).CornerRadius = UDim.new(1, 0)
    local rst = Instance.new("UIStroke", ripple)
    rst.Color = UI.accent
    rst.Thickness = 2
    rst.Transparency = 1
    Tour.ripple, Tour.rippleStroke = ripple, rst

    local cur = Instance.new("ImageLabel")
    cur.Name = "Cursor"
    cur.AnchorPoint = UI.touch and Vector2.new(0.5, 0.5) or Vector2.new(0.15, 0.1)
    cur.Size = UDim2.fromOffset(UI.touch and 30 or 26, UI.touch and 30 or 26)
    cur.BackgroundTransparency = 1
    cur.Image = UI.icon(UI.touch and "st_hand.png" or "st_mouse-pointer-2.png")
    cur.ImageColor3 = Color3.fromRGB(255, 255, 255)
    cur.ImageTransparency = 1
    cur.ZIndex = 9
    cur.Parent = gui
    Tour.cursor = cur

    -- Callout
    local card = Instance.new("Frame")
    card.Name = "Callout"
    card.AnchorPoint = Vector2.new(0.5, 0)
    card.Size = UDim2.fromOffset(360, 150)
    card.BackgroundColor3 = UI.cardFill
    card.BackgroundTransparency = 1
    card.BorderSizePixel = 0
    card.ZIndex = 6
    card.Parent = gui
    UI.glassify(card, 14)
    UI.accentWash(card)
    Tour.card = card

    local step = Instance.new("TextLabel")
    step.Position = UDim2.new(0, 20, 0, 16)
    step.Size = UDim2.new(1, -40, 0, 12)
    step.BackgroundTransparency = 1
    step.TextColor3 = UI.accent
    step.TextXAlignment = Enum.TextXAlignment.Left
    step.TextSize = 10
    step.ZIndex = 7
    step.Parent = card
    UI.applyFont(step, Enum.FontWeight.Bold)
    Tour.stepLabel = step

    local title = Instance.new("TextLabel")
    title.Position = UDim2.new(0, 20, 0, 32)
    title.Size = UDim2.new(1, -40, 0, 22)
    title.BackgroundTransparency = 1
    title.TextColor3 = UI.textPrimary
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextSize = 17
    title.TextTruncate = Enum.TextTruncate.AtEnd
    title.ZIndex = 7
    title.Parent = card
    UI.applyFont(title, Enum.FontWeight.Bold)
    Tour.titleLabel = title

    local body = Instance.new("TextLabel")
    body.Position = UDim2.new(0, 20, 0, 56)
    body.Size = UDim2.new(1, -40, 0, 44)
    body.BackgroundTransparency = 1
    body.TextColor3 = UI.textMuted
    body.TextXAlignment = Enum.TextXAlignment.Left
    body.TextYAlignment = Enum.TextYAlignment.Top
    body.TextWrapped = true
    body.TextSize = UI.T_ROW
    body.ZIndex = 7
    body.Parent = card
    UI.applyFont(body, Enum.FontWeight.Regular)
    Tour.bodyLabel = body

    local skip = UI.gradButton(card, "Skip", "st_x.png", "ghost")
    skip.Position = UDim2.new(0, 20, 0, 106)
    skip.ZIndex = 8
    skip.MouseButton1Click:Connect(function() Tour.finish(true) end)

    local next_ = UI.gradButton(card, "Next", "st_chevron-right.png", "light")
    next_.AnchorPoint = Vector2.new(1, 0)
    next_.Position = UDim2.new(1, -20, 0, 106)
    next_.ZIndex = 8
    next_.MouseButton1Click:Connect(function() Tour.advance() end)
    Tour.nextBtn = next_
end

-- Move the spotlight, ring and callout onto a rect.
function Tour.focus(x, y, w, h)
    local cam = workspace.CurrentCamera
    local vp = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
    local pad = 8
    x, y, w, h = x - pad, y - pad, w + pad * 2, h + pad * 2

    -- Clamp the hole to the viewport. A target flush against an edge pushes
    -- x or y negative, and the surrounding panels then overlap instead of
    -- tiling -- two shades at 0.42 stack into a visibly darker band.
    local x2, y2 = math.min(vp.X, x + w), math.min(vp.Y, y + h)
    x, y = math.max(0, x), math.max(0, y)
    w, h = math.max(0, x2 - x), math.max(0, y2 - y)

    local T = 0.42

    local ti = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local function put(f, px, py, pw, ph)
        TweenService:Create(f, ti, {
            Position = UDim2.fromOffset(px, py),
            Size = UDim2.fromOffset(math.max(0, pw), math.max(0, ph)),
            BackgroundTransparency = T,
        }):Play()
    end
    put(Tour.shade[1], 0, 0, vp.X, y)                            -- above
    put(Tour.shade[2], 0, y + h, vp.X, vp.Y - (y + h))           -- below
    put(Tour.shade[3], 0, y, x, h)                               -- left
    put(Tour.shade[4], x + w, y, vp.X - (x + w), h)              -- right

    TweenService:Create(Tour.ring, ti, {
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
    }):Play()

    -- Callout goes below the target, or above it when there is no room.
    local cw, ch = 360, 150
    local cx = math.clamp(x + w / 2, cw / 2 + 12, vp.X - cw / 2 - 12)
    local cy = (y + h + 16 + ch < vp.Y) and (y + h + 16) or (y - ch - 16)
    TweenService:Create(Tour.card, ti, {
        Position = UDim2.new(0, cx, 0, math.max(12, cy)),
    }):Play()
end

-- Glide the cursor to a point, then play a press. onPress fires at the
-- moment of contact so the UI reacts exactly when it looks like it should.
function Tour.walkTo(px, py, onPress)
    local cur, rip = Tour.cursor, Tour.ripple
    if not cur then if onPress then onPress() end return end

    if cur.ImageTransparency > 0.9 then
        -- first appearance: start a little off the target so the travel reads
        cur.Position = UDim2.fromOffset(px - 90, py + 70)
        TweenService:Create(cur, TweenInfo.new(0.25), { ImageTransparency = 0.05 }):Play()
    end

    local travel = TweenService:Create(cur,
        TweenInfo.new(0.62, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        { Position = UDim2.fromOffset(px, py) })
    travel.Completed:Connect(function()
        if not Tour.running then return end
        -- press: cursor dips, ring expands out from the contact point
        TweenService:Create(cur, TweenInfo.new(0.09), {
            Size = UDim2.fromOffset(UI.touch and 25 or 21, UI.touch and 25 or 21) }):Play()
        task.delay(0.09, function()
            pcall(function()
                TweenService:Create(cur, TweenInfo.new(0.16, Enum.EasingStyle.Back,
                    Enum.EasingDirection.Out), {
                    Size = UDim2.fromOffset(UI.touch and 30 or 26, UI.touch and 30 or 26) }):Play()
            end)
        end)

        rip.Position = UDim2.fromOffset(px, py)
        rip.Size = UDim2.fromOffset(10, 10)
        Tour.rippleStroke.Transparency = 0.15
        TweenService:Create(rip, TweenInfo.new(0.45, Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out), { Size = UDim2.fromOffset(64, 64) }):Play()
        TweenService:Create(Tour.rippleStroke, TweenInfo.new(0.45), { Transparency = 1 }):Play()

        if onPress then task.delay(0.08, function() pcall(onPress) end) end
    end)
    travel:Play()
end

function Tour.pulse()
    if Tour.pulseTween then Tour.pulseTween:Cancel() end
    Tour.ringStroke.Transparency = 0.1
    Tour.pulseTween = TweenService:Create(Tour.ringStroke,
        TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { Transparency = 0.62 })
    Tour.pulseTween:Play()
end

function Tour.steps()
    local touch = UI.touch
    local function resetUI()
        pcall(function()
            CmdBar.hide() Settings.hide() Info.hide() Profile.hide() Bar.close()
        end)
    end
    return {
        {
            target = function() return Bar.holder end,
            title = "This is the hub",
            text = touch and "Watch -- tapping it slides out the clock, weather and settings."
                          or "Watch -- hovering it slides out the clock, weather and settings.",
            reset = resetUI,
            act = function()
                Bar.mode = "idle"
                Notify.showGlyph(nil) Notify.showSubIcon(nil)
                Bar.mode = "menu"
                Bar.setText("Universal Hub", "Lite V2")
                Bar.subLabel.TextColor3 = UI.accent
                Bar.open(false) Info.show() Settings.show()
            end,
        },
        {
            target = function() return Settings.clip end,
            title = "Settings live here",
            text = touch and "Tapping this card expands it: prefix, opacity, theme, and the key for commands."
                          or "Hovering this card expands it: prefix, opacity, theme, and the command-bar key.",
            act = function() Settings.expand(true) end,
        },
        {
            target = function()
                if touch then return Bar.touchCmd end
                return Bar.holder
            end,
            title = touch and "Commands are one tap away" or "Press T for commands",
            text = touch and "This button opens the command bar wherever you are."
                          or "T opens the command bar. Rebind it in the settings you just saw.",
            reset = function() pcall(function() Settings.expand(false) end) end,
            act = function() CmdBar.show() end,
        },
        {
            target = function() return CmdBar.clip end,
            title = "Type, and it fills in",
            text = "Enter completes the highlighted row, Enter again runs it. Player commands show avatars as you type.",
            act = function()
                CmdBar.show()
                task.delay(0.15, function()
                    pcall(function() CmdBar.box.Text = "prof" end)
                    pcall(updateAutocomplete)
                end)
            end,
        },
    }
end

function Tour.showStep(i)
    local steps = Tour.steps()
    local st = steps[i]
    if not st then Tour.finish() return end
    Tour.step = i

    if st.reset then pcall(st.reset) end
    Tour.stepLabel.Text = ("STEP %d OF %d"):format(i, #steps)
    Tour.titleLabel.Text = st.title
    Tour.bodyLabel.Text = st.text
    Tour.nextBtn.Visible = true

    -- Resolve after a beat: the previous step's reset may still be tweening,
    -- and an element mid-tween reports the rect it is leaving, not arriving at.
    task.delay(st.reset and 0.45 or 0.2, function()
        if not Tour.running or Tour.step ~= i then return end
        local el = st.target and st.target()
        local x, y, w, h = UI.absRect(el)
        if not x then
            -- nothing to point at; skip rather than ring an empty rect
            Tour.advance()
            return
        end
        Tour.focus(x, y, w, h)
        Tour.pulse()
        -- Cursor walks over and performs it, so the gesture is demonstrated
        -- rather than described.
        Tour.walkTo(x + w / 2, y + h / 2, function()
            if not Tour.running or Tour.step ~= i then return end
            if st.act then pcall(st.act) end
            -- the act may resize the target (a card expanding); re-frame it
            task.delay(0.45, function()
                if not Tour.running or Tour.step ~= i then return end
                local nx, ny, nw, nh = UI.absRect(st.target and st.target())
                if nx then Tour.focus(nx, ny, nw, nh) end
            end)
        end)
    end)
end

function Tour.advance()
    if not Tour.running then return end
    Tour.showStep(Tour.step + 1)
end

function Tour.finish(skipped)
    if not Tour.running then return end
    Tour.running = false
    if Tour.pulseTween then Tour.pulseTween:Cancel() Tour.pulseTween = nil end
    Tour.cursor, Tour.ripple, Tour.block = nil, nil, nil
    local gui = Tour.gui
    Tour.gui = nil
    if gui then
        for _, f in ipairs(gui:GetChildren()) do
            pcall(function()
                TweenService:Create(f, TweenInfo.new(0.22),
                    { BackgroundTransparency = 1 }):Play()
            end)
        end
        task.delay(0.28, function() pcall(function() gui:Destroy() end) end)
    end
    UI.guideSeen = true
    UI.saveConfig()
    pcall(function()
        CmdBar.hide() Settings.hide() Info.hide() Bar.close()
    end)
    if not skipped then
        Notifications:Success("Universal Hub Lite",
            "That's it -- run guide any time to see it again", 4)
    end
end

function Tour.start()
    if Tour.running then return end
    Tour.build()
    Tour.running = true
    Tour.card.BackgroundTransparency = 1
    UI.fadeContent(Tour.card, true)
    TweenService:Create(Tour.card, TweenInfo.new(0.3),
        { BackgroundTransparency = UI.cardT() }):Play()
    task.delay(0.1, function()
        if Tour.card then UI.fadeContent(Tour.card, false, true) end
    end)
    Tour.showStep(1)
end

-- ── First-run guidance ──────────────────────────────────────────────────
-- Shown once, then never again unless asked for with !guide. The content
-- adapts to the device: telling a phone user to "press T" is useless.
Guide = {}

function Guide.rows()
    if UI.touch then
        return {
            { icon = "st_terminal.png", title = "Tap the terminal button",
              text = "Under the icon, top-right. Opens the command bar." },
            { icon = "st_users.png", title = "Tap the icon itself",
              text = "Clock, weather and settings slide out. Tap again to close." },
            { icon = "st_list.png", title = "Browse everything",
              text = "Run cmds to see every command with a description." },
            { icon = "st_circle-x.png", title = "Done with it?",
              text = "Run unexecute to unload cleanly and free a re-execute." },
        }
    end
    return {
        { icon = "st_terminal.png", title = "Press T for the command bar",
          text = "Type, Enter to complete, Enter again to run. Rebind it in settings." },
        { icon = "st_users.png", title = "Hover the icon, top-right",
          text = "Clock, weather and settings slide out underneath it." },
        { icon = "st_list.png", title = "Browse everything",
          text = "!cmds lists every command, grouped, with descriptions." },
        { icon = "st_circle-x.png", title = "Done with it?",
          text = "!unexecute unloads cleanly and frees a re-execute." },
    }
end

function Guide.show(firstRun)
    -- Built with inserts, NOT a constructor with a conditional entry: a nil
    -- in the middle of a table literal ends ipairs there, so on a re-open the
    -- whole button strip silently vanished while still reserving its height.
    local actions = {}
    if firstRun then
        actions[#actions + 1] = {
            label = "Don't show again", icon = "st_x.png", style = "ghost",
            run = function()
                UI.guideSeen = true
                UI.saveConfig()
                Notifications:Info("Universal Hub Lite",
                    "Guide hidden -- run guide to bring it back", 4)
            end,
        }
    else
        actions[#actions + 1] = {
            label = "Close", icon = "st_x.png", style = "ghost",
            run = function() end,
        }
    end
    actions[#actions + 1] = {
        label = "Show me", icon = "st_chevron-right.png", style = "light",
        run = function() Tour.start() end,
    }

    Modal.show{
        dismissOnBackdrop = false,
        title = "Universal Hub Lite",
        subtitle = firstRun
            and "Take the tour and it will point at each piece on screen."
            or  "Take the tour again, or just read the summary.",
        rows = Guide.rows(),
        actions = actions,
    }
end

function Guide.maybeShowOnStartup()
    if UI.guideSeen then return false end
    task.delay(0.6, function() Guide.show(true) end)
    return true
end

-- ════════════════════════════════════════════════════════════════════════
--  CARD STACK
--  Cards queue vertically under the bar in a fixed order. Opening one takes
--  its slot and everything below GLIDES down; closing one lets the rest rise
--  into the gap. Positions use each card's target height so a card's own
--  slide and the reflow of its neighbours stay in step.
-- ════════════════════════════════════════════════════════════════════════
Cards = {}

function Cards.order()
    return {
        { clip = CmdBar.clip,  panel = CmdBar.panel,  open = function() return CmdBar.open  end },
        { clip = Profile.clip, panel = Profile.panel, open = function() return Profile.open end },
        { clip = Info.clip,    panel = Info.panel,    open = function() return Info.open    end },
        { clip = Perf.clip,    panel = Perf.panel,    open = function() return Perf.open    end },
        { clip = Settings.clip, panel = Settings.panel, open = function() return Settings.open end },
    }
end

-- Raw-screen Y this card would occupy given what else is currently out.
function Cards.slotY(targetClip)
    if not Bar.holder then return 0 end
    local y = UI.bottomY(Bar.holder) + UI.MENU_GAP - 10
    for _, c in ipairs(Cards.order()) do
        if c.clip == targetClip then return y end
        -- a card can be flagged open while its panel is mid-rebuild
        if c.clip and c.panel and c.open()
           and not c.clip:GetAttribute("_detached") then
            y = y + UI.targetH(c.panel) + UI.MENU_GAP
        end
    end
    return y
end

function Cards.reflow(animate)
    if not Bar.holder then return end

    -- The chip stack hangs off the ScreenGui, not the holder, so it does not
    -- travel when the bar grows -- and the action tray grows the bar DOWNWARD
    -- into exactly the band the chips sit in. Any notification raised while a
    -- tray is open rendered straight through the buttons. It moves with the
    -- bar now, on the same tween as the cards.
    if Bar.stack then
        local sy = 14 + UI.targetH(Bar.holder) + 6
        local st = UDim2.new(1, -14, 0, sy)
        if animate then
            TweenService:Create(Bar.stack,
                TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                { Position = st }):Play()
        else
            Bar.stack.Position = st
        end
    end

    local y = UI.bottomY(Bar.holder) + UI.MENU_GAP - 10
    for _, c in ipairs(Cards.order()) do
        -- dragged out of the column: the user owns its position now
        if c.clip and c.panel and c.open()
           and not c.clip:GetAttribute("_detached") then
            local target = UDim2.new(1, -14, 0, y)
            if animate then
                TweenService:Create(c.clip,
                    TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                    { Position = target }):Play()
            else
                c.clip.Position = target
            end
            y = y + UI.targetH(c.panel) + UI.MENU_GAP
        end
    end
end

-- Is the cursor over the bar or any open card? Positional, so a card
-- tweening out from under a still cursor cannot report a false leave.
function Cards.hovered()
    if UI.mouseInside(Bar.holder, 4) then return true end
    for _, c in ipairs(Cards.order()) do
        if c.clip and c.open() and UI.mouseInside(c.clip, 6) then return true end
    end
    return false
end
-- ════════════════════════════════════════════════════════════════════════
--  SETTINGS CARD
--  Sits under the clock. Collapsed it reports the three values; hovering
--  expands it into live controls for prefix, opacity and theme.
-- ════════════════════════════════════════════════════════════════════════
Settings = { open = false, expanded = false, H = 52, EXP = 274 }

function Settings.build()
    local clip, p = UI.makeDrawer("SettingsPanel", UI.EXP_W, Settings.H, Bar.gui)
    Settings.clip, Settings.panel = clip, p

    -- Collapsed summary: three cells, same rhythm as the clock card.
    local col = Instance.new("Frame")
    col.Name = "Collapsed"
    col.Size = UDim2.new(1, 0, 0, Settings.H)
    col.BackgroundTransparency = 1
    col.ZIndex = 42
    col.Parent = p
    Settings.colView = col

    -- Gear at the far left so the card reads as settings at a glance.
    local gear = Instance.new("ImageLabel")
    gear.Name = "Gear"
    gear.AnchorPoint = Vector2.new(0, 0.5)
    gear.Position = UDim2.new(0, 15, 0.5, 0)
    gear.Size = UDim2.fromOffset(15, 15)
    gear.BackgroundTransparency = 1
    gear.Image = UI.icon("st_settings-2.png")
    gear.ImageColor3 = UI.accent
    gear.ImageTransparency = 0.1
    gear.ZIndex = 43
    gear.Parent = col
    Settings.gear = gear

    Settings.cells = {}
    local defs = { { "st_terminal.png", "PREFIX" },
                   { "st_gauge.png",    "OPACITY" },
                   { "st_sparkles.png", "THEME" } }
    -- KEEP is reported in the expanded pane, not the collapsed strip -- three
    -- cells is all that fits across 380px.
    for i, d in ipairs(defs) do
        local cx = 42 + (i - 1) * 112
        local ic = Instance.new("ImageLabel")
        ic.AnchorPoint = Vector2.new(0, 0.5)
        ic.Position = UDim2.new(0, cx, 0.5, 0)
        ic.Size = UDim2.fromOffset(15, 15)
        ic.BackgroundTransparency = 1
        ic.Image = UI.icon(d[1])
        ic.ImageColor3 = Color3.fromRGB(255, 255, 255)
        ic.ImageTransparency = 0.15
        ic.ZIndex = 43
        ic.Parent = col

        local v = Instance.new("TextLabel")
        v.AnchorPoint = Vector2.new(0, 0.5)
        v.Position = UDim2.new(0, cx + 21, 0.5, 0)
        v.Size = UDim2.fromOffset(86, 18)
        v.BackgroundTransparency = 1
        v.Text = "-"
        v.TextColor3 = Color3.fromRGB(255, 255, 255)
        v.TextTransparency = 0.1
        v.TextXAlignment = Enum.TextXAlignment.Left
        v.TextSize = UI.T_ROW
        v.TextTruncate = Enum.TextTruncate.AtEnd
        v.ZIndex = 43
        v.Parent = col
        UI.applyFont(v, Enum.FontWeight.Light)
        Settings.cells[d[2]] = v
    end

    local det = Instance.new("Frame")
    det.Name = "Detail"
    det.Position = UDim2.new(0, 0, 0, Settings.H)
    det.Size = UDim2.new(1, 0, 1, -Settings.H)
    det.BackgroundTransparency = 1
    det.Visible = false
    det.ZIndex = 43
    det.Parent = p
    Settings.detail = det

    UI.hoverOrTap(clip,
        function() Settings.expand(true) end,
        function() Settings.expand(false) end,
        function() return Settings.expanded end)

    Settings.bindDragEnd()
    Settings.renderCollapsed()
end

-- One session-level mouse-up for whatever slider is currently live.
function Settings.bindDragEnd()
    if Settings.dragBound then return end
    Settings.dragBound = true
    UserInputService.InputEnded:Connect(function(i)
        if (i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.Touch) and Settings.endDrag then
            Settings.endDrag()
        end
    end)
end

function Settings.renderCollapsed()
    local c = Settings.cells
    if not c then return end
    c.PREFIX.Text  = prefix
    c.OPACITY.Text = math.floor(UI.OPACITY * 100 + 0.5) .. "%"
    local t = UI.THEMES[UI.themeId]
    c.THEME.Text = t and t.name or "-"
    c.THEME.TextColor3 = UI.accent
    c.THEME.TextTransparency = 0
end

-- ── Slider ──────────────────────────────────────────────────────────────
function Settings.slider(parent, x, y, w, frac, onChange)
    local track = Instance.new("Frame")
    track.AnchorPoint = Vector2.new(0, 0.5)
    track.Position = UDim2.new(0, x, 0, y)
    track.Size = UDim2.fromOffset(w, 4)
    track.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    track.BackgroundTransparency = 0.86
    track.BorderSizePixel = 0
    track.ZIndex = 44
    track.Parent = parent
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.AnchorPoint = Vector2.new(0, 0.5)
    fill.Position = UDim2.fromScale(0, 0.5)
    fill.Size = UDim2.new(frac, 0, 1, 0)
    fill.BackgroundColor3 = UI.accent
    fill.BorderSizePixel = 0
    fill.ZIndex = 45
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.fromScale(frac, 0.5)
    knob.Size = UDim2.fromOffset(11, 11)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.ZIndex = 46
    knob.Parent = track
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    -- taller invisible grab strip
    local hit = Instance.new("TextButton")
    hit.AnchorPoint = Vector2.new(0, 0.5)
    hit.Position = UDim2.new(0, x, 0, y)
    hit.Size = UDim2.fromOffset(w, 20)
    hit.BackgroundTransparency = 1
    hit.Text = ""
    hit.AutoButtonColor = false
    hit.ZIndex = 47
    hit.Parent = parent

    local dragging, moveConn = false, nil
    -- GetMouseLocation reports the last touch point on mobile, so the maths
    -- is shared; only the event type differs.
    local function fracAt(input)
        local mx
        if input and input.Position then
            mx = input.Position.X
        else
            mx = UserInputService:GetMouseLocation().X
        end
        return math.clamp((mx - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
    end
    local function set(f)
        fill.Size = UDim2.new(f, 0, 1, 0)
        knob.Position = UDim2.fromScale(f, 0.5)
        onChange(f)
    end

    hit.MouseButton1Down:Connect(function()
        dragging = true
        Settings.dragging = true
        set(fracAt())
        moveConn = UserInputService.InputChanged:Connect(function(i)
            -- Touch drags arrive as UserInputType.Touch, never MouseMovement,
            -- so a mouse-only filter leaves the slider dead on mobile.
            if i.UserInputType == Enum.UserInputType.MouseMovement
            or i.UserInputType == Enum.UserInputType.Touch then
                set(fracAt(i))
            end
        end)
    end)
    -- Drag-end is handled by ONE session-level connection (see below);
    -- connecting here would add a handler on every hover-expand.
    Settings.endDrag = function()
        if not dragging then return end
        dragging = false
        Settings.dragging = false
        if moveConn then moveConn:Disconnect() moveConn = nil end
        UI.saveConfig()
    end
    return set
end

function Settings.renderDetail()
    for _, c in ipairs(Settings.detail:GetChildren()) do pcall(function() c:Destroy() end) end
    local d = Settings.detail

    -- Prefix -------------------------------------------------------------
    local pl = Instance.new("TextLabel")
    pl.Position = UDim2.new(0, 20, 0, 6)
    pl.Size = UDim2.fromOffset(70, 18)
    pl.BackgroundTransparency = 1
    pl.Text = "PREFIX"
    pl.TextColor3 = UI.textMuted
    pl.TextXAlignment = Enum.TextXAlignment.Left
    pl.TextSize = UI.T_EYEBROW
    pl.ZIndex = 44
    pl.Parent = d
    UI.applyFont(pl, Enum.FontWeight.Bold)

    local box = Instance.new("TextBox")
    box.AnchorPoint = Vector2.new(0, 0.5)
    box.Position = UDim2.new(0, 96, 0, 15)
    box.Size = UDim2.fromOffset(46, 26)
    box.BackgroundColor3 = Color3.fromRGB(42, 44, 52)
    box.Text = prefix
    box.PlaceholderText = "!"
    box.PlaceholderColor3 = UI.textMuted
    box.TextColor3 = UI.textPrimary
    box.TextSize = UI.T_ROW
    box.ClearTextOnFocus = false
    box.ZIndex = 44
    box.Parent = d
    UI.applyFont(box, Enum.FontWeight.SemiBold)
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 7)
    local bs = Instance.new("UIStroke", box)
    bs.Color = Color3.fromRGB(90, 92, 104); bs.Thickness = 1; bs.Transparency = 0.55

    box.Focused:Connect(function()
        Settings.typing = true
        TweenService:Create(bs, TweenInfo.new(0.15),
            { Color = UI.accent, Transparency = 0.1 }):Play()
    end)
    box.FocusLost:Connect(function()
        Settings.typing = false
        TweenService:Create(bs, TweenInfo.new(0.15),
            { Color = Color3.fromRGB(90, 92, 104), Transparency = 0.55 }):Play()
        local v = (box.Text or ""):gsub("%s", "")
        -- One character, and never alphanumeric or it would swallow chat.
        if #v == 1 and not v:match("[%w]") then
            prefix = v
            UI.saveConfig()
        end
        box.Text = prefix
        Settings.renderCollapsed()
    end)

    local hint = Instance.new("TextLabel")
    hint.Position = UDim2.new(0, 150, 0, 6)
    hint.Size = UDim2.new(1, -170, 0, 18)
    hint.BackgroundTransparency = 1
    hint.Text = "one symbol, not a letter"
    hint.TextColor3 = UI.textMuted
    hint.TextXAlignment = Enum.TextXAlignment.Left
    hint.TextSize = UI.T_SMALL
    hint.ZIndex = 44
    hint.Parent = d
    UI.applyFont(hint, Enum.FontWeight.Regular)

    -- Command bar key ----------------------------------------------------
    local kl = Instance.new("TextLabel")
    kl.Position = UDim2.new(0, 20, 0, 44)
    kl.Size = UDim2.fromOffset(70, 18)
    kl.BackgroundTransparency = 1
    kl.Text = "KEY"
    kl.TextColor3 = UI.textMuted
    kl.TextXAlignment = Enum.TextXAlignment.Left
    kl.TextSize = UI.T_EYEBROW
    kl.ZIndex = 44
    kl.Parent = d
    UI.applyFont(kl, Enum.FontWeight.Bold)

    local kb = Instance.new("TextButton")
    kb.AnchorPoint = Vector2.new(0, 0.5)
    kb.Position = UDim2.new(0, 96, 0, 53)
    kb.Size = UDim2.fromOffset(46, 26)
    kb.AutoButtonColor = false
    kb.BackgroundColor3 = Color3.fromRGB(42, 44, 52)
    kb.Text = _G.CmdBarKeybind and _G.CmdBarKeybind.Name or "T"
    kb.TextColor3 = UI.textPrimary
    kb.TextSize = UI.T_ROW
    kb.ZIndex = 44
    kb.Parent = d
    UI.applyFont(kb, Enum.FontWeight.SemiBold)
    Instance.new("UICorner", kb).CornerRadius = UDim.new(0, 7)
    local ks = Instance.new("UIStroke", kb)
    ks.Color = Color3.fromRGB(90, 92, 104); ks.Thickness = 1; ks.Transparency = 0.55

    local khint = Instance.new("TextLabel")
    khint.Position = UDim2.new(0, 150, 0, 44)
    khint.Size = UDim2.new(1, -170, 0, 18)
    khint.BackgroundTransparency = 1
    khint.Text = "click, then press a key"
    khint.TextColor3 = UI.textMuted
    khint.TextXAlignment = Enum.TextXAlignment.Left
    khint.TextSize = UI.T_SMALL
    khint.ZIndex = 44
    khint.Parent = d
    UI.applyFont(khint, Enum.FontWeight.Regular)

    kb.MouseButton1Click:Connect(function()
        if CmdBar.capturing then return end
        CmdBar.capturing = true            -- suppress the toggle while rebinding
        Settings.typing = true             -- and hold the pane open
        kb.Text = "..."
        TweenService:Create(ks, TweenInfo.new(0.15),
            { Color = UI.accent, Transparency = 0.1 }):Play()

        local conn
        conn = UserInputService.InputBegan:Connect(function(input, gp)
            if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            conn:Disconnect()
            local k = input.KeyCode
            -- Escape cancels; anything else becomes the new toggle.
            if k ~= Enum.KeyCode.Escape then
                _G.CmdBarKeybind = k
            end
            kb.Text = _G.CmdBarKeybind.Name
            UI.saveConfig()
            khint.Text = "click, then press a key"
            TweenService:Create(ks, TweenInfo.new(0.15),
                { Color = Color3.fromRGB(90, 92, 104), Transparency = 0.55 }):Play()
            task.delay(0.1, function()
                CmdBar.capturing = false
                Settings.typing = false
            end)
        end)
    end)

    -- Opacity ------------------------------------------------------------
    local ol = Instance.new("TextLabel")
    ol.Position = UDim2.new(0, 20, 0, 82)
    ol.Size = UDim2.fromOffset(70, 18)
    ol.BackgroundTransparency = 1
    ol.Text = "OPACITY"
    ol.TextColor3 = UI.textMuted
    ol.TextXAlignment = Enum.TextXAlignment.Left
    ol.TextSize = UI.T_EYEBROW
    ol.ZIndex = 44
    ol.Parent = d
    UI.applyFont(ol, Enum.FontWeight.Bold)

    local ov = Instance.new("TextLabel")
    ov.AnchorPoint = Vector2.new(1, 0.5)
    ov.Position = UDim2.new(1, -20, 0, 91)
    ov.Size = UDim2.fromOffset(48, 18)
    ov.BackgroundTransparency = 1
    ov.Text = math.floor(UI.OPACITY * 100 + 0.5) .. "%"
    ov.TextColor3 = Color3.fromRGB(230, 231, 236)
    ov.TextXAlignment = Enum.TextXAlignment.Right
    ov.TextSize = UI.T_SMALL
    ov.ZIndex = 44
    ov.Parent = d
    UI.applyFont(ov, Enum.FontWeight.SemiBold)

    -- 0.25..1 mapped onto the track
    Settings.slider(d, 96, 91, UI.EXP_W - 96 - 76,
        (UI.OPACITY - 0.25) / 0.75, function(f)
            UI.setOpacity(0.25 + f * 0.75)
            ov.Text = math.floor(UI.OPACITY * 100 + 0.5) .. "%"
            Settings.renderCollapsed()
        end)

    -- Theme --------------------------------------------------------------
    local tl = Instance.new("TextLabel")
    tl.Position = UDim2.new(0, 20, 0, 126)
    tl.Size = UDim2.fromOffset(70, 18)
    tl.BackgroundTransparency = 1
    tl.Text = "THEME"
    tl.TextColor3 = UI.textMuted
    tl.TextXAlignment = Enum.TextXAlignment.Left
    tl.TextSize = UI.T_EYEBROW
    tl.ZIndex = 44
    tl.Parent = d
    UI.applyFont(tl, Enum.FontWeight.Bold)

    local x = 96
    for _, id in ipairs(UI.THEME_ORDER) do
        local th = UI.THEMES[id]
        local cur = (id == UI.themeId)
        local dot = Instance.new("TextButton")
        dot.AnchorPoint = Vector2.new(0, 0.5)
        dot.Position = UDim2.new(0, x, 0, 135)
        dot.Size = UDim2.fromOffset(cur and 17 or 14, cur and 17 or 14)
        dot.BackgroundColor3 = th.p
        dot.AutoButtonColor = false
        dot.Text = ""
        dot.ZIndex = 45
        dot.Parent = d
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
        if cur then
            local r = Instance.new("UIStroke", dot)
            r.Color = Color3.fromRGB(255, 255, 255); r.Thickness = 2; r.Transparency = 0.1
        end
        local base = cur and 17 or 14
        dot.MouseEnter:Connect(function()
            TweenService:Create(dot,
                TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                { Size = UDim2.fromOffset(19, 19) }):Play()
        end)
        dot.MouseLeave:Connect(function()
            TweenService:Create(dot, TweenInfo.new(0.12),
                { Size = UDim2.fromOffset(base, base) }):Play()
        end)
        dot.MouseButton1Click:Connect(function() Settings.pickTheme(id) end)
        x = x + 20
    end

    -- Re-run after teleports
    local kp = Instance.new("TextLabel")
    kp.Position = UDim2.new(0, 20, 0, 168)
    kp.Size = UDim2.fromOffset(200, 18)
    kp.BackgroundTransparency = 1
    kp.Text = "KEEP AFTER REJOIN"
    kp.TextColor3 = UI.textMuted
    kp.TextXAlignment = Enum.TextXAlignment.Left
    kp.TextSize = UI.T_EYEBROW
    kp.ZIndex = 44
    kp.Parent = d
    UI.applyFont(kp, Enum.FontWeight.Bold)

    if Persist and Persist.queue then
        Settings.persistSwitch(d, 162)
    else
        local na = Instance.new("TextLabel")
        na.AnchorPoint = Vector2.new(1, 0.5)
        na.Position = UDim2.new(1, -20, 0, 177)
        na.Size = UDim2.fromOffset(150, 18)
        na.BackgroundTransparency = 1
        na.Text = "executor cannot"
        na.TextColor3 = UI.textMuted
        na.TextXAlignment = Enum.TextXAlignment.Right
        na.TextSize = UI.T_SMALL
        na.ZIndex = 44
        na.Parent = d
        UI.applyFont(na, Enum.FontWeight.Regular)
    end

    local tn = Instance.new("TextLabel")
    tn.Position = UDim2.new(0, 20, 0, 196)
    tn.Size = UDim2.new(1, -40, 0, 18)
    tn.BackgroundTransparency = 1
    tn.Text = "the U-Lite mark follows the theme"
    tn.TextColor3 = UI.textMuted
    tn.TextXAlignment = Enum.TextXAlignment.Left
    tn.TextSize = UI.T_SMALL
    tn.ZIndex = 44
    tn.Parent = d
    UI.applyFont(tn, Enum.FontWeight.Regular)
end

-- Small pill switch for the teleport-persistence setting.
function Settings.persistSwitch(parent, y)
    local sw = Instance.new("TextButton")
    sw.AnchorPoint = Vector2.new(1, 0.5)
    sw.Position = UDim2.new(1, -20, 0, y + 15)
    sw.Size = UDim2.fromOffset(32, 17)
    sw.AutoButtonColor = false
    sw.Text = ""
    sw.BackgroundColor3 = Persist.enabled and UI.accent or Color3.fromRGB(52, 54, 62)
    sw.ZIndex = 45
    sw.Parent = parent
    Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0, 0.5)
    knob.Position = Persist.enabled and UDim2.new(1, -15, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
    knob.Size = UDim2.fromOffset(13, 13)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.ZIndex = 46
    knob.Parent = sw
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    sw.MouseButton1Click:Connect(function()
        Persist.enabled = not Persist.enabled
        UI.saveConfig()
        TweenService:Create(knob,
            TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                Position = Persist.enabled and UDim2.new(1, -15, 0.5, 0)
                                            or UDim2.new(0, 2, 0.5, 0) }):Play()
        TweenService:Create(sw, TweenInfo.new(0.18), {
            BackgroundColor3 = Persist.enabled and UI.accent
                                                or Color3.fromRGB(52, 54, 62) }):Play()
    end)
    return sw
end

function Settings.expand(on)
    if not Settings.panel or Settings.expanded == on then return end
    if not on and (Settings.typing or Settings.dragging) then return end
    -- Collapsing mid-tour would undo the step the cursor just performed.
    if not on and Tour and Tour.running then return end
    Settings.expanded = on
    local h = on and Settings.EXP or Settings.H
    local ti = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    if on then
        Settings.renderDetail()
        Settings.detail.Visible = true
    end
    TweenService:Create(Settings.clip, ti,
        { Size = UDim2.fromOffset(UI.EXP_W, h + 12) }):Play()
    UI.setTargetH(Settings.panel, h)
    local tp = TweenService:Create(Settings.panel, ti,
        { Size = UDim2.fromOffset(UI.EXP_W, h) })
    tp:Play()
    Cards.reflow(true)
    if not on then
        tp.Completed:Connect(function()
            if not Settings.expanded then Settings.detail.Visible = false end
        end)
    end
end

-- Switching theme re-skins everything, so the whole overlay is rebuilt --
-- the same approach musicbot uses, because recolouring in place misses
-- strokes, gradients and cached colours.
function Settings.pickTheme(id)
    if id == UI.themeId or not UI.THEMES[id] then return end
    UI.setTheme(id)
    UI.saveConfig()
    rebuildUI()
end

function Settings.show()
    if not Settings.panel or Settings.open then return end
    Settings.open = true
    Settings.renderCollapsed()
    UI.openDrawerAtY(Settings.clip, Settings.panel, Cards.slotY(Settings.clip))
    Cards.reflow(true)
end

function Settings.hide()
    if not Settings.open then return end
    Settings.open = false
    Settings.expand(false)
    UI.closeDrawer(Settings.clip, Settings.panel)
    Cards.reflow(true)
end




-- ════════════════════════════════════════════════════════════════════════
--  STARTUP
-- ════════════════════════════════════════════════════════════════════════
-- ════════════════════════════════════════════════════════════════════════
--  STARTUP
-- ════════════════════════════════════════════════════════════════════════

-- Everything that builds the overlay, in one callable place, because a theme
-- change tears it all down and builds it again -- recolouring in place misses
-- strokes, gradients and cached colours.
function buildUI()
    Bar.build()
    CmdBar.build()
    CmdBar.wire()
    CmdBar.bindKey()          -- self-guards, safe on rebuild
    Info.build()
    Perf.build()
    Settings.build()
    Persist.init()

    -- One dismissal path for the bar and every card. CmdBar/CmdList are
    -- explicitly dismissed (T / Escape / execute), so they pin the stack
    -- open regardless of the cursor.
    local function armDismiss()
        if Tour and Tour.running then return end   -- do not close what it opened
        if UI.touch then return end     -- nothing to leave; the pill toggles
        task.delay(0.25, function()
            if Bar.mode ~= "menu" then return end
            if CmdBar.open then return end
            if Settings.typing or Settings.dragging then return end
            if Cards.hovered() then return end
            Settings.hide()
            Info.hide()
            Perf.hide()
            Profile.hide()
            Bar.close()
        end)
    end

    local function openMenu()
        if Tour and Tour.running then return end   -- the tour is driving
        if Bar.mode ~= "idle" then return end
        Bar.mode = "menu"
        Notify.showGlyph(nil)          -- no status glyph on the hover card
        Notify.showSubIcon(nil)
        Bar.setText("Universal Hub",
            UI.touch and "Lite V2  -  tap for commands" or "Lite V2  -  press T")
        Bar.subLabel.TextColor3 = UI.accent
        Bar.open(false)
        Info.show()
        Settings.show()
    end

    local function closeMenu()
        Settings.hide() Info.hide() Profile.hide() Bar.close()
    end

    if UI.touch then
        -- No hover on touch: the pill toggles the whole stack, and there is
        -- no mouse-leave to close it, so tapping again is the only way out.
        Bar.hit.MouseButton1Click:Connect(function()
            if Bar.mode == "menu" then closeMenu() else openMenu() end
        end)
    else
        Bar.hit.MouseEnter:Connect(openMenu)
    end

    Bar.hit.MouseLeave:Connect(armDismiss)
    Info.clip.MouseLeave:Connect(armDismiss)
    Settings.clip.MouseLeave:Connect(armDismiss)
end

-- Theme switch: fade the mark out, rebuild, fade back in.
function rebuildUI()
    local wasMenu = (Bar.mode == "menu")
    pcall(function()
        if Bar.icon then
            TweenService:Create(Bar.icon, TweenInfo.new(0.16),
                { ImageTransparency = 1 }):Play()
        end
    end)
    task.delay(0.18, function()
        pcall(function() if Info.clockLoop then Info.clockLoop:Disconnect() Info.clockLoop = nil end end)
        pcall(function() if Perf.loop then Perf.loop:Disconnect() Perf.loop = nil end end)
        pcall(function() if Bar.gui then Bar.gui:Destroy() end end)
        Info.open, Perf.open, Settings.open, CmdBar.open = false, false, false, false
        Modal.hide(true)
        Settings.expanded, Info.clip = false, nil
        Badge.frame, Badge.glyph, Badge.wrap, Badge.stroke = nil, nil, nil, nil
        pcall(buildUI)
        Bar.fadeIn()
        if wasMenu then
            task.delay(0.1, function()
                Bar.mode = "menu"
                Notify.showGlyph(nil)
                Notify.showSubIcon(nil)
                Bar.setText("Universal Hub", "Lite V2  -  press T")
                Bar.subLabel.TextColor3 = UI.accent
                Bar.open(false)
                Info.show()
                Settings.show()
            end)
        end
    end)
end

UI.loadConfig()

About.bootAt = os.clock()   -- session length, reported by !info

Splash.play(function()
    buildUI()
    Bar.fadeIn()

    -- Learn the game we are standing in, so it is quickjoinable next time
    -- without anyone editing a table.
    pcall(QuickJoin.learnCurrent)
    pcall(Pos.start)
    pcall(Chat.bind)

    local guided = Guide.maybeShowOnStartup()

    -- Never on top of the first-run guide, and never before the splash has
    -- cleared -- a modal fighting the tour is the bug that took two rounds
    -- to fix last time.
    task.delay(guided and 0 or 1.4, function()
        if guided then return end
        if Modal and Modal.open then return end
        if Tour and Tour.running then return end
        pcall(function() if Resume.should() then Resume.show() end end)
    end)

    task.wait(0.3)
    -- Offer the link rather than hijacking the clipboard unasked.
    Notifications:Info("Universal Hub Lite V2",
        "Loaded  \194\183  press T for commands", 6, {
            { label = "Copy site", icon = "st_copy.png", style = "light",
              run = function()
                  pcall(function() setclipboard("https://angxers2.github.io/Unihub/") end)
                  Notifications:Success("Universal Hub Lite", "Link copied to clipboard", 3)
              end },
            { label = "Ignore", style = "ghost", run = function() end },
        })
end)
