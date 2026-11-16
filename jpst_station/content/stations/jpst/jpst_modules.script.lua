local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"
local modulesutil = require "::/scripts/construction/modulesutil.lua"
local layout = require "jpst_station::/scripts/jpst/layout.lua"

local H = layout.PLATFORM_HEIGHT
local UZ = layout.UNDERGROUND_Z
local EZ = layout.ELEVATED_Z
local ELEVATED = layout.LEVEL.ELEVATED
local DECK_DEPTH = 2.4
local DECK_MODEL = "::/infrastructure/bridge/concrete/c_6_rep_rep.mdl"
local PILLAR_MODEL = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl"
local TERMINAL_LANE_WIDTH = 2.4
local LANE_WIDTH = 3

local function addModelTo(list, id, transform, localTransf, tag)
	table.insert(list, { id = id, transf = transf.mul(transform, localTransf), tag = tag })
end

-- perron models run along local X (0..40); rotate so they run along Y (-20..20)
local function perronTransf(x)
	return transf.rotZTransl(math.rad(90), vec3.new(x, -20, 0))
end

local function lift(localTransf, z)
	if z == 0 then return localTransf end
	return transf.mul(transf.transl(vec3.new(0, 0, z)), localTransf)
end

local function addBox(target, transform, x0, y0, x1, y1, halfHeight, alignType, modes, colliderZ)
	local face = layout.rectFace(x0, y0, x1, y1)
	modulesutil.TransformFaces(transform, face)
	table.insert(target.terrainAlignmentLists, { type = alignType or "EQUAL", faces = { face } })
	if modes then
		table.insert(target.groundFaces, { face = face, modes = modes })
	end
	if halfHeight then
		table.insert(target.colliders, {
			type = "BOX",
			transf = transf.mul(transform, transf.transl(vec3.new((x0 + x1) / 2, (y0 + y1) / 2, colliderZ or 0))),
			params = { halfExtents = { (x1 - x0) / 2, (y1 - y0) / 2, halfHeight } },
		})
	end
end

-- Underground passage grid shared by every track/platform cell:
-- along the row centre (x=0) and across the row at the segment centre (y=0).
local function addUnderground(cs, transform, rowWidth, extraX)
	local xs = { -rowWidth / 2, 0, rowWidth / 2 }
	if extraX and extraX ~= 0 then table.insert(xs, extraX) end
	table.sort(xs)
	local cross = {}
	for _, x in ipairs(xs) do table.insert(cross, { x, 0, UZ }) end
	layout.addLane(cs, cross, LANE_WIDTH, false, transform)
	layout.addLane(cs, { { 0, -20, UZ }, { 0, 0, UZ }, { 0, 20, UZ } }, LANE_WIDTH, false, transform)
end

-- Ground-level concourse under elevated rows: cross lane at y=0, a short lane along the row at x=cx,
-- and stairs down to the underground passage so elevated rows reach ground rows and buildings.
local function addConcourse(cs, transform, rowWidth, cx)
	local xs = { -rowWidth / 2, 0, rowWidth / 2 }
	if cx ~= 0 then table.insert(xs, cx) end
	table.sort(xs)
	local cross = {}
	for _, x in ipairs(xs) do table.insert(cross, { x, 0, 0 }) end
	layout.addLane(cs, cross, LANE_WIDTH, false, transform)
	layout.addLane(cs, { { cx, -20, 0 }, { cx, -8, 0 }, { cx, 0, 0 }, { cx, 20, 0 } }, LANE_WIDTH, false, transform)
	layout.addLane(cs, { { cx, -8, 0 }, { cx, -4, -2 }, { cx, 0, UZ } }, LANE_WIDTH, false, transform)
end

-- Stand-in viaduct under an elevated platform: stretched concrete bridge deck plus two piers.
local function addViaduct(cs, transform, w, tag)
	local deck = transf.scaleXYZRotZTransl(vec3.new(40 / 6, w / 4, 1), math.rad(90), vec3.new(w / 2, -20, EZ))
	addModelTo(cs.models, DECK_MODEL, transform, deck, tag)
	local pierH = EZ - DECK_DEPTH
	for _, y in ipairs({ -12, 12 }) do
		local pier = transf.scaleXYZRotZTransl(vec3.new(1, 1, pierH / 4), math.rad(90), vec3.new(1.5, y, 0))
		addModelTo(cs.models, PILLAR_MODEL, transform, pier, tag)
	end
end

-- Track ---------------------------------------------------------------------

-- Elevated slots sit at z = EZ so they are clickable on the viaduct; module code works from ground level.
local function groundTransf(t)
	local g = {}
	for i = 1, 16 do g[i] = t[i] end
	g[15] = 0
	return g
end

local function updateTrack(captureParams, result, transform, tag, slotId, addModel, constrParams)
	if result.jpst.layout.ignored[slotId] then return end
	local J = result.jpst
	local L = J.layout
	local _, level, row, seg = layout.decode(slotId)
	local elevated = level == ELEVATED
	if elevated then transform = groundTransf(transform) end

	local opts = nil
	if elevated then
		opts = { z = EZ, edgeType = "BRIDGE", edgeTypeName = layout.BRIDGE_TYPE }
	end
	local reg = layout.addTrackEdges(result, transform[13], transform[14], tag,
		captureParams.template, captureParams.catenary,
		not layout.isTrack(L, row, seg - 1), not layout.isTrack(L, row, seg + 1), opts)
	J.tracks[row] = J.tracks[row] or {}
	J.tracks[row][seg] = reg

	local w = layout.width(L, row)
	if elevated then
		addBox(result.cargoStation, transform, -w / 2, -20, w / 2, 20, nil, "EQUAL", layout.GROUND_MODES_PLATFORM)
		addConcourse(result.cargoStation, transform, w, 0)
	else
		addBox(result, transform, -w / 2, -20, w / 2, 20, nil, "EQUAL", nil)
	end
	addUnderground(result.cargoStation, transform, w)
end

local function getModelsTrack(captureParams, params)
	return {}
end

-- Platform ------------------------------------------------------------------

local function updatePlatform(captureParams, result, transform, tag, slotId, addModel, constrParams)
	if result.jpst.layout.ignored[slotId] then return end
	local cs = result.cargoStation
	local J = result.jpst
	local L = J.layout
	local _, level, row, seg = layout.decode(slotId)
	local cfg = captureParams
	local w = cfg.width
	local sx = cfg.stairsX
	local elevated = level == ELEVATED
	if elevated then transform = groundTransf(transform) end
	local z = elevated and EZ or 0
	local top = z + H
	-- elevated stairs need a longer run, so they start closer to the segment centre
	local stairY = elevated and 5 or 7.5

	for _, m in ipairs(cfg.models) do
		addModelTo(cs.models, m.id, transform, lift(perronTransf(m.x), z), tag)
	end
	-- neighbours must share the level to count (rows are single-level, so checking the row is enough)
	if not layout.isPlatform(L, row, seg - 1) then
		addModelTo(cs.models, cfg.endModel, transform, lift(transf.rotZTransl(math.rad(-90), vec3.new(0, -20, 0)), z), tag)
	end
	if not layout.isPlatform(L, row, seg + 1) then
		addModelTo(cs.models, cfg.endModel, transform, lift(transf.rotZTransl(math.rad(90), vec3.new(0, 20, 0)), z), tag)
	end
	if cfg.borderModel then
		local myLevel = layout.rowLevel(L, row)
		if layout.isTrack(L, row - 1, seg) and layout.rowLevel(L, row - 1) == myLevel then
			addModelTo(cs.models, cfg.borderModel, transform, lift(transf.rotZTransl(math.rad(90), vec3.new(-(w - 5) / 2, -20, 0)), z), tag)
		end
		if layout.isTrack(L, row + 1, seg) and layout.rowLevel(L, row + 1) == myLevel then
			addModelTo(cs.models, cfg.borderModel, transform, lift(transf.rotZTransl(math.rad(270), vec3.new((w - 5) / 2, 20, 0)), z), tag)
		end
	end

	if elevated then
		addViaduct(cs, transform, w, tag)
		addBox(cs, transform, -w / 2, -20, w / 2, 20, 3, "EQUAL", layout.GROUND_MODES_PLATFORM, EZ)
	else
		addBox(cs, transform, -w / 2, -20, w / 2, 20, 6, "EQUAL", layout.GROUND_MODES_PLATFORM)
	end

	-- Terminal lanes 1 m inside each platform edge (same node layout as vanilla: 4 edges).
	local xm, xp = -(w / 2 - 1), w / 2 - 1
	local function edgeLane(x)
		return layout.addLane(cs, {
			{ x, 20, top }, { x, stairY, top }, { x, 0, top }, { x, -stairY, top }, { x, -20, top },
		}, TERMINAL_LANE_WIDTH, false, transform)
	end
	local minus = edgeLane(xm)
	local plus = edgeLane(xp)
	J.platforms[row] = J.platforms[row] or {}
	J.platforms[row][seg] = { minus = minus, plus = plus }

	if sx and elevated then
		for _, y in ipairs({ -stairY, stairY }) do
			layout.addLane(cs, { { xm, y, top }, { sx, y, top }, { xp, y, top } }, LANE_WIDTH, false, transform)
			-- descend outward to the concourse at the segment end (about 15 m run for an 11 m drop)
			local dir = (y < 0) and -1 or 1
			layout.addLane(cs, { { sx, y, top }, { sx, dir * 20, 0 } }, LANE_WIDTH, false, transform)
		end
	elseif sx then
		for _, y in ipairs({ -stairY, stairY }) do
			layout.addLane(cs, { { xm, y, top }, { sx, y, top }, { xp, y, top } }, LANE_WIDTH, false, transform)
			-- same shape as the vanilla underpass stairs: walk in at platform level, descend to y=0, then drop to the passage
			local mid = (y < 0) and -2 or -3
			layout.addLane(cs, { { sx, y, top }, { sx, y * 2 / 3, top }, { sx, 0, mid }, { sx, 0, UZ } }, LANE_WIDTH, false, transform)
		end
	else
		layout.addLane(cs, { { xm, 0, top }, { xp, 0, top } }, LANE_WIDTH, false, transform)
	end

	if elevated then
		addConcourse(cs, transform, layout.width(L, row), sx or 0)
	end
	addUnderground(cs, transform, layout.width(L, row), sx)
end

local function getModelsPlatform(captureParams, params)
	local res = {}
	for _, m in ipairs(captureParams.models) do
		table.insert(res, { id = m.id, transf = perronTransf(m.x) })
	end
	table.insert(res, { id = captureParams.endModel, transf = transf.rotZTransl(math.rad(-90), vec3.new(0, -20, 0)) })
	table.insert(res, { id = captureParams.endModel, transf = transf.rotZTransl(math.rad(90), vec3.new(0, 20, 0)) })
	return res
end

-- Building ------------------------------------------------------------------
-- Functional part of every station building; the look ("skin") comes from the module params, so other
-- mods can add buildings by shipping only a module file (see README "駅舎スキン").
-- Local frame: origin at the middle of the front, front edge (y=0) touches the outermost row, +X runs
-- along the tracks, the building extends towards -Y and the street side lies beyond y=-depth.
-- params: models = { "m.mdl" | { id=, transf={16} } | { id=, x=, y=, z=, rotZ=deg } , ... }
--         length (m, default 40*size-2), depth (m, default 17), height (collider, default 8)

local BUILDING_HALL_Y = -8

local function buildingModelTransf(m)
	if type(m) == "string" then return m, transf.identity() end
	if m.transf then return m.id, m.transf end
	return m.id, transf.rotZTransl(math.rad(m.rotZ or 0), vec3.new(m.x or 0, m.y or 0, m.z or 0))
end

local function buildingDims(cfg, size)
	return cfg.length or (layout.SEG_LEN * size - 2), cfg.depth or 17, cfg.height or 8
end

local function updateBuilding(captureParams, result, transform, tag, slotId, addModel, constrParams)
	local J = result.jpst
	local L = J.layout
	local b = L.buildings[slotId]
	if L.ignored[slotId] or not b then return end
	local cs = result.cargoStation
	local cfg = captureParams
	local size = b.size
	local len, depth, height = buildingDims(cfg, size)
	transform = layout.buildingTransf(L, b.side, b.seg, size)

	for _, m in ipairs(cfg.models or {}) do
		local id, t = buildingModelTransf(m)
		addModelTo(cs.models, id, transform, t, tag)
	end
	addBox(cs, transform, -len / 2, -depth, len / 2, 0, height, "EQUAL", layout.GROUND_MODES_PLATFORM)

	-- local X of each covered segment centre
	local xs = {}
	for s = b.seg, b.seg + size - 1 do
		table.insert(xs, { s = s, x = layout.buildingLocalX(b.side, b.seg, size, s) })
	end
	table.sort(xs, function(a, c) return a.x < c.x end)

	-- street side (linkable) -> hall -> one access per covered segment
	local streetY = -(depth - 3)
	local half = math.max(len / 2 - 1, 1)
	local street, hall = { { -half, streetY, 0 } }, {}
	for _, e in ipairs(xs) do
		if e.x > -half + 0.01 and e.x < half - 0.01 then table.insert(street, { e.x, streetY, 0 }) end
		table.insert(hall, { e.x, BUILDING_HALL_Y, 0 })
	end
	table.insert(street, { half, streetY, 0 })
	layout.addLane(cs, street, LANE_WIDTH, true, transform)
	if #hall > 1 then layout.addLane(cs, hall, LANE_WIDTH, false, transform) end

	for _, e in ipairs(xs) do
		local x = e.x
		layout.addLane(cs, { { x, streetY, 0 }, { x, BUILDING_HALL_Y, 0 } }, LANE_WIDTH, false, transform)
		-- gap between the building front and this segment's outer row edge
		local xL, xR = layout.segEdges(L, e.s)
		local gap = (b.side == layout.SIDE.MINUS_X) and (xL - b.front) or (b.front - xR)
		if gap < 0.01 then gap = 0 end
		-- underground passage at the row edge
		layout.addLane(cs, { { x, BUILDING_HALL_Y, 0 }, { x, -4, -2 }, { x, 0, UZ } }, LANE_WIDTH, false, transform)
		if gap > 0 then
			layout.addLane(cs, { { x, 0, UZ }, { x, gap, UZ } }, LANE_WIDTH, false, transform)
		end
		-- direct ground-level access to the outermost row
		local sg = L.segs[e.s]
		local row = (b.side == layout.SIDE.MINUS_X) and sg.minRow or sg.maxRow
		if layout.isElevated(L, row) then
			layout.addLane(cs, { { x, BUILDING_HALL_Y, 0 }, { x, gap, 0 } }, LANE_WIDTH, false, transform)
		elseif layout.isPlatform(L, row, e.s) then
			layout.addLane(cs, { { x, BUILDING_HALL_Y, 0 }, { x, gap - 2, H }, { x, gap + 1, H } }, LANE_WIDTH, false, transform)
		end
	end
end

-- Concourse (橋上駅舎 + 自由通路) -----------------------------------------------
-- One module per segment, 2F floor at CZ spanning every ground row. Platforms reach it by ramps
-- from both segment ends; each outer side either drops into the station building or into a public
-- exit stair that ends at a linkable (street) lane, so the passage also works as a free walkway.

local CZ = layout.CONCOURSE_Z
local CHW = layout.CONCOURSE_HALF_WIDTH
local CONCOURSE_OVERHANG = 4 -- deck beyond the outer row edge
local EXIT_RUN = 16          -- horizontal run of the exit stair (9 m drop)
local RAMP_WIDTH = 3
local RAMP_DEPTH_SCALE = 0.3

-- Stretch the 6 x 4 m concrete deck piece (local X 0..6, Y 0..4, top at z=0) between two points.
local function beamTransf(p0, p1, width, depthScale)
	local dx, dy, dz = p1[1] - p0[1], p1[2] - p0[2], p1[3] - p0[3]
	local hl = math.sqrt(dx * dx + dy * dy)
	local hx, hy = dx / hl, dy / hl
	local yx, yy = -hy, hx
	local zx, zy, zz = -dz * hx, -dz * hy, dx * hx + dy * hy
	local zl = math.sqrt(zx * zx + zy * zy + zz * zz)
	local ds = (depthScale or 1) / zl
	local hw = width / 2
	return {
		dx / 6, dy / 6, dz / 6, 0,
		yx * width / 4, yy * width / 4, 0, 0,
		zx * ds, zy * ds, zz * ds, 0,
		p0[1] - yx * hw, p0[2] - yy * hw, p0[3], 1,
	}
end

local function updateConcourse(captureParams, result, transform, tag, slotId, addModel, constrParams)
	if result.jpst.layout.ignored[slotId] then return end
	local cs = result.cargoStation
	local L = result.jpst.layout
	local _, _, _, seg = layout.decode(slotId)
	local s = L.segs[seg]
	if not s then return end
	-- work in station X / absolute Z, segment-local Y
	local T = transf.transl(vec3.new(0, layout.segY(seg), 0))
	local xL, xR = layout.segEdges(L, seg)
	-- front X of the building covering this segment on each side (may lie beyond this segment's rows)
	local front = {}
	for _, side in ipairs({ layout.SIDE.MINUS_X, layout.SIDE.PLUS_X }) do
		local bid = L.buildingAt[side][seg]
		front[side] = bid and L.buildings[bid].front or nil
	end
	local hasBuilding = { [layout.SIDE.MINUS_X] = front[0] ~= nil, [layout.SIDE.PLUS_X] = front[1] ~= nil }
	local deckL = front[layout.SIDE.MINUS_X] or xL - CONCOURSE_OVERHANG
	local deckR = front[layout.SIDE.PLUS_X] or xR + CONCOURSE_OVERHANG

	addModelTo(cs.models, DECK_MODEL, T, beamTransf({ deckL, 0, CZ }, { deckR, 0, CZ }, CHW * 2), tag)
	local pierH = CZ - DECK_DEPTH
	local function pier(x)
		for _, y in ipairs({ -CHW + 1.5, CHW - 1.5 }) do
			local t = transf.scaleXYZRotZTransl(vec3.new(1, 1, pierH / 4), math.rad(90), vec3.new(x + 1.5, y, 0))
			addModelTo(cs.models, PILLAR_MODEL, T, t, tag)
		end
	end

	-- 2F walkway across the station (nodes at every platform and at both ends)
	local cross = { deckL, deckR }
	local platformRows = {}
	for row = s.minRow, s.maxRow do
		local c = layout.get(L, row, seg)
		if c and c.kind == layout.KIND.PLATFORM then
			table.insert(platformRows, { row = row, cell = c })
			table.insert(cross, layout.centre(L, row))
		end
	end
	table.sort(cross)
	local pts = {}
	for i, x in ipairs(cross) do
		if i == 1 or x - cross[i - 1] > 0.01 then table.insert(pts, { x, 0, CZ }) end
	end
	layout.addLane(cs, pts, LANE_WIDTH, false, T)

	-- ramps from both platform ends up to the deck
	local top = H
	for _, pr in ipairs(platformRows) do
		local c = layout.centre(L, pr.row)
		local w = (pr.cell.module.metadata and pr.cell.module.metadata.jpst_width) or layout.width(L, pr.row)
		local xm, xp = c - (w / 2 - 1), c + (w / 2 - 1)
		pier(c)
		layout.addLane(cs, { { c, -CHW, CZ }, { c, 0, CZ }, { c, CHW, CZ } }, LANE_WIDTH, false, T)
		for _, dir in ipairs({ -1, 1 }) do
			local yEnd = dir * 20
			-- the boundary cross lane is shared with a concourse in the next segment; add it once
			if not (dir > 0 and L.concourses[seg + 1]) then
				layout.addLane(cs, { { xm, yEnd, top }, { c, yEnd, top }, { xp, yEnd, top } }, LANE_WIDTH, false, T)
			end
			layout.addLane(cs, { { c, yEnd, top }, { c, dir * CHW, CZ } }, LANE_WIDTH, false, T)
			addModelTo(cs.models, DECK_MODEL, T,
				beamTransf({ c, yEnd, top }, { c, dir * CHW, CZ }, RAMP_WIDTH, RAMP_DEPTH_SCALE), tag)
		end
	end

	-- outer sides: into the station building, or a public exit stair to street level
	for _, side in ipairs({ layout.SIDE.MINUS_X, layout.SIDE.PLUS_X }) do
		local dir = (side == layout.SIDE.MINUS_X) and -1 or 1
		local xDeck = (dir < 0) and deckL or deckR
		if hasBuilding[side] then
			-- building concourse node sits 8 m outside the row edge at ground level
			layout.addLane(cs, { { xDeck, 0, CZ }, { front[side] - dir * BUILDING_HALL_Y, 0, 0 } }, LANE_WIDTH, false, T)
		else
			pier(xDeck - dir * 1.5)
			local xFoot = xDeck + dir * EXIT_RUN
			layout.addLane(cs, { { xDeck, 0, CZ }, { xFoot, 0, 0 } }, LANE_WIDTH, false, T)
			addModelTo(cs.models, DECK_MODEL, T,
				beamTransf({ xDeck, 0, CZ }, { xFoot, 0, 0 }, RAMP_WIDTH, RAMP_DEPTH_SCALE), tag)
			layout.addLane(cs, { { xFoot, -8, 0 }, { xFoot, 0, 0 }, { xFoot, 8, 0 } }, LANE_WIDTH, true, T)
			local x0, x1 = math.min(xFoot, xFoot - dir * 4), math.max(xFoot, xFoot - dir * 4)
			addBox(cs, T, x0, -8, x1, 8, nil, "EQUAL", layout.GROUND_MODES_PLATFORM)
		end
	end
end

local function getModelsConcourse(captureParams, params)
	return {
		{ id = DECK_MODEL, transf = beamTransf({ -10, 0, 0 }, { 10, 0, 0 }, CHW * 2) },
	}
end

local function getModelsBuilding(captureParams, params)
	local res = {}
	for _, m in ipairs(captureParams.models or {}) do
		local id, t = buildingModelTransf(m)
		table.insert(res, { id = id, transf = t })
	end
	return res
end

function data()
	return {
		track = {
			updateFn = updateTrack,
			getModelsFn = getModelsTrack,
		},
		platform = {
			updateFn = updatePlatform,
			getModelsFn = getModelsPlatform,
		},
		building = {
			updateFn = updateBuilding,
			getModelsFn = getModelsBuilding,
		},
		concourse = {
			updateFn = updateConcourse,
			getModelsFn = getModelsConcourse,
		},
	}
end
