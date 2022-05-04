--- TODO: add options
local M = {}

local notify = require("nvim-notify")
local fidgets = require("fidget.core.fidgets")

---@class NvimNotifyFidget : Fidget
local NvimNotifyFidget = fidgets.Fidget:subclass()
fidgets.NvimNotifyFidget = NvimNotifyFidget

NvimNotifyFidget.class = "notify"
NvimNotifyFidget.level = vim.log.levels.INFO

function NvimNotifyFidget:render(inputs)
  notify.notify(inputs.msg, inputs.level or self.level, inputs.opts)
  return inputs
end

return M
