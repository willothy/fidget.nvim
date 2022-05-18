-- TODO: refactor terminology in terms of flow graph
local M = {}

local schedule_fidget

---@class Fidget
--- A Fidget is a UI model component encapsulating some local state, organized
--- in an acyclic flow network of Fidgets. Fidgets are equipped with a render
--- method used to produce some kind of output data from that state and the
--- rendered output of their children.
---
---@field class string: class identifier of Fidget instance
---@field render FidgetRender: method to render output (required)
---@field children table<any, FidgetSource>: inbound data sources
---@field _parent Fidget|nil: where to propragate output to
---@field _scheduled FidgetSchedState: what this Fidget is scheduled to do
---@field _queued boolean|nil: whether this Fidget is queued for evaluation
---@field _output FidgetOutput: cached result of render
local Fidget = {}
M.Fidget = Fidget
Fidget.__index = Fidget

---@class FidgetOutput
--- The data produced by a Fidget

---@alias FidgetSource Fidget|function()->FidgetOutput|FidgetOutput
--- A Fidget may have non-Fidget sources, e.g., functions or unchanging plain data.

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
    children = {},
  })
  obj = vim.tbl_extend("error", obj, {
    -- Internal fields
    _parent = {},
    _scheduled = false,
    _queued = false,
    _output = "unrendered data", -- This dummy value will get overwritten.
  })

  setmetatable(obj, self)

  for _, child in pairs(obj.children) do
    if M.is_fidget(child) then
      child:_set_parent(obj)
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
---@param inputs table[any]FidgetOutput: table of child outputs
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
  return next(self._parent) == nil
end

--- Whether a Fidget has no children.
---@return boolean
function Fidget:is_leaf()
  return next(self.children) == nil
end

function Fidget:_set_parent(parent)
  if self._parent then
    error("already has parent")
  end
  self._parent = parent
end

--- Retrieve inbound node at given index.
---
---@param k any: given index
---@return FidgetSource
function Fidget:get(k)
  return self.children[k]
end

--- Set children at given index.
---
--- If a node previously existed at that key, it is destroyed.
---
--- Schedules self for rendering.
---
---@param k any: given index
---@param s FidgetSource|nil: optional ib node
function Fidget:set(k, s)
  local old = self.children[k]

  self.children[k] = s
  if M.is_fidget(s) then
    s:_set_parent(self)
  end

  if M.is_fidget(old) then
    old:schedule_destroy()
  end

  self:schedule_render()
end

--- Add a child, like table.insert().
---
--- Sets self as parent of inserted child if child is a Fidget,
--- and schedules self for rendering.
---
---@param idx number: where child should be inserted
---@param child FidgetSource: the child to be inserted
---@overload fun(self, child: FidgetSource)
function Fidget:insert(idx, child)
  if child then
    table.insert(self.children, idx, child)
  else
    table.insert(self.children, idx)
  end
  if type(child) == "table" then
    child:_set_parent(self)
  end

  self:schedule_render()
end

--- Remove a child, like table.remove().
---
--- Destroys the removed node, if any,
--- and schedules self for rendering.
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
  if type(old) == "table" then
    do_destroy(old)
  end

  self:schedule_render()
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

---@private
--- Destroy a Fidget and all its descendents.
local function do_destroy(self)
  self._scheduled = false

  -- TODO: account for possibility that child was already scheduled for render

  for _, ib in pairs(self.children) do
    if type(ib) == "table" then
      do_destroy(ib)
    end
  end
  self:destroy()
  self.children = nil
  self._parent = nil
  self._output = nil
end

---@private
--- Render a Fidget, and render or destroy its descendents as necessary.
local function do_render(self)
  self._scheduled = false
  ---@private
  --- What to do with each inbound datum.
  local function eval_source(k, src)
    if type(src) == "table" then
      -- Node is fidget object that has cached data at src._output
      return src._output
      -- if src._scheduled == "render" then
      --   src._scheduled = nil
      --
      --   -- Re-render Fidget
      --   return do_render(src)
      -- elseif src._scheduled == "destroy" then
      --   -- Destroy node and all of its upstream peers
      --   do_destroy(src)
      --
      --   return nil
      -- else
      --   -- Nothing needs to be done, use cached output
      --   return src._output
      -- end
    elseif type(src) == "function" then
      -- Node is function that returns output data
      return src()
    else
      -- Node is plain-old data, output it directly
      return src
    end
  end

  local inbound_data = {}
  local destroyed_children = {}
  for k, src in pairs(self.children) do
    if type(src) == "table" then
      if src._parent == nil then
        -- This child was destroyed
      end
    elseif type(src) == "function" then
      inbound_data[k] = src()
    else
      inbound_data[k] = src
    end

    -- inbound_data[k] = eval_source(k, d)
  end
  self._output = self:render(inbound_data)
  self._scheduled = nil

  return self._output
end

---@private
--- Handle to manage deferred work.
local work_handle = vim.loop.new_idle()

local work_set = {}

function schedule_fidget(fidget)
  work_set[fidget] = true
  work_handle:start(function()
    work_handle:stop()

    -- Fidgets need to be evaluated in topological order, so we construct the
    -- post-order work queue using DFS (built as a stack).
    local work_queue = {}

    local function queue_fidget(f)
      if f._queued then
        return
      end

      if f._queued == false then
        error("circular Fidget topology")
      end

      f._queued = false

      if f._parent and not f._parent._queued then
        queue_fidget(f._parent)
      end

      f._queued = true

      table.insert(work_queue, f)
    end

    for f, _ in pairs(work_set) do
      queue_fidget(f)
    end

    work_set = {}

    for i = #work_queue, 1, -1 do
      local f = work_queue[i]
      f._queued = nil

      if f._scheduled == "destroy" then
        do_destroy(f)
      else
        -- NOTE: It is possible that f._scheduled == false (i.e., it has not
        -- been explicit scheduled), if its children were re-rendered.
        -- Thus we re-render it anyway.
        do_render(f)
      end
    end
  end)
end

return M
