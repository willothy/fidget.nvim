-- TODO: refactor terminology in terms of flow graph
local M = {}

local sched = require("fidget.core.sched")

local do_render
local do_destroy
local schedule_fidget

---@class Fidget
--- A Fidget is a UI model component encapsulating some local state, organized
--- in an acyclic flow network of Fidgets. Fidgets are equipped with a render
--- method used to produce some kind of output data from that state and the
--- rendered output of their inbound.
---
---@field class string: class identifier of Fidget instance
---@field render FidgetRender: method to render output (required)
---@field inbound table[any]FidgetInbound: inbound peers of this Fidget
---@field _outbound table[Fidget]true: outbound peers of this Fidget
---@field _scheduled FidgetSchedState: what this Fidget is scheduled to do
---@field _queued boolean: whether this Fidget is queued for evaluation
---@field _output FidgetOutput: cached result of render
local Fidget = {}
M.Fidget = Fidget
Fidget.__index = Fidget

---@class FidgetOutput
--- The data produced by a Fidget

---@alias FidgetInbound Fidget|function()->FidgetOutput|FidgetOutput
--- A Fidget may have non-Fidget inbound, e.g., functions or unchanging plain data.

---@alias FidgetSchedState "render"|"destroy"|false

---@alias FidgetRender function(Fidget, table[any]FidgetOutput)->FidgetOutput
---@alias FidgetMethod function(Fidget)

--- Create subclass of Fidget.
function Fidget:subclass()
  local o = setmetatable({}, self)
  o.__index = o
  o.__baseclass = Fidget
  return o
end

--- Whether an object is an instance of Fidget.
function M.is_fidget(obj)
  local mt = getmetatable(obj)
  return mt and mt.__baseclass == Fidget
end

Fidget.class = "base"
Fidget.render = nil

--- Construct a Fidget object.
---@param obj table|nil: initial Fidget instance
---@returns Fidget
function Fidget:new(obj)
  obj = obj or {}

  obj = vim.tbl_extend("keep", obj, {
    inbound = {},
  })
  obj = vim.tbl_extend("error", obj, {
    -- Internal fields
    _outbound = {},
    _scheduled = false,
    _queued = false,
    _output = "unrendered data", -- This dummy value will get overwritten.
  })

  setmetatable(obj, self)
  assert(type(obj.render) == "function", "render method is required")

  for _, ib in pairs(obj.inbound) do
    if M.is_fidget(ib) then
      ib:add_outbound(obj)
    end
  end

  obj:initialize()

  -- Initialize this Fidget by rendering it at the next opportunity
  obj:schedule_render()

  return obj
end

--- Overrideable method to initialize a Fidget upon creation.
function Fidget:initialize() end

--- Overrideable method to initialize a Fidget upon creation.
---@param inputs table[any]FidgetOutput: table of inbound outputs
---@return FidgetOutput: flattened inputs
function Fidget:render(inputs)
  return vim.tbl_flatten(inputs)
end

--- Overrideable method to clean up a Fidget before destruction.
function Fidget:destroy() end

--- Construct a new render function by composing a function before it.
function Fidget:before_render(fn)
  return function(actual_self, inputs)
    return self.render(actual_self, fn(actual_self, inputs))
  end
end

--- Construct a new render function by composing a function after it.
function Fidget:after_render(fn)
  return function(actual_self, inputs)
    return fn(actual_self, self.render(actual_self, inputs))
  end
end

--- Schedule a Fidget to be re-rendered soon.
---
--- All its ancestors are also scheduled for re-rendering.
---
--- Scheduling destruction takes priority over scheduling rendering.
function Fidget:schedule_render()
  if self._scheduled then
    -- If _scheduled == "render", then no need to re-schedule self.
    -- If _scheduled == "destroy", then that takes priority.
    return
  end
  self._scheduled = "render"
  schedule_fidget(self)
end

--- Schedule a Fidget to be destroyed soon.
---
--- All its ancestors are scheduled for re-rendering, while all its descendents
--- will be destroyed.
---
--- Scheduling destruction takes priority over scheduling rendering, and is
--- idempotent.
function Fidget:schedule_destroy()
  if self._scheduled == "destroy" then
    return
  end
  -- "destroy" takes precedence over "render"
  self._scheduled = "destroy"
  schedule_fidget(self)
end

--- Whether a Fidget has no outbound nodes.
---@return boolean
function Fidget:is_sink()
  return next(self._outbound) == nil
end

--- Whether a Fidget has no inbound nodes.
---@return boolean
function Fidget:is_tap()
  return next(self.inbound) == nil
end

function Fidget:add_outbound(ob, key)
  self._outbound[ob] = key
end

function Fidget:remove_outbound(ob)
  local key = self._outbound[ob]
  if key == nil then
    return
  end

  self._outbound[ob] = nil
  return key
end

--- Retrieve inbound node at given index.
---
---@param k any: given index
---@return FidgetInbound
function Fidget:get(k)
  return self.inbound[k]
end

--- Set inbound node at given index.
---
--- If a node previously existed at that key, it is destroyed.
---
--- The ob is scheduled for rendering.
---
---@param k any: given index
---@param ib FidgetInbound|nil: optional ib node
function Fidget:set(k, ib)
  local old = self.inbound[k]

  self.inbound[k] = ib
  if M.is_fidget(ib) then
    ib:add_outbound(self)
  end

  if M.is_fidget(old) then
    old:schedule_destroy()
  end

  self:schedule_render()
end

--- Add a child node, like table.insert().
---
--- Sets self as ob of inserted child if child is a Fidget.
---
--- The ob is scheduled for rendering.
---
---@param idx number: where child should be inserted
---@param child FidgetInbound: the child to be inserted
---@overload fun(self, child: FidgetInbound)
function Fidget:insert(idx, child)
  if child then
    table.insert(self.inbound, idx, child)
  else
    table.insert(self.inbound, idx)
  end
  if type(child) == "table" then
    child:add_outbound(self)
  end

  self:schedule_render()
end

--- Remove an inbound node, like table.remove().
---
--- Destroys the removed node, if any.
---
--- The ob is scheduled for rendering.
---
---@param idx number: index of node to remove from Fidget
---@overload fun()
function Fidget:remove(idx)
  local old
  if idx then
    old = table.remove(self.inbound, idx)
  else
    old = table.remove(self.inbound)
  end
  if type(old) == "table" then
    do_destroy(old)
  end

  self:schedule_render()
end

---@private
--- Render a Fidget, and render or destroy its descendents as necessary.
function do_render(self)
  ---@private
  --- What to do with each inbound node.
  local function eval_inbound(ib)
    if type(ib) == "table" then
      -- Node is fidget object that may produce data
      if ib._scheduled == "render" then
        ib._scheduled = nil

        -- Re-render Fidget
        return do_render(ib)
      elseif ib._scheduled == "destroy" then
        -- Destroy node and all of its upstream peers
        do_destroy(ib)

        return nil
      else
        -- Nothing needs to be done, use cached output
        return ib._output
      end
    elseif type(ib) == "function" then
      -- Node is function that returns output data
      return ib()
    else
      -- Node is plain-old data, output it directly
      return ib
    end
  end

  local inbound_output = {}
  for k, ib in pairs(self.inbound) do
    inbound_output[k] = eval_inbound(ib)
  end
  self._output = self:render(inbound_output)
  self._scheduled = nil

  return self._output
end

---@private
--- Destroy a Fidget and all its descendents.
function do_destroy(self)
  if not self.inbound then
    vim.pretty_print("RUH ROH", self.class)
  end
  for _, ib in pairs(self.inbound) do
    if type(ib) == "table" then
      do_destroy(ib)
    end
  end
  self:destroy()
  self.inbound = nil
  self._outbound = nil
  self._output = nil
end

---@private
--- Handle to manage deferred work.
local work_handle = vim.loop.new_idle()

local work_set = {}

function schedule_fidget(fidget)
  work_set[fidget] = true
  work_handle:start(function()
    work_handle:stop()
    local work_queue = {}

    local function queue_fidget(f)
      -- TODO: check for _scheduled
      for ob, _ in pairs(f._outbound) do
        queue_fidget(ob)
      end
      table.insert(work_queue, f)
    end

    for f, _ in pairs(work_set) do
      queue_fidget(f)
    end

    work_set = {}

    for i = #work_queue, 1, -1 do
      eval_fidget(work_queue[i])
    end
  end)
end

return M
