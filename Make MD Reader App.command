#!/bin/bash
# Make MD Reader App — builds "MD Reader.app" in ~/Applications.
# Run it once on your Mac:
#   bash "Make MD Reader App.command"
# It wraps md-reader.html + md-server.py (kept next to this script) into a
# small compiled applet that macOS can open .md files with. v2: the app is a
# real osacompile applet, because Finder hands opened files to apps as an
# "open" event — a plain script bundle can't receive it and started with no
# file. The applet receives the file properly and passes its path to the
# server. Nothing is installed anywhere else.

set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/MD Reader.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "Building MD Reader.app (v2, applet) ..."

# --- python3 is required (it runs the tiny local bridge server) -------------
PYTHON3="/usr/bin/python3"
if [ ! -x "$PYTHON3" ]; then
  PYTHON3="$(command -v python3 2>/dev/null || true)"
fi
if [ -z "${PYTHON3:-}" ] || [ ! -x "$PYTHON3" ]; then
  osascript -e 'display dialog "MD Reader needs Python 3, which was not found on this Mac. Install the Xcode Command Line Tools (run: xcode-select --install) and then run this file again." buttons {"OK"} default button "OK" with icon caution' >/dev/null 2>&1
  echo "Python 3 not found — see the dialog. Aborting."
  read -r -p "Press Return to close this window."
  exit 1
fi
echo "Using Python: $PYTHON3"

# --- osacompile ships with macOS ---------------------------------------------
if ! command -v osacompile >/dev/null 2>&1; then
  echo "osacompile not found (it is part of macOS). Aborting."
  read -r -p "Press Return to close this window."
  exit 1
fi

# --- sources must be next to this script --------------------------------------
for f in md-reader.html md-server.py; do
  if [ ! -f "$DIR/$f" ]; then
    osascript -e "display dialog \"$f is missing. Keep md-reader.html, md-server.py and this .command file together in the same folder and run it again.\" buttons {\"OK\"} default button \"OK\" with icon caution" >/dev/null 2>&1
    echo "Missing $f next to this script. Aborting."
    read -r -p "Press Return to close this window."
    exit 1
  fi
done

# --- the applet source ---------------------------------------------------------
# Finder delivers opened files to the applet's `on open` handler. The applet
# starts the bridge server (detached, output to /tmp/mdreader.log) with the
# file's POSIX path as its argument; the server opens the editor in the
# default browser. `on run` (app double-clicked directly) opens a blank doc.
TMPD="$(mktemp -d)"
cat > "$TMPD/mdreader.applescript" << 'APPLESCRIPT'
on run
	my startServer("")
end run

on open theFiles
	repeat with f in theFiles
		my startServer(POSIX path of f)
	end repeat
end open

on startServer(thePath)
	set serverScript to POSIX path of (path to resource "md-server.py")
	set cmd to "nohup /usr/bin/python3 " & quoted form of serverScript
	if thePath is not "" then
		set cmd to cmd & " " & quoted form of thePath
	end if
	set cmd to cmd & " >> /tmp/mdreader.log 2>&1 &"
	try
		do shell script cmd
	on error errMsg
		display dialog "MD Reader could not start its local server:" & return & errMsg buttons {"OK"} default button "OK" with icon caution
	end try
end startServer
APPLESCRIPT

# --- build the bundle ----------------------------------------------------------
mkdir -p "$HOME/Applications"
if [ -d "$APP" ]; then
  echo "Removing the previous MD Reader.app ..."
  rm -rf "$APP"
fi
if ! osacompile -o "$APP" "$TMPD/mdreader.applescript"; then
  echo "osacompile failed. Aborting."
  read -r -p "Press Return to close this window."
  exit 1
fi
mkdir -p "$APP/Contents/Resources"
cp "$DIR/md-reader.html" "$DIR/md-server.py" "$APP/Contents/Resources/"
chmod +x "$APP/Contents/Resources/md-server.py"

# --- register .md handling in the applet's Info.plist ---------------------------
"$PYTHON3" - "$APP/Contents/Info.plist" << 'PYEOF'
import plistlib, sys

path = sys.argv[1]
with open(path, "rb") as f:
    plist = plistlib.load(f)

plist["CFBundleName"] = "MD Reader"
plist["CFBundleDisplayName"] = "MD Reader"
plist["CFBundleIdentifier"] = "jp.moab.mdreader"
plist["CFBundleDocumentTypes"] = [
    {
        "CFBundleTypeName": "Markdown Document",
        "CFBundleTypeRole": "Editor",
        "LSHandlerRank": "Owner",
        "CFBundleTypeExtensions": ["md", "markdown", "mdown", "mkd"],
        "LSItemContentTypes": ["net.daringfireball.markdown"],
    }
]
plist["UTImportedTypeDeclarations"] = [
    {
        "UTTypeIdentifier": "net.daringfireball.markdown",
        "UTTypeDescription": "Markdown Document",
        "UTTypeConformsTo": ["public.plain-text"],
        "UTTypeTagSpecification": {
            "public.filename-extension": ["md", "markdown", "mdown", "mkd"],
            "public.mime-type": ["text/markdown"],
        },
    }
]

with open(path, "wb") as f:
    plistlib.dump(plist, f, fmt=plistlib.FMT_XML, sort_keys=True)
print("Info.plist updated:", path)
PYEOF

# The sources came from a download and may carry a quarantine flag; the app is
# built locally and should not inherit it.
xattr -cr "$APP" >/dev/null 2>&1 || true

# Register with LaunchServices so Finder knows the app exists.
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
fi

# Validate the plist if plutil is around.
if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$APP/Contents/Info.plist" || true
fi

rm -rf "$TMPD"

echo ""
echo "Done: $APP"
echo ""
echo "To make MD Reader the default for .md files:"
echo "  1. Right-click any .md file in Finder and choose 'Get Info'."
echo "  2. Under 'Open with:', choose 'MD Reader'."
echo "  3. Click 'Change All...' and confirm."
echo ""
echo "After that, double-clicking any .md file opens it in MD Reader"
echo "(the editor appears in your default browser; a small background"
echo "server does the file reading/writing). Opening 'MD Reader' from"
echo "your Applications folder starts a blank document."
echo "Server log for troubleshooting: /tmp/mdreader.log"
echo ""
read -r -p "Press Return to close this window."
