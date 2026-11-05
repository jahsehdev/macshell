# Luma AI

Luma AI is MacShell's optional local assistant for chat, writing, summaries,
brainstorming and opening applications. It follows MacShell's light/dark theme,
accent color and font. It uses a CPU runtime and requires no cloud account or API key.

## Install and open

1. Open **Settings → Luma AI**.
2. Choose **Install** under **Light** (recommended), **Balanced**, or **Quality**.
3. Leave MacShell running until installation finishes. Progress and errors appear
   in Settings. Cancelled/incomplete downloads resume when retried.
4. Click the circular Luma icon in the menu bar or press **Super+Shift+Space**
   to open the quick panel. Choose **Open Luma AI** or run `macshell-luma` for
   the full application.

The main MacShell installer installs only the UI and its small Python bridge.
No models or runtime are bundled, downloaded, or launched by `install.sh`.
Opening Settings does not load a model or make a network request.

The optional setup downloads an official llama.cpp CPU runtime (unless
`llama-server` is already installed) and the selected official Gemma 3 GGUF model.
Downloads are checked against pinned SHA-256 checksums before activation and
recorded in a local provenance manifest. The Gemma repositories are gated: the
in-app download requires access to the weights and will stop with instructions
if Hugging Face refuses it. In that case, accept the Gemma terms on the model
page, download the GGUF file there, and use **Import GGUF…** in
**Settings → Luma AI**. Importing verifies the file size and SHA-256 before it is
activated. If no compatible CPU binary is available, install a compatible
`llama-server` on your PATH and retry. No privileged package-manager commands run
from the UI.

| Choice | Model | Approximate download | Suggested system RAM |
| --- | --- | --- | --- |
| Light (default) | Gemma 3 1B IT QAT Q4_0 | 1.0 GB | 2 GB+ |
| Balanced | Gemma 3 4B IT QAT Q4_0 | 3.2 GB | 6 GB+ |

These are estimates; runtime files need additional storage. Available memory
also needs to accommodate your desktop and other apps. Older CPUs may respond
slowly. No response-speed guarantee is made. Larger models are optional and
can be selected or removed individually. If a runtime is missing but a model
is installed, Settings offers **Repair runtime**.

Model files use model-specific names (`gemma-3-1b-it-q4_0.gguf`,
`gemma-3-4b-it-q4_0.gguf`). The old Qwen `light.gguf` is deliberately not
recognized, is never used as a fallback, and is never deleted automatically.

## Chat and Spotlight

**Super+Shift+Space** opens a new, independent **Search or Ask** menu in the
center of the focused display. It appears only when invoked, with a compact
380 × 60 px dark liquid-glass capsule and a stronger, two-pass backdrop blur.
The backdrop includes live application windows beneath the menu, with floating
windows layered above tiled windows on the active workspace. Window captures
use the shell's shared admission gate and pause during capture churn/recording.
The idle microphone icon changes to Send when the input contains a prompt.
Click the idle microphone to morph the search capsule into a circular
liquid-glass voice orb at the same center. Search controls disappear as the
capsule shortens and rounds; a centered wave follows microphone amplitude.
Click the orb or press Escape to stop and return to search. Closing the menu
also stops capture.
See [Microphone orb](LUMA-MIC-ORB.md) for the QML component, audio reader and
external shader integration. This visualizer does not transcribe speech.
Send uses a vector paper-plane icon; during generation it becomes Stop.
Each opening hides
previous messages until a new prompt is sent; conversation history stays saved.
Answers appear below the input. **Enter** sends, **Escape** or clicking outside closes, and the
same shortcut toggles it again. The menu is hosted separately from the menu bar
and works when that bar or its Luma icon is hidden.

The menu-bar Luma icon keeps its separate compact quick panel with the faster
520 ms opening. It shares the current conversation with the new menu and the
full application. **Open app ↗** continues that conversation in the application;
**+** starts a new conversation. During generation, the send arrow becomes
**Stop**. Closing either menu leaves an active response running. If no model is
installed, the menus offer Settings. Opening a menu never loads a model.

The search menu has its own IPC entry points: `qs -c MacShell ipc call lumasearch
toggle`, `lumasearch open`, and `lumasearch close`. The legacy `luma toggle`
command also opens the new search menu; `luma open` opens the full application.
The menu-bar icon can be hidden in **Settings → Menu Bar → Luma AI**.

Search normally in Spotlight and select **Ask Luma AI**, or use the explicit
prefix `luma: explain how photosynthesis works`. The query opens as an editable
draft in Luma AI. Press **Enter** to send; **Shift+Enter** inserts a line break.
**Stop** cancels generation. Answers stream into the panel and can be selected
or copied. **Ctrl+N** starts a new conversation; **Escape/Ctrl+W** closes the window.
Closing the window does not cancel an active response; use Stop for that.

Conversations appear in the sidebar. Select one to continue; deleting requires
a second click. Settings also offers **Delete all conversations** with confirmation.
The local store retains up to 100 conversations and 100 messages per conversation.
Only recent messages fitting the context budget are sent to the local model.
Individual messages are limited to 3500 characters. Answers are limited to 768
generated tokens to keep CPU work bounded.

## Desktop actions

After installation, explicit commands can open applications without loading
the language model:

- `Buka terminal` / `Open terminal`
- `Buka files` / `Open file manager`
- `Buka Firefox` (use the exact installed application name)
- `Buka pengaturan` / `Open settings`
- `Buka wallpaper`, `Buka bluetooth`, `Buka wifi`, `Buka suara`
- `Open appearance`, `Open Luma settings`

These commands use an explicit allowlist and installed desktop application
entries. Model output is always text; it is never executed as shell commands.
Application responses confirm the launch request, not that the app has finished
opening. No generated workflows, voice, screen reading, image understanding,
personal-file indexing or email/calendar integrations are included in this first version.

## Memory and privacy

The Python bridge starts only when Settings or Luma AI is first opened, and does
not load any model itself. The inference process starts on the first chat request,
binds only to `127.0.0.1` with a random per-process API key, and bypasses HTTP
proxies. Model inference never uses a cloud provider. The process exits and frees
its memory after 90 seconds without a request; Settings can release it immediately.
Changing/removing a model or stopping generation also stops the owned runtime.
Exiting MacShell cleans up the bridge and its inference process.

Internet is used only when the user requests installation: metadata and model
downloads from Hugging Face and runtime downloads from GitHub. Luma does not
read the screen, clipboard, documents, mail, or calendar. Only submitted text
and recent messages from the selected conversation enter the local model.
Local history is not encrypted; it is stored with user-only file permissions.

Locations respect the corresponding XDG environment variables:

- Preferences: `~/.config/macshell/luma.json`
- Models: `~/.local/share/macshell/luma/models/`
- Model provenance manifest: `~/.local/share/macshell/luma/models/manifest.json`
- Optional runtime: `~/.local/share/macshell/luma/runtime/`
- Conversations: `~/.local/share/macshell/luma/conversations.json`
- Runtime diagnostics: `~/.local/share/macshell/luma/runtime.log`

Removing the last model also removes Luma's downloaded runtime. A system-provided
`llama-server` is never removed. History is managed separately and survives model
removal and MacShell updates. Partial downloads use `.part` files and are removed
when their model is removed. Luma settings/model data are generated at runtime,
outside the repository and installer payload.

## Upstream components

- [llama.cpp](https://github.com/ggml-org/llama.cpp): MIT license; downloaded separately.
- [Gemma 3 1B IT QAT Q4_0 GGUF](https://huggingface.co/google/gemma-3-1b-it-qat-q4_0-gguf) and
  [Gemma 3 4B IT QAT Q4_0 GGUF](https://huggingface.co/google/gemma-3-4b-it-qat-q4_0-gguf):
  Gemma Terms of Use; gated, downloaded/imported separately from the publisher.
  The pinned file names and SHA-256 values are recorded in `bin/luma.py`.

## Validation

Run `python3 -B -m unittest discover -s tests -p 'test_*.py' -v`.
Luma tests cover verified/resumable downloads, cancellation, archive extraction,
model selection, install gating, local streaming, local history, failure recovery,
and idle memory release without requiring network access or large model files.
