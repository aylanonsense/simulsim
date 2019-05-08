-- Load dependencies
local simulsim = require 'simulsim'

-- Render constants
local GAME_WIDTH = 200
local GAME_HEIGHT = 200
local RENDER_SCALE = 1

-- Asset variables
local spriteSheet
local quads
local sounds

-- Define a new game
local gameDef = simulsim.defineGame({
  update = function(self, dt)
    for _, entity in ipairs(self.entities) do
      if entity.type == 'ball' then
        -- Move the ball
        entity.x = entity.x + entity.vx * dt
        entity.y = entity.y + entity.vy * dt
        -- Bounce the ball off of walls
        local bouncedOffSideWalls = false
        if entity.x < 0 then
          entity.x = 0
          entity.vx = math.abs(entity.vx)
          bouncedOffSideWalls = true
        elseif entity.x + entity.width > GAME_WIDTH then
          entity.x = GAME_WIDTH - entity.width
          entity.vx = -math.abs(entity.vx)
          bouncedOffSideWalls = true
        end
        if entity.y < 0 then
          entity.y = 0
          entity.vy = math.abs(entity.vy)
        elseif entity.y + entity.height > GAME_HEIGHT then
          entity.y = GAME_HEIGHT - entity.height
          entity.vy = -math.abs(entity.vy)
        end
        -- Apply friction to the ball's velocity
        entity.vx = entity.vx * 0.999
        entity.vy = entity.vy * 0.999
        -- Check to see if the ball entered the goal
        if bouncedOffSideWalls and 80 < entity.y and entity.y < 108 - entity.height then
          entity.x = GAME_WIDTH / 2 - 5
          entity.y = GAME_HEIGHT / 2 - 5
          entity.vx = 0
          entity.vy = 0
          -- if self.isClient then
            -- love.audio.play(sounds.goal:clone())
          -- end
        end
      elseif entity.type == 'tank' then
        local inputs = self.inputs[entity.clientId] or {}
        -- Change velocity in response to player input
        entity.vx = 250 * ((inputs.right and 1 or 0) - (inputs.left and 1 or 0))
        entity.vy = 250 * ((inputs.down and 1 or 0) - (inputs.up and 1 or 0))
        if entity.vx ~= 0 then
          entity.vy = 0
          entity.isFacingHorizontal = true
        elseif entity.vy ~=0 then
          entity.isFacingHorizontal = false
        end
        -- Keep the player in bounds
        entity.x = clamp(0, entity.x + entity.vx * dt, GAME_WIDTH - entity.width)
        entity.y = clamp(0, entity.y + entity.vy * dt, GAME_HEIGHT - entity.height)
        -- Reduce shoot cooldown
        entity.shootCooldown = math.max(0.00, entity.shootCooldown - dt)
      elseif entity.type == 'bullet' then
        -- Move the bullet
        entity.x = entity.x + entity.vx * dt
        entity.y = entity.y + entity.vy * dt
        -- Check for hits
        for _, entity2 in ipairs(self.entities) do
          if isOverlapping(entity, entity2) then
            -- Bullets push players back a bit
            if entity2.type == 'tank' and entity.team ~= entity2.team then
              self:temporarilyDisableSyncForEntity(entity2)
              -- self:temporarilyDisableSyncForEntity(entity)
              -- self:disableSyncForEntity(entity2)
              -- self:temporarilyDisableSyncForEntity(entity)
              -- entity2.x = entity2.x + 6 * entity.vx * dt
              -- entity2.y = entity2.y + 6 * entity.vy * dt
              entity2.x = 50
              entity2.y = 50
              self:despawnEntity(entity)
              -- if self.isClient then
                -- love.audio.play(sounds.bulletHit:clone())
              -- end
            -- Bullets push balls away
            elseif entity2.type == 'ball' then
              -- self:temporarilyDisableSyncForEntity(entity2)
              -- if entity.clientId ~= self.clientId then 
              entity2.clientId = entity.clientId
                local dx = entity2.x - entity.x
                local dy = entity2.y - entity.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist > 0 then
                  entity2.vx = (entity2.vx + entity.vx + 50 * dx / dist) / 2
                  entity2.vy = (entity2.vy + entity.vy + 50 * dy / dist) / 2
                end
              -- end
              self:despawnEntity(entity)
              -- if self.isClient then
                -- love.audio.play(sounds.ballHit:clone())
              -- end
            -- Bullets cancel each other out
            elseif entity2.type == 'bullet' and entity.team ~= entity2.team then
              self:despawnEntity(entity)
              self:despawnEntity(entity2)
              -- if self.isClient then
                -- love.audio.play(sounds.bulletHit:clone())
              -- end
            end
          end
        end
        -- Despawn the bullet if it goes off screen
        if entity.x > GAME_WIDTH or entity.y > GAME_HEIGHT or entity.x < -entity.width or entity.y < -entity.height then
          self:despawnEntity(entity)
        end
      end
    end
  end,
  handleEvent = function(self, type, data)
    if type == 'spawn-ball' then
      self:spawnEntity({
        type = 'ball',
        x = GAME_WIDTH / 2 - 5,
        y = GAME_HEIGHT / 2 - 5,
        width = 10,
        height = 10,
        vx = 0,
        vy = 0
      })
    elseif type == 'spawn-tank' then
      self:spawnEntity({
        type = 'tank',
        clientId = data.clientId,
        team = data.team,
        x = data.x,
        y = data.y,
        width = 16,
        height = 16,
        vx = 0,
        vy = 0,
        shootCooldown = 0.00,
        isFacingHorizontal = true
      })
    elseif type == 'shoot-bullet' then
      local tank
      for _, entity in ipairs(self.entities) do
        if entity.type == 'tank' and entity.clientId == data.clientId then
          tank = entity
          break
        end
      end
      if tank and tank.shootCooldown <= 0.00 then
        local aimAngle = math.atan2((data.aimY or 0) - tank.y - tank.width / 2, (data.aimX or 0) - tank.x - tank.height / 2)
        tank.shootCooldown = 1.00
        self:spawnEntity({
          type = 'bullet',
          clientId = tank.clientId,
          team = tank.team,
          x = tank.x + tank.width / 2 - 2.5,
          y = tank.y + tank.height / 2 - 2.5,
          width = 5,
          height = 5,
          vx = 64 * math.cos(aimAngle),
          vy = 64 * math.sin(aimAngle),
          angle = aimAngle
        })
        -- if self.isClient then
          -- love.audio.play(sounds.shoot:clone())
        -- end
      end
    end
  end
})

-- Create a new network
local network = simulsim.createGameNetwork({
  mode = 'development',
  numClients = 3,
  gameDefinition = gameDef
})
local server, client, clients = network.server, network.client, network.clients

local nextTankTeam = 1

function server.load()
  server.fireEvent('spawn-ball')
end

function server.clientconnected(client)
  server.fireEvent('spawn-tank', {
    clientId = client.clientId,
    team = nextTankTeam,
    x = math.random(20, GAME_WIDTH - 20),
    y = math.random(20, GAME_WIDTH - 20)
  })
  nextTankTeam = 3 - nextTankTeam
end

for clientIndex, client in ipairs(clients) do
  -- function client.smoothEntity(self, game, entity, idealEntity)
  --   return entity
  -- end

  -- function client.smoothEntity(game, entity, idealEntity)
  --   if idealEntity and entity and (entity.type == 'tank' or entity.type == 'ball') then
  --     local dx, dy = idealEntity.x - entity.x, idealEntity.y - entity.y
  --     idealEntity.x = entity.x + dx / 10
  --     idealEntity.y = entity.y + dy / 10
  --   end
  --   return idealEntity
  -- end

  function client.load()
    client.simulateNetworkConditions({
      latency = 500,
      -- latencyDeviation = 50,
    })
    -- Load images
    -- spriteSheet = love.graphics.newImage('img/sprite-sheet.png')
    -- spriteSheet:setFilter('nearest', 'nearest')
    -- -- Calculate the quads within the sprite sheet
    -- local width, height = spriteSheet:getDimensions()
    -- quads = {
    --   ball = love.graphics.newQuad(22, 34, 10, 10, width, height),
    --   teams = {
    --     {
    --       tankVertical = love.graphics.newQuad(22, 0, 16, 16, width, height),
    --       tankHorizontal = love.graphics.newQuad(39, 0, 16, 16, width, height),
    --       goal = love.graphics.newQuad(0, 0, 10, 40, width, height),
    --       bullet = love.graphics.newQuad(56, 6, 8, 5, width, height)
    --     },
    --     {
    --       tankVertical = love.graphics.newQuad(22, 17, 16, 16, width, height),
    --       tankHorizontal = love.graphics.newQuad(39, 17, 16, 16, width, height),
    --       goal = love.graphics.newQuad(11, 0, 10, 40, width, height),
    --       bullet = love.graphics.newQuad(56, 23, 8, 5, width, height)
    --     }
    --   }
    -- }
    -- -- Load sounds
    -- sounds = {
    --   goal = love.audio.newSource('sfx/goal.wav', 'static'),
    --   shoot = love.audio.newSource('sfx/shoot.wav', 'static'),
    --   ballHit = love.audio.newSource('sfx/ball-hit.wav', 'static'),
    --   bulletHit = love.audio.newSource('sfx/bullet-hit.wav', 'static')
    -- }
  end

  function client.update(dt)
    if clientIndex == 1 then
      client.setInputs({
        up = love.keyboard.isDown('w'),
        left = love.keyboard.isDown('a'),
        down = love.keyboard.isDown('s'),
        right = love.keyboard.isDown('d')
      })
    elseif clientIndex == 2 then
      client.setInputs({
        up = love.keyboard.isDown('up'),
        left = love.keyboard.isDown('left'),
        down = love.keyboard.isDown('down'),
        right = love.keyboard.isDown('right')
      })
    end
  end

  function client.mousepressed(x, y, button)
    if clientIndex == button then
      client.fireEvent('shoot-bullet', {
        clientId = client.clientId,
        aimX = (x - (clientIndex == 2 and RENDER_SCALE * (GAME_WIDTH + 10) or 0)) / RENDER_SCALE,
        aimY = y / RENDER_SCALE
      }, { predictClientSide = true })
    end
  end

  -- Draws the game
  function client.draw()
    local x = (GAME_WIDTH + 10) * (clientIndex - 1)
    local y = 0

    if clientIndex == 1 then
      -- Scale up the screen
      love.graphics.scale(RENDER_SCALE, RENDER_SCALE)
    end

    drawGame(client.game, client.gameWithoutPrediction, x, y)
    -- if client._client.lastSnapshot then
    --   drawGame(client._client.lastSnapshot, nil, x, y + GAME_HEIGHT + 10)
    -- end

    -- Draw network stats
    love.graphics.setColor(0, 0, 0)
    love.graphics.print('client id: ' .. (client.clientId or '--'), x + 4, y + 2)
    love.graphics.print('status: ' .. (client.isSynced() and 'synced' or (client.isConnected() and 'syncing' or (client.isConnecting() and 'connecting' or 'disconnected'))), x + 4, y + 18)
    love.graphics.print('latency: ' .. client:getFramesOfLatency() .. ' frames', x + 4, y + 34)
    love.graphics.print('frame rate: '  ..  tostring(love.timer.getFPS( )), x + 4, y + 50)
  end

  function client.synced()
    print('client.synced')
  end

  function client.desynced()
    print('client desynced')
  end
end

function drawGame(game1, game2, x, y)
  -- Clear the screen
  love.graphics.setColor(244 / 255, 56 / 255, 11 / 255)
  love.graphics.rectangle('fill', x, y, GAME_WIDTH, GAME_HEIGHT)
  love.graphics.setColor(1, 1, 1)

  -- Draw the goals
  -- love.graphics.draw(spriteSheet, quads.teams[1].goal, x + 1, 77)
  -- love.graphics.draw(spriteSheet, quads.teams[2].goal, x + GAME_WIDTH - 11, 77)

  -- Draw server-side entities
  if game2 then
    for _, entity in ipairs(game2.entities) do
      love.graphics.setColor(0, 1, 0)
      love.graphics.rectangle('line', x + entity.x, y + entity.y, entity.width, entity.height)
    end
  end

  -- Draw all the entities
  for _, entity in ipairs(game1.entities) do
    love.graphics.setColor(0, 1, 0)
    love.graphics.rectangle('fill', x + entity.x, y + entity.y, entity.width, entity.height)
    love.graphics.setColor(1, 1, 1)
    -- if entity.type == 'bullet' then
    --   love.graphics.draw(spriteSheet, quads.teams[entity.team].bullet, x + entity.x + entity.width / 2, entity.y + entity.height / 2, entity.angle, 1, 1, 4, 2.5)
    -- elseif entity.type == 'tank' then
    --   if entity.isFacingHorizontal then
    --     love.graphics.draw(spriteSheet, quads.teams[entity.team].tankHorizontal, x + entity.x, entity.y)
    --   else
    --     love.graphics.draw(spriteSheet, quads.teams[entity.team].tankVertical, x + entity.x, entity.y)
    --   end
    -- elseif entity.type == 'ball' then
    --   love.graphics.draw(spriteSheet, quads.ball, x + entity.x, entity.y)
    -- end
  end
end

-- Keeps a number between the given minimum and maximum values
function clamp(minimum, num, maximum)
  return math.min(math.max(minimum, num), maximum)
end

-- Checks to see if two entities are overlapping using AABB detection
function isOverlapping(entity1, entity2)
  return entity1.x + entity1.width > entity2.x and entity2.x + entity2.width > entity1.x
    and entity1.y + entity1.height > entity2.y and entity2.y + entity2.height > entity1.y
end
