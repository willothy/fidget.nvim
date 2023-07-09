local M = {}

---@class Container: Node
--- Non-leaves in the layout tree. Aggregates other nodes, including Content.
---
---@field [number] Node         children of this container
---@field layout Layout         how children of a container should be arranged
---@field coroutine false       no need to run update in coroutine context
---@field flex nil              containers do not themselves flex.
---@field cache UpdateResult[]  cached result of each child
---
---@alias Layout
---| '"leftright"' # lay out children left-to-right
---| '"rightleft"' # lay out children right-to-left
---| '"topbottom"' # lay out children top-to-bottom
---| '"bottomtop"' # lay out children bottom-to-top
local Container = {}
Container.__index = Container
M.Container = Container

function Container:new(o)
  setmetatable(o, self)
  return o
end

---Run the update function of a child node, possibly in a coroutine.
---
---@param cache UpdateResult[]
---@param idx number
---@param node Node
---@param msg UpdateMessage
---@return UpdateResult, boolean
local function update_node(cache, idx, node, msg)
  ---@type UpdateResult?
  local result, dirty = nil, false

  -- Run update function
  local co = node.coroutine
  if co then
    -- Update function should be run in coroutine context
    if type(co) ~= "thread" then
      -- coroutine not started
      co = coroutine.create(node.update)
      node.coroutine = co
    end

    _, result = coroutine.resume(co, msg)

    -- TODO: handle non-success??

    if result == nil then
      result = cache[idx]
    else
      cache[idx] = result
    end
  else
    -- Update function is just a one-shot function
    result = node:update(msg)
  end

  -- Manage cached result
  if result == nil then
    -- Child told us that nothing changed; use cached result
    result = cache[idx]
  else
    -- Child produced updated result; update cache, and mark ourselves dirty
    cache[idx] = result
    dirty = true
  end

  if type(co) == "thread" and coroutine.status(co) == "dead" then
    node.coroutine = result.restart
  end

  return result, dirty
end

---@param msg UpdateMessage
---@return UpdateResult?
function Container:update(msg)
  local vert = self.layout == "topbottom" or self.layout == "bottomtop"
  local reverse = self.layout == "rightleft" or self.layout == "bottomtop"
  local rem_width, rem_height = msg.max_width, msg.max_height

  if self.cache == nil then
    -- FIXME: complete this, initialize members
    self.cache = {}
  end

  local begin, limit, step
  if reverse then
    begin, limit, step = #self, 1, -1
  else
    begin, limit, step = 1, #self, 1
  end

  -- These will be accumulated as we iterate
  local total_flex, final_height, final_width, frame, dirty = 0, 0, 0, {}, false

  -- First, evaluate all the non-flex children (and count up flex)
  for idx = begin, limit, step do
    local child = self[idx]
    if child.flex ~= nil then
      total_flex = total_flex + child.flex
    else
      local result, child_dirty = update_node(self.cache, idx, child, {
        max_width = rem_width,
        max_height = rem_height,
        now = msg.now,
        delta = msg.delta
      })

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
    -- bother polling the flex children. Return nil to let the parent use our
    -- cached value.
    return nil
  end

  -- Then, evaluate remaining (flex) children, distributing remaining dimension
  if total_flex > 0 then
    for idx = begin, limit, step do
      local child = self[idx]
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
          now = msg.now,
          delta = msg.delta,
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

  local res = {
    width = final_width,
    height = final_height,
    restart = true,
  }

  if vert then
    res.vresults = frame
  else
    res.hresults = frame
  end
  return res
end

return M
