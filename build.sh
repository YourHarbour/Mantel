#!/bin/bash
# Builds Mantel.app: the MantelKit framework, the host app, and every plugin bundle.
# Needs the Xcode command line tools; no Xcode project involved.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Mantel.app"
CONTENTS="$APP/Contents"
FRAMEWORKS="$CONTENTS/Frameworks"
PLUGINS="$CONTENTS/PlugIns"
MODULES="build/modules"
TARGET="13.0"
ARCHS=(arm64 x86_64)

rm -rf "$APP" "$MODULES"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$FRAMEWORKS" "$PLUGINS" "$MODULES" build/obj

# Compiles $SOURCES once per architecture, then lipos them together. Falls back to the host
# architecture alone if the cross build is unavailable.
build_universal() {
    local out="$1"; shift
    local slices=()
    local ok=1
    for arch in "${ARCHS[@]}"; do
        local slice="build/obj/$(basename "$out").$arch"
        # Swift modules are per-architecture, so each slice gets its own module directory.
        local args=()
        for arg in "$@"; do args+=("${arg//@ARCH@/$arch}"); done
        mkdir -p "$MODULES/$arch"
        if swiftc -O -target "$arch-apple-macos$TARGET" -o "$slice" "${args[@]}" 2>"build/obj/$arch.log"; then
            slices+=("$slice")
        else
            ok=0
            if [ "$arch" = "$(uname -m)" ]; then
                echo "build failed for $out ($arch):"
                cat "build/obj/$arch.log"
                exit 1
            fi
        fi
    done
    if [ "$ok" = "1" ]; then
        lipo -create "${slices[@]}" -output "$out"
    else
        cp "build/obj/$(basename "$out").$(uname -m)" "$out"
    fi
}

# ---- MantelKit.framework -------------------------------------------------
FW="$FRAMEWORKS/MantelKit.framework"
mkdir -p "$FW/Versions/A/Resources" "$FW/Versions/A/Modules"
build_universal "$FW/Versions/A/MantelKit" \
    MantelKit/Sources/*.swift \
    -emit-library -module-name MantelKit \
    -emit-module -emit-module-path "$MODULES/@ARCH@/MantelKit.swiftmodule" \
    -framework AppKit \
    -Xlinker -install_name -Xlinker "@rpath/MantelKit.framework/Versions/A/MantelKit"
cp MantelKit/Resources/Info.plist "$FW/Versions/A/Resources/Info.plist"
ln -sf A "$FW/Versions/Current"
ln -sf Versions/Current/MantelKit "$FW/MantelKit"
ln -sf Versions/Current/Resources "$FW/Resources"

# ---- Host app ------------------------------------------------------------
build_universal "$CONTENTS/MacOS/Mantel" \
    Host/Sources/*.swift \
    -I "$MODULES/@ARCH@" -F "$FRAMEWORKS" -framework MantelKit -framework AppKit \
    -Xlinker -rpath -Xlinker "@executable_path/../Frameworks"
cp Host/Resources/Info.plist "$CONTENTS/Info.plist"
cp Host/Resources/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"

# ---- Plugins -------------------------------------------------------------
for dir in Plugins/*/; do
    name=$(basename "$dir")
    bundle="$PLUGINS/$name.mantelplugin"
    mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
    swift_files=($(find "$dir"Sources -name '*.swift'))
    framework_flags=(-framework MantelKit -framework AppKit)
    case "$name" in
        "FlagInput")
            framework_flags+=(-framework Carbon)
            ;;
        "Calendar")
            framework_flags+=(-framework SwiftUI -framework EventKit)
            ;;
        "Ordering")
            framework_flags+=(-framework ApplicationServices)
            ;;
    esac
    build_universal "$bundle/Contents/MacOS/$name" \
        "${swift_files[@]}" \
        -emit-library -module-name "$name" \
        -I "$MODULES/@ARCH@" -F "$FRAMEWORKS" "${framework_flags[@]}" \
        -Xlinker -bundle \
        -Xlinker -rpath -Xlinker "@loader_path/../../../../Frameworks"
    cp "$dir"Resources/Info.plist "$bundle/Contents/Info.plist"
    echo "  plugin: $name"
done

# ---- Sign ----------------------------------------------------------------
# Prefer the self-signed identity from tools/make-signing-identity.sh. macOS keys the
# Accessibility permission to the code signature, and ad-hoc signatures change on every build —
# which silently revokes the grant. A fixed identity keeps it across rebuilds.
IDENTITY="Mantel Local Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    SIGN="$IDENTITY"
else
    SIGN="-"
    echo "note: 没有找到「$IDENTITY」，回退到 ad-hoc 签名"
    echo "      每次重新构建都会作废辅助功能授权。跑 tools/make-signing-identity.sh 可以解决。"
fi

# Inside out: nested code has to be signed before the thing that contains it.
for bundle in "$PLUGINS"/*.mantelplugin; do codesign --force --sign "$SIGN" "$bundle" >/dev/null 2>&1 || true; done
codesign --force --sign "$SIGN" "$FW/Versions/A" >/dev/null 2>&1 || true
codesign --force --sign "$SIGN" "$APP" >/dev/null 2>&1 || echo "warning: 签名失败"

rm -rf build/obj
echo "-> $APP"
