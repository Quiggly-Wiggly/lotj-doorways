-- Compile a complete mapper route, then send its commands in one burst.
-- Subsequent room updates only track arrivals and support mapper recording.
local D = lotjDoorways
local W = {active=nil, executing=false, hook=nil}
D.walker = W

local function denseLength(value)
  if type(value) ~= "table" then return end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return end
    count = count + 1
  end
  for i = 1, count do if value[i] == nil then return end end
  return count
end

local function fullDirection(direction)
  for _, item in ipairs(D.directions) do
    if item.short == direction then return item.long end
  end
end

local function resolveStep(source, target, command)
  if type(command) ~= "string" or command == "" or command:find("[%z\r\n]") then
    return nil, "The map route contains an invalid command."
  end
  local valid, err = D.validateTransport({command})
  if not valid then return nil, err end
  if target == source then return nil, "The map route contains an exit back to the same room." end
  if type(roomLocked) == "function" and roomLocked(tonumber(target)) then
    return nil, "Room " .. target .. " is locked on the map."
  end
  if type(getRoomExits) ~= "function" then return nil, "Mudlet's map exit API is unavailable." end
  local exits = getRoomExits(tonumber(source)) or {}
  local direction = D.normalizeDirection(command)
  local long = direction and fullDirection(direction) or command
  if (direction or command == "in" or command == "out")
      and D.normalizeVnum(exits[long]) == target then
    if type(hasExitLock) == "function" and hasExitLock(tonumber(source), long) then
      return nil, "The " .. long .. " exit from room " .. source .. " is locked on the map."
    end
    return {source=source, destination=target, command=command,
      direction=direction, kind="normal"}
  end
  if type(getSpecialExits) == "function" then
    local special = getSpecialExits(tonumber(source), true) or {}
    local commands = special[tonumber(target)]
    if type(commands) == "table" and commands[command] == "0" then
      return {source=source, destination=target, command=command, kind="special"}
    end
  end
  return nil, "The map exit from room " .. source .. " to " .. target .. " is missing or locked."
end

function W.stop(reason, silent)
  local route = W.active
  if not route then return false end
  W.active = nil
  if route.timer then killTimer(route.timer) end
  if not silent then
    local prefix = route.dispatched and "Map-walk tracking stopped: " or "Map walk cancelled: "
    D.notify(prefix .. (reason or "cancelled.")
      .. (route.dispatched and " Commands already sent cannot be recalled." or ""))
  end
  return true
end

local function trackExpiry(route)
  if route.timer then killTimer(route.timer) end
  route.timer = tempTimer(5, function()
    if W.active ~= route or route.index > #route.steps then return end
    W.stop("no progress was confirmed within five seconds.")
    D.adoptGmcpRoom()
    D.refresh()
  end)
end

local function queueSnapshot(mapper)
  local queue, copy = mapper.lastMoveDirs, {}
  for i, item in ipairs(queue or {}) do copy[i] = item end
  return queue, copy
end

local function takeSentDirection(route, command, previous, prefix)
  local direction = D.normalizeDirection(command)
  if not direction then return end
  local queue = route.mapper.lastMoveDirs
  -- dirObj returns shared canonical tables. Identify our append by its position
  -- and unchanged prefix, never by table identity alone. Other packages' queue
  -- entries must remain intact, including repeated copies of the same direction.
  if queue == nil and previous == nil then return end
  if type(queue) ~= "table" then route.recording = false; return end
  if previous and queue ~= previous then route.recording = false; return end
  for i, item in ipairs(prefix) do
    if queue[i] ~= item then route.recording = false; return end
  end
  if #queue == #prefix then return end -- recording is currently off
  local entry = queue[#prefix + 1]
  if #queue ~= #prefix + 1 or type(entry) ~= "table"
      or (entry.short ~= direction and entry.long ~= fullDirection(direction)) then
    route.recording = false
    return
  end
  table.remove(queue, #prefix + 1)
end

-- Called by the mapper adapter immediately before its original room handler.
-- Holding future directions out of the mapper queue prevents its reverse-exit
-- heuristic from consuming the rest of a burst at a voice or one-way door.
function W.processMapperRoom(mapper, current, last, fresh)
  local route = W.active
  if not route or not route.dispatched or route.mapper ~= mapper then return false end
  local step = route.steps[route.mapperIndex]
  local source = step and step.source or route.destination
  if current == source and last == current and fresh == current then return true end
  if not step or current ~= step.destination or last ~= step.source or fresh ~= current then
    W.stop("the mapper reported an unexpected room transition.")
    return false
  end
  route.mapperIndex = route.mapperIndex + 1
  if route.recording and step.direction and mapper.mappingArea ~= nil
      and (not mapper.lastMoveDirs or next(mapper.lastMoveDirs) == nil) then
    mapper.handleSentCommand("sysDataSendRequest", step.direction)
  end
  return false
end

function W.dispatch(route)
  if W.active ~= route then return end
  if not D.running or not D.isEnabled() then W.stop("doorways are disabled."); return end
  if not (lotj and lotj.mapper == route.mapper) then W.stop("the mapper changed."); return end
  local room = D.getRoom()
  if not room or D.state.pending or room.vnum ~= route.steps[1].source then
    W.stop("room location changed before the stack was sent.")
    return
  end
  -- This is the only deferred send. Validate the entire frozen stack again
  -- before dispatch, so a local setting/map change cannot cause a partial walk.
  for _, step in ipairs(route.steps) do
    local current, err = resolveStep(step.source, step.destination, step.command)
    if not current or current.kind ~= step.kind or current.direction ~= step.direction then
      W.stop(err or "the map changed before the stack was sent."); return
    end
  end
  local valid, err = D.validateTransport(route.commands)
  if not valid then W.stop(err); return end
  route.dispatched = true
  D.state.known, D.state.uncertain = false, false
  W.executing = true
  D.state.sending = D.state.sending + 1
  local ok, problem = pcall(function()
    for _, command in ipairs(route.commands) do
      if W.active ~= route or not D.running or not D.isEnabled() then break end
      if not (lotj and lotj.mapper == route.mapper) then W.stop("the mapper changed."); break end
      local previous, prefix = queueSnapshot(route.mapper)
      -- No alias expansion, separator concatenation, timers, or room waits.
      -- Preserve visible door actions without echoing bare directions twice.
      local sent, sendErr = pcall(send, command, D.normalizeDirection(command) == nil)
      takeSentDirection(route, command, previous, prefix)
      if not sent then error(sendErr, 0) end
      route.sentCount = route.sentCount + 1
    end
  end)
  D.state.sending = D.state.sending - 1
  W.executing = false
  if not ok then
    W.stop("sending failed: " .. tostring(problem))
    return nil, problem
  end
  if W.active == route then
    D.notify("Map walk: sent " .. route.sentCount .. " commands for " .. #route.steps .. " rooms.")
    trackExpiry(route)
  end
  D.refresh()
  return true
end

function W.start(directions, destinations)
  W.stop("replaced by a new destination.", true)
  if not (lotj and lotj.mapper) then
    local err = "The LotJ mapper is unavailable. Reload it before starting a map walk."
    D.notify(err, true)
    return nil, err
  end
  local room = D.getRoom()
  if not room or D.state.pending then
    local err = "Room unknown or movement still pending. Wait for room information before choosing a destination."
    D.notify(err, true)
    return nil, err
  end
  local count, pathCount = denseLength(directions), denseLength(destinations)
  if not count or count ~= pathCount then
    local err = "The mapper supplied an incomplete route. Choose the destination again."
    D.notify(err, true)
    return nil, err
  end
  if count == 0 then D.notify("Already at the map destination."); return true end
  local steps, commands, source = {}, {}, room.vnum
  -- Freeze every room, direction and saved replacement before sending ANY of
  -- them. Later getPath calls or rule edits cannot alter a dispatched stack.
  for i = 1, count do
    local target = D.normalizeVnum(destinations[i])
    local step, err
    if target then step, err = resolveStep(source, target, directions[i]) end
    if not step then
      err = err or "The map route contains an invalid destination room."
      D.notify("Cannot start map walk: " .. err, true)
      return nil, err
    end
    local rule = step.direction and D.getRule(source, step.direction)
    local selected, ruleErr
    if rule then
      selected, ruleErr = D.validateSteps(step.direction, rule.commands)
      if not selected then D.notify("Cannot start map walk: " .. ruleErr, true); return nil, ruleErr end
    else
      selected = {step.direction and step.command:lower() or step.command}
    end
    local valid, problem = D.validateTransport(selected)
    if not valid then D.notify("Cannot start map walk: " .. problem, true); return nil, problem end
    for _, command in ipairs(selected) do commands[#commands+1] = command end
    steps[i], source = step, target
  end
  local route = {steps=steps, commands=commands, index=1, mapperIndex=1,
    destination=source, mapper=lotj.mapper, recording=true, sentCount=0}
  W.active = route
  -- A route can start inside a GMCP listener. Let that one event finish, then
  -- send the WHOLE stack in one callback; arrivals never send further commands.
  D.defer(function() W.dispatch(route) end)
  return true
end

function W.onRoomInfo(vnum, route)
  if not route or W.active ~= route or not route.dispatched then return end
  if not (lotj and lotj.mapper == route.mapper) then W.stop("the mapper changed."); return end
  vnum = D.normalizeVnum(vnum)
  local step = route.steps[route.index]
  if not step then
    if vnum ~= route.destination then W.stop("arrived beyond the expected destination.") end
    return
  end
  if vnum == step.source then D.state.known = false; return end
  if vnum ~= step.destination then
    W.stop("arrived in room " .. tostring(vnum or "unknown") .. ", expected " .. step.destination .. ".")
    return
  end
  route.index = route.index + 1
  D.state.known = route.index > #route.steps
  if D.state.known then
    if route.timer then killTimer(route.timer); route.timer = nil end
    -- Keep passive mapper context through the last event's other listeners.
    D.defer(function()
      if W.active ~= route then return end
      W.stop(nil, true)
      D.notify("Map walk complete.")
      D.refresh()
    end)
  else
    trackExpiry(route)
  end
end

function W.detach()
  W.stop("mapper integration removed.", true)
  if W.hook and doSpeedWalk == W.hook.wrapper then doSpeedWalk = W.hook.original end
  W.hook = nil
end

function W.attach()
  if not (lotj and lotj.mapper) then W.detach(); return end
  if W.hook and doSpeedWalk == W.hook.wrapper then return end
  W.detach()
  if type(doSpeedWalk) ~= "function" then return end
  local original = doSpeedWalk
  local wrapper = function(...)
    if not (lotj and lotj.mapper) then
      W.stop("the LotJ mapper is unavailable.")
      D.notify("The LotJ mapper is unavailable. Reload it before starting a map walk.", true)
      return nil
    end
    if not D.running or not D.isEnabled() then return original(...) end
    return W.start(speedWalkDir, speedWalkPath)
  end
  W.hook = {original=original, wrapper=wrapper}
  doSpeedWalk = wrapper
end
