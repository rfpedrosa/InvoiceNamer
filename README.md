# Invoice Namer

Automatically rename and organize invoice/receipt images using OCR (Optical Character Recognition). Extracts dates from invoice text and categorizes by content type for easy accounting and archival.

**Example:** `IMG_1234.jpg` → `2024-03-15_Amazon.jpg`

## Features

- 🔍 **Intelligent OCR** — Uses Apple Vision framework (same as Live Text on iPhone/Mac) for best accuracy, with Tesseract as fallback
- 📅 **Date Extraction** — Automatically finds dates in receipts (supports `YYYY-MM-DD` and `DD/MM/YYYY` formats)
- 🏷️ **Auto-Categorization** — Detects invoice types based on content keywords
- 🔒 **Safe Renaming** — Prevents file overwrites with automatic suffix increments (`_1`, `_2`, etc.)
- 🧪 **Dry Run Mode** — Preview changes before applying them
- 🖼️ **Image Preprocessing** — Optional ImageMagick enhancement for low-quality/blurry images
- 🌍 **Multi-Language** — Optimized for Portuguese and English text

## Prerequisites

- **macOS** (required for Apple Vision OCR)
- **Homebrew** — [Install here](https://brew.sh/)
- **Zsh shell** (default on macOS)

## Installation

### 1. Clone or Download

```bash
cd ~/Desktop  # or your preferred location
git clone https://github.com/yourusername/InvoiceNamer.git
cd InvoiceNamer
```

### 2. Make Scripts Executable

```bash
chmod +x invoice_namer.sh
chmod +x vision_ocr.py
```

### 3. First Run (Auto-Install Dependencies)

The script automatically installs required dependencies on first run:

```bash
./invoice_namer.sh ~/path/to/invoices --dry-run
```

This will install:
- Tesseract OCR + Portuguese language pack
- Python 3.11–3.13 (via Homebrew)
- `pyobjc-framework-Vision` (in isolated virtualenv)

**Optional:** ImageMagick (only if you use `--preprocess`)
```bash
brew install imagemagick
```

## Usage

### Basic Syntax

```bash
./invoice_namer.sh <directory_path> [options]
```

### Options

| Flag | Description |
|------|-------------|
| `--dry-run` | Preview changes without renaming files |
| `--preprocess` | Enable ImageMagick preprocessing for blurry/low-res images |
| `-h, --help` | Show usage information |

### Examples

**Preview what would happen (recommended first step):**
```bash
./invoice_namer.sh ~/Desktop/Invoices --dry-run
```

**Actually rename files:**
```bash
./invoice_namer.sh ~/Desktop/Invoices
```

**Enable preprocessing for poor quality images:**
```bash
./invoice_namer.sh ~/Desktop/Invoices --preprocess
```

**Combine options:**
```bash
./invoice_namer.sh ~/Desktop/Invoices --dry-run --preprocess
```

## How It Works

### 1. OCR Engine Selection

The script automatically chooses the best available OCR engine:

| Engine | Quality | Speed | Notes |
|--------|---------|-------|-------|
| **Apple Vision** | ⭐⭐⭐⭐⭐ | Fast | Same as iPhone Live Text; requires `vision_ocr.py` |
| **Tesseract** | ⭐⭐ | Medium | Open-source fallback |

### 2. Date Extraction Priority

1. **YYYY-MM-DD** format (e.g., `2024-03-15`)
2. **DD/MM/YYYY** format (e.g., `15/03/2024`) — converted to YYYY-MM-DD
3. **File creation date** — used if no date found in text

### 3. Type Detection Keywords

Files are categorized based on OCR text content:

| Type | Keywords Detected |
|------|-------------------|
| `Amazon` | `amazon` |
| `Gasoleo` | `combustivel`, `gasoleo`, `galp`, `prio` |
| `Software` | `adobe` |
| `Refeicao` | `restaurant`, `auschan`, `mercadona` |
| `Recibo` | `total` + `iva` (both must appear) |
| `Misc` | Default if no keywords match |

### 4. File Naming Convention

**Format:** `YYYY-MM-DD_Type[_N].ext`

**Examples:**
- `2024-03-15_Amazon.png`
- `2024-03-15_Gasoleo.jpg`
- `2024-03-15_Refeicao_1.png` ← Collision avoidance suffix

## Supported Image Formats

- `.png`, `.PNG`
- `.jpg`, `.JPG`
- `.jpeg`, `.JPEG`

## Adding Custom Categories

Edit the type detection section in `invoice_namer.sh`:

```bash
# 3. DETERMINE TYPE (Based on content keywords)
if echo "$file_content" | grep -q "amazon"; then
    inv_type="Amazon"
elif echo "$file_content" | grep -qE "your|keywords|here"; then
    inv_type="YourCategory"
# ... rest of conditions
```

Add your custom keywords using `grep` patterns:
- Single keyword: `grep -q "keyword"`
- Multiple keywords (OR): `grep -qE "keyword1|keyword2|keyword3"`

## Troubleshooting

### "Cannot locate a working compiler" Error

This happens if trying to build Python packages without Xcode Command Line Tools:

```bash
xcode-select --install
```

### "Vision OCR not working"

Verify `vision_ocr.py` is in the same directory as the shell script:

```bash
ls -l invoice_namer.sh vision_ocr.py
```

### Poor OCR Accuracy

1. **Try `--preprocess` mode** — enables image enhancement
2. **Check image quality** — very low resolution or heavily compressed images may fail
3. **Verify language** — script is optimized for Portuguese/English

### "Python 3.14 not supported" Error

The script automatically installs Python 3.13. If you get this error, manually install:

```bash
brew install python@3.13
```

### Files Not Being Renamed

Check the dry-run output first:

```bash
./invoice_namer.sh ~/Desktop/Invoices --dry-run
```

Look for:
- `[Would Rename]` — file will be renamed
- `[Skipped]` — file already has correct name
- Check OCR output to verify text is being extracted

## Project Structure

```
.
├── invoice_namer.sh      # Main shell script
├── vision_ocr.py         # Apple Vision OCR helper
├── README.md             # Documentation
├── .gitignore            # Git ignore rules
└── .invoice_ocr_venv/    # Python virtualenv (auto-created, gitignored)
```

## Notes

- **Safe Operation:** The script never deletes files, only renames them
- **Collision Handling:** If target filename exists, appends `_1`, `_2`, etc., gitignored)
- **Performance:** Apple Vision processes ~2-5 images/second; Tesseract is slower

## Version Control

The `.gitignore` file excludes:
- `.invoice_ocr_venv/` (virtual environment)
- Python cache files
- Temporary files and system files (.DS_Store, etc.)
- Editor/IDE configuration files

## License

MIT License - feel free to use and modify for your needs.

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/improvement`)
3. Commit your changes (`git commit -am 'Add new feature'`)
4. Push to the branch (`git push origin feature/improvement`)
5. Submit a pull request with clear description
[Your name/contact]

---

**Tip:** Run with `--dry-run` first to preview changes before actually renaming files!
