local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

local config = {
	width = 10,
	stairsX = -2.5,
	models = {
		{ id = "::/stations/rail/era_c/perron_5_underpass.mdl", x = -2.5 },
		{ id = "::/stations/rail/era_c/perron_5.mdl", x = 2.5 },
	},
	endModel = "::/stations/rail/era_c/perron_10_end.mdl",
	borderModel = "::/stations/rail/era_c/perron_5_border.mdl",
}

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_platforms", filterCategories = { "passenger" }, order = 113 },
			},
		},
		description = {
			name = _("JPST_PLATFORM_ELEVATED_10_STAIRS_NAME"),
			description = _("JPST_PLATFORM_ELEVATED_DESC"),
			icon = "::/stations/rail/modular_station/addon_platform_passenger_stairs_era_c.tga",
			previewIcon = "::/stations/rail/modular_station/addon_platform_passenger_stairs_era_c_preview.tga",
		},
		type = "jpst_platform_elevated",
		metadata = {
			platform = true,
			passenger_platform = true,
			jpst_width = 10,
			jpst_level = "elevated",
			jpst_stairs = true,
			price = 260000,
			maintenanceCost = 43333,
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
