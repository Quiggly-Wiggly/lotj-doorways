-- LotJ Doorways: data, validation, commands, and room-aware movement.
-- Reloads replace the namespace only after detaching the previous instance.
local blockedGmcp = lotjDoorways and lotjDoorways.state and lotjDoorways.state.gmcpBlocked
if lotjDoorways and lotjDoorways.shutdown then lotjDoorways.shutdown() end
lotjDoorways = { version = "1.3.2", packageName = "lotj-doorways" }
local D = lotjDoorways
D.directions = {
  {short="n", long="north"}, {short="ne", long="northeast"},
  {short="e", long="east"}, {short="se", long="southeast"},
  {short="s", long="south"}, {short="sw", long="southwest"},
  {short="w", long="west"}, {short="nw", long="northwest"},
  {short="u", long="up"}, {short="d", long="down"},
}
D.state = { known=false, generation=0, sending=0, enabled=true, gmcpBlocked=blockedGmcp == true }
D.rules = {}

function D.trim(value)
  return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end

function D.normalizeDirection(value)
  local text = D.trim(value):lower()
  for _, dir in ipairs(D.directions) do
    if text == dir.short or text == dir.long then return dir.short end
  end
end

function D.normalizeVnum(value)
  if type(value) == "number" then
    if value ~= value or value <= 0 or value > 9007199254740991 or value % 1 ~= 0 then return end
    return string.format("%.0f", value)
  end
  if type(value) ~= "string" or not value:match("^%d+$") then return end
  local trimmed = value:gsub("^0+", "")
  if trimmed == "" or #trimmed > 16 then return end
  return D.normalizeVnum(tonumber(trimmed))
end

local function copyRule(rule)
  if not rule then return end
  local result = {vnum=rule.vnum, name=rule.name, direction=rule.direction, commands={}}
  for i, cmd in ipairs(rule.commands) do result.commands[i] = cmd end
  return result
end

local consoleColors = {
  heading = {255, 185, 0}, command = {0, 225, 235},
  text = {235, 235, 235}, muted = {150, 150, 150}, error = {255, 110, 100},
}

local function plainFormat()
  -- echo inherits the console's current attributes, including underline from
  -- earlier game output. Reset explicitly so our help never inherits them.
  resetFormat()
  setUnderline(false)
  setBold(false)
  setItalics(false)
end

local function consoleText(color, text)
  setFgColor(unpack(consoleColors[color]))
  -- Keep commands, angle-bracket placeholders, and room names as literal text.
  -- Passing them through a color-tag parser could reinterpret player content.
  echo(tostring(text))
end

local function consoleRows(rows)
  local width = 0
  for _, row in ipairs(rows) do width = math.max(width, #row[1]) end
  for _, row in ipairs(rows) do
    consoleText("command", row[1])
    consoleText("muted", string.rep(" ", width - #row[1] + 2) .. "- ")
    consoleText("text", row[2] .. "\n")
  end
end

function D.notify(message, isError)
  plainFormat()
  consoleText(isError and "error" or "heading", "[Doorways] ")
  consoleText(isError and "error" or "text", tostring(message) .. "\n")
  plainFormat()
end

function D.printHelp()
  plainFormat()
  consoleText("heading", "\nLOTJ DOORWAYS v" .. D.version .. "\n")

  consoleRows({
    {"setdoorway <dir> <command>", "Save or replace a doorway here"},
    {"doorway append <dir> <command>", "Add the next command to a saved doorway"},
    {"doorway remove <dir>", "Remove a saved doorway here"},
    {"doorway list [all]", "List this room's doorways, or all saved rooms"},
    {"doorway ui", "Open the doorway editor"},
    {"doorway raw <dir>", "Move once without using saved commands"},
    {"doorway stop", "Clear map-walk tracking (sent commands remain)"},
    {"doorway on / doorway off", "Enable or disable saved doorways"},
    {"doorway help", "Show this help menu"},
  })
  consoleText("muted", "\nExample: setdoorway ne open ne, then doorway append ne ne\n")
  consoleText("muted", "Type those as separate lines. Use ;; only in doorway ui.\n")
  consoleText("muted", "No custom mapper needed. Stop cannot recall sent commands.\n")
  plainFormat()
end

function D.refresh()
  if D.ui and D.ui.refresh then D.ui.refresh() end
end

local function arrayLength(value)
  if type(value) ~= "table" then return end
  local count = 0
  for k in pairs(value) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return end
    count = count + 1
  end
  for i = 1, count do if value[i] == nil then return end end
  return count
end

function D.validateSteps(direction, steps)
  direction = D.normalizeDirection(direction)
  if not direction then return nil, "Choose one of the ten movement directions." end
  local count = arrayLength(steps)
  if not count or count == 0 then return nil, "Enter at least one game command." end
  local result, movement = {}, false
  for i = 1, count do
    local text = steps[i]
    if type(text) ~= "string" or text:find("[%z\r\n]") then
      return nil, "Each step must be one line of game text."
    end
    text = D.trim(text)
    if text == "" then return nil, "Empty command steps are not allowed." end
    if text:find(";;", 1, true) then return nil, "Use separate steps for each command." end
    local bare = D.normalizeDirection(text)
    if bare then
      if movement or bare ~= direction or i ~= count then
        return nil, "A bare direction must match the rule and be its final, only movement step."
      end
      movement = true
      text = text:lower() -- The standard LotJ mapper recognizes lowercase directions.
    end
    result[i] = text
  end
  return result
end

function D.validateTransport(steps)
  local separator = getCommandSeparator and getCommandSeparator() or ";;"
  if type(separator) == "string" and separator ~= "" then
    for _, command in ipairs(steps) do
      if command:find(separator, 1, true) then
        return nil, "A step contains Mudlet's active command separator. Use separate steps; the separator would split the command before sending."
      end
    end
  end
  return true
end

function D.parseSequence(text)
  if type(text) ~= "string" then return nil, "Enter a command sequence." end
  local steps, start = {}, 1
  while true do
    local pos = text:find(";;", start, true)
    local step = D.trim(text:sub(start, pos and pos - 1 or #text))
    if step == "" then return nil, "Empty command steps are not allowed." end
    if step:find("[%z\r\n]") then return nil, "Use ;; between single-line commands." end
    steps[#steps+1] = step
    if not pos then break end
    start = pos + 2
  end
  return steps
end

-- Setup reads the game's room data, independently of an outstanding crossing.
-- A blocked exit does not remove the vnum. Darkness/disconnect do invalidate
-- cached GMCP until the game supplies another valid room update.
function D.getGmcpRoom()
  if D.state.gmcpBlocked then return end
  local info = gmcp and gmcp.Room and gmcp.Room.Info
  local vnum = type(info) == "table" and D.normalizeVnum(info.vnum)
  if vnum then return {vnum=vnum, name=type(info.name)=="string" and info.name or ""} end
end

function D.adoptGmcpRoom()
  local room = D.getGmcpRoom()
  D.state.room, D.state.known = room, room ~= nil
  return room
end

-- Automatic movement still requires the previous crossing to have resolved.
function D.getRoom()
  if D.state.known and D.state.room then
    return {vnum=D.state.room.vnum, name=D.state.room.name}
  end
end

function D.getRule(vnum, direction)
  vnum, direction = D.normalizeVnum(vnum), D.normalizeDirection(direction)
  return copyRule(vnum and direction and D.rules[vnum] and D.rules[vnum][direction])
end

function D.listRules(all)
  local result, room = {}, D.getGmcpRoom()
  for vnum, rules in pairs(D.rules) do
    if all or (room and room.vnum == vnum) then
      for _, rule in pairs(rules) do result[#result+1] = copyRule(rule) end
    end
  end
  table.sort(result, function(a, b)
    if a.vnum ~= b.vnum then return tonumber(a.vnum) < tonumber(b.vnum) end
    return a.direction < b.direction
  end)
  return result
end

local function record(rules, enabled)
  local data = {version=1, enabled=enabled, rules={}}
  for _, roomRules in pairs(rules) do
    for _, rule in pairs(roomRules) do data.rules[#data.rules+1] = copyRule(rule) end
  end
  table.sort(data.rules, function(a,b)
    if a.vnum ~= b.vnum then return tonumber(a.vnum) < tonumber(b.vnum) end
    return a.direction < b.direction
  end)
  return data
end

function D.exportData() return record(D.rules, D.state.enabled) end

-- Both the profile file and map metadata use the same validated format.
function D.decodeData(text)
  local ok, data = pcall(yajl.to_value, text)
  if not ok or type(data) ~= "table" or data.version ~= 1 or type(data.enabled) ~= "boolean" or not arrayLength(data.rules) then
    return nil, nil, "invalid or unsupported JSON data"
  end
  local loaded = {}
  for _, rule in ipairs(data.rules) do
    local vnum = type(rule) == "table" and D.normalizeVnum(rule.vnum)
    local dir = type(rule) == "table" and D.normalizeDirection(rule.direction)
    local steps = dir and D.validateSteps(dir, rule.commands)
    if not vnum or not steps or type(rule.name) ~= "string" or (loaded[vnum] and loaded[vnum][dir]) then
      return nil, nil, "invalid or duplicate saved rule"
    end
    loaded[vnum] = loaded[vnum] or {}
    loaded[vnum][dir] = {vnum=vnum, name=rule.name, direction=dir, commands=steps}
  end
  return loaded, data.enabled
end

function D.storagePath()
  return getMudletHomeDir() .. "/lotj-doorways.json"
end

function D.save(data)
  if D.storageBlocked then return nil, D.storageBlocked end
  local ok, json = pcall(yajl.to_string, data or record(D.rules, D.state.enabled))
  if not ok then return nil, "Could not encode saved rules: " .. tostring(json) end
  local path = D.storagePath()
  local file, err = io.open(path .. ".tmp", "w")
  if not file then return nil, "Could not save rules: " .. tostring(err) end
  local wrote, writeErr = file:write(json)
  local closed, closeErr = file:close()
  if not wrote or not closed then
    os.remove(path .. ".tmp")
    return nil, "Could not finish saving rules: " .. tostring(writeErr or closeErr)
  end
  local renamed, renameErr = os.rename(path .. ".tmp", path)
  if not renamed then
    -- Some Windows runtimes do not replace an existing file with rename().
    -- Keep a backup and roll back if installing the completed new file fails.
    local old = io.open(path, "r")
    if old then
      old:close()
      local backup = path .. ".bak"
      local prior = io.open(backup, "r")
      if prior then prior:close() else
        local moved = os.rename(path, backup)
        if moved then
          renamed, renameErr = os.rename(path .. ".tmp", path)
          if renamed then os.remove(backup) else os.rename(backup, path) end
        end
      end
    end
  end
  if not renamed then
    os.remove(path .. ".tmp")
    return nil, "Could not replace saved rules; previous data retained: " .. tostring(renameErr)
  end
  D.storageExists = true
  return true
end

function D.load()
  D.rules, D.state.enabled, D.storageBlocked = {}, true, nil
  D.storageExists = false
  local path = D.storagePath()
  local file, err, code = io.open(path, "r")
  if not file then
    if code == 2 then
      local backup = io.open(path .. ".bak", "r")
      if backup then
        backup:close()
        D.storageBlocked = "An interrupted save left a backup at " .. path .. ".bak. Restore it to " .. path .. " and reload; the backup is preserved."
        D.state.enabled = false
        return nil, D.storageBlocked
      end
      return true
    end
    D.storageBlocked = "Cannot read " .. path .. ": " .. tostring(err)
    return nil, D.storageBlocked
  end
  local text = file:read("*a")
  file:close()
  local loaded, enabled, problem = D.decodeData(text)
  if loaded then
    D.rules, D.state.enabled, D.storageExists = loaded, enabled, true
    return true
  end
  D.storageBlocked = "Saved rules contain " .. problem .. ". File preserved at " .. path .. "; repair or move it aside, then reload the package."
  D.state.enabled = false
  return nil, D.storageBlocked
end

local function proposedRules()
  local result = {}
  for vnum, roomRules in pairs(D.rules) do
    result[vnum] = {}
    for dir, rule in pairs(roomRules) do result[vnum][dir] = copyRule(rule) end
  end
  return result
end

function D.setRule(vnum, name, direction, steps)
  vnum, direction = D.normalizeVnum(vnum), D.normalizeDirection(direction)
  if not vnum then return nil, "A valid GMCP room vnum is required." end
  local commands, err = D.validateSteps(direction, steps)
  if not commands then return nil, err end
  local valid, transportErr = D.validateTransport(commands)
  if not valid then return nil, transportErr end
  local updated = proposedRules()
  updated[vnum] = updated[vnum] or {}
  updated[vnum][direction] = {vnum=vnum, name=type(name)=="string" and name or "", direction=direction, commands=commands}
  local ok, saveErr = D.save(record(updated, D.state.enabled))
  if not ok then return nil, saveErr end
  D.rules = updated
  -- Explicitly configuring the current room starts a new manual attempt. A
  -- failed door may not match any known failure text, leaving a pending flag;
  -- do not let that old attempt suppress the rule the player just saved.
  -- Cancel its route/hint instead of interpreting the edit as an arrival.
  local current = D.getGmcpRoom()
  if current and current.vnum == vnum then
    if D.walker then D.walker.stop("the current room's doorway was edited.") end
    D.clearPending()
    D.state.uncertain = false
    D.adoptGmcpRoom()
  end
  if D.mapStorage then D.mapStorage.sync() end
  D.refresh()
  return true
end

function D.removeRule(vnum, direction)
  vnum, direction = D.normalizeVnum(vnum), D.normalizeDirection(direction)
  if not vnum or not direction or not D.rules[vnum] or not D.rules[vnum][direction] then
    return nil, "No saved rule exists for that room and direction."
  end
  local updated = proposedRules()
  updated[vnum][direction] = nil
  if not next(updated[vnum]) then updated[vnum] = nil end
  local ok, err = D.save(record(updated, D.state.enabled))
  if not ok then return nil, err end
  D.rules = updated
  if D.mapStorage then D.mapStorage.sync() end
  D.refresh()
  return true
end

function D.isEnabled() return D.state.enabled end

function D.clearPending()
  D.state.generation = D.state.generation + 1
  if D.state.pending and D.state.pending.timer then killTimer(D.state.pending.timer) end
  D.state.pending = nil
end

function D.setEnabled(enabled)
  enabled = enabled == true
  if not enabled then
    if D.walker then D.walker.stop("doorways were disabled.") end
    if D.state.pending then D.state.known = false end
    D.clearPending()
    D.state.enabled = false -- "off" always takes effect for this session.
  end
  local ok, err = D.save(record(D.rules, enabled))
  if ok then
    D.state.enabled = enabled
    if D.mapStorage then D.mapStorage.sync() end
  end
  D.refresh()
  return ok, err
end

local function beginCrossing(source, direction, hint, managed)
  D.clearPending()
  D.state.known = false
  if not source then D.state.uncertain = true; return end
  local pending = {source=source, direction=direction, hint=hint, managed=managed, generation=D.state.generation}
  D.state.pending = pending
  pending.timer = tempTimer(5, function()
    if D.state.pending ~= pending then return end
    if D.walker then D.walker.stop("no room change was confirmed within five seconds.") end
    D.clearPending()
    -- Expiry ends this attempt; it never retries or advances a route. Keep
    -- the game's last reported room usable for the player's next command.
    if not D.state.uncertain then D.adoptGmcpRoom() end
    D.refresh()
  end)
end

local function sendSteps(steps)
  D.state.sending = D.state.sending + 1
  local ok, err = pcall(function()
    for _, command in ipairs(steps) do
      -- Mudlet already echoes the typed direction before expanding its alias.
      -- Hide our forwarded direction; keep actual door actions visible.
      send(command, D.normalizeDirection(command) == nil)
    end
  end)
  D.state.sending = D.state.sending - 1
  if not ok then
    D.clearPending()
    D.state.known = false
    D.notify("Sending stopped: " .. tostring(err), true)
  end
  D.refresh()
  return ok, err
end

function D.raw(direction)
  local dir = D.normalizeDirection(direction)
  if not dir then return nil, "Unknown movement direction." end
  if D.walker and not D.walker.executing then D.walker.stop("manual movement.") end
  local source = D.getRoom()
  beginCrossing(source, dir, false, D.walker and D.walker.executing)
  return sendSteps({D.trim(direction):lower()})
end

function D.move(direction)
  local dir = D.normalizeDirection(direction)
  if not dir then return nil, "Unknown movement direction." end
  if D.walker and not D.walker.executing then D.walker.stop("manual movement.") end
  local room = D.getRoom()
  local rule = room and not D.state.pending and D.state.enabled and D.getRule(room.vnum, dir)
  if not rule then return D.raw(direction) end
  local valid, err = D.validateTransport(rule.commands)
  if not valid then
    D.notify("Rule skipped: " .. err, true)
    return D.raw(direction)
  end
  local hasDirection = D.normalizeDirection(rule.commands[#rule.commands]) ~= nil
  beginCrossing(room, dir, not hasDirection, true)
  D.notify(dir .. " → " .. table.concat(rule.commands, ";;"))
  return sendSteps(rule.commands)
end

function D.onSend(_, command)
  if D.state.sending > 0 then return end
  if D.walker then D.walker.stop("another command was sent.") end
  local dir, source = D.normalizeDirection(command), D.getRoom()
  if D.state.pending then
    D.clearPending()
    D.state.known = false
    D.state.uncertain = true
  elseif dir then
    beginCrossing(source, dir, false)
  end
  D.refresh()
end

function D.onRoomInfo()
  local info = gmcp and gmcp.Room and gmcp.Room.Info
  local vnum = info and D.normalizeVnum(info.vnum)
  if not vnum then
    if D.walker then D.walker.stop("room location is unknown.") end
    D.clearPending()
    D.state.known = false
    D.state.gmcpBlocked = true
    D.refresh()
    return
  end
  local room = {vnum=vnum, name=type(info.name)=="string" and info.name or ""}
  local pending = D.state.pending
  D.state.gmcpBlocked, D.state.uncertain = false, false
  D.state.room = room
  D.state.known = not pending or pending.source.vnum ~= vnum
  if pending and pending.source.vnum ~= vnum then
    -- Mapper and helper GMCP listeners may run in either order. Leave the hint
    -- alive until all listeners have had a chance to process this transition.
    D.defer(function()
      if D.state.pending == pending then D.clearPending() end
    end)
  end
  local route = D.walker and D.walker.active
  if route then
    -- Stack walking only observes arrivals. Process each event immediately so
    -- batched GMCP updates cannot overwrite an intermediate room; no sends here.
    D.walker.onRoomInfo(vnum, route)
  end
  D.refresh()
end

function D.onFailure()
  if D.walker then D.walker.stop("movement failed.") end
  D.clearPending()
  if not D.state.uncertain then D.adoptGmcpRoom() end
  D.refresh()
end

function D.onDark()
  D.state.gmcpBlocked = true
  D.state.known = false
  if D.walker then D.walker.stop("the room is no longer visible.") end
  D.clearPending()
  D.refresh()
end
function D.onDisconnect()
  if D.walker then D.walker.stop("connection changed.") end
  D.clearPending()
  D.state.room, D.state.known, D.state.gmcpBlocked = nil, false, true
  D.refresh()
end

function D.command(input)
  local action, rest = D.trim(input):match("^(%S+)%s*(.*)$")
  action = action and action:lower() or "help"
  if action == "help" then
    D.printHelp()
    return true
  elseif action == "ui" and rest == "" then
    if D.ui then D.ui.open() end
    return true
  elseif action == "stop" and rest == "" then
    if not (D.walker and D.walker.stop("cancelled by you.")) then D.notify("No map walk is running.") end
    return true
  elseif (action == "on" or action == "off") and rest == "" then
    local ok, err = D.setEnabled(action == "on")
    D.notify(ok and ("Replacements " .. (D.isEnabled() and "enabled." or "disabled.")) or err, not ok)
    return ok, err
  elseif action == "raw" then
    local ok, err = D.raw(rest)
    if not ok then D.notify(err, true) end
    return ok, err
  elseif action == "list" and (rest == "" or rest == "all") then
    local rules = D.listRules(rest == "all")
    if #rules == 0 then D.notify("No saved rules" .. (rest == "all" and "." or " for the current GMCP room.")) end
    for _, rule in ipairs(rules) do
      D.notify("[" .. rule.vnum .. "] " .. rule.name .. " / " .. rule.direction .. " → " .. table.concat(rule.commands, ";;"))
    end
    return true
  elseif action == "set" or action == "append" or action == "remove" then
    local direction, text = rest:match("^(%S+)%s*(.*)$")
    local dir, room = D.normalizeDirection(direction), D.getGmcpRoom()
    if not dir then D.notify("Choose a direction. See doorway help.", true); return nil end
    if not room then D.notify("No current GMCP room vnum is available. Wait for room information, or use look to request it.", true); return nil end
    local ok, err
    if action == "remove" and text == "" then
      ok, err = D.removeRule(room.vnum, dir)
    elseif action ~= "remove" then
      local steps = {}
      if action == "append" then
        local rule = D.getRule(room.vnum, dir)
        if not rule then D.notify("Create the rule with setdoorway first.", true); return nil end
        steps = rule.commands
      end
      steps[#steps+1] = text
      ok, err = D.setRule(room.vnum, room.name, dir, steps)
    else err = "Usage: doorway remove <direction>" end
    D.notify(ok and ("Rule " .. (action == "remove" and "removed" or "saved") .. " for room " .. room.vnum .. " / " .. dir .. ".") or err, not ok)
    return ok, err
  end
  D.notify("Unknown doorway command. See doorway help.", true)
  return nil, "Unknown door command."
end
