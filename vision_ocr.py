#!/usr/bin/env python3
"""
Apple Vision OCR Helper
Uses macOS native Vision framework for text recognition
"""

import sys
from pathlib import Path
from Vision import (
    VNRecognizeTextRequest,
    VNImageRequestHandler,
)
from Quartz import NSURL

# CGImagePropertyOrientation values worth trying.
# Phone photos of receipts often have no EXIF orientation tag, so the receipt
# can sit sideways or upside down in the frame. Vision does not auto-rotate,
# so we try each 90 degree step and keep the most confident reading.
ORIENTATIONS = (
    1,  # up
    6,  # rotated 90 CW
    3,  # rotated 180
    8,  # rotated 90 CCW
)

# Vision reports confidence in coarse steps; lines it is unsure about come back
# noticeably lower. Text read at the wrong angle is dominated by those.
CONFIDENT = 0.5


def _recognize(image_path: str, orientation: int):
    """Run one OCR pass at a given orientation. Returns (score, text)."""
    file_url = NSURL.fileURLWithPath_(image_path)

    request = VNRecognizeTextRequest.alloc().init()
    request.setRecognitionLevel_(1)  # 1 = accurate (vs. 0 = fast)
    request.setRecognitionLanguages_(["pt-PT", "pt-BR", "en-US"])
    request.setUsesLanguageCorrection_(True)

    handler = VNImageRequestHandler.alloc().initWithURL_orientation_options_(
        file_url, orientation, None
    )
    success = handler.performRequests_error_([request], None)

    if not success[0]:
        print("Error: Vision request failed", file=sys.stderr)
        return 0.0, ""

    results = request.results()
    if not results:
        return 0.0, ""

    score = 0.0
    text_lines = []
    for observation in results:
        # Get the top candidate for each text observation
        top_candidate = observation.topCandidates_(1)[0]
        line = top_candidate.string()
        text_lines.append(line)
        # Only confidently-read text counts towards the score — a receipt read
        # at the wrong angle still produces plenty of low-confidence garbage.
        if top_candidate.confidence() >= CONFIDENT:
            score += len(line) * top_candidate.confidence()

    return score, "\n".join(text_lines)


def recognize_text(image_path: str) -> str:
    """
    Perform OCR on an image using Apple's Vision framework, trying every
    90 degree orientation and returning the best-scoring reading.

    Args:
        image_path: Path to the image file

    Returns:
        Extracted text as a single string
    """
    best_score, best_text, best_orientation = 0.0, "", ORIENTATIONS[0]

    for orientation in ORIENTATIONS:
        score, text = _recognize(image_path, orientation)
        if score > best_score:
            best_score, best_text, best_orientation = score, text, orientation

    print(
        f"Vision: orientation {best_orientation} (score {best_score:.0f})",
        file=sys.stderr,
    )
    return best_text


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: vision_ocr.py <image_path>", file=sys.stderr)
        sys.exit(1)

    image_path = sys.argv[1]

    if not Path(image_path).exists():
        print(f"Error: File not found: {image_path}", file=sys.stderr)
        sys.exit(1)

    text = recognize_text(image_path)
    print(text)
