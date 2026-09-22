-- @description Create region from selected items
-- @author SBP & AI
-- @version 1.1
-- @about
--   Creates one region spanning from the earliest start to the latest end
--   of all selected media items. The region is named automatically using
--   the next available episode number: Ep1, Ep2, Ep3, etc.

local project = 0
local item_count = reaper.CountSelectedMediaItems(project)

if item_count == 0 then
    reaper.MB("Select one or more media items first.", "Create region", 0)
    return
end

local region_start = math.huge
local region_end = -math.huge

for index = 0, item_count - 1 do
    local item = reaper.GetSelectedMediaItem(project, index)
    local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

    region_start = math.min(region_start, position)
    region_end = math.max(region_end, position + length)
end

local highest_episode_number = 0
local _, marker_count, region_count = reaper.CountProjectMarkers(project)
local total_marker_count = marker_count + region_count

for index = 0, total_marker_count - 1 do
    local retval, is_region, _, _, name = reaper.EnumProjectMarkers3(project, index)

    if retval > 0 and is_region then
        local episode_number = name:match("^Ep(%d+)$")

        if episode_number then
            highest_episode_number = math.max(
                highest_episode_number,
                tonumber(episode_number)
            )
        end
    end
end

local region_name = "Ep" .. tostring(highest_episode_number + 1)

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

reaper.AddProjectMarker2(
    project,
    true,
    region_start,
    region_end,
    region_name,
    -1,
    0
)

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Create region " .. region_name .. " from selected items", -1)
