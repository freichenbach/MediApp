# Antrag auf das Critical-Alerts-Entitlement

Einzureichen unter
<https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement>
mit dem Apple-Developer-Account, dem das Team gehört.

Das Formular ist englisch, also ist der englische Text der einzureichende. Die
deutsche Fassung darunter dient nur zum Gegenlesen — sie wird nicht abgeschickt.

Vor dem Absenden zu prüfen:

- **Bundle ID:** `es.reichenbach.DosiCrew`
- **Team ID:** die zehnstellige ID aus dem Developer-Account
- **App-Name:** DosiCrew

Nach einer Freigabe fehlt nur noch
`com.apple.developer.usernotifications.critical-alerts` in
`Config/DosiCrew.entitlements` und `Config/DosiCrew.Release.entitlements`; der
Code darunter ist schon da. **Vorher eingetragen bricht es den Export.**

---

## Einzureichender Text (Englisch)

**App name:** DosiCrew
**Bundle ID:** `es.reichenbach.DosiCrew`

### What the app does

DosiCrew coordinates the administration of prescribed medication to a child
among the several people who care for that child — two parents in separate
households, a grandparent, a childminder. Each medication carries its dose and a
schedule; every caregiver's iPhone shows the same plan, and a dose ticked off on
one device is visible on all the others within seconds through CloudKit.

The app exists to prevent exactly two failures: a **missed dose** and a **double
dose**. Both are realistic when responsibility is shared and nobody is certain
whether somebody else has already given the medicine.

### Why critical alerts are needed

The reminders are already sent at the time-sensitive interruption level, which
gets them past Focus and Do Not Disturb. That is not sufficient, because the
situations in which a dose is most likely to be missed are precisely the ones in
which the iPhone is silenced:

- **Night doses.** Antibiotics on a strict interval, anticonvulsants and
  post-operative pain medication are commonly prescribed at intervals that fall
  in the middle of the night. Caregivers silence their phone at night — often
  deliberately, so as not to wake the sick child sleeping in the same room. A
  silent banner at 02:00 is not a reminder.
- **A caregiver who is not the parent.** A childminder or a grandparent keeps
  their phone silenced while looking after children. They are the person holding
  the medicine at that moment.
- **Handover gaps.** When the child moves between households mid-course, the
  next dose is owed by somebody who was not present for the last one and has no
  independent memory of the schedule.

A missed antibiotic dose is a treatment failure and a driver of resistance. A
missed anticonvulsant dose can mean a seizure. These are not conveniences that
can wait for the next time somebody unlocks their phone.

### How the app uses critical alerts

Narrowly, and only for medication:

1. A scheduled dose becomes due.
2. A dose is still not confirmed 30 minutes after it was due.

Nothing else in the app produces a critical alert. There are no marketing
messages, no sync notifications, no product news, no social or engagement
notifications of any kind — the app has no such features.

The volume is set to 0.8 rather than 1.0. This has to wake an adult in the next
room; it must not frighten the child the alert is about.

The number of alerts is bounded by the prescription itself — typically one to
six per day per medication, and zero on any day with no medication scheduled.
Alerts stop as soon as the treatment period entered for the medication ends.

Crucially, an alert is **withdrawn rather than repeated**: when any caregiver
ticks a dose off, that fact syncs to every device and the pending reminder for
that dose is removed everywhere. Somebody who is asleep while their partner
gives the dose is not woken.

### User control

- Reminders can be switched off entirely in the app's settings, and the overdue
  follow-up can be switched off separately.
- The app requests critical alert authorization explicitly and functions
  normally without it, falling back to time-sensitive notifications.
- The standard iOS per-app toggle for critical alerts applies and is not worked
  around.
- The app's settings screen always states plainly which level is actually in
  effect, so nobody relies on a sound that will not come.

### Scope

DosiCrew records who gave what and when. It does not diagnose, does not check
doses, interactions or contraindications, and does not present itself as a
medical device. The schedule is the one the prescribing doctor gave; the app
only makes sure the people sharing the care do not lose track of it.

---

## Deutsche Fassung (nur zum Gegenlesen)

**App-Name:** DosiCrew
**Bundle ID:** `es.reichenbach.DosiCrew`

### Was die App tut

DosiCrew stimmt die Gabe verordneter Medikamente an ein Kind zwischen den
mehreren Personen ab, die es betreuen — zwei Eltern in getrennten Haushalten,
Großeltern, eine Tagesmutter. Jedes Medikament trägt seine Dosierung und einen
Zeitplan; alle iPhones zeigen denselben Plan, und ein auf einem Gerät gesetzter
Haken ist über CloudKit binnen Sekunden auf allen anderen sichtbar.

Die App verhindert genau zwei Fehler: die **vergessene Gabe** und die **doppelte
Gabe**. Beide sind realistisch, sobald die Verantwortung geteilt ist und niemand
sicher weiß, ob jemand anderes das Medikament schon gegeben hat.

### Warum Critical Alerts nötig sind

Die Erinnerungen laufen bereits auf der zeitkritischen Stufe und kommen damit
durch Fokus und „Nicht stören". Das genügt nicht, denn genau die Lagen, in denen
eine Gabe am ehesten ausfällt, sind die, in denen das iPhone stummgeschaltet
ist:

- **Nachtgaben.** Antibiotika mit striktem Intervall, Antiepileptika und
  Schmerzmittel nach einer Operation liegen häufig mitten in der Nacht.
  Betreuende schalten ihr Telefon nachts stumm — oft mit Absicht, um das kranke
  Kind im selben Zimmer nicht zu wecken. Ein lautloses Banner um 2 Uhr ist keine
  Erinnerung.
- **Betreuende, die nicht die Eltern sind.** Eine Tagesmutter oder Großeltern
  haben das Telefon während der Betreuung stumm. Genau sie halten in dem Moment
  das Medikament in der Hand.
- **Übergaben.** Wechselt das Kind mitten in der Behandlung den Haushalt,
  schuldet die nächste Gabe jemand, der bei der letzten nicht dabei war.

Eine ausgelassene Antibiotikagabe ist ein Therapieversagen und treibt
Resistenzen. Eine ausgelassene Antiepileptikagabe kann einen Anfall bedeuten.
Das kann nicht warten, bis das Telefon das nächste Mal entsperrt wird.

### Wie die App sie einsetzt

Eng begrenzt und nur für Medikamente:

1. Eine geplante Gabe wird fällig.
2. Eine Gabe ist 30 Minuten nach der geplanten Zeit noch nicht bestätigt.

Sonst nichts. Keine Werbung, keine Sync-Meldungen, keine Produktneuigkeiten,
keine Engagement-Mitteilungen — die App hat solche Funktionen nicht.

Die Lautstärke ist 0,8 statt 1,0: das soll einen Erwachsenen im Nebenzimmer
wecken, nicht das Kind erschrecken, um das es geht.

Die Zahl der Meldungen ist durch die Verordnung selbst begrenzt — üblicherweise
ein bis sechs pro Tag und Medikament, an Tagen ohne Plan keine. Mit dem Ende des
eingetragenen Behandlungszeitraums hören sie auf.

Entscheidend: eine Meldung wird **zurückgenommen, nicht wiederholt**. Hakt eine
betreuende Person die Gabe ab, wird die noch ausstehende Erinnerung auf allen
Geräten gelöscht. Wer schläft, während der Partner die Dosis gibt, wird nicht
geweckt.

### Kontrolle durch die Nutzenden

- Erinnerungen lassen sich in den Einstellungen ganz abschalten, die
  Nachfass-Erinnerung getrennt davon.
- Die App fragt die Berechtigung ausdrücklich an und funktioniert ohne sie
  normal weiter, dann auf der zeitkritischen Stufe.
- Der übliche iOS-Schalter pro App gilt und wird nicht umgangen.
- Die Einstellungen der App nennen immer den tatsächlich wirksamen Zustand,
  damit sich niemand auf ein Klingeln verlässt, das nicht kommt.

### Abgrenzung

DosiCrew hält fest, wer wann was gegeben hat. Sie stellt keine Diagnose, prüft
weder Dosierungen noch Wechsel- oder Gegenanzeigen und gibt sich nicht als
Medizinprodukt aus. Der Zeitplan ist der des verordnenden Arztes; die App sorgt
nur dafür, dass die Betreuenden ihn nicht aus den Augen verlieren.
