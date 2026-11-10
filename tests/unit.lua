local M = {}

local function fails(fn, text)
  local ok, err = pcall(fn)
  assert(not ok and tostring(err):find(text, 1, true), tostring(err))
end

function M.run()
  local requests, releases, flutter = require("requests"), require("releases"), require("flutter")
  assert(requests.classify("git-ABC1234").sha == "abc1234")
  assert(requests.classify("main-abcdef123456").kind == "snapshot")
  local snapshot = requests.classify("main-20200229010203-ABCDEF123456")
  assert(snapshot.kind == "snapshot" and snapshot.timestamp == "20200229010203")
  assert(snapshot.sha == "abcdef123456" and snapshot.raw == "main-20200229010203-abcdef123456")
  assert(requests.snapshot_stamp("2020-02-29T01:02:03Z") == "20200229010203")
  for _, date in ipairs({
    "2019-02-29T00:00:00Z",
    "2020-13-01T00:00:00Z",
    "2020-01-01T24:00:00Z",
    "bad",
  }) do
    assert(requests.snapshot_stamp(date) == nil)
  end
  fails(function()
    requests.classify("main-20200230010203-abcdef123456")
  end, "UTC timestamp")
  assert(requests.classify("v1.9.1+hotfix.6").raw == "v1.9.1+hotfix.6")
  for _, request in ipairs({ "git-abcd", "git-abcdefg", "main-abc1234", "1.0;echo", "../1" }) do
    fails(function()
      requests.classify(request)
    end, "flutter:")
  end
  fails(function()
    requests.classify("dev")
  end, "obsolete")
  for _, path in ipairs({
    "",
    "/evil.zip",
    "../evil.zip",
    "a/../b",
    "a\\b",
    "https://evil/a",
    "a/%2e%2e/b",
  }) do
    fails(function()
      flutter.archive_url(path)
    end, "archive path")
  end
  local function entry(arch)
    return {
      version = "9.9.9",
      hash = string.rep("a", 40),
      channel = "stable",
      archive = "stable/macos/flutter_" .. arch .. "_9.9.9.zip",
      dart_sdk_arch = arch,
      sha256 = string.rep("b", 64),
    }
  end
  local x64, arm = entry("x64"), entry("arm64")
  assert(releases.select_arch({ x64, arm }, "macos", "arm64") == arm)
  assert(releases.select_arch({ arm, x64 }, "macos", "amd64") == x64)
  assert(releases.select_arch({ x64 }, "macos", "arm64", true) == x64)
  assert(releases.select_arch({ arm }, "macos", "amd64") == nil)
  assert(releases.select_arch({ x64 }, "windows", "arm64", true) == x64)
  assert(releases.entry_arch({ archive = "stable/macos/flutter_arm64_old.zip" }) == "arm64")
  assert(releases.entry_arch({ archive = "stable/macos/flutter_old.zip" }) == "x64")
  fails(function()
    releases.select_arch({ x64 }, "linux", "arm64")
  end, "Linux arm64")
  assert(releases.validate_entry(x64) == x64)
  local beta = entry("x64")
  beta.channel = "beta"
  local index = { releases = { beta, x64, arm }, current_release = { stable = x64.hash } }
  assert(releases.exact_entry(index, "9.9.9").channel == "stable")
  assert(releases.channel_entry(index, "beta", true) == nil)
  fails(function()
    releases.channel_entry(index, "beta")
  end, "no current beta")
  fails(function()
    releases.exact_entry(index, "1.2.3")
  end, "mise ls-remote flutter")
  x64.sha256 = nil
  fails(function()
    releases.validate_entry(x64)
  end, "no sha256")
  local cmd, git = require("cmd"), require("git")
  local original = cmd.exec
  cmd.exec = function()
    error("git not found")
  end
  fails(function()
    git.ensure_available(RUNTIME.cacheDirPath)
  end, "git is required")
  cmd.exec = function(command)
    if command == "git rev-parse HEAD" then
      return string.rep("d", 40)
    end
    return ""
  end
  fails(function()
    git.checkout(RUNTIME.cacheDirPath, string.rep("e", 40), {})
  end, "checkout is at")
  cmd.exec = original
  git.cache_sha("master", string.rep("a", 40))
  git.forget_master()
  assert(git.cached_sha("master") == nil)
  local http = require("http")
  local get = http.try_get
  http.try_get = function()
    return { status_code = 200, body = '{"sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}' }
  end
  local sha, err = git.try_resolve("aaaaaaa")
  assert(sha == nil and err:find("different commit", 1, true))
  http.try_get = function()
    return { status_code = 200, body = "not-json" }
  end
  local index_result, index_err = releases.try_load()
  assert(index_result == nil and index_err:find("invalid JSON/schema", 1, true))
  http.try_get = get
  require("log").info("request, platform, archive validation and Git failure assertions passed")
  return { { version = "9.9.9" } }
end

return M
