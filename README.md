# Mupdate Auto-Updater Module

## Description
This module provides an auto-updater for packages within the MUD client, Mudlet. It automates the process of checking for new versions of a package, downloading updates, and installing them.

## Acknowledgements
This module was heavily inspired by the MUDKIP_Mud2 package from @11BelowStudio, available at:
[https://github.com/11BelowStudio/MUDKIP_Mud2](https://github.com/11BelowStudio/MUDKIP_Mud2)

The core functionality of this auto-updater was adapted from the DSL PNP 4.0 Main Script by Zachary Hiland, originally shared on the Mudlet forums:
[https://forums.mudlet.org/viewtopic.php?p=20504](https://forums.mudlet.org/viewtopic.php?p=20504)

Special thanks to @demonnic for providing additional Lua code and guidance on package installation.

## Instructions for Use

### 1. Placement
- **Using Muddler:** Put the `Mupdate.lua` file in your project's resources directory.
- **Developing Directly in Mudlet:** Add the `Mupdate.lua` file to your Mudlet package's Script Group within Mudlet, and ensure that it is higher than the script that will be calling it.

### 2. Integration
In your package script, require the Mupdate module and instantiate it with the necessary options.

#### Example Implementation:
```lua
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
```

### Variables:
* `download_path`: The URL path where the package files are hosted.
* `package_name`: The name of your package.
* `version_check_download`: The file name of the version check file on the server.
* `version_check_save`: The file name to save the downloaded version check file locally.
* `debug_mode`: Boolean flag to enable or disable debug mode for detailed logging.
