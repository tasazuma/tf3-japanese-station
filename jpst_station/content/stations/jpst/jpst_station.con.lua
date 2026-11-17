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
							key = "jpst_tracks",
							name = _("Tracks"),
							values = { "1", "2", "3", "4", "5", "6", "7", "8" },
							defaultIndex = 2, -- 2 tracks
							displayMode = "Horizontal",
						},
						{
							key = "jpst_platformLayout",
							name = _("JPST_PARAM_PLATFORM_LAYOUT"),
							values = { _("JPST_LAYOUT_ISLAND"), _("JPST_LAYOUT_SIDE") },
							defaultIndex = 1, -- island
							displayMode = "Horizontal",
						},
						{
							key = "jpst_platformWidth",
							name = _("JPST_PARAM_PLATFORM_WIDTH"),
							values = { "5m", "10m" },
							defaultIndex = 2, -- 10 m
							displayMode = "Horizontal",
						},
						{
							key = "jpst_length",
							name = _("JPST_PARAM_LENGTH"),
							values = { "40", "80", "120", "160", "200", "240", "280", "320" },
							defaultIndex = 3, -- 120 m
							displayMode = "Sparse",
							formatValueScript = {
								fileName = "::/scripts/construction/param_util.script@formatLengthValueFn",
								params = {
									values = { 40, 80, 120, 160, 200, 240, 280, 320 },
									forceSmallUnit = true,
								},
							},
						},
						{
							key = "jpst_trackType",
							name = _("Track Type"),
							tooltips = { _("Simple"), _("Standard"), _("High-Speed") },
							values = {
								"::/infrastructure/track/simple/simple.tga",
								"::/infrastructure/track/standard/standard.tga",
								"::/infrastructure/track/high_speed/high_speed.tga",
							},
							defaultIndex = 2, -- standard
							displayMode = "Horizontal",
							uiType = "IconButton",
						},
						{
							key = "jpst_catenary",
							name = _("JPST_PARAM_CATENARY"),
							values = { _("JPST_NO"), _("JPST_YES"), _("JPST_CATENARY_NOPOLE") },
							defaultIndex = 2, -- yes
							displayMode = "Horizontal",
						},
						{
							key = "jpst_roof",
							name = _("JPST_PARAM_ROOF"),
							values = { _("JPST_NO"), _("JPST_ROOF_MIDDLE"), _("JPST_ROOF_FULL") },
							defaultIndex = 2, -- middle
							displayMode = "Horizontal",
						},
						{
							key = "jpst_level",
							name = _("JPST_PARAM_LEVEL"),
							values = { _("JPST_LEVEL_GROUND"), _("JPST_LEVEL_ELEVATED") },
							defaultIndex = 1, -- ground
							displayMode = "Horizontal",
						},
						{
							key = "jpst_passage",
							name = _("JPST_PARAM_PASSAGE"),
							values = { _("JPST_PASSAGE_UNDERPASS"), _("JPST_PASSAGE_CONCOURSE"), _("JPST_PASSAGE_UNDERVIADUCT") },
							defaultIndex = 1, -- underpass
							displayMode = "Horizontal",
						},
						{
							key = "jpst_building",
							name = _("JPST_PARAM_BUILDING"),
							values = { _("JPST_BUILDING_PARAM_SMALL"), _("JPST_BUILDING_PARAM_LARGE"), _("JPST_BUILDING_PARAM_NONE") },
							defaultIndex = 1, -- small
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
