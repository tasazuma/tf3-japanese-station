-- Shared layout rules for the JP modular station (grid, slot ids, helpers).
-- Grid: rows run along X (row 0 centred at X=0), segments run along Y (segment j centred at Y=j*40).
local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

local layout = {}

layout.MOD_ID = "jpst_station"
layout.SEG_LEN = 40
layout.DEFAULT_WIDTH = 5
layout.TRACK_WIDTH = 5
layout.PLATFORM_HEIGHT = 1.1
layout.UNDERGROUND_Z = -7
layout.ELEVATED_Z = 10
layout.CONCOURSE_Z = 9 -- 2F concourse floor over ground tracks
layout.CONCOURSE_HALF_WIDTH = 5
layout.BRIDGE_TYPE = "::/infrastructure/bridge/concrete.bridge"

layout.KIND = { TRACK = 1, PLATFORM = 2, BUILDING = 3, CONCOURSE = 4 }
layout.LEVEL = { GROUND = 0, ELEVATED = 1 } -- 2..9 reserved (underground etc.)
layout.LEVEL_Z = { [0] = 0, [1] = layout.ELEVATED_Z }
layout.LEVEL_SUFFIX = { [0] = "", [1] = "_elevated" }
layout.SIDE = { MINUS_X = 0, PLUS_X = 1 }
layout.MAX_BUILDING_SEGS = 8 -- station buildings span 1..8 segments (40..320 m)

layout.SLOT_TYPE = {
	[1] = "jpst_track",
	[2] = "jpst_platform",
	[3] = "jpst_building",
	[4] = "jpst_concourse",
}

-- Track/platform slot types differ per level so the module picker only shows matching slots.
function layout.slotType(kind, level)
	if kind == layout.KIND.BUILDING or kind == layout.KIND.CONCOURSE then return layout.SLOT_TYPE[kind] end
	return layout.SLOT_TYPE[kind] .. (layout.LEVEL_SUFFIX[level] or "")
end

-- Station buildings: the slot "row" packs side and length in segments (row = side + 2 * (size - 1)),
-- and every length has its own slot type: jpst_building (1 segment), jpst_building_2 .. jpst_building_8.
function layout.buildingRow(side, size)
	return side + 2 * ((size or 1) - 1)
end

function layout.buildingSideSize(row)
	return row % 2, math.floor(row / 2) + 1
end

function layout.buildingSlotType(size)
	if (size or 1) <= 1 then return layout.SLOT_TYPE[layout.KIND.BUILDING] end
	return layout.SLOT_TYPE[layout.KIND.BUILDING] .. "_" .. tostring(size)
end

-- Slot type for any slot id.
function layout.slotTypeOf(id)
	local kind, level, row = layout.decode(id)
	if kind == layout.KIND.BUILDING then
		local _, size = layout.buildingSideSize(row)
		return layout.buildingSlotType(size)
	end
	return layout.slotType(kind, level)
end

function layout.levelZ(level)
	return layout.LEVEL_Z[level] or 0
end

-- slot id = kind*10000000 + level*1000000 + (row+100)*1000 + (seg+100)
function layout.encode(kind, level, row, seg)
	return kind * 10000000 + level * 1000000 + (row + 100) * 1000 + (seg + 100)
end

function layout.decode(id)
	local kind = math.floor(id / 10000000)
	local rest = id - kind * 10000000
	local level = math.floor(rest / 1000000)
	rest = rest - level * 1000000
	local row = math.floor(rest / 1000) - 100
	local seg = rest % 1000 - 100
	return kind, level, row, seg
end

function layout.moduleName(file)
	return layout.MOD_ID .. "::/stations/jpst/" .. file .. ".module"
end

layout.TRACK_TYPES = { "simple", "standard", "high_speed" }

function layout.trackTemplate(typeName, catenary)
	return "::/infrastructure/track/" .. typeName .. "/" .. typeName .. (catenary and "_catenary" or "") .. ".street_template"
end

function layout.trackModuleFile(typeName, catenary, level)
	local prefix = (level == layout.LEVEL.ELEVATED) and "jpst_track_elevated_" or "jpst_track_"
	return prefix .. typeName .. (catenary and "_catenary" or "")
end

function layout.trackModuleName(typeName, catenary, level)
	return layout.moduleName(layout.trackModuleFile(typeName, catenary, level))
end

-- Build the grid description from params.modules.
-- A row has a single level; if modules disagree the lowest slot id wins and the rest are ignored.
function layout.compute(modules)
	local L = {
		cells = {},      -- cells[row][seg] = { kind, level, id, module }
		rowLevel = {},   -- [row] = level
		widths = {},
		centres = {},
		buildings = {},  -- [slotId] = { module, side, size, seg, front }
		buildingAt = { [0] = {}, [1] = {} }, -- buildingAt[side][seg] = slotId of the building covering it
		concourses = {}, -- [seg] = slotId (one per segment)
		ignored = {},    -- [slotId] = true: module kept in its slot but not built (level conflict, orphan building)
		segs = {},       -- [seg] = { minRow, maxRow }
		minRow = 0, maxRow = 0, minSeg = 0, maxSeg = 0,
		empty = true,
	}
	local ids = {}
	for id in pairs(modules or {}) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local m = modules[id]
		local kind, level, row, seg = layout.decode(id)
		local cellKind = (kind == layout.KIND.TRACK or kind == layout.KIND.PLATFORM)
		local fits = cellKind and layout.LEVEL_Z[level] ~= nil
			and (L.rowLevel[row] == nil or L.rowLevel[row] == level)
			and not (L.cells[row] and L.cells[row][seg])
		if fits then
			L.rowLevel[row] = level
			L.cells[row] = L.cells[row] or {}
			L.cells[row][seg] = { kind = kind, level = level, id = id, module = m }
			local w = (m.metadata and m.metadata.jpst_width) or layout.DEFAULT_WIDTH
			L.widths[row] = math.max(L.widths[row] or 0, w)
			if L.empty then
				L.minRow, L.maxRow, L.minSeg, L.maxSeg = row, row, seg, seg
				L.empty = false
			else
				L.minRow = math.min(L.minRow, row)
				L.maxRow = math.max(L.maxRow, row)
				L.minSeg = math.min(L.minSeg, seg)
				L.maxSeg = math.max(L.maxSeg, seg)
			end
			local s = L.segs[seg]
			if s then
				s.minRow = math.min(s.minRow, row)
				s.maxRow = math.max(s.maxRow, row)
			else
				L.segs[seg] = { minRow = row, maxRow = row }
			end
		elseif kind == layout.KIND.BUILDING then
			L.buildings[id] = { module = m }
		elseif kind == layout.KIND.CONCOURSE and L.concourses[seg] == nil then
			L.concourses[seg] = id
		else
			L.ignored[id] = true
		end
	end
	-- A building needs rows in every segment it covers and must not overlap another building on its side
	-- (lowest slot id wins).
	local bids = {}
	for id in pairs(L.buildings) do bids[#bids + 1] = id end
	table.sort(bids)
	for _, id in ipairs(bids) do
		local _, _, row, seg = layout.decode(id)
		local side, size = layout.buildingSideSize(row)
		local ok = size <= layout.MAX_BUILDING_SEGS and side <= layout.SIDE.PLUS_X
		for s = seg, seg + size - 1 do
			if not ok then break end
			if not L.segs[s] or L.buildingAt[side][s] then ok = false end
		end
		if ok then
			local b = L.buildings[id]
			b.side, b.size, b.seg = side, size, seg
			for s = seg, seg + size - 1 do L.buildingAt[side][s] = id end
		else
			L.buildings[id] = nil
			L.ignored[id] = true
		end
	end

	-- A 2F concourse only spans ground rows: it would cut through an elevated viaduct.
	for seg, id in pairs(L.concourses) do
		local s = L.segs[seg]
		local ok = s ~= nil
		if ok then
			for row = s.minRow, s.maxRow do
				local c = L.cells[row] and L.cells[row][seg]
				if c and c.level ~= layout.LEVEL.GROUND then ok = false end
			end
		end
		if not ok then
			L.concourses[seg] = nil
			L.ignored[id] = true
		end
	end

	local lo = math.min(L.minRow, 0) - 1
	local hi = math.max(L.maxRow, 0) + 1
	for r = lo, hi do
		L.widths[r] = L.widths[r] or layout.DEFAULT_WIDTH
	end
	L.centres[0] = 0
	for r = 1, hi do
		L.centres[r] = L.centres[r - 1] + L.widths[r - 1] / 2 + L.widths[r] / 2
	end
	for r = -1, lo, -1 do
		L.centres[r] = L.centres[r + 1] - L.widths[r + 1] / 2 - L.widths[r] / 2
	end
	for _, b in pairs(L.buildings) do
		b.front = layout.buildingFront(L, b.side, b.seg, b.size)
	end
	return L
end

function layout.get(L, row, seg)
	return L.cells[row] and L.cells[row][seg]
end

function layout.isTrack(L, row, seg)
	local c = layout.get(L, row, seg)
	return c ~= nil and c.kind == layout.KIND.TRACK
end

function layout.isPlatform(L, row, seg)
	local c = layout.get(L, row, seg)
	return c ~= nil and c.kind == layout.KIND.PLATFORM
end

function layout.width(L, row)
	return L.widths[row] or layout.DEFAULT_WIDTH
end

function layout.centre(L, row)
	return L.centres[row] or 0
end

function layout.segY(seg)
	return seg * layout.SEG_LEN
end

function layout.rowLevel(L, row)
	return L.rowLevel[row]
end

function layout.isElevated(L, row)
	return L.rowLevel[row] == layout.LEVEL.ELEVATED
end

-- Cell frame stays at ground level (z=0) for every level; modules add their own height.
function layout.cellTransf(L, row, seg)
	return transf.transl(vec3.new(layout.centre(L, row), layout.segY(seg), 0))
end

-- Slot marker position: raised for elevated slots so they are clickable above the ground ones.
function layout.slotTransf(L, row, seg, level)
	return transf.transl(vec3.new(layout.centre(L, row), layout.segY(seg), layout.levelZ(level)))
end

-- Outer X edges of the rows used in a segment.
function layout.segEdges(L, seg)
	local s = L.segs[seg]
	if not s then return nil end
	return layout.centre(L, s.minRow) - layout.width(L, s.minRow) / 2,
		layout.centre(L, s.maxRow) + layout.width(L, s.maxRow) / 2
end

-- X of a building front: the outermost row edge over every segment it covers.
function layout.buildingFront(L, side, seg, size)
	local front
	for s = seg, seg + (size or 1) - 1 do
		local xL, xR = layout.segEdges(L, s)
		if xL then
			if side == layout.SIDE.MINUS_X then
				front = front and math.min(front, xL) or xL
			else
				front = front and math.max(front, xR) or xR
			end
		end
	end
	return front
end

-- Building frame: origin at the middle of the front, local +X along the tracks, local -Y away from them.
-- A building of `size` segments starts at segment `seg` and extends towards +Y.
function layout.buildingTransf(L, side, seg, size)
	size = size or 1
	local x = layout.buildingFront(L, side, seg, size)
	if not x then return nil end
	local y = layout.segY(seg) + (size - 1) * layout.SEG_LEN / 2
	if side == layout.SIDE.MINUS_X then
		return transf.rotZTransl(math.rad(-90), vec3.new(x, y, 0))
	end
	return transf.rotZTransl(math.rad(90), vec3.new(x, y, 0))
end

-- Local X (building frame) of the centre of segment `s` for a building anchored at `seg`.
function layout.buildingLocalX(side, seg, size, s)
	local dy = (s - seg) * layout.SEG_LEN - ((size or 1) - 1) * layout.SEG_LEN / 2
	return side == layout.SIDE.MINUS_X and -dy or dy
end

function layout.concourseSlotTransf(L, seg)
	local xL, xR = layout.segEdges(L, seg)
	return transf.transl(vec3.new((xL + xR) / 2, layout.segY(seg), layout.CONCOURSE_Z))
end

-- Lanes ------------------------------------------------------------------

-- Straight polyline lane; every point becomes a shared node.
function layout.makeLane(points, width, linkable, localTransf)
	local nodes = {}
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local t = { b[1] - a[1], b[2] - a[2], b[3] - a[3] }
		nodes[#nodes + 1] = { { a[1], a[2], a[3] }, t, width }
		nodes[#nodes + 1] = { { b[1], b[2], b[3] }, t, width }
	end
	return {
		transf = localTransf or transf.identity(),
		nodes = nodes,
		speedLimit = 20,
		transportModes = { "PERSON" },
		linkable = linkable and true or false,
	}
end

-- Adds a lane to station (cargoStation) and returns its 0-based index.
function layout.addLane(station, points, width, linkable, localTransf)
	table.insert(station.laneLists, layout.makeLane(points, width, linkable, localTransf))
	return #station.laneLists - 1
end

-- Track edges ------------------------------------------------------------

function layout.findOrMakeEdgeList(result, template, catenary, edgeType, edgeTypeName)
	for k, v in ipairs(result.edgeLists) do
		if v.params.type == template and v.edgeType == edgeType and v.edgeTypeName == edgeTypeName then return k end
	end
	table.insert(result.edgeLists, {
		type = "TRACK",
		params = { type = template },
		edgeType = edgeType,
		edgeTypeName = edgeTypeName,
		edges = {},
		snapNodes = {},
		tag2nodes = {},
	})
	table.insert(result.edgeListHasCatenary, catenary and true or false)
	return #result.edgeLists
end

-- Same edge pattern as vanilla trainstationutil.makeTrack (6 edges per 40 m segment).
-- Returns { list = edgeListIndex, nedges = firstNodeIndex }.
-- opts: { z = height, edgeType = "BRIDGE"/"TUNNEL"/nil, edgeTypeName = res }
function layout.addTrackEdges(result, x, y, tag, template, catenary, snapStart, snapEnd, opts)
	opts = opts or {}
	local z = opts.z or 0
	local n = layout.findOrMakeEdgeList(result, template, catenary, opts.edgeType, opts.edgeTypeName)
	local el = result.edgeLists[n]
	local nedges = #el.edges
	local e = el.edges
	e[nedges + 1] = { { x, y - 18, z }, { 0, -2, 0 } }
	e[nedges + 2] = { { x, y - 20, z }, { 0, -2, 0 } }
	e[nedges + 3] = { { x, y - 2, z }, { 0, -16, 0 } }
	e[nedges + 4] = { { x, y - 18, z }, { 0, -16, 0 } }
	e[nedges + 5] = { { x, y, z }, { 0, -2, 0 } }
	e[nedges + 6] = { { x, y - 2, z }, { 0, -2, 0 } }
	e[nedges + 7] = { { x, y, z }, { 0, 2, 0 } }
	e[nedges + 8] = { { x, y + 2, z }, { 0, 2, 0 } }
	e[nedges + 9] = { { x, y + 2, z }, { 0, 16, 0 } }
	e[nedges + 10] = { { x, y + 18, z }, { 0, 16, 0 } }
	e[nedges + 11] = { { x, y + 18, z }, { 0, 2, 0 } }
	e[nedges + 12] = { { x, y + 20, z }, { 0, 2, 0 } }
	el.maxNodeSnapAngle = 60.0

	if snapStart then table.insert(el.snapNodes, nedges + 1) end
	if snapEnd then table.insert(el.snapNodes, nedges + 11) end

	el.tag2nodes[tag] = el.tag2nodes[tag] or {}
	for k = 0, 11 do table.insert(el.tag2nodes[tag], nedges + k) end

	return { list = n, nedges = nedges }
end

-- Ground faces -----------------------------------------------------------

function layout.rectFace(x0, y0, x1, y1)
	return {
		{ x0, y0, 0, 1 },
		{ x1, y0, 0, 1 },
		{ x1, y1, 0, 1 },
		{ x0, y1, 0, 1 },
	}
end

layout.GROUND_MODES_PLATFORM = {
	{ type = "FILL", key = "::/terrain/materials/gravel_03/gravel_03.gtex" },
	{ type = "STROKE_OUTER", key = "::/infrastructure/street/shared/street_border.gtex" },
}

return layout
