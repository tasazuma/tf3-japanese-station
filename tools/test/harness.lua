-- Offline harness: runs jpst_station scripts with vanilla Lua libs, stubbing engine APIs.
-- Run tools/test/setup.sh once, then: lua tools/test/harness.lua
local HERE = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
local REPO = HERE .. "/../.."
local BASE = HERE .. "/.vanilla/base"
local LIB = HERE .. "/.vanilla/lib"
local MOD = REPO .. "/jpst_station/content"
local MODS = {
	jpst_station = MOD,
	jpst_building_example = REPO .. "/jpst_building_example/content",
}

_G._ = function(s) return s end
_G.log = setmetatable({}, { __index = function() return function(...) print("[log]", ...) end end })
_G.toString = tostring
local warnings = {}
_G.api = {
	type = { Vec3f = {
		new = function(x, y, z) return { x = x, y = y, z = z } end,
		distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
	} },
	res = {
	moduleRep = {
		find = function(n) return n end,
		get = function(n) return { metadata = MODULE_META and MODULE_META[n] } end,
	},
	streetTemplateRep = { find = function(n) return n end, get = function() return { roadType = 0 } end },
} }

local cache = {}
local function stubTable(name)
	return setmetatable({}, { __index = function(_, k)
		return function() table.insert(warnings, "stub called: " .. name .. "." .. k) end
	end })
end

local function resolve(path)
	local modId, rel = path:match("^([%w_]+)::(/.*)$")
	if modId then
		return assert(MODS[modId], "unknown mod " .. modId) .. rel
	end
	local base = path:match("^::(/.*)$")
	local file
	if base then
		local name = base:match("^/scripts/([%w_]+)%.tl$")
		if name and (name == "vec3" or name == "vec4" or name == "mat4") then
			file = LIB .. "/" .. name .. ".lua"
		elseif base:match("%.tl$") then
			return nil
		else
			file = BASE .. base
		end
	elseif path:match("^/scripts/[%w_]+%.tl$") or path:match("^/scripts/construction/.*") then
		return resolve("::" .. path)
	elseif path:match("^[%w_]+%.tl$") then
		return resolve("::/scripts/" .. path)
	else
		file = MOD .. path
		local f = io.open(file)
		if f then f:close() else return resolve("::" .. path) end
	end
	return file
end

local origRequire = require
_G.require = function(path)
	if cache[path] ~= nil then return cache[path] end
	if path == "::/scripts/table_util.tl" or path == "/scripts/table_util.tl" then
		local function copy(o)
			if type(o) ~= "table" then return o end
			local r = {}
			for k, v in pairs(o) do r[k] = copy(v) end
			return setmetatable(r, getmetatable(o))
		end
		cache[path] = { copy = copy }
		return cache[path]
	end
	local file = resolve(path)
	if not file then
		cache[path] = stubTable(path)
		return cache[path]
	end
	local chunk, err = loadfile(file)
	if not chunk then error("require " .. path .. ": " .. tostring(err)) end
	cache[path] = chunk()
	return cache[path]
end
_G.ug_require = _G.require

local function loadData(path, root)
	local env = setmetatable({}, { __index = _G })
	local chunk = assert(loadfile((root or MOD) .. path .. ".lua", "t", env))
	chunk()
	return env.data()
end

local transf = require "::/scripts/mat4.tl"
local vec3 = require "::/scripts/vec3.tl"
local layout = require "jpst_station::/scripts/jpst/layout.lua"

local con = loadData("/stations/jpst/jpst_station.con")
local script = loadData("/stations/jpst/jpst_station.script")
-- the placement menu now starts from one track / side platform / 160 m; the tests keep the former
-- defaults (2 tracks, island, 120 m) unless they set a param themselves
do
	local create = script.createTemplateFn
	script.createTemplateFn = function(cap, params)
		local p = {}
		for k, v in pairs(params) do p[k] = v end
		if p.jpst_tracks == nil then p.jpst_tracks = 2 end
		if p.jpst_platformLayout == nil then p.jpst_platformLayout = 1 end
		if p.jpst_length == nil then p.jpst_length = 3 end
		return create(cap, p)
	end
end
local moduleScript = loadData("/stations/jpst/jpst_modules.script")

TEST_MODULES = {} -- name -> function returning a desc (test-only modules)
local function moduleDesc(name)
	if TEST_MODULES[name] then return TEST_MODULES[name]() end
	local modId, rel = name:match("^([%w_]+)::(/.*)$")
	assert(rel and MODS[modId], "module name not qualified: " .. tostring(name))
	return loadData(rel, MODS[modId])
end

MODULE_META = {}

local function fnFromRef(ref)
	local file, fn = ref:match("^(.-)@(.+)$")
	assert(file == "jpst_station::/stations/jpst/jpst_modules.script", file)
	local obj = moduleScript
	for part in fn:gmatch("[^.]+") do obj = obj[part] end
	return obj
end

local function slotTransf(result, id)
	for _, s in ipairs(result.slots) do
		if s.id == id then return s.transf, s end
	end
end

local function build(params)
	local modules = {}
	for id, name in pairs(params.modulesByName) do
		local d = moduleDesc(name)
		MODULE_META[name] = d.metadata
		modules[id] = { name = name, variant = 0, metadata = d.metadata, _desc = d }
	end
	params.modules = modules
	local result = script.updateFn({}, params)
	local ids = {}
	for id in pairs(modules) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local m = modules[id]
		local tf, slot = slotTransf(result, id)
		assert(tf, "no slot for module at " .. id .. " (" .. m.name .. ")")
		assert(slot.type == m._desc.type, ("slot type mismatch at %d: %s vs %s"):format(id, slot.type, m._desc.type))
		local fn = fnFromRef(m._desc.updateScript.fileName)
		local tag = "__module_" .. id
		fn(m._desc.updateScript.params, result, tf, tag, id, function(mid, mtf)
			table.insert(result.models, { id = mid, transf = transf.mul(tf, mtf), tag = tag })
		end, params)
		local gm = fnFromRef(m._desc.getModelsScript.fileName)
		local models = gm(m._desc.getModelsScript.params, 0)
		assert(type(models) == "table", "getModelsFn must return a table")
		m._desc = nil
	end
	result.terminateConstructionHook()
	return result
end

-- Default parameters: defaultIndex is 1-based in .con, 0-based in params.
local params = {}
for _, p in ipairs(con.params or (con.templates and con.templates[1] and con.templates[1].params) or {}) do
	params[p.key] = (p.defaultIndex or 1)
end
local tpl = con.constructionTemplates and con.constructionTemplates[1]
if tpl then
	for _, p in ipairs(tpl.data.params) do params[p.key] = (p.defaultIndex or 1) end
end
print("params:", params.jpst_length, params.jpst_trackType, params.jpst_catenary)

local function summarize(label, result)
	local cs = result.cargoStation
	print(("== %s: slots=%d models=%d edgeLists=%d"):format(label, #result.slots, #cs.models, #result.edgeLists))
	for i, el in ipairs(result.edgeLists) do
		print(("   edgeList %d type=%s template=%s edges=%d snap=%d catenary=%s"):format(i, tostring(el.type),
			tostring(el.params and el.params.type), #el.edges, #(el.snapNodes or {}), tostring(result.edgeListHasCatenary[i])))
	end
	local lanes = 0
	for _, ll in ipairs(cs.laneLists or {}) do lanes = lanes + #(ll.lanes or ll) end
	print("   terminals:", cs.station and #cs.station.terminals or 0, "capacity:", cs.station and cs.station.pool.capacity)
	if cs.station then
		for i, t in ipairs(cs.station.terminals) do
			print(("     T%d: vehicleNode list=%s node=%s personNodes=%d tag=%s len=%s"):format(i,
				tostring(t.vehicleNodeOverride and t.vehicleNodeOverride.list or (t.vehicleNodes and "?")),
				tostring(t.vehicleNodeOverride and t.vehicleNodeOverride.node),
				#(t.personNodes or {}), tostring(t.tag), tostring(t.cargoTransferSpeeds[1].length)))
		end
	end
	print("   snapPoint:", result.snapPoint ~= nil, "catchment:", cs.station and cs.station.catchment ~= nil)
	local types = {}
	for _, s in ipairs(result.slots) do types[s.type] = (types[s.type] or 0) + 1 end
	for k, v in pairs(types) do print("   slot", k, v) end
	if #warnings > 0 then
		for _, w in ipairs(warnings) do print("   WARN", w) end
		warnings = {}
	end
end

-- 1) default template
local tplModules = script.createTemplateFn({}, params)
local n = 0
for id, name in pairs(tplModules) do n = n + 1; local k, l, r, s = layout.decode(id) end
print("template modules:", n)
local r1 = build({ modulesByName = tplModules, jpst_length = params.jpst_length })
summarize("default", r1)

-- 2) all parameter combos
for len = 1, 8 do
	for tt = 1, 3 do
		for cat = 1, 2 do for lvl = 1, 2 do for nt = 1, 8 do for pw = 1, 2 do for pl = 1, 2 do for ps = 1, 2 do for bd = 1, 3 do
			local p = { jpst_building = bd, jpst_passage = ps, jpst_platformLayout = pl, jpst_length = len, jpst_trackType = tt, jpst_catenary = cat, jpst_level = lvl, jpst_tracks = nt, jpst_platformWidth = pw }
			local m = script.createTemplateFn({}, p)
			p.modulesByName = m
			local ok, err = pcall(build, p)
			if not ok then print("FAIL combo", len, tt, cat, lvl, nt, pw, pl, ps, bd, err) else COMBOS = (COMBOS or 0) + 1 end
		end end end end end end end
	end
end
print("combos done", COMBOS)

-- 3) variants: 5m platforms, building on +X, platform-only, track-only, empty
local function variant(label, mods)
	local ok, r = pcall(build, { modulesByName = mods })
	if ok then summarize(label, r) else print("FAIL", label, r) end
end
local K, G = layout.KIND, layout.LEVEL.GROUND
local T = layout.trackModuleName(layout.TRACK_TYPES[2], true)
local m5 = {}
for j = -1, 1 do
	m5[layout.encode(K.TRACK, G, -1, j)] = T
	m5[layout.encode(K.TRACK, G, 1, j)] = T
	m5[layout.encode(K.PLATFORM, G, 0, j)] = layout.moduleName(j == 0 and "jpst_platform_island_5_stairs" or "jpst_platform_island_5")
end
m5[layout.encode(K.BUILDING, G, layout.SIDE.PLUS_X, 1)] = layout.moduleName("jpst_building_small")
variant("5m + building +X", m5)
variant("track only", { [layout.encode(K.TRACK, G, 0, 0)] = T })
variant("platform only", { [layout.encode(K.PLATFORM, G, 0, 0)] = layout.moduleName("jpst_platform_island_10") })
variant("empty", {})
-- 2 platforms, 3 tracks
local m2 = {}
for j = 0, 1 do
	for _, row in ipairs({ -2, 0, 2 }) do m2[layout.encode(K.TRACK, G, row, j)] = T end
	m2[layout.encode(K.PLATFORM, G, -1, j)] = layout.moduleName("jpst_platform_island_10")
	m2[layout.encode(K.PLATFORM, G, 1, j)] = layout.moduleName(j == 0 and "jpst_platform_island_10_stairs" or "jpst_platform_island_10")
end
variant("2 platforms 3 tracks", m2)

-- 4) upgrade: catenary tool on a track slot
local trackSlot = layout.encode(K.TRACK, G, -1, 0)
local up = script.upgradeFn({}, { modules = r1 and (function()
	local mm = {}
	for id, name in pairs(tplModules) do mm[id] = { name = name, variant = 0, metadata = MODULE_META[name] } end
	return mm
end)() }, trackSlot, { catenaryToggle = true, streetTemplate = nil })
local cnt = 0
for _ in pairs(up or {}) do cnt = cnt + 1 end
print("upgrade (catenary toggle) returned entries:", cnt)
local up2 = script.upgradeFn({}, { modules = (function()
	local mm = {}
	for id, name in pairs(tplModules) do mm[id] = { name = name, variant = 0, metadata = MODULE_META[name] } end
	return mm
end)() }, trackSlot, { streetTemplate = "::/infrastructure/track/high_speed/high_speed.street_template" })
cnt = 0
for k, v in pairs(up2 or {}) do cnt = cnt + 1 end
print("upgrade (high_speed) returned entries:", cnt)
for k, v in pairs(up2 or {}) do print("   ", k, v) break end

-- 5) inspect structures
local cs = r1.cargoStation
print("catchmentAreas:", cs.catchmentAreas and #cs.catchmentAreas, "station.catchment", cs.station.catchment)
local function dump(t, ind, depth)
	ind = ind or ""; depth = depth or 0
	if depth > 3 then return end
	for k, v in pairs(t) do
		if type(v) == "table" then print(ind .. tostring(k) .. ":"); dump(v, ind .. "  ", depth + 1)
		else print(ind .. tostring(k) .. " = " .. tostring(v)) end
	end
end
print("laneLists count", #cs.laneLists, "first:")
dump(cs.laneLists[1], "  ", 1)
print("terminal 1:"); dump(cs.station.terminals[1], "  ", 1)
local after = {}
for id, m in pairs(up2.modules) do after[m.name] = (after[m.name] or 0) + 1 end
for k, v in pairs(after) do print("after high_speed upgrade:", k, v) end

-- 6) lane connectivity: every terminal lane must reach a linkable (street) lane
local function connectivity(label, r, tol)
	tol = tol or 0.01
	local cs = r.cargoStation
	local pts, parent = {}, {}
	local function find(i) while parent[i] ~= i do parent[i] = parent[parent[i]]; i = parent[i] end return i end
	local function union(a, b) a, b = find(a), find(b); if a ~= b then parent[a] = b end end
	local laneNodes = {}
	for li, ll in ipairs(cs.laneLists) do
		local t = ll.transf
		laneNodes[li] = {}
		for ni, n in ipairs(ll.nodes) do
			local p = n[1]
			local x = t[1] * p[1] + t[5] * p[2] + t[9] * p[3] + t[13]
			local y = t[2] * p[1] + t[6] * p[2] + t[10] * p[3] + t[14]
			local z = t[3] * p[1] + t[7] * p[2] + t[11] * p[3] + t[15]
			pts[#pts + 1] = { x, y, z, li }
			parent[#pts] = #pts
			laneNodes[li][ni] = #pts
		end
		for e = 1, #ll.nodes // 2 do union(laneNodes[li][2 * e - 1], laneNodes[li][2 * e]) end
	end
	for i = 1, #pts do for j = i + 1, #pts do
		local a, b = pts[i], pts[j]
		if math.abs(a[1] - b[1]) < tol and math.abs(a[2] - b[2]) < tol and math.abs(a[3] - b[3]) < tol then union(i, j) end
	end end
	local linkRoots = {}
	for li, ll in ipairs(cs.laneLists) do if ll.linkable then linkRoots[find(laneNodes[li][1])] = true end end
	local bad = 0
	local comps = {}
	for li in ipairs(cs.laneLists) do comps[find(laneNodes[li][1])] = true end
	local nc = 0 for _ in pairs(comps) do nc = nc + 1 end
	if cs.station then
		for ti, term in ipairs(cs.station.terminals) do
			for _, pe in ipairs(term.personEdges) do
				local li = pe[1] + 1
				if not linkRoots[find(laneNodes[li][1])] then bad = bad + 1 end
			end
		end
	end
	if DEBUG_CONN then
		local byComp = {}
		for li, ll in ipairs(cs.laneLists) do
			local r = find(laneNodes[li][1])
			byComp[r] = byComp[r] or {}
			local t = ll.transf
			local s = {}
			for ni, n in ipairs(ll.nodes) do
				local p = n[1]
				s[#s+1] = ("(%.1f,%.1f,%.1f)"):format(t[1]*p[1]+t[5]*p[2]+t[9]*p[3]+t[13], t[2]*p[1]+t[6]*p[2]+t[10]*p[3]+t[14], t[3]*p[1]+t[7]*p[2]+t[11]*p[3]+t[15])
			end
			table.insert(byComp[r], (ll.linkable and "L " or "  ") .. table.concat(s, " "))
		end
		for r, ls in pairs(byComp) do print("COMP", r, linkRoots[r] and "LINKED" or "unlinked"); for _, l in ipairs(ls) do print("   ", l) end end
	end
	print(("connectivity %s: lanes=%d components=%d unlinked terminal edges=%d linkable lanes=%s"):format(
		label, #cs.laneLists, nc, bad, next(linkRoots) and "yes" or "NO"))
	return bad, linkRoots
end
connectivity("default", r1)
connectivity("5m + building +X", build({ modulesByName = m5 }))
connectivity("2 platforms 3 tracks (no building)", build({ modulesByName = m2 }))

-- 7) elevated
local E = layout.LEVEL.ELEVATED
local pe = { jpst_length = 3, jpst_trackType = 2, jpst_catenary = 2, jpst_level = 2 }
local me = script.createTemplateFn({}, pe)
for id, name in pairs(me) do print("  elev tpl", id, name) end
local re = build({ modulesByName = me })
summarize("elevated default", re)
for i, el in ipairs(re.edgeLists) do
	local z = el.edges[1] and el.edges[1][1][3]
	print(("   EL%d edgeType=%s name=%s z=%s"):format(i, tostring(el.edgeType), tostring(el.edgeTypeName), tostring(z)))
end
DEBUG_CONN=false connectivity("elevated default", re) DEBUG_CONN=false
-- mixed: ground tracks -1,1 island 0 (ground); elevated tracks 3,5 island 4; building on -X
local TE = layout.trackModuleName(layout.TRACK_TYPES[2], true, E)
print("TE", TE)
local mx = {}
for j = -1, 1 do
	mx[layout.encode(K.TRACK, G, -1, j)] = T
	mx[layout.encode(K.TRACK, G, 1, j)] = T
	mx[layout.encode(K.PLATFORM, G, 0, j)] = layout.moduleName(j == 0 and "jpst_platform_island_10_stairs" or "jpst_platform_island_10")
	mx[layout.encode(K.TRACK, E, 2, j)] = TE
	mx[layout.encode(K.TRACK, E, 4, j)] = TE
	mx[layout.encode(K.PLATFORM, E, 3, j)] = layout.moduleName(j == 0 and "jpst_platform_elevated_island_10_stairs" or "jpst_platform_elevated_island_10")
end
mx[layout.encode(K.BUILDING, G, layout.SIDE.MINUS_X, 0)] = layout.moduleName("jpst_building_small")
local rx = build({ modulesByName = mx })
summarize("mixed", rx)
for i, el in ipairs(rx.edgeLists) do print(("   EL%d edgeType=%s edges=%d"):format(i, tostring(el.edgeType), #el.edges)) end
connectivity("mixed (building -X)", rx)
local mx2 = {}
for k, v in pairs(mx) do mx2[k] = v end
mx2[layout.encode(K.BUILDING, G, layout.SIDE.MINUS_X, 0)] = nil
mx2[layout.encode(K.BUILDING, G, layout.SIDE.PLUS_X, 0)] = layout.moduleName("jpst_building_small")
connectivity("mixed (building +X, elevated side)", build({ modulesByName = mx2 }))
-- 5m elevated
local m5e = {}
for j = -1, 1 do
	m5e[layout.encode(K.TRACK, E, -1, j)] = TE
	m5e[layout.encode(K.TRACK, E, 1, j)] = TE
	m5e[layout.encode(K.PLATFORM, E, 0, j)] = layout.moduleName(j == 0 and "jpst_platform_elevated_island_5_stairs" or "jpst_platform_elevated_island_5")
end
m5e[layout.encode(K.BUILDING, G, layout.SIDE.PLUS_X, 0)] = layout.moduleName("jpst_building_small")
connectivity("elevated 5m", build({ modulesByName = m5e }))
-- conflicting level in a row should be ignored, not crash
local mc = { [layout.encode(K.TRACK, G, 0, 0)] = T, [layout.encode(K.TRACK, E, 0, 1)] = TE }
variant("conflict row", mc)
-- slots offered: empty row offers both levels
local rs = build({ modulesByName = mx })
local lv = {}
for _, s in ipairs(rs.slots) do local k, l, r = layout.decode(s.id); lv[r] = lv[r] or {}; lv[r][l] = true end
for r = -3, 7 do if lv[r] then print("  row", r, "g", lv[r][0] and 1 or 0, "e", lv[r][1] and 1 or 0) end end
-- upgrade elevated track to high speed
local mm = {}
for id, name in pairs(me) do mm[id] = { name = name, variant = 0, metadata = MODULE_META[name] } end
local trk
for id, name in pairs(me) do if name:find("track") then trk = id break end end
local ue = script.upgradeFn({}, { modules = mm }, trk, { streetTemplate = "::/infrastructure/track/high_speed/high_speed.street_template" })
local after2 = {}
for id, m in pairs(ue.modules or ue) do if type(m) == "table" and m.name then after2[m.name] = (after2[m.name] or 0) + 1 end end
for k, v in pairs(after2) do print("elev upgrade:", k, v) end
local uc = script.upgradeFn({}, { modules = mm }, trk, { catenary = 1 })
for id, m in pairs(uc.modules or uc) do if id == trk then print("elev catenary toggle:", type(m)=="table" and m.name or m) end end

-- 8) track count templates: connectivity + counts
for lvl = 1, 2 do for nt = 1, 8 do for pl = 1, 2 do local pw = 2
	local p = { jpst_platformLayout = pl, jpst_length = 3, jpst_trackType = 2, jpst_catenary = 2, jpst_level = lvl, jpst_tracks = nt, jpst_platformWidth = pw }
	local m = script.createTemplateFn({}, p)
	local tr, pf, names = {}, {}, {}
	for id, name in pairs(m) do
		local k, l, r = layout.decode(id)
		if k == K.TRACK then tr[r] = true elseif k == K.PLATFORM then pf[r] = true; names[name:match("island_(%d+)")] = true end
	end
	local c = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
	local r = build({ modulesByName = m })
	local cs = r.cargoStation
	io.write(("layout=%d lvl=%d sel=%d width=%s tracks=%d platforms=%d terminals=%d  "):format(pl, lvl, nt, next(names), c(tr), c(pf), #cs.station.terminals))
	connectivity("", r)
end end end


-- 9) 2F concourse (橋上駅)
print("== concourse ==")
local function countLinkComps(r)
	-- number of distinct components that contain a linkable lane, plus whether all linkables share one
	local cs = r.cargoStation
	local n = 0
	for _, ll in ipairs(cs.laneLists) do if ll.linkable then n = n + 1 end end
	return n
end
for lvl = 1, 2 do for pl = 1, 2 do for pw = 1, 2 do for nt = 1, 8 do
	local p = { jpst_passage = 2, jpst_platformLayout = pl, jpst_length = 3, jpst_trackType = 2, jpst_catenary = 2, jpst_level = lvl, jpst_tracks = nt, jpst_platformWidth = pw }
	local m = script.createTemplateFn({}, p)
	local hasC, stairs = false, 0
	for id, name in pairs(m) do
		if name:find("concourse") then hasC = true end
		if name:find("_stairs") then stairs = stairs + 1 end
	end
	local r = build({ modulesByName = m })
	io.write(("conc lvl=%d layout=%d w=%d tracks=%d concourse=%s stairsMods=%d linkables=%d terminals=%d "):format(lvl, pl, pw, nt, tostring(hasC), stairs, countLinkComps(r), #r.cargoStation.station.terminals))
	connectivity("", r)
end end end end
-- no building: both exits public; check that the two exit lanes are in one component (free passage)
local p = { jpst_passage = 2, jpst_platformLayout = 1, jpst_length = 3, jpst_trackType = 2, jpst_catenary = 2, jpst_level = 1, jpst_tracks = 4, jpst_platformWidth = 2 }
local m = script.createTemplateFn({}, p)
for id, name in pairs(m) do if name:find("building") then m[id] = nil end end
local r = build({ modulesByName = m })
io.write("conc no building linkables=" .. countLinkComps(r) .. " ")
connectivity("", r)
-- two concourses in adjacent segments + one at an elevated-mixed segment (must be ignored)
m[layout.encode(K.CONCOURSE, G, 0, 1)] = layout.moduleName("jpst_concourse")
local r2 = build({ modulesByName = m })
io.write("conc two adjacent ")
connectivity("", r2)
local mx3 = {}
for k, v in pairs(mx) do mx3[k] = v end
mx3[layout.encode(K.CONCOURSE, G, 0, 0)] = layout.moduleName("jpst_concourse")
local r3 = build({ modulesByName = mx3 })
local ign = 0 for _ in pairs(r3.jpst.layout.ignored) do ign = ign + 1 end
io.write("conc over mixed elevated ignored=" .. ign .. " ")
connectivity("", r3)
-- concourse slot offered per segment
local cslots = 0
for _, s in ipairs(r.slots) do if s.type == "jpst_concourse" then cslots = cslots + 1 end end
print("concourse slots", cslots)
-- model sanity: no NaN in concourse model transforms
local nan = 0
for _, mdl in ipairs(r2.cargoStation.models) do for i = 1, 16 do if mdl.transf[i] ~= mdl.transf[i] then nan = nan + 1 end end end
print("NaN entries", nan)

-- 10) Tokyo type: multi-segment buildings, skins from other mods
print("== buildings ==")
local function copyMods(t) local r = {} for k, v in pairs(t) do r[k] = v end return r end
local function lanesAt(r, x, y, z)
	local n = 0
	for _, ll in ipairs(r.cargoStation.laneLists) do
		local t = ll.transf
		for _, nd in ipairs(ll.nodes) do
			local p = nd[1]
			local px = t[1] * p[1] + t[5] * p[2] + t[9] * p[3] + t[13]
			local py = t[2] * p[1] + t[6] * p[2] + t[10] * p[3] + t[14]
			local pz = t[3] * p[1] + t[7] * p[2] + t[11] * p[3] + t[15]
			if math.abs(px - x) < 0.01 and math.abs(py - y) < 0.01 and math.abs(pz - z) < 0.01 then n = n + 1; break end
		end
	end
	return n
end
local function nIgnored(r) local n = 0 for _ in pairs(r.jpst.layout.ignored) do n = n + 1 end return n end
local function bslots(r)
	local t = {}
	for _, s in ipairs(r.slots) do if s.type:match("^jpst_building") then t[s.type] = (t[s.type] or 0) + 1 end end
	local keys = {} for k in pairs(t) do keys[#keys + 1] = k end table.sort(keys)
	local out = {} for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. t[k] end
	return table.concat(out, " ")
end
local function brick(k) return layout.moduleName("jpst_building_brick_" .. k) end
local function bid(side, size, seg) return layout.encode(K.BUILDING, G, layout.buildingRow(side, size), seg) end
local MINUS, PLUS = layout.SIDE.MINUS_X, layout.SIDE.PLUS_X
local function check(label, r, expectIgnored)
	local ig = nIgnored(r)
	io.write(("%s ignored=%d%s "):format(label, ig, (expectIgnored and ig ~= expectIgnored) and " FAIL(expected " .. expectIgnored .. ")" or ""))
	connectivity("", r)
end

-- a) elevated, large building over the full length on -X; then also on +X
for len = 1, 8 do
	local p = { jpst_building = 2, jpst_length = len, jpst_trackType = 2, jpst_catenary = 2, jpst_level = 2, jpst_tracks = 4, jpst_platformWidth = 2 }
	local m = script.createTemplateFn({}, p)
	local r = build({ modulesByName = m })
	check("elev brick len=" .. len, r, 0)
	local s = -math.floor(len / 2)
	m[bid(PLUS, len, s)] = brick(len)
	check("elev brick both sides len=" .. len, build({ modulesByName = m }), 0)
end
-- b) mixed ground/elevated rows, brick_3 on both sides (-X faces ground rows, +X faces elevated rows)
local mxb = copyMods(mx)
mxb[layout.encode(K.BUILDING, G, MINUS, 0)] = nil
mxb[bid(MINUS, 3, -1)] = brick(3)
mxb[bid(PLUS, 3, -1)] = brick(3)
local rxb = build({ modulesByName = mxb })
check("mixed brick both sides", rxb, 0)
print("   slots:", bslots(rxb))
-- c) ground + 2F concourse + brick: the concourse descends into the building hall
for _, len in ipairs({ 1, 3, 5 }) do
	local p = { jpst_building = 2, jpst_passage = 2, jpst_length = len, jpst_trackType = 2, jpst_catenary = 2, jpst_level = 1, jpst_tracks = 4, jpst_platformWidth = 2 }
	local m = script.createTemplateFn({}, p)
	local r = build({ modulesByName = m })
	local L = r.jpst.layout
	local b = L.buildings[L.buildingAt[MINUS][0]]
	io.write(("conc+brick len=%d front=%.1f hallNodeLanes=%d "):format(len, b.front, lanesAt(r, b.front - 8, 0, 0)))
	check("", r, 0)
end
-- d) overlapping buildings: one of them is ignored
local p = { jpst_building = 2, jpst_length = 3, jpst_trackType = 2, jpst_catenary = 2, jpst_level = 1, jpst_tracks = 2, jpst_platformWidth = 2 }
local mo = script.createTemplateFn({}, p)
mo[layout.encode(K.BUILDING, G, MINUS, 0)] = layout.moduleName("jpst_building_small")
check("overlap small+brick3", build({ modulesByName = mo }), 1)
-- e) rows differ per segment: an extra side platform + track only in segment 0 on -X; brick_3 front follows it
local p = { jpst_building = 2, jpst_length = 3, jpst_trackType = 2, jpst_catenary = 2, jpst_level = 1, jpst_tracks = 2, jpst_platformWidth = 2 }
local me2 = script.createTemplateFn({}, p)
local minRow = 0
for id in pairs(me2) do local k, _, row = layout.decode(id) if k ~= K.BUILDING and row < minRow then minRow = row end end
me2[layout.encode(K.TRACK, G, minRow - 1, 0)] = T
me2[layout.encode(K.PLATFORM, G, minRow - 2, 0)] = layout.moduleName("jpst_platform_island_10")
local r = build({ modulesByName = me2 })
local L = r.jpst.layout
local b = L.buildings[L.buildingAt[MINUS][0]]
local xL1 = layout.segEdges(L, 1)
io.write(("uneven rows front=%.1f seg1 edge=%.1f gapLanes(UZ)=%d "):format(b.front, xL1, lanesAt(r, xL1, layout.segY(1), layout.UNDERGROUND_Z)))
check("", r, 0)
-- same, elevated: ground access under the viaduct across the gap
local p = { jpst_building = 2, jpst_length = 3, jpst_trackType = 2, jpst_catenary = 2, jpst_level = 2, jpst_tracks = 2, jpst_platformWidth = 2 }
local me3 = script.createTemplateFn({}, p)
me3[layout.encode(K.TRACK, E, minRow - 1, 0)] = TE
me3[layout.encode(K.PLATFORM, E, minRow - 2, 0)] = layout.moduleName("jpst_platform_elevated_island_10_stairs")
check("uneven rows elevated", build({ modulesByName = me3 }), 0)
-- f) a covered segment disappears: the building is ignored but keeps its (typed) slot
local p = { jpst_building = 2, jpst_length = 3, jpst_trackType = 2, jpst_catenary = 2, jpst_level = 1, jpst_tracks = 2, jpst_platformWidth = 2 }
local mf = script.createTemplateFn({}, p)
for id in pairs(mf) do local k, _, _, seg = layout.decode(id) if k ~= K.BUILDING and seg == 1 then mf[id] = nil end end
local rf = build({ modulesByName = mf })
check("covered seg removed", rf, 1)
-- g) skin from another mod (jpst_building_example) on +X, next to the small one on -X
local mg = script.createTemplateFn({}, { jpst_length = 3, jpst_tracks = 2 })
mg[layout.encode(K.BUILDING, G, PLUS, 0)] = "jpst_building_example::/stations/jpst_example/jpstx_building_wood.module"
local rg = build({ modulesByName = mg })
check("example mod skin +X", rg, 0)
-- h) slot offer: building slots of every size that fits, none over an occupied side
local rh = build({ modulesByName = script.createTemplateFn({}, { jpst_length = 3, jpst_tracks = 2 }) })
print("slots len=3 small at -X seg0:", bslots(rh))
local rh2 = build({ modulesByName = script.createTemplateFn({}, { jpst_length = 3, jpst_tracks = 2, jpst_building = 3 }) })
print("slots len=3 no building:", bslots(rh2))
-- i) NaN and building model count
local nan = 0
for _, mdl in ipairs(rxb.cargoStation.models) do for i = 1, 16 do if mdl.transf[i] ~= mdl.transf[i] then nan = nan + 1 end end end
print("NaN entries (mixed brick)", nan)
-- j) large building sweep: every level/layout/track count/passage/width, length 4
local sweepBad, sweepN = 0, 0
local realPrint = print
for lvl = 1, 2 do for pl = 1, 2 do for nt = 1, 8 do for ps = 1, 2 do for pw = 1, 2 do
	local p = { jpst_building = 2, jpst_passage = ps, jpst_platformLayout = pl, jpst_length = 4, jpst_trackType = 2, jpst_catenary = 2, jpst_level = lvl, jpst_tracks = nt, jpst_platformWidth = pw }
	local r = build({ modulesByName = script.createTemplateFn({}, p) })
	local out
	print = function(s) out = s end
	connectivity("", r)
	print = realPrint
	sweepN = sweepN + 1
	if nIgnored(r) > 0 or not out:match("unlinked terminal edges=0 ") then sweepBad = sweepBad + 1; print("FAIL sweep", lvl, pl, nt, ps, pw, out) end
end end end end end
print("large building sweep", sweepN, "bad", sweepBad)
-- k) free building slots must not overlap the slot box of a placed module at the same height
--    (the game refuses to place into such a slot; see the ground-station bug)
local function slotBox(s)
	local t, sp = s.transf, s.spacing
	local xs, ys = {}, {}
	for _, c in ipairs({ { -sp[1], -sp[3] }, { sp[2], -sp[3] }, { -sp[1], sp[4] }, { sp[2], sp[4] } }) do
		xs[#xs + 1] = t[1] * c[1] + t[5] * c[2] + t[13]
		ys[#ys + 1] = t[2] * c[1] + t[6] * c[2] + t[14]
	end
	return math.min(table.unpack(xs)), math.max(table.unpack(xs)), math.min(table.unpack(ys)), math.max(table.unpack(ys)), t[15]
end
local function blockedBuildingSlots(m, r)
	local occ = {}
	for _, s in ipairs(r.slots) do if m[s.id] then occ[#occ + 1] = s end end
	local bad = 0
	for _, s in ipairs(r.slots) do
		if s.type:match("^jpst_building") and not m[s.id] then
			local ax0, ax1, ay0, ay1, az = slotBox(s)
			for _, o in ipairs(occ) do
				local bx0, bx1, by0, by1, bz = slotBox(o)
				if math.abs(az - bz) < 1 and math.min(ax1, bx1) - math.max(ax0, bx0) > 1e-3 and math.min(ay1, by1) - math.max(ay0, by0) > 1e-3 then
					bad = bad + 1
					break
				end
			end
		end
	end
	return bad
end
local kBad, kN = 0, 0
for lvl = 1, 2 do for pl = 1, 2 do for nt = 1, 8 do for b = 1, 3 do for ps = 1, 2 do
	local p = { jpst_building = b, jpst_passage = ps, jpst_platformLayout = pl, jpst_length = 3, jpst_trackType = 2, jpst_catenary = 2, jpst_level = lvl, jpst_tracks = nt, jpst_platformWidth = 2 }
	local m = script.createTemplateFn({}, p)
	local n = blockedBuildingSlots(m, build({ modulesByName = m }))
	kN = kN + 1
	if n > 0 then kBad = kBad + 1; print("FAIL blocked building slots", lvl, pl, nt, b, ps, n) end
end end end end end
print("building slot overlap check", kN, "bad", kBad)
-- 11) forecourt (駅前): plaza modules behind the station buildings
print("== forecourt ==")
local function fcid(side, d, w, h, seg) return layout.encode(K.FORECOURT, G, layout.forecourtRow(side, d, w, h), seg) end
local PAVED = function(w, h) return layout.moduleName(("jpst_forecourt_paved_%dx%d"):format(w, h)) end
local GREEN = function(w, h) return layout.moduleName(("jpst_forecourt_green_%dx%d"):format(w, h)) end
local function fslots(r)
	local t, n = {}, 0
	for _, s in ipairs(r.slots) do if s.type:match("^jpst_forecourt") then t[s.type] = (t[s.type] or 0) + 1; n = n + 1 end end
	local keys = {} for k in pairs(t) do keys[#keys + 1] = k end table.sort(keys)
	local out = {} for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. t[k] end
	return n, table.concat(out, " ")
end
-- union-find over lane nodes; returns a function mapping a world point to its component (nil if no node)
local function components(r)
	local pts, parent = {}, {}
	local function find(i) while parent[i] ~= i do parent[i] = parent[parent[i]]; i = parent[i] end return i end
	for _, ll in ipairs(r.cargoStation.laneLists) do
		local t, first = ll.transf, #pts + 1
		for _, n in ipairs(ll.nodes) do
			local p = n[1]
			pts[#pts + 1] = { t[1] * p[1] + t[5] * p[2] + t[9] * p[3] + t[13], t[2] * p[1] + t[6] * p[2] + t[10] * p[3] + t[14],
				t[3] * p[1] + t[7] * p[2] + t[11] * p[3] + t[15] }
			parent[#pts] = #pts
		end
		for e = 0, (#ll.nodes // 2) - 1 do parent[find(first + 2 * e)] = find(first + 2 * e + 1) end
	end
	local function near(a, b) return math.abs(a[1] - b[1]) < 0.01 and math.abs(a[2] - b[2]) < 0.01 and math.abs(a[3] - b[3]) < 0.01 end
	for i = 1, #pts do for j = i + 1, #pts do if near(pts[i], pts[j]) then
		local a, b = find(i), find(j); if a ~= b then parent[a] = b end
	end end end
	return function(x, y, z)
		for i, p in ipairs(pts) do if near(p, { x, y, z }) then return find(i) end end
	end, function(li) -- component of lane li (1-based), first node
		local k = 0
		for i = 1, li - 1 do k = k + #r.cargoStation.laneLists[i].nodes end
		return find(k + 1)
	end
end
-- every cell centre of every placed plaza must be on the same lane component as the platforms
local function fcCheck(label, m, expectIgnored, expectUnreachable)
	local r = build({ modulesByName = m })
	local L = r.jpst.layout
	local compAt, compOfLane = components(r)
	local term = compOfLane(r.cargoStation.station.terminals[1].personEdges[1][1] + 1)
	local cells, bad = 0, 0
	for id, f in pairs(L.forecourts) do
		local tf = layout.forecourtTransf(L, f.side, f.seg, f.d, f.w, f.h)
		for i = 0, f.w - 1 do for j = 0, f.h - 1 do
			local lx, ly = -f.w * 20 + 20 + 40 * i, -f.h * 20 + 20 + 40 * j
			local x, y = tf[1] * lx + tf[5] * ly + tf[13], tf[2] * lx + tf[6] * ly + tf[14]
			cells = cells + 1
			if compAt(x, y, f.level == E and layout.DECK_Z or 0) ~= term then bad = bad + 1 end
		end end
	end
	local ig = nIgnored(r)
	local fail = (ig ~= (expectIgnored or 0)) or bad ~= (expectUnreachable or 0)
	local nan = 0
	for _, mdl in ipairs(r.cargoStation.models) do for i = 1, 16 do if mdl.transf[i] ~= mdl.transf[i] then nan = nan + 1 end end end
	print(("%s%s ignored=%d cells=%d unreachable=%d nan=%d slots=%d"):format(fail and "FAIL " or "", label, ig, cells, bad, nan,
		(fslots(r))))
	return r
end
-- a) ground, brick_3 on -X; 2x2 + 1x1 in row 0 and a 1x1 two rows out (reached through the 2x2)
for lvl = 1, 2 do
	local m = script.createTemplateFn({}, { jpst_building = 2, jpst_length = 3, jpst_tracks = 2, jpst_level = lvl })
	local L0 = build({ modulesByName = m }).jpst.layout
	local s0 = math.huge for s in pairs(L0.buildingAt[MINUS]) do s0 = math.min(s0, s) end
	local b0 = L0.buildings[L0.buildingAt[MINUS][s0]]
	print(("lvl %d brick depth=%s front=%.1f back=%.1f base=%.1f"):format(lvl, b0.depth, b0.front, b0.back, L0.forecourtBase[MINUS]))
	if b0.depth ~= 40 then print("FAIL brick jpst_depth") end
	print("   forecourt slots (none placed):", select(2, fslots(build({ modulesByName = m }))), "count", (fslots(build({ modulesByName = m }))))
	m[fcid(MINUS, 0, 2, 2, s0)] = PAVED(2, 2)
	m[fcid(MINUS, 0, 1, 1, s0 + 2)] = GREEN(1, 1)
	m[fcid(MINUS, 2, 1, 1, s0)] = PAVED(1, 1)
	m[fcid(MINUS, 1, 1, 1, s0 + 2)] = GREEN(1, 1)
	m[fcid(MINUS, 2, 2, 1, s0 + 1)] = PAVED(2, 1)
	fcCheck("lvl " .. lvl .. " brick3 + 5 plazas", m, 0)
end
-- b) mixed depths in row 0: small (17) + wood (20) + small; the gap to the shallow ones is bridged
local mb = script.createTemplateFn({}, { jpst_length = 3, jpst_tracks = 2 })
mb[bid(MINUS, 1, -1)] = layout.moduleName("jpst_building_small")
mb[bid(MINUS, 1, 1)] = "jpst_building_example::/stations/jpst_example/jpstx_building_wood.module"
mb[fcid(MINUS, 0, 1, 1, -1)] = PAVED(1, 1)
mb[fcid(MINUS, 0, 2, 1, 0)] = GREEN(2, 1)
local rb = fcCheck("mixed depths", mb, 0)
local Lb = rb.jpst.layout
print(("   base=%.1f gaps=%.1f,%.1f,%.1f"):format(Lb.forecourtBase[MINUS], layout.forecourtGap(Lb, MINUS, -1),
	layout.forecourtGap(Lb, MINUS, 0), layout.forecourtGap(Lb, MINUS, 1)))
-- plazas on both sides with brick on both sides, elevated
local mc = script.createTemplateFn({}, { jpst_building = 2, jpst_length = 4, jpst_tracks = 4, jpst_level = 2 })
mc[bid(PLUS, 4, -2)] = brick(4)
mc[fcid(PLUS, 0, 2, 2, -2)] = PAVED(2, 2)
mc[fcid(PLUS, 0, 2, 2, 0)] = PAVED(2, 2)
mc[fcid(MINUS, 0, 2, 1, -1)] = GREEN(2, 1)
fcCheck("elevated both sides", mc, 0)
-- c) ignored: no building in a covered column / overlap / beyond the grid
local md = script.createTemplateFn({}, { jpst_length = 3, jpst_tracks = 2 }) -- small at -X seg 0 only
md[fcid(MINUS, 0, 2, 1, 0)] = PAVED(2, 1)
fcCheck("no building in column", md, 1)
local me = script.createTemplateFn({}, { jpst_length = 3, jpst_tracks = 2 })
me[fcid(MINUS, 0, 1, 1, 0)] = PAVED(1, 1)
me[fcid(PLUS, 0, 1, 1, 0)] = PAVED(1, 1)
fcCheck("plaza on side without building", me, 1)
local mf2 = script.createTemplateFn({}, { jpst_building = 2, jpst_length = 3, jpst_tracks = 2 })
mf2[fcid(MINUS, 0, 2, 2, -1)] = PAVED(2, 2)
mf2[fcid(MINUS, 1, 1, 1, 0)] = PAVED(1, 1)
-- the 1x1 has the lower id and wins; with nothing between it and the building it is a separate
-- (still linkable) lane island, which is accepted
fcCheck("overlapping plazas", mf2, 1, 1)
-- the building behind a plaza is removed: the plaza is ignored but keeps its slot
local mg2 = script.createTemplateFn({}, { jpst_length = 3, jpst_tracks = 2 })
mg2[fcid(MINUS, 0, 1, 1, 0)] = PAVED(1, 1)
mg2[layout.encode(K.BUILDING, G, MINUS, 0)] = nil
fcCheck("building removed", mg2, 1)
-- d) slot overlap check: free building/forecourt slots vs placed modules, with plazas placed
local function blockedSlots(m, r, pattern)
	local occ = {}
	for _, s in ipairs(r.slots) do if m[s.id] then occ[#occ + 1] = s end end
	local bad = 0
	for _, s in ipairs(r.slots) do
		if s.type:match(pattern) and not m[s.id] then
			local ax0, ax1, ay0, ay1, az = slotBox(s)
			for _, o in ipairs(occ) do
				local bx0, bx1, by0, by1, bz = slotBox(o)
				if math.abs(az - bz) < 1 and math.min(ax1, bx1) - math.max(ax0, bx0) > 1e-3 and math.min(ay1, by1) - math.max(ay0, by0) > 1e-3 then
					bad = bad + 1
					break
				end
			end
		end
	end
	return bad
end
local fN, fBad, fOffered = 0, 0, 0
for lvl = 1, 2 do for nt = 1, 6 do for b = 1, 3 do for withPlaza = 0, 1 do
	local m = script.createTemplateFn({}, { jpst_building = b, jpst_length = 3, jpst_tracks = nt, jpst_level = lvl })
	m[bid(PLUS, 1, 1)] = "jpst_building_example::/stations/jpst_example/jpstx_building_wood.module"
	if withPlaza == 1 then
		m[fcid(PLUS, 0, 1, 1, 1)] = GREEN(1, 1)
		local L = build({ modulesByName = m }).jpst.layout
		if L.buildingAt[MINUS][0] then m[fcid(MINUS, 1, 1, 1, 0)] = PAVED(1, 1) end
	end
	local r = build({ modulesByName = m })
	local n = blockedSlots(m, r, "^jpst_building") + blockedSlots(m, r, "^jpst_forecourt")
	fOffered = fOffered + (fslots(r))
	fN = fN + 1
	if n > 0 or nIgnored(r) > 0 then fBad = fBad + 1; print("FAIL forecourt slot overlap", lvl, nt, b, withPlaza, n, nIgnored(r)) end
end end end end
print("forecourt slot overlap check", fN, "bad", fBad, "slots offered", fOffered)
-- e) lane patterns (cross / along / through / none): same skin, different lanes param
for _, pat in ipairs({ "cross", "along", "through", "none" }) do
	local name = "jpst_station::/test/forecourt_" .. pat
	TEST_MODULES[name] = function()
		local d = moduleDesc(PAVED(2, 2))
		d.updateScript.params = { lanes = pat }
		return d
	end
	local m = script.createTemplateFn({}, { jpst_building = 2, jpst_length = 3, jpst_tracks = 2 })
	m[fcid(MINUS, 0, 2, 2, -1)] = name
	local r = build({ modulesByName = m })
	local L = r.jpst.layout
	local n = 0
	for _, ll in ipairs(r.cargoStation.laneLists) do if ll.linkable and #ll.nodes > 0 then n = n + 1 end end
	-- cross/through reach the station: 4 cells; along/none: none reachable from the platforms
	local expect = (pat == "cross" or pat == "through") and 0 or 4
	fcCheck("lanes=" .. pat, m, 0, expect)
end
-- 12) pedestrian deck (ペデストリアンデッキ): forecourt level 1 at DECK_Z
print("== deck ==")
local DZ = layout.DECK_Z
local function dkid(side, d, w, h, seg) return layout.encode(K.FORECOURT, E, layout.forecourtRow(side, d, w, h), seg) end
local DECK = function(w, h) return layout.moduleName(("jpst_deck_concrete_%dx%d"):format(w, h)) end
local function nodesAt(r, x, y, z)
	local n = 0
	for _, ll in ipairs(r.cargoStation.laneLists) do
		local t = ll.transf
		for _, nd in ipairs(ll.nodes) do
			local p = nd[1]
			local wx = t[1] * p[1] + t[5] * p[2] + t[9] * p[3] + t[13]
			local wy = t[2] * p[1] + t[6] * p[2] + t[10] * p[3] + t[14]
			local wz = t[3] * p[1] + t[7] * p[2] + t[11] * p[3] + t[15]
			if math.abs(wx - x) < 0.01 and math.abs(wy - y) < 0.01 and math.abs(wz - z) < 0.01 then n = n + 1 end
		end
	end
	return n
end
-- world point of a local forecourt-frame point
local function fcWorld(L, f, lx, ly)
	local tf = layout.forecourtTransf(L, f.side, f.seg, f.d, f.w, f.h)
	return tf[1] * lx + tf[5] * ly + tf[13], tf[2] * lx + tf[6] * ly + tf[14]
end
-- a) ground + 2F concourse + small building: deck 1x1 over a paved 1x1; the deck joins the concourse at
--    the building front at 2F, and its stair foot lands on the plaza centre node
do
	local m = script.createTemplateFn({}, { jpst_length = 3, jpst_tracks = 2, jpst_passage = 2 })
	m[dkid(MINUS, 0, 1, 1, 0)] = DECK(1, 1)
	m[fcid(MINUS, 0, 1, 1, 0)] = PAVED(1, 1)
	local r = fcCheck("deck + concourse + plaza", m, 0)
	local L = r.jpst.layout
	local b = L.buildings[L.buildingAt[MINUS][0]]
	local compAt, compOfLane = components(r)
	local term = compOfLane(r.cargoStation.station.terminals[1].personEdges[1][1] + 1)
	local nFront = nodesAt(r, b.front, 0, DZ)
	print(("   deck/concourse joint nodes=%d (deck %s)"):format(nFront, tostring(DZ == layout.CONCOURSE_Z)))
	if nFront < 3 then print("FAIL deck does not meet the concourse at the building front") end
	local f = L.forecourts[dkid(MINUS, 0, 1, 1, 0)]
	local cx, cy = fcWorld(L, f, 0, 0)
	if compAt(cx, cy, 0) ~= term or nodesAt(r, cx, cy, 0) < 4 then print("FAIL deck stair foot not on the plaza centre") end
	-- without the plaza the stair foot is still a linkable lane end on the ground
	m[fcid(MINUS, 0, 1, 1, 0)] = nil
	local r2 = fcCheck("deck without plaza", m, 0)
	local linkGround = 0
	for _, ll in ipairs(r2.cargoStation.laneLists) do
		if ll.linkable and ll.nodes[1] and math.abs(ll.nodes[1][1][3]) < 0.01 then linkGround = linkGround + 1 end
	end
	print("   linkable ground lanes", linkGround)
end
-- b) brick over 3 segments + concourse: 2x2 deck and 1x1 decks (one two rows out, reached over the 2x2)
for lvl = 1, 2 do
	local m = script.createTemplateFn({}, { jpst_building = 2, jpst_length = 3, jpst_tracks = 4, jpst_level = lvl, jpst_passage = 2 })
	local L0 = build({ modulesByName = m }).jpst.layout
	local s0 = math.huge for s in pairs(L0.buildingAt[MINUS]) do s0 = math.min(s0, s) end
	m[dkid(MINUS, 0, 2, 2, s0)] = DECK(2, 2)
	m[dkid(MINUS, 0, 1, 1, s0 + 2)] = DECK(1, 1)
	m[dkid(MINUS, 2, 1, 1, s0)] = DECK(1, 1)
	m[fcid(MINUS, 0, 2, 2, s0)] = PAVED(2, 2)
	m[fcid(MINUS, 2, 2, 1, s0 + 1)] = GREEN(2, 1)
	fcCheck("lvl " .. lvl .. " brick3 + 3 decks + 2 plazas", m, 0)
end
-- c) mixed depths on -X (small 17 / wood 20 / small): the plaza connector of every column must end on the
--    street lane of the building in that same column (column order is mirrored on the -X side)
do
	local m = script.createTemplateFn({}, { jpst_length = 3, jpst_tracks = 2, jpst_passage = 2 })
	m[bid(MINUS, 1, -1)] = layout.moduleName("jpst_building_small")
	m[bid(MINUS, 1, 1)] = "jpst_building_example::/stations/jpst_example/jpstx_building_wood.module"
	m[fcid(MINUS, 0, 2, 1, 0)] = GREEN(2, 1)
	m[dkid(MINUS, 0, 2, 1, -1)] = DECK(2, 1)
	local r = fcCheck("mixed depths + deck", m, 0)
	local L = r.jpst.layout
	for s = 0, 1 do
		local b = L.buildings[L.buildingAt[MINUS][s]]
		local n = nodesAt(r, b.front - (b.depth - 3), layout.segY(s), 0)
		if n < 3 then print("FAIL plaza connector misses the street lane of column", s, n) end
	end
end
-- d) both sides, elevated (no concourse: the deck goes down into the building hall)
do
	local m = script.createTemplateFn({}, { jpst_building = 2, jpst_length = 4, jpst_tracks = 4, jpst_level = 2 })
	m[bid(PLUS, 4, -2)] = brick(4)
	m[dkid(PLUS, 0, 1, 1, -2)] = DECK(1, 1)
	m[dkid(PLUS, 0, 2, 1, 0)] = DECK(2, 1)
	m[dkid(MINUS, 0, 2, 2, -1)] = DECK(2, 2)
	fcCheck("elevated decks both sides", m, 0)
end
-- e) ignored: no building on that side / two decks overlapping; a deck over a plaza is fine
do
	local m = script.createTemplateFn({}, { jpst_length = 3, jpst_tracks = 2 })
	m[dkid(PLUS, 0, 1, 1, 0)] = DECK(1, 1)
	fcCheck("deck on side without building", m, 1)
	local m2 = script.createTemplateFn({}, { jpst_building = 2, jpst_length = 3, jpst_tracks = 2 })
	m2[dkid(MINUS, 0, 2, 2, -1)] = DECK(2, 2)
	m2[dkid(MINUS, 1, 1, 1, 0)] = DECK(1, 1)
	fcCheck("overlapping decks", m2, 1, 1)
end
-- f) slot overlap: free building/forecourt/deck slots vs placed modules
do
	local n, bad, offered = 0, 0, 0
	for lvl = 1, 2 do for nt = 1, 6 do for b = 1, 3 do for ps = 1, 2 do
		local m = script.createTemplateFn({}, { jpst_building = b, jpst_length = 3, jpst_tracks = nt, jpst_level = lvl, jpst_passage = ps })
		m[bid(PLUS, 1, 1)] = "jpst_building_example::/stations/jpst_example/jpstx_building_wood.module"
		m[dkid(PLUS, 0, 1, 1, 1)] = DECK(1, 1)
		m[fcid(PLUS, 0, 1, 1, 1)] = GREEN(1, 1)
		local L = build({ modulesByName = m }).jpst.layout
		if L.buildingAt[MINUS][0] then m[dkid(MINUS, 1, 1, 1, 0)] = DECK(1, 1) end
		local r = build({ modulesByName = m })
		local k = blockedSlots(m, r, "^jpst_building") + blockedSlots(m, r, "^jpst_forecourt") + blockedSlots(m, r, "^jpst_deck")
			+ blockedSlots(m, r, "^jpst_concourse")
		for _, sl in ipairs(r.slots) do if sl.type:match("^jpst_deck") then offered = offered + 1 end end
		n = n + 1
		if k > 0 or nIgnored(r) > 0 then bad = bad + 1; print("FAIL deck slot overlap", lvl, nt, b, ps, k, nIgnored(r)) end
	end end end end
	print("deck slot overlap check", n, "bad", bad, "deck slots offered", offered)
end
-- g) lane patterns and stairs params
for _, pat in ipairs({ "cross", "along", "through" }) do for _, st in ipairs({ "outer", "all", "none" }) do
	local name = ("jpst_station::/test/deck_%s_%s"):format(pat, st)
	TEST_MODULES[name] = function()
		local d = moduleDesc(DECK(2, 2))
		d.updateScript.params = { lanes = pat, stairs = st }
		return d
	end
	local m = script.createTemplateFn({}, { jpst_building = 2, jpst_length = 3, jpst_tracks = 2, jpst_passage = 2 })
	m[dkid(MINUS, 0, 2, 2, -1)] = name
	-- along: the outer cell row only reaches the station through its stairs, which need a plaza below
	local expect = (pat == "along") and 2 or 0
	if pat == "along" and st ~= "none" then
		m[fcid(MINUS, 0, 2, 2, -1)] = PAVED(2, 2)
		expect = 0
	end
	fcCheck(("deck lanes=%s stairs=%s"):format(pat, st), m, 0, expect)
end end

-- 13) bus rotary (バスロータリー): 1F forecourt module with a bus loop and bus stop terminals
print("== bus rotary ==")
local ROT = function(w, h) return layout.moduleName(("jpst_busrotary_basic_%dx%d"):format(w, h)) end
local function wpt(t, x, y, z)
	return t[1] * x + t[5] * y + t[9] * z + t[13], t[2] * x + t[6] * y + t[10] * z + t[14], t[3] * x + t[7] * y + t[11] * z + t[15]
end
local function rotCheck(label, m, expectStops, expectIgnored)
	local r = build({ modulesByName = m })
	local L = r.jpst.layout
	local cs = r.cargoStation
	local compAt, compOfLane = components(r)
	local terms = cs.station.terminals
	local fail = {}
	local trainTerm = compOfLane(terms[1].personEdges[1][1] + 1)
	local bus = 0
	for i, t in ipairs(terms) do
		if t.tag ~= i then fail[#fail + 1] = "tag" end
		if t.transportModes[1] == "BUS" then
			bus = bus + 1
			local vl = cs.laneLists[t.vehicleNode[1] + 1]
			if not vl or vl.transportModes[1] ~= "BUS" or #vl.nodes < t.vehicleNode[2] + 1 then fail[#fail + 1] = "vehicleNode" end
			for _, e in ipairs(t.vehicleEdges) do
				if e[1] ~= t.vehicleNode[1] or 2 * e[2] + 2 > #vl.nodes then fail[#fail + 1] = "vehicleEdge" end
			end
			for _, pe in ipairs(t.personEdges) do
				local pl = cs.laneLists[pe[1] + 1]
				if pl.transportModes[1] ~= "PERSON" or 2 * pe[2] + 2 > #pl.nodes then fail[#fail + 1] = "personEdge" end
				if compOfLane(pe[1] + 1) ~= trainTerm then fail[#fail + 1] = "stop not reachable from the platforms" end
			end
			for _, pn in ipairs(t.personNodes) do
				if pn[2] + 1 > #cs.laneLists[pn[1] + 1].nodes then fail[#fail + 1] = "personNode" end
			end
			if not t.cargoTransferSpeeds or t.cargoTransferSpeeds[1].length <= 0 then fail[#fail + 1] = "length" end
		end
	end
	if bus ~= expectStops then fail[#fail + 1] = ("stops %d ~= %d"):format(bus, expectStops) end
	-- street stubs: one per placed rotary, after the track lists, outer node on the module edge; the loop
	-- ends meet the stub's driving lanes (inner node +-2.5 m) and the whole loop is one component
	local stubs = 0
	for i, el in ipairs(r.edgeLists) do
		if el.type == "STREET" then
			stubs = stubs + 1
			if r.edgeListHasCatenary[i] ~= nil then fail[#fail + 1] = "street list before track lists" end
			if el.snapNodes[1] ~= 0 or #el.edges ~= 2 then fail[#fail + 1] = "stub shape" end
		elseif stubs > 0 then fail[#fail + 1] = "track list after street list" end
	end
	local placed = 0
	for id, f in pairs(L.forecourts) do
		if m[id] and m[id]:match("busrotary") then
			placed = placed + 1
			local g = layout.rotaryGeometry(f.w, f.h)
			local tf = layout.forecourtTransf(L, f.side, f.seg, f.d, f.w, f.h)
			local found = false
			for _, el in ipairs(r.edgeLists) do
				if el.type == "STREET" then
					local ox, oy = wpt(tf, 0, -g.hy, 0)
					local p = el.edges[1][1]
					if math.abs(p[1] - ox) < 0.01 and math.abs(p[2] - oy) < 0.01 then found = true end
				end
			end
			if not found then fail[#fail + 1] = "stub not at the outer edge" end
			local ix, iy = wpt(tf, 2.5, g.entryY, 0)
			local ox2, oy2 = wpt(tf, -2.5, g.entryY, 0)
			local a, b = compAt(ix, iy, 0), compAt(ox2, oy2, 0)
			if not a or a ~= b then fail[#fail + 1] = "bus loop not closed" end
			-- sidewalk side edges meet the neighbouring plaza grid rows
			local ex, ey = wpt(tf, -g.hx, -g.hy + 20, 0)
			if not compAt(ex, ey, 0) then fail[#fail + 1] = "no side node" end
		end
	end
	if stubs ~= placed then fail[#fail + 1] = ("stubs %d ~= placed %d"):format(stubs, placed) end
	if nIgnored(r) ~= (expectIgnored or 0) then fail[#fail + 1] = "ignored " .. nIgnored(r) end
	local nan = 0
	for _, mdl in ipairs(cs.models) do for i = 1, 16 do if mdl.transf[i] ~= mdl.transf[i] then nan = nan + 1 end end end
	for _, ll in ipairs(cs.laneLists) do for _, n in ipairs(ll.nodes) do for k = 1, 3 do
		if n[1][k] ~= n[1][k] or n[2][k] ~= n[2][k] then nan = nan + 1 end
	end end end
	if nan > 0 then fail[#fail + 1] = "NaN " .. nan end
	print(("%s%s terminals=%d bus=%d stubs=%d %s"):format(#fail > 0 and "FAIL " or "", label, #terms, bus, stubs,
		table.concat(fail, ", ")))
	return r
end
for lvl = 1, 2 do
	local m = script.createTemplateFn({}, { jpst_building = 2, jpst_length = 3, jpst_tracks = 2, jpst_level = lvl })
	local L0 = build({ modulesByName = m }).jpst.layout
	local s0 = math.huge for s in pairs(L0.buildingAt[MINUS]) do s0 = math.min(s0, s) end
	m[fcid(MINUS, 0, 1, 1, s0)] = ROT(1, 1)
	rotCheck("lvl " .. lvl .. " 1x1", m, 1)
	m[fcid(MINUS, 0, 2, 1, s0 + 1)] = ROT(2, 1)
	rotCheck("lvl " .. lvl .. " 1x1 + 2x1", m, 3)
	-- a plaza between the rotary and the station; a plaza beside it
	local m2 = script.createTemplateFn({}, { jpst_building = 2, jpst_length = 3, jpst_tracks = 2, jpst_level = lvl })
	m2[fcid(MINUS, 0, 2, 1, s0)] = PAVED(2, 1)
	m2[fcid(MINUS, 1, 2, 1, s0)] = ROT(2, 1)
	m2[fcid(MINUS, 1, 1, 1, s0 + 2)] = GREEN(1, 1)
	m2[fcid(MINUS, 0, 1, 1, s0 + 2)] = PAVED(1, 1)
	rotCheck("lvl " .. lvl .. " behind a plaza", m2, 2)
	-- under a deck
	local m3 = script.createTemplateFn({}, { jpst_building = 2, jpst_length = 3, jpst_tracks = 2, jpst_level = lvl, jpst_passage = 2 })
	m3[fcid(MINUS, 0, 2, 1, s0)] = ROT(2, 1)
	m3[dkid(MINUS, 0, 2, 1, s0)] = DECK(2, 1)
	rotCheck("lvl " .. lvl .. " under a deck", m3, 2)
end
-- mixed depths (small / wood / small): the connector of every column reaches its building street lane
do
	local m = script.createTemplateFn({}, { jpst_length = 3, jpst_tracks = 2 })
	m[bid(MINUS, 1, -1)] = layout.moduleName("jpst_building_small")
	m[bid(MINUS, 1, 1)] = "jpst_building_example::/stations/jpst_example/jpstx_building_wood.module"
	m[fcid(MINUS, 0, 2, 1, 0)] = ROT(2, 1)
	m[fcid(MINUS, 0, 1, 1, -1)] = ROT(1, 1)
	local r = rotCheck("mixed depths", m, 3)
	local L = r.jpst.layout
	for s = -1, 1 do
		local b = L.buildings[L.buildingAt[MINUS][s]]
		if nodesAt(r, b.front - (b.depth - 3), layout.segY(s), 0) < 3 then print("FAIL rotary connector misses column", s) end
	end
	-- both sides
	local m2 = script.createTemplateFn({}, { jpst_building = 2, jpst_length = 4, jpst_tracks = 4, jpst_level = 2 })
	m2[bid(PLUS, 4, -2)] = brick(4)
	m2[fcid(PLUS, 0, 2, 1, -2)] = ROT(2, 1)
	m2[fcid(MINUS, 0, 1, 1, -1)] = ROT(1, 1)
	rotCheck("both sides", m2, 3)
	-- no building on that side: ignored, no terminal, no stub
	local m3 = script.createTemplateFn({}, { jpst_length = 3, jpst_tracks = 2 })
	m3[fcid(PLUS, 0, 1, 1, 0)] = ROT(1, 1)
	rotCheck("side without building", m3, 0, 1)
end
-- slot overlap with a rotary placed
do
	local bad = 0
	for lvl = 1, 2 do for b = 1, 3 do
		local m = script.createTemplateFn({}, { jpst_building = b, jpst_length = 3, jpst_tracks = 2, jpst_level = lvl })
		m[bid(PLUS, 1, 1)] = "jpst_building_example::/stations/jpst_example/jpstx_building_wood.module"
		m[fcid(PLUS, 0, 1, 1, 1)] = ROT(1, 1)
		local r = build({ modulesByName = m })
		local k = blockedSlots(m, r, "^jpst_forecourt") + blockedSlots(m, r, "^jpst_building") + blockedSlots(m, r, "^jpst_deck")
		if k > 0 or nIgnored(r) > 0 then bad = bad + 1; print("FAIL rotary slot overlap", lvl, b, k) end
	end end
	print("rotary slot overlap check bad", bad)
end

-- 14) deck without a 2F concourse right behind the building: no empty lane lists
print("== deck without concourse ==")
do
	local m5 = script.createTemplateFn({}, { jpst_passage = 1, jpst_length = 3, jpst_tracks = 2, jpst_building = 1 })
	m5[dkid(MINUS, 0, 1, 1, 0)] = DECK(1, 1)
	local r5 = build({ modulesByName = m5 })
	for _, ll in ipairs(r5.cargoStation.laneLists) do if #ll.nodes == 0 then print("FAIL empty lane list") end end
	io.write("deck no concourse ignored=" .. nIgnored(r5) .. " ")
	connectivity("", r5)
end

-- 15) platform signs: track numbers (番線) and station name boards
print("== signs ==")
do
	local function numberLabels(r, row)
		local out = {}
		for _, s in ipairs(r.jpst.signs) do
			local id = r.cargoStation.models[s.index + 1].id
			if s.label == "number" then
				if not id:find("perron_number") then print("FAIL number sign index points to", id) end
				if s.row == row then table.insert(out, table.concat(r.cargoStation.labelText[s.index], ",")) end
			elseif not id:find("station_name") then
				print("FAIL name sign index points to", id)
			end
		end
		return out
	end
	local function expect(label, got, want)
		local ok = #got > 0
		for _, g in ipairs(got) do if g ~= want then ok = false end end
		print((ok and "" or "FAIL ") .. "signs " .. label, table.concat(got, " | "), "want", want)
	end
	local r2 = build({ modulesByName = m2 })
	expect("3 tracks row -1", numberLabels(r2, -1), "1,1,2,2")
	expect("3 tracks row 1", numberLabels(r2, 1), "2,2,3,3")
	local r5 = build({ modulesByName = m5 })
	expect("building +X counts from +X", numberLabels(r5, 0), "2,2,1,1")
	-- side platform: no track on the outer side
	local ms = {}
	for j = 0, 1 do
		ms[layout.encode(K.TRACK, G, 0, j)] = T
		ms[layout.encode(K.PLATFORM, G, 1, j)] = layout.moduleName("jpst_platform_island_5")
	end
	expect("side platform", numberLabels(build({ modulesByName = ms }), 1), "1,1,,")
	-- elevated platform next to a ground track: the ground track is not its track
	local E = layout.LEVEL.ELEVATED
	local me = {
		[layout.encode(K.TRACK, G, -1, 0)] = T,
		[layout.encode(K.TRACK, E, 1, 0)] = layout.trackModuleName(layout.TRACK_TYPES[2], true, E),
		[layout.encode(K.PLATFORM, E, 0, 0)] = layout.moduleName("jpst_platform_elevated_island_5"),
	}
	local okE, re = pcall(build, { modulesByName = me })
	if okE then expect("elevated next to ground", numberLabels(re, 0), ",,2,2") else print("FAIL elevated signs", re) end
	local n = 0
	for _ in pairs(r2.cargoStation.labelText) do n = n + 1 end
	print("labelText entries (3 tracks, 2 segs)", n)
end

-- 16) 高架下駅舎 (station hall under the viaduct)
print("== under viaduct ==")
do
	local UV = layout.moduleName("jpst_underviaduct_pillars")
	local me = script.createTemplateFn({}, { jpst_length = 3, jpst_trackType = 2, jpst_catenary = 2, jpst_level = 2 })
	local PIER = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl"
	local function uid(seg) return layout.encode(K.UNDER, G, 0, seg) end
	local function linkables(r)
		local n = 0
		for _, ll in ipairs(r.cargoStation.laneLists) do if ll.linkable then n = n + 1 end end
		return n
	end
	local function check(label, r, wantLink)
		local bad = connectivity("under " .. label, r)
		local n = linkables(r)
		if bad ~= 0 or (wantLink and n ~= wantLink) then print("FAIL under " .. label, "unlinked", bad, "linkables", n, "want", wantLink) end
		for _, mdl in ipairs(r.cargoStation.models) do for i = 1, 16 do
			if mdl.transf[i] ~= mdl.transf[i] then print("FAIL under NaN", label) return end
		end end
	end
	-- a) template: elevated + passage 3, no side building: every layout must reach the street via the hall
	local nBad = 0
	for pl = 1, 2 do for pw = 1, 2 do for nt = 1, 8 do
		local p = { jpst_passage = 3, jpst_building = 3, jpst_platformLayout = pl, jpst_length = 3, jpst_trackType = 2, jpst_catenary = 2, jpst_level = 2, jpst_tracks = nt, jpst_platformWidth = pw }
		local m = script.createTemplateFn({}, p)
		if m[uid(0)] ~= UV then nBad = nBad + 1; print("FAIL under template missing", pl, pw, nt) end
		local r = build({ modulesByName = m })
		if r.jpst.layout.ignored[uid(0)] then nBad = nBad + 1; print("FAIL under ignored", pl, pw, nt) end
		local bad = connectivity(("under tpl layout=%d w=%d tracks=%d"):format(pl, pw, nt), r)
		if bad ~= 0 or linkables(r) ~= 2 then nBad = nBad + 1; print("FAIL under tpl", pl, pw, nt, bad, linkables(r)) end
	end end end
	print("under template sweep bad", nBad)
	-- passage 3 on a ground station places nothing
	local mg = script.createTemplateFn({}, { jpst_passage = 3, jpst_level = 1, jpst_length = 3, jpst_tracks = 2 })
	if mg[uid(0)] then print("FAIL under on ground template") end

	-- b) small building on -X: exit only on +X (building street lane + 1 exit)
	local pb = { jpst_passage = 3, jpst_building = 1, jpst_length = 3, jpst_trackType = 2, jpst_catenary = 2, jpst_level = 2, jpst_tracks = 2 }
	local mb = script.createTemplateFn({}, pb)
	check("building -X", build({ modulesByName = mb }), 2)

	-- c) mixed ground/elevated (building -X): the hall under rows 2..4 opens on +X only
	local mxu = {}
	for k, v in pairs(mx) do mxu[k] = v end
	mxu[uid(0)] = UV
	local rxu = build({ modulesByName = mxu })
	if rxu.jpst.layout.ignored[uid(0)] then print("FAIL under mixed ignored") end
	check("mixed", rxu, 2)
	-- the +X exit (row 4 edge + 4 m) is a linkable lane at y=0
	local xEdge = layout.centre(rxu.jpst.layout, 4) + layout.width(rxu.jpst.layout, 4) / 2
	local comp = components(rxu)
	if not comp(xEdge + 4, 0, 0) then print("FAIL under mixed: no exit node at", xEdge + 4) end

	-- d) ground-only segment: ignored, keeps a slot; no free slot offered there
	local mg2 = { [layout.encode(K.TRACK, G, 0, 0)] = T, [layout.encode(K.PLATFORM, G, 1, 0)] = layout.moduleName("jpst_platform_island_10"), [uid(0)] = UV }
	local rg = build({ modulesByName = mg2 })
	print((rg.jpst.layout.ignored[uid(0)] and "" or "FAIL ") .. "under on ground ignored")

	-- e) slots: one per segment with an elevated row; none for ground-only segments; free ground slots
	--    must not overlap the hall slot box
	local rs2 = build({ modulesByName = me })
	local nU = 0
	for _, s in ipairs(rs2.slots) do if s.type == "jpst_underviaduct" then nU = nU + 1 end end
	print((nU == 3 and "" or "FAIL ") .. "under slots (3 elevated segments)", nU)
	local rgs = build({ modulesByName = script.createTemplateFn({}, { jpst_level = 1, jpst_length = 3 }) })
	for _, s in ipairs(rgs.slots) do if s.type == "jpst_underviaduct" then print("FAIL under slot on ground station") break end end
	local ov = 0
	for _, r in ipairs({ rxu, rs2 }) do
		local us
		for _, s in ipairs(r.slots) do if s.type == "jpst_underviaduct" and s.id == uid(0) then us = s end end
		if us then
			local ax0, ax1, ay0, ay1, az = slotBox(us)
			for _, s in ipairs(r.slots) do
				if s ~= us then
					local bx0, bx1, by0, by1, bz = slotBox(s)
					if math.abs(az - bz) < 1 and math.min(ax1, bx1) - math.max(ax0, bx0) > 1e-3 and math.min(ay1, by1) - math.max(ay0, by0) > 1e-3 then
						ov = ov + 1
						print("  overlap", s.type, s.id)
					end
				end
			end
		end
	end
	print((ov == 0 and "" or "FAIL ") .. "under slot overlaps", ov)

	-- f) stand-in piers are replaced by the column grid in the hall segment only
	local function piersAt(r, seg)
		local n = 0
		for _, mdl in ipairs(r.cargoStation.models) do
			if mdl.id == PIER and math.abs(mdl.transf[14] - layout.segY(seg)) < 20 then n = n + 1 end
		end
		return n
	end
	local me2 = {}
	for k, v in pairs(me) do me2[k] = v end
	local r0 = build({ modulesByName = me2 })
	me2[uid(0)] = UV
	local r1u = build({ modulesByName = me2 })
	print("under piers seg0 before/after", piersAt(r0, 0), piersAt(r1u, 0), "seg1", piersAt(r0, 1), piersAt(r1u, 1))
	if piersAt(r1u, 1) ~= piersAt(r0, 1) then print("FAIL under piers changed in other segment") end
	check("default elevated + hall", r1u)

	-- g) elevated stair lanes follow the stair model: down towards the segment centre (y = +-1 at deck level)
	local turns = 0
	for _, ll in ipairs(r0.cargoStation.laneLists) do
		local t = ll.transf
		for _, nd in ipairs(ll.nodes) do
			local p = nd[1]
			local py = t[2] * p[1] + t[6] * p[2] + t[10] * p[3] + t[14] - layout.segY(0)
			local pz = t[3] * p[1] + t[7] * p[2] + t[11] * p[3] + t[15]
			if math.abs(math.abs(py) - 1) < 0.01 and math.abs(pz - (layout.ELEVATED_Z - 2.4)) < 0.01 then turns = turns + 1 end
		end
	end
	print((turns > 0 and "" or "FAIL ") .. "elevated stair turn nodes seg0", turns)
end

-- 17) catenary without poles: template option 3 -> no-pole track modules on the hidden track type
do
	print("== 17 no-pole catenary")
	for lvl = 1, 2 do
		local m = script.createTemplateFn({}, { jpst_length = 3, jpst_trackType = 2, jpst_catenary = 3, jpst_level = lvl })
		local n = 0
		for _, name in pairs(m) do if name:find("_catenary_nopole", 1, true) then n = n + 1 end end
		if n == 0 then print("FAIL nopole template level", lvl) end
		local r = build({ modulesByName = m })
		local ok = false
		for i, el in ipairs(r.edgeLists) do
			if el.type == "TRACK" then
				if el.params.type:find("jpst_track/standard_catenary_nopole.street_template", 1, true) and r.edgeListHasCatenary[i] then ok = true
				else print("FAIL nopole edge list", el.params.type, tostring(r.edgeListHasCatenary[i])) end
			end
		end
		print((ok and "" or "FAIL ") .. "nopole edges level " .. lvl, n)
		-- catenary removal leads to the plain track; the no-pole module offers no catenaryAdd
		local md = MODULE_META[layout.trackModuleName("standard", true, lvl == 2 and E or G, true)]
		if not md or md.catenaryAdd or not (md.catenaryRemove or ""):find(layout.trackModuleFile("standard", false, lvl == 2 and E or G) .. ".module", 1, true) then
			print("FAIL nopole metadata", md and md.catenaryRemove)
		end
	end
	-- the hidden track type files exist and keep the wires
	for _, t in ipairs(layout.TRACK_TYPES) do
		local f = io.open("jpst_station/content/infrastructure/jpst_track/" .. t .. "_nopole.street.lua")
		local s = f and f:read("a") or ""
		if f then f:close() end
		if not s:find("catenaryMaterial", 1, true) or s:find("power_pole", 1, true) then print("FAIL nopole street style", t) end
	end
end

-- 18) platform roofs (上家): template middle/full/none, per-5 m strips, end pieces, level handling
do
	print("== 18 platform roofs")
	local ROOF_MDL = "::/stations/rail/era_c/perron_5_roof.mdl"
	local ROOF_END = "::/stations/rail/era_c/perron_5_roof_end.mdl"
	local function count(r, id, zMin)
		local n = 0
		for _, mdl in ipairs(r.cargoStation.models) do
			if mdl.id == id and (zMin == nil or mdl.transf[15] >= zMin) then n = n + 1 end
		end
		return n
	end
	local function roofSlots(r)
		local n = 0
		for _, s in ipairs(r.slots) do if s.type == "jpst_roof" then n = n + 1 end end
		return n
	end
	-- 5 x 40 m, 2 tracks, one 10 m island: middle = whole (<= 200 m), 2 strips each
	for _, case in ipairs({ { 1, 0, 0 }, { 2, 5, 2 }, { 3, 5, 2 } }) do
		local idx, segs, ends = case[1], case[2], case[3]
		for lvl = 1, 2 do
			local m = script.createTemplateFn({}, { jpst_length = 5, jpst_tracks = 2, jpst_roof = idx, jpst_level = lvl, jpst_platformWidth = 2 })
			local r = build({ modulesByName = m })
			local z = (lvl == 2) and layout.ELEVATED_Z or 0
			local nr, ne = count(r, ROOF_MDL, z), count(r, ROOF_END, z)
			local ok = nr == segs * 2 and ne == ends * 2 and roofSlots(r) == 5
			print((ok and "" or "FAIL ") .. "roof option " .. idx .. " level " .. lvl, nr, ne, roofSlots(r))
			check("roof option " .. idx .. " level " .. lvl, r)
		end
	end
	-- gap in the middle: removing the centre roof adds two more end pieces; a roof without a platform is ignored
	local m = script.createTemplateFn({}, { jpst_length = 5, jpst_tracks = 2, jpst_roof = 3, jpst_platformWidth = 1 })
	local rid
	for id, name in pairs(m) do
		local k, _, _, seg = layout.decode(id)
		if k == layout.KIND.ROOF and seg == 0 then rid = id end
	end
	m[rid] = nil
	local stray = layout.encode(layout.KIND.ROOF, layout.LEVEL.GROUND, 5, 0)
	m[stray] = m[layout.encode(layout.KIND.ROOF, layout.LEVEL.GROUND, 0, 1)]
	local r = build({ modulesByName = m })
	local nr, ne = count(r, ROOF_MDL), count(r, ROOF_END)
	print(((nr == 4 and ne == 4) and "" or "FAIL ") .. "roof gap 5 m", nr, ne)
	if not r.jpst.layout.ignored[stray] then print("FAIL stray roof not ignored") end
	check("roof gap", r)
	-- lightpoles only on roofless segments: 5 segments, middle roof covers all, full none -> 0; no roof -> 5 x 4
	for _, case in ipairs({ { 1, 20 }, { 2, 0 } }) do
		local m = script.createTemplateFn({}, { jpst_length = 5, jpst_tracks = 2, jpst_roof = case[1] })
		local r = build({ modulesByName = m })
		local np = 0
		for _, md in ipairs(r.cargoStation.models) do
			if md.id:find("lightpole") then np = np + 1 end
		end
		print((np == case[2] and "" or "FAIL ") .. "lightpoles roof " .. case[1], np, "want", case[2])
	end
	-- middle roof is symmetric for every length
	for len = 1, 8 do
		local mm = script.createTemplateFn({}, { jpst_length = len, jpst_tracks = 2, jpst_roof = 2 })
		local lo, hi
		for id in pairs(mm) do
			local k, _, _, seg = layout.decode(id)
			if k == layout.KIND.ROOF then
				lo = math.min(lo or seg, seg)
				hi = math.max(hi or seg, seg)
			end
		end
		local ps = -math.floor(len / 2)
		local pe = ps + len - 1
		local ok = lo ~= nil and (lo - ps) == (pe - hi)
		print((ok and "" or "FAIL ") .. "middle roof len " .. len, lo, hi, ps, pe)
	end
end

-- 19) rigid-frame viaduct: the base station leaves the deck floating; the 高架下 skins draw columns and
-- beams, each box being two crossed pier pieces (the piece only has its +-X faces)
print("== viaduct frames ==")
do
	local function pieces(r)
		local out = {}
		for _, md in ipairs(r.cargoStation.models) do if md.id:find("c_pillar_small") then table.insert(out, md.transf) end end
		return out
	end
	local base = { jpst_length = 1, jpst_tracks = 2, jpst_level = 2, jpst_platformWidth = 2 }
	local r0 = build({ modulesByName = script.createTemplateFn({}, base) })
	print((#pieces(r0) == 0 and "" or "FAIL ") .. "elevated without 高架下 module floats", #pieces(r0))
	local ok = true
	for _, el in ipairs(r0.edgeLists or {}) do
		if el.edgeTypeName and el.edgeTypeName ~= "jpst_station::/infrastructure/bridge/jpst_viaduct.bridge" then ok = false end
	end
	print((ok and "" or "FAIL ") .. "viaduct bridge type")

	-- 2 tracks + 10 m island = one 20 m block: column lines only on its two edges (inner boundaries are
	-- within 6 m of an edge) x 4 frames, plus 4 beams across the whole block
	base.jpst_passage = 3
	base.jpst_building = 3
	local ps = pieces(build({ modulesByName = script.createTemplateFn({}, base) }))
	local nCol, nBeam, bad = 0, 0, 0
	local colAxes, beamAxes = {}, {}
	for _, t in ipairs(ps) do
		local det = t[1] * (t[6] * t[11] - t[7] * t[10]) - t[5] * (t[2] * t[11] - t[3] * t[10]) + t[9] * (t[2] * t[7] - t[3] * t[6])
		local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
		for _, x in ipairs({ -1.056, 1.056 }) do for _, y in ipairs({ 0, 3 }) do for _, z in ipairs({ 0, 4 }) do
			for i = 1, 3 do
				local v = t[i] * x + t[4 + i] * y + t[8 + i] * z + t[12 + i]
				lo[i], hi[i] = math.min(lo[i], v), math.max(hi[i], v)
			end
		end end end
		local d = { hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3] }
		local function near(a, b) return math.abs(a - b) < 1e-3 end
		-- face normal = the piece's X axis
		local ax = math.abs(t[1]) > 1e-6 and "x" or math.abs(t[2]) > 1e-6 and "y" or "z"
		if det <= 0 then bad = bad + 1
		elseif near(d[1], 1) and near(d[2], 1) and near(d[3], 7.6) and near(lo[3], 0) then
			nCol = nCol + 1; colAxes[ax] = (colAxes[ax] or 0) + 1
		elseif near(d[1], 20) and near(d[2], 1) and near(d[3], 1) and near(hi[3], 7.6) then
			nBeam = nBeam + 1; beamAxes[ax] = (beamAxes[ax] or 0) + 1
		else bad = bad + 1 end
	end
	local good = bad == 0 and nCol == 16 and nBeam == 8 and colAxes.x == 8 and colAxes.y == 8 and beamAxes.y == 4 and beamAxes.z == 4
	print((good and "" or "FAIL ") .. "closed 1x1x7.6 columns and 20x1x1 beams", bad, nCol, nBeam)

	local g = build({ modulesByName = script.createTemplateFn({}, { jpst_length = 1, jpst_tracks = 2 }) })
	print((#pieces(g) == 0 and "" or "FAIL ") .. "ground no columns", #pieces(g))
end

-- 20) removing a platform / track module must offer its slot again
print("== re-add slots ==")
do
	for _, nt in ipairs({ 1, 2 }) do
		for _, pl in ipairs({ 1, 2 }) do
			local mods = script.createTemplateFn({}, { jpst_tracks = nt, jpst_platformLayout = pl, jpst_length = 4, jpst_building = 3 })
			local ids = {}
			for id in pairs(mods) do ids[#ids + 1] = id end
			table.sort(ids)
			for _, id in ipairs(ids) do
				local kind = layout.decode(id)
				if kind == K.PLATFORM or kind == K.TRACK then
					local m = {}
					for k, v in pairs(mods) do if k ~= id then m[k] = v end end
					local ok, r = pcall(build, { modulesByName = m })
					local found = false
					if ok then for _, s in ipairs(r.slots) do if s.id == id then found = true end end end
					if not ok or not found then print("FAIL re-add slot", nt, pl, select(2, layout.decode(id)), select(3, layout.decode(id)), select(4, layout.decode(id)), ok and "missing" or r) end
				end
			end
		end
	end
end

-- 21) roof with wire arms: beams from the roof edge over the neighbouring tracks
print("== roof arms ==")
do
	local ARM = layout.moduleName("jpst_roof_era_c_arm")
	for _, lvl in ipairs({ 1, 2 }) do
		local mods = script.createTemplateFn({}, { jpst_length = 1, jpst_tracks = 2, jpst_level = lvl, jpst_roof = 3, jpst_building = 3 })
		for id, name in pairs(mods) do if (layout.decode(id)) == K.ROOF then mods[id] = ARM end end
		local r = build({ modulesByName = mods })
		local zTop, nBeam, nStrut, bad = (lvl == 2) and 17 or 7, 0, 0, 0
		for _, md in ipairs(r.cargoStation.models) do
			if md.id:find("c_pillar_small") then
				local t = md.transf
				local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
				for _, x in ipairs({ -1.056, 1.056 }) do for _, y in ipairs({ 0, 3 }) do for _, z in ipairs({ 0, 4 }) do
					for i = 1, 3 do
						local v = t[i] * x + t[4 + i] * y + t[8 + i] * z + t[12 + i]
						lo[i], hi[i] = math.min(lo[i], v), math.max(hi[i], v)
					end
				end end end
				local det = t[1] * (t[6] * t[11] - t[7] * t[10]) - t[5] * (t[2] * t[11] - t[3] * t[10]) + t[9] * (t[2] * t[7] - t[3] * t[6])
				if det <= 0 then bad = bad + 1 end
				if math.abs(hi[3] - zTop) < 1e-3 and hi[1] - lo[1] > 2 then nBeam = nBeam + 1
				elseif math.abs((hi[1] - lo[1])) < 1 and hi[3] - lo[3] > 1 then nStrut = nStrut + 1 end
			end
		end
		print((nBeam == 12 and nStrut == 12 and bad == 0 and "" or "FAIL ") .. "roof arms level " .. lvl, nBeam, nStrut, bad)
	end
end

-- 22) cover roof: a high roof over the neighbouring tracks, shared between facing platforms
print("== roof cover ==")
do
	local COVER = layout.moduleName("jpst_roof_era_c_cover")
	for _, case in ipairs({ { layoutIdx = 1, pieces = 2, name = "island" }, { layoutIdx = 2, pieces = 2, name = "sides" },
			{ layoutIdx = 2, pieces = 1, name = "sides, only one is a cover", mixed = true } }) do
		local mods = script.createTemplateFn({}, { jpst_length = 1, jpst_tracks = 2, jpst_platformLayout = case.layoutIdx, jpst_level = 1, jpst_roof = 3, jpst_building = 3 })
		local first = true
		for id, name in pairs(mods) do if (layout.decode(id)) == K.ROOF then
			if not (case.mixed and not first) then mods[id] = COVER end
			first = false
		end end
		local r = build({ modulesByName = mods })
		local n, bad, maxX = 0, 0, 0
		for _, md in ipairs(r.cargoStation.models) do
			local t = md.transf
			if md.id:find("perron_5_roof.mdl", 1, true) and t[15] > 0.5 then
				n = n + 1
				maxX = math.max(maxX, math.abs(t[13]))
				local det = t[1] * (t[6] * t[11] - t[7] * t[10]) - t[5] * (t[2] * t[11] - t[3] * t[10]) + t[9] * (t[2] * t[7] - t[3] * t[6])
				if det <= 0 then bad = bad + 1 end
			end
		end
		print((n == case.pieces and bad == 0 and "" or "FAIL ") .. "roof cover " .. case.name, n, bad, maxX)
	end
end

-- 23) parallel bus bay: one-way lane along the station side, a stub at each end
print("== bus bay ==")
for lvl = 1, 2 do
	local m = script.createTemplateFn({}, { jpst_building = 2, jpst_length = 3, jpst_tracks = 2, jpst_level = lvl })
	local L0 = build({ modulesByName = m }).jpst.layout
	local s0 = math.huge for s in pairs(L0.buildingAt[MINUS]) do s0 = math.min(s0, s) end
	m[fcid(MINUS, 0, 2, 1, s0)] = layout.moduleName("jpst_busbay_basic_2x1")
	local r = build({ modulesByName = m })
	local cs = r.cargoStation
	local compAt, compOfLane = components(r)
	local fail, bus, stubs = {}, 0, 0
	local trainTerm = compOfLane(cs.station.terminals[1].personEdges[1][1] + 1)
	for _, t in ipairs(cs.station.terminals) do
		if t.transportModes[1] == "BUS" then
			bus = bus + 1
			if compOfLane(t.personEdges[1][1] + 1) ~= trainTerm then fail[#fail + 1] = "stop not reachable" end
		end
	end
	for _, el in ipairs(r.edgeLists) do if el.type == "STREET" then stubs = stubs + 1 end end
	local f
	for _, ff in pairs(r.jpst.layout.forecourts) do f = ff end
	local tf = layout.forecourtTransf(r.jpst.layout, f.side, f.seg, f.d, f.w, f.h)
	local a = compAt(wpt(tf, 40 - 8, 10, 0))
	local b = compAt(wpt(tf, -(40 - 8), 10, 0))
	if not a or a ~= b then fail[#fail + 1] = "bus lane not continuous" end
	if bus ~= 2 or stubs ~= 2 then fail[#fail + 1] = ("bus %d stubs %d"):format(bus, stubs) end
	print((#fail > 0 and "FAIL " or "") .. "bus bay lvl " .. lvl, bus, stubs, table.concat(fail, ", "))
end
-- bay continuation beyond the buildings
do
	local m = script.createTemplateFn({}, { jpst_building = 2, jpst_length = 3, jpst_tracks = 2, jpst_level = 1 })
	local L0 = build({ modulesByName = m }).jpst.layout
	local lo, hi = math.huge, -math.huge
	for s in pairs(L0.buildingAt[MINUS]) do lo, hi = math.min(lo, s), math.max(hi, s) end
	local BAY = layout.moduleName("jpst_busbay_basic_1x1")
	m[fcid(MINUS, 0, 1, 1, hi)] = BAY
	m[fcid(MINUS, 0, 1, 1, hi + 1)] = BAY
	m[fcid(MINUS, 0, 1, 1, hi + 2)] = BAY
	m[fcid(MINUS, 0, 1, 1, hi + 4)] = BAY -- gap: ignored
	m[fcid(MINUS, 0, 1, 1, lo - 1)] = PAVED(1, 1) -- not a bay: ignored
	local r = build({ modulesByName = m })
	local cs = r.cargoStation
	local compAt, compOfLane = components(r)
	local bus, stubs, fail = 0, 0, {}
	local trainTerm = compOfLane(cs.station.terminals[1].personEdges[1][1] + 1)
	for _, t in ipairs(cs.station.terminals) do
		if t.transportModes[1] == "BUS" then
			bus = bus + 1
			if compOfLane(t.personEdges[1][1] + 1) ~= trainTerm then fail[#fail + 1] = "stop not reachable" end
		end
	end
	for _, el in ipairs(r.edgeLists) do if el.type == "STREET" then stubs = stubs + 1 end end
	if bus ~= 3 or stubs ~= 4 or nIgnored(r) ~= 2 then fail[#fail + 1] = ("bus %d stubs %d ignored %d"):format(bus, stubs, nIgnored(r)) end
	local has = false
	for _, sl in ipairs(r.slots or {}) do if sl.id == fcid(MINUS, 0, 1, 1, hi + 3) then has = true end end
	print((#fail > 0 and "FAIL " or "") .. "bay continuation", bus, stubs, table.concat(fail, ", "))
end

-- under-viaduct shop skin: two units per long edge of every elevated block, inside the block
do
	local m = script.createTemplateFn({}, { jpst_length = 3, jpst_trackType = 2, jpst_catenary = 2, jpst_level = 2 })
	local function count(skin)
		m[layout.encode(K.UNDER, G, 0, 0)] = layout.moduleName(skin)
		local r = build({ modulesByName = m })
		local n, bad = 0, 0
		for _, mdl in ipairs(r.cargoStation.models) do
			if mdl.id:match("c_pillar_small_rep_m") then n = n + 1 end
			for i = 1, 16 do if mdl.transf[i] ~= mdl.transf[i] then bad = bad + 1 end end
		end
		return n, bad, nIgnored(r)
	end
	local a, _, _ = count("jpst_underviaduct_pillars")
	local b, bad, ign = count("jpst_underviaduct_shops")
	-- 2 edges x 2 ranges x 2 crossed pieces per elevated block
	print((b - a ~= 8 or bad > 0 or ign > 0) and "FAIL " or "", "under shops", b - a, bad, ign)
end

-- under-viaduct exits = false: no linkable street exit
do
	local m = script.createTemplateFn({}, { jpst_length = 3, jpst_trackType = 2, jpst_catenary = 2, jpst_level = 2 })
	local function linkables(modName)
		m[layout.encode(K.UNDER, G, 0, 0)] = modName
		local r = build({ modulesByName = m })
		local n = 0
		for _, ll in ipairs(r.cargoStation.laneLists) do if ll.linkable then n = n + 1 end end
		return n
	end
	local a, b = linkables(layout.moduleName("jpst_underviaduct_pillars")), linkables(layout.moduleName("jpst_underviaduct_closed"))
	print(((a - b == 1) and "" or "FAIL ") .. "under exits", a, b)
end
