#!/usr/bin/env bash
set -euo pipefail
probe_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
command -v flutter >/dev/null || { echo 'Flutter не найден. См. clients/flutter-probe/README.md'; exit 1; }
command -v python3 >/dev/null
flutter --version
if [[ ! -d "$probe_root/app" ]]; then
  probe_temp="$(mktemp -d "$probe_root/.scaffold.XXXXXX")"
  trap 'rm -rf -- "$probe_temp"' EXIT
  flutter create --no-pub --platforms=android,linux,windows --org ru.sovdelo \
    --project-name sovdelo_probe "$probe_temp"
  rm -rf -- "$probe_temp/test"
  rm -f -- "$probe_temp/analysis_options.yaml"
  cp -R "$probe_root/template/." "$probe_temp/"
  python3 "$probe_root/configure_android.py" "$probe_temp"
  flutter --version --machine > "$probe_temp/flutter-sdk.json"
  mv -- "$probe_temp" "$probe_root/app"
  trap - EXIT
fi
# Re-running never replaces source files or native platform customizations.
cd "$probe_root/app"
flutter pub get
flutter analyze --no-fatal-infos
flutter test
printf '\nГотово. Запуск: cd clients/flutter-probe/app && flutter run -d linux\n'
