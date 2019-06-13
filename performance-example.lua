local simulsim = require 'simulsim'

local NUM_CLIENTS = 1
local NUM_BOXES_PER_CLIENT = 1
local NUM_CLIENT_EVENTS_PER_SECOND = 2

local game = simulsim.defineGame()
function game.update(self, dt)
  for _, entity in ipairs(self.entities) do
    entity.x = entity.x + entity.vx * dt
    entity.y = entity.y + entity.vy * dt
    if entity.x < 0 then
      entity.x = 0
      entity.vx = math.abs(entity.vx)
    elseif entity.x > 200 - entity.width then
      entity.x = 200 - entity.width
      entity.vx = -math.abs(entity.vx)
    end
    if entity.y < 50 then
      entity.y = 50
      entity.vy = math.abs(entity.vy)
    elseif entity.y > 200 - entity.height then
      entity.y = 200 - entity.height
      entity.vy = -math.abs(entity.vy)
    end
  end
end
function game.handleEvent(self, eventType, eventData)
  if eventType == 'spawn-box' then
    self:spawnEntity({
      id = eventData.id,
      clientId = eventData.clientId,
      x = eventData.x,
      y = eventData.y,
      width = 10,
      height = 10,
      vx = eventData.vx,
      vy = eventData.vy,
      color = eventData.color
    })
  elseif eventType == 'change-box-velocity' then
    local box = self:getEntityById(eventData.entityId)
    if box then
      box.vx = eventData.vx
      box.vy = eventData.vy
    end
  end
end

local network, server, client = simulsim.createGameNetwork(game, {
  mode = 'development',
  numClients = NUM_CLIENTS,
  exposeGameWithoutPrediction = true
})

function server.clientconnected(client)
  for i = 1, NUM_BOXES_PER_CLIENT do
    local color
    if client.clientId == 1 then
      color = { 1, 0, 0 }
    elseif client.clientId == 2 then
      color = { 0, 0.7, 1 }
    elseif client.clientId == 3 then
      color = { 0, 1, 0 }
    elseif client.clientId == 4 then
      color = { 1, 1, 0 }
    elseif client.clientId == 5 then
      color = { 1, 0, 1 }
    elseif client.clientId == 6 then
      color = { 0, 1, 1 }
    elseif client.clientId == 7 then
      color = { 1, 0.7, 0 }
    elseif client.clientId == 8 then
      color = { 1, 1, 1 }
    elseif client.clientId == 9 then
      color = { 0.4, 0.4, 0.4 }
    end
    server.fireEvent('spawn-box', {
      id = 'client-' .. client.clientId .. '-box-' .. i,
      clientId = client.clientId,
      x = math.random(0, 190),
      y = math.random(50, 190),
      vx = 0,
      vy = 0,
      color = color
    })
  end
end

-- Because numClients = 2, we have two clients to set up handlers for
for _, client in ipairs(network.clients) do
  function client.load()
    client.simulateNetworkConditions({ latency = 350, latencyDeviation = 0 })
    client.timer = 0.00
  end

  function client.update(dt)
    if client.isConnected() then
      client.timer = client.timer + dt
      while client.timer > 1 / NUM_CLIENT_EVENTS_PER_SECOND do
        client.fireEvent('change-box-velocity', {
          entityId = 'client-' .. client.clientId .. '-box-' .. math.random(1, NUM_BOXES_PER_CLIENT),
          vx = math.random(-50, 50),
          vy = math.random(-50, 50)
        })
        client.timer = client.timer - 1 / NUM_CLIENT_EVENTS_PER_SECOND
      end
    end
  end

  function client.draw()
    if client.clientId then
      -- Offset the drawn elements so that you can see both clients' screens side-by-side
      love.graphics.reset()
      love.graphics.translate(210 * ((client.clientId - 1) % 3) + 10, 210 * math.floor((client.clientId - 1) / 3) + 10)
      -- Clear the screen
      love.graphics.setColor(0.1, 0.1, 0.1)
      love.graphics.rectangle('fill', 0, 0, 200, 200)
      -- Draw each entity
      for _, entity in ipairs(client.gameWithoutPrediction.entities) do
        love.graphics.setColor(entity.color)
        love.graphics.rectangle('line', entity.x, entity.y, entity.width, entity.height)
      end
      for _, entity in ipairs(client.game.entities) do
        love.graphics.setColor(entity.color)
        love.graphics.rectangle('fill', entity.x, entity.y, entity.width, entity.height)
      end
      -- Draw the frame rate
      love.graphics.setColor(1, 1, 1)
      love.graphics.print('Frames per second: '..tostring(love.timer.getFPS()), 10, 10)
      if client.isConnecting() then
        love.graphics.print('Connecting...', 10, 25)
      elseif not client.isConnected() then
        love.graphics.print('Disconnected! :(', 10, 25)
      elseif not client.isStable() then
        love.graphics.print('Connected! Stabilizing...', 10, 25)
      else
        love.graphics.print('Connected! Latency: ' .. client.getFramesOfLatency(), 10, 25)
      end
    end
  end
end
