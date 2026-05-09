# jumping_jack

Jeu mobile/web/desktop construit avec **Flutter** + **Flame**.

## Versions utilisées

| Outil   | Version  |
| ------- | -------- |
| Flutter | `3.41.9` (stable) |
| Dart    | `3.11.5` |
| Flame   | `1.37.0` |
| FVM     | `4.1.0`  |

La version Flutter est figée au projet via `.fvmrc` — tout collaborateur avec FVM installé récupère automatiquement la bonne version.

## Prérequis

```bash
brew tap leoafarias/fvm
brew install fvm
fvm install 3.41.9
fvm global 3.41.9          # rend `flutter` dispo partout
```

Ajouter dans `~/.zshrc` :

```bash
export PATH="$HOME/fvm/default/bin:$PATH"
```

## Lancer le jeu

### Web (Chrome)

```bash
flutter run -d chrome
```

Compile l'app en JavaScript et l'ouvre automatiquement dans Chrome avec hot reload activé. C'est la façon la plus rapide d'itérer sur le gameplay : pas besoin de simulateur, modifications visibles en moins d'une seconde.

### Autres plateformes disponibles

```bash
flutter devices                  # liste les devices/émulateurs détectés
flutter run                      # device par défaut (demande si plusieurs)
flutter run -d macos             # macOS desktop
flutter run -d ios               # simulateur iOS (nécessite Xcode)
flutter run -d android           # émulateur ou device Android
flutter run -d windows           # Windows desktop
flutter run -d linux             # Linux desktop
```

### Commandes utiles pendant `flutter run`

| Touche | Action |
| ------ | ------ |
| `r`    | Hot reload (réapplique le code, garde l'état) |
| `R`    | Hot restart (redémarre l'app à zéro) |
| `p`    | Toggle debug paint (overlay des bounds) |
| `o`    | Toggle plateforme (iOS ⇄ Android) |
| `q`    | Quitter |

### Build de production

```bash
flutter build web                # dist dans build/web/
flutter build apk                # APK Android
flutter build ipa                # IPA iOS (signé)
flutter build macos              # .app macOS
```

## Qualité

```bash
flutter analyze                  # analyse statique
flutter test                     # tests unitaires + widget
flutter pub outdated             # dépendances à mettre à jour
flutter pub upgrade              # upgrade dans les contraintes du pubspec
```

## Gameplay

Tap/clic à l'écran → le carré jaune saute. Gravité gérée dans `lib/main.dart` (`JumpingJackGame`).

## Structure

```
lib/main.dart              # point d'entrée + JumpingJackGame (FlameGame)
test/widget_test.dart      # smoke test (mount du GameWidget)
.fvmrc                     # pin Flutter 3.41.9
pubspec.yaml               # dépendances (flame: ^1.37.0)
```
