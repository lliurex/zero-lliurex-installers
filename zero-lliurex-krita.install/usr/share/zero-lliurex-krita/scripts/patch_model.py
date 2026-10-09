import sys

model_py = sys.argv[1]

with open(model_py, "r") as f:
    content = f.read()

if 'from .nsfw_filter import' in content:
    print("NSFW patch already in model.py")
    sys.exit(0)

old_import = "from typing import Any, NamedTuple\n"
new_import = "from typing import Any, NamedTuple\nfrom .nsfw_filter import _check_nsfw_prompts\n"
if old_import not in content:
    print("ERROR: cannot find import line in model.py")
    sys.exit(1)
content = content.replace(old_import, new_import, 1)

old = """            self.report_error(util.log_error(e))
            return
        self.clear_error()"""
new = """            self.report_error(util.log_error(e))
            return
        if not _check_nsfw_prompts(cond_orig):
            return
        self.clear_error()"""
if old not in content:
    print("WARNING: Could not find injection point in _generate()")
else:
    content = content.replace(old, new, 1)

with open(model_py, "w") as f:
    f.write(content)

print("NSFW patch applied to model.py")
