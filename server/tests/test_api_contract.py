import json
from pathlib import Path

from fastapi.testclient import TestClient

from app.main import app
from app.routes.sync import _TASK_FIELD_NAMES


def test_health_contract():
    client = TestClient(app)

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_task_sync_fields_match_repository_metadata():
    metadata_path = (
        Path(__file__).resolve().parents[2] / "docs" / "sync_task_fields.json"
    )
    metadata = json.loads(metadata_path.read_text())

    assert list(_TASK_FIELD_NAMES) == metadata["changed_task_fields"]
