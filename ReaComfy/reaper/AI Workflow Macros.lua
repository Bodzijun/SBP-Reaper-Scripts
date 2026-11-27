-- @noindex
-- Macro controls shown by AI Workflow Launcher.
-- Each entry targets: workflow filename -> ComfyUI node id -> input name.
-- Add your own workflows here; values are applied only to the job copy sent
-- to ComfyUI, so the saved workflow JSON remains unchanged.

return {
  ["voice_isolator_api.json"] = {
    {
      label = "Voice isolation amount",
      node = "2", input = "strength",
      min = 0.0, max = 1.0, default = 1.0, format = "%.2f",
      help = "1.0 = only the isolated voice. Lower values blend some of the original room and background back in."
    }
  },

  ["vocal_dereverb_wpe_api.json"] = {
    {
      label = "Dereverb amount",
      node = "2", input = "iterations",
      min = 1, max = 3, default = 2, integer = true,
      help = "Keep this at 1–3. Higher WPE passes can become extremely slow on long files."
    },
    {
      label = "Room tail length",
      node = "2", input = "taps",
      min = 3, max = 12, default = 8, integer = true,
      help = "Higher values target a longer reverb tail."
    }
  },

  ["clean_vocal_rnnoise_api.json"] = {
    {
      label = "Noise reduction",
      node = "2", input = "strength",
      min = 0.0, max = 1.0, default = 0.65, format = "%.2f",
      help = "Use lower values for a more natural vocal."
    }
  },

  ["clean_vocal_resemble_denoise_api.json"] = {
    {
      label = "Denoise strength",
      node = "2", input = "denoise_strength",
      min = 0.0, max = 1.0, default = 0.30, format = "%.2f",
      help = "Lower values preserve more of the original vocal texture."
    },
    {
      label = "Quality / speed",
      node = "2", input = "nfe",
      min = 8, max = 64, default = 32, integer = true,
      help = "Higher values are slower and can improve processing quality."
    }
  },

  ["voicefixer_dereverb_gentle_blend_api.json"] = {
    {
      label = "VoiceFixer amount (dB)",
      node = "3", input = "volume",
      min = -30, max = 0, default = -12, integer = true,
      help = "0 dB = the strongest VoiceFixer contribution. Start at -12 dB; use -18 to -24 dB if you hear artefacts."
    }
  },

  ["cinematic_dialogue_and_background_api.json"] = {
    {
      label = "Separation chunk length (s)",
      node = "2", input = "chunk_length",
      min = 6, max = 30, default = 20, integer = true,
      help = "Longer chunks can improve separation, but use more VRAM and take longer. Start at 20 s."
    },
    {
      label = "Chunk overlap (s)",
      node = "2", input = "chunk_overlap",
      min = 0.1, max = 3.0, default = 1.0, format = "%.1f",
      help = "Increase for rapidly changing ambience or if you hear seams between chunks."
    }
  },

  ["qwen_voice_clone_api.json"] = {
    {
      label = "Generation language",
      node = "3", input = "language", kind = "choice", default = "Russian",
      options = {"Russian", "English", "German", "French", "Spanish", "Italian", "Japanese", "Chinese", "Auto"},
      help = "Choose the language of Text to generate. Ukrainian is not available in this Qwen node; avoid Auto for reliable pronunciation."
    },
    {
      label = "Reference transcript",
      node = "3", input = "reference_text", kind = "string", multiline = true,
      default = "", required = true,
      help = "Enter the exact words spoken in the selected reference item."
    },
    {
      label = "Text to generate",
      node = "3", input = "text", kind = "string", multiline = true,
      default = "Введи тут текст, який має вимовити клонований голос.", required = true,
      help = "This is the new sentence that Qwen will speak using the reference voice."
    },
    { label = "Generation speed", node = "3", input = "speed", min = 0.5, max = 1.5, default = 1.0, format = "%.2f" },
    { label = "Voice variation", node = "3", input = "temperature", min = 0.2, max = 1.2, default = 0.6, format = "%.2f" },
    { label = "Guidance (CFG)", node = "3", input = "cfg_scale", min = 1.0, max = 2.5, default = 1.5, format = "%.2f" }
  },

  ["nemotron_reuse_api.json"] = {
    {
      label = "Enhancement amount",
      node = "2", input = "strength",
      min = 0.0, max = 1.0, default = 1.0, format = "%.2f",
      help = "1.0 = fully cleaned dialogue. Lower values blend some of the original back in."
    },
    {
      label = "Bandwidth extension",
      node = "2", input = "bandwidth_extension", kind = "choice", default = "off",
      options = {"off", "32000", "44100", "48000"},
      help = "For phone, Zoom or 16 kHz recordings: the model regenerates the missing highs at this rate."
    },
    {
      label = "Chunk length (s)",
      node = "2", input = "chunk_seconds",
      min = 0, max = 30, default = 5, format = "%.1f",
      help = "NVIDIA's long-file recipe uses 5 s. 0 = whole file at once (more VRAM)."
    }
  },

  ["zonos3_tts_api.json"] = {
    {
      label = "Text to speak",
      node = "2", input = "text", kind = "string", multiline = true,
      default = "Привіт! Це тест голосу ZONOS3.", required = true,
      help = "Each line is generated separately and joined. The selected item is the voice to clone (5-30 s of clean speech). The first run installs ZONOS3 automatically and can take 10-30 minutes."
    },
    {
      label = "Language",
      node = "2", input = "language", kind = "choice", default = "uk",
      options = {"uk", "en_us", "en_gb", "ru", "pl", "cs", "sk", "bg", "ro", "hu", "de", "fr_fr", "es", "it", "pt_br", "nl", "da", "no", "sv", "fi", "el", "tr", "he", "ar", "ka", "hi", "bn", "gu", "kn", "ml", "mr", "or", "pa", "ta", "te", "ur", "id", "ms", "tl", "th", "vi", "ja", "ko", "cmn"},
      help = "uk = Ukrainian, ru = Russian, en_us / en_gb = English..."
    },
    {
      label = "Emotion",
      node = "2", input = "emotion", kind = "choice", default = "none",
      options = {"none", "angry", "happy", "sad", "calm", "scared", "confused"}
    },
    { label = "Emotion strength", node = "2", input = "emotion_strength", min = 0.0, max = 2.0, default = 1.0, format = "%.2f",
      help = "1.0 = Zyphra's recommended dose. Above ~1.5 the voice can drift or break." },
    { label = "Pace (slower <-> faster)", node = "2", input = "pace", min = -2.0, max = 2.0, default = 0.0, format = "%.1f" },
    { label = "Projection (whisper <-> loud)", node = "2", input = "projection", min = -1.5, max = 2.0, default = 0.0, format = "%.1f" },
    { label = "Mood: negative <-> positive", node = "2", input = "valence", min = -4.0, max = 4.0, default = 0.0, format = "%.1f" },
    { label = "Mood: calm <-> excited", node = "2", input = "arousal", min = -4.0, max = 4.0, default = 0.0, format = "%.1f" },
    { label = "Read <-> chatty", node = "2", input = "chatty", min = -4.0, max = 4.0, default = 0.0, format = "%.1f" },
    { label = "Flat <-> lively", node = "2", input = "liveliness", min = -8.0, max = 8.0, default = 0.0, format = "%.1f" },
    {
      label = "Accent",
      node = "2", input = "accent", kind = "choice", default = "none",
      options = {"none", "american", "british", "scottish", "irish", "welsh", "australian", "indian english", "hindi", "spanish", "french", "portuguese", "german", "vietnamese", "polish", "mandarin"},
      help = "Accent directions work best on English text; strong doses change the voice identity."
    },
    { label = "Accent strength", node = "2", input = "accent_strength", min = 0.0, max = 2.0, default = 1.0, format = "%.2f" },
    {
      label = "Character preset",
      node = "2", input = "preset", kind = "choice", default = "none",
      options = {"none", "BBC newsreader", "Elderly Scottish narrator", "Gravelly old man", "Chatty podcaster", "Late-night radio", "Phone call"}
    },
    { label = "Seed (0 = random)", node = "2", input = "seed", min = 0, max = 999999, default = 0, integer = true,
      help = "Keep a seed to regenerate the same take." },
    { label = "Pause between lines (ms)", node = "2", input = "gap_ms", min = 0, max = 2000, default = 350, integer = true }
  },

  ["zonos3_speech_edit_api.json"] = {
    -- Speech edits need exactly the selected item, so this preset always glues it.
    input_mode = "glue",
    {
      label = "Corrected text (whole clip)",
      node = "2", input = "corrected_text", kind = "string", multiline = true, default = "", required = true,
      help = "What the WHOLE selected item should say after the fix. Keep items short: one or two sentences."
    },
    {
      label = "Original text (as recorded)",
      node = "2", input = "original_text", kind = "string", multiline = true, default = "",
      help = "What the item says now, slip included. The words that differ are found and regenerated automatically. Leave empty only when you use the REAPER time selection."
    },
    {
      label = "Language",
      node = "2", input = "language", kind = "choice", default = "uk",
      options = {"uk", "en_us", "en_gb", "ru", "pl", "cs", "sk", "bg", "ro", "hu", "de", "fr_fr", "es", "it", "pt_br", "nl", "da", "no", "sv", "fi", "el", "tr", "he", "ar", "ka", "hi", "bn", "gu", "kn", "ml", "mr", "or", "pa", "ta", "te", "ur", "id", "ms", "tl", "th", "vi", "ja", "ko", "cmn"}
    },
    {
      label = "Part to regenerate",
      node = "2", input = "edit_start", time_selection = "edit_end", kind = "choice", default = "found from the texts",
      options = {"found from the texts", "REAPER time selection"},
      help = "REAPER time selection: only the part of the item inside the time selection is regenerated (set it around the slip)."
    },
    {
      label = "Unchanged words",
      node = "2", input = "keep_original_audio", kind = "choice", default = "original recording",
      options = {"original recording", "re-decoded by ZONOS3"},
      values = {["original recording"] = true, ["re-decoded by ZONOS3"] = false},
      help = "original recording: only the fixed words are new; the rest is your recording, crossfaded and level-matched. re-decoded: the whole clip comes from ZONOS3's codec (timbre and intonation of every word shift slightly)."
    },
    { label = "Seed (0 = random)", node = "2", input = "seed", min = 0, max = 999999, default = 0, integer = true,
      help = "Change it for another take of the same fix." },
    { label = "Variation", node = "2", input = "temperature", min = 0.3, max = 1.2, default = 0.75, format = "%.2f" }
  },


  ["eq_match_api.json"] = {
    note = 'First select the reference item and press "Send reference audio", then select the item to process and run this preset. The reference is the sound to match (e.g. the main mic).',
    { label = "Match amount", node = "2", input = "match_strength", min = 0.0, max = 1.0, default = 0.65, format = "%.2f",
      help = "How far the tone moves toward the reference. 1.0 = full match." },
    { label = "Max EQ move (dB)", node = "2", input = "max_correction_db", min = 0.5, max = 18.0, default = 6.0, format = "%.1f",
      help = "The largest boost or cut at any frequency." },
    { label = "Smoothness", node = "2", input = "smoothing_bins", min = 3, max = 127, default = 9, integer = true,
      help = "Higher = broader, gentler EQ curve; lower = more detailed match." },
    { label = "Low limit (Hz)", node = "2", input = "low_frequency_hz", min = 0, max = 1000, default = 80, format = "%.0f",
      help = "Frequencies below this are left alone." },
    { label = "High limit (Hz)", node = "2", input = "high_frequency_hz", min = 1000, max = 24000, default = 16000, format = "%.0f",
      help = "Frequencies above this are left alone." },
    { label = "Output ceiling (dB)", node = "2", input = "output_ceiling_db", min = -6.0, max = -0.1, default = -1.0, format = "%.1f" }
  },

  ["dynamic_eq_match_api.json"] = {
    note = 'First select the reference item and press "Send reference audio", then select the item to process and run this preset. Follows tone changes over time (mic distance, head turns in interviews).',
    { label = "Match amount", node = "2", input = "match_strength", min = 0.0, max = 1.0, default = 0.45, format = "%.2f" },
    { label = "Max EQ move (dB)", node = "2", input = "max_correction_db", min = 0.5, max = 12.0, default = 3.0, format = "%.1f" },
    { label = "Smoothness", node = "2", input = "smoothing_bins", min = 3, max = 127, default = 21, integer = true,
      help = "Higher = broader, gentler EQ curve." },
    { label = "Reaction speed", node = "2", input = "temporal_smoothing", min = 0.0, max = 0.99, default = 0.88, format = "%.2f",
      help = "Higher = slower, smoother changes over time; lower = follows quick changes." },
    { label = "Voice gate (dB)", node = "2", input = "voice_gate_db", min = -80, max = -6, default = -35, format = "%.0f",
      help = "Quieter parts (pauses, noise) do not steer the EQ." },
    { label = "Low limit (Hz)", node = "2", input = "low_frequency_hz", min = 0, max = 1000, default = 80, format = "%.0f" },
    { label = "High limit (Hz)", node = "2", input = "high_frequency_hz", min = 1000, max = 24000, default = 16000, format = "%.0f" },
    { label = "Output ceiling (dB)", node = "2", input = "output_ceiling_db", min = -6.0, max = -0.1, default = -1.0, format = "%.1f" }
  },

  ["voice_leveler_api.json"] = {
    { label = "Target level (dB)", node = "2", input = "target_level_db", min = -36.0, max = -10.0, default = -20.0, format = "%.1f",
      help = "The speech level the leveler aims for." },
    { label = "Voice gate (dB)", node = "2", input = "voice_gate_db", min = -80, max = -12, default = -45, format = "%.0f",
      help = "Parts quieter than this (pauses, room) are not lifted." },
    { label = "Max boost (dB)", node = "2", input = "max_gain_db", min = 0.0, max = 18.0, default = 6.0, format = "%.1f" },
    { label = "Max cut (dB)", node = "2", input = "max_cut_db", min = 0.0, max = 18.0, default = 6.0, format = "%.1f" },
    { label = "Analysis window (ms)", node = "2", input = "window_ms", min = 80, max = 1000, default = 300, format = "%.0f" },
    { label = "Attack (ms)", node = "2", input = "attack_ms", min = 20, max = 1000, default = 120, format = "%.0f" },
    { label = "Release (ms)", node = "2", input = "release_ms", min = 100, max = 2000, default = 650, format = "%.0f" },
    { label = "Ceiling (dB)", node = "2", input = "ceiling_db", min = -6.0, max = -0.1, default = -1.0, format = "%.1f" }
  },

  ["clearvoice_enhance_api.json"] = {
    note = "ClearVoice installs itself on the first run (a few minutes).",
    { label = "Model", node = "2", input = "model", kind = "choice", default = "MossFormer2_SE_48K",
      options = {"MossFormer2_SE_48K", "FRCRN_SE_16K", "MossFormerGAN_SE_16K"},
      help = "MossFormer2_SE_48K keeps full bandwidth. The 16K models are for phone or low-rate speech." },
    { label = "Amount", node = "2", input = "strength", min = 0.0, max = 1.0, default = 1.0, format = "%.2f",
      help = "Lower values blend some of the original back in." }
  },

  ["clearvoice_super_resolution_api.json"] = {
    note = "Restores missing highs (48 kHz). Best after noise removal. ClearVoice installs itself on the first run.",
    { label = "Amount", node = "2", input = "strength", min = 0.0, max = 1.0, default = 1.0, format = "%.2f" },
    { label = "Keep original below (Hz)", node = "2", input = "preserve_low_hz", min = 0, max = 12000, default = 6000, integer = true,
      help = "The original is kept below this frequency; only the band above it is rebuilt." }
  },

  ["audio_inpaint_api.json"] = {
    note = "Removes clicks, mouth/saliva noise and short dropouts. Set Output to 'removed' to hear only what is taken out. Needs ComfyUI-ReaComfy 0.6.3.",
    { label = "Mode", node = "2", input = "mode", kind = "choice", default = "auto",
      options = {"auto", "de_click", "inpaint"},
      help = "de_click: clicks and mouth noise. inpaint: clicks and dropouts (silent gaps up to 50 ms). auto: all of them." },
    { label = "Click sensitivity", node = "2", input = "sensitivity", min = 2.0, max = 20.0, default = 8.0, format = "%.1f",
      help = "Lower = finds more and quieter clicks. 5-6 for heavy crackle." },
    { label = "Mouth-noise sensitivity", node = "2", input = "mouth_sensitivity", min = 2.0, max = 20.0, default = 8.0, format = "%.1f",
      help = "Lower = finds more mouth/saliva noise. Mouth noise is replaced only above 2 kHz, the voice stays." },
    { label = "Protect transients", node = "2", input = "speech_protect", min = 0.0, max = 1.0, default = 0.80, format = "%.2f",
      help = "Higher keeps more natural sharp sounds (plosives, drum hits). Lower for heavily damaged non-musical material." },
    { label = "Longest repair (ms)", node = "2", input = "max_repair_ms", min = 0.5, max = 15.0, default = 8.0, format = "%.1f" },
    { label = "Amount", node = "2", input = "strength", min = 0.0, max = 1.0, default = 1.0, format = "%.2f",
      help = "1.0 removes each found defect completely, 0.5 halves it." },
    { label = "Output", node = "2", input = "output", kind = "choice", default = "repaired",
      options = {"repaired", "removed"},
      help = "removed: only what the repair took out, to check that nothing useful is lost." }
  },

  ["room_match_api.json"] = {
    note = 'Puts a lavalier (close mic) into the room of an ambient/boom mic. First select the reference item and press "Send reference audio", then select the item to process and run this preset. The reference is the room mic of the same take. Results: the matched lav and the room impulse response.',
    { label = "Room amount", node = "2", input = "mix", min = 0.0, max = 1.0, default = 0.35, format = "%.2f",
      help = "How much of the matched room is mixed into the lav." },
    { label = "Reverb length (s)", node = "2", input = "ir_length_sec", min = 0.25, max = 5.0, default = 1.5, format = "%.2f" },
    { label = "Tail length scale", node = "2", input = "tail_rt60_scale", min = 0.5, max = 2.0, default = 1.0, format = "%.2f",
      help = "Above 1 = longer tail than measured." },
    { label = "Early reflections (dB)", node = "2", input = "early_gain_db", min = -24.0, max = 12.0, default = 0.0, format = "%.1f" },
    { label = "Late reverb (dB)", node = "2", input = "late_gain_db", min = -24.0, max = 12.0, default = 0.0, format = "%.1f" },
    { label = "Reverb high cut (Hz)", node = "2", input = "ir_high_cut_hz", min = 4000, max = 20000, default = 12000, integer = true },
    { label = "Stereo room", node = "2", input = "stereo_ir", kind = "choice", default = "mono",
      options = {"mono", "stereo"}, values = {mono = false, stereo = true},
      help = "stereo needs a stereo room mic." },
    { label = "Max mic offset (ms)", node = "2", input = "max_alignment_ms", min = 20, max = 1000, default = 250, format = "%.0f",
      help = "How far apart in time the two mics may be." }
  },

  ["lavasr_api.json"] = {
    note = "Rebuilds the highs of dull, low-rate or cloned speech to 48 kHz. LavaSR installs itself on the first run.",
    { label = "Amount", node = "2", input = "strength", min = 0.0, max = 1.0, default = 1.0, format = "%.2f" },
    { label = "Also remove noise", node = "2", input = "denoise", kind = "choice", default = "off",
      options = {"off", "on"}, values = {off = false, on = true} },
    { label = "Crossover (Hz, 0 = auto)", node = "2", input = "cutoff_hz", min = 0, max = 20000, default = 0, integer = true,
      help = "Below this the original is kept, above it the band is rebuilt. 0 = automatic." }
  },

}
