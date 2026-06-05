# Audit dsp-408-ui / piste DSP 204

Date: 2026-06-04

## Etat du projet

- Projet Flutter multi-plateforme clone depuis `Aeternitaas/dsp-408-ui`.
- Application cible actuelle: t.racks DSP 408, interface TCP locale, port par defaut `9761`.
- Fonctionnel declare dans le README: presets, gain/mute/meters, matrix, GEQ; PEQ/RTA en developpement.
- Validation locale effectuee avec Flutter desktop Windows.

## Findings principaux

### 1. Compatibilite DSP 204 non parametree

Le modele DSP 408 est code en dur dans la structure, les labels, le protocole, les widgets et le parsing. Le DSP 204 ne pourra pas etre supporte proprement par quelques remplacements de texte.

Points visibles:

- `lib/main.dart`: titre `DSP408 Controller`.
- `lib/devices/t_racks408/*`: tout le device est nomme et organise autour du 408.
- `DeviceProvider`: 4 entrees, 8 sorties, 12 meters.
- `GainTab`, `MatrixTab`, `PeqTab`: listes de canaux ecrites en dur.
- `ProtocolService`: maps de canaux `In A..D`, `Out 1..8`.
- `ChannelConfigParser`: recherche des noms `InA..InD`, `Out1..Out8`, offsets et dernier canal `Out 8`.

### 2. Parsing des dumps fragile

Le parser reconstruit 29 chunks `0x00..0x1C` et deduit des offsets a partir de la structure observee pour le 408. Si le 204 emet moins de canaux, moins de chunks, ou des offsets differents, l'initialisation peut rester incomplete ou appliquer des valeurs incorrectes.

### 3. Sequence d'initialisation specifique 408

La sequence lit 20 presets, 29 chunks de configuration, puis lance les keepalive. Pour le 204, il faut confirmer au minimum:

- nombre de presets;
- commandes handshake/device info/preset/config;
- nombre et taille des chunks;
- format de la reponse keepalive/meters;
- index de canaux et bitmasks matrix.

### 4. Tests Flutter

Le test widget par defaut a ete remplace par un smoke test adapte a l'application DSP.

### 5. Commandes parfois generables, parfois hard-codees

Le checksum est calcule pour certaines commandes, mais d'autres listes sont ecrites integralement. Pour ajouter un modele, il vaut mieux centraliser la generation des commandes au lieu de dupliquer des tableaux d'octets.

## Strategie recommandee pour le DSP 204

1. Introduire une definition de modele:
   - nom affichable;
   - entrees/sorties;
   - index protocole des canaux;
   - nombre de meters;
   - nombre de presets;
   - nombre de chunks config;
   - capacites: GEQ, PEQ, matrix, RTA.

2. Remplacer les listes de canaux hard-codees par cette definition dans:
   - `DeviceProvider`;
   - `GainTab`;
   - `MatrixTab`;
   - `PeqTab`;
   - `ProtocolService`;
   - `ConnectionProvider` debug decode.

3. Separer le protocole de l'UI:
   - `DeviceModel`;
   - `DeviceProtocolProfile`;
   - un parser de config par profil.

4. Capturer le protocole DSP 204:
   - lancer le logiciel officiel Thomann;
   - capturer handshake, lecture presets, dump config, keepalive, commandes gain/mute/matrix;
   - comparer avec les scripts PCAP presents dans le depot.

5. Ajouter une selection de modele dans l'UI:
   - `DSP 408`;
   - `DSP 204`;
   - profil par defaut `DSP 408` pour conserver le comportement actuel.

## Validation

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

## Conclusion

Le projet est une bonne base pour piloter le DSP 408, mais le support DSP 204 demande une vraie couche d'abstraction modele/protocole. La premiere etape concrete n'est pas encore de modifier tous les widgets: c'est de capturer ou confirmer les trames du DSP 204 pour eviter d'envoyer des commandes 408 a un appareil 204.
