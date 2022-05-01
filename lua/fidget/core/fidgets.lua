local M = {}

local sched = require("fidget.core.sched")

local do_render
local do_destroy

---@class FidgetOutput
--- The data produced by a Fidget

---@alias FidgetChild Fidget|function()->FidgetOutput|FidgetOutput
--- A Fidget may have non-Fidget children, e.g., functions or unchanging plain data.
--- TODO: if a Fidget "evaluates" to nil, then it is automatically destroyed.

---@alias FidgetSchedState "render"|"destroy"|false

---@alias FidgetRender function(Fidget, table[any]FidgetOutput)->FidgetOutput
---@alias FidgetMethod function(Fidget)

---@class Fidget
--- A Fidget is a hierarchical UI component encapsulating some local state,
--- organized in a forest of Fidgets. Fidgets are equipped with a render method
--- used to produce some kind of output data from that state and the rendered
--- output of their children.
---
---@field class string: class identifier of Fidget instance
---@field render FidgetRender: method to render output (required)
---@field initialize FidgetMethod: method to initialize a fidget (optional)
---@field destroy FidgetMethod: method to cleanup fidget (optional)
---@field children table[any]FidgetChild: children of this Fidget
---@field _parent Fidget|false: optional parent of this Fidget
---@field _scheduled FidgetSchedState: what this Fidget is scheduled to do
---@field _output FidgetOutput: cached result of render
local Fidget = {}
Fidget.__index = Fidget

--- Create subclass of Fidget.
function Fidget:subclass()
  local o = setmetatable({}, self)
  o.__index = o
  return o
end

Fidget.class = "base"
Fidget.render = nil
Fidget.destroy = nil

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
    _parent = false,
    _scheduled = false,
    _output = "unrendered data", -- This dummy value will get overwritten.
  })

  setmetatable(obj, self)
  assert(type(obj.render) == "function", "render method is required")

  for _, child in pairs(obj.children) do
    if type(child) == "table" then
      child._parent = obj
    end
  end

  if obj.initialize then
    obj:initialize()
  end

  -- Initialize this Fidget by rendering it at the next opportunity
  obj:schedule_render()

  return obj
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

  if self._parent then
    self._parent:schedule_render()
  else
    sched.method(self, do_render)
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

  if self._parent then
    self._parent:schedule_render()
  else
    sched.method(self, do_destroy)
  end
end

--- Whether a Fidget is at the root of a Fidget tree, i.e., has no parent.
---@return boolean
function Fidget:is_root()
  return self._parent == nil
end

--- Whether a Fidget is a leaf in a Fidget tree, i.e., has no children.
---@return boolean
function Fidget:is_leaf()
  return next(self.children) == nil
end

--- Retrieve child node at given index.
---
---@param k any: given index
---@return FidgetChild
function Fidget:get(k)
  return self.children[k]
end

--- Set child node at given index.
---
--- If a child previously existed at that key, it is destroyed.
---
--- The parent is scheduled for rendering.
---
---@param k any: given index
---@param child FidgetChild|nil: optional child node
function Fidget:set(k, child)
  local old = self.children[k]

  self.children[k] = child
  if type(child) == "table" then
    child._parent = self
  end

  if type(old) == "table" then
    do_destroy(old)
  end

  self:schedule_render()
end

--- Add a child node, like table.insert().
---
--- Sets self as parent of inserted child if child is a Fidget.
---
--- The parent is scheduled for rendering.
---
---@param idx number: where child should be inserted
---@param child FidgetChild: the child to be inserted
---@overload fun(self, child: FidgetChild)
function Fidget:insert(idx, child)
  table.insert(self.children, idx, child)
  if type(child) == "table" then
    child._parent = self
  end

  self:schedule_render()
end

--- Remove a child node, like table.remove().
---
--- Destroys the removed child, if any.
---
--- The parent is scheduled for rendering.
---
---@param idx number: index of child to remove from Fidget
---@overload fun()
function Fidget:remove(idx)
  local old = table.remove(self.children, idx)
  if type(old) == "table" then
    do_destroy(old)
  end

  self:schedule_render()
end

---@private
--- Render a Fidget, and render or destroy its descendents as necessary.
function do_render(self)
  ---@private
  --- What to do with each child.
  local function eval_child(child)
    if type(child) == "table" then
      -- Child is fidget object that may produce data
      if child._scheduled == "render" then
        child._scheduled = nil

        -- Re-render child
        return do_render(child)
        -- table.insert(children_output, do_render(child))
      elseif child._scheduled == "destroy" then
        -- table.remove(new_children)

        -- Destroy child and all of its descendents
        do_destroy(child)

        return nil
      else
        -- Nothing needs to be done, use cached child data
        return child._output
      end
    elseif type(child) == "function" then
      -- Child is function that returns data
      return child()
    else
      -- Child is plain-old data, insert it directly
      return child
    end
  end

  local children_output = {}
  local new_children = {}

  for k, child in pairs(self.children) do
    local data = eval_child(child)
    if data ~= nil then
      new_children[k] = child
      children_output[k] = data
    end
  end
  self.children = new_children

  self._output = self:render(children_output)
  self._scheduled = nil

  return self._output
end

---@private
--- Destroy a Fidget and all its descendents.
function do_destroy(self)
  for _, child in pairs(self.children) do
    if type(child) == "table" then
      do_destroy(child)
    end
  end
  if self.destroy then
    self:destroy()
  end
  self.children = nil
  self._parent = nil
  self._output = nil
end

M.Fidget = Fidget

return M
