local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

local config = {
	width = 5,
	stairsX = 0,
	models = {
		{ id = "jpst_station::/stations/jpst/perron/jpst_perron_5.mdl", x = 0 },
	},
	stairModels = {
		{ id = "jpst_station::/stations/jpst/perron/jpst_perron_5_underpass.mdl", x = 0 },
	},
	endModel = "::/stations/rail/era_c/perron_5_end.mdl",
	borderModel = "::/stations/rail/era_c/perron_5_border.mdl",
	signs = {
		-- kept between the roof pillars (every 10 m from y = -20) and clear of the stairwells (5 < |y| < 9.5)
		{ id = "::/assets/stations/rail/c_lightpole.mdl", y = -15, z = 1.1, roofless = true },
		{ id = "::/assets/stations/rail/c_lightpole.mdl", y = 15, z = 1.1, roofless = true },
		{ id = "::/assets/stations/rail/era_c_station_name.mdl", y = -15, z = 2.5, label = "name" },
		{ id = "::/assets/stations/rail/era_c_station_name.mdl", y = 15, z = 2.5, label = "name" },
		{ id = "::/assets/stations/rail/era_c_perron_number.mdl", y = -12.5, z = 3.5, label = "number" },
	},
}

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_platforms", filterCategories = { "passenger" }, order = 10 },
			},
		},
		description = {
			name = _("JPST_PLATFORM_5_NAME"),
			description = _("JPST_PLATFORM_DESC"),
			icon = "::/stations/rail/modular_station/platform_passenger_era_c.tga",
			previewIcon = "::/stations/rail/modular_station/platform_passenger_era_c_preview.tga",
		},
		type = "jpst_platform",
		metadata = {
			platform = true,
			passenger_platform = true,
			jpst_width = 5,
			jpst_level = "ground",
			price = 60000,
			maintenanceCost = 10000,
			emissionConfig = { noise = 1, pollution = 5 },
		},
		updateScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@platform.updateFn",
			params = config,
		},
		getModelsScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@platform.getModelsFn",
			params = config,
		},
		builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
	}
end
