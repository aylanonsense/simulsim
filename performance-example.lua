local simulsim = require 'simulsim'

simulsim.setLogLevel('DEBUG')

local NUM_CLIENTS = 1
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
    if entity.y < 70 then
      entity.y = 70
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
    id = 'box-for-client-' .. client.clientId,
    clientId = client.clientId,
    x = math.random(0, 190),
    y = math.random(70, 190),
    vx = 0,
    vy = 0,
    color = color
  })
end

-- Because numClients = 2, we have two clients to set up handlers for
for _, client in ipairs(network.clients) do
  local x, y, width, height, vx, vy
  local jitterList = {}
  local frame = 0
  local jitteriness = 0
  local prevSumOfSquares = 0

  function client.load()
    client.simulateNetworkConditions({ latency = 350, latencyDeviation = 200 })
    client.timer =  math.random()
  end

  function client.update(dt)
    frame = frame + 1
    if client.isConnected() then
      client.timer = client.timer + dt
      local hasChangedVelocity = false
      while client.timer > 1 / NUM_CLIENT_EVENTS_PER_SECOND do
        hasChangedVelocity = true
        client.fireEvent('change-box-velocity', {
          entityId = 'box-for-client-' .. client.clientId,
          vx = math.random(-50, 50),
          vy = math.random(-50, 50)
        })
        client.timer = client.timer - 1 / NUM_CLIENT_EVENTS_PER_SECOND
      end
    end
    if client.clientId then
      local box = client.game:getEntityById('box-for-client-' .. client.clientId)
      local distFromActual = 0
      if box then
        if not hasChangedVelocity and x and y and width and height and vx and vy then
          x = x + vx * dt
          y = y + vy * dt
          if x < 0 then
            x = 0
            vx = math.abs(vx)
          elseif x > 200 - width then
            x = 200 - width
            vx = -math.abs(vx)
          end
          if y < 70 then
            y = 70
            vy = math.abs(vy)
          elseif y > 200 - height then
            y = 200 - height
            vy = -math.abs(vy)
          end
          local dx = box.x - x
          local dy = box.y - y
          distFromActual = math.sqrt(dx * dx + dy * dy)
        end
        x = box.x
        y = box.y
        width = box.width
        height = box.height
        vx = box.vx
        vy = box.vy
      end
      jitterList[frame % 240 + 1] = distFromActual
      local sumOfSquares = 0
      for i = 1, #jitterList do
        local n = jitterList[i] or 0
        if n < 2 then
          n = 0
        elseif n > 12 then
          n = 12
        end
        sumOfSquares = sumOfSquares + n * n
      end
      if sumOfSquares <= 0 then
        jitteriness = 'none'
      elseif sumOfSquares > 400 then
        jitteriness = 'TONS' .. ' (' .. math.floor(sumOfSquares) .. ')'
      elseif sumOfSquares > 200 then
        jitteriness = 'lots' .. ' (' .. math.floor(sumOfSquares) .. ')'
      elseif sumOfSquares > 100 then
        jitteriness = 'some' .. ' (' .. math.floor(sumOfSquares) .. ')'
      else
        jitteriness = 'a bit' .. ' (' .. math.floor(sumOfSquares) .. ')'
      end
      if sumOfSquares > prevSumOfSquares then
        print('jitteriness increased for client ' .. client.clientId .. ' to ' .. jitteriness)
      end
      prevSumOfSquares = sumOfSquares
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
      -- for _, entity in ipairs(client.gameWithoutPrediction.entities) do
      --   love.graphics.setColor(entity.color)
      --   love.graphics.rectangle('line', entity.x, entity.y, entity.width, entity.height)
      -- end
      for _, entity in ipairs(client.game.entities) do
        love.graphics.setColor(entity.color)
        love.graphics.rectangle('fill', entity.x, entity.y, entity.width, entity.height)
      end
      -- Draw the frame rate
      love.graphics.setColor(0.3, 0.3, 0.3)
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
      if jitteriness == 'none' then
        love.graphics.setColor(0.7, 0.7, 0.7)
      else
        love.graphics.setColor(1, 1, 1)
      end
      love.graphics.print('Jitteriness: ' .. jitteriness, 10, 40)
    end
  end
end
