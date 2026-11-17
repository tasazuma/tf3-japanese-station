local vec3 = require "::/scripts/vec3.tl"
local transf = require "::/scripts/mat4.tl"

function data()
	return {
		availability = { yearFrom = 0, yearTo = 0 },
		menuCategory = {
			categories = {
				{ category = "modules_building", filterCategories = { "passenger" }, order = 20 },
			},
		},
		description = {
			name = _("JPST_UNDERVIADUCT_VIADUCT_NAME"),
			description = _("JPST_UNDERVIADUCT_VIADUCT_DESC"),
			icon = "::/stations/rail/modular_station/stairs.tga",
			previewIcon = "::/stations/rail/modular_station/stairs_preview@2x.tga",
			attributes = {
				cost = { 40000, -1 },
				maintenanceCost = { 4000, -1 },
			},
		},
		type = "jpst_underviaduct",
		metadata = {
			jpst_underviaduct = true,
			moreCapacity = { passenger = 50 },
			emissionConfig = { noise = 1, pollution = 1 },
			catchmentPassenger = { radius = 200 },
			comfortFactor = 0.1,
			price = 40000,
			maintenanceCost = 4000,
		},
		updateScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@underviaduct.updateFn",
			params = {
				columns = {
				models = {
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 1 / 2.112, 0, 0, 0, 0, 1 / 3, 0, 0, 0, 0, 7.6 / 4, 0, 0, -0.5, 0, 1 } },
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 0, 1 / 2.112, 0, 0, -1 / 3, 0, 0, 0, 0, 0, 7.6 / 4, 0, 0.5, 0, 0, 1 } },
				},
				ys = { -15, -5, 5, 15 }, minGap = 6,
			},
				beams = {
				models = {
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 0, -1 / 2.112, 0, 0, 1 / 3, 0, 0, 0, 0, 0, 1 / 4, 0, 0, 0, -1, 1 } },
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 0, 0, 1 / 2.112, 0, 1 / 3, 0, 0, 0, 0, 1 / 4, 0, 0, 0, -0.5, -0.5, 1 } },
				},
			},
				exitModels = {

				},
				hallModels = {},
			},
		},
		getModelsScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@underviaduct.getModelsFn",
			params = {
				columns = {
				models = {
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 1 / 2.112, 0, 0, 0, 0, 1 / 3, 0, 0, 0, 0, 7.6 / 4, 0, 0, -0.5, 0, 1 } },
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 0, 1 / 2.112, 0, 0, -1 / 3, 0, 0, 0, 0, 0, 7.6 / 4, 0, 0.5, 0, 0, 1 } },
				},
				ys = { -15, -5, 5, 15 }, minGap = 6,
			},
				beams = {
				models = {
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 0, -1 / 2.112, 0, 0, 1 / 3, 0, 0, 0, 0, 0, 1 / 4, 0, 0, 0, -1, 1 } },
					{ id = "::/infrastructure/bridge/concrete/c_pillar_small_rep_m.mdl", transf = { 0, 0, 1 / 2.112, 0, 1 / 3, 0, 0, 0, 0, 1 / 4, 0, 0, 0, -0.5, -0.5, 1 } },
				},
			},
				exitModels = {

				},
				hallModels = {},
			},
		},
		builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
	}
end
