local marshal = require 'marshal'
local share = require 'src/lib/share'
local stringUtils = require 'src/utils/string'

--- Creates a new client-side connection that's able to connect to a server
local ShareConnection = {}
function ShareConnection:new()
  local conn = {
    -- Private vars
    _connectCallbacks = {},
    _disconnectCallbacks = {},
    _receiveCallbacks = {},

    -- Public methods
    connect = function(self)
      -- Start connecting
      if USE_CASTLE_CONFIG then
        share.client.useCastleConfig()
      else
        share.client.enabled = true
        share.client.start('127.0.0.1:22122')
      end
    end,
    disconnect = function(self)
      share.client.kick()
    end,
    isConnected = function(self)
      return share.client.connected
    end,
    send = function(self, msg)
      share.client.send(marshal.encode(msg))
    end,
    update = function(self, dt) end,
    simulateNetworkConditions = function(self, params) end,

    -- Callback methods
    onConnect = function(self, callback)
      table.insert(self._connectCallbacks, callback)
    end,
    onDisconnect = function(self, callback)
      table.insert(self._disconnectCallbacks, callback)
    end,
    onReceive = function(self, callback)
      table.insert(self._receiveCallbacks, callback)
    end,

    -- Private methods
    _handleConnect = function(self)
      for _, callback in ipairs(self._connectCallbacks) do
        callback()
      end
    end,
    _handleDisconnect = function(self)
      for _, callback in ipairs(self._disconnectCallbacks) do
        callback()
      end
    end,
    _handleReceive = function(self, msg)
      for _, callback in ipairs(self._receiveCallbacks) do
        callback(msg)
      end
    end
  }

  -- Bind events
  function share.client.connect()
    conn:_handleConnect()
  end
  function share.client.disconnect()
    conn:_handleDisconnect()
  end
  function share.client.receive(msg)
    conn:_handleReceive(marshal.decode(msg))
  end

  return conn
end

return ShareConnection
