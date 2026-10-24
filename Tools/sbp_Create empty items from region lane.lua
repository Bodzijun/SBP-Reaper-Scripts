-- @description Create empty items with subtitle notes from a region lane
-- @author SBP & AI
-- @version 1.0
-- @about
--   Select a destination track and a region in the source ruler lane.
--   Copies ALL regions in that lane to empty items with the same bounds,
--   text (item notes) and color. Original regions are preserved.
--   If the source is ambiguous, a menu lists all lanes containing regions.
--   Requires the native GetRegionOrMarker API; no extensions required.

local r = reaper
local project = 0
local title = "Регіони → айтеми субтитрів"
local function message(text) r.MB(text, title, 0) end

if not (r.GetRegionOrMarker and r.GetNumRegionsOrMarkers
    and r.GetRegionOrMarkerInfo_Value and r.GetSetRegionOrMarkerInfo_String) then
    message("Онови REAPER: потрібен API регіонів із підтримкою ruler lanes.")
    return
end
if r.CountSelectedTracks(project) ~= 1 then
    message("Вибери один трек для створення айтемів.")
    return
end
local track = r.GetSelectedTrack(project, 0)
local lanes, lane_ids, selected_lanes = {}, {}, {}
for i = 0, r.GetNumRegionsOrMarkers(project) - 1 do
    local obj = r.GetRegionOrMarker(project, i, "")
    if obj and r.GetRegionOrMarkerInfo_Value(project, obj, "B_ISREGION") == 1 then
        local lane = r.GetRegionOrMarkerInfo_Value(project, obj, "I_LANENUMBER")
        if not lanes[lane] then
            lanes[lane] = {}
            lane_ids[#lane_ids + 1] = lane
        end
        if r.GetRegionOrMarkerInfo_Value(project, obj, "B_UISEL") == 1 then
            selected_lanes[lane] = true
        end
        local _, text = r.GetSetRegionOrMarkerInfo_String(project, obj, "P_NAME", "", false)
        lanes[lane][#lanes[lane] + 1] = {
            start = r.GetRegionOrMarkerInfo_Value(project, obj, "D_STARTPOS"),
            finish = r.GetRegionOrMarkerInfo_Value(project, obj, "D_ENDPOS"),
            color = r.GetRegionOrMarkerInfo_Value(project, obj, "I_DISPLAYEDCOLOR"),
            text = text,
        }
    end
end
if #lane_ids == 0 then
    message("У проєкті немає регіонів.")
    return
end
table.sort(lane_ids)
local source_lane, selected_count = nil, 0
for lane in pairs(selected_lanes) do
    source_lane = lane
    selected_count = selected_count + 1
end
if selected_count ~= 1 then
    if #lane_ids == 1 then
        source_lane = lane_ids[1]
    else
        local entries = {}
        for _, lane in ipairs(lane_ids) do
            local _, name = r.GetSetProjectInfo_String(project, "RULER_LANE_NAME:" .. lane, "", false)
            -- Escape menu control characters in user-defined lane names.
            name = (name or ""):gsub("[|#!<>]", " "):gsub("[\r\n]", " ")
            entries[#entries + 1] = string.format("Lane %d — %s (%d)", lane, name, #lanes[lane])
        end
        gfx.init(title, 1, 1)
        gfx.x, gfx.y = 0, 0
        local choice = gfx.showmenu(table.concat(entries, "|"))
        gfx.quit()
        if choice == 0 then return end
        source_lane = lane_ids[choice]
    end
end

local regions = {}
for _, region in ipairs(lanes[source_lane]) do
    if region.finish > region.start then regions[#regions + 1] = region end
end
if #regions == 0 then
    message("У цій lane немає регіонів із додатною тривалістю.")
    return
end

local created = {}
r.Undo_BeginBlock2(project)
r.PreventUIRefresh(1)
local ok, err = xpcall(function()
    for _, region in ipairs(regions) do
        local item = r.AddMediaItemToTrack(track)
        if not item then error("Не вдалося створити айтем.") end
        created[#created + 1] = item
        r.SetMediaItemInfo_Value(item, "D_POSITION", region.start)
        r.SetMediaItemInfo_Value(item, "D_LENGTH", region.finish - region.start)
        r.SetMediaItemInfo_Value(item, "C_BEATATTACHMODE", 0)
        r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", region.color)
        if not r.GetSetMediaItemInfo_String(item, "P_NOTES", region.text, true) then
            error("Не вдалося записати нотатки айтема.")
        end
    end
end, debug.traceback)
if not ok then
    for _, item in ipairs(created) do r.DeleteTrackMediaItem(track, item) end
end
r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock2(project, "Create subtitle items from region lane", -1)
if not ok then message(err) end
