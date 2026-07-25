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
