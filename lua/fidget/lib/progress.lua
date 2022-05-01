---
--- TODO: keep track of buffer numbers?
local M = {}

local active_clients = {}
M.active_clients = active_clients

local fidgets = require("fidget.core.fidgets")
local err_message = require("fidget.utils.errors").err_message

local options = {
  client = {
    decay = 2000,
  },

  task = {
    begin_message = "Started",
    end_message = "Completed",
    decay = 1000,
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

---@class ClientFidget : Fidget
---@field name string: name of LSP client (required)
---@field complete boolean: whether all tasks of this client are complete
---@field _destroy_timer TimerHandle|nil: timer to self-destruct upon completion
local ClientFidget = fidgets.Fidget:subclass()
M.ClientFidget = ClientFidget

ClientFidget.class = "lsp-progress"

function ClientFidget:render(inputs)
  local output = {}
  output.title = self.name
  output.complete = true

  local messages = {}
  for _, input in pairs(inputs) do
    table.insert(messages, input.message)
    output.complete = output.complete and input.complete
  end
  output.body = vim.fn.join(messages, "\n")

  self.complete = output.complete

  if self._destroy_timer then
    self._destroy_timer:stop()
    self._destroy_timer = nil
  end

  if self.complete then
    self._destroy_timer = vim.defer_fn(function()
      self:schedule_destroy()
    end, options.client.decay)
  end

  return output
end

function ClientFidget:initialize()
  print("hello[]")
end

---@class TaskFidget : Fidget
---@field fmt function|nil: function to format
---@field title string|nil: title of the task
---@field message string|nil: message reported of the task
---@field percentage number|nil: percentage completion of the task
---@field _complete boolean: whether the task is complete
---@field _destroy_timer TimerHandle|nil: handle to self-destruct upon completion
local TaskFidget = fidgets.Fidget:subclass()
M.TaskFidget = TaskFidget

TaskFidget.class = "lsp-progress-task"

function TaskFidget:render()
  local fmt = self.fmt or options.task.fmt
  return {
    complete = self._complete,
    message = fmt(self.title, self.message, self.percentage),
  }
end

--- Update a task with a progress message.
---@param msg LspProgressMessage
function TaskFidget:update_task(msg)
  if self._destroy_timer then
    self._destroy_timer:stop()
  end

  self._complete = false

  if msg.kind == "begin" then
    self.title = msg.title
    self.message = msg.message or options.task.begin_message
  elseif msg.kind == "report" then
    self.percentage = msg.percentage or self.percentage
    self.message = msg.message or self.message
  elseif msg.kind == "end" then
    if self.percentage then
      self.percentage = 100
    end
    self._complete = true
    self.message = msg.message or options.task.end_message
    self._destroy_timer = vim.defer_fn(function()
      self:schedule_destroy()
    end, options.task.decay)
  else
    -- WARN
  end

  self:schedule_render()
end

--- Construct a TaskFidget initialized with an LspProgressMessage
---@param msg LspProgressMessage:
function TaskFidget:new_from_message(msg)
  local obj = self:new()
  obj:update_task(msg)
  return obj
end

---@class LspProgressMessage
---@field kind "begin"|"report"|"end": what kind of report
---@field title string|nil: title of the progress operation
---@field message string|nil: detailed information about progress
---@field percentage number|nil: percentage of progress completed

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
    err_message(
      "LSP[",
      client_name,
      "] client has shut down after sending the message"
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
      client.messages.M[token] = {
        title = val.title,
        message = val.message,
        percentage = val.percentage,
      }
    elseif val.kind == "report" then
      client.messages.M[token].message = val.message
      client.messages.M[token].percentage = val.percentage
    elseif val.kind == "end" then
      if client.messages.M[token] == nil then
        err_message(
          "LSP[",
          client_name,
          "] received `end` message with no corresponding `begin`"
        )
      else
        client.messages.M[token].message = val.message
        client.messages.M[token].done = true
      end
    end
  else
    client.messages.M[token] = val
    client.messages.M[token].done = true
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

--- Read progress messages from LSP clients.
---
--- Adapted from Neovim nightly (2022/04/22): https://github.com/neovim/neovim/pull/18040
---
--- This implementation depends on its contemporary progress handler, i.e., what
--- was Neovim nightly as of 2022/04/22, backported above. It is not compatible
--- with the progress handler that ships with Neovim 0.7.
---
--- It is based on and compatible with vim.lsp.util.get_progress_messages() on nightly,
--- with the following differences:
---
--- -  this implementation may return messages where the title field is nil.
--- -  this implementation returns a per-client table of messages rather than
---    a flat list of progress messages.
--- -  this implementation will not clear the client message tables if a truthy
---    argument is given.
---
---@param readonly boolean: whether to clear messages from client objects.
---@return table[string]LspProgressMessage: messages indexed by client name
function M.digest_progress_messages(readonly)
  local new_messages = {}
  local progress_remove = {}

  for _, client in ipairs(vim.lsp.get_active_clients()) do
    new_messages[client.name] = {}

    for token, ctx in pairs(client.messages.progress) do
      local new_report = {
        name = client.name,
        title = ctx.title,
        message = ctx.message,
        percentage = ctx.percentage,
        done = ctx.done,
        progress = true,
      }

      table.insert(new_messages[client.name], new_report)

      if not readonly and ctx.done then
        table.insert(progress_remove, { client = client, token = token })
      end
    end
  end

  for _, item in ipairs(progress_remove) do
    item.client.messages.progress[item.token] = nil
  end

  return new_messages
end

local function handle_progress_notification()
  local client_messages = M.digest_progress_messages()
  for client, messages in pairs(client_messages) do
    if not active_clients[client] then
      active_clients[client] = ClientFidget:new {name = client}
    end

    local client_fidget = active_clients[client]

    for _, msg in ipairs(messages) do
      client_fidget:insert(TaskFidget:new_from_message(msg))
    end
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

return M
