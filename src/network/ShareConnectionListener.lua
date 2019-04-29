local marshal = require 'marshal'
local share = require 'src/lib/share'

--- Creates a new server-side connection listener that can have multiple client-side connections connect to it
local ShareConnectionListener = {}
function ShareConnectionListener:new(params)
  params = params or {}
  local isLocalhost = params.isLocalhost ~= false
  local port = params.port or 22122

  local listener = {
    -- Private vars
    _isLocalhost = isLocalhost,
    _port = port,
    _connections = {},
    _connectCallbacks = {},
    _disconnectCallbacks = {},
    _receiveCallbacks = {},

    -- Public methods
    startListening = function(self)
      -- Start a localhost server
      if self._isLocalhost then
        share.server.enabled = true
        share.server.start('' .. self._port)
      -- Start a proper dedicated server
      else
        share.server.useCastleConfig()
      end
    end,
    isListening = function(self)
      return share.server.started
    end,
    disconnect = function(self, connId)
      share.server.kick(connId)
    end,
    isConnected = function(self, connId)
      return self._connections[connId]
    end,
    send = function(self, connId, msg)
      share.server.sendExt(connId, nil, nil, marshal.encode(msg))
    end,
    update = function(self, dt) end,

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
    _handleConnect = function(self, connId)
      self._connections[connId] = true
      for _, callback in ipairs(self._connectCallbacks) do
        callback(connId)
      end
    end,
    _handleDisconnect = function(self, connId)
      self._connections[connId] = nil
      for _, callback in ipairs(self._disconnectCallbacks) do
        callback(connId)
      end
    end,
    _handleReceive = function(self, connId, msg)
      for _, callback in ipairs(self._receiveCallbacks) do
        callback(connId, msg)
      end
    end
  }

  -- Bind events
  function share.server.connect(connId)
    listener:_handleConnect(connId)
  end
  function share.server.disconnect(connId)
    listener:_handleDisconnect(connId)
  end
  function share.server.receive(connId, msg)
    listener:_handleReceive(connId, marshal.decode(msg))
  end

  return listener
end

return ShareConnectionListener
