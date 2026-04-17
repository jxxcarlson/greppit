#!/usr/bin/env bash
PORT=8085 DATABASE_URL="${DATABASE_URL:-host=localhost dbname=greppit_dev}" stack exec greppit-backend
