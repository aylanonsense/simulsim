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

return {
  cloneTable = cloneTable,
  clearProps = clearProps,
  copyProps = copyProps
}
