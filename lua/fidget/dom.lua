local M = {}

local container = require("fidget.dom.container")
local static = require("fidget.dom.static")
local box = require("fidget.dom.box")

---@class DOMNode
--- Elements in a Fidget layout tree.
---
--- Each DOMNode is equipped with an update() method that, at each timestep, is
--- invoked with some Constraint and returns a partially-rendered SubFrame.
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
---@alias UpdateFn fun(self, cons: Constraint): SubFrame|true, number, number
--- The type signature of DOMNodes' update() method. An UpdateFn may return true
--- to indicate that it would have otherwise returned the exact same SubFrame
--- as before, so a cached value should be used. The UpdateFn should also
--- return two additional values, indicating the intended width and height of
--- the returned SubFrame.

---@class Constraint
--- Constraint for rendering SubFrame at each timestep.
---
---@field max_width   number    the maximum rendered line length
---@field max_height  number    the maximum number of lines
---@field now         number    the timestamp of the current frame
---@field delta       number    the time that has passed since the last frame
---@field force       boolean   if true, update() cannot rely on cache (must return SubFrame)

---@class SubFrame
--- A partially-rendered buffer produced by DOMNodes at each timestep.
---
--- A SubFrame represents some virtual rectangular area that can be rendered
--- into a 2-dimensional text buffer by some backend. It is a nested data
--- structure that may contain other SubFrames, laid out horizontally or
--- vertically.
---
--- Its data is contained in the array part and indexed by numbers; the contents
--- of that array depend on which kind of SubFrame this is, as indicated by the
--- value of the "type" field:
---
--- - nil:      This is a text buffer, i.e., an array of strings.
--- - "hframe": This is an array of SubFrames, laid out horizontally.
--- - "vframe": This is an array of SubFrames, laid out vertically.
---
--- If the SubFrame is an hframe or a vframe, it will also have two other
--- fields, "width" and "height"; for some index i, the SubFrame at index [i]
--- is constrained to be ["width"][i] wide and ["height"][i] high.
---
--- Note that the dimensions of each SubFrame are only constrained by its
--- containing frame; on its own, a SubFrame is unconstrained. This means that
--- the contents of an inner SubFrame may be larger than its container; in this
--- case, the inner content will be truncated. (This design is meant to
--- encourage DOM nodes to reuse content and reduce allocations.)
---
---@field type ("hframe"|"vframe")?   nil if this SubFrame is a text buffer
---@field [number] (string|SubFrame)  indexes strings if ["type"] == nil; SubFrames otherwise
---@field width number[]?             defined if ["type"] ~= nil
---@field height number[]?            defined if ["type"] ~= nil

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

---@class BoxOptions
---@field [1]     DOMNode   single child of Box
---@field width   number?   optional width to constrain child by
---@field height  number?   optional height to constrain child by
---
---@param opt BoxOptions
---@return DOMNode
function M.Box(opt)
  assert(#opt == 1, "Box must have exactly one child")

  local child, width, height = opt[1], opt.width, opt.height

  if width ~= nil then
    assert(type(width) == "number" and width > 0, "Box must have positive width")
  end
  if height ~= nil then
    assert(type(height) == "number" and height > 0, "Box must have positive height")
  end

  return box.Box:new(child, width, height)
end

return M
