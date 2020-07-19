local Main = {}

local tileSize = 32
local boundarySize = 2
local maxZoom = 1
local minZoom = 0.031250

function Main.tick()
    for index, player in pairs(game.players) do
        local playerSettings = global.playerSettings[player.index]
        local mainCamera = playerSettings.cameras[1]

        if
            playerSettings.enabled and
                (game.tick % mainCamera.screenshotInterval == 0 or
                    (global.rocketLaunching and game.tick % mainCamera.rocketInterval == 0))
         then
            if mainCamera.factorySize == nil then
                Main.follow_player(playerSettings, player)

                if playerSettings.followPlayer == false then
                    -- Do not take screenshots yet
                    return
                end
            elseif global.rocketLaunching ~= nil then
                -- Focus on launch
                -- TODO get a proper rocket camera
                Main.follow_center_pos(
                    playerSettings,
                    player,
                    mainCamera,
                    global.rocketLaunching.centerPos,
                    global.rocketLaunching.size
                )
            else
                -- Focus on base
                Main.follow_center_pos(
                    playerSettings,
                    player,
                    mainCamera,
                    mainCamera.baseCenterPos,
                    mainCamera.factorySize
                )
            end

            game.take_screenshot {
                by_player = player,
                surface = game.surfaces[1],
                position = mainCamera.centerPos,
                resolution = {mainCamera.width, mainCamera.height},
                zoom = mainCamera.zoom,
                path = string.format("%s/%08d-%s.png", playerSettings.saveFolder, game.tick, mainCamera.name),
                show_entity_info = false,
                allow_in_replay = true,
                daytime = 0 -- take screenshot at full light
            }
        end
    end
end

function Main.chart_added(event)
    local player = game.players[1]
    local mainCamera = global.playerSettings[1].cameras[1]
    --player.print("ADDED: " .. event.tag.text)
    local newEntityBBox = {
        left = mainCamera.minPos.x,
        bottom = mainCamera.minPos.y,
        right = mainCamera.maxPos.x,
        top = mainCamera.maxPos.y
    }
    if event.tag.text == "ctl" then
        newEntityBBox.left = event.tag.position.x
        newEntityBBox.bottom = event.tag.position.y
    end
    if event.tag.text == "cbr" then
        newEntityBBox.right = event.tag.position.x
        newEntityBBox.top = event.tag.position.y
    end
    Main.move_camera(newEntityBBox, true)
end

function Main.entity_built(event)
    -- top/bottom seems to be swapped, so use this table to reduce confusion of rest of the code
    local newEntityBBox = {
        left = event.created_entity.bounding_box.left_top.x - boundarySize,
        bottom = event.created_entity.bounding_box.left_top.y - boundarySize,
        right = event.created_entity.bounding_box.right_bottom.x + boundarySize,
        top = event.created_entity.bounding_box.right_bottom.y + boundarySize
    }

    Main.move_camera(newEntityBBox, false)

end

function Main.move_camera(bounding_box, force_box)
    for i, playerSettings in ipairs(global.playerSettings) do
        local mainCamera = playerSettings.cameras[1]

        if mainCamera.factorySize == nil then
            -- Set start point of base
            mainCamera.minPos = {x = bounding_box.left, y = bounding_box.bottom}
            mainCamera.maxPos = {x = bounding_box.right, y = bounding_box.top}
        else
            -- Recalculate base boundary
            if (force_box or bounding_box.left < mainCamera.minPos.x) then
                mainCamera.minPos.x = bounding_box.left
            end
            if (force_box or bounding_box.bottom < mainCamera.minPos.y) then
                mainCamera.minPos.y = bounding_box.bottom
            end
            if (force_box or bounding_box.right > mainCamera.maxPos.x) then
                mainCamera.maxPos.x = bounding_box.right
            end
            if (force_box or bounding_box.top > mainCamera.maxPos.y) then
                mainCamera.maxPos.y = bounding_box.top
            end
        end

        mainCamera.lastChange = game.tick
        mainCamera.factorySize = {
            x = mainCamera.maxPos.x - mainCamera.minPos.x,
            y = mainCamera.maxPos.y - mainCamera.minPos.y
        }

        -- Update center position
        mainCamera.baseCenterPos = {
            x = mainCamera.minPos.x + mainCamera.factorySize.x / 2,
            y = mainCamera.minPos.y + mainCamera.factorySize.y / 2
        }
    end
end

function Main.rocket_launch(event)
    if global.rocketLaunching ~= nil then
        -- already following a launch, ignore
        return
    end

    for i, playerSettings in ipairs(global.playerSettings) do
        local mainCamera = playerSettings.cameras[1]
        mainCamera.lastChange = game.tick
    end

    global.rocketLaunching = {
        centerPos = event.rocket_silo.position,
        size = {x = 1, y = 1} -- don't care about size, it will fit with maxZoom
    }
end

function Main.rocket_launched()
    -- Done, recenter on base and allow tracking next launch
    for i, playerSettings in ipairs(global.playerSettings) do
        local mainCamera = playerSettings.cameras[1]

        mainCamera.lastChange = game.tick
    end

    global.rocketLaunching = nil
end

function Main.follow_player(playerSettings, player)
    local mainCamera = playerSettings.cameras[1]

    -- Follow player (update begin position)
    mainCamera.centerPos = player.position
    mainCamera.zoom = maxZoom
end

function Main.follow_center_pos(playerSettings, player, camera, centerPos, centerSize)
    local ticksLeft = camera.lastChange - game.tick
    if global.rocketLaunching then
        ticksLeft = ticksLeft + camera.zoomTicksRocket
    else
        ticksLeft = ticksLeft + camera.zoomTicks
    end

    if ticksLeft > 0 then
        local stepsLeft
        if global.rocketLaunching then
            stepsLeft = ticksLeft / camera.rocketInterval
        else
            stepsLeft = ticksLeft / camera.screenshotInterval
        end

        -- Gradually move to new center of the base
        local xDiff = centerPos.x - camera.centerPos.x
        local yDiff = centerPos.y - camera.centerPos.y
        camera.centerPos.x = camera.centerPos.x + xDiff / stepsLeft
        camera.centerPos.y = camera.centerPos.y + yDiff / stepsLeft

        -- Calculate desired zoom
        local zoomX = camera.width / (tileSize * centerSize.x)
        local zoomY = camera.height / (tileSize * centerSize.y)
        local zoom = math.min(zoomX, zoomY, maxZoom)

        -- Gradually zoom out with same duration as centering
        camera.zoom = camera.zoom - (camera.zoom - zoom) / stepsLeft

        if camera.zoom < minZoom then
            if playerSettings.noticeMaxZoom == nil then
                player.print({"max-zoom"}, {r = 1})
                player.print({"msg-once"})
                playerSettings.noticeMaxZoom = true
            end

            camera.zoom = minZoom
        else
            -- Max (min atually) zoom is not reached (anymore)
            playerSettings.noticeMaxZoom = nil
        end
    end
end

return Main
