--[[

This is the auto-updater for this package. It uses downloads the latest
version of Mupdate and then uses it to download the latest version of the
package, uninstalls the old version, and installs the new version.

If this script has __PKGNAME__ in the name, it will be automatically translated
to the package name when run through muddler. Else, you will have to do
a search/replace for your package name.

This script should be able to be dropped in as-is, but you will need to
customize the settings for Mupdate to work properly.

The Customizable settings are:
  mupdateUrl: The URL to download the latest version of Mupdate
  payload: A table of settings for Mupdate
    downloadPath: The URL to download the latest version of the package
    packageName: The name of the package
    remoteVersionFile: The name of the file that contains the version
    paramKey: (optional) The key to look for in the headers
    paramRegex: (optional) The regex to use to extract the filename from the headers
    debugMode: (optional) Whether to print debug messages

Written by Gesslar@ThresholdRPG 2024-06-24

]] --

__PKGNAME__ = __PKGNAME__ or {}
__PKGNAME__.Mupdate = __PKGNAME__.Mupdate or {
  -- System information
  tag = "__PKGNAME__.AutoMupdate",
  packageDirectory = getMudletHomeDir() .. "/__PKGNAME__",
  localPath = getMudletHomeDir() .. "/__PKGNAME__/Mupdate.lua",
  functionName = "__PKGNAME__:AutoMupdate",
  handlerEvents = {
    sysDownloadDone = "__PKGNAME__.AutoMupdate.DownloadDone",
    sysDownloadError = "__PKGNAME__.AutoMupdate.DownloadError"
  },

  -- Customizable settings
  mupdateUrl = "https://github.com/gesslar/Mupdate/releases/latest/download/Mupdate.lua",
  payload = {
    downloadPath = "https://github.com/gesslar/__PKGNAME__/releases/latest/download/",
    packageName = "__PKGNAME__",
    remoteVersionFile = "__PKGNAME___version.txt",
    paramKey = "response-content-disposition",
    paramRegex = "attachment; filename=(.*)",
    debugMode = true
  }
}

function __PKGNAME__.Mupdate:Debug(message)
  if not self.debugMode then return end

  debugc(message)
end

function __PKGNAME__.Mupdate:AutoMupdate(handle, path)
  self:Debug("AutoMupdate - Package Name: __PKGNAME__, Handle: " .. handle)

  if handle ~= self.tag then return end

  registerNamedTimer(self.tag, self.tag, 2, function()
    deleteAllNamedTimers(self.tag)
    package.loaded["__PKGNAME__/Mupdate"] = nil
    self.MupdateScript = require("__PKGNAME__/Mupdate")
    self.Mupdater = self.MupdateScript:new(self.payload)
    self.Mupdater:Start()
  end)
end

function __PKGNAME__.Mupdate:RegisterMupdateEventHandlers()
  local existingHandlers = getNamedEventHandlers(self.tag) or {}
  local newEvents = {}
  for event, label in pairs(self.handlerEvents) do
    if not existingHandlers[label] then
      self:Debug("Adding new event for " .. label)
      newEvents[event] = label
    else
      self:Debug("Event for " .. label .. " already exists.")
    end
  end

  if newEvents["sysDownloadDone"] then
    registerNamedEventHandler(
      self.tag,
      newEvents["sysDownloadDone"],
      "sysDownloadDone",
      function(event, path, size, response)
        self:Debug("Received download event for " .. path)

        if path ~= self.localPath then return end
        self:UnregisterMupdateEventHandlers()
        self:AutoMupdate(self.tag, path)
      end
    )
  end

  if newEvents["sysDownloadError"] then
    registerNamedEventHandler(
      self.tag,
      newEvents["sysDownloadError"],
      "sysDownloadError",
      function(event, err, path, actualurl)
        self:Debug("Received download error event for " .. path)
        self:Debug("Error: " .. err)

        if path ~= self.localPath then return end
        self:UnregisterMupdateEventHandlers()
      end
    )
  end
end

function __PKGNAME__.Mupdate:UnregisterMupdateEventHandlers()
  local existingHandlers = getNamedEventHandlers(self.tag) or {}
  for _, label in pairs(self.handlerEvents) do
    local result = deleteNamedEventHandler(self.tag, label)
  end
end

function __PKGNAME__.update()
  local version = getPackageInfo("__PKGNAME__", "version")
  cecho(f "<chocolate>[[ __PKGNAME__ ]]<reset> Initiating manual update to currently installed version {version}.\n")
  cecho(f "<chocolate>[[ __PKGNAME__ ]]<reset> If there is a new version, it will be downloaded and installed.\n")
  cecho(f "<chocolate>[[ __PKGNAME__ ]]<reset> Full logging of update activity may be found in <u>Scripts</u> > <u>Errors</u>\n")

  __PKGNAME__.Mupdate:downloadLatestMupdate()
end

function __PKGNAME__.Mupdate:downloadLatestMupdate()
  local packagePathExists = io.exists(self.packageDirectory)
  self:Debug("Package directory " .. self.packageDirectory .. " exists: " .. tostring(packagePathExists))

  local pathExists = io.exists(self.localPath)

  if pathExists then
    self:Debug("Path " .. self.localPath .. " exists: Removing")
    local success, err = pcall(os.remove, self.localPath)
    if not success then
      self:Debug(err)
      return
    else
      self:Debug("Succeeded in removing " .. self.localPath)
    end
  else
    self:Debug("Path " .. self.localPath .. " does not exist.")
  end

  -- Register the download event handlers
  self:Debug("Registering download handlers.")
  self:RegisterMupdateEventHandlers()

  -- Initiate download
  self:Debug("Initiating download of " .. self.mupdateUrl .. " to " .. self.localPath)
  downloadFile(self.localPath, self.mupdateUrl)
end

-- Start it up
registerNamedEventHandler(
  __PKGNAME__.Mupdate.tag,            -- username
  __PKGNAME__.Mupdate.tag .. ".Load", -- handler name
  "sysLoadEvent",                     -- event name
  function(event) __PKGNAME__.Mupdate:downloadLatestMupdate() end
)
