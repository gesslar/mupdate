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
  1. If you are using muddler/muddy, put the file in your project's resources
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
      -- If using muddler
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

local function generateEventName(base, package_name, profile)
  return base .. "_" .. package_name .. "_" .. profile
end

function Mupdate:Debug(text)
  if self.debug_mode then
    debugc("[" .. (self.package_name or "Mupdate") .. "] " .. text)
  end
end

function Mupdate:Error(text)
  cecho(f [["<red>[ ERROR ]<reset> <DarkOrange>{(self.package_name or "Mupdate")}<reset> - {text}\n"]])
end

function Mupdate:Info(text)
  cecho(f [[<gold>[ INFO ]<reset> <DarkOrange>{(self.package_name or "Mupdate")}<reset> - {text}]] .. "\n")
end

local function isValidRegex(pattern)
  if type(pattern) ~= "string" then
    return false, "Pattern is not a string"
  end

  local success, err = pcall(function() return pattern:match("") end)

  if not success then
    return false, "Invalid regex pattern: " .. err
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
  registerNamedEventHandler(
    "__PKGNAME__",
    "__PKGNAME__.AutoMupdate.Uninstall",
    "sysUninstall",
    function(event, name)
      if name == "__PKGNAME__" then
        deleteAllNamedEventHandlers(self.tag)
        deleteAllNamedTimers(self.tag)
      end
    end
  )

  if self:running() then
    tempTimer(2, function() self:Start() end)
    return
  end

  registerNamedTimer("Mupdate", "MupdateRunning", 10, function()
    deleteNamedTimer("Mupdate", "MupdateRunning")
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

local function parseUrl(url)
  local protocol, host, path, queryString = string.match(url, "^(https?)://([^/]+)/([^?]*)%??(.*)")
  local file = string.match(path, "([^/]+)$")
  local params = parseUrlParams(queryString)
  local parsed = {
    protocol = protocol,
    host = host,
    path = path,
    file = file,
    params = params
  }

  -- Uncomment the below if you also want to see the debugging output
  -- for the parsed URL

  -- Debugging output
  debugc("Parsed URL:")
  debugc("  Protocol: " .. (parsed.protocol or "nil"))
  debugc("  Host: " .. (parsed.host or "nil"))
  debugc("  Path: " .. (parsed.path or "nil"))
  debugc("  File: " .. (parsed.file or "nil"))

  for key, value in pairs(parsed.params) do
    debugc("  Param: " .. key .. " = " .. value)
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
  local parsedUrl = parseUrl(url)
  local expectedFileName = self.package_name .. "_version.txt"

  if self.param_key and parsedUrl.params[self.param_key] then
    if self.param_regex then
      local matched = parsedUrl.params[self.param_key]:match(self.param_regex)

      if matched == expectedFileName then
        self:Debug("Mupdate:sysGetHttpDone - Param regex matches: " .. parsedUrl.params[self.param_key])
        self:checkVersions(response)
      else
        self:Debug("Mupdate:sysGetHttpDone - Param regex does not match: " .. parsedUrl.params[self.param_key])
        self:Debug("Expected: " .. expectedFileName .. ", Got: " .. matched)
      end
    else
      if parsedUrl.params[self.param_key] == expectedFileName then
        self:Debug("Mupdate:sysGetHttpDone - Param matches: " .. parsedUrl.params[self.param_key])
        self:checkVersions(response)
      else
        self:Debug("Mupdate:sysGetHttpDone - Param does not match: " .. parsedUrl.params[self.param_key])
        self:Debug("Expected: " .. expectedFileName .. ", Got: " .. parsedUrl.params[self.param_key])
      end
    end
  elseif not self.param_key and string.find(parsedUrl.file, expectedFileName) then
    self:Debug("Mupdate:sysGetHttpDone - File name matches: " .. parsedUrl.file)
    self:checkVersions(response)
  else
    self:Debug("Mupdate:sysGetHttpDone - URL does not contain the expected parameter or file, ignoring")
    self:Debug("Parsed file: " .. parsedUrl.file)

    if self.param_key then
      self:Debug("Parsed param: " .. (parsedUrl.params[self.param_key] or "nil"))
    end
  end
end

function Mupdate:failHttpGet(event, response, url)
  local parsedUrl = parseUrl(url)
  local expectedFile = self.package_name .. "_version.txt"

  if self.param_key and parsedUrl.params[self.param_key] then
    if self.param_regex then
      local matched = parsedUrl.params[self.param_key]:match(self.param_regex)

      if matched == expectedFile then
        self:Error("Failed to read version from " .. self.versionUrl)
        self:Debug("Mupdate:sysGetHttpError - Param regex matches but failed to read version")
      else
        self:Debug("Mupdate:sysGetHttpError - Param regex does not match: " .. parsedUrl.params[self.param_key])
        self:Debug("Expected: " .. expectedFile .. ", Got: " .. matched)
      end
    else
      if parsedUrl.params[self.param_key] == expectedFile then
        self:Error("Failed to read version from " .. self.versionUrl)
        self:Debug("Mupdate:sysGetHttpError - Param matches but failed to read version")
      else
        self:Debug("Mupdate:sysGetHttpError - Param does not match: " .. parsedUrl.params[self.param_key])
        self:Debug("Expected: " .. expectedFile .. ", Got: " .. parsedUrl.params[self.param_key])
      end
    end
  elseif not self.param_key and string.find(parsedUrl.file, expectedFile) then
    self:Error("Failed to read version from " .. self.versionUrl)
    self:Debug("Mupdate:sysGetHttpError - File matches but failed to read version")
  else
    self:Debug("Mupdate:sysGetHttpError - URL does not contain the expected parameter or file, ignoring")
    self:Debug("Parsed file: " .. parsedUrl.file)

    if self.param_key then
      self:Debug("Parsed param: " .. (parsedUrl.params[self.param_key] or "nil"))
    end
  end
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

function Mupdate:validateEventUrl(url)
  local parsedUrl = parseUrl(url)

  if self.param_key and parsedUrl.params[self.param_key] then
    return parsedUrl.params[self.param_key] == self.package_name
  else
    return parsedUrl.file == self.remote_version_file
  end
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
  self:Debug("Mupdate:loadPackagMmpackage() - Loading package mpackage from: " .. path)
  self:uninstallAndInstall(path)
end

function Mupdate:uninstallAndInstall(path)
  self:Debug("Mupdate:uninstallAndInstall() - Uninstalling and installing: " .. path)
  self:UninstallPackage()

  tempTimer(1, function()
    installPackage(path)
    os.remove(path)
    lfs.rmdir(self.tempFilePath)
    self:Info("Package updated successfully on " .. self.profile)
  end)
end

function Mupdate:failDownload(err, localfile, actualurl)
  self:Error("Failed downloading " .. err)
  self:Debug("Mupdate:failDownload() - " .. err)

  local parsedUrl = parseUrl(actualurl)

  if not self.param_key then
    -- No params, check if file name matches
    if parsedUrl.file == self.package_name .. ".mpackage" then
      self:Debug("Mupdate:failDownload() - File name matches: " .. parsedUrl.file)
    else
      self:Debug("Mupdate:failDownload() - File name does not match: " .. parsedUrl.file)
      self:Debug("Expected: " .. self.package_name .. ".mpackage, Got: " .. parsedUrl.file)
    end
  else
    -- Params exist, check according to param_key and param_regex
    local paramValue = parsedUrl.params[self.param_key]

    if self.param_regex then
      -- Use regex to extract and match
      local matched = paramValue:match(self.param_regex)

      if matched == self.package_name .. ".mpackage" then
        self:Debug("Mupdate:failDownload() - Param regex matches: " .. paramValue)
      else
        self:Debug("Mupdate:failDownload() - Param regex does not match: " .. paramValue)
        self:Debug("Expected: " .. self.package_name .. ".mpackage, Got: " .. matched)
      end
    else
      -- Exact match
      if paramValue == self.package_name .. ".mpackage" then
        self:Debug("Mupdate:failDownload() - Param matches: " .. paramValue)
      else
        self:Debug("Mupdate:failDownload() - Param does not match: " .. paramValue)
        self:Debug("Expected: " .. self.package_name .. ".mpackage, Got: " .. paramValue)
      end
    end
  end
end

function Mupdate:UninstallPackage()
  self:Debug("Mupdate:UninstallPackage() - Uninstalling package: " .. self.package_name)

  -- First, let's pause our own uninstall handler.
  stopNamedEventHandler("__PKGNAME__", "__PKGNAME__.AutoMupdate.Uninstall")

  -- Create a new temporary one to re-enable it after uninstall.
  -- Admittedly, this can be a race condition, but, an unlikely one.
  registerAnonymousEventHandler(
    "sysUninstall",
    function(event, name)
      if name == "__PKGNAME__" then
        resumeNamedEventHandler("__PKGNAME__", "__PKGNAME__.AutoMupdate.Uninstall")
        return false
      end

      return true
    end
    , true
  )

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
  end
end

function Mupdate:semanticVersionSplitter(versionString)
  local t = {}

  for k in string.gmatch(versionString, "([^.]+)") do
    table.insert(t, tonumber(k))
  end

  self:Debug(
    "Mupdate:semanticVersionSplitter() - Split version string: " ..
    versionString .. " -> " .. table.concat(t, ", ")
  )

  return t
end

function Mupdate:compareVersions(installed, remote)
  local splitCurrent = self:semanticVersionSplitter(installed)
  local splitRemote = self:semanticVersionSplitter(remote)

  self:Debug("Mupdate:compareVersions() - Comparing versions, Installed: " ..
    table.concat(splitCurrent, ".") .. ", Remote: " .. table.concat(splitRemote, "."))

  if splitCurrent[1] < splitRemote[1] then
    self:Debug("Mupdate:compareVersions() - Remote version is newer")
    return true
  elseif splitCurrent[1] == splitRemote[1] then
    if splitCurrent[2] < splitRemote[2] then
      self:Debug("Mupdate:compareVersions() - Remote version is newer")

      return true
    elseif splitCurrent[2] == splitRemote[2] then
      if splitCurrent[3] < splitRemote[3] then
        self:Debug("Mupdate:compareVersions() - Remote version is newer")

        return true
      end
    end
  end

  self:Debug("Mupdate:compareVersions() - Installed version is up-to-date")

  return false
end

function Mupdate:Cleanup()
  self:Debug("Mupdate:Cleanup() - Cleaning up")

  self.inProgress = false

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

return Mupdate
