local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

local config = {
	width = 5,
	stairsX = 0,
	models = {
		{ id = "::/stations/rail/era_c/perron_5_underpass.mdl", x = 0 },
	},
	endModel = "::/stations/rail/era_c/perron_5_end.mdl",
	borderModel = "::/stations/rail/era_c/perron_5_border.mdl",
	signs = {
		{ id = "::/assets/stations/rail/c_lightpole.mdl", y = -10, z = 1.1 },
		{ id = "::/assets/stations/rail/c_lightpole.mdl", y = 0, z = 1.1 },
		{ id = "::/assets/stations/rail/c_lightpole.mdl", y = 10, z = 1.1 },
		{ id = "::/assets/stations/rail/era_c_station_name.mdl", y = -10, z = 2.5, label = "name" },
		{ id = "::/assets/stations/rail/era_c_station_name.mdl", y = 10, z = 2.5, label = "name" },
		{ id = "::/assets/stations/rail/era_c_perron_number.mdl", y = 0.235, z = 3.5, label = "number" },
	},
}

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_platforms", filterCategories = { "passenger" }, order = 11 },
			},
		},
		description = {
			name = _("JPST_PLATFORM_5_STAIRS_NAME"),
			description = _("JPST_PLATFORM_DESC"),
			icon = "::/stations/rail/modular_station/addon_platform_passenger_stairs_era_c.tga",
			previewIcon = "::/stations/rail/modular_station/addon_platform_passenger_stairs_era_c_preview.tga",
		},
		type = "jpst_platform",
		metadata = {
			platform = true,
			passenger_platform = true,
			jpst_width = 5,
			jpst_level = "ground",
			jpst_stairs = true,
			price = 90000,
			maintenanceCost = 15000,
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
