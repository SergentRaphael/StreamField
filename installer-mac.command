#!/bin/bash
cd "$(dirname "$0")"
echo "=== Installation de StreamField ==="
command -v flutter >/dev/null || { echo "Flutter n'est pas installé. Voir README.md"; exit 1; }
flutter pub get && dart run tool/setup.dart && flutter test && {
  echo "Tout est prêt ! Lancement de StreamField…"
  flutter run -d macos
} || echo "Une erreur est survenue : copie le message ci-dessus et envoie-le moi."
