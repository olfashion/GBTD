#!/usr/bin/env python3
"""Package a fresh Godot Web export for a static host with an asset-size limit.

python3 tools/prepare_web_preview.py --input builds/web --output /path/to/dist

Original WASM bytes are split, not compressed or modified. A small fetch
adapter streams the ordered parts to Godot using standard browser APIs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import tempfile
from pathlib import Path


PART_BYTES = 12 * 1024 * 1024
FORMAT = "good-boys-web-preview-v1"
MANIFEST_NAME = "web-preview-manifest.json"
TEMPLATE_DIRECTORY = Path(__file__).resolve().parent / "web_preview"

STATUS = """<div id="status" role="status" aria-live="polite">
  <img class="preview-emblem" src="index.icon.png" alt="">
  <p class="preview-eyebrow">LIBERTY HILL · TEXAS</p>
  <h1 class="preview-title">GOOD BOYS</h1>
  <p class="preview-subtitle">Backyard Defense</p>
  <span class="preview-badge">iPhone browser playtest</span>
  <p id="loader-label">Getting the pack together…</p>
  <progress id="status-progress" aria-label="Game download progress"></progress>
  <div id="status-notice"></div>
  <button id="reload-game" type="button" hidden>Reload game</button>
  <p class="preview-note">Protect the puppy. Earn your pack.<br>Browser preview · Native iPhone app in development.</p>
</div>
<div id="rotate-hint" role="dialog" aria-modal="true" aria-label="Turn your phone sideways">
  <div class="rotate-phone" aria-hidden="true"></div>
  <h2>A big yard needs a little more room.</h2>
  <p>Turn your phone sideways to play Good Boys.</p>
  <small>If the screen won’t turn, switch off Portrait Orientation Lock.</small>
</div>"""

FAILURE = """function displayFailureNotice(err) {
    console.error(err);
    document.getElementById('loader-label').textContent = 'The backyard couldn’t load.';
    const message = String(err && err.message || err);
    setStatusNotice(message.includes('WebGL2')
      ? 'This browser cannot start the 3D renderer (WebGL 2). On iPhone, open this link in an up-to-date Safari browser.'
      : 'Check your connection or try a current browser, then reload to try again.');
    document.getElementById('reload-game').hidden = false;
    setStatusMode('notice');
    initializing = false;
  }

  window.addEventListener('goodboys-load-error', function (event) {
    displayFailureNotice(new Error(event.detail.message));
  });

  const missing"""


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def prepare(source: Path, destination: Path) -> dict:
    source = source.resolve(strict=True)
    destination = destination.resolve()
    if destination == source or destination in source.parents or source in destination.parents:
        raise ValueError("Input and output must be separate, non-nested directories")
    for path in source.rglob("*"):
        if path.is_symlink():
            raise ValueError(f"Refusing to publish a symlink: {path.name}")
    for name in ("index.html", "index.js", "index.wasm", "index.pck"):
        if not (source / name).is_file():
            raise ValueError(f"Missing Godot Web export file: {name}")
    if destination.exists() and any(destination.iterdir()):
        marker = destination / MANIFEST_NAME
        if not marker.is_file() or json.loads(marker.read_text()).get("format") != FORMAT:
            raise ValueError("Output is nonempty and is not a previous Good Boys preview package")

    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="good-boys-preview-", dir=destination.parent) as temporary:
        staging = Path(temporary) / "dist"
        shutil.copytree(source, staging)
        wasm = staging / "index.wasm"
        manifest = {
            "format": FORMAT,
            "wasm": "index.wasm",
            "bytes": wasm.stat().st_size,
            "sha256": sha256(wasm),
            "part_size_limit": PART_BYTES,
            "parts": [],
        }
        if manifest["bytes"] == 0:
            raise ValueError("WASM export is empty")
        with wasm.open("rb") as binary:
            index = 0
            while block := binary.read(PART_BYTES):
                name = f"index.wasm.part-{index:03d}.bin"
                (staging / name).write_bytes(block)
                manifest["parts"].append({
                    "file": name,
                    "bytes": len(block),
                    "sha256": hashlib.sha256(block).hexdigest(),
                })
                index += 1

        combined = hashlib.sha256()
        byte_count = 0
        for part in manifest["parts"]:
            block = (staging / part["file"]).read_bytes()
            combined.update(block)
            byte_count += len(block)
        if byte_count != manifest["bytes"] or combined.hexdigest() != manifest["sha256"]:
            raise ValueError("Reassembled WASM differs from the exported binary")
        wasm.unlink()

        loader = (TEMPLATE_DIRECTORY / "wasm-chunk-loader.js").read_text()
        loader = loader.replace("__GOOD_BOYS_WASM_MANIFEST__", json.dumps(manifest, separators=(",", ":")))
        (staging / "wasm-chunk-loader.js").write_text(loader)
        for filename in ("preview-shell.css", "preview-shell.js"):
            shutil.copy2(TEMPLATE_DIRECTORY / filename, staging / filename)

        html_path = staging / "index.html"
        html = html_path.read_text()
        config_match = re.search(r"const GODOT_CONFIG = (\{[^\n]+\});", html)
        if not config_match:
            raise ValueError("Unsupported Godot HTML template: missing GODOT_CONFIG")
        config = json.loads(config_match.group(1))
        if config.get("fileSizes", {}).get("index.wasm") != manifest["bytes"]:
            raise ValueError("Godot WASM size metadata does not match the exported binary")
        if "const GODOT_THREADS_ENABLED = false;" not in html:
            raise ValueError("Use the single-threaded Web export preset for this preview")

        html, count = re.subn(
            r'<meta name="viewport"[^>]*>',
            '<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">',
            html,
            count=1,
        )
        if count != 1:
            raise ValueError("Missing viewport declaration")
        html = re.sub(r"<title>.*?</title>", "<title>Good Boys · iPhone browser playtest</title>", html, count=1)
        html = html.replace("</head>", '<link rel="stylesheet" href="preview-shell.css">\n</head>', 1)
        html, count = re.subn(
            r'<div id="status">.*?<div id="status-notice"></div>\s*</div>',
            STATUS,
            html,
            count=1,
            flags=re.S,
        )
        if count != 1:
            raise ValueError("Unsupported Godot HTML status overlay")
        script_marker = '<script src="index.js"></script>'
        if script_marker not in html:
            raise ValueError("Unsupported Godot engine script tag")
        html = html.replace(
            script_marker,
            '<script src="preview-shell.js"></script>\n'
            '<script src="wasm-chunk-loader.js"></script>\n' + script_marker,
            1,
        )
        html, count = re.subn(
            r"function displayFailureNotice\(err\) \{.*?\n\t\}\n\n\tconst missing",
            FAILURE,
            html,
            count=1,
            flags=re.S,
        )
        if count != 1:
            raise ValueError("Unsupported Godot failure handler")
        progress_marker = "statusProgress.max = total;"
        if progress_marker not in html:
            raise ValueError("Unsupported Godot progress callback")
        html = html.replace(
            progress_marker,
            progress_marker + "\n          document.getElementById('loader-label').textContent = "
            "'Getting the pack together… ' + Math.min(100, Math.round(current / total * 100)) + '%';",
            1,
        )
        # The exported byte count is deliberately unchanged: Godot sees one
        # streamed response containing the exact original WASM bytes.
        html_path.write_text(html)
        (staging / MANIFEST_NAME).write_text(json.dumps(manifest, indent=2) + "\n")

        oversize = [p.name for p in staging.rglob("*") if p.is_file() and p.stat().st_size > 25 * 1024 * 1024]
        if oversize:
            raise ValueError("Assets still exceed the static host limit: " + ", ".join(oversize))
        if destination.exists():
            shutil.rmtree(destination)
        shutil.move(str(staging), str(destination))
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="Fresh Godot Web export directory")
    parser.add_argument("--output", required=True, type=Path, help="New or previously prepared output directory")
    arguments = parser.parse_args()
    manifest = prepare(arguments.input, arguments.output)
    print(f"Prepared {arguments.output.resolve()}")
    print(f"WASM: {manifest['bytes']:,} identical bytes in {len(manifest['parts'])} ordered parts")
    print(f"SHA256: {manifest['sha256']}")
    print("All generated assets fit within 25 MiB; WASM parts are at most 12 MiB.")


if __name__ == "__main__":
    main()
