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
    param_regex = nil,
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

local function parse_url(url)
    local protocol, host, file, query_string = string.match(url, "^(https?)://([^/]+)/(.-)%??(.*)")
    local params = parse_url_params(query_string)
    local parsed = {
        protocol = protocol,
        host = host,
        file = file,
        params = params
    }
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
    local downloadHandlerLabel = generateEventName("DownloadDone", self.package_name)
    local downloadErrorHandlerLabel = generateEventName("DownloadError", self.package_name)
    local httpHandlerLabel = generateEventName("HTTPDone", self.package_name)
    local httpErrorHandlerLabel = generateEventName("HTTPError", self.package_name)

    registerNamedEventHandler(self.package_name, downloadHandlerLabel, "sysDownloadDone", function(event, path , size, response)
        -- Compare the downloaded file path with the expected file path
        if path == self.temp_file_path .. self.package_name .. ".mpackage" then
            self:finish_download(event, path)
        else
            self:Debug("Mupdate:sysDownloadDone() - Downloaded file path does not match the expected path")
            self:Debug("Expected: " .. self.temp_file_path .. self.package_name .. ".mpackage" .. ", Got: " .. path)
            self:Done()
        end
    end)

    registerNamedEventHandler(self.package_name, downloadErrorHandlerLabel, "sysDownloadError", function(event, err, localfile, actualurl)
        -- Compare the error file path with the expected file path
        if localfile == self.temp_file_path .. self.package_name .. ".mpackage" then
            self:fail_download(event, err, localfile, actualurl)
        else
            self:Debug("Mupdate:sysDownloadError() - Error file path does not match the expected path")
            self:Debug("Expected: " .. self.temp_file_path .. self.package_name .. ".mpackage" .. ", Got: " .. localfile)
            self:Done()
        end
    end)

    registerNamedEventHandler(self.package_name, httpHandlerLabel, "sysGetHttpDone", function(event, url, response)
        local parsed_url = parse_url(url)
        local expected_file = self.package_name .. "_version.txt"

        if self.param_key and parsed_url.params[self.param_key] then
            if self.param_regex then
                local matched = parsed_url.params[self.param_key]:match(self.param_regex)
                if matched == expected_file then
                    self:Debug("Mupdate:get_version_check() - Param regex matches: " .. parsed_url.params[self.param_key])
                    self:check_versions(response)
                else
                    self:Debug("Mupdate:get_version_check() - Param regex does not match: " .. parsed_url.params[self.param_key])
                    self:Debug("Expected: " .. expected_file .. ", Got: " .. matched)
                end
            else
                if parsed_url.params[self.param_key] == expected_file then
                    self:Debug("Mupdate:get_version_check() - Param matches: " .. parsed_url.params[self.param_key])
                    self:check_versions(response)
                else
                    self:Debug("Mupdate:get_version_check() - Param does not match: " .. parsed_url.params[self.param_key])
                    self:Debug("Expected: " .. expected_file .. ", Got: " .. parsed_url.params[self.param_key])
                end
            end
        elseif not self.param_key and string.find(parsed_url.file, expected_file) then
            self:Debug("Mupdate:get_version_check() - File matches: " .. parsed_url.file)
            self:check_versions(response)
        else
            self:Debug("Mupdate:get_version_check() - URL does not contain the expected parameter or file, ignoring")
            self:Debug("Parsed file: " .. parsed_url.file)
            if self.param_key then
                self:Debug("Parsed param: " .. (parsed_url.params[self.param_key] or "nil"))
            end
        end
    end)

    registerNamedEventHandler(self.package_name, httpErrorHandlerLabel, "sysGetHttpError", function(event, response, url)
        local parsed_url = parse_url(url)
        local expected_file = self.package_name .. "_version.txt"

        if self.param_key and parsed_url.params[self.param_key] then
            if self.param_regex then
                local matched = parsed_url.params[self.param_key]:match(self.param_regex)
                if matched == expected_file then
                    self:Error("Failed to read version from " .. self.version_url)
                    self:Debug("Mupdate:get_version_check() - Param regex matches but failed to read version")
                else
                    self:Debug("Mupdate:get_version_check() - Param regex does not match: " .. parsed_url.params[self.param_key])
                    self:Debug("Expected: " .. expected_file .. ", Got: " .. matched)
                end
            else
                if parsed_url.params[self.param_key] == expected_file then
                    self:Error("Failed to read version from " .. self.version_url)
                    self:Debug("Mupdate:get_version_check() - Param matches but failed to read version")
                else
                    self:Debug("Mupdate:get_version_check() - Param does not match: " .. parsed_url.params[self.param_key])
                    self:Debug("Expected: " .. expected_file .. ", Got: " .. parsed_url.params[self.param_key])
                end
            end
        elseif not self.param_key and string.find(parsed_url.file, expected_file) then
            self:Error("Failed to read version from " .. self.version_url)
            self:Debug("Mupdate:get_version_check() - File matches but failed to read version")
        else
            self:Debug("Mupdate:get_version_check() - URL does not contain the expected parameter or file, ignoring")
            self:Debug("Parsed file: " .. parsed_url.file)
            if self.param_key then
                self:Debug("Parsed param: " .. (parsed_url.params[self.param_key] or "nil"))
            end
        end
        self:Done()
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

    local parsed_url = parse_url(path)

    if not self.param_key then
        -- No params, check if file name matches
        if parsed_url.file == self.remote_version_file then
            self:Debug("Mupdate:finish_download() - File name matches: " .. parsed_url.file)
            self:load_package_mpackage(path)
        else
            self:Debug("Mupdate:finish_download() - File name does not match: " .. parsed_url.file)
            self:Debug("Expected: " .. self.remote_version_file .. ", Got: " .. parsed_url.file)
            self:Done()
        end
    else
        -- Params exist, check according to param_key and param_regex
        local param_value = parsed_url.params[self.param_key]
        if self.param_regex then
            -- Use regex to extract and match
            local matched = param_value:match(self.param_regex)
            if matched == self.remote_version_file then
                self:Debug("Mupdate:finish_download() - Param regex matches: " .. param_value)
                self:load_package_mpackage(path)
            else
                self:Debug("Mupdate:finish_download() - Param regex does not match: " .. param_value)
                self:Debug("Expected: " .. self.remote_version_file .. ", Got: " .. matched)
                self:Done()
            end
        else
            -- Exact match
            if param_value == self.remote_version_file then
                self:Debug("Mupdate:finish_download() - Param matches: " .. param_value)
                self:load_package_mpackage(path)
            else
                self:Debug("Mupdate:finish_download() - Param does not match: " .. param_value)
                self:Debug("Expected: " .. self.remote_version_file .. ", Got: " .. param_value)
                self:Done()
            end
        end
    end
end

function Mupdate:fail_download(event, err, localfile, actualurl)
    self:Error("Failed downloading " .. err)
    self:Debug("Mupdate:fail_download() - " .. err)

    local parsed_url = parse_url(actualurl)

    if not self.param_key then
        -- No params, check if file name matches
        if parsed_url.file == self.remote_version_file then
            self:Debug("Mupdate:fail_download() - File name matches: " .. parsed_url.file)
        else
            self:Debug("Mupdate:fail_download() - File name does not match: " .. parsed_url.file)
            self:Debug("Expected: " .. self.remote_version_file .. ", Got: " .. parsed_url.file)
        end
    else
        -- Params exist, check according to param_key and param_regex
        local param_value = parsed_url.params[self.param_key]
        if self.param_regex then
            -- Use regex to extract and match
            local matched = param_value:match(self.param_regex)
            if matched == self.remote_version_file then
                self:Debug("Mupdate:fail_download() - Param regex matches: " .. param_value)
            else
                self:Debug("Mupdate:fail_download() - Param regex does not match: " .. param_value)
                self:Debug("Expected: " .. self.remote_version_file .. ", Got: " .. matched)
            end
        else
            -- Exact match
            if param_value == self.remote_version_file then
                self:Debug("Mupdate:fail_download() - Param matches: " .. param_value)
            else
                self:Debug("Mupdate:fail_download() - Param does not match: " .. param_value)
                self:Debug("Expected: " .. self.remote_version_file .. ", Got: " .. param_value)
            end
        end
    end

    self:Done()
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
