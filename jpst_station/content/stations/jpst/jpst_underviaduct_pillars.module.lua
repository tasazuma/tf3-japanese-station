local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_building", filterCategories = { "passenger" }, order = 21 },
			},
		},
		description = {
			name = _("JPST_UNDERVIADUCT_PILLARS_NAME"),
			description = _("JPST_UNDERVIADUCT_PILLARS_DESC"),
			icon = "::/stations/rail/modular_station/stairs.tga",
			previewIcon = "::/stations/rail/modular_station/stairs_preview@2x.tga",
			attributes = {
				cost = { 80000, -1 },
				maintenanceCost = { 8000, -1 },
			},
		},
		type = "jpst_underviaduct",
		metadata = {
			jpst_underviaduct = true,
			moreCapacity = { passenger = 50 },
			emissionConfig = { noise = 1, pollution = 1 },
			catchmentPassenger = { radius = 200 },
			comfortFactor = 0.1,
			price = 80000,
			maintenanceCost = 8000,
		},
		updateScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@underviaduct.updateFn",
			params = {
				columns = { id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", rotZ = 90, scale = { 1 / 3, 1 / 3, 7.6 / 4 }, offset = { 0.5, 0 },
				ys = { -15, -5, 5, 15 }, minGap = 6 },
				exitModels = {
				{ id = "::/assets/stations/street/tickets_era_c_1.mdl", x = 3.5, y = 2.5, rotZ = -90 },
				{ id = "::/assets/stations/street/tickets_era_c_1.mdl", x = 3.5, y = 3.6, rotZ = -90 },
				{ id = "::/assets/stations/street/tickets_era_c_1.mdl", x = -3.5, y = 2.5, rotZ = 90 },
				{ id = "::/assets/stations/street/tickets_era_c_1.mdl", x = -3.5, y = 3.6, rotZ = 90 },
				{ id = "::/assets/stations/rail/era_c_trashcan.mdl", x = 5.5, y = 1.0, rotZ = 0 },
				{ id = "::/assets/stations/rail/era_c_double_chair.mdl", x = -10, y = 1.5, rotZ = 90 },
				{ id = "::/assets/stations/rail/era_c_double_chair.mdl", x = 10, y = 1.5, rotZ = 90 },
				},
				hallModels = {},
			},
		},
		getModelsScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@underviaduct.getModelsFn",
			params = {
				columns = { id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", rotZ = 90, scale = { 1 / 3, 1 / 3, 7.6 / 4 }, offset = { 0.5, 0 },
				ys = { -15, -5, 5, 15 }, minGap = 6 },
				exitModels = {
				{ id = "::/assets/stations/street/tickets_era_c_1.mdl", x = 3.5, y = 2.5, rotZ = -90 },
				{ id = "::/assets/stations/street/tickets_era_c_1.mdl", x = 3.5, y = 3.6, rotZ = -90 },
				{ id = "::/assets/stations/street/tickets_era_c_1.mdl", x = -3.5, y = 2.5, rotZ = 90 },
				{ id = "::/assets/stations/street/tickets_era_c_1.mdl", x = -3.5, y = 3.6, rotZ = 90 },
				{ id = "::/assets/stations/rail/era_c_trashcan.mdl", x = 5.5, y = 1.0, rotZ = 0 },
				{ id = "::/assets/stations/rail/era_c_double_chair.mdl", x = -10, y = 1.5, rotZ = 90 },
				{ id = "::/assets/stations/rail/era_c_double_chair.mdl", x = 10, y = 1.5, rotZ = 90 },
				},
				hallModels = {},
			},
		},
		builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
	}
end
