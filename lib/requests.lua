local M = {}

function M.snapshot_stamp(date)
  if type(date) ~= "string" then
    return nil
  end
  local y, m, d, h, min, s = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$")
  if not y then
    return nil
  end
  local year, month, day = tonumber(y), tonumber(m), tonumber(d)
  local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  if year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) then
    days[2] = 29
  end
  if
    year < 1970
    or not days[month]
    or day < 1
    or day > days[month]
    or tonumber(h) > 23
    or tonumber(min) > 59
    or tonumber(s) > 59
  then
    return nil
  end
  return y .. m .. d .. h .. min .. s
end

function M.classify(version)
  local flutter = require("flutter")
  if type(version) ~= "string" then
    flutter.fail("version must be a string")
  end
  local raw = flutter.trim(version)
  if raw == "dev" then
    flutter.fail("the dev channel is obsolete; use main or beta")
  end
  if raw == "stable" or raw == "beta" then
    return { kind = "channel", channel = raw, raw = raw }
  end
  if raw == "main" then
    return { kind = "main", channel = "main", raw = raw }
  end
  local prefix, sha = raw:match("^(%a+)%-(.+)$")
  if prefix == "git" or prefix == "main" then
    sha = sha:lower()
    local min, max, stamp = 7, 40, nil
    if prefix == "main" then
      min, max = 12, 12
      local date, commit = sha:match("^(%d+)%-(%x+)$")
      if date then
        local iso = date:gsub("^(%d%d%d%d)(%d%d)(%d%d)(%d%d)(%d%d)(%d%d)$", "%1-%2-%3T%4:%5:%6Z")
        stamp = M.snapshot_stamp(iso)
        if not stamp then
          flutter.fail("main snapshot requires a valid UTC timestamp (YYYYMMDDHHMMSS)")
        end
        sha = commit
      end
    end
    if not flutter.hex(sha, min, max) then
      flutter.fail(prefix .. " requires " .. min .. ".." .. max .. " hexadecimal commit characters")
    end
    return {
      kind = prefix == "git" and "commit" or "snapshot",
      channel = prefix == "main" and "main" or nil,
      sha = sha,
      short = sha,
      timestamp = stamp,
      raw = prefix .. "-" .. (stamp and stamp .. "-" or "") .. sha,
    }
  end
  if not flutter.valid_version(raw) then
    flutter.fail("invalid Flutter version request")
  end
  return { kind = "exact", raw = raw }
end

function M.is_main_snapshot(version)
  return M.classify(version).kind == "snapshot"
end

function M.is_commit(version)
  local kind = M.classify(version).kind
  return kind == "commit" or kind == "snapshot" or kind == "main"
end

return M
