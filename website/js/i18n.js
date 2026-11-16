// Language: English or German. Picks the browser's language on the first visit, remembers the
// footer switch (localStorage), and also takes ?lang=de / ?lang=en. English text lives in the
// HTML; German strings are swapped in by data-i18n key. Legal pages use [data-lang] blocks.
(function () {
  var DE = {
 "nav.tables": "Tische",
 "nav.shove": "Schubsen",
 "nav.mini": "Minispiele",
 "nav.items": "Items",
 "nav.wish": "Wunschliste",
 "hero.eyebrow": "The Lucky Lounge · seit heute Abend",
 "hero.t1": "Roter Teppich.",
 "hero.t2": "Goldrand.",
 "hero.t3": "Null Würde.",
 "hero.lede": "Ein chaotisches Casino-Partyspiel für 2–8 Freunde. Gewinn an den Tischen, schubs den Führenden vom Hocker und sei die reichste Bohne zur Sperrstunde.",
 "cta.soon": "Bald verfügbar",
 "cta.wish": "Auf Steam wünschen",
 "cta.float": "<span aria-hidden=\"true\">★</span> Auf Steam wünschen",
 "hero.trailer": "▶ Trailer ansehen",
 "hero.scroll": "Scrollen zum Eintreten",
 "tk.players": "<b>2–8</b> Spieler online",
 "tk.casino": "<b>11</b> Casinospiele",
 "tk.mini": "<b>16</b> Minispiele",
 "tk.items": "<b>33</b> Items",
 "tk.start": "<b>$1.000</b> Startgeld",
 "tk.outfit": "<b>75</b> Outfit-Teile",
 "t.eyebrow": "<span class=\"num\">01</span> Spiel an den Tischen",
 "t.h2": "Die Bank gewinnt immer.<br><em>Deine Freunde müssen nicht.</em>",
 "t.p": "Lauf in der Ego-Perspektive durchs Casino und setz dich, wo du willst. Alle spielen gleichzeitig, also weißt du immer, wer gerade gewinnt. Und wo er sitzt.",
 "t.l1": "<b>Elf Casinospiele</b> mit echten Regeln: Blackjack, Roulette, Craps, Casino Hold'em, Hi-Lo, Slots, Peg Drop, das Big Wheel, Rubbellose, das Bean Derby und Sword Tapper",
 "t.l2": "<b>Ein progressiver Jackpot</b>, der die ganze Nacht wächst und bei einer glücklichen Bohne landet",
 "t.l3": "<b>Hot Tables</b> zahlen extra, also rennen alle zu denselben paar Hockern",
 "t.l4": "<b>Glück ist ein echter Wert.</b> Ein Kleeblatt hebt ihn, eine schwarze Katze zieht ihn runter",
 "f.eyebrow": "<span class=\"num\">02</span> Oder spiel gegen deine Freunde",
 "f.h2": "Warum gegen die Quoten spielen,<br><em>wenn du den Führenden schlagen kannst?</em>",
 "f.l1": "Schubs, pack und wirf jeden, dem es besser geht als dir",
 "f.l2": "Schlag einen Rivalen k.o. und schüttel ihm die Chips aus den Taschen",
 "f.l3": "Sammel die verstreuten Chips ein, bevor er aufwacht",
 "f.l4": "Die Security schaut zu. Wer erwischt wird, landet im Knast, und die Strafe wird jedes Mal höher",
 "f.l5": "Schlag nicht den Dealer. Wirklich nicht.",
 "f.cap": "Szenen aus dem Spiel",
 "m.eyebrow": "<span class=\"num\">03</span> 16 Minispiele, moderiert von einer Katze",
 "m.h2": "Alle paar Minuten<br><em>schließt Lucky die Tische.</em>",
 "m.p": "Lucky, die Hauskatze, treibt alle in ein Minispiel. Wer gut abschneidet, kommt mit Geld und einem Item zurück ins Casino.",
 "g.think": "Kurz nachdenken",
 "g.brawl": "Prügeln",
 "g.climb": "Klettern",
 "lc.eyebrow": "Die letzten 60 Sekunden",
 "lc.mult": "<span>×1,5</span> Auszahlung. Keiner benimmt sich.",
 "i.eyebrow": "<span class=\"num\">04</span> Das Taschen-Arsenal",
 "i.h2": "33 Items, die<br><em>Freundschaften beenden.</em>",
 "i.hint": "Wischen <i>→</i>",
 "i.1": "Er rutscht aus, seine Chips fliegen, du warst nie da.",
 "i.2": "Glück −3 für den, der ihn trägt. Mit einem Schubser weitergeben.",
 "i.3": "$300 jetzt, $360 zurück in 90 Sekunden. Oder alles, was du hast.",
 "i.4": "Jeder Abzug bringt 20 % mehr Geld. Bis auf den einen.",
 "i.5": "Ein freundliches Schulterklopfen. Eine leichtere Brieftasche.",
 "i.6": "Der schnellste Weg, einen Streit um Chips zu gewinnen.",
 "i.7": "30 Sekunden lang schaut die Security weg. Nutz sie.",
 "i.8": "Dein Glück steigt. Die Anzeige auf deinem Bildschirm sagt es.",
 "i.9": "Nimm dem Führenden 8 % und verteil sie an alle anderen. Dich eingeschlossen.",
 "i.10": "Genau das, was draufsteht. Jeden Chip wert.",
 "i.11": "Jedes schlimmer für deine Freundschaften als das letzte.",
 "tr.play": "Trailer ansehen",
 "r.eyebrow": "<span class=\"num\">05</span> Laut mit Absicht",
 "r.h2": "Proximity-Voice.<br><em>Zehn Emotes. Keine Scham.</em>",
 "r.p": "Hör den Nachbartisch jubeln und die Bohne, die sich von hinten anschleicht. Die Bohnen bewegen beim Reden den Mund.",
 "r.c1": "Der Casinosaal",
 "r.c2": "Elf Tische, eine Brieftasche",
 "r.c3": "Minispiele",
 "r.c4": "Emotes, inklusive 6-7",
 "ru.eyebrow": "<span class=\"num\">06</span> Dein Casino, deine Regeln",
 "ru.h2": "Eine halbe Stunde.<br><em>Oder bis jemand weint.</em>",
 "ru.1h": "Spieler online",
 "ru.1p": "Lade über Steam ein, teil einen Raumcode aus fünf Buchstaben oder öffne eine öffentliche Lobby.",
 "ru.2h": "Minispiele pro Abend",
 "ru.2p": "Mit 1 bis 6 Minuten Zocken dazwischen. Du bestimmst die Länge.",
 "ru.3h": "Casinos",
 "ru.3p": "Die Tische werden jede Runde neu aufgestellt, während alle in der Lobby eingesperrt sind.",
 "ru.4h": "Mathe nötig",
 "ru.4p": "Der Modus „Nur Minispiele“, wenn niemand Karten zählen will.",
 "ru.5h": "Outfit-Teile",
 "ru.5p": "Hüte, Hemden, Hosen, Umhänge und Stiefel. Die meisten schaltest du mit Coins frei, die du beim Spielen verdienst, ein paar sind optionale Extras auf Steam. Rein kosmetisch, keine Lootboxen.",
 "ru.6p": "Übe die Tische alleine, bevor du dich vor allen blamierst.",
 "fin.eyebrow": "Sperrstunde",
 "fin.h2": "Sei die reichste Bohne<br>im Raum.",
 "faq.eyebrow": "Fragen an der Kasse",
 "faq.q1": "Was ist Better at Gambling?",
 "faq.a1": "Better at Gambling ist ein Online-Casino-Partyspiel für 2 bis 8 Freunde. Alle starten mit $1.000 in Spielchips. Geld gewinnst du an elf Casinospielen wie Blackjack, Roulette und Slots, in 16 Minispielen oder indem du den Führenden schubst und ihm die Chips aus den Taschen schüttelst. Die reichste Bohne zur Sperrstunde gewinnt.",
 "faq.q2": "Wird um echtes Geld gespielt?",
 "faq.a2": "Nein. Gespielt wird nur mit fiktiven Chips. Echtes Geld kann weder eingesetzt noch gewonnen werden, Chips und Coins kann man nicht kaufen, und nichts lässt sich auszahlen.",
 "faq.q3": "Gibt es Mikrotransaktionen?",
 "faq.a3": "Ja, optionale Kosmetik. Einzelne Outfit-Teile für deine Bohne kosten über Steam 0,50 bis 1 €, und 10 Outfit-Pakete gibt es günstiger als die Teile einzeln. Die meisten der 75 Outfit-Teile kannst du auch mit Coins freischalten, die du beim Spielen verdienst, zehn Teile gibt es nur gegen Geld, und alle Bohnenfarben verdienst du im Spiel. Käufe sind rein kosmetisch: Sie helfen dir nie beim Gewinnen, und es gibt keine Lootboxen.",
 "faq.q4": "Wie viele Spieler können mitspielen?",
 "faq.a4": "2 bis 8 Spieler online. Freunde lädst du über Steam ein. Mit einem Übungsmodus und einem Tutorial lernst du die Tische alleine.",
 "faq.q5": "Auf welchen Plattformen gibt es das Spiel?",
 "faq.a5": "Better at Gambling erscheint auf Steam für Windows-PC. Versionen für macOS und Linux sind im Test.",
 "faq.q6": "Wann erscheint Better at Gambling?",
 "faq.a6": "Das Spiel kommt bald auf Steam. Setz es auf deine Steam-Wunschliste, dann bekommst du am Erscheinungstag eine Nachricht.",
 "faq.q7": "Gibt es Voice-Chat?",
 "faq.a7": "Ja. Proximity-Voice-Chat ist eingebaut, du hörst also die Spieler in deiner Nähe, und die Bohnen bewegen beim Reden den Mund. Ein Mikrofon ist optional.",
 "faq.q8": "Wie lange dauert eine Runde?",
 "faq.a8": "Das bestimmst du: 1 bis 10 Minispiele mit 1 bis 6 Minuten Zocken dazwischen. Ein normaler Abend dauert etwa eine halbe Stunde.",
 "fp.seal": "NUR<br>SPIEL-<br>GELD",
 "fp.h3": "Das Einzige, was du hier verlieren kannst, ist dein Gesicht.",
 "fp.p": "Better at Gambling wird mit fiktiven Chips gespielt. Es gibt kein Glücksspiel um echtes Geld und nichts zum Auszahlen. Zu kaufen gibt es nur optionale kosmetische Outfits für deine Bohne, und keins davon hilft dir beim Gewinnen.",
 "ft.imp": "Impressum",
 "ft.priv": "Datenschutz",
 "ft.legal": "© 2026 <a href=\"https://cerny.app/\">Patrick Cerny</a>. Gemacht mit der Godot Engine. Nur fiktive Chips; echtes Geld kann weder eingesetzt noch gewonnen werden. Steam und das Steam-Logo sind Marken der Valve Corporation.",
 "ld.label": "Karten werden gemischt <b id=\"loaderPct\">0%</b>"
};
  var EN = {"ft.imp": "Imprint", "ft.priv": "Privacy Policy"};
  var META = {
    de: { title: 'Better at Gambling · Casino-Partyspiel für 2–8 Freunde', desc: 'Better at Gambling ist ein chaotisches Online-Casino-Partyspiel für 2–8 Freunde. Blackjack, Roulette und Slots mit Spielgeld, den Führenden schubsen und 16 Minispiele gewinnen. Auf Steam wünschen.' },
    en: null
  };
  var orig = {};
  function pick() {
    try { var q = new URLSearchParams(location.search).get('lang'); if (q === 'de' || q === 'en') { localStorage.setItem('bag-lang', q); return q; } } catch (e) {}
    try { var s = localStorage.getItem('bag-lang'); if (s === 'de' || s === 'en') return s; } catch (e) {}
    var langs = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || 'en'];
    for (var i = 0; i < langs.length; i++) {
      var l = String(langs[i]).toLowerCase();
      if (l.indexOf('de') === 0) return 'de';
      if (l.indexOf('en') === 0) return 'en';
    }
    return 'en';
  }
  function apply(lang) {
    document.documentElement.lang = lang;
    var els = document.querySelectorAll('[data-i18n]');
    for (var i = 0; i < els.length; i++) {
      var el = els[i], k = el.getAttribute('data-i18n');
      if (!(k in orig)) orig[k] = el.innerHTML;
      var t = lang === 'de' ? DE[k] : (EN[k] || orig[k]);
      if (t != null && el.innerHTML !== t) el.innerHTML = t;
    }
    var tp = document.querySelector('[data-i18n-title]');
    if (tp) {
      if (!orig.__title) orig.__title = document.title;
      document.title = lang === 'de' && tp.getAttribute('data-i18n-title') ? tp.getAttribute('data-i18n-title') : orig.__title;
    } else if (META.de && document.body.classList.contains('home')) {
      if (!orig.__title) orig.__title = document.title;
      document.title = lang === 'de' ? META.de.title : orig.__title;
    }
    var btns = document.querySelectorAll('[data-setlang]');
    for (var j = 0; j < btns.length; j++) btns[j].setAttribute('aria-pressed', btns[j].getAttribute('data-setlang') === lang ? 'true' : 'false');
  }
  window.bagSetLang = function (lang) {
    try { localStorage.setItem('bag-lang', lang); } catch (e) {}
    apply(lang);
  };
  document.addEventListener('click', function (e) {
    var b = e.target.closest && e.target.closest('[data-setlang]');
    if (b) { e.preventDefault(); window.bagSetLang(b.getAttribute('data-setlang')); }
  });
  apply(pick());
})();
