--- Helpers for scheduling work in the event loop's idle phase.
---
--- The primary feature that this module provides is idempotency, i.e., the
--- ability to schedule the same thing multiple times in the same instant, but
--- only have it be run once.
local sched = {}

---@private
--- Set of outstanding work to complete, indexed by some key.
local work_set = {}

---@private
--- Handle to manage deferred work.
local work_handle = vim.loop.new_idle()

---@private
--- Perform deferred work.
local function deferred_work()
  work_handle:stop()

  for _, work in pairs(work_set) do
    vim.schedule(function()
      work.callback(vim.F.unpack_len(work.args))
    end)
  end

  -- clear work set
  work_set = {}
end

--- Schedule some work to be performed later, indexed by a key.
---
---@param key any: key used to
---@param cb function(...)|nil: callback to be performed
---@vararg any: arguments applied to callback later
function sched.call(key, cb, ...)
  if not cb then
    work_set[cb] = nil
    return
  end

  work_set[key] = {
    callback = cb,
    args = vim.F.pack_len(...),
  }

  work_handle:start(deferred_work)
end

--- Schedule a method to be called on an object later.
---
---@generic O
---@param self `O`: the object whose method is to be scheduled
---@param method function(O): the method to be scheduled
function sched.method(self, method)
  sched.call(self, method, self)
end

return sched
