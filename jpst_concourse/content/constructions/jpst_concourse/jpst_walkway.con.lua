local LENS, RISES, WIDTHS = {}, {}, {}
for w = 3, 10 do WIDTHS[#WIDTHS + 1] = tostring(w) .. "m" end
for l = 10, 80, 5 do LENS[#LENS + 1] = tostring(l) .. "m" end
for r = -30, 30 do RISES[#RISES + 1] = string.format("%.1fm", r / 2) end

function data()
	return {
		type = "ASSET_DEFAULT",
		description = { name = _("JPST_CC_NAME"), description = _("JPST_CC_DESC") },
		availability = { yearFrom = 0, yearTo = 0 },
		order = 9100,
		menuCategory = { categories = { { category = "rail_buildings", order = 9100 } } },
		params = {
			{ key = "jpst_cc_len", name = _("JPST_CC_LEN"), values = LENS, defaultIndex = 3, uiType = "Slider" },
			{ key = "jpst_cc_rise", name = _("JPST_CC_RISE"), values = RISES, defaultIndex = 31, uiType = "Slider" },
			{ key = "jpst_cc_width", name = _("JPST_CC_WIDTH"), values = WIDTHS, defaultIndex = 6, uiType = "Slider" },
		},
		updateScript = { fileName = "jpst_walkway.script@updateFn", params = {} },
	}
end
