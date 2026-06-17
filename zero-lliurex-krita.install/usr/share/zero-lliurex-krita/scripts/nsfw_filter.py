# KRITA_AI_NSFW_FILTER
import os, json, traceback, sys
from datetime import datetime

_venv_dir = os.path.join("REPLACE_ME_BASE_DIR", "venv")
_site_pkgs = os.path.join(
    _venv_dir, "lib",
    f"python{sys.version_info.major}.{sys.version_info.minor}",
    "site-packages",
)
if os.path.isdir(_site_pkgs) and _site_pkgs not in sys.path:
    sys.path.insert(0, _site_pkgs)

_log_dir = os.path.join("REPLACE_ME_BASE_DIR", "logs")
_log_file = None

def _patch_log(context, msg, exc=None):
    global _log_file
    try:
        if _log_file is None:
            os.makedirs(_log_dir, exist_ok=True)
            _log_file = os.path.join(_log_dir, "krita_ai_diffusion.log")
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        level = "ERROR" if exc else "INFO"
        with open(_log_file, "a") as f:
            f.write(f"[{ts}] [{level}] [{context}] {msg}\n")
            if exc:
                traceback.print_exception(type(exc), exc, exc.__traceback__, file=f)
                f.write("\n")
    except Exception:
        pass

_model_tokenizer = None
_model_session = None
_model_label_names = None

_THRESHOLD_MAP = {
    "sexual_explicit": 0.25,
    "severe_toxic":     0.30,
    "severe_toxicity":  0.30,
    "toxic":            0.40,
    "toxicity":         0.40,
    "threat":           0.40,
    "obscene":          0.40,
    "insult":           0.50,
    "identity_attack":  0.50,
    "identity_hate":    0.50,
}

def _load_model():
    global _model_tokenizer, _model_session, _model_label_names
    if _model_session is None:
        model_dir = os.path.join(_log_dir, "..", "models", "nsfw_onnx")
        _patch_log("nsfw", "loading ONNX model from " + model_dir)
        import warnings
        warnings.filterwarnings("ignore", message=".*incorrect regex.*")
        from transformers import AutoTokenizer
        import onnxruntime as _ort
        _model_tokenizer = AutoTokenizer.from_pretrained(model_dir)
        _model_session = _ort.InferenceSession(
            os.path.join(model_dir, "model.onnx"),
            providers=["CPUExecutionProvider"],
        )
        with open(os.path.join(model_dir, "config.json"), "r") as f:
            config = json.load(f)
        _model_label_names = [
            config["id2label"][str(i)]
            for i in range(len(config["id2label"]))
        ]
        _patch_log("nsfw", f"ONNX model loaded, labels: {_model_label_names}")
    return _model_tokenizer, _model_session, _model_label_names

def _predict(text):
    import numpy as np
    tokenizer, session, label_names = _load_model()
    encoded = tokenizer(
        text, return_tensors="np", padding=True,
        truncation=True, max_length=512,
    )
    logits = session.run(None, {
        "input_ids": encoded["input_ids"],
        "attention_mask": encoded["attention_mask"],
    })[0]
    probs = 1.0 / (1.0 + np.exp(-logits))
    return dict(zip(label_names, map(float, probs[0])))

def _check_nsfw_prompts(cond_orig):
    prompts_to_check = []
    if cond_orig.positive:
        prompts_to_check.append(("positive", cond_orig.positive))
    if cond_orig.negative:
        prompts_to_check.append(("negative", cond_orig.negative))
    for i, region in enumerate(getattr(cond_orig, "regions", []) or []):
        if region.positive:
            prompts_to_check.append((f"region_{i}", region.positive))
    if not prompts_to_check:
        return True
    for source, prompt in prompts_to_check:
        scores = _predict(prompt)
        print(f"[krita-ai-nsfw] Prompt ({source}): {prompt[:120]}...", file=sys.stderr)
        for label, score in sorted(scores.items(), key=lambda x: -x[1]):
            threshold = _THRESHOLD_MAP.get(label, 0.5)
            marker = ">>>" if score > threshold else "   "
            print(f"[krita-ai-nsfw]   {marker} {label}: {score:.4f} (thr={threshold})", file=sys.stderr)
        blocked_labels = [
            label for label, thr in _THRESHOLD_MAP.items()
            if scores.get(label, 0) > thr
        ]
        if blocked_labels:
            msg = f"blocked prompt ({source}): {', '.join(blocked_labels)}"
            print(f"[krita-ai-nsfw] BLOQUEADO: {msg}", file=sys.stderr)
            _patch_log("nsfw", msg)
            from PyQt5.QtWidgets import QMessageBox
            QMessageBox.warning(None, "Filtro de contenido",
                "El prompt ha sido bloqueado por el filtro de contenido NSFW.")
            return False
        print(f"[krita-ai-nsfw] Permitido ({source}).", file=sys.stderr)
    _patch_log("nsfw", "all prompts passed nsfw filter")
    return True
