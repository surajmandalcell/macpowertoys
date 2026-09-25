#!/bin/sh
set -eu

normal=$(make -n install ALLOW_INSTALL=1)
prebuilt=$(make -n install ALLOW_INSTALL=1 PREBUILT_APP=/tmp/MacPowerToys.app)

printf '%s\n' "$normal" | rg -q xcodebuild
! printf '%s\n' "$prebuilt" | rg -q xcodebuild
printf '%s\n' "$prebuilt" | rg -q 'MPTSourceCommit'
printf '%s\n' "$prebuilt" | rg -q 'codesign --verify --deep --strict'
printf '%s\n' "$prebuilt" | rg -q 'TeamIdentifier='
printf '%s\n' "$prebuilt" | rg -q 'pgrep -f'
