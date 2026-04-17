#!/bin/bash
psql "postgres://$(whoami)@localhost/greppit_dev?sslmode=disable"
