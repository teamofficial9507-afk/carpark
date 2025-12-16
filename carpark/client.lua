local ResourceVersion = "1.0.0"
Citizen.CreateThread(function()
    local updatePath = "https://raw.githubusercontent.com/YourGitHubUser/YourRepo/main/version.txt"
    PerformHttpRequest(updatePath, function(err, text, headers)
        if err == 200 and text then
            local remoteVersion = string.gsub(text, "%s+", "") -- trim whitespace
            if ResourceVersion ~= remoteVersion then
                print("^1[Carpark] WARNING: Your version (" .. ResourceVersion .. ") is outdated. Latest is (" .. remoteVersion .. ").^0")
            else
                print("^2[Carpark] You are running the latest version (" .. ResourceVersion .. ").^0")
            end
        else
            print("^3[Carpark] Could not check version (HTTP error).^0")
        end
    end, "GET", "")
end)

-- Config options
Config = {}
Config.ValetEnabled  = true   -- true = valet drives car to you, false = instant spawn at feet
Config.ValetDistance = 5     -- how far away (in game units/metres) the valet spawns the car

-- Helper: find a safe ground Z coordinate near player
local function GetSafeCoordsAroundPlayer(playerCoords, radius)
    local x = playerCoords.x + math.random(-radius, radius)
    local y = playerCoords.y + math.random(-radius, radius)
    local z = playerCoords.z + 50.0 -- start high

    -- Probe downward for ground
    local found, groundZ = GetGroundZFor_3dCoord(x, y, z, 0.0, false)
    if found then
        return vector3(x, y, groundZ)
    else
        -- fallback: just return player coords
        return playerCoords
    end
end

-- Command: park current vehicle
RegisterCommand('parkcar', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)

    if veh ~= 0 then
        local coords = GetEntityCoords(veh)
        local heading = GetEntityHeading(veh)
        local model = GetEntityModel(veh) -- hash
        local plate = GetVehicleNumberPlateText(veh)

        -- Collect mods/colors
        local mods = {}
        for i=0, 49 do
            mods[i] = GetVehicleMod(veh, i)
        end
        local color1, color2 = GetVehicleColours(veh)

        -- Save to server DB
        TriggerServerEvent('carpark:saveVehicle', model, plate, coords, heading, mods, color1, color2)

        -- Despawn the vehicle after saving
        DeleteEntity(veh)
        print('[Carpark] Vehicle parked and saved!')
    else
        print('[Carpark] You are not in a vehicle.')
    end
end, false)

-- Command: retrieve latest vehicle
RegisterCommand('retrievecar', function()
    TriggerServerEvent('carpark:retrieveVehicle')
end, false)

-- Command: list saved vehicles
RegisterCommand('mycars', function()
    TriggerServerEvent('carpark:listVehicles')
end, false)

-- Retrieval event: valet or instant spawn depending on config
RegisterNetEvent('carpark:spawnVehicle')
AddEventHandler('carpark:spawnVehicle', function(modelHash, plate, coords, heading, mods, color1, color2)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)

    -- Ensure model loads
    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Wait(0)
    end

    -- Decide spawn coords
    local spawnCoords
    if Config.ValetEnabled then
        spawnCoords = GetSafeCoordsAroundPlayer(playerCoords, Config.ValetDistance)
    else
        spawnCoords = GetSafeCoordsAroundPlayer(playerCoords, 3)
    end

   -- After creating the vehicle
local veh = CreateVehicle(modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, heading, true, true)

if not DoesEntityExist(veh) then
    print("[Carpark] ERROR: Vehicle failed to spawn.")
    return
end

-- Create a blip for the vehicle
local blip = AddBlipForEntity(veh)
SetBlipSprite(blip, 225)        -- car icon
SetBlipColour(blip, 3)          -- light blue
SetBlipScale(blip, 0.8)
BeginTextCommandSetBlipName("STRING")
AddTextComponentString("Valet Vehicle")
EndTextCommandSetBlipName(blip)

-- Optional: remove blip after valet arrives
Citizen.CreateThread(function()
    while true do
        Wait(1000)
        local dist = #(GetEntityCoords(veh) - playerCoords)
        if dist < 6.0 then
            -- valet has arrived, clean up blip after a short delay
            Citizen.SetTimeout(10000, function()
                if DoesBlipExist(blip) then
                    RemoveBlip(blip)
                end
            end)
            break
        end
    end
end)

    -- Apply plate and colors
    SetVehicleNumberPlateText(veh, plate)
    SetVehicleColours(veh, color1, color2)

    -- Apply mods
    for i, mod in pairs(mods) do
        if mod ~= -1 then
            SetVehicleMod(veh, i, mod, false)
        end
    end

    if Config.ValetEnabled then
        -- Spawn valet NPC driver
        local npcModel = GetHashKey("s_m_m_valet_01")
        RequestModel(npcModel)
        while not HasModelLoaded(npcModel) do
            Wait(0)
        end

        local driver = CreatePedInsideVehicle(veh, 4, npcModel, -1, true, false)

        -- Task driver to bring car to player (long-range, reliable)
        TaskVehicleDriveToCoordLongrange(
            driver,
            veh,
            playerCoords.x,
            playerCoords.y,
            playerCoords.z,
            20.0,      -- speed
            modelHash, -- vehicle model hash
            786603,    -- driving style
            5.0        -- stopping range
        )

        -- Monitor arrival
        Citizen.CreateThread(function()
            local timeout = GetGameTimer() + 60000 -- 60s failsafe
            while true do
                Wait(1000)
                local dist = #(GetEntityCoords(veh) - playerCoords)
                if dist < 6.0 then
                    TaskLeaveVehicle(driver, veh, 0)
                    Wait(3000)
                    TaskWanderStandard(driver, 10.0, 10)
                    Citizen.SetTimeout(30000, function()
                        if DoesEntityExist(driver) then DeleteEntity(driver) end
                    end)
                    break
                end
                if GetGameTimer() > timeout then
                    -- Failsafe: warp car to player if valet gets stuck
                    SetEntityCoords(veh, playerCoords.x + 2.0, playerCoords.y + 2.0, playerCoords.z)
                    TaskLeaveVehicle(driver, veh, 0)
                    break
                end
            end
        end)

        print('[Carpark] Valet is delivering your vehicle!')
    else
        -- Instant spawn: put player in car
        SetPedIntoVehicle(playerPed, veh, -1)
        print('[Carpark] Vehicle retrieved instantly!')
    end
end)

-- Show list of vehicles
RegisterNetEvent('carpark:showList')
AddEventHandler('carpark:showList', function(list)
    for _, v in pairs(list) do
        print(string.format('[Carpark] %s - Plate: %s', v.model, v.plate))
    end
end)

-- Optional: add chat suggestions
Citizen.CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/parkcar', 'Save and despawn your current vehicle')
    TriggerEvent('chat:addSuggestion', '/retrievecar', 'Retrieve your last saved vehicle')
    TriggerEvent('chat:addSuggestion', '/mycars', 'List all your saved vehicles')
end)
