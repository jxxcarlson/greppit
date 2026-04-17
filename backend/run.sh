#!/usr/bin/env bash
PORT=8085 DATABASE_URL="${DATABASE_URL:-postgres://localhost/greppit_dev}" stack exec greppit-backend
