--[[
  Test harness for Mupdate specs running inside Mudlet (gesslardev/mudlet-busted).

  Mudlet's own event and named-timer machinery is used as-is. Only the edges
  are replaced:

  - Time: tempTimer/killTimer are swapped for a fake clock. Mudlet's named
    timers are built on the global tempTimer, so registerNamedTimer and friends
    keep their real bookkeeping and simply fire when the clock is advanced.
  - The outside world: network, package install/uninstall, package info and
    the filesystem calls Mupdate makes are recorded instead of performed.
  - Handler errors: Mudlet swallows errors raised inside event handlers, which
    would let a broken handler pass silently. Handlers are wrapped so errors
    are recorded and reported by teardown().
]]

local H = {}

local here = debug.getinfo(1, "S").source:match("^@(.*/)")
H.root = here .. "../../../"

local real = {}

-- Records every call to `name` in H.calls[name] and returns `result`.
local function recorder(name, result)
  H.calls[name] = H.calls[name] or {}

  return function(...)
    table.insert(H.calls[name], { ... })

    if type(result) == "function" then
      return result(...)
    end

    return result
  end
end

-- Fake clock --------------------------------------------------------------

local function fakeTempTimer(delay, fn, repeating)
  assert(type(fn) == "function", "harness: tempTimer only supports functions")

  H.clock.nextId = H.clock.nextId + 1
  local id = H.clock.nextId

  H.clock.timers[id] = {
    id = id,
    at = H.clock.now + delay,
    delay = delay,
    fn = fn,
    repeating = repeating,
  }

  return id
end

local function fakeKillTimer(id)
  if H.clock.timers[id] then
    H.clock.timers[id] = nil
    return true
  end

  return false
end

--- Advance the fake clock by `seconds`, firing due timers in order.
function H.advance(seconds)
  local target = H.clock.now + seconds

  while true do
    local nextTimer

    for _, timer in pairs(H.clock.timers) do
      if timer.at <= target and (not nextTimer or timer.at < nextTimer.at
          or (timer.at == nextTimer.at and timer.id < nextTimer.id)) then
        nextTimer = timer
      end
    end

    if not nextTimer then break end

    H.clock.now = nextTimer.at

    if nextTimer.repeating then
      nextTimer.at = nextTimer.at + nextTimer.delay
    else
      H.clock.timers[nextTimer.id] = nil
    end

    nextTimer.fn()
  end

  H.clock.now = target
end

-- Handler error capture ----------------------------------------------------

local function guard(label, fn)
  return function(...)
    local result = { pcall(fn, ...) }

    if not result[1] then
      table.insert(H.handlerErrors, label .. ": " .. tostring(result[2]))
      error(result[2])
    end

    return unpack(result, 2)
  end
end

-- Setup / teardown ----------------------------------------------------------

--- Installed packages as seen by getPackageInfo, keyed by name.
H.packages = {}

function H.setup()
  H.calls = {}
  H.handlerErrors = {}
  H.anonymousHandlers = {}
  H.clock = { now = 0, nextId = 0, timers = {} }
  H.packages = {
    MupTest = { version = "1.0.0" },
  }

  real.tempTimer = _G.tempTimer
  real.killTimer = _G.killTimer
  real.getHTTP = _G.getHTTP
  real.downloadFile = _G.downloadFile
  real.installPackage = _G.installPackage
  real.uninstallPackage = _G.uninstallPackage
  real.getPackageInfo = _G.getPackageInfo
  real.debugc = _G.debugc
  real.cecho = _G.cecho
  real.osRemove = os.remove
  real.ioExists = io.exists
  real.lfsMkdir = lfs.mkdir
  real.lfsRmdir = lfs.rmdir
  real.registerNamedEventHandler = _G.registerNamedEventHandler
  real.registerAnonymousEventHandler = _G.registerAnonymousEventHandler
  real.Mupdate = rawget(_G, "Mupdate")

  _G.tempTimer = fakeTempTimer
  _G.killTimer = fakeKillTimer

  _G.getHTTP = recorder("getHTTP")
  _G.downloadFile = recorder("downloadFile")
  _G.installPackage = recorder("installPackage")
  _G.debugc = recorder("debugc")
  _G.cecho = recorder("cecho")
  os.remove = recorder("os.remove", true)
  lfs.mkdir = recorder("lfs.mkdir", true)
  lfs.rmdir = recorder("lfs.rmdir", true)

  -- Mudlet raises sysUninstall with the package name while uninstalling.
  _G.uninstallPackage = recorder("uninstallPackage", function(name)
    H.packages[name] = nil
    raiseEvent("sysUninstall", name)

    return true
  end)

  _G.getPackageInfo = recorder("getPackageInfo", function(name, field)
    local info = H.packages[name]

    if not info then return nil end
    if field then return info[field] end

    return info
  end)

  _G.registerNamedEventHandler = function(user, name, event, fn, ...)
    return real.registerNamedEventHandler(user, name, event, guard(user .. "/" .. name, fn), ...)
  end

  _G.registerAnonymousEventHandler = function(event, fn, ...)
    local id = real.registerAnonymousEventHandler(event, guard("anonymous " .. event, fn), ...)
    table.insert(H.anonymousHandlers, id)

    return id
  end
end

--- Restores everything and returns the errors raised inside event handlers.
--- `users` are named handler/timer users to clear between tests.
function H.teardown(users)
  -- Delete named timers while the fake killTimer can still cancel them.
  for _, user in ipairs(users or {}) do
    deleteAllNamedTimers(user)
    deleteAllNamedEventHandlers(user)
  end

  deleteAllNamedTimers("Mupdate")

  for _, id in ipairs(H.anonymousHandlers) do
    killAnonymousEventHandler(id)
  end

  _G.tempTimer = real.tempTimer
  _G.killTimer = real.killTimer
  _G.getHTTP = real.getHTTP
  _G.downloadFile = real.downloadFile
  _G.installPackage = real.installPackage
  _G.uninstallPackage = real.uninstallPackage
  _G.getPackageInfo = real.getPackageInfo
  _G.debugc = real.debugc
  _G.cecho = real.cecho
  os.remove = real.osRemove
  io.exists = real.ioExists
  lfs.mkdir = real.lfsMkdir
  lfs.rmdir = real.lfsRmdir
  _G.registerNamedEventHandler = real.registerNamedEventHandler
  _G.registerAnonymousEventHandler = real.registerAnonymousEventHandler
  _G.Mupdate = real.Mupdate

  return H.handlerErrors
end

-- Loading the code under test ---------------------------------------------

--- Loads a fresh copy of Mupdate.lua the way require() would.
function H.loadMupdate()
  local chunk = assert(loadfile(H.root .. "Mupdate.lua"))

  return chunk("Mupdate")
end

--- Loads Updater.lua with __PKGNAME__ replaced, as muddy does when building.
function H.loadUpdater(packageName)
  local file = assert(io.open(H.root .. "Updater.lua", "r"))
  local source = file:read("*a"):gsub("__PKGNAME__", packageName)
  file:close()

  local chunk = assert(loadstring(source, "@Updater.lua"))

  return chunk()
end

-- Helpers -----------------------------------------------------------------

function H.options(overrides)
  local options = {
    download_path = "https://example.test/releases/latest/download/",
    package_name = "MupTest",
    remote_version_file = "MupTest_version.txt",
  }

  for k, v in pairs(overrides or {}) do
    options[k] = v
  end

  return options
end

--- The URL GitHub redirects a release asset download to, which is what
--- Mudlet reports in sysGetHttpDone and friends.
function H.githubAssetUrl(fileName)
  return "https://objects.githubusercontent.com/github-production-release-asset-2e65be/123/abc"
      .. "?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Expires=300"
      .. "&response-content-disposition=attachment%3B%20filename%3D" .. fileName
      .. "&response-content-type=application%2Foctet-stream"
end

function H.callCount(name)
  return #(H.calls[name] or {})
end

function H.lastCall(name)
  local calls = H.calls[name] or {}

  return calls[#calls]
end

function H.hasNamedTimer(user, name)
  for _, timer in ipairs(getNamedTimers(user) or {}) do
    if timer == name then return true end
  end

  return false
end

function H.hasNamedHandler(user, name)
  for _, handler in ipairs(getNamedEventHandlers(user) or {}) do
    if handler == name then return true end
  end

  return false
end

function H.locked()
  return H.hasNamedTimer("Mupdate", "MupdateRunning")
end

--- Every string cecho'd, concatenated.
function H.output()
  local out = {}

  for _, call in ipairs(H.calls.cecho or {}) do
    table.insert(out, call[1])
  end

  return table.concat(out)
end

return H
