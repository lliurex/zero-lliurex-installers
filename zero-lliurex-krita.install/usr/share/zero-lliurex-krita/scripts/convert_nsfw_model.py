import os, sys, json, shutil
from optimum.onnxruntime import ORTModelForSequenceClassification
from transformers import AutoTokenizer
from onnxruntime.quantization import quantize_dynamic, QuantType

MODEL_ID = sys.argv[1]
OUT = sys.argv[2]

print("[ONNX] Loading model from HuggingFace (first time downloads ~1 GB)...")
ort_model = ORTModelForSequenceClassification.from_pretrained(
    MODEL_ID, export=True, trust_remote_code=False
)

print("[ONNX] Saving tokenizer...")
tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
tokenizer.save_pretrained(OUT)

print("[ONNX] Saving raw ONNX model...")
ort_model.save_pretrained(OUT)

print("[ONNX] Applying INT8 dynamic quantization...")
for f in os.listdir(OUT):
    if f.endswith(".onnx"):
        path = os.path.join(OUT, f)
        orig_size = os.path.getsize(path) / (1024 * 1024)
        quantize_dynamic(path, path, weight_type=QuantType.QInt8)
        new_size = os.path.getsize(path) / (1024 * 1024)
        print(f"[ONNX] {f}: {orig_size:.1f} MB -> {new_size:.1f} MB")

print("[ONNX] Done. Cleaning HuggingFace cache...")
cache = os.path.expanduser("~/.cache/huggingface")
if os.path.exists(cache):
    shutil.rmtree(cache, ignore_errors=True)
    print("[ONNX] Cache cleaned.")
