local M = {}

local log = require("fidget.utils.log")

local schedule_fidget

---@class Fidget
--- A Fidget is a UI model component encapsulating some local state, organized
--- in an acyclic flow network of Fidgets. Fidgets are equipped with a render
--- method used to produce some kind of output data from that state and the
--- rendered output of their children.
---
---@field class string: class identifier of Fidget instance
---@field children table<FidgetKey, FidgetSource>: data sources
---@field _parent Fidget|nil: where to propragate output to
---@field _parent_key FidgetKey|nil: parent's index to this Fidget
---@field _scheduled FidgetSchedState: what this Fidget is scheduled to do
---@field _queued boolean|nil: whether this Fidget is queued for evaluation
---@field _output FidgetOutput: cached result of render
local Fidget = {}
M.Fidget = Fidget
Fidget.__index = Fidget

---@class FidgetOutput
--- The data produced by a Fidget.

---@alias FidgetKey any
--- The key a parent uses to index its children.

---@alias FidgetSource Fidget | fun(): FidgetOutput | FidgetOutput
--- A Fidget may have non-Fidget sources, e.g., functions or unchanging plain data.

---@alias FidgetSchedState "render" | "destroy" | false
--- A Fidget may be scheduled for re-rendering or destruction, if at all.

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

--- Construct a Fidget object.
---@param obj Fidget|nil: initial Fidget instance
---@returns Fidget: the newly construct Fidget
function Fidget:new(obj)
  obj = obj or {}

  obj = vim.tbl_extend("keep", obj, {
    children = {},
  })
  obj = vim.tbl_extend("error", obj, {
    -- Internal fields
    _parent = {},
    _scheduled = false,
    _queued = nil,  -- Only used during top sort
    _output = nil,  -- Initialized during impending render phase
  })

  setmetatable(obj, self)

  for k, child in pairs(obj.children) do
    if M.is_fidget(child) then
      child:_set_parent(k, obj)
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
---@param inputs table<any, FidgetOutput>: table of child outputs
---@return FidgetOutput: flattened inputs
function Fidget:render(inputs)
  return vim.tbl_flatten(inputs)
end

--- Overrideable method to clean up a Fidget before destruction.
function Fidget:destroy() end

-- --- Construct a new render function by composing a function before it.
-- function Fidget:before_render(fn)
--   return function(actual_self, inputs)
--     return self.render(actual_self, fn(actual_self, inputs))
--   end
-- end
--
-- --- Construct a new render function by composing a function after it.
-- function Fidget:after_render(fn)
--   return function(actual_self, inputs)
--     return fn(actual_self, self.render(actual_self, inputs))
--   end
-- end

--- Whether a Fidget has no outbound nodes.
---@return boolean
function Fidget:is_sink()
  return self._parent == nil
end

--- Whether a Fidget has no children.
---@return boolean
function Fidget:is_leaf()
  return next(self.children) == nil
end

---@private
--- Set the parent of this Fidget.
--
--- If this Fidget already has a parent, it is removed and scheduled for
--- re-rendering.
---
--- Note that this method does not schedule self for re-rendering.
---
---@param k FidgetKey: key that the parent uses to references this Fidget
---@param parent Fidget: the parent
function Fidget:_set_parent(k, parent)
  self:_remove_parent()
  self._parent_key = k
  self._parent = parent
end

---@private
--- Remove the parent of this Fidget, if any.
---
--- That parent is scheduled for re-rendering, but self is not.
function Fidget:_remove_parent()
  if not self._parent then
    return
  end

  self._parent:schedule_render()
  self._parent.children[self._parent_key] = nil

  self._parent_key = nil
  self._parent = nil
end

--- Retrieve child at given index.
---
---@param k FidgetKey
---@return FidgetSource
function Fidget:get(k)
  return self.children[k]
end

--- Set (or remove) child at given index.
---
--- If a Fidget previously existed at that index, it is destroyed.
---
--- Schedules self for rendering.
---
---@param k FidgetKey: given index
---@param s FidgetSource|nil: child to be set at given index
function Fidget:set(k, s)
  local old_child = self.children[k]
  self.children[k] = s

  if M.is_fidget(s) then
    s:_set_parent(k, self)
  end

  if M.is_fidget(old_child) then
    old_child:schedule_destroy()
  end

  self:schedule_render()
end

--- Add a child, like table.insert().
---
--- Schedules self for rendering.
---
---@param idx number: where child should be inserted
---@param child FidgetSource: the child to be inserted
---@overload fun(self, child: FidgetSource)
function Fidget:insert(idx, child)
  if child then
    table.insert(self.children, idx, child)
  else
    child = idx
    table.insert(self.children, child)
    idx = #self.children
  end

  if M.is_fidget(child) then
    child:_set_parent(idx, self)
  end

  self:schedule_render()
end

--- Remove a child, like table.remove().
---
--- Destroys the removed node, if any.
---
--- Schedules self for rendering.
---
---@param idx number: index of node to remove from Fidget
---@overload fun()
function Fidget:remove(idx)
  local old
  if idx then
    old = table.remove(self.children, idx)
  else
    old = table.remove(self.children)
  end
  if M.is_fidget(old) then
    old:schedule_destroy()
  end

  self:schedule_render()
end

--- Schedule a Fidget to be re-rendered soon.
---
--- This method is idempotent; invoking it multiple times (before this Fidget is
--- re-rendered) is the same as invoking it once.
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
    -- No need to re-schedule self.
    return
  end

  local needs_schedule = self._scheduled == "render"
  -- No need to re-schedule, but "destroy" takes precedence over "render".

  self._scheduled = "destroy"
  self:_remove_parent()

  if needs_schedule then
    schedule_fidget(self)
  end
end

---@private
--- Destroy a Fidget and all its descendents.
---
---@param self Fidget: Fidget to be destroyed
local function do_destroy(self)
  self._scheduled = false

  -- TODO: account for possibility that child was already scheduled for render?

  for _, child in pairs(self.children) do
    if M.is_fidget(child) then
      do_destroy(child)
    end
  end

  self:destroy()

  self.children = nil
  self._parent = nil
  self._output = nil
end

---@private
--- Render a Fidget, updating its ._output.
---
---@param self Fidget: Fidget to be rendered.
local function do_render(self)
  self._scheduled = false

  local data = {}

  for k, src in pairs(self.children) do
    if M.is_fidget(src) then
      -- Node is fidget object that has cached data at src._output
      data[k] = src._output
    elseif type(src) == "function" then
      -- Node is function that returns output data
      data[k] = src()
    else
      -- Node is plain-old data, output it directly
      data[k] = src
    end
  end

  self._output = self:render(data)
end

---@private
--- Handle to manage deferred work.
local work_handle = vim.loop.new_idle()

local work_set = {}

---@private
--- Schedules a Fidget to be rendered or destroyed soon.
---
--- This helper function is idempotent: calling it multiple times is the same as
--- calling it once.
function schedule_fidget(fidget)
  work_set[fidget] = true
  work_handle:start(function()
    work_handle:stop()
    log.trace("Render/destroy phase: started")

    -- Fidgets need to be evaluated in topological order, so we construct the
    -- post-order work queue using DFS (built in FILO order).
    local work_queue = {}

    local function queue_fidget(f)
      if f._queued then
        return
      end

      if f._queued == false then
        error("Circular Fidget topology")
      end

      f._queued = false

      if f._parent and not f._parent._queued then
        queue_fidget(f._parent)
      end

      f._queued = true

      table.insert(work_queue, f)
    end

    log.trace("Render/destroy phase: constructing work schedule")
    for f, _ in pairs(work_set) do
      queue_fidget(f)
    end

    work_set = {}

    log.trace("Render/destroy phase: executing work schedule")
    for i = #work_queue, 1, -1 do
      local f = work_queue[i]
      f._queued = nil

      if f._scheduled == "destroy" then
        do_destroy(f)
      else
        -- Note that it is possible that f._scheduled == false (i.e., it has not
        -- been explicit scheduled), if its children were re-rendered.
        -- Thus we re-render it anyway.
        do_render(f)
      end
    end
    log.trace("Render/destroy phase: complete")
  end)
end

return M
