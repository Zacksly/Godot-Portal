extends Spatial
class_name Portal

export var color = Color.white

onready var _player = get_tree().get_nodes_in_group("player")[0] as Player
onready var _player_cam = get_tree().get_nodes_in_group("player_cam")[0] as Camera
onready var _player_cam_ray = get_tree().get_nodes_in_group("player_cam_ray")[0] as RayCast
onready var _anim_player := $AnimationPlayer
onready var _particles_success = preload("res://Scenes/FX/PortalParticlesSuccess.tscn")
onready var _particles_fail = preload("res://Scenes/FX/PortalParticlesFail.tscn")
onready var ring_particles := $CPURingParticles as CPUParticles
onready var portal_glow := $Meshes/Front/PortalGlow as OmniLight

var other_portal
var other_portal_cam
var placed_on_floor_or_ceiling
var use_boost = false
var tracked_bodies = []
onready var portal_area := $PortalArea

var portal_placement_state = "success"
var portals_linked = false
onready var _side_raycasts = $SideRaycasts.get_children()
onready var _back_raycasts = $BackRaycasts.get_children()

onready var portal_material
onready var portal_mesh_inst = $Meshes/Front
onready var portal_mesh_inst_recursive = $Meshes/Front/FrontRecursive

func _ready():
	# Find the other portal node and its camera
	for child in $"..".get_children():
		if child.name != name:
			other_portal = child
			other_portal_cam = child.get_node("CamTransform")
	
	# Initialize the portal's color, texture, etc.
	portal_mesh_inst.mesh.surface_get_material(0).set_shader_param("texture_albedo", other_portal.get_node("Viewport").get_texture())
	portal_mesh_inst.material_override = portal_mesh_inst.mesh.surface_get_material(0).duplicate()
	var overlay_img = Image.new()
	var overlay_tex = ImageTexture.new()
	overlay_img.load("res://Textures/portal_door.png")
	overlay_tex.create_from_image(overlay_img, 1)
	portal_mesh_inst.material_override.set_shader_param("overlay", overlay_tex)
	portal_mesh_inst.material_override.set_shader_param("modulate", color)
	portal_material = portal_mesh_inst.material_override
	
	portal_mesh_inst_recursive.material_override = portal_mesh_inst.material_override.duplicate()
	portal_mesh_inst_recursive.material_override.set_shader_param("mix_amount", 1)
	
	# Set color of camera meshes used for debugging
	$"Viewport/Camera/DebugMesh".mesh.surface_get_material(0).set_shader_param("albedo_color", color)
	$"Viewport/Camera/DebugMesh".material_override = $"Viewport/Camera/DebugMesh".mesh.surface_get_material(0).duplicate()
	
	# Set Color of Portal Particles
	ring_particles.color = color
	ring_particles.color.a = .75
	
	portal_glow.light_color = color

	
func _process(delta):
	portals_linked = true if (portal_placement_state == "success" && other_portal.portal_placement_state == "success") else false

	_set_portal_cam_pos()
	
	var valid = true
	if portal_placement_state == "testing":
		for raycast in _side_raycasts:
			if raycast is RayCast:
				if raycast.is_colliding():
					valid = false
		
		for raycast in _back_raycasts:
			if raycast is RayCast:
				if !raycast.is_colliding():
					valid = false
	
		if !valid:
			portal_placement_state = "failed"
			remove_portal()

	update_portals()
	
func update_portals():
	
	# The next two lines are for getting the portal's normal
	var normal = global_transform.basis.z
	# Loop through all tracked bodies
	for body in tracked_bodies:
		if portal_placement_state == "success" && other_portal.portal_placement_state == "success":
			print(body)	
			# Get the direction from the front face of the portal to the body
			var body_dir = portal_mesh_inst.global_transform.origin - body.global_transform.origin
			
			# If the body is a player,
			# then get the direction of the front face of the portal to the player's camera rather than the player itself
			if body is Player:
				body_dir = portal_mesh_inst.global_transform.origin - _player_cam.global_transform.origin
			else:
				body_dir = portal_mesh_inst.global_transform.origin - body.global_transform.origin
							#put code for whatever it does there
			# If the angle between the direction to the body and
			# the portal's normal is < 90 degrees (the body is behind the portal),
			# then teleport the body to the other portal and play the portal enter sfx at the player
			print(normal.dot(body_dir) > 0)
			if normal.dot(body_dir) > 0:
				_teleport_to_other_portal(body)
				if body is Player:
					Audio.play_player("Portal/Enter")
					_set_portal_cam_pos()
					if other_portal.use_boost:
						body.velocity += other_portal.global_transform.basis.z * 5
				elif body is RigidBody:
					if other_portal.use_boost:
						body.linear_velocity += other_portal.global_transform.basis.z * 5
		else:
			# Stops players from clipping through after changing portals mid pass
			body.set_collision_mask_bit(3, true)

func _set_portal_cam_pos():
	# Set the portal's camera transform to the player's camera relative to the other portal
	var trans = other_portal.global_transform.inverse() * _player_cam.global_transform
	# Rotate by 180 degrees around the up axis because the camera should be facing the opposite way (180 degrees) at the other portal
	trans = trans.rotated(Vector3.UP, PI)
	$CamTransform.transform = trans
	other_portal.get_node("Viewport/Camera").global_transform = $CamTransform.global_transform
	
	# Set Portal Cam Cull Distance
	var pos2d = _player_cam.unproject_position(global_transform.origin)
	var resolution = get_viewport().get_visible_rect().size
	var screen_pos_percent = Vector2.ZERO
	screen_pos_percent.x = clamp(pos2d.x/resolution.x, 0,1) - .5
	screen_pos_percent.y = clamp(pos2d.y/resolution.y, 0,1) - .5
	
	# We need to change the cull distance based on where on the screen the portal is
	# This helps minimize clipping issues Still not a 100% fix though.
	# Godot needs to suppor curved culling planes to truly fix
	var cull_dist = global_transform.origin.distance_to(_player_cam.global_transform.origin)
	if cull_dist > 1:
		var slide = cull_dist * .033
		var adjustment_factor_x = lerp(.25, -7 * slide, abs(screen_pos_percent.x) * 2)
		var adjustment_factor_y = lerp(-1, -1 * slide, abs(screen_pos_percent.y) * 2)
		var total_adjustment_factor = adjustment_factor_x - (adjustment_factor_y * .2)
		other_portal.get_node("Viewport/Camera").near = cull_dist + total_adjustment_factor
	else:
		other_portal.get_node("Viewport/Camera").near = cull_dist + .25
	# Set the size of this portal's viewport to the size of the root viewport
	$Viewport.size = get_viewport().size

func _teleport_to_other_portal(body):
	print("porting")
	# Remove the body from being tracked by the portal
	var i = tracked_bodies.find(body)
	tracked_bodies.remove(i)
	
	# Rotate players back to normal over time
	if body is Player:
		if body.rot_blend_tween != null:
			body.rot_blend_tween.queue_free()
			body.rot_blend_tween = null

	# Set the body's position to be at the other portal and rotated 180 degrees
	# so that the player is facing away from the portal
	var offset 
	offset = global_transform.inverse() * body.global_transform
	var trans = other_portal.global_transform * offset.rotated(Vector3.UP, PI)
	body.global_transform = trans
	body.global_transform.origin += other_portal.global_transform.basis.z * .025

	
	# If the body is the player,
	# get the difference in rotation of this portal and the other portal
	# and rotate the player's velocity by that
	# +180 degrees on the y axis
	if body is Player:
		var r = other_portal.global_transform.basis.get_euler() - global_transform.basis.get_euler()
		body.velocity = body.velocity \
			.rotated(Vector3(1, 0, 0), r.x) \
			.rotated(Vector3(0, 1, 0), r.y + PI) \
			.rotated(Vector3(0, 0, 1), r.z)
		
		var speed = body.velocity.length()
		body.last_velocity = body.velocity
		
		if use_boost:
			body.velocity = other_portal.global_transform.basis.z * speed
			body.last_velocity = body.velocity.length() * other_portal.global_transform.basis.z
		
		body.motion_blur.cam_pos_prev =  body.player_cam.global_transform.origin
		body.motion_blur.cam_rot_prev = Quat( body.player_cam.global_transform.basis)
	elif body is RigidBody:
		var r = other_portal.global_transform.basis.get_euler() - global_transform.basis.get_euler()
		body.linear_velocity = body.linear_velocity \
			.rotated(Vector3(1, 0, 0), r.x) \
			.rotated(Vector3(0, 1, 0), r.y + PI) \
			.rotated(Vector3(0, 0, 1), r.z)
		
		if use_boost:
			var speed = body.linear_velocity.length()
			body.linear_velocity = other_portal.global_transform.basis.z * speed
			
func place_portal(pos, normal):
	
	if other_portal.portal_placement_state != "testing":	
		other_portal._anim_player.play("portal_fade_out", -1, 2)
		portal_material.set_shader_param("mix_amount", 1)
	
	$Meshes/Front.scale = Vector3.ZERO
	$SideRaycasts.scale = Vector3(0,0,1)
	portal_placement_state = "testing"
	
	# Actual Placement Code -----------------------------------------------------------------------
	if normal != Vector3.UP && normal != Vector3.DOWN:
		look_at_from_position(pos + normal * .1, pos - normal, Vector3.UP )
	else:
		look_at_from_position(pos + normal * .1, pos - normal, _player_cam.global_transform.basis.z )
		
	# Change colliders if placed on floor or ceiling
	$PortalArea/FloorCollisionShape.disabled = true
	$PortalArea/CeilingCollisionShape.disabled = true
	if normal != Vector3.UP:
		var dot = Vector3.UP.dot(normal)
		print(dot)
		if dot < .5 && dot > -.5:
			placed_on_floor_or_ceiling = false
#			print("placed on floor is a ",placed_on_floor_or_ceiling, " statement")
			# If it's on the floor
			if dot < 0:
				use_boost = true
				$PortalArea/FloorCollisionShape.disabled = false
			else:
				use_boost = false
				
		else:
			
			if dot > .8:
				print("floor?")
			if dot < .5:
				print("ceiling?")
				$PortalArea/CeilingCollisionShape.disabled = false
			placed_on_floor_or_ceiling = true
			use_boost = false
	else:
		placed_on_floor_or_ceiling = true
		$PortalArea/FloorCollisionShape.disabled = false
		use_boost = true
		
	enable_border_colliders()
	
	# Animation ------------------------------------------------------------------------------------
	_anim_player.stop()
	_anim_player.play("portal_open")
	
	create_portal_fx(_particles_success)
		
	ring_particles.restart()
	
	
	# Check if hitting another portal (Need a few physics frames for new data to validate)
	yield(get_tree(),"physics_frame")
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "physics_frame")
	print(portal_area.overlaps_area(other_portal.portal_area))
	if portal_area.overlaps_area(other_portal.portal_area):
		remove_portal()
		
func remove_portal():
#	return
	# Animation ------------------------------------------------------------------------------------
	var percentage_complete = _anim_player.current_animation_position/_anim_player.current_animation_length
	_anim_player.stop()
	_anim_player.play("portal_close")
	_anim_player.seek((.2 * percentage_complete), true)
	
	if portals_linked:
		other_portal._anim_player.play("portal_fade_out", -1, 2)
	
	ring_particles.emitting = false
	
	create_portal_fx(_particles_fail)
	
	# Disable Colliders for failed portal
	disable_border_colliders()
	other_portal.disable_border_colliders()
	
func create_portal_fx(effect):
	var instance = effect.instance()
	get_tree().current_scene.add_child(instance)
	instance.global_transform = global_transform
	
	# Set Color of Portal Particles
	var temp_mat = instance.process_material.duplicate()
	temp_mat.color = color
	temp_mat.color.a = .75
	instance.process_material = temp_mat
	
	# Auto Remove Splash Particles
	var timer = Timer.new()
	instance.add_child(timer)
	timer.set_wait_time(instance.lifetime)
	timer.connect("timeout", instance,"queue_free") 
	timer.start()
	
	# Start FX
	instance.emitting = true

# This is called via animation
func portal_placed_successfully():
	portal_placement_state = "success"
	
	# See if both portals are open
	if (portal_placement_state == "success" && other_portal.portal_placement_state == "success"):
		other_portal._anim_player.seek(other_portal._anim_player.current_animation_length, true)
		other_portal._anim_player.play("portal_fade_in")
		_anim_player.play("portal_fade_in")
		ring_particles.emitting = true
		
		# Check for objects already in portaling range
		initial_check()
		other_portal.initial_check()


func disable_border_colliders():
	for collider in $WallColliders.get_children():
			if collider is CollisionShape:
				collider.disabled = true
	for collider in $NonWallColliders.get_children():
		if collider is CollisionShape:
			collider.disabled = true

func enable_border_colliders():
	for collider in $WallColliders.get_children():
		if collider is CollisionShape:
			collider.disabled = placed_on_floor_or_ceiling
	for collider in $NonWallColliders.get_children():
		if collider is CollisionShape:
			collider.disabled = !placed_on_floor_or_ceiling

func initial_check():
	# Fix not-registering collisions for objects already on portal
	if !$PortalArea/FloorCollisionShape.disabled:
		var bodies = $PortalArea.get_overlapping_bodies()
		if bodies.size() > 0:
			for body in bodies:
				if body.has_node("CanTeleport"):
					body.set_collision_mask_bit(3, false)
					tracked_bodies.append(body)
	
	if !$PortalArea/CeilingCollisionShape.disabled:
		var bodies = $PortalArea.get_overlapping_bodies()
		if bodies.size() > 0:
			for body in bodies:
				if body.has_node("CanTeleport"):
					body.set_collision_mask_bit(3, false)
					tracked_bodies.append(body)

func check_for_portal_between(start_pos, end_pos):
	var space_state = get_world().get_direct_space_state()
	var layer_mask = pow(2,2)
	var hit = space_state.intersect_ray(start_pos, end_pos, [_player], layer_mask, false, true) #this is raycasting
	var result = false
	if hit:
		print("hit ", hit.collider.name)
		if hit.collider == other_portal.portal_area:
			print("detected")
			return result
	
	return result
	
# Signals ---------------------------------------------------------------
func _on_body_entered(body):
	
	if !portals_linked:
		return
		
	# If body enters portal, disable its collision on bit 3
	# so if the portal is on a wall the player can pass through
	# but still be able to stand on the portal's collision
#	if body is PhysicsBody:
#		if body is Player:
#			body.set_collision_mask_bit(3, false)
		
	# If a body enters portal, it will only start to be tracked for teleportation
	# if it has a node named CanTeleport as a child
	if body.has_node("CanTeleport"):
		body.set_collision_mask_bit(3, false)
		tracked_bodies.append(body)
		update_portals()


func _on_body_exited(body):
	# If body exits portal, set its collision on bit 0 to be enabled again
	if body is PhysicsBody:
		if body is Player:
#			body.set_collision_mask_bit(3, true)
			# Stop body from falling through ground
			body.rotate_blend()
		
	# If a body exits portal, it will be removed from being tracked
	# if it has a CanTelport child node and was already being tracked
	if body.has_node("CanTeleport"):
		body.set_collision_mask_bit(3, true)
		var i = tracked_bodies.find(body)
		if not i == -1:
			tracked_bodies.remove(i)
