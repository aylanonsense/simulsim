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

return {
  generateRandomString = generateRandomString
}
