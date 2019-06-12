local simulsim = require 'simulsim'

local NUM_CLIENTS = 4
local NUM_BOXES_PER_CLIENT = 20
local NUM_CLIENT_EVENTS_PER_SECOND = 275

local game = simulsim.defineGame()
function game.update(self, dt)
  for _, entity in ipairs(self.entities) do
    entity.x = math.min(math.max(0, entity.x + entity.vx * dt), 200 - entity.width)
    entity.y = math.min(math.max(0, entity.y + entity.vy * dt), 200 - entity.height)
  end
end
function game.handleEvent(self, eventType, eventData)
  if eventType == 'spawn-box' then
    self:spawnEntity({
      id = eventData.id,
      clientId = eventData.clientId,
      x = eventData.x,
      y = eventData.y,
      width = 5,
      height = 5,
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
  numClients = NUM_CLIENTS
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
    end
    server.fireEvent('spawn-box', {
      id = 'client-' .. client.clientId .. '-box-' .. i,
      clientId = client.clientId,
      x = math.random(0, 195),
      y = math.random(0, 195),
      vx = 0,
      vy = 0,
      color = color
    })
  end
end

-- Because numClients = 2, we have two clients to set up handlers for
for clientIndex, client in ipairs(network.clients) do
  function client.load()
    client.simulateNetworkConditions({ latency = 350, latencyDeviation = 100 })
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
    -- Offset the drawn elements so that you can see both clients' screens side-by-side
    love.graphics.reset()
    love.graphics.translate(210 * ((clientIndex - 1) % 2) + 10, 210 * math.floor((clientIndex - 1) / 2) + 10)
    -- Clear the screen
    love.graphics.setColor(0.1, 0.1, 0.1)
    love.graphics.rectangle('fill', 0, 0, 200, 200)
    -- Draw each entity
    for _, entity in ipairs(client.game.entities) do
      love.graphics.setColor(entity.color)
      love.graphics.rectangle('fill', entity.x, entity.y, entity.width, entity.height)
    end
    -- Draw the frame rate
    love.graphics.setColor(1, 1, 1)
    love.graphics.print('Frames per second: '..tostring(love.timer.getFPS()), 10, 10)
  end
end
