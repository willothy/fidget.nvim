local M = {}

local fidgets = require("fidget.core.fidgets")
local notify = require("notify")

local options = {
  default_level = vim.log.levels.INFO,
  default_opts = {},
}

---@class NvimNotifyFidget : Fidget
local NvimNotifyFidget = fidgets.Fidget:subclass()
M.NvimNotifyFidget = NvimNotifyFidget

NvimNotifyFidget.class = "nvim-notify"
NvimNotifyFidget.level = nil
NvimNotifyFidget.opts = nil
NvimNotifyFidget.handle = nil

function NvimNotifyFidget:render(input)
  if next(self.inbound) == nil then
    self:schedule_destroy()
  end

  local level = input.level or self.level or options.default_level

  local opts = options.default_opts
  if self.opts then
    opts = vim.tbl_deep_extend("force", opts, self.opts)
  end
  if input.opts then
    opts = vim.tbl_deep_extend("force", opts, input.opts)
  end

  opts.replace = self.record
  opts.timeout = false
  opts.hide_from_history = true

  self.record = notify.notify(input.msg, level, opts)

  return input
end

function NvimNotifyFidget:destroy()
  if self.record then
    notify.notify("", nil, { timeout = 0, replace = self.record })
  end
end

return M
