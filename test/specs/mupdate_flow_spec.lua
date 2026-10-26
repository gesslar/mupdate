local H = dofile(debug.getinfo(1, "S").source:match("^@(.*/)") .. "support/harness.lua")

local USERS = { "MupTest", "OtherPkg", "My-Pkg", "__PKGNAME__" }

local function with(base, extra)
  local merged = {}

  for k, v in pairs(base) do merged[k] = v end
  for k, v in pairs(extra) do merged[k] = v end

  return merged
end

describe("Mupdate update run", function()
  local Mupdate
  local tempPath

  before_each(function()
    H.setup()
    H.packages.OtherPkg = { version = "1.0.0" }
    H.packages["My-Pkg"] = { version = "1.0.0" }
    Mupdate = H.loadMupdate()
    tempPath = getMudletHomeDir() .. "/MupTest_temp/MupTest.mpackage"
  end)

  after_each(function()
    _G.MupTest = nil
    assert.same({}, H.teardown(USERS))
  end)

  local function start(overrides)
    local updater = Mupdate:new(H.options(overrides))
    updater:Start()

    return updater
  end

  local function respond(url, body)
    raiseEvent("sysGetHttpDone", url, body)
  end

  local versionUrl = "https://example.test/releases/latest/download/MupTest_version.txt"

  -- Runs a full update for MupTest up to the point the new package is installed.
  local function runUpdate(overrides)
    local updater = start(overrides)
    respond(versionUrl, "1.0.1")
    raiseEvent("sysDownloadDone", tempPath, 1024)
    H.advance(1)

    return updater
  end

  describe("starting", function()
    it("asks for the version file", function()
      start()

      assert.equals(1, H.callCount("getHTTP"))
      assert.equals(versionUrl, H.lastCall("getHTTP")[1])
    end)

    it("holds the profile-wide lock while it runs", function()
      start()

      assert.is_true(H.locked())
    end)
  end)

  describe("recognising its version file", function()
    it("updates when its version file reports a newer version", function()
      start()
      respond(versionUrl, "1.0.1")

      assert.equals(1, H.callCount("downloadFile"))
      assert.same(
        { tempPath, "https://example.test/releases/latest/download/MupTest.mpackage" },
        H.lastCall("downloadFile")
      )
      assert.equals(getMudletHomeDir() .. "/MupTest_temp/", H.lastCall("lfs.mkdir")[1])
    end)

    it("uses the configured remote_version_file name", function()
      start({ remote_version_file = "version.txt" })
      respond("https://example.test/releases/latest/download/version.txt", "1.0.1")

      assert.equals(1, H.callCount("downloadFile"))
    end)

    it("handles package names containing Lua pattern characters", function()
      local updater = start({ package_name = "My-Pkg", remote_version_file = "My-Pkg_version.txt" })
      respond(updater.versionUrl, "1.0.1")

      assert.equals(1, H.callCount("downloadFile"))
    end)

    it("ignores the version file of a package whose name merely contains its own", function()
      start()
      respond("https://example.test/releases/latest/download/XMupTest_version.txt", "9.9.9")

      assert.equals(0, H.callCount("downloadFile"))
      assert.is_true(H.locked())
    end)

    it("ignores unrelated HTTP traffic, whatever shape the URL has", function()
      start({ debug_mode = true })

      respond("https://example.test/some/other/file.json", "9.9.9")
      respond("https://example.test/", "9.9.9")
      respond("https://example.test", "9.9.9")
      respond("https://example.test/search?q=MupTest_version.txt", "9.9.9")

      assert.equals(0, H.callCount("downloadFile"))
      assert.is_true(H.locked())
    end)

    it("reads only the first line of the version file and tolerates CRLF", function()
      start()
      respond(versionUrl, "1.0.1\r\nRelease notes go here\r\n")

      assert.equals(1, H.callCount("downloadFile"))
    end)
  end)

  describe("recognising its version file behind a GitHub redirect", function()
    local github = {
      param_key = "response-content-disposition",
      param_regex = "attachment; filename=(.*)",
    }

    it("matches the file name carried in the URL parameter", function()
      start(github)
      respond(H.githubAssetUrl("MupTest_version.txt"), "1.0.1")

      assert.equals(1, H.callCount("downloadFile"))
    end)

    it("ignores another package's release asset", function()
      start(github)
      respond(H.githubAssetUrl("OtherPkg_version.txt"), "9.9.9")

      assert.equals(0, H.callCount("downloadFile"))
      assert.is_true(H.locked())
    end)

    it("ignores URLs without the parameter", function()
      start(with(github, { debug_mode = true }))
      respond("https://example.test/some/other/file.json", "9.9.9")

      assert.equals(0, H.callCount("downloadFile"))
    end)

    it("falls back to the file name when the file is served without a redirect", function()
      start(github)
      respond(versionUrl, "1.0.1")

      assert.equals(1, H.callCount("downloadFile"))
    end)

    it("reports a failed direct request too", function()
      start(github)
      raiseEvent("sysGetHttpError", "404 Not Found", versionUrl)

      assert.matches("Failed to read version", H.output())
      assert.is_false(H.locked())
    end)

    it("only falls back for the exact URL it requested, not a same-named file elsewhere", function()
      start(with(github, { remote_version_file = "version.txt" }))
      respond("https://other.example/version.txt", "9.9.9")
      raiseEvent("sysGetHttpError", "404 Not Found", "https://other.example/version.txt")

      assert.equals(0, H.callCount("downloadFile"))
      assert.equals("", H.output())
      assert.is_true(H.locked())
    end)

    it("lets the parameter decide when present, whatever the file name says", function()
      start(github)
      respond(versionUrl .. "?response-content-disposition=attachment%3B%20filename%3DOtherPkg_version.txt", "9.9.9")

      assert.equals(0, H.callCount("downloadFile"))
    end)

    it("ignores parameter values the regex doesn't match", function()
      start(with(github, { debug_mode = true }))
      respond("https://example.test/x?response-content-disposition=inline", "9.9.9")

      assert.equals(0, H.callCount("downloadFile"))
    end)

    it("compares the raw parameter value when there is no regex", function()
      start({ param_key = "file" })
      respond("https://example.test/get?file=MupTest_version.txt", "1.0.1")
      respond("https://example.test/get?file=OtherPkg_version.txt", "9.9.9")

      assert.equals(1, H.callCount("downloadFile"))
    end)
  end)

  describe("deciding whether to update", function()
    it("does nothing when already up to date, and finishes straight away", function()
      start()
      respond(versionUrl, "1.0.0")

      assert.equals(0, H.callCount("downloadFile"))
      assert.is_false(H.locked())
    end)

    it("never downgrades", function()
      start()
      respond(versionUrl, "0.9.0")

      assert.equals(0, H.callCount("downloadFile"))
      assert.is_false(H.locked())
    end)

    it("announces the update it is about to install", function()
      start()
      respond(versionUrl, "1.0.1")

      assert.matches("Attempting to update MupTest to v1.0.1", H.output(), 1, true)
    end)

    it("reports an unreadable version file and finishes", function()
      start()
      respond(versionUrl, "<!DOCTYPE html><html>Not Found</html>")

      assert.equals(0, H.callCount("downloadFile"))
      assert.matches("ERROR", H.output())
      assert.is_false(H.locked())
    end)

    it("reports a failed version request and finishes", function()
      start()
      raiseEvent("sysGetHttpError", "404 Not Found", versionUrl)

      assert.matches("Failed to read version", H.output())
      assert.is_false(H.locked())
    end)

    it("ignores failed requests that aren't its own", function()
      start({ debug_mode = true })
      raiseEvent("sysGetHttpError", "404 Not Found", "https://example.test/releases/latest/download/OtherPkg_version.txt")
      raiseEvent("sysGetHttpError", "timeout", "https://example.test")

      assert.equals("", H.output())
      assert.is_true(H.locked())
    end)
  end)

  describe("installing the update", function()
    it("uninstalls the old version first and clears its global", function()
      _G.MupTest = { stale = true }

      start()
      respond(versionUrl, "1.0.1")
      raiseEvent("sysDownloadDone", tempPath, 1024)

      assert.same({ "MupTest" }, H.lastCall("uninstallPackage"))
      assert.is_nil(rawget(_G, "MupTest"))
      assert.equals(0, H.callCount("installPackage"))
    end)

    it("then installs the downloaded package and tidies up after itself", function()
      runUpdate()

      assert.same({ tempPath }, H.lastCall("installPackage"))
      assert.same({ tempPath }, H.lastCall("os.remove"))
      assert.equals(getMudletHomeDir() .. "/MupTest_temp/", H.lastCall("lfs.rmdir")[1])
      assert.matches("Package updated successfully", H.output())
    end)

    it("finishes once installed", function()
      runUpdate()

      assert.is_false(H.locked())
    end)

    it("ignores downloads that aren't its package", function()
      start()
      respond(versionUrl, "1.0.1")
      raiseEvent("sysDownloadDone", getMudletHomeDir() .. "/OtherPkg_temp/OtherPkg.mpackage", 1024)
      H.advance(1)

      assert.equals(0, H.callCount("uninstallPackage"))
      assert.equals(0, H.callCount("installPackage"))
      assert.is_true(H.locked())
    end)

    it("reports a failed download, leaves the installed package alone, and finishes", function()
      start()
      respond(versionUrl, "1.0.1")
      raiseEvent("sysDownloadError", "Host not found", tempPath,
        "https://example.test/releases/latest/download/MupTest.mpackage")

      assert.matches("Failed downloading", H.output())
      assert.equals(0, H.callCount("uninstallPackage"))
      assert.is_false(H.locked())
    end)

    it("reports a failed GitHub download without tripping over its URL", function()
      start({ param_key = "response-content-disposition", param_regex = "attachment; filename=(.*)", debug_mode = true })
      respond(H.githubAssetUrl("MupTest_version.txt"), "1.0.1")
      raiseEvent("sysDownloadError", "Connection reset", tempPath, "https://example.test")

      assert.matches("Failed downloading", H.output())
      assert.is_false(H.locked())
    end)

    it("ignores failed downloads that aren't its package", function()
      start()
      respond(versionUrl, "1.0.1")
      raiseEvent("sysDownloadError", "Host not found", "/elsewhere/OtherPkg.mpackage", "https://example.test/OtherPkg.mpackage")

      assert.is_nil(H.output():find("Failed downloading", 1, true))
      assert.is_true(H.locked())
    end)
  end)

  describe("once finished", function()
    it("ignores late responses", function()
      start()
      respond(versionUrl, "1.0.0")

      respond(versionUrl, "9.9.9")
      raiseEvent("sysDownloadDone", tempPath, 1024)
      H.advance(5)

      assert.equals(0, H.callCount("downloadFile"))
      assert.equals(0, H.callCount("installPackage"))
    end)

    it("lets the same package run again with a fresh updater", function()
      start()
      respond(versionUrl, "1.0.0")

      start()
      respond(versionUrl, "1.0.1")

      assert.equals(1, H.callCount("downloadFile"))
    end)
  end)

  describe("the profile-wide lock", function()
    local function startOther()
      local updater = Mupdate:new(H.options({
        package_name = "OtherPkg",
        remote_version_file = "OtherPkg_version.txt",
      }))
      updater:Start()

      return updater
    end

    it("makes a second package wait while one is running", function()
      start()
      startOther()

      assert.equals(1, H.callCount("getHTTP"))
      assert.equals(versionUrl, H.lastCall("getHTTP")[1])
    end)

    it("lets the waiting package go within a couple of seconds of the first finishing", function()
      start()
      local other = startOther()
      H.advance(1)
      respond(versionUrl, "1.0.0")
      H.advance(2)

      assert.equals(2, H.callCount("getHTTP"))
      assert.equals(other.versionUrl, H.lastCall("getHTTP")[1])
    end)

    it("keeps the lock through the install, so packages don't update over each other", function()
      start()
      startOther()
      respond(versionUrl, "1.0.1")
      raiseEvent("sysDownloadDone", tempPath, 1024)
      H.advance(0.5)

      assert.equals(1, H.callCount("getHTTP"))

      H.advance(3)
      assert.equals(2, H.callCount("getHTTP"))
    end)

    it("lets a slow update finish", function()
      start()
      H.advance(5)
      respond(versionUrl, "1.0.1")
      H.advance(25)
      raiseEvent("sysDownloadDone", tempPath, 1024)
      H.advance(1)

      assert.same({ tempPath }, H.lastCall("installPackage"))
    end)

    it("gives up on a run that never hears back, and ignores it if it does later", function()
      start()
      H.advance(61)

      assert.is_false(H.locked())

      respond(versionUrl, "1.0.1")
      assert.equals(0, H.callCount("downloadFile"))
    end)

    it("still installs cleanly if the timeout lands during the install delay", function()
      start()
      H.advance(59.5)
      respond(versionUrl, "1.0.1")
      raiseEvent("sysDownloadDone", tempPath, 1024)
      H.advance(1)

      assert.same({ tempPath }, H.lastCall("installPackage"))
      assert.is_false(H.locked())
    end)
  end)

  describe("uninstall handling", function()
    it("registers its uninstall handler under the package's own name", function()
      start()

      assert.is_true(H.hasNamedHandler("MupTest", "MupTest.AutoMupdate.Uninstall"))
      assert.is_false(H.hasNamedHandler("__PKGNAME__", "__PKGNAME__.AutoMupdate.Uninstall"))
    end)

    it("removes the package's named handlers and timers when the user uninstalls it", function()
      start()
      registerNamedEventHandler("MupTest", "Probe", "probeEvent", function() end)
      registerNamedTimer("MupTest", "ProbeTimer", 100, function() end)

      raiseEvent("sysUninstall", "MupTest")

      assert.is_false(H.hasNamedHandler("MupTest", "Probe"))
      assert.is_false(H.hasNamedTimer("MupTest", "ProbeTimer"))
    end)

    it("leaves the package alone when a different package is uninstalled", function()
      start()
      registerNamedEventHandler("MupTest", "Probe", "probeEvent", function() end)

      raiseEvent("sysUninstall", "OtherPkg")

      assert.is_true(H.hasNamedHandler("MupTest", "Probe"))
    end)

    it("releases the lock when the package is uninstalled mid-run, letting others go", function()
      start()
      local other = Mupdate:new(H.options({
        package_name = "OtherPkg",
        remote_version_file = "OtherPkg_version.txt",
      }))
      other:Start()

      raiseEvent("sysUninstall", "MupTest")
      H.advance(2)

      assert.equals(other.versionUrl, H.lastCall("getHTTP")[1])
    end)

    it("stops the run for good when its package is uninstalled", function()
      start()
      raiseEvent("sysUninstall", "MupTest")

      respond(versionUrl, "1.0.1")
      H.advance(61)

      assert.equals(0, H.callCount("downloadFile"))
    end)

    it("doesn't release the lock held by another package", function()
      start()
      local other = Mupdate:new(H.options({
        package_name = "OtherPkg",
        remote_version_file = "OtherPkg_version.txt",
      }))
      other:Start()

      raiseEvent("sysUninstall", "OtherPkg")

      assert.is_true(H.locked())
    end)

    it("stops a package that is still waiting for the lock from starting later", function()
      start()
      local other = Mupdate:new(H.options({
        package_name = "OtherPkg",
        remote_version_file = "OtherPkg_version.txt",
      }))
      other:Start()

      raiseEvent("sysUninstall", "OtherPkg")
      respond(versionUrl, "1.0.0")
      H.advance(5)

      assert.equals(1, H.callCount("getHTTP"))
    end)

    it("survives its own update's uninstall, so a later real uninstall still cleans up", function()
      runUpdate()
      registerNamedEventHandler("MupTest", "Probe", "probeEvent", function() end)

      raiseEvent("sysUninstall", "MupTest")

      assert.is_false(H.hasNamedHandler("MupTest", "Probe"))
    end)
  end)

  describe("debug output", function()
    it("stays silent unless debug_mode is on", function()
      start()
      respond("https://example.test/some/other/file.json", "x")
      respond(versionUrl, "1.0.1")
      raiseEvent("sysDownloadDone", tempPath, 1024)
      H.advance(1)

      assert.equals(0, H.callCount("debugc"))
    end)

    it("logs, labelled with the package, when debug_mode is on", function()
      start({ debug_mode = true })
      respond(versionUrl, "1.0.0")

      assert.is_true(H.callCount("debugc") > 0)

      for _, call in ipairs(H.calls.debugc) do
        assert.matches("^%[MupTest%] ", call[1])
      end
    end)
  end)

  describe("messages", function()
    it("prints errors as one clean line", function()
      start()
      raiseEvent("sysGetHttpError", "404 Not Found", versionUrl)

      local out = H.output()

      assert.matches("^<red>%[ ERROR %]<reset> <DarkOrange>MupTest<reset> %- ", out)
      assert.matches("\n$", out)
      assert.is_nil(out:find('"', 1, true))
      assert.is_nil(out:find("\\n", 1, true))
    end)

    it("prints info the same way", function()
      start()
      respond(versionUrl, "1.0.1")

      assert.matches("^<gold>%[ INFO %]<reset> <DarkOrange>MupTest<reset> %- .*\n$", H.output())
    end)
  end)
end)
