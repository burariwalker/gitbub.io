#requires -Version 5.1
<#
.SYNOPSIS
    NDLOCR-Lite ポータブル版ビルドスクリプト
.DESCRIPTION
    Windows 11環境でPythonをインストールしていないユーザーでも実行できる
    「NDLOCR-Lite PDF OCRツール」のポータブル一式を自動構築する。
    実行すると NDLOCR-Lite-Portable フォルダが生成される。
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# ---- URL設定 ----
$pythonZipUrl = 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip'
$getPipUrl    = 'https://bootstrap.pypa.io/get-pip.py'
$ndlZipUrl    = 'https://github.com/ndl-lab/ndlocr-lite/archive/refs/heads/master.zip'

# ---- パス設定 ----
$portableDir = Join-Path $PSScriptRoot 'NDLOCR-Lite-Portable'
$pythonDir   = Join-Path $portableDir 'python'
$ndlDir      = Join-Path $portableDir 'ndlocr-lite'
$pythonExe   = Join-Path $pythonDir 'python.exe'

# ---- エンコーディング ----
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$utf8Bom   = New-Object System.Text.UTF8Encoding $true

function Write-Step([string]$msg) {
    Write-Host ''
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Fail([string]$msg) {
    Write-Host "[エラー] $msg" -ForegroundColor Red
    exit 1
}

# ===== Step 0: ポータブルフォルダ準備 =====
Write-Step 'ポータブルフォルダを準備しています...'
if (Test-Path $portableDir) {
    Write-Host '  既存の NDLOCR-Lite-Portable を削除して再作成します...'
    Remove-Item $portableDir -Recurse -Force
}
New-Item -ItemType Directory -Path $portableDir | Out-Null
Write-Host "  フォルダ作成完了: $portableDir"

# ===== Step 1: Python Embeddable のダウンロードと展開 =====
Write-Step 'Step 1: Python 3.12.10 embeddable をダウンロード中...'
$pythonZip = Join-Path $env:TEMP 'python-3.12.10-embed-amd64.zip'
try {
    Invoke-WebRequest -Uri $pythonZipUrl -OutFile $pythonZip -UseBasicParsing
} catch {
    Fail "Python のダウンロードに失敗しました: $_"
}
Write-Host '  ダウンロード完了。展開中...'
New-Item -ItemType Directory -Path $pythonDir | Out-Null
Expand-Archive -Path $pythonZip -DestinationPath $pythonDir -Force
Write-Host '  展開完了。'

# python312._pth を修正 (import site を有効化)
$pthFile = Join-Path $pythonDir 'python312._pth'
if (-not (Test-Path $pthFile)) {
    Fail 'python312._pth が見つかりません。ダウンロードしたzipを確認してください。'
}
$pthContent = [System.IO.File]::ReadAllText($pthFile, $utf8NoBom)
if ($pthContent -match '(?m)^#import site') {
    $pthContent = $pthContent -replace '(?m)^#import site', 'import site'
    [System.IO.File]::WriteAllText($pthFile, $pthContent, $utf8NoBom)
    Write-Host '  python312._pth を修正しました（import site 有効化）'
} else {
    Write-Host '  python312._pth: import site はすでに有効です。'
}

# ===== Step 2: pip のインストール =====
Write-Step 'Step 2: pip をインストール中...'
$getPipScript = Join-Path $env:TEMP 'get-pip.py'
try {
    Invoke-WebRequest -Uri $getPipUrl -OutFile $getPipScript -UseBasicParsing
} catch {
    Fail "get-pip.py のダウンロードに失敗しました: $_"
}
Write-Host '  get-pip.py をダウンロードしました。pip をインストール中...'
& $pythonExe $getPipScript
if ($LASTEXITCODE -ne 0) {
    Fail 'pip のインストールに失敗しました。'
}
Write-Host '  pip インストール完了。'

# ===== Step 3: NDLOCR-Lite のダウンロード =====
Write-Step 'Step 3: NDLOCR-Lite をダウンロード中...'
$ndlZip = Join-Path $env:TEMP 'ndlocr-lite-master.zip'
try {
    Invoke-WebRequest -Uri $ndlZipUrl -OutFile $ndlZip -UseBasicParsing
} catch {
    Fail "NDLOCR-Lite のダウンロードに失敗しました: $_"
}
Write-Host '  ダウンロード完了。展開中...'
$ndlTemp = Join-Path $env:TEMP 'ndlocr-lite-extract'
if (Test-Path $ndlTemp) { Remove-Item $ndlTemp -Recurse -Force }
Expand-Archive -Path $ndlZip -DestinationPath $ndlTemp -Force

$ndlMaster = Join-Path $ndlTemp 'ndlocr-lite-master'
if (-not (Test-Path $ndlMaster)) {
    Fail 'ndlocr-lite-master フォルダが展開先に見つかりません。'
}
Move-Item $ndlMaster $ndlDir
Write-Host "  NDLOCR-Lite を配置しました: $ndlDir"

# ===== Step 4: 依存ライブラリのインストール =====
Write-Step 'Step 4: 依存ライブラリをインストール中...'
$reqFile = Join-Path $ndlDir 'requirements.txt'
if (-not (Test-Path $reqFile)) {
    Fail 'requirements.txt が見つかりません。NDLOCR-Lite のダウンロードを確認してください。'
}

$reqLines    = [System.IO.File]::ReadAllLines($reqFile, $utf8NoBom)
$filteredLines = $reqLines | Where-Object {
    $_ -notmatch '^\s*flet' -and $_ -notmatch '^\s*pypdfium2'
}
$reqCliFile = Join-Path $ndlDir 'requirements_cli.txt'
[System.IO.File]::WriteAllLines($reqCliFile, [string[]]$filteredLines, $utf8NoBom)
Write-Host '  requirements_cli.txt を生成しました（flet, pypdfium2 を除外）'

Write-Host '  パッケージをインストール中（数分かかる場合があります）...'
& $pythonExe -m pip install -r $reqCliFile
if ($LASTEXITCODE -ne 0) {
    Fail '依存ライブラリのインストールに失敗しました。'
}

Write-Host '  pymupdf を追加インストール中...'
& $pythonExe -m pip install pymupdf
if ($LASTEXITCODE -ne 0) {
    Fail 'pymupdf のインストールに失敗しました。'
}
Write-Host '  依存ライブラリのインストール完了。'

# ===== Step 5: ocr_batch_pdf.py を生成 =====
Write-Step 'Step 5: ocr_batch_pdf.py を生成中...'

$srcDir = Join-Path $ndlDir 'src'
if (-not (Test-Path $srcDir)) {
    New-Item -ItemType Directory -Path $srcDir | Out-Null
}

$ocrBatchContent = @'
"""
ocr_batch_pdf.py
input_dirフォルダ内の全PDFをNDLOCR-LiteでOCRし、
元のPDFに透明テキスト(render_mode=3)を埋め込んでoutput_dirに出力する。
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
import glob
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
    """1つのPDFを処理する。引数はPathオブジェクトでもstrでもOK。"""
    input_str = str(input_pdf_path)
    output_str = str(output_pdf_path)

    doc = fitz.open(input_str)
    total_pages = len(doc)

    for page_idx in range(total_pages):
        page_num = page_idx + 1
        print(f"    ページ {page_num}/{total_pages} ...", end="", flush=True)
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
        print(f" {len(ocr_results)}行認識 ({elapsed:.1f}秒)")

    doc.save(output_str, garbage=4, deflate=True)
    doc.close()


def process_batch(args):
    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    dpi = args.dpi

    if not input_dir.is_dir():
        print(f"[エラー] 入力フォルダが見つかりません: {input_dir}")
        return

    output_dir.mkdir(parents=True, exist_ok=True)

    pdf_files = sorted([p for p in input_dir.iterdir()
                        if p.is_file() and p.suffix.lower() == ".pdf"])

    if len(pdf_files) == 0:
        print("")
        print("[お知らせ] input_sousahyo フォルダにPDFファイルがありません。")
        print("           PDFファイルを入れてから、もう一度実行してください。")
        return

    print("")
    print("=" * 56)
    print("  NDLOCR-Lite PDF OCR 一括処理")
    print("=" * 56)
    print(f"  入力フォルダ : {input_dir.resolve()}")
    print(f"  出力フォルダ : {output_dir.resolve()}")
    print(f"  対象ファイル : {len(pdf_files)} 件")
    print(f"  DPI          : {dpi}")
    print("=" * 56)
    print("")

    print("[準備] AIモデルを読み込んでいます...")
    print("       （初回は30秒ほどかかることがあります）")
    model_start = time.time()
    detector = get_detector(args)
    recognizer100 = get_recognizer(args=args)
    recognizer30 = get_recognizer(args=args, weights_path=args.rec_weights30)
    recognizer50 = get_recognizer(args=args, weights_path=args.rec_weights50)
    model_elapsed = time.time() - model_start
    print(f"[準備] 完了！ ({model_elapsed:.1f}秒)")
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
            print(f"  → 保存完了 ({file_elapsed:.1f}秒)")
            success_count += 1
        except Exception as e:
            print(f"  → [エラー] {e}")
            error_count += 1
            error_files.append(filename)

        print("")

    total_elapsed = time.time() - total_start
    print("=" * 56)
    print("  処理結果")
    print("=" * 56)
    print(f"  成功 : {success_count} 件")
    if error_count > 0:
        print(f"  失敗 : {error_count} 件")
        for ef in error_files:
            print(f"         - {ef}")
    print(f"  合計時間 : {total_elapsed:.1f}秒")
    print(f"  出力先   : {output_dir.resolve()}")
    print("=" * 56)
    print("")


def main():
    base_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description="NDLOCR-Lite 複数PDF一括OCR")
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
Write-Host "  ocr_batch_pdf.py を生成しました: $ocrBatchPath"

# ===== Step 6: OCR実行.bat を生成 =====
Write-Step 'Step 6: OCR実行.bat を生成中...'

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

echo.
echo ============================================
echo   NDLOCR-Lite PDF OCR ツール
echo ============================================
echo.
echo   input_sousahyo フォルダ内のPDFを
echo   まとめてOCR処理します。
echo.
echo   結果は output フォルダに出力されます。
echo ============================================
echo.

rem 入力フォルダにPDFがあるかチェック
dir /b "%INPUT_DIR%\*.pdf" >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [お知らせ] input_sousahyo フォルダにPDFファイルがありません。
    echo            PDFファイルを入れてから、もう一度実行してください。
    echo.
    pause
    exit /b
)

rem 処理実行
"%PYTHON%" "%SCRIPT%" --input-dir "%INPUT_DIR%" --output-dir "%OUTPUT_DIR%" --dpi 300

echo.
if %ERRORLEVEL% EQU 0 (
    echo 全ての処理が完了しました。output フォルダを確認してください。
) else (
    echo エラーが発生しました。上のメッセージを確認してください。
)
echo.
pause
'@

$batPath = Join-Path $portableDir 'OCR実行.bat'
[System.IO.File]::WriteAllText($batPath, $batContent, $utf8Bom)
Write-Host "  OCR実行.bat を生成しました: $batPath"

# ===== Step 7: 空フォルダを作成 =====
Write-Step 'Step 7: input_sousahyo / output フォルダを作成中...'
New-Item -ItemType Directory -Path (Join-Path $portableDir 'input_sousahyo') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $portableDir 'output') | Out-Null
Write-Host '  フォルダを作成しました。'

# ===== Step 8: README.txt を生成 =====
Write-Step 'Step 8: README.txt を生成中...'

$readmeContent = @'
==================================================
  NDLOCR-Lite ポータブル版 PDF OCR ツール
  使い方ガイド
==================================================

■ このツールでできること
  スキャンしたPDFに透明テキストを埋め込み、
  文字の検索・コピーができるPDFに変換します。
  複数のPDFファイルをまとめて一括処理できます。
  Pythonのインストールは不要です。
  フォルダやファイル名に日本語が含まれていてもOKです。

■ 使い方（3ステップ）

  ステップ1:
    「input_sousahyo」フォルダにPDFファイルを入れる。
    ファイルは何個でもOKです。

  ステップ2:
    「OCR実行.bat」をダブルクリックする。
    黒い画面が開いて処理が始まります。
    処理中は画面を閉じないでください。

  ステップ3:
    処理が完了したら「output」フォルダを開く。
    同じファイル名でOCR済みPDFが保存されています。

■ 処理時間の目安
  1ページあたり 約5〜10秒（PCの性能によります）
  例: 10ページのPDFが3つ → 約3〜5分

■ 注意事項
  - フォルダやファイル名に日本語が含まれていても動作します
  - PCのメモリが4GB以上あることを推奨します
  - outputフォルダに同名のファイルがあると上書きされます
  - 処理中は黒い画面を閉じないでください

■ うまくいかないとき
  - PDFファイル名に特殊文字（& % ! 等）が含まれて
    いるとエラーになることがあります。
    ファイル名を変更してお試しください。
  - 黒い画面に赤い文字でエラーが出た場合は、
    その内容をシステム管理者にお伝えください。

■ ライセンス
  NDLOCR-Lite: CC BY 4.0（国立国会図書館）
  https://github.com/ndl-lab/ndlocr-lite
'@

$readmePath = Join-Path $portableDir 'README.txt'
[System.IO.File]::WriteAllText($readmePath, $readmeContent, $utf8Bom)
Write-Host "  README.txt を生成しました: $readmePath"

# ===== 完了 =====
Write-Host ''
Write-Host '============================================' -ForegroundColor Green
Write-Host '  ビルド完了！' -ForegroundColor Green
Write-Host '============================================' -ForegroundColor Green
Write-Host '  NDLOCR-Lite-Portable フォルダが作成されました。' -ForegroundColor Green
Write-Host '  このフォルダは日本語パスに置いても動作します。' -ForegroundColor Green
Write-Host '============================================' -ForegroundColor Green
