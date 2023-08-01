local M = {}

---@class Container: DOMNode
--- Non-leaves in the Fidget layout tree. Aggregates other nodes.
---
---@field children  DOMNode[]    children of this container
---@field layout    Layout       how children of a container should be arranged
---@field vert      boolean       whether the main axis is vertical
---@field reverse   boolean       whether children are arranged in reverse order
---@field flex      nil          containers do not flex
---
---@alias Layout
---| '"leftright"' # lay out children left-to-right
---| '"rightleft"' # lay out children right-to-left
---| '"topdown"' # lay out children top-to-bottom
---| '"bottomup"' # lay out children bottom-to-top
local Container = {}
Container.__index = Container
M.Container = Container

--- Construct a DOM node container of the given children, in the given layout.
---
---@param children  DOMNode[] the children contained in this node
---@param layout    Layout    the layout those children should be arranged
---@return Container          constructed Container node
function Container:new(children, layout)
  local vert, reverse

  if layout == "topdown" then
    vert, reverse = true, false
  elseif layout == "bottomup" then
    vert, reverse = true, true
  elseif layout == "leftright" then
    vert, reverse = false, false
  elseif layout == "rightleft" then
    vert, reverse = false, true
  else
    assert(false, "Unknown container layout: " .. layout)
  end

  local my_children, cache = {}, {}

  for i, _ in ipairs(children) do
    -- Initialize cache with empty SubBuffers.
    cache[i] = { height = 0, width = 0 }
    -- Construct local array of children
    my_children[i] = children[i]
  end

  return setmetatable({ children = my_children, vert = vert, reverse = reverse, cache = cache }, self)
end

--- Run the update function of a child node.
---
---@param cache SubBuffer[]
---@param idx number
---@param node DOMNode
---@param cons Constraint
---@return SubBuffer, boolean
local function update_node(cache, idx, node, cons)
  -- Run update function
  local result = node:update(cons)

  -- Manage cached result
  if result == true then
    -- Child told us that nothing changed; use cached result
    return cache[idx], false
  else
    -- Child produced updated result; update cache, and mark ourselves dirty
    cache[idx] = result
    return result, true
  end
end

---@param cons Constraint
---@return SubBuffer|true
function Container:update(cons)
  local vert, reverse = self.vert, self.reverse
  local rem_width, rem_height = cons.max_width, cons.max_height

  local begin, limit, step
  if reverse then
    begin, limit, step = #self.children, 1, -1
  else
    begin, limit, step = 1, #self.children, 1
  end

  -- These will be accumulated as we iterate
  local total_flex, final_height, final_width, frame, dirty = 0, 0, 0, {}, false

  -- First, evaluate all the non-flex children (and count up flex)
  for idx = begin, limit, step do
    local child = self.children[idx]
    if child.flex ~= nil then
      total_flex = total_flex + child.flex
    else

      local result, width, height = child:update{
        max_width = rem_width,
        max_height = rem_height,
        now = cons.now,
        delta = cons.delta
      }

      -- TODO: WIP

      dirty = dirty or child_dirty

      result.width = math.min(result.width, rem_width)
      result.height = math.min(result.height, rem_height)

      if vert then
        rem_height = rem_height - result.height
        final_height = final_height + result.height
        final_width = math.max(final_width, result.width)
      else
        rem_width = rem_width - result.width
        final_width = final_width + result.width
        final_height = math.max(final_height, result.height)
      end

      if reverse then
        frame[begin + 1 - idx] = result
      else
        frame[idx] = result
      end
    end
  end

  if not dirty then
    -- Optimization: nothing changed with non-flex children, so don't even
    -- bother polling the flex children. Return nil to let the parent re-use our
    -- cached value.
    return true
  end

  -- Then, evaluate remaining (flex) children, distributing remaining dimension
  if total_flex > 0 then
    for idx = begin, limit, step do
      local child = self.children[idx]
      if child.flex ~= nil then
        local child_width, child_height
        if vert then
          child_width = rem_width
          child_height = math.floor(rem_height * child.flex / total_flex)
        else
          child_width = math.floor(rem_width * child.flex / total_flex)
          child_height = rem_height
        end

        local result = update_node(self.cache, idx, child, {
          max_width = child_width,
          max_height = child_height,
          now = cons.now,
          delta = cons.delta,
        })

        result.width = math.min(result.width, child_width)
        result.height = math.min(result.height, child_height)

        if vert then
          final_height = final_height + result.height
          final_width = math.max(final_width, result.width)
        else
          final_width = final_width + result.width
          final_height = math.max(final_height, result.height)
        end

        if reverse then
          frame[begin + 1 - idx] = result
        else
          frame[idx] = result
        end
      end
    end
  end

  local sub = {
    width = final_width,
    height = final_height,
  }

  if vert then
    sub.vframe = frame
  else
    sub.hframe = frame
  end

  return sub
end

return M
