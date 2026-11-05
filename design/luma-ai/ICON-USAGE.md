# Luma AI application icon

`luma-ai.webp` is the user-provided source of the approved solid-white icon.
The application uses PNG copies because Qt installations without the optional
WebP image plugin cannot decode the source. The conversion preserves the decoded
pixels, transparency and dimensions; it does not redesign the artwork.

Runtime copies:

- `config/quickshell/MacShell/assets/luma-ai.png`: Settings, Luma AI window and Spotlight.
- `share/macshell/icons/luma-ai.png`: desktop application and launcher shortcuts.

To refresh both copies after replacing the WebP source, run from the repository:

```sh
magick design/luma-ai/luma-ai.webp config/quickshell/MacShell/assets/luma-ai.png
cp config/quickshell/MacShell/assets/luma-ai.png share/macshell/icons/luma-ai.png
```

The installer copies both assets and expands the desktop entry's `@DATA_HOME@`
icon path for the installing user.
