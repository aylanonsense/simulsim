local cs = require 'https://raw.githubusercontent.com/castle-games/share.lua/34cc93e9e35231de2ed37933d82eb7c74edfffde/cs.lua'
local update = love.update

return {
  client = cs.client,
  server = cs.server,
  update = update
}
