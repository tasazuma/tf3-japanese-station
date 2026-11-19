local DECK = "jpst_station::/stations/jpst/perron/jpst_deck.mdl"

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

local PILLAR = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl"
local THICK, LAND = 0.8, 4

local function column(models, x, y, zTop)
	local z0 = math.min(0, zTop) - 4
	local sz = (zTop - z0) / 4
	models[#models + 1] = { id = PILLAR, transf = { 1 / 1.056, 0, 0, 0, 0, 2 / 3, 0, 0, 0, 0, sz, 0, x, y - 1, z0, 1 } }
	models[#models + 1] = { id = PILLAR, transf = { 0, 2 / 2.112, 0, 0, -2 / 3, 0, 0, 0, 0, 0, sz, 0, x + 1, y, z0, 1 } }
end

function data()
	return {
		updateFn = function(captureParams, params)
			local len = 10 + 5 * ((params.jpst_cc_len or 3) - 1)
			local rise = ((params.jpst_cc_rise or 31) - 31) / 2
			local width = 2 + (params.jpst_cc_width or 7)
			local pts = { { 0, 0, 0 }, { LAND, 0, 0 }, { len - LAND, 0, rise }, { len, 0, rise } }
			local nodes, models, cost = {}, {}, 20000
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				local t = { b[1] - a[1], 0, b[3] - a[3] }
				nodes[#nodes + 1] = { a, t, 3 }
				nodes[#nodes + 1] = { b, t, 3 }
				models[#models + 1] = { id = DECK, transf = beamTransf(a, b, width) }
				cost = cost + 500 * math.sqrt(t[1] * t[1] + t[3] * t[3])
			end
			for _, p in ipairs(pts) do
				if p[3] - THICK > -3 then column(models, p[1], 0, p[3] - THICK) end
			end
			local lane = {
				transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 },
				nodes = nodes,
				speedLimit = 20,
				transportModes = { "PERSON" },
				linkable = true,
			}
			return {
				models = {},
				subconstructions = { { models = models, laneLists = { lane } } },
				cost = cost,
				maintenanceCost = 100,
			}
		end,
	}
end
