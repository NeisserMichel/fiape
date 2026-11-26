#!/bin/sh
# Prueba de navegador completa sobre una base limpia (requiere Postgres local en /tmp/pg:5544 y Playwright).
set -e
cd "$(dirname "$0")/.."
psql -h /tmp/pg -p 5544 -U postgres -qc "drop database if exists e2e" -c "create database e2e" 2>/dev/null
psql -h /tmp/pg -p 5544 -U postgres -q -v ON_ERROR_STOP=1 -d e2e -f supabase/tests/stubs.sql
psql -h /tmp/pg -p 5544 -U postgres -q -v ON_ERROR_STOP=1 -d e2e -f supabase/schema.sql 2>&1 | grep -v NOTICE || true
rm -rf /tmp/fiape-files
pkill -f servidor_prueba.py || true; sleep 0.5
FIAPE_DB=e2e python3 tests/servidor_prueba.py > /tmp/srv.log 2>&1 &
sleep 1.2
FIAPE_DB=e2e python3 tests/e2e.py
