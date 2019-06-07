-- Load dependencies
local LocalTransportStream = require 'src/transport/LocalTransportStream'

describe('LocalTransportStream', function()
  -- Randomize the order of the test cases
  randomize()

  -- Keep track of network vars
  local stream
  after_each(function()
    stream = nil
  end)

  -- Helper method to create a new stream
  local function setUpStream(params)
    stream = LocalTransportStream:new(params)
  end

  -- Helper function that pretends time has passed
  local function progressTime(seconds)
    while seconds > 0 do
      local dt = math.min(seconds, 1 / 60)
      seconds = seconds - 1 / 60
      stream:update(dt)
    end
  end

  it('triggers the onReceive callback when send is called with the sent message', function()
    setUpStream({ latency = 0 })
    local receivedMessage = nil
    stream:onReceive(function(message) receivedMessage = message end)
    assert.falsy(receivedMessage)
    stream:send('hello')
    assert.equal(receivedMessage, 'hello')
  end)

  it('delays sent messages by an amount of time corresponding to its latency parameter', function()
    setUpStream({ latency = 200 })
    local receivedMessage = nil
    stream:onReceive(function(message) receivedMessage = message end)
    stream:send('hello')
    progressTime(0.190, stream)
    assert.falsy(receivedMessage)
    progressTime(0.020, stream)
    assert.equal(receivedMessage, 'hello')
  end)
end)
