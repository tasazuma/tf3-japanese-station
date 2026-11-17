local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_platforms", filterCategories = { "passenger" }, order = 154 },
			},
		},
		description = {
			name = _("JPST_ROOF_ERA_C_COVER_NAME"),
			description = _("JPST_ROOF_COVER_DESC"),
			icon = "::/stations/rail/modular_station/platform_passenger_roof_era_c.tga",
			previewIcon = "::/stations/rail/modular_station/platform_passenger_roof_era_c_preview@2x.tga",
			attributes = {
				cost = { 60000, -1 },
				maintenanceCost = { 6000, -1 },
			},
		},
		type = "jpst_roof",
		metadata = {
			jpst_roof = true,
			jpst_roof_cover = true,
			price = 60000,
			maintenanceCost = 6000,
		},
		updateScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@roof.updateFn",
			params = {
				roofModel = "::/stations/rail/era_c/perron_5_roof.mdl",
				endModel = "::/stations/rail/era_c/perron_5_roof_end.mdl",
				cover = {
				z = 9.0,
				ys = { -10, 10 },
				column = 0.5,
			},
			},
		},
		getModelsScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@roof.getModelsFn",
			params = {
				roofModel = "::/stations/rail/era_c/perron_5_roof.mdl",
				endModel = "::/stations/rail/era_c/perron_5_roof_end.mdl",
				cover = {
				z = 9.0,
				ys = { -10, 10 },
				column = 0.5,
			},
			},
		},
		builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
	}
end
