local M = {}

local fidgets = require("fidget.core.fidgets")
local log = require("fidget.utils.log")

local options = {
  spinner_frames = "pipe",
  complete_text = "✔",
  frame_rate = 125,
}

local function get_spinner(spinner)
  if type(spinner) == "string" then
    spinner = require("fidget.utils.spinners")[spinner]
    if spinner == nil then
      log.error("Unknown spinner name: " .. spinner)
    end
  end
  return spinner
end

---@alias SpinnerOutput string

---@class SpinnerFidget : Fidget
---@field spinner_frames string[]|nil: frames of text to output when incomplete
---@field complete_text string|nil: text to output when complete
---@field frame_rate number|nil: rate at which spinner frames are animated
---@field _spinner_index number: frame number in spinner_frames to output
---@field _spinner_timer TimerHandle|nil: handle to animate spinner
local SpinnerFidget = fidgets.Fidget:subclass()
M.SpinnerFidget = SpinnerFidget

SpinnerFidget.class = "spinner"

function SpinnerFidget:render(complete)
  if next(self.inbound) == nil then
    vim.pretty_print("destroying spinner")
    self:schedule_destroy()
  end

  if complete == nil then
    return nil
  end

  assert(type(complete) == "boolean", "spinner input type must be boolean")

  if complete then
    self:stop_animation()
    return self.complete_text or options.complete_text
  else
    self:start_animation()
    local frames = self.spinner_frames or options.spinner_frames

    -- Wrap _spinner_index if necessary
    if self._spinner_index >= #frames then
      self._spinner_index = self._spinner_index % #frames
    end
    return frames[self._spinner_index + 1]
  end
end

function SpinnerFidget:initialize()
  self._spinner_index = 0
  self.spinner_frames = get_spinner(
    self.spinner_frames or options.spinner_frames
  )
  self:start_animation()
end

function SpinnerFidget:destroy()
  self:stop_animation()
end

function SpinnerFidget:start_animation()
  if not self._spinner_timer then
    self._spinner_timer = vim.defer_fn(function()
      self:_step_animation()
    end, self.frame_rate or options.frame_rate)
  end
end

function SpinnerFidget:stop_animation()
  if self._spinner_timer then
    self._spinner_timer:stop()
    self._spinner_timer = nil
  end
end

function SpinnerFidget:_step_animation()
  self._spinner_index = self._spinner_index + 1
  self._spinner_timer = vim.defer_fn(function()
    self:_step_animation()
  end, self.frame_rate or options.frame_rate)
  self:schedule_render()
end

function M.setup(opts)
  options = vim.tbl_deep_extend("force", options, opts or {})
end

return M
