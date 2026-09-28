-- Mudlet lifecycle and the narrowly scoped optional LotJ mapper adapter.
local D = lotjDoorways
D.handles = {events={}, aliases={}, triggers={}, deferred={}}

function D.defer(callback)
  local id
  id = tempTimer(0, function()
    D.handles.deferred[id] = nil
    if D.running then callback() end
  end)
  D.handles.deferred[id] = true
  return id
end

function D.detachMapper()
  if D.walker then D.walker.detach() end
  local adapter = D.adapter
  if adapter and adapter.mapper.processCurrentRoom == adapter.wrapper then
    adapter.mapper.processCurrentRoom = adapter.original
  end
  D.adapter = nil
end

function D.attachMapper()
  local mapper = lotj and lotj.mapper
  if D.adapter and D.adapter.mapper == mapper and mapper.processCurrentRoom == D.adapter.wrapper then
    if D.walker then D.walker.attach() end
    return
  end
  D.detachMapper()
  if type(mapper) ~= "table" or type(mapper.processCurrentRoom) ~= "function" or type(mapper.handleSentCommand) ~= "function" then return end
  local original, recorder = mapper.processCurrentRoom, mapper.handleSentCommand
  local adapter = {mapper=mapper, original=original}
  adapter.wrapper = function(...)
    local pending = D.state.pending
    local last = mapper.last and D.normalizeVnum(mapper.last.vnum)
    local current = mapper.current and D.normalizeVnum(mapper.current.vnum)
    local info = gmcp and gmcp.Room and gmcp.Room.Info
    local fresh = info and D.normalizeVnum(info.vnum)
    if D.walker and D.walker.processMapperRoom(mapper, current, last, fresh) then return end
    if D.running and D.isEnabled() and pending and pending.managed
        and current == pending.source.vnum and last == current and fresh == current then
      -- Opening a door can report the source again after our final direction
      -- has already been sent. The mapper otherwise pops that queued direction
      -- here and links the source to itself. Keep it for the actual crossing;
      -- onEnterRoom has already refreshed the mapper's source-room metadata.
      return
    end
    if D.running and D.isEnabled() and pending and pending.hint
        and mapper.mappingArea ~= nil and last == pending.source.vnum
        and current and current ~= last and current == fresh
        and (not mapper.lastMoveDirs or next(mapper.lastMoveDirs) == nil) then
      -- The original canceled direction was never sent. Supply just the logical
      -- crossing now that a room change is confirmed, immediately before the
      -- mapper consumes its queue. No gameplay command or event is emitted.
      pending.hint = false
      recorder("sysDataSendRequest", pending.direction)
    end
    return original(...)
  end
  D.adapter = adapter
  mapper.processCurrentRoom = adapter.wrapper
  if D.walker then D.walker.attach() end
end

function D.shutdown()
  D.running = false
  D.clearPending()
  D.state.known = false
  for _, id in ipairs(D.handles.events) do killAnonymousEventHandler(id) end
  for _, id in ipairs(D.handles.aliases) do killAlias(id) end
  for _, id in ipairs(D.handles.triggers) do killTrigger(id) end
  for id in pairs(D.handles.deferred) do killTimer(id) end
  D.handles = {events={}, aliases={}, triggers={}, deferred={}}
  D.detachMapper()
  if D.ui and D.ui.destroy then D.ui.destroy() end
end

local function event(name, callback)
  D.handles.events[#D.handles.events+1] = registerAnonymousEventHandler(name, callback)
end

function D.init()
  if D.running then D.attachMapper(); return true end
  if getMudletVersion then
    local version = tostring(getMudletVersion("string"))
    local major, minor = version:match("^(%d+)%.(%d+)")
    if major and (tonumber(major) < 4 or (tonumber(major) == 4 and tonumber(minor) < 20)) then
      D.notify("Mudlet 4.20 or newer is required. Installed version: " .. version, true)
      return nil
    end
  end
  local loaded, err = D.load()
  if not loaded then D.notify(err, true) end
  -- Installing/updating in a connected session already has a usable Room.Info;
  -- do not require the player to force another room event with look.
  D.state.uncertain = false
  if type(getConnectionInfo) == "function" then
    local ok, _, _, connected = pcall(getConnectionInfo)
    D.state.gmcpBlocked = D.state.gmcpBlocked or (ok and connected == false)
  end
  D.adoptGmcpRoom()
  D.running = true
  D.handles.aliases[#D.handles.aliases+1] = tempAlias(
    [[(?i)^\s*(northwest|northeast|southwest|southeast|north|south|east|west|up|down|nw|ne|sw|se|n|s|e|w|u|d)\s*$]],
    function() D.move(matches[2]) end)
  D.handles.aliases[#D.handles.aliases+1] = tempAlias(
    [[(?i)^doorway(?:\s+(.*))?\s*$]],
    function() D.command(matches[2] or "") end)
  D.handles.aliases[#D.handles.aliases+1] = tempAlias(
    [[(?i)^setdoorway(?:\s+(.*))?\s*$]],
    function()
      local text = D.trim(matches[2])
      D.command(text == "" and "help" or ("set " .. text))
    end)
  event("gmcp.Room.Info", D.onRoomInfo)
  event("sysDataSendRequest", D.onSend)
  event("sysConnectionEvent", D.onDisconnect)
  event("sysDisconnectionEvent", D.onDisconnect)
  event("sysProtocolDisabled", function(_, protocol)
    if protocol == "GMCP" then D.onDisconnect() end
  end)
  event("lotjUiLoaded", function()
    D.attachMapper()
    if D.mapStorage then D.mapStorage.load() end
  end)
  event("sysMapDownloadEvent", function()
    if D.mapStorage then D.mapStorage.load() end
  end)
  event("sysLoadEvent", D.init)
  event("sysInstallPackage", function(_, packageName)
    if packageName == D.packageName then D.init() end
  end)
  event("sysUninstallPackage", function(_, packageName)
    if packageName == D.packageName then
      D.shutdown()
    elseif packageName == "lotj-ui" then
      if D.walker then D.walker.stop("the LotJ UI was removed.") end
      D.detachMapper()
    end
  end)
  local failures = {
    [[^Alas, you cannot go that way\.$]],
    [[^The .* is closed\.$]],
    [[^You can't go that way,]],
    [[^You can't do that sitting down\.$]],
    [[^Nah\.\.\. You feel too relaxed\.\.\.$]],
    [[^In your dreams, or what\?$]],
    [[^You are too exhausted\.$]],
    [[^That room is private right now\.$]],
  }
  for _, pattern in ipairs(failures) do
    D.handles.triggers[#D.handles.triggers+1] = tempRegexTrigger(pattern, D.onFailure)
  end
  D.handles.triggers[#D.handles.triggers+1] = tempRegexTrigger([[^It is pitch black \.\.\.\s*$]], D.onDark)
  if D.ui and D.ui.init then D.ui.init() end
  if D.mapStorage then D.mapStorage.load() end
  D.attachMapper()
  return true
end

D.init()
