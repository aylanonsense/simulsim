-- Generates a random string of the given length using the characters A-Za-z0-9
local function generateRandomString(len)
  -- Start with a blank string
  local s = ''
  -- Add random characters onto the end of the string
  for i = 1, len do
    local randomNumber = math.random(0, 61)
    -- 0-9 (character codes 48 to 57)
    if randomNumber < 10 then
      randomNumber = randomNumber + 48
    -- A-Z (character codes 65 to 90)
    elseif randomNumber < 36 then
      randomNumber = randomNumber + 55
    -- a-z (character codes 97 to 122)
    else
      randomNumber = randomNumber + 61
    end
    s = s .. string.char(randomNumber)
  end
  -- Return the string
  return s
end

-- Stringifies any value
local function stringify(value, isExpanded, indent)
  indent = indent or 0
  local t = type(value)
  if t == 'boolean' then
    return tostring(value)
  elseif t == 'string' then
    return '"' .. value .. '"'
  elseif t == 'function' then
    return 'fn()'
  elseif t == 'number' then
    return '' .. value
  elseif t == 'nil' then
    return 'nil'
  elseif t == 'table' then
    -- Calculate indent
    local indentString = ''
    for i = 1, indent do
      indentString = indentString .. '  '
    end
    local separator = isExpanded and '\n' .. indentString .. '  ' or ' '
    local terminalSeparator = isExpanded and '\n' .. indentString or ' '
    -- Figure out if this should be printed as an array or an object
    local hasKeys = false
    local hasNonArrayKeys = false
    local hasNonStringKeys = false
    for k, v in pairs(value) do
      local t2 = type(k)
      hasKeys = true
      if t2 ~= 'string' then
        hasNonStringKeys = true
      end
      if t2 == 'string' or (t2 == 'number' and k <= 0) then
        hasNonArrayKeys = true
      end
    end
    -- Trivial case
    if not hasKeys then
      return '{}'
    -- Print as an object
    elseif hasNonArrayKeys or #value <= 0 then
      local s = '{'
      local isFirstProperty = true
      for k, v in pairs(value) do
        if isFirstProperty then
          isFirstProperty = false
        else
          s = s .. ','
        end
        s = s .. separator
        if hasNonStringKeys then
          s = s .. '[' .. stringify(k) .. '] = '
        else
          s = s .. k .. ' = '
        end
        s = s .. stringify(v, isExpanded, indent + 1)
      end
      return s .. terminalSeparator .. '}'

    -- Print as an array
    else
      local s = '['
      for i = 1, #value do
        if i > 1 then
          s = s .. ','
        end
        s = s .. separator .. stringify(value[i])
      end
      return s .. terminalSeparator .. ']'
    end
  else
    return '???'
  end
end

return {
  generateRandomString = generateRandomString,
  stringify = stringify
}
