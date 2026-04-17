#!/bin/bash
kill -9 $(lsof -ti :8085) 2>/dev/null && echo "Stopped backend" || echo "No backend running"
kill -9 $(lsof -ti :8011) 2>/dev/null && echo "Stopped frontend" || echo "No frontend running"
