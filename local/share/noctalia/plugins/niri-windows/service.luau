-- Polls niri for open windows and publishes them per output, sorted by
-- real layout position (column = left -> right). The widget picks the
-- list for its own monitor.

local function iconFor(appId)
	if type(appId) ~= "string" or appId == "" then
		return nil
	end
	local size = noctalia.getConfig("icon_size") or 20
	local ok, path = pcall(noctalia.appIconPath, appId, size)
	if ok and type(path) == "string" and path ~= "" then
		return path
	end
	return nil
end

local function colRow(w)
	local pos = w.layout and w.layout.pos_in_scrolling_layout
	if type(pos) ~= "table" or type(pos[1]) ~= "number" then
		return math.huge, math.huge
	end
	return pos[1], (type(pos[2]) == "number") and pos[2] or 0
end

local function sortWindows(list)
	-- pos_in_scrolling_layout gives [column, row] where column 1 is leftmost.
	-- This matches the visual left-to-right order on screen.
	table.sort(list, function(a, b)
		local ca, ra = colRow(a)
		local cb, rb = colRow(b)
		if ca ~= cb then
			return ca < cb
		end
		return ra < rb
	end)
end

local function publish(windows, workspaces, focusedId)
	-- Map workspace id -> output.
	local wsOutput = {}
	-- Track which workspace is active on each output.
	local activeWsByOutput = {}
	for _, ws in ipairs(workspaces) do
		wsOutput[ws.id] = ws.output
		if ws.is_active and ws.output then
			activeWsByOutput[ws.output] = ws.id
		end
	end

	-- Group windows by output, but only from the active workspace.
	local byOutput = {}
	for _, w in ipairs(windows) do
		local output = wsOutput[w.workspace_id]
		if output and activeWsByOutput[output] == w.workspace_id then
			local list = byOutput[output] or {}
			table.insert(list, {
				id = w.id,
				title = w.title or "",
				icon = iconFor(w.app_id),
				focused = w.id == focusedId,
			})
			byOutput[output] = list
		end
	end

	for _, list in pairs(byOutput) do
		sortWindows(list)
	end

	noctalia.state.set("wsWindows", { outputs = byOutput })
end

local function refresh()
	noctalia.runAsync("niri msg --json windows", function(res)
		if res.exitCode ~= 0 or type(res.stdout) ~= "string" then
			return
		end
		local ok, windows = pcall(noctalia.json.decode, res.stdout)
		if not ok or type(windows) ~= "table" then
			return
		end

		noctalia.runAsync("niri msg --json workspaces", function(wsRes)
			if wsRes.exitCode ~= 0 or type(wsRes.stdout) ~= "string" then
				return
			end
			local okWs, workspaces = pcall(noctalia.json.decode, wsRes.stdout)
			if not okWs or type(workspaces) ~= "table" then
				return
			end

			noctalia.runAsync("niri msg --json focused-window", function(fwRes)
				local focusedId = nil
				if fwRes.exitCode == 0 and type(fwRes.stdout) == "string" then
					local okFw, focused = pcall(noctalia.json.decode, fwRes.stdout)
					if okFw and type(focused) == "table" then
						focusedId = focused.id
					end
				end
				publish(windows, workspaces, focusedId)
			end)
		end)
	end)
end

noctalia.setUpdateInterval(500)

function update()
	refresh()
end
