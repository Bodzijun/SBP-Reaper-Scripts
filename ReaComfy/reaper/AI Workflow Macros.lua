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

}
