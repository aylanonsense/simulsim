-- Load dependencies
local LocalTransportStream = require 'src/transport/LocalTransportStream'

describe('LocalTransportStream', function()
  -- Randomize the order of the test cases
  randomize()

  -- Helper function that pretends time has passed
  function progressTime(stream, seconds)
    while seconds > 0 do
      stream:update(math.min(seconds, 1 / 60))
      seconds = seconds - 1 / 60
    end
  end

  it('triggers the onReceive callback when send is called with the sent message', function()
    local stream = LocalTransportStream:new({ latency = 0 })
    local receivedMessage = nil
    stream:onReceive(function(message) receivedMessage = message end)
    assert.falsy(receivedMessage)
    stream:send('hello')
    assert.equal(receivedMessage, 'hello')
  end)

  it('delays sent messages by an amount of time corresponding to its latency parameter', function()
    local stream = LocalTransportStream:new({ latency = 250 })
    local receivedMessage = nil
    stream:onReceive(function(message) receivedMessage = message end)
    assert.falsy(receivedMessage)
    stream:send('hello')
    assert.falsy(receivedMessage)
    progressTime(stream, 0.240)
    assert.falsy(receivedMessage)
    progressTime(stream, 0.020)
    assert.equal(receivedMessage, 'hello')
  end)
end)
