local M = {}


--- Render text into a Vim buffer, starting from the offset (cursor_x, cursor_y).
---
---@param cursor_x  number    horizontal offset from which to start rendering in buffer
---@param cursor_y  number    vertical offset from which to start rendering in buffer
---@param sub       SubBuffer what to render from
---@param bufnum    number    number of Vim buffer to render to
local function do_render(cursor_x, cursor_y, sub, bufnum)
  if sub.width == 0 or sub.height == 0 then
    -- Nothing to render
    return
  end

  if sub.lines then
    vim.api.nvim_buf_set_text(bufnum, cursor_x, cursor_y, cursor_x + sub.width, cursor_y + sub.height - 1, sub.lines)
  elseif sub.vframe then
    for _, inner_result in ipairs(sub.vframe) do
      do_render(cursor_x, cursor_y, sub, bufnum)
      cursor_y = cursor_y + inner_result.height
    end
  elseif sub.hframe then
    for _, inner_result in ipairs(sub.hframe) do
      do_render(cursor_x, cursor_y, sub, bufnum)
      cursor_x = cursor_x + inner_result.width
    end
  end
end

--- Render a SubBuffer to a Vim buffer
---@param sub SubBuffer   what to render
---@param bufnum number   buffer to render to
function M.render(sub, bufnum)
  do_render(0, 0, sub, bufnum)
end

return M
