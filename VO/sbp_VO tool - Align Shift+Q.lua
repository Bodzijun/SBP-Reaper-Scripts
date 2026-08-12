-- @description VO Tool - Align selected items (companion hotkey action)
-- @author SBP & AI
-- @version 1.0
-- @about Assign Shift+Q to this action in REAPER. The open VO Tool consumes
--        the request and performs alignment using its current settings.

reaper.SetExtState(
    "SBP_VO_TOOL",
    "align_shift_q_request",
    tostring(reaper.time_precise()),
    false
)
