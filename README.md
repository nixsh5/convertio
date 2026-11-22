# Convertio

A theme-responsive, offline file converter widget and details panel for the **Omarchy Quattro bar**, featuring automatic GPU hardware acceleration (NVENC / VA-API) and live ETA tracking.

## Features

### Video & Audio
Convert between the following formats using FFmpeg:

- **Video:** `mp4`, `mkv`, `webm`, `mov`, `avi`, `flv`, `ts`, `m4v`
- **Audio:** `mp3`, `wav`, `flac`, `ogg`, `m4a`, `opus`, `aac`
- **Animation:** `gif`

### GPU Acceleration
- Automatically detects NVIDIA NVENC (`h264_nvenc`) and AMD/Intel VA-API (`h264_vaapi` / `vp9_vaapi`).
- One-click toggle to switch between hardware acceleration and CPU encoding.

### Images & PDF
Convert between the following formats using ImageMagick and Poppler:

`png`, `jpg`, `webp`, `avif`, `svg`, `bmp`, `ico`, `tiff`, `pdf`

### Documents & Office Suites
Convert between the following formats using Pandoc and LibreOffice:

`md`, `html`, `tex`, `epub`, `rst`, `txt`, `docx`, `odt`, `xlsx`, `ods`, `pptx`, `odp`, `csv`

### In-Panel Dependency Check
- Automatically detects missing CLI tools.
- Offers a one-click terminal prompt to install dependencies using `sudo pacman -S --needed ...`.

## External Dependencies

Convertio runs locally and delegates conversions to standard CLI tools:

| Dependency | Purpose |
|---|---|
| `ffmpeg` | Video, audio, and GIF transcoding |
| `imagemagick` | Image conversion |
| `pandoc` | Markdown, HTML, LaTeX, and e-book conversion |
| `libreoffice-fresh` | Office documents, spreadsheets, presentations, and PDF import |
| `poppler` | `pdftotext` and `pdftoppm` for PDF text extraction and page rendering |
| `zenity` | Native file dialogs |
| `wl-clipboard` | Wayland clipboard path pasting |

### Install All Optional Backends

On Arch Linux / Omarchy:

```bash
sudo pacman -S --needed ffmpeg imagemagick pandoc libreoffice-fresh poppler zenity wl-clipboard
```

## Install

Install and enable Convertio using:

```bash
omarchy plugin add https://github.com/nixsh5/convertio.git --enable
```

## Usage

- **Left-click** the bar icon (`󰑐`) to open or close the converter panel. Press `Escape` to close it.
- **Right-click** the bar icon to load a file path directly from your Wayland clipboard.
- **Drag and drop** any supported file directly onto the open panel.
- Click the folder icon (`󰉋`) to browse for files.
- Click the **Compute** cell (`GPU (NVENC)` / `CPU`) in the metadata grid to toggle hardware acceleration.

## Configure

Move the widget to any section of your Omarchy bar:

```bash
omarchy bar move io.github.nixsh5.convertio --section right
```

## Remove

Uninstall Convertio using:

```bash
omarchy plugin remove io.github.nixsh5.convertio
```

