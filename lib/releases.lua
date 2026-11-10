local M = {}

function M.try_load()
  local flutter = require("flutter")
  local url = flutter.index_url()
  local response = require("http").try_get({ url = url })
  if not response then
    return nil, "release index " .. url .. " could not be reached"
  end
  if response.status_code ~= 200 then
    return nil, "release index " .. url .. " returned HTTP " .. response.status_code
  end
  local ok, index = pcall(require("json").decode, response.body)
  if
    not ok
    or type(index) ~= "table"
    or type(index.releases) ~= "table"
    or type(index.current_release) ~= "table"
  then
    return nil, "release index " .. url .. " returned invalid JSON/schema (HTTP 200)"
  end
  return index
end

function M.load()
  local index, err = M.try_load()
  if not index then
    require("flutter").fail(err)
  end
  return index
end

function M.entry_arch(entry)
  if entry.dart_sdk_arch == "arm64" or entry.dart_sdk_arch == "x64" then
    return entry.dart_sdk_arch
  end
  if type(entry.archive) == "string" and entry.archive:find("arm64", 1, true) then
    return "arm64"
  end
  return "x64"
end

function M.select_arch(entries, os, arch, quiet)
  local x64, arm64
  for _, entry in ipairs(entries) do
    if entry.channel == "stable" or entry.channel == "beta" then
      if M.entry_arch(entry) == "arm64" then
        arm64 = arm64 or entry
      else
        x64 = x64 or entry
      end
    end
  end
  if os == "macos" and arch == "arm64" then
    if arm64 then
      return arm64
    end
    if x64 and not quiet then
      require("log").warn("no arm64 Flutter SDK for this version; using x64 under Rosetta")
    end
  elseif os == "linux" and arch == "arm64" then
    require("flutter").fail(
      "Flutter does not publish Linux arm64 SDKs; use an x64 machine (linux/arm64)"
    )
  elseif os == "windows" and arch == "arm64" and x64 and not quiet then
    require("log").warn("using the x64 Flutter SDK under Windows emulation (windows/arm64)")
  end
  return x64
end

function M.validate_entry(entry)
  local flutter = require("flutter")
  flutter.validate_archive(entry.archive)
  if not flutter.hex(entry.sha256, 64, 64) then
    flutter.fail("release index has no sha256 for " .. entry.archive)
  end
  if not flutter.valid_version(entry.version) or not flutter.hex(entry.hash, 40, 40) then
    flutter.fail("release index has invalid version or commit metadata")
  end
  return entry
end

local function matching(index, predicate)
  local entries = {}
  for _, entry in ipairs(index.releases) do
    if
      type(entry) == "table"
      and (entry.channel == "stable" or entry.channel == "beta")
      and predicate(entry)
    then
      table.insert(entries, entry)
    end
  end
  return entries
end

local function choose(entries, quiet)
  local os, arch = require("flutter").supported_platform()
  return M.select_arch(entries, os, arch, quiet)
end

function M.channel_entry(index, channel, optional)
  local hash = index.current_release[channel]
  if type(hash) ~= "string" then
    if optional then
      return nil
    end
    require("flutter").fail("release index has no current " .. channel .. " release")
  end
  local entry = choose(
    matching(index, function(e)
      return e.hash == hash and e.channel == channel
    end),
    optional
  )
  if not entry then
    if optional then
      return nil
    end
    require("flutter").fail(
      "no " .. channel .. " archive for " .. RUNTIME.osType .. "/" .. RUNTIME.archType
    )
  end
  return M.validate_entry(entry)
end

function M.exact_entry(index, version, optional)
  -- Prefer stable when a version was published on both channels.
  for _, channel in ipairs({ "stable", "beta" }) do
    local entry = choose(
      matching(index, function(e)
        return e.version == version and e.channel == channel
      end),
      optional
    )
    if entry then
      return M.validate_entry(entry)
    end
  end
  if optional then
    return nil
  end
  require("flutter").fail(
    "version "
      .. version
      .. " not found for "
      .. RUNTIME.osType
      .. "/"
      .. RUNTIME.archType
      .. "; run `mise ls-remote flutter`"
  )
end

function M.find_hash(index, sha)
  for _, channel in ipairs({ "stable", "beta" }) do
    local entry = choose(matching(index, function(e)
      return e.hash == sha and e.channel == channel
    end))
    if entry then
      return M.validate_entry(entry)
    end
  end
  return nil
end

function M.version_from_hash(index, sha, channel)
  local entry = choose(matching(index, function(e)
    return e.hash == sha and (not channel or e.channel == channel)
  end))
  return entry and entry.version or nil
end

return M
