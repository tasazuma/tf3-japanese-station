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

-- vanilla platform furniture faces along local X, so turn it to run along Y like the perrons
local function signTransf(s)
	return transf.rotZTransl(math.rad(90 + (s.rotZ or 0)), vec3.new(s.x or 0, s.y or 0, s.z or 0))
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
-- A 高架下駅舎 in the segment brings its own column grid, so the stand-in piers are left out there.
local function addViaduct(cs, transform, w, tag, noPiers)
	local deck = transf.scaleXYZRotZTransl(vec3.new(40 / 6, w / 4, 1), math.rad(90), vec3.new(w / 2, -20, EZ))
	addModelTo(cs.models, DECK_MODEL, transform, deck, tag)
	if noPiers then return end
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
	local stairY = 7.5

	for _, m in ipairs(cfg.models) do
		addModelTo(cs.models, m.id, transform, lift(perronTransf(m.x), z), tag)
	end
	for _, s in ipairs(cfg.signs or {}) do
		-- labelText is keyed by the 0-based index into cargoStation.models; the hook fills it
		if s.label then table.insert(J.signs, { index = #cs.models, label = s.label, row = row, seg = seg }) end
		addModelTo(cs.models, s.id, transform, lift(signTransf(s), z), tag)
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
		addViaduct(cs, transform, w, tag, L.underViaducts[seg] ~= nil)
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
			-- follow the stair model (it descends towards the segment centre like the vanilla underpass),
			-- then turn back under the deck and descend outward to the concourse at the segment end
			local dir = (y < 0) and -1 or 1
			local turn = { sx, dir * 1, EZ - DECK_DEPTH }
			layout.addLane(cs, { { sx, y, top }, { sx, y * 2 / 3, top }, turn }, LANE_WIDTH, false, transform)
			layout.addLane(cs, { turn, { sx, dir * 20, 0 } }, LANE_WIDTH, false, transform)
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
	for _, s in ipairs(captureParams.signs or {}) do
		table.insert(res, { id = s.id, transf = signTransf(s) })
	end
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
	-- the layout (forecourt base line) uses metadata.jpst_depth; follow it so both agree
	if b.module and b.module.metadata and b.module.metadata.jpst_depth then depth = b.depth end
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

-- Station building under the viaduct (高架下駅舎) -------------------------------------
-- One module per segment at ground level under its elevated rows (綱島・大倉山 style: ticket hall between
-- the viaduct columns). The ground lanes under the viaduct come from the elevated cells (cross lane at
-- y=0); this module adds a public street exit on every outer side of the station that has no building,
-- so an elevated station works without a side building. The look comes from params (skins):
--   columns = { id, rotZ, scale = { sx, sy, sz }, offset = { x, y }, ys = { ... }, minGap }: a column at
--             every ys (segment-local Y) on both outer edges of each elevated block and on inner row
--             boundaries at least minGap apart;
--   exitModels = models at every street exit, building frame: origin at the row edge (segment centre),
--             +X along the tracks, -Y out of the station;
--   hallModels = models per elevated block, relative to its centre (station X, segment-local Y).

local UNDER_EXIT_RUN = 4 -- paved exit outside the row edge; its far end is the linkable street lane
local UNDER_COLUMN_INSET = 0.5

local function underBlockEdges(L, b)
	return layout.centre(L, b.first) - layout.width(L, b.first) / 2, layout.centre(L, b.last) + layout.width(L, b.last) / 2
end

local function updateUnderViaduct(captureParams, result, transform, tag, slotId, addModel, constrParams)
	local L = result.jpst.layout
	if L.ignored[slotId] or not L.underViaducts then return end
	local _, _, _, seg = layout.decode(slotId)
	if L.underViaducts[seg] ~= slotId then return end
	local cs = result.cargoStation
	local cfg = captureParams or {}
	local s = L.segs[seg]
	local T = transf.transl(vec3.new(0, layout.segY(seg), 0))

	for _, b in ipairs(layout.elevatedBlocks(L, seg)) do
		local x0, x1 = underBlockEdges(L, b)

		local col = cfg.columns
		if col and col.id then
			local xs = { x0 + UNDER_COLUMN_INSET }
			local minGap = col.minGap or 6
			local last = xs[1]
			for row = b.first, b.last - 1 do
				local xb = layout.centre(L, row) + layout.width(L, row) / 2
				if xb - last >= minGap and x1 - xb >= minGap then
					table.insert(xs, xb)
					last = xb
				end
			end
			table.insert(xs, x1 - UNDER_COLUMN_INSET)
			local sc = col.scale or { 1, 1, 1 }
			local off = col.offset or { 0, 0 }
			for _, x in ipairs(xs) do
				for _, y in ipairs(col.ys or { -15, -5, 5, 15 }) do
					local t = transf.scaleXYZRotZTransl(vec3.new(sc[1], sc[2], sc[3]), math.rad(col.rotZ or 0),
						vec3.new(x + off[1], y + off[2], 0))
					addModelTo(cs.models, col.id, T, t, tag)
				end
			end
		end

		local C = transf.mul(T, transf.transl(vec3.new((x0 + x1) / 2, 0, 0)))
		for _, m in ipairs(cfg.hallModels or {}) do
			local id, t = buildingModelTransf(m)
			addModelTo(cs.models, id, C, t, tag)
		end

		-- public exits on the outer sides of the station without a building
		for _, side in ipairs({ layout.SIDE.MINUS_X, layout.SIDE.PLUS_X }) do
			local outer = (side == layout.SIDE.MINUS_X) and b.first == s.minRow or (side == layout.SIDE.PLUS_X and b.last == s.maxRow)
			if outer and not L.buildingAt[side][seg] then
				local dir = (side == layout.SIDE.MINUS_X) and -1 or 1
				local xEdge = (dir < 0) and x0 or x1
				local xFoot = xEdge + dir * UNDER_EXIT_RUN
				layout.addLane(cs, { { xEdge, 0, 0 }, { xFoot, 0, 0 } }, LANE_WIDTH, false, T)
				layout.addLane(cs, { { xFoot, -8, 0 }, { xFoot, 0, 0 }, { xFoot, 8, 0 } }, LANE_WIDTH, true, T)
				addBox(cs, T, math.min(xEdge, xFoot), -8, math.max(xEdge, xFoot), 8, nil, "EQUAL", layout.GROUND_MODES_PLATFORM)
				local E = transf.mul(T, transf.rotZTransl(math.rad(dir < 0 and -90 or 90), vec3.new(xEdge, 0, 0)))
				for _, m in ipairs(cfg.exitModels or {}) do
					local id, t = buildingModelTransf(m)
					addModelTo(cs.models, id, E, t, tag)
				end
			end
		end
	end
end

local function getModelsUnderViaduct(captureParams, params)
	local res = {}
	for _, key in ipairs({ "hallModels", "exitModels" }) do
		for _, m in ipairs((captureParams or {})[key] or {}) do
			local id, t = buildingModelTransf(m)
			table.insert(res, { id = id, transf = t })
		end
	end
	return res
end

-- Forecourt (駅前) -------------------------------------------------------------
-- Functional part of every forecourt module: ground, terrain and a walkable lane grid; the look comes from
-- the module params so other mods can add plazas by shipping only a module file (see README "駅前").
-- Local frame: origin at the centre of the covered w x h cells (40 m each), +X along the tracks, +Y towards
-- the station. The module spans x = -w*20..w*20, y = -h*20..h*20.
-- params: ground = { modes } (groundFaces modes, default paving), terrain = "EQUAL" | "LESS" | ...,
--         cellModels = models placed in every cell relative to the cell centre (same forms as buildings),
--         models = models placed once relative to the module centre,
--         lanes = "cross" (default, both directions) | "along" (一の字 along the tracks, x) |
--                 "through" (一の字 towards the station, y) | "none".
-- Lanes: a linkable grid through the cell centres, with nodes on the cell edges so neighbouring forecourt
-- modules connect; modules in the first row also connect to the street lane of the building behind them.

local FORECOURT_GROUND = {
	{ type = "FILL", key = "::/buildings/shared/building_paving_fill.gtex" },
	{ type = "STROKE_OUTER", key = "::/infrastructure/street/shared/street_border.gtex" },
}

local function forecourtCells(w, h)
	local C = layout.FORECOURT_CELL
	local xs, ys = {}, {}
	for i = 0, w - 1 do xs[#xs + 1] = -w * C / 2 + C / 2 + i * C end
	for j = 0, h - 1 do ys[#ys + 1] = -h * C / 2 + C / 2 + j * C end
	return xs, ys
end

local function updateForecourt(captureParams, result, transform, tag, slotId, addModel, constrParams)
	local J = result.jpst
	local L = J.layout
	local f = L.forecourts[slotId]
	if L.ignored[slotId] or not f or f.level ~= layout.LEVEL.GROUND then return end
	local cs = result.cargoStation
	local cfg = captureParams or {}
	local C = layout.FORECOURT_CELL
	local w, h = f.w, f.h
	local hx, hy = w * C / 2, h * C / 2
	transform = layout.forecourtTransf(L, f.side, f.seg, f.d, w, h)
	local modes = cfg.ground or FORECOURT_GROUND
	local align = cfg.terrain or "EQUAL"

	addBox(cs, transform, -hx, -hy, hx, hy, nil, align, modes)

	local xs, ys = forecourtCells(w, h)
	for _, x in ipairs(xs) do
		for _, y in ipairs(ys) do
			for _, m in ipairs(cfg.cellModels or {}) do
				local id, t = buildingModelTransf(m)
				addModelTo(cs.models, id, transform, transf.mul(transf.transl(vec3.new(x, y, 0)), t), tag)
			end
		end
	end
	for _, m in ipairs(cfg.models or {}) do
		local id, t = buildingModelTransf(m)
		addModelTo(cs.models, id, transform, t, tag)
	end

	-- lane grid: one lane per cell row (along X) and per cell column (along Y), edge to edge
	local pattern = cfg.lanes or "cross"
	local alongX = pattern == "cross" or pattern == "along"
	local alongY = pattern == "cross" or pattern == "through"
	if alongX then for _, y in ipairs(ys) do
		local pts = { { -hx, y, 0 } }
		for _, x in ipairs(xs) do pts[#pts + 1] = { x, y, 0 } end
		pts[#pts + 1] = { hx, y, 0 }
		layout.addLane(cs, pts, LANE_WIDTH, true, transform)
	end end
	for s = f.seg, f.seg + w - 1 do
		local x = layout.forecourtColumnX(f.side, f.seg, w, s)
		if alongY then
			local pts = { { x, -hy, 0 } }
			for _, y in ipairs(ys) do pts[#pts + 1] = { x, y, 0 } end
			pts[#pts + 1] = { x, hy, 0 }
			layout.addLane(cs, pts, LANE_WIDTH, true, transform)
		end
		if f.d == 0 then
			-- bridge the gap to a shallower building and reach its street lane (3 m inside its back)
			local gap = layout.forecourtGap(L, f.side, s)
			if gap > 0.01 then
				addBox(cs, transform, x - C / 2, hy, x + C / 2, hy + gap, nil, align, modes)
			end
			if alongY then
				layout.addLane(cs, { { x, hy, 0 }, { x, hy + gap + 3, 0 } }, LANE_WIDTH, false, transform)
			end
		end
	end
end

-- Bus rotary (バスロータリー) ------------------------------------------------------------
-- A 1F forecourt module (same slots / grid as the plazas) with a bus loop and one bus stop terminal per
-- cell column along the station side. Functional part: street stub at the outer edge (centre, snaps to a
-- road), one-lane bus loop (lanes, like the vanilla street station), stop lanes + sidewalk terminals, and a
-- linkable sidewalk that reaches the building street lane (row 0), the plaza grid of neighbouring modules
-- (side edges, through the cell-centre rows) and the next module towards the station (row > 0).
-- Local frame as forecourt (+Y towards the station). Buses run counter-clockwise seen from above:
-- in at x = +2.5, along the stops towards -X, out at x = -2.5.
-- params: ground / sidewalkGround / islandGround = groundFaces modes, terrain = "EQUAL" | ...,
--         streetTemplate = street template of the stub (default entrance_new),
--         stopModels = models per terminal, relative to (terminal centre x, kerb y), +Y = into the sidewalk,
--         models = models relative to the module centre.

local ROTARY_GROUND = {
	{ type = "FILL", key = "::/infrastructure/street/shared/street_fill.gtex" },
	{ type = "STROKE_OUTER", key = "::/infrastructure/street/shared/street_border.gtex" },
}
local ROTARY_SIDEWALK = {
	{ type = "FILL", key = "::/infrastructure/street/shared/street_sidewalk_fill.gtex" },
}
local ROTARY_ISLAND = {
	{ type = "FILL", key = "::/terrain/materials/grass_cutted_01/grass_cutted_01.gtex" },
	{ type = "STROKE_OUTER", key = "::/infrastructure/street/shared/street_border.gtex" },
}
local BUS_MODES = { "BUS" }
local BUS_LANE_WIDTH = 3
local function lpt(t, x, y, z)
	return { t[1] * x + t[5] * y + t[9] * z + t[13], t[2] * x + t[6] * y + t[10] * z + t[14],
		t[3] * x + t[7] * y + t[11] * z + t[15] }
end
local function ldir(t, x, y, z)
	return { t[1] * x + t[5] * y + t[9] * z, t[2] * x + t[6] * y + t[10] * z, t[3] * x + t[7] * y + t[11] * z }
end

local function updateBusRotary(captureParams, result, transform, tag, slotId, addModel, constrParams)
	local J = result.jpst
	local L = J.layout
	local f = L.forecourts[slotId]
	if L.ignored[slotId] or not f or f.level ~= layout.LEVEL.GROUND then return end
	local cs = result.cargoStation
	local cfg = captureParams or {}
	local w, h = f.w, f.h
	local g = layout.rotaryGeometry(w, h)
	local hx, hy = g.hx, g.hy
	transform = layout.forecourtTransf(L, f.side, f.seg, f.d, w, h)
	local align = cfg.terrain or "EQUAL"
	local sidewalk = cfg.sidewalkGround or ROTARY_SIDEWALK

	addBox(cs, transform, -hx, -hy, hx, g.kerbY, nil, align, cfg.ground or ROTARY_GROUND)
	addBox(cs, transform, -hx, g.kerbY, hx, hy, nil, align, sidewalk)
	local is = g.island
	if is[3] > is[1] and is[4] > is[2] then
		addBox(cs, transform, is[1], is[2], is[3], is[4], nil, align, cfg.islandGround or ROTARY_ISLAND)
	end

	for _, st in ipairs(g.stops) do
		local cx = (st[1] + st[2]) / 2
		for _, m in ipairs(cfg.stopModels or {}) do
			local id, t = buildingModelTransf(m)
			addModelTo(cs.models, id, transform, transf.mul(transf.transl(vec3.new(cx, g.kerbY, 0)), t), tag)
		end
	end
	for _, m in ipairs(cfg.models or {}) do
		local id, t = buildingModelTransf(m)
		addModelTo(cs.models, id, transform, t, tag)
	end

	-- street stub: outer node snaps to a road; its two driving lanes meet the loop at x = +-2.5
	J.streets = J.streets or {}
	local tng = ldir(transform, 0, g.entryY + hy, 0)
	table.insert(J.streets, {
		type = "STREET",
		params = {
			type = cfg.streetTemplate or "::/infrastructure/street/constructions/entrance_new.street_template",
			tramTrackType = "NO",
		},
		edges = { { lpt(transform, 0, -hy, 0), tng }, { lpt(transform, 0, g.entryY, 0), tng } },
		snapNodes = { 0 },
	})

	-- bus loop
	layout.addCurveLane(cs, g.inbound, BUS_LANE_WIDTH, BUS_MODES, { 0, 1, 0 }, { -1, 0, 0 }, transform)
	layout.addCurveLane(cs, g.outbound, BUS_LANE_WIDTH, BUS_MODES, { -1, 0, 0 }, { 0, -1, 0 }, transform)

	-- sidewalk along the stops: nodes at the stop ends, stop centres and the column connectors
	local cols = {}
	for s = f.seg, f.seg + w - 1 do cols[#cols + 1] = layout.forecourtColumnX(f.side, f.seg, w, s) end
	local function walkPoints(x1, x0)
		local xs = { x1, x0, (x1 + x0) / 2 }
		for _, x in ipairs(cols) do if x < x1 - 0.01 and x > x0 + 0.01 then xs[#xs + 1] = x end end
		table.sort(xs, function(a, b) return a > b end)
		local pts, last = {}, nil
		for _, x in ipairs(xs) do
			if not last or math.abs(x - last) > 0.01 then pts[#pts + 1] = { x, g.walkY, 0 } end
			last = x
		end
		return pts
	end
	J.busStops = J.busStops or {}
	for _, st in ipairs(g.stops) do
		local mid = (st[1] + st[2]) / 2
		local vl = layout.addCurveLane(cs, { { st[1], g.stopY, 0 }, { mid, g.stopY, 0 }, { st[2], g.stopY, 0 } },
			BUS_LANE_WIDTH, BUS_MODES, { -1, 0, 0 }, { -1, 0, 0 }, transform)
		local pts = walkPoints(st[1], st[2])
		local pl = layout.addLane(cs, pts, LANE_WIDTH, false, transform)
		local personEdges, personNodes = {}, {}
		for e = 0, #pts - 2 do
			personEdges[#personEdges + 1] = { pl, e }
			personNodes[#personNodes + 1] = { pl, 2 * e }
		end
		personNodes[#personNodes + 1] = { pl, 2 * (#pts - 2) + 1 }
		table.insert(J.busStops, {
			personEdges = personEdges,
			personNodes = personNodes,
			vehicleNode = { vl, 2 },
			vehicleEdges = { { vl, 0 }, { vl, 1 } },
			length = st[1] - st[2],
		})
	end

	-- sidewalk ends to the side edges, then along the side edges through the cell-centre rows
	local C = layout.FORECOURT_CELL
	for _, sx in ipairs({ 1, -1 }) do
		local edge = { { sx * hx, g.walkY, 0 } }
		for j = h - 1, 0, -1 do
			local y = -hy + C / 2 + j * C
			if y < g.walkY - 0.01 then edge[#edge + 1] = { sx * hx, y, 0 } end
		end
		edge[#edge + 1] = { sx * hx, -hy, 0 }
		layout.addLane(cs, edge, LANE_WIDTH, true, transform)
		local inner = { { sx * g.stopX, g.walkY, 0 } }
		for _, x in ipairs(cols) do
			if sx * x > g.stopX + 0.01 and sx * x < hx - 0.01 then inner[#inner + 1] = { x, g.walkY, 0 } end
		end
		inner[#inner + 1] = { sx * hx, g.walkY, 0 }
		table.sort(inner, function(a, b) return sx * a[1] < sx * b[1] end)
		layout.addLane(cs, inner, LANE_WIDTH, true, transform)
	end

	-- towards the station: every column to the module edge; in row 0 across the gap to the street lane
	for s = f.seg, f.seg + w - 1 do
		local x = layout.forecourtColumnX(f.side, f.seg, w, s)
		layout.addLane(cs, { { x, g.walkY, 0 }, { x, hy, 0 } }, LANE_WIDTH, true, transform)
		if f.d == 0 then
			local gap = layout.forecourtGap(L, f.side, s)
			if gap > 0.01 then
				addBox(cs, transform, x - C / 2, hy, x + C / 2, hy + gap, nil, align, sidewalk)
			end
			layout.addLane(cs, { { x, hy, 0 }, { x, hy + gap + 3, 0 } }, LANE_WIDTH, false, transform)
		end
	end
end

local function getModelsBusRotary(captureParams, params)
	local res = {}
	local cfg = captureParams or {}
	for _, list in ipairs({ cfg.stopModels or {}, cfg.models or {} }) do
		for _, m in ipairs(list) do
			local id, t = buildingModelTransf(m)
			table.insert(res, { id = id, transf = t })
		end
	end
	return res
end

-- Pedestrian deck (ペデストリアンデッキ) ------------------------------------------------
-- Forecourt level 1: the same 40 m grid as the 1F plazas, floor at DZ (= 2F concourse height), so a deck
-- can stand over a plaza. Functional part: walkway lanes on the deck, the link into the station (through
-- the building at 2F straight onto a 2F concourse in that column, and down into the building hall), and
-- stairs down to street level whose foot meets the 1F plaza lane grid at the cell centre.
-- Frame and params as forecourt, plus:
--   structure = true (default) | false: stand-in concrete walkways, piers and stairs (false = skin draws all)
--   walkWidth = walkway width in m (3..10, default 8)
--   stairs = "outer" (default, one per column in the outermost cell row) | "all" (every cell) | "none"
--   models / cellModels are placed relative to the deck floor (z = 0 is the deck surface).
-- Stairs sit at x = cell centre + 16, running from the walkway edge 15 m away from the station.

local DZ = layout.DECK_Z
local STAIR_X = 16
local STAIR_RUN = 15

local function updateDeck(captureParams, result, transform, tag, slotId, addModel, constrParams)
	local J = result.jpst
	local L = J.layout
	local f = L.forecourts[slotId]
	if L.ignored[slotId] or not f or f.level ~= ELEVATED then return end
	local cs = result.cargoStation
	local cfg = captureParams or {}
	local C = layout.FORECOURT_CELL
	local w, h = f.w, f.h
	local hx, hy = w * C / 2, h * C / 2
	transform = layout.forecourtTransf(L, f.side, f.seg, f.d, w, h)
	local structure = cfg.structure ~= false
	local ww = math.max(3, math.min(10, cfg.walkWidth or 8))
	local pattern = cfg.lanes or "cross"
	local alongX = pattern == "cross" or pattern == "along"
	local alongY = pattern == "cross" or pattern == "through"
	local stairs = cfg.stairs or "outer"
	local xs, ys = forecourtCells(w, h)

	local function beam(p0, p1, width, depthScale)
		if structure then addModelTo(cs.models, DECK_MODEL, transform, beamTransf(p0, p1, width, depthScale), tag) end
	end
	local function pier(x, y)
		if not structure then return end
		local t = transf.scaleXYZRotZTransl(vec3.new(1, 1, (DZ - DECK_DEPTH) / 4), math.rad(90), vec3.new(x + 1.5, y, 0))
		addModelTo(cs.models, PILLAR_MODEL, transform, t, tag)
	end

	for _, x in ipairs(xs) do
		for _, y in ipairs(ys) do
			for _, m in ipairs(cfg.cellModels or {}) do
				local id, t = buildingModelTransf(m)
				addModelTo(cs.models, id, transform, transf.mul(transf.transl(vec3.new(x, y, DZ)), t), tag)
			end
			for _, px in ipairs({ -3, 3 }) do for _, py in ipairs({ -3, 3 }) do pier(x + px, y + py) end end
		end
	end
	for _, m in ipairs(cfg.models or {}) do
		local id, t = buildingModelTransf(m)
		addModelTo(cs.models, id, transform, transf.mul(transf.transl(vec3.new(0, 0, DZ)), t), tag)
	end

	-- walkways: lanes edge to edge through the cell centres (nodes on the edges join neighbouring decks)
	if alongX then for _, y in ipairs(ys) do
		local pts = { { -hx, y, DZ } }
		for _, x in ipairs(xs) do pts[#pts + 1] = { x, y, DZ } end
		pts[#pts + 1] = { hx, y, DZ }
		layout.addLane(cs, pts, LANE_WIDTH, false, transform)
		beam({ -hx, y, DZ }, { hx, y, DZ }, ww)
	end end
	for s = f.seg, f.seg + w - 1 do
		local x = layout.forecourtColumnX(f.side, f.seg, w, s)
		if alongY then
			local pts = { { x, -hy, DZ } }
			for _, y in ipairs(ys) do pts[#pts + 1] = { x, y, DZ } end
			pts[#pts + 1] = { x, hy, DZ }
			layout.addLane(cs, pts, LANE_WIDTH, false, transform)
			-- split around the crossing walkways so the stretched pieces do not overlap (z-fighting)
			local y0 = -hy
			for _, y in ipairs(ys) do
				local y1 = alongX and (y - ww / 2) or y
				if y1 - y0 > 0.01 then beam({ x, y0, DZ }, { x, y1, DZ }, ww) end
				y0 = alongX and (y + ww / 2) or y
			end
			if hy - y0 > 0.01 then beam({ x, y0, DZ }, { x, hy, DZ }, ww) end
		end
		if f.d == 0 then
			-- into the station: over the gap to a shallower building, then through the building at 2F
			local b = L.buildings[L.buildingAt[f.side][s]]
			local yBack = hy + layout.forecourtGap(L, f.side, s)
			local yFront = yBack + b.depth
			local pts = { { x, hy, DZ } }
			if not alongY then
				pts = { { x, ys[#ys], DZ }, { x, hy, DZ } }
				beam({ x, ys[#ys] + (alongX and ww / 2 or 0), DZ }, { x, hy, DZ }, ww)
			end
			if yBack - hy > 0.01 then
				pts[#pts + 1] = { x, yBack, DZ }
				beam({ x, hy, DZ }, { x, yBack, DZ }, ww)
			end
			if L.concourses[s] then pts[#pts + 1] = { x, yFront, DZ } end
			if #pts >= 2 then layout.addLane(cs, pts, LANE_WIDTH, false, transform) end
			-- down into the building hall (same node as the building's hall lane)
			layout.addLane(cs, { { x, yBack, DZ }, { x, yFront + BUILDING_HALL_Y, 0 } }, LANE_WIDTH, false, transform)
		end
	end

	-- stairs to street level; the foot lane is linkable and ends on the 1F plaza grid node at the cell centre
	if stairs ~= "none" then
		for _, x in ipairs(xs) do
			for j, y in ipairs(ys) do
				if stairs == "all" or j == 1 then
					local sx = x + STAIR_X
					local yTop = y - ww / 2
					local yFoot = yTop - STAIR_RUN
					layout.addLane(cs, { { x, y, DZ }, { sx, y, DZ }, { sx, yTop, DZ } }, LANE_WIDTH, false, transform)
					layout.addLane(cs, { { sx, yTop, DZ }, { sx, yFoot, 0 } }, LANE_WIDTH, false, transform)
					layout.addLane(cs, { { sx, yFoot, 0 }, { x, y, 0 } }, LANE_WIDTH, true, transform)
					if not alongX then beam({ x + (alongY and ww / 2 or 0), y, DZ }, { sx + RAMP_WIDTH / 2, y, DZ }, ww) end
					beam({ sx, yTop, DZ }, { sx, yFoot, 0 }, RAMP_WIDTH, RAMP_DEPTH_SCALE)
					addBox(cs, transform, sx - 2, yFoot - 1, sx + 2, yFoot + 4, nil, "EQUAL", layout.GROUND_MODES_PLATFORM)
				end
			end
		end
	end
end

local function getModelsDeck(captureParams, params)
	local res = {}
	local cfg = captureParams or {}
	if cfg.structure ~= false then
		res[#res + 1] = { id = DECK_MODEL, transf = beamTransf({ -10, 0, 0 }, { 10, 0, 0 }, 8) }
		res[#res + 1] = { id = DECK_MODEL, transf = beamTransf({ 0, -10, 0 }, { 0, -4, 0 }, 8) }
		res[#res + 1] = { id = DECK_MODEL, transf = beamTransf({ 0, 4, 0 }, { 0, 10, 0 }, 8) }
	end
	for _, m in ipairs(cfg.cellModels or {}) do
		local id, t = buildingModelTransf(m)
		table.insert(res, { id = id, transf = t })
	end
	for _, m in ipairs(cfg.models or {}) do
		local id, t = buildingModelTransf(m)
		table.insert(res, { id = id, transf = t })
	end
	return res
end

local function getModelsForecourt(captureParams, params)
	local res = {}
	local cfg = captureParams or {}
	for _, m in ipairs(cfg.cellModels or {}) do
		local id, t = buildingModelTransf(m)
		table.insert(res, { id = id, transf = t })
	end
	for _, m in ipairs(cfg.models or {}) do
		local id, t = buildingModelTransf(m)
		table.insert(res, { id = id, transf = t })
	end
	return res
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
		underviaduct = {
			updateFn = updateUnderViaduct,
			getModelsFn = getModelsUnderViaduct,
		},
		forecourt = {
			updateFn = updateForecourt,
			getModelsFn = getModelsForecourt,
		},
		busrotary = {
			updateFn = updateBusRotary,
			getModelsFn = getModelsBusRotary,
		},
		deck = {
			updateFn = updateDeck,
			getModelsFn = getModelsDeck,
		},
	}
end
