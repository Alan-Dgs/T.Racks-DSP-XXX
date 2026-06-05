# Audit de l'editeur officiel t.racks DSP 408

Date: 2026-06-04
Sources locales non publiees: official editor screenshots, local captures, code/protocole actuel.
Source doc: manuel officiel Thomann DSP 204 / DSP 206 / DSP 306 / DSP 408, PDF:
https://images.static-thomann.de/pics/atg/atgdata/document/manual/435192_c_435191_435192_435193_435194_v2_r2_en_online.pdf

## Synthese courte

L'editeur officiel couvre bien plus que l'app Flutter actuelle. L'app existante est une bonne base pour connexion, presets, gain/mute/meters, matrix routing, GEQ et PEQ partiel. Il manque surtout les blocs dynamiques et les reglages systeme: Gate, Comp, Limit, Delay, Phase, matrix attenuation, link/copy, test tone, channel names, ID/IP, lock, fichiers presets.

Avant d'attaquer DSP 204/206, le plus rentable est de finir les commandes DSP 408 manquantes avec des captures ciblees. Les captures doivent etre petites, nommees et horodatees, avec un scenario par fonction. Le DSP 204/206 pourra ensuite reutiliser les memes scenarios avec un profil de canaux different.

## Perimetre visible dans les captures

Menu principal:
- `File`: probablement charger/sauver des presets PC.
- `Link`: liaison de canaux input/output.
- `Copy`: copie des reglages d'un canal vers un autre.
- `Lock`: mot de passe / verrouillage.
- `Setting ID/IP`: ID serie et IP appareil.
- `Test Tone`: source analogique, pink noise, white noise, sine 20 Hz...20 kHz.
- `Channel Name`: renommage InA...InD et Out1...Out8.
- `Help`: codes de controle de l'interface serie, tres important a capturer si disponible.
- `About`: version logiciel.

Onglets:
- `Gain`, `Gate`, `Comp`, `Limit`, `Delay`, `Matrix`, `GEQ`.
- Onglets de canal: `InA`, `InB`, `InC`, `InD`, `Out1`...`Out8`.

## Plages confirmees par la documentation

La documentation Thomann indique:
- Gain de canal: `-60 dB` a `+12 dB`.
- PEQ: bandes `1` a `9`, frequence `20 Hz` a `20 kHz`, Q `0.4` a `128`, gain `-12 dB` a `+12 dB`, styles `PEAK`, `L-SHLF`, `H-SHLF`, `LP6dB`, `LP12dB`, `HP6dB`, `HP12dB`, `A-PAS1`, `A-PAS2`, et etat `ON` / `BP`.
- GEQ: `31` bandes fixes de `20 Hz` a `20 kHz`, gain `-12 dB` a `+12 dB`.
- Delay: `0 ms` a `680 ms`, ou `0 m` a `234 m`, ou `0 ft` a `766 ft`.
- X-Over: HP/LP `20 Hz` a `20 kHz`, types Butterworth, Bessel, Linkwitz-Riley, ou bypass.
- Gate: threshold `-90 dB` a `0 dB`, hold `10 ms` a `999 ms`, attack `1 ms` a `999 ms`, release `10 ms` a `3000 ms`.
- Phase: `0` ou `180`.
- Matrix routing: chaque sortie peut recevoir une ou plusieurs entrees.
- Matrix output: attenuation par couple entree/sortie de `-60 dB` a `0 dB`.
- Limiter: threshold `-90 dB` a `+20 dB`, attack `1 ms` a `999 ms`, release `10 ms` a `3000 ms`.
- Presets utilisateur: `U01` a `U20`, avec rappel de `F00` possible.
- ID: `1` a `254`.
- IP initiale doc: `192.168.1.101`; les captures locales utilisent une IP privee non publiee.

Point a valider: l'onglet ordinateur `Comp` montre threshold, ratio, knee, attack, release. La documentation ordinateur nomme bien le compresseur, mais la table de plages du manuel PDF ne donne pas clairement les valeurs du compresseur comme elle le fait pour le limiter. Il faut donc capturer l'UI officielle.

## Valeurs UI confirmees manuellement

Confirme par Alan depuis le logiciel officiel:
- Comp, outputs: threshold `-90.0 dB..+20.0 dB`, pas `0.5 dB`; ratio `1:1.0`, `1:1.7`, puis `1:2.0`, `1:2.5`, pas `0.5` jusqu'a `1:4.0`, puis `1:5.0`, `1:6.0`, `1:8.0`, `1:10`, `1:20`, `Limit`; knee `0..12 dB`, pas `1 dB`; attack `1..999 ms`, pas `1 ms`; release `10..3000 ms`, pas `1 ms`.
- Limit, outputs seulement: threshold `-90.0 dB..+20.0 dB`, pas `0.5 dB`; attack/release identiques au Comp.
- Gate, inputs seulement: threshold `-90.0 dB..0.0 dB`, pas `0.5 dB`; attack identique au Comp; hold `10..999 ms`, pas `1 ms`; release identique au Comp.
- Delay: `0.000..680.000 ms`; `0..233.580 m`; `0..766.329 ft`; changement d'unite modifie affichage et valeur.
- Matrix attenuation: `-60.0..0.0 dB`; pas `0.1 dB` jusqu'a `-20 dB`, puis `0.5 dB` jusqu'a `-60 dB`; reglable meme si l'entree n'est pas routee vers la sortie.
- PEQ input: 8 bandes visibles; types visibles confirmes: `Low Shelf`, `High Shelf`, `LP -6dB`, `LP -12dB`, `HP -6dB`, `HP -12dB`, `AllPass1`, `AllPass2`. Le type `Peak` est visible dans les captures et deja implemente.

## Etat par fonction

| Fonction | Editeur officiel | App actuelle | Priorite capture |
| --- | --- | --- | --- |
| Connexion | IP/ID, Online, presets | Fonctionnel en Windows natif | Basse, deja connu |
| Gain | InA-D + Out1-8, normal/inverse, mute | Gain/mute/meters OK, phase incomplete | Haute pour phase |
| Gate | InA-D visibles dans capture | Onglet placeholder/incomplet | Haute |
| Comp | Out1-8, threshold/attack/ratio/knee/release | Placeholder/incomplet | Haute |
| Limit | Out1-8 dans capture, doc parle aussi input/output | Placeholder/incomplet | Haute |
| Delay | InA-D + Out1-8, unites ms/m/ft | Placeholder/incomplet | Haute |
| Matrix routing | Routage input vers output | Commande routing presente | Moyenne, verifier tous bitmasks |
| Matrix attenuation | Gain par couple In/Out `-60..0 dB` | UI locale/incomplete, commande absente | Haute |
| GEQ | 31 bandes input InA-D | Commande presente | Moyenne, valider bypass/reset |
| PEQ | In et Out avec HPF/LPF, bypass, types | Partiel, commande PEQ presente | Haute |
| X-Over / HP-LP | Dans onglets In/Out | Partiel, HP/LP commandes partielles | Haute |
| Preset store/recall | U01-U20/F00, nom preset | Present | Moyenne, verifier noms/store |
| Link | Associe canaux | Non implemente | Moyenne |
| Copy | Copie In->In, Out->Out | Non implemente | Basse ou derive de dump |
| Lock | Mot de passe | Non implemente | Basse, risque UX |
| Setting ID/IP | ID et IP | Non implemente | Basse, dangereux en test |
| Test tone | Analog, pink, white, sine freq | Non implemente | Moyenne |
| Channel name | 12 noms canaux | Parsing partiel dans dump, edition absente | Moyenne |
| Help/control codes | Codes serie | Non capture | Tres haute si l'ecran existe |

## Observations protocole deja utiles

Ces points viennent du code existant et des scripts d'analyse, donc ils restent a confirmer par capture quand on modifie une valeur dans l'editeur officiel:
- Les trames commencent par `10 02` et finissent par `10 03` + checksum XOR.
- Port TCP utilise par l'app: `9761`.
- Gain: commande `0x34`.
- Mute: commande `0x35`.
- GEQ: commande `0x48`, input seulement, 31 bandes.
- Matrix routing: commande `0x3a`, bitmask input `InA=0x01`, `InB=0x02`, `InC=0x04`, `InD=0x08`.
- PEQ: commande `0x33`.
- HPF/LPF: commandes `0x32` et `0x31` dans l'app, a valider avec l'editeur officiel.
- Dump config: 29 chunks `0x00..0x1c`, reponses `0x24`.
- Structure observee: inputs avec GEQ 31 bandes + PEQ 8 bandes dans le dump actuel; outputs avec PEQ 9 bandes. La doc annonce 9 bandes PEQ, donc l'ecart input doit etre verifie.

### Capture validee: phase

Scenario: `001_phase_input_output`

Trames PC -> DSP hors keepalive:
- InA inverse: `10 02 00 01 03 36 00 01 10 03 34`
- InA normal: `10 02 00 01 03 36 00 00 10 03 35`
- Out1 inverse: `10 02 00 01 03 36 04 01 10 03 30`
- Out1 normal: `10 02 00 01 03 36 04 00 10 03 31`

Conclusion: phase utilise la commande TCP `0x36`.
Format probable: `10 02 00 01 03 36 [channel] [phase] 10 03 [checksum]`, avec `[phase]=0 normal`, `[phase]=1 inverse`, et index canal deja connu (`InA=0x00`, `Out1=0x04`).

## Help officiel: Processor Extend Remote Control Protocol

Capture Help fournie le 2026-06-04. Attention: ce tableau de l'editeur officiel documente un protocole "extended remote control" au format `7B 7D ... 7D 7B`, avec baudrate `115200`, 8 data bits, parity none, stop bit 1, step >= 20 ms. Il ressemble au protocole serie/remote documente, pas au protocole TCP deja observe dans l'app Flutter, qui utilise des trames `10 02 ... 10 03`.

Format package Help:
- `0x7B 0x7D [device address 1..254] [CMD 0x41..0x4A] [Data1] [Data2] [Data3] 0x7D 0x7B`
- ID par defaut: `1`.

Commandes Help visibles:
- `0x41` Gain Control: in/out, channel, `+/-`.
- `0x42` Mute Control: in/out, channel, no/yes.
- `0x43` Load Preset Control: factory/user, preset.
- `0x44` Input Volume Control: channel, hi-vol, lo-vol.
- `0x45` Output Volume Control: channel, hi-vol, lo-vol.
- `0x48` Get Now Gain.
- `0x49` Get Mute.
- `0x4A` Get Now Preset.

Exemples Help visibles:
- Gain In1 +: `7B7D01410000007D7B`
- Mute Out1: `7B7D0142010017D7B`
- Recall user preset U01: `7B7D01330100007D7B`
- Set InA volume +0.0 dB: `7B7D01440001187D7B`
- Set Out2 volume -3.0 dB: `7B7D01450100FA7D7B`
- Read In1 volume: `7B7D01480000007D7B`
- Read mute: `7B7D01490000007D7B`
- Read now preset: `7B7D014A000007D7B`

Conclusion: le Help aide pour gain/mute/preset/volume, mais ne couvre pas Gate, Comp, Limit, Delay, Matrix, GEQ, PEQ, HPF/LPF, phase, names, test tone. Pour l'app Flutter TCP, il faut verifier si ces commandes `7B7D` sont acceptees sur le port TCP ou si elles ne concernent qu'une interface serie.

## Scenarios de capture recommandes

Convention de nommage:
- Dossier local: `captures/DSP408/YYYY-MM-DD/`.
- Nom: `NNN_fonction_canal_parametre_valeur.pcapng`.
- Journal associe: meme nom en `.json` ou `.md` avec heure debut, heure action, heure stop, appareil, IP, port, version logiciel.

Filtre Wireshark conseille:
`ip.addr == <DSP_IP> || tcp.port == 9761`

Chaque scenario doit suivre ce rythme:
1. Mettre l'editeur officiel Online.
2. Lancer capture.
3. Attendre 1 seconde sans action.
4. Faire une seule modification.
5. Cliquer "fait" dans l'appli de protocole de test.
6. Attendre 1 seconde.
7. Stop capture.

Scenarios minimum DSP 408:
- `001_gain`: InA `0.0 -> -6.0 -> +3.0`, Out1 pareil.
- `002_mute_phase`: InA mute on/off, phase normal/inverse; Out1 pareil.
- `003_gate_input`: InA threshold, attack, hold, release avec valeurs non defaut.
- `004_comp_output`: Out1 threshold, ratio, knee, attack, release.
- `005_limit_output`: Out1 threshold, attack, release.
- `006_delay`: InA `1 ms`, Out1 `10 ms`, puis changer unite `m` et `ft` sans modifier la valeur si possible.
- `007_matrix_routing`: Out1 route InA seul, InB seul, InA+InB, tout off, InA+InB+InC+InD.
- `008_matrix_attenuation`: Out1/InA `0 dB -> -6 dB -> -60 dB`; Out1/InB `-3 dB`.
- `009_geq`: InA bande 20 Hz `+3 dB`, 1 kHz `-6 dB`, EQ bypass, EQ reset.
- `010_peq_input`: InA band 1 freq/Q/gain/type/bypass; HPF freq/slope/bypass; LPF freq/slope/bypass.
- `011_peq_output`: Out1 band 1 et band 9, HPF/LPF, gain/mute/phase.
- `012_preset`: store U20 nom court, recall U20, recall F00 si autorise.
- `013_channel_name`: renommer InA et Out1, revenir valeurs initiales.
- `014_test_tone`: analog, pink, white, sine 20 Hz, sine 1 kHz.
- `015_link_copy`: link minimal InA/InB et copy InA->InB, Out1->Out2.
- `016_help_codes`: ouvrir Help et capturer/photographier/copier tous les codes de controle disponibles.

## Adaptation DSP 204 / 206 / 306

Le manuel couvre la meme famille DSP 204 / 206 / 306 / 408. La difference structurante est le nombre de canaux:
- DSP 204: probablement 2 inputs / 4 outputs.
- DSP 206: probablement 2 inputs / 6 outputs.
- DSP 306: probablement 3 inputs / 6 outputs.
- DSP 408: 4 inputs / 8 outputs.

L'appli de protocole de test doit donc etre profilee:
- `deviceModel`
- `inputChannels`
- `outputChannels`
- `ip`
- `port`
- scenarios compatibles
- captures obligatoires / optionnelles

Pour DSP 204, il faudra refaire les scenarios essentiels avec moins de canaux, surtout:
- connexion + dump config;
- gain/mute/phase;
- matrix routing et attenuation;
- GEQ/PEQ/HPF/LPF;
- delay/gate/limit/comp si presents pareil dans l'editeur 204.

## Proposition pour l'appli de capture

Appli volontairement simple:
- choix appareil: DSP408, DSP204, DSP206, DSP306;
- IP/port;
- choix dossier de sortie;
- liste de scenarios;
- bouton `Start scenario`;
- instructions etape par etape;
- bouton `Marquer action faite`;
- bouton `Stop scenario`;
- generation automatique du nom de capture et du journal horodate.

Si possible, l'appli lance `dumpcap` ou `tshark` en arriere-plan. Sinon elle pilote seulement le protocole humain et produit les noms exacts a utiliser dans Wireshark.

Le journal doit inclure des marqueurs comme:
- `scenario_started_at`
- `pcap_started_at`
- `action_001_prompted_at`
- `action_001_done_at`
- `pcap_stopped_at`
- `notes`

Cela permet de retrouver rapidement la trame exacte meme si le logiciel officiel envoie du keepalive en continu.

## Ordre de travail conseille

1. Capturer `Help/control codes` si l'ecran donne vraiment les commandes serie.
2. Capturer une valeur simple connue par fonction: phase, delay, matrix attenuation, gate, comp, limit.
3. Capturer PEQ/HPF/LPF avec seulement une bande et un filtre.
4. Implementer les commandes confirmees dans l'app Flutter.
5. Rejouer les tests avec l'app Flutter contre le DSP 408.
6. Ensuite seulement, sortir le DSP 204 et refaire le pack minimum de scenarios.
