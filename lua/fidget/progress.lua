--- Fidget's LSP progress subsystem.
local M            = {}
M.display          = require("fidget.progress.display")
M.lsp              = require("fidget.progress.lsp")
local poll         = require("fidget.poll")
local notification = require("fidget.notification")
local logger       = require("fidget.logger")

--- Used to ensure only a single autocmd callback exists.
---@type number?
local autocmd_id   = nil

--- Options related to LSP progress notification subsystem
require("fidget.options").declare(M, "progress", {
  --- How and when to poll for progress messages
  ---
  --- Set to `0` to immediately poll on each `LspProgress` event.
  ---
  --- Set to a positive number to poll for progress messages at the specified
  --- frequency (Hz, i.e., polls per second). Combining a slow `poll_rate`
  --- (e.g., `0.5`) with the `ignore_done_already` setting can be used to filter
  --- out short-lived progress tasks, de-cluttering notifications.
  ---
  --- Note that if too many LSP progress messages are sent between polls,
  --- Neovim's progress ring buffer will overflow and messages will be
  --- overwritten (dropped), possibly causing stale progress notifications.
  --- Workarounds include using the `progress.lsp.progress_ringbuf_size` option,
  --- or manually calling `fidget.notification.reset()` (see #167).
  ---
  --- Set to `false` to disable polling altogether; you can still manually poll
  --- progress messages by calling `fidget.progress.poll()`.
  ---
  ---@type number|false
  poll_rate = 0,

  --- Suppress new messages while in insert mode
  ---
  --- Note that progress messages for new tasks will be dropped, but existing
  --- tasks will be processed to completion.
  ---
  ---@type boolean
  suppress_on_insert = false,

  --- Ignore new tasks that are already complete
  ---
  --- This is useful if you want to avoid excessively bouncy behavior, and only
  --- seeing notifications for long-running tasks. Works best when combined with
  --- a low `poll_rate`.
  ---
  ---@type boolean
  ignore_done_already = false,

  --- Ignore new tasks that don't contain a message
  ---
  --- Some servers may send empty messages for tasks that don't actually exist.
  --- And if those tasks are never completed, they will become stale in Fidget.
  --- This option tells Fidget to ignore such messages unless the LSP server has
  --- anything meaningful to say. (See #171)
  ---
  --- Note that progress messages for new empty tasks will be dropped, but
  --- existing tasks will be processed to completion.
  ---
  ---@type boolean
  ignore_empty_message = true,

  --- How to get a progress message's notification group key
  ---
  --- Set this to return a constant to group all LSP progress messages together,
  --- e.g.,
  ---
  --- ```lua
  --- notification_group = function(msg)
  ---   -- N.B. you may also want to configure this group key ("lsp_progress")
  ---   -- using progress.display.overrides or notification.configs
  ---   return "lsp_progress"
  --- end
  --- ```
  ---
  ---@type fun(msg: ProgressMessage): NotificationKey
  notification_group = function(msg)
    return msg.lsp_name
  end,

  --- List of LSP servers to ignore
  ---
  --- Example:
  ---
  --- ```lua
  --- ignore = { "rust_analyzer" }
  --- ```
  ---
  ---@type NotificationKey[]
  ignore = {},

  display = M.display,
  lsp = M.lsp,
}, function()
  if autocmd_id ~= nil then
    vim.api.nvim_del_autocmd(autocmd_id)
    autocmd_id = nil
  end
  if M.options.poll_rate ~= false then
    autocmd_id = M.lsp.on_progress_message(function()
      if M.options.poll_rate > 0 then
        M.poller:start_polling(M.options.poll_rate)
      else
        M.poller:poll_once()
      end
    end)
  end
end)

--- Whether progress message updates are suppressed.
local progress_suppressed = false

--- Cache of generated LSP notification group configs.
---
---@type { [NotificationKey]: NotificationConfig }
local loaded_configs = {}

--- Lazily load the notification configuration for some progress message.
---
---@param msg ProgressMessage
function M.load_config(msg)
  local group = M.options.notification_group(msg)
  if loaded_configs[group] then
    return
  end

  local config = M.display.make_config(group)

  notification.set_config(group, config, false)
end

---@param msg ProgressMessage
---@return string?
---@return number
---@return NotificationOptions
function M.format_progress(msg)
  local group = M.options.notification_group(msg)
  local message = M.options.display.format_message(msg)
  local annote = M.options.display.format_annote(msg)

  local update_only = false
  if M.options.ignore_done_already and msg.done then
    update_only = true
  elseif M.options.ignore_empty_message and msg.message == nil then
    update_only = true
  elseif M.options.suppress_on_insert and string.find(vim.fn.mode(), "i") then
    update_only = true
  end

  return message, msg.done and vim.log.levels.INFO or vim.log.levels.WARN, {
    key = msg.token,
    group = group,
    annote = annote,
    update_only = update_only,
    ttl = msg.done and 0 or M.display.options.progress_ttl, -- Use config default when done
    data = msg.done,                                        -- use data to convey whether this task is done
  }
end

local NEXT_ID = 0
local PREFIX = "fidget-user-"

local function next_token()
  NEXT_ID = NEXT_ID + 1
  return PREFIX .. NEXT_ID
end

---@class ProgressHandle: ProgressMessage  A handle for a progress message, reactive to changes
---@field cancel fun(self: ProgressHandle) Cancel the task
---@field finish fun(self: ProgressHandle) Mark the task as complete
---@field report fun(self: ProgressHandle, props: table) Update one or more properties of the progress message

---Create a new progress message, and return a handle to it for updating.
---The handle is a reactive object, so you can update its properties and the
---message will be updated accordingly. You can also use the `report` method to
---update multiple properties at once.
---
---Example:
---
---```lua
---local progress = require("fidget.progress")
---
---local handle = progress.create({
---  title = "My Task",
---  message = "Doing something...",
---  lsp_name = "my_fake_lsp",
---  percentage = 0,
---})
---
----- You can update properties directly and the
----- progress message will be updated accordingly
---handle.message = "Doing something else..."
---
----- Or you can use the `report` method to bulk-update
----- properties.
---handle:report({
---  title = "The task status changed"
---  message = "Doing another thing...",
---  percentage = 50,
---})
---
----- You can also cancel the task (errors if not cancellable)
---handle:cancel()
---
----- Or mark it as complete (updates percentage to 100 automatically)
---handle:finish()
---````
---
---@param message ProgressMessage
---@return ProgressHandle
function M.create(message)
  message = message or {}

  local data = vim.deepcopy(message)
  data.token = data.token or next_token()
  data.message = data.message or ""
  data.title = data.title or ""
  data.lsp_name = data.lsp_name or "progress"
  data.lsp_id = data.lsp_id or -1

  -- Ensure that the task isn't updated after it's finished
  local done = false

  -- Load the notification config
  M.load_config(data)

  -- Initial update (for begin)
  notification.notify(M.format_progress(data))

  local handle = setmetatable({}, {
    __newindex = function(_, k, v)
      if k == "token" then
        error(string.format("attempted to modify read-only field '%s'", k))
      end
      data[k] = v
      if not done then
        notification.notify(M.format_progress(data))
      end
    end,
    __index = function(_, k)
      return data[k]
    end,
  })

  function handle:cancel()
    if done then
      return
    end
    if data.cancellable then
      data.done = true
      notification.notify(M.format_progress(data))
      done = true
    else
      error("attempted to cancel non-cancellable progress")
    end
  end

  function handle:finish()
    if done then
      return
    end
    data.done = true
    if data.percentage ~= nil then
      data.percentage = 100
    end
    notification.notify(M.format_progress(data))
    done = true
  end

  function handle:report(props)
    if done then
      return
    end
    for k, v in pairs(props) do
      if k ~= "token" and k ~= "kind" then
        data[k] = v
      end
    end
    notification.notify(M.format_progress(data))
  end

  return handle
end

--- Poll for progress messages to feed to the fidget notifications subsystem.
M.poller = poll.Poller {
  name = "progress",
  poll = function()
    if progress_suppressed then
      return false
    end

    local messages = M.lsp.poll_for_messages()
    if #messages == 0 then
      logger.info("No LSP messages (that can be displayed)")
      return false
    end

    for _, msg in ipairs(messages) do
      -- Determine if we should ignore this message
      local ignore = false
      for _, lsp_name in ipairs(M.options.ignore) do
        -- NOTE: hopefully this loop isn't too expensive.
        -- But if it is, consider indexing by hash.
        if msg.lsp_name == lsp_name then
          ignore = true
          logger.info("Ignoring LSP progress message:", msg)
          break
        end
      end
      if not ignore then
        logger.info("Notifying LSP progress message:", msg)
        M.load_config(msg)
        notification.notify(M.format_progress(msg))
      end
    end
    return true
  end
}

--- Suppress consumption of progress messages.
---
--- Pass `false` as argument to turn off suppression.
---
--- If no argument is given, suppression state is toggled.
---@param suppress boolean? Whether to suppress or toggle suppression
function M.suppress(suppress)
  if suppress == nil then
    progress_suppressed = not progress_suppressed
  else
    progress_suppressed = suppress
  end
end

return M
