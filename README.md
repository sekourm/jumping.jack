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
lib/main.dart              # point d'entrée + init Supabase
lib/app.dart               # MaterialApp + letterboxing web (480 max)
lib/game/                  # FlameGame, components, physique
lib/services/              # AudioManager, Preferences, BattleRoyaleService
lib/state/                 # GameState, DeathReason
lib/ui/                    # screens (home, lobby, settings, game) + widgets
lib/config/supabase_config.dart  # URL + anon key Supabase
supabase/migrations/       # SQL à exécuter une fois sur le projet Supabase
web/                       # template index.html + favicon + manifest PWA
test/widget_test.dart      # smoke test (mount du GameWidget)
.fvmrc                     # pin Flutter 3.41.9
pubspec.yaml               # dépendances (flame, flame_audio, supabase_flutter, …)
vercel.json                # build command Flutter web pour Vercel
.vercelignore              # exclut build/ .dart_tool/ etc. de l'upload
```

## Backend — Supabase (mode Battle Royale)

Le mode **Battle Royale** utilise [Supabase](https://supabase.com) pour le matchmaking + sync temps réel via Realtime channels (Postgres Changes). Le mode **Solo** ne dépend pas du backend et fonctionne hors-ligne.

### Setup d'un nouveau projet Supabase

1. Créer un projet sur [supabase.com](https://supabase.com) (free tier suffit, choisir la région la plus proche)
2. Récupérer dans **Settings → API** :
   - **Project URL** (`https://xxxxx.supabase.co`)
   - **anon public key** (`sb_publishable_…` — safe à embarquer côté client)
3. Reporter ces deux valeurs dans `lib/config/supabase_config.dart` :
   ```dart
   static const String url = 'https://xxxxx.supabase.co';
   static const String anonKey = 'sb_publishable_…';
   ```
4. Ouvrir **SQL Editor → New query**, copier le contenu de `supabase/migrations/0001_battle_royale.sql`, lancer **Run**. Le script crée :
   - Tables `br_rooms` + `br_room_players`
   - Policies RLS ouvertes (pas d'auth utilisateur dans ce jeu)
   - Publication realtime sur les deux tables
   - Fonction RPC `join_or_create_br_room()` qui réserve un slot atomiquement

### Vérification rapide

```bash
curl -X POST https://xxxxx.supabase.co/rest/v1/rpc/join_or_create_br_room \
  -H "apikey: sb_publishable_…" \
  -H "Authorization: Bearer sb_publishable_…" \
  -H "Content-Type: application/json" \
  -d '{"p_player_id":"_test","p_name":"_test"}'
```

Réponse attendue : `[{"room_id":"…","slot_index":0}]` (HTTP 200). Si HTTP 404 + `PGRST202` → le SQL n'est pas exécuté.

### Sécurité

- La **anon key** (`sb_publishable_…`) est PUBLIQUE — safe à committer / shipper. Les policies RLS contrôlent ce qu'elle peut faire.
- La **secret/service-role key** (`sb_secret_…`) bypass RLS — **JAMAIS** dans le code client, jamais committée. Elle n'est pas nécessaire pour faire tourner le jeu.

## Déploiement — Vercel

L'app est déployée sur **Vercel** avec un build container qui clone Flutter SDK + lance `flutter build web --release`.

### URLs

- **Production** : https://jumping-jack-six.vercel.app
- **Dashboard** : https://vercel.com/sekourms-projects/jumping-jack
- Repo Git : `github.com/sekourm/jumping.jack` (auto-deploy au push sur `main`)

### Comment Vercel build une app Flutter

Vercel ne supporte pas Flutter nativement. La config se trouve dans `vercel.json` :

```json
{
  "buildCommand": "git clone https://github.com/flutter/flutter.git --depth 1 -b 3.41.9 _flutter && _flutter/bin/flutter config --enable-web --no-analytics && _flutter/bin/flutter pub get && _flutter/bin/flutter build web --release",
  "outputDirectory": "build/web",
  "installCommand": "echo skip",
  "framework": null
}
```

À chaque deploy, Vercel :
1. Clone le SDK Flutter à la version pinnée (`3.41.9`)
2. Active le support web + lance `flutter pub get`
3. Compile en `--release` → output dans `build/web/`
4. Sert le contenu de `build/web/` en static

Build typique : ~2 minutes (clone Flutter SDK + compilation Dart→JS + tree-shaking icons).

### Déployer manuellement (en plus du auto-deploy git)

```bash
npm i -g vercel              # une fois
vercel link                  # lier le dossier au projet (interactive)
vercel                       # deploy preview (URL unique)
vercel --prod                # deploy production (met à jour jumping-jack-six.vercel.app)
```

### Versionning / vérification du deploy

La constante `kAppVersion` dans `lib/ui/screens/home_screen.dart` est affichée en bas-droite du menu. Bump-la avant un push pour vérifier que la nouvelle version est bien servie après le rebuild.
