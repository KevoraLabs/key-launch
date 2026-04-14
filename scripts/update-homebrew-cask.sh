#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  update-homebrew-cask.sh --cask-token <token> --version <version> --sha256 <sha256> --url <url> [options]

Options:
  --cask-file <path>   Path to cask file. Defaults to <repo>/Casks/<token>.rb
  --app-name <name>    App bundle name for new cask files
  --desc <text>        Description for new cask files
  --homepage <url>     Homepage for new cask files
  --verified <value>   verified stanza value for the cask URL
EOF
}

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "Missing required value: $name" >&2
    exit 1
  fi
}

cask_token=""
cask_file=""
version=""
sha256=""
url=""
app_name=""
desc=""
homepage=""
verified=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cask-token)
      cask_token="$2"
      shift 2
      ;;
    --cask-file)
      cask_file="$2"
      shift 2
      ;;
    --version)
      version="$2"
      shift 2
      ;;
    --sha256)
      sha256="$2"
      shift 2
      ;;
    --url)
      url="$2"
      shift 2
      ;;
    --app-name)
      app_name="$2"
      shift 2
      ;;
    --desc)
      desc="$2"
      shift 2
      ;;
    --homepage)
      homepage="$2"
      shift 2
      ;;
    --verified)
      verified="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_value "cask-token" "$cask_token"
require_value "version" "$version"
require_value "sha256" "$sha256"
require_value "url" "$url"
require_value "app-name" "$app_name"
require_value "desc" "$desc"
require_value "homepage" "$homepage"

if [[ -z "$cask_file" ]]; then
  cask_file="$ROOT_DIR/Casks/${cask_token}.rb"
fi

mkdir -p "$(dirname "$cask_file")"

export CASK_FILE="$cask_file"
export CASK_TOKEN="$cask_token"
export CASK_VERSION="$version"
export CASK_SHA256="$sha256"
export CASK_URL="$url"
export CASK_APP_NAME="$app_name"
export CASK_DESC="$desc"
export CASK_HOMEPAGE="$homepage"
export CASK_VERIFIED="$verified"

ruby <<'RUBY'
path = ENV.fetch("CASK_FILE")
token = ENV.fetch("CASK_TOKEN")
version = ENV.fetch("CASK_VERSION")
sha256 = ENV.fetch("CASK_SHA256")
url = ENV.fetch("CASK_URL")
app_name = ENV.fetch("CASK_APP_NAME")
desc = ENV.fetch("CASK_DESC")
homepage = ENV.fetch("CASK_HOMEPAGE")
verified = ENV.fetch("CASK_VERIFIED")

url_block = if verified.empty?
  "  url \"#{url}\""
else
  "  url \"#{url}\",\n      verified: \"#{verified}\""
end

content = [
  "cask \"#{token}\" do",
  "  version \"#{version}\"",
  "  sha256 \"#{sha256}\"",
  "",
  url_block,
  "  name \"#{app_name}\"",
  "  desc \"#{desc}\"",
  "  homepage \"#{homepage}\"",
  "",
  "  app \"#{app_name}.app\"",
  "end",
  ""
].join("\n")

File.write(path, content)
RUBY

echo "Updated $cask_file"
