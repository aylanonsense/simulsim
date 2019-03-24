local Client = {}
function Client:new(params)
  local conn = params and params.conn

  -- The client is just the connection, TBD if this class is necessary
  return conn
end

return Client
