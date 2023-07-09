local M = {}

local node = require("fidget.node")
local container = require("fidget.container")
local fill = require("fidget.fill")
local text = require("fidget.text")

M.render = node.render

function M.Fill(o)
  return fill.Fill:new(o)
end

function M.Text(o)
  return text.Text:new(o)
end

function M.Container(o)
  return container.Container:new(o)
end

return M
