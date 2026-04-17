#requires -Version 5.1
<#
.SYNOPSIS
    NDLOCR-Lite Portable Build Script
.DESCRIPTION
    Automatically builds a self-contained NDLOCR-Lite PDF OCR tool
    for Windows 11 users who do not have Python installed.
    Run this script once to generate the NDLOCR-Lite-Portable folder.
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# ---- URLs ----
$pythonZipUrl = 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip'
$getPipUrl    = 'https://bootstrap.pypa.io/get-pip.py'
$ndlZipUrl    = 'https://github.com/ndl-lab/ndlocr-lite/archive/refs/heads/master.zip'

# ---- Paths ----
$portableDir = Join-Path $PSScriptRoot 'NDLOCR-Lite-Portable'
$pythonDir   = Join-Path $portableDir 'python'
$ndlDir      = Join-Path $portableDir 'ndlocr-lite'
$pythonExe   = Join-Path $pythonDir 'python.exe'

# ---- Encodings ----
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Write-Step([string]$msg) {
    Write-Host ''
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Fail([string]$msg) {
    Write-Host "[ERROR] $msg" -ForegroundColor Red
    exit 1
}

# ===== Step 0: Prepare output folder =====
Write-Step 'Preparing output folder...'
if (Test-Path $portableDir) {
    Write-Host '  Removing existing NDLOCR-Lite-Portable folder...'
    Remove-Item $portableDir -Recurse -Force
}
New-Item -ItemType Directory -Path $portableDir | Out-Null
Write-Host "  Created: $portableDir"

# ===== Step 1: Download and extract Python Embeddable =====
Write-Step 'Step 1: Downloading Python 3.12.10 embeddable...'
$pythonZip = Join-Path $env:TEMP 'python-3.12.10-embed-amd64.zip'
try {
    Invoke-WebRequest -Uri $pythonZipUrl -OutFile $pythonZip -UseBasicParsing
} catch {
    Fail "Failed to download Python: $_"
}
Write-Host '  Download complete. Extracting...'
New-Item -ItemType Directory -Path $pythonDir | Out-Null
Expand-Archive -Path $pythonZip -DestinationPath $pythonDir -Force
Write-Host '  Extraction complete.'

# Edit python312._pth to enable import site
$pthFile = Join-Path $pythonDir 'python312._pth'
if (-not (Test-Path $pthFile)) {
    Fail 'python312._pth not found in extracted archive.'
}
$pthContent = [System.IO.File]::ReadAllText($pthFile, $utf8NoBom)
if ($pthContent -match '(?m)^#import site') {
    $pthContent = $pthContent -replace '(?m)^#import site', 'import site'
    [System.IO.File]::WriteAllText($pthFile, $pthContent, $utf8NoBom)
    Write-Host '  python312._pth patched (import site enabled).'
} else {
    Write-Host '  python312._pth: import site already enabled.'
}

# ===== Step 2: Install pip =====
Write-Step 'Step 2: Installing pip...'
$getPipScript = Join-Path $env:TEMP 'get-pip.py'
try {
    Invoke-WebRequest -Uri $getPipUrl -OutFile $getPipScript -UseBasicParsing
} catch {
    Fail "Failed to download get-pip.py: $_"
}
Write-Host '  Running get-pip.py...'
& $pythonExe $getPipScript
if ($LASTEXITCODE -ne 0) {
    Fail 'pip installation failed.'
}
Write-Host '  pip installed.'

# ===== Step 3: Download NDLOCR-Lite =====
Write-Step 'Step 3: Downloading NDLOCR-Lite...'
$ndlZip = Join-Path $env:TEMP 'ndlocr-lite-master.zip'
try {
    Invoke-WebRequest -Uri $ndlZipUrl -OutFile $ndlZip -UseBasicParsing
} catch {
    Fail "Failed to download NDLOCR-Lite: $_"
}
Write-Host '  Download complete. Extracting...'
$ndlTemp = Join-Path $env:TEMP 'ndlocr-lite-extract'
if (Test-Path $ndlTemp) { Remove-Item $ndlTemp -Recurse -Force }
Expand-Archive -Path $ndlZip -DestinationPath $ndlTemp -Force

$ndlMaster = Join-Path $ndlTemp 'ndlocr-lite-master'
if (-not (Test-Path $ndlMaster)) {
    Fail 'ndlocr-lite-master folder not found in extracted archive.'
}
Move-Item $ndlMaster $ndlDir
Write-Host "  NDLOCR-Lite placed at: $ndlDir"

# ===== Step 4: Install dependencies =====
Write-Step 'Step 4: Installing dependencies...'
$reqFile = Join-Path $ndlDir 'requirements.txt'
if (-not (Test-Path $reqFile)) {
    Fail 'requirements.txt not found. Check NDLOCR-Lite download.'
}

# Generate requirements_cli.txt excluding flet and pypdfium2
$reqLines      = [System.IO.File]::ReadAllLines($reqFile, $utf8NoBom)
$filteredLines = $reqLines | Where-Object {
    $_ -notmatch '^\s*flet' -and $_ -notmatch '^\s*pypdfium2'
}
$reqCliFile = Join-Path $ndlDir 'requirements_cli.txt'
[System.IO.File]::WriteAllLines($reqCliFile, [string[]]$filteredLines, $utf8NoBom)
Write-Host '  requirements_cli.txt generated (flet and pypdfium2 excluded).'

Write-Host '  Installing packages (this may take several minutes)...'
& $pythonExe -m pip install -r $reqCliFile
if ($LASTEXITCODE -ne 0) {
    Fail 'Dependency installation failed.'
}

Write-Host '  Installing pymupdf...'
& $pythonExe -m pip install pymupdf
if ($LASTEXITCODE -ne 0) {
    Fail 'pymupdf installation failed.'
}
Write-Host '  All dependencies installed.'

# ===== Step 5: Generate ocr_batch_pdf.py =====
Write-Step 'Step 5: Generating ocr_batch_pdf.py...'

$srcDir = Join-Path $ndlDir 'src'
if (-not (Test-Path $srcDir)) {
    New-Item -ItemType Directory -Path $srcDir | Out-Null
}

$ocrBatchContent = @'
"""
ocr_batch_pdf.py
Processes all PDFs in input_dir with NDLOCR-Lite OCR and embeds
invisible text (render_mode=3) into the original PDF, saving results
to output_dir.
"""

import os
os.environ["PYTHONUTF8"] = "1"

import sys
sys.setrecursionlimit(5000)
try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

import argparse
import time
import numpy as np
from pathlib import Path
from PIL import Image
import xml.etree.ElementTree as ET

import fitz  # PyMuPDF

from ocr import (
    get_detector,
    get_recognizer,
    process_detector,
    process_cascade,
    RecogLine,
)
from reading_order.xy_cut.eval import eval_xml
from ndl_parser import convert_to_xml_string3


def pdf_page_to_numpy(page, dpi=200):
    scale = dpi / 72.0
    mat = fitz.Matrix(scale, scale)
    pix = page.get_pixmap(matrix=mat, alpha=False)
    img = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.h, pix.w, 3)
    return img


def ocr_one_page(img, page_name, detector, recognizer30, recognizer50, recognizer100):
    img_h, img_w = img.shape[:2]

    detections, classeslist = process_detector(
        detector, inputname=page_name, npimage=img,
        outputpath=".", issaveimg=False,
    )

    resultobj = [dict(), dict()]
    resultobj[0][0] = list()
    for i in range(17):
        resultobj[1][i] = []
    for det in detections:
        xmin, ymin, xmax, ymax = det["box"]
        conf = det["confidence"]
        char_count = det["pred_char_count"]
        if det["class_index"] == 0:
            resultobj[0][0].append([xmin, ymin, xmax, ymax])
        resultobj[1][det["class_index"]].append(
            [xmin, ymin, xmax, ymax, conf, char_count]
        )

    xmlstr = convert_to_xml_string3(img_w, img_h, page_name, classeslist, resultobj)
    xmlstr = "<OCRDATASET>" + xmlstr + "</OCRDATASET>"
    root = ET.fromstring(xmlstr)
    eval_xml(root, logger=None)

    alllineobj = []
    tatelinecnt = 0
    alllinecnt = 0

    for idx, lineobj in enumerate(root.findall(".//LINE")):
        xmin = int(lineobj.get("X"))
        ymin = int(lineobj.get("Y"))
        line_w = int(lineobj.get("WIDTH"))
        line_h = int(lineobj.get("HEIGHT"))
        try:
            pred_char_cnt = float(lineobj.get("PRED_CHAR_CNT"))
        except Exception:
            pred_char_cnt = 100.0
        if line_h > line_w:
            tatelinecnt += 1
        alllinecnt += 1
        lineimg = img[ymin:ymin + line_h, xmin:xmin + line_w, :]
        alllineobj.append(RecogLine(lineimg, idx, pred_char_cnt))

    if len(alllineobj) == 0 and len(detections) > 0:
        page_elem = root.find("PAGE")
        for idx, det in enumerate(detections):
            xmin, ymin, xmax, ymax = det["box"]
            line_w = int(xmax - xmin)
            line_h = int(ymax - ymin)
            if line_w > 0 and line_h > 0:
                line_elem = ET.SubElement(page_elem, "LINE")
                line_elem.set("TYPE", "")
                line_elem.set("X", str(int(xmin)))
                line_elem.set("Y", str(int(ymin)))
                line_elem.set("WIDTH", str(line_w))
                line_elem.set("HEIGHT", str(line_h))
                pred_char_cnt = det.get("pred_char_count", 100.0)
                line_elem.set("PRED_CHAR_CNT", f"{pred_char_cnt:0.3f}")
                if line_h > line_w:
                    tatelinecnt += 1
                alllinecnt += 1
                lineimg = img[int(ymin):int(ymax), int(xmin):int(xmax), :]
                alllineobj.append(RecogLine(lineimg, idx, pred_char_cnt))

    if len(alllineobj) > 0:
        resultlinesall = process_cascade(
            alllineobj, recognizer30, recognizer50, recognizer100, is_cascade=True
        )
    else:
        resultlinesall = []

    lines = root.findall(".//LINE")
    results = []
    for idx, lineelem in enumerate(lines):
        if idx >= len(resultlinesall):
            break
        text = resultlinesall[idx]
        if not text.strip():
            continue
        xmin = int(lineelem.get("X"))
        ymin = int(lineelem.get("Y"))
        line_w = int(lineelem.get("WIDTH"))
        line_h = int(lineelem.get("HEIGHT"))
        is_vert = line_h > line_w
        results.append({
            "text": text,
            "bbox": (xmin, ymin, xmin + line_w, ymin + line_h),
            "is_vertical": is_vert,
        })

    if alllinecnt > 0 and tatelinecnt / alllinecnt > 0.5:
        results = results[::-1]

    return results


def embed_invisible_text(pdf_page, ocr_results, img_w, img_h):
    page_rect = pdf_page.rect
    scale_x = page_rect.width / img_w
    scale_y = page_rect.height / img_h
    font_ja = fitz.Font("japan")

    for item in ocr_results:
        text = item["text"]
        xmin, ymin, xmax, ymax = item["bbox"]
        is_vertical = item["is_vertical"]

        pdf_x0 = xmin * scale_x
        pdf_y0 = ymin * scale_y
        pdf_x1 = xmax * scale_x
        pdf_y1 = ymax * scale_y
        box_w = pdf_x1 - pdf_x0
        box_h = pdf_y1 - pdf_y0

        if is_vertical:
            fontsize = box_w * 0.85
            if fontsize < 1:
                fontsize = 1
            char_step = box_h / max(len(text), 1)
            if char_step < fontsize and len(text) > 0:
                fontsize = char_step * 0.95
            x_pos = pdf_x0 + box_w * 0.1
            for i, ch in enumerate(text):
                y_pos = pdf_y0 + fontsize + i * char_step
                if y_pos > pdf_y1 + fontsize:
                    break
                pdf_page.insert_text(
                    fitz.Point(x_pos, y_pos), ch,
                    fontname="japan", fontsize=fontsize, render_mode=3,
                )
        else:
            fontsize = box_h * 0.85
            if fontsize < 1:
                fontsize = 1
            text_width = font_ja.text_length(text, fontsize=fontsize)
            if text_width > 0 and text_width > box_w:
                fontsize = fontsize * (box_w / text_width)
            insertion_point = fitz.Point(pdf_x0, pdf_y1 - box_h * 0.1)
            pdf_page.insert_text(
                insertion_point, text,
                fontname="japan", fontsize=fontsize, render_mode=3,
            )


def process_single_pdf(input_pdf_path, output_pdf_path, dpi, detector, recognizer30, recognizer50, recognizer100):
    input_str = str(input_pdf_path)
    output_str = str(output_pdf_path)

    doc = fitz.open(input_str)
    total_pages = len(doc)

    for page_idx in range(total_pages):
        page_num = page_idx + 1
        print(f"    page {page_num}/{total_pages} ...", end="", flush=True)
        page_start = time.time()

        page = doc[page_idx]
        img = pdf_page_to_numpy(page, dpi=dpi)
        img_h, img_w = img.shape[:2]

        page_name = f"page_{page_num:04d}.png"
        ocr_results = ocr_one_page(
            img, page_name, detector, recognizer30, recognizer50, recognizer100
        )

        embed_invisible_text(page, ocr_results, img_w, img_h)

        elapsed = time.time() - page_start
        print(f" {len(ocr_results)} lines ({elapsed:.1f}s)")

    doc.save(output_str, garbage=4, deflate=True)
    doc.close()


def process_batch(args):
    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    dpi = args.dpi

    if not input_dir.is_dir():
        print(f"[ERROR] Input folder not found: {input_dir}")
        return

    output_dir.mkdir(parents=True, exist_ok=True)

    pdf_files = sorted([p for p in input_dir.iterdir()
                        if p.is_file() and p.suffix.lower() == ".pdf"])

    if len(pdf_files) == 0:
        print("")
        print("========================================")
        print("  No PDF files in input_sousahyo folder.")
        print("  Please add PDF files and try again.")
        print("========================================")
        return

    print("")
    print("=" * 56)
    print("  NDLOCR-Lite PDF OCR Batch Processing")
    print("=" * 56)
    print(f"  Input  : {input_dir.resolve()}")
    print(f"  Output : {output_dir.resolve()}")
    print(f"  Files  : {len(pdf_files)}")
    print(f"  DPI    : {dpi}")
    print("=" * 56)
    print("")

    print("[INIT] Loading AI models...")
    print("       (May take ~30 seconds on first run)")
    model_start = time.time()
    detector = get_detector(args)
    recognizer100 = get_recognizer(args=args)
    recognizer30 = get_recognizer(args=args, weights_path=args.rec_weights30)
    recognizer50 = get_recognizer(args=args, weights_path=args.rec_weights50)
    model_elapsed = time.time() - model_start
    print(f"[INIT] Done ({model_elapsed:.1f}s)")
    print("")

    total_start = time.time()
    success_count = 0
    error_count = 0
    error_files = []

    for file_idx, pdf_path in enumerate(pdf_files):
        file_num = file_idx + 1
        filename = pdf_path.name
        output_path = output_dir / filename

        print(f"[{file_num}/{len(pdf_files)}] {filename}")

        try:
            file_start = time.time()
            process_single_pdf(
                pdf_path, output_path, dpi,
                detector, recognizer30, recognizer50, recognizer100
            )
            file_elapsed = time.time() - file_start
            print(f"  -> Saved ({file_elapsed:.1f}s)")
            success_count += 1
        except Exception as e:
            print(f"  -> [ERROR] {e}")
            error_count += 1
            error_files.append(filename)

        print("")

    total_elapsed = time.time() - total_start
    print("=" * 56)
    print("  Results")
    print("=" * 56)
    print(f"  Success : {success_count}")
    if error_count > 0:
        print(f"  Failed  : {error_count}")
        for ef in error_files:
            print(f"            - {ef}")
    print(f"  Time    : {total_elapsed:.1f}s")
    print(f"  Output  : {output_dir.resolve()}")
    print("=" * 56)
    print("")


def main():
    base_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description="NDLOCR-Lite Batch PDF OCR")
    parser.add_argument("--input-dir", type=str, required=True)
    parser.add_argument("--output-dir", type=str, required=True)
    parser.add_argument("--dpi", type=int, default=300)
    parser.add_argument("--det-weights", type=str,
        default=str(base_dir / "model" / "deim-s-1024x1024.onnx"))
    parser.add_argument("--det-classes", type=str,
        default=str(base_dir / "config" / "ndl.yaml"))
    parser.add_argument("--det-score-threshold", type=float, default=0.2)
    parser.add_argument("--det-conf-threshold", type=float, default=0.25)
    parser.add_argument("--det-iou-threshold", type=float, default=0.2)
    parser.add_argument("--rec-weights30", type=str,
        default=str(base_dir / "model" / "parseq-ndl-16x256-30-tiny-192epoch-tegaki3.onnx"))
    parser.add_argument("--rec-weights50", type=str,
        default=str(base_dir / "model" / "parseq-ndl-16x384-50-tiny-146epoch-tegaki2.onnx"))
    parser.add_argument("--rec-weights", type=str,
        default=str(base_dir / "model" / "parseq-ndl-16x768-100-tiny-165epoch-tegaki2.onnx"))
    parser.add_argument("--rec-classes", type=str,
        default=str(base_dir / "config" / "NDLmoji.yaml"))
    parser.add_argument("--device", type=str, choices=["cpu", "cuda"], default="cpu")
    args = parser.parse_args()
    process_batch(args)


if __name__ == "__main__":
    main()
'@

$ocrBatchPath = Join-Path $srcDir 'ocr_batch_pdf.py'
[System.IO.File]::WriteAllText($ocrBatchPath, $ocrBatchContent, $utf8NoBom)
Write-Host "  ocr_batch_pdf.py generated: $ocrBatchPath"

# ===== Step 6: Generate OCR実行.bat (ASCII, no Japanese) =====
Write-Step 'Step 6: Generating OCR実行.bat...'

# Pure ASCII content - cmd.exe reads this safely regardless of system locale
$batContent = @'
@echo off
chcp 65001 >nul
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8

set "PORTABLE_DIR=%~dp0"
set "PYTHON=%PORTABLE_DIR%python\python.exe"
set "SCRIPT=%PORTABLE_DIR%ndlocr-lite\src\ocr_batch_pdf.py"
set "INPUT_DIR=%PORTABLE_DIR%input_sousahyo"
set "OUTPUT_DIR=%PORTABLE_DIR%output"

"%PYTHON%" "%SCRIPT%" --input-dir "%INPUT_DIR%" --output-dir "%OUTPUT_DIR%" --dpi 300

pause
'@

$batPath = Join-Path $portableDir 'OCR実行.bat'
Set-Content -Path $batPath -Value $batContent -Encoding ASCII
Write-Host "  OCR実行.bat generated: $batPath"

# ===== Step 7: Create empty input/output folders =====
Write-Step 'Step 7: Creating input_sousahyo and output folders...'
New-Item -ItemType Directory -Path (Join-Path $portableDir 'input_sousahyo') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $portableDir 'output') | Out-Null
Write-Host '  Folders created.'

# ===== Step 8: Generate README.txt (UTF-8 no BOM) =====
Write-Step 'Step 8: Generating README.txt...'

$readmeContent = @'
==================================================
  NDLOCR-Lite Portable PDF OCR Tool
==================================================

How to use:

  Step 1: Put PDF files into "input_sousahyo" folder.
  Step 2: Double-click "OCR実行.bat".
  Step 3: Check "output" folder for results.

Notes:
  - Japanese file/folder names are supported.
  - Processing takes ~5-10 seconds per page.
  - Do not close the black window during processing.
  - Existing files in output folder will be overwritten.

License:
  NDLOCR-Lite: CC BY 4.0 (National Diet Library of Japan)
  https://github.com/ndl-lab/ndlocr-lite
'@

$readmePath = Join-Path $portableDir 'README.txt'
[System.IO.File]::WriteAllText($readmePath, $readmeContent, $utf8NoBom)
Write-Host "  README.txt generated: $readmePath"

# ===== Done =====
Write-Host ''
Write-Host '============================================' -ForegroundColor Green
Write-Host '  Build complete!' -ForegroundColor Green
Write-Host '  NDLOCR-Lite-Portable folder is ready.' -ForegroundColor Green
Write-Host '  Japanese paths and filenames are supported.' -ForegroundColor Green
Write-Host '============================================' -ForegroundColor Green
