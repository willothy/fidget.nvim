---
--- TODO: keep track of buffer numbers?
local M = {}

local active_clients = {}
M.active_clients = active_clients

local fidgets = require("fidget.core.fidgets")
local log = require("fidget.utils.log")

local ReleaseFidget = require("fidget.lib.release").ReleaseFidget
local SpinnerFidget = require("fidget.lib.spinner").SpinnerFidget

local options = {
  enable = true,
  backend = "nvim-notify",
  client = {
    release = 2000,
  },
  task = {
    begin_message = "Started",
    end_message = "Completed",
    release = 1000,
    fmt = function(title, message, percentage)
      return string.format(
        "%s%s [%s]",
        message,
        percentage and string.format(" (%.0f%%)", percentage) or "",
        title
      )
    end,
  },
}

---@class TasksFidget : Fidget
--- Aggregates progress reports from TaskFidgets
---
---@field complete boolean: whether all tasks of this client are complete
local TasksFidget = fidgets.Fidget:subclass("TasksFidget")
M.TasksFidget = TasksFidget

TasksFidget.complete = false

--- Overrideable method that is invoked when tasks are updated but not completed.
function TasksFidget:on_update() end

--- Overrideable method that is invoked when all the tasks are complete
function TasksFidget:on_complete() end

---@param inputs table<any, TaskOutput>
---@return string
function TasksFidget:render(inputs)
  local output = {}
  self.complete = true

  local messages = {}
  for _, input in pairs(inputs) do
    table.insert(messages, input.message)
    self.complete = self.complete and input.complete
  end
  output = vim.fn.join(messages, "\n")

  if self.complete then
    self:on_complete()
  else
    self:on_update()
  end
  return output
end

---@class TaskFidget : Fidget
---@field new fun() TaskFidget: inherited constructor
---@field fmt function|nil: function to format
---@field title string|nil: title of the task
---@field message string|nil: message reported of the task
---@field percentage number|nil: percentage completion of the task
---@field complete boolean: whether the task is complete
local TaskFidget = fidgets.Fidget:subclass("TaskFidget")
M.TaskFidget = TaskFidget

---@class TaskOutput : FidgetOutput
---@field complete boolean: whether the task is complete
---@field message string: current message of task

--- Overrideable method that is invoked when task is updated (but not completed).
function TaskFidget:on_update() end

--- Overrideable method that is invoked when task is complete.
function TaskFidget:on_complete() end

---@return TaskOutput
function TaskFidget:render()
  local fmt = self.fmt or options.task.fmt
  return {
    complete = self.complete,
    message = fmt(self.title, self.message, self.percentage),
  }
end

--- Update a task with a progress message.
---@param msg LspProgressMessage
function TaskFidget:update_with_message(msg)
  if not msg.done then
    self.title = msg.title or self.title
    self.complete = false
    self.percentage = msg.percentage or self.percentage
    self.message = msg.message or self.message or options.task.begin_message
  else
    self.title = msg.title or self.title
    if self.percentage then
      self.percentage = 100
    end
    self.message = msg.message or options.task.end_message
    self.complete = true
  end

  if self.complete then
    self:on_complete()
  else
    self:on_update()
  end

  self:schedule_render()
end

local function get_active_client_root(client_id)
  if active_clients[client_id] then
    return active_clients[client_id]
  end

  -- TODO: check for option
  local NvimNotifyFidget = require("fidget.lib.nvim-notify").NvimNotifyFidget

  active_clients[client_id] = ReleaseFidget:new({
    release_time = options.client.release,
    destroy = function(self)
      active_clients[client_id] = nil
      ReleaseFidget.destroy(self)
    end,
  }, {
    NvimNotifyFidget:new({}, {
      title = vim.lsp.get_client_by_id(client_id).name,
      icon = SpinnerFidget:new(),
      message = TasksFidget:new({
        on_complete = function(self)
          self:parent():get("icon"):set_complete()
          self:parent():parent():start_release()
        end,
        on_update = function(self)
          self:parent():get("icon"):set_incomplete()
          self:parent():parent():cancel_release()
        end,
      }),
    }),
  })

  return active_clients[client_id]
end

local function get_active_client_tasks(client_id)
  return get_active_client_root(client_id):get():get("message")
end

---@return TaskFidget
local function get_task_by_token(tasks, token)
  if tasks:get(token) then
    return tasks:get(token):get()
  end

  tasks:set(
    token,
    ReleaseFidget:new({ release_time = options.task.release }, {
      TaskFidget:new({
        on_complete = function(self)
          self:parent():start_release()
        end,
        on_update = function(self)
          self:parent():cancel_release()
        end,
      }),
    })
  )

  return tasks:get(token):get()
end

---@class LspProgressMessage
---@field name string|nil: name of the client
---@field title string|nil: title of the progress operation
---@field message string|nil: detailed information about progress
---@field percentage number|nil: percentage of progress completed
---@field done boolean: whether the progress reported is complete

---@private
--- LSP progress handler for vim.lsp.handlers["$/progress"]
---
--- Backported from Neovim nightly (2022/04/22): https://github.com/neovim/neovim/pull/18040
local function progress_handler(_, result, ctx, _)
  local client_id = ctx.client_id
  local client = vim.lsp.get_client_by_id(client_id)
  local client_name = client and client.name
    or string.format("id=%d", client_id)
  if not client then
    log.error(
      "LSP["
        .. client_name
        .. "] client has shut down after sending the message"
    )
    return vim.NIL
  end
  local val = result.value -- unspecified yet
  local token = result.token -- string or number

  if type(val) ~= "table" then
    val = { content = val }
  end
  if val.kind then
    if val.kind == "begin" then
      client.messages.progress[token] = {
        title = val.title,
        message = val.message,
        percentage = val.percentage,
      }
    elseif val.kind == "report" then
      client.messages.progress[token].message = val.message
      client.messages.progress[token].percentage = val.percentage
    elseif val.kind == "end" then
      if client.messages.progress[token] == nil then
        log.error(
          "LSP["
            .. client_name
            .. "] received `end` message with no corresponding `begin`"
        )
      else
        client.messages.progress[token].message = val.message
        client.messages.progress[token].done = true
      end
    end
    client.messages.progress[token].kind = val.kind
  else
    client.messages.progress[token] = val
    client.messages.progress[token].done = true
  end

  vim.api.nvim_command("doautocmd <nomodeline> User LspProgressUpdate")
end

---@private
--- Replace LSP progress handler with what was backported above.
local function backport_progress_handler()
  local version = vim.version()
  if version.major <= 0 and version.minor <= 7 then
    require("vim.lsp.handlers")["$/progress"] = progress_handler
  end
end

--- Based on get_progress_messages from Neovim nightly (2022/04/22): https://github.com/neovim/neovim/pull/18040
---
local function handle_progress_notification()
  local to_remove = {}

  for _, client in ipairs(vim.lsp.get_active_clients()) do
    local tasks = get_active_client_tasks(client.id)

    for token, ctx in pairs(client.messages.progress) do
      get_task_by_token(tasks, token):update_with_message({
        title = ctx.title,
        message = ctx.message,
        percentage = ctx.percentage,
        done = ctx.done,
        progress = true,
      })

      if ctx.done then
        table.insert(to_remove, { client = client, token = token })
      end
    end
  end

  for _, item in ipairs(to_remove) do
    item.client.messages.progress[item.token] = nil
  end
end

local function subscribe_to_progress_messages()
  vim.api.nvim_create_autocmd("User", {
    pattern = "LspProgressUpdate",
    callback = handle_progress_notification,
    desc = "Fidget handler for progress notifications",
  })
end

function M.setup(opts)
  options = vim.tbl_deep_extend("force", options, opts or {})
  if options.enable then
    backport_progress_handler()
    subscribe_to_progress_messages()
  end
end

M.setup()

return M
