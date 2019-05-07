local marshal = require 'marshal'
local share = require 'src/lib/share'

--- Creates a new client-side connection that's able to connect to a server
local ShareConnection = {}
function ShareConnection:new(params)
  params = params or {}
  local isLocalhost = params.isLocalhost ~= false
  local port = params.port or 22122

  local conn = {
    -- Private vars
    _isLocalhost = isLocalhost,
    _port = port,
    _connectCallbacks = {},
    _disconnectCallbacks = {},
    _receiveCallbacks = {},

    -- Public methods
    connect = function(self)
      -- Start connecting to a localhost server
      if self._isLocalhost then
        share.client.enabled = true
        share.client.start('127.0.0.1:' .. self._port)
      -- Start connecting a proper remote server
      else
        share.client.useCastleConfig()
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
