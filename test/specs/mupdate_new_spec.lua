local H = dofile(debug.getinfo(1, "S").source:match("^@(.*/)") .. "support/harness.lua")

describe("Mupdate:new()", function()
  local Mupdate

  before_each(function()
    H.setup()
    Mupdate = H.loadMupdate()
  end)

  after_each(function()
    assert.same({}, H.teardown({ "MupTest" }))
  end)

  describe("required options", function()
    for _, field in ipairs({ "download_path", "package_name", "remote_version_file" }) do
      it("rejects a missing " .. field .. ", naming the field", function()
        local options = H.options()
        options[field] = nil

        local ok, err = pcall(Mupdate.new, Mupdate, options)

        assert.is_false(ok)
        assert.matches(field, err, 1, true)
      end)

      it("rejects a non-string " .. field .. ", naming the field", function()
        local ok, err = pcall(Mupdate.new, Mupdate, H.options({ [field] = 42 }))

        assert.is_false(ok)
        assert.matches(field, err, 1, true)
      end)
    end

    it("rejects being called with no options at all", function()
      assert.is_false(pcall(Mupdate.new, Mupdate))
    end)
  end)

  describe("param_regex", function()
    it("rejects a malformed pattern up front rather than failing mid-update", function()
      local ok, err = pcall(Mupdate.new, Mupdate, H.options({
        param_key = "response-content-disposition",
        param_regex = "attachment; filename=(.*",
      }))

      assert.is_false(ok)
      assert.matches("regex", err)
    end)

    local function accepts(pattern)
      return pcall(Mupdate.new, Mupdate, H.options({ param_key = "k", param_regex = pattern }))
    end

    for _, pattern in ipairs({ "filename=(.*", "(.*))", "abc%", "[abc", "[^", "%b(", "%fx", "%1", "%0", "(a)%2", "(a%1)" }) do
      it("rejects the malformed pattern " .. pattern, function()
        assert.is_false(accepts(pattern))
      end)
    end

    for _, pattern in ipairs({ "%((.-)%)", "[]x]", "[^]]", "[%]]", "%b()", "%f[%w]%w+", "a-z?b*c+", "", "(a)%1", "(a)(b)%2%1", "[%1]" }) do
      it("accepts the valid pattern " .. pattern, function()
        assert.is_true(accepts(pattern))
      end)
    end

    it("accepts the pattern Updater.lua ships with", function()
      assert.has_no.errors(function()
        Mupdate:new(H.options({
          param_key = "response-content-disposition",
          param_regex = "attachment; filename=(.*)",
        }))
      end)
    end)
  end)

  describe("the installed package", function()
    it("refuses to manage a package that is not installed", function()
      H.packages.MupTest = nil

      local ok, err = pcall(Mupdate.new, Mupdate, H.options())

      assert.is_false(ok)
      assert.matches("not found", err)
    end)

    it("refuses a package without a version, since there is nothing to compare", function()
      H.packages.MupTest = {}

      local ok, err = pcall(Mupdate.new, Mupdate, H.options())

      assert.is_false(ok)
      assert.matches("version", err)
    end)

    it("records the installed version and the current profile", function()
      H.packages.MupTest = { version = "2.3.4" }

      local updater = Mupdate:new(H.options())

      assert.equals("2.3.4", updater.currentVersion)
      assert.equals(getProfileName(), updater.profile)
      assert.is_true(updater.initialized)
    end)
  end)

  describe("derived locations", function()
    it("downloads the package and version file from download_path", function()
      local updater = Mupdate:new(H.options({ remote_version_file = "version.txt" }))

      assert.equals("https://example.test/releases/latest/download/MupTest.mpackage", updater.packageUrl)
      assert.equals("https://example.test/releases/latest/download/version.txt", updater.versionUrl)
    end)

    it("stages the download in a temp directory under the Mudlet home dir", function()
      local updater = Mupdate:new(H.options())

      assert.equals(getMudletHomeDir() .. "/MupTest_temp/", updater.tempFilePath)
    end)
  end)

  describe("instances", function()
    it("keeps each package's settings separate", function()
      H.packages.OtherPkg = { version = "9.0.0" }

      local first = Mupdate:new(H.options())
      local second = Mupdate:new(H.options({
        package_name = "OtherPkg",
        remote_version_file = "OtherPkg_version.txt",
      }))

      assert.equals("MupTest", first.package_name)
      assert.equals("1.0.0", first.currentVersion)
      assert.equals("OtherPkg", second.package_name)
      assert.equals("9.0.0", second.currentVersion)
    end)

    it("leaves the module itself untouched", function()
      Mupdate:new(H.options({ debug_mode = true }))

      assert.is_nil(Mupdate.package_name)
      assert.is_false(Mupdate.debug_mode)
      assert.is_false(Mupdate.initialized)
    end)

    it("is quiet by default", function()
      assert.is_false(Mupdate:new(H.options()).debug_mode)
    end)
  end)
end)

describe("loading Mupdate.lua", function()
  before_each(function()
    H.setup()
    _G.Mupdate = nil
  end)

  after_each(function()
    assert.same({}, H.teardown())
  end)

  it("returns the module to require() without creating a global", function()
    local chunk = assert(loadfile(H.root .. "Mupdate.lua"))
    local module = chunk("SomePkg/Mupdate")

    assert.is_table(module)
    assert.is_function(module.new)
    assert.is_nil(rawget(_G, "Mupdate"))
  end)

  it("exposes a global when run as a Mudlet script, which has no caller to return to", function()
    local chunk = assert(loadfile(H.root .. "Mupdate.lua"))
    local module = chunk()

    assert.equals(module, rawget(_G, "Mupdate"))
  end)
end)
