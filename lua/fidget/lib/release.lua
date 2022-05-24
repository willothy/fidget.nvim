local M = {}

local fidgets = require("fidget.core.fidgets")

---@class ReleaseFidget : Fidget
--- Fidget that can be instructed to self-destruct after a set timeout.
---
--- Uses default render() method to transparently pass children data to parents.
---
---@field new fun(): ReleaseFidget: inherited constructor
---@field release_time number: time to release (required)
---@field _destroy_timer TimerHandle|nil: handle to self-destruct upon completion
local ReleaseFidget = fidgets.Fidget:subclass("ReleaseFidget")
M.ReleaseFidget = ReleaseFidget

function ReleaseFidget:destroy()
  self:cancel_release()
end

function ReleaseFidget:start_release()
  self:cancel_release()
  self._destroy_timer = vim.defer_fn(function()
    if self._destroy_timer then
      self:schedule_destroy()
    end
  end, self.release_time)
end

function ReleaseFidget:cancel_release()
  if self._destroy_timer then
    self._destroy_timer:stop()
    self._destroy_timer = nil
  end
end

return M
