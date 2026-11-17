local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_platforms", filterCategories = { "passenger" }, order = 153 },
			},
		},
		description = {
			name = _("JPST_ROOF_ERA_C_ARM_NAME"),
			description = _("JPST_ROOF_ARM_DESC"),
			icon = "::/stations/rail/modular_station/platform_passenger_roof_era_c.tga",
			previewIcon = "::/stations/rail/modular_station/platform_passenger_roof_era_c_preview@2x.tga",
			attributes = {
				cost = { 40000, -1 },
				maintenanceCost = { 4000, -1 },
			},
		},
		type = "jpst_roof",
		metadata = {
			jpst_roof = true,
			price = 40000,
			maintenanceCost = 4000,
		},
		updateScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@roof.updateFn",
			params = {
				roofModel = "::/stations/rail/era_c/perron_5_roof.mdl",
				endModel = "::/stations/rail/era_c/perron_5_roof_end.mdl",
				arms = {
				z = 7.0,
				section = { 0.3, 0.5 },
				strut = { width = 0.3, z0 = 5.3 },
				ys = { -20, 0, 20 },
				models = {
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 0, -1 / 2.112, 0, 0, 1 / 3, 0, 0, 0, 0, 0, 1 / 4, 0, 0, 0, -1, 1 } },
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 0, 0, 1 / 2.112, 0, 1 / 3, 0, 0, 0, 0, 1 / 4, 0, 0, 0, -0.5, -0.5, 1 } },
				},
			},
			},
		},
		getModelsScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@roof.getModelsFn",
			params = {
				roofModel = "::/stations/rail/era_c/perron_5_roof.mdl",
				endModel = "::/stations/rail/era_c/perron_5_roof_end.mdl",
				arms = {
				z = 7.0,
				section = { 0.3, 0.5 },
				strut = { width = 0.3, z0 = 5.3 },
				ys = { -20, 0, 20 },
				models = {
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 0, -1 / 2.112, 0, 0, 1 / 3, 0, 0, 0, 0, 0, 1 / 4, 0, 0, 0, -1, 1 } },
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 0, 0, 1 / 2.112, 0, 1 / 3, 0, 0, 0, 0, 1 / 4, 0, 0, 0, -0.5, -0.5, 1 } },
				},
			},
			},
		},
		builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
	}
end
