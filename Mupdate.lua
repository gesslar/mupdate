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

Mupdate = Mupdate or {
    download_path = nil,
    package_name = nil,
    package_url = nil,
    version_check_download = nil,
    version_url = nil,
    file_path = nil,
    version_check_save = nil,
    initialized = false,
    downloading = false,
    download_queue = {}, -- Ensure this is here in case the initialization function is missed
    debug_mode = false -- Add a flag for debugging mode
}

function Mupdate:Debug(text)
    if self.debug_mode then
        debugc(text)
    end
end

function Mupdate:new(options)
    options = options or {}
    local me = table.deepcopy(options)
    setmetatable(me, self)
    self.__index = self

    -- Test to see if any of the required fields are nil and error if so
    for k, v in pairs(me) do
        if v == nil then
            error("Mupdate:new() - Required field " .. k .. " is nil")
        end
    end

    -- Now that we know we have all the required fields, we can setup the fields
    -- that are derived from the required fields
    me.file_path = getMudletHomeDir() .. "/" .. me.package_name .. "/"
    me.temp_file_path = getMudletHomeDir() .. "/" .. me.package_name .. "_temp" .. "/"
    me.package_url = me.download_path .. me.package_name .. ".mpackage"
    me.version_url = me.download_path .. me.version_check_download
    me.version_check_save = me.version_check_save

    local packageInfo = getPackageInfo(me.package_name)
    if not packageInfo then
        error("Mupdate:new() - Package " .. me.package_name .. " not found")
    end
    if not packageInfo.version then
        error("Mupdate:new() - Package " .. me.package_name .. " does not have a version")
    end

    me.current_version = packageInfo.version
    me:Debug("Mupdate:new() - Current version: " .. me.current_version)

    me.initialized = true
    me.downloading = false
    me.download_queue = {} -- Ensure download_queue is initialized as an empty table
    me:Debug("Mupdate:new() - Initialized download_queue")

    registerNamedEventHandler(me.package_name, "DownloadComplete", "sysDownloadDone", function(...)
        me:eventHandler("sysDownloadDone", ...)
    end)
    registerNamedEventHandler(me.package_name, "DownloadError", "sysDownloadError", function(...)
        me:eventHandler("sysDownloadError", ...)
    end)

    return me
end

function Mupdate:Start()
    self:Debug("Mupdate:Start() - Auto-updater started")

    if not self.initialized then
        error("Mupdate:Start() - Mupdate object not initialized")
    end

    self:update_scripts()
end

function Mupdate:fileOpen(filename, mode)
    mode = mode or "read"
    assert(table.contains({ "read", "write", "append", "modify" }, mode), "Invalid mode: must be 'read', 'write', 'append', or 'modify'.")

    if mode ~= "write" then
        local info = lfs.attributes(filename)
        if not info or info.mode ~= "file" then
            return nil, "Invalid filename: " .. (info and "path points to a directory." or "no such file.")
        end
    end

    local file = { name = filename, mode = mode, type = "fileIO_file", contents = {} }
    if mode == "read" or mode == "modify" then
        local tmp, err = io.open(filename, "r")
        if not tmp then
            return nil, err
        end
        for line in tmp:lines() do
            table.insert(file.contents, line)
        end
        tmp:close()
    end

    self:Debug("Mupdate:fileOpen() - Opened file: " .. filename .. " in mode: " .. mode)
    return file, nil
end

function Mupdate:fileClose(file)
    assert(file.type == "fileIO_file", "Invalid file: must be file returned by fileIO.open.")
    local tmp
    if file.mode == "write" then
        tmp = io.open(file.name, "w")
    elseif file.mode == "append" then
        tmp = io.open(file.name, "a")
    elseif file.mode == "modify" then
        tmp = io.open(file.name, "w+")
    end
    if tmp then
        for k, v in ipairs(file.contents) do
            tmp:write(v .. "\n")
        end
        tmp:flush()
        tmp:close()
        tmp = nil
    end
    self:Debug("Mupdate:fileClose() - Closed file: " .. file.name)
    return true
end

function Mupdate:UninstallPackage()
    self:Debug("Mupdate:UninstallPackage() - Uninstalling package: " .. self.package_name)
    uninstallPackage(self.package_name)
    _G[self.package_name] = nil
end

function Mupdate:uninstallAndInstall(path)
    self:Debug("Mupdate:uninstallAndInstall() - Uninstalling and installing: " .. path)
    self:UninstallPackage()
    tempTimer(1, function()
        installPackage(path)
        os.remove(path)
        lfs.rmdir(self.temp_file_path)
    end)
end

function Mupdate:update_the_package()
    local download_here = self.package_url
    self:Debug("Mupdate:update_the_package() - Uninstalling old package and installing new from: " .. download_here)
    self:UninstallPackage()
    tempTimer(2, function() installPackage(download_here) end)
end

function Mupdate:load_package_xml(path)
    self:Debug("Mupdate:load_package_xml() - Loading package XML from: " .. path)
    if path ~= self.temp_file_path .. self.package_name .. ".xml" then return end
    self:uninstallAndInstall(path)
end

function Mupdate:load_package_mpackage(path)
    self:Debug("Mupdate:load_package_mpackage() - Loading package mpackage from: " .. path)
    self:uninstallAndInstall(path)
end

function Mupdate:start_next_download()
    self:Debug("Mupdate:start_next_download() - Checking download_queue")
    local info = self.download_queue[1]
    if not info then
        self.downloading = false
        self:Debug("Mupdate:start_next_download() - No more items in download_queue")
        return
    end

    -- Remove the current item from the queue
    table.remove(self.download_queue, 1)
    self:Debug("Mupdate:start_next_download() - Removed item from download_queue, new size: " .. #self.download_queue)

    -- Start the download
    downloadFile(info[1], info[2])
    self.downloading = true
end

function Mupdate:queue_download(path, address)
    -- Add the download request to the queue
    self:Debug("Mupdate:queue_download() - Adding to download_queue: " .. address .. " -> " .. path)
    table.insert(self.download_queue, { path, address })
    self:Debug("Mupdate:queue_download() - Current queue size: " .. #self.download_queue)

    -- Start the download if not already in progress
    if not self.downloading then
        self:start_next_download()
    end
end

function Mupdate:finish_download(_, path)
    self:Debug("Mupdate:finish_download() - Finished downloading: " .. path)
    self:start_next_download()
    self:Debug("Mupdate:finish_download() - Checking if downloaded file is version info file")
    self:Debug("Mupdate:finish_download() - " .. path)

    -- Check if the downloaded file is the version info file
    if string.find(path, self.version_check_save) then
        self:Debug("Mupdate:finish_download() - Downloaded file is version info file, proceeding to check versions")
        self:check_versions()
    elseif string.find(path, ".mpackage") then
        self:Debug("Mupdate:finish_download() - Downloaded file is mpackage, proceeding to load package mpackage")
        self:load_package_mpackage(path)
    elseif string.find(path, ".xml") then
        self:Debug("Mupdate:finish_download() - Downloaded file is XML, proceeding to load package XML")
        self:load_package_xml(path)
    end
end

function Mupdate:fail_download(...)
    cecho("\n<b><ansiLightRed>ERROR</b><reset> - failed downloading " .. arg[2] .. arg[1] .. "\n")
    self:Debug("Mupdate:fail_download() - Failed to download: " .. arg[2] .. arg[1])
    self:start_next_download()
end

function Mupdate:update_package()
    lfs.mkdir(self.temp_file_path)
    self:Debug("Mupdate:update_package() - Queuing download for package update")
    self:queue_download(
        self.temp_file_path .. self.package_name .. ".mpackage",
        self.download_path .. self.package_name .. ".mpackage"
    )
end

function Mupdate:update_scripts()
    self:Debug("Mupdate:update_scripts() - Starting script update check")
    self:get_version_check()
end

function Mupdate:eventHandler(event, ...)
    -- self:Debug("Mupdate:eventHandler() - Event: " .. event .. ", Args: " .. table.concat({...}, ", "))
    if event == "sysDownloadDone" then
        self:finish_download(...)
    elseif event == "sysDownloadError" then
        self:fail_download(...)
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

function Mupdate:get_version_check()
    lfs.mkdir(self.file_path)
    self:Debug("Mupdate:get_version_check() - Getting version check file")
    self:Debug("Mupdate:get_version_check() - " .. self.version_url)
    self:Debug("Mupdate:get_version_check() - " .. self.file_path .. self.version_check_save)

    -- Ensure the version file is saved in the correct directory
    self:queue_download(
        self.file_path .. self.version_check_save, -- Local path to save the file
        self.version_url                           -- Remote URL to download from
    )
end

function Mupdate:check_versions()
    local dl_path = self.file_path .. self.version_check_save
    self:Debug("Mupdate:check_versions() - Checking versions with file: " .. dl_path)
    local dl_file, dl_errors = self:fileOpen(dl_path, "read")
    if not dl_file then
        cecho("\n<b><ansiLightRed>ERROR</b><reset> - Could not read remote version info file, aborting auto-update routine. (" .. dl_errors .. ")\n")
        self:Debug("Mupdate:check_versions() - Could not read remote version info file: " .. dl_errors)
        return
    end

    local curr_version = self.current_version
    local dl_version = dl_file.contents[1]

    self:Debug("Mupdate:check_versions() - Installed version: " .. curr_version .. ", Remote version: " .. dl_version)

    self:fileClose(dl_file)
    os.remove(dl_path)

    if self:compare_versions(curr_version, dl_version) then
        cecho(f"<b><ansiLightYellow>INFO</b><reset> - Attempting to update {self.package_name} to v{dl_version}\n")
        self:Debug("Mupdate:check_versions() - Remote version is newer, proceeding to update package")
        self:update_package()
    else
        self:Debug("Mupdate:check_versions() - Installed version is up-to-date")
    end
end
