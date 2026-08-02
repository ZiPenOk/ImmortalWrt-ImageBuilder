#!/bin/sh

# Metadata and asset naming used by the project's LuCI AutoUpdate client.

project_prepare_update_metadata() {
    PROJECT_UPDATE_VERSION="${PROJECT_UPDATE_VERSION:-$(date +%s)}"
    PROJECT_LUCI_EDITION="${PROJECT_LUCI_EDITION:-24.10}"
    PROJECT_UPDATE_TAG="${PROJECT_UPDATE_TAG:-Update-x86-64-${PROJECT_LUCI_EDITION}}"
    PROJECT_GITHUB_LINK="${PROJECT_GITHUB_LINK:-https://github.com/ZiPenOk/ImmortalWrt-ImageBuilder}"
    PROJECT_SOURCE="Immortalwrt"
    PROJECT_DEVICE_MODEL="x86-64"
    PROJECT_FIRMWARE_SUFFIX=".img.gz"

    export PROJECT_UPDATE_VERSION PROJECT_LUCI_EDITION PROJECT_UPDATE_TAG
    export PROJECT_GITHUB_LINK PROJECT_SOURCE PROJECT_DEVICE_MODEL PROJECT_FIRMWARE_SUFFIX

    mkdir -p files/etc
    chmod +x files/etc/uci-defaults/*.sh files/etc/uci-defaults/40_luci-app-autoupdate \
        files/etc/init.d/autoupdate files/usr/bin/AutoUpdate files/usr/bin/AutoUpgrade 2>/dev/null || true
    cat > files/etc/openwrt_update <<EOF
GITHUB_LINK="${PROJECT_GITHUB_LINK}"
FIRMWARE_VERSION="${PROJECT_SOURCE}-${PROJECT_DEVICE_MODEL}-${PROJECT_UPDATE_VERSION}"
LUCI_EDITION="${PROJECT_LUCI_EDITION}"
SOURCE="${PROJECT_SOURCE}"
DEVICE_MODEL="${PROJECT_DEVICE_MODEL}"
FIRMWARE_SUFFIX="${PROJECT_FIRMWARE_SUFFIX}"
TARGET_BOARD="x86"
GITHUB_PROXY="https://ghfast.top"
RELEASE_DOWNLOAD="${PROJECT_GITHUB_LINK}/releases/download/${PROJECT_UPDATE_TAG}"
EOF
}

project_prepare_root_password_defaults() {
    # Store only a SHA-512 crypt hash in the generated first-boot script.
    ROOT_PASSWORD_HASH='$6$Ft9HNSn4ng/rtoj8$54lXDtm0rvABhXFXhQmgpHP/1Yt8hsZ7lyI6AuP..KmkE3mwyVf1NBhDV4cdsAY0NvwQyBxxlbVHWfR8OD3hc0'

    mkdir -p files/etc/uci-defaults
    cat > files/etc/uci-defaults/05-project-root-password <<EOF
#!/bin/sh
ROOT_PASSWORD_HASH='${ROOT_PASSWORD_HASH}'

if [ -f /etc/shadow ]; then
    sed -i "s#^root:[^:]*:#root:\${ROOT_PASSWORD_HASH}:#" /etc/shadow
fi

exit 0
EOF
    chmod 700 files/etc/uci-defaults/05-project-root-password
}

project_install_zashboard_overlay() {
    case " ${PACKAGES:-} " in
        *" luci-app-openclash "*) ;;
        *)
            return 0
            ;;
    esac

    ZASHBOARD_URL="${ZASHBOARD_URL:-https://github.com/ZiPenOk/zashboard/releases/latest/download/zashboard.zip}"
    if ! ZASHBOARD_TMP="$(mktemp -d /tmp/zashboard.XXXXXX)"; then
        echo "Cannot create temporary directory for custom Zashboard" >&2
        return 1
    fi
    ZASHBOARD_ZIP="$ZASHBOARD_TMP/zashboard.zip"
    ZASHBOARD_DIST="$ZASHBOARD_TMP/dist"
    ZASHBOARD_TARGET="/home/build/immortalwrt/files/usr/share/openclash/ui/zashboard"

    echo "Downloading custom Zashboard release"
    if ! curl -fsSL --retry 3 --retry-delay 2 \
        "$ZASHBOARD_URL" -o "$ZASHBOARD_ZIP"; then
        echo "Failed to download custom Zashboard" >&2
        rm -rf "$ZASHBOARD_TMP"
        return 1
    fi

    if command -v unzip >/dev/null 2>&1; then
        if ! unzip -q "$ZASHBOARD_ZIP" -d "$ZASHBOARD_TMP"; then
            echo "Failed to extract custom Zashboard" >&2
            rm -rf "$ZASHBOARD_TMP"
            return 1
        fi
    elif command -v busybox >/dev/null 2>&1 && busybox unzip --help >/dev/null 2>&1; then
        if ! busybox unzip -q "$ZASHBOARD_ZIP" -d "$ZASHBOARD_TMP"; then
            echo "Failed to extract custom Zashboard" >&2
            rm -rf "$ZASHBOARD_TMP"
            return 1
        fi
    else
        echo "Cannot install custom Zashboard: unzip is unavailable in the build container" >&2
        rm -rf "$ZASHBOARD_TMP"
        return 1
    fi

    if [ ! -f "$ZASHBOARD_DIST/index.html" ]; then
        echo "Custom Zashboard archive must contain dist/index.html" >&2
        rm -rf "$ZASHBOARD_TMP"
        return 1
    fi

    rm -rf "$ZASHBOARD_TARGET"
    mkdir -p "$ZASHBOARD_TARGET"
    cp -a "$ZASHBOARD_DIST"/. "$ZASHBOARD_TARGET"/
    rm -rf "$ZASHBOARD_TMP"
    echo "Installed custom Zashboard into $ZASHBOARD_TARGET"
}

project_install_mosdns_packages() {
    case " ${PACKAGES:-} " in
        *" mosdns-t "*|*" luci-app-mosdns-t "*) ;;
        *)
            return 0
            ;;
    esac

    case "${PROJECT_LUCI_EDITION:-}" in
        24.10)
            MOSDNS_ASSET_EXTENSION=".ipk"
            MOSDNS_CORE_MARKER="/mosdns-t_"
            MOSDNS_LUCI_MARKER="/luci-app-mosdns-t_"
            ;;
        25.12)
            MOSDNS_ASSET_EXTENSION=".apk"
            MOSDNS_CORE_MARKER="/mosdns-t-"
            MOSDNS_LUCI_MARKER="/luci-app-mosdns-t-"
            ;;
        *)
            echo "Unsupported MosDNS-T OpenWrt edition: ${PROJECT_LUCI_EDITION:-unknown}" >&2
            return 1
            ;;
    esac

    MOSDNS_RELEASE_API="https://api.github.com/repos/jasonxtt/mosdns/releases/latest"
    MOSDNS_RELEASE_JSON="$(curl -fsSL --retry 3 --retry-delay 2 "$MOSDNS_RELEASE_API")" || {
        echo "Failed to query the latest MosDNS-T release" >&2
        return 1
    }

    MOSDNS_CORE_URL="$(printf '%s\n' "$MOSDNS_RELEASE_JSON" | awk -F'"' \
        -v marker="$MOSDNS_CORE_MARKER" -v extension="$MOSDNS_ASSET_EXTENSION" \
        '/"browser_download_url":/ && index($0, marker) && index($0, "x86_64") && index($0, extension) { print $4; exit }')"
    MOSDNS_LUCI_URL="$(printf '%s\n' "$MOSDNS_RELEASE_JSON" | awk -F'"' \
        -v marker="$MOSDNS_LUCI_MARKER" -v extension="$MOSDNS_ASSET_EXTENSION" \
        '/"browser_download_url":/ && index($0, marker) && index($0, "x86_64") && index($0, extension) { print $4; exit }')"

    if [ -z "$MOSDNS_CORE_URL" ] || [ -z "$MOSDNS_LUCI_URL" ]; then
        echo "Latest MosDNS-T release has no matching x86_64 ${MOSDNS_ASSET_EXTENSION} packages" >&2
        return 1
    fi

    MOSDNS_PACKAGE_DIR="/home/build/immortalwrt/packages"
    mkdir -p "$MOSDNS_PACKAGE_DIR"
    echo "Downloading latest MosDNS-T packages for ${PROJECT_LUCI_EDITION} x86_64"
    wget -q "$MOSDNS_CORE_URL" -P "$MOSDNS_PACKAGE_DIR" || {
        echo "Failed to download mosdns-t package" >&2
        return 1
    }
    wget -q "$MOSDNS_LUCI_URL" -P "$MOSDNS_PACKAGE_DIR" || {
        echo "Failed to download luci-app-mosdns-t package" >&2
        return 1
    }
}

project_copy_online_firmware_asset() {
    found=0
    for spec in \
        "uefi:*squashfs-combined-efi.img.gz" \
        "legacy:*squashfs-combined.img.gz"; do
        boot_type="${spec%%:*}"
        image_pattern="${spec#*:}"
        image=$(find bin/targets/x86/64 -type f -name "$image_pattern" -print -quit)
        if [ -z "${image:-}" ] || [ ! -f "$image" ]; then
            continue
        fi

        short_hash="$(md5sum "$image" | cut -c1-3)$(sha256sum "$image" | cut -c1-3)"
        online_name="${PROJECT_LUCI_EDITION}-${PROJECT_SOURCE}-${PROJECT_DEVICE_MODEL}-${PROJECT_UPDATE_VERSION}-${boot_type}-${short_hash}${PROJECT_FIRMWARE_SUFFIX}"
        mkdir -p bin/update
        cp -f "$image" "bin/update/$online_name"
        echo "Online update asset: bin/update/$online_name"
        found=1
    done

    if [ "$found" -ne 1 ]; then
        echo "Unable to find an x86 squashfs combined firmware image" >&2
        return 1
    fi
}

project_remove_unneeded_firmware_assets() {
    # Rootfs archives are not bootable images and are not used by AutoUpdate.
    find bin/targets/x86/64 -type f \
        \( -name '*squashfs-rootfs.img.gz' -o -name '*squashfs-rootfs.img' \) \
        -print -delete
}
