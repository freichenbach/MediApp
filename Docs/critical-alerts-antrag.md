# Antrag auf das Critical-Alerts-Entitlement

Formular:
<https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement>

**Gestellt am 2026-09-03 — Request ID `5BULB2V9N5`. Am selben Tag genehmigt.**
Apple hat das Entitlement der App ID `es.reichenbach.DosiCrew` zugewiesen; es
steht seither in `Config/DosiCrew.entitlements` und
`Config/DosiCrew.Release.entitlements`.

Was unten steht, ist damit Beleg statt Anleitung: es dokumentiert, was
eingereicht wurde, und dient als Vorlage, falls Apple nachfragt oder der Antrag
für eine weitere App wiederholt werden muss.

Im Code war der Weg schon vorbereitet und hat sich mit dem Entitlement von
selbst eingeschaltet: `requestAuthorization` fragt `.criticalAlert` seit jeher
mit an, und `urgency(for:)` liest `criticalAlertSetting` und stuft die
Erinnerung hoch, sobald das System die Berechtigung erteilt hat. Es war also
kein Codeumbau nötig, nur zwei Zeilen in den Entitlements.

Auszufüllen ist der Abschnitt **Details**. Er hat vier Eingaben; unten steht zu
jeder der fertige Text zum Kopieren. Das Formular ist englisch, also ist der
englische Text der einzureichende — die deutsche Fassung darunter dient nur zum
Gegenlesen und wird nicht abgeschickt.

| Feld | Wert |
|---|---|
| App Type | **Healthcare** |
| Bundle ID | `es.reichenbach.DosiCrew` |
| Describe your app | Text 1 |
| What type of notifications will you send as Critical Alerts? | Text 2 |
| How frequently will you send Critical Alerts? | siehe unten |
| Explain why you need this entitlement and how it will be used in your app. | Text 3 |

Nach einer Freigabe fehlt nur noch
`com.apple.developer.usernotifications.critical-alerts` in
`Config/DosiCrew.entitlements` und `Config/DosiCrew.Release.entitlements`; der
Code darunter ist schon da. **Vorher eingetragen bricht es den Export.**

---

## Text 1 — Describe your app

> DosiCrew coordinates giving prescribed medication to a child among the several
> people who care for that child: two parents, often in separate households, a
> grandparent, a childminder. Each medication holds its dose and its schedule.
> Every caregiver's iPhone shows the same plan, and a dose ticked off on one
> device appears on all the others within seconds through CloudKit.
>
> The app exists to prevent two specific failures: a missed dose and a double
> dose. Both are realistic once responsibility is shared and nobody is certain
> whether somebody else has already given the medicine.
>
> DosiCrew does not diagnose, and does not check doses, interactions or
> contraindications. The schedule is the one the prescribing doctor gave; the
> app only keeps the people sharing the care from losing track of it.

## Text 2 — What type of notifications will you send as Critical Alerts?

> Only two, both about medication for a child:
>
> 1. A scheduled dose is due now.
> 2. A dose is still not confirmed 30 minutes after it was due.
>
> Nothing else in the app produces a Critical Alert. There are no marketing,
> engagement, social or sync notifications — the app has no such features.
>
> An alert is withdrawn rather than repeated: when any caregiver ticks a dose
> off, that syncs to every device and the pending reminder for that dose is
> removed everywhere. Somebody asleep while their partner gives the dose is not
> woken.

## How frequently will you send Critical Alerts?

Ein Auswahlfeld. Die wahrheitsgemäße Antwort ist **mehrmals täglich**: die Zahl
ist durch die Verordnung selbst begrenzt, üblicherweise ein bis sechs pro Tag
und Medikament, an Tagen ohne Plan keine, und mit dem Ende des eingetragenen
Behandlungszeitraums hören sie auf.

Wähle also die Option, die *mehrmals* oder *mehrfach täglich* sagt. Gibt es das
nicht, nimm **Daily** — nach oben zu runden ist der ehrlichere Fehler als nach
unten.

## Text 3 — Explain why you need this entitlement and how it will be used

> The reminders already use the time-sensitive interruption level, which gets
> them past Focus and Do Not Disturb. That is not sufficient, because the
> situations in which a dose is most likely to be missed are precisely the ones
> in which the iPhone is silenced:
>
> - Night doses. Antibiotics on a strict interval, anticonvulsants and
>   post-operative pain medication are commonly prescribed at intervals that
>   fall in the middle of the night. Caregivers silence their phone at night,
>   often deliberately, so as not to wake the sick child sleeping in the same
>   room. A silent banner at 02:00 is not a reminder.
> - A caregiver who is not the parent. A childminder or a grandparent keeps
>   their phone silenced while looking after children. They are the person
>   holding the medicine at that moment.
> - Handovers. When the child moves between households mid-course, the next
>   dose is owed by somebody who was not present for the last one and has no
>   independent memory of the schedule.
>
> A missed antibiotic dose is a treatment failure and a driver of resistance. A
> missed anticonvulsant dose can mean a seizure. These are not conveniences
> that can wait until somebody next unlocks their phone.
>
> Users stay in control. Reminders can be switched off entirely in the app's
> settings, and the overdue follow-up can be switched off separately. The app
> requests critical alert authorization explicitly and works normally without
> it, falling back to time-sensitive notifications. The standard iOS per-app
> toggle for Critical Alerts applies and is not worked around. The app's
> settings screen always states plainly which level is actually in effect, so
> nobody relies on a sound that will not come.
>
> The alert volume is set to 0.8 rather than 1.0: this has to wake an adult in
> the next room, it must not frighten the child the alert is about.

**Falls Text 3 zu lang ist** für das Feld: die drei Aufzählungspunkte auf den
ersten kürzen (Nachtgaben) und den letzten Absatz zur Lautstärke weglassen. Der
Absatz über die Kontrolle durch die Nutzenden muss bleiben — danach fragt Apple
ausdrücklich.

---

## Deutsche Fassung (nur zum Gegenlesen)

### Text 1 — Beschreibung der App

DosiCrew stimmt die Gabe verordneter Medikamente an ein Kind zwischen den
mehreren Personen ab, die es betreuen: zwei Eltern, oft in getrennten
Haushalten, Großeltern, eine Tagesmutter. Jedes Medikament trägt seine
Dosierung und seinen Zeitplan. Alle iPhones zeigen denselben Plan, und ein auf
einem Gerät gesetzter Haken ist über CloudKit binnen Sekunden auf allen anderen
sichtbar.

Die App verhindert genau zwei Fehler: die vergessene Gabe und die doppelte
Gabe. Beide sind realistisch, sobald die Verantwortung geteilt ist und niemand
sicher weiß, ob jemand anderes das Medikament schon gegeben hat.

DosiCrew stellt keine Diagnose und prüft weder Dosierungen noch Wechsel- oder
Gegenanzeigen. Der Zeitplan ist der des verordnenden Arztes; die App sorgt nur
dafür, dass die Betreuenden ihn nicht aus den Augen verlieren.

### Text 2 — Art der Meldungen

Nur zwei, beide zur Medikamentengabe an ein Kind:

1. Eine geplante Gabe ist jetzt fällig.
2. Eine Gabe ist 30 Minuten nach der geplanten Zeit noch nicht bestätigt.

Sonst nichts. Keine Werbung, keine Engagement-, Social- oder Sync-Meldungen —
die App hat solche Funktionen nicht.

Eine Meldung wird zurückgenommen, nicht wiederholt: hakt eine betreuende Person
die Gabe ab, wird die ausstehende Erinnerung auf allen Geräten gelöscht. Wer
schläft, während der Partner die Dosis gibt, wird nicht geweckt.

### Text 3 — Begründung

Die Erinnerungen laufen bereits auf der zeitkritischen Stufe und kommen damit
durch Fokus und „Nicht stören". Das genügt nicht, denn genau die Lagen, in
denen eine Gabe am ehesten ausfällt, sind die, in denen das iPhone
stummgeschaltet ist:

- Nachtgaben. Antibiotika mit striktem Intervall, Antiepileptika und
  Schmerzmittel nach einer Operation liegen häufig mitten in der Nacht.
  Betreuende schalten ihr Telefon nachts stumm — oft mit Absicht, um das kranke
  Kind im selben Zimmer nicht zu wecken. Ein lautloses Banner um 2 Uhr ist
  keine Erinnerung.
- Betreuende, die nicht die Eltern sind. Eine Tagesmutter oder Großeltern haben
  das Telefon während der Betreuung stumm. Genau sie halten in dem Moment das
  Medikament in der Hand.
- Übergaben. Wechselt das Kind mitten in der Behandlung den Haushalt, schuldet
  die nächste Gabe jemand, der bei der letzten nicht dabei war.

Eine ausgelassene Antibiotikagabe ist ein Therapieversagen und treibt
Resistenzen. Eine ausgelassene Antiepileptikagabe kann einen Anfall bedeuten.
Das kann nicht warten, bis das Telefon das nächste Mal entsperrt wird.

Die Kontrolle bleibt bei den Nutzenden. Erinnerungen lassen sich in den
Einstellungen ganz abschalten, die Nachfass-Erinnerung getrennt davon. Die App
fragt die Berechtigung ausdrücklich an und funktioniert ohne sie normal weiter,
dann auf der zeitkritischen Stufe. Der übliche iOS-Schalter pro App gilt und
wird nicht umgangen. Die Einstellungen der App nennen immer den tatsächlich
wirksamen Zustand, damit sich niemand auf ein Klingeln verlässt, das nicht
kommt.

Die Lautstärke ist 0,8 statt 1,0: das soll einen Erwachsenen im Nebenzimmer
wecken, nicht das Kind erschrecken, um das es geht.
