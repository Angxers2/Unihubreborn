-- Universal Hub -- executor diagnostic.
-- Paste this into the executor and send me the output. It changes nothing:
-- every request either reads, or writes a value back to what it already was.
--
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/Angxers2/Unihubreborn/main/tools/diag.lua"))()

local out = {}
local function say(s) out[#out + 1] = s print(s) end

say("=== Universal Hub diagnostic ===")

-- ── who is this ─────────────────────────────────────────────────────────
say("executor: " .. tostring((identifyexecutor and select(1, identifyexecutor())) or "?"))
local UIS = game:GetService("UserInputService")
say("platform: touch=" .. tostring(UIS.TouchEnabled)
    .. " mouse=" .. tostring(UIS.MouseEnabled)
    .. " keyboard=" .. tostring(UIS.KeyboardEnabled))
local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
say("viewport: " .. tostring(vp) .. "  inset: "
    .. tostring(game:GetService("GuiService"):GetGuiInset()))

-- ── where does our UI land ──────────────────────────────────────────────
-- A protected container is further from the game than CoreGui, and that is
-- what decides whether typing into our own boxes is reported as processed.
say("gethui: " .. typeof(gethui))
local host = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui")
say("ui host: " .. tostring(host) .. " (" .. tostring(host.ClassName) .. ")")
say("GetFocusedTextBox: " .. typeof(UIS.GetFocusedTextBox))

-- ── the HTTP question ───────────────────────────────────────────────────
-- Spotify needs PUT for play, pause, volume and like. Some executors send
-- it as something else, and Spotify then refuses every one of them.
local send = (syn and syn.request) or (http and typeof(http) == "table" and http.request)
    or (getgenv and getgenv().request) or request or http_request
say("request(): " .. typeof(send))

if typeof(send) == "function" then
    -- Two independent echo servers, because one of them agreeing with a
    -- theory is not evidence.
    for _, ep in ipairs({ "https://httpbin.org/anything", "https://postman-echo.com/put" }) do
        local ok, r = pcall(send, {
            Url = ep, Method = "PUT",
            Headers = { ["Content-Type"] = "application/json" }, Body = "{}",
        })
        if not ok then
            say("PUT " .. ep .. " -> threw: " .. tostring(r):sub(1, 70))
        else
            local body = tostring((type(r) == "table" and (r.Body or r.body)) or "")
            local saw = body:match('"method"%s*:%s*"(%w+)"')
                     or body:match('"url"%s*:%s*"[^"]*"') and "(no method field)"
            say("PUT " .. ep .. " -> server saw: " .. tostring(saw or body:sub(1, 60)))
        end
    end
end

-- ── and the same question asked of Spotify itself ───────────────────────
-- PUT /me/library with no uris is a 400 from an honest connection and a 405
-- from one that arrived as the wrong method. Nothing is saved either way.
if Spot and Spot.token and Spot.token ~= "" and typeof(send) == "function" then
    local ok, r = pcall(send, {
        Url = "https://api.spotify.com/v1/me/library", Method = "PUT",
        Headers = { Authorization = "Bearer " .. Spot.token,
                    ["Content-Type"] = "application/json" }, Body = "{}",
    })
    local code = ok and type(r) == "table" and (r.StatusCode or r.Status) or "?"
    say("spotify PUT -> " .. tostring(code)
        .. "  (400 = arrives intact, 405 = arrives as the wrong method)")
else
    say("spotify PUT -> skipped (connect Spotify first)")
end

say("=== end ===")
if setclipboard then
    pcall(setclipboard, table.concat(out, "\n"))
    say("(copied to clipboard)")
end
