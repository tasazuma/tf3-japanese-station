local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_platforms", filterCategories = { "passenger" }, order = 160 },
			},
		},
		description = {
			name = _("JPST_SIGNS_STANDARD_NAME"),
			description = _("JPST_SIGNS_DESC"),
			icon = "::/stations/rail/modular_station/addon_platform_passenger_stairs_era_c.tga",
			previewIcon = "::/stations/rail/modular_station/addon_platform_passenger_stairs_era_c_preview.tga",
			attributes = {
				cost = { 20000, -1 },
				maintenanceCost = { 2000, -1 },
			},
		},
		type = "jpst_signs",
		metadata = {
			jpst_signs = true,
			price = 20000,
			maintenanceCost = 2000,
		},
		updateScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@signs.updateFn",
			params = {
				hangSign = "jpst_station::/stations/jpst/perron/jpst_sign_hang.mdl",
				trackSign = "jpst_station::/stations/jpst/perron/jpst_track_sign_hang.mdl",
			},
		},
		getModelsScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@signs.getModelsFn",
			params = {
				hangSign = "jpst_station::/stations/jpst/perron/jpst_sign_hang.mdl",
				trackSign = "jpst_station::/stations/jpst/perron/jpst_track_sign_hang.mdl",
			},
		},
		builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
	}
end
