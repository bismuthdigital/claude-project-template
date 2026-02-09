---
name: comic
description: >
  Generates SVG explainer comics about the project for non-technical audiences.
  Supports technical reference and kawaii pastel pink themes, single or 4-panel layouts.
argument-hint: "[--kawaii] [--panels 1|4] [topic]"
allowed-tools: Read, Glob, Grep, Write, Bash(mkdir -p *)
---

# SVG Explainer Comic Generator

Generate visual explainer comics that communicate project concepts to a wide audience. Analyzes the codebase to produce accurate, engaging SVG comics using pre-built character symbols and a structured layout system.

## Arguments

```
/comic                                    # Auto-pick topic, technical theme, single panel
/comic --kawaii                            # Kawaii pastel pink theme
/comic --panels 4                         # 4-panel comic strip
/comic --kawaii --panels 4                 # 4-panel kawaii comic
/comic "authentication flow"              # Specific topic
/comic --kawaii "how testing works" --panels 4
```

**Defaults:** technical theme, 1 panel, auto-detected topic.

## Theme Palettes

### Technical Reference

| Role | Value |
|------|-------|
| `bg` | `#1B2838` |
| `panel` | `#FFFFFF` |
| `border` | `#2C3E50` |
| `accent` | `#3498DB` |
| `accent2` | `#2980B9` |
| `text` | `#2C3E50` |
| `titleBg` | `#1B2838` |
| `titleText` | `#FFFFFF` |
| `captionText` | `#7F8C8D` |
| `success` | `#2ECC71` |
| `danger` | `#E74C3C` |
| `warning` | `#F39C12` |
| `font` | `monospace` |
| `radius` | `0` (sharp corners on panels) |
| `borderWidth` | `2` |
| `borderStyle` | (solid — no stroke-dasharray) |

### Kawaii Pastel Pink

| Role | Value |
|------|-------|
| `bg` | `#FFF0F5` |
| `panel` | (use gradient `url(#panel-grad)` — white→soft pink radial) |
| `panelStroke` | `#F48FB1` |
| `border` | `#F48FB1` (softer than raw hot-pink) |
| `accent` | `#E8508B` (deep rose — for bold text, command names, highlights) |
| `accent2` | `#C9A6DE` (lavender — content line accents, list borders) |
| `text` | `#C94077` (warm rose — primary readable text) |
| `descText` | `#A888B5` (muted purple — secondary/description text) |
| `headerBg` | `#F8E8FD` (light violet — card header bands) |
| `headerText` | `#9C5BBF` (purple — card header text) |
| `titleBg` | (use gradient `url(#kawaii-title-grad)`) |
| `titleText` | `#FFFFFF` |
| `captionText` | `#C94077` |
| `bgCircle1` | `#F8E0EC` at opacity 0.35 (pink floating bg circles) |
| `bgCircle2` | `#EDE0F5` at opacity 0.3 (lavender floating bg circles) |
| `altRowBg` | `#FFF5F8` at opacity 0.6 (alternating row highlight) |
| `mint` | `#8ECFA8` (for green content accents) |
| `cream` | `#FFFDD0` |
| `blush` | `#FF69B4` at opacity 0.4 |
| `font` | `'Comic Sans MS', 'Chalkboard SE', cursive` |
| `radius` | `15-18` (all corners generously rounded) |
| `borderWidth` | `1.5-2` |
| `borderStyle` | `stroke-dasharray="10 5"` |

## SVG Defs Block

**Copy this entire `<defs>` block verbatim** into every generated SVG. Then reference characters with `<use href="#symbol-id" x="N" y="N" width="W" height="H"/>`.

All characters use `viewBox="0 0 100 150"` so they scale uniformly. Place them at any size — recommended: `width="100" height="150"` for single panel, `width="80" height="120"` for 4-panel.

```xml
<defs>
  <!-- ==================== FILTERS ==================== -->
  <filter id="drop-shadow" x="-20%" y="-20%" width="140%" height="140%">
    <feDropShadow dx="2" dy="3" stdDeviation="3" flood-color="#000000" flood-opacity="0.2"/>
  </filter>
  <filter id="soft-shadow" x="-20%" y="-20%" width="140%" height="140%">
    <feDropShadow dx="1" dy="3" stdDeviation="5" flood-color="#E75480" flood-opacity="0.18"/>
  </filter>
  <filter id="card-shadow" x="-10%" y="-10%" width="130%" height="130%">
    <feDropShadow dx="2" dy="4" stdDeviation="6" flood-color="#D4618C" flood-opacity="0.15"/>
  </filter>
  <filter id="glow" x="-30%" y="-30%" width="160%" height="160%">
    <feGaussianBlur in="SourceGraphic" stdDeviation="6" result="blur"/>
    <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>

  <!-- ==================== GRADIENTS ==================== -->
  <linearGradient id="tech-title-grad" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0%" stop-color="#1B2838"/>
    <stop offset="100%" stop-color="#2C3E50"/>
  </linearGradient>
  <linearGradient id="kawaii-title-grad" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0%" stop-color="#E8508B"/>
    <stop offset="50%" stop-color="#F7A8C4"/>
    <stop offset="100%" stop-color="#E8508B"/>
  </linearGradient>
  <!-- Kawaii background depth: radial glows behind content -->
  <radialGradient id="bg-glow-1" cx="0.2" cy="0.3" r="0.5">
    <stop offset="0%" stop-color="#FFDDE8" stop-opacity="0.7"/>
    <stop offset="100%" stop-color="#FFF0F5" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="bg-glow-2" cx="0.8" cy="0.7" r="0.45">
    <stop offset="0%" stop-color="#E8D5F0" stop-opacity="0.5"/>
    <stop offset="100%" stop-color="#FFF0F5" stop-opacity="0"/>
  </radialGradient>
  <!-- Kawaii panel: white-center → soft-pink-edge radial -->
  <radialGradient id="panel-grad" cx="0.5" cy="0.3" r="0.7">
    <stop offset="0%" stop-color="#FFFFFF"/>
    <stop offset="100%" stop-color="#FFF5F8"/>
  </radialGradient>
  <!-- Kawaii card gradients for elevated content blocks -->
  <linearGradient id="file-grad" x1="0" y1="0" x2="0.3" y2="1">
    <stop offset="0%" stop-color="#FFFFFF"/>
    <stop offset="100%" stop-color="#FFF0F3"/>
  </linearGradient>
  <linearGradient id="cmd-grad" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0%" stop-color="#FFFFFF"/>
    <stop offset="100%" stop-color="#FDF5FF"/>
  </linearGradient>
  <linearGradient id="body-blue-grad" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0%" stop-color="#5DADE2"/>
    <stop offset="100%" stop-color="#2E86C1"/>
  </linearGradient>
  <linearGradient id="body-pink-grad" x1="0.3" y1="0" x2="0.7" y2="1">
    <stop offset="0%" stop-color="#FFD1DC"/>
    <stop offset="100%" stop-color="#FFB6C1"/>
  </linearGradient>
  <linearGradient id="body-lavender-grad" x1="0.3" y1="0" x2="0.7" y2="1">
    <stop offset="0%" stop-color="#F0E6FF"/>
    <stop offset="100%" stop-color="#E6E6FA"/>
  </linearGradient>
  <linearGradient id="body-green-grad" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0%" stop-color="#A9DFBF"/>
    <stop offset="100%" stop-color="#8FBC8F"/>
  </linearGradient>
  <radialGradient id="strawberry-grad" cx="0.4" cy="0.3" r="0.6">
    <stop offset="0%" stop-color="#FF8A8A"/>
    <stop offset="100%" stop-color="#FF6B6B"/>
  </radialGradient>

  <!-- ==================== TECH CHARACTERS ==================== -->

  <!-- ROBOT EXPLAINER: main narrator for tech theme -->
  <symbol id="robot-explainer" viewBox="0 0 100 150">
    <ellipse cx="50" cy="143" rx="28" ry="5" fill="#000" opacity="0.1"/>
    <rect x="35" y="118" width="12" height="27" rx="3" fill="#2C3E50"/>
    <rect x="53" y="118" width="12" height="27" rx="3" fill="#2C3E50"/>
    <rect x="20" y="48" width="60" height="72" rx="8" fill="url(#body-blue-grad)" stroke="#2980B9" stroke-width="1"/>
    <line x1="30" y1="65" x2="70" y2="65" stroke="#FFFFFF" stroke-width="1" opacity="0.3"/>
    <line x1="30" y1="80" x2="70" y2="80" stroke="#FFFFFF" stroke-width="1" opacity="0.3"/>
    <line x1="30" y1="95" x2="70" y2="95" stroke="#FFFFFF" stroke-width="1" opacity="0.3"/>
    <circle cx="68" cy="55" r="4" fill="#2ECC71"/>
    <circle cx="68" cy="55" r="2" fill="#FFFFFF" opacity="0.5"/>
    <rect x="78" y="62" width="22" height="9" rx="4" fill="#2C3E50"/>
    <circle cx="98" cy="66" r="6" fill="#ECF0F1" stroke="#BDC3C7" stroke-width="1"/>
    <rect x="0" y="62" width="22" height="9" rx="4" fill="#2C3E50"/>
    <line x1="-8" y1="66" x2="2" y2="66" stroke="#7F8C8D" stroke-width="3" stroke-linecap="round"/>
    <circle cx="-10" cy="66" r="5" fill="none" stroke="#7F8C8D" stroke-width="2"/>
    <rect x="26" y="10" width="48" height="40" rx="6" fill="#ECF0F1" stroke="#BDC3C7" stroke-width="1"/>
    <rect x="32" y="17" width="36" height="26" rx="3" fill="#2C3E50"/>
    <circle cx="43" cy="28" r="3.5" fill="#3498DB"/>
    <circle cx="44" cy="27" r="1.5" fill="#FFFFFF" opacity="0.6"/>
    <circle cx="57" cy="28" r="3.5" fill="#3498DB"/>
    <circle cx="58" cy="27" r="1.5" fill="#FFFFFF" opacity="0.6"/>
    <path d="M 43 36 Q 50 41 57 36" stroke="#3498DB" stroke-width="1.5" fill="none"/>
    <line x1="50" y1="10" x2="50" y2="0" stroke="#7F8C8D" stroke-width="2"/>
    <circle cx="50" cy="-2" r="4" fill="#3498DB" stroke="#2980B9" stroke-width="1"/>
  </symbol>

  <!-- SERVER RACK: data/storage topics -->
  <symbol id="server-rack" viewBox="0 0 100 150">
    <ellipse cx="50" cy="143" rx="25" ry="5" fill="#000" opacity="0.1"/>
    <rect x="20" y="15" width="60" height="125" rx="4" fill="#2C3E50" stroke="#1A252F" stroke-width="1"/>
    <rect x="25" y="22" width="50" height="18" rx="2" fill="#34495E"/>
    <rect x="25" y="45" width="50" height="18" rx="2" fill="#34495E"/>
    <rect x="25" y="68" width="50" height="18" rx="2" fill="#34495E"/>
    <rect x="25" y="91" width="50" height="18" rx="2" fill="#34495E"/>
    <circle cx="32" cy="31" r="2.5" fill="#2ECC71"/><circle cx="39" cy="31" r="2.5" fill="#2ECC71"/>
    <circle cx="46" cy="31" r="2.5" fill="#F39C12"/><circle cx="32" cy="54" r="2.5" fill="#2ECC71"/>
    <circle cx="39" cy="54" r="2.5" fill="#E74C3C"/><circle cx="46" cy="54" r="2.5" fill="#2ECC71"/>
    <circle cx="32" cy="77" r="2.5" fill="#2ECC71"/><circle cx="39" cy="77" r="2.5" fill="#2ECC71"/>
    <circle cx="46" cy="77" r="2.5" fill="#2ECC71"/><circle cx="32" cy="100" r="2.5" fill="#F39C12"/>
    <circle cx="39" cy="100" r="2.5" fill="#2ECC71"/><circle cx="46" cy="100" r="2.5" fill="#2ECC71"/>
    <rect x="58" y="28" width="12" height="4" rx="1" fill="#7F8C8D" opacity="0.5"/>
    <rect x="58" y="51" width="12" height="4" rx="1" fill="#7F8C8D" opacity="0.5"/>
    <rect x="58" y="74" width="12" height="4" rx="1" fill="#7F8C8D" opacity="0.5"/>
    <rect x="58" y="97" width="12" height="4" rx="1" fill="#7F8C8D" opacity="0.5"/>
    <line x1="50" y1="15" x2="50" y2="3" stroke="#7F8C8D" stroke-width="2"/>
    <circle cx="50" cy="1" r="3" fill="#E74C3C"/>
  </symbol>

  <!-- ANTENNA BOT: network/API topics -->
  <symbol id="antenna-bot" viewBox="0 0 100 150">
    <ellipse cx="50" cy="143" rx="28" ry="5" fill="#000" opacity="0.1"/>
    <rect x="35" y="118" width="12" height="27" rx="3" fill="#6C3483"/>
    <rect x="53" y="118" width="12" height="27" rx="3" fill="#6C3483"/>
    <rect x="20" y="48" width="60" height="72" rx="8" fill="#9B59B6" stroke="#7D3C98" stroke-width="1"/>
    <line x1="30" y1="65" x2="70" y2="65" stroke="#FFFFFF" stroke-width="1" opacity="0.25"/>
    <line x1="30" y1="80" x2="70" y2="80" stroke="#FFFFFF" stroke-width="1" opacity="0.25"/>
    <circle cx="68" cy="55" r="4" fill="#2ECC71"/>
    <rect x="78" y="62" width="18" height="9" rx="4" fill="#6C3483"/>
    <rect x="4" y="62" width="18" height="9" rx="4" fill="#6C3483"/>
    <rect x="26" y="10" width="48" height="40" rx="6" fill="#ECF0F1" stroke="#BDC3C7" stroke-width="1"/>
    <rect x="32" y="17" width="36" height="26" rx="3" fill="#6C3483"/>
    <circle cx="43" cy="28" r="3.5" fill="#AF7AC5"/>
    <circle cx="57" cy="28" r="3.5" fill="#AF7AC5"/>
    <path d="M 43 36 Q 50 40 57 36" stroke="#AF7AC5" stroke-width="1.5" fill="none"/>
    <polyline points="50,10 45,0 55,-8 48,-16" stroke="#7F8C8D" stroke-width="2" fill="none" stroke-linejoin="round"/>
    <circle cx="48" cy="-18" r="4" fill="#F39C12" stroke="#E67E22" stroke-width="1"/>
    <path d="M 68,-10 Q 78,-8 82,-2" stroke="#F39C12" stroke-width="1.5" fill="none" opacity="0.6"/>
    <path d="M 72,-16 Q 85,-12 90,-4" stroke="#F39C12" stroke-width="1.5" fill="none" opacity="0.4"/>
    <path d="M 75,-22 Q 92,-16 98,-6" stroke="#F39C12" stroke-width="1.5" fill="none" opacity="0.2"/>
  </symbol>

  <!-- CLIPBOARD BOT: testing/verification topics -->
  <symbol id="clipboard-bot" viewBox="0 0 100 150">
    <ellipse cx="50" cy="143" rx="25" ry="5" fill="#000" opacity="0.1"/>
    <rect x="35" y="120" width="10" height="24" rx="3" fill="#2C3E50"/>
    <rect x="55" y="120" width="10" height="24" rx="3" fill="#2C3E50"/>
    <rect x="22" y="30" width="56" height="92" rx="4" fill="#ECF0F1" stroke="#BDC3C7" stroke-width="1.5"/>
    <rect x="36" y="24" width="28" height="12" rx="3" fill="#BDC3C7"/>
    <rect x="42" y="22" width="16" height="6" rx="2" fill="#95A5A6"/>
    <line x1="32" y1="52" x2="68" y2="52" stroke="#BDC3C7" stroke-width="1"/>
    <line x1="32" y1="64" x2="68" y2="64" stroke="#BDC3C7" stroke-width="1"/>
    <line x1="32" y1="76" x2="58" y2="76" stroke="#BDC3C7" stroke-width="1"/>
    <polyline points="35,88 42,96 58,78" stroke="#2ECC71" stroke-width="3" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
    <circle cx="43" cy="42" r="3" fill="#2C3E50"/>
    <circle cx="57" cy="42" r="3" fill="#2C3E50"/>
    <path d="M 45 48 Q 50 52 55 48" stroke="#2C3E50" stroke-width="1.2" fill="none"/>
    <rect x="72" y="65" width="18" height="8" rx="3" fill="#2C3E50"/>
    <circle cx="96" cy="60" r="8" fill="none" stroke="#3498DB" stroke-width="2"/>
    <line x1="102" y1="65" x2="110" y2="73" stroke="#3498DB" stroke-width="2.5" stroke-linecap="round"/>
  </symbol>

  <!-- HUMAN SILHOUETTE: user/end-user perspective -->
  <symbol id="human-silhouette" viewBox="0 0 100 150">
    <ellipse cx="50" cy="143" rx="22" ry="4" fill="#000" opacity="0.08"/>
    <circle cx="50" cy="25" r="18" fill="#95A5A6"/>
    <circle cx="50" cy="25" r="16" fill="#AAB7B8"/>
    <path d="M 20 145 Q 20 80 35 70 Q 50 62 65 70 Q 80 80 80 145 Z" fill="#95A5A6"/>
    <path d="M 25 145 Q 25 85 38 74 Q 50 67 62 74 Q 75 85 75 145 Z" fill="#AAB7B8"/>
  </symbol>

  <!-- ==================== KAWAII CHARACTERS ==================== -->

  <!-- PINK CAT: main narrator for kawaii theme -->
  <symbol id="pink-cat" viewBox="0 0 100 150">
    <ellipse cx="50" cy="140" rx="22" ry="5" fill="#FF69B4" opacity="0.15"/>
    <path d="M 28 45 L 22 15 L 38 35 Z" fill="url(#body-pink-grad)" stroke="#F48FB1" stroke-width="1"/>
    <path d="M 29 44 L 25 20 L 37 37 Z" fill="#F48FB1" opacity="0.5"/>
    <path d="M 72 45 L 78 15 L 62 35 Z" fill="url(#body-pink-grad)" stroke="#F48FB1" stroke-width="1"/>
    <path d="M 71 44 L 75 20 L 63 37 Z" fill="#F48FB1" opacity="0.5"/>
    <ellipse cx="50" cy="75" rx="32" ry="35" fill="url(#body-pink-grad)" stroke="#F48FB1" stroke-width="1"/>
    <ellipse cx="50" cy="120" rx="18" ry="22" fill="url(#body-pink-grad)" stroke="#F48FB1" stroke-width="1"/>
    <ellipse cx="36" cy="128" rx="10" ry="6" fill="url(#body-pink-grad)" stroke="#F48FB1" stroke-width="0.8"/>
    <ellipse cx="64" cy="128" rx="10" ry="6" fill="url(#body-pink-grad)" stroke="#F48FB1" stroke-width="0.8"/>
    <ellipse cx="38" cy="70" rx="6" ry="7" fill="#FFFFFF"/>
    <ellipse cx="38" cy="70" rx="4" ry="5.5" fill="#2C3E50"/>
    <ellipse cx="39.5" cy="68" rx="1.8" ry="2" fill="#FFFFFF"/>
    <ellipse cx="62" cy="70" rx="6" ry="7" fill="#FFFFFF"/>
    <ellipse cx="62" cy="70" rx="4" ry="5.5" fill="#2C3E50"/>
    <ellipse cx="63.5" cy="68" rx="1.8" ry="2" fill="#FFFFFF"/>
    <ellipse cx="50" cy="78" rx="2" ry="1.5" fill="#F48FB1"/>
    <path d="M 43 83 Q 46 86 50 84 Q 54 86 57 83" stroke="#C94077" stroke-width="1.2" fill="none"/>
    <ellipse cx="30" cy="80" rx="6" ry="4" fill="#F48FB1" opacity="0.35"/>
    <ellipse cx="70" cy="80" rx="6" ry="4" fill="#F48FB1" opacity="0.35"/>
    <circle cx="72" cy="38" r="5" fill="#E8508B"/>
    <path d="M 66 34 L 72 38 L 66 42" fill="#E8508B"/>
    <path d="M 78 34 L 72 38 L 78 42" fill="#E8508B"/>
    <path d="M 82 80 Q 90 70 92 85 Q 88 95 82 90" stroke="#FFB6C1" stroke-width="2" fill="none"/>
  </symbol>

  <!-- POTATO WITH GLASSES: data/storage topics kawaii -->
  <symbol id="potato-glasses" viewBox="0 0 100 150">
    <ellipse cx="50" cy="140" rx="22" ry="5" fill="#8B4513" opacity="0.1"/>
    <ellipse cx="50" cy="85" rx="34" ry="52" fill="#DEB887" stroke="#C4A265" stroke-width="1"/>
    <ellipse cx="50" cy="85" rx="30" ry="48" fill="#E8CFA0" opacity="0.4"/>
    <line x1="50" y1="30" x2="50" y2="14" stroke="#6B8E23" stroke-width="2.5"/>
    <ellipse cx="43" cy="12" rx="7" ry="4" fill="#98FB98" transform="rotate(-30 43 12)"/>
    <ellipse cx="57" cy="12" rx="7" ry="4" fill="#98FB98" transform="rotate(30 57 12)"/>
    <circle cx="38" cy="72" r="9" fill="none" stroke="#8B4513" stroke-width="2.5"/>
    <circle cx="62" cy="72" r="9" fill="none" stroke="#8B4513" stroke-width="2.5"/>
    <line x1="47" y1="72" x2="53" y2="72" stroke="#8B4513" stroke-width="2.5"/>
    <line x1="29" y1="72" x2="22" y2="69" stroke="#8B4513" stroke-width="2"/>
    <line x1="71" y1="72" x2="78" y2="69" stroke="#8B4513" stroke-width="2"/>
    <circle cx="38" cy="72" r="3" fill="#5D4037"/>
    <circle cx="39" cy="71" r="1" fill="#FFFFFF" opacity="0.7"/>
    <circle cx="62" cy="72" r="3" fill="#5D4037"/>
    <circle cx="63" cy="71" r="1" fill="#FFFFFF" opacity="0.7"/>
    <path d="M 44 90 Q 50 95 56 90" stroke="#8B4513" stroke-width="1.5" fill="none"/>
    <ellipse cx="30" cy="82" rx="5" ry="3.5" fill="#E8967D" opacity="0.4"/>
    <ellipse cx="70" cy="82" rx="5" ry="3.5" fill="#E8967D" opacity="0.4"/>
    <ellipse cx="32" cy="120" rx="12" ry="8" fill="#DEB887" stroke="#C4A265" stroke-width="0.8"/>
    <ellipse cx="68" cy="120" rx="12" ry="8" fill="#DEB887" stroke="#C4A265" stroke-width="0.8"/>
  </symbol>

  <!-- BUNNY WITH ENVELOPE: network/API topics kawaii -->
  <symbol id="bunny-envelope" viewBox="0 0 100 150">
    <ellipse cx="50" cy="142" rx="20" ry="5" fill="#E6E6FA" opacity="0.2"/>
    <ellipse cx="36" cy="18" rx="8" ry="22" fill="url(#body-lavender-grad)" stroke="#D8BFD8" stroke-width="1"/>
    <ellipse cx="36" cy="18" rx="5" ry="18" fill="#FFB6C1" opacity="0.4"/>
    <ellipse cx="64" cy="18" rx="8" ry="22" fill="url(#body-lavender-grad)" stroke="#D8BFD8" stroke-width="1"/>
    <ellipse cx="64" cy="18" rx="5" ry="18" fill="#FFB6C1" opacity="0.4"/>
    <ellipse cx="50" cy="72" rx="30" ry="35" fill="url(#body-lavender-grad)" stroke="#D8BFD8" stroke-width="1"/>
    <ellipse cx="50" cy="118" rx="16" ry="20" fill="url(#body-lavender-grad)" stroke="#D8BFD8" stroke-width="1"/>
    <ellipse cx="37" cy="126" rx="9" ry="5.5" fill="url(#body-lavender-grad)" stroke="#D8BFD8" stroke-width="0.8"/>
    <ellipse cx="63" cy="126" rx="9" ry="5.5" fill="url(#body-lavender-grad)" stroke="#D8BFD8" stroke-width="0.8"/>
    <ellipse cx="40" cy="65" rx="5" ry="6" fill="#FFFFFF"/>
    <ellipse cx="40" cy="65" rx="3.5" ry="5" fill="#2C3E50"/>
    <ellipse cx="41" cy="63.5" rx="1.5" ry="1.8" fill="#FFFFFF"/>
    <ellipse cx="60" cy="65" rx="5" ry="6" fill="#FFFFFF"/>
    <ellipse cx="60" cy="65" rx="3.5" ry="5" fill="#2C3E50"/>
    <ellipse cx="61" cy="63.5" rx="1.5" ry="1.8" fill="#FFFFFF"/>
    <ellipse cx="50" cy="74" rx="2.5" ry="2" fill="#FFB6C1"/>
    <path d="M 44 80 Q 50 84 56 80" stroke="#D1568A" stroke-width="1.2" fill="none"/>
    <ellipse cx="32" cy="76" rx="5" ry="3.5" fill="#FFB6C1" opacity="0.35"/>
    <ellipse cx="68" cy="76" rx="5" ry="3.5" fill="#FFB6C1" opacity="0.35"/>
    <g transform="translate(72, 88) rotate(10)">
      <rect x="0" y="0" width="24" height="16" rx="2" fill="#FFE4E1" stroke="#FF69B4" stroke-width="1"/>
      <path d="M 0 0 L 12 9 L 24 0" fill="none" stroke="#FF69B4" stroke-width="1"/>
      <circle cx="20" cy="12" r="3" fill="#FF69B4" opacity="0.3"/>
    </g>
  </symbol>

  <!-- BROCCOLI WITH MAGNIFYING GLASS: testing topics kawaii -->
  <symbol id="broccoli-magnifier" viewBox="0 0 100 150">
    <ellipse cx="50" cy="143" rx="18" ry="4" fill="#228B22" opacity="0.1"/>
    <rect x="38" y="80" width="24" height="60" rx="5" fill="url(#body-green-grad)" stroke="#6B8E23" stroke-width="1"/>
    <ellipse cx="38" cy="135" rx="10" ry="6" fill="url(#body-green-grad)" stroke="#6B8E23" stroke-width="0.8"/>
    <ellipse cx="62" cy="135" rx="10" ry="6" fill="url(#body-green-grad)" stroke="#6B8E23" stroke-width="0.8"/>
    <circle cx="50" cy="42" r="22" fill="#228B22"/>
    <circle cx="36" cy="32" r="14" fill="#2E7D32"/>
    <circle cx="64" cy="32" r="14" fill="#2E7D32"/>
    <circle cx="50" cy="24" r="12" fill="#33A033"/>
    <circle cx="40" cy="48" r="10" fill="#2E7D32"/>
    <circle cx="60" cy="48" r="10" fill="#2E7D32"/>
    <circle cx="43" cy="95" r="2.5" fill="#5D4037"/>
    <circle cx="44" cy="94" r="0.8" fill="#FFFFFF" opacity="0.7"/>
    <circle cx="57" cy="95" r="2.5" fill="#5D4037"/>
    <circle cx="58" cy="94" r="0.8" fill="#FFFFFF" opacity="0.7"/>
    <path d="M 46 103 Q 50 106 54 103" stroke="#5D4037" stroke-width="1.2" fill="none"/>
    <ellipse cx="38" cy="100" rx="4" ry="2.5" fill="#E8967D" opacity="0.35"/>
    <ellipse cx="62" cy="100" rx="4" ry="2.5" fill="#E8967D" opacity="0.35"/>
    <g transform="translate(68, 95) rotate(25)">
      <circle cx="0" cy="0" r="10" fill="none" stroke="#FF69B4" stroke-width="2.5"/>
      <circle cx="0" cy="0" r="7" fill="#FFE4E1" opacity="0.3"/>
      <line x1="7" y1="7" x2="18" y2="18" stroke="#FF69B4" stroke-width="3" stroke-linecap="round"/>
    </g>
  </symbol>

  <!-- STRAWBERRY: user/end-user perspective kawaii -->
  <symbol id="strawberry" viewBox="0 0 100 150">
    <ellipse cx="50" cy="142" rx="18" ry="4" fill="#FF6B6B" opacity="0.1"/>
    <path d="M 50 8 L 40 5 Q 35 2 38 -2 Q 42 -5 46 -2 L 50 2 L 54 -2 Q 58 -5 62 -2 Q 65 2 60 5 Z" fill="#98FB98" stroke="#6B8E23" stroke-width="0.8"/>
    <path d="M 50 8 Q 15 55 22 95 Q 30 130 50 140 Q 70 130 78 95 Q 85 55 50 8 Z" fill="url(#strawberry-grad)" stroke="#E74C3C" stroke-width="1"/>
    <ellipse cx="38" cy="50" rx="2" ry="3" fill="#FFD700" opacity="0.6" transform="rotate(-10 38 50)"/>
    <ellipse cx="60" cy="48" rx="2" ry="3" fill="#FFD700" opacity="0.6" transform="rotate(10 60 48)"/>
    <ellipse cx="50" cy="65" rx="2" ry="3" fill="#FFD700" opacity="0.6"/>
    <ellipse cx="35" cy="75" rx="2" ry="3" fill="#FFD700" opacity="0.6" transform="rotate(-15 35 75)"/>
    <ellipse cx="65" cy="73" rx="2" ry="3" fill="#FFD700" opacity="0.6" transform="rotate(15 65 73)"/>
    <ellipse cx="42" cy="92" rx="2" ry="3" fill="#FFD700" opacity="0.6" transform="rotate(-5 42 92)"/>
    <ellipse cx="58" cy="90" rx="2" ry="3" fill="#FFD700" opacity="0.6" transform="rotate(5 58 90)"/>
    <ellipse cx="50" cy="108" rx="2" ry="3" fill="#FFD700" opacity="0.6"/>
    <path d="M 36 68 Q 40 62 44 68" stroke="#2C3E50" stroke-width="2" fill="none" stroke-linecap="round"/>
    <path d="M 56 68 Q 60 62 64 68" stroke="#2C3E50" stroke-width="2" fill="none" stroke-linecap="round"/>
    <ellipse cx="50" cy="82" rx="5" ry="4" fill="#FF4444" opacity="0.7"/>
    <path d="M 45 80 Q 50 86 55 80" stroke="#2C3E50" stroke-width="1" fill="none"/>
    <ellipse cx="33" cy="73" rx="5" ry="3.5" fill="#FF69B4" opacity="0.3"/>
    <ellipse cx="67" cy="73" rx="5" ry="3.5" fill="#FF69B4" opacity="0.3"/>
  </symbol>

  <!-- ==================== DECORATIONS ==================== -->

  <!-- Detailed gear (8-tooth) for tech theme -->
  <symbol id="gear" viewBox="0 0 40 40">
    <path d="M 17 2 L 23 2 L 24 7 L 28 8 L 32 4 L 36 8 L 32 12 L 33 16 L 38 17 L 38 23 L 33 24 L 32 28 L 36 32 L 32 36 L 28 32 L 24 33 L 23 38 L 17 38 L 16 33 L 12 32 L 8 36 L 4 32 L 8 28 L 7 24 L 2 23 L 2 17 L 7 16 L 8 12 L 4 8 L 8 4 L 12 8 L 16 7 Z" fill="#3498DB" opacity="0.2" stroke="#3498DB" stroke-width="0.5" opacity="0.3"/>
    <circle cx="20" cy="20" r="7" fill="none" stroke="#3498DB" stroke-width="1" opacity="0.3"/>
  </symbol>

  <!-- Circuit trace pattern for tech theme -->
  <symbol id="circuit" viewBox="0 0 60 30">
    <path d="M 0 15 L 15 15 L 20 5 L 35 5 L 40 15 L 60 15" stroke="#3498DB" stroke-width="1.2" fill="none" opacity="0.15"/>
    <circle cx="20" cy="5" r="2" fill="#3498DB" opacity="0.2"/>
    <circle cx="40" cy="15" r="2" fill="#3498DB" opacity="0.2"/>
  </symbol>

  <!-- 4-point sparkle for kawaii theme -->
  <symbol id="sparkle" viewBox="0 0 20 20">
    <path d="M 10 0 Q 10.5 8 20 10 Q 10.5 12 10 20 Q 9.5 12 0 10 Q 9.5 8 10 0 Z" fill="#F7A8C4"/>
  </symbol>

  <!-- Small heart for kawaii theme -->
  <symbol id="heart" viewBox="0 0 20 20">
    <path d="M 10 18 Q 0 10 2 5 Q 4 0 10 5 Q 16 0 18 5 Q 20 10 10 18 Z" fill="#E8508B" opacity="0.55"/>
  </symbol>

  <!-- Star decoration for kawaii backgrounds -->
  <symbol id="star" viewBox="0 0 24 24">
    <path d="M 12 0 L 14.5 8.5 L 24 9.5 L 17 15.5 L 19 24 L 12 19.5 L 5 24 L 7 15.5 L 0 9.5 L 9.5 8.5 Z" fill="#F7C6D6" opacity="0.4"/>
  </symbol>

</defs>
```

## Character Selection Guide

| Topic | Tech Character | Kawaii Character |
|-------|---------------|-----------------|
| General / overview | `#robot-explainer` | `#pink-cat` |
| Data, storage, files | `#server-rack` | `#potato-glasses` |
| Network, API, requests | `#antenna-bot` | `#bunny-envelope` |
| Testing, verification | `#clipboard-bot` | `#broccoli-magnifier` |
| User, end-user | `#human-silhouette` | `#strawberry` |

Use 1-2 characters per panel. In 4-panel comics, the main narrator appears in panels 1 and 4; supporting characters appear in panels 2-3.

## Layout Grid

### Single Panel (800 x 600)

```
┌──────────────────────────────────────────────────┐
│ TITLE BAR  y=0..60                                │
├──────────────────────────────────────────────────┤
│ PANEL  x=20 y=70 w=760 h=470                     │
│                                                    │
│  ┌─CHAR─┐  ┌──────BUBBLE ZONE──────────────┐     │
│  │ zone  │  │ x=220..750  y=80..230         │     │
│  │ x=40  │  │ (top bubble)                  │     │
│  │ ..200 │  └───────────────────────────────┘     │
│  │ y=100 │                                        │
│  │ ..460 │  ┌──────CONTENT ZONE─────────────┐     │
│  │       │  │ x=220..750  y=240..500        │     │
│  │       │  │ (diagram, second char, etc.)  │     │
│  └───────┘  └───────────────────────────────┘     │
│                                                    │
├──────────────────────────────────────────────────┤
│ CAPTION BAR  y=545..600                           │
└──────────────────────────────────────────────────┘
```

**Decoration zones** (kawaii: 12+ decorations, tech: 6+):
- Corners: (30,80), (760,80), (30,530), (760,530) — 4 main positions
- Left gutter: x=25..40, scattered along y
- Right gutter: x=755..775, scattered along y
- Near content: scatter hearts and sparkles adjacent to content blocks
- Background layer: large faint stars behind panels (kawaii only)

### 4-Panel (800 x 1200)

```
┌──────────────────────────────────────────────────┐
│ TITLE BAR  y=0..60                                │
├────────────────────┬─────────────────────────────┤
│ PANEL 1            │ PANEL 2                      │
│ x=20 y=70          │ x=410 y=70                   │
│ w=370 h=520        │ w=370 h=520                   │
│                    │                               │
│  char: x=30..140   │  char: x=30..140              │
│  y=250..490 rel.   │  y=250..490 rel.              │
│                    │                               │
│  bubble: x=20..350 │  bubble: x=20..350            │
│  y=20..230 rel.    │  y=20..230 rel.               │
├────────────────────┼─────────────────────────────┤
│ PANEL 3            │ PANEL 4                      │
│ x=20 y=610         │ x=410 y=610                   │
│ w=370 h=520        │ w=370 h=520                   │
│                    │                               │
│  (same zones)      │  (same zones)                 │
├────────────────────┴─────────────────────────────┤
│ CAPTION BAR  y=1145..1200                         │
└──────────────────────────────────────────────────┘
```

**Panel-relative coordinates** — add panel's x,y to get absolute position. For example, Panel 2 character at relative (50, 300) → absolute (460, 370).

## Visual Depth Techniques

These techniques add visual richness and depth. **Apply all of them for kawaii theme. Apply the tech-marked ones for technical theme.**

### Background Depth (kawaii)

Layer these behind all content, immediately after the base `<rect>`:

```xml
<!-- Base fill -->
<rect width="800" height="600" fill="#FFF0F5" rx="15"/>
<!-- Radial glows for color depth -->
<rect width="800" height="600" fill="url(#bg-glow-1)" rx="15"/>
<rect width="800" height="600" fill="url(#bg-glow-2)" rx="15"/>

<!-- Floating soft circles (3-5, behind everything) -->
<circle cx="680" cy="480" r="80" fill="#F8E0EC" opacity="0.35"/>
<circle cx="100" cy="500" r="55" fill="#EDE0F5" opacity="0.3"/>
<circle cx="720" cy="120" r="45" fill="#F8E0EC" opacity="0.25"/>

<!-- Background faint stars (2-3 large, behind panels) -->
<use href="#star" x="690" y="440" width="50" height="50"/>
<use href="#star" x="55" y="460" width="35" height="35"/>
```

### Panel Inner Glow (kawaii)

After the main panel `<rect>`, add a slightly inset rectangle for a soft inner border glow:

```xml
<rect x="20" y="70" width="760" height="470" fill="url(#panel-grad)" stroke="#F48FB1"
      stroke-width="2" rx="18" stroke-dasharray="10 5" filter="url(#card-shadow)"/>
<!-- Inner glow border -->
<rect x="25" y="75" width="750" height="460" rx="15" fill="none"
      stroke="#FFD6E5" stroke-width="3" opacity="0.4"/>
```

### Card Elevation (kawaii)

Content blocks (file illustrations, command lists, diagrams) should appear "lifted" with:

1. **Gradient fills** — use `url(#file-grad)`, `url(#cmd-grad)` instead of flat `#FFFFFF`
2. **Card shadow filter** — apply `filter="url(#card-shadow)"` to the content group
3. **Header bands** — add a soft-colored header `<rect>` inside cards with `#F8E8FD` fill
4. **Alternating row backgrounds** — for lists, add `<rect>` fills at `#FFF5F8` opacity 0.6 on odd rows
5. **Cute faces on objects** — add tiny dot eyes (r=2.5) and a smile path to file/document illustrations
6. **Slight rotation** — apply `transform="rotate(-2)"` or similar to cards for a playful tilt

### Title Bar Polish (kawaii)

```xml
<!-- Highlight line -->
<line x1="250" y1="8" x2="550" y2="8" stroke="#FFFFFF" stroke-width="1" opacity="0.25" stroke-linecap="round"/>
<!-- Decorative hearts flanking title text -->
<use href="#heart" x="248" y="18" width="18" height="18"/>
<use href="#heart" x="534" y="18" width="18" height="18"/>
```

### Decoration Sizing (both themes)

- **Corner sparkles:** 18-22px, apply `filter="url(#glow)"` to 2 of the 4 corner sparkles
- **Scattered sparkles:** 12-15px, no filter
- **Hearts:** 13-18px, scattered in gutters and near content
- **Stars:** 18-50px, use in background layer and scattered areas, larger = more transparent
- **Minimum total:** 12+ decoration elements for kawaii, 6+ for tech

### Speech Bubble Enhancement (kawaii)

Use cloud-style bubbles instead of plain rectangles:

```xml
<!-- Outer cloud shape (dashed stroke) -->
<ellipse cx="240" cy="32" rx="242" ry="38" fill="#FFF5F8" stroke="#F48FB1"
         stroke-width="2" stroke-dasharray="7 4"/>
<!-- Inner cloud layers for soft depth -->
<ellipse cx="140" cy="28" rx="90" ry="30" fill="#FFEFF5"/>
<ellipse cx="340" cy="28" rx="90" ry="30" fill="#FFEFF5"/>
<ellipse cx="240" cy="22" rx="190" ry="26" fill="#FFF5F8"/>
<!-- Heart pointer (instead of triangle) -->
<path d="M 12 18 Q 1 11 3 5 Q 6 -1 12 5 Q 18 -1 21 5 Q 23 11 12 18 Z" fill="#E8508B" opacity="0.6"/>
```

## Text Containment Rules

**CRITICAL: All text must fit inside its container. Use these formulas.**

### Bubble Sizing

```
Given:
  text       = the speech bubble content string
  words      = word count of text (MAXIMUM 15 per bubble)
  chars      = character count of text
  font_size  = 16 (default for bubbles)
  max_width  = 480 (single panel) or 300 (4-panel)
  padding    = 15

Compute:
  char_width   = font_size * 0.6 (monospace) or font_size * 0.52 (cursive)
  line_width   = chars * char_width
  lines        = ceil(line_width / max_width)  (minimum 1)
  bubble_w     = min(line_width, max_width) + (padding * 2)
  bubble_h     = (lines * font_size * 1.4) + (padding * 2)

Text placement inside bubble:
  text_anchor  = "middle"
  text_x       = bubble_x + bubble_w / 2
  first_line_y = bubble_y + padding + font_size
  next_line_y  = previous_y + (font_size * 1.4)
```

### Hard Rules

- **NEVER** place `<text>` with `y` outside its container `<rect>`'s y..y+height range
- **NEVER** use `font-size` below 13px
- **MAXIMUM** 15 words per speech bubble. If more, split into two bubbles
- **ALWAYS** use `text-anchor="middle"` for bubble text and center it horizontally
- For multi-line text: use separate `<text>` elements or `<tspan>` with explicit `dy`

## Process

### Step 1: Parse Arguments

Extract from `${ARGUMENTS}`:
- `--kawaii` flag → kawaii theme; otherwise technical
- `--panels N` → N panels (1 or 4); default 1
- Remaining text → the topic (if empty, auto-detect)

### Step 2: Analyze the Codebase

- Use Glob to find `*.py` files, config files, docs
- Read `CLAUDE.md`, `README.md`, `pyproject.toml` for project context
- Read `src/` structure and key source files
- Build understanding of: purpose, architecture, workflows, audience

### Step 3: Choose Topic and Write Script

**If topic specified:** use it. **Otherwise pick from:** project overview, architecture, a key workflow, or a standout feature.

Write script for each panel:
- Which character(s) from the Character Selection Guide
- Speech bubble text (SHORT — under 15 words, plain language, no jargon)
- Scene description (what's being shown)
- Caption if needed

**4-panel narrative arc:**
1. **Setup** — introduce the problem or question
2. **Explain** — show the core concept
3. **Detail** — dive into how it works
4. **Conclusion** — the takeaway or punchline

### Step 4: Assemble the SVG

1. Open `<svg>` with correct dimensions and viewBox
2. **Copy the entire `<defs>` block from this skill verbatim**
3. **Build background layers** (see Visual Depth Techniques):
   - Base `<rect>` with theme bg color
   - Kawaii: add `bg-glow-1` and `bg-glow-2` overlay rects, floating soft circles, background stars
   - Tech: solid bg is sufficient
4. **Add title bar** with gradient background (`url(#tech-title-grad)` or `url(#kawaii-title-grad)`)
   - Kawaii: add highlight line and flanking hearts (see Title Bar Polish)
5. **Add panel** `<rect>`(s) with theme border style
   - Kawaii: use `fill="url(#panel-grad)"`, `filter="url(#card-shadow)"`, dashed stroke, then add inner glow rect
   - Tech: solid white fill, no filter
6. **Place characters with `<use>`**:
   ```xml
   <use href="#robot-explainer" x="60" y="150" width="100" height="150" filter="url(#drop-shadow)"/>
   ```
7. **Build speech bubbles**:
   - Tech: rectangle with pointer triangle, sized by Text Containment formulas
   - Kawaii: cloud-style ellipse layers with heart pointer (see Speech Bubble Enhancement)
8. Add text inside bubbles using computed coordinates
9. **Build content blocks** (diagrams, file illustrations, command lists):
   - Kawaii: use gradient fills (`url(#file-grad)`, `url(#cmd-grad)`), `filter="url(#card-shadow)"`, header bands, alternating row backgrounds, cute faces, slight rotation
   - Tech: clean rectangles with accent borders
10. **Scatter decorations** — follow Decoration Sizing guidelines:
    - Tech: 6+ `<use href="#gear">` and `<use href="#circuit">` elements
    - Kawaii: 12+ total: `<use href="#sparkle">` (corner 18-22px with glow, scattered 12-15px), `<use href="#heart">` (13-18px), `<use href="#star">` (18-50px in background)
11. Add caption text at bottom

### Step 5: Self-Review Pass

**Before saving, verify every element. This is mandatory.**

Check each `<text>` element:
1. Find its `y` coordinate and the `y` + `height` of its containing `<rect>`
2. Verify: `rect_y + padding < text_y < rect_y + rect_height - 5`
3. If not: adjust `text_y` or increase `rect_height`

Check each `<use>` element:
1. Verify the `href` value matches a `<symbol id="...">` in `<defs>`
2. Verify its `x + width` does not exceed the panel's right edge
3. Verify its `y + height` does not exceed the panel's bottom edge

Count decorations:
- Tech theme: at least 6 gear or circuit elements → if fewer, add more
- Kawaii theme: at least 12 total (sparkle + heart + star) → if fewer, add more

Check visual depth (kawaii only):
- Background has radial glow overlays (`bg-glow-1`, `bg-glow-2`) → if missing, add them
- At least 3 floating background circles → if fewer, add more
- Panel uses `url(#panel-grad)` fill and `filter="url(#card-shadow)"` → if missing, add
- Panel has inner glow rect → if missing, add
- Content blocks use gradient fills → if using flat `#FFFFFF`, switch to `url(#file-grad)` or `url(#cmd-grad)`
- At least 2 corner sparkles use `filter="url(#glow)"` → if missing, add

Check font sizes:
- No `font-size` value below 13 anywhere in the SVG

**Fix any issues found before proceeding to save.**

### Step 6: Save and Report

```bash
mkdir -p docs/comics
```

Save to `docs/comics/{slug}-{theme}-{N}p.svg`:
- `{slug}` = topic in kebab-case
- `{theme}` = `tech` or `kawaii`
- `{N}` = panel count

Report:
```
═══════════════════════════════════════════════════
              COMIC GENERATED
═══════════════════════════════════════════════════

Theme: {Technical Reference | Kawaii Pastel Pink}
Panels: {1 | 4}
Topic: {topic description}
Characters: {list of characters used}

Saved to: docs/comics/{filename}.svg

Open in any browser to view.
═══════════════════════════════════════════════════
```

## Quality Thresholds

| Check | Minimum |
|-------|---------|
| Decorations (tech) | 6 elements (gears + circuits) |
| Decorations (kawaii) | 12 elements (sparkles + hearts + stars) |
| Font size | 13px |
| Bubble padding | 15px all sides |
| Character shadow | 1 `<ellipse>` per character |
| Gradient usage | Title bar must use gradient; kawaii panel must use `url(#panel-grad)` |
| Card elevation (kawaii) | Content blocks use gradient fills + `filter="url(#card-shadow)"` |
| Background depth (kawaii) | `bg-glow-1` + `bg-glow-2` overlays + 3 floating circles + 2 background stars |
| Inner panel glow (kawaii) | Inset `<rect>` with `stroke="#FFD6E5"` opacity 0.4 |
| Corner sparkle glow (kawaii) | At least 2 of 4 corner sparkles have `filter="url(#glow)"` |
| `<defs>` block | Must be present and contain all symbols, filters, and gradients |

## Examples

```
/comic                              # Single tech panel about the project
/comic --kawaii                      # Single kawaii panel about the project
/comic --panels 4                   # 4-panel tech comic, auto topic
/comic --kawaii --panels 4           # 4-panel kawaii comic, auto topic
/comic "how tests work"             # Single tech panel about testing
/comic --kawaii "project setup"     # Single kawaii panel about setup
/comic --kawaii --panels 4 "CI/CD"  # 4-panel kawaii comic about CI/CD
```
