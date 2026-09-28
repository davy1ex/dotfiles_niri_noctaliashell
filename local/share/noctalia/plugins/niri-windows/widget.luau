-- Renders the current workspace's windows split around the focused one:
--   [left window icons] [focused icon + title] [right window icons]
-- Clicking an icon focuses that window.

local windows = {}

local function focusWindow(id)
	noctalia.runAsync("niri msg action focus-window --id " .. id)
end

local function iconFor(w)
	local size = noctalia.getConfig("icon_size") or 18
	local onClick = function()
		focusWindow(w.id)
	end
	if w.focused then
		if w.icon then
			return ui.image({
				key = "w" .. w.id,
				path = w.icon,
				width = size,
				height = size,
				radius = 5,
				border = "primary",
				borderWidth = 1.5,
				onClick = onClick,
			})
		end
		return ui.glyph({ key = "w" .. w.id, name = "app-window", size = size - 2 })
	end
	if w.icon then
		return ui.image({
			key = "w" .. w.id,
			path = w.icon,
			width = size,
			height = size,
			radius = 5,
			opacity = 0.6,
			onClick = onClick,
		})
	end
	return ui.glyph({
		key = "w" .. w.id,
		name = "app-window",
		size = size - 2,
		opacity = 0.6,
	})
end

local function sideItems(list)
	local items = {}
	local maxSide = noctalia.getConfig("max_side") or 4
	local n = #list
	local shown = math.min(n, maxSide)
	for i = 1, shown do
		table.insert(items, iconFor(list[i]))
	end
	if n > maxSide then
		table.insert(items, ui.label({ text = "+" .. (n - maxSide), opacity = 0.6 }))
	end
	return items
end

local function render()
	local output = barWidget.outputName()
	local data = windows[output]
	if data == nil then
		for _, list in pairs(windows) do
			data = list
			break
		end
	end
	data = data or {}

	local focusedIndex = nil
	for i, w in ipairs(data) do
		if w.focused then
			focusedIndex = i
			break
		end
	end

	local items = {}

	if focusedIndex then
		local leftItems = sideItems({ table.unpack(data, 1, focusedIndex - 1) })
		if #leftItems > 0 then
			table.insert(items, ui.row({ gap = 6, align = "center" }, leftItems))
		end

		local fw = data[focusedIndex]
		local centerItems = { iconFor(fw) }
		if fw.title and fw.title ~= "" then
			local title = fw.title
			local maxLen = noctalia.getConfig("title_max_length") or 28
			if #title > maxLen then
				title = string.sub(title, 1, maxLen - 1) .. "..."
			end
			table.insert(centerItems, ui.label({
				key = "wtitle" .. fw.id,
				text = title,
				fontWeight = "bold",
				color = "primary",
			}))
		end
		table.insert(items, ui.row({ gap = 6, align = "center" }, centerItems))

		local rightItems = sideItems({ table.unpack(data, focusedIndex + 1) })
		if #rightItems > 0 then
			table.insert(items, ui.row({ gap = 6, align = "center" }, rightItems))
		end
	end

	if #items == 0 then
		barWidget.setVisible(false)
		return
	end
	barWidget.setVisible(true)
	barWidget.render(ui.row({ gap = 10, align = "center" }, items))
end

local initial = noctalia.state.get("wsWindows")
if type(initial) == "table" and type(initial.outputs) == "table" then
	windows = initial.outputs
	render()
end

noctalia.state.watch("wsWindows", function(value)
	windows = (type(value) == "table" and type(value.outputs) == "table") and value.outputs or {}
	render()
end)
