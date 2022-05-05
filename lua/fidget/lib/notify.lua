local M = {}

local fidgets = require("fidget.core.fidgets")

local options = {
  default_level = vim.log.levels.INFO,
  default_opts = {},
}

---@class NotifyFidget : Fidget
local NotifyFidget = fidgets.Fidget:subclass()
M.NotifyFidget = NotifyFidget

NotifyFidget.class = "notify"
NotifyFidget.level = nil
NotifyFidget.opts = nil

function NotifyFidget:render(inputs)
  local level = inputs.level or self.level or options.default_level

  local opts = options.default_opts
  if self.opts then
    opts = vim.tbl_deep_extend("force", opts, self.opts)
  end
  if inputs.opts then
    opts = vim.tbl_deep_extend("force", opts, inputs.opts)
  end

  vim.notify(inputs.msg, level, opts)
  return inputs
end

return M
