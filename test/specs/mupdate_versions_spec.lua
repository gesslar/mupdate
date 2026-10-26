local H = dofile(debug.getinfo(1, "S").source:match("^@(.*/)") .. "support/harness.lua")

describe("Mupdate version comparison", function()
  local updater

  before_each(function()
    H.setup()
    updater = H.loadMupdate():new(H.options())
  end)

  after_each(function()
    assert.same({}, H.teardown({ "MupTest" }))
  end)

  -- compareVersions(installed, remote) answers "should we update?"
  local function shouldUpdate(installed, remote)
    return updater:compareVersions(installed, remote)
  end

  describe("MAJOR.MINOR.PATCH", function()
    local cases = {
      { "1.0.0", "1.0.1", true, "a newer patch" },
      { "1.0.9", "1.1.0", true, "a newer minor, even with a lower patch" },
      { "1.9.9", "2.0.0", true, "a newer major, even with lower minor and patch" },
      { "1.0.0", "1.0.0", false, "the same version" },
      { "1.0.1", "1.0.0", false, "an older patch" },
      { "2.0.0", "1.9.9", false, "an older major, even with higher minor and patch" },
      { "1.2.0", "1.10.0", true, "parts numerically, not as text" },
      { "1.10.0", "1.2.0", false, "parts numerically, not as text (reversed)" },
    }

    for _, case in ipairs(cases) do
      it(("%s -> %s: %s"):format(case[1], case[2], case[4]), function()
        assert.equals(case[3], shouldUpdate(case[1], case[2]))
      end)
    end
  end)

  describe("pre-release versions", function()
    local cases = {
      { "1.0.0-rc.1", "1.0.0", true, "the release outranks its pre-release" },
      { "1.0.0", "1.0.0-rc.1", false, "a pre-release never replaces its release" },
      { "1.0.0-rc.1", "0.9.9", false, "a pre-release still outranks the previous release" },
      { "1.2.3-rc.1", "1.2.2", false, "pre-release tags don't shift the numeric parts" },
      { "1.0.0-alpha", "1.0.0-alpha.1", true, "more identifiers win when the rest are equal" },
      { "1.0.0-alpha.1", "1.0.0-alpha.beta", true, "numeric identifiers sort below text" },
      { "1.0.0-beta.2", "1.0.0-beta.11", true, "numeric identifiers compare numerically" },
      { "1.0.0-alpha", "1.0.0-beta", true, "text identifiers compare as text" },
      { "1.0.0-rc.1", "1.0.0-rc.1", false, "the same pre-release" },
      { "1.0.0-1e2", "1.0.0-200", false, "'1e2' is text, not the number 100" },
      { "1.0.0-0x10", "1.0.0-20", false, "'0x10' is text, not the number 16" },
    }

    for _, case in ipairs(cases) do
      it(("%s -> %s: %s"):format(case[1], case[2], case[4]), function()
        assert.equals(case[3], shouldUpdate(case[1], case[2]))
      end)
    end

    it("follows the full precedence example from the SemVer spec", function()
      local ordered = {
        "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta",
        "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0",
      }

      for i = 1, #ordered do
        for j = 1, #ordered do
          assert.equals(i < j, shouldUpdate(ordered[i], ordered[j]),
            ordered[i] .. " -> " .. ordered[j])
        end
      end
    end)
  end)

  describe("loosely formatted versions", function()
    it("ignores build metadata", function()
      assert.is_false(shouldUpdate("1.0.0+build.5", "1.0.0"))
      assert.is_false(shouldUpdate("1.0.0", "1.0.0+build.9"))
      assert.is_true(shouldUpdate("1.0.0+build.5", "1.0.1"))
    end)

    it("treats missing parts as zero", function()
      assert.is_true(shouldUpdate("1.2", "1.2.1"))
      assert.is_false(shouldUpdate("1.2", "1.2.0"))
      assert.is_true(shouldUpdate("1", "1.0.1"))
    end)

    it("accepts a leading v", function()
      assert.is_true(shouldUpdate("v1.0.0", "1.0.1"))
      assert.is_false(shouldUpdate("1.0.1", "v1.0.1"))
    end)
  end)

  describe("unusable versions", function()
    it("does not update when the remote version can't be read, and says so", function()
      assert.is_false(shouldUpdate("1.0.0", "<html>Not Found</html>"))
      assert.matches("ERROR", H.output())
    end)

    it("does not update when the installed version can't be read", function()
      assert.is_false(shouldUpdate("unknown", "1.0.0"))
    end)

    it("does not update from an empty version file", function()
      assert.is_false(shouldUpdate("1.0.0", ""))
    end)
  end)
end)
