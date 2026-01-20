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
    autoStart = true,
    customSoundId = "rbxassetid://9167433166",
    hopCount = 0,
    recentVisited = {},
    notificationDuration = 4,
    autoJoin = true  -- Nueva opción: auto-joiner
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
local optionGui = nil  -- GUI para opciones de join
local pendingJoinTarget = nil  -- Datos del servidor pendiente para join

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

local function matchesFilters(labels, overhead)
    if isStolenPodium(overhead) then
        return false
    end
    
    local genValue = extractNumber(labels.Generation)
    
    -- Si hay target names, solo acepta esos
    if #settings.targetNames > 0 then
        local hasTargetName = false
        for i = 1, #settings.targetNames do
            local name = settings.targetNames[i]
            if name ~= "" and string.find(string.lower(labels.DisplayName), string.lower(name)) then
                hasTargetName = true
                break
            end
        end
        if not hasTargetName then return false end
    end
    
    -- Si hay target mutation, solo acepta esa
    if settings.targetMutation ~= "" then
        if string.lower(labels.Mutation) ~= string.lower(settings.targetMutation) then
            return false
        end
        return true
    end
    
    -- Si hay target names y no hay target mutation, acepta con esos nombres
    if #settings.targetNames > 0 then
        return true
    end
    
    -- Verifica generación mínima (el usuario puso este valor como MÍNIMO)
    if genValue < settings.minGeneration then
        return false
    end
    
    -- Verifica blacklist
    if #settings.blacklistNames > 0 then
        for i = 1, #settings.blacklistNames do
            local name = settings.blacklistNames[i]
            if name ~= "" and string.find(string.lower(labels.DisplayName), string.lower(name)) then
                return false
            end
        end
    end
    
    -- Verifica rareza
    if settings.targetRarity ~= "" then
        if string.lower(labels.Rarity) ~= string.lower(settings.targetRarity) then
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
    optionGui.Parent = playerGui
    
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 350, 0, 200)
    mainFrame.Position = UDim2.new(0.5, -175, 0.5, -100)
    mainFrame.BackgroundColor3 = THEME.Background
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = optionGui
    
    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 8)
    mainCorner.Parent = mainFrame
    
    local mainStroke = Instance.new("UIStroke")
    mainStroke.Thickness = 1.5
    mainStroke.Color = THEME.Accent
    mainStroke.Parent = mainFrame
    
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -20, 0, 40)
    titleLabel.Position = UDim2.new(0, 10, 0, 10)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "🎯 TARGET FOUND!"
    titleLabel.TextColor3 = THEME.Accent
    titleLabel.TextSize = 18
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Center
    titleLabel.Parent = mainFrame
    
    local displayResults = {}
    for _, entry in ipairs(podiumsData) do
        local genValue = extractNumber(entry.labels.Generation)
        table.insert(displayResults, {entry = entry, gen = genValue})
    end
    table.sort(displayResults, function(a, b) return a.gen > b.gen end)
    
    local foundText = ""
    local numToShow = math.min(2, #displayResults)
    for i = 1, numToShow do
        local entry = displayResults[i].entry
        local genFormatted = formatGeneration(entry.labels.Generation)
        foundText = foundText .. "• " .. entry.labels.DisplayName .. " (" .. genFormatted .. ")"
        if i < numToShow then
            foundText = foundText .. "\n"
        end
    end
    
    local descLabel = Instance.new("TextLabel")
    descLabel.Size = UDim2.new(1, -20, 0, 80)
    descLabel.Position = UDim2.new(0, 10, 0, 50)
    descLabel.BackgroundTransparency = 1
    descLabel.Text = foundText
    descLabel.TextColor3 = THEME.Text
    descLabel.TextSize = 14
    descLabel.Font = Enum.Font.Gotham
    descLabel.TextXAlignment = Enum.TextXAlignment.Left
    descLabel.TextWrapped = true
    descLabel.Parent = mainFrame
    
    local buttonContainer = Instance.new("Frame")
    buttonContainer.Size = UDim2.new(1, -20, 0, 50)
    buttonContainer.Position = UDim2.new(0, 10, 1, -70)
    buttonContainer.BackgroundTransparency = 1
    buttonContainer.Parent = mainFrame
    
    local joinButton = Instance.new("TextButton")
    joinButton.Size = UDim2.new(0.45, 0, 1, 0)
    joinButton.BackgroundColor3 = THEME.JoinButton
    joinButton.BorderSizePixel = 0
    joinButton.Text = "JOIN"
    joinButton.TextColor3 = THEME.Text
    joinButton.TextSize = 14
    joinButton.Font = Enum.Font.GothamBold
    joinButton.Parent = buttonContainer
    
    local joinCorner = Instance.new("UICorner")
    joinCorner.CornerRadius = UDim.new(0, 5)
    joinCorner.Parent = joinButton
    
    local forceJoinButton = Instance.new("TextButton")
    forceJoinButton.Size = UDim2.new(0.45, 0, 1, 0)
    forceJoinButton.Position = UDim2.new(0.55, 0, 0, 0)
    forceJoinButton.BackgroundColor3 = THEME.ForceJoinButton
    forceJoinButton.BorderSizePixel = 0
    forceJoinButton.Text = "FORCE JOIN"
    forceJoinButton.TextColor3 = THEME.Text
    forceJoinButton.TextSize = 14
    forceJoinButton.Font = Enum.Font.GothamBold
    forceJoinButton.Parent = buttonContainer
    
    local forceJoinCorner = Instance.new("UICorner")
    forceJoinCorner.CornerRadius = UDim.new(0, 5)
    forceJoinCorner.Parent = forceJoinButton
    
    local closeButton = Instance.new("TextButton")
    closeButton.Size = UDim2.new(0, 30, 0, 30)
    closeButton.Position = UDim2.new(1, -35, 0, 5)
    closeButton.BackgroundColor3 = THEME.Error
    closeButton.BorderSizePixel = 0
    closeButton.Text = "X"
    closeButton.TextColor3 = THEME.Text
    closeButton.TextSize = 14
    closeButton.Font = Enum.Font.GothamBold
    closeButton.Parent = mainFrame
    
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 4)
    closeCorner.Parent = closeButton
    
    local autoJoinLabel = Instance.new("TextLabel")
    autoJoinLabel.Size = UDim2.new(1, 0, 0, 20)
    autoJoinLabel.Position = UDim2.new(0, 0, 1, -120)
    autoJoinLabel.BackgroundTransparency = 1
    autoJoinLabel.Text = "Auto-join está " .. (settings.autoJoin and "ACTIVADO" or "DESACTIVADO")
    autoJoinLabel.TextColor3 = settings.autoJoin and THEME.Success or THEME.Warning
    autoJoinLabel.TextSize = 12
    autoJoinLabel.Font = Enum.Font.Gotham
    autoJoinLabel.TextXAlignment = Enum.TextXAlignment.Center
    autoJoinLabel.Parent = mainFrame
    
    -- Funciones de los botones
    joinButton.MouseButton1Click:Connect(function()
        logMessage("Join clicked - staying in current server", THEME.Success)
        if optionGui then
            optionGui:Destroy()
            optionGui = nil
        end
        -- Ya estamos en el servidor, no hacer nada más
    end)
    
    forceJoinButton.MouseButton1Click:Connect(function()
        logMessage("Force Join clicked", THEME.Success)
        if optionGui then
            optionGui:Destroy()
            optionGui = nil
        end
        showNotification("Force Join", "Attempting to rejoin server...", 2)
        -- Intentar reconectar al mismo servidor
        task.wait(1)
        TPS:TeleportToPlaceInstance(ALLOWED_PLACE_ID, game.JobId)
    end)
    
    closeButton.MouseButton1Click:Connect(function()
        logMessage("Join options closed, resuming search", THEME.Warning)
        if optionGui then
            optionGui:Destroy()
            optionGui = nil
        end
        -- Reanudar la búsqueda
        if not isRunning then
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
    end)
    
    -- Si autoJoin está activado, auto-join después de 5 segundos
    if settings.autoJoin then
        task.spawn(function()
            for i = 5, 1, -1 do
                autoJoinLabel.Text = "Auto-joining in " .. i .. " seconds..."
                task.wait(1)
                if not optionGui or not optionGui.Parent then
                    break
                end
            end
            
            if optionGui and optionGui.Parent then
                optionGui:Destroy()
                optionGui = nil
                logMessage("Auto-joined to server", THEME.Success)
                showNotification("Auto-Joined", "Staying in current server with target", 3)
            end
        end)
    end
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
            -- Si perdimos todos los targets, reanudar búsqueda
            if #foundPodiumsData == 0 then
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
        
        -- Mostrar opciones de join
        showJoinOptions(results)
        
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

local function createTagList(parent, list, placeholder, onAdd, onRemove)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 22)
    container.BackgroundColor3 = THEME.Input
    container.BorderSizePixel = 0
    container.Parent = parent
    
    local containerCorner = Instance.new("UICorner")
    containerCorner.CornerRadius = UDim.new(0, 4)
    containerCorner.Parent = container

    local containerStroke = Instance.new("UIStroke")
    containerStroke.Thickness = 1
    containerStroke.Color = THEME.Accent
    containerStroke.Parent = container
    
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Size = UDim2.new(1, -50, 1, 0)
    scrollFrame.Position = UDim2.new(0, 4, 0, 0)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 0
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.Parent = container
    
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 3)
    layout.Parent = scrollFrame
    
    local textBox = Instance.new("TextBox")
    textBox.Size = UDim2.new(0, 45, 1, 0)
    textBox.Position = UDim2.new(1, -46, 0, 0)
    textBox.BackgroundTransparency = 1
    textBox.Text = ""
    textBox.PlaceholderText = placeholder
    textBox.TextColor3 = THEME.Text
    textBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
    textBox.TextSize = 9
    textBox.Font = Enum.Font.Gotham
    textBox.Parent = container
    
    local function updateCanvas()
        local totalWidth = layout.AbsoluteContentSize.X
        scrollFrame.CanvasSize = UDim2.new(0, totalWidth, 0, 0)
    end
    
    local function createTag(text)
        local tag = Instance.new("Frame")
        tag.Size = UDim2.new(0, 0, 0, 16)
        tag.BackgroundColor3 = THEME.Accent
        tag.BorderSizePixel = 0
        tag.Parent = scrollFrame
        
        local tagCorner = Instance.new("UICorner")
        tagCorner.CornerRadius = UDim.new(0, 8)
        tagCorner.Parent = tag
        
        local tagLabel = Instance.new("TextLabel")
        tagLabel.Size = UDim2.new(1, -14, 1, 0)
        tagLabel.Position = UDim2.new(0, 3, 0, 0)
        tagLabel.BackgroundTransparency = 1
        tagLabel.Text = text
        tagLabel.TextColor3 = THEME.Text
        tagLabel.TextSize = 8
        tagLabel.Font = Enum.Font.Gotham
        tagLabel.TextXAlignment = Enum.TextXAlignment.Left
        tagLabel.Parent = tag
        
        local removeButton = Instance.new("TextButton")
        removeButton.Size = UDim2.new(0, 12, 0, 12)
        removeButton.Position = UDim2.new(1, -13, 0.5, -5)
        removeButton.BackgroundColor3 = THEME.Error
        removeButton.BorderSizePixel = 0
        removeButton.Text = "X"
        removeButton.TextColor3 = THEME.Text
        removeButton.TextSize = 6
        removeButton.Font = Enum.Font.GothamBold
        removeButton.Parent = tag
        
        local removeCorner = Instance.new("UICorner")
        removeCorner.CornerRadius = UDim.new(0, 6)
        removeCorner.Parent = removeButton
        
        local textSize = TextService:GetTextSize(text, 8, Enum.Font.Gotham, Vector2.new(math.huge, 16))
        tag.Size = UDim2.new(0, textSize.X + 18, 0, 16)
        
        removeButton.MouseButton1Click:Connect(function()
            onRemove(text)
            tag:Destroy()
            updateCanvas()
        end)
        
        updateCanvas()
        return tag
    end
    
    local function refreshTags()
        for _, child in ipairs(scrollFrame:GetChildren()) do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end
        
        for _, item in ipairs(list) do
            if item and item ~= "" then
                createTag(item)
            end
        end
        updateCanvas()
    end
    
    textBox.FocusLost:Connect(function(enterPressed)
        if textBox.Text ~= "" then
            onAdd(textBox.Text:gsub("^%s*(.-)%s*$", "%1"))
            textBox.Text = ""
            refreshTags()
        end
    end)
    
    textBox.Focused:Connect(function()
        TweenService:Create(containerStroke, TweenInfo.new(0.2), {Color = Color3.fromRGB(200, 100, 255)}):Play()
    end)
    
    textBox.FocusLost:Connect(function()
        TweenService:Create(containerStroke, TweenInfo.new(0.2), {Color = THEME.Accent}):Play()
    end)
    
    refreshTags()
    return refreshTags
end

local function createSettingsGUI()
    local playerGui = player:WaitForChild("PlayerGui")
    
    local existingGUI = playerGui:FindFirstChild("VorteXFinderGUI")
    if existingGUI then
        existingGUI:Destroy()
    end
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "VorteXFinderGUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = playerGui
    
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 250, 0, 350)  -- Aumentado para nueva opción
    mainFrame.Position = UDim2.new(guiState.position.XScale, guiState.position.XOffset, guiState.position.YScale, guiState.position.YOffset)
    mainFrame.BackgroundColor3 = THEME.Background
    mainFrame.BorderSizePixel = 0
    mainFrame.ClipsDescendants = true
    mainFrame.Parent = screenGui
    
    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 8)
    mainCorner.Parent = mainFrame
    
    local mainStroke = Instance.new("UIStroke")
    mainStroke.Thickness = 1.5
    mainStroke.Color = THEME.Accent
    mainStroke.Parent = mainFrame
    
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 30)
    titleBar.Position = UDim2.new(0, 0, 0, 0)
    titleBar.BackgroundColor3 = THEME.Header
    titleBar.BorderSizePixel = 0
    titleBar.Parent = mainFrame
    
    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 8)
    titleCorner.Parent = titleBar
    
    local titleFix = Instance.new("Frame")
    titleFix.Size = UDim2.new(1, 0, 0, 15)
    titleFix.Position = UDim2.new(0, 0, 1, -15)
    titleFix.BackgroundColor3 = THEME.Header
    titleFix.BorderSizePixel = 0
    titleFix.Parent = titleBar
    
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -80, 1, 0)
    titleLabel.Position = UDim2.new(0, 8, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "VorteX Finder"
    titleLabel.TextColor3 = THEME.Accent
    titleLabel.TextSize = 12
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = titleBar
    
    local isMinimized = guiState.isMinimized
    local originalSize = mainFrame.Size
    
    local minimizeButton = Instance.new("TextButton")
    minimizeButton.Size = UDim2.new(0, 22, 0, 22)
    minimizeButton.Position = UDim2.new(1, -54, 0, 4)
    minimizeButton.BackgroundColor3 = THEME.Button
    minimizeButton.BorderSizePixel = 0
    minimizeButton.Text = isMinimized and "+" or "-"
    minimizeButton.TextColor3 = THEME.Text
    minimizeButton.TextSize = 10
    minimizeButton.Font = Enum.Font.GothamBold
    minimizeButton.Parent = titleBar
    
    local minimizeCorner = Instance.new("UICorner")
    minimizeCorner.CornerRadius = UDim.new(0, 4)
    minimizeCorner.Parent = minimizeButton
    
    local closeButton = Instance.new("TextButton")
    closeButton.Size = UDim2.new(0, 22, 0, 22)
    closeButton.Position = UDim2.new(1, -28, 0, 4)
    closeButton.BackgroundColor3 = THEME.Error
    closeButton.BorderSizePixel = 0
    closeButton.Text = "X"
    closeButton.TextColor3 = THEME.Text
    closeButton.TextSize = 10
    closeButton.Font = Enum.Font.GothamBold
    closeButton.Parent = titleBar
    
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 4)
    closeCorner.Parent = closeButton
    
    local contentFrame = Instance.new("Frame")
    contentFrame.Size = UDim2.new(1, 0, 1, -30)
    contentFrame.Position = UDim2.new(0, 0, 0, 30)
    contentFrame.BackgroundTransparency = 1
    contentFrame.Visible = not isMinimized
    contentFrame.Parent = mainFrame
    
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Size = UDim2.new(1, -10, 1, -140)
    scrollFrame.Position = UDim2.new(0, 5, 0, 5)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 4
    scrollFrame.ScrollBarImageColor3 = THEME.Accent
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 400)
    scrollFrame.Parent = contentFrame
    
    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 4)
    layout.Parent = scrollFrame
    
    if isMinimized then
        mainFrame.Size = UDim2.new(0, 250, 0, 30)
    else
        mainFrame.Size = UDim2.new(0, 250, 0, 350)
    end
    
    minimizeButton.MouseButton1Click:Connect(function()
        isMinimized = not isMinimized
        guiState.isMinimized = isMinimized
        saveGUIState()
        
        if isMinimized then
            mainFrame.Size = UDim2.new(0, 250, 0, 30)
            minimizeButton.Text = "+"
            contentFrame.Visible = false
        else
            contentFrame.Visible = true
            mainFrame.Size = originalSize
            minimizeButton.Text = "-"
        end
    end)
    
    local function createInputField(name, placeholder, defaultValue, layoutOrder, settingKey, desc)
        local container = Instance.new("Frame")
        container.Size = UDim2.new(1, 0, 0, 35)
        container.BackgroundTransparency = 1
        container.LayoutOrder = layoutOrder
        container.Parent = scrollFrame
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 0, 12)
        label.Position = UDim2.new(0, 0, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = name
        label.TextColor3 = THEME.Text
        label.TextSize = 9
        label.Font = Enum.Font.Gotham
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = container
        
        local inputFrame = Instance.new("Frame")
        inputFrame.Size = UDim2.new(1, -10, 0, 22)
        inputFrame.Position = UDim2.new(0, 0, 0, 13)
        inputFrame.BackgroundColor3 = THEME.Input
        inputFrame.BorderSizePixel = 0
        inputFrame.Parent = container
        
        local inputCorner = Instance.new("UICorner")
        inputCorner.CornerRadius = UDim.new(0, 4)
        inputCorner.Parent = inputFrame

        local inputStroke = Instance.new("UIStroke")
        inputStroke.Thickness = 1
        inputStroke.Color = THEME.Accent
        inputStroke.Parent = inputFrame
        
        local textBox = Instance.new("TextBox")
        textBox.Size = UDim2.new(1, -8, 1, 0)
        textBox.Position = UDim2.new(0, 4, 0, 0)
        textBox.BackgroundTransparency = 1
        textBox.Text = defaultValue or ""
        textBox.PlaceholderText = placeholder
        textBox.TextColor3 = THEME.Text
        textBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
        textBox.TextSize = 10
        textBox.Font = Enum.Font.Gotham
        textBox.Parent = inputFrame
        
        textBox.Focused:Connect(function()
            TweenService:Create(inputStroke, TweenInfo.new(0.2), {Color = Color3.fromRGB(200, 100, 255)}):Play()
        end)
        
        textBox.FocusLost:Connect(function()
            TweenService:Create(inputStroke, TweenInfo.new(0.2), {Color = THEME.Accent}):Play()
            
            if settingKey then
                if settingKey == "minGeneration" or settingKey == "minPlayers" or settingKey == "notificationDuration" then
                    local num = tonumber(textBox.Text)
                    if num then
                        settings[settingKey] = num
                        saveSettings()
                    end
                else
                    settings[settingKey] = textBox.Text:gsub("^%s*(.-)%s*$", "%1")
                    saveSettings()
                end
            end
        end)
        
        return textBox
    end
    
    local function createTagInputField(name, list, placeholder, layoutOrder, descAdd, descRemove)
        local container = Instance.new("Frame")
        container.Size = UDim2.new(1, 0, 0, 35)
        container.BackgroundTransparency = 1
        container.LayoutOrder = layoutOrder
        container.Parent = scrollFrame
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 0, 12)
        label.Position = UDim2.new(0, 0, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = name
        label.TextColor3 = THEME.Text
        label.TextSize = 9
        label.Font = Enum.Font.Gotham
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = container
        
        local tagContainer = Instance.new("Frame")
        tagContainer.Size = UDim2.new(1, -10, 0, 22)
        tagContainer.Position = UDim2.new(0, 0, 0, 13)
        tagContainer.BackgroundTransparency = 1
        tagContainer.Parent = container
        
        local refreshTags = createTagList(tagContainer, list, placeholder,
            function(text)
                if text and text ~= "" and not table.find(list, text) then
                    table.insert(list, text)
                    saveSettings()
                end
            end,
            function(text)
                local index = table.find(list, text)
                if index then
                    table.remove(list, index)
                    saveSettings()
                end
            end
        )
        
        return refreshTags
    end
    
    local function createToggle(name, defaultValue, layoutOrder, settingKey, descOn, descOff)
        local container = Instance.new("Frame")
        container.Size = UDim2.new(1, 0, 0, 28)
        container.BackgroundTransparency = 1
        container.LayoutOrder = layoutOrder
        container.Parent = scrollFrame
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -45, 1, 0)
        label.Position = UDim2.new(0, 0, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = name
        label.TextColor3 = THEME.Text
        label.TextSize = 10
        label.Font = Enum.Font.Gotham
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = container
        
        local toggleFrame = Instance.new("Frame")
        toggleFrame.Size = UDim2.new(0, 36, 0, 18)
        toggleFrame.Position = UDim2.new(1, -36, 0.5, -9)
        toggleFrame.BackgroundColor3 = defaultValue and Color3.fromRGB(50, 150, 50) or Color3.fromRGB(60, 60, 70)
        toggleFrame.BorderSizePixel = 0
        toggleFrame.Parent = container
        
        local toggleCorner = Instance.new("UICorner")
        toggleCorner.CornerRadius = UDim.new(0, 9)
        toggleCorner.Parent = toggleFrame
        
        local toggleButton = Instance.new("Frame")
        toggleButton.Size = UDim2.new(0, 14, 0, 14)
        toggleButton.Position = defaultValue and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
        toggleButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        toggleButton.BorderSizePixel = 0
        toggleButton.Parent = toggleFrame
        
        local buttonCorner = Instance.new("UICorner")
        buttonCorner.CornerRadius = UDim.new(0, 7)
        buttonCorner.Parent = toggleButton
        
        local isEnabled = defaultValue
        local clickDetector = Instance.new("TextButton")
        clickDetector.Size = UDim2.new(1, 0, 1, 0)
        clickDetector.Position = UDim2.new(0, 0, 0, 0)
        clickDetector.BackgroundTransparency = 1
        clickDetector.Text = ""
        clickDetector.Parent = toggleFrame
        
        clickDetector.MouseButton1Click:Connect(function()
            isEnabled = not isEnabled
            local frameColor = isEnabled and Color3.fromRGB(50, 150, 50) or Color3.fromRGB(60, 60, 70)
            local buttonPos = isEnabled and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
            
            TweenService:Create(toggleFrame, TweenInfo.new(0.2), {BackgroundColor3 = frameColor}):Play()
            TweenService:Create(toggleButton, TweenInfo.new(0.2), {Position = buttonPos}):Play()
            
            if settingKey and settings[settingKey] ~= nil then
                settings[settingKey] = isEnabled
                saveSettings()
                showNotification("Auto-Join", "Auto-join is now " .. (isEnabled and "ENABLED" or "DISABLED"), 3)
            end
        end)
        
        return function() return isEnabled end
    end
    
    local function createSortOrderToggle(name, defaultValue, layoutOrder, desc)
        local container = Instance.new("Frame")
        container.Size = UDim2.new(1, 0, 0, 35)
        container.BackgroundTransparency = 1
        container.LayoutOrder = layoutOrder
        container.Parent = scrollFrame
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 0, 12)
        label.Position = UDim2.new(0, 0, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = name
        label.TextColor3 = THEME.Text
        label.TextSize = 9
        label.Font = Enum.Font.Gotham
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = container
        
        local toggleButton = Instance.new("TextButton")
        toggleButton.Size = UDim2.new(1, -10, 0, 22)
        toggleButton.Position = UDim2.new(0, 0, 0, 13)
        toggleButton.BackgroundColor3 = THEME.Input
        toggleButton.BorderSizePixel = 0
        toggleButton.Text = defaultValue
        toggleButton.TextColor3 = THEME.Text
        toggleButton.TextSize = 10
        toggleButton.Font = Enum.Font.Gotham
        toggleButton.TextXAlignment = Enum.TextXAlignment.Left
        toggleButton.Parent = container
        
        local toggleCorner = Instance.new("UICorner")
        toggleCorner.CornerRadius = UDim.new(0, 4)
        toggleCorner.Parent = toggleButton

        local toggleStroke = Instance.new("UIStroke")
        toggleStroke.Thickness = 1
        toggleStroke.Color = THEME.Accent
        toggleStroke.Parent = toggleButton
        
        local padding = Instance.new("UIPadding")
        padding.PaddingLeft = UDim.new(0, 4)
        padding.Parent = toggleButton
        
        local currentValue = defaultValue
        toggleButton.MouseButton1Click:Connect(function()
            if currentValue == "Asc" then
                currentValue = "Desc"
            else
                currentValue = "Asc"
            end
            toggleButton.Text = currentValue
            settings.sortOrder = currentValue
            saveSettings()
        end)
        
        return toggleButton
    end
    
    local minGenInput = createInputField("Min. Generation", "40000000", tostring(settings.minGeneration), 1, "minGeneration", "Minimum generation value to search for.")
    local refreshTargetTags = createTagInputField("Target (Add)", settings.targetNames, "Bloodrot, Aura", 2, "Added target for search regardless of generation:", "Removed target:")
    local refreshBlacklistTags = createTagInputField("Blacklist (Add)", settings.blacklistNames, "Common, Trash", 3, "Added to blacklist to ignore:", "Removed from blacklist:")
    local rarityInput = createInputField("Rarity", "Secret, Mythical", settings.targetRarity, 4, "targetRarity", "Target rarity. Only pets of this rarity will be noticed.")
    local mutationInput = createInputField("Mutation", "Rainbow, Gold", settings.targetMutation, 5, "targetMutation", "Target mutation. Only pets with this mutation will be noticed.")
    local minPlayersInput = createInputField("Min. Players", "2", tostring(settings.minPlayers), 6, "minPlayers", "Minimum number of players on server for hopping.")
    local soundInput = createInputField("Sound ID", "rbxassetid://9167433166", settings.customSoundId, 7, "customSoundId", "Sound ID to play when pet is found.")
    local notificationDurationInput = createInputField("Notification Duration (sec)", "4", tostring(settings.notificationDuration), 8, "notificationDuration", "Duration of notifications in seconds.")
    
    local sortOrderToggle = createSortOrderToggle("Sort Order", settings.sortOrder, 9, "Server sort order: Asc - low to high, Desc - high to low.")
    local autoStartToggle = createToggle("Auto Start", settings.autoStart, 10, "autoStart", "Auto start script after webhook check enabled.", "Auto start script disabled.")
    local autoJoinToggle = createToggle("Auto Join", settings.autoJoin, 11, "autoJoin", "Auto join servers with targets.", "Manual join with options.")
    
    local fixedBottomFrame = Instance.new("Frame")
    fixedBottomFrame.Name = "FixedBottomFrame"
    fixedBottomFrame.Size = UDim2.new(1, 0, 0, 110)
    fixedBottomFrame.Position = UDim2.new(0, 0, 1, -115)
    fixedBottomFrame.BackgroundTransparency = 1
    fixedBottomFrame.Parent = contentFrame
    
    local buttonContainer = Instance.new("Frame")
    buttonContainer.Size = UDim2.new(1, -10, 0, 55)
    buttonContainer.Position = UDim2.new(0, 5, 0, 0)
    buttonContainer.BackgroundTransparency = 1
    buttonContainer.Parent = fixedBottomFrame
    
    local startButton = Instance.new("TextButton")
    startButton.Size = UDim2.new(1, -5, 0, 26)
    startButton.Position = UDim2.new(0, 0, 0, 0)
    startButton.BackgroundColor3 = THEME.Success
    startButton.BorderSizePixel = 0
    startButton.Text = "START"
    startButton.TextColor3 = THEME.Text
    startButton.TextSize = 11
    startButton.Font = Enum.Font.GothamBold
    startButton.Parent = buttonContainer
    
    local startCorner = Instance.new("UICorner")
    startCorner.CornerRadius = UDim.new(0, 5)
    startCorner.Parent = startButton
    
    local stopButton = Instance.new("TextButton")
    stopButton.Size = UDim2.new(1, -5, 0, 26)
    stopButton.Position = UDim2.new(0, 0, 0, 29)
    stopButton.BackgroundColor3 = THEME.Error
    stopButton.BorderSizePixel = 0
    stopButton.Text = "STOP"
    stopButton.TextColor3 = THEME.Text
    stopButton.TextSize = 11
    stopButton.Font = Enum.Font.GothamBold
    stopButton.Parent = buttonContainer
    
    local stopCorner = Instance.new("UICorner")
    stopCorner.CornerRadius = UDim.new(0, 5)
    stopCorner.Parent = stopButton
    
    local statusContainer = Instance.new("Frame")
    statusContainer.Size = UDim2.new(1, -10, 0, 45)
    statusContainer.Position = UDim2.new(0, 5, 0, 60)
    statusContainer.BackgroundTransparency = 1
    statusContainer.Parent = fixedBottomFrame
    
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 0, 24)
    statusLabel.Position = UDim2.new(0, 0, 0, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Ready to search..."
    statusLabel.TextColor3 = THEME.Text
    statusLabel.TextSize = 9
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextWrapped = true
    statusLabel.Parent = statusContainer
    
    local apiStatusLabel = Instance.new("TextLabel")
    apiStatusLabel.Size = UDim2.new(1, 0, 0, 21)
    apiStatusLabel.Position = UDim2.new(0, 0, 0, 24)
    apiStatusLabel.BackgroundTransparency = 1
    apiStatusLabel.Text = string.format("API: %d/3 | Cache: %d | Hops: %d", apiState.mainApiUses, #apiState.cachedServers, settings.hopCount)
    apiStatusLabel.TextColor3 = THEME.Text
    apiStatusLabel.TextSize = 8
    apiStatusLabel.Font = Enum.Font.Gotham
    apiStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    apiStatusLabel.Parent = statusContainer
    
    local function updateScrollCanvas()
        task.wait(0.1)
        local contentHeight = layout.AbsoluteContentSize.Y + 20
        scrollFrame.CanvasSize = UDim2.new(0, 0, 0, contentHeight)
    end
    
    updateScrollCanvas()
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateScrollCanvas)
    
    local function addButtonHover(button, hoverColor, originalColor)
        button.MouseEnter:Connect(function()
            TweenService:Create(button, TweenInfo.new(0.2), {BackgroundColor3 = hoverColor}):Play()
        end)
        button.MouseLeave:Connect(function()
            TweenService:Create(button, TweenInfo.new(0.2), {BackgroundColor3 = originalColor}):Play()
        end)
    end
    
    addButtonHover(startButton, Color3.fromRGB(60, 180, 60), THEME.Success)
    addButtonHover(stopButton, Color3.fromRGB(180, 60, 60), THEME.Error)
    addButtonHover(closeButton, Color3.fromRGB(255, 80, 80), THEME.Error)
    addButtonHover(minimizeButton, THEME.ButtonHover, THEME.Button)
    
    local function updateAPIStatus()
        apiStatusLabel.Text = string.format("API: %d/3 | Cache: %d | Hops: %d | %s",
            apiState.mainApiUses,
            #apiState.cachedServers,
            settings.hopCount,
            apiState.useCachedServers and "Cache" or "Live"
        )
    end
    
    local function startHopping()
        if isRunning then
            statusLabel.Text = "Already running!"
            statusLabel.TextColor3 = THEME.Warning
            showNotification("Already Running", "VorteX Finder is already searching.", 2)
            return
        end
        
        -- Limpiar conexiones anteriores
        if hopConnection then
            task.cancel(hopConnection)
            hopConnection = nil
        end
        
        if monitoringConnection then
            monitoringConnection:Disconnect()
            monitoringConnection = nil
        end
        
        foundPodiumsData = {}
        
        isRunning = true
        statusLabel.Text = "Searching..."
        statusLabel.TextColor3 = THEME.Success
        
        logMessage("VorteX Finder started with min value: " .. formatGeneration(tostring(settings.minGeneration)), THEME.Success)
        showNotification("VorteX Finder", "Searching for targets ≥ " .. formatGeneration(tostring(settings.minGeneration)), 3)
        
        hopConnection = task.spawn(function()
            while isRunning do
                runServerCheck()
                if #foundPodiumsData > 0 then
                    break
                end
                task.wait(0.5)
                updateAPIStatus()
            end
        end)
    end
    
    startButton.MouseButton1Click:Connect(startHopping)
    
    stopButton.MouseButton1Click:Connect(function()
        if not isRunning then
            statusLabel.Text = "Not running"
            statusLabel.TextColor3 = THEME.Text
            return
        end
        
        isRunning = false
        foundPodiumsData = {}
        autoHopping = false
        
        if monitoringConnection then
            monitoringConnection:Disconnect()
            monitoringConnection = nil
        end
        
        if hopConnection then
            task.cancel(hopConnection)
            hopConnection = nil
        end
        
        -- Cerrar GUI de opciones si está abierta
        if optionGui then
            optionGui:Destroy()
            optionGui = nil
        end
        
        statusLabel.Text = "Search stopped."
        statusLabel.TextColor3 = THEME.Error
        
        logMessage("VorteX Finder stopped", THEME.Error)
        showNotification("Stopped", "VorteX Finder has been stopped.", 2)
    end)
    
    closeButton.MouseButton1Click:Connect(function()
        isRunning = false
        foundPodiumsData = {}
        autoHopping = false
        
        if monitoringConnection then
            monitoringConnection:Disconnect()
            monitoringConnection = nil
        end
        
        if hopConnection then
            task.cancel(hopConnection)
            hopConnection = nil
        end
        
        if optionGui then
            optionGui:Destroy()
            optionGui = nil
        end
        
        screenGui:Destroy()
    end)
    
    local dragging = false
    local dragStart = nil
    local startPos = nil
    
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            local newPos = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            mainFrame.Position = newPos
            
            guiState.position = {
                XScale = newPos.X.Scale,
                XOffset = newPos.X.Offset,
                YScale = newPos.Y.Scale,
                YOffset = newPos.Y.Offset
            }
            saveGUIState()
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    
    task.spawn(function()
        while screenGui and screenGui.Parent do
            updateAPIStatus()
            task.wait(3)
        end
    end)
    
    _G.CloseVorteXFinder = function()
        pcall(function()
            local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
            if playerGui then
                local finderGui = playerGui:FindFirstChild("VorteXFinderGUI")
                if finderGui then
                    finderGui:Destroy()
                end
            end
        end)
    end
    
    if settings.autoStart and game.PlaceId == ALLOWED_PLACE_ID then
        task.wait(1)
        startHopping()
    end
    
    return screenGui
end

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