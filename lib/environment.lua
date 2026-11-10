local M = {}

function M.keys(ctx)
  local file, install = require("file"), require("install")
  local dart = file.join_path(ctx.path, "bin", "cache", "dart-sdk")
  local ok, cache = pcall(require, "mise.cache")
  if ok then
    cache.watch_files({
      install.marker_path(ctx.path),
      file.join_path(dart, "version"),
      file.join_path(ctx.path, "bin", "cache", "flutter.version.json"),
      dart,
    })
  end
  local marker, info = install.read_marker(ctx.path) or {}, install.version_info(ctx.path)
  local result = {
    { key = "FLUTTER_ROOT", value = ctx.path },
    { key = "PATH", value = file.join_path(ctx.path, "bin") },
  }
  local function add(key, value)
    if type(value) == "string" and value ~= "" then
      table.insert(result, { key = key, value = value })
    end
  end
  add("MISE_FLUTTER_REVISION", marker.framework_revision or info.frameworkRevision)
  add("MISE_FLUTTER_CHANNEL", marker.channel or info.channel)
  add("MISE_FLUTTER_DART_VERSION", install.detect_dart_version(ctx.path))
  local stat = file.stat(dart)
  if stat and stat.is_dir then
    add("DART_SDK", dart)
  end
  return result
end

function M.parse_legacy(ctx)
  if ctx.filename ~= ".flutter-version" then
    return nil
  end
  local ok, text = pcall(require("file").read, ctx.filepath)
  if not ok then
    return nil
  end
  for line in text:gmatch("[^\r\n]+") do
    line = require("flutter").trim(line)
    if line ~= "" then
      local valid = pcall(require("requests").classify, line)
      if valid then
        return { version = line }
      end
      return nil
    end
  end
  return nil
end

return M
