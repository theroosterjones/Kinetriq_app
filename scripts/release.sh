#!/bin/bash
#
# Kinetriq release: version bump -> archive -> distribution export -> TestFlight upload.
#
#   scripts/release.sh                  bump the build number, keep the marketing version
#   scripts/release.sh 3.5.7            set the marketing version, bump the build number
#   scripts/release.sh 3.5.7 55         set both explicitly
#   scripts/release.sh --no-upload      archive and export only, stop before uploading
#   scripts/release.sh --no-bump        release the current version as-is
#
# The archive lands in Xcode's Organizer (~/Library/Developer/Xcode/Archives/<date>/)
# so past releases stay browsable there.

set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID="YCKQ2HTCQ3"
SCHEME="Kinetriq"
PROJECT="Kinetriq.xcodeproj"

upload=true
bump=true
version=""
build=""

for arg in "$@"; do
    case "$arg" in
        --no-upload) upload=false ;;
        --no-bump)   bump=false ;;
        -h|--help)   sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)          echo "Unknown option: $arg" >&2; exit 1 ;;
        *)
            if [ -z "$version" ]; then version="$arg"
            elif [ -z "$build" ]; then build="$arg"
            else echo "Too many arguments: $arg" >&2; exit 1
            fi
            ;;
    esac
done

fail() { echo "error: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

# --- Preflight -------------------------------------------------------------
# Both of these are gitignored, so a fresh clone hits this before a 90s archive.

[ -f "Sources/pose_landmarker_full.task" ] || fail \
    "Missing Sources/pose_landmarker_full.task (gitignored). Download it first — see README."

[ -f "Config/KinetriqSecrets.xcconfig" ] || fail \
    "Missing Config/KinetriqSecrets.xcconfig (gitignored). Copy Config/KinetriqSecrets.example.xcconfig and fill it in."

command -v xcodegen >/dev/null || fail "xcodegen not installed. brew install xcodegen"

if [ -n "$(git status --porcelain)" ]; then
    echo "warning: working tree has uncommitted changes; they will be included in this build."
fi

# --- Resolve the version to ship -------------------------------------------

current_version=$(grep -m1 'MARKETING_VERSION: ' project.yml | sed 's/.*"\(.*\)".*/\1/')
current_build=$(grep -m1 'CURRENT_PROJECT_VERSION: ' project.yml | sed 's/.*"\(.*\)".*/\1/')

if [ "$bump" = false ]; then
    version="$current_version"
    build="$current_build"
else
    [ -n "$version" ] || version="$current_version"
    [ -n "$build" ]   || build=$((current_build + 1))
fi

echo "Releasing Kinetriq $version ($build)  [was $current_version ($current_build)]"

# project.yml carries the version in six places: the two build settings, plus
# hardcoded fallbacks inside each of the two MediaPipe plist-patch scripts.
# Archive builds read the fallbacks when the build settings aren't exported into
# the script environment, so all six have to move together.
if [ "$bump" = true ]; then
    step "Bumping project.yml to $version ($build)"
    perl -pi -e "
        s/MARKETING_VERSION:-[0-9.]+/MARKETING_VERSION:-$version/g;
        s/CURRENT_PROJECT_VERSION:-[0-9]+/CURRENT_PROJECT_VERSION:-$build/g;
        s/MARKETING_VERSION: \"[0-9.]+\"/MARKETING_VERSION: \"$version\"/;
        s/CURRENT_PROJECT_VERSION: \"[0-9]+\"/CURRENT_PROJECT_VERSION: \"$build\"/;
    " project.yml

    found=$(grep -cE "MARKETING_VERSION.*$version|CURRENT_PROJECT_VERSION.*$build" project.yml)
    [ "$found" -eq 6 ] || fail "expected 6 version references in project.yml, updated $found"
fi

step "Regenerating the Xcode project"
xcodegen generate

# --- Archive ---------------------------------------------------------------

archive_dir="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
archive_path="$archive_dir/Kinetriq $version ($build).xcarchive"
mkdir -p "$archive_dir"

step "Archiving to Organizer: $archive_path"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive_path" \
    -allowProvisioningUpdates \
    -quiet

# Trust the artifact, not the config: confirm the archive really carries the
# version we intended before it goes anywhere.
archived_version=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" "$archive_path/Info.plist")
archived_build=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$archive_path/Info.plist")
[ "$archived_version" = "$version" ] || fail "archive says $archived_version, expected $version"
[ "$archived_build" = "$build" ]     || fail "archive says build $archived_build, expected $build"
echo "Archive verified: $archived_version ($archived_build)"

# --- Export / upload -------------------------------------------------------

# manageAppVersionAndBuildNumber=false stops App Store Connect from silently
# auto-incrementing the build number away from the one we just committed.
export_dir="build/release-$version-$build"
rm -rf "$export_dir"
mkdir -p "$export_dir"

if [ "$upload" = true ]; then destination="upload"; else destination="export"; fi

cat > "$export_dir/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>uploadSymbols</key>
	<true/>
	<key>destination</key>
	<string>$destination</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
PLIST

if [ "$upload" = true ]; then
    step "Exporting and uploading to TestFlight"
else
    step "Exporting signed IPA (skipping upload)"
fi

# MediaPipe ships prebuilt frameworks without dSYMs, so "Upload Symbols Failed"
# warnings for them are expected and do not block TestFlight.
xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportOptionsPlist "$export_dir/ExportOptions.plist" \
    -exportPath "$export_dir" \
    -allowProvisioningUpdates

step "Done: Kinetriq $version ($build)"
echo "Archive: $archive_path"
if [ "$upload" = true ]; then
    echo "Uploaded to App Store Connect — processing takes ~5-15 min."
    echo "Answer the export-compliance prompt in App Store Connect to release to testers."
else
    echo "IPA: $export_dir/Kinetriq.ipa"
fi
if [ "$bump" = true ]; then
    echo
    echo "Still to do: commit the version bump and update the release notes in AGENTS.md."
fi
