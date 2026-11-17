function data()
	return {
		configureLayerScript = {
			fileName = "::/gui/construction/construction_desc_layers.script@configureDefaultLayerFn",
			params = { heightmapContours = true },
		},
		namePrefix = _("{townName} Station"),
		subConstructionNamePrefix = "{constructionName}",
		description = {
			name = _("JPST_STATION_NAME"),
			description = _("JPST_STATION_DESC"),
			icon = "::/stations/rail/modular_station/station_era_c.tga",
			previewIcon = "::/stations/rail/modular_station/station_era_c_preview.tga",
		},
		availability = {
			yearFrom = 0,
			yearTo = 0,
		},
		order = 9000,
		soundConfig = {
			soundSet = { name = "::/stations/rail/sound/modular_rail_station.snd" },
			effects = {
				select = { "::/stations/rail/sound/selected_passengertrainstation2.wav" },
			},
			builderAudioRes = "::/gui/construction/sound/buildoze_construction_large.builder_audio",
		},
		constructionTemplates = {
			{
				type = "DYNAMIC",
				availability = {
					yearFrom = 0,
					yearTo = 0,
				},
				description = {
					name = _("JPST_STATION_NAME"),
					description = _("JPST_STATION_DESC"),
					icon = "::/stations/rail/modular_station/station_era_c.tga",
					previewIcon = "::/stations/rail/modular_station/station_era_c_preview.tga",
				},
				data = {
					params = {
						{
							key = "jpst_level",
							name = _("JPST_PARAM_LEVEL"),
							values = { _("JPST_LEVEL_GROUND"), _("JPST_LEVEL_ELEVATED") },
							defaultIndex = 1, -- ground
							displayMode = "Horizontal",
						},
					},
				},
				menuCategory = {
					categories = {
						{ category = "rail_buildings", order = 9000 },
					},
				},
				configureLayerScript = {
					fileName = "::/gui/construction/construction_desc_layers.script@configureDefaultLayerFn",
					params = { heightmapContours = true },
				},
				configureHudIconsScript = {
					fileName = "::/gui/construction/construction_desc_hud_icons.script@configureStationHudIconsFn",
					params = { cargo = false, rail = true },
				},
			},
		},
		createTemplateScript = {
			fileName = "/stations/jpst/jpst_station.script@createTemplateFn",
			params = {},
		},
		updateScript = {
			fileName = "/stations/jpst/jpst_station.script@updateFn",
			params = {},
		},
		upgradeScript = {
			fileName = "/stations/jpst/jpst_station.script@upgradeFn",
			params = {},
		},
		isAffectedByToolScript = {
			fileName = "/stations/jpst/jpst_station.script@isAffectedByToolFn",
			params = {},
		},
	}
end
