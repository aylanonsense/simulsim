local LOG_LEVEL_PRIORITIES = {
  NONE = 0,
  ERROR = 1,
  WARN = 2,
  INFO = 3,
  VERBOSE = 4,
  DEBUG = 5,
  SILLY = 6
}

local logLevel = 'INFO'

local function setLogLevel(lvl)
  logLevel = lvl
end

local function isLogging(lvl)
  return LOG_LEVEL_PRIORITIES[logLevel] >= LOG_LEVEL_PRIORITIES[lvl]
end

local function error(...)
  if isLogging('ERROR') then
    print('ERROR:', ...)
  end
end

local function warn(...)
  if isLogging('WARN') then
    print('WARN:', ...)
  end
end

local function info(...)
  if isLogging('INFO') then
    print('INFO:', ...)
  end
end

local function verbose(...)
  if isLogging('VERBOSE') then
    print('VERBOSE:', ...)
  end
end

local function debug(...)
  if isLogging('DEBUG') then
    print('DEBUG:', ...)
  end
end

local function silly(...)
  if isLogging('SILLY') then
    print('SILLY:', ...)
  end
end

return {
  setLogLevel = setLogLevel,
  isLogging = isLogging,
  error = error,
  warn = warn,
  info = info,
  verbose = verbose,
  debug = debug,
  silly = silly
}
