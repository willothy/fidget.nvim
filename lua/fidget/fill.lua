local M = {}

---@class Fill: Node
--- Fill in given space with spaces.
---@field coroutine false
---@field flex number
local Fill = {}
M.Fill = Fill

Fill.coroutine = false

---@param o { flex: number }
---@return Fill
function Fill:new(o)
  setmetatable(o, self)
  assert(o.flex > 0, "Flex factor must be greater than 0")
  return o
end

---@param msg UpdateMessage
---@return UpdateResult
function Fill:update(msg)
  local result = {
    width = msg.max_width,
    height = msg.max_height,
    lines = {},
    restart = true,
  }

  local line = string.rep(" ", result.width)
  for _ = 1, result.height do
    table.insert(result.lines, line)
  end

  return result
end

return M
