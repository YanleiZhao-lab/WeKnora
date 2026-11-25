#!/usr/bin/env bash
source "$(dirname "$0")/victor-common.sh"
start_log shutdown
compose stop
