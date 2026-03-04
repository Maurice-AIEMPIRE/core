---
name: faceless-youtube
description: Faceless YouTube Automation Pipeline — Script to Upload
version: 1.0.0
metadata:
  openclaw:
    requires:
      config:
        - browser
---

# Faceless YouTube Factory Skill

Vollautomatische Faceless YouTube Video Produktion Pipeline.
Agent: Ross (YouTube & Video)

## Pipeline (5 Schritte)
1. **Script** — AI generiert Video-Script mit SEO-Metadaten
2. **TTS** — Text-to-Speech Audio (edge-tts, piper, gTTS)
3. **Images** — Stock-Bilder via Pexels Browser
4. **Assemble** — FFmpeg Video aus Audio + Bildern
5. **Upload** — Via youtube-studio.sh mit Human-in-the-Loop

## Browser Script
`openclaw/browser/youtube-faceless.sh`

## Befehle
- `/ross-faceless` — Volle 1-Klick Pipeline
- `/ross-script` — Nur Script generieren
- `/ross-tts` — Text-to-Speech
- `/ross-niches` — Profitable Nischen anzeigen
- `/ross-trending` — Trending Topics finden
- `./youtube-faceless.sh assemble <audio> [images-dir]` — Video bauen
- `./youtube-faceless.sh thumbnail <title>` — Thumbnail erstellen
- `./youtube-faceless.sh upload <video> <meta.json>` — Upload
- `./youtube-faceless.sh analytics` — Performance Report

## Profitable Nischen
Finance, Tech, Health, Motivation, Facts, Horror, Gaming, Money

## Voraussetzungen
- ffmpeg (Video-Assembly)
- edge-tts oder gTTS (pip install edge-tts)
- ImageMagick oder Pillow (Thumbnails)
