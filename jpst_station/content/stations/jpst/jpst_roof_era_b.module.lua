local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_platforms", filterCategories = { "passenger" }, order = 151 },
			},
		},
		description = {
			name = _("JPST_ROOF_B_NAME"),
			description = _("JPST_ROOF_DESC"),
			icon = "::/stations/rail/modular_station/platform_passenger_roof_era_b.tga",
			previewIcon = "::/stations/rail/modular_station/platform_passenger_roof_era_b_preview@2x.tga",
			attributes = {
				cost = { 25000, -1 },
				maintenanceCost = { 2500, -1 },
			},
		},
		type = "jpst_roof",
		metadata = {
			jpst_roof = true,
			price = 25000,
			maintenanceCost = 2500,
		},
		updateScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@roof.updateFn",
			params = {
				roofModel = "::/stations/rail/era_b/perron_5_roof.mdl",
				endModel = "::/stations/rail/era_b/perron_5_roof_end.mdl",
			},
		},
		getModelsScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@roof.getModelsFn",
			params = {
				roofModel = "::/stations/rail/era_b/perron_5_roof.mdl",
				endModel = "::/stations/rail/era_b/perron_5_roof_end.mdl",
			},
		},
		builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
	}
end
