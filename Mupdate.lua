--[[
    Mupdate Auto-Updater Module
    Written by Gesslar@ThresholdRPG

    Description:
    This module provides an auto-updater for packages within the MUD client, Mudlet.
    It automates the process of checking for new versions of a package, downloading updates, and installing them.

    Acknowledgements:
    This module was essentially ripped off from the MUDKIP_Mud2 package from 11BelowStudio, and refactored. The original
    is available at:
    https://github.com/11BelowStudio/MUDKIP_Mud2

    The core functionality of this auto-updater was adapted from the DSL PNP 4.0 Main Script by Zachary Hiland,
    originally shared on the Mudlet forums:
    https://forums.mudlet.org/viewtopic.php?p=20504

    Special thanks to @demonnic for providing additional Lua code and guidance on package installation.

    Instructions for Use:
    1. If you are using muddler, put the file in your project's resources directory.
       If you are developing directly in Mudlet, add the file to your Mudlet package's Script Group within Mudlet,
       and ensure that it is higher than the script that will be calling it.

    2. In your package script, require the Mupdate module and instantiate it with the necessary options.

    Variables:
    - download_path: The URL path where the package files are hosted.
    - package_name: The name of your package.
    - version_check_download: The file name of the version check file on the server.
    - version_check_save: The file name to save the downloaded version check file locally.
    - debug_mode: Boolean flag to enable or disable debug mode for detailed logging.

       Example implementation:

       -- Auto Updater
       function ThreshCopy:Loaded()
           -- If using muddler
           -- require("ThreshCopy\\Mupdate")
           if not Mupdate then return end

           local updater = Mupdate:new({
               download_path = "https://github.com/gesslar/ThreshCopy/releases/latest/download/",
               package_name = "ThreshCopy",
               version_check_download = "version.txt",
               version_check_save = "version.txt",
               debug_mode = true
           })
           updater:Start()
       end

       -- Start it up
       ThreshCopy.LoadHandler = ThreshCopy.LoadHandler or registerAnonymousEventHandler("sysLoadEvent", "ThreshCopy:Loaded")

    Version Comparison:
    - Mupdate calls `getPackageInfo(packageName)` to get your package's version number.
      Which must be in the SemVar (above) format. So, this must be set on your package.
    - Mupdate downloads the version file from the same location that hosts your `.mpackage`
      file, and its contents must simply contain the updated version in the SemVar format.

    Semantic Versioning:
    The Mupdate system requires the use of semantic versioning (SemVer) for package version numbers.
    Semantic versioning follows the format MAJOR.MINOR.PATCH, where:
    - MAJOR version increments indicate incompatible API changes,
    - MINOR version increments add functionality in a backward-compatible manner, and
    - PATCH version increments include backward-compatible bug fixes.

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
    package_url = nil,
    remote_version_file = nil,
    version_url = nil,
    file_path = nil,
    param_key = nil,
    initialized = false,
    debug_mode = false,
}

local function generateEventName(base, packageName)
    return base .. "_" .. packageName
end

function Mupdate:Debug(text)
    if self.debug_mode then
        debugc("[" .. (self.package_name or "Mupdate") .. "] " .. text)
    end
end

function Mupdate:Error(text)
    cecho("<b><ansiLightRed>ERROR</b><reset> [" .. (self.package_name or "Mupdate") .. "] - " .. text .. "\n")
end

function Mupdate:Info(text)
    cecho("<b><ansiLightYellow>INFO</b><reset> [" .. (self.package_name or "Mupdate") .. "] - " .. text .. "\n")
end

function Mupdate:new(options)
    options = options or {}

    for k, v in pairs(MupdateRequired) do
        if not options[k] then
            error("Mupdate:new() [" .. (options.package_name or "Unknown") .. "] - Required field " .. k .. " is missing")
        end
        if type(options[k]) ~= v then
            error("Mupdate:new() [" .. (options.package_name or "Unknown") .. "] - Required field " .. k .. " is not of type " .. v)
        end
    end

    local me = setmetatable({}, { __index = self })
    for k, v in pairs(options) do
        me[k] = v
    end

    me.file_path = getMudletHomeDir() .. "/" .. me.package_name .. "/"
    me.temp_file_path = getMudletHomeDir() .. "/" .. me.package_name .. "_temp" .. "/"
    me.package_url = me.download_path .. me.package_name .. ".mpackage"
    me.version_url = me.download_path .. me.remote_version_file

    local packageInfo = getPackageInfo(me.package_name)
    if not packageInfo then
        error("Mupdate:new() [" .. me.package_name .. "] - Package " .. me.package_name .. " not found")
    end
    if not packageInfo.version then
        error("Mupdate:new() [" .. me.package_name .. "] - Package " .. me.package_name .. " does not have a version")
    end

    me.current_version = packageInfo.version
    me:Debug("Mupdate:new() - Current version: " .. me.current_version)

    me.initialized = true

    return me
end

function Mupdate:Start(cb)
    self:Debug("Mupdate:Start() - Auto-updater started")

    if not self.initialized then
        error("Mupdate:Start() [" .. self.package_name .. "] - Mupdate object not initialized")
    end

    self.callback = cb
    self:Info("Checking url: " .. self.version_url)
    self:registerEventHandlers()
    self:update_scripts()
end

-- Local function to decode URL entities
local function url_decode(str)
    str = string.gsub(str, '+', ' ')
    str = string.gsub(str, '%%(%x%x)', function(h)
        return string.char(tonumber(h, 16))
    end)
    return str
end

-- Local function to parse URL parameters
local function parse_url_params(query_string)
    local params = {}
    for key_value in string.gmatch(query_string, "([^&]+)") do
        local key, value = string.match(key_value, "([^=]+)=([^=]+)")
        if key and value then
            params[url_decode(key)] = url_decode(value)
        end
    end
    return params
end

-- Local function to parse the entire URL
local function parse_url(url)
    local protocol, host, file, query_string = string.match(url, "^(https?)://([^/]+)/(.-)%??(.*)")
    local params = parse_url_params(query_string)
    return {
        protocol = protocol,
        host = host,
        file = file,
        params = params
    }
end

function Mupdate:registerEventHandlers()
    local downloadHandlerLabel = generateEventName("DownloadDone", self.package_name)
    local downloadErrorHandlerLabel = generateEventName("DownloadError", self.package_name)
    local httpHandlerLabel = generateEventName("HTTPDone", self.package_name)
    local httpErrorHandlerLabel = generateEventName("HTTPError", self.package_name)

    registerNamedEventHandler(self.package_name, downloadHandlerLabel, "sysDownloadDone", function(event, path , size, response)
        self:finish_download(event, path)
    end)

    registerNamedEventHandler(self.package_name, downloadErrorHandlerLabel, "sysDownloadError", function(event, err, localfile, actualurl)
        if self:validate_event_url(actualurl) then
            self:fail_download(event, err, localfile, actualurl)
        else
            self:Done()
        end
    end)

    registerNamedEventHandler(self.package_name, httpHandlerLabel, "sysGetHttpDone", function(event, url, response)
        if self:validate_event_url(url) then
            self:Debug("Mupdate:get_version_check() [" .. self.package_name .. "] - URL: " .. url)
            self:Debug("Mupdate:get_version_check() [" .. self.package_name .. "] - Response: " .. response)
            self:check_versions(response)
        else
            self:Debug("Mupdate:get_version_check() [" .. self.package_name .. "] - Ignored response for URL: " .. url)
        end
    end)

    registerNamedEventHandler(self.package_name, httpErrorHandlerLabel, "sysGetHttpError", function(event, response, url)
        if self:validate_event_url(url) then
            self:Error("Failed to read version from " .. self.version_url)
            self:Debug("Mupdate:registerEventHandlers() [" .. self.package_name .. "] - Failed to read version from " .. self.version_url)
            self:Done()
        else
            self:Debug("Mupdate:registerEventHandlers() [" .. self.package_name .. "] - Ignored error response for URL: " .. url)
        end
    end)
end

function Mupdate:validate_event_url(url)
    local parsed_url = parse_url(url)
    if self.param_key and parsed_url.params[self.param_key] then
        return parsed_url.params[self.param_key] == self.package_name
    else
        return parsed_url.file == self.remote_version_file
    end
end

function Mupdate:unregisterEventHandlers()
    local downloadHandlerLabel = generateEventName("DownloadDone", self.package_name)
    local downloadErrorHandlerLabel = generateEventName("DownloadError", self.package_name)
    local httpHandlerLabel = generateEventName("HTTPDone", self.package_name)
    local httpErrorHandlerLabel = generateEventName("HTTPError", self.package_name)

    deleteNamedEventHandler(self.package_name, downloadHandlerLabel)
    deleteNamedEventHandler(self.package_name, downloadErrorHandlerLabel)
    deleteNamedEventHandler(self.package_name, httpHandlerLabel)
    deleteNamedEventHandler(self.package_name, httpErrorHandlerLabel)
end

function Mupdate:update_package()
    lfs.mkdir(self.temp_file_path)

    downloadFile(
        self.temp_file_path .. self.package_name .. ".mpackage",
        self.package_url
    )
end

function Mupdate:update_scripts()
    self:Debug("Mupdate:update_scripts() - Starting script update check")
    self:get_version_check()
end

function Mupdate:finish_download(event, path)
    self:Debug("Mupdate:finish_download() - Finished downloading: " .. path)
    self:Debug("Mupdate:finish_download() - Checking if downloaded file is version info file")
    self:Debug("Mupdate:finish_download() - " .. path)

    if string.find(path, ".mpackage") then
        self:Debug("Mupdate:finish_download() - Downloaded file is mpackage, proceeding to load package mpackage")
        self:load_package_mpackage(path)
    end
end

function Mupdate:fail_download(event, err, localfile, actualurl)
    self:Error("Failed downloading " .. err)
    self:Debug("Mupdate:fail_download() - " .. err)
    self:Done()
end

function Mupdate:load_package_mpackage(path)
    self:Debug("Mupdate:load_package_mpackage() - Loading package mpackage from: " .. path)
    self:uninstallAndInstall(path)
end

function Mupdate:uninstallAndInstall(path)
    self:Debug("Mupdate:uninstallAndInstall() - Uninstalling and installing: " .. path)
    self:UninstallPackage()
    tempTimer(1, function()
        installPackage(path)
        os.remove(path)
        lfs.rmdir(self.temp_file_path)
        self:Done()
    end)
end

function Mupdate:UninstallPackage()
    self:Debug("Mupdate:UninstallPackage() - Uninstalling package: " .. self.package_name)
    uninstallPackage(self.package_name)
    _G[self.package_name] = nil
end

function Mupdate:get_version_check()
    self:Info("Checking for updates for " .. self.package_name)
    getHTTP(self.version_url)
end

function Mupdate:check_versions(version)
    local curr_version = self.current_version

    self:Debug("Mupdate:check_versions() - Installed version: " .. curr_version .. ", Remote version: " .. version)

    if self:compare_versions(curr_version, version) then
        self:Info("Attempting to update " .. self.package_name .. " to v" .. version)
        self:Debug("Mupdate:check_versions() - Remote version is newer, proceeding to update package")
        self:update_package()
    else
        self:Info("No updates available for " .. self.package_name)
        self:Debug("Mupdate:check_versions() - Installed version is up-to-date")
        self:Done()
    end
end

function Mupdate:semantic_version_splitter(_version_string)
    local t = {}
    for k in string.gmatch(_version_string, "([^.]+)") do
        table.insert(t, tonumber(k))
    end
    self:Debug("Mupdate:semantic_version_splitter() - Split version string: " .. _version_string .. " -> " .. table.concat(t, ", "))
    return t
end

function Mupdate:compare_versions(_installed, _remote)
    local current = self:semantic_version_splitter(_installed)
    local remote = self:semantic_version_splitter(_remote)
    self:Debug("Mupdate:compare_versions() - Comparing versions, Installed: " .. table.concat(current, ".") .. ", Remote: " .. table.concat(remote, "."))

    if current[1] < remote[1] then
        self:Debug("Mupdate:compare_versions() - Remote version is newer")
        return true
    elseif current[1] == remote[1] then
        if current[2] < remote[2] then
            self:Debug("Mupdate:compare_versions() - Remote version is newer")
            return true
        elseif current[2] == remote[2] then
            if current[3] < remote[3] then
                self:Debug("Mupdate:compare_versions() - Remote version is newer")
                return true
            end
        end
    end
    self:Debug("Mupdate:compare_versions() - Installed version is up-to-date")
    return false
end

function Mupdate:Cleanup()
    self:Debug("Mupdate:Cleanup() - Cleaning up")

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

function Mupdate:Done()
    self:Debug("Mupdate:Done() - Auto-updater finished")
    self:unregisterEventHandlers()
    if self.callback and type(self.callback) == "function" then
        pcall(self.callback)
    end
end

return Mupdate
