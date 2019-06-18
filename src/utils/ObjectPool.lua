local tableUtils = require 'src/utils/table'

local ObjectPool = {}

function ObjectPool:new = function()
  return {
    _objects = {},
    _index = 1,
    requisition = function(self, shouldClearProps)
      if not self._objects[self._index] then
        self._objects[self._index] = {}
      elseif shouldClearProps then
        tableUtils.clearProps(self._objects[self._index])
      end
      self._index = self._index + 1
      return self._objects[self._index - 1]
    end,
    reset = function(self)
      self._index = 1
    end
  }
end

return ObjectPool
