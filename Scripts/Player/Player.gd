extends Standable

class_name Player

export var velocity = Vector3.ZERO
export var added_velocity = Vector3.ZERO

var Controller = load("res://Scripts/Player/Controller.gd")
var StepHandler = load("res://Scripts/Player/StepHandler.gd")
#onready var _health_label = $"CanvasLayer/Health"
onready var _portal_ray = $"Head/CameraOffset/Camera/PortalRay"
onready var player_cam = $"Head/CameraOffset/Camera"

var _last_attack_pos = Vector3.ZERO
var last_velocity = Vector3.ZERO
var delta_velocity = Vector3.ZERO
const mouse_sensitivity = 2.4
const max_health = 100
var paused = false
var mouse_captured = false
var health = max_health
var water_is_at_feet = false
var water_is_at_waist = false
var water_is_at_head = false
var dead = false
var look_area: Area
var is_riding = false
var vehicle
var last_pos = Vector3.ZERO

var controller = Controller.new()
var step_handler = StepHandler.new()
#var rotation_blending = false
onready var motion_blur = $Head/CameraOffset/Camera/motion_blur

onready var portal_a = $"../Portals/A"
onready var portal_b = $"../Portals/B"

var rot_blend_tween = null

func _ready():
	controller.init(self, $Head, $CollisionShape)
	step_handler.init(self, $Feet)
	$BallGunAnimator.play("BallGunIdle")

func _physics_process(delta):
	step_handler.physics_process(delta)
	if not is_riding:
		controller.process_movement(delta)
	_view_bobbing()
	delta_velocity = last_velocity - velocity
	last_velocity = velocity

func _process(delta):
	_pause_input()
	_fullscreen_input()
	if not is_riding:
		controller.process(delta)
		
	var just_used = Input.is_action_just_pressed("use")
	var just_used_alt = Input.is_action_just_pressed("use_alt")
	
	if just_used or just_used_alt:
		if _portal_ray.is_colliding():
			var pos = _portal_ray.get_collision_point()
			var normal = _portal_ray.get_collision_normal()
			if just_used:
				Audio.play_player("Portal/Shoot")
				portal_a.place_portal(pos, normal)
			elif just_used_alt:
				Audio.play_player("Portal/Shoot")
				portal_b.place_portal(pos, normal)
		
	last_pos = global_transform.origin

func _input(event):
	controller.input(event)
	
func _pause_input():
	var just_paused = Input.is_action_just_pressed("escape")
	if just_paused:
		paused = not paused
		if not paused:
			capture_mouse()
			$PauseScreen.get_child(0).visible = false
		else:
			uncapture_mouse()
			$PauseScreen.get_child(0).visible = true
	
func _fullscreen_input():
	var just_fullscreen = Input.is_action_just_pressed("fullscreen")
	if just_fullscreen:
		OS.window_fullscreen = !OS.window_fullscreen
	
func _view_bobbing():
	if Input.is_action_pressed("move_forward") and is_on_floor():
		if Input.is_action_pressed("sprint"):
			$"BobAnimator".playback_speed = 1.6
		else:
			$"BobAnimator".playback_speed = 1
		$"BobAnimator".play("Bob")
	else:
		$"BobAnimator".stop()
	
func capture_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true
func uncapture_mouse():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false
	
func heal(amount: int):
	health += amount
	if health > max_health:
		health = max_health
#	_health_label.on_heal()
	
func hurt(amount: int, origin: Vector3):
	health -= amount
	if health < 0:
		health = 0
	_last_attack_pos = origin
	
	Audio.play_rand_player("Hurt", "hurt")
	$HurtAnimator.stop()
	$HurtAnimator.play("hurt")
	
	if health <= 0:
		dead = true
		paused = true
		$DeathScreen.get_child(0).visible = true
		$CanvasLayer/CenterContainer/Cursor.visible = false
		uncapture_mouse()
		AudioServer.set_bus_effect_enabled(0, 1, true)
		
#	_health_label.on_hurt()

func rotate_blend():
	
	if rot_blend_tween != null:
		return
		
	rot_blend_tween = Tween.new()
	add_child(rot_blend_tween)

	rot_blend_tween.interpolate_property(self, "rotation:x", rotation.x, 0, 0.5,
		Tween.TRANS_LINEAR, Tween.TRANS_LINEAR, .15)
	rot_blend_tween.interpolate_property(self, "rotation:z", rotation.z, 0, 0.5,
		Tween.TRANS_LINEAR, Tween.TRANS_LINEAR, .15)
	rot_blend_tween.connect("tween_all_completed", self, "rot_blend_complete")
	rot_blend_tween.start()

func rot_blend_complete():
	rot_blend_tween.queue_free()
	rot_blend_tween = null
#	rot_speed = .1
