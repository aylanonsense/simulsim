-- Load simulsim as a dependency (you should use a url for a specific commit)
local simulsim = require 'simulsim'

local game = simulsim.defineGame()
function game.update(self, dt)
  for _, entity in ipairs(self.entities) do
    entity.x = entity.x + entity.vx * dt
    entity.y = entity.y + entity.vy * dt
    if entity.x < 0 then
      entity.x, entity.vx = 0, math.abs(entity.vx)
    elseif entity.x > 400 - entity.width then
      entity.x, entity.vx = 400 - entity.width, -math.abs(entity.vx)
    end
    if entity.y < 0 then
      entity.y, entity.vy = 0, math.abs(entity.vy)
    elseif entity.y > 400 - entity.height then
      entity.y, entity.vy = 400 - entity.height, -math.abs(entity.vy)
    end
  end
end
function game.handleEvent(self, eventType, eventData)
  if eventType == 'spawn-box' then
    self:spawnEntity({
      x = eventData.x,
      y = eventData.y,
      width = 20,
      height = 20,
      vx = eventData.vx,
      vy = eventData.vy,
      color = eventData.color
    })
  end
end

local network, server, client = simulsim.createGameNetwork(game, { mode = 'development' })

function server.load()
  -- upwards of 20,000 entities without smoothing, receiving snapshots, or generating snapshots
  for i = 1, 12000 do
    server.fireEvent('spawn-box', {
      x = math.random(0, 10),
      y = math.random(0, 380),
      vx = 50,
      vy = 0,
      color = { math.random(), math.random(), math.random() }
    })
  end
end

function client.draw()
  -- Clear the screen
  love.graphics.clear(0.1, 0.1, 0.1)
  -- Draw each entity
  for _, entity in ipairs(client.game.entities) do
    love.graphics.setColor(entity.color)
    love.graphics.rectangle('fill', entity.x, entity.y, entity.width, entity.height)
  end
  -- Draw the frame rate
  love.graphics.setColor(1, 1, 1)
  love.graphics.print('Frames per second: '..tostring(love.timer.getFPS()), 10, 10)
end
