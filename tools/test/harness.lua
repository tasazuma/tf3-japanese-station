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
local moduleScript = loadData("/stations/jpst/jpst_modules.script")

local function moduleDesc(name)
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
