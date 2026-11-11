"""Execute with Python and lupa (Lua 5.1, matching addon syntax)."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / ".tools"))
from lupa.lua51 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
addon = lua.table()
lua.globals().TEST_ADDON = addon

def load(name):
    source = (root / "ForeverQuestRoute" / name).read_text(encoding="utf-8")
    lua.execute(source, "ForeverQuestRoute", addon)

for name in ("Engine.lua", "Adapter.lua", "Catalog.lua", "Requirements.lua", "Area.lua", "Tracker.lua"):
    load(name)
lua.globals().LOAD_UI_CORE = lambda: (load("TrackerUI.lua"), load("UI.lua"), load("Core.lua"))
lua.execute((root / "tests" / "test_addon.lua").read_text(encoding="utf-8"))
lua.execute((root / "tests" / "test_catalog.lua").read_text(encoding="utf-8"))
lua.execute((root / "tests" / "test_area.lua").read_text(encoding="utf-8"))
lua.execute((root / "tests" / "test_requirements.lua").read_text(encoding="utf-8"))
for name in ("test_tracker.lua", "test_catalog_regressions.lua", "test_ui_regressions.lua", "test_core_regressions.lua"):
    test = root / "tests" / name
    lua.execute(test.read_text(encoding="utf-8"))
