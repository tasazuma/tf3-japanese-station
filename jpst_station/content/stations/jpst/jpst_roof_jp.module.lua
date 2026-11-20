local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_platforms", filterCategories = { "passenger" }, order = 155 },
			},
		},
		description = {
			name = _("JPST_ROOF_JP_NAME"),
			description = _("JPST_ROOF_DESC"),
			icon = "::/stations/rail/modular_station/platform_passenger_roof_era_c.tga",
			previewIcon = "::/stations/rail/modular_station/platform_passenger_roof_era_c_preview@2x.tga",
			attributes = {
				cost = { 35000, -1 },
				maintenanceCost = { 3500, -1 },
			},
		},
		type = "jpst_roof",
		metadata = {
			jpst_roof = true,
			price = 35000,
			maintenanceCost = 3500,
		},
		updateScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@roof.updateFn",
			params = {
				roofModel = "jpst_station::/stations/jpst/perron/jpst_roof_jp.mdl",
			},
		},
		getModelsScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@roof.getModelsFn",
			params = {
				roofModel = "jpst_station::/stations/jpst/perron/jpst_roof_jp.mdl",
			},
		},
		builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
	}
end
