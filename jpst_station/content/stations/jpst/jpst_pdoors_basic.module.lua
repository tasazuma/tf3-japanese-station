local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_platforms", filterCategories = { "passenger" }, order = 150 },
			},
		},
		description = {
			name = _("JPST_PDOORS_BASIC_NAME"),
			description = _("JPST_PDOORS_DESC"),
			icon = "::/stations/rail/modular_station/addon_platform_passenger_stairs_era_c.tga",
			previewIcon = "::/stations/rail/modular_station/addon_platform_passenger_stairs_era_c_preview.tga",
			attributes = {
				cost = { 80000, -1 },
				maintenanceCost = { 8000, -1 },
			},
		},
		type = "jpst_pdoors",
		metadata = {
			jpst_pdoors = true,
			price = 80000,
			maintenanceCost = 8000,
		},
		updateScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@pdoors.updateFn",
			params = {},
		},
		getModelsScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@pdoors.getModelsFn",
			params = {},
		},
		builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
	}
end
