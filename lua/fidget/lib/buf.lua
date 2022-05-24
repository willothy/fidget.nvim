local M = {}

local fidgets = require("fidget.core.fidgets")

---@class BufFidget : Fidget
---
---@field _bufnr number: number of the buffer that this Fidget forwards data to
---@field _winnr number: number of the window where the buffer is displayed
local BufFidget = fidgets.Fidget:subclass("BufFidget")
fidgets.BufFidget = BufFidget

---@diagnostic disable-next-line: unused-local
function BufFidget:render(inputs)

end

function BufFidget:on_render()
end

function BufFidget:initialize()
end

function BufFidget:destroy()
end

return M
