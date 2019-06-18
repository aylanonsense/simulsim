local stringUtils = require 'src/utils/string'
local tableUtils = require 'src/utils/table'
local marshal = require 'marshal'


local blah = { wow = 'a', wow1 = 'b', wow2 = 'c', 'd', 'e', 'f', 'g' }

function love.load()
end

function love.update(dt)
  -- 10,000 x (marshal.encode + marshal.decode) = 75% CPU + 20 fps
  for i = 1, 20000 do
    local abc = marshal.encode(blah)
    local def = marshal.decode(abc)
  end

  -- -- 10,000 x marshal.encode = 75% CPU + 30 fps
  -- for i = 1, 10000 do
  --   local abc = marshal.encode(blah)
  -- end

  -- -- 40,000 x marshal.encode = 10 fps (87% CPU)
  -- for i = 1, 15000 do
  --   local abc = marshal.encode(blah)
  -- end

  -- -- 40,000 x stringUtils.stringify = 9 fps (92% CPU)
  -- for i = 1, 40000 do
  --   local abc = stringUtils.stringify(blah)
  -- end

  -- -- 10,000 x stringutils.stringify = 80% CPU + 30 fps
  -- for i = 1, 10000 do
  --   local abc = stringUtils.stringify(blah)
  -- end

  -- -- 30,000 x tableUtils.cloneTable = 75% CPU + 20 fps
  -- for i = 1, 30000 do
  --   local abc = tableUtils.cloneTable(blah)
  -- end

  -- -- 30,000 x marshal.clone = 98% CPU + 10 fps
  -- for i = 1, 30000 do
  --   local abc = marshal.clone(blah)
  -- end
end

function love.draw()
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("Current FPS: "..tostring(love.timer.getFPS( )), 10, 10)
end
