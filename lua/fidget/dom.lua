---@class DOMNode
--- Elements in a Fidget layout tree.
---
--- Each DOMNode is equipped with an update() method that, at each timestep, is
--- invoked with some Constraint and returns a partially-rendered SubBuffer.
--- DOMNodes that contain children should recursively invoke the update()
--- methods of those children during this update phase.
---
--- The flex factor is used by Container nodes to determine how available space
--- should be allocated among their children. DOMNodes with nil/zero flex factor
--- have their update() methods called first (in an order determined by the
--- layout of the container node). Their update() method will _always_ be
--- invoked, even if there is no remaining space for them (so the Constraint
--- they are given will have 0 as one of the dimensions). This is so that they
--- can still update their local state without being obligated to return
--- anything.
---
--- DOMNodes with a non-nil/non-zero flex factor, used to fill remaining space
--- among a collection of nodes. The space is divided among them according to
--- their flex factor (higher flex factor means higher proportion of available
--- space is given). However, their update() method may not be called if there's
--- no remaining space to fill in the container.
---
---@field update  UpdateFn      method invoked to generate each frame
---@field flex    number?       determines distribution of remaining space
---
---@alias UpdateFn fun(self, cons: Constraint): SubBuffer?
--- The type signature of DOMNodes' update() method. When an UpdateFn returns
--- nil, the container should use the SubBuffer returned by the previous call
--- (which should be cached).

---@class Constraint
--- Constraint for rendering SubBuffer at each timestep.
---
---@field max_width   number    the maximum rendered line length
---@field max_height  number    the maximum number of lines
---@field now         number    the timestamp of the current frame
---@field delta       number    the time that has passed since the last frame

---@class SubBuffer
--- A partially-rendered frame produced by DOMNodes at each timestep.
---
--- A SubBuffer represents a virtual rectangular area that can be rendered into
--- a 2-dimensional textual buffer by some backend.
---
--- A SubBuffer may directly contain content (when lines is defined), or other
--- SubBuffers that are layed out horizontally (when hframe is defined) or
--- vertically (when vframe is defined).
---
--- Exactly one field should be defined among lines, vframe, and hframe.
---
--- The dimensions of the virtual rectangular area are solely determined by the
--- width and height fields, and populated by the contents rendered from lines,
--- vframe, or hframe. Note that actual length of any line (or the combined
--- virtual length rendered from vframe or hframe) may be smaller than or exceed
--- the width field of the SubBuffer; the backend is responsible for padding or
--- truncating the displayed output accordingly. The same is true for the height
--- of the SubBuffer. (The SubBuffer is specified this way to encourage DOM
--- nodes to reuse rendered textual content and reduce allocations; they need
--- only adjust the height and width according to changing constraints.)
---
--- If either width or height are 0, then the backend should ignore the
--- SubBuffer during rendering, and should not attempt to read from lines,
--- vframe, or hframe (since those may be undefined).
---
---@field width   number          horizontal dimension of the frame
---@field height  number          vertical dimension of the frame
---@field lines   string[]?       array of lines of rendered text
---@field vframe  SubBuffer[]?    vertically stacked results
---@field hframe  SubBuffer[]?    horizontally stacked results
---@field restart true?           whether to restart after termination

local M = {}

local container = require("fidget.dom.container")
local static = require("fidget.dom.static")

---@class RowOptions
---@field [number]  DOMNode                     children to be laid out horizontally
---@field layout    ("leftright"|"rightleft")?  direction children are laid out (default = "leftright")
---
---@param opt RowOptions
---@return    DOMNode
function M.Row(opt)
  assert(#opt > 0, "Row must be constructed with at least one child")

  local layout = opt.layout or "leftright"
  assert(layout == "leftright" or layout == "rightleft", "Row layout must be either 'leftright' or 'rightleft'")

  return container.Container:new(opt, layout)
end

---@class ColOptions
---@field [number]  DOMNode                 children to be laid out vertically
---@field layout    ("topdown"|"bottomup")? direction chilren are laid out (default = "topdown")
---
---@param opt ColOptions
---@return    DOMNode
function M.Col(opt)
  assert(#opt > 0, "Col must be constructed with at least one child")

  local layout = opt.layout or "topdown"
  assert(layout == "topdown" or layout == "bottomup", "Row layout must be either 'topdown' or 'bottomup'")

  return container.Container:new(opt, layout)
end

---@class FillOptions
---@field flex        number?   flex factor for this Fill (default = 1)
---@field fill        string?   string used to generate padding (default = " ")
---@field max_width   number?   maximum width to pad (default = "999")
---@field max_height  number?   maximum height to pad (default = "299")
---
---@param opt FillOptions
---@return    DOMNode
function M.Fill(opt)
  local flex = opt.flex or 1
  local fill = opt.fill or " "
  local max_width = opt.max_width or 999
  local max_height = opt.max_width or 299

  assert(type(flex) == "number" and flex > 0, "Fill must have positive flex factor")
  assert(type(fill) == "string" and #fill > 0, "Fill must be filled with non-empty")
  assert(type(max_width) == "number" and max_width > 0, "Fill must have positive max width")
  assert(type(max_height) == "number" and max_height > 0, "Fill must have positive max height")

  -- To avoid duplication: generate a single line, and point all entries of
  -- lines to the same line.
  local line = string.rep(fill, math.ceil(max_width / #fill))
  local lines = {}
  for _ = 1, max_height do
    table.insert(lines, line)
  end

  return static.Static:new(lines, flex)
end

---@class TextOptions
---@field [number]  string  lines of static text to display
---@field flex      number? optional flex factor (default = nil)
---
---@param opt TextOptions
---@return    DOMNode
function M.Text(opt)
  local flex = opt.flex

  assert(#opt > 0, "Text must have at least one line of text")
  if type(flex) ~= "nil" then
    assert(type(flex) == "number" and flex >= 0, "Text must have numeric flex factor")
  end

  return static.Static:new(opt, flex)
end

return M
