-- TODO: refactor terminology in terms of flow graph
local M = {}

local sched = require("fidget.core.sched")

local do_render
local do_destroy

---@class FidgetOutput
--- The data produced by a Fidget

---@alias FidgetInbound Fidget|function()->FidgetOutput|FidgetOutput
--- A Fidget may have non-Fidget inbound, e.g., functions or unchanging plain data.

---@alias FidgetSchedState "render"|"destroy"|false

---@alias FidgetRender function(Fidget, table[any]FidgetOutput)->FidgetOutput
---@alias FidgetMethod function(Fidget)

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
---@field _output FidgetOutput: cached result of render
local Fidget = {}
M.Fidget = Fidget
Fidget.__index = Fidget

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
    _output = "unrendered data", -- This dummy value will get overwritten.
  })

  setmetatable(obj, self)
  assert(type(obj.render) == "function", "render method is required")

  for _, ib in pairs(obj.inbound) do
    if type(ib) == "table" then
      ib:add_outbound(obj)
    end
  end

  obj:initialize()

  -- Initialize this Fidget by rendering it at the next opportunity
  obj:schedule_render()

  return obj
end

--- Overrideable method to initialize a Fidget upon creation.
function Fidget:initialize()
end

--- Overrideable method to clean up a Fidget before destruction.
function Fidget:destroy()
end

--- Construct a new render function by composing a function before it.
function Fidget:before_render(fn)
  return function(actual_self, inputs)
    self.render(actual_self, fn(actual_self, inputs))
  end
end

--- Construct a new render function by composing a function after it.
function Fidget:after_render(fn)
  return function(actual_self, inputs)
    fn(actual_self, self.render(actual_self, inputs))
  end
end

--- Schedule a Fidget to be re-rendered soon.
---
--- All its ancestors are also scheduled for re-rendering.
---
--- Scheduling destruction takes priority over scheduling rendering.
function Fidget:schedule_render()
  -- Optimization: if already scheduled, no need to reschedule.
  if self._scheduled == "render" then
    return
  end

  if self._scheduled == "destroy" then
    -- Already scheduled for destruction, should not also render.
    return
  end

  self._scheduled = "render"

  if not self:is_sink() then
    self:schedule_outbound()
  else
    sched.method(self, do_render)
  end
end

function Fidget:schedule_outbound()
  for ob, _ in pairs(self._outbound) do
    ob:schedule_render()
  end
end

--- Schedule a Fidget to be destroyed soon.
---
--- All its ancestors are scheduled for re-rendering, while all its descendents
--- will be destroyed.
---
--- Scheduling destruction takes priority over scheduling rendering, and is
--- idempotent.
function Fidget:schedule_destroy()
  self._scheduled = "destroy"

  if not self:is_sink() then
    self:schedule_outbound()
  else
    sched.method(self, do_destroy)
  end
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

function Fidget:add_outbound(ob)
  self._outbound[ob] = true
end

function Fidget:remove_outbound(ob)
  self._outbound[ob] = false
end

function Fidget:outbounds(_v)
  return next(self._outbound, _v)
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
  if type(ib) == "table" then
    ib:add_outbound(self)
  end

  if type(old) == "table" then
    do_destroy(old)
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
  table.insert(self.inbound, idx, child)
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
  local old = table.remove(self.inbound, idx)
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

return M
