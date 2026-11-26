#!/usr/bin/env python3
# @noindex
"""Local bridge between REAPER actions and a running ComfyUI instance.

Only stdlib is used so the bridge can run with the Python runtime provided by
Pinokio.  It uploads an audio file, queues a saved API workflow, waits for the
result, and writes a small status JSON file for the REAPER action to read.
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urlencode
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_WORKFLOW = ROOT / "workflows" / "clean_vocal_rnnoise_api.json"
DEFAULT_RUNTIME = ROOT / "runtime"



def resolve_input_path(raw_path: str) -> Path:
    """Resolve Windows paths that were mojibaked by REAPER/Lua -> cmd.exe."""
    original = Path(raw_path).resolve()
    if original.is_file():
        return original
    # Some REAPER/Windows path conversions insert a separator before an
    # underscore (for example ``GDrive\_VideoSila`` instead of
    # ``GDrive_VideoSila``). Try that repaired spelling before reporting a
    # missing source, while still preferring the literal path when it exists.
    for repaired_raw in (raw_path.replace("\\_", "_"), raw_path.replace("/_", "_")):
        repaired_path = Path(repaired_raw).resolve()
        if repaired_path.is_file():
            return repaired_path
    # UTF-8 bytes decoded as Windows-1251 produce strings such as РўРў...
    # Recover the original Unicode path when that is the only existing variant.
    try:
        repaired = Path(raw_path.encode("cp1251").decode("utf-8")).resolve()
    except (UnicodeEncodeError, UnicodeDecodeError):
        repaired = original
    if repaired.is_file():
        return repaired
    return original


def request_json(url: str, method: str = "GET", payload: dict | None = None) -> dict:
    data = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = Request(url, data=data, headers=headers, method=method)
    with urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def upload_audio(base_url: str, audio_path: Path) -> str:
    boundary = f"----reaper-comfy-{uuid.uuid4().hex}"
    content_type = mimetypes.guess_type(audio_path.name)[0] or "application/octet-stream"
    body = b"".join(
        [
            f"--{boundary}\r\n".encode(),
            (
                "Content-Disposition: form-data; name=\"image\"; "
                f"filename=\"{audio_path.name}\"\r\n"
            ).encode(),
            f"Content-Type: {content_type}\r\n\r\n".encode(),
            audio_path.read_bytes(),
            b"\r\n",
            f"--{boundary}--\r\n".encode(),
        ]
    )
    request = Request(
        f"{base_url}/api/upload/image",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}", "Accept": "application/json"},
        method="POST",
    )
    with urlopen(request, timeout=120) as response:
        answer = json.loads(response.read().decode("utf-8"))
    # ComfyUI's audio widget uses the generic image upload endpoint and field.
    # It returns {name, subfolder, type}; LoadAudio then reads it from input/.
    return "/".join(part for part in (answer.get("subfolder", ""), answer["name"]) if part)


def write_status(path: Path, status: str, **values: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"status": status, "updated_at": time.time(), **values}
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)


def output_file(history: dict, node_id: str) -> dict:
    outputs = history.get("outputs", {}).get(node_id, {})
    for key in ("audio", "images", "gifs"):
        values = outputs.get(key, [])
        if values:
            return values[0]
    raise RuntimeError(f"ComfyUI completed the job, but output node {node_id} returned no audio file: {outputs}")


def job_error(history: dict) -> str | None:
    status = history.get("status", {})
    if status.get("status_str") != "error":
        return None
    messages = status.get("messages", [])
    if messages:
        # ComfyUI stores execution errors as [event_name, detail_object].
        # Keep REAPER's console useful: report the real exception, not a
        # multi-line, JSON-escaped traceback.
        latest = messages[-1]
        if isinstance(latest, list) and len(latest) > 1 and isinstance(latest[1], dict):
            detail = latest[1]
            message = detail.get("exception_message") or detail.get("error")
            if message:
                return str(message).strip()
        if isinstance(latest, dict):
            message = latest.get("exception_message") or latest.get("error")
            if message:
                return str(message).strip()
    return "ComfyUI reported an execution error; check its server log for details."


def find_unique_node(workflow: dict, description: str, predicate) -> str:
    matches = [node_id for node_id, node in workflow.items() if predicate(node)]
    if len(matches) != 1:
        raise RuntimeError(f"Workflow must contain exactly one {description}; found: {', '.join(matches) or 'none'}")
    return matches[0]


def find_output_nodes(workflow: dict) -> list[str]:
    """Return all standard ComfyUI audio-save nodes in workflow order."""
    matches = [node_id for node_id, node in workflow.items() if node.get("class_type", "").startswith("SaveAudio")]
    if not matches:
        raise RuntimeError("Workflow must contain at least one SaveAudio output node.")
    return matches


def output_label(workflow: dict, node_id: str) -> str:
    """Use the workflow's original filename prefix as a human-readable REAPER lane name."""
    prefix = str(workflow[node_id].get("inputs", {}).get("filename_prefix", "AI result"))
    label = Path(prefix.replace("\\", "/")).name.replace("replace-at-runtime", "AI result")
    return label or "AI result"


def apply_overrides(workflow: dict, overrides: list[str]) -> None:
    """Apply simple node/input/value overrides received from the REAPER UI."""
    for item in overrides:
        try:
            node_id, input_name, raw_value = item.split(":", 2)
            node = workflow[node_id]
            if input_name not in node.get("inputs", {}):
                raise KeyError(f"input '{input_name}'")
            current_value = node["inputs"][input_name]
            if isinstance(current_value, str):
                value: object = unquote(raw_value)
            elif raw_value.lower() in {"true", "false"}:
                value: object = raw_value.lower() == "true"
            else:
                numeric = float(raw_value)
                value = int(numeric) if numeric.is_integer() else numeric
            node["inputs"][input_name] = value
        except (ValueError, KeyError) as error:
            raise RuntimeError(f"Invalid workflow macro override '{item}': {error}") from error


def download_output(base_url: str, file_info: dict, destination: Path) -> None:
    query = urlencode(
        {
            "filename": file_info["filename"],
            "subfolder": file_info.get("subfolder", ""),
            "type": file_info.get("type", "output"),
        }
    )
    with urlopen(f"{base_url}/view?{query}", timeout=120) as response:
        destination.write_bytes(response.read())


def find_ffmpeg() -> str | None:
    """Find FFmpeg shipped with REAPER or available on PATH."""
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg:
        return ffmpeg
    for resource_dir in reaper_resource_dirs():
        for name in ("ffmpeg.exe", "ffmpeg"):
            candidate = resource_dir / "UserPlugins" / name
            if candidate.is_file():
                return str(candidate)
    return None


def reaper_resource_dirs() -> list[Path]:
    """Default REAPER resource folders on Windows, macOS and Linux."""
    candidates = []
    if os.environ.get("REAPER_RESOURCE_PATH"):
        candidates.append(Path(os.environ["REAPER_RESOURCE_PATH"]))
    if os.environ.get("APPDATA"):
        candidates.append(Path(os.environ["APPDATA"]) / "REAPER")
    home = Path.home()
    candidates.append(home / "Library" / "Application Support" / "REAPER")
    candidates.append(Path(os.environ.get("XDG_CONFIG_HOME", home / ".config")) / "REAPER")
    return candidates


def resample_to_48k(source: Path, target_rate: int = 48000) -> Path:
    """Resample a downloaded ComfyUI file with FFmpeg (no Python audio libs)."""
    ffmpeg = find_ffmpeg()
    if not ffmpeg:
        raise RuntimeError("48 kHz resampling requires ffmpeg, but it was not found in PATH or REAPER/UserPlugins.")
    temporary = source.with_name(source.stem + "_48k.tmp" + source.suffix)
    codec = ["-c:a", "flac"] if source.suffix.lower() == ".flac" else ["-c:a", "pcm_s24le"]
    completed = subprocess.run(
        [ffmpeg, "-y", "-i", str(source), "-ar", str(target_rate), *codec, str(temporary)],
        capture_output=True,
        text=True,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    if completed.returncode != 0 or not temporary.is_file():
        detail = completed.stderr.strip().splitlines()[-1] if completed.stderr.strip() else "unknown ffmpeg error"
        raise RuntimeError(f"48 kHz resampling failed: {detail}")
    os.replace(temporary, source)
    return source


def convert_to_wav(source: Path, target_rate: int = 48000) -> Path:
    """Decode ComfyUI's FLAC result to a WAV file using REAPER's ffmpeg."""
    ffmpeg = find_ffmpeg()
    if not ffmpeg:
        raise RuntimeError("WAV output requires ffmpeg, but it was not found in PATH or REAPER/UserPlugins.")
    destination = source.with_suffix(".wav")
    completed = subprocess.run(
        [ffmpeg, "-y", "-i", str(source), "-ar", str(target_rate), "-c:a", "pcm_s24le", str(destination)],
        capture_output=True,
        text=True,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    if completed.returncode != 0 or not destination.is_file():
        detail = completed.stderr.strip().splitlines()[-1] if completed.stderr.strip() else "unknown ffmpeg error"
        raise RuntimeError(f"WAV conversion failed: {detail}")
    source.unlink(missing_ok=True)
    return destination


def run_clean_vocal(args: argparse.Namespace) -> None:
    base_url = args.base_url.rstrip("/")
    input_path = resolve_input_path(args.input)
    status_path = Path(args.status).resolve()
    workflow_path = Path(args.workflow).resolve()
    if not input_path.is_file():
        raise FileNotFoundError(f"Audio file not found: {input_path}")

    job_name = f"reaper_clean_{time.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:8]}"
    write_status(status_path, "uploading", input=str(input_path), job_name=job_name)
    uploaded_name = upload_audio(base_url, input_path)
    workflow = json.loads(workflow_path.read_text(encoding="utf-8"))
    apply_overrides(workflow, args.set_values)
    input_node_id = find_unique_node(workflow, "LoadAudio node", lambda node: node.get("class_type") == "LoadAudio")
    output_node_ids = find_output_nodes(workflow)
    workflow[input_node_id]["inputs"]["audio"] = uploaded_name
    output_labels = {node_id: output_label(workflow, node_id) for node_id in output_node_ids}
    for node_id in output_node_ids:
        workflow[node_id]["inputs"]["filename_prefix"] = f"reaper_ai/{job_name}_{node_id}"

    queued = request_json(f"{base_url}/prompt", "POST", {"prompt": workflow, "client_id": job_name})
    prompt_id = queued.get("prompt_id")
    if not prompt_id:
        raise RuntimeError(f"ComfyUI rejected the workflow: {queued}")
    write_status(status_path, "queued", input=str(input_path), job_name=job_name, prompt_id=prompt_id)

    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        history = request_json(f"{base_url}/history/{prompt_id}")
        entry = history.get(prompt_id)
        if entry:
            error = job_error(entry)
            if error:
                raise RuntimeError(f"ComfyUI execution error: {error}")
            outputs: dict[str, str] = {}
            for index, node_id in enumerate(output_node_ids, start=1):
                info = output_file(entry, node_id)
                suffix = Path(info["filename"]).suffix or ".flac"
                destination = status_path.parent / f"{job_name}_{index}{suffix}"
                download_output(base_url, info, destination)
                if args.output_format == "wav":
                    destination = convert_to_wav(destination, args.sample_rate)
                else:
                    destination = resample_to_48k(destination, args.sample_rate)
                label = output_labels[node_id]
                # A duplicate label should never overwrite another stem in the
                # JSON passed to REAPER.
                if label in outputs:
                    label = f"{label} {index}"
                outputs[label] = str(destination)
            first_output = next(iter(outputs.values()))
            write_status(
                status_path,
                "complete",
                input=str(input_path),
                job_name=job_name,
                prompt_id=prompt_id,
                output=first_output,
                outputs=outputs,
            )
            return
        write_status(status_path, "running", input=str(input_path), job_name=job_name, prompt_id=prompt_id)
        time.sleep(1)
    raise TimeoutError(f"ComfyUI did not complete the job within {args.timeout} seconds")


def validate(args: argparse.Namespace) -> None:
    nodes = request_json(f"{args.base_url.rstrip('/')}/object_info")
    required = {"LoadAudio", "Egregora_RNNoise_Denoise", "SaveAudio"}
    missing = sorted(required - set(nodes))
    if missing:
        raise RuntimeError(f"Required ComfyUI nodes are unavailable: {', '.join(missing)}")
    print("OK: ComfyUI API and required workflow nodes are available.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:8188")
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate_parser = subparsers.add_parser("validate")
    validate_parser.set_defaults(func=validate)
    clean = subparsers.add_parser("clean-vocal")
    clean.add_argument("--input", required=True)
    clean.add_argument("--workflow", default=str(DEFAULT_WORKFLOW))
    clean.add_argument("--status", default=str(DEFAULT_RUNTIME / "latest_result.json"))
    clean.add_argument("--timeout", type=int, default=3600)
    clean.add_argument("--output-format", choices=("flac", "wav"), default="flac")
    clean.add_argument("--sample-rate", type=int, default=48000,
                       help="Output sample rate in Hz (default: 48000).")
    clean.add_argument("--set", dest="set_values", action="append", default=[],
                       metavar="NODE:INPUT:VALUE",
                       help="Override one numeric or boolean workflow input for this job.")
    clean.set_defaults(func=run_clean_vocal)
    args = parser.parse_args()
    try:
        args.func(args)
        return 0
    except Exception as error:
        status = getattr(args, "status", None)
        if status:
            try:
                write_status(Path(status).resolve(), "failed", error=str(error))
            except Exception:
                pass
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
