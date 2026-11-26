#!/bin/sh
# Recrea la base de prueba, carga Supabase simulado + schema.sql (dos veces,
# para comprobar que se puede volver a ejecutar) y corre todas las pruebas.
set -e
cd "$(dirname "$0")/.."
PG="psql -h /tmp/pg -p 5544 -U postgres -v ON_ERROR_STOP=1 -q"
psql -h /tmp/pg -p 5544 -U postgres -qc "drop database if exists t" -c "create database t"
$PG -d t -f tests/stubs.sql
$PG -d t -f schema.sql
$PG -d t -f schema.sql
$PG -d t -t -f tests/pruebas.sql 2>&1 | grep -E "OK|FALLO|ERROR|===" | sed 's/^.*NOTICE:  //'
