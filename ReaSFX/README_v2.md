# ReaSFX v2.0 - Advanced Sampler for Film Post-Production

Мощный семплер для фоли и звуковых эффектов в REAPER, интегрированный в timeline с поддержкой Smart Loop, многослойных эффектов и системой пресетов.

---

## 🎯 Features

### Core Capabilities
- **30-Key Layout**: 30 клавиш (base note 36) для быстрого доступа
- **16 Sets per Key**: 16 независимых сетов на каждую клавишу
- **Multi-Layer Support**: Одновременная вставка нескольких слоев
- **Smart Markers System**: S/L/E/R маркеры для умных лупов
- **XY Performance Pad**: Живой контроль intensity/spread
- **Modulation Matrix**: 7 параметров randomization

### ✨ NEW in v2.0
- **Smart Loop Mode**: Полная реализация с intro/loop/release
- **Preset System**: Сохранение/загрузка состояния
- **Auto-Save**: Автоматическое сохранение каждые 30 секунд
- **Modular Architecture**: Улучшенная производительность и расширяемость

---

## 🚀 Quick Start

### Installation
1. Скопируйте папку `ReaSFX/` в ваш REAPER Scripts directory
2. В REAPER: Actions → Show Action List → Load ReaScript...
3. Выберите `ReaSFX_Full_v2.lua`

### Dependencies
**Required:**
- REAPER 6.0+
- ReaImGui 0.8+ (установите через ReaPack)

**Optional (for enhanced features):**
- SWS Extensions (для preview функциональности)
- JS_ReaScriptAPI (для глобальных hotkeys)

### First Run
1. Запустите скрипт
2. Выберите аудио items в проекте
3. Нажмите **CAPTURE (+)**
4. Триггерите с помощью **INSERT (K)** или клавиши `K`

---

## 📖 Usage Guide

### Basic Workflow

#### 1. Capture Samples
```
1. Выделите media items в проекте
2. Выберите клавишу (например, 60)
3. Выберите set (S1-S16)
4. Нажмите CAPTURE (+)
```

**Group Threshold**: Items в пределах этого времени группируются в один event.

#### 2. Configure Parameters

**Per-Set Randomization:**
- Vol: Вариация громкости (-12 до +12 dB)
- Pitch: Вариация pitch (-12 до +12 semitones)
- Pan: Вариация панорамы (-100 до +100%)
- Pos: Вариация позиции (до 0.2 сек)
- Offset: Вариация start offset (до 1.0 сек)
- Fade: Вариация fade in/out (до 0.5 сек)
- Len: Вариация длины (до 1.0 сек)

**XY Performance Pad:**
- X-axis: Intensity (0-200%) - множитель для randomization
- Y-axis: Spread (0-200%) - множитель для spread параметров

#### 3. Trigger Modes

**One Shot (Mode 0):**
- Вставляет один random event из set
- Применяет randomization
- Best для: Single hits, impacts

**Sequencer (Mode 1):**
- Автоматическая секвенция events
- 3 режима:
  - **Repeat First**: Повторяет первый event
  - **Random Pool**: Случайный выбор из pool
  - **Stitch Random**: Непрерывное склеивание random events

**Settings:**
- Count: Количество повторений
- Rate: Интервал между events (секунды)
- Len: Длина каждого event
- Fade: Fadeout на каждом event

**Smart Loop (Mode 2):** ⭐ NEW!
- Использует Smart Markers для умного looping
- 3 фазы: Intro (0→S), Loop (L→E), Release (E→R)
- Hold клавишу K для sustain, отпустите для release

#### 4. Smart Markers Setup

Для использования Smart Loop, добавьте маркеры в take:
1. Правый клик на item → Take markers
2. Добавьте маркеры:
   - **S** (Start): Начало loop section
   - **L** (Loop): Начало loop region
   - **E** (End): Конец loop region
   - **R** (Release): Конец release tail

**Example:**
```
Audio: |-----[S]---[L]=====[E]----[R]-----|
       Intro    Loop Body    Release
```

**Smart Loop Logic:**
1. Воспроизводит intro (0→S)
2. Циклит loop body (L→E) пока клавиша удерживается
3. Воспроизводит release (E→R) при отпускании

---

## 🎛️ Interface Guide

### Top Bar
- **Status Log**: Текущее действие/сообщение
- **INSERT (K)**: Manual trigger (эквивалент клавиши K)

### Keyboard Section
- 30 клавиш (36-65)
- Белые/черные клавиши как на фортепиано
- Оранжевый = active key
- Click для выбора

### Sets Tabs
- 16 buttons (S1-S16)
- **Click**: Select set
- **Shift+Click**: Add to multi-layer
- **Alt+Click**: Clear set
- Colors:
  - Orange: Main selected
  - Yellow: Multi-layer
  - Teal: Has data
  - Gray: Empty

### Event Slots
- Визуализация captured events
- Layers показаны как цветные полоски
- **(S)**: Smart markers present
- **(R)**: Release marker present
- **M button**: Mute event
- **P slider**: Probability (0-100%)
- **V slider**: Volume offset (-12 to +12 dB)
- **X button**: Delete event
- **Hover**: Preview audio (требует SWS)

### Main Controls Panel

**Column 1: Capture**
- CAPTURE (+): Capture selected items
- Gap Thrs: Grouping threshold
- Trigger Type: Key Down / Key Up
- Snap Offset: Align by snap offset
- Placement Mode:
  - **Rel Layers**: Tracks по относительной позиции
  - **Old FIPM**: Free Item Positioning (vertical)
  - **Fixed Lanes**: Fixed lanes mode

**Column 2: Trigger Mode**
- One Shot / Sequencer / Smart Loop
- Sequencer settings (if mode 1)

**Column 3: Modulation Matrix**
- Event-level (per set)
- Global-level (all sets)

**Column 4: XY Pad**
- Interactive performance control
- Crosshairs показывают текущую позицию

---

## 💾 Preset System

### Save/Load State
**Auto-Save**: Каждые 30 секунд автоматически сохраняет в ExtState

**Manual:**
- File → Save State: Сохранить текущее состояние
- File → Load State: Загрузить последнее состояние

**Что сохраняется:**
- Все keys/sets/events
- Все параметры randomization
- XY Pad positions
- Trigger modes
- Placement modes

### Export/Import Presets
**Export:**
1. File → Export Preset...
2. Выберите filename.rsfx
3. Preset сохранен в JSON format

**Import:**
1. File → Import Preset...
2. Выберите .rsfx файл
3. Preset загружен

**Use Cases:**
- Шаринг пресетов между проектами
- Backup критических настроек
- Collaboration с другими sound designers

---

## ⌨️ Hotkeys

| Key | Action |
|-----|--------|
| K | Trigger selected set |
| K (hold) | Smart Loop sustain |
| K (release) | Smart Loop release |
| Shift+Click Set | Add to multi-layer |
| Alt+Click Set | Clear set |

---

## 🔧 Advanced Features

### Multi-Layer Triggering
1. Выберите main set (например, S1)
2. Shift+Click другие sets (например, S2, S3)
3. Trigger будет играть все выбранные sets одновременно

**Use Case:** Layering multiple variations (close mic + room mic)

### Probability-Based Triggering
- Установите probability < 100% для random variation
- Event с 50% probability будет играть только в половине случаев
- Use для human-like randomness

### Volume Offset
- Per-event volume adjustment
- Полезно для balancing layers
- Не влияет на randomization

### Placement Modes

**Rel Layers (0):**
- Items размещаются на разных tracks
- Сохраняет относительную track позицию из capture
- Best для: Multitrack recordings

**Old FIPM (1):**
- Free Item Positioning (vertical lanes)
- Все items на одном track
- Best для: Simple playback

**Fixed Lanes (2):**
- Items в fixed lanes
- Similar to FIPM но с фиксированными позициями
- Best для: Organized viewing

---

## 🐛 Troubleshooting

### Script Won't Load
**Error: "Please install ReaImGui"**
- Solution: Install ReaImGui via ReaPack

**Error: "Module not found"**
- Check: modules/ folder exists
- Check: Core.lua, GUI.lua, Preset.lua present

### Smart Loop Not Working
**Check:**
1. Items have Smart Markers (S/L/E/R)?
2. Trigger Mode = Smart Loop (2)?
3. Hold K key during playback?

### Preview Not Working
- Install SWS Extensions
- Restart REAPER

### Auto-Save Not Working
- Check: File → Save State works manually?
- ExtState location: REAPER resource path

---

## 📊 Performance Tips

### Optimize Large Projects
- Use fewer events per set (< 20)
- Clear unused sets (Alt+Click)
- Avoid extreme randomization values

### Memory Management
- Export/clear old presets
- Don't capture extremely long items

---

## 🔜 Roadmap

### Phase 2: REAPER Integration
- [ ] Time Selection Auto-Fill
- [ ] Region/Marker integration
- [ ] FX Chain management
- [ ] Automation Envelopes

### Phase 3: Advanced Features
- [ ] Grid-synced sequencer
- [ ] XY Pad recording
- [ ] Smart grouping (track/color-aware)

### Phase 4: New Features
- [ ] Sample library browser
- [ ] MIDI control
- [ ] Batch region processing

---

## 💡 Tips & Tricks

### Foley Workflow
1. Record multiple takes of footsteps
2. Capture each take as separate event
3. Use Random Pool sequencer mode
4. Adjust probability for natural variation

### Layered Sound Design
1. Capture different mic positions to different sets
2. Use Multi-Layer triggering
3. Balance with Volume Offset
4. Add randomization for each layer separately

### Smart Loop for Ambiences
1. Record amb with clear start/loop/end
2. Add Smart Markers
3. Use Smart Loop mode
4. Hold K to sustain, release for natural tail

### Emergency Undo
- REAPER Undo works for all operations
- Ctrl+Z to undo last trigger/capture

---

## 📞 Support

**Issues:** [GitHub Issues](https://github.com/Bodzijun/SBP-Reaper-Scripts/issues)
**Email:** bodzik@gmail.com
**Donate:** PayPal - bodzik@gmail.com

---

## 📜 License

MIT License - Free to use and modify

## 🙏 Credits

**Author:** SBP
**AI Assistant:** Claude (Anthropic)
**Version:** 2.0.0
**Date:** 2026-01-21

**Inspired by:**
- KROTOS Studio Pro
- Community feedback
- Film post-production workflows

---

**Happy Sound Designing! 🎵**
