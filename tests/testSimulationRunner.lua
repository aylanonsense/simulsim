-- Load dependencies
local Simulation = require 'src/simulation/Simulation'
local SimulationRunner = require 'src/simulation/SimulationRunner'

describe('simulation runner', function()
  randomize()

  -- Define a simulation
  local simulationDefinition = Simulation:define({
    initialState = {
      data = {
        fruits = { 'apple' }
      }
    },
    handleEvent = function(self, eventType, eventData)
      if eventType == 'add-fruit' then
        table.insert(self.data.fruits, eventData.fruit)
      end
    end
  })

  local sim, runner

  -- Helper function that simulates advancing through time
  function progressFrames(numFrames)
    for i = 1, numFrames do
      runner:update(1 / 60)
    end
  end

  before_each(function()
    -- Create a simulation
    sim = simulationDefinition:new()
    -- Create a runner for that simulation
    runner = SimulationRunner:new({
      simulation = sim,
      framesOfHistory = 30,
      framesBetweenStateSnapshots = 5
    })
    -- Advance forward
    progressFrames(60)
  end)

  describe('update()', function()
    it('updates the simulation', function()
      progressFrames(60)
      assert.True(1.99 < sim.time and sim.time < 2.01)
      assert.is.equal(120, sim.frame)
      assert.is.same({ 'apple' }, sim.data.fruits)
    end)
  end)
  describe('setState()', function()
    it('sets the current state of the simulation', function()
      runner:setState({
        time = 1.50,
        frame = 90,
        nextEntityId = 1,
        inputs = {},
        data = {
          fruits = { 'cranberry' }
        },
        entities = {}
      })
      assert.is.equal(1.50, sim.time)
      assert.is.equal(90, sim.frame)
      assert.is.same({ 'cranberry' }, sim.data.fruits)
    end)
    it('undoes past events', function()
      runner:applyEvent({
        frame = 45,
        type = 'add-fruit',
        data = {
          fruit = 'mango'
        }
      })
      assert.is.same({ 'apple', 'mango' }, sim.data.fruits)
      runner:setState({
        time = 1.00,
        frame = 60,
        nextEntityId = 1,
        inputs = {},
        data = {
          fruits = { 'cranberry' }
        },
        entities = {}
      })
      assert.is.same({ 'cranberry' }, sim.data.fruits)
    end)
    it('maintains future events', function()
      runner:applyEvent({
        frame = 90,
        type = 'add-fruit',
        data = {
          fruit = 'mango'
        }
      })
      runner:setState({
        time = 1.00,
        frame = 60,
        nextEntityId = 1,
        inputs = {},
        data = {
          fruits = { 'cranberry' }
        },
        entities = {}
      })
      assert.is.same({ 'cranberry' }, sim.data.fruits)
      progressFrames(60)
      assert.is.same({ 'cranberry', 'mango' }, sim.data.fruits)
    end)
    it('prevents rewindings due to lost snapshots', function()
      runner:setState({
        time = 1.00,
        frame = 60,
        nextEntityId = 1,
        inputs = {},
        data = {
          fruits = { 'cranberry' }
        },
        entities = {}
      })
      assert.False(runner:applyEvent({
        frame = 45,
        type = 'add-fruit',
        data = {
          fruit = 'mango'
        }
      }))
      assert.is.same({ 'cranberry' }, sim.data.fruits)
    end)
  end)
  describe('applyEvent()', function()
    it('schedules events to occur in the future', function()
      runner:applyEvent({
        id = 'some-event',
        frame = 65,
        type = 'add-fruit',
        data = {
          fruit = 'orange'
        }
      })
      runner:applyEvent({
        id = 'some-other-event',
        frame = 80,
        type = 'add-fruit',
        data = {
          fruit = 'banana'
        }
      })
      assert.is.same({ 'apple' }, sim.data.fruits)
      progressFrames(60)
      assert.is.same({ 'apple', 'orange', 'banana' }, sim.data.fruits)
    end)
    it('immediately applies events that happened in the recent past', function()
      runner:applyEvent({
        frame = 30,
        type = 'add-fruit',
        data = {
          fruit = 'orange'
        }
      })
      runner:applyEvent({
        frame = 50,
        type = 'add-fruit',
        data = {
          fruit = 'banana'
        }
      })
      assert.is.same({ 'apple', 'orange', 'banana' }, sim.data.fruits)
    end)
    it('returns true if a future event was scheduled to be applied', function()
      assert.True(runner:applyEvent({
        frame = 100,
        type = 'add-fruit',
        data = {
          fruit = 'blueberry'
        }
      }))
    end)
    it('returns true if a past event was applied', function()
      assert.True(runner:applyEvent({
        frame = 30,
        type = 'add-fruit',
        data = {
          fruit = 'blueberry'
        }
      }))
    end)
    it('returns false if an event too far in the past could not be applied', function()
      assert.False(runner:applyEvent({
        frame = 29,
        type = 'add-fruit',
        data = {
          fruit = 'blueberry'
        }
      }))
    end)
    it('calls the simulation\'s handleEvent() method for each applied event', function()
      spy.on(sim, "handleEvent")
      runner:applyEvent({
        frame = 65,
        type = 'add-fruit',
        data = {
          fruit = 'blueberry'
        }
      })
      progressFrames(5)
      assert.spy(sim.handleEvent).was.called(1)
    end)
    it('does not call the simulation\'s handleEvent() method for input events', function()
      spy.on(sim, "handleEvent")
      runner:applyEvent({
        frame = 65,
        isInputEvent = true,
        type = 'set-inputs',
        clientId = 2,
        data = {
          left = true,
          right = false
        }
      })
      progressFrames(5)
      assert.spy(sim.handleEvent).was.called(0)
    end)
    it('does not include input events in the list of events passed to the simulation\'s update() method', function()
      runner:applyEvent({
        frame = 65,
        isInputEvent = true,
        type = 'set-inputs',
        clientId = 2,
        data = {
          left = true,
          right = false
        }
      })
      assert.is.same({}, sim.inputs)
      progressFrames(5)
      assert.is.same({ [2] = { left = true, right = false } }, sim.inputs)
    end)
    it('applies set-input events to the simulation\'s input data', function()
      runner:applyEvent({
        frame = 65,
        isInputEvent = true,
        type = 'set-inputs',
        clientId = 2,
        data = {
          left = true,
          right = false
        }
      })
      assert.is.same({}, sim.inputs)
      progressFrames(5)
      assert.is.same({ [2] = { left = true, right = false } }, sim.inputs)
    end)
  end)
  describe('unapplyEvent()', function()
    it('returns true if the event could be unapplied', function()
      runner:applyEvent({
        id = 'some-event-id',
        frame = 40,
        type = 'add-fruit',
        data = {
          fruit = 'orange'
        }
      })
      assert.True(runner:unapplyEvent('some-event-id'))
    end)
    it('returns false if the event could not be unapplied', function()
      runner:applyEvent({
        id = 'some-event-id',
        frame = 40,
        type = 'add-fruit',
        data = {
          fruit = 'orange'
        }
      })
      assert.False(runner:unapplyEvent('some-event-id-2'))
    end)
    it('undoes the effects of an event', function()
      runner:applyEvent({
        id = 'some-event-id',
        frame = 40,
        type = 'add-fruit',
        data = {
          fruit = 'orange'
        }
      })
      runner:applyEvent({
        id = 'some-other-event-id',
        frame = 45,
        type = 'add-fruit',
        data = {
          fruit = 'banana'
        }
      })
      assert.is.same({ 'apple', 'orange', 'banana' }, sim.data.fruits)
      runner:unapplyEvent('some-event-id')
      assert.is.same({ 'apple', 'banana' }, sim.data.fruits)
    end)
  end)
end)
