local M = {}

function M.archive_result(version, entry)
  require("releases").validate_entry(entry)
  return {
    version = version,
    url = require("flutter").archive_url(entry.archive),
    sha256 = entry.sha256,
  }
end

function M.pre_install(ctx)
  local request = require("requests").classify(ctx.version)
  local releases = require("releases")
  local index = releases.load()
  if request.kind == "channel" then
    return M.archive_result(ctx.version, releases.channel_entry(index, request.channel))
  end
  if request.kind == "exact" then
    return M.archive_result(ctx.version, releases.exact_entry(index, request.raw))
  end
  local git = require("git")
  if request.kind == "main" then
    local sha, err = git.try_resolve("master")
    if not sha then
      git.forget_master()
      require("log").warn(err .. "; PostInstall will resolve master with Git")
      return { version = ctx.version }
    end
    git.cache_sha("master", sha)
    request.sha = sha
  elseif request.kind == "snapshot" then
    request.sha = git.resolve_snapshot(request)
  else
    request.sha = git.resolve_full_sha(request.sha)
  end
  local entry = releases.find_hash(index, request.sha)
  if entry then
    return M.archive_result(ctx.version, entry)
  end
  return { version = ctx.version }
end

return M
