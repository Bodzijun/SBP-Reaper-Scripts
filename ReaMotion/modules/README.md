# ReaMotion Pad Modules

Ця папка містить модулі для скрипта ReaMotion Pad. Модулі розділені за функціональністю для покращення підтримки та читабельності коду.

## Core Modules (Існуючі)

| Module | Description |
|--------|-------------|
| `State.lua` | Серіалізація/десеріалізація стану, міграція даних, збереження/завантаження пресетів |
| `SegmentEngine.lua` | Розрахунок таймінгу для сегментації (Manual/Musical режими) |
| `PadEngine.lua` | Обчислення значень Pad, LFO, envelope для різних режимів |
| `BindingRegistry.lua` | Реєстр прив'язок FX та параметрів, пошук треків |
| `AutomationWriter.lua` | Запис automation точок в envelope |

## New UI Modules

| Module | Description |
|--------|-------------|
| `UIHelpers.lua` | Допоміжні функції для ImGui: теми, кольори, draw utilities |
| `PadUI.lua` | Візуалізація Pad (Vector/Points режими), segmentation controls |
| `MasterModulatorUI.lua` | UI для Master LFO + MSEG (compact layout) |
| `IndependentModulatorUI.lua` | UI для Independent Modulator з parameter binding |
| `LinkModuleUI.lua` | UI для Link Pad parameter morph (4-corner binding) |
| `ExternalUI.lua` | UI для External Pad sources та mixer channels |

## New Functionality Modules

| Module | Description |
|--------|-------------|
| `LiveAutomation.lua` | Live automation engine, оновлення в реальному часі |
| `Randomizer.lua` | Логіка рандомізації всіх параметрів |
| `PresetManager.lua` | Збереження/завантаження пресетів |
| `JSFXSync.lua` | Синхронізація з JSFX мікшером |
| `MorphEngine.lua` | Морфінг айтемів: перенесення на новий трек, роутинг, automation |
| `ModuleLoader.lua` | Завантажувач модулів з перевіркою |

## Структура модулів

Кожен модуль повертає таблицю з функціями:

```lua
local ModuleName = {}

function ModuleName.SomeFunction(param1, param2)
  -- implementation
end

return ModuleName
```

## Використання в головному скрипті

```lua
local ModuleLoader = loadModule('ModuleLoader')
local modules = ModuleLoader.LoadAll(script_path)

-- Або індивідуально:
local UIHelpers = loadModule('UIHelpers')
local PadUI = loadModule('PadUI')
```

## Переваги модуляризації

1. **Підтримка** - Легше знайти та виправити баги
2. **Тестування** - Можна тестувати модулі окремо
3. **Розширюваність** - Нові функції додаються як нові модулі
4. **Читабельність** - Кожний модуль має одну відповідальність
5. **Спільна робота** - Різні розробники можуть працювати на різними модулями

## Migration Notes

Головний скрипт `sbp_ReaMotionPad.lua` тепер імпортує всі модулі на початку:

```lua
local UIHelpers = loadModule('UIHelpers')
local PadUI = loadModule('PadUI')
local MasterModulatorUI = loadModule('MasterModulatorUI')
-- etc...
```

Старі функції замінені на виклики модулів:
- `pushTheme()` → `UIHelpers.PushTheme(ctx)`
- `randomizeState()` → `Randomizer.Randomize(app.state, markDirty)`
- `updateLiveAutomation()` → `LiveAutomation.Update(...)`
