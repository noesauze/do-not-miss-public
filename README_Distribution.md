# Distribution macOS hors Mac App Store

Ce document prépare `Do Not Miss` pour une distribution macOS hors Mac App Store avec une chaîne propre:

1. archive signée
2. export `Developer ID`
3. notarization
4. stapling
5. packaging DMG
6. validation sur machine propre

Les scripts fournis sont:

- `Scripts/archive_app.sh`
- `Scripts/notarize_app.sh`
- `Scripts/build_dmg.sh`

Le template d’export utilisé par défaut est:

- `build/export/ExportOptions.plist`

Configuration locale recommandée:

- `Config/Shared.xcconfig` est versionné
- `Config/Local.xcconfig` doit rester local et non commité
- `Config/Local.xcconfig.example` sert de modèle

## Pré-requis Apple Developer

- Être membre de l’Apple Developer Program.
- Disposer d’un certificat `Developer ID Application`.
- Utiliser une version récente de Xcode. Apple recommande d’utiliser la dernière version de Xcode pour signer et notarizer les apps distribuées hors App Store.
- Pour la notarization, configurer soit:
  - un profil `notarytool` stocké dans le trousseau, recommandé
  - soit des credentials explicites `APPLE_ID`, `APP_SPECIFIC_PASSWORD`, `TEAM_ID`

Si l’app utilise des capacités avancées Apple côté Developer ID, un provisioning profile Developer ID peut être nécessaire. Apple l’indique pour certains cas comme CloudKit ou push notifications. Pour cette app, il faut vérifier dans `Signing & Capabilities` que seules les capacités réellement nécessaires sont actives.

Sources Apple utilisées:

- [Signing your apps for Gatekeeper](https://developer.apple.com/developer-id/)
- [Developer ID support](https://developer.apple.com/support/developer-id/)
- [Distributing software on macOS](https://developer.apple.com/macos/distribution/)

## Réglages Xcode à vérifier

### Dans Xcode GUI

Dans `TARGETS > Do Not Miss > General`:

- `Bundle Identifier`: doit être stable et cohérent avec les credentials OAuth.
- `Version` et `Build`: incrémenter avant chaque release.
- `Deployment Target`: corriger pour macOS 13+.

Important: dans l’état actuel du projet, `MACOSX_DEPLOYMENT_TARGET` est configuré à `26.3` dans `Do Not Miss.xcodeproj/project.pbxproj`. Pour une cible macOS 13+, il faut le remettre à `13.0` ou à la version minimale réellement supportée.

Dans `TARGETS > Do Not Miss > Signing & Capabilities`:

- `Team`: votre vraie team Apple Developer.
- `Automatically manage signing`: acceptable si Xcode résout correctement `Developer ID Application`.
- `Signing Certificate` en Release: vérifier qu’il s’agit bien d’un certificat `Developer ID Application`.
- `Hardened Runtime`: doit être activé pour la notarization.
- `App Sandbox`: ne laisser activé que si c’est volontaire et validé pour votre distribution hors App Store.
- `App Groups`: ne laisser activé que si réellement utilisé.
- `Background Modes`, `Network`, `Keychain`, `Login Item` ou autres capacités: vérifier qu’elles correspondent exactement au besoin produit.

Dans `TARGETS > Do Not Miss > Build Settings`:

- `Code Signing Style`: `Automatic` ou `Manual`, mais cohérent avec la stratégie release.
- `Code Signing Identity` Release: `Developer ID Application`.
- `Enable Hardened Runtime`: `Yes`.
- `Product Bundle Identifier`: identique partout.
- `Info.plist File`: pointe bien vers `Do-Not-Miss-Info.plist`.
- `Build Active Architecture Only` en Release: `No`.
- `Debug Information Format` en Release: `DWARF with dSYM File`.

### Côté Terminal

Le terminal doit utiliser le Xcode complet, pas seulement Command Line Tools:

```bash
xcode-select -p
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Dans cet environnement, `xcodebuild` échoue actuellement car `xcode-select` pointe sur `/Library/Developer/CommandLineTools`. Il faut corriger cela avant d’exécuter la chaîne de release.

## Configuration notarytool recommandée

Méthode recommandée:

```bash
xcrun notarytool store-credentials "DoNotMiss-Notary" \
  --apple-id "YOUR_APPLE_ID@example.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

Ensuite:

```bash
export NOTARY_PROFILE="DoNotMiss-Notary"
```

Alternative sans profil trousseau:

```bash
export APPLE_ID="YOUR_APPLE_ID@example.com"
export APP_SPECIFIC_PASSWORD="YOUR_APP_SPECIFIC_PASSWORD"
export TEAM_ID="YOUR_TEAM_ID"
```

## Variables à adapter

Avant première release, adapter au minimum:

- `Config/Local.xcconfig`: renseigner les vraies valeurs locales
- `build/export/ExportOptions.plist`: remplacer `YOUR_TEAM_ID`
- `EXPECTED_BUNDLE_ID`: si le bundle ID final change
- `EXPECTED_TEAM_ID`: si vous voulez une vérification stricte côté script
- `NOTARY_PROFILE` ou les variables `APPLE_ID` / `APP_SPECIFIC_PASSWORD` / `TEAM_ID`

Exemple de setup local:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Puis éditer:

```xcconfig
APP_DEVELOPMENT_TEAM = YOUR_REAL_TEAM_ID
APP_BUNDLE_IDENTIFIER = your.bundle.identifier
GOOGLE_CLIENT_ID = your-google-client-id.apps.googleusercontent.com
GOOGLE_CALLBACK_SCHEME = com.googleusercontent.apps.your-google-client-id
GOOGLE_REDIRECT_URI = com.googleusercontent.apps.your-google-client-id:/oauth-callback
```

## Scripts

### 1. Archive + export signé

Le script:

- vérifie que le projet est accessible
- refuse une build autre que `Release`
- vérifie `ExportOptions.plist`
- crée une archive Xcode
- exporte l’app signée en `Developer ID`
- valide la signature locale

Commande:

```bash
./Scripts/archive_app.sh
```

Variables utiles:

```bash
export PROJECT_PATH="/absolute/path/to/Do Not Miss.xcodeproj"
export SCHEME="Do Not Miss"
export CONFIGURATION="Release"
export ARCHIVE_PATH="/absolute/path/to/build/archive/DoNotMiss.xcarchive"
export EXPORT_PATH="/absolute/path/to/build/export"
export EXPORT_OPTIONS_PLIST="/absolute/path/to/build/export/ExportOptions.plist"
export EXPECTED_BUNDLE_ID="YOUR_BUNDLE_IDENTIFIER"
export EXPECTED_TEAM_ID="YOUR_TEAM_ID"
./Scripts/archive_app.sh
```

Résultat attendu:

- archive dans `build/archive/`
- app exportée dans `build/export/Do Not Miss.app`

### 2. Notarization + stapling

Le script:

- zippe l’app exportée
- soumet à Apple avec `notarytool`
- attend le verdict
- récupère un log si la notarization échoue
- staple le ticket
- valide le stapling
- lance `spctl`

Commande:

```bash
NOTARY_PROFILE="DoNotMiss-Notary" ./Scripts/notarize_app.sh
```

Alternative:

```bash
APPLE_ID="YOUR_APPLE_ID@example.com" \
APP_SPECIFIC_PASSWORD="YOUR_APP_SPECIFIC_PASSWORD" \
TEAM_ID="YOUR_TEAM_ID" \
./Scripts/notarize_app.sh
```

Résultat attendu:

- ZIP de soumission dans `build/notarization/`
- logs JSON dans `build/notarization/`
- app staplée dans `build/export/Do Not Miss.app`

### 3. Packaging DMG

Le script:

- vérifie que l’app est déjà staplée
- prépare un dossier de staging
- crée un DMG de distribution avec lien vers `/Applications`
- génère un checksum SHA-256
- peut notarizer le DMG final si `NOTARIZE_DMG=1`

Commande minimale:

```bash
./Scripts/build_dmg.sh
```

Commande recommandée pour un livrable final téléchargé depuis le web:

```bash
NOTARY_PROFILE="DoNotMiss-Notary" \
NOTARIZE_DMG=1 \
./Scripts/build_dmg.sh
```

Résultat attendu:

- DMG dans `build/dmg/DoNotMiss-macOS.dmg`
- checksum dans `build/dmg/DoNotMiss-macOS.dmg.sha256`

## Validation de signature et notarization

Vérifier la signature:

```bash
codesign --verify --deep --strict --verbose=2 "build/export/Do Not Miss.app"
codesign -dv --verbose=4 "build/export/Do Not Miss.app"
```

Vérifier Gatekeeper:

```bash
spctl --assess --type execute --verbose=4 "build/export/Do Not Miss.app"
```

Vérifier le ticket staplé:

```bash
xcrun stapler validate "build/export/Do Not Miss.app"
```

Si vous notarizez aussi le DMG:

```bash
xcrun stapler validate "build/dmg/DoNotMiss-macOS.dmg"
spctl --assess --type open --verbose=4 "build/dmg/DoNotMiss-macOS.dmg"
```

## Test sur machine propre

Tester sur un Mac qui n’a jamais lancé l’app, idéalement:

- autre machine physique
- autre compte utilisateur macOS
- aucune build Xcode locale de `Do Not Miss`
- aucun ancien item Keychain lié au bundle ID

Procédure:

1. Télécharger le DMG final.
2. Ouvrir le DMG sans désactiver Gatekeeper.
3. Glisser l’app vers `/Applications`.
4. Lancer l’app normalement.
5. Vérifier qu’aucune alerte anormale de sécurité n’apparaît.
6. Vérifier que l’app démarre comme menu bar app et n’apparaît pas dans le Dock.
7. Vérifier le flux OAuth complet.
8. Vérifier la persistence Keychain.
9. Vérifier `Launch at login`.
10. Vérifier le scheduler.
11. Vérifier l’overlay fullscreen.

## Release checklist

- Mettre à jour `Version` et `Build` Xcode.
- Vérifier que la build est faite en `Release`.
- Vérifier que le `Bundle Identifier` final est correct et cohérent avec OAuth callback.
- Vérifier que le certificat utilisé est `Developer ID Application`.
- Vérifier `Hardened Runtime`.
- Vérifier les capacités réellement nécessaires seulement.
- Corriger le `Deployment Target` pour macOS 13+.
- Lancer `./Scripts/archive_app.sh`.
- Vérifier la signature locale avec `codesign`.
- Lancer `./Scripts/notarize_app.sh`.
- Vérifier `xcrun stapler validate`.
- Lancer `./Scripts/build_dmg.sh`.
- Recommandé: relancer `./Scripts/build_dmg.sh` avec `NOTARIZE_DMG=1` pour notarizer le conteneur final.
- Installer sur une machine vierge.
- Vérifier ouverture sans alerte anormale.
- Vérifier OAuth callback.
- Vérifier Keychain.
- Vérifier launch at login.
- Vérifier overlay fullscreen.
- Vérifier scheduler.
- Archiver les artefacts de release: archive, app exportée, logs de notarization, DMG, checksum.

## Edge cases et dépannage

### Certificat manquant

Symptômes:

- `xcodebuild -exportArchive` échoue
- Xcode ne propose pas `Developer ID Application`

Actions:

- Installer le certificat `Developer ID Application` dans le trousseau.
- Vérifier le bon `Team`.
- Relancer Xcode et revalider `Signing & Capabilities`.

### Bundle ID incohérent

Symptômes:

- OAuth callback cassé
- app différente entre archive, export et configuration Google

Actions:

- Vérifier le bundle ID dans Xcode.
- Vérifier `EXPECTED_BUNDLE_ID`.
- Vérifier le schéma d’URL dans `Do-Not-Miss-Info.plist`.
- Vérifier la configuration Google OAuth côté console Google.

### Notarization refusée

Symptômes:

- `Scripts/notarize_app.sh` échoue
- statut différent de `Accepted`

Actions:

- Ouvrir le JSON de log généré dans `build/notarization/notary-log.json`.
- Vérifier la signature de tous les binaires embarqués.
- Vérifier `Hardened Runtime`.
- Vérifier qu’aucun composant non signé ou ad-hoc n’est embarqué.

### App non staple

Symptômes:

- `xcrun stapler validate` échoue
- `Scripts/build_dmg.sh` refuse de construire le DMG

Actions:

- Relancer `Scripts/notarize_app.sh`.
- Vérifier que le statut Apple est bien `Accepted`.
- Vérifier que vous staplez le même artefact que celui soumis.

### Chemin de build incorrect

Symptômes:

- archive introuvable
- app exportée introuvable

Actions:

- Vérifier `ARCHIVE_PATH`, `EXPORT_PATH`, `APP_PATH`.
- Lancer les scripts sans overrides d’abord.

### Script lancé depuis le mauvais dossier

Les scripts résolvent le repo à partir de leur propre emplacement. Ils n’exigent pas d’être lancés depuis la racine, mais ils supposent que l’arborescence du dépôt n’a pas été déplacée partiellement.

### Différences Debug / Release

Risque:

- app qui marche en local depuis Xcode mais échoue une fois exportée

Actions:

- ne valider la release que sur une build `Release`
- éviter toute dépendance implicite à des affordances debug
- toujours tester l’artefact exporté, pas la build Xcode de dev

### App OK en local mais KO sur machine propre

Causes fréquentes:

- entitlement/capability mal configuré
- OAuth redirect URI incorrecte
- dépendance à un état Keychain local
- login item non enregistré correctement hors environnement de dev
- container DMG non notarizé alors que l’app l’est

Actions:

- tester l’app installée depuis le DMG final
- purger les anciens secrets et anciens installs
- vérifier OAuth sur un compte non utilisé pendant le dev
- vérifier la persistence Keychain après redémarrage
- vérifier `Launch at login` après logout/login

## Commandes finales à exécuter

Chaîne minimale:

```bash
./Scripts/archive_app.sh
NOTARY_PROFILE="DoNotMiss-Notary" ./Scripts/notarize_app.sh
./Scripts/build_dmg.sh
```

Chaîne recommandée pour le livrable final:

```bash
./Scripts/archive_app.sh
NOTARY_PROFILE="DoNotMiss-Notary" ./Scripts/notarize_app.sh
NOTARY_PROFILE="DoNotMiss-Notary" NOTARIZE_DMG=1 ./Scripts/build_dmg.sh
```

Validation finale:

```bash
codesign --verify --deep --strict --verbose=2 "build/export/Do Not Miss.app"
spctl --assess --type execute --verbose=4 "build/export/Do Not Miss.app"
xcrun stapler validate "build/export/Do Not Miss.app"
xcrun stapler validate "build/dmg/DoNotMiss-macOS.dmg"
```
