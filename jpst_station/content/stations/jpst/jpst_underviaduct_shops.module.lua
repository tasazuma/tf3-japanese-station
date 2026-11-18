local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_building", filterCategories = { "passenger" }, order = 22 },
			},
		},
		description = {
			name = _("JPST_UNDERVIADUCT_SHOPS_NAME"),
			description = _("JPST_UNDERVIADUCT_SHOPS_DESC"),
			icon = "::/stations/rail/modular_station/stairs.tga",
			previewIcon = "::/stations/rail/modular_station/stairs_preview@2x.tga",
			attributes = {
				cost = { 120000, -1 },
				maintenanceCost = { 12000, -1 },
			},
		},
		type = "jpst_underviaduct",
		metadata = {
			jpst_underviaduct = true,
			moreCapacity = { passenger = 50 },
			emissionConfig = { noise = 1, pollution = 1 },
			catchmentPassenger = { radius = 200 },
			comfortFactor = 0.1,
			price = 120000,
			maintenanceCost = 12000,
		},
		updateScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@underviaduct.updateFn",
			params = {
				columns = {
				models = {
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 1 / 2.112, 0, 0, 0, 0, 1 / 3, 0, 0, 0, 0, 7.6 / 4, 0, 0, -0.5, 0, 1 } },
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 0, 1 / 2.112, 0, 0, -1 / 3, 0, 0, 0, 0, 0, 7.6 / 4, 0, 0.5, 0, 0, 1 } },
				},
				ys = { -15, -5, 5, 15 }, minGap = 6,
			},
				beams = {
				models = {
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 0, -1 / 2.112, 0, 0, 1 / 3, 0, 0, 0, 0, 0, 1 / 4, 0, 0, 0, -1, 1 } },
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 0, 0, 1 / 2.112, 0, 1 / 3, 0, 0, 0, 0, 1 / 4, 0, 0, 0, -0.5, -0.5, 1 } },
				},
			},
				exitModels = {
				{ id = "::/assets/stations/street/tickets_era_c_1.mdl", x = 3.5, y = 2.5, rotZ = -90 },
				{ id = "::/assets/stations/street/tickets_era_c_1.mdl", x = 3.5, y = 3.6, rotZ = -90 },
				{ id = "::/assets/stations/street/tickets_era_c_1.mdl", x = -3.5, y = 2.5, rotZ = 90 },
				{ id = "::/assets/stations/street/tickets_era_c_1.mdl", x = -3.5, y = 3.6, rotZ = 90 },
				},
				hallModels = {},
				shops = {
				models = {
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 1 / 2.112, 0, 0, 0, 0, 1 / 3, 0, 0, 0, 0, 1 / 4, 0, 0.5, 0, 0, 1 } },
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 0, 1 / 2.112, 0, 0, -1 / 3, 0, 0, 0, 0, 0, 1 / 4, 0, 1, 0.5, 0, 1 } },
				},
				depth = 2.5, height = 3.5,
				ranges = { { -19.5, -8.5 }, { 8.5, 19.5 } },
			},
			},
		},
		getModelsScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@underviaduct.getModelsFn",
			params = {
				columns = {
				models = {
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 1 / 2.112, 0, 0, 0, 0, 1 / 3, 0, 0, 0, 0, 7.6 / 4, 0, 0, -0.5, 0, 1 } },
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 0, 1 / 2.112, 0, 0, -1 / 3, 0, 0, 0, 0, 0, 7.6 / 4, 0, 0.5, 0, 0, 1 } },
				},
				ys = { -15, -5, 5, 15 }, minGap = 6,
			},
				beams = {
				models = {
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 0, -1 / 2.112, 0, 0, 1 / 3, 0, 0, 0, 0, 0, 1 / 4, 0, 0, 0, -1, 1 } },
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 0, 0, 1 / 2.112, 0, 1 / 3, 0, 0, 0, 0, 1 / 4, 0, 0, 0, -0.5, -0.5, 1 } },
				},
			},
				exitModels = {
				{ id = "::/assets/stations/street/tickets_era_c_1.mdl", x = 3.5, y = 2.5, rotZ = -90 },
				{ id = "::/assets/stations/street/tickets_era_c_1.mdl", x = 3.5, y = 3.6, rotZ = -90 },
				{ id = "::/assets/stations/street/tickets_era_c_1.mdl", x = -3.5, y = 2.5, rotZ = 90 },
				{ id = "::/assets/stations/street/tickets_era_c_1.mdl", x = -3.5, y = 3.6, rotZ = 90 },
				},
				hallModels = {},
				shops = {
				models = {
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 1 / 2.112, 0, 0, 0, 0, 1 / 3, 0, 0, 0, 0, 1 / 4, 0, 0.5, 0, 0, 1 } },
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 0, 1 / 2.112, 0, 0, -1 / 3, 0, 0, 0, 0, 0, 1 / 4, 0, 1, 0.5, 0, 1 } },
				},
				depth = 2.5, height = 3.5,
				ranges = { { -19.5, -8.5 }, { 8.5, 19.5 } },
			},
			},
		},
		builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
	}
end
