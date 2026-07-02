import os, sys, json, shutil
from huggingface_hub import snapshot_download

MODEL_ID = sys.argv[1]
OUT = sys.argv[2]

_NSFW_LABELS = [
    "toxicity", "severe_toxicity", "obscene", "identity_attack",
    "insult", "threat", "sexual_explicit", "male", "female",
    "homosexual_gay_or_lesbian", "christian", "jewish", "muslim",
    "black", "white", "psychiatric_or_mental_illness",
]

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

config_path = os.path.join(OUT, "config.json")
with open(config_path) as f:
    config = json.load(f)
if config.get("id2label", {}).get("0", "").startswith("LABEL_"):
    print("[ONNX] Patching config.json with correct label names...")
    config["id2label"] = {str(i): _NSFW_LABELS[i] for i in range(len(_NSFW_LABELS))}
    config["label2id"] = {name: i for i, name in enumerate(_NSFW_LABELS)}
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)

print(f"[ONNX] Done. Model saved to {OUT}")

cache = os.path.expanduser("~/.cache/huggingface")
if os.path.exists(cache):
    shutil.rmtree(cache, ignore_errors=True)
    print("[ONNX] Cache cleaned.")
