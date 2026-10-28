# Come usare Taggo

Taggo modifica i tag dei file audio (titolo, artista, album, copertina…) su macOS.
Formati: MP3, M4A/AAC/ALAC, FLAC, OGG, Opus, WAV, AIFF, APE, WavPack, WMA e altri.

> **Prima di iniziare:** fai una copia di prova di qualche album. Il salvataggio
> modifica i file originali.

---

## 1. Installazione

1. Apri `Taggo-x.y.z.dmg` e trascina **Taggo** nella cartella **Applicazioni**.
2. Al primo avvio macOS lo blocca, perché l'app non è firmata da uno sviluppatore registrato Apple:
   - **macOS 15 e successivi:** apri Taggo e chiudi l'avviso. Poi vai in
     **Impostazioni di Sistema → Privacy e sicurezza**, scorri in basso e premi **Apri comunque**.
   - **macOS 14:** tasto destro su Taggo → **Apri** → **Apri**.

   Serve solo la prima volta.

Requisiti: macOS 14 Sonoma o successivo, Mac Apple Silicon o Intel.

---

## 2. Aprire i file

- **Apri cartella** (⌘O) oppure trascina una cartella nella finestra. Taggo legge anche le sottocartelle.
- **Aggiungi cartella** (⇧⌘O) aggiunge file a quelli già aperti.
- Clic su un'intestazione per ordinare. Tasto destro sull'intestazione per mostrare o nascondere colonne.
- Il campo **Filtra** in alto mostra solo i file che contengono il testo cercato.

I file senza tag compaiono normalmente, con le colonne dei tag vuote.

---

## 3. Modificare i tag

1. Seleziona uno o più file nella tabella (⌘A seleziona tutto).
2. Modifica i campi nel pannello a sinistra.
3. Premi **Invio** o **Applica** (⌘↩).
4. Premi **Salva** (⌘S) per scrivere sul disco.

- Un **pallino arancione** indica i file modificati ma non ancora salvati.
- Con più file selezionati, un campo con valori diversi mostra `< mantieni >`:
  se lo lasci così, ogni file conserva il suo valore. Se scrivi qualcosa, il valore vale per tutti.
- Per svuotare un campo su tutti i file: tasto destro sul campo → **Svuota campo**.
- **File → Annulla modifiche non salvate** riporta tutto all'ultimo salvataggio.
- Se esci con modifiche in sospeso, Taggo chiede se salvarle.

### Copertina

In fondo al pannello: **Aggiungi…**, oppure trascina un'immagine sul riquadro.
Poi **Rimuovi** o **Esporta…**. L'immagine vale per tutti i file selezionati.

---

## 4. Convertitori (menu Converti)

Si applicano ai file selezionati, oppure a tutti quelli visibili se non ne selezioni nessuno.
Prima di confermare mostrano sempre un'anteprima.

Segnaposto disponibili:

| Segnaposto | Campo |
|---|---|
| `%title%` | Titolo |
| `%artist%` | Artista |
| `%album%` | Album |
| `%albumartist%` | Artista album |
| `%year%` | Anno |
| `%track%` | Traccia |
| `%discnumber%` | Disco |
| `%genre%` `%composer%` `%comment%` | Genere, Compositore, Commento |

### Tag → Nome file (⌥1)

Rinomina i file usando i tag.
`$num(%track%,2) - %title%` → `07 - L'estasi dell'oro.mp3`

- `$num(%campo%,2)` aggiunge zeri davanti (7 → 07).
- `/` crea sottocartelle: `CD%discnumber%/$num(%track%,2) - %title%`.
  Le sottocartelle nascono dentro la cartella in cui si trova già il file.
- **La rinomina avviene subito, senza ⌘S, e non si può annullare.**
- I file con tutti i campi vuoti e quelli il cui nuovo nome esiste già vengono saltati.

### Nome file → Tag (⌥2)

Ricava i tag dal nome del file.
`%track% - %artist% - %title%` su `07 - Ennio Morricone - L'estasi dell'oro.mp3`
→ Traccia 07, Artista Ennio Morricone, Titolo L'estasi dell'oro.

- `%dummy%` ignora una parte del nome.
- `/` legge anche le cartelle: `%artist%/%album%/%track% - %title%`.
- I nomi che non corrispondono allo schema vengono saltati.

### Numerazione automatica (⌥⌘K)

Numera le tracce 1, 2, 3… nell'ordine della tabella. Può ricominciare per ogni cartella.

### Dividi in dischi (⌥⌘D)

Divide un album in Disco 1, Disco 2… e ricomincia la numerazione delle tracce su ogni disco.
Un nuovo disco può iniziare:

- quando la numerazione riparte (…12, 1, 2…);
- a ogni sottocartella (CD1, CD2…);
- ogni N brani;
- dai brani che indichi tu.

**Ordina la tabella per Percorso prima di dividere:** l'ordine della tabella conta.

---

## 5. Azioni (menu Azioni)

- **Maiuscole/minuscole** (⌥⌘U): Iniziali Maiuscole, Prima lettera maiuscola, MAIUSCOLO, minuscolo.
- **Sostituisci** (⌥⌘F): cerca e sostituisci nei campi scelti. Accetta anche espressioni regolari, con `$1`, `$2` per i gruppi.

---

## 6. Fonti online (menu Fonti)

### Cerca su MusicBrainz (⌥⌘M)

1. Seleziona i brani di **un** album.
2. Artista e album sono già compilati, dai tag o dai nomi delle cartelle. Correggili se serve e premi **Cerca**.
3. Scegli l'edizione: in verde quelle con lo stesso numero di brani dei tuoi file.
4. Controlla l'abbinamento file → traccia. Le durate molto diverse sono in arancione.
5. Scegli i campi e la copertina, premi **Applica ai file**, poi **⌘S**.

Serve una connessione internet. Se MusicBrainz è occupato, Taggo riprova da solo.

### Apri in MusicBrainz Picard (⌥⌘P)

Apre i file in [Picard](https://picard.musicbrainz.org), che va installato a parte.
Picard riconosce anche i brani senza alcuna informazione, ascoltandone l'audio.
**Dopo aver salvato in Picard, torna in Taggo e premi Ricarica (⌘R).**

### Cerca sul web

Apre la ricerca dell'album su Discogs, AllMusic, Wikipedia, Last.fm, Bandcamp,
Apple Music, MusicBrainz o Google Immagini (utile per trovare le copertine).

---

## Scorciatoie

| Comando | Tasti |
|---|---|
| Apri cartella / Aggiungi | ⌘O / ⇧⌘O |
| Salva | ⌘S |
| Ricarica | ⌘R |
| Applica i campi del pannello | ⌘↩ |
| Tag → Nome file / Nome file → Tag | ⌥1 / ⌥2 |
| Numerazione / Dividi in dischi | ⌥⌘K / ⌥⌘D |
| Maiuscole / Sostituisci | ⌥⌘U / ⌥⌘F |
| MusicBrainz / Picard | ⌥⌘M / ⌥⌘P |

## Buono a sapersi

- Gli MP3 vengono salvati in ID3v2.4. Alcuni lettori molto vecchi leggono solo ID3v2.3.
- Al salvataggio vengono scritti solo i campi modificati: gli altri tag del file restano intatti.
- Doppio clic su un file lo apre con l'app predefinita. Il tasto destro offre **Mostra nel Finder**.
