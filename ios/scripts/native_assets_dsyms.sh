#!/bin/sh
# Flutter builds native-asset frameworks (e.g. objective_c.framework, pulled in
# by path_provider_foundation) outside Xcode and ships no dSYM for them, so
# App Store Connect warns "The archive did not include a dSYM for ...".
# On archive, rebuild each missing dSYM from the unstripped dylib that the Dart
# build hooks left in .dart_tool, matched by UUID.
[ "$ACTION" = "install" ] || exit 0

HOOKS="$SRCROOT/../.dart_tool/hooks_runner/shared"
FRAMEWORKS="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
[ -d "$HOOKS" ] || exit 0

for fw in "$FRAMEWORKS"/*.framework; do
  name=$(basename "$fw" .framework)
  bin="$fw/$name"
  dsym="$DWARF_DSYM_FOLDER_PATH/$name.framework.dSYM"
  [ -f "$bin" ] || continue
  uuid=$(dwarfdump --uuid "$bin" | awk 'NR==1 {print $2}')
  [ -n "$uuid" ] || continue
  # Already has a matching dSYM (Pods, Flutter, App, or a previous run).
  if [ -d "$dsym" ] && dwarfdump --uuid "$dsym" | grep -q "$uuid"; then
    continue
  fi
  for src in "$HOOKS"/*/build/*/"$name.dylib"; do
    [ -f "$src" ] || continue
    dwarfdump --uuid "$src" | grep -q "$uuid" || continue
    out="$DERIVED_FILE_DIR/native_assets_dsyms/$name.framework.dSYM"
    mkdir -p "$(dirname "$out")"
    xcrun dsymutil "$src" -o "$out" || break
    mv "$out/Contents/Resources/DWARF/$name.dylib" "$out/Contents/Resources/DWARF/$name"
    ditto "$out" "$dsym"
    echo "native_assets_dsyms: wrote $name.framework.dSYM ($uuid)"
    break
  done
done
exit 0
