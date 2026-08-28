#!/bin/zsh

# ==========================================
# MAC IMAGE INVOICE ORGANIZER (CLI VERSION)
# ==========================================

# 1. PARSE ARGUMENTS
DRY_RUN=false
TARGET_DIR=""
PREPROCESS=false
SUFFIX=""

# Function to print usage
usage() {
    echo "Usage: $0 <directory_path> [--dry-run] [--preprocess] [--suffix <suffix>]"
    echo "Example: $0 ~/Desktop/Invoices --dry-run"
    echo "         $0 ~/Desktop/Invoices --suffix CompanyName"
    exit 1
}

# Loop through all arguments provided
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift # Remove --dry-run from processing
      ;;
    --preprocess)
      PREPROCESS=true
      shift # Remove --preprocess from processing
      ;;
    --suffix)
      SUFFIX="$2"
      shift 2 # Remove --suffix and its value
      ;;
    -h|--help)
      usage
      ;;
    *)
      # If TARGET_DIR is empty, assume this argument is the folder
      if [[ -z "$TARGET_DIR" ]]; then
        TARGET_DIR="$1"
      else
        echo "❌ Error: Multiple directories specified or unknown argument: '$1'"
        usage
      fi
      shift # Remove the directory argument from processing
      ;;
  esac
done

# Check if a directory was provided
if [[ -z "$TARGET_DIR" ]]; then
    echo "❌ Error: No directory specified."
    usage
fi

# ==========================================

echo "--- Starting Smart Invoice Organizer ---"

# --- PART 2: DEPENDENCY CHECK ---
echo "🔍 Checking dependencies..."

if ! command -v brew &> /dev/null; then
    echo "❌ Error: Homebrew is not installed."
    echo "   Please install it first: https://brew.sh/"
    exit 1
fi

if ! command -v tesseract &> /dev/null; then
    echo "⚠️  Tesseract (OCR) not found. Installing via Homebrew..."
    brew install tesseract
    echo "✅ Tesseract installed."
else
    echo "✅ Tesseract is ready."
fi

# Check for Apple Vision OCR (best quality — same engine as Live Text)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VISION_HELPER="$SCRIPT_DIR/vision_ocr.py"
DATE_HELPER="$SCRIPT_DIR/extract_date.py"
USE_VISION=false

if [[ ! -f "$DATE_HELPER" ]]; then
    echo "❌ Error: extract_date.py not found next to script."
    exit 1
fi

# pyobjc ships wheels for Python 3.9–3.13; newer pyobjc also builds on 3.14,
# but it is tried last. Prefer specific versioned Homebrew Pythons in order.
BREW_BIN="$(brew --prefix)/bin"
PYTHON3=""
for ver in python3.13 python3.12 python3.11 python3.14; do
    if [[ -x "$BREW_BIN/$ver" ]]; then
        PYTHON3="$BREW_BIN/$ver"
        break
    fi
done

# If none found, install python@3.13 explicitly
if [[ -z "$PYTHON3" ]]; then
    echo "⚠️  No compatible Homebrew Python (3.11–3.14) found. Installing python@3.13..."
    brew install python@3.13
    PYTHON3="$BREW_BIN/python3.13"
fi

echo "ℹ️  Using Python: $("$PYTHON3" --version 2>&1)"

# Use a dedicated venv to avoid PEP 668 "externally managed" restrictions.
# A venv holds only a symlink to the Python it was built from, so a Homebrew
# upgrade or `brew cleanup` can leave it pointing at a binary that no longer
# exists. Existing on disk proves nothing — run it before trusting it.
VENV_DIR="$SCRIPT_DIR/.invoice_ocr_venv"
VENV_PYTHON="$VENV_DIR/bin/python3"

if [[ -d "$VENV_DIR" ]] && ! "$VENV_PYTHON" -c "pass" 2>/dev/null; then
    echo "⚠️  Existing venv is stale (its Python was removed or upgraded). Rebuilding..."
    rm -rf "$VENV_DIR"
fi

if [[ ! -d "$VENV_DIR" ]]; then
    echo "ℹ️  Creating virtual environment at $VENV_DIR..."
    "$PYTHON3" -m venv "$VENV_DIR"
fi

VENV_OK=false
if "$VENV_PYTHON" -c "pass" 2>/dev/null; then
    VENV_OK=true
else
    echo "⚠️  Could not build a working venv. Falling back to $PYTHON3 directly."
fi

if [[ "$VENV_OK" = true ]] && [[ -f "$VISION_HELPER" ]]; then
    if "$VENV_PYTHON" -c "import Vision" 2>/dev/null; then
        USE_VISION=true
        echo "✅ Apple Vision OCR is ready (best quality)."
    else
        echo "⚠️  pyobjc-framework-Vision not found. Installing into venv..."
        "$VENV_PYTHON" -m pip install --upgrade pip --quiet 2>/dev/null
        # Surface pip's own error instead of swallowing it — a silent failure
        # here is what silently downgrades every later scan to Tesseract.
        if ! "$VENV_PYTHON" -m pip install pyobjc-framework-Vision --quiet; then
            echo "   └─ pip install failed (see output above)."
        fi
        if "$VENV_PYTHON" -c "import Vision" 2>/dev/null; then
            USE_VISION=true
            echo "✅ Apple Vision OCR installed and ready."
        else
            echo "⚠️  Could not install Apple Vision bindings. Falling back to Tesseract."
        fi
    fi
elif [[ ! -f "$VISION_HELPER" ]]; then
    echo "⚠️  vision_ocr.py not found next to script. Falling back to Tesseract."
fi

# vision_ocr.py needs the venv (pyobjc lives there); extract_date.py is
# stdlib-only, so it stays on $PYTHON3 and keeps working even if the venv does not.
if [[ "$VENV_OK" = true ]]; then
    VISION_PYTHON="$VENV_PYTHON"
else
    VISION_PYTHON="$PYTHON3"
fi

if ! command -v convert &> /dev/null; then
    if [ "$PREPROCESS" = true ]; then
        echo "⚠️  ImageMagick not found. Installing via Homebrew..."
        brew install imagemagick
        echo "✅ ImageMagick installed."
    else
        echo "ℹ️  ImageMagick not found (skipping, use --preprocess to enable)."
    fi
else
    if [ "$PREPROCESS" = true ]; then
        echo "✅ ImageMagick is ready."
    else
        echo "ℹ️  ImageMagick available but not used (pass --preprocess to enable)."
    fi
fi

if ! tesseract --list-langs 2>/dev/null | grep -q "^por$"; then
    echo "⚠️  Portuguese language data not found. Installing tesseract-lang..."
    brew install tesseract-lang
    echo "✅ Tesseract language packs installed."
else
    echo "✅ Portuguese language data is ready."
fi

echo "----------------------------------"
echo "Target Directory: $TARGET_DIR"
if [ "$DRY_RUN" = true ]; then
    echo "⚠️  DRY RUN MODE: No files will be renamed."
else
    echo "✅  LIVE MODE: Files WILL be renamed."
fi
if [ "$PREPROCESS" = true ]; then
    echo "🖼️  PREPROCESS MODE: ImageMagick preprocessing enabled."
fi
echo "----------------------------------"

if [ ! -d "$TARGET_DIR" ]; then
    echo "❌ Error: Directory '$TARGET_DIR' does not exist."
    exit 1
fi

# --- PART 3: PROCESSING FILES ---

# Loop through image files only (png, jpg, jpeg)
# (N) is a Zsh flag that prevents errors if no files match
for file in "$TARGET_DIR"/*.{png,jpg,jpeg,PNG,JPG,JPEG}(N); do

    filename=$(basename "$file")
    ext="${file##*.}"

    echo "Processing: $filename..."

    # 1. EXTRACT TEXT CONTENT (OCR)
    if [ "$USE_VISION" = true ]; then
        # Apple Vision framework — best quality, handles real-world photos well
        if [ "$PREPROCESS" = true ]; then
            tmp_img=$(mktemp /tmp/invoice_preprocess_XXXXXX.png)
            convert "$file" -colorspace Gray -resize 200% -normalize -sharpen 0x1.5 "$tmp_img" 2>/dev/null
            file_content=$("$VISION_PYTHON" "$VISION_HELPER" "$tmp_img" 2>/dev/null | tr '[:upper:]' '[:lower:]')
            rm -f "$tmp_img"
        else
            file_content=$("$VISION_PYTHON" "$VISION_HELPER" "$file" 2>/dev/null | tr '[:upper:]' '[:lower:]')
        fi
    else
        # Tesseract fallback
        if [ "$PREPROCESS" = true ]; then
            tmp_img=$(mktemp /tmp/invoice_preprocess_XXXXXX.png)
            convert "$file" -colorspace Gray -resize 200% -normalize -sharpen 0x1.5 "$tmp_img" 2>/dev/null
            ocr_source="$tmp_img"
        else
            ocr_source="$file"
        fi
        file_content=$(tesseract "$ocr_source" - --oem 1 --psm 6 -l por+eng 2>/dev/null | tr '[:upper:]' '[:lower:]')
        [ "$PREPROCESS" = true ] && rm -f "$tmp_img"
    fi
    if [[ -z "${file_content//[[:space:]]/}" ]]; then
        echo "   ⚠️  OCR returned no text — try --preprocess or a sharper photo."
    fi
    echo "   -> OCR Content: $file_content"

    # 2. FIND DATE
    # extract_date.py collects every date printed on the receipt (terminal
    # timestamp, emission date, ...) and returns the best-supported one.
    extracted_date=$(echo "$file_content" | "$PYTHON3" "$DATE_HELPER" 2>/dev/null)

    # Fall back to the file creation date when the document yields nothing
    if [ -z "$extracted_date" ]; then
        echo "   -> No date found in text. Using file creation date."
        file_date=$(stat -f "%SB" -t "%Y-%m-%d" "$file")
    else
        echo "   -> Found date in document: $extracted_date"
        file_date="$extracted_date"
    fi

    # 3. DETERMINE TYPE (Based on content keywords)
    # Short brand names need word boundaries — "bp" otherwise matches OCR noise
    # in the middle of a word. A price per litre is the surest sign of fuel.
    if echo "$file_content" | grep -qiE "combustivel|gasoleo|gasolina|galp|prio|repsol|shell|\bbp\b|cepsa|posto de abastecimento|eur/l|€/l"; then
        inv_type="Gasoleo"
    elif echo "$file_content" | grep -qiE "farmacia|farmácia|parafarmacia"; then
        inv_type="Farmacia"
    elif echo "$file_content" | grep -qiE "adobe|microsoft|google play|app store|netflix|spotify|github|aws |amazon web"; then
        inv_type="Software"
    #elif echo "$file_content" | grep -qiE "amazon\."; then
    #    inv_type="Amazon"
    # "cp" (Comboios de Portugal) is too short to match on its own — it turns up
    # inside OCR noise on unrelated receipts, so require the full name.
    elif echo "$file_content" | grep -qiE "uber|bolt (taxa|viagem)|táxi|taxi|comboios|\bmetro\b|autocarro|flixbus|renfe"; then
        inv_type="Transporte"
    elif echo "$file_content" | grep -qiE "parque|estacionamento|emel|parking"; then
        inv_type="Estacionamento"
    elif echo "$file_content" | grep -qiE "hotel|hostel|airbnb|booking\.com|alojamento"; then
        inv_type="Alojamento"
    elif echo "$file_content" | grep -qiE "mercad|continent|pingo doc|lidl|aldi|miniprec|jumbo|intermarch|worten|fnac|leroy mer|ikea|decathlon|irmadona|supermerc"; then
        inv_type="Refeicao"
    elif echo "$file_content" | grep -qiE "restaurante|pastelaria|snack.bar|tasca|taberna|pizzar|hamburguer|mcdonald|burger king|kfc|subway|nando|sushi"; then
        inv_type="Refeicao"
    elif echo "$file_content" | grep -qiE "fatura simpl|recibo|total.*iva|iva.*total"; then
        inv_type="Refeicao"
    else
        inv_type="Refeicao"
    fi

    # 4. CONSTRUCT NEW NAME
    clean_original="${filename%.*}"
    clean_original="${clean_original// /_}"

    if [ ! -z "$SUFFIX" ]; then
        base_name="${file_date}_${inv_type}_${SUFFIX}"
    else
        base_name="${file_date}_${inv_type}"
    fi
    new_name="${base_name}.${ext}"
    new_path="$TARGET_DIR/$new_name"

    # Avoid overwriting existing files — append _1, _2, ... until name is free
    counter=1
    while [[ -f "$new_path" ]] && [[ "$new_path" != "$file" ]]; do
        new_name="${base_name}_${counter}.${ext}"
        new_path="$TARGET_DIR/$new_name"
        (( counter++ ))
    done

    # 5. EXECUTE RENAME
    if [ "$file" != "$new_path" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo "   [Would Rename] -> $new_name"
        else
            mv "$file" "$new_path"
            echo "   [Renamed] -> $new_name"
        fi
    else
        echo "   [Skipped] Name is already correct."
    fi
    echo ""

done

echo "Processing complete."