import os, sys, shutil
from huggingface_hub import snapshot_download

MODEL_ID = sys.argv[1]
OUT = sys.argv[2]

print(f"[ONNX] Downloading pre-quantized ONNX model from {MODEL_ID}...")
snapshot_download(
    repo_id=MODEL_ID,
    local_dir=OUT,
    local_dir_use_symlinks=False,
)

onnx_files = [f for f in os.listdir(OUT) if f.endswith(".onnx")]
if onnx_files:
    src = os.path.join(OUT, onnx_files[0])
    dst = os.path.join(OUT, "model.onnx")
    if src != dst:
        os.rename(src, dst)

print(f"[ONNX] Done. Model saved to {OUT}")

cache = os.path.expanduser("~/.cache/huggingface")
if os.path.exists(cache):
    shutil.rmtree(cache, ignore_errors=True)
    print("[ONNX] Cache cleaned.")
