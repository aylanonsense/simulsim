-- Game entities
local player
local entities

function love.load()
  -- Create the game entities
  entities = {}
  player = {
    isPlayerControlled = true,
    x = math.random(10, 280),
    y = math.random(10, 280),
    color = { math.random(), math.random(), math.random() }
  }
  table.insert(entities, player)
end

function love.update(dt)
  -- Keep track of inputs
  local inputs = {
    up = love.keyboard.isDown('up') or love.keyboard.isDown('w'),
    left = love.keyboard.isDown('left') or love.keyboard.isDown('a'),
    down = love.keyboard.isDown('down') or love.keyboard.isDown('s'),
    right = love.keyboard.isDown('right') or love.keyboard.isDown('d')
  }
  -- Update all game entities
  for _, entity in ipairs(entities) do
    if entity.isPlayerControlled then
      entity.x = math.min(math.max(0, entity.x + 100 * dt * ((inputs.right and 1 or 0) - (inputs.left and 1 or 0))), 280)
      entity.y = math.min(math.max(0, entity.y + 100 * dt * ((inputs.down and 1 or 0) - (inputs.up and 1 or 0))), 280)
    end
  end
end

-- Change colors by pressing the C key
function love.keypressed(key)
  if key == 'c' then
    player.color = { math.random(), math.random(), math.random() }
  end
end

-- Draw the game
function love.draw()
  -- Reset the canvas
  love.graphics.setColor(0.5, 0.5, 0.5)
  love.graphics.rectangle('fill', 0, 0, 300, 300)
  -- Draw entities
  for _, entity in ipairs(entities) do
    love.graphics.setColor(entity.color)
    love.graphics.rectangle('fill', entity.x, entity.y, 20, 20)
  end
end
