--[[
  Mupdate Auto-Updater Module
  Written by Gesslar@ThresholdRPG

  Description:
  This module provides an auto-updater for packages within the MUD client,
  Mudlet.

  It automates the process of checking for new versions of a package,
  downloading updates, and installing them.

  Acknowledgements:
  This module was essentially ripped off from the MUDKIP_Mud2 package from
  11BelowStudio, and refactored. The original is available at:

    https://github.com/11BelowStudio/MUDKIP_Mud2

  Original acknowledgements from the MUDKIP_Mud2 package:

  The core functionality of this auto-updater was adapted from the DSL PNP 4.0
  Main Script by Zachary Hiland, originally shared on the Mudlet forums:

  https://forums.mudlet.org/viewtopic.php?p=20504

  Special thanks to @demonnic for providing additional Lua code and guidance
  on package installation.

  Instructions for Use:
  1. If you are using muddy/muddler, put the file in your project's resources
     directory.

     If you are developing directly in Mudlet, add the file to your Mudlet
     package's Script Group within Mudlet, and ensure that it is higher than
     the script that will be calling it.

  2. In your package script, require the Mupdate module and instantiate it with
     the necessary options.

  Variables:
  - download_path: The URL path where the package files are hosted.
  - package_name: The name of your package.
  - remote_version_file: The file name of the version check file on the server.
  - param_key: (Optional) The key of the URL parameter to check for the file
    name.
  - param_regex: (Optional) The regex pattern to extract the file name from the
    URL parameter value.
  - debug_mode: Boolean flag to enable or disable debug mode for detailed
    logging.

  Example implementation:

  -- Auto Updater
  function ThreshCopy:Loaded()
      -- If using muddy/muddler
      -- local Mupdate = require("ThreshCopy/Mupdate")
      if not Mupdate then return end

      -- GitHub example
      local updater = Mupdate:new({
          download_path = "https://github.com/gesslar/ThreshCopy/releases/latest/download/",
          package_name = "ThreshCopy",
          remote_version_file = "ThreshCopy_version.txt",
          param_key = "response-content-disposition",
          param_regex = "attachment; filename=(.*)",
          debug_mode = true
      })
      updater:Start()
  end

  -- Start it up
  ThreshCopy.LoadHandler = ThreshCopy.LoadHandler or registerAnonymousEventHandler("sysLoadEvent", "ThreshCopy:Loaded")

  Version Comparison:
  - Mupdate calls `getPackageInfo(package_name)` to get your package's version
    number. Which must be in the SemVer format. So, this must be set on your
    package.
  - Mupdate downloads the version file from the same location that hosts your
    `.mpackage` file, and its contents must simply contain the updated version
    in the SemVer format.

  Semantic Versioning:

  The Mupdate system requires the use of semantic versioning (SemVer) for
  package version numbers.

  Semantic versioning follows the format MAJOR.MINOR.PATCH, where:

  - MAJOR version increments indicate incompatible API changes
  - MINOR version increments add functionality in a backward-compatible manner
  - PATCH version increments include backward-compatible bug fixes

  Example:
  - 1.0.0 -> Initial release
  - 1.1.0 -> New feature added
  - 1.1.1 -> Bug fix
  - 2.0.0 -> Breaking change introduced
]] --

local MupdateRequired = {
  download_path = "string",
  package_name = "string",
  remote_version_file = "string",
}

local Mupdate = {
  download_path = nil,
  package_name = nil,
  packageUrl = nil,
  remote_version_file = nil,
  versionUrl = nil,
  filePath = nil,
  param_key = nil,
  param_regex = nil,
  initialized = false,
  debug_mode = false,
}

-- The lock is released by Cleanup() when an update run finishes. This is only
-- a fallback for a run that never hears back from Mudlet.
local LOCK_TIMEOUT = 60

local function generateEventName(base, package_name, profile)
  return base .. "_" .. package_name .. "_" .. profile
end

function Mupdate:Debug(text)
  if self.debug_mode then
    debugc("[" .. (self.package_name or "Mupdate") .. "] " .. text)
  end
end

function Mupdate:Error(text)
  cecho(f [[<red>[ ERROR ]<reset> <DarkOrange>{(self.package_name or "Mupdate")}<reset> - {text}]] .. "\n")
end

function Mupdate:Info(text)
  cecho(f [[<gold>[ INFO ]<reset> <DarkOrange>{(self.package_name or "Mupdate")}<reset> - {text}]] .. "\n")
end

-- Lua only reports a malformed pattern when matching reaches the bad part, so
-- trying it against a sample string can't catch every mistake. Walk the
-- pattern instead and check the pieces Lua would reject.
local function isValidRegex(pattern)
  if type(pattern) ~= "string" then
    return false, "Pattern is not a string"
  end

  -- Open captures, innermost last, and which numbered captures have closed.
  local open, closed, count = {}, {}, 0
  local i = 1

  while i <= #pattern do
    local c = pattern:sub(i, i)

    if c == "%" then
      local class = pattern:sub(i + 1, i + 1)

      if class == "" then
        return false, "pattern ends with '%'"
      elseif class == "b" then
        if #pattern < i + 3 then
          return false, "missing arguments to '%b'"
        end

        i = i + 4
      elseif class:match("%d") then
        if not closed[tonumber(class)] then
          return false, "invalid capture index %" .. class
        end

        i = i + 2
      elseif class == "f" then
        if pattern:sub(i + 2, i + 2) ~= "[" then
          return false, "missing '[' after '%f' in pattern"
        end

        i = i + 2
      else
        i = i + 2
      end
    elseif c == "[" then
      local j = i + 1

      if pattern:sub(j, j) == "^" then j = j + 1 end
      -- A ']' straight after the opening bracket is a literal member.
      if pattern:sub(j, j) == "]" then j = j + 1 end

      while pattern:sub(j, j) ~= "]" do
        if j > #pattern then
          return false, "missing ']'"
        end

        j = j + (pattern:sub(j, j) == "%" and 2 or 1)
      end

      i = j + 1
    elseif c == "(" then
      count = count + 1
      table.insert(open, count)
      i = i + 1
    elseif c == ")" then
      if #open == 0 then
        return false, "invalid pattern capture"
      end

      closed[table.remove(open)] = true
      i = i + 1
    else
      i = i + 1
    end
  end

  if #open > 0 then
    return false, "unfinished capture"
  end

  return true, ""
end

function Mupdate:new(options)
  options = options or {}

  for k, v in pairs(MupdateRequired) do
    if not options[k] then
      error("Mupdate:new() [" .. (options.package_name or "Unknown") .. "] - Required field " .. k .. " is missing")
    end

    if type(options[k]) ~= v then
      error(
        "Mupdate:new() ["
        .. (options.package_name or "Unknown") ..
        "] - Required field " .. k .. " is not of type " .. v
      )
    end
  end

  if options.param_regex then
    local valid, reason = isValidRegex(options.param_regex)

    if not valid then
      error("Mupdate:new() [" .. (options.package_name or "Unknown") .. "] - Invalid regex pattern: " .. reason)
    end
  end

  local me = setmetatable({}, { __index = self })
  for k, v in pairs(options) do
    me[k] = v
  end

  me.filePath = getMudletHomeDir() .. "/" .. me.package_name .. "/"
  me.tempFilePath = getMudletHomeDir() .. "/" .. me.package_name .. "_temp" .. "/"
  me.packageUrl = me.download_path .. me.package_name .. ".mpackage"
  me.versionUrl = me.download_path .. me.remote_version_file

  local packageInfo = getPackageInfo(me.package_name)

  if not packageInfo then
    error("Mupdate:new() [" .. me.package_name .. "] - Package " .. me.package_name .. " not found")
  end

  if not packageInfo.version then
    error("Mupdate:new() [" .. me.package_name .. "] - Package " .. me.package_name .. " does not have a version")
  end

  me.currentVersion = packageInfo.version
  me:Debug("Mupdate:new() - Current version: " .. me.currentVersion)

  me.profile = getProfileName()
  me:Debug("Mupdate:new() - Profile: " .. me.profile)

  me.initialized = true

  return me
end

function Mupdate:running()
  local timers = getNamedTimers("Mupdate") or {}

  for _, timer in ipairs(timers) do
    if timer == "MupdateRunning" then
      return true
    end
  end

  return false
end

function Mupdate:Start()
  -- Captured now because Cleanup() clears self before uninstall can happen.
  local package_name = self.package_name

  registerNamedEventHandler(
    package_name,
    package_name .. ".AutoMupdate.Uninstall",
    "sysUninstall",
    function(event, name)
      if name == package_name then
        -- Only the run that holds the lock is in progress, so this never
        -- releases another package's lock.
        if self.inProgress then
          self:Cleanup()
        end

        -- Also cancels a retry still waiting for the lock.
        deleteAllNamedEventHandlers(package_name)
        deleteAllNamedTimers(package_name)
      end
    end
  )

  if self:running() then
    registerNamedTimer(package_name, package_name .. ".AutoMupdate.Retry", 2, function()
      self:Start()
    end)
    return
  end

  registerNamedTimer("Mupdate", "MupdateRunning", LOCK_TIMEOUT, function()
    self:Cleanup()
  end)

  self:Debug("Mupdate:Start() - Auto-updater started")

  if not self.initialized then
    error("Mupdate:Start() - Mupdate object not initialized")
  end

  self.inProgress = true

  self:registerEventHandlers()
  self:updateScripts()
end

local function urlDecode(str)
  str = string.gsub(str, '+', ' ')
  str = string.gsub(str, '%%(%x%x)', function(h)
    return string.char(tonumber(h, 16))
  end)

  return str
end

local function parseUrlParams(queryString)
  local params = {}

  for keyValue in string.gmatch(queryString, "([^&]+)") do
    local key, value = string.match(keyValue, "([^=]+)=([^=]+)")

    if key and value then
      params[urlDecode(key)] = urlDecode(value)
    end
  end

  return params
end

function Mupdate:parseUrl(url)
  local protocol, host, path, queryString = string.match(url, "^(https?)://([^/]+)/([^?]*)%??(.*)")
  local file = string.match(path or "", "([^/]+)$")
  local params = parseUrlParams(queryString or "")
  local parsed = {
    protocol = protocol,
    host = host,
    path = path,
    file = file,
    params = params
  }

  self:Debug("Parsed URL:")
  self:Debug("  Protocol: " .. (parsed.protocol or "nil"))
  self:Debug("  Host: " .. (parsed.host or "nil"))
  self:Debug("  Path: " .. (parsed.path or "nil"))
  self:Debug("  File: " .. (parsed.file or "nil"))

  for key, value in pairs(parsed.params) do
    self:Debug("  Param: " .. key .. " = " .. value)
  end

  return parsed
end

function Mupdate:registerEventHandlers()
  local handlerEvents = {
    sysDownloadDone = generateEventName("DownloadDone", self.package_name, self.profile),
    sysDownloadError = generateEventName("DownloadError", self.package_name, self.profile),
    sysGetHttpDone = generateEventName("HTTPDone", self.package_name, self.profile),
    sysGetHttpError = generateEventName("HTTPError", self.package_name, self.profile),
  }

  local existingHandlers = getNamedEventHandlers(self.package_name) or {}
  local newEvents = {}

  for event, label in pairs(handlerEvents) do
    if not existingHandlers[label] then
      newEvents[event] = label
    end
  end

  if newEvents["sysDownloadDone"] then
    registerNamedEventHandler(self.package_name, newEvents["sysDownloadDone"], "sysDownloadDone",
      function(event, path, size, response)
        if not self.inProgress then return end

        self:handleDownloadDone(event, path, size, response)
      end)
  end

  if newEvents["sysDownloadError"] then
    registerNamedEventHandler(self.package_name, newEvents["sysDownloadError"], "sysDownloadError",
      function(event, err, path, actualUrl)
        if not self.inProgress then return end

        self:handleDownloadError(event, err, path, actualUrl)
      end)
  end

  if newEvents["sysGetHttpDone"] then
    registerNamedEventHandler(self.package_name, newEvents["sysGetHttpDone"], "sysGetHttpDone",
      function(event, url, response)
        if not self.inProgress then return end

        self:handleHttpGet(event, url, response)
      end)
  end

  if newEvents["sysGetHttpError"] then
    registerNamedEventHandler(self.package_name, newEvents["sysGetHttpError"], "sysGetHttpError",
      function(event, response, url)
        if not self.inProgress then return end
        self:handleHttpError(event, response, url)
      end)
  end
end

function Mupdate:finishHttpGet(event, url, response)
  if not self:urlIsFor(url, self.remote_version_file, self.versionUrl) then
    self:Debug("Mupdate:sysGetHttpDone - Not our version file, ignoring")
    return
  end

  self:Debug("Mupdate:sysGetHttpDone - Received version file")
  self:checkVersions(response)
end

function Mupdate:failHttpGet(event, response, url)
  if not self:urlIsFor(url, self.remote_version_file, self.versionUrl) then
    self:Debug("Mupdate:sysGetHttpError - Not our version file, ignoring")
    return
  end

  self:Error("Failed to read version from " .. self.versionUrl)
  self:Debug("Mupdate:sysGetHttpError - " .. tostring(response))
  self:Cleanup()
end

function Mupdate:handleDownloadDone(event, path, size, response)
  -- Compare the downloaded file path with the expected file path
  if path ~= self.tempFilePath .. self.package_name .. ".mpackage" then
    return
  end

  self:Debug("Mupdate:sysDownloadDone() - Downloaded path = " .. path)
  self:finishDownload(path)
end

function Mupdate:handleDownloadError(event, err, path, actualurl)
  -- Compare the downloaded file path with the expected file path
  if path ~= self.tempFilePath .. self.package_name .. ".mpackage" then
    return
  end

  self:Debug("Mupdate:sysDownloadError() - Error downloading: " .. err)
  self:failDownload(err, path, actualurl)
end

function Mupdate:handleHttpGet(event, url, response)
  self:finishHttpGet(event, url, response)
end

function Mupdate:handleHttpError(event, response, url)
  self:failHttpGet(event, response, url)
end

-- Whether `url` is the response for `fileName`, requested from `requestUrl`.
-- GitHub redirects release downloads to a URL that carries the file name in
-- a parameter, which param_key and param_regex extract. Without param_key,
-- the URL's own file name is compared.
--
-- With param_key set, a URL lacking the parameter means the file was served
-- directly, so it must be the URL we requested: every script's HTTP events
-- reach this handler, and a common name like version.txt could otherwise
-- match someone else's request.
function Mupdate:urlIsFor(url, fileName, requestUrl)
  local parsedUrl = self:parseUrl(url)
  local paramValue = self.param_key and parsedUrl.params[self.param_key]

  if self.param_key and not paramValue then
    self:Debug("Mupdate:urlIsFor() - Expected: " .. requestUrl .. ", Got: " .. url)

    return url == requestUrl
  end

  local found

  if not paramValue then
    found = parsedUrl.file
  elseif self.param_regex then
    found = paramValue:match(self.param_regex)
  else
    found = paramValue
  end

  self:Debug("Mupdate:urlIsFor() - Expected: " .. fileName .. ", Got: " .. tostring(found))

  return found == fileName
end

function Mupdate:unregisterEventHandlers()
  local downloadHandlerLabel = generateEventName("DownloadDone", self.package_name, self.profile)
  local downloadErrorHandlerLabel = generateEventName("DownloadError", self.package_name, self.profile)
  local httpHandlerLabel = generateEventName("HTTPDone", self.package_name, self.profile)
  local httpErrorHandlerLabel = generateEventName("HTTPError", self.package_name, self.profile)

  deleteNamedEventHandler(self.package_name, downloadHandlerLabel)
  deleteNamedEventHandler(self.package_name, downloadErrorHandlerLabel)
  deleteNamedEventHandler(self.package_name, httpHandlerLabel)
  deleteNamedEventHandler(self.package_name, httpErrorHandlerLabel)
end

function Mupdate:updatePackage()
  lfs.mkdir(self.tempFilePath)

  downloadFile(
    self.tempFilePath .. self.package_name .. ".mpackage",
    self.packageUrl
  )
end

function Mupdate:updateScripts()
  self:Debug("Mupdate:updateScripts() - Starting script update check")
  self:getVersionCheck()
end

function Mupdate:finishDownload(path)
  self:Debug("Mupdate:finishDownload() - Finished downloading: " .. path)
  self:loadPackageMpackage(path)
end

function Mupdate:loadPackageMpackage(path)
  self:Debug("Mupdate:loadPackageMpackage() - Loading package mpackage from: " .. path)
  self:uninstallAndInstall(path)
end

function Mupdate:uninstallAndInstall(path)
  self:Debug("Mupdate:uninstallAndInstall() - Uninstalling and installing: " .. path)
  self:UninstallPackage()

  -- Copied out so the install doesn't depend on self surviving the delay.
  local tempFilePath = self.tempFilePath
  local profile = self.profile
  local package_name = self.package_name

  tempTimer(1, function()
    installPackage(path)
    os.remove(path)
    lfs.rmdir(tempFilePath)
    resumeNamedEventHandler(package_name, package_name .. ".AutoMupdate.Uninstall")

    -- The lock timeout may already have emptied self via Cleanup().
    if self.initialized then
      self:Info("Package updated successfully on " .. profile)
      self:Cleanup()
    end
  end)
end

function Mupdate:failDownload(err, localfile, actualurl)
  self:Error("Failed downloading " .. err)
  self:Debug("Mupdate:failDownload() - " .. err)

  if self.debug_mode then
    local ours = self:urlIsFor(actualurl, self.package_name .. ".mpackage", self.packageUrl)
    self:Debug("Mupdate:failDownload() - URL is for our package: " .. tostring(ours))
  end

  self:Cleanup()
end

function Mupdate:UninstallPackage()
  self:Debug("Mupdate:UninstallPackage() - Uninstalling package: " .. self.package_name)

  -- Pause our own uninstall handler so this uninstall doesn't tear down the
  -- updater. uninstallAndInstall() resumes it once the new version is in;
  -- resuming from a sysUninstall handler would let Mudlet deliver this same
  -- event to it.
  stopNamedEventHandler(self.package_name, self.package_name .. ".AutoMupdate.Uninstall")

  uninstallPackage(self.package_name)

  _G[self.package_name] = nil
end

function Mupdate:getVersionCheck()
  getHTTP(self.versionUrl)
end

function Mupdate:checkVersions(version)
  -- Extract the first line and remove any trailing newline characters
  local firstLineVersion = version:match("([^\n]*)")

  if firstLineVersion then
    firstLineVersion = firstLineVersion:gsub("%s+$", "")
  end

  local currVersion = self.currentVersion

  self:Debug("Mupdate:checkVersions() - Installed version: " ..
    currVersion .. ", Remote version: " .. firstLineVersion)

  if self:compareVersions(currVersion, firstLineVersion) then
    self:Info("Attempting to update " .. self.package_name .. " to v" .. firstLineVersion)
    self:Debug("Mupdate:checkVersions() - Remote version is newer, proceeding to update package")
    self:updatePackage()
  else
    self:Debug("Mupdate:checkVersions() - Installed version is up-to-date")
    self:Cleanup()
  end
end

-- Parses MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]. Missing parts default to 0
-- and build metadata is ignored, as SemVer says it has no bearing on order.
function Mupdate:semanticVersionSplitter(versionString)
  local core, prerelease = versionString:match("^v?([%d.]+)%-?([^+]*)")

  if not core then
    return nil
  end

  local t = { 0, 0, 0, prerelease = {} }
  local i = 0

  for part in core:gmatch("(%d+)") do
    i = i + 1
    if i > 3 then break end
    t[i] = tonumber(part)
  end

  for id in prerelease:gmatch("([^.]+)") do
    table.insert(t.prerelease, id:match("^%d+$") and tonumber(id) or id)
  end

  self:Debug(
    "Mupdate:semanticVersionSplitter() - Split version string: " ..
    versionString .. " -> " .. table.concat(t, ", ") ..
    (#t.prerelease > 0 and (" pre " .. table.concat(t.prerelease, ".")) or "")
  )

  return t
end

-- SemVer precedence for pre-release identifiers: numeric ids compare
-- numerically and sort before alphanumeric ones, and a longer list wins a tie.
local function prereleaseLess(a, b)
  for i = 1, math.max(#a, #b) do
    local x, y = a[i], b[i]

    if x == nil then return true end
    if y == nil then return false end

    if x ~= y then
      local xn, yn = type(x) == "number", type(y) == "number"

      if xn and yn then return x < y end
      if xn ~= yn then return xn end

      return x < y
    end
  end

  return false
end

function Mupdate:compareVersions(installed, remote)
  local splitCurrent = self:semanticVersionSplitter(installed)
  local splitRemote = self:semanticVersionSplitter(remote)

  if not splitCurrent or not splitRemote then
    self:Error("Unable to compare versions, installed: " .. installed .. ", remote: " .. remote)

    return false
  end

  self:Debug("Mupdate:compareVersions() - Comparing versions, Installed: " ..
    table.concat(splitCurrent, ".") .. ", Remote: " .. table.concat(splitRemote, "."))

  local newer = false

  for i = 1, 3 do
    if splitCurrent[i] ~= splitRemote[i] then
      newer = splitCurrent[i] < splitRemote[i]
      break
    end

    -- Same MAJOR.MINOR.PATCH: a release outranks any of its pre-releases.
    if i == 3 then
      local preCurrent, preRemote = splitCurrent.prerelease, splitRemote.prerelease

      if #preCurrent > 0 and #preRemote == 0 then
        newer = true
      elseif #preCurrent > 0 then
        newer = prereleaseLess(preCurrent, preRemote)
      end
    end
  end

  self:Debug("Mupdate:compareVersions() - " ..
    (newer and "Remote version is newer" or "Installed version is up-to-date"))

  return newer
end

function Mupdate:Cleanup()
  self:Debug("Mupdate:Cleanup() - Cleaning up")

  self.inProgress = false

  -- Release the lock so the next package waiting in Start() can run.
  deleteNamedTimer("Mupdate", "MupdateRunning")

  -- Unregister event handlers
  if self.package_name then
    self:unregisterEventHandlers()
  end

  -- Set all keys to nil
  for k in pairs(self) do
    self[k] = nil
  end

  -- Break the metatable link
  setmetatable(self, nil)
end

-- Loaded as a Mudlet script rather than through require(), there is no
-- caller to receive the return value, so expose it globally instead.
if not ... then
  _G.Mupdate = Mupdate
end

return Mupdate
