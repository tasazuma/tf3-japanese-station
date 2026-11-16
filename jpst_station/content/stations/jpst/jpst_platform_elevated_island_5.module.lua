local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

local config = {
	width = 5,
	stairsX = nil,
	models = {
		{ id = "::/stations/rail/era_c/perron_5.mdl", x = 0 },
	},
	endModel = "::/stations/rail/era_c/perron_5_end.mdl",
	borderModel = "::/stations/rail/era_c/perron_5_border.mdl",
}

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_platforms", filterCategories = { "passenger" }, order = 110 },
			},
		},
		description = {
			name = _("JPST_PLATFORM_ELEVATED_5_NAME"),
			description = _("JPST_PLATFORM_ELEVATED_DESC"),
			icon = "::/stations/rail/modular_station/platform_passenger_era_c.tga",
			previewIcon = "::/stations/rail/modular_station/platform_passenger_era_c_preview.tga",
		},
		type = "jpst_platform_elevated",
		metadata = {
			platform = true,
			passenger_platform = true,
			jpst_width = 5,
			jpst_level = "elevated",
			jpst_stairs = false,
			price = 120000,
			maintenanceCost = 20000,
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
