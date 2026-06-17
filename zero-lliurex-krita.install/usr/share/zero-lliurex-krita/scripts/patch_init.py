# KRITA_AI_PATCH_BEGIN
_KRITA_AI_PATCH_V6 = True
import os, json, traceback, datetime

_log_dir = os.path.join("REPLACE_ME_BASE_DIR", "logs")
_log_file = None

def _patch_log(context, msg, exc=None):
    try:
        global _log_file
        if _log_file is None:
            os.makedirs(_log_dir, exist_ok=True)
            _log_file = os.path.join(_log_dir, "krita_ai_diffusion.log")
        ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        level = "ERROR" if exc else "INFO"
        with open(_log_file, "a") as f:
            f.write(f"[{ts}] [{level}] [{context}] {msg}\n")
            if exc:
                traceback.print_exception(type(exc), exc, exc.__traceback__, file=f)
                f.write("\n")
    except Exception:
        pass

try:
    _data_home = os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))
    _st_dir = os.path.join(_data_home, "krita", "ai_diffusion")
    _st_file = os.path.join(_st_dir, "settings.json")
    os.makedirs(_st_dir, exist_ok=True)
    _data = {}
    if os.path.exists(_st_file):
        with open(_st_file, "r") as f:
            _data = json.load(f)
    _changed = False
    _target_path = "REPLACE_ME_BASE_DIR"
    if _data.get("server_path") != _target_path:
        _data["server_path"] = _target_path
        _changed = True
    if _data.get("server_mode") != "managed":
        _data["server_mode"] = "managed"
        _changed = True
    if _data.get("server_backend") != "cpu":
        _data["server_backend"] = "cpu"
        _changed = True
    if _data.get("check_server_resources") != False:
        _data["check_server_resources"] = False
        _changed = True
    if _data.get("auto_update") != False:
        _data["auto_update"] = False
        _changed = True
    if _changed:
        with open(_st_file, "w") as f:
            json.dump(_data, f)
    _patch_log("settings", "settings.json written successfully")
except Exception as __e:
    _patch_log("settings", "failed to write settings.json", exc=__e)

try:
    from PyQt5.QtCore import QTimer
    def _show_ai_diffusion_docker():
        try:
            for d in Krita.instance().dockers():
                if d.objectName() == "imageDiffusion":
                    d.setVisible(True)
                    return
        except Exception as __e2:
            _patch_log("docker", "failed to show docker", exc=__e2)
    QTimer.singleShot(2000, _show_ai_diffusion_docker)
    _patch_log("docker", "docker visibility timer registered")
except Exception as __e:
    _patch_log("docker", "failed to register docker timer", exc=__e)
# KRITA_AI_PATCH_END
