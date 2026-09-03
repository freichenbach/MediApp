# DosiCrew

[![Build & Test](https://github.com/freichenbach/MediApp/actions/workflows/ci.yml/badge.svg?branch=claude/medication-management-iphone-app-b4jg7a)](https://github.com/freichenbach/MediApp/actions/workflows/ci.yml)

**Medikamente gemeinsam im Blick**

Eine iPhone-App, mit der sich mehrere Personen — Eltern, Großeltern, Kita — über
die Medikamentengabe an ein gemeinsames Kind abstimmen. Medikamente mit Dosierung
und Zeitplan hinterlegen, pro Tag abhaken, über alle Beteiligten synchronisiert,
mit Erinnerungen und dem Festhalten besonderer Ereignisse.

Die App verhindert genau zwei Fehler: die **doppelte Gabe** und die **vergessene
Gabe**.

## Name im App Store

| Feld | Wert | Länge |
|---|---|---|
| App-Name | `DosiCrew` | 8 / 30 |
| Untertitel | `Medikamente gemeinsam im Blick` | 30 / 30 |

Beides zusammen als *ein* Feld wäre mit 41 Zeichen über dem Limit von 30, das
App Store Connect für den Namen setzt. Aufgeteilt geht es genau auf — der
Untertitel trifft die 30 Zeichen punktgenau. Auf dem Home-Bildschirm steht unter
dem Icon ohnehin nur `DosiCrew`; iOS kürzt dort nach rund zwölf Zeichen.

Technisch heißt die App an diesen Stellen `DosiCrew`: Bundle Identifier
`es.reichenbach.DosiCrew`, CloudKit-Container `iCloud.es.reichenbach.DosiCrew`,
Core-Data-Modell, Targets und Schema. Der Untertitel ist reine
App-Store-Metadatei und steht nirgends im Code.

## Was drin ist

- **Heute** — alle fälligen Gaben eines Tages, gruppiert nach Morgen / Mittag /
  Abend / Nacht. Ein Tipp hakt ab, danach steht dort *„Gegeben von Papa, 08:12"*.
  Wischen für *Ausgelassen*, *Verweigert* oder *Rückgängig*. Vor- und
  Zurückblättern zwischen den Tagen.
- **Doppelgabe-Warnung** — haken zwei Personen denselben Slot ab (etwa weil eine
  offline war), wird das rot markiert statt stillschweigend zusammengeführt.
- **Medikamente** — Name, Darreichungsform, Menge pro Gabe mit Einheit, Stärke,
  Hinweis („zum Essen"), Farbe, Behandlungszeitraum. Archivieren statt löschen,
  damit der Verlauf erhalten bleibt.
- **Zeitpläne** — beliebig viele Uhrzeiten pro Tag, täglich / alle N Tage / an
  bestimmten Wochentagen. Mehrere Regeln pro Medikament sind möglich.
- **Erinnerungen** — lokale Benachrichtigung zur geplanten Zeit, plus eine
  Nachfass-Erinnerung nach 30 Minuten. Direkt aus der Mitteilung *Gegeben* oder
  *In 15 Minuten erinnern*.
- **Ereignisse** — Fieber, Nebenwirkung, Erbrechen, Arztbesuch oder freie Notiz,
  mit Zeitstempel und optionalem Messwert (z. B. 38,9 °C).
- **Teilen** — Einladung per Link/iMessage über iCloud. Wer annimmt, sieht
  denselben Plan; Änderungen erscheinen innerhalb von Sekunden auf allen iPhones.
- **Drei Sprachen** — Deutsch, Englisch, Spanisch; die Gerätesprache entscheidet.

## Bauen ohne Mac

Der Build läuft in GitHub Actions auf einem macOS-Runner
(`.github/workflows/ci.yml`): bei jedem Push wird kompiliert und die Testsuite
im Simulator ausgeführt. Für ein privates Repository zählen macOS-Minuten
zehnfach auf das Kontingent — bei diesem Projektumfang trotzdem unkritisch.

Was der Workflow bewusst tut:

- Er wählt das **neueste installierte Xcode** auf dem Runner, weil das Projekt
  Xcode-16-Ordnersynchronisierung nutzt (`objectVersion 77`).
- Er sucht sich per `.github/scripts/pick_simulator.py` zur Laufzeit einen
  verfügbaren iPhone-Simulator, statt ein Modell fest zu verdrahten — GitHub
  tauscht die Simulator-Auswahl mit jedem Image-Update aus.
- Er baut **ohne Signierung** (`CODE_SIGNING_ALLOWED=NO`). Für den Simulator
  reicht das; CloudKit und Push lassen sich damit aber nicht ausprobieren.

## Auf das iPhone

`.github/workflows/release.yml` archiviert, signiert und lädt nach TestFlight —
ebenfalls auf dem macOS-Runner. Der Weg ist erprobt: Build 4 ging am
2026-09-01 mit `UPLOAD SUCCEEDED with no errors` durch. Er läuft **nicht** bei jedem Push, sondern nur
von Hand oder bei einem Tag `v*`: jede Nummer ist in TestFlight nur einmal
verwendbar, und macOS-Minuten zählen zehnfach.

Signiert wird über `xcodebuild -allowProvisioningUpdates` mit einem
App-Store-Connect-API-Schlüssel. Xcode legt Zertifikat und Profil selbst an;
damit entfallen Fastlane `match` und ein eigenes Zertifikats-Repository.

Zwei Eigenheiten, die den Weg dorthin gekostet haben und deshalb hier stehen:

- **Das Archiv entsteht unsigniert** (`CODE_SIGNING_ALLOWED=NO`). Signiert man
  es mit, greift Xcode zu einem *Development*-Profil, und die verlangen
  mindestens ein registriertes Gerät. Ein frisches Team hat keins, und
  TestFlight braucht auch keins — dort zählt das Distribution-Profil, das im
  Export-Schritt entsteht.
- **Der API-Schlüssel braucht `Admin`.** Siehe unten.

### Einmalig einrichten

Voraussetzung ist das **Apple Developer Program** (99 $/Jahr, Beitritt geht über
die Apple-Developer-App auf dem iPhone). Alles Weitere läuft im Browser, auch
auf dem iPad:

| Was | Wo | Wert |
|---|---|---|
| App ID | developer.apple.com → Identifiers | `es.reichenbach.DosiCrew`, mit **iCloud**, **Push Notifications** und **Time Sensitive Notifications** |
| CloudKit-Container | ebenda, beim iCloud-Häkchen | `iCloud.es.reichenbach.DosiCrew` |
| App-Datensatz | App Store Connect → Apps → **+** | Name `DosiCrew`, Untertitel `Medikamente gemeinsam im Blick` |
| API-Schlüssel | App Store Connect → Users and Access → Integrations | **Team Key** mit Rolle **Admin**; die `.p8` ist nur einmal ladbar |

Zur Rolle: **`Admin` ist Pflicht, `App Manager` reicht nicht.** App Manager darf
Provisioning-Profile anlegen, aber keine Distributions-Zertifikate — und genau
die erzeugt `xcodebuild`, wenn es den Export signiert. Mit einer schwächeren
Rolle bricht der Export mit `Cloud signing permission error` ab, gefolgt von
einem irreführenden `No profiles … were found`, das einen in die falsche
Richtung schickt. Der Workflow fängt den Fall ab und nennt die Ursache beim
Namen.

Ein bereits erzeugter Schlüssel lässt sich in der Rolle nicht ändern: einen
neuen Team Key mit `Admin` anlegen und `ASC_KEY_ID`, `ASC_ISSUER_ID` und
`ASC_KEY_P8` aktualisieren. Den alten danach widerrufen.

Dann die Secrets unter *Settings → Secrets and variables → Actions* →
**New repository secret** (nicht *Environment secrets*, nicht *Variables*):

| Secret | Inhalt |
|---|---|
| `APPLE_TEAM_ID` | die zehnstellige Team-ID |
| `ASC_KEY_ID` | Key-ID des API-Schlüssels |
| `ASC_ISSUER_ID` | Issuer-ID, gilt fürs ganze Team |
| `ASC_KEY_P8` | Inhalt der `.p8`-Datei, mitsamt der BEGIN- und END-Zeilen |
| `DIST_CERT_P12_BASE64` | das Distributions-Zertifikat als `.p12`, base64-kodiert (siehe unten) |
| `DIST_CERT_PASSWORD` | das Passwort, mit dem die `.p12` exportiert wurde |

Für den Schlüssel gibt es zwei Wege, einer genügt: `ASC_KEY_P8` mit dem rohen
Dateiinhalt — GitHub-Secrets nehmen mehrzeilige Werte — oder
`ASC_KEY_P8_BASE64` mit derselben Datei base64-kodiert. Ohne Mac ist Einfügen
einfacher als Kodieren; sind beide gesetzt, gewinnt `ASC_KEY_P8`.

Fehlt etwas, bricht der Workflow im ersten Schritt mit einer klaren Meldung ab
statt später beim Signieren. Direkt danach prüft er, ob die abgelegte Datei
wirklich mit `-----BEGIN PRIVATE KEY-----` beginnt — das fängt einen halb
kopierten Text oder einen Wert im falschen Secret sofort ab.

### Zertifikat hinterlegen

Das Archiv muss auf dem Runner signiert werden, denn nur beim Signieren
schreibt Xcode die Entitlements ins Binary — den iCloud-Container, CloudKit,
Time Sensitive. Ein Build ohne sie startet nicht, sondern bricht sofort in
`-[CKContainerImplementation _checkRequiredEntitlements]` ab.

Dafür braucht der Runner ein echtes Zertifikat samt privatem Schlüssel.
`xcodebuild -allowProvisioningUpdates` erzeugt zwar eines, behält den privaten
Schlüssel aber bei Apple; auf dem Runner meldet `security find-identity`
deshalb `0 valid identities found`, auch mit frisch angelegtem, entsperrtem
Schlüsselbund. Das Zertifikat muss also mitgebracht werden.

Das geht ohne Mac, in **PowerShell** mit OpenSSL. Ist keines installiert,
bringt [Git für Windows](https://git-scm.com/download/win) eines mit.

Zuerst die Version feststellen — davon hängt ein Schalter weiter unten ab:

```powershell
openssl version
```

**1. Schlüssel und Zertifikatsantrag erzeugen**

```powershell
mkdir ~\dosicrew-cert; cd ~\dosicrew-cert

openssl genrsa -out distribution.key 2048
```

`openssl req` braucht eine Konfigurationsdatei. Manche Windows-Binaries suchen
sie an einem Pfad, der beim Bauen fest eingetragen wurde und auf dem eigenen
Rechner nicht existiert — der Befehl bricht dann mit
`Can't open …/openssl.cnf for reading` ab. Die Datei selbst anzulegen ist
einfacher als das zu reparieren, und die Angaben stehen dann gleich mit drin:

```powershell
@"
[ req ]
distinguished_name = dn
prompt = no

[ dn ]
emailAddress = DEINE@MAIL.DE
CN = DosiCrew Distribution
C = DE
"@ | Set-Content -Encoding ascii openssl.cnf

openssl req -new -key distribution.key -out distribution.csr -config openssl.cnf
```

`-Encoding ascii` ist nicht kosmetisch: PowerShell schreibt sonst UTF-16, und
OpenSSL liest die Datei dann als Kauderwelsch.

`distribution.key` ist der private Schlüssel. Er verlässt den Rechner nicht und
lässt sich nicht wiederherstellen — geht er verloren, wird das Zertifikat
wertlos und muss neu erzeugt werden.

**2. Zertifikat bei Apple abholen**

developer.apple.com → *Certificates, Identifiers & Profiles* → **Certificates**
→ **+** → **Apple Distribution** → *Continue* → bei *Upload a Certificate
Signing Request* die Datei `distribution.csr` hochladen → *Continue* →
**Download**. Es kommt eine Datei `distribution.cer` heraus; sie gehört ins
selbe Verzeichnis.

> Apple erlaubt höchstens drei Distributions-Zertifikate gleichzeitig, und
> Cloud Signing hat über die Läufe hinweg möglicherweise schon welche angelegt.
> Ist der Knopf ausgegraut, in derselben Liste ein altes auswählen und
> *Revoke* — deren private Schlüssel liegen bei Apple und sind hier ohnehin
> nicht zu gebrauchen.

**3. Beides zu einer `.p12` zusammenfügen**

```powershell
openssl x509 -inform DER -in distribution.cer -out distribution.pem

openssl pkcs12 -export -inkey distribution.key -in distribution.pem `
  -out distribution.p12 -name "Apple Distribution"
```

Der zweite Befehl fragt zweimal nach einem Passwort. Es darf beliebig sein,
muss aber gemerkt werden — es wird gleich zum Secret `DIST_CERT_PASSWORD`.

**Bei OpenSSL 3 gehört `-legacy` dazu**, direkt hinter `-export`. OpenSSL 3
verschlüsselt `.p12`-Dateien sonst mit einem Verfahren, das macOS nicht lesen
kann; der Import auf dem Runner scheitert dann mit einer Meldung, die nach
einem falschen Passwort aussieht. OpenSSL 1.1.1 kennt den Schalter nicht und
braucht ihn auch nicht — dort ist das alte Format ohnehin der Standard.

**4. Base64 für das Secret**

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$PWD\distribution.p12")) `
  | Set-Content -Encoding ascii distribution.p12.txt
```

Den Inhalt von `distribution.p12.txt` — eine einzige lange Zeile — als
`DIST_CERT_P12_BASE64` ablegen, das Passwort aus Schritt 3 als
`DIST_CERT_PASSWORD`.

Danach `distribution.key` und `distribution.p12` sicher aufbewahren oder
löschen; im Repository haben sie nichts zu suchen.

Der Workflow prüft beim Import, ob eine Identität vom Typ *Apple Distribution*
herauskommt, und nennt bei einem Fehlschlag die beiden realistischen Ursachen —
falsches Passwort oder eine `.p12` ohne `-legacy`.

### CloudKit-Schema anlegen

Der eine Schritt, der einen Mac braucht — und zwar einen, auf dem **Xcode 16
oder neuer** läuft, also mindestens macOS Sonoma 14.5. Ältere Macs helfen
nicht: das Projekt braucht das iOS-17-SDK, und das gibt es erst ab Xcode 15,
das Ordnerformat erst ab 16. **TestFlight-Builds
laufen immer gegen die Produktionsumgebung von CloudKit, und das Schema muss
dort liegen, bevor der erste Build hochgeht** — erzeugt wird es aber nur von
einem Lauf in der *Development*-Umgebung. Das braucht einmalig einen Mac; ein
stundenweise gemieteter Cloud-Mac (MacStadium, Scaleway, MacinCloud) reicht.

**Xcode aus dem App Store geht meist nicht.** Der App Store bietet immer nur
die *neueste* Xcode-Version an, und die verlangt regelmäßig ein macOS, das noch
nicht auf dem Rechner ist — „benötigt macOS 26.2 oder neuer" auf einem Mac mit
Sequoia 15.3. Das heißt nicht, dass der Mac zu alt ist. Ältere Xcode-Versionen
liegen als `.xip` unter <https://developer.apple.com/download/all/> (Suchfeld:
`Xcode`, Anmeldung mit demselben Developer-Account). Jeder Eintrag nennt dort
sein Mindest-macOS — **diese Angabe zählt**, nicht das, was der App Store sagt.
Nimm die neueste Version, die der eigene Mac laut dieser Angabe trägt; alles ab
Xcode 16 reicht für dieses Projekt.

Danach:

```sh
# .xip doppelklicken, entpacken dauert einige Minuten, dann:
mv ~/Downloads/Xcode.app /Applications/
sudo xcode-select -s /Applications/Xcode.app
xcodebuild -version          # muss 16.x oder höher zeigen
```

Xcode einmal öffnen, damit es seine Zusatzkomponenten installiert. Platzbedarf
beim Entpacken: rund 40 GB frei. Alternativ macOS aktualisieren und dann den
App Store nehmen — geht auch, ist aber der größere Eingriff, besonders auf einem
geliehenen Rechner.

**Der kurze Weg:** `./Tools/bootstrap-cloudkit.sh <APPLE_TEAM_ID>` erledigt
Bauen, Installieren und Starten mit dem richtigen Argument und zeigt das
Ergebnis direkt im Terminal. Von Hand bleiben nur die zwei Schritte, die
wirklich einen Menschen brauchen: die iCloud-Anmeldung im Simulator und das
Deployen in der CloudKit Console. Über eine Remote-Desktop-Verbindung spart
das eine Menge Klickerei.

**Der Aufruf läuft oft in einen Timeout — das ist kein Fehlschlag.**
`initializeCloudKitSchema` gibt sich 30 Sekunden für das ganze Modell und
bricht ab, wenn die Runden zu CloudKit länger brauchen. Was angelegt wurde,
bleibt. Aber der Aufruf prüft bei jedem Lauf das *gesamte* Modell erneut, statt
dort weiterzumachen, wo er aufgehört hat — auf einer langsamen Verbindung läuft
er also weiter in den Timeout, auch wenn nichts mehr anzulegen ist.

Nicht die Meldung entscheidet, sondern die Konsole:

> icloud.developer.apple.com → Container → **Schema → Record Types**

Diese fünf müssen dastehen: `CD_Patient`, `CD_Medication`, `CD_ScheduleRule`,
`CD_DoseLog`, `CD_CareEvent`. Der Typ `Users` gehört CloudKit selbst.

- **Alle fünf da** → fertig. *Deploy Schema Changes → Production*, Argument
  wieder entfernen. Weitere Läufe bringen nichts.
- **Einer fehlt** → nochmal starten. WLAN statt Mobilfunk hilft spürbar.

**Von Hand, falls das Skript hakt:**

1. Repo klonen, `DosiCrew.xcodeproj` öffnen, Team unter *Signing & Capabilities*
   wählen.
2. **Das iPhone anschließen** und als Ziel wählen. Xcode registriert das Gerät
   dabei selbst im Developer-Portal. Bequemer als der Simulator, weil das
   iPhone ohnehin in iCloud angemeldet ist — und `initializeCloudKitSchema`
   braucht ein angemeldetes Konto. (Simulator geht auch, dort aber erst unter
   *Einstellungen* in iCloud anmelden.)
3. *Product → Scheme → Edit Scheme → Run → Arguments*: Startargument
   `-DosiCrewInitializeCloudKitSchema` hinzufügen.
4. Einmal starten. Der Start dauert spürbar länger — das Anlegen des Schemas
   blockiert. In der Xcode-Konsole erscheint ein umrahmter Block mit
   *„CloudKit development schema initialized"* und dem Container-Namen.
5. Startargument wieder entfernen. Es ist zwar `#if DEBUG`-geschützt und kann
   nie in einen Release-Build geraten, kostet aber bei jedem Start Zeit.
6. `icloud.developer.apple.com` → CloudKit Console → Container auswählen →
   Schema prüfen → **Deploy Schema Changes** nach Production.

**Der bereits installierte TestFlight-Build fängt danach von selbst an zu
synchronisieren.** Das Schema liegt auf dem Server, nicht in der App; ein neuer
Upload ist nicht nötig. In den Einstellungen wechselt die Anzeige unter
*Teilen* von der Warnung auf einen Zeitpunkt — daran erkennst du, dass es
wirklich läuft.

Danach ist wieder alles CI-getrieben. Erneut nötig ist das nur, wenn das
Datenmodell wächst — und Änderungen daran sind ohnehin nur additiv möglich.

### Erinnerungen, die durchkommen

Eine Erinnerung, die im Fokus hängenbleibt, ist keine. Deshalb tragen alle
Dosis-Erinnerungen `interruptionLevel = .timeSensitive` — sie kommen durch
Fokus und „Nicht stören".

Dafür braucht die App-ID die Berechtigung, sonst lehnt der Export das
Entitlement ab:

> developer.apple.com → Certificates, Identifiers & Profiles → **Identifiers** →
> `es.reichenbach.DosiCrew` → **Time Sensitive Notifications** ankreuzen → *Save*

Das ist ein Häkchen ohne Antrag; Apple prüft nichts. Ist es nicht gesetzt,
scheitert der Release-Lauf beim Signieren mit einer Meldung, die das Entitlement
beim Namen nennt. Der Entitlement-Eintrag steht in einem eigenen Commit und ist
damit in einem Schritt zurücknehmbar.

**Was Time Sensitive nicht kann:** gegen den Stummschalter anklingeln. Das
können nur *Critical Alerts*, und die gibt Apple einzeln frei —
Medikamentengabe ist ein ausdrücklich zugelassener Fall. Der Code dafür liegt
schon da und ist bis zur Freigabe unerreichbar: `requestAuthorization` fragt
`.criticalAlert` mit an, und `criticalAlertSetting` entscheidet zur Laufzeit.
Kommt die Freigabe, wirkt sie ohne Codeänderung — es fehlt dann nur noch
`com.apple.developer.usernotifications.critical-alerts` in beiden
Entitlement-Dateien. **Vorher eingetragen bricht es den Export**, also erst
danach.

Der fertige Antragstext liegt unter [`Docs/critical-alerts-antrag.md`](Docs/critical-alerts-antrag.md),
einzureichen unter
<https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement>.

Was in den Einstellungen der App steht, ist jeweils der tatsächliche Zustand:
klingelt trotz Stummschaltung, kommt nur durch den Fokus, oder zeitkritische
Mitteilungen sind in iOS ausgeschaltet.

### Screenshots

`.github/workflows/screenshots.yml` startet die App im CI-Simulator, klickt sie
durch und legt die Bilder unter `Screenshots/` im Repo ab. Nur manuell
auslösbar, weil die UI-Tests Minuten brauchen.

Das ist nicht Kosmetik, sondern die einzige Möglichkeit, die App überhaupt zu
*sehen*, solange kein Mac und kein signierter Build auf einem Gerät da ist. Der
Test startet mit `-DosiCrewUITestSeed`; die App nutzt dann einen
In-Memory-Store mit einem Demoplan — inklusive einer absichtlich doppelt
gegebenen Dosis, damit die Warnung auf einem Bild landet.

Zwei Startargumente halten Dialoge von den Bildern fern: `-personName Papa`
beantwortet die Frage nach dem Gerätenamen (iOS übernimmt
`-key value`-Argumente in `UserDefaults`), und der Erlaubnisdialog für
Mitteilungen wird unter UI-Tests übersprungen.

Die Unit-Tests und die UI-Tests haben **getrennte Schemata**: `DosiCrew` für
die 35 schnellen Tests bei jedem Push, `DosiCrewScreenshots` für die langsamen
UI-Tests auf Abruf.

### Läuft die Synchronisation überhaupt?

Bis das Schema in Produktion liegt, baut und startet die App, synchronisiert
aber nichts. Damit dieser Zustand nicht wie ein ruhiger Tag aussieht, zeigen
die Einstellungen unter *Teilen* den echten Zustand: Zeitpunkt der letzten
erfolgreichen Synchronisation, oder eine Warnung, wenn seit dem Start nichts
ausgetauscht wurde. Bei einer geteilten Medikamentenliste ist der stille
Ausfall gefährlicher als eine Fehlermeldung.

## Mit Mac

1. `open DosiCrew.xcodeproj`
   Falls das Projekt nicht sauber öffnet, liegt eine XcodeGen-Spec bei:
   ```
   brew install xcodegen && xcodegen
   ```
   Beide Wege erzeugen dasselbe Projekt.

2. **Signing & Capabilities** für das Target `DosiCrew`:
   - *Team* auswählen (ein **kostenpflichtiges Apple Developer Programm ist
     Pflicht** — CloudKit und Push gibt es im kostenlosen Account nicht).
   - *Bundle Identifier* setzen. Voreingestellt ist `es.reichenbach.DosiCrew`.
   - **iCloud** → *CloudKit*, Container `iCloud.es.reichenbach.DosiCrew` anlegen
     oder anpassen. Wenn du einen anderen Namen nimmst, ändere ihn an beiden
     Stellen:
     - `Config/DosiCrew.entitlements`
     - `PersistenceController.cloudKitContainerIdentifier`
   - **Push Notifications** aktivieren.
   - **Background Modes** → *Remote notifications*.

3. `⌘U` — die Tests müssen grün sein.
4. `⌘R` auf einem Simulator oder Gerät, das in iCloud angemeldet ist.

## Icon

Ein Tropfen — die Gabe — mit einem Haken darin: eine Dosis, einmal bestätigt.
Die drei Varianten in `DosiCrew/Resources/Assets.xcassets/AppIcon.appiconset/`
(hell, dunkel, getönt) sind gerenderte 1024×1024-PNGs ohne Alphakanal, wie der
App Store es verlangt. Erzeugt werden sie von `Tools/make_icon.py`; wer Form
oder Farbe ändern will, passt das Skript an und lässt es neu laufen:

```
pip install Pillow && python3 Tools/make_icon.py
```

## Tests

35 Tests, die die Terminlogik abdecken und weder iCloud noch ein Gerät
brauchen. Sie laufen bei jedem Push auf dem macOS-Runner mit:

- `ScheduleEngineTests` (19) — Wiederholungsmuster, Behandlungszeiträume,
  überlappende Regeln, Zeitzonen und die Sommerzeit-Umstellung (eine Gabe um
  02:30 darf am Umstellungstag nicht verschwinden), Vorausplanung für
  Erinnerungen.
- `DoseMatchingTests` (16) — Zuordnung von Gaben zu geplanten Slots, Erkennung
  der Doppelgabe, Extra-Gaben, tagesübergreifende Gaben, Überfälligkeit.

Dazu `DosiCrewUITests` — kein Teil der schnellen Suite, sondern der
Screenshot-Lauf (siehe oben).

## Wie es gebaut ist

```
DosiCrew/
  Model/          Core-Data-Modell, Persistenz, Sharing, ScheduleEngine
  Features/       Heute · Medikamente · Ereignisse · Teilen · Einstellungen
  Notifications/  Planung und Aktionen der Erinnerungen
  Resources/      Localizable.xcstrings (de/en/es), Assets
Config/           Info.plist und Entitlements (bewusst außerhalb des
                  synchronisierten Ordners, damit Xcode sie nicht als
                  Ressource einbettet)
```

**Geplante Gaben werden berechnet, nicht gespeichert.** In der Datenbank liegen
nur Regeln (`ScheduleRule`) und tatsächliche Gaben (`DoseLog`). Der
`ScheduleEngine` leitet daraus die Slots eines Tages ab. Das hält die Zahl der
CloudKit-Records klein, macht Planänderungen rückwirkend konsistent — und die
gesamte Logik ist reines Swift ohne Core Data und damit ohne Gerät testbar.

**Synchronisation** läuft über `NSPersistentCloudKitContainer` mit zwei Stores
auf demselben Modell: `private.sqlite` spiegelt die eigene iCloud-Datenbank,
`shared.sqlite` alles, was andere geteilt haben. Geteilt wird das Wurzelobjekt
`Patient` — daran hängen Medikamente, Zeitpläne, Gaben und Ereignisse, sodass
eine angenommene Einladung den kompletten Plan mitbringt.

> SwiftData wäre der modernere Weg, spiegelt aber bis heute nur die *private*
> iCloud-Datenbank und hat keine `CKShare`-Schnittstelle. Für „mehrere Personen,
> ein Datensatz" führt derzeit kein Weg an Core Data vorbei.

**Erinnerungen werden nicht synchronisiert.** Jedes iPhone plant sie selbst aus
denselben Regeln — es gibt kein Backend, das pushen könnte. Damit trotzdem
niemand an eine Gabe erinnert wird, die längst jemand anderes gegeben hat,
weckt CloudKit die App per Silent Push (`NSPersistentStoreRemoteChange`), und
der Scheduler baut die ausstehenden Mitteilungen neu auf. Geplant wird immer nur
das nächste 48-Stunden-Fenster, weil iOS höchstens 64 ausstehende
Benachrichtigungen pro App zulässt.

## Grenzen

- Alle Beteiligten brauchen ein iPhone mit iCloud-Anmeldung. Kein Android, kein Web.
- Änderungen am Core-Data-Modell sind nach dem ersten Produktiveinsatz nur noch
  additiv möglich. Die Ereignisse sind deshalb von Anfang an im Schema.
- Nicht in dieser Version: Bedarfsmedikation („bei Bedarf" mit Mindestabstand und
  Tagesmaximum), Verlaufsansicht und PDF-Export für den Arzt. Das Datenmodell
  steht dem nicht im Weg.
- **Kein Medizinprodukt.** Die App organisiert, wer wann was gibt. Sie prüft
  weder Dosierungen noch Wechsel- oder Nebenwirkungen — das bleibt Sache von
  Ärztin, Arzt oder Apotheke.
