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
from Quartz import (
    CIImage,
    NSURL,
)


def recognize_text(image_path: str) -> str:
    """
    Perform OCR on an image using Apple's Vision framework.
    
    Args:
        image_path: Path to the image file
        
    Returns:
        Extracted text as a single string
    """
    file_url = NSURL.fileURLWithPath_(image_path)
    ci_image = CIImage.imageWithContentsOfURL_(file_url)
    
    if ci_image is None:
        print(f"Error: Could not load image from {image_path}", file=sys.stderr)
        return ""
    
    # Create a text recognition request
    request = VNRecognizeTextRequest.alloc().init()
    request.setRecognitionLevel_(1)  # 1 = accurate (vs. 0 = fast)
    request.setUsesLanguageCorrection_(True)
    
    # Create request handler and perform the request
    handler = VNImageRequestHandler.alloc().initWithCIImage_options_(ci_image, None)
    success = handler.performRequests_error_([request], None)
    
    if not success[0]:
        print(f"Error: Vision request failed", file=sys.stderr)
        return ""
    
    # Extract recognized text
    results = request.results()
    if not results:
        return ""
    
    text_lines = []
    for observation in results:
        # Get the top candidate for each text observation
        top_candidate = observation.topCandidates_(1)[0]
        text_lines.append(top_candidate.string())
    
    return "\n".join(text_lines)


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
