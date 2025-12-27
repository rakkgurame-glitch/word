local Players = game:GetService("Players")
local LogService = game:GetService("LogService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Configuration
local Config = {
    MinWordLength = 1,
    MaxWordLength = 100,
    AutoTypingEnabled = true,

    TypingProfile = "balanced",

    Profiles = {
        fast     = { MinDelay = 25,  MaxDelay = 55,  PreferMinLen = 3,  PreferMaxLen = 6,  ThinkDelayMin = 200,  ThinkDelayMax = 800  },
        balanced = { MinDelay = 35,  MaxDelay = 75,  PreferMinLen = 4,  PreferMaxLen = 8,  ThinkDelayMin = 400,  ThinkDelayMax = 1200 },
        safe     = { MinDelay = 45,  MaxDelay = 95,  PreferMinLen = 5,  PreferMaxLen = 10, ThinkDelayMin = 600,  ThinkDelayMax = 1600 },
        chaos    = { MinDelay = 20,  MaxDelay = 50,  PreferMinLen = 10, PreferMaxLen = 20, ThinkDelayMin = 100,  ThinkDelayMax = 500  }
    },

    ExtraBackspacesAfterClear = 3,
    PressEnterAfterClear = true,

    GuiPosition = UDim2.new(0.5, -100, 0.02, 0),
    GuiSize = UDim2.new(0, 220, 0, 180),

    PrimarySource = "https://raw.githubusercontent.com/rakkgurame-glitch/word/refs/heads/main/main.txt",
    SecondarySource = "https://raw.githubusercontent.com/rakkgurame-glitch/word/refs/heads/main/second.txt"
}

local PrefixCache = {}
local SecondaryCache = {}
local UsedWords = {}
local PrimaryLoaded = false
local SecondaryLoaded = false
local IsTyping = false
local LastDetectionTime = 0
local DETECTION_COOLDOWN = 0.35

local function SendNotification(text, duration)
    duration = duration or 2
    StarterGui:SetCore("SendNotification", {
        Title = "WordTyper OP++",
        Text = text,
        Duration = duration,
        Icon = "rbxassetid://4483345998"
    })
end

local KeyMap = {
    a = Enum.KeyCode.A, b = Enum.KeyCode.B, c = Enum.KeyCode.C, d = Enum.KeyCode.D,
    e = Enum.KeyCode.E, f = Enum.KeyCode.F, g = Enum.KeyCode.G, h = Enum.KeyCode.H,
    i = Enum.KeyCode.I, j = Enum.KeyCode.J, k = Enum.KeyCode.K, l = Enum.KeyCode.L,
    m = Enum.KeyCode.M, n = Enum.KeyCode.N, o = Enum.KeyCode.O, p = Enum.KeyCode.P,
    q = Enum.KeyCode.Q, r = Enum.KeyCode.R, s = Enum.KeyCode.S, t = Enum.KeyCode.T,
    u = Enum.KeyCode.U, v = Enum.KeyCode.V, w = Enum.KeyCode.W, x = Enum.KeyCode.X,
    y = Enum.KeyCode.Y, z = Enum.KeyCode.Z,
    [" "] = Enum.KeyCode.Space
}

local function TypeWord(prefix, fullWord)
    local profile = Config.Profiles[Config.TypingProfile]
    
    local thinkDelay = math.random(profile.ThinkDelayMin, profile.ThinkDelayMax) / 1000
    task.wait(thinkDelay)

    local vim = VirtualInputManager
    local camera = Workspace.CurrentCamera
    local centerX, centerY = camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2

    for _ = 1, 3 do
        vim:SendMouseButtonEvent(centerX, centerY, 0, true, game, 1)
        task.wait(0.05)
        vim:SendMouseButtonEvent(centerX, centerY, 0, false, game, 1)
        task.wait(0.05)
    end

    local remainingText = fullWord:sub(#prefix + 1)
    local typedCharacterCount = 0

    for i = 1, #remainingText do
        local char = remainingText:sub(i, i):lower()

        if KeyMap[char] then
            vim:SendKeyEvent(true, KeyMap[char], false, game)
            task.wait(math.random(profile.MinDelay, profile.MaxDelay) / 1000)
            vim:SendKeyEvent(false, KeyMap[char], false, game)

            local delay = math.random(profile.MinDelay, profile.MaxDelay)
            if typedCharacterCount > 5 then
                delay = delay * 0.85
            end
            task.wait(delay / 1000)

            typedCharacterCount += 1
        end
    end

    task.wait(math.random(80, 150) / 1000)
    vim:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
    task.wait(0.04)
    vim:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
    task.wait(0.1)

    for _ = 1, typedCharacterCount do
        vim:SendKeyEvent(true, Enum.KeyCode.Backspace, false, game)
        task.wait(math.random(profile.MinDelay, profile.MaxDelay) / 1000)
        vim:SendKeyEvent(false, Enum.KeyCode.Backspace, false, game)
        task.wait(math.random(profile.MinDelay, profile.MaxDelay) / 1000)
    end

    for _ = 1, Config.ExtraBackspacesAfterClear do
        vim:SendKeyEvent(true, Enum.KeyCode.Backspace, false, game)
        task.wait(math.random(25, 45) / 1000)
        vim:SendKeyEvent(false, Enum.KeyCode.Backspace, false, game)
        task.wait(math.random(25, 45) / 1000)
    end

    if Config.PressEnterAfterClear then
        task.wait(0.05)
        vim:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
        task.wait(0.02)
        vim:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
    end

    IsTyping = false
end

local function LoadDictionaryFromURL(url)
    local requestFunc = (syn and syn.request) or (http and http.request) or http_request or request
    if not requestFunc then
        return nil, "HTTP request not available"
    end

    local success, response = pcall(function()
        return requestFunc({
            Url = url,
            Method = "GET"
        })
    end)

    if not success or not response then
        return nil, "Failed to fetch from URL"
    end

    local body = typeof(response) == "table" and response.Body or response
    return body, nil
end

local function ProcessDictionaryText(text, targetCache)
    local wordCount = 0
    
    for line in text:gmatch("[^\r\n]+") do
        local word = line:lower():match("^%s*(.-)%s*$")
        if word and #word >= Config.MinWordLength and #word <= Config.MaxWordLength and word:match("^[a-z]+$") then
            for prefixLen = 1, math.min(4, #word) do
                local prefix = word:sub(1, prefixLen)
                targetCache[prefix] = targetCache[prefix] or {}
                table.insert(targetCache[prefix], word)
            end
            wordCount += 1
        end
    end
    
    return wordCount
end

local function LoadPrimaryDictionary()
    SendNotification("Loading primary source...", 2)
    local body, error = LoadDictionaryFromURL(Config.PrimarySource)
    
    if body then
        local wordCount = ProcessDictionaryText(body, PrefixCache)
        PrimaryLoaded = true
        SendNotification("✓ Primary: " .. wordCount .. " words", 3)
    else
        SendNotification("❌ Primary source failed", 3)
        warn("Primary dictionary error: " .. (error or "Unknown"))
    end
end

local function LoadSecondaryDictionary()
    if SecondaryLoaded then return end
    
    SendNotification("Loading backup source...", 2)
    local body, error = LoadDictionaryFromURL(Config.SecondarySource)
    
    if body then
        local wordCount = ProcessDictionaryText(body, SecondaryCache)
        SecondaryLoaded = true
        SendNotification("✓ Backup: " .. wordCount .. " words", 3)
    else
        SendNotification("❌ Backup source failed", 3)
        warn("Secondary dictionary error: " .. (error or "Unknown"))
    end
end

task.spawn(LoadPrimaryDictionary)

local function SelectWord(prefix)
    local profile = Config.Profiles[Config.TypingProfile]
    
    local pool = PrefixCache[prefix]
    
    if not pool or #pool == 0 then
        if not SecondaryLoaded then
            SendNotification("🔄 Loading backup for: " .. prefix:upper(), 2)
            LoadSecondaryDictionary()
        end
        
        pool = SecondaryCache[prefix]
        
        if not pool or #pool == 0 then
            SendNotification("❌ Prefix not found: " .. prefix:upper(), 3)
            return nil
        end
        
        SendNotification("✓ Using backup for: " .. prefix:upper(), 2)
    end
    
    UsedWords[prefix] = UsedWords[prefix] or {}
    
    -- First try: preferred length only
    local preferredWords = {}
    for _, word in ipairs(pool) do
        local wordLength = #word
        if not UsedWords[prefix][word] and wordLength >= profile.PreferMinLen and wordLength <= profile.PreferMaxLen then
            table.insert(preferredWords, word)
        end
    end
    
    -- Second try: all available words (1-100 chars)
    local allAvailable = {}
    if #preferredWords == 0 then
        for _, word in ipairs(pool) do
            if not UsedWords[prefix][word] then
                table.insert(allAvailable, word)
            end
        end
    end
    
    -- Use preferred if available, otherwise use any available
    local available = #preferredWords > 0 and preferredWords or allAvailable

    if #available == 0 then
        SendNotification("⚠ All words used for: " .. prefix:upper() .. " (Reset needed)", 3)
        return nil
    end

    -- Scoring system
    local idealMinLength = #prefix + profile.PreferMinLen
    local idealMaxLength = #prefix + profile.PreferMaxLen
    local idealLength = math.random(idealMinLength, idealMaxLength)
    
    local scored = {}

    for _, word in ipairs(available) do
        local score = 100 - math.abs(#word - idealLength)
        -- Bonus for preferred length range
        if #word >= profile.PreferMinLen and #word <= profile.PreferMaxLen then
            score = score + 100  -- High bonus for preferred length
        end
        table.insert(scored, { Word = word, Score = score })
    end

    table.sort(scored, function(a, b) return a.Score > b.Score end)

    local topCount = math.max(1, math.floor(#scored * 0.3))
    local chosen = scored[math.random(1, topCount)].Word
    UsedWords[prefix][chosen] = true

    return chosen
end

LogService.MessageOut:Connect(function(message)
    if not Config.AutoTypingEnabled or IsTyping then return end
    if tick() - LastDetectionTime < DETECTION_COOLDOWN then return end

    local prefix = message:match("Word:%s*([A-Z]+)")
    if prefix then
        LastDetectionTime = tick()
        prefix = prefix:lower()

        local word = SelectWord(prefix)
        if not word then
            SendNotification("✗ No available words for: " .. prefix:upper(), 3)
            return
        end

        IsTyping = true
        task.spawn(TypeWord, prefix, word)
    end
end)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "WordTyperGUI"
ScreenGui.Parent = PlayerGui
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local MainFrame = Instance.new("Frame")
MainFrame.Size = Config.GuiSize
MainFrame.Position = Config.GuiPosition
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
MainFrame.BackgroundTransparency = 0.1
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 12)
Corner.Parent = MainFrame

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(80, 120, 200)
Stroke.Thickness = 2
Stroke.Parent = MainFrame

local Shadow = Instance.new("ImageLabel")
Shadow.Size = UDim2.new(1, 10, 1, 10)
Shadow.Position = UDim2.new(0, -5, 0, -5)
Shadow.BackgroundTransparency = 1
Shadow.Image = "rbxassetid://5554236805"
Shadow.ImageColor3 = Color3.new(0, 0, 0)
Shadow.ImageTransparency = 0.7
Shadow.ScaleType = Enum.ScaleType.Slice
Shadow.SliceCenter = Rect.new(10, 10, 118, 118)
Shadow.ZIndex = -1
Shadow.Parent = MainFrame

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 35)
Header.BackgroundColor3 = Color3.fromRGB(40, 60, 150)
Header.BorderSizePixel = 0
Header.Parent = MainFrame

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 12)
HeaderCorner.Parent = Header

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -40, 1, 0)
TitleLabel.Position = UDim2.new(0, 10, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "⚡ WORD TYPER OP++"
TitleLabel.TextColor3 = Color3.new(1, 1, 1)
TitleLabel.TextSize = 16
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = Header

local CloseButton = Instance.new("TextButton")
CloseButton.Size = UDim2.new(0, 35, 1, 0)
CloseButton.Position = UDim2.new(1, -35, 0, 0)
CloseButton.BackgroundTransparency = 1
CloseButton.Text = "×"
CloseButton.TextColor3 = Color3.new(1, 1, 1)
CloseButton.TextSize = 24
CloseButton.Font = Enum.Font.GothamBold
CloseButton.Parent = Header

local ContentFrame = Instance.new("Frame")
ContentFrame.Size = UDim2.new(1, -20, 1, -55)
ContentFrame.Position = UDim2.new(0, 10, 0, 45)
ContentFrame.BackgroundTransparency = 1
ContentFrame.Parent = MainFrame

local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(1, 0, 0, 40)
ToggleButton.BackgroundColor3 = Color3.fromRGB(40, 180, 100)
ToggleButton.Text = "🎯 AUTO: ON"
ToggleButton.TextColor3 = Color3.new(1, 1, 1)
ToggleButton.TextSize = 16
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.AutoButtonColor = false
ToggleButton.Parent = ContentFrame

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 10)
ToggleCorner.Parent = ToggleButton

local ResetButton = Instance.new("TextButton")
ResetButton.Size = UDim2.new(0.48, -5, 0, 35)
ResetButton.Position = UDim2.new(0, 0, 0, 50)
ResetButton.BackgroundColor3 = Color3.fromRGB(220, 80, 80)
ResetButton.Text = "♻ RESET POOL"
ResetButton.TextColor3 = Color3.new(1, 1, 1)
ResetButton.TextSize = 14
ResetButton.Font = Enum.Font.GothamBold
ResetButton.AutoButtonColor = false
ResetButton.Parent = ContentFrame

local ResetCorner = Instance.new("UICorner")
ResetCorner.CornerRadius = UDim.new(0, 8)
ResetCorner.Parent = ResetButton

local ProfileButton = Instance.new("TextButton")
ProfileButton.Size = UDim2.new(0.48, -5, 0, 35)
ProfileButton.Position = UDim2.new(0.52, 5, 0, 50)
ProfileButton.BackgroundColor3 = Color3.fromRGB(100, 120, 220)
ProfileButton.Text = "⚖️ BALANCED"
ProfileButton.TextColor3 = Color3.new(1, 1, 1)
ProfileButton.TextSize = 14
ProfileButton.Font = Enum.Font.GothamBold
ProfileButton.AutoButtonColor = false
ProfileButton.Parent = ContentFrame

local ProfileCorner = Instance.new("UICorner")
ProfileCorner.CornerRadius = UDim.new(0, 8)
ProfileCorner.Parent = ProfileButton

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, 0, 0, 25)
StatusLabel.Position = UDim2.new(0, 0, 0, 95)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Ready | Primary: No | Backup: No"
StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
StatusLabel.TextSize = 11
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = ContentFrame

local ProfileInfoLabel = Instance.new("TextLabel")
ProfileInfoLabel.Size = UDim2.new(1, 0, 0, 20)
ProfileInfoLabel.Position = UDim2.new(0, 0, 0, 120)
ProfileInfoLabel.BackgroundTransparency = 1
ProfileInfoLabel.Text = "Prefer: 4-8 | Speed: 35-75ms"
ProfileInfoLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
ProfileInfoLabel.TextSize = 10
ProfileInfoLabel.Font = Enum.Font.Gotham
ProfileInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
ProfileInfoLabel.Parent = ContentFrame

local function AddHoverEffect(button, normal, hover)
    button.MouseEnter:Connect(function() button.BackgroundColor3 = hover end)
    button.MouseLeave:Connect(function() button.BackgroundColor3 = normal end)
end

AddHoverEffect(ToggleButton, Color3.fromRGB(40, 180, 100), Color3.fromRGB(60, 220, 120))
AddHoverEffect(ResetButton, Color3.fromRGB(220, 80, 80), Color3.fromRGB(240, 100, 100))
AddHoverEffect(ProfileButton, Color3.fromRGB(100, 120, 220), Color3.fromRGB(120, 140, 240))

local function UpdateProfileInfo()
    local profile = Config.Profiles[Config.TypingProfile]
    ProfileInfoLabel.Text = string.format(
        "Prefer: %d-%d | Speed: %d-%dms",
        profile.PreferMinLen,
        profile.PreferMaxLen,
        profile.MinDelay,
        profile.MaxDelay
    )
end

ToggleButton.MouseButton1Click:Connect(function()
    Config.AutoTypingEnabled = not Config.AutoTypingEnabled
    if Config.AutoTypingEnabled then
        ToggleButton.Text = "🎯 AUTO: ON"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(40, 180, 100)
        SendNotification("Auto-typing ENABLED")
    else
        ToggleButton.Text = "⭕ AUTO: OFF"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(120, 120, 120)
        SendNotification("Auto-typing DISABLED")
    end
end)

ResetButton.MouseButton1Click:Connect(function()
    UsedWords = {}
    SendNotification("✓ All word pools RESET (Manual)", 2)
end)

ProfileButton.MouseButton1Click:Connect(function()
    local profiles = {"fast", "balanced", "safe", "chaos"}
    local current = table.find(profiles, Config.TypingProfile) or 2
    local nextIndex = (current % #profiles) + 1
    Config.TypingProfile = profiles[nextIndex]
    
    local profileEmojis = {
        fast = "⚡",
        balanced = "⚖️",
        safe = "🛡️",
        chaos = "💥"
    }
    
    ProfileButton.Text = (profileEmojis[Config.TypingProfile] or "⚡") .. " " .. Config.TypingProfile:upper()
    UpdateProfileInfo()
    SendNotification("Profile: " .. Config.TypingProfile:upper())
end)

CloseButton.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
    CloseButton.Text = MainFrame.Visible and "×" or "⚙"
end)

task.spawn(function()
    while task.wait(2) do
        StatusLabel.Text = string.format(
            "%s | P:%s | B:%s",
            Config.AutoTypingEnabled and "ACTIVE" or "PAUSED",
            PrimaryLoaded and "✓" or "✗",
            SecondaryLoaded and "✓" or "✗"
        )
    end
end)

UpdateProfileInfo()

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.T and UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) then
        ToggleButton.MouseButton1Click:Fire()
    end
end)

print("=====================================")
print("✅ WORD TYPER OP++ LOADED")
print("🎯 Profile: " .. Config.TypingProfile)
print("📝 Shortcut: Alt+T")
print("🧠 Think Delay: ENABLED")
print("📏 Dictionary: 1-100 chars (prefer filtered)")
print("=====================================")
SendNotification("Word Typer Loaded! Alt+T", 4)
