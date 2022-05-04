local M = {}

local fidgets = require("fidget.core.fidgets")

---@class NotifyFidget : Fidget
local NotifyFidget = fidgets.Fidget:subclass()
fidgets.NotifyFidget = NotifyFidget

NotifyFidget.class = "notify"
NotifyFidget.level = vim.log.levels.INFO

function NotifyFidget:render(inputs)
  vim.notify(inputs.msg, inputs.level or self.level, inputs.opts)
  return inputs
end

return M
