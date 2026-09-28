-- Local-only editor. All writes use the same core API as `setdoorway`.
local D = lotjDoorways
if D.ui and D.ui.destroy then D.ui.destroy() end

local ui = { widgets = {}, selection = nil, direction = "n", showAll = false }
D.ui = ui
local prefix = "lotjDoorwaysEditor"
local colors = {
  background = "#121b25", panel = "#1d2a38", text = "#edf4fa",
  muted = "#adbecf", accent = "#9ae6bf", border = "#3a4d61",
  error = "#ffb8a9",
}

local function html(value)
  return tostring(value or ""):gsub("&", "&amp;"):gsub("<", "&lt;")
    :gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("[\r\n]", " ")
end

local function plain(value)
  return tostring(value or ""):gsub("[%c]", " ")
end

local function label(name, x, y, width, height, text, parent)
  local widget = Geyser.Label:new({
    name = prefix .. name, x = x, y = y, width = width, height = height,
    color = colors.background, fgColor = colors.text, fontSize = 11,
  }, parent or ui.window)
  widget:setStyleSheet("background-color: " .. colors.background .. "; color: " .. colors.text .. "; border: none;")
  widget:echo(text or "")
  return widget
end

local function buttonStyle(active, danger)
  return string.format([[
    QLabel { background-color: %s; color: %s; border: 1px solid %s;
      border-radius: 4px; padding: 4px; }
    QLabel:hover { background-color: #34485c; border-color: #9ae6bf; }
  ]], active and "#25493d" or colors.panel,
      danger and colors.error or (active and colors.accent or colors.text),
      active and "#65977f" or colors.border)
end

local function button(name, x, y, width, height, text, callback)
  local widget = label(name, x, y, width, height, "<center>" .. html(text) .. "</center>")
  widget:setStyleSheet(buttonStyle(false))
  widget:setClickCallback(function(event)
    if not event or not event.button or event.button == "LeftButton" then callback() end
  end)
  return widget
end

local function message(text, isError)
  ui.message = text or ""
  ui.messageIsError = isError == true
  if ui.widgets.message then
    ui.widgets.message:echo('<span style="color:' .. (isError and colors.error or colors.accent)
      .. '">' .. html(text) .. "</span>")
  end
end

local function printDraft(text)
  if ui.widgets.sequence then ui.widgets.sequence:print(text or "") end
end

local function loadDraft()
  local rule = ui.selection and D.getRule(ui.selection.vnum, ui.direction)
  printDraft(rule and table.concat(rule.commands, ";;") or "")
  message("")
end

-- Explicit selection is deliberately independent of live GMCP. A room refresh
-- must never silently redirect a save or overwrite a partially typed sequence.
function ui.selectRoom(room, direction)
  if not room or not room.vnum then
    message("Room unavailable. Wait for fresh room information, then use the current room.", true)
    return
  end
  ui.selection = { vnum = tostring(room.vnum), name = tostring(room.name or "Unknown room") }
  if direction then ui.direction = D.normalizeDirection(direction) or ui.direction end
  loadDraft()
  ui.refresh()
end

function ui.selectDirection(direction)
  local normalized = D.normalizeDirection(direction)
  if not normalized then return end
  if normalized == ui.direction then return end
  ui.direction = normalized
  loadDraft()
  ui.refresh()
end

function ui.save(text)
  if type(text) ~= "string" then text = ui.widgets.sequence:getText() end
  if not ui.selection then
    printDraft(text)
    message("Choose a room with Use current room or select a saved rule first.", true)
    return nil
  end
  -- The command-line action supplies a captured draft. It never reaches the
  -- game or aliases, even when Mudlet is configured to clear input after Enter.
  local commands, err = D.parseSequence(text)
  if not commands then
    printDraft(text)
    message(err, true)
    return nil, err
  end
  local ok
  ok, err = D.setRule(ui.selection.vnum, ui.selection.name, ui.direction, commands)
  if not ok then
    printDraft(text)
    message(err, true)
    return nil, err
  end
  printDraft(table.concat(commands, ";;"))
  message("Saved " .. ui.direction:upper() .. " for room " .. ui.selection.vnum .. ".")
  ui.refresh()
  return true
end

function ui.deleteSelected()
  if not ui.selection then
    message("Choose a room before deleting a rule.", true)
    return nil
  end
  local ok, err = D.removeRule(ui.selection.vnum, ui.direction)
  if not ok then message(err, true); return nil, err end
  printDraft("")
  message("Removed " .. ui.direction:upper() .. " for room " .. ui.selection.vnum .. ".")
  ui.refresh()
  return true
end

local function renderRules()
  local console = ui.widgets.rules
  if not console then return end
  console:clear()
  local rules = D.listRules(ui.showAll)
  ui.widgets.rulesTitle:echo("<b>Saved rules</b> <span style=\"color:" .. colors.muted
    .. "\">(" .. #rules .. ")</span>")
  if #rules == 0 then
    local text = ui.showAll and "No saved rules yet." or "No saved rules for your current room."
    console:echo(text .. "\n\nChoose a direction, enter the door commands, and save.\n")
    return
  end
  for _, rule in ipairs(rules) do
    local entry = rule
    local selected = ui.selection and ui.selection.vnum == tostring(entry.vnum)
      and ui.direction == entry.direction
    console:echoLink((selected and "> " or "  ") .. plain(entry.direction):upper()
      .. "  |  " .. plain(entry.name) .. "  [" .. plain(entry.vnum) .. "]",
      function() ui.selectRoom({ vnum = entry.vnum, name = entry.name }, entry.direction) end,
      "Edit this saved rule", true)
    console:echo("\n    " .. plain(table.concat(entry.commands, ";;")) .. "\n\n")
  end
end

function ui.refresh()
  if not ui.window then return end
  local room = D.getGmcpRoom()
  ui.widgets.liveRoom:echo('<span style="color:' .. colors.muted .. '">Current room: '
    .. (room and (html(room.name) .. " [" .. html(room.vnum) .. "]") or "waiting for fresh room information")
    .. "</span>")
  local selectedText = "No room selected"
  if ui.selection then
    selectedText = html(ui.selection.name) .. " <span style=\"color:" .. colors.accent
      .. "\">[" .. html(ui.selection.vnum) .. "]</span>"
  end
  ui.widgets.selection:echo('<span style="color:' .. colors.muted
    .. '">EDITING ROOM</span><br><b>' .. selectedText .. "</b>")
  local enabled = D.isEnabled()
  ui.widgets.toggle:echo("<center>" .. (enabled and "Enabled" or "Disabled") .. " · click to toggle</center>")
  ui.widgets.toggle:setStyleSheet(buttonStyle(enabled))
  for direction, widget in pairs(ui.widgets.directions) do
    widget:setStyleSheet(buttonStyle(direction == ui.direction))
  end
  ui.widgets.currentFilter:setStyleSheet(buttonStyle(not ui.showAll))
  ui.widgets.allFilter:setStyleSheet(buttonStyle(ui.showAll))
  local integrated = D.adapter and D.walker and D.walker.hook
    and doSpeedWalk == D.walker.hook.wrapper
  local status = not enabled and "Doorways disabled"
    or (integrated and "LotJ map walking connected" or "Manual doorways ready · LotJ map walking unavailable")
  ui.widgets.status:echo('<span style="color:' .. colors.muted .. '">' .. status .. "</span>")
  local direction = html(ui.direction)
  ui.widgets.sequenceHint:echo('<span style="color:' .. colors.muted
    .. '">Separate steps with ;; &nbsp; Example: open ' .. direction .. ';;' .. direction
    .. ' &nbsp; or &nbsp; say enter</span>')
  renderRules()
end

function ui.init()
  -- Lazy construction leaves the editor hidden and creates no windows on load.
  return true
end

local function createWindow()
  if not (Geyser and Geyser.Label and Geyser.CommandLine and Geyser.MiniConsole
      and Adjustable and Adjustable.Container) then
    return nil, "The Doorways editor needs Mudlet 4.20+ with its bundled Geyser widgets."
  end
  ui.window = Adjustable.Container:new({
    name = prefix, x = 40, y = 55, width = 760, height = 720,
    titleText = "LotJ Doorways v" .. D.version, titleTxtColor = colors.muted, titleFormat = "l10",
    padding = 12, autoSave = false, autoLoad = false, hidden = true,
    adjLabelstyle = "background-color: " .. colors.background .. "; border: 1px solid " .. colors.border .. ";",
    buttonstyle = "QLabel { background-color: #1d2a38; color: #edf4fa; border: none; } QLabel:hover { background-color: #34485c; }",
  })
  ui.window:changeMenuStyle("dark")
  local w = ui.widgets
  w.heading = label("Heading", 0, 3, "49%", 30, "<b>Walk through familiar doors.</b>")
  w.help = button("Help", "51%", 1, "12%", 30, "Help", function()
    D.printHelp()
    message("Command help printed in the main console.")
  end)
  w.toggle = button("Toggle", "65%", 1, "35%", 30, "", function()
    local ok, err = D.setEnabled(not D.isEnabled())
    if not ok then message(err, true) else ui.refresh() end
  end)
  w.liveRoom = label("LiveRoom", 0, 40, "100%", 25)
  w.selection = label("Selection", 0, 74, "70%", 48)
  w.useCurrent = button("UseCurrent", "73%", 80, "27%", 34, "Use current room", function()
    ui.selectRoom(D.getGmcpRoom())
  end)
  w.directions = {}
  for index, direction in ipairs(D.directions) do
    local key = direction.short
    w.directions[key] = button("Direction" .. key, ((index - 1) * 10) .. "%", 132,
      "10%-5px", 34, key:upper(), function() ui.selectDirection(key) end)
  end
  w.sequenceTitle = label("SequenceTitle", 0, 180, "100%", 24, "<b>Door commands</b>")
  w.sequenceHint = label("SequenceHint", 0, 204, "100%", 26,
    '<span style="color:' .. colors.muted .. '">Separate steps with ;; &nbsp; Example: open ne;;ne &nbsp; or &nbsp; say enter</span>')
  w.sequence = Geyser.CommandLine:new({
    name = prefix .. "Sequence", x = 0, y = 236, width = "100%", height = 48,
    stylesheet = "QPlainTextEdit { background-color: #0c141d; color: #edf4fa; border: 1px solid #657b90; border-radius: 4px; padding: 8px; font-size: 14px; }",
  }, ui.window)
  -- This must be set at construction, before the editor can be shown. Mudlet
  -- calls the action once per pasted line, then may clear the field. Coalesce
  -- those callbacks and capture the complete draft before that clear so invalid
  -- multiline input cannot become multiple saves. Restore it after Enter's own
  -- input cleanup. This timer performs local editing only.
  w.sequence:setAction(function(text)
    local draft = w.sequence:getText()
    if draft == "" then draft = text end
    if ui.enterTimer then killTimer(ui.enterTimer) end
    ui.enterTimer = tempTimer(0, function()
      ui.enterTimer = nil
      if ui.widgets.sequence == w.sequence then ui.save(draft) end
    end)
  end)
  w.save = button("Save", 0, 298, 130, 34, "Save rule", function() ui.save() end)
  w.save:setStyleSheet(buttonStyle(true))
  w.delete = button("Delete", 140, 298, 120, 34, "Delete rule", ui.deleteSelected)
  w.delete:setStyleSheet(buttonStyle(false, true))
  w.enterHint = label("EnterHint", 275, 304, "100%-275px", 24,
    '<span style="color:' .. colors.muted .. '">Enter saves. Editing sends no commands.</span>')
  w.message = label("Message", 0, 342, "100%", 42)
  w.rulesTitle = label("RulesTitle", 0, 394, "48%", 30, "<b>Saved rules</b>")
  w.currentFilter = button("CurrentFilter", "52%", 388, "28%", 30, "Current room", function()
    ui.showAll = false
    ui.refresh()
  end)
  w.allFilter = button("AllFilter", "81%", 388, "19%", 30, "All rooms", function()
    ui.showAll = true
    ui.refresh()
  end)
  w.rules = Geyser.MiniConsole:new({
    name = prefix .. "Rules", x = 0, y = 430, width = "100%", height = "100%-510px",
    color = "#0c141d", fgColor = colors.text, fontSize = 10,
    scrollBar = true, scrolling = true, autoWrap = true, commandLine = false,
  }, ui.window)
  w.status = label("Status", 0, "100%-72px", "100%", 22)
  w.walkHint = label("WalkHint", 0, "100%-48px", "100%", 22,
    '<span style="color:' .. colors.muted .. '">Map walks send every step at once. Stop cannot recall commands already sent.</span>')
  w.footer = label("Footer", 0, "100%-24px", "100%", 22,
    '<span style="color:' .. colors.muted .. '">Rules are shared by this profile. The editing room stays fixed while you walk.</span>')
  ui.window:hide()
  return true
end

function ui.open()
  if not ui.window then
    local ok, err = createWindow()
    if not ok then D.notify(err, true); return nil, err end
    local room = D.getGmcpRoom()
    if room then ui.selectRoom(room) end
  end
  ui.refresh()
  if ui.window.minimized then ui.window:restore() end
  ui.window:show()
  ui.window:raiseAll()
  return true
end

function ui.destroy()
  if not ui.window then return end
  local window = ui.window
  if ui.enterTimer then killTimer(ui.enterTimer); ui.enterTimer = nil end
  -- Keep the action harmless throughout teardown, including deferred Qt deletes.
  if ui.widgets.sequence then ui.widgets.sequence:setAction(function() end) end
  window:hide()
  if window.autoSaveHandler then killAnonymousEventHandler(window.autoSaveHandler) end
  if window.connectedToBorder or window.connectedContainers then window:disconnect() end
  if window.attached then window:detach() end
  -- Adjustable's context menu can move its labels to Geyser's root. Delete its
  -- own menu tree before the container so those detached widgets cannot survive.
  local seen = {}
  local function deleteMenu(menu)
    if not menu or seen[menu] then return end
    seen[menu] = true
    for _, child in pairs(menu.MenuLabels or {}) do deleteMenu(child) end
    if menu.delete then menu:delete() end
  end
  deleteMenu(window.rCLabel)
  window:delete()
  if Adjustable.Container.all[prefix] == window then
    Adjustable.Container.all[prefix] = nil
    for index = #Adjustable.Container.all_windows, 1, -1 do
      if Adjustable.Container.all_windows[index] == prefix then
        table.remove(Adjustable.Container.all_windows, index)
      end
    end
  end
  ui.window = nil
  ui.widgets = {}
  ui.selection = nil
end
