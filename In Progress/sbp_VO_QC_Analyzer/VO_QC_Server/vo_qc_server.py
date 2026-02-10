#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
VO QC Server - Speech-to-Text and Voice-Over Quality Control Analysis
Powered by OpenAI Whisper and Flask

Version: 2.0.0

Changelog:
  v1.0.0 - Initial release with basic transcription and matching
  v2.0.0 - Sentence-level analysis with auto language detection
         - Split text into sentences for granular comparison
         - Multi-language support (auto-detect)
         - Sentence alignment and status reporting
"""

import os
import sys
import json
import traceback
import unicodedata
from pathlib import Path
from flask import Flask, request, jsonify
import whisper
from difflib import SequenceMatcher, unified_diff
from fuzzywuzzy import fuzz
try:
    from Levenshtein import distance as levenshtein_distance
except ImportError:
    from levenshtein import distance as levenshtein_distance

# ============================================================
# CONFIG
# ============================================================

MODELS_DIR = Path(__file__).parent / "models"
PORT = 5000
DEBUG = False
DEFAULT_WHISPER_MODEL = "large-v3"  # Default: turbo, base, small, medium, large-v3
MAX_WORKERS = 4

# Create Flask app
app = Flask(__name__)
app.config['JSON_AS_ASCII'] = False

# Global state
whisper_model = None
current_model_name = None  # Track which model is currently loaded
job_store = {}

# ============================================================
# UTILITY FUNCTIONS
# ============================================================

def load_whisper_model(model_name=None):
    """Load Whisper model into memory (with dynamic model switching)"""
    global whisper_model, current_model_name
    
    if model_name is None:
        model_name = DEFAULT_WHISPER_MODEL
    
    # If same model already loaded, return
    if whisper_model is not None and current_model_name == model_name:
        return True
    
    # If different model needed, unload current one
    if whisper_model is not None and current_model_name != model_name:
        del whisper_model
        whisper_model = None
        current_model_name = None
        print(f"[INFO] Unloaded model: {current_model_name}")
    
    try:
        print(f"[INFO] Loading Whisper model: {model_name}")
        whisper_model = whisper.load_model(model_name)
        current_model_name = model_name
        print(f"[INFO] Model loaded successfully: {model_name}")
        return True
    except Exception as e:
        print(f"[ERROR] Failed to load Whisper model '{model_name}': {e}")
        traceback.print_exc()
        return False

def transcribe_audio(audio_path, language=None, terminology='', model=None):
    """Transcribe audio file using Whisper with optional language forcing and terminology guidance"""
    try:
        # Load requested model (or default if not specified)
        if not load_whisper_model(model):
            return None
        
        print(f"[INFO] Transcribing: {audio_path}")
        
        # Disable Triton kernels (they cause issues with CUDA timing)
        # Use simpler faster-whisper with pure CUDA
        import os
        os.environ['CUDA_LAUNCH_BLOCKING'] = '1'
        
        # If language is None, let Whisper auto-detect
        kwargs = {
            'word_timestamps': True,
            'fp16': True  # Enable GPU acceleration (fp16 for RTX cards)
        }
        
        # Add language constraint if specified
        if language and language.lower() != 'auto':
            kwargs['language'] = language
            print(f"[INFO] Using forced language: {language}")
        else:
            print(f"[INFO] Auto-detecting language")
        
        # Add terminology guidance if provided
        if terminology and terminology.strip():
            # Format terminology as comma-separated list for Whisper's initial_prompt
            terms = [t.strip() for t in terminology.split('\n') if t.strip()]
            if terms:
                initial_prompt = "Recognize these terms correctly: " + ", ".join(terms[:20])  # Limit to 20 terms
                kwargs['initial_prompt'] = initial_prompt
                print(f"[INFO] Using terminology guidance ({len(terms)} terms)")
        
        result = whisper_model.transcribe(audio_path, **kwargs)
        
        # Log detected language
        detected_lang = result.get('language', 'unknown')
        print(f"[INFO] Detected language: {detected_lang}")
        
        return result
    except Exception as e:
        print(f"[ERROR] Transcription failed: {e}")
        traceback.print_exc()
        return None

def normalize_text(text):
    """Normalize text for comparison: strip diacritics, normalize hyphens, collapse newlines, numbers, lower-case."""
    if not text:
        return ""
    
    # Normalize accents/diacritics
    text = unicodedata.normalize("NFKD", text)
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    
    # Normalize common hyphen variants
    text = text.replace("–", "-").replace("—", "-").replace("‑", "-")
    
    # CRITICAL: Convert word numbers to digits (один → 1, два → 2, etc.)
    # Russian/Ukrainian number words - BOTH cardinal and ordinal
    number_map = {
        # Cardinal numbers
        "нуль": "0", "нулю": "0", "ноль": "0",
        "один": "1", "одна": "1", "одного": "1", "одному": "1",
        "два": "2", "две": "2", "двум": "2",
        "три": "3", "трем": "3", "трём": "3",
        "четыре": "4", "четырем": "4",
        "пять": "5", "пяти": "5",
        "шесть": "6", "шести": "6",
        "семь": "7", "семи": "7",
        "восемь": "8", "восьми": "8",
        "девять": "9", "девяти": "9",
        "десять": "10", "десяти": "10",
        "двадцать": "20", "двадцати": "20",
        "тридцать": "30", "сорок": "40", "пятьдесят": "50",
        "сто": "100", "тысяча": "1000",
        # Ordinal numbers (порядковые) - CRITICAL FIX
        "первый": "1", "первая": "1", "первого": "1", "первому": "1", "первом": "1",
        "второй": "2", "вторая": "2", "второго": "2", "второму": "2", "втором": "2",
        "третий": "3", "третья": "3", "третьего": "3", "третьему": "3", "третьем": "3",
        "четвёртый": "4", "четвертый": "4", "четвёртая": "4", "четвертая": "4",
        "пятый": "5", "пятая": "5", "пятого": "5",
        "шестой": "6", "шестая": "6", "шестого": "6",
        "седьмой": "7", "седьмая": "7", "седьмого": "7",
        "восьмой": "8", "восьмая": "8", "восьмого": "8",
        "девятый": "9", "девятая": "9", "девятого": "9",
        "десятый": "10", "десятая": "10", "десятого": "10",
    }
    for word, digit in number_map.items():
        text = text.replace(word, digit)
        text = text.replace(word.capitalize(), digit)
    
    # Normalize Russian/Ukraine-specific letters
    text = text.replace("Ё", "Е").replace("ё", "е")
    
    # Collapse ALL whitespace (including newlines) into single spaces
    text = " ".join(text.split())
    
    # Lower-case
    text = text.lower()
    return text


def calculate_similarity(text1, text2):
    """Calculate similarity score between two texts (0-1)"""
    t1 = normalize_text(text1)
    t2 = normalize_text(text2)
    if not t1 or not t2:
        return 0.0
    
    # Try fuzzy matching first
    ratio = fuzz.token_set_ratio(t1, t2) / 100.0
    return ratio

def split_into_sentences(text):
    """Split text into sentences (multi-language support)"""
    import re
    
    if not text:
        return []
    
    # CRITICAL FIX: Collapse newlines/multi-space BEFORE splitting
    # This prevents Whisper's line breaks inside parentheses from creating false sentence boundaries
    text = " ".join(text.split())
    
    # Pattern for sentence endings (., !, ?, ... with spaces after)
    # Support for Russian, Ukrainian, English punctuation
    sentence_endings = r'[.!?]+\s+'
    
    # Split by sentence endings
    sentences = re.split(sentence_endings, text)
    
    # Clean up and filter empty
    sentences = [s.strip() for s in sentences if s.strip()]
    
    return sentences

def align_sentences(script_sentences, transcribed_sentences):
    """
    Align script sentences with transcribed sentences using fuzzy matching.
    CRITICAL: This dynamic alignment handles when Whisper shifts recognition.
    Uses sliding window approach to find best match for each script sentence.
    
    Returns list of dicts: [{script, transcribed, similarity, status}, ...]
    """
    
    alignments = []
    used_transcribed_indices = set()  # Track which transcribed sentences have been matched
    
    # For each script sentence, find the best matching transcribed sentence
    for script_idx, script_sent in enumerate(script_sentences):
        best_match_idx = -1
        best_similarity = 0.0
        
        # Search in transcribed sentences for best match
        for trans_idx, trans_sent in enumerate(transcribed_sentences):
            # Skip already-matched transcribed sentences (optional: enable for greedy matching)
            # if trans_idx in used_transcribed_indices:
            #     continue
            
            # Calculate similarity
            similarity = calculate_similarity(script_sent, trans_sent)
            
            # Check if this is the best match so far
            if similarity > best_similarity:
                best_similarity = similarity
                best_match_idx = trans_idx
        
        # Build alignment result
        trans_sent = ""
        if best_match_idx >= 0 and best_match_idx < len(transcribed_sentences):
            trans_sent = transcribed_sentences[best_match_idx]
            used_transcribed_indices.add(best_match_idx)
        
        # Determine status based on normalized similarity
        if best_similarity >= 0.99:
            status = 'match'
        elif best_similarity >= 0.85:
            status = 'minor_diff'
        else:
            status = 'mismatch'
        
        alignments.append({
            'script': script_sent,
            'transcribed': trans_sent,
            'similarity': best_similarity,
            'status': status
        })
    
    return alignments

def find_best_match(target_text, candidates):
    """Find the best matching candidate text"""
    best_score = 0
    best_index = -1
    
    for idx, candidate in enumerate(candidates):
        score = calculate_similarity(target_text, candidate)
        if score > best_score:
            best_score = score
            best_index = idx
    
    return best_index, best_score

def detect_error_type(script_text, transcribed_text, similarity_score, confidence):
    """Determine the type of error (using NORMALIZED comparison for accuracy)"""
    # CRITICAL FIX: Use normalized similarity as primary metric
    # This catches cases like "один" vs "1" or "наго́с" vs "наѓос"
    normalized_similarity = calculate_similarity(script_text, transcribed_text)
    
    if normalized_similarity >= 0.99:  # Essentially identical after normalization
        return "NONE"
    elif normalized_similarity >= 0.85:  # Minor differences
        return "MINOR_DIFF"
    else:
        return "MISMATCH"

def generate_diff(text1, text2):
    """Generate unified diff between two texts"""
    lines1 = text1.split('\n')
    lines2 = text2.split('\n')
    
    diff = list(unified_diff(lines1, lines2, lineterm=''))
    return '\n'.join(diff)

def analyze_duplicates(results, gap_threshold=1.0):
    """Detect duplicate items (same/similar text) BOTH between files AND within same file"""
    
    # First pass: detect duplicates WITHIN each file's segments
    for result in results:
        sentence_alignments = result.get('sentence_alignments', [])
        
        for i, sent1 in enumerate(sentence_alignments):
            trans1 = sent1.get('transcribed', '')
            if not trans1 or len(trans1) < 5:  # Skip very short texts
                continue
            
            # Check against later sentences in SAME file
            for j in range(i + 1, len(sentence_alignments)):
                sent2 = sentence_alignments[j]
                trans2 = sent2.get('transcribed', '')
                
                if not trans2:
                    continue
                
                # Calculate normalized similarity
                similarity = calculate_similarity(trans1, trans2)
                
                # CRITICAL FIX: Detect internal duplicates (like at 2:26)
                # If normalized similarity > 90%, mark as duplicate
                if similarity > 0.90:
                    # Mark the second occurrence as duplicate
                    if 'duplicate_info' not in sent2:
                        sent2['duplicate_info'] = {
                            'is_duplicate': True,
                            'reference_sentence': i + 1,
                            'similarity': round(similarity, 3),
                            'note': f'Duplicate of sentence {i + 1} (within same audio)'
                        }
    
    # Second pass: detect duplicates BETWEEN different files (original logic)
    for i, result1 in enumerate(results):
        if result1['error_type'] != "NONE":
            continue
        
        for j in range(i + 1, len(results)):
            result2 = results[j]
            if result2['error_type'] != "NONE":
                continue
            
            # Check if texts are similar (CRITICAL FIX: simplified logic)
            similarity = calculate_similarity(
                result1['transcribed_text'],
                result2['transcribed_text']
            )
            
            # Mark as DUPLICATE if normalized similarity is very high (>90%)
            if similarity > 0.90:
                result2['error_type'] = "DUPLICATE"
                result2['duplicate_of'] = f"Item {i + 1}"
                result2['issues'].append({
                    'type': 'DUPLICATE',
                    'reference_index': i,
                    'similarity': round(similarity, 3),
                    'description': f"Duplicate/same text as item {i + 1}"
                })

# ============================================================
# FLASK ROUTES
# ============================================================

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'ok',
        'model': current_model_name or DEFAULT_WHISPER_MODEL,
        'model_loaded': whisper_model is not None
    }), 200

@app.route('/analyze', methods=['POST'])
def analyze():
    """
    Analyze voice-over items
    
    Request JSON:
    {
        "audio_files": [
            {"path": "/path/to/audio.wav", "guid": "abc123", "index": 0}
        ],
        "script_lines": ["Hello world", "Good morning"],
        "detection_flags": {
            "mismatches": true,
            "duplicates": true,
            "off_script": true,
            "missing": true
        },
        "duplicate_gap_threshold": 1.0,
        "similarity_threshold": 0.85,
        "language": "uk",  # Optional: use null/None for auto-detect
        "terminology": "Apidra, Lantus, Tudjeo, ..."  # Optional: glossary for improved recognition
    }
    """
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({'error': 'No JSON data provided'}), 400
        
        audio_files = data.get('audio_files', [])
        # Now receiving pre-split script_sentences from Lua instead of raw script_lines
        # If old client sends script_lines, support that too (backward compatible)
        script_sentences = data.get('script_sentences', None)
        if not script_sentences:
            # Fallback for old clients using script_lines
            script_lines = data.get('script_lines', [])
            if script_lines:
                full_script_text = ' '.join(script_lines)
                script_sentences = split_into_sentences(full_script_text)
            else:
                script_sentences = []
        else:
            # script_sentences provided; reconstruct full text for error detection
            full_script_text = ' '.join(script_sentences)
        
        language = data.get('language', None)  # None triggers auto-detect
        terminology = data.get('terminology', '')  # Optional glossary
        model = data.get('model', None)  # Optional: turbo, base, small, medium, large-v3
        duplicate_gap_threshold = data.get('duplicate_gap_threshold', 1.0)
        similarity_threshold = data.get('similarity_threshold', 0.85)
        
        if language:
            print(f"[INFO] Language forced to: {language}")
        else:
            print(f"[INFO] Language auto-detection enabled")
        
        if model:
            print(f"[INFO] Using Whisper model: {model}")
        
        if terminology:
            print(f"[INFO] Using terminology guidance for recognition")
        
        if not audio_files or not script_sentences:
            return jsonify({'error': 'Missing audio_files or script_sentences'}), 400
        
        results = []
        
        # Process each audio file
        for idx, audio_info in enumerate(audio_files):
            audio_path = audio_info.get('path')
            guid = audio_info.get('guid', '')
            
            print(f"[DEBUG] Processing audio file {idx+1}/{len(audio_files)}")
            print(f"[DEBUG] Raw path from JSON: {repr(audio_path)}")
            print(f"[DEBUG] Path type: {type(audio_path)}")
            print(f"[DEBUG] Path exists check: {os.path.exists(audio_path)}")
            
            if not os.path.exists(audio_path):
                print(f"[ERROR] File not found at: {audio_path}")
                # Try to debug why - check if path has encoding issues or special characters
                try:
                    resolved = os.path.abspath(audio_path)
                    print(f"[DEBUG] Absolute path: {resolved}")
                except Exception as e:
                    print(f"[DEBUG] Path resolution error: {e}")
                
                results.append({
                    'index': idx,
                    'guid': guid,
                    'filename': Path(audio_path).name,
                    'error': f'Audio file not found: {audio_path}',
                    'error_type': 'FILE_NOT_FOUND',
                    'issues': []
                })
                continue
            
            # Transcribe audio (with optional model selection and terminology guidance)
            transcription = transcribe_audio(audio_path, language=language, terminology=terminology, model=model)
            
            if not transcription:
                results.append({
                    'index': idx,
                    'guid': guid,
                    'filename': Path(audio_path).name,
                    'error': 'Transcription failed',
                    'error_type': 'TRANSCRIPTION_ERROR',
                    'issues': []
                })
                continue
            
            transcribed_text = transcription.get('text', '').strip()
            detected_language = transcription.get('language', 'unknown')
            confidence = 0.5  # Default confidence
            
            # CRITICAL FIX: Use Whisper segments with precise timestamps instead of naive sentence splitting
            # This fixes: 1) timing desync up to 10 seconds, 2) duplicate detection within same audio
            whisper_segments = transcription.get('segments', [])
            
            # Extract transcribed sentences from Whisper segments (with accurate timestamps)
            transcribed_sentences = []
            segment_timings = []  # Store timings for CSV output
            
            for seg in whisper_segments:
                seg_text = seg.get('text', '').strip()
                if seg_text:  # Skip empty segments
                    transcribed_sentences.append(seg_text)
                    segment_timings.append({
                        'start': seg.get('start', 0.0),
                        'end': seg.get('end', 0.0),
                        'duration': seg.get('end', 0.0) - seg.get('start', 0.0)
                    })
            
            print(f"[INFO] Script sentences: {len(script_sentences)}, Whisper segments: {len(transcribed_sentences)}")
            
            # Align sentences for comparison
            sentence_alignments = align_sentences(script_sentences, transcribed_sentences)
            
            # CRITICAL FIX: Add Whisper timestamps to alignments for accurate timing in CSV
            # This fixes 10-second desync issue by using Whisper's precise segment boundaries
            for align_idx, alignment in enumerate(sentence_alignments):
                if align_idx < len(segment_timings):
                    timing = segment_timings[align_idx]
                    alignment['start_time'] = timing['start']
                    alignment['end_time'] = timing['end']
                    alignment['duration'] = timing['duration']
                else:
                    # Fallback if alignment count exceeds segments (shouldn't happen)
                    alignment['start_time'] = 0.0
                    alignment['end_time'] = 0.0
                    alignment['duration'] = 0.0
            
            # Calculate overall similarity
            if sentence_alignments:
                similarities = [a['similarity'] for a in sentence_alignments if a['similarity'] > 0]
                overall_similarity = sum(similarities) / len(similarities) if similarities else 0.0
            else:
                overall_similarity = 0.0
            
            # Determine error type based on overall similarity
            error_type = detect_error_type(full_script_text, transcribed_text, overall_similarity, confidence)
            
            # Build issues list with sentence-level details
            issues = []
            mismatches = 0
            minor_diffs = 0
            
            for sent_idx, alignment in enumerate(sentence_alignments):
                sent_status = alignment['status']
                sent_similarity = alignment['similarity']
                
                if sent_status == 'mismatch':
                    mismatches += 1
                    issues.append({
                        'type': 'SENTENCE_MISMATCH',
                        'sentence_index': sent_idx,
                        'script_sentence': alignment['script'],
                        'transcribed_sentence': alignment['transcribed'],
                        'similarity': round(sent_similarity, 3),
                        'note': f'Sentence {sent_idx + 1} does not match'
                    })
                elif sent_status == 'minor_diff':
                    minor_diffs += 1
                    issues.append({
                        'type': 'SENTENCE_MINOR_DIFF',
                        'sentence_index': sent_idx,
                        'script_sentence': alignment['script'],
                        'transcribed_sentence': alignment['transcribed'],
                        'similarity': round(sent_similarity, 3),
                        'note': f'Sentence {sent_idx + 1} has minor differences'
                    })
            
            # Add overall issue if error type is set
            if error_type == "MISMATCH" and not issues:
                issues.append({
                    'type': 'MISMATCH',
                    'similarity': round(overall_similarity, 3),
                    'note': 'Overall text mismatch'
                })
            elif error_type == "MINOR_DIFF" and not issues:
                issues.append({
                    'type': 'MINOR_DIFF',
                    'similarity': round(overall_similarity, 3),
                    'note': 'Text differs slightly from script'
                })
            
            result_item = {
                'index': idx,
                'guid': guid,
                'filename': Path(audio_path).name,
                'transcribed_text': transcribed_text,
                'script_text': full_script_text,
                'detected_language': detected_language,
                'error_type': error_type,
                'similarity': round(overall_similarity, 3),
                'confidence': round(confidence, 3),
                'sentence_count': len(sentence_alignments),
                'sentence_alignments': sentence_alignments,  # Detailed sentence-by-sentence comparison
                'issues': issues,
                'duplicate_of': ""  # Will be filled by analyze_duplicates if needed
            }
            
            results.append(result_item)
        
        # Analyze duplicates
        if data.get('detection_flags', {}).get('duplicates', True):
            analyze_duplicates(results, duplicate_gap_threshold)
        
        # Generate summary
        summary = {
            'total': len(results),
            'errors': sum(1 for r in results if r.get('error_type') not in ['NONE', None]),
            'mismatches': sum(1 for r in results if r.get('error_type') == 'MISMATCH'),
            'duplicates': sum(1 for r in results if r.get('error_type') == 'DUPLICATE'),
            'minor_diffs': sum(1 for r in results if r.get('error_type') == 'MINOR_DIFF'),
        }
        
        return jsonify({
            'status': 'success',
            'results': results,
            'summary': summary
        }), 200
    
    except Exception as e:
        print(f"[ERROR] Analysis failed: {e}")
        traceback.print_exc()
        return jsonify({
            'status': 'error',
            'error': str(e),
            'traceback': traceback.format_exc()
        }), 500

@app.route('/info', methods=['GET'])
def info():
    """Get server info"""
    return jsonify({
        'name': 'VO QC Server',
        'version': '1.0.0',
        'model': current_model_name or DEFAULT_WHISPER_MODEL,
        'port': PORT,
        'endpoints': {
            '/health': 'Health check',
            '/info': 'Server info',
            '/analyze': 'Analyze audio files'
        }
    }), 200

# ============================================================
# ERROR HANDLERS
# ============================================================

@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Endpoint not found'}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({'error': 'Internal server error'}), 500

# ============================================================
# MAIN
# ============================================================

if __name__ == '__main__':
    print(f"\n[INFO] Starting VO QC Server on http://localhost:{PORT}")
    print(f"[INFO] Default Whisper model: {DEFAULT_WHISPER_MODEL}")
    
    # Pre-load model
    if load_whisper_model():
        print("[INFO] Server ready!")
    else:
        print("[ERROR] Failed to load Whisper model!")
        sys.exit(1)
    
    try:
        app.run(host='127.0.0.1', port=PORT, debug=DEBUG, use_reloader=False)
    except KeyboardInterrupt:
        print("\n[INFO] Server stopped")
        sys.exit(0)
