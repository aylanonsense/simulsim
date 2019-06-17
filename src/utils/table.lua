-- Makes a deep clone of a table
local function cloneTable(obj)
  if obj and type(obj) == 'table' then
    local clonedTable = {}
    for k, v in pairs(obj) do
      clonedTable[k] = cloneTable(v)
    end
    return clonedTable
  else
    return obj
  end
end

-- Clears all the properties off of an object
local function clearProps(obj)
  for k,v in pairs(obj) do
    obj[k] = nil
  end
  return obj
end

-- Copies all properties from the source object to the target object
local function copyProps(sourceObj, targetObj)
  for k, v in pairs(sourceObj) do
    targetObj[k] = cloneTable(v)
  end
  return targetObj
end

-- Returns true if the tables are equivalent, false otherwie
local function isEquivalent(obj1, obj2)
  local type1, type2 = type(obj1), type(obj2)
  if type1 == type2 then
    if type1 == 'table' then
      for k, v in pairs(obj1) do
        if not isEquivalent(v, obj2[k]) then
          return false
        end
      end
      for k, v in pairs(obj2) do
        if obj1[k] == nil then
          return false
        end
      end
      return true
    else
      return obj1 == obj2
    end
  else
    return false
  end
end

return {
  cloneTable = cloneTable,
  clearProps = clearProps,
  copyProps = copyProps,
  isEquivalent = isEquivalent
}
