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

var controller = Controller.new()
var step_handler = StepHandler.new()
var rot_speed = 1
var rotation_blending = false
onready var motion_blur = $Head/CameraOffset/Camera/motion_blur

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
		
	var rot_diff = Vector3.ZERO - rotation
	if abs(rot_diff.x) > 0.01 or abs(rot_diff.z) > 0.01:
		rotation += Vector3(1, 0, 1) * rot_diff.sign() * delta * rot_speed
	else:
		rotation += Vector3(1, 0, 1) * rot_diff
	
	var just_used = Input.is_action_just_pressed("use")
	var just_used_alt = Input.is_action_just_pressed("use_alt")
	
	if just_used or just_used_alt:
#		var d = _portal_ray.to_global(_portal_ray.cast_to) - _portal_ray.to_global(Vector3.ZERO)
#		d = d.normalized() * 3
#		var pos = $Head.global_transform.origin + d
		if _portal_ray.is_colliding():
			var pos = _portal_ray.get_collision_point()
			var normal = _portal_ray.get_collision_normal()
			printt(pos, normal)
			if just_used:
#				$"../Portals/A".global_transform.origin = pos
#				$"../Portals/A".rotation = $Head/CameraOffset/Camera.global_transform.basis.get_euler()
				if normal != Vector3.UP && normal != Vector3.DOWN:
					$"../Portals/A".look_at_from_position(pos + normal * .1, pos - normal, Vector3.UP )
				else:
					$"../Portals/A".look_at_from_position(pos + normal * .1, pos - normal, player_cam.global_transform.basis.z )
				Audio.play_player("Portal/Shoot")
			elif just_used_alt:
#				$"../Portals/B".global_transform.origin = pos
#				$"../Portals/B".rotation = $Head/CameraOffset/Camera.global_transform.basis.get_euler()
				if normal != Vector3.UP && normal != Vector3.DOWN:
					$"../Portals/B".look_at_from_position(pos + normal * .1, pos - normal, Vector3.UP )
				else:
					$"../Portals/B".look_at_from_position(pos + normal * .1, pos - normal, player_cam.global_transform.basis.z )
				Audio.play_player("Portal/Shoot")

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
	if rotation_blending:
		print("already blending")
		return
		
	print("blending")
	rotation_blending = true
	
#	yield(get_tree().create_timer(.25), "timeout")
	
	var tween = Tween.new()
	add_child(tween)
	tween.interpolate_property(self, "rot_speed", 0.1, 5.0, 0.5,
		Tween.TRANS_LINEAR, Tween.EASE_IN_OUT, .2)
	tween.connect("tween_all_completed", self, "rot_blend_complete")
#	tween.connect("tween_completed", tween, "queue_free")
	tween.start()

func rot_blend_complete():
	print("yeet")
	rotation_blending = false;
	rot_speed = .1
