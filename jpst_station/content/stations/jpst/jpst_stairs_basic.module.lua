local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_platforms", filterCategories = { "passenger" }, order = 140 },
			},
		},
		description = {
			name = _("JPST_STAIRS_BASIC_NAME"),
			description = _("JPST_STAIRS_DESC"),
			icon = "::/stations/rail/modular_station/addon_platform_passenger_stairs_era_c.tga",
			previewIcon = "::/stations/rail/modular_station/addon_platform_passenger_stairs_era_c_preview.tga",
			attributes = {
				cost = { 30000, -1 },
				maintenanceCost = { 3000, -1 },
			},
		},
		type = "jpst_stairs",
		metadata = {
			jpst_stairs = true,
			price = 30000,
			maintenanceCost = 3000,
		},
		updateScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@stairs.updateFn",
			params = {},
		},
		getModelsScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@stairs.getModelsFn",
			params = {},
		},
		builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
	}
end
