"""Run pg_dump with libpq environment settings parsed from DATABASE_URL."""

import os
import subprocess
import sys
from urllib.parse import parse_qsl, unquote, urlsplit

uri = urlsplit(os.environ["DATABASE_URL"])
if uri.scheme not in {"postgres", "postgresql", "postgresql+psycopg"}:
    raise SystemExit("DATABASE_URL must be a PostgreSQL URL")

environment = os.environ.copy()
parameters = {
    "PGHOST": uri.hostname,
    "PGPORT": str(uri.port) if uri.port else None,
    "PGUSER": unquote(uri.username) if uri.username else None,
    "PGPASSWORD": unquote(uri.password) if uri.password else None,
    "PGDATABASE": unquote(uri.path.lstrip("/")),
}
query_variables = {
    "host": "PGHOST",
    "port": "PGPORT",
    "user": "PGUSER",
    "password": "PGPASSWORD",
    "dbname": "PGDATABASE",
    "sslmode": "PGSSLMODE",
    "sslcert": "PGSSLCERT",
    "sslkey": "PGSSLKEY",
    "sslrootcert": "PGSSLROOTCERT",
    "connect_timeout": "PGCONNECT_TIMEOUT",
    "application_name": "PGAPPNAME",
    "options": "PGOPTIONS",
    "target_session_attrs": "PGTARGETSESSIONATTRS",
}
for key, value in parse_qsl(uri.query):
    if key not in query_variables:
        raise SystemExit(f"Unsupported DATABASE_URL query option: {key}")
    parameters[query_variables[key]] = value
environment.update(
    {key: value for key, value in parameters.items() if value is not None}
)
subprocess.run(
    ["pg_dump", "--format=custom", f"--file={sys.argv[1]}"], env=environment, check=True
)
