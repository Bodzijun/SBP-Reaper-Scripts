-- Module Loader for ReaMotion Pad
-- This file provides backward compatibility by loading all modules
-- and exposing them through a unified interface

local ModuleLoader = {}

-- Load a module by name
local function loadModule(name, script_path)
  local ok, mod = pcall(dofile, script_path .. 'modules/' .. name .. '.lua')
  if not ok then
    return nil
  end
  return mod
end

-- Load all modules
function ModuleLoader.LoadAll(script_path)
  local modules = {}
  
  -- Core modules (existing)
  modules.State = loadModule('State', script_path)
  modules.SegmentEngine = loadModule('SegmentEngine', script_path)
  modules.PadEngine = loadModule('PadEngine', script_path)
  modules.BindingRegistry = loadModule('BindingRegistry', script_path)
  modules.AutomationWriter = loadModule('AutomationWriter', script_path)
  
  -- New UI modules
  modules.UIHelpers = loadModule('UIHelpers', script_path)
  modules.PadUI = loadModule('PadUI', script_path)
  modules.MasterModulatorUI = loadModule('MasterModulatorUI', script_path)
  modules.IndependentModulatorUI = loadModule('IndependentModulatorUI', script_path)
  modules.LinkModuleUI = loadModule('LinkModuleUI', script_path)
  modules.ExternalUI = loadModule('ExternalUI', script_path)
  
  -- New functionality modules
  modules.LiveAutomation = loadModule('LiveAutomation', script_path)
  modules.Randomizer = loadModule('Randomizer', script_path)
  modules.PresetManager = loadModule('PresetManager', script_path)
  modules.JSFXSync = loadModule('JSFXSync', script_path)
  
  return modules
end

-- Validate that all required modules are loaded
function ModuleLoader.Validate(modules)
  local required = {'State', 'SegmentEngine', 'PadEngine', 'BindingRegistry', 'AutomationWriter'}
  for _, name in ipairs(required) do
    if not modules[name] then
      return false, name
    end
  end
  return true
end

return ModuleLoader
