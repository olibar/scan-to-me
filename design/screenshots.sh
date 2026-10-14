#!/bin/zsh
# screenshots.sh - App Store screenshots of Scan to Me, captured from the
# simulator: 4 screens x 4 languages x (iPhone 6.3", iPad 13"). App Store
# Connect's iPhone slot is "iPhone with Dynamic Island (medium display)":
# 1206 x 2622 (6.3") or 1179 x 2556 (6.1"); 6.9" images are rejected there.
#
# Usage, from the repository root:  zsh design/screenshots.sh
# Output: appstore/screenshots/<device>/<language>/NN-<screen>.png, numbered in
# upload order (git-ignored). Needs Xcode and the simulators below.
#
# A stand-in printer (design/screenshots/fake_printer.py) runs on this Mac so
# the app shows a printer as Ready; the app's state (printers "Office" and
# "Home", recent scans) is written into the simulator before launching. The
# debug-only launch options -ScreenshotTab and -ScreenshotPreview open the
# screens, since the simulator cannot tap.
set -e
ROOT=${0:A:h:h}
OUT="$ROOT/appstore/screenshots"
WORK=$(mktemp -d)
IP=$(ipconfig getifaddr en0 || ipconfig getifaddr en1)
BUNDLE=com.obarlier.scantome
DEVICES=("iPhone 17 Pro|iphone-6.3" "iPad Pro 13-inch (M5)|ipad-13")
LANGS=(en fr es zh-Hans)
SCREENS=("01-listening|" "02-scan-preview|-ScreenshotPreview YES" "03-printers|-ScreenshotTab printers" "04-settings|-ScreenshotTab settings")

echo "screenshots: building the app for the simulator"
xcodebuild -project "$ROOT/ScanToMe.xcodeproj" -scheme ScanToMe -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$WORK/dd" build -quiet
APP="$WORK/dd/Build/Products/Debug-iphonesimulator/ScanToMe.app"
swift "$ROOT/design/screenshots/sample_scans.swift" "$WORK"

echo "screenshots: starting the stand-in printer on $IP:8080"
python3 "$ROOT/design/screenshots/fake_printer.py" 8080 2>"$WORK/fake.log" &
FAKE=$!
trap 'kill $FAKE 2>/dev/null' EXIT

for entry in $DEVICES; do
  NAME=${entry%%|*}; DIR=${entry#*|}
  UDID=$(xcrun simctl list devices available | grep -F "$NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
  [[ -n $UDID ]] || { echo "screenshots: simulator $NAME not found"; exit 1; }
  echo "screenshots: $NAME ($UDID)"
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
  xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true
  xcrun simctl uninstall "$UDID" $BUNDLE 2>/dev/null || true
  xcrun simctl install "$UDID" "$APP"
  DATA=$(xcrun simctl get_app_container "$UDID" $BUNDLE data)
  write_state() {  # $1 = language: sample names in that language
  python3 - "$DATA" "$WORK" "$IP" "$DIR" "$1" <<'PY'
import json, os, shutil, sys, uuid, datetime
data, work, ip, device, lang = sys.argv[1:6]
# Sample names per language: office printer, home printer, this device.
NAMES = {"en": ("Office", "Home", "My %s"), "fr": ("Bureau", "Maison", "Mon %s"),
         "es": ("Oficina", "Casa", "Mi %s"), "zh-Hans": ("\u529e\u516c\u5ba4", "\u5bb6", "\u6211\u7684 %s")}
office, home, mine = NAMES[lang]
phone = mine % ("iPad" if device.startswith("ipad") else "iPhone")
docs = os.path.join(data, "Documents"); os.makedirs(docs, exist_ok=True)
state_dir = os.path.join(data, "Library", "Application Support", "ScanToMe"); os.makedirs(state_dir, exist_ok=True)
APPLE_EPOCH = 978307200  # 2001-01-01 UTC, the reference date of Swift's Date
today = datetime.datetime.now().replace(second=0, microsecond=0)
def at(days, h, m):
    return (today - datetime.timedelta(days=days)).replace(hour=h, minute=m)
scans = [  # newest first: (source, when, pages, format, printer)
    ("receipt.pdf", at(0, 8, 42), 1, "pdf", office),
    ("letter.pdf", at(0, 8, 15), 2, "pdf", office),
    ("photo.jpg", at(1, 17, 30), 1, "jpeg", home),
    ("letter.pdf", at(1, 17, 2), 2, "pdf", home),
]
recent = []
for src, when, pages, fmt, printer in scans:
    name = "scan_%s.%s" % (when.strftime("%Y-%m-%d_%H%M%S"), "jpg" if fmt == "jpeg" else "pdf")
    shutil.copy(os.path.join(work, src), os.path.join(docs, name))
    recent.append({"id": str(uuid.uuid4()).upper(), "url": "file://" + os.path.join(docs, name),
                   "date": when.timestamp() - APPLE_EPOCH, "pages": pages, "format": fmt, "printer": printer})
state = {
    "printers": [
        {"id": str(uuid.uuid4()).upper(), "displayName": office, "host": ip, "port": 8080},
        {"id": str(uuid.uuid4()).upper(), "displayName": home, "serviceName": "Printer [5C2A91]",
         "uuid": "0b7e3c52-1f4d-4a6e-9c3a-5c2a91d0e7f4", "host": "192.168.1.20", "port": 8080},
    ],
    "preferences": {"destinationName": phone, "format": "pdf", "resolution": 300, "colorMode": "color",
                    "paper": "a4", "filenamePattern": "scan_{date}_{time}", "pageTimeout": 120,
                    "saveJPEGToPhotos": False, "trimMargins": True},
    "outputLocation": {"documents": {}},
    "recentScans": recent,
    "wantsListening": True,
}
json.dump(state, open(os.path.join(state_dir, "state.json"), "w"))
PY
  }
  for lang in $LANGS; do
    mkdir -p "$OUT/$DIR/$lang"
    xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true
    rm -f "$DATA/Documents"/scan_*(N)   # (N): no error when none exist yet
    write_state "$lang"
    for screen in $SCREENS; do
      FILE=${screen%%|*}; ARGS=(${(z)${screen#*|}})
      xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true
      xcrun simctl launch "$UDID" $BUNDLE -AppleLanguages "($lang)" -AppleLocale "${lang%%-*}" $ARGS >/dev/null
      sleep 9   # listening reaches Ready, the Home printer is found absent
      xcrun simctl io "$UDID" screenshot "$OUT/$DIR/$lang/$FILE.png" >/dev/null 2>&1
      echo "screenshots: $DIR/$lang/$FILE.png"
    done
  done
  xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true
done
echo "screenshots: done, see $OUT"
