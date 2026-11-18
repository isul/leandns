#!/bin/sh
# Serve LeanDNS UI at / (no OpenWrt/LuCI splash). Keep /leandns/ as the same files.
set -e
mkdir -p /www
ln -sfn leandns/index.html /www/index.html
ln -sfn leandns/css /www/css
ln -sfn leandns/js /www/js
ln -sfn leandns/img /www/img
