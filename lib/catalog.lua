local M = {}

function M.list()
  local releases = require("releases")
  local index = releases.load()
  local result, seen = {}, {}
  for _, channel in ipairs({ "stable", "beta" }) do
    local entry = releases.channel_entry(index, channel, true)
    if entry then
      table.insert(result, { version = channel, rolling = true, checksum = entry.sha256 })
    end
  end
  local sha, err, date = require("git").try_resolve("master")
  local stamp = require("requests").snapshot_stamp(date)
  if sha and stamp then
    -- mise orders versions, not commit dates; prefix the SHA with UTC commit time.
    -- Do not attach created_at: main is a moving branch, not a release. A
    -- release-age cooldown would hide the newest commit by default and make
    -- `flutter@main` fall back to a bare `main` directory. The timestamp prefix
    -- already gives ordering without applying a release cooldown.
    table.insert(result, { version = "main-" .. stamp .. "-" .. sha:sub(1, 12) })
  else
    require("log").warn("main snapshot unavailable; stable and beta are still available")
    require("log").debug(err or "GitHub API returned no valid UTC commit date")
  end
  for _, entry in ipairs(index.releases) do
    if
      type(entry) == "table"
      and (entry.channel == "stable" or entry.channel == "beta")
      and require("flutter").valid_version(entry.version)
      and not seen[entry.version]
    then
      seen[entry.version] = true
      local selected = releases.exact_entry(index, entry.version, true)
      if selected then
        table.insert(result, { version = selected.version, created_at = selected.release_date })
      end
    end
  end
  return result
end

return M
