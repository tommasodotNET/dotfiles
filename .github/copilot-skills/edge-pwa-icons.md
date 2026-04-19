# Edge PWA Icon Replacement

Replace Edge PWA icons with custom macOS-style icons so they look consistent in GNOME Dash-to-Dock.

## Prerequisites

- **ImageMagick** (`convert`, `identify`) must be installed
- Source icon as `.icns` (from [macosicons.com](https://macosicons.com)) or high-res PNG (≥ 1024×1024 recommended)
- The PWA must already be installed in Edge so its manifest resource directory exists

## Context

Edge PWAs store icons in `~/.config/microsoft-edge/Default/Web Applications/Manifest Resources/<app-id>/`. In this dotfiles repo, that directory is symlinked to `microsoft/edge-pwas/<app-id>/`.

Each app has multiple icon subdirectories that Edge may read from — **all** must be updated or the dock will show the wrong icon:

| Directory | Typical sizes | Purpose |
|---|---|---|
| `Icons/` | 32, 48, 64, 96, 128, 144, 192, 256, 512 | Primary icons |
| `Trusted Icons/Icons/` | 32, 48, 64, 96, 128, 256, 512 | Verified/pinned icons (Edge uses these for the dock) |
| `Icons Maskable/` | 128, 192, 256, 512, 1024 | Adaptive icons (only some apps) |

> **Important:** Some apps have extra sizes (16, 20, 24, 40, 150, 1024). Preserve whatever sizes already exist in each directory — do not add or remove sizes.

## Workflow

### Step 1 — Extract the largest frame from `.icns`

`.icns` is a container with multiple sizes. Extract the largest PNG:

```sh
# Install icnsutils if needed: sudo apt install icnsutils
icns2png -x source.icns            # extracts all frames as source_NxN.png
# Pick the largest (typically 512x512 or 1024x1024)
```

If `icns2png` is not available, use `sips` (macOS) or convert manually:

```sh
# On macOS:
sips -s format png source.icns --out source.png --resampleWidth 1024
```

Save the high-res source PNG to `microsoft/icons/<app-name>.png` for reference.

### Step 2 — Generate all required sizes

For each icon directory in the app, resize the source to every size that already exists there:

```sh
APP_DIR="microsoft/edge-pwas/<app-id>"
SOURCE="microsoft/icons/<app-name>-hires.png"

for icon_dir in "$APP_DIR/Icons" "$APP_DIR/Trusted Icons/Icons" "$APP_DIR/Icons Maskable"; do
  [ -d "$icon_dir" ] || continue
  for existing in "$icon_dir"/*.png; do
    [ -e "$existing" ] || continue
    size=$(basename "$existing" .png)
    convert "$SOURCE" -resize "${size}x${size}" "$icon_dir/${size}.png"
  done
done
```

### Step 3 — Add padding for GNOME dock consistency

macOS-style squircle icons fill the entire canvas edge-to-edge. Native GNOME icons have built-in padding, so unpadded icons appear ~12% larger in the dock.

Shrink the icon content to **88%** of the canvas and center it on a transparent background:

```sh
for icon_dir in "$APP_DIR/Icons" "$APP_DIR/Trusted Icons/Icons" "$APP_DIR/Icons Maskable"; do
  [ -d "$icon_dir" ] || continue
  for png in "$icon_dir"/*.png; do
    [ -e "$png" ] || continue
    size=$(basename "$png" .png)
    inner=$(( size * 88 / 100 ))
    convert "$png" \
      -resize "${inner}x${inner}" \
      -gravity center \
      -background none \
      -extent "${size}x${size}" \
      "$png"
  done
done
```

### Step 4 — Verify

```sh
# Check that dimensions are correct
for png in "$APP_DIR"/Icons/*.png; do
  identify "$png"
done

# Visually inspect a representative size
# (open the 128px icon in an image viewer)
```

After replacing icons, **restart Edge** or **log out and back in** for the dock to pick up the changes.

## Known PWA app IDs

| App | ID |
|---|---|
| Microsoft Teams | `ompifgpmddkgmclendfeacglnodjjndh` |
| Outlook | `faolnafnngnfdaknnbpnkhgohbobgegn` |
| Microsoft OneDrive | `beplpalihhkbdaocmobeinjjbmagdkig` |
| Spotify | `pjibgclleladliembfgfagdaldikeohf` |

## Key lessons

- **Always update ALL icon directories** — Edge reads from `Trusted Icons/Icons/` for the dock, not just `Icons/`.
- **88% is the right shrink factor** for matching GNOME's native icon visual weight with macOS squircle icons.
- **Preserve existing sizes** per directory; different apps have different size sets.
- **Use `-background none`** to keep transparency when adding padding.
