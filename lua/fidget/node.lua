local M = {}

---@class UpdateMessage
---
---@field max_width number  the maximum rendered line length
---@field max_height number the maximum number of lines
---@field now number        the timestamp of the current frame
---@field delta number      the time that has passed since the last frame
---
---@class UpdateResult
---
--- Only one of lines, vresults, and hresults should be defined.
---
---@field width number                  maximum width of any line in frame
---@field height number                 maximum number of lines in frame
---@field lines string[]?               array of lines of rendered text
---@field vresults UpdateResult[]?      vertically stacked results
---@field hresults UpdateResult[]?      horizontally stacked results
---@field restart true?                 whether to restart after termination

---@class Node
--- Elements in a layout tree.
---
---@field update  UpdateFn          function used to generate each frame.
---@field coroutine boolean|thread  whether to run update in a coroutine context
---@field flex number?
---
---@alias UpdateFn fun(self: self, msg: UpdateMessage): UpdateResult?

--- Render text into a text buffer, starting from the offset (cursor_x, cursor_y).
---
---@param cursor_x number
---@param cursor_y number
---@param buffer string[][]
---@param result UpdateResult
local function do_render(cursor_x, cursor_y, buffer, result)
  if result.width == 0 or result.height == 0 then
    -- Nothing to render
    return
  end

  if result.lines then
    for y, line in ipairs(result.lines) do
      buffer[y + cursor_y] = buffer[y + cursor_y] ..
          string.sub(line, 1, result.width) .. string.rep(" ", result.width - #line)
    end
  elseif result.vresults then
    for _, inner_result in ipairs(result.vresults) do
      do_render(cursor_x, cursor_y, buffer, inner_result)
      if inner_result.width < result.width then
        -- inner frame is narrower than the outer frame; pad spacing on the right side
        for y = 1, inner_result.height do
          buffer[y + cursor_y] = buffer[y + cursor_y] .. string.rep(" ", result.width - inner_result.width)
        end
      end
      cursor_y = cursor_y + inner_result.height
    end
  elseif result.hresults then
    for _, inner_result in ipairs(result.hresults) do
      do_render(cursor_x, cursor_y, buffer, inner_result)
      if inner_result.height < result.height then
        -- inner frame is shorter than outer frame; pad empty lines on the bottom
        for x = inner_result.height + 1, result.height do
          buffer[x] = buffer[x] .. string.rep(" ", inner_result.width)
        end
      end
      cursor_x = cursor_x + inner_result.width
    end
  end
end

--- Render an UpdateResult into a text buffer, i.e., a 2D character array.
---
---@param result UpdateResult
---@teturn string[][]
function M.render(result)
  local buffer = {}
  for _ = 1, result.height do
    table.insert(buffer, "")
  end

  do_render(0, 0, buffer, result)

  return buffer
end

return M
