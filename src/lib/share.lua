local cs = require 'https://raw.githubusercontent.com/castle-games/share.lua/34cc93e9e35231de2ed37933d82eb7c74edfffde/cs.lua'

-- Get the client and server
local client = cs.client
local server = cs.server

-- We'll call share.lua's update method manually, so override it
local update = love.update
function love.update() end

return {
  client = client,
  server = server,
  update = update
}
