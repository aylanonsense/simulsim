-- Load dependencies
local Simulation = require 'src/simulation/Simulation'
local SimulationRunner = require 'src/simulation/SimulationRunner'

describe('simulation runner', function()
  local sim, runner

  -- Helper function that simulates advancing through time
  function progressFrames(numFrames)
    for i = 1, numFrames do
      runner:update(1 / 60)
    end
  end

  before_each(function()
    -- Create a simulation
    sim = Simulation:new()
    sim.update = function(self, dt, inputs, events, isTopFrame)
      for _, event in ipairs(events) do
        if event.type == 'add-fruit' then
          table.insert(self.data.fruits, event.fruit)
        end
      end
    end
    -- Create a runner for that simulation
    runner = SimulationRunner:new({
      simulation = sim,
      framesOfHistory = 30,
      framesBetweenStateSnapshots = 5
    })
    -- Set the initial state
    runner:setState({
      time = 0.00,
      frame = 0,
      nextEntityId = 1,
      data = {
        fruits = { 'apple' }
      },
      entities = {}
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
        fruit = 'mango'
      })
      assert.is.same({ 'apple', 'mango' }, sim.data.fruits)
      runner:setState({
        time = 1.00,
        frame = 60,
        nextEntityId = 1,
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
        fruit = 'mango'
      })
      runner:setState({
        time = 1.00,
        frame = 60,
        nextEntityId = 1,
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
        data = {
          fruits = { 'cranberry' }
        },
        entities = {}
      })
      assert.False(runner:applyEvent({
        frame = 45,
        type = 'add-fruit',
        fruit = 'mango'
      }))
      assert.is.same({ 'cranberry' }, sim.data.fruits)
    end)
  end)
  describe('applyEvent()', function()
    it('schedules events to occur in the future', function()
      runner:applyEvent({
        frame = 65,
        type = 'add-fruit',
        fruit = 'orange'
      })
      runner:applyEvent({
        frame = 80,
        type = 'add-fruit',
        fruit = 'banana'
      })
      assert.is.same({ 'apple' }, sim.data.fruits)
      progressFrames(60)
      assert.is.same({ 'apple', 'orange', 'banana' }, sim.data.fruits)
    end)
    it('immediately applies events that happened in the recent past', function()
      runner:applyEvent({
        frame = 30,
        type = 'add-fruit',
        fruit = 'orange'
      })
      runner:applyEvent({
        frame = 50,
        type = 'add-fruit',
        fruit = 'banana'
      })
      assert.is.same({ 'apple', 'orange', 'banana' }, sim.data.fruits)
    end)
    it('returns true if a future event was scheduled to be applied', function()
      assert.True(runner:applyEvent({
        frame = 100,
        type = 'add-fruit',
        fruit = 'blueberry'
      }))
    end)
    it('returns true if a past event was applied', function()
      assert.True(runner:applyEvent({
        frame = 30,
        type = 'add-fruit',
        fruit = 'blueberry'
      }))
    end)
    it('returns false if an event too far in the past could not be applied', function()
      assert.False(runner:applyEvent({
        frame = 29,
        type = 'add-fruit',
        fruit = 'blueberry'
      }))
    end)
  end)
end)
