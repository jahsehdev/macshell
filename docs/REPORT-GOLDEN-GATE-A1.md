# Golden Gate 27 — A1 Luma migration report

Date: 2026-10-31
Scope: non-Qwen model catalog, local GGUF import, provenance manifest, Qwen-specific prompt/template removal
Status: implementation and offline verification complete; real Gemma inference (A2) waits for the gated model file

## Result

| A1 requirement | State |
| --- | --- |
| Non-Qwen catalog and model-specific IDs | Done — Gemma 3 1B and 4B |
| No dependency on `light.gguf` | Done — old Qwen file is not referenced and was left untouched |
| Local GGUF import | Done — Settings → Luma AI → Import GGUF… |
| Provenance/checksum manifest | Done — `models/manifest.json` |
| Gated-repository handling | Done — clear message, no silent terms acceptance, no partial file |
| Remove Qwen-specific flags | Done — `/no_think` and `enable_thinking` removed |
| Real offline inference smoke test | Blocked — the official model is gated and has not been downloaded |

## What changed

### Model catalog

`config/quickshell/MacShell/bin/luma.py`

- Replaced the Qwen-only catalog with:

  | ID | Name | Family | File | Quant | Download | Suggested RAM |
  | --- | --- | --- | --- | --- | --- | --- |
  | `gemma-3-1b` | Light (default) | Gemma 3 1B IT | `gemma-3-1b-it-q4_0.gguf` | QAT Q4_0 | 1.0 GB | 2 GB+ |
  | `gemma-3-4b` | Balanced | Gemma 3 4B IT | `gemma-3-4b-it-q4_0.gguf` | QAT Q4_0 | 3.2 GB | 6 GB+ |

- Each entry pins the repository, exact filename, byte size, SHA-256, license, and
  gated flag. The 12B QAT file is not offered because it is 7.5 GiB and would not
  fit this machine's 7.7 GiB of RAM.
- Model paths now use the model-specific filename, not `light.gguf` or a generic
  ID filename. The old Qwen file remains at
  `~/.local/share/macshell/luma/models/light.gguf` but is not selectable, not a
  fallback, and not deleted automatically.
- Old preference IDs (`light`, `balanced`, `quality`) are replaced in memory by
  the new default (`gemma-3-1b`); the old preference is not treated as an
  installed model.

### Download, import, and provenance

- `model_metadata()` matches the exact pinned filename and refuses a publisher
  checksum or size that differs from the pinned Gemma file.
- If Hugging Face rejects the gated download (HTTP 401/403), Luma shows:
  “Gemma 3 is gated on Hugging Face. Accept the Gemma terms on the model page,
  download the GGUF file there, then use Import GGUF in Settings → Luma AI.”
  The failed attempt creates no model file and no manifest entry.
- `Import GGUF…` opens a Qt file dialog filtered to `*.gguf`. The bridge checks
  the exact byte size and SHA-256, streams the file into a `.part` file with
  progress/cancel support, and only publishes it after verification.
- Successful downloads and imports write
  `~/.local/share/macshell/luma/models/manifest.json` with the model family,
  repository, filename, parameters, quantization, SHA-256, size, license,
  installation method, source, and timestamp.
- Selecting/loading a model requires the manifest, the pinned size, and the
  pinned digest. A file without provenance is shown as Unverified and cannot be
  loaded until it is imported again.
- Removing a model removes only its own model file, partial file, and manifest
  entry. The old Qwen file and other models are untouched.

### UI and prompts

`LumaSettings.qml`, `LumaController.qml`

- Model cards now show the Gemma family and the two new sizes, with Install,
  Use model, Import GGUF…, Remove, and the gated-model explanation. A model file
  without a provenance record is labelled **Unverified**, and its primary button
  opens Import instead of loading the file.
- The progress panel is shown for both install and import jobs.
- The privacy text explains pinned checksums and the local manifest.
- `SYSTEM` no longer contains Qwen's `/no_think`, and chat requests no longer send
  `chat_template_kwargs.enable_thinking`. llama.cpp uses the model's Jinja chat
  template.

`docs/LUMA.md` documents the Gemma catalog, gated/import flow, model-specific
filenames, manifest path, and Gemma terms/license.

## Verification

- `python3 -m py_compile config/quickshell/MacShell/bin/luma.py` — passes.
- `python3 -B -m unittest discover -s tests -p 'test_*.py'` — **32 tests pass**,
  including new coverage for:
  - gated metadata that tries to replace the pinned Gemma file;
  - wrong-file import rejection without publishing;
  - verified import, manifest creation, and activation;
  - removal of a model and its manifest entry;
  - no Qwen-specific chat flags or `/no_think`.
- Live bridge status returns the two Gemma models, `runtime_ready: true`,
  `ready: false`, and the old `light.gguf` is not listed as installed.
- `model_metadata()` for Gemma 3 1B returned exactly the pinned size
  `1,003,541,152` bytes and SHA-256
  `95e5b8d891cd6a794f66c2a6fb59a41e9562b4660560b854274eceffb628b22a`.
- A gated install attempt produced the gated message and created no
  `.part`/model file or manifest.
- Importing the old Qwen `light.gguf` was rejected with a size-mismatch error;
  `light.gguf` and the model directory were unchanged.
- The import file dialog opens with the `GGUF models (*.gguf)` filter
  (`docs/ui-previews/golden-gate-phase1/luma-import-dialog.webp`).
- The Gemma model pane renders in Settings
  (`docs/ui-previews/golden-gate-phase1/luma-gemma-settings.webp`).
- Shell reload reports `Configuration Loaded` with no new QML errors.

## Deployment

Copied to `~/.config/quickshell/...` and byte-identical to the repository:

```
MacShell/bin/luma.py
MacShell/LumaController.qml
MacShell/LumaSettings.qml
```

The Python bridge and QML controller use the new catalog. No package or model
installation was performed.

## Pending

1. **Gemma 3 1B import and A2 smoke test.** The official repository is gated.
   Download `gemma-3-1b-it-q4_0.gguf` from
   <https://huggingface.co/google/gemma-3-1b-it-qat-q4_0-gguf> after accepting
   the Gemma terms, then report the file path. MacShell will verify the pinned
   size/SHA-256, import it, and run an offline inference smoke test with the
   network disconnected or blocked.
2. **Local runtime import UI.** The private runtime at
   `~/.local/share/macshell/luma/runtime/llama-b11928/` is detected, and a system
   `llama-server` on PATH is also used. A separate “import a runtime folder”
   control is not exposed yet; it is not part of the A1 acceptance criteria.
3. **Dependency installs awaiting approval** (unchanged from the UI batch):

```bash
# OCR (GG-19)
sudo pacman -S --needed tesseract tesseract-data-eng tesseract-data-ind

# Android mirroring (GG-05); android-tools 37.0.0.p1-1 is already installed
sudo pacman -S --needed scrcpy

# Optional system AI runtime; the private llama.cpp runtime already exists
sudo pacman -S --needed llama-cpp
```

The Gemma weights are not included in any of these commands and are not
downloaded automatically.
