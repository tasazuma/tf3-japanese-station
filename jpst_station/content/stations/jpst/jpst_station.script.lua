local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"
local table_util = require "::/scripts/table_util.tl"
local modulesutil = require "::/scripts/construction/modulesutil.lua"
local constructionutil = require "::/scripts/construction/constructionutil.lua"
local layout = require "jpst_station::/scripts/jpst/layout.lua"

local KIND = layout.KIND
local GROUND = layout.LEVEL.GROUND

local function platformName(level, stairs, width)
	local mid = (level == layout.LEVEL.ELEVATED) and "jpst_platform_elevated_island_" or "jpst_platform_island_"
	return layout.moduleName(mid .. tostring(width) .. (stairs and "_stairs" or ""))
end
local BUILDING_SMALL = layout.moduleName("jpst_building_small")
local function brickBuildingName(size)
	return layout.moduleName("jpst_building_brick_" .. tostring(size))
end
local CONCOURSE = layout.moduleName("jpst_concourse")
local UNDER_VIADUCT = layout.moduleName("jpst_underviaduct_pillars")

local DEFAULT_CATCHMENT_RADIUS = 150

-- Construction params arrive 1-based (same as defaultIndex in the .con): 1 = first value.
local function paramIndex(v, default, count)
	if type(v) ~= "number" then return default end
	return math.max(1, math.min(count, math.floor(v)))
end

local LENGTH_COUNT = 8 -- 40 .. 320 m
local MAX_TRACKS = 8
local PLATFORM_WIDTHS = { 5, 10 }

-- Row patterns for n tracks.
-- island: pairs share an island platform (T P T T P T ...); an odd last track gets its own platform.
-- side:   platforms on the outside of each pair (P T T P T T P ...); with 2 tracks this is the classic 2面2線.
--         An odd last track only gets the platform before it (1 track = P T).
local function templateRows(nTracks, side)
	local rows = {}
	local remaining = nTracks
	if side then
		rows[1] = KIND.PLATFORM
		while remaining > 0 do
			rows[#rows + 1] = KIND.TRACK
			if remaining >= 2 then
				rows[#rows + 1] = KIND.TRACK
				rows[#rows + 1] = KIND.PLATFORM
			end
			remaining = remaining - 2
		end
		return rows
	end
	while remaining > 0 do
		rows[#rows + 1] = KIND.TRACK
		rows[#rows + 1] = KIND.PLATFORM
		if remaining >= 2 then rows[#rows + 1] = KIND.TRACK end
		remaining = remaining - 2
	end
	return rows
end

local function createTemplateFn(captureParams, params)
	local n = paramIndex(params.jpst_length, 3, LENGTH_COUNT)
	local nTracks = paramIndex(params.jpst_tracks, 2, MAX_TRACKS)
	local typeIdx = paramIndex(params.jpst_trackType, 2, #layout.TRACK_TYPES)
	local catenary = paramIndex(params.jpst_catenary, 2, 2) == 2
	local level = (paramIndex(params.jpst_level, 1, 2) == 2) and layout.LEVEL.ELEVATED or GROUND
	local sidePlatforms = paramIndex(params.jpst_platformLayout, 1, 2) == 2
	local platformWidth = PLATFORM_WIDTHS[paramIndex(params.jpst_platformWidth, 2, #PLATFORM_WIDTHS)]
	local trackName = layout.trackModuleName(layout.TRACK_TYPES[typeIdx], catenary, level)
	-- 2F concourse is only for ground stations (it would cut through a viaduct)
	local passage = paramIndex(params.jpst_passage, 1, 3)
	local concourse = level == GROUND and passage == 2
	-- 高架下駅舎 is only for elevated stations
	local underViaduct = level == layout.LEVEL.ELEVATED and passage == 3

	local result = {}
	local s = -math.floor(n / 2)
	local e = s + n - 1
	local function hasStairs(j)
		if concourse then return false end
		return j == 0 or (n >= 5 and (j == s + 1 or j == e - 1))
	end
	local rows = templateRows(nTracks, sidePlatforms)
	local firstRow = -math.floor((#rows - 1) / 2)
	for i, kind in ipairs(rows) do
		local row = firstRow + i - 1
		for j = s, e do
			if kind == KIND.TRACK then
				result[layout.encode(KIND.TRACK, level, row, j)] = trackName
			else
				result[layout.encode(KIND.PLATFORM, level, row, j)] = platformName(level, hasStairs(j), platformWidth)
			end
		end
	end
	-- 1 = small building, 2 = large brick building over the whole length, 3 = none
	local building = paramIndex(params.jpst_building, 1, 3)
	if building == 1 then
		result[layout.encode(KIND.BUILDING, GROUND, layout.SIDE.MINUS_X, 0)] = BUILDING_SMALL
	elseif building == 2 then
		local row = layout.buildingRow(layout.SIDE.MINUS_X, n)
		result[layout.encode(KIND.BUILDING, GROUND, row, s)] = brickBuildingName(n)
	end
	if concourse then
		result[layout.encode(KIND.CONCOURSE, GROUND, 0, 0)] = CONCOURSE
	end
	if underViaduct then
		result[layout.encode(KIND.UNDER, GROUND, 0, 0)] = UNDER_VIADUCT
	end
	return result
end

local function addSlots(result, L, modules)
	local function addSlot(id, tf, slotType, spacing)
		table.insert(result.slots, {
			id = id,
			transf = tf,
			type = slotType,
			spacing = spacing,
			replaceable = true,
		})
	end

	local candidates = {}
	local function mark(row, seg)
		candidates[row] = candidates[row] or {}
		candidates[row][seg] = true
	end
	if L.empty then mark(0, 0) end
	for row, segs in pairs(L.cells) do
		for seg, _ in pairs(segs) do
			mark(row, seg)
			mark(row - 1, seg)
			mark(row + 1, seg)
			mark(row, seg - 1)
			mark(row, seg + 1)
		end
	end

	-- A row keeps one level: occupied rows only offer their own level, empty rows offer every level.
	local ALL_LEVELS = { GROUND, layout.LEVEL.ELEVATED }
	for row, segs in pairs(candidates) do
		local w = layout.width(L, row)
		local spacing = { w / 2, w / 2, 19.5, 19.5 }
		local rl = layout.rowLevel(L, row)
		local levels = rl and { rl } or ALL_LEVELS
		for seg, _ in pairs(segs) do
			local cell = layout.get(L, row, seg)
			for _, level in ipairs(levels) do
				local tf = layout.slotTransf(L, row, seg, level)
				for _, kind in ipairs({ KIND.TRACK, KIND.PLATFORM }) do
					if cell == nil or cell.kind == kind then
						addSlot(layout.encode(kind, level, row, seg), tf, layout.slotType(kind, level), spacing)
					end
				end
			end
		end
	end

	-- Building slots of every length (1..8 segments) wherever all covered segments exist and no other
	-- building occupies them; the building already placed keeps its own slot.
	for seg, _ in pairs(L.segs) do
		for _, side in ipairs({ layout.SIDE.MINUS_X, layout.SIDE.PLUS_X }) do
			for size = 1, layout.MAX_BUILDING_SEGS do
				local id = layout.encode(KIND.BUILDING, GROUND, layout.buildingRow(side, size), seg)
				local ok = true
				for s2 = seg, seg + size - 1 do
					local occ = L.buildingAt[side][s2]
					if not L.segs[s2] or (occ and occ ~= id) then ok = false break end
				end
				if ok then
					-- The box must end exactly at the front: reaching past it would overlap the outermost
					-- ground track/platform box, and the game then refuses to place into the slot.
					-- A placed building only reaches its own depth so the forecourt slots behind it stay free.
					local half = layout.SEG_LEN * size / 2 - 0.5
					local b = L.buildings[id]
					addSlot(id, layout.buildingTransf(L, side, seg, size), layout.buildingSlotType(size),
						{ half, half, b and b.depth or 40, 0 })
				end
			end
		end
	end

	-- Forecourt slots of every size behind the station buildings (only where buildings stand):
	-- 1F plazas on the ground, pedestrian decks (level 1) at DECK_Z over the same grid.
	local C = layout.FORECOURT_CELL
	for _, level in ipairs({ GROUND, layout.LEVEL.ELEVATED }) do
		local z = (level == GROUND) and 0 or layout.DECK_Z
		for _, side in ipairs({ layout.SIDE.MINUS_X, layout.SIDE.PLUS_X }) do
			for seg, _ in pairs(L.buildingAt[side]) do
				for d = 0, layout.FORECOURT_ROWS - 1 do
					for h = 1, layout.FORECOURT_ROWS - d do
						for w = 1, layout.MAX_FORECOURT_W do
							local id = layout.encode(KIND.FORECOURT, level, layout.forecourtRow(side, d, w, h), seg)
							if layout.forecourtFits(L, side, d, w, h, seg, id, level) then
								local hx, hy = w * C / 2 - 0.5, h * C / 2 - 0.5
								local tf = transf.mul(transf.transl(vec3.new(0, 0, z)), layout.forecourtTransf(L, side, seg, d, w, h))
								addSlot(id, tf, layout.forecourtSlotType(w, h, level), { hx, hx, hy, hy })
							end
						end
					end
				end
			end
		end
	end

	for seg, _ in pairs(L.segs) do
		local xL, xR = layout.segEdges(L, seg)
		local half = (xR - xL) / 2 + 4
		addSlot(layout.encode(KIND.CONCOURSE, GROUND, 0, seg), layout.concourseSlotTransf(L, seg),
			layout.SLOT_TYPE[KIND.CONCOURSE], { half, half, layout.CONCOURSE_HALF_WIDTH, layout.CONCOURSE_HALF_WIDTH })
	end

	-- 高架下駅舎: ground level under the elevated rows of a segment (10 m below the elevated slots)
	for seg, _ in pairs(L.segs) do
		local tf, half = layout.underViaductSlotTransf(L, seg)
		if tf then
			addSlot(layout.encode(KIND.UNDER, GROUND, 0, seg), tf, layout.SLOT_TYPE[KIND.UNDER],
				{ half - 0.5, half - 0.5, 4, 4 })
		end
	end

	-- Ignored modules still need their slot, otherwise the construction is invalid; the user can remove them there.
	for id in pairs(L.ignored) do
		local kind, level, row, seg = layout.decode(id)
		local tf
		if kind == KIND.BUILDING or kind == KIND.FORECOURT then
			local z = (kind == KIND.FORECOURT and level == layout.LEVEL.ELEVATED) and layout.DECK_Z or 0
			tf = transf.transl(vec3.new(0, layout.segY(seg), z))
		elseif kind == KIND.CONCOURSE then
			tf = transf.transl(vec3.new(0, layout.segY(seg), layout.CONCOURSE_Z))
		elseif kind == KIND.UNDER then
			tf = transf.transl(vec3.new(0, layout.segY(seg), 0))
		else
			tf = layout.slotTransf(L, row, seg, level)
		end
		addSlot(id, tf, layout.slotTypeOf(id), { 1, 1, 1, 1 })
	end
end

-- Group consecutive track segments that face a platform into terminals.
local function buildTerminals(result, L)
	local J = result.jpst
	local cumsum = {}
	local c = 0
	for i = 1, #result.edgeLists do
		cumsum[i] = c
		c = c + #result.edgeLists[i].edges
	end

	local function modesFor(list)
		if result.edgeListHasCatenary[list] then
			return { "TRAIN", "ELECTRIC_TRAIN", "TRAM_TRACK", "ELECTRIC_TRAM_TRACK" }
		end
		return { "TRAIN", "TRAM_TRACK" }
	end

	local terminals = {}
	local rows = {}
	for row, _ in pairs(J.tracks) do table.insert(rows, row) end
	table.sort(rows)

	for _, row in ipairs(rows) do
		local segs = J.tracks[row]
		for _, side in ipairs({ -1, 1 }) do
			local group = nil
			local function flush()
				if group == nil then return end
				local n = #group.nodes
				local pick
				if n % 2 == 0 then
					pick = side < 0 and group.centresLeft[n / 2 + 1] or group.centresRight[n / 2]
				else
					pick = group.nodes[math.ceil(n / 2)]
				end
				table.insert(terminals, {
					personEdges = group.personEdges,
					personNodes = group.personNodes,
					vehicleNode = { -1, pick.node },
					transportModes = modesFor(pick.list),
					passengers = true,
					tag = #terminals + 1,
					length = 40 * n,
				})
				group = nil
			end

			for seg = L.minSeg, L.maxSeg do
				local t = segs[seg]
				local pr = J.platforms[row + side]
				local p = pr and pr[seg]
				if p and layout.rowLevel(L, row + side) ~= layout.rowLevel(L, row) then p = nil end
				if t and p then
					if group and group.lastSeg ~= seg - 1 then flush() end
					group = group or { personEdges = {}, personNodes = {}, nodes = {}, centresLeft = {}, centresRight = {} }
					local lane = side < 0 and p.plus or p.minus
					for e = 0, 3 do table.insert(group.personEdges, { lane, e }) end
					table.insert(group.personNodes, { lane, 1 })
					local base = t.nedges + cumsum[t.list]
					table.insert(group.nodes, { node = base + (side < 0 and 5 or 7), list = t.list })
					table.insert(group.centresLeft, { node = base + 0, list = t.list })
					table.insert(group.centresRight, { node = base + 10, list = t.list })
					group.lastSeg = seg
				else
					flush()
				end
			end
			flush()
		end
	end
	return terminals
end

-- Japanese track numbers (番線): every track row gets a number, counted from the station building side
-- (from -X unless buildings stand only on +X). Number signs show the tracks on both sides of their platform.
local function trackNumbers(result, L)
	local rows = {}
	for row, _ in pairs(result.jpst.tracks) do table.insert(rows, row) end
	table.sort(rows)
	local fromPlus = next(L.buildingAt[layout.SIDE.PLUS_X]) ~= nil and next(L.buildingAt[layout.SIDE.MINUS_X]) == nil
	local numbers = {}
	for i, row in ipairs(rows) do numbers[row] = fromPlus and (#rows - i + 1) or i end
	return numbers
end

local function fillSignLabels(result, L)
	local J = result.jpst
	if #J.signs == 0 then return end
	local numbers = trackNumbers(result, L)
	local function numberAt(platformRow, row, seg)
		local t = J.tracks[row]
		if t and t[seg] and layout.rowLevel(L, row) == layout.rowLevel(L, platformRow) then
			return tostring(numbers[row])
		end
		return ""
	end
	local labelText = result.cargoStation.labelText
	for _, s in ipairs(J.signs) do
		if s.label == "number" then
			local m = numberAt(s.row, s.row - 1, s.seg)
			local p = numberAt(s.row, s.row + 1, s.seg)
			labelText[s.index] = { m, m, p, p }
		elseif s.label == "name" then
			-- same as vanilla: STATION_NAME labels get the station index, the game draws the name
			labelText[s.index] = { "0", "0" }
		end
	end
end

local function updateFn(captureParams, params)
	local result = {}
	result.models = {}
	result.slots = {}
	result.colliders = {}
	result.terrainAlignmentLists = {}
	result.groundFaces = {}
	result.dependentSlots = {}
	result.edgeLists = {}
	result.edgeListHasCatenary = {}
	result.labelText = {}
	result.cost = 0

	local modules = params.modules or {}
	local L = layout.compute(modules)
	-- Shared registry filled by module updateFns, consumed by the hook.
	result.jpst = {
		layout = L,
		tracks = {},    -- tracks[row][seg] = { list, nedges }
		platforms = {}, -- platforms[row][seg] = { minus = laneIdx, plus = laneIdx }
		busStops = {},  -- bus stop terminals from bus rotary modules (lane indices into cargoStation.laneLists)
		streets = {},   -- street edge lists (rotary stubs), appended after the track lists in the hook
		signs = {},     -- { index (0-based into cargoStation.models), label = "number"|"name", row, seg }
	}

	addSlots(result, L, modules)

	local cargoStation = { tag = 1 }
	for k, v in pairs(result) do cargoStation[k] = v end
	cargoStation.models = {}
	cargoStation.colliders = {}
	cargoStation.terrainAlignmentLists = {}
	cargoStation.groundFaces = {}
	cargoStation.labelText = {}
	cargoStation.laneLists = {}
	cargoStation.emissionEmitter = {}
	result.cargoStation = cargoStation

	result.terminateConstructionHook = function()
		if params.modules == nil then return end
		local cs = result.cargoStation

		local terminals = buildTerminals(result, L)
		fillSignLabels(result, L)
		for _, b in ipairs(result.jpst.busStops) do
			table.insert(terminals, {
				personEdges = b.personEdges,
				personNodes = b.personNodes,
				vehicleNode = b.vehicleNode,
				vehicleEdges = b.vehicleEdges,
				transportModes = { "BUS" },
				passengers = true,
				tag = #terminals + 1,
				length = b.length,
			})
		end
		-- after buildTerminals: track node indices and edgeListHasCatenary only cover the track lists
		for _, el in ipairs(result.jpst.streets) do table.insert(result.edgeLists, el) end
		local passCap = modulesutil.getStationPoolCapacities(params.modules, result)
		local comfort = modulesutil.getStationPoolComfortFactor(params.modules, result)
		local emissions = modulesutil.getModulesEmissions(params.modules, result)

		if #terminals > 0 then
			for _, t in ipairs(terminals) do
				t.cargoTransferSpeeds = {
					{
						cargoTypeSet = { cargoClassesIncluded = { "PASSENGERS" } },
						loadSpeedModifier = 1,
						length = t.length,
					},
				}
				t.length = nil
				t.comfortFactor = 1 + comfort
			end
			cs.station = {
				terminals = terminals,
				pool = {
					edges = modulesutil.getStationPoolEdges(result, true),
					capacity = passCap,
				},
			}
			cs.metadata = { emissions = {
				{ noise = emissions.noise, pollution = emissions.pollution },
				{ noise = emissions.noise * 2, pollution = emissions.pollution * 2 },
			} }
		end

		if #result.models + #cs.models == 0 then
			table.insert(result.models, {
				id = "::/assets/markers/marker_exclamation.mdl",
				transf = transf.transl(vec3.new(0, 0, 0)),
			})
		end
		if #result.terrainAlignmentLists + #cs.terrainAlignmentLists == 0 then
			result.terrainAlignmentLists = {
				{ type = "LESS", faces = { layout.rectFace(-0.1, -0.1, 0.1, 0.1) } },
			}
		end

		result.subconstructions = {}
		for _, v in pairs(result.models) do table.insert(cs.models, v) end
		for _, v in pairs(result.colliders) do table.insert(cs.colliders, v) end
		for _, v in pairs(result.terrainAlignmentLists) do table.insert(cs.terrainAlignmentLists, v) end
		for _, v in pairs(result.groundFaces) do table.insert(cs.groundFaces, v) end
		if #cs.models > 0 then
			table.insert(result.subconstructions, cs)
		end

		constructionutil.addStationCapacities(cs)
		constructionutil.addCatchmentCircles(cs.station, cs.station, params.modules, result.slots,
			{ position = { 0, 0, 0 }, radius = DEFAULT_CATCHMENT_RADIUS })
		modulesutil.addAutoSnap(params, result)

		local legacytransportnetworks = require "::/scripts/construction/legacytransportnetworks.lua"
		legacytransportnetworks.addLaneLists(result, true)
	end

	return result
end

-- Track type / catenary tools -------------------------------------------------

local function metadataOf(module)
	if module == nil then return nil end
	if module.metadata then return module.metadata end
	local ok, desc = pcall(function() return api.res.moduleRep.get(api.res.moduleRep.find(module.name)) end)
	return ok and desc and desc.metadata or nil
end

local function templateToModule(streetTemplate, level)
	local catenary = string.find(streetTemplate, "_catenary", 1, true) ~= nil
	for _, t in ipairs(layout.TRACK_TYPES) do
		if string.find(streetTemplate, "/track/" .. t .. "/", 1, true) then
			return layout.trackModuleName(t, catenary, level)
		end
	end
	return nil
end

local function upgradeFn(captureParams, params, slotId, constructionConfig)
	local module = params.modules and params.modules[slotId]
	local md = metadataOf(module)
	if not (md and md.track) then return params end

	local paramsCopy = table_util.copy(params)
	local kind, level, row, seg = layout.decode(slotId)

	local function swapRow(nameFn)
		for _, dir in ipairs({ -1, 1 }) do
			local s = (dir < 0) and seg or seg + 1
			while true do
				local id = layout.encode(kind, level, row, s)
				local m = params.modules[id]
				local mmd = metadataOf(m)
				if not (mmd and mmd.track) then break end
				local to = nameFn(mmd)
				if to then paramsCopy.modules[id].name = to end
				s = s + dir
			end
		end
	end

	if constructionConfig.streetTemplate then
		local to = templateToModule(constructionConfig.streetTemplate, level)
		if to then swapRow(function() return to end) end
	elseif constructionConfig.catenary then
		if constructionConfig.catenary == 2 then
			swapRow(function(m) return m.catenaryAdd end)
		else
			swapRow(function(m) return m.catenaryRemove end)
		end
	end
	return paramsCopy
end

local function isAffectedByToolFn(captureParams, params, conConfigAdd, conConfigRemove)
	if conConfigAdd.streetTemplate then
		local streetTemplate = api.res.streetTemplateRep.get(api.res.streetTemplateRep.find(conConfigAdd.streetTemplate))
		return streetTemplate.roadType == 0 -- 0: TRACK
	end
	return true
end

function data()
	return {
		createTemplateFn = createTemplateFn,
		updateFn = updateFn,
		upgradeFn = upgradeFn,
		isAffectedByToolFn = isAffectedByToolFn,
	}
end
