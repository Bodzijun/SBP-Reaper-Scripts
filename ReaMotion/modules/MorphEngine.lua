---@diagnostic disable: undefined-field, need-check-nil, param-type-mismatch, assign-type-mismatch
local MorphEngine = {}

local r = reaper

local function clamp(v, min_v, max_v)
  if v == nil then return min_v or 0.0 end
  min_v = min_v or 0.0
  max_v = max_v or 1.0
  if v < min_v then return min_v end
  if v > max_v then return max_v end
  return v
end

-- Get selected items within time selection
function MorphEngine.GetSelectedItemsInTimeSelection()
  local items = {}
  local start_t, end_t = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  local is_time_sel = (end_t > start_t)

  local sel_count = r.CountSelectedMediaItems(0)
  for i = 0, sel_count - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    if item then
      local item_start = r.GetMediaItemInfo_Value(item, 'D_POSITION')
      local item_len = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
      local item_end = item_start + item_len

      if is_time_sel then
        if item_start < end_t and item_end > start_t then
          items[#items + 1] = item
        end
      else
        items[#items + 1] = item
      end
    end
  end

  return items
end

-- Create new track at index
function MorphEngine.CreateTrack(track_name, insert_at_index)
  r.InsertTrackAtIndex(insert_at_index or 0, false)
  local track = r.GetTrack(0, insert_at_index or 0)
  if track_name then
    r.GetSetMediaTrackInfo_String(track, 'P_NAME', track_name, true)
  end
  return track
end

-- Duplicate item to specific track with optional trimming
function MorphEngine.CopyItemToTrack(item, target_track, trim_left, trim_right)
  if not item or not target_track then return nil, 'Invalid item or track' end

  trim_left = trim_left or 0
  trim_right = trim_right or 0

  -- Get original item properties
  local item_len = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
  local snap_offset = r.GetMediaItemInfo_Value(item, 'D_SNAPOFFSET')
  local mute = r.GetMediaItemInfo_Value(item, 'B_MUTE')

  -- Get source take
  local source_take = r.GetActiveTake(item)
  if not source_take then return nil, 'No active take' end

  -- Get take source info - P_SOURCE can be empty for processed audio, that's OK
  local _, media_path = r.GetSetMediaItemTakeInfo_String(source_take, 'P_SOURCE', '', false)

  local take_start_offset = r.GetMediaItemTakeInfo_Value(source_take, 'D_STARTOFFS')
  local playrate = r.GetMediaItemTakeInfo_Value(source_take, 'D_PLAYRATE')
  local vol = r.GetMediaItemTakeInfo_Value(source_take, 'D_VOL')
  local pan = r.GetMediaItemTakeInfo_Value(source_take, 'D_PAN')

  -- Calculate new length and start offset after trimming
  local new_len = item_len - trim_left - trim_right
  if new_len <= 0 then return nil, 'Invalid length after trim: ' .. new_len end

  -- New start offset in the media file (accounts for trim)
  local new_start_offset = take_start_offset + (trim_left * playrate)

  -- Get item chunk from source - this is the most reliable method
  local ok, chunk = r.GetItemStateChunk(item, "", false)
  if not ok or not chunk or chunk == "" then
    return nil, 'Failed to get item chunk'
  end

  -- Create new item on target track
  local new_item = r.AddMediaItemToTrack(target_track)
  if not new_item then return nil, 'Failed to create item' end

  -- Set the chunk to copy all item data
  ok = r.SetItemStateChunk(new_item, chunk, false)
  if not ok then
    r.DeleteTrackMediaItem(target_track, new_item)
    return nil, 'Failed to set item chunk'
  end

  -- Get the take from the chunk-created item
  local new_take = r.GetActiveTake(new_item)
  if not new_take then
    r.DeleteTrackMediaItem(target_track, new_item)
    return nil, 'No take in chunk item'
  end

  -- Now adjust the take's start offset and item properties for trimming
  r.SetMediaItemTakeInfo_Value(new_take, 'D_STARTOFFS', new_start_offset)
  r.SetMediaItemInfo_Value(new_item, 'D_LENGTH', new_len)
  r.SetMediaItemInfo_Value(new_item, 'D_SNAPOFFSET', snap_offset + trim_left)
  r.SetMediaItemInfo_Value(new_item, 'B_MUTE', mute)
  r.SetMediaItemTakeInfo_Value(new_take, 'D_VOL', vol)
  r.SetMediaItemTakeInfo_Value(new_take, 'D_PAN', pan)
  r.SetMediaItemTakeInfo_Value(new_take, 'D_PLAYRATE', playrate)

  return new_item, nil
end

-- Add ReaMotion Pad JSFX to track (same as findOrCreateMixer in main script)
function MorphEngine.AddReaMotionPadMixer(track)
  if not track then return -1 end

  -- List of possible JSFX names/paths
  local ext_mixer_candidates = {
    'JS: sbp_ReaMotionPad_Mixer',
    'JS: Utility/sbp_ReaMotionPad_Mixer',
    'JS: IX/Mixer_8xS-1xS',
    'JS: Utility/8x Stereo to 1x Stereo Mixer',
    'JS: Utility/4x Stereo to 1x Stereo Mixer'
  }

  -- Search for existing mixer
  local fx_count = r.TrackFX_GetCount(track)
  for i = 0, fx_count - 1 do
    local _, fx_name = r.TrackFX_GetFXName(track, i)
    for _, candidate in ipairs(ext_mixer_candidates) do
      if fx_name == candidate then
        return i -- Found existing mixer
      end
    end
  end

  -- Create mixer if not found
  for _, candidate in ipairs(ext_mixer_candidates) do
    local fx_idx = r.TrackFX_AddByName(track, candidate, false, 0)
    if fx_idx >= 0 then
      return fx_idx
    end
  end

  return -1 -- Failed to add mixer
end

-- Setup child track routing to parent folder
-- Use PARENT SEND routing (not regular sends) to avoid duplicate audio in 1/2.
-- SOURCE channels stay 1/2; parent destination channels vary (1/2, 3/4, 5/6, 7/8).
function MorphEngine.SetupChildTrackRouting(child_track, folder_track, channel_pair)
  if not child_track or not folder_track then return false end

  -- DESTINATION channels vary by channel_pair:
  --   channel_pair 1 = parent ch 1/2 (0)
  --   channel_pair 2 = parent ch 3/4 (2)
  --   channel_pair 3 = parent ch 5/6 (4)
  --   channel_pair 4 = parent ch 7/8 (6)
  local dst_ch = (channel_pair - 1) * 2

  -- Ensure parent send is enabled and offset to needed destination channels.
  r.SetMediaTrackInfo_Value(child_track, 'I_MAINSEND', 1)
  r.SetMediaTrackInfo_Value(child_track, 'C_MAINSEND_OFFS', dst_ch)
  r.SetMediaTrackInfo_Value(child_track, 'C_MAINSEND_NCH', 2)

  -- Cleanup legacy explicit sends from child to folder (created by previous builds).
  local send_count = r.GetTrackNumSends(child_track, 0)
  for send_idx = send_count - 1, 0, -1 do
    local dest = r.GetTrackSendInfo_Value(child_track, 0, send_idx, 'P_DESTTRACK')
    if dest and dest == folder_track then
      r.RemoveTrackSend(child_track, 0, send_idx)
    end
  end

  return true
end

-- Enable envelope for JSFX parameter
function MorphEngine.EnableEnvelope(track, fx_index, param_index)
  if not track or fx_index < 0 then return nil end
  local env = r.GetFXEnvelope(track, fx_index, param_index, true)
  return env
end

-- Main morph function
function MorphEngine.MorphItems(options, state)
  local function doMorph()
    options = options or {}
    state = state or {}

    local folder_name = options.folder_name or 'Morph'
    local insert_at_index = options.insert_at_index or 0
    local copy_and_mute = options.copy_and_mute or false -- If true: copy items and mute originals; if false: move items
    local ext_pad = options.ext_pad                      -- External pad data for envelope writing

    -- Get selected items
    local items = MorphEngine.GetSelectedItemsInTimeSelection()
    if #items == 0 then
      return false, 'No items selected'
    end

    if #items > 4 then
      return false, 'Maximum 4 items supported'
    end

    -- Get time selection
    local start_t, end_t = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    local has_time_sel = (end_t > start_t)
    if not has_time_sel then
      start_t = r.GetCursorPosition()
      end_t = start_t + 1.0
    end

    -- Store item positions
    local item_positions = {}
    for i, item in ipairs(items) do
      item_positions[i] = r.GetMediaItemInfo_Value(item, 'D_POSITION')
    end

    -- Get the source track (where original items are)
    local source_track = r.GetMediaItemTrack(items[1])

    -- Check if Morph folder already exists
    local folder_track = nil
    local child_tracks = {}
    local existing_folder = false

    for i = 0, r.CountTracks(0) - 1 do
      local track = r.GetTrack(0, i)
      local _, track_name = r.GetSetMediaTrackInfo_String(track, 'P_NAME', '', false)
      if track_name == folder_name then
        -- Check if it's a folder (has children)
        local depth = r.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH')
        if depth == 1 then
          folder_track = track
          existing_folder = true
          break
        end
      end
    end

    if existing_folder and folder_track then
      -- Reuse existing folder - find or create Ext tracks
      local folder_track_num = r.GetMediaTrackInfo_Value(folder_track, 'IP_TRACKNUMBER')
      for i = 1, #items do
        local child_name = string.format('Ext %d', i)
        local child_track = nil
        -- Look for existing Ext track under this folder
        for j = 1, 4 do
          local track = r.GetTrack(0, folder_track_num - 1 + j)
          if track then
            local _, tname = r.GetSetMediaTrackInfo_String(track, 'P_NAME', '', false)
            if tname == child_name then
              child_track = track
              break
            end
          end
        end
        -- Create if doesn't exist (insert right after folder)
        if not child_track then
          child_track = MorphEngine.CreateTrack(child_name, folder_track_num)
        end
        if child_track then
          -- Set folder depth for child track
          -- Last child closes the folder
          if i == #items then
            r.SetMediaTrackInfo_Value(child_track, 'I_FOLDERDEPTH', -1)
          else
            r.SetMediaTrackInfo_Value(child_track, 'I_FOLDERDEPTH', 0)
          end
          child_tracks[#child_tracks + 1] = {
            track = child_track,
            item = nil,
            source_item = items[i],
            source_track = source_track,
            channel_pair = i,
            position = item_positions[i]
          }
        end
      end
      -- Ensure folder track has correct depth
      r.SetMediaTrackInfo_Value(folder_track, 'I_FOLDERDEPTH', 1)

      -- Ensure 8 channels for folder
      r.SetMediaTrackInfo_Value(folder_track, 'I_NCHAN', 8)
    else
      -- Create new folder and child tracks
      -- First create all tracks (folder + children)
      local all_tracks = {}
      for i = 1, #items + 1 do
        local track_name
        if i == 1 then
          track_name = folder_name                    -- First track becomes folder parent
        else
          track_name = string.format('Ext %d', i - 1) -- Ext 1, Ext 2, Ext 3, Ext 4
        end
        local tr = MorphEngine.CreateTrack(track_name, insert_at_index + i - 1)
        if tr then
          all_tracks[#all_tracks + 1] = tr
        end
      end

      if #all_tracks < 2 then
        return false, 'Failed to create tracks'
      end

      -- Get the folder track (first one)
      folder_track = all_tracks[1]

      -- Deselect all tracks first
      for i = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, i)
        r.SetTrackSelected(track, false)
      end

      -- Select all tracks for folder creation
      for _, tr in ipairs(all_tracks) do
        r.SetTrackSelected(tr, true)
      end

      -- Create folder from selected tracks
      -- Note: Action 40001 may not work reliably, so we'll set folder structure manually
      -- r.Main_OnCommand(40001, 0)  -- Group tracks (create folder)

      -- Manually set folder structure:
      -- folder_track: I_FOLDERDEPTH = 1 (folder parent)
      -- child tracks: I_FOLDERDEPTH = 0 (normal tracks inside folder)
      -- last child: I_FOLDERDEPTH = -1 (closes folder)

      r.SetMediaTrackInfo_Value(folder_track, 'I_FOLDERDEPTH', 1) -- Open folder

      -- Set folder to 8 channels
      r.SetMediaTrackInfo_Value(folder_track, 'I_NCHAN', 8)

      -- Get child tracks (after folder) and set their folder depth
      local folder_track_num = r.GetMediaTrackInfo_Value(folder_track, 'IP_TRACKNUMBER')
      for i = 1, #items do
        local child_track = r.GetTrack(0, folder_track_num - 1 + i)
        if child_track then
          -- Last child track closes the folder (I_FOLDERDEPTH = -1)
          if i == #items then
            r.SetMediaTrackInfo_Value(child_track, 'I_FOLDERDEPTH', -1)
          else
            r.SetMediaTrackInfo_Value(child_track, 'I_FOLDERDEPTH', 0)
          end
          child_tracks[#child_tracks + 1] = {
            track = child_track,
            item = nil,
            source_item = items[i],
            source_track = source_track,
            channel_pair = i,
            position = item_positions[i]
          }
        end
      end
    end

    if #child_tracks == 0 then
      return false, 'Failed to setup child tracks'
    end

    -- Deselect ALL tracks before moving/copying items
    for i = 0, r.CountTracks(0) - 1 do
      local track = r.GetTrack(0, i)
      r.SetTrackSelected(track, false)
    end

    -- Get time selection for trimming
    local ts_start, ts_end = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    local has_time_sel = (ts_end > ts_start)

    -- Move or copy items to their respective tracks
    for i, child_data in ipairs(child_tracks) do
      local source_item = child_data.source_item
      local target_track = child_data.track
      local final_item
      local err

      -- Get original item properties
      local item_start = r.GetMediaItemInfo_Value(source_item, 'D_POSITION')
      local item_len = r.GetMediaItemInfo_Value(source_item, 'D_LENGTH')
      local item_end = item_start + item_len
      local snap_offset = r.GetMediaItemInfo_Value(source_item, 'D_SNAPOFFSET')

      -- Calculate trim amounts if item extends beyond time selection
      local trim_left = 0
      local trim_right = 0
      if has_time_sel then
        -- Trim from left if item starts before time selection
        if item_start < ts_start then
          trim_left = ts_start - item_start
        end
        -- Trim from right if item ends after time selection
        if item_end > ts_end then
          trim_right = item_end - ts_end
        end
      end

      local target_pos = has_time_sel and ts_start or (child_data.position or item_start)

      if copy_and_mute then
        -- COPY mode: duplicate item to target track, mute original
        -- Pass trim values to CopyItemToTrack for proper source trimming
        final_item, err = MorphEngine.CopyItemToTrack(source_item, target_track, trim_left, trim_right)
        if final_item then
          -- Keep original position when there is no time selection.
          r.SetMediaItemInfo_Value(final_item, 'D_POSITION', target_pos)
          -- Mute the original item
          r.SetMediaItemInfo_Value(source_item, 'B_MUTE', 1)
        else
          r.ShowConsoleMsg('[MorphEngine] Copy failed: ' .. tostring(err) .. '\n')
        end
      else
        -- MOVE mode: move item to target track
        -- Apply trimming first if time selection exists
        if has_time_sel and (trim_left > 0 or trim_right > 0) then
          -- Trim the item by adjusting start, length, and take start offset
          local new_len = math.max(0.001, item_len - trim_left - trim_right)

          -- Adjust take start offset to skip trimmed portion
          local take = r.GetActiveTake(source_item)
          if take then
            local current_offset = r.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
            local playrate = r.GetMediaItemTakeInfo_Value(take, 'D_PLAYRATE')
            r.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', current_offset + (trim_left * playrate))
          end

          -- Position at time selection start
          r.SetMediaItemInfo_Value(source_item, 'D_POSITION', ts_start)
          r.SetMediaItemInfo_Value(source_item, 'D_LENGTH', new_len)
          r.SetMediaItemInfo_Value(source_item, 'D_SNAPOFFSET', snap_offset + trim_left)
        end

        -- Move item to target track using MoveMediaItemToTrack
        -- This function takes (item, track_pointer)
        r.MoveMediaItemToTrack(source_item, target_track)

        -- Keep original position when there is no time selection.
        r.SetMediaItemInfo_Value(source_item, 'D_POSITION', target_pos)

        final_item = source_item
      end

      -- Store the final item (moved or copied)
      child_data.item = final_item
    end

    -- Deselect ALL tracks
    for i = 0, r.CountTracks(0) - 1 do
      local track = r.GetTrack(0, i)
      r.SetTrackSelected(track, false)
    end

    -- Setup child track routing to folder parent
    for _, child_data in ipairs(child_tracks) do
      MorphEngine.SetupChildTrackRouting(child_data.track, folder_track, child_data.channel_pair)
    end

    -- Add JSFX to FOLDER TRACK (always added for morph functionality)
    local jsfx_idx = MorphEngine.AddReaMotionPadMixer(folder_track)

    -- Select folder track
    for i = 0, r.CountTracks(0) - 1 do
      local track = r.GetTrack(0, i)
      r.SetTrackSelected(track, false)
    end
    r.SetTrackSelected(folder_track, true)

    r.UpdateArrange()

    return true, {
      folder_track = folder_track,
      child_tracks = child_tracks,
      jsfx_index = jsfx_idx,
      item_count = #items
    }
  end -- end of doMorph

  -- Wrap in pcall for error handling
  -- doMorph returns: success, data (or false, error_message)
  local ok, ret_success, ret_data = pcall(doMorph)
  if not ok then
    -- pcall caught an exception
    return false, 'Error: ' .. tostring(ret_data)
  end
  -- doMorph completed without exception, check its return value
  if not ret_success then
    -- doMorph returned false, error_message
    return false, ret_data
  end
  -- doMorph returned true, data
  return true, ret_data
end

return MorphEngine
