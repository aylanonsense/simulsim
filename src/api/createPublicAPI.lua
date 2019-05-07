local FRAME_RATE = 60
local LOVE_METHODS = {
  load = { server = true, client = true },
  -- update = { server = true, client = true },
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

function createPublicAPI(network)
  -- Create client APIs
  local clientAPIs = {}
  for _, client in ipairs(network.clients) do
    table.insert(clientAPIs, createClientAPI(client, network:isClientSide()))
  end

  -- Create server API
  local serverAPI = createServerAPI(network.server, network:isServerSide())

  -- Bind events
  for cbName, where in pairs(LOVE_METHODS) do
    local cb = love[cbName]
    love[cbName] = function(...)
      if where.server and network:isServerSide() then
        local serverCb = serverAPI[cbName]
        if serverCb then
          serverCb(...)
        end
      end
      if where.client and network:isClientSide() then
        for _, clientAPI in ipairs(clientAPIs) do
          local clientCb = clientAPI[cbName]
          if clientCb then
            clientCb(...)
          end
        end
      end
      if cb then
        cb(...)
      end
    end
  end

  -- Bind update event
  local leftoverTime = 1 / (2 * FRAME_RATE)
  local cb = love.update
  love.update = function(dt, ...)
    if cb then
      cb(dt, ...)
    end
    -- Figure out how many frames have passed
    local df = 0
    leftoverTime = leftoverTime + dt
    while leftoverTime > 1 / FRAME_RATE do
      leftoverTime = leftoverTime - 1 / FRAME_RATE
      df = df + 1
    end
    -- Update everything for each frame that has passed
    network:update(dt)
    for f = 1, df do
      network:moveForwardOneFrame(1 / FRAME_RATE)
      if network:isServerSide() then
        if serverAPI.update then
          serverAPI.update(1 / FRAME_RATE)
        end
      end
      if network:isClientSide() then
        for _, clientAPI in ipairs(clientAPIs) do
          if clientAPI.update then
            clientAPI.update(1 / FRAME_RATE)
          end
        end
      end
    end
  end

  -- Start the server
  if network:isServerSide() then
    network.server:startListening()
  end

  -- Connect the clients to the server
  if network:isClientSide() then
    for _, client in ipairs(network.clients) do
      client:connect()
    end
  end

  -- Return APIs
  return serverAPI, clientAPIs[1], clientAPIs
end

function createServerAPI(server, isServerSide)
  local clients = {}

  local api = {
    -- Overrideable callback functions
    clientconnected = function(client) end,
    clientdisconnected = function(client) end,

    -- Functions that configure server behavior
    handleConnectRequest = function(handshake, accept, reject)
      accept()
    end,
    shouldAcceptEventFromClient = function(client, event)
      return true
    end,
    shouldSendEventToClient = function(client, event)
      return true
    end,
    generateStateSnapshotForClient = function(client)
      return server:getGame():getState()
    end,

    -- Functions to call
    isServerSide = function()
      return isServerSide
    end,
    getClients = function()
      return clients
    end,
    getClientById = function(clientId)
      for _, client in ipairs(clients) do
        if client.clientId == clientId then
          return client
        end
      end
    end,
    getGame = function()
      return server:getGame()
    end,
    fireEvent = function(eventType, eventData, params)
      return server:fireEvent(eventType, eventData, params)
    end
  }

  -- Bind events
  server:onConnect(function(client)
    local clientApi = createServerSideClientAPI(client)
    table.insert(clients, clientApi)
    api.clientconnected(clientApi)
    client:onDisconnect(function(reason)
      for i = #clients, 1, -1 do
        if clients[i].clientId == clientApi.clientId then
          table.remove(clients, i)
          break
        end
      end
      api.clientdisconnected(clientApi)
    end)
  end)

  -- Override server methods
  server.handleConnectRequest = function(self, client, handshake, accept, reject)
    api.handleConnectRequest(handshake, accept, reject)
  end
  server.shouldAcceptEventFromClient = function(self, client, event)
    return api.shouldAcceptEventFromClient(api.getClientById(client.clientId), event)
  end
  server.shouldSendEventToClient = function(self, client, event)
    return api.shouldSendEventToClient(api.getClientById(client.clientId), event)
  end
  server.generateStateSnapshotForClient = function(self, client)
    return api.generateStateSnapshotForClient(api.getClientById(client.clientId))
  end

  -- Return the server api
  return api
end

function createServerSideClientAPI(client)
  return {
    clientId = client.clientId,
    data = client.data,

    disconnect = function(reason)
      client:disconnect(reason)
    end,
    isConnected = function()
      return client:isConnected()
    end
  }
end

function createClientAPI(client, isClientSide)
  local api
  api = {
    _client = client,
    clientId = client.clientId,
    data = client.data,

    -- Overrideable callback functions
    connected = function() end,
    connectfailed = function(reason) end,
    disconnected = function(reason) end,
    synced = function() end,
    desynced = function() end,

    -- Functions to call
    isClientSide = function()
      return isClientSide
    end,
    disconnect = function(reason)
      client:disconnect(reason)
    end,
    isConnecting = function()
      return client:isConnecting()
    end,
    isConnected = function()
      return client:isConnected(0)
    end,
    isSynced = function()
      return client:isSynced()
    end,
    getGame = function()
      return client:getGame()
    end,
    getGameWithoutPrediction = function()
      return client:getGameWithoutPrediction()
    end,
    getFramesOfLatency = function()
      return client:getFramesOfLatency()
    end,
    fireEvent = function(eventType, eventData, params)
      return client:fireEvent(eventType, eventData, params)
    end,
    setInputs = function(inputs, params)
      return client:setInputs(inputs, params)
    end,
    simulateNetworkConditions = function(params)
      client:simulateNetworkConditions(params)
    end
  }

  -- Bind events
  client:onConnect(function()
    api.clientId = client.clientId
    api.data = client.data
    api.connected()
  end)
  client:onConnectFailure(function(reason)
    api.clientId = client.clientId
    api.data = client.data
    api.connectfailed(reason)
  end)
  client:onDisconnect(function(reason)
    api.disconnected(reason)
    api.clientId = client.clientId
    api.data = client.data
  end)
  client:onSync(function()
    api.synced()
  end)
  client:onDesync(function()
    api.desynced()
  end)

  return api
end

return createPublicAPI
