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

    Original acknowledgements from the MUDKIP_Mud2 package:
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
    - remote_version_file: The file name of the version check file on the server.
    - param_key: (Optional) The key of the URL parameter to check for the file name.
    - param_regex: (Optional) The regex pattern to extract the file name from the URL parameter value.
    - debug_mode: Boolean flag to enable or disable debug mode for detailed logging.

       Example implementation:

       -- Auto Updater
       function ThreshCopy:Loaded()
           -- If using muddler
           -- local Mupdate = require("ThreshCopy\\Mupdate")
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
    - Mupdate calls `getPackageInfo(packageName)` to get your package's version number.
      Which must be in the SemVer format. So, this must be set on your package.
    - Mupdate downloads the version file from the same location that hosts your `.mpackage`
      file, and its contents must simply contain the updated version in the SemVer format.

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
    param_regex = nil,
    initialized = false,
    debug_mode = false,
}

local function generateEventName(base, packageName, profile)
    return base .. "_" .. packageName .. "_" .. profile
end

function Mupdate:Debug(text)
    if self.debug_mode then
        debugc("[" .. (self.package_name or "Mupdate") .. "] " .. text)
    end
end

function Mupdate:Error(text)
    cecho(f"<red>[ ERROR ]<reset> <DarkOrange>{(self.package_name or \"Mupdate\")}<reset> - {text}\n")
end

function Mupdate:Info(text)
    cecho(f"<gold>[ INFO ]<reset> <DarkOrange>{(self.package_name or \"Mupdate\")}<reset> - {text}\n")

end

local function is_valid_regex(pattern)
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
            error("Mupdate:new() [" .. (options.package_name or "Unknown") .. "] - Required field " .. k .. " is not of type " .. v)
        end
    end

    if options.param_regex then
        local valid, reason = is_valid_regex(options.param_regex)
        if not valid then
            error("Mupdate:new() [" .. (options.package_name or "Unknown") .. "] - Invalid regex pattern: " .. reason)
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
    if(self:running()) then
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

    self.in_progress = true

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

local function parse_url(url)
    local protocol, host, file, query_string = string.match(url, "^(https?)://([^/]+)/(.-)%??(.*)")
    local params = parse_url_params(query_string)
    local parsed = {
        protocol = protocol,
        host = host,
        file = file,
        params = params
    }

-- Uncomment the below if you also want to see the debugging output
-- for the parsed URL
--[[
    -- Debugging output
    debugc("Parsed URL:")
    debugc("  Protocol: " .. (parsed.protocol or "nil"))
    debugc("  Host: " .. (parsed.host or "nil"))
    debugc("  File: " .. (parsed.file or "nil"))
    for key, value in pairs(parsed.params) do
        debugc("  Param: " .. key .. " = " .. value)
    end
]] --

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
        registerNamedEventHandler(self.package_name, newEvents["sysDownloadDone"], "sysDownloadDone", function(event, path, size, response)
            if not self.in_progress then return end
            self:handleDownloadDone(event, path, size, response)
        end)
    end

    if newEvents["sysDownloadError"] then
        registerNamedEventHandler(self.package_name, newEvents["sysDownloadError"], "sysDownloadError", function(event, err, path, actualurl)
            if not self.in_progress then return end
            self:handleDownloadError(event, err, path, actualurl)
        end)
    end

    if newEvents["sysGetHttpDone"] then
        registerNamedEventHandler(self.package_name, newEvents["sysGetHttpDone"], "sysGetHttpDone", function(event, url, response)
            if not self.in_progress then return end
            self:handleHttpGet(event, url, response)
        end)
    end

    if newEvents["sysGetHttpError"] then
        registerNamedEventHandler(self.package_name, newEvents["sysGetHttpError"], "sysGetHttpError", function(event, response, url)
            if not self.in_progress then return end
            self:handleHttpError(event, response, url)
        end)
    end
end

function Mupdate:finish_httpget(event, url, response)
    local parsed_url = parse_url(url)
    local expected_file = self.package_name .. "_version.txt"

    if self.param_key and parsed_url.params[self.param_key] then
        if self.param_regex then
            local matched = parsed_url.params[self.param_key]:match(self.param_regex)
            if matched == expected_file then
                self:Debug("Mupdate:sysGetHttpDone - Param regex matches: " .. parsed_url.params[self.param_key])
                self:check_versions(response)
            else
                self:Debug("Mupdate:sysGetHttpDone - Param regex does not match: " .. parsed_url.params[self.param_key])
                self:Debug("Expected: " .. expected_file .. ", Got: " .. matched)
            end
        else
            if parsed_url.params[self.param_key] == expected_file then
                self:Debug("Mupdate:sysGetHttpDone - Param matches: " .. parsed_url.params[self.param_key])
                self:check_versions(response)
            else
                self:Debug("Mupdate:sysGetHttpDone - Param does not match: " .. parsed_url.params[self.param_key])
                self:Debug("Expected: " .. expected_file .. ", Got: " .. parsed_url.params[self.param_key])
            end
        end
    elseif not self.param_key and string.find(parsed_url.file, expected_file) then
        self:Debug("Mupdate:sysGetHttpDone - File name matches: " .. parsed_url.file)
        self:check_versions(response)
    else
        self:Debug("Mupdate:sysGetHttpDone - URL does not contain the expected parameter or file, ignoring")
        self:Debug("Parsed file: " .. parsed_url.file)
        if self.param_key then
            self:Debug("Parsed param: " .. (parsed_url.params[self.param_key] or "nil"))
        end
    end
end

function Mupdate:fail_httpget(event, response, url)
    local parsed_url = parse_url(url)
    local expected_file = self.package_name .. "_version.txt"

    if self.param_key and parsed_url.params[self.param_key] then
        if self.param_regex then
            local matched = parsed_url.params[self.param_key]:match(self.param_regex)
            if matched == expected_file then
                self:Error("Failed to read version from " .. self.version_url)
                self:Debug("Mupdate:sysGetHttpError - Param regex matches but failed to read version")
            else
                self:Debug("Mupdate:sysGetHttpError - Param regex does not match: " .. parsed_url.params[self.param_key])
                self:Debug("Expected: " .. expected_file .. ", Got: " .. matched)
            end
        else
            if parsed_url.params[self.param_key] == expected_file then
                self:Error("Failed to read version from " .. self.version_url)
                self:Debug("Mupdate:sysGetHttpError - Param matches but failed to read version")
            else
                self:Debug("Mupdate:sysGetHttpError - Param does not match: " .. parsed_url.params[self.param_key])
                self:Debug("Expected: " .. expected_file .. ", Got: " .. parsed_url.params[self.param_key])
            end
        end
    elseif not self.param_key and string.find(parsed_url.file, expected_file) then
        self:Error("Failed to read version from " .. self.version_url)
        self:Debug("Mupdate:sysGetHttpError - File matches but failed to read version")
    else
        self:Debug("Mupdate:sysGetHttpError - URL does not contain the expected parameter or file, ignoring")
        self:Debug("Parsed file: " .. parsed_url.file)
        if self.param_key then
            self:Debug("Parsed param: " .. (parsed_url.params[self.param_key] or "nil"))
        end
    end
end

function Mupdate:handleDownloadDone(event, path, size, response)
    -- Compare the downloaded file path with the expected file path
    if path ~= self.temp_file_path .. self.package_name .. ".mpackage" then
        return
    end

    self:Debug("Mupdate:sysDownloadDone() - Downloaded path = " .. path)
    self:finish_download(path)
end

function Mupdate:handleDownloadError(event, err, path, actualurl)
    -- Compare the downloaded file path with the expected file path
    if path ~= self.temp_file_path .. self.package_name .. ".mpackage" then
        return
    end

    self:Debug("Mupdate:sysDownloadError() - Error downloading: " .. err)
    self:fail_download(err, path, actualurl)
end

function Mupdate:handleHttpGet(event, url, response)
    self:finish_httpget(event, url, response)
end

function Mupdate:handleHttpError(event, response, url)
    self:fail_httpget(event, response, url)
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
    local downloadHandlerLabel = generateEventName("DownloadDone", self.package_name, self.profile)
    local downloadErrorHandlerLabel = generateEventName("DownloadError", self.package_name, self.profile)
    local httpHandlerLabel = generateEventName("HTTPDone", self.package_name, self.profile)
    local httpErrorHandlerLabel = generateEventName("HTTPError", self.package_name, self.profile)

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

function Mupdate:finish_download(path)
    self:Debug("Mupdate:finish_download() - Finished downloading: " .. path)
    self:load_package_mpackage(path)
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
        self:Info("Package updated successfully on " .. self.profile)
    end)
end

function Mupdate:fail_download(err, localfile, actualurl)
    self:Error("Failed downloading " .. err)
    self:Debug("Mupdate:fail_download() - " .. err)

    local parsed_url = parse_url(actualurl)

    if not self.param_key then
        -- No params, check if file name matches
        if parsed_url.file == self.package_name .. ".mpackage" then
            self:Debug("Mupdate:fail_download() - File name matches: " .. parsed_url.file)
        else
            self:Debug("Mupdate:fail_download() - File name does not match: " .. parsed_url.file)
            self:Debug("Expected: " .. self.package_name .. ".mpackage, Got: " .. parsed_url.file)
        end
    else
        -- Params exist, check according to param_key and param_regex
        local param_value = parsed_url.params[self.param_key]
        if self.param_regex then
            -- Use regex to extract and match
            local matched = param_value:match(self.param_regex)
            if matched == self.package_name .. ".mpackage" then
                self:Debug("Mupdate:fail_download() - Param regex matches: " .. param_value)
            else
                self:Debug("Mupdate:fail_download() - Param regex does not match: " .. param_value)
                self:Debug("Expected: " .. self.package_name .. ".mpackage, Got: " .. matched)
            end
        else
            -- Exact match
            if param_value == self.package_name .. ".mpackage" then
                self:Debug("Mupdate:fail_download() - Param matches: " .. param_value)
            else
                self:Debug("Mupdate:fail_download() - Param does not match: " .. param_value)
                self:Debug("Expected: " .. self.package_name .. ".mpackage, Got: " .. param_value)
            end
        end
    end
end

function Mupdate:UninstallPackage()
    self:Debug("Mupdate:UninstallPackage() - Uninstalling package: " .. self.package_name)
    uninstallPackage(self.package_name)
    _G[self.package_name] = nil
end

function Mupdate:get_version_check()
    -- self:Info("Checking for updates for " .. self.package_name .. " on " .. self.profile)
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
        -- self:Info("No updates available for " .. self.package_name)
        self:Debug("Mupdate:check_versions() - Installed version is up-to-date")
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

    self.in_progress = false

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
