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
    { label = "Seed (0 = random)", node = "2", input = "seed", min = 0, max = 999999, default = 0, integer = true,
      help = "Change it for another take of the same fix." },
    { label = "Variation", node = "2", input = "temperature", min = 0.3, max = 1.2, default = 0.75, format = "%.2f" }
  },

}
