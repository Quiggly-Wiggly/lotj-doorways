-- Keep a portable copy in the map without creating rooms or changing exits.
-- The profile JSON remains authoritative, including an intentionally empty
-- library. Map userdata is written to disk by Mudlet's normal map saves.
local D = lotjDoorways
local M = {key="lotj-doorways.rules.v1", loading=false, lastError=nil}
D.mapStorage = M

local function report(message)
  if M.lastError ~= message then D.notify(message, true) end
  M.lastError = message
  return nil, message
end

local function readMap()
  if type(getMapUserData) ~= "function" then
    return nil, "Mudlet's map userdata API is unavailable."
  end
  local called, text = pcall(getMapUserData, M.key)
  if not called then return nil, tostring(text) end
  -- The native API returns nil plus a message when this key is absent.
  if text == nil then return nil end
  if type(text) ~= "string" then return nil, "The map copy is not a JSON string." end
  return text
end

function M.sync(data)
  if D.storageBlocked then return nil, D.storageBlocked end
  if M.loading or not D.storageExists then return true end
  local text, readErr = readMap()
  if readErr then
    return report("Rules are saved in this profile; the map copy could not be updated: " .. readErr)
  end
  local encoded, json = pcall(function() return yajl.to_string(data or D.exportData()) end)
  if not encoded then
    return report("Rules are saved in this profile; the map copy could not be encoded: " .. tostring(json))
  end
  if text ~= json then
    if text ~= nil then
      local called, rules, _, problem = pcall(D.decodeData, text)
      if not called or not rules then
        return report("Rules are saved in this profile; existing doorway map data was left unchanged: " .. tostring(called and problem or rules))
      end
    end
    if type(setMapUserData) ~= "function" then
      return report("Rules are saved in this profile; the map copy could not be updated: Mudlet's map userdata API is unavailable.")
    end
    local called, saved, err = pcall(setMapUserData, M.key, json)
    if not called or not saved then
      return report("Rules are saved in this profile; the map copy could not be updated: " .. tostring(called and (err or "map write failed") or saved))
    end
  end
  M.lastError = nil
  return true
end

local function recoveredData(rules, enabled)
  local data = {version=1, enabled=enabled, rules={}}
  for _, roomRules in pairs(rules) do
    for _, rule in pairs(roomRules) do data.rules[#data.rules+1] = rule end
  end
  table.sort(data.rules, function(a,b)
    if a.vnum ~= b.vnum then return tonumber(a.vnum) < tonumber(b.vnum) end
    return a.direction < b.direction
  end)
  return data
end

function M.load()
  if M.loading then return true end
  if D.storageBlocked then return nil, D.storageBlocked end
  -- Never revive an old map rule over a newer local edit or deletion.
  if D.storageExists then return M.sync() end
  local text, err = readMap()
  if err then return report("Could not read doorway rules from the map: " .. err) end
  if text == nil then M.lastError = nil; return true end
  local called, rules, enabled, problem = pcall(D.decodeData, text)
  if not called or not rules then
    return report("Doorway map data was left unchanged: " .. tostring(called and problem or rules))
  end
  -- Save the validated candidate before adopting it. A read/write problem must
  -- leave both the active library and the existing map copy recoverable.
  M.loading = true
  local savedCall, saved, saveErr = pcall(D.save, recoveredData(rules, enabled))
  M.loading = false
  if not savedCall or not saved then
    return report("Could not restore doorway rules to this profile; the map copy is preserved: " .. tostring(savedCall and saveErr or saved))
  end
  if D.walker then D.walker.stop("doorway rules were restored from the map.") end
  D.rules, D.state.enabled = rules, enabled
  D.storageExists = true
  D.refresh()
  local synced, syncErr = M.sync()
  if not synced then return nil, syncErr end
  D.notify("Doorway rules restored from this map to the current profile.")
  return true
end
