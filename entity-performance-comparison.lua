local entities = {}

function love.load()
  for i = 1, 40000 do
    table.insert(entities, {
      x = math.random(0, 10),
      y = math.random(0, 380),
      width = 20,
      height = 20,
      vx = 50,
      vy = 0,
      color = { math.random(), math.random(), math.random() }
    })
  end
end

function love.update(dt)
  for _, entity in ipairs(entities) do
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

function love.draw()
  -- Clear the screen
  love.graphics.clear(0.1, 0.1, 0.1)
  -- Draw each entity
  for _, entity in ipairs(entities) do
    love.graphics.setColor(entity.color)
    love.graphics.rectangle('fill', entity.x, entity.y, entity.width, entity.height)
  end
  -- Draw the frame rate
  love.graphics.setColor(1, 1, 1)
  love.graphics.print('Frames per second: '..tostring(love.timer.getFPS()), 10, 10)
end
