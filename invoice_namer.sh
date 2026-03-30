#!/bin/zsh

# ==========================================
# MAC IMAGE INVOICE ORGANIZER (CLI VERSION)
# ==========================================

# 1. PARSE ARGUMENTS
DRY_RUN=false
TARGET_DIR=""
PREPROCESS=false

# Function to print usage
usage() {
    echo "Usage: $0 <directory_path> [--dry-run] [--preprocess]"
    echo "Example: $0 ~/Desktop/Invoices --dry-run"
    echo "         $0 ~/Desktop/Invoices --preprocess"
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
USE_VISION=false

# pyobjc supports Python 3.8–3.13 only (3.14+ not yet supported).
# Prefer specific versioned Homebrew Pythons in order, avoiding 3.14+.
BREW_BIN="$(brew --prefix)/bin"
PYTHON3=""
for ver in python3.13 python3.12 python3.11; do
    if [[ -x "$BREW_BIN/$ver" ]]; then
        PYTHON3="$BREW_BIN/$ver"
        break
    fi
done

# If none found, install python@3.13 explicitly
if [[ -z "$PYTHON3" ]]; then
    echo "⚠️  No compatible Homebrew Python (3.11–3.13) found. Installing python@3.13..."
    brew install python@3.13
    PYTHON3="$BREW_BIN/python3.13"
fi

echo "ℹ️  Using Python: $("$PYTHON3" --version 2>&1)"

# Use a dedicated venv to avoid PEP 668 "externally managed" restrictions
VENV_DIR="$SCRIPT_DIR/.invoice_ocr_venv"
if [[ ! -d "$VENV_DIR" ]]; then
    echo "ℹ️  Creating virtual environment at $VENV_DIR..."
    "$PYTHON3" -m venv "$VENV_DIR"
fi
VENV_PYTHON="$VENV_DIR/bin/python3"

if [[ -f "$VISION_HELPER" ]]; then
    if "$VENV_PYTHON" -c "import Vision" 2>/dev/null; then
        USE_VISION=true
        echo "✅ Apple Vision OCR is ready (best quality)."
    else
        echo "⚠️  pyobjc-framework-Vision not found. Installing into venv..."
        "$VENV_PYTHON" -m pip install pyobjc-framework-Vision --quiet
        if "$VENV_PYTHON" -c "import Vision" 2>/dev/null; then
            USE_VISION=true
            echo "✅ Apple Vision OCR installed and ready."
        else
            echo "⚠️  Could not install Apple Vision bindings. Falling back to Tesseract."
        fi
    fi
else
    echo "⚠️  vision_ocr.py not found next to script. Falling back to Tesseract."
fi
# All Vision calls use the venv python
PYTHON3="$VENV_PYTHON"

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
            file_content=$("$PYTHON3" "$VISION_HELPER" "$tmp_img" 2>/dev/null | tr '[:upper:]' '[:lower:]')
            rm -f "$tmp_img"
        else
            file_content=$("$PYTHON3" "$VISION_HELPER" "$file" 2>/dev/null | tr '[:upper:]' '[:lower:]')
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
    echo "   -> OCR Content: $file_content"

    # 2. FIND DATE (REGEX)
    extracted_date=""

    # Strip stray dots/spaces OCR inserts inside numbers (e.g. "2.026-0.4-12" -> "2026-04-12")
    clean_content=$(echo "$file_content" | sed 's/\([0-9]\)[. ]\([0-9]\)/\1\2/g; s/\([0-9]\)[. ]\([0-9]\)/\1\2/g')

    # Priority 1: YYYY-MM-DD (also catches terminal timestamps like 2026-03-2113:28 via head)
    extracted_date=$(echo "$clean_content" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -n 1)

    # Priority 2: DD/MM/YYYY or DD-MM-YYYY or DD.MM.YYYY -> convert to YYYY-MM-DD
    # (requires 4-digit year at end so terminal lines like "26-03-27 20:48" don't match)
    if [ -z "$extracted_date" ]; then
        alt_date=$(echo "$clean_content" | grep -oE '[0-9]{2}[-/.][0-9]{2}[-/.][0-9]{4}' | head -n 1)
        if [ ! -z "$alt_date" ]; then
            extracted_date=$(echo "$alt_date" | sed 's|[/.]|-|g' | awk -F- '{print $3"-"$2"-"$1}')
        fi
    fi

    # Priority 3: YY-MM-DD followed by time (e.g. "26-03-13 21:18") -> prepend century
    if [ -z "$extracted_date" ]; then
        short_date=$(echo "$clean_content" | grep -oE '[0-9]{2}[-/.][0-9]{2}[-/.][0-9]{2} *[0-9]{2}[;:][0-9]{2}' | head -n 1)
        if [ ! -z "$short_date" ]; then
            date_part=$(echo "$short_date" | grep -oE '^[0-9]{2}[-/.][0-9]{2}[-/.][0-9]{2}')
            extracted_date=$(echo "$date_part" | sed 's|[/.]|-|g' | awk -F- '{print "20"$1"-"$2"-"$3}')
        fi
    fi

    # Priority 4: Partial date -MM-DD or MM-DD followed by time (OCR truncated year)
    # Assumes current year
    if [ -z "$extracted_date" ]; then
        partial_date=$(echo "$clean_content" | grep -oE '[-]?[0-9]{2}-[0-9]{2} *[0-9]{2}[;:][0-9]{2}' | head -n 1)
        if [ ! -z "$partial_date" ]; then
            mm_dd=$(echo "$partial_date" | grep -oE '[0-9]{2}-[0-9]{2}' | head -n 1)
            current_year=$(date +%Y)
            month="${mm_dd%%-*}"
            day="${mm_dd##*-}"
            if [ "$month" -ge 1 ] && [ "$month" -le 12 ] && [ "$day" -ge 1 ] && [ "$day" -le 31 ]; then
                extracted_date="${current_year}-${month}-${day}"
            fi
        fi
    fi

    # Priority 5: File Creation Date
    if [ -z "$extracted_date" ]; then
        echo "   -> No date found in text. Using file creation date."
        file_date=$(stat -f "%SB" -t "%Y-%m-%d" "$file")
    else
        echo "   -> Found date in document: $extracted_date"
        file_date="$extracted_date"
    fi

    # 3. DETERMINE TYPE (Based on content keywords)
    if echo "$file_content" | grep -qiE "combustivel|gasoleo|gasolina|galp|prio|repsol|shell|bp |cepsa|posto de abastecimento"; then
        inv_type="Gasoleo"
    elif echo "$file_content" | grep -qiE "farmacia|farmácia|parafarmacia"; then
        inv_type="Farmacia"
    elif echo "$file_content" | grep -qiE "adobe|microsoft|google play|app store|netflix|spotify|github|aws |amazon web"; then
        inv_type="Software"
    #elif echo "$file_content" | grep -qiE "amazon\."; then
    #    inv_type="Amazon"
    elif echo "$file_content" | grep -qiE "uber|bolt (taxa|viagem)|táxi|taxi|cp |comboios|metro |autocarro|flixbus|renfe"; then
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

    base_name="${file_date}_${inv_type}"
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