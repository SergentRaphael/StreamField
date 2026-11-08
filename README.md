# StreamField

Lecteur IPTV léger pour **TV Android / Google TV / Fire TV, PC Windows, Mac, téléphones Android, iPhone et iPad**.

## ⬇️ Télécharger
Page des téléchargements : **[Releases → dernière version](https://github.com/SergentRaphael/StreamField/releases/latest)**

| Appareil | Fichier |
|---|---|
| TV Android, Google TV, Fire TV, téléphone ou tablette Android | [StreamField-Android.apk](https://github.com/SergentRaphael/StreamField/releases/latest/download/StreamField-Android.apk) |
| PC Windows | [StreamField-Windows.zip](https://github.com/SergentRaphael/StreamField/releases/latest/download/StreamField-Windows.zip) |
| Mac | [StreamField-Mac.zip](https://github.com/SergentRaphael/StreamField/releases/latest/download/StreamField-Mac.zip) |
| iPhone / iPad | [StreamField-iOS.ipa](https://github.com/SergentRaphael/StreamField/releases/latest/download/StreamField-iOS.ipa) |

Ces liens pointent toujours vers la dernière version : chaque modification du code reconstruit l'app automatiquement (~15 min).

## 📺 Installer
**TV (Android TV, Google TV, Fire TV)**
1. Installe l'appli **Downloader** (Play Store de la TV ou Amazon Appstore).
2. Autorise-la à installer des applis : Paramètres → Applis / Sécurité → *Sources inconnues* → Downloader.
3. Dans Downloader, tape le lien du fichier `StreamField-Android.apk` (astuce : raccourcis-le avec un service comme is.gd).
4. StreamField apparaît dans les applis de la TV.

**Téléphone Android** : ouvre le lien `.apk` depuis le téléphone et autorise l'installation.

**PC Windows** : dézippe `StreamField-Windows.zip`, lance `streamfield.exe`.
Si Windows affiche « Windows a protégé votre ordinateur » : *Informations complémentaires* → *Exécuter quand même*.

**Mac** : dézippe, glisse `StreamField.app` dans Applications. Premier lancement : clic droit → *Ouvrir*.

**iPhone / iPad** (Apple n'autorise pas l'installation libre) :
| Méthode | Coût | Limite |
|---|---|---|
| **Sideloadly** (PC ou Mac) + identifiant Apple gratuit | gratuit | à ré-signer tous les 7 jours (Sideloadly peut le faire tout seul) |
| TestFlight (compte développeur Apple) | 99 $/an | chaque version dure 90 jours |
| App Store | 99 $/an | validation par Apple |

Avec Sideloadly : installe-le (sideloadly.io), branche l'iPhone, glisse `StreamField-iOS.ipa`, entre ton identifiant Apple → *Start*.
Puis sur l'iPhone : Réglages → Général → VPN et gestion de l'appareil → faire confiance ;
et Réglages → Confidentialité et sécurité → **Mode développeur** (iOS 16 et plus).

## ✨ Fonctions
- **TV du monde** : plus de 11 000 chaînes gratuites (sources iptv-org et Free-TV), rangées **par pays** dans la
  colonne de gauche, les plus connues en haut. Mis à jour chaque jour automatiquement.
  Pour changer l'ordre des grandes chaînes d'un pays : modifie `tool/catalog/populaires.txt`.
- **Compte StreamField** (icône 👤) : connecte-toi sur chaque appareil pour retrouver les mêmes playlists et favoris.
- **Playlists** : lien M3U, compte **Xtream** (serveur + identifiant + mot de passe), fichier `.m3u` ou liste texte.
- **Navigation** : catégories, recherche, ★ favoris, chaînes récentes.
- **Lecteur** : zapping, reconnexion automatique si le flux coupe, plein écran.
- **Testeur de liens** (menu ⋮) : point vert / rouge, retrait des chaînes hors ligne, export `.m3u`.
- Les playlists sont gardées sur l'appareil : ouverture instantanée, même si le lien ne répond plus (⟳ pour recharger).

## 🎮 Commandes du lecteur
| Action | Télécommande / clavier | Tactile / souris |
|---|---|---|
| Chaîne suivante / précédente | ▼ / ▲ (ou CH+ / CH−) | glisser vers le haut / le bas, ⏭ ⏮ |
| Liste des chaînes | OK / Entrée | bouton ☰ |
| Afficher les infos | ◀ ▶ | toucher l'écran |
| Plein écran (PC / Mac) | F | double-clic |
| Pause / muet | Espace / M | — |
| Quitter | Retour / Échap | ← |

---

## 🛠️ Pour modifier l'app
Le code est en **Flutter** (un seul code pour toutes les plateformes). Chaque envoi sur la branche `main`
relance la construction (onglet **Actions**) puis publie une nouvelle version dans **Releases**.

Compiler sur ton ordinateur (facultatif) : installe Flutter puis double-clique
`installer-windows.bat` (PC) ou `installer-mac.command` (Mac).

```
lib/
  main.dart                      démarrage, thème, télécommande
  config.dart                    adresse du service de comptes (Supabase)
  screens/home_screen.dart       accueil : catégories, recherche, liste
  screens/player_screen.dart     lecteur
  screens/playlists_screen.dart  ajout / gestion des playlists
  screens/account_screen.dart    connexion au compte
  services/account.dart          comptes et synchronisation
  services/parsers.dart          lecture M3U et listes texte
  services/xtream_client.dart    connexion Xtream Codes
  services/stream_checker.dart   testeur de liens
  services/storage.dart          sauvegarde sur l'appareil
tool/catalog/                    catalogue « TV du monde » (classement : populaires.txt)
supabase/schema.sql              table des comptes (à coller une fois dans Supabase)
tool/setup.dart                  préparation automatique des plateformes
```

**Comptes** : service gratuit Supabase. Un projet gratuit se met en pause après une semaine sans aucune
utilisation ; il suffit alors de cliquer *Restore* sur supabase.com.
Les identifiants Xtream sont synchronisés avec le compte (protégés : chacun ne voit que ses données).

**Version pour les stores** (démarre sans chaînes intégrées, exigé par Google et Apple) :
`flutter build appbundle --dart-define=STORE_BUILD=true` (Play Store) ·
`flutter build ipa --dart-define=STORE_BUILD=true` (App Store).
