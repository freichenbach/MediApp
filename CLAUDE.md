# DosiCrew — verbindliche Vorgaben

## Zweckbestimmung: DosiCrew ist kein Medizinprodukt

**Entschieden am 4. September 2026. Diese Entscheidung steht nicht mehr zur
Diskussion und ist bei jeder Änderung einzuhalten.**

DosiCrew ist ein **Protokoll- und Absprachewerkzeug** für Angehörige. Es hält
fest, was Menschen eingetragen haben, und zeigt es ihnen und den anderen
Beteiligten wieder an. Mehr nicht.

Diese Grenze ist keine Formalie: Sobald Software Gesundheitsdaten zu
diagnostischen oder therapeutischen Zwecken auswertet, ist sie nach MDR
Regel 11 ein Medizinprodukt der Klasse IIa oder höher. Das bedeutet Benannte
Stelle, Konformitätsbewertung, Swissmedic/MepV im Heimmarkt und einen
EU-Bevollmächtigten für den EU-Markt — für eine kostenlose App eines einzelnen
Entwicklers ist das nicht tragbar. Eine einzige gut gemeinte Zeile Code kann
diese Kette auslösen.

### Was die App darf

- Eingetragene Werte **speichern, anzeigen, umrechnen und formatieren**
  (mg/dl ⇄ mmol/l, Sekunden als „2:15 min", 120/80).
- Einen **Zeitplan abbilden** und daran erinnern — das ist ein Wecker, keine
  Therapieempfehlung.
- **Doppelte und fehlende Gaben sichtbar machen.** Das ist eine Aussage über
  die Einträge, nicht über das Kind.
- Auf **physikalisch unmögliche Eingaben** hinweisen (Sättigung über 100 %,
  diastolisch über systolisch). Das ist Tippfehlerschutz, keine Bewertung.
- Das Erfasste **für den Arzt exportieren**, ohne es zu deuten.

### Was die App niemals tun darf

- Einen Messwert als **auffällig, kritisch, zu hoch oder zu niedrig**
  kennzeichnen — auch nicht farblich, auch nicht mit einem Warndreieck.
- **Klinische Schwellen** hinterlegen, an denen sich die Anzeige ändert.
  (Deshalb wurde der Fünf-Minuten-Hinweis beim epileptischen Anfall entfernt.
  Siehe den Kommentar in `DosiCrew/Model/Measurements.swift`, `SeizureDuration`.)
- Eine **Dosis berechnen**, vorschlagen oder aus Gewicht, Alter oder
  Vorgeschichte ableiten.
- Zu einer **Handlung raten** — „Arzt rufen", „Notfallmedikament geben",
  „Dosis auslassen".
- **Trends deuten** („der Blutdruck steigt seit drei Tagen").
- Werte gegen **Normbereiche, Leitlinien oder Referenzkurven** prüfen.

Faustregel für jede neue Funktion: *Sagt sie etwas über die Einträge — oder
über das Kind?* Das Erste ist erlaubt, das Zweite nicht. Im Zweifel weglassen
und nachfragen.

### Wo das sonst noch gilt

Auch in Store-Beschreibung, Screenshots, Schlüsselwörtern, Marketingtexten und
Review-Notizen. Wörter wie „überwacht", „erkennt", „warnt" oder „kontrolliert"
beschreiben ein Medizinprodukt; „festhalten", „anzeigen", „abstimmen",
„erinnern" beschreiben diese App. Die Zweckbestimmung, die der Anbieter selbst
angibt, ist der Ausgangspunkt jeder Einstufung — sie muss überall dieselbe sein.
