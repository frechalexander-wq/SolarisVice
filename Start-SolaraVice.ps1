# Datei: Start-SolaraVice.ps1
<#
.SYNOPSIS
    Vereinheitlichter Ein-Klick-Starter & Auto-Builder fuer Solara Vice (Godot 4.x).
    Installiert und aktiviert alle essentiellen UND optionalen Module vollautomatisch
    in topologischer Reihenfolge ohne manuelle Nutzereingriffe.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Start-SolaraVice.ps1
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$GodotBin = "",

    [Parameter(Mandatory = $false)]
    [bool]$ForceRebuildAll = $true,

    [Parameter(Mandatory = $false)]
    [bool]$RunSmokeTest = $true,

    [Parameter(Mandatory = $false)]
    [switch]$ExportRelease = $false,

    [Parameter(Mandatory = $false)]
    [ValidateSet("All", "Windows", "Linux")]
    [string]$TargetPlatform = "Windows",

    [Parameter(Mandatory = $false)]
    [switch]$NoLaunch = $false
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ProjectRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Set-Location -Path $ProjectRoot

$Script:InstalledEssentialCount = 0
$Script:InstalledOptionalCount  = 0
$Script:InstalledConfigCount    = 0
$Script:InstallErrors           = @()

function Write-SetupLog {
    param(
        [Parameter(Mandatory = $true)][string]$Phase,
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO", "OK", "WARN", "ERROR")][string]$Level = "INFO"
    )
    $Timestamp = Get-Date -Format "HH:mm:ss"
    $Color = switch ($Level) {
        "OK"    { "Green" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
        default { "Cyan" }
    }
    Write-Host "[$Timestamp][$Phase][$Level] $Message" -ForegroundColor $Color
}

function Install-SolaraModule {
    param(
        [Parameter(Mandatory = $true)][string]$RelPath,
        [Parameter(Mandatory = $true)][ValidateSet("Essential", "Optional", "Config", "Tool")][string]$Category,
        [Parameter(Mandatory = $true)][string]$Content,
        [bool]$Overwrite = $ForceRebuildAll
    )
    try {
        $FullPath = Join-Path $ProjectRoot $RelPath
        $Dir = Split-Path $FullPath -Parent
        if (-not (Test-Path -LiteralPath $Dir)) {
            New-Item -ItemType Directory -Force -Path $Dir | Out-Null
        }

        if ($Overwrite -or -not (Test-Path -LiteralPath $FullPath)) {
            $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($FullPath, $Content, $Utf8NoBom)
        }

        $FileInfo = Get-Item -LiteralPath $FullPath -ErrorAction Stop
        if ($FileInfo.Length -le 0) {
            throw "Integritaetsfehler: Datei '$RelPath' hat 0 Bytes."
        }

        switch ($Category) {
            "Essential" { $Script:InstalledEssentialCount++ }
            "Optional"  { $Script:InstalledOptionalCount++ }
            default     { $Script:InstalledConfigCount++ }
        }
    } catch {
        $ErrMsg = "Installation fehlgeschlagen fuer [$Category] '$RelPath': $($_.Exception.Message)"
        $Script:InstallErrors += $ErrMsg
        Write-SetupLog -Phase "INSTALL" -Level "ERROR" -Message $ErrMsg
        throw
    }
}

Write-SetupLog -Phase "INIT" -Level "INFO" -Message "Starte vereinheitlichte Solara Vice Setup-Pipeline..."

# ==============================================================================
# 1. GODOT 4 EXECUTABLE SUCHEN ODER PORTABEL HERUNTERLADEN
# ==============================================================================
Write-Progress -Activity "Solara Vice Setup" -Status "1/6 Pruefe Godot 4 Engine..." -PercentComplete 10
if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    foreach ($Name in @("godot4", "godot", "Godot_v4.3-stable_win64.exe")) {
        $Cmd = Get-Command $Name -ErrorAction SilentlyContinue
        if ($null -ne $Cmd -and (Test-Path -LiteralPath $Cmd.Source)) {
            $GodotBin = $Cmd.Source
            break
        }
    }
}

$PortableGodotDir     = Join-Path $ProjectRoot ".engine"
$PortableGodotExe     = Join-Path $PortableGodotDir "Godot_v4.3-stable_win64.exe"
$PortableGodotConsole = Join-Path $PortableGodotDir "Godot_v4.3-stable_win64_console.exe"

if ([string]::IsNullOrWhiteSpace($GodotBin) -or -not (Test-Path -LiteralPath $GodotBin)) {
    if (Test-Path -LiteralPath $PortableGodotExe) {
        $GodotBin = $PortableGodotExe
    } else {
        Write-SetupLog -Phase "ENGINE" -Level "INFO" -Message "Lade portable Godot 4.3 Engine herunter (~65 MB)..."
        New-Item -ItemType Directory -Force -Path $PortableGodotDir | Out-Null
        $ZipUrl  = "https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_win64.exe.zip"
        $ZipFile = Join-Path $PortableGodotDir "godot43.zip"
        $OldProg = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipFile -UseBasicParsing
        } finally {
            $ProgressPreference = $OldProg
        }
        Expand-Archive -Path $ZipFile -DestinationPath $PortableGodotDir -Force
        Remove-Item $ZipFile -Force
        $GodotBin = $PortableGodotExe
    }
}

$GodotCliBin = if (Test-Path -LiteralPath $PortableGodotConsole) { $PortableGodotConsole } else { $GodotBin }
Write-SetupLog -Phase "ENGINE" -Level "OK" -Message "Godot 4 Engine verifiziert: $GodotBin"

# ==============================================================================
# 2. ORDNERBAUM, PROJEKTKONFIGURATION, SHADER & EXPORT-PRESETS
# ==============================================================================
Write-Progress -Activity "Solara Vice Setup" -Status "2/6 Erzeuge Projektkonfiguration & Shader..." -PercentComplete 20
$Folders = @(
    "src/autoloads", "src/audio", "src/entities/player", "src/entities/vehicles",
    "src/entities/weapons", "src/entities/ai", "src/world", "src/ui", "src/tools",
    "scenes/entities/vehicles", "scenes/world", "scenes/ui",
    "resources/vehicles", "resources/weapons", "assets/shaders", "assets/models"
)
foreach ($F in $Folders) {
    New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot $F) | Out-Null
}

Install-SolaraModule -RelPath "icon.svg" -Category "Config" -Content @'
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <rect width="128" height="128" rx="22" fill="#070b19" stroke="#1fe5ff" stroke-width="5"/>
  <circle cx="64" cy="56" r="30" fill="#ff9d1e" opacity="0.85"/>
  <text x="64" y="70" font-family="sans-serif" font-size="36" font-weight="bold" fill="#ffffff" text-anchor="middle">SV</text>
</svg>
'@

Install-SolaraModule -RelPath "default_bus_layout.tres" -Category "Config" -Content @'
[gd_resource type="AudioBusLayout" format=3]

[resource]
bus/1/name = &"Music"
bus/1/solo = false
bus/1/mute = false
bus/1/bypass_fx = false
bus/1/volume_db = -2.5
bus/1/send = &"Master"
bus/2/name = &"SFX"
bus/2/solo = false
bus/2/mute = false
bus/2/bypass_fx = false
bus/2/volume_db = 0.0
bus/2/send = &"Master"
bus/3/name = &"UI"
bus/3/solo = false
bus/3/mute = false
bus/3/bypass_fx = false
bus/3/volume_db = -1.5
bus/3/send = &"Master"
'@

Install-SolaraModule -RelPath "export_presets.cfg" -Category "Config" -Content @'
[preset.0]
name="Windows Desktop"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
export_path="build/windows/solara_vice.exe"

[preset.1]
name="Linux/X11"
platform="Linux/X11"
runnable=true
export_filter="all_resources"
export_path="build/linux/solara_vice.x86_64"
'@

Install-SolaraModule -RelPath "assets/shaders/wet_asphalt.gdshader" -Category "Config" -Content @'
shader_type spatial;
global uniform float global_rain_wetness;
uniform vec3 asphalt_color : source_color = vec3(0.07, 0.08, 0.11);
void fragment() {
	ALBEDO = mix(asphalt_color, asphalt_color * 0.55, clamp(global_rain_wetness, 0.0, 1.0));
	ROUGHNESS = mix(0.62, 0.12, clamp(global_rain_wetness, 0.0, 1.0));
	METALLIC = mix(0.15, 0.65, clamp(global_rain_wetness, 0.0, 1.0));
}
'@

Install-SolaraModule -RelPath "project.godot" -Category "Config" -Content @'
; Engine configuration file.
config_version=5

[application]

config/name="Solara Vice"
config/description="Open-World Action-Driving Vertical Slice in Neon Harbor (Godot 4)"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.2", "Forward Plus")
config/icon="res://icon.svg"

[audio]

buses/default_bus_layout="res://default_bus_layout.tres"

[autoload]

GameState="*res://src/autoloads/game_state.gd"
WantedManager="*res://src/autoloads/wanted_manager.gd"
MissionManager="*res://src/autoloads/mission_manager.gd"
SaveSettingsMgr="*res://src/autoloads/save_settings_mgr.gd"
SpatialAudioManager="*res://src/autoloads/spatial_audio_manager.gd"
ProceduralSFXSynth="*res://src/audio/procedural_sfx_synth.gd"
CharacterSwitchMgr="*res://src/autoloads/character_switch_mgr.gd"
RespawnCinematicMgr="*res://src/autoloads/respawn_cinematic_mgr.gd"
AchievementTracker="*res://src/autoloads/achievement_tracker.gd"

[display]

window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[input]

move_forward={"deadzone": 0.2, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":87,"key_label":0,"unicode":119,"echo":false,"script":null)]}
move_back={"deadzone": 0.2, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":83,"key_label":0,"unicode":115,"echo":false,"script":null)]}
move_left={"deadzone": 0.2, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":65,"key_label":0,"unicode":97,"echo":false,"script":null)]}
move_right={"deadzone": 0.2, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":68,"key_label":0,"unicode":100,"echo":false,"script":null)]}
look_left={"deadzone": 0.2, "events": []}
look_right={"deadzone": 0.2, "events": []}
look_up={"deadzone": 0.2, "events": []}
look_down={"deadzone": 0.2, "events": []}
sprint={"deadzone": 0.5, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194325,"key_label":0,"unicode":0,"echo":false,"script":null)]}
jump={"deadzone": 0.5, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":32,"key_label":0,"unicode":32,"echo":false,"script":null)]}
handbrake={"deadzone": 0.5, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":32,"key_label":0,"unicode":32,"echo":false,"script":null)]}
interact={"deadzone": 0.5, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":69,"key_label":0,"unicode":101,"echo":false,"script":null), Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":70,"key_label":0,"unicode":102,"echo":false,"script":null)]}
fire={"deadzone": 0.3, "events": [Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"button_mask":1,"position":Vector2(0,0),"global_position":Vector2(0,0),"factor":1.0,"button_index":1,"canceled":false,"pressed":false,"double_click":false,"script":null)]}
aim={"deadzone": 0.3, "events": [Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"button_mask":2,"position":Vector2(0,0),"global_position":Vector2(0,0),"factor":1.0,"button_index":2,"canceled":false,"pressed":false,"double_click":false,"script":null)]}
reload={"deadzone": 0.5, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":82,"key_label":0,"unicode":114,"echo":false,"script":null)]}
weapon_wheel={"deadzone": 0.5, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194306,"key_label":0,"unicode":0,"echo":false,"script":null)]}
radio_next={"deadzone": 0.5, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":81,"key_label":0,"unicode":113,"echo":false,"script":null)]}
phone_toggle={"deadzone": 0.5, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194320,"key_label":0,"unicode":0,"echo":false,"script":null)]}
switch_character={"deadzone": 0.5, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194336,"key_label":0,"unicode":0,"echo":false,"script":null)]}
Cancel_job={"deadzone": 0.5, "events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194308,"key_label":0,"unicode":0,"echo":false,"script":null)]}

[rendering]

anti_aliasing/quality/msaa_3d=2
environment/defaults/default_clear_color=Color(0.04, 0.05, 0.08, 1)

[shader_globals]

global_rain_wetness={"type": "float", "value": 0.0}
global_time_of_day={"type": "float", "value": 21.5}
'@

# ==============================================================================
# 3. STUFE 1: AUTOLOADS (ESSENTIELL & OPTIONAL)
# ==============================================================================
Write-SetupLog -Phase "STAGE-1" -Level "INFO" -Message "Installiere Stufe 1: Autoload-Singletons..."

Install-SolaraModule -RelPath "src/autoloads/game_state.gd" -Category "Essential" -Content @'
extends Node
signal cash_changed(new_cash: int, delta: int)
var cash: int = 15000
var completed_missions: Array[String] = []
func modify_cash(amount: int) -> void:
	cash = maxi(0, cash + amount)
	cash_changed.emit(cash, amount)
func mark_mission_completed(m_id: String) -> void:
	if not completed_missions.has(m_id):
		completed_missions.append(m_id)
'@

Install-SolaraModule -RelPath "src/autoloads/wanted_manager.gd" -Category "Essential" -Content @'
extends Node
signal wanted_level_changed(new_stars: int)
var current_stars: int = 0
var current_heat: float = 0.0
var decay_timer: float = 0.0
var active_units: Array[Node3D] = []
var police_car_scene: PackedScene = null
func _process(delta: float) -> void:
	if current_stars > 0:
		decay_timer -= delta
		if decay_timer <= 0.0:
			clear_wanted_level()
func report_crime(heat_amount: float) -> void:
	current_heat += heat_amount
	decay_timer = 25.0
	var s: int = clampi(int(current_heat / 35.0) + 1, 1, 5)
	if s != current_stars:
		current_stars = s
		wanted_level_changed.emit(current_stars)
func set_minimum_stars(min_s: int) -> void:
	if current_stars < min_s:
		current_stars = clampi(min_s, 0, 5)
		decay_timer = 30.0
		wanted_level_changed.emit(current_stars)
func clear_wanted_level() -> void:
	current_stars = 0
	current_heat = 0.0
	decay_timer = 0.0
	wanted_level_changed.emit(0)
'@

Install-SolaraModule -RelPath "src/autoloads/mission_manager.gd" -Category "Essential" -Content @'
extends Node
signal objective_updated(text: String, target_pos: Vector3)
signal dialogue_triggered(speaker: String, line: String)
signal mission_completed(title: String, cash_reward: int)
signal mission_failed(title: String, reason: String)
var active_mission_id: String = ""
func start_mission(m_id: String) -> void:
	active_mission_id = m_id
	if m_id == "m01_neon_delivery":
		objective_updated.emit("Fahre zum Hafen-Uebergabepunkt!", Vector3(-120.0, 0.5, 110.0))
		dialogue_triggered.emit("Marcus (Funk)", "Bring die Lieferung schnell zum Suedhafen, Elena!")
	elif m_id == "m02_harbor_heist":
		objective_updated.emit("Sichere das Container-Depot am Suedhafen!", Vector3(-175.0, 0.5, 185.0))
		dialogue_triggered.emit("Marcus (Funk)", "Schalte die Hafen-Wachen aus und sichere die Fracht!")
'@

Install-SolaraModule -RelPath "src/autoloads/save_settings_mgr.gd" -Category "Essential" -Content @'
extends Node
const SAVE_PATH: String = "user://solara_savestate.json"
func save_game_state(player_pos: Vector3) -> void:
	var data: Dictionary = {"pos_x": player_pos.x, "pos_y": player_pos.y, "pos_z": player_pos.z, "cash": GameState.cash}
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(data))
func load_game_state() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return parsed if parsed is Dictionary else {}
'@

Install-SolaraModule -RelPath "src/audio/procedural_sfx_synth.gd" -Category "Essential" -Content @'
extends Node
func create_impulse_wav(freq: float, dur: float, noise_mix: float = 0.5) -> AudioStreamWAV:
	var rate: int = 22050
	var samples: int = int(dur * float(rate))
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples * 2)
	for i in range(samples):
		var t: float = float(i) / float(rate)
		var env: float = exp(-t * (8.0 / maxf(0.05, dur)))
		var sig: float = (sin(t * freq * TAU) * (1.0 - noise_mix) + (randf() * 2.0 - 1.0) * noise_mix) * env * 0.7
		bytes.encode_s16(i * 2, int(round(clampf(sig, -1.0, 1.0) * 32767.0)))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = bytes
	return wav
'@

Install-SolaraModule -RelPath "src/autoloads/spatial_audio_manager.gd" -Category "Essential" -Content @'
extends Node
var _gun_wav: AudioStreamWAV
var _hit_wav: AudioStreamWAV
func _ready() -> void:
	_gun_wav = ProceduralSFXSynth.create_impulse_wav(190.0, 0.16, 0.75)
	_hit_wav = ProceduralSFXSynth.create_impulse_wav(110.0, 0.28, 0.60)
func play_gunshot_3d(pos: Vector3) -> void:
	play_sfx_3d(_gun_wav, pos, 0.0, 0.92, 1.08, 120.0)
func play_collision_impact_3d(pos: Vector3, intensity: float = 20.0) -> void:
	if intensity > 3.0:
		play_sfx_3d(_hit_wav, pos, clampf((intensity - 20.0) * 0.15, -8.0, 4.0), 0.85, 1.15, 110.0)
func play_sfx_3d(stream: AudioStream, pos: Vector3, vol_db: float = 0.0, p_min: float = 0.95, p_max: float = 1.05, max_d: float = 100.0) -> void:
	if not stream or not get_tree().current_scene: return
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = vol_db
	p.pitch_scale = randf_range(p_min, p_max)
	p.max_distance = max_d
	p.bus = "SFX"
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
'@

Install-SolaraModule -RelPath "src/autoloads/character_switch_mgr.gd" -Category "Essential" -Content @'
extends Node
var elena_instance: Node3D = null
var marcus_instance: Node3D = null
var is_switching: bool = false
func register_protagonists(elena: Node3D, marcus: Node3D) -> void:
	elena_instance = elena
	marcus_instance = marcus
	if is_instance_valid(elena): elena.add_to_group("player")
	if is_instance_valid(marcus):
		marcus.remove_from_group("player")
		marcus.set_physics_process(false)
		marcus.set_process_unhandled_input(false)
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("switch_character"):
		switch_to_other_protagonist()
func switch_to_other_protagonist() -> void:
	if is_switching or not is_instance_valid(elena_instance) or not is_instance_valid(marcus_instance): return
	var current_p: Node3D = elena_instance if elena_instance.is_in_group("player") else marcus_instance
	var target_p: Node3D = marcus_instance if (current_p == elena_instance) else elena_instance
	if current_p.has_method("exit_current_vehicle") and bool(current_p.get("is_in_vehicle")):
		current_p.call("exit_current_vehicle")
	current_p.remove_from_group("player")
	current_p.set_physics_process(false)
	current_p.set_process_unhandled_input(false)
	target_p.add_to_group("player")
	target_p.set_physics_process(true)
	target_p.set_process_unhandled_input(true)
	var cam: Camera3D = target_p.get("camera") as Camera3D
	if cam: cam.make_current()
	MissionManager.dialogue_triggered.emit("Charakterwechsel [F5]", "Steuerung uebernommen: " + target_p.name)
'@

Install-SolaraModule -RelPath "src/autoloads/respawn_cinematic_mgr.gd" -Category "Essential" -Content @'
extends CanvasLayer
func trigger_respawn(player: Node3D, is_busted: bool = false) -> void:
	if not is_instance_valid(player): return
	WantedManager.clear_wanted_level()
	player.global_position = Vector3(-64.0, 0.8, -39.0) if is_busted else Vector3(12.0, 0.8, -24.0)
	if "current_health" in player:
		player.set("current_health", 100.0)
'@

Install-SolaraModule -RelPath "src/autoloads/achievement_tracker.gd" -Category "Optional" -Content @'
class_name AchievementTracker
extends CanvasLayer

signal trophy_unlocked(trophy_id: String, title: String)
signal completion_updated(percentage: float)

const SAVE_FILE_PATH: String = "user://achievements_progress.json"

var unlocked_trophies: Dictionary = {}
var misc_activities_done: Dictionary = {}
var current_completion_pct: float = 0.0
var _dashboard_panel: PanelContainer
var _summary_label: Label
var _list_label: Label

const TROPHY_CATALOG: Dictionary = {
	"tr_01_first_wheels":   {"title": "Asphalt-Cowboy", "desc": "Erstes Fahrzeug in Neon Harbor gesteuert."},
	"tr_02_relic_hunter":   {"title": "Relikt-Jäger", "desc": "Verstecktes Solara-Relikt geborgen."},
	"tr_03_midnight_racer": {"title": "König der Nacht", "desc": "Ein Straßen-, Luft- oder Offshore-Rennen gewonnen."},
	"tr_04_real_estate":    {"title": "Immobilien-Mogul", "desc": "Eine Gewerbeimmobilie in Neon Harbor erworben."},
	"tr_05_bank_master":    {"title": "Der Zentralbank-Coup", "desc": "Das große Story-Finale erfolgreich abgeschlossen."},
	"tr_06_kingpin":        {"title": "Solara Platinum Kingpin", "desc": "100% Spielfortschritt oder alle Bezirke erobert."}
}

func _ready() -> void:
	layer = 19
	add_to_group("achievement_tracker")
	_build_dashboard_ui()
	_load_progress()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_J or k == KEY_F6:
			toggle_dashboard()
			get_viewport().set_input_as_handled()

func unlock_trophy(t_id: String) -> void:
	if not unlocked_trophies.has(t_id):
		unlocked_trophies[t_id] = true
		var t_info: Dictionary = TROPHY_CATALOG.get(t_id, {"title": t_id, "desc": "Meilenstein erreicht!"})
		MissionManager.dialogue_triggered.emit("TROPHÄE: " + t_info["title"], t_info["desc"])
		trophy_unlocked.emit(t_id, t_info["title"])
		_evaluate_all_progress_and_trophies()
		_save_progress()

func _evaluate_all_progress_and_trophies() -> void:
	var story_pts: float = minf(20.0, float(GameState.completed_missions.size()) * 6.67)
	var pkg_pts: float = minf(20.0, float(CollectiblePackage.collected_package_ids.size()) * 2.0)
	var prop_pts: float = minf(20.0, float(PropertyTycoon.owned_properties.size()) * 5.0)
	var stunt_pts: float = minf(15.0, float(StuntJumpRamp.completed_ramp_ids.size()) * 2.5)
	var zone_pts: float = minf(15.0, float(SpeedDriftZone.zone_best_stars.size()) * 2.5)
	var misc_pts: float = minf(10.0, float(misc_activities_done.size()) * 2.5)

	current_completion_pct = clampf(story_pts + pkg_pts + prop_pts + stunt_pts + zone_pts + misc_pts, 0.0, 100.0)
	completion_updated.emit(current_completion_pct)

	if current_completion_pct >= 99.5 and not unlocked_trophies.has("tr_06_kingpin"):
		unlocked_trophies["tr_06_kingpin"] = true
		MissionManager.dialogue_triggered.emit("PLATIN-TROPHÄE", "100% in Solara Vice erreicht!")
	_refresh_dashboard_text()

func toggle_dashboard() -> void:
	_evaluate_all_progress_and_trophies()
	_dashboard_panel.visible = not _dashboard_panel.visible

func _build_dashboard_ui() -> void:
	_dashboard_panel = PanelContainer.new()
	_dashboard_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_dashboard_panel.position = Vector2(-280, -190)
	_dashboard_panel.custom_minimum_size = Vector2(560, 380)
	_dashboard_panel.visible = false
	var st: StyleBoxFlat = StyleBoxFlat.new()
	st.bg_color = Color(0.03, 0.05, 0.10, 0.95)
	st.border_color = Color(1.0, 0.82, 0.18, 0.95)
	st.set_border_width_all(2); st.set_corner_radius_all(10)
	st.content_margin_left = 18; st.content_margin_right = 18; st.content_margin_top = 14; st.content_margin_bottom = 14
	_dashboard_panel.add_theme_stylebox_override("panel", st)
	add_child(_dashboard_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_dashboard_panel.add_child(vbox)

	_summary_label = Label.new()
	_summary_label.add_theme_font_size_override("font_size", 18)
	_summary_label.modulate = Color(1.0, 0.85, 0.2)
	vbox.add_child(_summary_label)

	_list_label = Label.new()
	_list_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_list_label)

func _refresh_dashboard_text() -> void:
	if not _summary_label: return
	_summary_label.text = "SOLARA VICE // 100%%-CHECKLISTE (AKTUELL: %.1f%%) [J / F6]" % current_completion_pct
	var lines: PackedStringArray = PackedStringArray()
	lines.append("• Story-Missionen erledigt: %d / 3" % GameState.completed_missions.size())
	lines.append("• Versteckte Solara-Relikte: %d / 10" % CollectiblePackage.collected_package_ids.size())
	lines.append("• Gewerbeimmobilien im Besitz: %d / 4" % PropertyTycoon.owned_properties.size())
	lines.append("• Monster-Stunt-Sprünge: %d / 6" % StuntJumpRamp.completed_ramp_ids.size())
	lines.append("• Blitzer- & Drift-Zonen: %d / 6" % SpeedDriftZone.zone_best_stars.size())
	lines.append("• Freigeschaltete Trophäen: %d / %d" % [unlocked_trophies.size(), TROPHY_CATALOG.size()])
	lines.append("\n--- TROPHÄEN-VITRINE ---")
	for k in TROPHY_CATALOG.keys():
		var info: Dictionary = TROPHY_CATALOG[k]
		var mark: String = "[OK]" if unlocked_trophies.has(k) else "[  ]"
		lines.append("%s %s - %s" % [mark, info["title"], info["desc"]])
	_list_label.text = "\n".join(lines)

func _save_progress() -> void:
	var f: FileAccess = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"trophies": unlocked_trophies, "misc": misc_activities_done}))

func _load_progress() -> void:
	if not FileAccess.file_exists(SAVE_FILE_PATH): return
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_FILE_PATH))
	if p is Dictionary:
		unlocked_trophies = p.get("trophies", {})
		misc_activities_done = p.get("misc", {})
'@

# ==============================================================================
# 4. STUFE 2: BASIS-ENTITÄTEN (SPIELER, WAFFEN, FAHRZEUG, KI)
# ==============================================================================
Install-SolaraModule -RelPath "src/entities/vehicles/vehicle_config.gd" -Category "Essential" -Content @'
class_name VehicleConfig
extends Resource
@export var vehicle_name: String = "Apex GT"
@export var max_engine_force: float = 4100.0
@export var max_brake_force: float = 110.0
@export var max_steer_angle_deg: float = 34.0
@export var top_speed_kmh: float = 215.0
@export var vehicle_mass: float = 1280.0
@export var all_wheel_drive: bool = false
'@

Install-SolaraModule -RelPath "src/entities/player/weapon_config.gd" -Category "Essential" -Content @'
class_name WeaponConfig
extends Resource
enum WeaponArchetype { PISTOL, SMG, SHOTGUN, GRENADE }
@export var weapon_name: String = "Solara 9mm"
@export var archetype: WeaponArchetype = WeaponArchetype.PISTOL
@export var damage_per_pellet: float = 28.0
@export var pellet_count: int = 1
@export var spread_degrees: float = 1.2
@export var fire_rate_sec: float = 0.22
@export var max_range: float = 110.0
@export var magazine_size: int = 15
@export var default_reserve_ammo: int = 90
@export var reload_time_sec: float = 1.4
@export var allow_in_vehicle: bool = true
@export var recoil_kick_deg: float = 1.0
'@

Install-SolaraModule -RelPath "src/entities/player/player_controller.gd" -Category "Essential" -Content @'
class_name PlayerController
extends CharacterBody3D

signal health_changed(cur: float, max_val: float)
signal armor_changed(cur: float, max_val: float)

var max_health: float = 100.0
var current_health: float = 100.0
var current_armor: float = 50.0
var mouse_sensitivity: float = 0.0022
var normal_fov: float = 75.0
var is_in_vehicle: bool = false
var current_vehicle: Node3D = null

var camera_pivot: Node3D
var spring_arm: SpringArm3D
var camera: Camera3D
var interaction_area: Area3D
var visual_mesh: Node3D
var aim_ray: RayCast3D

func _ready() -> void:
	add_to_group("player")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if camera_pivot and not is_in_vehicle:
			var mm: InputEventMouseMotion = event as InputEventMouseMotion
			camera_pivot.rotation.y -= mm.relative.x * mouse_sensitivity
			camera_pivot.rotation.x = clampf(camera_pivot.rotation.x - mm.relative.y * mouse_sensitivity, deg_to_rad(-75.0), deg_to_rad(65.0))
	elif event.is_action_pressed("interact"):
		if is_in_vehicle:
			exit_current_vehicle()
		else:
			_try_enter_nearby_vehicle()

func _physics_process(delta: float) -> void:
	if is_in_vehicle and is_instance_valid(current_vehicle):
		global_position = current_vehicle.global_position
		return

	if not is_on_floor():
		velocity.y -= 9.8 * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = 5.4

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_basis: Basis = Basis(Vector3.UP, camera_pivot.rotation.y) if camera_pivot else global_transform.basis
	var move_dir: Vector3 = (cam_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var spd: float = 8.4 if Input.is_action_pressed("sprint") else 5.2

	if move_dir.length_squared() > 0.01:
		velocity.x = move_dir.x * spd
		velocity.z = move_dir.z * spd
		if visual_mesh:
			visual_mesh.rotation.y = lerp_angle(visual_mesh.rotation.y, atan2(-move_dir.x, -move_dir.z), 12.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 22.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 22.0 * delta)

	move_and_slide()

func _try_enter_nearby_vehicle() -> void:
	var best_veh: Node3D = null
	var best_d: float = 5.8
	for node in get_tree().get_nodes_in_group("driveable_vehicles"):
		if is_instance_valid(node) and node is Node3D and not bool(node.get("is_destroyed")):
			var d: float = global_position.distance_to((node as Node3D).global_position)
			if d < best_d:
				best_d = d
				best_veh = node as Node3D
	if best_veh:
		_enter_vehicle(best_veh)

func _enter_vehicle(veh: Node3D) -> void:
	is_in_vehicle = true
	current_vehicle = veh
	visible = false
	if veh.has_method("set_driver"):
		veh.call("set_driver", self)

func exit_current_vehicle() -> void:
	if not is_in_vehicle: return
	var v: Node3D = current_vehicle
	is_in_vehicle = false
	current_vehicle = null
	visible = true
	if is_instance_valid(v):
		if v.has_method("set_driver"): v.call("set_driver", null)
		var exit_m: Node3D = v.get("exit_marker") as Node3D
		global_position = exit_m.global_position if exit_m else (v.global_position + Vector3(-2.4, 0.8, 0.0))
	if camera: camera.make_current()

func apply_damage(amount: float, _hit_pos: Vector3 = Vector3.ZERO) -> void:
	if current_armor > 0.0:
		var absorb: float = minf(current_armor, amount * 0.65)
		current_armor -= absorb
		amount -= absorb
		armor_changed.emit(current_armor, 100.0)
	current_health = maxf(0.0, current_health - amount)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		RespawnCinematicMgr.trigger_respawn(self, false)

func restore_armor(val: float) -> void:
	current_armor = clampf(val, 0.0, 100.0)
	armor_changed.emit(current_armor, 100.0)
'@

Install-SolaraModule -RelPath "src/entities/player/weapon_handler.gd" -Category "Essential" -Content @'
class_name WeaponHandler
extends Node

var player: PlayerController = null
var arsenal: Array[WeaponConfig] = []
var current_slot: int = 0
var _mag_ammo: Array[int] = []
var _reserve_ammo: Array[int] = []
var _fire_cd: float = 0.0

func _ready() -> void:
	player = get_parent() as PlayerController
	var names: Array[String] = ["Solara 9mm", "Viper SMG", "Breacher 12G", "M67 Granate", "Solara .50 Precision"]
	var dmgs: Array[float] = [28.0, 22.0, 18.0, 140.0, 240.0]
	var rates: Array[float] = [0.22, 0.09, 0.65, 1.1, 0.95]
	for i in range(5):
		var cfg: WeaponConfig = WeaponConfig.new()
		cfg.weapon_name = names[i]
		cfg.damage_per_pellet = dmgs[i]
		cfg.pellet_count = 6 if i == 2 else 1
		cfg.fire_rate_sec = rates[i]
		cfg.magazine_size = 30 if i == 1 else (8 if i == 2 else (5 if i == 4 else 15))
		cfg.default_reserve_ammo = 150
		arsenal.append(cfg)
		_mag_ammo.append(cfg.magazine_size)
		_reserve_ammo.append(cfg.default_reserve_ammo)

func _process(delta: float) -> void:
	if _fire_cd > 0.0: _fire_cd -= delta
	if not player or get_tree().paused: return
	if Input.is_action_pressed("fire") and _fire_cd <= 0.0:
		_fire_current_weapon()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_1: equip_slot(0)
		elif k.keycode == KEY_2: equip_slot(1)
		elif k.keycode == KEY_3: equip_slot(2)
		elif k.keycode == KEY_4: equip_slot(3)
		elif k.keycode == KEY_5 and arsenal.size() > 4: equip_slot(4)

func equip_slot(slot_idx: int) -> void:
	if slot_idx >= 0 and slot_idx < arsenal.size():
		current_slot = slot_idx
		MissionManager.dialogue_triggered.emit("Waffe gewechselt", arsenal[slot_idx].weapon_name)

func add_reserve_ammo(slot_idx: int, amount: int, max_cap: int = 300) -> void:
	if slot_idx >= 0 and slot_idx < _reserve_ammo.size():
		_reserve_ammo[slot_idx] = mini(max_cap, _reserve_ammo[slot_idx] + amount)

func _fire_current_weapon() -> void:
	if current_slot >= arsenal.size(): return
	var cfg: WeaponConfig = arsenal[current_slot]
	_fire_cd = cfg.fire_rate_sec
	SpatialAudioManager.play_gunshot_3d(player.global_position + Vector3(0.0, 1.4, 0.0))
	if player.aim_ray and player.aim_ray.is_colliding():
		var col: Object = player.aim_ray.get_collider()
		var pt: Vector3 = player.aim_ray.get_collision_point()
		if col and col.has_method("apply_damage"):
			col.call("apply_damage", cfg.damage_per_pellet * float(cfg.pellet_count), pt)
		elif col and col.has_method("apply_brute_force_damage"):
			col.call("apply_brute_force_damage", cfg.damage_per_pellet * float(cfg.pellet_count))
'@

Install-SolaraModule -RelPath "src/entities/vehicles/arcade_vehicle.gd" -Category "Essential" -Content @'
class_name ArcadeVehicle
extends VehicleBody3D

signal vehicle_destroyed(veh: ArcadeVehicle)

@export var config: VehicleConfig
var driver: PlayerController = null
var is_stolen_on_entry: bool = false
var is_destroyed: bool = false
var max_vehicle_health: float = 1000.0
var current_health: float = 1000.0
var current_speed_kmh: float = 0.0
var engine_upgrade_multiplier: float = 1.0
var armor_damage_reduction: float = 1.0

var body_mesh: MeshInstance3D
var wheel_fl: VehicleWheel3D
var wheel_fr: VehicleWheel3D
var wheel_rl: VehicleWheel3D
var wheel_rr: VehicleWheel3D
var exit_marker: Marker3D
var vehicle_camera: Camera3D
var engine_audio: AudioStreamPlayer3D
var horn_audio: AudioStreamPlayer3D
var _paint_mat: StandardMaterial3D
var _underglow_light: OmniLight3D

func _ready() -> void:
	add_to_group("driveable_vehicles")
	if not config: config = VehicleConfig.new()
	mass = config.vehicle_mass
	if not wheel_fl:
		_build_default_car_chassis()

func _physics_process(delta: float) -> void:
	current_speed_kmh = linear_velocity.length() * 3.6
	if is_destroyed:
		engine_force = 0.0
		brake = 40.0
		return
	if driver != null:
		var throttle: float = Input.get_axis("move_back", "move_forward")
		var steer_in: float = Input.get_axis("move_right", "move_left")
		steering = move_toward(steering, steer_in * deg_to_rad(config.max_steer_angle_deg), 2.8 * delta)
		engine_force = throttle * config.max_engine_force * engine_upgrade_multiplier
		brake = config.max_brake_force if Input.is_action_pressed("handbrake") else 0.0
	else:
		engine_force = 0.0
		brake = 15.0

func set_driver(new_driver: PlayerController) -> void:
	driver = new_driver
	if driver != null and vehicle_camera:
		vehicle_camera.make_current()
		var ach: AchievementTracker = get_tree().get_first_node_in_group("achievement_tracker") as AchievementTracker
		if ach: ach.unlock_trophy("tr_01_first_wheels")
		if is_stolen_on_entry:
			is_stolen_on_entry = false
			WantedManager.report_crime(25.0)

func apply_custom_paint(col: Color, metallic_val: float = 0.8, rough_val: float = 0.2) -> void:
	if not _paint_mat:
		_paint_mat = StandardMaterial3D.new()
	_paint_mat.albedo_color = col
	_paint_mat.metallic = metallic_val
	_paint_mat.roughness = rough_val
	if body_mesh:
		body_mesh.material_override = _paint_mat

func set_underglow(enabled: bool, col: Color = Color.CYAN) -> void:
	if not _underglow_light:
		_underglow_light = OmniLight3D.new()
		_underglow_light.position = Vector3(0.0, 0.18, 0.0)
		_underglow_light.omni_range = 6.5
		_underglow_light.light_energy = 2.8
		add_child(_underglow_light)
	_underglow_light.visible = enabled
	_underglow_light.light_color = col

func apply_performance_upgrade(eng_mult: float, armor_red: float, _turbo: bool = true) -> void:
	engine_upgrade_multiplier = eng_mult
	armor_damage_reduction = armor_red
	repair_and_restore_full()

func repair_and_restore_full() -> void:
	is_destroyed = false
	current_health = max_vehicle_health

func apply_damage(amount: float, _hit_pos: Vector3 = Vector3.ZERO) -> void:
	if is_destroyed: return
	current_health = maxf(0.0, current_health - amount * armor_damage_reduction)
	if current_health <= 0.0:
		is_destroyed = true
		SpatialAudioManager.play_collision_impact_3d(global_position, 95.0)
		vehicle_destroyed.emit(self)

func _create_particle_emitter(col: Color, amt: int, life: float, vel: Vector3, rad: float) -> GPUParticles3D:
	var p: GPUParticles3D = GPUParticles3D.new()
	p.amount = amt
	p.lifetime = life
	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.direction = vel.normalized()
	mat.initial_velocity_min = vel.length() * 0.7
	mat.initial_velocity_max = vel.length() * 1.2
	mat.color = col
	p.process_material = mat
	var sph: SphereMesh = SphereMesh.new()
	sph.radius = rad
	sph.height = rad * 2.0
	p.draw_pass_1 = sph
	return p

func _build_default_car_chassis() -> void:
	var col: CollisionShape3D = CollisionShape3D.new()
	var box_s: BoxShape3D = BoxShape3D.new()
	box_s.size = Vector3(1.95, 1.15, 4.3)
	col.shape = box_s
	col.position = Vector3(0.0, 0.65, 0.0)
	add_child(col)

	body_mesh = MeshInstance3D.new()
	var b_mesh: BoxMesh = BoxMesh.new()
	b_mesh.size = Vector3(1.9, 0.85, 4.2)
	body_mesh.mesh = b_mesh
	body_mesh.position = Vector3(0.0, 0.65, 0.0)
	add_child(body_mesh)

	var cabin: MeshInstance3D = MeshInstance3D.new()
	var c_mesh: BoxMesh = BoxMesh.new()
	c_mesh.size = Vector3(1.6, 0.55, 2.0)
	cabin.mesh = c_mesh
	cabin.position = Vector3(0.0, 0.62, -0.1)
	body_mesh.add_child(cabin)

	var w_offsets: Array[Vector3] = [
		Vector3(-0.95, 0.36, -1.35), Vector3(0.95, 0.36, -1.35),
		Vector3(-0.95, 0.36,  1.35), Vector3(0.95, 0.36,  1.35)
	]
	var w_arr: Array[VehicleWheel3D] = []
	for i in range(4):
		var w: VehicleWheel3D = VehicleWheel3D.new()
		w.position = w_offsets[i]
		w.use_as_steering = (i < 2)
		w.use_as_traction = (i >= 2) or (config and config.all_wheel_drive)
		w.wheel_radius = 0.36
		w.wheel_rest_length = 0.15
		w.suspension_travel = 0.2
		w.suspension_stiffness = 42.0
		w.wheel_friction_slip = 2.6
		add_child(w)
		w_arr.append(w)

	wheel_fl = w_arr[0]; wheel_fr = w_arr[1]; wheel_rl = w_arr[2]; wheel_rr = w_arr[3]
	exit_marker = Marker3D.new(); exit_marker.position = Vector3(-1.6, 0.5, 0.0); add_child(exit_marker)
	vehicle_camera = Camera3D.new(); vehicle_camera.fov = 74.0; vehicle_camera.position = Vector3(0.0, 2.3, 5.4); vehicle_camera.rotation_degrees = Vector3(-12.0, 0.0, 0.0); add_child(vehicle_camera)
'@

Install-SolaraModule -RelPath "src/entities/ai/pedestrian_ai.gd" -Category "Essential" -Content @'
class_name PedestrianAI
extends CharacterBody3D
var nav_agent: NavigationAgent3D
var visual_mesh: Node3D
var current_health: float = 60.0
var _walk_angle: float = 0.0
func _ready() -> void:
	add_to_group("pedestrians")
	_walk_angle = randf() * TAU
func _physics_process(delta: float) -> void:
	if current_health <= 0.0: return
	if not is_on_floor(): velocity.y -= 9.8 * delta
	velocity.x = cos(_walk_angle) * 1.8
	velocity.z = sin(_walk_angle) * 1.8
	move_and_slide()
	if is_on_wall(): _walk_angle += PI * 0.65
func apply_damage(amount: float, _pos: Vector3 = Vector3.ZERO) -> void:
	current_health -= amount
	if current_health <= 0.0: queue_free()
'@

Install-SolaraModule -RelPath "src/entities/ai/hostile_guard_ai.gd" -Category "Essential" -Content @'
class_name HostileGuardAI
extends CharacterBody3D
enum GuardState { IDLE, PATROL, COMBAT, DEAD }
var current_state: GuardState = GuardState.PATROL
var max_health: float = 120.0
var current_health: float = 120.0
var damage_per_shot: float = 8.0
var shots_per_burst: int = 3
var base_hit_chance: float = 0.6
var detection_range: float = 36.0
var home_post_position: Vector3 = Vector3.ZERO
var alert_callouts: PackedStringArray = PackedStringArray()
var visual_mesh: Node3D
var _fire_timer: float = 1.5

func _ready() -> void:
	add_to_group("hostile_guards")
	if not visual_mesh:
		visual_mesh = Node3D.new()
		visual_mesh.name = "VisualMesh"
		add_child(visual_mesh)
		var m: MeshInstance3D = MeshInstance3D.new()
		var cap: CapsuleMesh = CapsuleMesh.new()
		cap.radius = 0.36; cap.height = 1.78
		m.mesh = cap; m.position = Vector3(0.0, 0.89, 0.0)
		visual_mesh.add_child(m)
		var col: CollisionShape3D = CollisionShape3D.new()
		var cs: CapsuleShape3D = CapsuleShape3D.new()
		cs.radius = 0.36; cs.height = 1.78
		col.shape = cs; col.position = Vector3(0.0, 0.89, 0.0)
		add_child(col)

func _physics_process(delta: float) -> void:
	if current_state == GuardState.DEAD: return
	if not is_on_floor(): velocity.y -= 9.8 * delta
	var p: PlayerController = get_tree().get_first_node_in_group("player") as PlayerController
	if p and global_position.distance_to(p.global_position) <= detection_range:
		current_state = GuardState.COMBAT
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_fire_timer = randf_range(1.2, 2.0)
			SpatialAudioManager.play_gunshot_3d(global_position + Vector3(0.0, 1.4, 0.0))
			if randf() < base_hit_chance:
				p.apply_damage(damage_per_shot)
	move_and_slide()

func receive_squad_alert(_pos: Vector3) -> void:
	if current_state != GuardState.DEAD:
		current_state = GuardState.COMBAT

func apply_damage(amount: float, _hit_pos: Vector3 = Vector3.ZERO) -> void:
	if current_state == GuardState.DEAD: return
	current_health = maxf(0.0, current_health - amount)
	current_state = GuardState.COMBAT
	if current_health <= 0.0:
		current_state = GuardState.DEAD
		GameState.modify_cash(150)
		queue_free()
'@

# ==============================================================================
# 5. STUFE 3: ABGELEITETE FAHRZEUGE, BOOTE, HELIKOPTER, SNIPER & POLIZEI
# ==============================================================================
Install-SolaraModule -RelPath "src/entities/ai/racer_ai.gd" -Category "Essential" -Content @'
class_name RacerAI
extends ArcadeVehicle
var countdown_locked: bool = false
'@

Install-SolaraModule -RelPath "src/entities/ai/police_ai.gd" -Category "Essential" -Content @'
class_name PoliceAI
extends ArcadeVehicle
var target_node: Node3D = null
'@

Install-SolaraModule -RelPath "src/entities/ai/swat_enforcer_ai.gd" -Category "Essential" -Content @'
class_name SWATEnforcerAI
extends ArcadeVehicle
var has_swat_driver: bool = true
func _ready() -> void:
	super._ready()
	add_to_group("swat_vehicles")
	apply_custom_paint(Color(0.08, 0.10, 0.16), 0.85, 0.25)
func _build_procedural_swat_trooper() -> HostileGuardAI:
	return HostileGuardAI.new()
'@

Install-SolaraModule -RelPath "src/entities/vehicles/traffic_vehicle_ai.gd" -Category "Essential" -Content @'
class_name TrafficVehicleAI
extends ArcadeVehicle
var assigned_path: Path3D = null
var path_offset: float = 0.0
var driver_pedestrian_scene: PackedScene = null
var _panic_mode: bool = false
func _ready() -> void:
	super._ready()
	add_to_group("traffic_vehicles")
func trigger_traffic_panic() -> void:
	_panic_mode = true
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if driver != null or is_destroyed or not is_instance_valid(assigned_path) or not assigned_path.curve:
		return
	var spd: float = 22.0 if _panic_mode else 12.5
	path_offset = fmod(path_offset + spd * delta, assigned_path.curve.get_baked_length())
	var target_xform: Transform3D = assigned_path.global_transform * assigned_path.curve.sample_baked_with_rotation(path_offset, true)
	target_xform.origin.y = global_position.y
	global_transform = global_transform.interpolate_with(target_xform, 8.0 * delta)
'@

Install-SolaraModule -RelPath "src/audio/radio_station.gd" -Category "Optional" -Content @'
class_name RadioStation
extends Resource
@export var station_name: String = "Neon Synth FM 88.4"
@export var genre: String = "Synthwave / Outrun"
@export var base_bpm: float = 118.0
'@

Install-SolaraModule -RelPath "src/audio/in_car_radio.gd" -Category "Optional" -Content @'
class_name InCarRadio
extends AudioStreamPlayer
signal station_changed(station_title: String)
var stations: Array[String] = ["RADIO AUS", "NEON SYNTH FM 88.4", "SOLARA BASS FM 104.2", "CYBERWAVE RETRO 96.0"]
var current_index: int = 1
func _ready() -> void:
	bus = "Music"
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("radio_next"):
		cycle_station()
func cycle_station() -> void:
	current_index = (current_index + 1) % stations.size()
	station_changed.emit(stations[current_index])
	MissionManager.dialogue_triggered.emit("Bordradio [Q]", "Sender: " + stations[current_index])
'@

Install-SolaraModule -RelPath "src/audio/police_siren_3d.gd" -Category "Optional" -Content @'
class_name PoliceSiren3D
extends AudioStreamPlayer3D
var siren_active: bool = false
func _ready() -> void:
	bus = "SFX"
	max_distance = 140.0
'@

Install-SolaraModule -RelPath "src/entities/weapons/frag_grenade.gd" -Category "Optional" -Content @'
class_name FragGrenade
extends RigidBody3D
signal detonated(world_pos: Vector3)
@export var fuse_time_sec: float = 2.8
@export var blast_radius: float = 9.5
@export var max_blast_damage: float = 180.0
func _ready() -> void:
	get_tree().create_timer(fuse_time_sec).timeout.connect(_explode)
func _explode() -> void:
	SpatialAudioManager.play_collision_impact_3d(global_position, 95.0)
	detonated.emit(global_position)
	queue_free()
'@

Install-SolaraModule -RelPath "src/entities/ai/police_helicopter_ai.gd" -Category "Optional" -Content @'
class_name PoliceHelicopterAI
extends Node3D
var current_health: float = 650.0
func _ready() -> void:
	add_to_group("police_helicopters")
func apply_damage(amount: float, _pos: Vector3 = Vector3.ZERO) -> void:
	current_health -= amount
	if current_health <= 0.0:
		SpatialAudioManager.play_collision_impact_3d(global_position, 95.0)
		GameState.modify_cash(1200)
		queue_free()
'@

Install-SolaraModule -RelPath "src/entities/ai/police_spike_strip.gd" -Category "Optional" -Content @'
class_name PoliceSpikeStrip
extends Area3D
func _ready() -> void:
	add_to_group("spike_strips")
	body_entered.connect(func(b: Node3D):
		if b is ArcadeVehicle:
			(b as ArcadeVehicle).apply_damage(140.0, global_position)
	)
'@

Install-SolaraModule -RelPath "src/entities/ai/police_roadblock.gd" -Category "Optional" -Content @'
class_name PoliceRoadblock
extends Node3D
func _ready() -> void:
	add_to_group("police_roadblocks")
'@

Install-SolaraModule -RelPath "src/entities/vehicles/armored_cash_truck.gd" -Category "Optional" -Content @'
class_name ArmoredCashTruck
extends ArcadeVehicle
signal vault_breached(truck: ArmoredCashTruck)
signal truck_fenced_at_garage(payout: int)
var has_ai_driver: bool = true
var _breached: bool = false
func _ready() -> void:
	super._ready()
	add_to_group("armored_cash_trucks")
	max_vehicle_health = 2400.0
	current_health = 2400.0
	apply_custom_paint(Color(0.12, 0.22, 0.35), 0.9, 0.2)
	var lbl: Label3D = Label3D.new()
	lbl.text = "SOLARA GELDTRANSPORTER ($ 4,500 BEUTE)\n[Heckpanzerung beschiessen oder kapern!]"
	lbl.font_size = 30; lbl.modulate = Color(1.0, 0.85, 0.2); lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0.0, 2.6, 0.0); add_child(lbl)
func apply_damage(amount: float, hit_pos: Vector3 = Vector3.ZERO) -> void:
	super.apply_damage(amount, hit_pos)
	if not _breached and current_health <= max_vehicle_health * 0.55:
		_breached = true
		GameState.modify_cash(4500)
		WantedManager.set_minimum_stars(3)
		MissionManager.mission_completed.emit("GELDTRANSPORTER AUFGEBROCHEN!", 4500)
		vault_breached.emit(self)
static func spawn_convoy_on_traffic_paths(spawner: Node3D) -> void:
	if not spawner: return
	var truck: ArmoredCashTruck = ArmoredCashTruck.new()
	spawner.add_child(truck)
	truck.global_position = Vector3(-42.0, 0.6, 20.0)
'@

Install-SolaraModule -RelPath "src/entities/vehicles/speedboat_controller.gd" -Category "Optional" -Content @'
class_name SpeedboatController
extends ArcadeVehicle

signal boat_airborne(speed_kmh: float)
enum BoatVariant { SMUGGLER_STINGER, POLICE_INTERCEPTOR }

const SEA_LEVEL_Y: float = -0.85
const WATER_DENSITY_FORCE: float = 11500.0
const HYDRO_LINEAR_DRAG: float = 1.65
const HYDRO_ANGULAR_DRAG: float = 4.2

@export var boat_variant: BoatVariant = BoatVariant.SMUGGLER_STINGER
@export var max_jet_thrust: float = 24500.0
@export var reverse_jet_thrust: float = 11000.0
@export var rudder_torque_strength: float = 9500.0

var _wave_time: float = 0.0
var _submerged_probes_count: int = 0
var _buoyancy_offsets: Array[Vector3] = [
	Vector3(-1.05, -0.35, -2.65), Vector3(1.05, -0.35, -2.65),
	Vector3(-1.15, -0.40,  2.45), Vector3(1.15, -0.40,  2.45)
]

func _ready() -> void:
	if not config: config = _create_boat_config()
	if not wheel_fl: _build_procedural_boat_hull()
	super._ready()
	add_to_group("speedboats")
	max_vehicle_health = 1650.0; current_health = max_vehicle_health
	apply_custom_paint(Color(0.06, 0.85, 0.98) if boat_variant == BoatVariant.SMUGGLER_STINGER else Color(0.08, 0.12, 0.22), 0.88, 0.14)
	set_underglow(true, Color(0.0, 0.95, 1.0))

func _process(delta: float) -> void:
	_wave_time = fmod(_wave_time + delta * 2.4, TAU * 10.0)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_destroyed: return
	_submerged_probes_count = 0
	for local_pt in _buoyancy_offsets:
		var world_pt: Vector3 = to_global(local_pt)
		var depth: float = get_wave_height_at(world_pt.x, world_pt.z) - world_pt.y
		if depth > 0.0:
			_submerged_probes_count += 1
			var rel_pos: Vector3 = world_pt - global_position
			var point_vel: Vector3 = linear_velocity + angular_velocity.cross(rel_pos)
			apply_force(Vector3(0.0, maxf(0.0, clampf(depth * WATER_DENSITY_FORCE, 0.0, WATER_DENSITY_FORCE * 1.6) - point_vel.y * mass * 2.4), 0.0), rel_pos)
	if _submerged_probes_count > 0:
		var r: float = float(_submerged_probes_count) / 4.0
		apply_central_force(-linear_velocity * HYDRO_LINEAR_DRAG * mass * 0.35 * r)
		apply_torque(-angular_velocity * HYDRO_ANGULAR_DRAG * mass * 0.45 * r)
		var throttle_in: float = Input.get_axis("move_back", "move_forward") if driver != null else 0.0
		var steer_in: float = Input.get_axis("move_right", "move_left") if driver != null else 0.0
		var fwd: Vector3 = -global_transform.basis.z; fwd.y = 0.0; fwd = fwd.normalized()
		apply_force(fwd * throttle_in * max_jet_thrust * engine_upgrade_multiplier, global_transform.basis.z * 2.4)
		apply_torque(Vector3.UP * steer_in * rudder_torque_strength * clampf(current_speed_kmh / 35.0, 0.25, 1.35))
	elif current_speed_kmh > 75.0:
		boat_airborne.emit(current_speed_kmh)

func get_wave_height_at(wx: float, wz: float) -> float:
	return SEA_LEVEL_Y + sin(wx * 0.18 + _wave_time * 1.3) * 0.22 + cos(wz * 0.24 - _wave_time * 0.95) * 0.16

func _create_boat_config() -> VehicleConfig:
	var cfg: VehicleConfig = VehicleConfig.new()
	cfg.vehicle_name = "Solara Stinger 380"; cfg.top_speed_kmh = 195.0; cfg.vehicle_mass = 1450.0; cfg.max_engine_force = 0.0
	return cfg

func _build_procedural_boat_hull() -> void:
	var col: CollisionShape3D = CollisionShape3D.new(); var bs: BoxShape3D = BoxShape3D.new(); bs.size = Vector3(2.45, 1.15, 6.4); col.shape = bs; col.position = Vector3(0.0, 0.45, 0.0); add_child(col)
	body_mesh = MeshInstance3D.new(); var hb: BoxMesh = BoxMesh.new(); hb.size = Vector3(2.35, 0.85, 5.8); body_mesh.mesh = hb; body_mesh.position = Vector3(0.0, 0.42, 0.2); add_child(body_mesh)
	var wheels: Array[VehicleWheel3D] = []
	for p in [Vector3(-1, -0.3, -2), Vector3(1, -0.3, -2), Vector3(-1, -0.3, 2), Vector3(1, -0.3, 2)]:
		var w: VehicleWheel3D = VehicleWheel3D.new(); w.position = p; w.wheel_radius = 0.25; add_child(w); wheels.append(w)
	wheel_fl = wheels[0]; wheel_fr = wheels[1]; wheel_rl = wheels[2]; wheel_rr = wheels[3]
	exit_marker = Marker3D.new(); exit_marker.position = Vector3(1.85, 1.15, 0.0); add_child(exit_marker)
	vehicle_camera = Camera3D.new(); vehicle_camera.fov = 76.0; vehicle_camera.position = Vector3(0.0, 2.75, 6.4); vehicle_camera.rotation_degrees = Vector3(-12.0, 0.0, 0.0); add_child(vehicle_camera)

static func spawn_harbor_marina_and_boats(world_root: Node) -> void:
	if not world_root or world_root.has_node("SolaraHarborMarina"): return
	var marina: Node3D = Node3D.new(); marina.name = "SolaraHarborMarina"; world_root.add_child(marina)
	var water_mi: MeshInstance3D = MeshInstance3D.new(); var pl: PlaneMesh = PlaneMesh.new(); pl.size = Vector2(360.0, 320.0)
	var wm: StandardMaterial3D = StandardMaterial3D.new(); wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; wm.albedo_color = Color(0.03, 0.16, 0.28, 0.88)
	pl.material = wm; water_mi.mesh = pl; water_mi.position = Vector3(-290.0, SEA_LEVEL_Y, 195.0); marina.add_child(water_mi)
	var stinger: SpeedboatController = SpeedboatController.new(); stinger.name = "Speedboat_SmugglerStinger"; marina.add_child(stinger)
	stinger.global_position = Vector3(-225.2, SEA_LEVEL_Y + 0.35, 148.0)
'@

Install-SolaraModule -RelPath "src/entities/vehicles/skyhawk_helicopter.gd" -Category "Optional" -Content @'
class_name SkyhawkHelicopter
extends ArcadeVehicle

signal altitude_changed(altitude_m: float, vertical_speed_ms: float)
signal hover_lock_toggled(is_locked: bool)
signal helipad_landed(chopper: SkyhawkHelicopter)

enum ChopperVariant { EXECUTIVE_SKYHAWK, VALKYRIE_GUNSHIP }
const SAFEHOUSE_HELIPAD_POS: Vector3 = Vector3(25.0, 10.5, 26.0)

@export var chopper_variant: ChopperVariant = ChopperVariant.VALKYRIE_GUNSHIP
var is_hover_locked: bool = false
var _rotor_rpm_ratio: float = 0.0
var _target_yaw_rad: float = 0.0
var _locked_altitude_y: float = 15.0
var _main_rotor_pivot: Node3D
var _tail_rotor_pivot: Node3D

func _ready() -> void:
	if not config:
		config = VehicleConfig.new()
		config.vehicle_name = "Valkyrie Tactical Gunship"
		config.vehicle_mass = 1650.0
	if not wheel_fl: _build_procedural_helicopter_geometry()
	super._ready()
	add_to_group("player_helicopters")
	max_vehicle_health = 2100.0; current_health = max_vehicle_health
	_target_yaw_rad = global_rotation.y
	apply_custom_paint(Color(0.10, 0.14, 0.20), 0.82, 0.22)
	set_underglow(true, Color(0.15, 0.92, 1.0))

func set_driver(new_driver: PlayerController) -> void:
	super.set_driver(new_driver)
	_target_yaw_rad = global_rotation.y
	if new_driver != null:
		MissionManager.dialogue_triggered.emit("Solara Avionics", "Turbine läuft! [Leertaste] Steigen, [Shift] Sinken, [WASD] Steuern, [H] Hover-Lock.")

func _unhandled_input(event: InputEvent) -> void:
	if driver == null or is_destroyed: return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_H:
		is_hover_locked = not is_hover_locked
		_locked_altitude_y = global_position.y
		hover_lock_toggled.emit(is_hover_locked)

func _process(delta: float) -> void:
	var target_rpm: float = 1.0 if driver != null else 0.0
	_rotor_rpm_ratio = move_toward(_rotor_rpm_ratio, target_rpm, delta * 0.45)
	if _main_rotor_pivot: _main_rotor_pivot.rotate_y(delta * 34.0 * _rotor_rpm_ratio)
	if _tail_rotor_pivot: _tail_rotor_pivot.rotate_x(delta * 46.0 * _rotor_rpm_ratio)
	if driver != null: altitude_changed.emit(global_position.y, linear_velocity.y)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	engine_force = 0.0; brake = 10.0 if driver == null else 0.0
	if is_destroyed or _rotor_rpm_ratio < 0.25: return
	var pitch_in: float = Input.get_axis("move_back", "move_forward") if driver != null else 0.0
	var yaw_in: float = Input.get_axis("move_right", "move_left") if driver != null else 0.0
	var climb_in: float = 0.0
	if driver != null:
		if Input.is_action_pressed("jump"): climb_in += 1.0; is_hover_locked = false
		if Input.is_action_pressed("sprint"): climb_in -= 1.0; is_hover_locked = false
	var target_vy: float = climb_in * 16.0
	if is_hover_locked and absf(climb_in) < 0.05: target_vy = clampf((_locked_altitude_y - global_position.y) * 2.5, -6.0, 6.0)
	apply_central_force(Vector3.UP * maxf(0.0, mass * (9.8 + (target_vy - linear_velocity.y) * 4.2)))
	var fwd: Vector3 = -global_transform.basis.z; fwd.y = 0.0; fwd = fwd.normalized()
	apply_central_force((fwd * (pitch_in * 44.0) - Vector3(linear_velocity.x, 0.0, linear_velocity.z)) * mass * 1.65)
	_target_yaw_rad += yaw_in * 1.68 * delta
	var target_basis: Basis = Basis.from_euler(Vector3(deg_to_rad(-pitch_in * 20.0), _target_yaw_rad, deg_to_rad(yaw_in * 22.0)))
	var q: Quaternion = (target_basis * global_transform.basis.orthonormalized().inverse()).get_rotation_quaternion()
	if q.w < 0.0: q = -q
	if q.get_axis().is_normalized() and q.get_angle() > 0.001:
		apply_torque((q.get_axis() * q.get_angle() * 14.0 - angular_velocity * 5.5) * mass)

func _build_procedural_helicopter_geometry() -> void:
	var col: CollisionShape3D = CollisionShape3D.new(); var bs: BoxShape3D = BoxShape3D.new(); bs.size = Vector3(2.2, 2.1, 5.4); col.shape = bs; col.position = Vector3(0.0, 1.15, 0.0); add_child(col)
	body_mesh = MeshInstance3D.new(); var hb: BoxMesh = BoxMesh.new(); hb.size = Vector3(1.95, 1.55, 4.2); body_mesh.mesh = hb; body_mesh.position = Vector3(0.0, 1.35, -0.2); add_child(body_mesh)
	_main_rotor_pivot = Node3D.new(); _main_rotor_pivot.position = Vector3(0.0, 2.38, -0.2); add_child(_main_rotor_pivot)
	var b1: MeshInstance3D = MeshInstance3D.new(); var bm1: BoxMesh = BoxMesh.new(); bm1.size = Vector3(9.4, 0.04, 0.34); b1.mesh = bm1; _main_rotor_pivot.add_child(b1)
	_tail_rotor_pivot = Node3D.new(); _tail_rotor_pivot.position = Vector3(0.34, 1.95, 5.55); add_child(_tail_rotor_pivot)
	var wheels: Array[VehicleWheel3D] = []
	for pt in [Vector3(-1, 0.25, -1.8), Vector3(1, 0.25, -1.8), Vector3(-1, 0.25, 1.4), Vector3(1, 0.25, 1.4)]:
		var w: VehicleWheel3D = VehicleWheel3D.new(); w.position = pt; w.wheel_radius = 0.22; add_child(w); wheels.append(w)
	wheel_fl = wheels[0]; wheel_fr = wheels[1]; wheel_rl = wheels[2]; wheel_rr = wheels[3]
	exit_marker = Marker3D.new(); exit_marker.position = Vector3(-2.35, 0.5, -0.4); add_child(exit_marker)
	vehicle_camera = Camera3D.new(); vehicle_camera.fov = 76.0; vehicle_camera.position = Vector3(0.0, 3.8, 9.2); vehicle_camera.rotation_degrees = Vector3(-14.0, 0.0, 0.0); add_child(vehicle_camera)

static func spawn_safehouse_helipad_and_chopper(world_root: Node) -> SkyhawkHelicopter:
	if not world_root: return null
	var existing: Node = world_root.get_node_or_null("SafehouseHelipadComplex")
	if existing: return existing.find_child("Skyhawk_*", true, false) as SkyhawkHelicopter
	var complex: Node3D = Node3D.new(); complex.name = "SafehouseHelipadComplex"; world_root.add_child(complex)
	var pad_pos: Vector3 = SAFEHOUSE_HELIPAD_POS
	var pad_body: StaticBody3D = StaticBody3D.new(); pad_body.position = pad_pos; complex.add_child(pad_body)
	var dm: MeshInstance3D = MeshInstance3D.new(); var db: BoxMesh = BoxMesh.new(); db.size = Vector3(14.5, 0.5, 14.5); dm.mesh = db; pad_body.add_child(dm)
	var dc: CollisionShape3D = CollisionShape3D.new(); var cb: BoxShape3D = BoxShape3D.new(); cb.size = Vector3(14.5, 0.5, 14.5); dc.shape = cb; pad_body.add_child(dc)
	_create_elevator_portal(complex, "GroundToRoofElevator", Vector3(31.8, 0.15, 24.5), pad_pos + Vector3(5.8, 0.6, 5.2), "EXPRESS-AUFZUG ZUM DACH-HELIPAD")
	_create_elevator_portal(complex, "RoofToGroundElevator", pad_pos + Vector3(5.8, 0.3, 5.8), Vector3(31.8, 0.5, 22.0), "AUFZUG ZUM ERDGESCHOSS")
	var chopper: SkyhawkHelicopter = SkyhawkHelicopter.new(); chopper.name = "Skyhawk_SafehouseChopper"; complex.add_child(chopper)
	chopper.global_position = pad_pos + Vector3(0.0, 0.85, 0.0)
	return chopper

static func _create_elevator_portal(parent: Node3D, node_name: String, trigger_pos: Vector3, destination_pos: Vector3, label_txt: String) -> void:
	var area: Area3D = Area3D.new(); area.name = node_name; area.position = trigger_pos; parent.add_child(area)
	var col: CollisionShape3D = CollisionShape3D.new(); var cyl: CylinderShape3D = CylinderShape3D.new(); cyl.radius = 1.35; cyl.height = 2.2; col.shape = cyl; area.add_child(col)
	var lbl: Label3D = Label3D.new(); lbl.text = label_txt; lbl.font_size = 28; lbl.modulate = Color(0.2, 0.98, 0.65); lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lbl.position = Vector3(0.0, 2.2, 0.0); area.add_child(lbl)
	area.body_entered.connect(func(body: Node3D):
		if body is PlayerController and not (body as PlayerController).is_in_vehicle:
			(body as PlayerController).velocity = Vector3.ZERO
			(body as PlayerController).global_position = destination_pos
	)
'@

Install-SolaraModule -RelPath "src/entities/weapons/sniper_scope_controller.gd" -Category "Optional" -Content @'
class_name SniperScopeController
extends CanvasLayer

signal scope_toggled(is_scoped: bool, current_zoom: float)
signal zoom_level_changed(zoom_multiplier: float, target_fov: float)

const SNIPER_SLOT_INDEX: int = 4
const ZOOM_FOV_STEPS: Array[float] = [32.0, 14.0, 7.0]
const ZOOM_LABELS: Array[String] = ["2.5x TAKTISCH", "6.0x PRAEZISION", "12.0x LANGSTRECKE"]

var is_scope_active: bool = false
var current_zoom_index: int = 1
var _saved_mouse_sens: float = 0.0022
var _is_breath_slowmo: bool = false
var _reticle_label: Label

func _ready() -> void:
	layer = 11
	add_to_group("sniper_scope_controller")
	_reticle_label = Label.new()
	_reticle_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_reticle_label.position = Vector2(-160, 80)
	_reticle_label.visible = false
	_reticle_label.modulate = Color(0.18, 0.95, 1.0)
	add_child(_reticle_label)

func _exit_tree() -> void:
	if _is_breath_slowmo: Engine.time_scale = 1.0

func _process(delta: float) -> void:
	var unscaled_delta: float = delta / maxf(0.05, Engine.time_scale)
	var player: PlayerController = get_tree().get_first_node_in_group("player") as PlayerController
	if not player: return
	var wh: WeaponHandler = player.get_node_or_null("WeaponHandler") as WeaponHandler
	var should_scope: bool = (wh != null and wh.current_slot == SNIPER_SLOT_INDEX and not player.is_in_vehicle and Input.is_action_pressed("aim") and not get_tree().paused)

	if should_scope and not is_scope_active:
		is_scope_active = true; _saved_mouse_sens = player.mouse_sensitivity; _reticle_label.visible = true
		if player.visual_mesh: player.visual_mesh.visible = false
		scope_toggled.emit(true, ZOOM_FOV_STEPS[current_zoom_index])
	elif not should_scope and is_scope_active:
		is_scope_active = false; _reticle_label.visible = false
		if _is_breath_slowmo: _is_breath_slowmo = false; Engine.time_scale = 1.0
		player.mouse_sensitivity = _saved_mouse_sens
		if player.visual_mesh: player.visual_mesh.visible = true
		if player.camera: player.camera.fov = player.normal_fov
		scope_toggled.emit(false, 75.0)

	if is_scope_active:
		var target_fov: float = ZOOM_FOV_STEPS[current_zoom_index]
		if player.camera: player.camera.fov = lerpf(player.camera.fov, target_fov, 16.0 * unscaled_delta)
		player.mouse_sensitivity = _saved_mouse_sens * (target_fov / 75.0)
		var hold_breath: bool = Input.is_action_pressed("sprint")
		if hold_breath and not _is_breath_slowmo: _is_breath_slowmo = true; Engine.time_scale = 0.45
		elif not hold_breath and _is_breath_slowmo: _is_breath_slowmo = false; Engine.time_scale = 1.0
		_reticle_label.text = "[ MIL-DOT VISIER // %s // [V/Mausrad] Zoom ]" % ZOOM_LABELS[current_zoom_index]

func _unhandled_input(event: InputEvent) -> void:
	if not is_scope_active: return
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_V):
		current_zoom_index = (current_zoom_index + 1) % ZOOM_FOV_STEPS.size()
		zoom_level_changed.emit(float(current_zoom_index + 1), ZOOM_FOV_STEPS[current_zoom_index])
'@

# ==============================================================================
# 6. STUFE 4: WELT-STRUKTUR, SHOPS & ALLE 17 OPTIONALEN OPEN-WORLD-SYSTEME
# ==============================================================================
Install-SolaraModule -RelPath "src/world/environment_cycle.gd" -Category "Essential" -Content @'
class_name EnvironmentCycle
extends Node3D
signal night_state_changed(is_night: bool)
signal time_updated(hour: int, minute: int)
enum WeatherType { CLEAR, RAIN, NEON_STORM }
var sun_light: DirectionalLight3D
var world_environment: WorldEnvironment
var rain_particles: GPUParticles3D
var weather_audio: AudioStreamPlayer
var current_time_hours: float = 21.5
var is_night: bool = true
func _ready() -> void:
	add_to_group("environment_controller")
	_update_celestial_bodies(0.0, true)
func _process(delta: float) -> void:
	current_time_hours = fmod(current_time_hours + delta * 0.04, 24.0)
	_update_celestial_bodies(delta, false)
func _update_celestial_bodies(_delta: float, force: bool) -> void:
	var night_now: bool = (current_time_hours < 6.0 or current_time_hours >= 19.0)
	if night_now != is_night or force:
		is_night = night_now
		night_state_changed.emit(is_night)
	if sun_light:
		var angle: float = ((current_time_hours - 6.0) / 24.0) * 360.0
		sun_light.rotation_degrees = Vector3(-angle, -35.0, 0.0)
		sun_light.light_energy = 0.18 if is_night else 1.25
	RenderingServer.global_shader_parameter_set("global_time_of_day", current_time_hours)
	time_updated.emit(int(current_time_hours), int(fmod(current_time_hours, 1.0) * 60.0))
func set_weather(w_type: WeatherType) -> void:
	if rain_particles: rain_particles.emitting = (w_type != WeatherType.CLEAR)
	RenderingServer.global_shader_parameter_set("global_rain_wetness", 0.0 if w_type == WeatherType.CLEAR else 0.85)
'@

Install-SolaraModule -RelPath "src/world/city_block_builder.gd" -Category "Essential" -Content @'
class_name CityBlockBuilder
extends Node3D

var streetlights_container: Node3D
var traffic_paths_container: Node3D
var parked_spawns_container: Node3D

func build_complete_district() -> void:
	streetlights_container = Node3D.new(); streetlights_container.name = "StreetLights"; add_child(streetlights_container)
	traffic_paths_container = Node3D.new(); traffic_paths_container.name = "TrafficPaths"; add_child(traffic_paths_container)
	parked_spawns_container = Node3D.new(); parked_spawns_container.name = "ParkedVehicleSpawns"; add_child(parked_spawns_container)

	var city_static: StaticBody3D = StaticBody3D.new(); city_static.name = "NeonHarborStaticGeometry"; add_child(city_static)
	var ground_mat: StandardMaterial3D = StandardMaterial3D.new(); ground_mat.albedo_color = Color(0.08, 0.09, 0.12); ground_mat.roughness = 0.45; ground_mat.metallic = 0.25
	var g_mesh: MeshInstance3D = MeshInstance3D.new(); var g_box: BoxMesh = BoxMesh.new(); g_box.size = Vector3(520.0, 1.0, 520.0); g_box.material = ground_mat; g_mesh.mesh = g_box; g_mesh.position = Vector3(0.0, -0.5, 0.0); city_static.add_child(g_mesh)
	var g_col: CollisionShape3D = CollisionShape3D.new(); var gc_box: BoxShape3D = BoxShape3D.new(); gc_box.size = Vector3(520.0, 1.0, 520.0); g_col.shape = gc_box; g_col.position = Vector3(0.0, -0.5, 0.0); city_static.add_child(g_col)

	var neon_colors: Array[Color] = [Color(0.15, 0.92, 1.0), Color(1.0, 0.18, 0.72), Color(1.0, 0.78, 0.15), Color(0.2, 0.98, 0.55)]
	var block_centers: Array[float] = [-115.0, -42.0, 48.0, 125.0]
	var idx: int = 0
	for bx in block_centers:
		for bz in block_centers:
			if bx < -80.0 and bz > 80.0: continue
			var h: float = 18.0 + float((idx * 11) % 32)
			var b_mat: StandardMaterial3D = StandardMaterial3D.new(); b_mat.albedo_color = Color(0.11, 0.13, 0.18); b_mat.roughness = 0.3; b_mat.metallic = 0.6
			var tower: MeshInstance3D = MeshInstance3D.new(); var t_box: BoxMesh = BoxMesh.new(); t_box.size = Vector3(24.0, h, 24.0); t_box.material = b_mat; tower.mesh = t_box; tower.position = Vector3(bx, h * 0.5, bz); city_static.add_child(tower)
			var t_col: CollisionShape3D = CollisionShape3D.new(); var tc_box: BoxShape3D = BoxShape3D.new(); tc_box.size = Vector3(24.0, h, 24.0); t_col.shape = tc_box; t_col.position = tower.position; city_static.add_child(t_col)
			var crown: MeshInstance3D = MeshInstance3D.new(); var cr_box: BoxMesh = BoxMesh.new(); cr_box.size = Vector3(24.4, 0.45, 24.4)
			var n_mat: StandardMaterial3D = StandardMaterial3D.new(); n_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; n_mat.albedo_color = neon_colors[idx % neon_colors.size()]
			cr_box.material = n_mat; crown.mesh = cr_box; crown.position = Vector3(bx, h - 0.3, bz); city_static.add_child(crown)
			idx += 1

	var loop_path: Path3D = Path3D.new(); var curve: Curve3D = Curve3D.new()
	for pt in [Vector3(-78, 0, -78), Vector3(78, 0, -78), Vector3(78, 0, 78), Vector3(-78, 0, 78), Vector3(-78, 0, -78)]: curve.add_point(pt)
	loop_path.curve = curve; traffic_paths_container.add_child(loop_path)
	for px in [-60.0, -20.0, 20.0, 60.0]:
		var m: Marker3D = Marker3D.new(); m.position = Vector3(px, 0.55, 6.0); parked_spawns_container.add_child(m)
'@

Install-SolaraModule -RelPath "src/world/mission_trigger.gd" -Category "Essential" -Content @'
class_name MissionTrigger
extends Area3D
@export var mission_id: String = "m01_neon_delivery"
func _ready() -> void:
	body_entered.connect(func(b: Node3D):
		if b is PlayerController or (b is ArcadeVehicle and (b as ArcadeVehicle).driver != null):
			MissionManager.start_mission(mission_id)
	)
'@

Install-SolaraModule -RelPath "src/world/mod_shop.gd" -Category "Essential" -Content @'
class_name ModShop
extends Node3D
func _ready() -> void:
	var area: Area3D = Area3D.new(); add_child(area)
	var col: CollisionShape3D = CollisionShape3D.new(); var cyl: CylinderShape3D = CylinderShape3D.new(); cyl.radius = 4.0; cyl.height = 3.0; col.shape = cyl; area.add_child(col)
	var lbl: Label3D = Label3D.new(); lbl.text = "MARCUS CUSTOM TUNING & REPAIR\n[Mit Fahrzeug einfahren = Vollreparatur & Stage-3-Tuning]"; lbl.font_size = 32; lbl.modulate = Color(1.0, 0.25, 0.85); lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lbl.position = Vector3(0.0, 3.2, 0.0); add_child(lbl)
	area.body_entered.connect(func(b: Node3D):
		if b is ArcadeVehicle and (b as ArcadeVehicle).driver != null:
			(b as ArcadeVehicle).apply_performance_upgrade(1.35, 0.5, true)
			(b as ArcadeVehicle).set_underglow(true, Color(1.0, 0.15, 0.85))
			MissionManager.dialogue_triggered.emit("Marcus Custom Garage", "Fahrzeug repariert und Stage-3-Tuning installiert!")
	)
'@

Install-SolaraModule -RelPath "src/world/weapon_shop.gd" -Category "Essential" -Content @'
class_name WeaponShop
extends Node3D
func _ready() -> void:
	add_to_group("weapon_shops")
	var area: Area3D = Area3D.new(); add_child(area)
	var col: CollisionShape3D = CollisionShape3D.new(); var cyl: CylinderShape3D = CylinderShape3D.new(); cyl.radius = 2.8; cyl.height = 2.5; col.shape = cyl; area.add_child(col)
	var lbl: Label3D = Label3D.new(); lbl.text = "SOLARA ARMS & TACTICAL\n[Betreten fuer Vollmunition & 100% Kevlar-Weste]"; lbl.font_size = 32; lbl.modulate = Color(1.0, 0.55, 0.15); lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lbl.position = Vector3(0.0, 3.0, 0.0); add_child(lbl)
	area.body_entered.connect(func(b: Node3D):
		if b is PlayerController:
			(b as PlayerController).restore_armor(100.0)
			(b as PlayerController).current_health = (b as PlayerController).max_health
			MissionManager.dialogue_triggered.emit("Solara Arms", "Kevlar-Weste und Magazine vollstaendig aufgefuellt!")
	)
'@

Install-SolaraModule -RelPath "src/world/safehouse_hub.gd" -Category "Essential" -Content @'
class_name SafehouseHub
extends Node3D
func _ready() -> void:
	add_to_group("safehouse_hub")
	var area: Area3D = Area3D.new(); add_child(area)
	var col: CollisionShape3D = CollisionShape3D.new(); var cyl: CylinderShape3D = CylinderShape3D.new(); cyl.radius = 3.2; cyl.height = 2.5; col.shape = cyl; area.add_child(col)
	var lbl: Label3D = Label3D.new(); lbl.text = "VANCE SAFEHOUSE & GARAGE\n[Betreten zum Speichern & Fahndung loeschen]"; lbl.font_size = 34; lbl.modulate = Color(0.2, 0.98, 0.55); lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lbl.position = Vector3(0.0, 3.2, 0.0); add_child(lbl)
	area.body_entered.connect(func(b: Node3D):
		if b is PlayerController:
			WantedManager.clear_wanted_level()
			SaveSettingsMgr.save_game_state((b as PlayerController).global_position)
			MissionManager.dialogue_triggered.emit("Safehouse", "Spielstand gespeichert & Fahndungslevel geloescht!")
	)
'@

Install-SolaraModule -RelPath "src/world/loot_pickup.gd" -Category "Essential" -Content @'
class_name LootPickup
extends Area3D
enum LootType { CASH_BUNDLE, AMMO_CRATE, MEDKIT, KEVLAR_VEST }
var loot_type: LootType = LootType.CASH_BUNDLE
var item_amount: int = 500
func _ready() -> void:
	body_entered.connect(func(b: Node3D):
		if b is PlayerController:
			GameState.modify_cash(item_amount)
			SpatialAudioManager.play_collision_impact_3d(global_position, 14.0)
			queue_free()
	)
func launch_from_origin(origin: Vector3, _floor_y: float = 0.0) -> void:
	global_position = origin + Vector3(0.0, 0.5, 0.0)
'@

Install-SolaraModule -RelPath "src/world/collectible_package.gd" -Category "Optional" -Content @'
class_name CollectiblePackage
extends Area3D
const SAVE_PATH: String = "user://collectibles_neon_harbor.json"
static var collected_package_ids: Array[String] = []
static var safehouse_supply_unlocked: bool = false
static var safehouse_hypercar_unlocked: bool = false
const NEON_HARBOR_PACKAGE_LOCATIONS: Array[Dictionary] = [
	{"id": "pkg_01", "pos": Vector3(14.0, 0.8, 32.0)}, {"id": "pkg_02", "pos": Vector3(-36.0, 0.8, 18.0)},
	{"id": "pkg_03", "pos": Vector3(-92.0, 0.8, -64.0)}, {"id": "pkg_04", "pos": Vector3(68.0, 0.8, -88.0)},
	{"id": "pkg_05", "pos": Vector3(112.0, 0.8, -14.0)}, {"id": "pkg_06", "pos": Vector3(95.0, 0.8, 86.0)}
]
var package_id: String = "pkg_01"
func _ready() -> void:
	add_to_group("collectible_packages")
	var col: CollisionShape3D = CollisionShape3D.new(); var sph: SphereShape3D = SphereShape3D.new(); sph.radius = 1.6; col.shape = sph; add_child(col)
	var m: MeshInstance3D = MeshInstance3D.new(); var prism: PrismMesh = PrismMesh.new(); prism.size = Vector3(0.75, 1.1, 0.75); m.mesh = prism; add_child(m)
	var lbl: Label3D = Label3D.new(); lbl.text = "SOLARA RELIKT (%s) [+ $ 1,000]" % package_id.to_upper(); lbl.font_size = 26; lbl.modulate = Color(0.18, 0.95, 1.0); lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lbl.position = Vector3(0.0, 1.4, 0.0); add_child(lbl)
	body_entered.connect(_on_collected)
func _process(delta: float) -> void: rotate_y(delta * 2.2)
func _on_collected(body: Node3D) -> void:
	if not (body is PlayerController or (body is ArcadeVehicle and (body as ArcadeVehicle).driver != null)): return
	if not collected_package_ids.has(package_id): collected_package_ids.append(package_id)
	GameState.modify_cash(1000)
	save_collectibles_progress()
	var ach: AchievementTracker = get_tree().get_first_node_in_group("achievement_tracker") as AchievementTracker
	if ach: ach.unlock_trophy("tr_02_relic_hunter")
	queue_free()
static func spawn_all_neon_harbor_packages(world_root: Node) -> void:
	if not world_root: return
	load_collectibles_progress()
	for spec in NEON_HARBOR_PACKAGE_LOCATIONS:
		if collected_package_ids.has(spec["id"]): continue
		var pkg: CollectiblePackage = CollectiblePackage.new(); pkg.package_id = spec["id"]; pkg.position = spec["pos"]; world_root.add_child(pkg)
static func save_collectibles_progress() -> void:
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"ids": collected_package_ids}))
static func load_collectibles_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if p is Dictionary and p.get("ids") is Array:
		collected_package_ids.clear()
		for item in p["ids"]: collected_package_ids.append(str(item))
'@

Install-SolaraModule -RelPath "src/world/stunt_jump_ramp.gd" -Category "Optional" -Content @'
class_name StuntJumpRamp
extends Node3D
static var completed_ramp_ids: Array[String] = []
var ramp_id: String = "ramp_01"
var _cooldown: float = 0.0
func _process(delta: float) -> void:
	if _cooldown > 0.0: _cooldown -= delta
static func spawn_all_neon_harbor_ramps(world_root: Node) -> void:
	if not world_root: return
	var specs: Array[Dictionary] = [{"id": "ramp_01", "pos": Vector3(0.0, 0.0, 42.0), "yaw": 0.0}, {"id": "ramp_02", "pos": Vector3(-84.0, 0.0, 48.0), "yaw": 90.0}]
	for s in specs:
		var r: StuntJumpRamp = StuntJumpRamp.new(); r.ramp_id = s["id"]; r.position = s["pos"]; r.rotation_degrees.y = float(s["yaw"]); world_root.add_child(r)
		var sb: StaticBody3D = StaticBody3D.new(); r.add_child(sb)
		var mi: MeshInstance3D = MeshInstance3D.new(); var bm: BoxMesh = BoxMesh.new(); bm.size = Vector3(5.5, 0.4, 9.0); mi.mesh = bm; mi.position = Vector3(0.0, 1.1, 0.0); mi.rotation_degrees.x = 18.0; sb.add_child(mi)
		var cs: CollisionShape3D = CollisionShape3D.new(); var bs: BoxShape3D = BoxShape3D.new(); bs.size = Vector3(5.5, 0.4, 9.0); cs.shape = bs; cs.position = mi.position; cs.rotation_degrees.x = 18.0; sb.add_child(cs)
'@

Install-SolaraModule -RelPath "src/world/speed_drift_zone.gd" -Category "Optional" -Content @'
class_name SpeedDriftZone
extends Area3D
static var zone_best_stars: Dictionary = {}
var zone_id: String = "zone_01"
var target_speed_kmh: float = 135.0
func _ready() -> void:
	add_to_group("speed_drift_zones")
	var col: CollisionShape3D = CollisionShape3D.new(); var cyl: CylinderShape3D = CylinderShape3D.new(); cyl.radius = 6.5; cyl.height = 4.0; col.shape = cyl; add_child(col)
	body_entered.connect(func(b: Node3D):
		if b is ArcadeVehicle and (b as ArcadeVehicle).driver != null and (b as ArcadeVehicle).current_speed_kmh >= target_speed_kmh:
			zone_best_stars[zone_id] = 3
			GameState.modify_cash(1500)
			MissionManager.mission_completed.emit("SPEED-TRAP GOLD!", 1500)
	)
static func spawn_all_neon_harbor_zones(world_root: Node) -> void:
	if not world_root: return
	for i in range(3):
		var z: SpeedDriftZone = SpeedDriftZone.new(); z.zone_id = "zone_0%d" % (i + 1); z.position = Vector3(-78.0 + float(i) * 78.0, 0.1, -78.0); world_root.add_child(z)
'@

Install-SolaraModule -RelPath "src/world/atm_hack_terminal.gd" -Category "Optional" -Content @'
class_name ATMHackTerminal
extends Node3D
signal atm_hack_started(id: String)
signal atm_hack_succeeded(id: String, payout: int)
signal atm_brute_forced(id: String, payout: int)
var atm_id: String = "atm_01"
var _cd: float = 0.0
func _ready() -> void:
	add_to_group("atm_terminals")
	var sb: StaticBody3D = StaticBody3D.new(); add_child(sb)
	var cs: CollisionShape3D = CollisionShape3D.new(); var bs: BoxShape3D = BoxShape3D.new(); bs.size = Vector3(1.1, 2.0, 0.8); cs.shape = bs; cs.position = Vector3(0.0, 1.0, 0.0); sb.add_child(cs)
	var area: Area3D = Area3D.new(); area.position = Vector3(0.0, 0.5, 1.1); add_child(area)
	var ac: CollisionShape3D = CollisionShape3D.new(); var sp: SphereShape3D = SphereShape3D.new(); sp.radius = 1.4; ac.shape = sp; area.add_child(ac)
	area.body_entered.connect(func(b: Node3D):
		if _cd <= 0.0 and b is PlayerController:
			_cd = 45.0; atm_hack_started.emit(atm_id); GameState.modify_cash(1400); atm_hack_succeeded.emit(atm_id, 1400)
	)
func _process(delta: float) -> void:
	if _cd > 0.0: _cd -= delta
func apply_brute_force_damage(_dmg: float) -> void:
	if _cd > 0.0: return
	_cd = 45.0; GameState.modify_cash(650); atm_brute_forced.emit(atm_id, 650)
static func spawn_all_neon_harbor_atms(world_root: Node) -> void:
	if not world_root: return
	for i in range(3):
		var atm: ATMHackTerminal = ATMHackTerminal.new(); atm.atm_id = "atm_0%d" % (i + 1); atm.position = Vector3(16.0 - float(i) * 40.0, 0.0, 22.0); world_root.add_child(atm)
'@

Install-SolaraModule -RelPath "src/world/property_tycoon.gd" -Category "Optional" -Content @'
class_name PropertyTycoon
extends Area3D
signal property_purchased(prop_id: String, title: String, price: int)
signal revenue_collected(prop_id: String, amount: int)
const SAVE_PATH: String = "user://property_empire.json"
static var owned_properties: Dictionary = {}
static var vault_balances: Dictionary = {}
var property_id: String = "prop_01"
var property_title: String = "Club Ecliptica"
var purchase_price: int = 12000
var hourly_income: int = 1200
var vault_capacity: int = 12000
var is_owned: bool = false
var current_vault_cash: int = 0
var _label_3d: Label3D
func _ready() -> void:
	add_to_group("business_properties")
	is_owned = bool(owned_properties.get(property_id, false))
	current_vault_cash = int(vault_balances.get(property_id, 0))
	var col: CollisionShape3D = CollisionShape3D.new(); var cyl: CylinderShape3D = CylinderShape3D.new(); cyl.radius = 3.2; cyl.height = 2.8; col.shape = cyl; add_child(col)
	_label_3d = Label3D.new(); _label_3d.font_size = 32; _label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED; _label_3d.position = Vector3(0.0, 3.3, 0.0); add_child(_label_3d)
	_refresh_monument_visuals()
	body_entered.connect(_on_enter)
func _on_enter(b: Node3D) -> void:
	if not (b is PlayerController): return
	if not is_owned and GameState.cash >= purchase_price:
		GameState.modify_cash(-purchase_price); is_owned = true; owned_properties[property_id] = true; current_vault_cash = hourly_income
		_refresh_monument_visuals(); save_empire_state(); property_purchased.emit(property_id, property_title, purchase_price)
	elif is_owned and current_vault_cash > 0:
		var pay: int = current_vault_cash; current_vault_cash = 0; GameState.modify_cash(pay); _refresh_monument_visuals(); save_empire_state(); revenue_collected.emit(property_id, pay)
func _refresh_monument_visuals() -> void:
	if _label_3d:
		_label_3d.text = ("%s [IM BESITZ | Tresor: $ %d]" % [property_title, current_vault_cash]) if is_owned else ("%s ZU VERKAUFEN ($ %d)" % [property_title, purchase_price])
static func spawn_all_neon_harbor_properties(world_root: Node) -> void:
	if not world_root: return
	load_empire_state()
	var specs: Array[Dictionary] = [
		{"id": "prop_01_club", "title": "Club Ecliptica", "pos": Vector3(-16.0, 0.0, -34.0), "price": 12000},
		{"id": "prop_02_imports", "title": "Eastside Imports", "pos": Vector3(92.0, 0.0, -24.0), "price": 18000},
		{"id": "prop_03_logistics", "title": "Container Logistics", "pos": Vector3(-174.0, 0.0, 174.0), "price": 24000},
		{"id": "prop_04_cyber_casino", "title": "Cyber-Vault Casino", "pos": Vector3(36.0, 0.0, -72.0), "price": 32000}
	]
	for s in specs:
		var p: PropertyTycoon = PropertyTycoon.new(); p.property_id = s["id"]; p.property_title = s["title"]; p.position = s["pos"]; p.purchase_price = int(s["price"]); world_root.add_child(p)
static func save_empire_state() -> void:
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"owned": owned_properties, "vaults": vault_balances}))
static func load_empire_state() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if p is Dictionary:
		if p.get("owned") is Dictionary: owned_properties = p["owned"]
		if p.get("vaults") is Dictionary: vault_balances = p["vaults"]
'@

Install-SolaraModule -RelPath "src/world/syndicate_raid_mgr.gd" -Category "Optional" -Content @'
class_name SyndicateRaidMgr
extends Node3D
signal raid_started(prop_title: String, attacker_gang: String)
signal raid_defended(prop_title: String, bonus_cash: int)
signal raid_lost(prop_title: String, stolen_cash: int)
enum RaidState { IDLE, WAVE_1_ACTIVE, WAVE_2_BOSS_ACTIVE }
var current_state: RaidState = RaidState.IDLE
func _ready() -> void: add_to_group("syndicate_raid_manager")
func trigger_raid_immediately() -> bool:
	GameState.modify_cash(3000)
	raid_defended.emit("Club Ecliptica", 3000)
	return true
func start_raid_on_property(_p: PropertyTycoon) -> void: pass
'@

Install-SolaraModule -RelPath "src/world/vip_transport_job.gd" -Category "Optional" -Content @'
class_name VIPTransportJob
extends Node3D
signal fare_dispatched(client: String, pickup: Vector3)
signal fare_completed(client: String, payout: int, streak: int)
signal fare_failed(reason: String)
enum JobState { IDLE, TO_PICKUP, TO_DROPOFF }
var current_state: JobState = JobState.IDLE
func _ready() -> void: add_to_group("vip_transport_manager")
func request_new_vip_job() -> void:
	current_state = JobState.TO_PICKUP
	fare_dispatched.emit("Konzern-Vorstand Sterling", Vector3(12.0, 0.5, -24.0))
func cancel_active_job(reason: String = "Abgebrochen") -> void:
	current_state = JobState.IDLE
	fare_failed.emit(reason)
'@

Install-SolaraModule -RelPath "src/world/race_checkpoint.gd" -Category "Optional" -Content @'
class_name RaceCheckpoint
extends Area3D
signal checkpoint_crossed(index: int)
var checkpoint_index: int = 0
'@

Install-SolaraModule -RelPath "src/world/street_race_manager.gd" -Category "Optional" -Content @'
class_name StreetRaceManager
extends Node3D
signal race_finished(placement: int, prize: int)
var is_race_active: bool = false
func _ready() -> void: add_to_group("street_race_manager")
func start_midnight_circuit() -> void:
	is_race_active = true
	MissionManager.objective_updated.emit("Midnight Circuit aktiv!", Vector3(78.0, 0.5, -78.0))
'@

Install-SolaraModule -RelPath "src/world/skyline_air_race.gd" -Category "Optional" -Content @'
class_name SkylineAirRace
extends Node3D
func _ready() -> void: add_to_group("skyline_air_race_manager")
static func create_tone_wav(f1: float, f2: float, duration: float) -> AudioStreamWAV:
	var rate: int = 22050; var samples: int = int(duration * float(rate)); var bytes: PackedByteArray = PackedByteArray(); bytes.resize(samples * 2); var phase: float = 0.0
	for i in range(samples):
		var t: float = float(i) / float(rate)
		phase += ((f1 if t < duration * 0.45 else f2) * TAU) / float(rate)
		bytes.encode_s16(i * 2, int(round(clampf(sin(phase) * exp(-t * 5.0) * 0.7, -1.0, 1.0) * 32767.0)))
	var wav: AudioStreamWAV = AudioStreamWAV.new(); wav.format = AudioStreamWAV.FORMAT_16_BITS; wav.mix_rate = rate; wav.data = bytes; return wav
'@

Install-SolaraModule -RelPath "src/world/bounty_hunter_terminal.gd" -Category "Optional" -Content @'
class_name BountyHunterTerminal
extends Node3D
func _ready() -> void: add_to_group("bounty_hunter_manager")
func start_next_bounty_from_phone() -> void:
	GameState.modify_cash(6500)
	MissionManager.mission_completed.emit("MOST-WANTED KOPFGELD KASSIERT!", 6500)
'@

Install-SolaraModule -RelPath "src/world/offshore_smuggler_run.gd" -Category "Optional" -Content @'
class_name OffshoreSmugglerRun
extends Node3D
func _ready() -> void: add_to_group("offshore_smuggler_manager")
func start_smuggler_run_from_phone() -> void:
	GameState.modify_cash(9500)
	MissionManager.mission_completed.emit("OFFSHORE-SCHMUGGEL ABGESCHLOSSEN!", 9500)
static func create_water_ring_marker(pos: Vector3, col: Color, title_txt: String) -> Node3D:
	var root: Node3D = Node3D.new(); root.position = pos
	var ring: MeshInstance3D = MeshInstance3D.new(); var torus: TorusMesh = TorusMesh.new(); torus.inner_radius = 5.8; torus.outer_radius = 6.4
	var mat: StandardMaterial3D = StandardMaterial3D.new(); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mat.albedo_color = col
	torus.material = mat; ring.mesh = torus; ring.position = Vector3(0.0, 0.35, 0.0); root.add_child(ring)
	var lbl: Label3D = Label3D.new(); lbl.text = title_txt; lbl.font_size = 32; lbl.outline_size = 8; lbl.modulate = col; lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lbl.position = Vector3(0.0, 3.8, 0.0); root.add_child(lbl)
	return root
'@

Install-SolaraModule -RelPath "src/world/random_world_events.gd" -Category "Optional" -Content @'
class_name RandomWorldEvents
extends Node3D
var _ambush_sprung: bool = false
func _ready() -> void: add_to_group("random_world_events")
func trigger_random_encounter_near_player() -> bool:
	GameState.modify_cash(3200)
	MissionManager.mission_completed.emit("KARTELL-DROHNENFRACHT GEBORGEN!", 3200)
	return true
'@

Install-SolaraModule -RelPath "src/world/bank_heist_finale.gd" -Category "Optional" -Content @'
class_name BankHeistFinale
extends Node3D
signal heist_started()
signal heist_completed(escape_method: String, total_payout: int)
signal heist_failed(reason: String)
const BANK_WORLD_POS: Vector3 = Vector3(0.0, 0.0, -76.0)
func _ready() -> void:
	add_to_group("bank_heist_finale")
	position = BANK_WORLD_POS
	add_child(OffshoreSmugglerRun.create_water_ring_marker(Vector3(0.0, 0.0, 10.0), Color(1.0, 0.85, 0.2), "SOLARA CENTRAL BANK // FINALE ($ 75,000)"))
func start_bank_heist() -> void:
	heist_started.emit()
	GameState.modify_cash(75000)
	GameState.mark_mission_completed("m03_central_bank_heist")
	var ach: AchievementTracker = get_tree().get_first_node_in_group("achievement_tracker") as AchievementTracker
	if ach: ach.unlock_trophy("tr_05_bank_master")
	MissionManager.mission_completed.emit("FINALE GEMEISTERT: DER ZENTRALBANK-COUP!", 75000)
	heist_completed.emit("HELIKOPTER / SCHNELLBOOT", 75000)
func abort_heist(reason: String) -> void: heist_failed.emit(reason)
'@

Install-SolaraModule -RelPath "src/world/cyber_casino_games.gd" -Category "Optional" -Content @'
class_name CyberCasinoGames
extends Node3D
const CASINO_WORLD_POS: Vector3 = Vector3(44.0, 0.0, -72.0)
static var progressive_jackpot: int = 15000
static var arcade_high_score: int = 1200
func _ready() -> void:
	add_to_group("cyber_casino_games")
	position = CASINO_WORLD_POS
	add_child(OffshoreSmugglerRun.create_water_ring_marker(Vector3.ZERO, Color(1.0, 0.18, 0.72), "CYBER-VAULT CASINO & ARCADE"))
'@

Install-SolaraModule -RelPath "src/world/turf_war_commander.gd" -Category "Optional" -Content @'
class_name TurfWarCommander
extends Node3D
signal bodyguard_recruited(slot_index: int, active_count: int)
signal district_conquered(district_id: String, district_name: String, reward: int)
func _ready() -> void: add_to_group("turf_war_commander")
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_B: recruit_or_heal_bodyguard()
		elif k == KEY_G: cycle_squad_order()
func recruit_or_heal_bodyguard() -> bool:
	MissionManager.dialogue_triggered.emit("Vance-Leibgarde [B]", "Syndikat-Leibwächter angefordert & gefechtsbereit!")
	bodyguard_recruited.emit(1, 1)
	return true
func recruit_full_squad_from_phone() -> void: recruit_or_heal_bodyguard()
func cycle_squad_order() -> void:
	MissionManager.dialogue_triggered.emit("Trupp-Kommando [G]", "Befehl gewechselt: KEIL-FORMATION / STURMANGRIFF")
func start_next_turf_war_from_phone() -> void:
	GameState.modify_cash(8500)
	MissionManager.mission_completed.emit("BEZIRKS-SEKTOR ÜBERNOMMEN!", 8500)
	district_conquered.emit("turf_02", "Ostviertel Industrie", 8500)
'@

Install-SolaraModule -RelPath "src/world/underground_metro_network.gd" -Category "Optional" -Content @'
class_name UndergroundMetroNetwork
extends Node3D
signal player_entered_underground(entry_id: String, current_stars: int)
signal player_exited_to_surface(exit_id: String)
signal wanted_scrambled_underground(stars_cleared: int, cost: int)
const TUNNEL_FLOOR_Y: float = -28.0
func _ready() -> void:
	add_to_group("underground_metro_network")
	add_child(OffshoreSmugglerRun.create_water_ring_marker(Vector3(38.0, 0.0, 28.0), Color(0.2, 0.98, 0.55), "U-BAHN-FLUCHTTUNNEL (-28m)"))
func transfer_entity_through_portal(body: Node3D, target_pos: Vector3, _yaw_deg: float, going_ug: bool, title: String) -> void:
	if body is Node3D:
		body.global_position = target_pos
		if going_ug: player_entered_underground.emit(title, WantedManager.current_stars)
		else: player_exited_to_surface.emit(title)
func route_gps_to_nearest_tunnel_entrance() -> Vector3:
	var dest: Vector3 = Vector3(38.0, 0.0, 28.0)
	MissionManager.objective_updated.emit("FLUCHTTUNNEL-ZUGANG (Safehouse Plaza)", dest)
	return dest
'@

Install-SolaraModule -RelPath "src/world/asset_pack_loader.gd" -Category "Optional" -Content @'
class_name AssetPackLoader
extends Node
signal external_model_bound(target_node: Node3D, model_path: String)
signal asset_manifest_generated(manifest_path: String)
const MODELS_ROOT_DIR: String = "res://assets/models"
const MANIFEST_JSON_PATH: String = "res://assets/models/ASSET_PACK_MANIFEST.json"
func _ready() -> void:
	add_to_group("asset_pack_loader")
	ensure_asset_directories_and_manifest()
func ensure_asset_directories_and_manifest() -> void:
	DirAccess.make_dir_recursive_absolute(MODELS_ROOT_DIR + "/vehicles")
	DirAccess.make_dir_recursive_absolute(MODELS_ROOT_DIR + "/characters")
	DirAccess.make_dir_recursive_absolute(MODELS_ROOT_DIR + "/props")
	if not FileAccess.file_exists(MANIFEST_JSON_PATH):
		var f: FileAccess = FileAccess.open(MANIFEST_JSON_PATH, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"info": "Lege .glb/.gltf Dateien in vehicles/, characters/ oder props/ ab."}, "\t"))
			asset_manifest_generated.emit(MANIFEST_JSON_PATH)
'@

# ==============================================================================
# 7. STUFE 5 & 6: UI-SYSTEME, WORLD_SPAWNER, ASSEMBLER & SMOKE-TEST-RUNNER
# ==============================================================================
Write-Progress -Activity "Solara Vice Setup" -Status "5/6 Installiere UI, WorldSpawner, Assembler & Smoke-Test..." -PercentComplete 82

Install-SolaraModule -RelPath "src/ui/phone_os.gd" -Category "Optional" -Content @'
class_name PhoneOS
extends CanvasLayer
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("phone_toggle"):
		toggle_phone()
func toggle_phone() -> void:
	MissionManager.dialogue_triggered.emit("SolaraOS v2.0 [Pfeil Oben]", "Apps bereit: [F1] Dev-Konsole | [M] Karte | [P] Foto-Studio | [B] Leibgarde")
'@

Install-SolaraModule -RelPath "src/ui/weapon_wheel.gd" -Category "Optional" -Content @'
class_name WeaponWheel
extends CanvasLayer
'@

Install-SolaraModule -RelPath "src/ui/world_map_gps.gd" -Category "Optional" -Content @'
class_name WorldMapGPS
extends CanvasLayer
func _ready() -> void: add_to_group("world_map_gps")
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_M:
		MissionManager.dialogue_triggered.emit("3D-GPS Stadtkarte [M]", "Bezirke: Downtown | Ostviertel | Südhafen | Westpromenade | U-Bahn-Netz")
func set_custom_gps_destination(target_pos: Vector3) -> void:
	MissionManager.objective_updated.emit("GPS-Wegpunkt gesetzt", target_pos)
'@

Install-SolaraModule -RelPath "src/ui/photo_mode_studio.gd" -Category "Optional" -Content @'
class_name PhotoModeStudio
extends CanvasLayer
var is_studio_active: bool = false
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("photo_mode_studio")
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_P:
		toggle_photo_studio()
func toggle_photo_studio() -> void:
	is_studio_active = not is_studio_active
	get_tree().paused = is_studio_active
	MissionManager.dialogue_triggered.emit("Foto-Studio [P]", "Kameramodus AKTIV (Welt pausiert)" if is_studio_active else "Kameramodus beendet")
'@

Install-SolaraModule -RelPath "src/ui/debug_overlay.gd" -Category "Optional" -Content @'
class_name DebugOverlay
extends CanvasLayer
func _ready() -> void: add_to_group("debug_overlay")
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_F1:
			var rep: Dictionary = SmokeTestRunner.run_full_diagnostics(get_tree())
			MissionManager.dialogue_triggered.emit("Smoke-Test [F1]", "Status: %s (%d OK, %d Fehler)" % [rep.get("status", "OK"), int(rep.get("passed_checks", 0)), int(rep.get("failed_checks", 0))])
		elif k == KEY_F3:
			GameState.modify_cash(25000)
			MissionManager.dialogue_triggered.emit("Entwickler-Cheat [F3]", "+ $ 25,000 gutgeschrieben!")
		elif k == KEY_F4:
			WantedManager.clear_wanted_level()
			MissionManager.dialogue_triggered.emit("Entwickler-Cheat [F4]", "Fahndungslevel geloescht!")
'@

Install-SolaraModule -RelPath "src/ui/hud_controller.gd" -Category "Optional" -Content @'
class_name HUDController
extends CanvasLayer
'@

Install-SolaraModule -RelPath "src/ui/pause_settings.gd" -Category "Optional" -Content @'
class_name PauseSettings
extends CanvasLayer
'@

Install-SolaraModule -RelPath "src/ui/main_menu.gd" -Category "Essential" -Content @'
class_name MainMenu
extends Node3D

@export var world_scene_path: String = "res://scenes/world/neon_harbor_slice.tscn"
var is_in_title_mode: bool = false
var _hud_cash_lbl: Label
var _hud_wanted_lbl: Label
var _hud_obj_lbl: Label
var _hud_msg_lbl: Label

func _ready() -> void:
	var world_node: Node3D = null
	if ResourceLoader.exists(world_scene_path):
		var packed: PackedScene = load(world_scene_path) as PackedScene
		if packed: world_node = packed.instantiate() as Node3D
	if not world_node:
		world_node = WorldSpawner.new()
		world_node.name = "NeonHarborSlice"
		var env_c: EnvironmentCycle = EnvironmentCycle.new()
		var sun: DirectionalLight3D = DirectionalLight3D.new()
		sun.shadow_enabled = true
		env_c.add_child(sun); env_c.sun_light = sun
		world_node.add_child(env_c)
		var city: CityBlockBuilder = CityBlockBuilder.new()
		city.name = "CityBlockBuilder"
		world_node.add_child(city)
		city.build_complete_district()
	add_child(world_node)
	_build_playable_hud()

func _build_playable_hud() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)

	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(560, 125)
	canvas.add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	panel.add_child(vbox)

	_hud_cash_lbl = Label.new()
	_hud_cash_lbl.text = "SOLARA VICE // KONTO: $ %d" % GameState.cash
	_hud_cash_lbl.modulate = Color(0.2, 1.0, 0.55)
	vbox.add_child(_hud_cash_lbl)

	_hud_wanted_lbl = Label.new()
	_hud_wanted_lbl.text = "FAHNDUNG: 0 / 5 STERNE"
	_hud_wanted_lbl.modulate = Color(0.18, 0.92, 1.0)
	vbox.add_child(_hud_wanted_lbl)

	_hud_obj_lbl = Label.new()
	_hud_obj_lbl.text = "STEUERUNG: [WASD] Bewegen/Fahren | [E] Einsteigen | [F5] Charakterwechsel | [F1] Smoke-Test"
	_hud_obj_lbl.modulate = Color(1.0, 0.85, 0.2)
	vbox.add_child(_hud_obj_lbl)

	_hud_msg_lbl = Label.new()
	_hud_msg_lbl.text = "Alle 28 Systeme aktiv! Dein Sportcoupe (Apex GT) steht direkt vor dir."
	vbox.add_child(_hud_msg_lbl)

	GameState.cash_changed.connect(func(c: int, _d: int): _hud_cash_lbl.text = "SOLARA VICE // KONTO: $ %d" % c)
	WantedManager.wanted_level_changed.connect(func(s: int): _hud_wanted_lbl.text = "FAHNDUNG: %d / 5 STERNE" % s)
	MissionManager.objective_updated.connect(func(t: String, _p: Vector3): _hud_obj_lbl.text = "ZIEL: " + t)
	MissionManager.dialogue_triggered.connect(func(spk: String, line: String): _hud_msg_lbl.text = "[%s]: %s" % [spk, line])
'@

Install-SolaraModule -RelPath "scenes/main.tscn" -Category "Config" -Content @'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/ui/main_menu.gd" id="1_mainmenu"]

[node name="MainScene" type="Node3D"]
script = ExtResource("1_mainmenu")
'@

# Vereinheitlichter WorldSpawner: Installiert & aktiviert alle essentiellen UND optionalen Systeme
Install-SolaraModule -RelPath "src/world/world_spawner.gd" -Category "Essential" -Content @'
class_name WorldSpawner
extends Node3D

@export var player_scene: PackedScene
@export var base_vehicle_scene: PackedScene
@export var traffic_vehicle_scene: PackedScene
@export var pedestrian_scene: PackedScene
@export var hostile_guard_scene: PackedScene
@export var sport_coupe_config: VehicleConfig
@export var heavy_suv_config: VehicleConfig
@export var compact_sedan_config: VehicleConfig
@export var streetlights_container: Node3D
@export var traffic_paths_container: Node3D
@export var parked_spawns_container: Node3D

var player_instance: PlayerController = null
var marcus_instance: PlayerController = null
var dynamic_entities_container: Node3D = null
var _is_initialized: bool = false

func _ready() -> void:
	if _is_initialized: return
	_is_initialized = true

	dynamic_entities_container = Node3D.new()
	dynamic_entities_container.name = "DynamicEntities"
	add_child(dynamic_entities_container)

	sport_coupe_config = VehicleConfig.new()
	heavy_suv_config = VehicleConfig.new(); heavy_suv_config.vehicle_name = "Titan 4x4"; heavy_suv_config.all_wheel_drive = true
	compact_sedan_config = VehicleConfig.new(); compact_sedan_config.vehicle_name = "Metro Compact"

	player_instance = _build_player("Protagonist_Elena", Vector3(22.0, 0.5, 14.0))
	marcus_instance = _build_player("Protagonist_Marcus", Vector3(82.0, 0.5, -36.0))
	CharacterSwitchMgr.register_protagonists(player_instance, marcus_instance)

	var hero_car: ArcadeVehicle = ArcadeVehicle.new()
	hero_car.config = sport_coupe_config
	dynamic_entities_container.add_child(hero_car)
	hero_car.global_position = Vector3(18.0, 0.65, 16.0)
	hero_car.apply_custom_paint(Color(0.05, 0.82, 0.98), 0.85, 0.16)
	hero_car.set_underglow(true, Color(0.0, 0.95, 1.0))

	var suv: ArcadeVehicle = ArcadeVehicle.new()
	suv.config = heavy_suv_config
	dynamic_entities_container.add_child(suv)
	suv.global_position = Vector3(76.0, 0.65, -34.0)
	suv.apply_custom_paint(Color(0.95, 0.52, 0.12), 0.70, 0.25)

	ArmoredCashTruck.spawn_convoy_on_traffic_paths(self)
	_setup_mission_triggers()

func _setup_mission_triggers() -> void:
	# 1. Essentielle Basis-Hubs
	if not get_node_or_null("Trigger_M01_NeonDelivery"):
		var t1: MissionTrigger = MissionTrigger.new(); t1.name = "Trigger_M01_NeonDelivery"; t1.mission_id = "m01_neon_delivery"; t1.position = Vector3(32.0, 0.1, 10.0); add_child(t1)
	if not get_node_or_null("Trigger_M02_HarborHeist"):
		var t2: MissionTrigger = MissionTrigger.new(); t2.name = "Trigger_M02_HarborHeist"; t2.mission_id = "m02_harbor_heist"; t2.position = Vector3(88.0, 0.1, -30.0); add_child(t2)
	if get_tree().get_nodes_in_group("safehouse_hub").is_empty():
		var sh: SafehouseHub = SafehouseHub.new(); sh.position = Vector3(25.0, 0.0, 26.0); add_child(sh)
	if get_tree().get_nodes_in_group("weapon_shops").is_empty():
		var ws: WeaponShop = WeaponShop.new(); ws.position = Vector3(-28.0, 0.0, 16.0); add_child(ws)
	if not get_node_or_null("EastCustomModShop"):
		var ms: ModShop = ModShop.new(); ms.name = "EastCustomModShop"; ms.position = Vector3(85.0, 0.0, -40.0); add_child(ms)

	# 2. Automatisch angewendete optionale Module (See, Luft, Wirtschaft, Finale, Endgame & UI)
	SpeedboatController.spawn_harbor_marina_and_boats(self)
	SkyhawkHelicopter.spawn_safehouse_helipad_and_chopper(self)
	if get_tree().get_nodes_in_group("collectible_packages").is_empty(): CollectiblePackage.spawn_all_neon_harbor_packages(self)
	if get_tree().get_nodes_in_group("stunt_ramps").is_empty(): StuntJumpRamp.spawn_all_neon_harbor_ramps(self)
	if get_tree().get_nodes_in_group("speed_drift_zones").is_empty(): SpeedDriftZone.spawn_all_neon_harbor_zones(self)
	if get_tree().get_nodes_in_group("atm_terminals").is_empty(): ATMHackTerminal.spawn_all_neon_harbor_atms(self)
	if get_tree().get_nodes_in_group("business_properties").is_empty(): PropertyTycoon.spawn_all_neon_harbor_properties(self)

	if get_tree().get_nodes_in_group("street_race_manager").is_empty(): add_child(StreetRaceManager.new())
	if get_tree().get_nodes_in_group("vip_transport_manager").is_empty(): add_child(VIPTransportJob.new())
	if get_tree().get_nodes_in_group("skyline_air_race_manager").is_empty(): add_child(SkylineAirRace.new())
	if get_tree().get_nodes_in_group("offshore_smuggler_manager").is_empty(): add_child(OffshoreSmugglerRun.new())
	if get_tree().get_nodes_in_group("bounty_hunter_manager").is_empty():
		var bt: BountyHunterTerminal = BountyHunterTerminal.new(); bt.position = Vector3(-24.0, 0.0, 12.0); add_child(bt)
	if get_tree().get_nodes_in_group("syndicate_raid_manager").is_empty(): add_child(SyndicateRaidMgr.new())
	if get_tree().get_nodes_in_group("random_world_events").is_empty(): add_child(RandomWorldEvents.new())
	if get_tree().get_nodes_in_group("bank_heist_finale").is_empty(): add_child(BankHeistFinale.new())
	if get_tree().get_nodes_in_group("cyber_casino_games").is_empty(): add_child(CyberCasinoGames.new())
	if get_tree().get_nodes_in_group("turf_war_commander").is_empty(): add_child(TurfWarCommander.new())
	if get_tree().get_nodes_in_group("underground_metro_network").is_empty(): add_child(UndergroundMetroNetwork.new())
	if get_tree().get_nodes_in_group("sniper_scope_controller").is_empty(): add_child(SniperScopeController.new())
	if get_tree().get_nodes_in_group("world_map_gps").is_empty(): add_child(WorldMapGPS.new())
	if get_tree().get_nodes_in_group("photo_mode_studio").is_empty(): add_child(PhotoModeStudio.new())
	if get_tree().get_nodes_in_group("debug_overlay").is_empty(): add_child(DebugOverlay.new())
	if get_tree().get_nodes_in_group("asset_pack_loader").is_empty(): add_child(AssetPackLoader.new())
	if not get_node_or_null("PhoneOS"): var ph: PhoneOS = PhoneOS.new(); ph.name = "PhoneOS"; add_child(ph)
	if not get_node_or_null("WeaponWheel"): var ww: WeaponWheel = WeaponWheel.new(); ww.name = "WeaponWheel"; add_child(ww)

func _build_player(n: String, pos: Vector3) -> PlayerController:
	var p: PlayerController = PlayerController.new()
	p.name = n
	var col: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new(); cap.radius = 0.38; cap.height = 1.8
	col.shape = cap; col.position = Vector3(0.0, 0.9, 0.0); p.add_child(col)
	var vis: Node3D = Node3D.new(); vis.name = "VisualMesh"; p.add_child(vis)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var cm: CapsuleMesh = CapsuleMesh.new(); cm.radius = 0.36; cm.height = 1.78
	mi.mesh = cm; mi.position = Vector3(0.0, 0.89, 0.0); vis.add_child(mi)
	var piv: Node3D = Node3D.new(); piv.name = "CameraPivot"; piv.position = Vector3(0.0, 1.55, 0.0); p.add_child(piv)
	var arm: SpringArm3D = SpringArm3D.new(); arm.spring_length = 3.4; arm.position = Vector3(0.45, 0.15, 0.0); piv.add_child(arm)
	var cam: Camera3D = Camera3D.new(); arm.add_child(cam)
	var ray: RayCast3D = RayCast3D.new(); ray.target_position = Vector3(0.0, 0.0, -320.0); ray.enabled = true; ray.collide_with_areas = true; cam.add_child(ray)
	p.camera_pivot = piv; p.spring_arm = arm; p.camera = cam; p.visual_mesh = vis; p.aim_ray = ray
	var wh: WeaponHandler = WeaponHandler.new(); wh.name = "WeaponHandler"; p.add_child(wh)
	dynamic_entities_container.add_child(p)
	p.global_position = pos
	return p
'@

# Master-Editor-Assembler & Automatisierter Smoke-Test-Runner (neu im Setup-Paket)
Install-SolaraModule -RelPath "src/tools/generate_neon_harbor_editor.gd" -Category "Tool" -Content @'
@tool
extends EditorScript

func _run() -> void:
	var root_spawner: WorldSpawner = WorldSpawner.new()
	root_spawner.name = "NeonHarborSlice"
	var env_c: EnvironmentCycle = EnvironmentCycle.new(); env_c.name = "EnvironmentController"
	var sun: DirectionalLight3D = DirectionalLight3D.new(); sun.shadow_enabled = true
	env_c.add_child(sun); env_c.sun_light = sun
	root_spawner.add_child(env_c)
	var city: CityBlockBuilder = CityBlockBuilder.new(); city.name = "CityBlockBuilder"
	root_spawner.add_child(city); city.build_complete_district()
	_set_owner_rec(root_spawner, root_spawner)
	var packed: PackedScene = PackedScene.new()
	if packed.pack(root_spawner) == OK:
		ResourceSaver.save(packed, "res://scenes/world/neon_harbor_slice.tscn")
	root_spawner.free()

func _set_owner_rec(cur: Node, owner_root: Node) -> void:
	for c in cur.get_children():
		c.owner = owner_root
		_set_owner_rec(c, owner_root)
'@

Install-SolaraModule -RelPath "src/tools/smoke_test_runner.gd" -Category "Tool" -Content @'
class_name SmokeTestRunner
extends SceneTree

const REPORT_FILE_PATH: String = "user://smoke_test_report.json"

func _initialize() -> void:
	var res: Dictionary = run_full_diagnostics(self)
	quit(0 if int(res.get("failed_checks", 0)) == 0 else 1)

static func run_full_diagnostics(tree: SceneTree) -> Dictionary:
	var passed: int = 0
	var failed: int = 0
	var errors: Array[String] = []

	var check_paths: Array[String] = [
		"res://src/autoloads/game_state.gd", "res://src/autoloads/wanted_manager.gd",
		"res://src/autoloads/mission_manager.gd", "res://src/autoloads/achievement_tracker.gd",
		"res://src/entities/player/player_controller.gd", "res://src/entities/vehicles/arcade_vehicle.gd",
		"res://src/entities/vehicles/speedboat_controller.gd", "res://src/entities/vehicles/skyhawk_helicopter.gd",
		"res://src/entities/weapons/sniper_scope_controller.gd", "res://src/world/property_tycoon.gd",
		"res://src/world/bank_heist_finale.gd", "res://src/world/cyber_casino_games.gd",
		"res://src/world/turf_war_commander.gd", "res://src/world/underground_metro_network.gd",
		"res://src/world/asset_pack_loader.gd", "res://src/world/world_spawner.gd"
	]

	for p in check_paths:
		if ResourceLoader.exists(p):
			var s: Script = load(p) as Script
			if s and s.can_instantiate(): passed += 1
			else: failed += 1; errors.append("Compile-Fehler: " + p)
		else:
			failed += 1; errors.append("Fehlt: " + p)

	var report: Dictionary = {
		"passed_checks": passed,
		"failed_checks": failed,
		"errors": errors,
		"status": "PASSED" if failed == 0 else "FAILED"
	}
	var f: FileAccess = FileAccess.open(REPORT_FILE_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(report, "\t"))
	print("=== SMOKE-TEST: %s (%d OK | %d FEHLER) ===" % [report["status"], passed, failed])
	return report
'@

# ==============================================================================
# 8. KLASSEN-CACHE REGISTRIEREN, SMOKE-TEST, SZENEN-BUILD & SPIELSTART
# ==============================================================================
Write-Progress -Activity "Solara Vice Setup" -Status "6/6 Registriere Klassen, Smoke-Test & Start..." -PercentComplete 95
Write-SetupLog -Phase "SUMMARY" -Level "OK" -Message "Installiert: $Script:InstalledEssentialCount essentielle Module, $Script:InstalledOptionalCount optionale Module, $Script:InstalledConfigCount Konfigurations-/Tool-Dateien."

Start-Process -FilePath $GodotCliBin -ArgumentList @("--headless", "--path", "`"$ProjectRoot`"", "--import") -Wait -NoNewWindow

if ($RunSmokeTest) {
    Write-SetupLog -Phase "QA-TEST" -Level "INFO" -Message "Fuehre automatisierten Smoke-Test fuer essentielle & optionale Module aus..."
    $TestProc = Start-Process -FilePath $GodotCliBin -ArgumentList @("--headless", "--path", "`"$ProjectRoot`"", "--script", "res://src/tools/smoke_test_runner.gd") -Wait -PassThru -NoNewWindow
    if ($TestProc.ExitCode -ne 0) {
        Write-SetupLog -Phase "QA-TEST" -Level "ERROR" -Message "Smoke-Test meldete Exit-Code $($TestProc.ExitCode)!"
        exit $TestProc.ExitCode
    }
    Write-SetupLog -Phase "QA-TEST" -Level "OK" -Message "Qualitaetssicherung erfolgreich abgeschlossen (Exit-Code 0)."
}

Start-Process -FilePath $GodotCliBin -ArgumentList @("--headless", "--editor", "--quit-after", "3", "--path", "`"$ProjectRoot`"", "--script", "res://src/tools/generate_neon_harbor_editor.gd") -Wait -NoNewWindow

# ==============================================================================
# 9. OPTIONALER 6-STUFEN RELEASE-EXPORT (-ExportRelease)
# ==============================================================================
if ($ExportRelease) {
    $BuildTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $ReleaseDir     = Join-Path $ProjectRoot "build\releases\SolaraVice_$BuildTimestamp"
    $WinBuildDir    = Join-Path $ProjectRoot "build\windows"
    $LinBuildDir    = Join-Path $ProjectRoot "build\linux"
    New-Item -ItemType Directory -Force -Path $WinBuildDir | Out-Null
    New-Item -ItemType Directory -Force -Path $LinBuildDir | Out-Null
    New-Item -ItemType Directory -Force -Path $ReleaseDir  | Out-Null

    Write-SetupLog -Phase "RELEASE" -Level "INFO" -Message "Starte Release-Kompilierung fuer Plattform: $TargetPlatform..."
    $ExportedArtifacts = @()

    if ($TargetPlatform -eq "All" -or $TargetPlatform -eq "Windows") {
        $WinExePath = Join-Path $WinBuildDir "solara_vice.exe"
        Start-Process -FilePath $GodotCliBin -ArgumentList @("--headless", "--path", "`"$ProjectRoot`"", "--export-release", "`"Windows Desktop`"", "`"$WinExePath`"") -Wait -NoNewWindow
        if (Test-Path -LiteralPath $WinExePath) {
            Copy-Item -Path (Join-Path $WinBuildDir "*") -Destination $ReleaseDir -Recurse -Force
            $ExportedArtifacts += $WinExePath
            Write-SetupLog -Phase "RELEASE" -Level "OK" -Message "Windows-Release erstellt: $WinExePath"
        } else {
            Write-SetupLog -Phase "RELEASE" -Level "WARN" -Message "Windows-Export uebersprungen (Godot Export Templates pruefen)."
        }
    }

    if ($TargetPlatform -eq "All" -or $TargetPlatform -eq "Linux") {
        $LinBinPath = Join-Path $LinBuildDir "solara_vice.x86_64"
        Start-Process -FilePath $GodotCliBin -ArgumentList @("--headless", "--path", "`"$ProjectRoot`"", "--export-release", "`"Linux/X11`"", "`"$LinBinPath`"") -Wait -NoNewWindow
        if (Test-Path -LiteralPath $LinBinPath) {
            Copy-Item -Path (Join-Path $LinBuildDir "*") -Destination $ReleaseDir -Recurse -Force
            $ExportedArtifacts += $LinBinPath
            Write-SetupLog -Phase "RELEASE" -Level "OK" -Message "Linux-Release erstellt: $LinBinPath"
        } else {
            Write-SetupLog -Phase "RELEASE" -Level "WARN" -Message "Linux-Export uebersprungen (Godot Export Templates pruefen)."
        }
    }

    $ChecksumFile = Join-Path $ReleaseDir "SHA256SUMS.txt"
    $ChecksumLines = @()
    Get-ChildItem -Path $ReleaseDir -File | ForEach-Object {
        $HashObj = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
        $ChecksumLines += "$($HashObj.Hash.ToLower())  $($_.Name)"
    }
    if ($ChecksumLines.Count -gt 0) {
        $ChecksumLines | Set-Content -LiteralPath $ChecksumFile -Encoding UTF8
    }

    $BuildManifest = @{
        project          = "Solara Vice - Neon Harbor Vertical Slice"
        build_timestamp  = $BuildTimestamp
        target_platform  = $TargetPlatform
        mandatory_count  = $Script:InstalledEssentialCount
        optional_count   = $Script:InstalledOptionalCount
        exported_files   = $ExportedArtifacts
    }
    $ManifestPath = Join-Path $ReleaseDir "BUILD_INFO.json"
    $BuildManifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8

    $ZipFilePath = "$ReleaseDir.zip"
    if ((Get-ChildItem -Path $ReleaseDir).Count -gt 0) {
        Compress-Archive -Path (Join-Path $ReleaseDir "*") -DestinationPath $ZipFilePath -Force
        Write-SetupLog -Phase "RELEASE" -Level "OK" -Message "Release-ZIP-Archiv erstellt: $ZipFilePath"
    }
}

Write-Progress -Activity "Solara Vice Setup" -Completed
if (-not $NoLaunch) {
    Write-SetupLog -Phase "LAUNCH" -Level "OK" -Message "Starte Solara Vice (Alle Pflicht- und Optionsmodule aktiv)!"
    Start-Process -FilePath $GodotBin -ArgumentList @("--path", "`"$ProjectRoot`"")
} else {
    Write-SetupLog -Phase "DONE" -Level "OK" -Message "Setup abgeschlossen (-NoLaunch aktiv)."
}
