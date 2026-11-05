# Third-party components

This repository is a customized MacShell distribution. Existing notices remain
with their source; different components retain their respective licenses.

| Component | Source | License/notice |
| --- | --- | --- |
| MacShell and MacLock base | https://github.com/0-ss/MacShell | MIT; root LICENSE preserves the upstream copyright |
| MacTahoe GTK theme | https://github.com/vinceliuice/MacTahoe-gtk-theme | MIT; licenses/MacTahoe-gtk-MIT.txt |
| MacTahoe icons and cursors | https://github.com/vinceliuice/MacTahoe-icon-theme | GPL-3.0; icons/MacTahoe/COPYING and licenses/MacTahoe-icons-GPL-3.0.txt |
| OpenRunde font inherited from MacShell | https://github.com/lauridskern/open-runde | Font authors' license; see licenses/OpenRunde.txt |

The icon collection includes third-party application marks; inclusion does not
imply affiliation. Apple San Francisco font files, private avatars, camera
preferences, captured photos/videos, application caches, browser data, rollback
snapshots, compiled binaries, and copied Electron application distributions are
not part of this source bundle.

Luma AI optionally downloads [llama.cpp](https://github.com/ggml-org/llama.cpp)
(MIT) and uses Google Gemma 3 GGUF models
([1B QAT](https://huggingface.co/google/gemma-3-1b-it-qat-q4_0-gguf),
[4B QAT](https://huggingface.co/google/gemma-3-4b-it-qat-q4_0-gguf)) under the
Gemma Terms of Use. The repositories are gated; the user accepts the terms and
downloads/imports the weights explicitly. These binaries and model weights are
not bundled. See [Luma AI](docs/LUMA.md) for the exact files and storage paths.

The default SVG wallpaper was created for this bundle and is supplied under
the repository's MIT license. Native integration and app source are included
so they can be rebuilt against the recipient's installed toolkit/compositor.
