vim.opt.rtp:append("/Users/j-hui/Documents/personal/fidget.nvim")

local d = require("fidget.dom")
local s = require("fidget.sub")

local cons = {
  delta = 1,
  now = 0,
  max_height = 8,
  max_width = 25,
}

local t1 = d.Text {
  "first line",
  "second line",
  "thirdthirdthirdthirdthird",
  "4",
  "fivefivefivefivefivefivefive",
  "sixy",
}

local t2 = d.Row {
  d.Text { "aaa", "aaaaaa" },
  d.Text { "b", "bb", "bbbb" },
  d.Text { "c" },
}


-- local res = t:update(msg)

sub = t1:update(cons)
-- print(vim.inspect(sub) .. "\n")

local buf = s.render_to_strings(sub)

print("+" .. string.rep("-", sub.width + 2) .. "+")
for _, line in ipairs(buf) do
  print("|", line, "|")
end
print("+" .. string.rep("-", sub.width + 2) .. "+")

print("fin\n")
