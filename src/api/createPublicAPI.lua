local tableUtils = require 'src/utils/table'

local FRAME_RATE = 60
local OVERRIDEABLE_LOVE_METHODS = {
  load = { server = true, client = true },
  update = { server = true, client = true },
  uiupdate = { client = true },
  draw = { client = true },
  lowmemory = { server = true, client = true },
  quit = { server = true, client = true },
  threaderror = { server = true, client = true },
  directorydropped = { client = true },
  filedropped = { client = true },
  focus = { client = true },
  keypressed = { client = true },
  keyreleased = { client = true },
  mousefocus = { client = true },
  mousemoved = { client = true },
  mousepressed = { client = true },
  mousereleased = { client = true },
  resize = { client = true },
  textedited = { client = true },
  textinput = { client = true },
  touchmoved = { client = true },
  touchpressed = { client = true },
  touchreleased = { client = true },
  visible = { client = true },
  wheelmoved = { client = true },
  gamepadaxis = { client = true },
  gamepadpressed = { client = true },
  gamepadreleased = { client = true },
  joystickadded = { client = true },
  joystickaxis = { client = true },
  joystickhat = { client = true },
  joystickpressed = { client = true },
  joystickreleased = { client = true },
  joystickremoved = { client = true }
}

local function bindServerToAPI(server, api)
  -- Allow for certain server methods to be overridden
  local overrideableMethods = { 'handleConnectRequest', 'shouldAcceptEventFromClient', 'shouldSendEventToClient', 'generateStateSnapshotForClient' }
  for _, methodName in ipairs(overrideableMethods) do
    local originalMethod = server[methodName]
    server[methodName] = function(...)
      if api[methodName] then
        return api[methodName](...)
      else
        return originalMethod(...)
      end
    end
  end

  -- Bind events
  server:onConnect(function(client)
    if api.clientconnected then
      api.clientconnected(server, client)
    end
    client:onDisconnect(function(reason)
      if api.clientdisconnected then
        api.clientdisconnected(server, client, reason)
      end
    end)
  end)

  -- Set a metatable so the server inherits all the properties and functions placed on the api
  setmetatable(server, {
    __index = api
  })
end

local function bindClientToAPI(client, api)
  -- Allow for certain client methods to be overridden
  local overrideableMethods = { 'syncEntity', 'syncInputs', 'syncData', 'smoothEntity', 'smoothInputs', 'smoothData', 'isEntityUsingPrediction', 'isEventUsingPrediction' }
  for _, methodName in ipairs(overrideableMethods) do
    local originalMethod = client[methodName]
    client[methodName] = function(...)
      if api[methodName] then
        return api[methodName](...)
      else
        return originalMethod(...)
      end
    end
  end

  -- Bind events
  client:onConnect(function()
    if api.connected then
      api.connected(client)
    end
  end)
  client:onConnectFailure(function(reason)
    if api.connectfailed then
      api.connectfailed(client, reason)
    end
  end)
  client:onDisconnect(function(reason)
    if api.disconnected then
      api.disconnected(client, reason)
    end
  end)
  client:onStabilize(function()
    if api.stabilized then
      api.stabilized(client)
    end
  end)
  client:onDestabilize(function()
    if api.destabilized then
      api.destabilized(client)
    end
  end)

  -- Set a metatable so the client inherits all the properties and functions placed on the api
  setmetatable(client, {
    __index = api
  })
end

local function createPublicAPI(network, params)
  params = params or {}
  local overrideCallbackMethods = params.overrideCallbackMethods ~= false
  local width = params.width
  local height = params.height
  local drawClientsInGrid = params.drawClientsInGrid ~= false

  -- Calculate where each client should be drawn
  if drawClientsInGrid and width and height then
    local numCols = math.ceil(math.sqrt(#network.clients))
    local numRows = math.ceil(#network.clients / numCols)
    local gridSize = math.max(numCols, numRows)
    local numEmptySpaces = numCols * numRows - #network.clients
    local col = 1
    local row = 1
    local padding = 1
    local scaledWidth = (width - padding * (gridSize - 1)) / gridSize
    local scaledHeight = (height - padding * (gridSize - 1)) / gridSize
    local scale = math.min(scaledWidth / width, scaledHeight / height)
    local clientWidth = (width - padding * (gridSize - 1)) * scale
    local clientHeight = (height - padding * (gridSize - 1)) * scale
    local xOffset = 0
    local yOffset = (height - clientHeight * numRows - padding * (numRows - 1)) / 2
    for _, client in ipairs(network.clients) do
      local clientX = xOffset + (col - 1) * width * scale + padding * (col - 1)
      local clientY = yOffset + (row - 1) * height * scale + padding * (row - 1)
      client._drawProps = { x = clientX, y = clientY, width = clientWidth, height = clientHeight, scale = scale }
      col = col + 1
      if col > numCols then
        col, row = 1, row + 1
        if row == numRows then
          xOffset = (clientWidth * numEmptySpaces + padding * math.max(0, numEmptySpaces - 1)) / 2
        end
      end
    end
  end

  -- Create a server API and bind the server to it
  local serverAPI = {}
  bindServerToAPI(network.server, serverAPI)

  -- Create a client API and bind all clients to it
  local clientAPI = {
    toDrawnCoordinates = function(self, x, y)
      local props = self._drawProps
      if props then
        return (x - props.x) * props.scale, (y - props.y) * props.scale
      else
        return x, y
      end
    end,
    isHighlighted = function(self)
      local props = self._drawProps
      if not props then
        return true
      else
        local x, y = love.mouse.getPosition()
        return x and y and props.x <= x and x < props.x + props.width and props.y <= y and y < props.y + props.height
      end
    end
  }
  for _, client in ipairs(network.clients) do
    bindClientToAPI(client, clientAPI)
  end

  -- Create a network API
  local networkAPI = {
    server = serverAPI,
    client = clientAPI,
    isClientSide = function(self)
      return network:isClientSide()
    end,
    isServerSide = function(self)
      return network:isServerSide()
    end
  }

  -- Add callback methods onto the network API
  for methodName, where in pairs(OVERRIDEABLE_LOVE_METHODS) do
    local originalMethod = love[methodName]
    -- Add an update method onto the network API
    if methodName == 'update' then
      local leftoverTime = 1 / (2 * FRAME_RATE)
      networkAPI.update = function(dt, ...)
        if originalMethod then
          originalMethod(dt, ...)
        end
        -- Figure out how many frames have passed
        leftoverTime = leftoverTime + dt
        local df = math.floor(leftoverTime * FRAME_RATE)
        if df > 1 then
          df = df - 1
        end
        leftoverTime = leftoverTime - df / FRAME_RATE
        -- Update everything for each frame that has passed
        network:update(dt)
        for f = 1, df do
          network:moveForwardOneFrame(1 / FRAME_RATE)
          if network:isServerSide() and serverAPI.update then
            serverAPI.update(network.server, 1 / FRAME_RATE, ...)
          end
          if network:isClientSide() and clientAPI.update then
            for _, client in ipairs(network.clients) do
              clientAPI.update(client, 1 / FRAME_RATE, ...)
            end
          end
        end
      end
    -- Do some trickiness to get multiple clients' screens dispaying at once in development mode
    elseif methodName == 'draw' then
      networkAPI.draw = function(...)
        if network:isClientSide() and clientAPI.draw then
          for _, client in ipairs(network.clients) do
            local props = client._drawProps
            if props then
              love.graphics.push()
              love.graphics.translate(props.x, props.y)
              love.graphics.scale(props.scale, props.scale)
              love.graphics.setScissor(props.x, props.y, props.width, props.height)
              clientAPI.draw(client, ...)
              love.graphics.pop()
            else
              clientAPI.draw(client, ...)
            end
          end
        end
      end
    -- Add a callback method onto the network API
    else
      networkAPI[methodName] = function(...)
        if originalMethod then
          originalMethod(...)
        end
        if where.server and network:isServerSide() and serverAPI[methodName] then
          serverAPI[methodName](network.server, ...)
        end
        if where.client and network:isClientSide() and clientAPI[methodName] then
          for _, client in ipairs(network.clients) do
            clientAPI[methodName](client, ...)
          end
        end
      end
    end
    -- Override the default LOVE method
    if overrideCallbackMethods then
      love[methodName] = function(...)
        networkAPI[methodName](...)
      end
    end
  end

  -- Bind uiupdate callback
  local originalMethod = castle.uiupdate
  networkAPI.uiupdate = function(...)
    if originalMethod then
      originalMethod(...)
    end
    if network:isClientSide() and clientAPI.uiupdate then
      for _, client in ipairs(network.clients) do
        clientAPI.uiupdate(client, ...)
      end
    end
  end

  -- Bind background update event (so simulsim can update even in the background)
  if overrideCallbackMethods then
    castle.backgroundupdate = function(...)
      networkAPI.update(...)
    end
    castle.uiupdate = function(...)
      networkAPI.uiupdate(...)
    end
  end

  -- Start the server
  network.server:startListening()

  -- Connect the clients to the server
  for _, client in ipairs(network.clients) do
    client:connect()
  end

  -- Return APIs
  return networkAPI, serverAPI, clientAPI
end

return createPublicAPI
