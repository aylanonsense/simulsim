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

return {
  cloneTable = cloneTable
}
