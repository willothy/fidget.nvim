local M = {}

--- Render text into a text buffer, starting from the offset (cursor_x, cursor_y).
---
---@param cursor_x  number    horizontal offset from which to start rendering in buffer
---@param cursor_y  number    vertical offset from which to start rendering in buffer
---@param buffer    string[]  pre-allocated buffer to render into
---@param sub       SubFrame what to render from
---@param padding   string    character to pad empty space with
local function do_render(cursor_x, cursor_y, buffer, sub, padding)
  if sub.width == 0 or sub.height == 0 then
    -- Nothing to render
    return
  end

  if sub.lines then
    for y, line in ipairs(sub.lines) do
      buffer[y + cursor_y] = buffer[y + cursor_y] ..
          string.sub(line, 1, sub.width) .. string.rep(padding, sub.width - #line)
    end
  elseif sub.vframe then
    for _, inner_result in ipairs(sub.vframe) do
      do_render(cursor_x, cursor_y, buffer, inner_result, padding)
      if inner_result.width < sub.width then
        -- inner frame is narrower than the outer frame; pad spacing on the right side
        for y = 1, inner_result.height do
          buffer[y + cursor_y] = buffer[y + cursor_y] .. string.rep(padding, sub.width - inner_result.width)
        end
      end
      cursor_y = cursor_y + inner_result.height
    end
  elseif sub.hframe then
    for _, inner_result in ipairs(sub.hframe) do
      do_render(cursor_x, cursor_y, buffer, inner_result, padding)
      if inner_result.height < sub.height then
        -- inner frame is shorter than outer frame; pad empty lines on the bottom
        for x = inner_result.height + 1, sub.height do
          buffer[x] = buffer[x] .. string.rep(padding, inner_result.width)
        end
      end
      cursor_x = cursor_x + inner_result.width
    end
  end
end

--- Render a SubFrame into a text canvas, i.e., an array of strings.
---
---@param sub     SubFrame   what to render
---@param padding string      character to pad empty space with
---@return        string[]    what is rendered
function M.render(sub, padding)
  -- Pre-allocate vertical dimension of buffer we will render to, by allocating
  -- an array of empty strings; do_render() will extend each line
  local buffer = {}

  for _ = 1, sub.height do
    table.insert(buffer, "")
  end

  do_render(0, 0, buffer, sub, padding)

  return buffer
end

return M
