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

Was damit **nicht** geht: die App auf ein echtes iPhone bringen. Dafür braucht
es Signierung mit einem Apple-Developer-Zertifikat. Ohne eigenen Mac sind die
realistischen Wege ein gemieteter Mac in der Cloud (MacStadium, Scaleway,
AWS EC2 Mac — stundenweise) oder ein Fastlane-Setup mit App-Store-Connect-
API-Key, das aus derselben CI heraus nach TestFlight lädt.

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
