import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("release_order", Path(__file__).parents[1] / "Tools/check-release-order.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def release(tag, draft=False, prerelease=False):
    return dict(tag_name=tag, draft=draft, prerelease=prerelease)


module.validate([release("v1.0.57")], "v1.0.58")
module.validate([release("v2.0.0-beta", prerelease=True)], "v1.0.58")
for previous in [release("v1.0.58"), release("v1.0.58", draft=True), release("v1.0.59"), release("v2.0.0")]:
    try:
        module.validate([previous], "v1.0.58")
    except ValueError:
        pass
    else:
        raise AssertionError("Duplicate or out-of-order release accepted")
print("PASS: stable release order and duplicate protection")
