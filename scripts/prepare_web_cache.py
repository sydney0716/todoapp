"""Prepare the offline shell after Flutter's release build."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
build = root / "build/web"
assets = []
digest = hashlib.sha256()
for file in sorted(build.rglob("*")):
    if not file.is_file():
        continue
    relative = file.relative_to(build).as_posix()
    if (
        relative in {"service-worker.js", "flutter_service_worker.js"}
        or file.suffix in {".map", ".symbols"}
        or "profiling/" in relative
        or "skwasm" in relative
    ):
        continue
    assets.append(relative)
    digest.update(relative.encode())
    digest.update(file.read_bytes())
assets.append("./")
worker = (root / "web/service-worker.js").read_text()
worker = worker.replace("__BUILD_VERSION__", digest.hexdigest()[:16])
worker = worker.replace("__ASSET_LIST__", json.dumps(assets))
(build / "service-worker.js").write_text(worker)
print(f"Prepared offline cache with {len(assets)} assets.")
