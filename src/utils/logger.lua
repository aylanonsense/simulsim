local LOG_LEVEL_PRIORITIES = {
  NONE = 0,
  ERROR = 1,
  WARN = 2,
  INFO = 3,
  VERBOSE = 4,
  DEBUG = 5,
  SILLY = 6
}

local logLevel = 'NONE'

local function setLogLevel(lvl)
  logLevel = lvl
end

local function error(...)
  if LOG_LEVEL_PRIORITIES[logLevel] >= LOG_LEVEL_PRIORITIES.ERROR then
    print('ERROR:', ...)
  end
end

local function warn(...)
  if LOG_LEVEL_PRIORITIES[logLevel] >= LOG_LEVEL_PRIORITIES.WARN then
    print('WARN:', ...)
  end
end

local function info(...)
  if LOG_LEVEL_PRIORITIES[logLevel] >= LOG_LEVEL_PRIORITIES.INFO then
    print('INFO:', ...)
  end
end

local function verbose(...)
  if LOG_LEVEL_PRIORITIES[logLevel] >= LOG_LEVEL_PRIORITIES.VERBOSE then
    print('VERBOSE:', ...)
  end
end

local function debug(...)
  if LOG_LEVEL_PRIORITIES[logLevel] >= LOG_LEVEL_PRIORITIES.DEBUG then
    print('DEBUG:', ...)
  end
end

local function silly(...)
  if LOG_LEVEL_PRIORITIES[logLevel] >= LOG_LEVEL_PRIORITIES.SILLY then
    print('SILLY:', ...)
  end
end

return {
  setLogLevel = setLogLevel,
  error = error,
  warn = warn,
  info = info,
  verbose = verbose,
  debug = debug,
  silly = silly
}
