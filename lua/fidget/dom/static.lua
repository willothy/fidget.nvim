local M = {}

---@class Static: DOMNode
--- Static textual content.
---
--- Optimized to minimize allocations; also used to implement Expanders.
---
---@field lines     string[]  lines of pre-computed content
---@field max_width number    the length of the longest line
local Static = {}
Static.__index = Static
M.Static = Static

--- Construct a Static DOM node.
---
---@param lines string[]  lines of pre-computed content
---@param flex  number?   optional flex factor
---@return      Static    constructed Static node
function Static:new(lines, flex)
  local max_width = 0
  for _, line in ipairs(lines) do
    max_width = math.max(max_width, #line)
  end
  return setmetatable({ lines = lines, max_width = max_width, flex = flex }, self)
end

--- Construct SubBuffer given constraints.
---
--- This implementation directly point the lines of the constructed SubBuffer at
--- self.lines, to avoid constructing new objects or copying things around.
--- Doing so is ok because a Static node outputs the same lines every time, and
--- the backend shouldn't modify sub.lines while rendering, only read from it.
---
--- Also note that it's ok if the width of the constructed SubBuffer is smaller
--- than self.max_width, because it's the job of the backend to only take as
--- many as sub.width characters from each line.
---
---@param cons  Constraint
---@return      SubBuffer
function Static:update(cons)
  return {
    width = math.min(cons.max_width, self.max_width),
    height = math.min(cons.max_height, #self.lines),
    lines = self.lines,
    restart = true,
  }
end

return M
