local H = dofile(debug.getinfo(1, "S").source:match("^@(.*/)") .. "support/harness.lua")

local PKG = "UpdTest"
local TAG = PKG .. ".AutoMupdate"
local MODULE = PKG .. "/Mupdate"

describe("Updater.lua", function()
  local localPath
  local started

  -- Stands in for the downloaded Mupdate.lua, recording how it is used.
  local function fakeMupdate()
    started = { loads = 0, payloads = {}, starts = 0 }

    package.preload[MODULE] = function()
      started.loads = started.loads + 1

      return {
        new = function(_, payload)
          table.insert(started.payloads, payload)

          return { Start = function() started.starts = started.starts + 1 end }
        end,
      }
    end
  end

  before_each(function()
    H.setup()
    H.packages[PKG] = { version = "1.0.0" }
    _G[PKG] = nil
    package.loaded[MODULE] = nil
    localPath = getMudletHomeDir() .. "/" .. PKG .. "/Mupdate.lua"
    fakeMupdate()
    H.loadUpdater(PKG)
  end)

  after_each(function()
    package.preload[MODULE] = nil
    package.loaded[MODULE] = nil
    _G[PKG] = nil
    assert.same({}, H.teardown({ TAG, PKG }))
  end)

  local function updater()
    return _G[PKG].Mupdate
  end

  describe("when loaded", function()
    it("checks for updates every time the profile loads", function()
      assert.is_true(H.hasNamedHandler(TAG, TAG .. ".Load"))
    end)

    it("is configured for its own package once muddy fills in the name", function()
      local payload = updater().payload

      assert.equals(PKG, payload.package_name)
      assert.equals(PKG .. "_version.txt", payload.remote_version_file)
      assert.equals("https://github.com/gesslar/" .. PKG .. "/releases/latest/download/", payload.download_path)
    end)

    it("fetches Mupdate from the latest Mupdate release", function()
      assert.equals("https://github.com/gesslar/Mupdate/releases/latest/download/Mupdate.lua", updater().mupdateUrl)
    end)

    it("keeps an existing updater if the script is loaded again", function()
      local first = updater()
      H.loadUpdater(PKG)

      assert.equals(first, updater())
    end)
  end)

  describe("fetching Mupdate", function()
    it("downloads the latest Mupdate into the package directory", function()
      updater():downloadLatestMupdate()

      assert.same({ localPath, updater().mupdateUrl }, H.lastCall("downloadFile"))
    end)

    it("removes a stale copy first so the download replaces it", function()
      io.exists = function(path) return path == localPath end

      updater():downloadLatestMupdate()

      assert.same({ localPath }, H.lastCall("os.remove"))
    end)

    it("can be triggered by hand, telling the user what it is doing", function()
      _G[PKG].update()

      assert.equals(1, H.callCount("downloadFile"))
      assert.matches("1.0.0", H.output(), 1, true)
    end)
  end)

  describe("once Mupdate has downloaded", function()
    it("loads it and starts it with the package's settings, after a short delay", function()
      updater():downloadLatestMupdate()
      raiseEvent("sysDownloadDone", localPath, 2048)

      assert.equals(0, started.starts)

      H.advance(2)

      assert.equals(1, started.starts)
      assert.equals(updater().payload, started.payloads[1])
    end)

    it("loads the freshly downloaded copy rather than one cached from an earlier run", function()
      updater():downloadLatestMupdate()
      raiseEvent("sysDownloadDone", localPath, 2048)
      H.advance(2)

      updater():downloadLatestMupdate()
      raiseEvent("sysDownloadDone", localPath, 2048)
      H.advance(2)

      assert.equals(2, started.loads)
    end)

    it("ignores other downloads", function()
      updater():downloadLatestMupdate()
      raiseEvent("sysDownloadDone", getMudletHomeDir() .. "/Other/Mupdate.lua", 2048)
      H.advance(5)

      assert.equals(0, started.starts)
    end)

    it("stops listening once its download is done", function()
      updater():downloadLatestMupdate()
      raiseEvent("sysDownloadDone", localPath, 2048)
      raiseEvent("sysDownloadDone", localPath, 2048)
      H.advance(5)

      assert.equals(1, started.starts)
    end)

    it("gives up quietly if the download fails, and stops listening", function()
      updater():downloadLatestMupdate()
      raiseEvent("sysDownloadError", "Host not found", localPath, updater().mupdateUrl)
      raiseEvent("sysDownloadDone", localPath, 2048)
      H.advance(5)

      assert.equals(0, started.starts)
    end)
  end)

  describe("uninstalling the package", function()
    it("removes the updater's handlers and timers", function()
      updater():downloadLatestMupdate()
      raiseEvent("sysDownloadDone", localPath, 2048)

      raiseEvent("sysUninstall", PKG)

      assert.is_false(H.hasNamedHandler(TAG, TAG .. ".Load"))
      assert.same({}, getNamedTimers(TAG) or {})

      H.advance(5)
      assert.equals(0, started.starts)
    end)

    it("leaves the updater alone when another package is uninstalled", function()
      updater():downloadLatestMupdate()
      raiseEvent("sysDownloadDone", localPath, 2048)

      raiseEvent("sysUninstall", "OtherPkg")

      assert.is_true(H.hasNamedHandler(TAG, TAG .. ".Load"))
    end)
  end)

  describe("end to end with the real Mupdate", function()
    before_each(function()
      package.preload[MODULE] = function() return H.loadMupdate() end
    end)

    it("updates the package from a GitHub release", function()
      local tempPath = getMudletHomeDir() .. "/" .. PKG .. "_temp/" .. PKG .. ".mpackage"

      updater():downloadLatestMupdate()
      raiseEvent("sysDownloadDone", localPath, 2048)
      H.advance(2)

      assert.equals(
        "https://github.com/gesslar/" .. PKG .. "/releases/latest/download/" .. PKG .. "_version.txt",
        H.lastCall("getHTTP")[1]
      )

      raiseEvent("sysGetHttpDone", H.githubAssetUrl(PKG .. "_version.txt"), "1.1.0\n")

      assert.same(
        { tempPath, "https://github.com/gesslar/" .. PKG .. "/releases/latest/download/" .. PKG .. ".mpackage" },
        H.lastCall("downloadFile")
      )

      raiseEvent("sysDownloadDone", tempPath, 4096)
      H.advance(1)

      assert.same({ PKG }, H.lastCall("uninstallPackage"))
      assert.same({ tempPath }, H.lastCall("installPackage"))
      assert.is_false(H.locked())
    end)

    it("updates the package when the release is served without a redirect", function()
      local base = "https://github.com/gesslar/" .. PKG .. "/releases/latest/download/"

      updater():downloadLatestMupdate()
      raiseEvent("sysDownloadDone", localPath, 2048)
      H.advance(2)
      raiseEvent("sysGetHttpDone", base .. PKG .. "_version.txt", "1.1.0\n")

      assert.equals(base .. PKG .. ".mpackage", H.lastCall("downloadFile")[2])
    end)

    it("leaves an up-to-date package alone", function()
      updater():downloadLatestMupdate()
      raiseEvent("sysDownloadDone", localPath, 2048)
      H.advance(2)
      raiseEvent("sysGetHttpDone", H.githubAssetUrl(PKG .. "_version.txt"), "1.0.0\n")

      assert.equals(1, H.callCount("downloadFile"))
      assert.equals(0, H.callCount("uninstallPackage"))
      assert.is_false(H.locked())
    end)
  end)
end)
