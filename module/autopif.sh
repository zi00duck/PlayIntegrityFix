#!/bin/sh
PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:/data/data/com.termux/files/usr/bin:$PATH
MODDIR=/data/adb/modules/playintegrityfix

download() {
	if command -v curl > /dev/null 2>&1; then
		curl --connect-timeout 10 -s "$1"
        else
		busybox wget -T 10 --no-check-certificate -qO - "$1"
        fi
}  

set_random_beta() {
    if [ "$(echo "$MODEL_LIST" | wc -l)" -ne "$(echo "$PRODUCT_LIST" | wc -l)" ]; then
        echo "Error: MODEL_LIST and PRODUCT_LIST have different lengths."
    fi
    count=$(echo "$MODEL_LIST" | wc -l)
    rand_index=$(( $$ % count ))
    MODEL=$(echo "$MODEL_LIST" | sed -n "$((rand_index + 1))p")
    PRODUCT=$(echo "$PRODUCT_LIST" | sed -n "$((rand_index + 1))p")
    DEVICE=$(echo "$PRODUCT" | sed 's/_beta//')
}

# lets try to use tmpfs for processing
TEMPDIR="$MODDIR/autopif"
[ -w /sbin ] && TEMPDIR="/sbin/autopif"
[ -w /debug_ramdisk ] && TEMPDIR="/debug_ramdisk/autopif"
mkdir -p "$TEMPDIR"
cd "$TEMPDIR"

download https://developer.android.com/topic/generic-system-image/releases > PIXEL_GSI_HTML || {
	echo "download failed!"
	exit 0
	}
grep -m1 -o 'li>.*(Beta)' PIXEL_GSI_HTML | cut -d\> -f2
grep -m1 -o 'Date:.*' PIXEL_GSI_HTML

RELEASE="$(grep -m1 'corresponding Google Pixel builds' PIXEL_GSI_HTML | grep -o '/versions/.*' | cut -d/ -f3)"
ID="$(grep -m1 -o 'Build:.*' PIXEL_GSI_HTML | cut -d' ' -f2)"
INCREMENTAL="$(grep -m1 -o "$ID-.*-" PIXEL_GSI_HTML | cut -d- -f2)"

download "https://developer.android.com$(grep -m1 'corresponding Google Pixel builds' PIXEL_GSI_HTML | grep -o 'href.*' | cut -d\" -f2)" > PIXEL_GET_HTML || {
	echo "download failed!"
	exit 0
	}
download "https://developer.android.com$(grep -m1 'Factory images for Google Pixel' PIXEL_GET_HTML | grep -o 'href.*' | cut -d\" -f2)" > PIXEL_BETA_HTML || {
	echo "download failed!"
	exit 0
	}

MODEL_LIST="$(grep -A1 'tr id=' PIXEL_BETA_HTML | grep 'td' | sed 's;.*<td>\(.*\)</td>;\1;')"
PRODUCT_LIST="$(grep -o 'factory/.*_beta' PIXEL_BETA_HTML | cut -d/ -f2)"

download https://source.android.com/docs/security/bulletin/pixel > PIXEL_SECBULL_HTML || {
	echo "download failed!"
	exit 0
	}

SECURITY_PATCH="$(grep -A15 "$(grep -m1 -o 'Security patch level:.*' PIXEL_GSI_HTML | cut -d' ' -f4-)" PIXEL_SECBULL_HTML | grep -m1 -B1 '</tr>' | grep 'td' | sed 's;.*<td>\(.*\)</td>;\1;')"

echo "- Selecting Pixel Beta device ..."
[ -z "$PRODUCT" ] && set_random_beta
echo "$MODEL ($PRODUCT)"

sdk_version="$(getprop ro.build.version.sdk)"
sdk_version="${sdk_version:-25}"
echo "Device SDK version: $sdk_version"

echo "- Dumping values to pif.json ..."
cat <<EOF | tee pif.json
{
  "FINGERPRINT": "google/$PRODUCT/$DEVICE:$RELEASE/$ID/$INCREMENTAL:user/release-keys",
  "MANUFACTURER": "Google",
  "MODEL": "$MODEL",
  "SECURITY_PATCH": "$SECURITY_PATCH",
  "DEVICE_INITIAL_SDK_INT": $sdk_version
}
EOF

cp "$TEMPDIR/pif.json" "/data/adb/pif.json"
echo "- new pif.json saved to /data/adb/pif.json"

cd "$MODPATH"

echo "- Cleaning up ..."
rm -rf "$TEMPDIR"

for i in $(busybox pidof com.google.android.gms.unstable); do
	echo "- Killing pid $i"
	kill -9 $i 
done
