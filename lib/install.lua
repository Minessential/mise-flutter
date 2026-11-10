local M = {}

function M.marker_path(root)
  return require("file").join_path(root, ".mise-flutter.json")
end

function M.read_marker(root)
  local marker = require("flutter").read_json(M.marker_path(root))
  return marker and marker.schema == 1 and marker or nil
end

function M.write_marker(root, marker)
  require("flutter").write_json(M.marker_path(root), marker)
end

function M.verify_tree(root, os)
  local file = require("file")
  local name = os == "windows" and "flutter.bat" or "flutter"
  if not file.exists(file.join_path(root, "bin", name)) then
    local hint = os == "windows" and " (on Windows, check antivirus quarantine)" or ""
    require("flutter").fail("the archive did not contain bin/" .. name .. hint)
  end
end

function M.version_info(root)
  return require("flutter").read_json(
    require("file").join_path(root, "bin", "cache", "flutter.version.json")
  ) or {}
end

function M.detect_dart_version(root)
  local file, flutter = require("file"), require("flutter")
  local ok, text = pcall(file.read, file.join_path(root, "bin", "cache", "dart-sdk", "version"))
  if ok and flutter.trim(text) ~= "" then
    return flutter.trim(text)
  end
  local info = M.version_info(root)
  if type(info.dartSdkVersion) == "string" then
    return info.dartSdkVersion
  end
  local marker = M.read_marker(root)
  return marker and type(marker.dart_sdk_version) == "string" and marker.dart_sdk_version or nil
end

function M.expected_dart_version(index, request)
  local releases = require("releases")
  local entry
  if request.kind == "channel" then
    entry = releases.channel_entry(index, request.channel)
  elseif request.kind == "exact" then
    entry = releases.exact_entry(index, request.raw)
  elseif request.sha then
    entry = releases.find_hash(index, request.sha)
  end
  return entry and entry.dart_sdk_version or nil
end

function M.archive_marker(root, request, resolved_index)
  local flutter, releases = require("flutter"), require("releases")
  local previous = M.read_marker(root)
  if previous and previous.request == request.raw and previous.source == "archive" then
    return previous
  end
  local index, err = resolved_index
  if not index then
    index, err = releases.try_load()
  end
  local entry
  if index then
    if request.kind == "channel" then
      entry = releases.channel_entry(index, request.channel)
    elseif request.kind == "exact" then
      entry = releases.exact_entry(index, request.raw)
    elseif request.sha then
      entry = releases.find_hash(index, request.sha)
    end
  else
    require("log").warn(err .. "; archive installed, Dart metadata unavailable")
  end
  local info = M.version_info(root)
  return {
    schema = 1,
    request = request.raw,
    version = entry and entry.version or info.frameworkVersion or "0.0.0-unknown",
    channel = entry and entry.channel or request.channel or "unknown",
    source = "archive",
    framework_revision = entry and entry.hash or info.frameworkRevision,
    dart_sdk_version = entry and entry.dart_sdk_version or require("json").decode("null"),
    archive = entry and entry.archive,
    sha256 = entry and entry.sha256,
    bootstrapped = false,
  }
end

function M.commit_marker(root, request)
  local git, file, flutter = require("git"), require("file"), require("flutter")
  local previous = M.read_marker(root)
  local ref = request.kind == "main" and "master" or request.sha
  local sha = previous and previous.framework_revision or git.cached_sha(ref)
  if not flutter.hex(sha, 40, 40) then
    if request.kind == "main" then
      sha = git.remote_head(root)
    elseif request.kind == "snapshot" then
      sha = git.resolve_snapshot(request)
    else
      sha = git.resolve_full_sha(request.sha)
    end
  end
  if request.sha and sha:sub(1, #request.sha) ~= request.sha then
    flutter.fail("marker commit does not match request")
  end
  request.sha = sha
  if previous and previous.source == "archive" then
    return previous
  end
  if not previous then
    -- A released commit was installed from its official archive, so the SDK
    -- tree already exists. A `main` API-outage fallback has no archive tree:
    -- do not mistake a master HEAD that happens to equal a release for one.
    local binary = file.join_path(root, "bin", flutter.is_windows() and "flutter.bat" or "flutter")
    local extracted = file.exists(binary)
    local index = require("releases").try_load()
    if extracted and index and require("releases").find_hash(index, sha) then
      return M.archive_marker(root, request, index)
    end
    if extracted and not index then
      return M.archive_marker(root, request)
    end
  end
  git.checkout(root, sha, { branch = request.channel == "main" and "master" or nil })
  return {
    schema = 1,
    request = request.raw,
    version = "0.0.0-unknown",
    channel = request.channel or "unknown",
    source = "git",
    framework_revision = sha,
    dart_sdk_version = require("json").decode("null"),
    bootstrapped = previous and previous.bootstrapped or false,
  }
end

function M.bootstrap(root, os, timeout)
  local file, flutter = require("file"), require("flutter")
  local command = os == "windows" and ".\\bin\\flutter.bat" or "./bin/flutter"
  command = command .. " --suppress-analytics --version --machine"
  local ok, err = pcall(require("cmd").exec, command, {
    cwd = root,
    timeout = timeout or 1800,
    -- Bootstrap must not populate the user's Pub cache or analytics/config dirs.
    env = {
      CI = "true",
      FLUTTER_SUPPRESS_ANALYTICS = "true",
      DART_SUPPRESS_ANALYTICS = "true",
      PUB_CACHE = file.join_path(root, "bin", "cache", "pub-cache"),
      HOME = root,
      USERPROFILE = root,
      XDG_CONFIG_HOME = file.join_path(root, ".config"),
      APPDATA = file.join_path(root, ".appdata"),
      LOCALAPPDATA = file.join_path(root, ".local-appdata"),
    },
  })
  if not ok then
    local message = tostring(err):gsub("[\r\n]+", " ")
    flutter.fail(
      "Dart SDK bootstrap failed ("
        .. command
        .. "): "
        .. message
        .. "; retry with bootstrap = false to install without it"
    )
  end
  local info = M.version_info(root)
  if
    not file.exists(file.join_path(root, "bin", "cache", "dart-sdk", "version"))
    or type(info.dartSdkVersion) ~= "string"
  then
    flutter.fail(
      "Dart SDK bootstrap failed: missing Dart version metadata; retry with bootstrap = false"
    )
  end
  return info
end

function M.satisfied(ctx)
  local file, flutter = require("file"), require("flutter")
  local name = flutter.is_windows() and "flutter.bat" or "flutter"
  if not file.exists(file.join_path(ctx.path, "bin", name)) then
    return { satisfied = false, reason = "missing bin/" .. name }
  end
  if
    ctx.options
    and ctx.options.bootstrap == "true"
    and not file.exists(file.join_path(ctx.path, "bin", "cache", "dart-sdk", "version"))
  then
    return { satisfied = false, reason = "Dart SDK has not been bootstrapped" }
  end
  if require("requests").is_commit(ctx.version) and not M.read_marker(ctx.path) then
    return { satisfied = false, reason = "missing .mise-flutter.json" }
  end
  return { satisfied = true }
end

function M.post_install(ctx)
  local flutter = require("flutter")
  flutter.supported_platform()
  local request = require("requests").classify(ctx.runtimeVersion)
  local marker
  if request.kind == "channel" or request.kind == "exact" then
    M.verify_tree(ctx.rootPath, RUNTIME.osType)
    marker = M.archive_marker(ctx.rootPath, request)
  else
    marker = M.commit_marker(ctx.rootPath, request)
  end
  M.verify_tree(ctx.rootPath, RUNTIME.osType)
  marker.request = ctx.runtimeVersion
  if ctx.options and ctx.options.bootstrap == "true" then
    marker.bootstrapped = false
    M.write_marker(ctx.rootPath, marker)
    local info = M.bootstrap(ctx.rootPath, RUNTIME.osType, 1800)
    marker.bootstrapped = true
    marker.dart_sdk_version = info.dartSdkVersion
    if marker.source == "archive" then
      marker.framework_revision = info.frameworkRevision or marker.framework_revision
    end
    marker.version = info.frameworkVersion or marker.version
  end
  M.write_marker(ctx.rootPath, marker)
  require("log").info(
    ctx.runtimeVersion
      .. " -> "
      .. marker.version
      .. " ("
      .. marker.channel
      .. "/"
      .. marker.source
      .. ") Dart "
      .. (type(marker.dart_sdk_version) == "string" and marker.dart_sdk_version or "unknown")
  )
end

return M
