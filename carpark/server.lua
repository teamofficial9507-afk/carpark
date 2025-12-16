-- Server-side Carpark Script (using carpark_data table)

RegisterNetEvent('carpark:saveVehicle')
AddEventHandler('carpark:saveVehicle', function(model, plate, coords, heading, mods, color1, color2)
    local src = source
    local playerId = GetPlayerIdentifier(src, 0)

    MySQL.Async.execute(
        'INSERT INTO carpark_data (player_id, plate, model, x, y, z, heading, mods, color1, color2) VALUES (@player_id, @plate, @model, @x, @y, @z, @heading, @mods, @color1, @color2)',
        {
            ['@player_id'] = playerId,
            ['@plate'] = plate,
            ['@model'] = model, -- already a hash
            ['@x'] = coords.x,
            ['@y'] = coords.y,
            ['@z'] = coords.z,
            ['@heading'] = heading,
            ['@mods'] = json.encode(mods),
            ['@color1'] = color1,
            ['@color2'] = color2
        }
    )
end)

RegisterNetEvent('carpark:retrieveVehicle')
AddEventHandler('carpark:retrieveVehicle', function()
    local src = source
    local playerId = GetPlayerIdentifier(src, 0)

    MySQL.Async.fetchAll(
        'SELECT * FROM carpark_data WHERE player_id = @player_id ORDER BY id DESC LIMIT 1',
        { ['@player_id'] = playerId },
        function(result)
            if result[1] then
                local data = result[1]
                TriggerClientEvent('carpark:spawnVehicle', src, tonumber(data.model), data.plate,
                    {x=data.x, y=data.y, z=data.z}, data.heading,
                    json.decode(data.mods), data.color1, data.color2)
            else
                TriggerClientEvent('chat:addMessage', src, { args = { '[Carpark]', 'No vehicle parked!' } })
            end
        end
    )
end)

RegisterNetEvent('carpark:listVehicles')
AddEventHandler('carpark:listVehicles', function()
    local src = source
    local playerId = GetPlayerIdentifier(src, 0)

    MySQL.Async.fetchAll(
        'SELECT * FROM carpark_data WHERE player_id = @player_id',
        { ['@player_id'] = playerId },
        function(result)
            TriggerClientEvent('carpark:showList', src, result)
        end
    )
end)
