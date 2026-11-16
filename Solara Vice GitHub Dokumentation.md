# 🌴 SOLARA VICE // Neon Harbor Vertical Slice

[![Godot Engine](https://img.shields.io/badge/Godot-4.3%2B%20(Forward%2B)-478cbf?logo=godot-engine&logoColor=white)](https://godotengine.org/)
[![Language](https://img.shields.io/badge/GDScript-2.0%20(Strict%20Typed)-blue)](#system-architektur--topologische-schichten)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux-lightgrey)](#schnellstart-one-click-setup--start)
[![Dependencies](https://img.shields.io/badge/External%20Assets-Zero--Dependency%20Ready-brightgreen)](#modding-guide-eigene-3d-modelle-einbinden-asset-bridge)
[![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions%20%2B%20Smoke--Test-orange)](#qualit%C3%A4tssicherung-smoke-test--ci-cd-pipeline)

**Solara Vice** ist ein modular aufgebautes Open-World-Action-Driving-Spiel in **Godot 4 (Forward+)**. Das Projekt vereint eine prozedural generierte Synthwave-Metropole (*Neon Harbor*) inklusive dynamischem 24-Stunden-Tag-/Nacht-Zyklus und Wettersystem mit Arcade-Fahrzeugphysik, Wasser- und Luftfahrzeugen, einem nahtlosen Dual-Protagonisten-Wechsel (*Elena & Marcus Vance*), einem 5-Sterne-Polizeifahndungssystem, unterirdischen U-Bahn-Fluchttunneln sowie einem mehrstufigen Zentralbank-Raubfinale.

Dank **prozeduraler 3D-Geometrie** und einer **16-Bit-PCM-Echtzeit-Klangsynthese** (`ProceduralSFXSynth`) kommt das Projekt **ohne externe Asset-Abhängigkeiten** aus und lässt sich über ein einziges PowerShell-Skript (`Start-SolaraVice.ps1`) vollautomatisch einrichten, testen, kompilieren und starten. Über die integrierte **3D-Asset-Bridge (`AssetPackLoader`)** können sämtliche Platzhalter-Modelle jederzeit automatisch gegen detaillierte `.glb`- oder `.gltf`-Modelle aus Blender ausgetauscht werden.

---

## 📋 Inhaltsverzeichnis

1. [Kern-Features im Überblick](#-kern-features-im-%C3%BCberblick)
2. [Schnellstart (One-Click-Setup & Start)](#-schnellstart-one-click-setup--start)
3. [Steuerungs- & Hotkey-Referenz](#-steuerungs--hotkey-referenz)
4. [System-Architektur & Topologische Schichten](#-system-architektur--topologische-schichten)
5. [Open-World-Aktivitäten, Endgame & 100%-Fortschritt](#-open-world-aktivit%C3%A4ten-endgame--100-fortschritt)
6. [Modding-Guide: Eigene 3D-Modelle einbinden (Asset-Bridge)](#-modding-guide-eigene-3d-modelle-einbinden-asset-bridge)
7. [Qualitätssicherung, Smoke-Test & CI/CD-Pipeline](#-qualit%C3%A4tssicherung-smoke-test--cicd-pipeline)
8. [Verzeichnisstruktur](#-verzeichnisstruktur)

---

## ✨ Kern-Features im Überblick

### 👥 Dual-Protagonisten & Taktische Leibgarde
* **Nahtloser Charakterwechsel (`F5`):** Wechsle jederzeit zwischen **Elena Vance** (Safehouse Plaza) und **Marcus Vance** (Ostviertel-Tuningwerkstatt).
* **Rekrutierbare 4-Sitzer-Leibgarde (`TurfWarCommander`):** Rekrutiere bis zu $3$ bewaffnete Syndikat-Leibwächter (`B`), die in Formation folgen (`G`), automatisch mit dir in Fahrzeuge einsteigen und während der Fahrt eigenständig feindliche Ziele unter Feuer nehmen.

### 🏎️ Land-, See- & Luft-Fuhrpark (`ArcadeVehicle`-Hierarchie)
* **Straßenfahrzeuge:** Sportcoupé (*Apex GT*), Allrad-Geländewagen (*Titan 4x4*), Kompaktwagen (*Metro Compact*), Polizeikreuzer, gepanzerter *SWAT Enforcer* sowie sprengbare *Solara-Geldtransporter* (`ArmoredCashTruck`).
* **Seefahrt & Hafen-Marina (`SpeedboatController`):** Steuerbare Schnellboote (*Solara Stinger 380* & *N.H.P.D. Harbor Interceptor*) mit physikalischem 4-Punkt-Archimedes-Auftrieb, Echtzeit-Gerstner-Wellen auf $Y = -0.85\text{ m}$ und beweglichen Außenbordmotoren.
* **Luftfahrt & Dach-Helipad (`SkyhawkHelicopter`):** Steuerbarer Kampfhelikopter (*Valkyrie Tactical Gunship*) mit Kreisel-Stabilisator, Hover-Lock (`H`), schwenkbarem Suchscheinwerfer (`L`), doppelläufigen Bordkanonen, Avionik-HUD (Künstlicher Horizont, Steigrate, Rotor-RPM) und Express-Aufzug zum Safehouse-Dach.

### 🔫 5-Waffen-Arsenal & Präzisions-Optik
* **Waffen-Slots (`1`–`5`):** *Solara 9mm Pistole*, *Viper SMG* (inklusive Fahrzeug-Drive-By), *Breacher 12G Schrotflinte*, physische *M67 Splittergranate* (`FragGrenade`) und das *Solara .50 Precision* Scharfschützengewehr.
* **Mil-Dot-Scharfschützen-Visier (`SniperScopeController`):** 3-stufiger Optik-Zoom ($2.5\times$, $6.0\times$, $12.0\times$ per Mausrad oder `V`), Laser-Entfernungsmesser und Fokus-Zeitlupe (`Shift` senkt `Engine.time_scale` auf $0.45\times$).

### 🚨 5-Sterne-Polizeifahndung & Unterirdisches U-Bahn-Fluchtnetzwerk
* **Dynamische Eskalation (`WantedManager`):** Streifenwagen ($1\star$–$2\star$), Helikopter-Luftüberwachung und Nagelbänder (`PoliceSpikeStrip`, $3\star$) bis hin zu gepanzerten SWAT-Straßensperren (`PoliceRoadblock` & `SWATEnforcerAI`, $4\star$–$5\star$).
* **U-Bahn- & Fluchttunnel-Netzwerk (`UndergroundMetroNetwork`):** Befahrbares Röhrensystem in $28\text{ Metern}$ Tiefe ($Y = -28.0\text{ m}$) mit $4$ oberirdischen Einfahrtsrampen, $3.5\times$ schnellerem Fahndungsabbau im Radar-Schatten gegen Helikopter, zentralem Transponder-Scrambler und $110\text{ km/h}$ schnellen Express-U-Bahnen.

### 🏦 Story-Kampagne & Das Zentralbank-Finale
* **Story-Aufträge:** *Mission 1 (Kurierfahrt unter Strom)*, *Mission 2 (Heißes Pflaster am Hafen)* und das mehrstufige Finale *Mission 3 (Der Solara-Zentralbank-Coup)* (`BankHeistFinale`) mit Schalterhallen-Erstürmung, thermischem Tresorbohrer, 5-Sterne-SWAT-Belagerung, $\$75.000$ Goldbeute und freier Fluchtwahl per Helikopter oder Schnellboot.

---

## 🚀 Schnellstart (One-Click-Setup & Start)

Das Projekt wird über den All-in-One PowerShell-Release-Manager **`Start-SolaraVice.ps1`** verwaltet. Du benötigst vorab **keine** manuelle Godot-Installation: Findet das Skript keine Engine im Systempfad, lädt es automatisch die offizielle portable **Godot 4.3 Stable (Win64)** in das lokale Unterverzeichnis `.engine\` herunter.

### 1. Standard-Start unter Windows (Einrichten, Prüfen, Bauen & Spielen)

Lege `Start-SolaraVice.ps1` in einem leeren Ordner ab (z. B. `C:\Spiele\SolaraVice`), öffne dort ein PowerShell-Terminal und führe folgenden Befehl aus:

```powershell
powershell -ExecutionPolicy Bypass -File .\Start-SolaraVice.ps1
```

**Was dieser Befehl vollautomatisch ausführt:**
1. **Engine-Auflösung:** Prüft Godot 4 lokal oder lädt die portable Engine nach `.engine\` herunter.
2. **UTF-8-Ohne-BOM Installation:** Erzeugt alle $19$ Projektordner, `project.godot`, `default_bus_layout.tres`, `export_presets.cfg`, Shader und alle **57 Pflicht- und Optionsmodule** in topologischer Reihenfolge.
3. **Klassen-Cache & Qualitätssicherung:** Führt `--import` sowie den automatisierten Headless-Diagnoselauf (`smoke_test_runner.gd`) aus.
4. **Szenen-Assembler:** Baut `res://scenes/world/neon_harbor_slice.tscn` und `res://scenes/main.tscn` über `generate_neon_harbor_editor.gd`.
5. **Direktstart:** Öffnet unmittelbar das spielbare Fenster von *Solara Vice*.

### 2. Kommandozeilen-Parameter von `Start-SolaraVice.ps1`

| Parameter | Typ | Standard | Beschreibung |
| :--- | :--- | :--- | :--- |
| `-GodotBin` | `String` | `""` | Optionaler Pfad zu einer bereits installierten Godot-4-Executable. |
| `-ForceRebuildAll` | `Bool` | `$true` | Bei `$false` werden lokal bearbeitete `.gd`-Dateien beim Start nicht überschrieben. |
| `-RunSmokeTest` | `Bool` | `$true` | Führt vor dem Spielstart den Headless-Smoke-Test über die Projektmodule aus. |
| `-ExportRelease` | `Switch` | `$false` | Kompiliert fertige Binärdateien (`.exe` / `.x86_64`), erstellt `SHA256SUMS.txt` & ein Release-ZIP. |
| `-TargetPlatform` | `String` | `"Windows"` | Zielplattform für `-ExportRelease`: `"Windows"`, `"Linux"` oder `"All"`. |
| `-NoLaunch` | `Switch` | `$false` | Beendet das Skript nach dem Build/Test ohne Öffnen des Spielfensters (für CI/CD). |

**Beispiele für fortgeschrittene Aufrufe:**

```powershell
# Lokale Code-Änderungen behalten und sofort starten:
powershell -ExecutionPolicy Bypass -File .\Start-SolaraVice.ps1 -ForceRebuildAll:$false

# Fertiges Windows-Release (.exe + SHA256SUMS.txt + ZIP-Archiv in build/releases/) erzeugen:
powershell -ExecutionPolicy Bypass -File .\Start-SolaraVice.ps1 -ExportRelease -TargetPlatform Windows -NoLaunch
```

### 3. Einrichtung unter Linux / macOS / WSL (Bash)

```bash
chmod +x setup_solara_vice.sh build_release.sh
./build_release.sh --platform linux
```

---

## 🎮 Steuerungs- & Hotkey-Referenz

| Taste / Eingabe | Aktion zu Fuß | Aktion im Fahrzeug / Boot / Helikopter |
| :--- | :--- | :--- |
| **`W, A, S, D`** | Bewegen in Kamera-Blickrichtung | Gas, Bremse & Lenkung (Heli: Neigen & Gieren) |
| **`Mausbewegung`** | Kamera frei umsehen / Zielen | Kamera führen |
| **`E` oder `F`** | In Fahrzeug einsteigen / Shop, ATM, Casino nutzen | Fahrzeug / Boot / Helikopter verlassen |
| **`Leertaste`** | Springen | Handbremse / Drift (Heli: **Steigen**) |
| **`Shift (Links)`** | Sprinten (Im Sniper-Visier: **Atem & Zeitlupe**) | Boot: Jet-Boost (Heli: **Sinken**) |
| **`Linke Maustaste`** | Waffe abfeuern / Granate werfen | Drive-By-Feuer (Heli: **Zwillings-Bordkanonen**) |
| **`Rechte Maustaste`** | Präzisionszielen / Sniper-Mil-Dot-Visier | Drive-By-Zielmodus |
| **`1` – `5` / `Tab`** | Waffe direkt wählen (Slot $1$–$5$) / Waffenrad | Drive-By-Waffe wechseln |
| **`Mausrad` / `V`** | Im Sniper-Visier (Slot $5$): **Zoom $2.5\times / 6\times / 12\times$** | — |
| **`R`** | Waffe nachladen | Waffe nachladen |
| **`Q`** | — | Bordradio-Sender wechseln (`InCarRadio`) |
| **`H` / `L`** | — | Helikopter: **Hover-Lock (`H`)** / **Scheinwerfer (`L`)** |
| **`B` / `G`** | **Leibwächter rekrutieren/heilen (`B`)** / **Befehl (`G`)** | Leibwächter geben autonomes Beifahrer-Feuer |
| **`Pfeil Oben`** | **Smartphone (`SolaraOS v2.0`)** öffnen/schließen | Missionen, Rennen & Scanner vom Steuer starten |
| **`M`** | **Taktische 3D-GPS-Stadtkarte & Schnellreise** | GPS-Ziel & Schnellreise wählen |
| **`J` oder `F6`** | **100%-Komplettierungs- & Trophäen-Dashboard** | Spielfortschritt & Trophäen-Vitrine prüfen |
| **`P`** | **Foto-Studio & freie Kamera-Drohne** (Pausiert Welt) | Action-Aufnahmen im Sprung/Drift erstellen |
| **`F5`** | **Charakterwechsel** (*Elena Vance* $\leftrightarrow$ *Marcus Vance*) | Wechselt zum anderen Protagonisten |
| **`F1`** | **Entwickler-Konsole & Live-Smoke-Test** | Telemetrie, Spawner & Systemdiagnose |
| **`F3` / `F4`** | Schnell-Cheat: **$+\$25.000$ (`F3`)** / **Fahndung $0\star$ (`F4`)** | Sofort Bargeld / Fahndung löschen |

---

## 🏗 System-Architektur & Topologische Schichten

Um zirkuläre Abhängigkeiten auszuschließen und deterministische Headless-Builds zu garantieren, sind alle **57 Komponenten** in **6 topologische Schichten** gegliedert:

```text
Schicht 0: Projekt- & Engine-Konfiguration
  └── project.godot, default_bus_layout.tres, export_presets.cfg, wet_asphalt.gdshader

Schicht 1: Globale Autoload-Singletons (src/autoloads/ & src/audio/)
  ├── GameState              (Bargeld-Transaktionen & abgeschlossene Missionen)
  ├── WantedManager          (5-Sterne-Polizeifahndung, Heat-Decay & Einheiten-Pool)
  ├── MissionManager         (Story-Kampagne, Wegpunkte & Funk-Dialoge)
  ├── SaveSettingsMgr        (JSON-Persistenz unter user://solara_savestate.json)
  ├── ProceduralSFXSynth     (Mathematische 16-Bit-PCM-Synthese für Schüsse, Aufprall & Motoren)
  ├── SpatialAudioManager    (3D-Audio-Emitter-Pool auf dem SFX-Bus)
  ├── CharacterSwitchMgr     (Dual-Protagonisten-Umschaltung Elena <-> Marcus)
  ├── RespawnCinematicMgr    (Wasted-/Busted-Behandlung & Krankenhaus-/Revier-Respawn)
  └── AchievementTracker     (100%-Fortschrittsberechnung, Trophäen & Vitrine)

Schicht 2: Essentielle Basis-Entitäten (src/entities/)
  ├── VehicleConfig & WeaponConfig (Typisierte Resource-Datenprofile)
  ├── PlayerController & WeaponHandler (Charakterphysik, Kamera-Rig & 5-Slot-Arsenal)
  ├── ArcadeVehicle          (Basis-Fahrzeugphysik, Lackierung, Underglow & Schadensmodell)
  └── PedestrianAI & HostileGuardAI (Passanten- & Kampf-KI)

Schicht 3: Spezialisierte Fahrzeuge, Luft-/Seefahrt, Optik & Polizei
  ├── SpeedboatController    (4-Punkt-Auftrieb, Gerstner-Wellen & Hafen-Marina)
  ├── SkyhawkHelicopter      (Kreisel-Flugphysik, Avionik-HUD & Safehouse-Helipad)
  ├── ArmoredCashTruck       (Sprengbarer Geldtransporter mit Heckpanzerung)
  ├── SniperScopeController  (Mil-Dot-Visier, 3 Zoom-Stufen & Fokus-Zeitlupe)
  └── PoliceAI, SWATEnforcerAI, PoliceHelicopterAI, PoliceSpikeStrip, PoliceRoadblock

Schicht 4: Prozedurale Welt, Wirtschaft, Finale & Endgame (src/world/)
  ├── EnvironmentCycle & CityBlockBuilder (Tag-/Nacht-Zyklus, Wetter & Straßenraster)
  ├── SafehouseHub, WeaponShop, ModShop (Speichern, Kevlar/Munition & Stage-3-Tuning)
  ├── PropertyTycoon & SyndicateRaidMgr (4 Gewerbeimmobilien, Tresore & Syndikat-Raids)
  ├── StreetRaceManager, SkylineAirRace, OffshoreSmugglerRun (Land-, Luft- & See-Rennen)
  ├── VIPTransportJob, BountyHunterTerminal, ATMHackTerminal, RandomWorldEvents
  ├── BankHeistFinale        (Mehrstufiger Zentralbank-Coup über $75.000)
  ├── CyberCasinoGames       (Slot-Maschine, Roulette & Retro-Arcade)
  ├── TurfWarCommander       (Bezirks-Kriege & 4-Sitzer-Leibgarde)
  ├── UndergroundMetroNetwork(U-Bahn-Röhrensystem auf Y = -28.0m mit Radar-Schatten)
  └── AssetPackLoader        (Dynamisches glTF/GLB-Hot-Swapping zur Laufzeit)

Schicht 5 & 6: UI-Systeme, Master-Welt-Controller & Build-Tools (src/ui/ & src/tools/)
  ├── MainMenu, PhoneOS, WorldMapGPS, PhotoModeStudio, DebugOverlay
  ├── WorldSpawner           (Idempotente Orchestrierung aller 28 Open-World-Systeme)
  ├── generate_neon_harbor_editor.gd (Headless-Assembler für .tscn-Szenen)
  └── SmokeTestRunner        (Automatisierte Diagnose-Suite mit JSON-Report)
```

---

## 🏆 Open-World-Aktivitäten, Endgame & 100%-Fortschritt

Das Modul `AchievementTracker` (`J` oder `F6`) berechnet den Gesamtfortschritt in Echtzeit über **6 gewichtete Säulen** bis hin zur Platin-Auszeichnung (*Solara Platinum Kingpin*):

$$P_{\text{Gesamt}} = P_{\text{Story}} (20\%) + P_{\text{Relikte}} (20\%) + P_{\text{Immobilien}} (20\%) + P_{\text{Stunts}} (15\%) + P_{\text{Blitzer}} (15\%) + P_{\text{Spezial}} (10\%)$$

1. **Story-Kampagne ($20\%$):** Abschluss der Hauptmissionen inklusive des großen Zentralbank-Coups (`m03_central_bank_heist`).
2. **Versteckte Solara-Relikte ($20\%$):** Bergung der leuchtenden Relikt-Pakete (`CollectiblePackage`, je $+\$1.000$).
3. **Immobilien-Imperium ($20\%$):** Erwerb aller $4$ Gewerbeimmobilien (*Club Ecliptica*, *Eastside Imports*, *Container Logistics*, *Cyber-Vault Casino*) mit laufenden Tresor-Einnahmen (`PropertyTycoon`).
4. **Monster-Stunt-Sprünge ($15\%$):** Sprünge über die Stunt-Rampen (`StuntJumpRamp`) mit mindestens $65\text{ km/h}$.
5. **Speed-Trap-Blitzer & Drift-Zonen ($15\%$):** Durchfahren der Blitzer-Zonen (`SpeedDriftZone`) mit $\ge 135\text{ km/h}$.
6. **Open-World-Spezialaufträge ($10\%$):** Midnight-Circuit-Straßenrennen, Skyline-Helikopter-Rennen, Offshore-Schmuggel, Most-Wanted-Kopfgeldjagd, VIP-Chauffeurdienst, ATM-Cyber-Hack und Geldtransporter-Überfall.

---

## 🎨 Modding-Guide: Eigene 3D-Modelle einbinden (Asset-Bridge)

Das Modul `res://src/world/asset_pack_loader.gd` legt beim ersten Start automatisch die Ordnerstruktur unter `res://assets/models/` sowie die Spezifikationsdatei `res://assets/models/ASSET_PACK_MANIFEST.json` an.

Sobald du eine `.glb`- oder `.gltf`-Datei unter einem der folgenden Pfade ablegst, tauscht das Spiel die prozedurale Platzhalter-Geometrie beim nächsten Start vollautomatisch aus – inklusive Verknüpfung von Fahrzeug-Rädern, Helikopter-Rotoren, Lack-Materialien und Charakter-Animationen:

| Spiel-Entität | Erwarteter Modellpfad (`.glb` oder `.gltf`) | Unterstützte Kindknoten / Animationen |
| :--- | :--- | :--- |
| **Apex GT (Sportcoupé)** | `res://assets/models/vehicles/sport_coupe.glb` | `Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR`, `Body` |
| **Titan 4x4 (SUV)** | `res://assets/models/vehicles/heavy_suv.glb` | `Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR`, `Body` |
| **Metro Compact** | `res://assets/models/vehicles/compact_sedan.glb` | `Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR`, `Body` |
| **Police Cruiser** | `res://assets/models/vehicles/police_cruiser.glb` | `Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR` |
| **SWAT Enforcer** | `res://assets/models/vehicles/swat_enforcer.glb` | `Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR` |
| **Geldtransporter** | `res://assets/models/vehicles/armored_cash_truck.glb` | `Wheel_FL`, `Wheel_FR`, `Wheel_RL`, `Wheel_RR` |
| **Schnellboot (Stinger)** | `res://assets/models/vehicles/speedboat_stinger.glb` | `Body` |
| **Kampfhelikopter** | `res://assets/models/vehicles/skyhawk_gunship.glb` | `MainRotor`, `TailRotor`, `Body` |
| **Elena Vance** | `res://assets/models/characters/elena_vance.glb` | `AnimationPlayer` (`Idle`, `Walk`, `Run`, `Drive`) |
| **Marcus Vance** | `res://assets/models/characters/marcus_vance.glb` | `AnimationPlayer` (`Idle`, `Walk`, `Run`, `Drive`) |
| **Syndikat-Wache** | `res://assets/models/characters/syndicate_guard.glb` | `AnimationPlayer` (`Idle`, `Walk`, `Run`) |
| **Vance-Leibwächter** | `res://assets/models/characters/vance_bodyguard.glb` | `AnimationPlayer` (`Idle`, `Walk`, `Run`, `Drive`) |
| **ATM-Terminal** | `res://assets/models/props/solara_atm_kiosk.glb` | Statisches Mesh |

---

## 🧪 Qualitätssicherung, Smoke-Test & CI/CD-Pipeline

### Automatisierter Headless-Smoke-Test (`smoke_test_runner.gd`)
Das Projekt verfügt über eine eigene Diagnose-Suite, die sowohl über die Entwickler-Konsole (`F1`) im laufenden Spiel als auch komplett ohne grafische Oberfläche über die Kommandozeile ausgeführt werden kann:

```powershell
godot --headless --path . --script res://src/tools/smoke_test_runner.gd
```

* Prüft alle registrierten GDScript-Module auf Existenz, fehlerfreie Bytecode-Kompilierung und Instanziierbarkeit (`can_instantiate()`).
* Schreibt einen maschinenlesbaren Diagnosebericht nach `user://smoke_test_report.json` und beendet den Prozess mit Exit-Code `0` (`PASSED`) oder `1` (`FAILED`).

### GitHub Actions Workflow (`.github/workflows/release_build.yml`)
Bei jedem `git push` oder `pull_request` auf `main`/`master` sowie bei Versions-Tags (`v*.*.*`) führt die GitHub-Actions-Pipeline automatisch folgende Schritte auf `ubuntu-24.04` aus:
1. Bereitstellung von Godot 4.3 und den offiziellen Export-Templates (mit Actions-Cache).
2. Ausführung des Headless-Smoke-Tests und Upload von `smoke_test_report.json` als Build-Artefakt.
3. Headless-Szenen-Assemblierung über `generate_neon_harbor_editor.gd`.
4. Cross-Platform-Kompilierung für **Windows Desktop (`solara_vice.exe`)** und **Linux/X11 (`solara_vice.x86_64`)** inklusive `SHA256SUMS.txt`.

---

## 📂 Verzeichnisstruktur

```text
solara-vice/
├── .github/workflows/
│   └── release_build.yml              # Automatisierte GitHub Actions CI/CD-Pipeline
├── assets/
│   ├── models/                        # Zielordner für optionale .glb/.gltf 3D-Modelle
│   │   └── ASSET_PACK_MANIFEST.json   # Automatisch generierte Modding-Spezifikation
│   └── shaders/
│       └── wet_asphalt.gdshader       # Dynamischer Nass-Asphalt-Shader bei Regen
├── scenes/
│   ├── main.tscn                      # Boot-Szene (MainMenu + Live-HUD)
│   └── world/
│       └── neon_harbor_slice.tscn     # Assemblierte Open-World-Hauptszene
├── src/
│   ├── audio/                         # 16-Bit-PCM-Synthesizer, Bordradio & 3D-Sirenen
│   ├── autoloads/                     # 9 globale Singletons (GameState, Wanted, Mission etc.)
│   ├── entities/
│   │   ├── ai/                        # Passanten-, Wachen-, Renn-, Polizei- & SWAT-KI
│   │   ├── player/                    # PlayerController, WeaponConfig & WeaponHandler
│   │   ├── vehicles/                  # ArcadeVehicle, Speedboat, SkyhawkHeli, CashTruck
│   │   └── weapons/                   # FragGrenade & SniperScopeController
│   ├── tools/
│   │   ├── generate_neon_harbor_editor.gd # Headless Master-Editor-Assembler
│   │   └── smoke_test_runner.gd       # Automatisierte Qualitäts- & Compile-Prüfung
│   ├── ui/                            # MainMenu, PhoneOS, WorldMapGPS, PhotoStudio, Debug
│   └── world/                         # WorldSpawner, CityBuilder & alle 17 Gameplay-Module
├── default_bus_layout.tres            # 4-Kanal-Audio-Mixer (Master, Music, SFX, UI)
├── export_presets.cfg                 # Export-Profile für Windows Desktop & Linux/X11
├── project.godot                      # Godot 4 Projektkonfiguration, Autoloads & Input-Map
├── Start-SolaraVice.ps1               # All-in-One Windows Setup-, Test-, Build- & Release-Skript
└── README.md                          # Projektdokumentation
```

---

## 📄 Lizenz

Dieses Projekt steht unter der **MIT-Lizenz** – frei verwendbar für eigene Spieleprojekte, Erweiterungen und Lernzwecke in Godot 4.