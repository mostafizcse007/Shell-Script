#!/usr/bin/env bash
# ==============================================================================
# Helper Script: Generate Sample Messy Directory for Lab Demo & Testing
# ==============================================================================
set -euo pipefail

TARGET="${1:-./examples/sample_dirty_dir}"
mkdir -p "${TARGET}"

echo "Generating sample disorganized files in: ${TARGET}..."

# Documents
echo "Sample Report Content" > "${TARGET}/quarterly_report.pdf"
echo "Project Outline" > "${TARGET}/lecture_notes.docx"
echo "Todo list item 1" > "${TARGET}/todo.txt"
echo "# Project Readme" > "${TARGET}/project_spec.md"
echo "id,val\n1,100" > "${TARGET}/data_export.csv"

# Images
echo "fake_png_header" > "${TARGET}/architecture_diagram.png"
echo "fake_jpg_header" > "${TARGET}/screenshot_mock.jpg"
echo "<svg><circle r='10'/></svg>" > "${TARGET}/icon_vector.svg"

# Media
echo "fake_audio_stream" > "${TARGET}/podcast_recording.mp3"
echo "fake_video_stream" > "${TARGET}/demo_clip.mp4"

# Archives
echo "fake_zip_bytes" > "${TARGET}/old_dataset.zip"
echo "fake_tar_bytes" > "${TARGET}/backup_stub.tar.gz"

# Code
echo "print('Hello Antigravity')" > "${TARGET}/analytics_script.py"
echo "#include <stdio.h>\nint main() { return 0; }" > "${TARGET}/main.c"
echo "#!/usr/bin/env bash\necho hi" > "${TARGET}/helper.sh"
echo "{\"status\": \"ok\"}" > "${TARGET}/config.json"

# Logs (Recent and Stale)
echo "[INFO] [Recent] System health normal" > "${TARGET}/app_active.log"
echo "[WARN] [Recent] Disk latency spike" > "${TARGET}/service_recent.log"

# Create a stale log (backdated by 20 days)
STALE_LOG="${TARGET}/legacy_audit_archive.log"
echo "[ERROR] [Old] Kernel page fault from 30 days ago" > "${STALE_LOG}"

# Cross-platform backdating (GNU touch vs BSD touch)
if touch -d "30 days ago" "${STALE_LOG}" 2>/dev/null; then
  :
elif touch -t "202001010000" "${STALE_LOG}" 2>/dev/null; then
  :
fi

# Create an oversized log (>1MB for testing size compression threshold)
OVERSIZED_LOG="${TARGET}/oversized_transaction.log"
# Generate 1.2 MB file using dd or loop
if command -v dd &>/dev/null; then
  dd if=/dev/zero of="${OVERSIZED_LOG}" bs=1024 count=1200 2>/dev/null || true
else
  yes "LOG_ENTRY_PADDING_FOR_TESTING_OVERSIZED_FILE_THRESHOLD_MB" | head -n 30000 > "${OVERSIZED_LOG}"
fi

echo "Sample test directory successfully populated at '${TARGET}'."
ls -lh "${TARGET}"
