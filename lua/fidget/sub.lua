local M = {}

local strings = require("fidget.sub.strings")

--- Render a SubBuffer into a text canvas, i.e., an array of strings.
---
---@param sub     SubBuffer   what to render
---@param padding string?     character to pad empty space with (default = " ")
---@return        string[]    what is rendered
function M.render_to_strings(sub, padding)
  padding = padding or " "
  assert(type(padding) == "string" and #padding == 1, "padding must be a single character")
  return strings.render(sub, padding)
end

return M
