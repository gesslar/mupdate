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
    mupdate_url: The URL to download the latest version of Mupdate
    payload: A table of settings for Mupdate
        download_path: The URL to download the latest version of the package
        package_name: The name of the package
        remote_version_file: The name of the file that contains the version
        param_key: (optional) The key to look for in the headers
        param_regex: (optional) The regex to use to extract the filename from the headers
        debug_mode: (optional) Whether to print debug messages

Written by Gesslar@ThresholdRPG 2024-06-24

]]--

__PKGNAME__ = __PKGNAME__ or {}
__PKGNAME__.Mupdate = __PKGNAME__.Mupdate or {
    -- System information
    tag = "__PKGNAME__.AutoMupdate",
    local_path = getMudletHomeDir() .. "/__PKGNAME__/Mupdate.lua",
    function_name = "__PKGNAME__:AutoMupdate",
    handler_events = {
        sysDownloadDone = "__PKGNAME__.AutoMupdate.DownloadDone",
        sysDownloadError = "__PKGNAME__.AutoMupdate.DownloadError"
    },
    -- Customizable settings
    mupdate_url = "https://github.com/gesslar/Mupdate/releases/latest/download/Mupdate.lua",
    payload = {
        download_path = "https://github.com/gesslar/__PKGNAME__/releases/latest/download/",
        package_name = "__PKGNAME__",
        remote_version_file = "__PKGNAME___version.txt",
        param_key = "response-content-disposition",
        param_regex = "attachment; filename=(.*)",
        debug_mode = true
    }
}

function __PKGNAME__.Mupdate:AutoMupdate(handle, path)
    debugc("AutoMupdate - Package Name: __PKGNAME__, Handle: " .. handle)
    if handle ~= self.tag then return end

    registerNamedTimer(self.tag, self.tag, 2, function()
        deleteAllNamedTimers(self.tag)
        self.MupdateScript = require("__PKGNAME__\\Mupdate")
        self.Mupdater = self.MupdateScript:new(self.payload)
        self.Mupdater:Start()
    end)
end

function __PKGNAME__.Mupdate:RegisterMupdateEventHandlers()
    local existingHandlers = getNamedEventHandlers(self.tag) or {}
    local newEvents = {}
        for event, label in pairs(self.handler_events) do
        if not existingHandlers[label] then
            newEvents[event] = label
        end
    end

    if newEvents["sysDownloadDone"] then
        registerNamedEventHandler(
            self.tag,
            newEvents["sysDownloadDone"],
            "sysDownloadDone",
            function(event, path, size, response)
                if path ~= self.local_path then return end
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
                if path ~= self.local_path then return end
                self:UnregisterMupdateEventHandlers()
            end
        )
    end
end

function __PKGNAME__.Mupdate:UnregisterMupdateEventHandlers()
    local existingHandlers = getNamedEventHandlers(self.tag) or {}
    for _, label in pairs(self.handler_events) do
        local result = deleteNamedEventHandler(self.tag, label)
    end
end

function __PKGNAME__.update()
    local version = getPackageInfo("__PKGNAME__", "version")
    cecho(f"<chocolate>[[ __PKGNAME__ ]]<reset> Initiating manual update to currently installed version "..version..".\n")
    cecho(f"<chocolate>[[ __PKGNAME__ ]]<reset> If there is a new version, it will be downloaded and installed.\n")
    cecho(f"<chocolate>[[ __PKGNAME__ ]]<reset> Full logging of update activity may be found in <u>Scripts</u> > <u>Errors</u>\n")

    __PKGNAME__.Mupdate:downloadLatestMupdate()
end

function __PKGNAME__.Mupdate:downloadLatestMupdate()
    local success, err = pcall(os.remove, self.local_path)

    -- Register the download event handlers
    self:RegisterMupdateEventHandlers()

    -- Initiate download
    downloadFile(self.local_path, self.mupdate_url)
end

-- Start it up
__PKGNAME__.Mupdate.MupdateLoadHandler = __PKGNAME__.MupdateLoadHandler or
    registerNamedEventHandler(
        __PKGNAME__.Mupdate.tag, -- username
        __PKGNAME__.Mupdate.tag..".Load", -- handler name
        "sysLoadEvent", -- event name
        function(event) __PKGNAME__.Mupdate:downloadLatestMupdate() end
    )
