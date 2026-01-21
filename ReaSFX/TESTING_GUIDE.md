# ReaSFX v2.0 - Testing & Debugging Guide

## 🐛 Smart Loop Troubleshooting

### Проблема: Smart Loop не работает

**Симптомы:**
- При нажатии K в режиме Smart Loop ничего не происходит
- Нет items на timeline после release клавиши K
- Нет сообщений в status bar

### Диагностика (шаг за шагом):

#### Шаг 1: Проверьте Trigger Mode
1. Откройте ReaSFX
2. В панели "TRIGGER MODE" убедитесь, что выбран **"Smart Loop"** (не "One Shot" и не "Sequencer")
3. Status bar должен показывать текущий mode

#### Шаг 2: Проверьте наличие Events в Set
1. Выберите клавишу (например, 60)
2. Выберите set (например, S1)
3. Проверьте, что внизу есть события (E01, E02, etc.)
4. Если events нет:
   - Выделите media items в REAPER
   - Нажмите **CAPTURE (+)**
   - Должны появиться события

#### Шаг 3: Проверьте Smart Markers
Smart Loop **требует** наличия маркеров в take:

**Как добавить маркеры:**
1. Правый клик на media item → **Take markers**
2. Добавьте минимум 2 маркера:
   - **L** (Loop start) - например, в позиции 1.000
   - **E** (End) - например, в позиции 2.000
3. Опционально:
   - **S** (Start) - начало intro (по умолчанию 0)
   - **R** (Release) - конец release tail

**Пример правильной конфигурации:**
```
Audio:  |-----[S=0.5]---[L=1.0]=====[E=2.0]----[R=2.5]-----|
        ^     ^         ^           ^         ^           ^
        0s    Intro      Loop body   Loop end  Release    End
```

#### Шаг 4: Тест Basic Smart Loop
1. **Setup:**
   - Создайте audio item (любой)
   - Добавьте take markers: L=1.0, E=2.0
   - Capture item в set
   - Trigger mode = Smart Loop

2. **Test:**
   - Нажмите и **ДЕРЖИТЕ** клавишу K
   - Смотрите на status bar - должно появиться:
     ```
     "Smart Loop: Event captured, hold K and release for loop"
     ```
   - **Отпустите** K через 3-5 секунд
   - Items должны появиться на timeline

3. **Expected Result:**
   - На timeline появляются зацикленные items
   - Status bar показывает: `"SmartLoop: X.XXs, Y loops"`

#### Шаг 5: Проверьте Status Log
Status log (вверху слева) показывает все сообщения:

**Нормальная работа:**
```
"Smart Loop: Event captured, hold K and release for loop"
→ (после release K)
"BuildSmartLoop called: start=0.00, end=5.23"
"SmartLoop markers: S=0.000, L=1.000, E=2.000, R=nil"
"SmartLoop: intro=0.000, loop=1.000, duration=5.23"
"SmartLoop: 5.23s, 5 loops"
```

**Ошибки:**
```
"Smart Loop: No pending event (trigger first!)"
→ Вы не нажали K перед release

"Smart Loop: Event has no smart markers (add S/L/E/R markers)"
→ В item нет take markers L и E

"BuildSmartLoop: Missing L or E markers (L=nil, E=nil)"
→ Markers добавлены но неправильно названы (регистр важен!)

"BuildSmartLoop: Duration too short: 0.023s"
→ Вы отпустили K слишком быстро (< 0.1 сек)
```

---

## 🧪 Test Scenarios

### Test 1: Basic Smart Loop (No Markers)
**Purpose:** Проверить fallback на обычную вставку

**Steps:**
1. Capture item БЕЗ smart markers
2. Set trigger mode = Smart Loop
3. Hold K for 2 seconds, release
4. **Expected:** Item вставлен как обычный (не зациклен)
5. **Status:** "Smart Loop: Event has no smart markers"

### Test 2: Smart Loop with L/E Markers
**Purpose:** Базовый loop

**Steps:**
1. Add markers: L=1.0, E=2.0
2. Capture item
3. Hold K for 5 seconds, release
4. **Expected:**
   - 5 loops (5 секунд / 1 секунда loop)
   - Crossfade 0.05s на каждом loop
5. **Status:** "SmartLoop: 5.00s, 5 loops"

### Test 3: Smart Loop with S/L/E/R Markers (Full)
**Purpose:** Полный цикл с intro и release

**Steps:**
1. Add markers: S=0.5, L=1.0, E=2.0, R=2.5
2. Capture item
3. Hold K for 10 seconds, release
4. **Expected:**
   - Intro (0-0.5s) один раз
   - Loop (1.0-2.0s) ~9 раз
   - Release (2.0-2.5s) один раз
5. **Status:** "SmartLoop: 10.00s, 9 loops"

### Test 4: Multi-Layer Smart Loop
**Purpose:** Несколько слоев одновременно

**Steps:**
1. Capture 2 items (разные tracks) в S1
2. Capture другой item в S2
3. Shift+Click S2 (add to multi-layer)
4. Hold K for 3 seconds, release
5. **Expected:** Оба сета играют одновременно

### Test 5: Trigger Type = Key Up
**Purpose:** Trigger на release вместо press

**Steps:**
1. Set "Trigger Type" = "Start: Key Up"
2. Hold K
3. **Expected:** Ничего не происходит пока держите
4. Release K
5. **Expected:** Теперь smart loop активируется

---

## 📊 Debug Checklist

Если Smart Loop не работает, проверьте:

- [ ] ✅ ReaImGui установлен (иначе скрипт не запустится)
- [ ] ✅ JS_VKeys установлен (иначе клавиша K не работает)
- [ ] ✅ Trigger Mode = "Smart Loop" (не One Shot/Sequencer)
- [ ] ✅ Set содержит события (нажата CAPTURE)
- [ ] ✅ Events не muted (кнопка M не оранжевая)
- [ ] ✅ Probability > 0% (не 0%)
- [ ] ✅ Take markers существуют (L и E минимум)
- [ ] ✅ Marker names правильные (ЗАГЛАВНЫЕ: L, E, не l, e)
- [ ] ✅ Trigger Type соответствует вашему действию (Key Down)
- [ ] ✅ Держите K достаточно долго (> 0.1 сек)

---

## 🔍 Advanced Debugging

### Enable REAPER Console
1. REAPER → Actions → Show Action List
2. Search: "ReaScript console output"
3. Run action
4. Окно консоли покажет Lua errors

### Check ExtState (Preset System)
```lua
-- В REAPER Console:
reaper.ShowConsoleMsg(reaper.GetExtState("ReaSFX", "ProjectState"))
```

### Manual Test BuildSmartLoop
Если хотите протестировать функцию напрямую:

1. Откройте modules/Core.lua
2. Найдите строку 409: `function Core.BuildSmartLoop(...)`
3. Добавьте в конец функции:
   ```lua
   reaper.ShowConsoleMsg("BuildSmartLoop executed!\n")
   ```
4. Reload скрипт в REAPER

---

## 🐞 Known Issues & Workarounds

### Issue 1: K Key Not Responding
**Причина:** JS_VKeys не установлен или не работает

**Workaround:**
- Используйте кнопку **INSERT (K)** в GUI вместо клавиши K
- Install JS_ReaScriptAPI via ReaPack

### Issue 2: Items Not Appearing
**Причина:** Может быть несколько

**Debug:**
1. Check REAPER Console для Lua errors
2. Check status log для сообщений
3. Verify track существует (скрипт создаст если нет)
4. Try One Shot mode - если работает, проблема в Smart Loop logic

### Issue 3: Wrong Loop Length
**Причина:** Маркеры в неправильных позициях

**Fix:**
- Markers должны быть в take (item), не в timeline
- L < E (Loop start меньше Loop end)
- Positions в секундах от начала take

### Issue 4: No Crossfade
**Причина:** Crossfade = 0 или очень маленький

**Fix:**
- В Lua: `set.loop_crossfade = 0.100` (100ms)
- Reload скрипт
- *Note: GUI controls для crossfade в разработке (Phase 3)*

---

## 📝 Reporting Bugs

Если проблема не решена, соберите информацию:

**Include:**
1. REAPER version
2. ReaImGui version (Extensions → ReaPack → Browse packages)
3. JS_VKeys installed? (да/нет)
4. SWS installed? (да/нет)
5. Status log message (скопируйте текст)
6. REAPER Console errors (если есть)
7. Steps to reproduce
8. Screenshot (опционально)

**Where to report:**
- GitHub Issues: https://github.com/Bodzijun/SBP-Reaper-Scripts/issues
- Email: bodzik@gmail.com

---

## ✅ Success Indicators

Smart Loop работает правильно если:

1. ✅ Status log показывает messages на каждом шаге
2. ✅ Items появляются на timeline после release K
3. ✅ Loop section повторяется (не просто один shot)
4. ✅ Crossfade слышен между loops
5. ✅ Release tail играет в конце (если R marker exists)
6. ✅ Randomization применяется (volume/pitch variations)

---

**Last Updated:** 2026-01-21
**Version:** 2.0.0
