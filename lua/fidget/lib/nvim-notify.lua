local M = {}

local fidgets = require("fidget.core.fidgets")
local notify = require("notify")

local options = {
  default_level = vim.log.levels.INFO,
  default_opts = {},
}

local stages_util = require("notify.stages.util")
local stages = {
  function(state)
    local next_height = state.message.height + 2
    local next_row = stages_util.available_slot(
      state.open_windows,
      next_height,
      stages_util.DIRECTION.TOP_DOWN
    )
    if not next_row then
      return nil
    end
    return {
      relative = "editor",
      anchor = "NE",
      width = state.message.width,
      height = state.message.height,
      col = vim.opt.columns:get(),
      row = next_row,
      border = "rounded",
      style = "minimal",
      opacity = 0,
    }
  end,
  function(_)
    -- vim.pretty_print("stage 2", state)
    return {
      opacity = { 100 },
      -- height = { state.message.height },
      col = { vim.opt.columns:get() },
    }
  end,
  function(_)
    -- vim.pretty_print("stage 3", state)
    return {
      col = { vim.opt.columns:get() },
      -- height = { state.message.height },
      time = true,
    }
  end,
  function()
    return {
      width = {
        1,
        frequency = 2.5,
        damping = 0.9,
        complete = function(cur_width)
          return cur_width < 3
        end,
      },
      opacity = {
        0,
        frequency = 2,
        complete = function(cur_opacity)
          return cur_opacity <= 4
        end,
      },
      col = { vim.opt.columns:get() },
    }
  end,
}
notify.setup({ stages = stages })

---@class NvimNotifyFidget : Fidget
---
---@field level number:
---@field opts table:
---@return nil
local NvimNotifyFidget = fidgets.Fidget:subclass()
M.NvimNotifyFidget = NvimNotifyFidget

NvimNotifyFidget.class = "nvim-notify"

function NvimNotifyFidget:render(inputs)
  local level = self.level or options.default_level

  local opts = vim.tbl_deep_extend(
    "force",
    options.default_opts,
    self.opts or {},
    {
      title = inputs.title,
      icon = inputs.icon,
    },
    {
      replace = self._record,
      timeout = false,
      hide_from_history = true,
      on_close = function()
        self:schedule_destroy()
      end,
    }
  )
  self:log("notifying: ", vim.inspect(inputs))

  self._record = notify.notify(inputs.message or "", level, opts)

  return nil
end

function NvimNotifyFidget:destroy()
  self:close_notification()
end

function NvimNotifyFidget:close_notification()
  if self._record then
    notify.notify("", nil, { timeout = 0, replace = self._record })
    self._record = nil
  end
end

return M
