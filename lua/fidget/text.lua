local M = {}

---@class Text: Node
--- Static textual content.
---
---@field [number] string   each line of text
---@field max_width number  the length of the longest line
local Text = {}
Text.__index = Text
M.Text = Text

function Text:new(o)
  local max_width = 0
  for _, line in ipairs(o) do
    max_width = math.max(max_width, #line)
  end
  o.max_width = max_width
  setmetatable(o, self)
  return o
end

function Text:update(msg)
  local result = {
    width = math.min(msg.max_width, self.max_width),
    height = math.min(msg.max_height, #self),
    lines = {},
    restart = true,
  }

  for i=1, result.height do
    table.insert(result.lines, self[i])
  end

  return result
end

return M
