local M = {}

function M.try_resolve(ref)
  local flutter = require("flutter")
  if ref ~= "master" and not flutter.hex(ref, 7, 40) then
    flutter.fail("invalid Git commit")
  end
  local response = require("http").try_get({
    url = flutter.API_URL .. ref,
    headers = { ["Accept"] = "application/vnd.github+json" },
  })
  if not response then
    return nil, "GitHub API could not be reached; set MISE_GITHUB_TOKEN to raise the rate limit"
  end
  if response.status_code ~= 200 then
    local message = "GitHub API returned HTTP "
      .. response.status_code
      .. "; set MISE_GITHUB_TOKEN to raise the rate limit"
    if response.status_code == 404 then
      message = "commit " .. ref .. " was not found in flutter/flutter; " .. message
    end
    return nil, message
  end
  local ok, data = pcall(require("json").decode, response.body)
  if not ok or type(data) ~= "table" or not flutter.hex(data.sha, 40, 40) then
    return nil, "GitHub API returned invalid commit metadata (HTTP 200)"
  end
  if ref ~= "master" and data.sha:sub(1, #ref) ~= ref then
    return nil, "GitHub API returned a different commit than requested"
  end
  local date = type(data.commit) == "table"
      and type(data.commit.committer) == "table"
      and data.commit.committer.date
    or nil
  return data.sha, nil, type(date) == "string" and date or nil
end

local function cache_path(short)
  if short ~= "master" and not require("flutter").hex(short, 7, 40) then
    require("flutter").fail("invalid commit cache key")
  end
  if not RUNTIME.cacheDirPath then
    return nil
  end
  return require("file").join_path(RUNTIME.cacheDirPath, "commit-" .. short .. ".json")
end

function M.forget_master()
  local path = cache_path("master")
  if path then
    os.remove(path)
  end
end

function M.cache_sha(short, full)
  if
    not require("flutter").hex(full, 40, 40)
    or (short ~= "master" and full:sub(1, #short) ~= short)
  then
    require("flutter").fail("invalid resolved commit")
  end
  local path = cache_path(short)
  if path then
    require("flutter").write_json(path, { sha = full })
  end
end

function M.cached_sha(short)
  local path = cache_path(short)
  local data = path and require("flutter").read_json(path)
  if
    data
    and require("flutter").hex(data.sha, 40, 40)
    and (short == "master" or data.sha:sub(1, #short) == short)
  then
    return data.sha
  end
end

function M.resolve_full_sha(short)
  if require("flutter").hex(short, 40, 40) then
    return short
  end
  local cached = short ~= "master" and M.cached_sha(short)
  if cached then
    return cached
  end
  local full, err = M.try_resolve(short)
  if not full then
    require("flutter").fail(err)
  end
  M.cache_sha(short, full)
  return full
end

function M.resolve_snapshot(request)
  if not request.timestamp then
    return M.resolve_full_sha(request.sha)
  end
  -- Validate the ordering prefix against GitHub, never a user-invented date.
  local sha, err, date = M.try_resolve(request.sha)
  if not sha then
    require("flutter").fail(err)
  end
  if require("requests").snapshot_stamp(date) ~= request.timestamp then
    require("flutter").fail("main snapshot timestamp does not match its commit")
  end
  M.cache_sha(request.sha, sha)
  return sha
end

function M.ensure_available(root)
  local ok = pcall(require("cmd").exec, "git --version", { cwd = root, timeout = 30 })
  if not ok then
    require("flutter").fail(
      "git is required for main and commit installs; install Git and retry, or use stable/beta"
    )
  end
end

function M.head(root)
  return require("flutter").trim(
    require("cmd").exec("git rev-parse HEAD", { cwd = root, timeout = 30 })
  )
end

function M.remote_head(root)
  M.ensure_available(root)
  local output = require("cmd").exec(
    "git ls-remote " .. require("flutter").REPO_URL .. " refs/heads/master",
    { cwd = root, timeout = 1800 }
  )
  local sha = output:match("^([0-9a-f]+)%s")
  if not require("flutter").hex(sha, 40, 40) then
    require("flutter").fail("cannot resolve flutter/flutter master HEAD")
  end
  return sha
end

function M.checkout(root, full_sha, options)
  local flutter, cmd = require("flutter"), require("cmd")
  if not flutter.hex(full_sha, 40, 40) then
    flutter.fail("invalid full Git commit")
  end
  M.ensure_available(root)
  local exec_options = { cwd = root, timeout = 1800, env = { GIT_TERMINAL_PROMPT = "0" } }
  cmd.exec("git init", exec_options)
  local ok = pcall(cmd.exec, "git remote set-url origin " .. flutter.REPO_URL, exec_options)
  if not ok then
    cmd.exec("git remote add origin " .. flutter.REPO_URL, exec_options)
  end
  -- A repair of an existing pinned checkout should not need the network.
  local has_head, actual = pcall(M.head, root)
  if not has_head or actual ~= full_sha then
    local fetched = pcall(cmd.exec, "git fetch --depth 1 origin " .. full_sha, exec_options)
    if not fetched then
      flutter.fail(
        "git fetch failed for " .. full_sha .. "; the commit must be reachable in flutter/flutter"
      )
    end
    local checkout = options and options.branch == "master" and "git checkout -B master FETCH_HEAD"
      or "git checkout --detach FETCH_HEAD"
    cmd.exec(checkout, exec_options)
  end
  actual = M.head(root)
  if actual ~= full_sha then
    flutter.fail("checkout is at " .. actual .. ", expected " .. full_sha)
  end
end

return M
