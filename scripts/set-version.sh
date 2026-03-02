#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"

# Portable sed -i (BSD vs GNU)
sedi() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Chart.yaml
sedi -E "s/^version: ('.*'|.*)$/version: $VERSION/" waldur/Chart.yaml
sedi -E "s/^appVersion: ('.*'|.*)$/appVersion: \"$VERSION\"/" waldur/Chart.yaml

# Mastermind imageTag (2-space indent, top-level under waldur:)
sedi -E "s/^  imageTag: \".*\"$/  imageTag: \"$VERSION\"/" waldur/values.yaml

# Homeport imageTag (4-space indent, under waldur.homeport:)
awk -v ver="$VERSION" '
  /^  homeport:$/ { in_homeport = 1 }
  in_homeport && /^    imageTag: / {
    $0 = "    imageTag: \"" ver "\""
    in_homeport = 0
  }
  { print }
' waldur/values.yaml > waldur/values.yaml.tmp && mv waldur/values.yaml.tmp waldur/values.yaml

echo "Version set to $VERSION"
echo "  Chart.yaml: version + appVersion"
echo "  values.yaml: waldur.imageTag (mastermind)"
echo "  values.yaml: waldur.homeport.imageTag"
