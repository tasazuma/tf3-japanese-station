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
			name = _("JPST_CONCOURSE_NAME"),
			description = _("JPST_CONCOURSE_DESC"),
			icon = "::/stations/rail/modular_station/stairs.tga",
			previewIcon = "::/stations/rail/modular_station/stairs_preview@2x.tga",
			attributes = {
				cost = { 150000, -1 },
				maintenanceCost = { 15000, -1 },
			},
		},
		type = "jpst_concourse",
		metadata = {
			jpst_concourse = true,
			moreCapacity = { passenger = 50 },
			emissionConfig = { noise = 1, pollution = 2 },
			catchmentPassenger = { radius = 200 },
			comfortFactor = 0.1,
			price = 150000,
			maintenanceCost = 15000,
		},
		updateScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@concourse.updateFn",
			params = {},
		},
		getModelsScript = {
			fileName = "jpst_station::/stations/jpst/jpst_modules.script@concourse.getModelsFn",
			params = {},
		},
		builderAudioRes = "::/gui/construction/sound/buildoze_module.builder_audio",
	}
end
