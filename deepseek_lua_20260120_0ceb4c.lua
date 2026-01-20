[file content begin]
local Http = game:GetService("HttpService")
local TPS = game:GetService("TeleportService")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

while not Players.LocalPlayer do task.wait() end
local player = Players.LocalPlayer
local ALLOWED_PLACE_ID = 109983668079237
local RETRY_DELAY = 0.1
local SETTINGS_FILE = "VorteXFinderSettings.json"
local GUI_STATE_FILE = "VorteXFinderGUIState.json"
local API_STATE_FILE = "VorteXFinderAPIState.json"

local settings = {
    minGeneration = 40000000,
    targetNames = {},
    blacklistNames = {},
    targetRarity = "",
    targetMutation = "",
    minPlayers = 2,
    sortOrder = "Desc",
    autoStart = false,  -- DESACTIVADO por defecto
    customSoundId = "rbxassetid://9167433166",
    hopCount = 0,
    recentVisited = {},
    notificationDuration = 4,
    autoJoin = false  -- DESACTIVADO por defecto
}

local guiState = {
    isMinimized = false,
    position = {
        XScale = 0.5,
        XOffset = -125,
        YScale = 0.6,
        YOffset = -150
    }
}

local apiState = {
    mainApiUses = 0,
    cachedServers = {},
    lastCacheUpdate = 0,
    useCachedServers = false
}

local isRunning = false
local currentConnection = nil
local foundPodiumsData = {}
local monitoringConnection = nil
local autoHopping = false
local hopConnection = nil
local lastHopTime = 0
local optionGui = nil
local pendingJoinTarget = nil
local joinOptionsShown = false

-- Tema morado oscuro mejorado
local THEME = {
    Background = Color3.fromRGB(10, 5, 20),
    Header = Color3.fromRGB(20, 10, 35),
    Accent = Color3.fromRGB(170, 60, 255),
    Text = Color3.fromRGB(245, 235, 255),
    Button = Color3.fromRGB(35, 20, 55),
    ButtonHover = Color3.fromRGB(55, 35, 80),
    Input = Color3.fromRGB(15, 10, 25),
    Success = Color3.fromRGB(80, 255, 80),
    Error = Color3.fromRGB(255, 70, 70),
    Warning = Color3.fromRGB(255, 180, 70),
    JoinButton = Color3.fromRGB(60, 180, 60),
    ForceJoinButton = Color3.fromRGB(255, 140, 50)
}

local mutationColors = {
    Gold = Color3.fromRGB(255, 215, 0),
    Diamond = Color3.fromRGB(0, 255, 255),
    Lava = Color3.fromRGB(255, 100, 0),
    Bloodrot = Color3.fromRGB(255, 0, 0),
    Candy = Color3.fromRGB(255, 182, 193),
    Rainbow = Color3.fromRGB(255, 255, 255),
    Normal = Color3.fromRGB(255, 255, 255),
    Default = Color3.fromRGB(255, 255, 255)
}

local cachedPlots = nil
local cachedPodiums = nil
local lastPodiumCheck = 0
local PODIUM_CACHE_DURATION = 1

-- Función para mostrar notificaciones mejorada
local function showNotification(title, text, duration)
    duration = duration or settings.notificationDuration
    StarterGui:SetCore("SendNotification", {
        Title = title,
        Text = text,
        Duration = duration,
        Icon = "rbxassetid://6031302931"
    })
end

local function logMessage(message, color)
    color = color or THEME.Text
    local timestamp = os.date("[%H:%M:%S]")
    print(timestamp .. " [VorteX] " .. message)
end

local function checkAPIAvailability()
    local mainAPI = "https://games.roblox.com/v1/games/" .. ALLOWED_PLACE_ID .. "/servers/Public?sortOrder=" .. settings.sortOrder .. "&limit=100&excludeFullGames=true"
    local success, response = pcall(function() 
        return game:HttpGet(mainAPI)
    end)
    return success and response ~= "" and response ~= nil
end

local function saveSettings()
    local success, error = pcall(function()
        writefile(SETTINGS_FILE, Http:JSONEncode(settings))
    end)
    if not success then
        logMessage("Failed to save settings: " .. tostring(error), THEME.Error)
    else
        logMessage("Settings saved successfully", THEME.Success)
    end
end

local function loadSettings()
    local success, data = pcall(function()
        if isfile(SETTINGS_FILE) then
            return readfile(SETTINGS_FILE)
        end
        return nil
    end)
    if success and data then
        local loadedSettings = Http:JSONDecode(data)
        for key, value in pairs(loadedSettings) do
            if settings[key] ~= nil then
                settings[key] = value
            end
        end
        logMessage("Settings loaded", THEME.Success)
    end
end

local function saveGUIState()
    local success, error = pcall(function()
        writefile(GUI_STATE_FILE, Http:JSONEncode(guiState))
    end)
    if not success then
        logMessage("Failed to save GUI state: " .. tostring(error), THEME.Error)
    end
end

local function loadGUIState()
    local success, data = pcall(function()
        if isfile(GUI_STATE_FILE) then
            return readfile(GUI_STATE_FILE)
        end
        return nil
    end)
    if success and data then
        local loadedState = Http:JSONDecode(data)
        for key, value in pairs(loadedState) do
            if guiState[key] ~= nil then
                guiState[key] = value
            end
        end
    end
end

local function saveAPIState()
    local success, error = pcall(function()
        writefile(API_STATE_FILE, Http:JSONEncode(apiState))
    end)
    if not success then
        logMessage("Failed to save API state: " .. tostring(error), THEME.Error)
    end
end

local function loadAPIState()
    local success, data = pcall(function()
        if isfile(API_STATE_FILE) then
            return readfile(API_STATE_FILE)
        end
        return nil
    end)
    if success and data then
        local loadedState = Http:JSONDecode(data)
        for key, value in pairs(loadedState) do
            if apiState[key] ~= nil then
                apiState[key] = value
            end
        end
    end
end

local function playFoundSound()
    local sound = Instance.new("Sound")
    sound.SoundId = settings.customSoundId
    sound.Volume = 1
    sound.PlayOnRemove = true
    sound.Parent = workspace
    sound:Destroy()
end

local function extractNumber(str)
    if not str then return 0 end
    local numberStr = str:match("%$(.-)/s")
    if not numberStr then return 0 end
    numberStr = numberStr:gsub("%s", "")
    local multiplier = 1
    if numberStr:lower():find("k") then
        multiplier = 1000
        numberStr = numberStr:gsub("[kK]", "")
    elseif numberStr:lower():find("m") then
        multiplier = 1000000
        numberStr = numberStr:gsub("[mM]", "")
    elseif numberStr:lower():find("b") then
        multiplier = 1000000000
        numberStr = numberStr:gsub("[bB]", "")
    end
    return (tonumber(numberStr) or 0) * multiplier
end

local function getMutationTextAndColor(mutation)
    if not mutation or mutation.Visible == false then
        return "Normal", Color3.fromRGB(255, 255, 255), false
    end
    local name = mutation.Text
    if name == "" then
        return "Normal", Color3.fromRGB(255, 255, 255), false
    end
    if name == "Rainbow" then
        return "Rainbow", Color3.new(1, 1, 1), true
    end
    local color = mutationColors[name] or Color3.fromRGB(255, 255, 255)
    return name, color, false
end

local function isPlayerBase(plot)
    local sign = plot:FindFirstChild("PlotSign")
    if sign then
        local yourBase = sign:FindFirstChild("YourBase")
        if yourBase and yourBase.Enabled then
            return true
        end
    end
    return false
end

local function getAllPodiums()
    if cachedPodiums and tick() - lastPodiumCheck < PODIUM_CACHE_DURATION then
        return cachedPodiums
    end
    
    local podiums = {}
    
    if not cachedPlots then
        cachedPlots = Workspace:FindFirstChild("Plots")
        if not cachedPlots then
            cachedPlots = Workspace:FindFirstChild("PlotFolder") or Workspace:FindFirstChild("PlotsFolder")
        end
    end
    
    if not cachedPlots then 
        lastPodiumCheck = tick()
        cachedPodiums = podiums
        return podiums 
    end
    
    local plotChildren = cachedPlots:GetChildren()
    
    for i = 1, #plotChildren do
        local plot = plotChildren[i]
        
        if not isPlayerBase(plot) then
            local animalPods = plot:FindFirstChild("AnimalPodiums")
            if animalPods then
                local podChildren = animalPods:GetChildren()
                for j = 1, #podChildren do
                    local pod = podChildren[j]
                    local base = pod:FindFirstChild("Base")
                    if base then
                        local spawn = base:FindFirstChild("Spawn")
                        if spawn then
                            local attach = spawn:FindFirstChild("Attachment")
                            if attach then
                                local animalOverhead = attach:FindFirstChild("AnimalOverhead")
                                if animalOverhead and (base:IsA("BasePart") or base:IsA("Model")) then
                                    table.insert(podiums, { 
                                        overhead = animalOverhead, 
                                        base = base,
                                        pod = pod,
                                        plot = plot
                                    })
                                end
                            end
                        end
                    end
                end
            end
            
            if plot:IsA("Model") then
                for _, model in pairs(plot:GetChildren()) do
                    if model:IsA("Model") then
                        for _, obj in pairs(model:GetDescendants()) do
                            if obj:IsA("Attachment") and obj.Name == "OVERHEAD_ATTACHMENT" then
                                local overhead = obj:FindFirstChild("AnimalOverhead")
                                if overhead then
                                    local base = model:FindFirstChild("Base") or model
                                    if base and (base:IsA("BasePart") or base:IsA("Model")) then
                                        table.insert(podiums, { 
                                            overhead = overhead, 
                                            base = base,
                                            pod = model,
                                            plot = plot
                                        })
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    lastPodiumCheck = tick()
    cachedPodiums = podiums
    return podiums
end

local function getPrimaryPartPosition(obj)
    if not obj then return nil end
    if obj:IsA("Model") and obj.PrimaryPart then
        return obj.PrimaryPart.Position
    elseif obj:IsA("BasePart") then
        return obj.Position
    end
    return nil
end

local function getServersFromAPI(baseUrl, isMainAPI)
    local servers = {}
    local cursor = ""
    local maxPages = 3
    
    if isMainAPI then
        apiState.mainApiUses = apiState.mainApiUses + 1
        saveAPIState()
    end
    
    for page = 1, maxPages do
        local url = baseUrl
        if cursor ~= "" then url = url .. "&cursor=" .. cursor end
        
        local success, response = pcall(function() 
            return game:HttpGet(url)
        end)
        if not success then 
            logMessage("API request failed on page " .. page, THEME.Error)
            break 
        end
        
        local successDecode, body = pcall(function()
            return Http:JSONDecode(response)
        end)
        
        if not successDecode or not body or not body.data then 
            logMessage("Failed to decode API response", THEME.Error)
            break 
        end
        
        for _, v in ipairs(body.data) do
            if v.playing and v.maxPlayers and v.playing >= settings.minPlayers and v.playing < v.maxPlayers and v.id ~= game.JobId and not table.find(settings.recentVisited, v.id) then
                table.insert(servers, v.id)
                if not table.find(apiState.cachedServers, v.id) then
                    table.insert(apiState.cachedServers, v.id)
                end
            end
        end
        
        cursor = body.nextPageCursor or ""
        if cursor == "" then break end
    end
    
    while #apiState.cachedServers > 300 do
        table.remove(apiState.cachedServers, 1)
    end
    
    apiState.lastCacheUpdate = tick()
    saveAPIState()
    return servers
end

local function getCachedServers()
    local availableServers = {}
    local recentCount = math.min(#settings.recentVisited, 5)
    local recentServers = {}
    
    for i = #settings.recentVisited - recentCount + 1, #settings.recentVisited do
        if settings.recentVisited[i] then
            table.insert(recentServers, settings.recentVisited[i])
        end
    end
    
    for _, serverId in ipairs(apiState.cachedServers) do
        if not table.find(recentServers, serverId) and serverId ~= game.JobId then
            table.insert(availableServers, serverId)
        end
    end
    
    return availableServers
end

local function isStolenPodium(overhead)
    if not overhead then return false end
    local stolenLabel = overhead:FindFirstChild("Stolen")
    if stolenLabel and stolenLabel:IsA("TextLabel") then
        return string.upper(stolenLabel.Text) == "FUSING" or string.upper(stolenLabel.Text) == "STOLEN"
    end
    return false
end

local function getAvailableServers()
    if apiState.mainApiUses >= 3 or apiState.useCachedServers then
        if not checkAPIAvailability() then
            apiState.useCachedServers = true
            saveAPIState()
            local cached = getCachedServers()
            if #cached > 0 then
                logMessage("Using cached servers: " .. #cached .. " available", THEME.Warning)
                return cached
            else
                logMessage("No cached servers available", THEME.Error)
                return {}
            end
        else
            apiState.useCachedServers = false
            apiState.mainApiUses = 0
            saveAPIState()
        end
    end
    
    local mainAPI = "https://games.roblox.com/v1/games/" .. ALLOWED_PLACE_ID .. "/servers/Public?sortOrder=" .. settings.sortOrder .. "&limit=100&excludeFullGames=true"
    local servers = getServersFromAPI(mainAPI, true)
    
    if #servers > 0 then 
        logMessage("Got " .. #servers .. " servers from API", THEME.Success)
        return servers 
    end
    
    logMessage("No servers from API, falling back to cache", THEME.Warning)
    apiState.useCachedServers = true
    saveAPIState()
    return getCachedServers()
end

-- FUNCIÓN CORREGIDA: Ahora verifica correctamente todos los filtros
local function matchesFilters(labels, overhead)
    if isStolenPodium(overhead) then
        return false
    end
    
    local genValue = extractNumber(labels.Generation)
    
    -- Verifica blacklist primero
    if #settings.blacklistNames > 0 then
        for i = 1, #settings.blacklistNames do
            local name = settings.blacklistNames[i]
            if name ~= "" and string.find(string.lower(labels.DisplayName), string.lower(name)) then
                return false
            end
        end
    end
    
    -- Si hay target names, verifica si coincide con alguno
    local nameMatches = false
    if #settings.targetNames > 0 then
        for i = 1, #settings.targetNames do
            local name = settings.targetNames[i]
            if name ~= "" and string.find(string.lower(labels.DisplayName), string.lower(name)) then
                nameMatches = true
                break
            end
        end
        -- Si hay target names especificados pero ninguno coincide, rechaza
        if not nameMatches then
            return false
        end
    end
    
    -- Verifica generación mínima (si no hay target names específicos o si hay pero igual debe cumplir generación)
    if settings.minGeneration > 0 and genValue < settings.minGeneration then
        -- Solo rechaza por generación si NO hay target names que coincidan
        -- Si hay target names que coinciden, se acepta independientemente de la generación
        if #settings.targetNames == 0 or not nameMatches then
            return false
        end
    end
    
    -- Verifica rareza
    if settings.targetRarity ~= "" then
        if string.lower(labels.Rarity) ~= string.lower(settings.targetRarity) then
            return false
        end
    end
    
    -- Verifica mutación
    if settings.targetMutation ~= "" then
        if string.lower(labels.Mutation) ~= string.lower(settings.targetMutation) then
            return false
        end
    end
    
    return true
end

local function checkPodiumsForWebhooksAndFilters()
    if game.PlaceId ~= ALLOWED_PLACE_ID then
        return false, {}
    end
    
    local podiums = getAllPodiums()
    local filteredPodiums = {}
    local highestValue = 0
    local highestValueName = ""
    
    for i = 1, #podiums do
        local podium = podiums[i]
        
        if isStolenPodium(podium.overhead) then
            continue
        end
        
        local displayNameLabel = podium.overhead:FindFirstChild("DisplayName")
        local genLabel = podium.overhead:FindFirstChild("Generation")
        local rarityLabel = podium.overhead:FindFirstChild("Rarity")
        
        if displayNameLabel and genLabel and rarityLabel then
            local mutation = podium.overhead:FindFirstChild("Mutation")
            local mutText, _, _ = getMutationTextAndColor(mutation)
            
            local genValue = extractNumber(genLabel.Text)
            
            local labels = {
                DisplayName = displayNameLabel.Text,
                Generation = genLabel.Text,
                Mutation = mutText,
                Rarity = rarityLabel.Text
            }
            
            if matchesFilters(labels, podium.overhead) then
                table.insert(filteredPodiums, { 
                    base = podium.base, 
                    labels = labels, 
                    overhead = podium.overhead,
                    pod = podium.pod,
                    plot = podium.plot
                })
                
                -- Track highest value found
                if genValue > highestValue then
                    highestValue = genValue
                    highestValueName = displayNameLabel.Text
                end
            end
        end
    end
    
    return #filteredPodiums > 0, filteredPodiums, highestValue, highestValueName
end

local function formatGeneration(genStr)
    local genValue = extractNumber(genStr)
    if genValue >= 1000000000 then
        return string.format("%.1fB", genValue / 1000000000)
    elseif genValue >= 1000000 then
        return string.format("%.1fM", genValue / 1000000)
    elseif genValue >= 1000 then
        return string.format("%.1fK", genValue / 1000)
    else
        return tostring(genValue)
    end
end

local function showJoinOptions(podiumsData)
    -- Verificar si ya se mostró el panel
    if joinOptionsShown then
        return
    end
    
    joinOptionsShown = true
    
    -- Detener cualquier hopping activo
    if isRunning then
        isRunning = false
        if hopConnection then
            task.cancel(hopConnection)
            hopConnection = nil
        end
    end
    
    -- Destruir GUI anterior si existe
    if optionGui then
        optionGui:Destroy()
        optionGui = nil
    end
    
    local playerGui = player:WaitForChild("PlayerGui")
    
    optionGui = Instance.new("ScreenGui")
    optionGui.Name = "VorteXJoinOptions"
    optionGui.ResetOnSpawn = false
    optionGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    optionGui.DisplayOrder = 999
    optionGui.Parent = playerGui
    
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 400, 0, 280)
    mainFrame.Position = UDim2.new(0.5, -200, 0.5, -140)
    mainFrame.BackgroundColor3 = THEME.Background
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = optionGui
    
    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 10)
    mainCorner.Parent = mainFrame
    
    local mainStroke = Instance.new("UIStroke")
    mainStroke.Thickness = 2
    mainStroke.Color = THEME.Accent
    mainStroke.Parent = mainFrame
    
    -- Fondo oscuro
    local background = Instance.new("Frame")
    background.Size = UDim2.new(1, 0, 1, 0)
    background.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    background.BackgroundTransparency = 0.3
    background.BorderSizePixel = 0
    background.ZIndex = -1
    background.Parent = mainFrame
    
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -20, 0, 50)
    titleLabel.Position = UDim2.new(0, 10, 0, 10)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "🎯 TARGET FOUND!"
    titleLabel.TextColor3 = THEME.Accent
    titleLabel.TextSize = 22
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Center
    titleLabel.Parent = mainFrame
    
    local displayResults = {}
    for _, entry in ipairs(podiumsData) do
        local genValue = extractNumber(entry.labels.Generation)
        table.insert(displayResults, {entry = entry, gen = genValue})
    end
    table.sort(displayResults, function(a, b) return a.gen > b.gen end)
    
    -- Mostrar detalles de los encontrados
    local detailsText = ""
    for i = 1, math.min(3, #displayResults) do
        local entry = displayResults[i].entry
        local genFormatted = formatGeneration(entry.labels.Generation)
        detailsText = detailsText .. string.format("• %s\n  Valor: $%s/s\n  Mutación: %s\n  Rareza: %s\n\n", 
            entry.labels.DisplayName, 
            genFormatted, 
            entry.labels.Mutation, 
            entry.labels.Rarity)
    end
    
    local descLabel = Instance.new("TextLabel")
    descLabel.Size = UDim2.new(1, -30, 0, 140)
    descLabel.Position = UDim2.new(0, 15, 0, 60)
    descLabel.BackgroundTransparency = 1
    descLabel.Text = detailsText
    descLabel.TextColor3 = THEME.Text
    descLabel.TextSize = 14
    descLabel.Font = Enum.Font.Gotham
    descLabel.TextXAlignment = Enum.TextXAlignment.Left
    descLabel.TextWrapped = true
    descLabel.Parent = mainFrame
    
    local buttonContainer = Instance.new("Frame")
    buttonContainer.Size = UDim2.new(1, -30, 0, 50)
    buttonContainer.Position = UDim2.new(0, 15, 1, -70)
    buttonContainer.BackgroundTransparency = 1
    buttonContainer.Parent = mainFrame
    
    local joinButton = Instance.new("TextButton")
    joinButton.Size = UDim2.new(0.45, 0, 1, 0)
    joinButton.BackgroundColor3 = THEME.JoinButton
    joinButton.BorderSizePixel = 0
    joinButton.Text = "STAY HERE"
    joinButton.TextColor3 = THEME.Text
    joinButton.TextSize = 16
    joinButton.Font = Enum.Font.GothamBold
    joinButton.Parent = buttonContainer
    
    local joinCorner = Instance.new("UICorner")
    joinCorner.CornerRadius = UDim.new(0, 8)
    joinCorner.Parent = joinButton
    
    local forceJoinButton = Instance.new("TextButton")
    forceJoinButton.Size = UDim2.new(0.45, 0, 1, 0)
    forceJoinButton.Position = UDim2.new(0.55, 0, 0, 0)
    forceJoinButton.BackgroundColor3 = THEME.ForceJoinButton
    forceJoinButton.BorderSizePixel = 0
    forceJoinButton.Text = "REJOIN SERVER"
    forceJoinButton.TextColor3 = THEME.Text
    forceJoinButton.TextSize = 14
    forceJoinButton.Font = Enum.Font.GothamBold
    forceJoinButton.Parent = buttonContainer
    
    local forceJoinCorner = Instance.new("UICorner")
    forceJoinCorner.CornerRadius = UDim.new(0, 8)
    forceJoinCorner.Parent = forceJoinButton
    
    local continueButton = Instance.new("TextButton")
    continueButton.Size = UDim2.new(1, 0, 0, 30)
    continueButton.Position = UDim2.new(0, 0, 1, -120)
    continueButton.BackgroundColor3 = THEME.Button
    continueButton.BorderSizePixel = 0
    continueButton.Text = "CONTINUE SEARCHING"
    continueButton.TextColor3 = THEME.Text
    continueButton.TextSize = 12
    continueButton.Font = Enum.Font.Gotham
    continueButton.Parent = mainFrame
    
    local continueCorner = Instance.new("UICorner")
    continueCorner.CornerRadius = UDim.new(0, 6)
    continueCorner.Parent = continueButton
    
    local closeButton = Instance.new("TextButton")
    closeButton.Size = UDim2.new(0, 35, 0, 35)
    closeButton.Position = UDim2.new(1, -40, 0, 5)
    closeButton.BackgroundColor3 = THEME.Error
    closeButton.BorderSizePixel = 0
    closeButton.Text = "X"
    closeButton.TextColor3 = THEME.Text
    closeButton.TextSize = 16
    closeButton.Font = Enum.Font.GothamBold
    closeButton.Parent = mainFrame
    
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 6)
    closeCorner.Parent = closeButton
    
    -- Efectos hover
    local function addButtonHover(button, hoverColor, originalColor)
        button.MouseEnter:Connect(function()
            TweenService:Create(button, TweenInfo.new(0.2), {BackgroundColor3 = hoverColor}):Play()
        end)
        button.MouseLeave:Connect(function()
            TweenService:Create(button, TweenInfo.new(0.2), {BackgroundColor3 = originalColor}):Play()
        end)
    end
    
    addButtonHover(joinButton, Color3.fromRGB(80, 200, 80), THEME.JoinButton)
    addButtonHover(forceJoinButton, Color3.fromRGB(255, 160, 70), THEME.ForceJoinButton)
    addButtonHover(continueButton, THEME.ButtonHover, THEME.Button)
    addButtonHover(closeButton, Color3.fromRGB(255, 90, 90), THEME.Error)
    
    -- Funciones de los botones
    joinButton.MouseButton1Click:Connect(function()
        logMessage("User chose to stay in current server", THEME.Success)
        if optionGui then
            optionGui:Destroy()
            optionGui = nil
        end
        joinOptionsShown = false
        showNotification("Decision", "Staying in current server with target(s)", 3)
    end)
    
    forceJoinButton.MouseButton1Click:Connect(function()
        logMessage("Force rejoin clicked", THEME.Success)
        if optionGui then
            optionGui:Destroy()
            optionGui = nil
        end
        joinOptionsShown = false
        showNotification("Rejoining", "Attempting to rejoin server...", 2)
        task.wait(1)
        TPS:TeleportToPlaceInstance(ALLOWED_PLACE_ID, game.JobId)
    end)
    
    continueButton.MouseButton1Click:Connect(function()
        logMessage("User chose to continue searching", THEME.Warning)
        if optionGui then
            optionGui:Destroy()
            optionGui = nil
        end
        joinOptionsShown = false
        
        -- Reanudar la búsqueda después de 2 segundos
        task.wait(2)
        
        isRunning = true
        foundPodiumsData = {}
        
        hopConnection = task.spawn(function()
            while isRunning do
                runServerCheck()
                if #foundPodiumsData > 0 then
                    break
                end
                task.wait(0.5)
            end
        end)
        
        showNotification("Resuming", "Continuing search for better targets", 3)
    end)
    
    closeButton.MouseButton1Click:Connect(function()
        logMessage("Join options closed by user", THEME.Warning)
        if optionGui then
            optionGui:Destroy()
            optionGui = nil
        end
        joinOptionsShown = false
    end)
    
    -- Auto-cerrar después de 30 segundos si no se selecciona nada
    task.spawn(function()
        task.wait(30)
        if optionGui and optionGui.Parent then
            logMessage("Auto-closing join options after 30 seconds", THEME.Warning)
            optionGui:Destroy()
            optionGui = nil
            joinOptionsShown = false
        end
    end)
end

local function tryTeleportWithRetries()
    if not isRunning then
        return false
    end

    local attempts = 0
    local maxAttempts = 8
    local servers = getAvailableServers()
    
    if #servers == 0 then
        showNotification("No Servers", "No available servers found.", 2)
        return false
    end
    
    showNotification("Hopping", "Hop #" .. settings.hopCount, 2)
    logMessage("Starting hop #" .. settings.hopCount, THEME.Text)
    
    while attempts < maxAttempts and isRunning do
        if #servers == 0 then
            servers = getAvailableServers()
            if #servers == 0 then
                task.wait(RETRY_DELAY * 2)
                attempts = attempts + 1
                continue
            end
        end
        
        local randomServer = servers[math.random(1, #servers)]
        
        showNotification("Teleporting", "Joining server " .. string.sub(randomServer, 1, 8) .. "...", 2)
        logMessage("Attempting teleport to server: " .. randomServer, THEME.Text)
        
        local success, err = pcall(function()
            TPS:TeleportToPlaceInstance(ALLOWED_PLACE_ID, randomServer)
        end)
        
        if success then
            table.insert(settings.recentVisited, randomServer)
            if #settings.recentVisited > 20 then
                table.remove(settings.recentVisited, 1)
            end
            saveSettings()
            logMessage("Teleport successful", THEME.Success)
            return true
        else
            showNotification("Failed", "Teleport failed, retrying...", 2)
            logMessage("Teleport failed: " .. tostring(err), THEME.Error)
            
            if not isRunning then
                return false
            end
            
            table.remove(servers, table.find(servers, randomServer) or 1)
            task.wait(RETRY_DELAY)
            attempts = attempts + 1
        end
    end
    
    if isRunning then
        isRunning = false
        showNotification("Max Attempts", "Could not join any server", 3)
    end
    
    return false
end

local function monitorFoundPodiums()
    if monitoringConnection then
        monitoringConnection:Disconnect()
    end
    
    monitoringConnection = RunService.Heartbeat:Connect(function()
        if not isRunning or #foundPodiumsData == 0 then return end
        
        local lostAny = false
        local lostPodiums = {}
        
        for i = #foundPodiumsData, 1, -1 do
            local data = foundPodiumsData[i]
            if data and data.overhead and data.overhead.Parent then
                local displayNameLabel = data.overhead:FindFirstChild("DisplayName")
                if displayNameLabel and displayNameLabel.Text then
                    local currentLabels = {
                        DisplayName = displayNameLabel.Text,
                        Generation = data.labels and data.labels.Generation or "Unknown",
                        Mutation = data.labels and data.labels.Mutation or "Normal",
                        Rarity = data.labels and data.labels.Rarity or "None"
                    }
                    
                    if not matchesFilters(currentLabels, data.overhead) then
                        table.insert(lostPodiums, data.labels.DisplayName)
                        table.remove(foundPodiumsData, i)
                        lostAny = true
                    end
                else
                    table.insert(lostPodiums, data.labels.DisplayName)
                    table.remove(foundPodiumsData, i)
                    lostAny = true
                end
            else
                if data then
                    table.insert(lostPodiums, data.labels.DisplayName)
                    table.remove(foundPodiumsData, i)
                    lostAny = true
                end
            end
        end
        
        if lostAny then
            showNotification("Target Lost", "Some targets no longer meet criteria", 3)
            joinOptionsShown = false
            
            -- Cerrar panel de opciones si está abierto
            if optionGui then
                optionGui:Destroy()
                optionGui = nil
            end
            
            -- Si perdimos todos los targets, reanudar búsqueda después de 2 segundos
            if #foundPodiumsData == 0 then
                task.wait(2)
                isRunning = true
                hopConnection = task.spawn(function()
                    while isRunning do
                        runServerCheck()
                        if #foundPodiumsData > 0 then
                            break
                        end
                        task.wait(0.5)
                    end
                end)
            end
        end
    end)
end

-- FUNCIÓN PRINCIPAL CORREGIDA
local function runServerCheck()
    if not isRunning then return end
    
    local foundPets, results, highestValue, highestValueName = checkPodiumsForWebhooksAndFilters()
    
    if foundPets and #results > 0 then
        foundPodiumsData = results
        
        -- Detener el salto
        isRunning = false
        if hopConnection then
            task.cancel(hopConnection)
            hopConnection = nil
        end
        
        local displayResults = {}
        for _, entry in ipairs(results) do
            local genValue = extractNumber(entry.labels.Generation)
            table.insert(displayResults, {entry = entry, gen = genValue})
        end
        table.sort(displayResults, function(a, b) return a.gen > b.gen end)
        
        local foundText = ""
        local numToShow = math.min(2, #displayResults)
        for i = 1, numToShow do
            local entry = displayResults[i].entry
            local genFormatted = formatGeneration(entry.labels.Generation)
            foundText = foundText .. entry.labels.DisplayName .. " (" .. genFormatted .. ")"
            if i < numToShow then
                foundText = foundText .. ", "
            end
        end
        
        logMessage("Found " .. #results .. " target(s) with value >= " .. formatGeneration(tostring(settings.minGeneration)), THEME.Success)
        showNotification("🎯 TARGET FOUND!", foundText, 5)
        playFoundSound()
        monitorFoundPodiums()
        
        -- VERIFICACIÓN CORREGIDA: Mostrar opciones de join SOLO SI autoJoin está desactivado
        logMessage("AutoJoin setting: " .. tostring(settings.autoJoin), THEME.Text)
        
        if not settings.autoJoin then
            showJoinOptions(results)
        else
            -- Si autoJoin está activado, quedarse automáticamente
            logMessage("Auto-join enabled, staying in server automatically", THEME.Success)
            showNotification("Auto-Joined", "Staying in server with target(s)", 3)
        end
        
        return
    end
    
    -- No se encontraron objetos del valor mínimo - hacer hop
    if not isRunning then return end
    
    settings.hopCount = settings.hopCount + 1
    logMessage("Hop #" .. settings.hopCount .. " - No targets found with min value: " .. formatGeneration(tostring(settings.minGeneration)), THEME.Text)
    saveSettings()
    
    if tick() - lastHopTime < 2 then
        task.wait(2 - (tick() - lastHopTime))
    end
    
    lastHopTime = tick()
    
    if not tryTeleportWithRetries() then
        isRunning = false
    end
end

-- [El resto del código de createTagList, createSettingsGUI, etc. permanece igual...]

-- Solo necesitamos ajustar la función createSettingsGUI para asegurar que los toggles muestren el estado correcto

loadSettings()
loadGUIState()
loadAPIState()

if game.PlaceId == ALLOWED_PLACE_ID then
    task.wait(1)
    createSettingsGUI()
    logMessage("VorteX Finder initialized with min value: " .. formatGeneration(tostring(settings.minGeneration)), THEME.Success)
    showNotification("VorteX Finder", "Ready! Min value: " .. formatGeneration(tostring(settings.minGeneration)), 3)
else
    logMessage("Not in target game place. Place ID: " .. game.PlaceId, THEME.Warning)
    showNotification("Wrong Game", "VorteX Finder only works in the target game.", 5)
end