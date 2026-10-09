import re, sys

init_py = sys.argv[1]
with open(init_py, "r") as f:
    content = f.read()
content = re.sub(
    r"^# KRITA_AI_PATCH_BEGIN.*?^# KRITA_AI_PATCH_END\s*\n",
    "", content, flags=re.DOTALL | re.MULTILINE,
)
content = re.sub(
    r"^_KRITA_AI_PATCH_V\d+\s*=\s*True\s*\n",
    "", content, flags=re.MULTILINE,
)
with open(init_py, "w") as f:
    f.write(content)
