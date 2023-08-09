local M = {}

---@class Box: DOMNode
--- A DOM node that limits the dimensions of its single child.
---
--- A Box may render a SubFrame smaller than its width and height, but never
--- anything larger. It does so by limiting the Constraint passed to its child.
---
---@field child   DOMNode   DOM node contained in this Box
---@field width   number?   maximum width
---@field height  number?   maximum height
local Box = {}
Box.__index = Box
M.Box = Box

--- Construct a Box DOM node.
---
---@param child   DOMNode   child node
---@param width   number?   optional width to constrain child by
---@param height  number?   optional height to constrain child by
---@return        Box       constructed Box node
function Box:new(child, width, height)
  return setmetatable({ child = child, width = width, height = height }, self)
end

--- Construct a SubFrame given constraints.
---
--- Note that a Box doesn't wrap an additional SubFrame around what is returned
--- by the child, since that's unnecessary. As such, a Box also relies on the
--- cache of its parent when its child returns nil.
---
---@param cons  Constraint
---@return      SubFrame|true
function Box:update(cons)
  local max_width, max_height = cons.max_width, cons.max_height

  if self.width then
    max_width = math.min(max_width, self.width)
  end
  if self.height then
    max_height = math.min(max_height, self.height)
  end

  return self.child:update(vim.fn.extend({ max_width = max_width, max_height = max_height }, cons, "keep"))
end

return M
