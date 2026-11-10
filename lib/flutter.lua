local M = {}

M.REPO_URL = "https://github.com/flutter/flutter.git"
M.API_URL = "https://api.github.com/repos/flutter/flutter/commits/"
M.DEFAULT_STORAGE_BASE = "https://storage.googleapis.com"

function M.fail(message)
  error("flutter: " .. message, 0)
end

function M.trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.hex(value, min, max)
  return type(value) == "string"
    and #value >= min
    and #value <= max
    and value:match("^[0-9a-f]+$") ~= nil
end

function M.valid_version(value)
  return type(value) == "string" and #value <= 128 and value:match("^v?%d[%w%.%+%-]*$") ~= nil
end

function M.supported_platform()
  local os, arch = RUNTIME.osType, RUNTIME.archType
  if os == "linux" and arch == "arm64" then
    M.fail("Flutter does not publish Linux arm64 SDKs; use an x64 machine (linux/arm64)")
  end
  if
    (os ~= "darwin" and os ~= "linux" and os ~= "windows")
    or (arch ~= "amd64" and arch ~= "arm64")
  then
    M.fail(
      "unsupported platform "
        .. tostring(os)
        .. "/"
        .. tostring(arch)
        .. "; use macOS x64/arm64, Linux x64 or Windows x64"
    )
  end
  return os == "darwin" and "macos" or os, arch
end

function M.index_os()
  local os = M.supported_platform()
  return os
end

function M.is_windows()
  return RUNTIME.osType == "windows"
end

function M.storage_base()
  local base = os.getenv("FLUTTER_STORAGE_BASE_URL") or M.DEFAULT_STORAGE_BASE
  base = base:gsub("/+$", "")
  -- Disallow embedded credentials, query strings and control characters in mirrors.
  if not base:match("^https?://[^/]+") or base:find("[%s@?#\\]") then
    M.fail("FLUTTER_STORAGE_BASE_URL must be an http(s) base URL without credentials or query")
  end
  return base
end

function M.index_url()
  return M.storage_base() .. "/flutter_infra_release/releases/releases_" .. M.index_os() .. ".json"
end

function M.validate_archive(path)
  if
    type(path) ~= "string"
    or path == ""
    or path:sub(1, 1) == "/"
    or path:find("[^%w%._%+%/-]")
  then
    M.fail("release index contains an invalid relative archive path")
  end
  for segment in path:gmatch("[^/]+") do
    if segment == ".." or segment == "." then
      M.fail("release index contains an escaping archive path")
    end
  end
  return path
end

function M.archive_url(path)
  return M.storage_base() .. "/flutter_infra_release/releases/" .. M.validate_archive(path)
end

function M.read_json(path)
  local ok, text = pcall(require("file").read, path)
  if not ok then
    return nil
  end
  local parsed, data = pcall(require("json").decode, text)
  return parsed and type(data) == "table" and data or nil
end

function M.write_json(path, data)
  local handle = io.open(path, "w")
  if not handle then
    M.fail("cannot write " .. path)
  end
  local ok = handle:write(require("json").encode(data), "\n")
  local closed = handle:close()
  if not ok or not closed then
    M.fail("cannot write " .. path)
  end
end

return M
