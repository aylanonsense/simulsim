-- Makes a deep clone of a table
local function cloneTable(obj)
  local clonedTable = {}
  for k, v in pairs(obj) do
    if type(v) == 'table' then
      clonedTable[k] = cloneTable(v)
    else
      clonedTable[k] = v
    end
  end
  return clonedTable
end

return {
  cloneTable = cloneTable
}
