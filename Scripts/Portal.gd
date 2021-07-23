extends Spatial

export var color = Color.white

onready var _player_cam = get_tree().get_nodes_in_group("player_cam")[0] as Camera
onready var _player_cam_ray = get_tree().get_nodes_in_group("player_cam_ray")[0] as RayCast
var other_portal
var other_portal_cam

var tracked_bodies = []

func _ready():
	# Find the other portal node and its camera
	for child in $"..".get_children():
		if child.name != name:
			other_portal = child
			other_portal_cam = child.get_node("CamTransform")
	
	# Initialize the portal's color, texture, etc.
	$Meshes/Front.mesh.surface_get_material(0).set_shader_param("texture_albedo", other_portal.get_node("Viewport").get_texture())
	for mesh in $Meshes/Clip.get_children():
		mesh.material_override = mesh.mesh.surface_get_material(0).duplicate()
	$Meshes/Front.material_override = $Meshes/Front.mesh.surface_get_material(0).duplicate()
	var overlay_img = Image.new()
	var overlay_tex = ImageTexture.new()
	overlay_img.load("res://Textures/portal.png")
	overlay_tex.create_from_image(overlay_img, 1)
	$Meshes/Front.material_override.set_shader_param("overlay", overlay_tex)
	$Meshes/Front.material_override.set_shader_param("modulate", color)
	
	# Set color of camera meshes used for debugging
	$"Viewport/Camera/MeshInstance".mesh.surface_get_material(0).set_shader_param("albedo_color", color)
	$"Viewport/Camera/MeshInstance".material_override = $"Viewport/Camera/MeshInstance".mesh.surface_get_material(0).duplicate()
	
func _process(delta):
	_set_portal_cam_pos()
	
	# The next two lines are for getting the portal's normal
	# Theres probably an easier way to get the normal but i dont know how
	var rot = global_transform.basis.get_euler()
	var normal = Vector3(0, 0, 1).rotated(Vector3(1, 0, 0), rot.x).rotated(Vector3(0, 1, 0), rot.y).rotated(Vector3(0, 0, 1), rot.z)
	
	# Loop through all tracked bodies
	for body in tracked_bodies:
		# Get the direction from the front face of the portal to the body
		var body_dir = $Meshes/Front.global_transform.origin - body.global_transform.origin
		
		# If the body is a player,
		# then get the direction of the front face of the portal to the player's camera rather than the player itself
		if body is Player:
			body_dir = $Meshes/Front.global_transform.origin - _player_cam.global_transform.origin
			
		# If the angle between the direction to the body and
		# the portal's normal is < 90 degrees (the body is behind the portal),
		# then teleport the body to the other portal and play the portal enter sfx at the player
		if normal.dot(body_dir) > 0:
			_teleport_to_other_portal(body)
			if body is Player:
				Audio.play_player("Portal/Enter")
				_set_portal_cam_pos()

func _set_portal_cam_pos():
	# Set the portal's camera transform to the player's camera relative to the other portal
	var trans = other_portal.global_transform.inverse() * _player_cam.global_transform
	# Rotate by 180 degrees around the up axis because the camera should be facing the opposite way (180 degrees) at the other portal
	trans = trans.rotated(Vector3.UP, PI)
	$CamTransform.transform = trans
	other_portal.get_node("Viewport/Camera").global_transform = $CamTransform.global_transform
	
	# Set Portal Cam Cull Dist
	var pos2d = _player_cam.unproject_position(global_transform.origin)
	var resolution = get_viewport().get_visible_rect().size
	var percent = Vector2.ZERO
	percent.x = clamp(pos2d.x/resolution.x, 0,1) - .5
	percent.y = clamp(pos2d.y/resolution.y, 0,1) - .5
	
	print(pos2d, "    ", resolution, "    " , percent)
	# We need to change the cull distance based on where on the screen the portal is
	# This helps minimize clipping issues Still not a 100% fix though.
	# Godot needs to suppor curved culling planes to truly fix
	var cull_dist = global_transform.origin.distance_to(_player_cam.global_transform.origin)
	var slide = cull_dist * .033
	var adjustment_factor = lerp(.25, -.7 * slide, abs(percent.x) * 2)
	print("adjustment_factor: ", adjustment_factor)
	other_portal.get_node("Viewport/Camera").near = cull_dist + adjustment_factor
	
	# Set the size of this portal's viewport to the size of the root viewport
	$Viewport.size = get_viewport().size


func _teleport_to_other_portal(body):
	
	# Remove the body from being tracked by the portal
	var i = tracked_bodies.find(body)
	tracked_bodies.remove(i)

	# Set the body's position to be at the other portal and rotated 180 degrees
	# so that the player is facing away from the portal
	var offset = global_transform.inverse() * body.global_transform
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
		
		body.motion_blur.cam_pos_prev =  body.player_cam.global_transform.origin
		body.motion_blur.cam_rot_prev = Quat( body.player_cam.global_transform.basis)

func _on_body_entered(body):
	# If body enters portal, disable its collision on bit 0
	# so if the portal is on a wall the player can pass through
	# but still be able to stand on the portal's collision
	if body is PhysicsBody:
		if body is Player:
			body.set_collision_mask_bit(3, false)
			# Stop body from falling through ground
			body.controller.gravity = 0
		
	# If a body enters portal, it will only start to be tracked for teleportation
	# if it has a node named CanTeleport as a child
	if body.has_node("CanTeleport"):
		tracked_bodies.append(body)


func _on_body_exited(body):
	# If body exits portal, set its collision on bit 0 to be enabled again
	if body is PhysicsBody:
		if body is Player:
			body.set_collision_mask_bit(3, true)
			# Stop body from falling through ground
			body.controller.gravity = 15
			body.rotate_blend()
		
	# If a body exits portal, it will be removed from being tracked
	# if it has a CanTelport child node and was already being tracked
	if body.has_node("CanTeleport"):
		var i = tracked_bodies.find(body)
		if not i == -1:
			tracked_bodies.remove(i)

func _on_ClipArea_body_entered(body):
	# If a body that can teleport enters the ClipArea area,
	# then make the inside meshes of the portal be visible
	# This helps with flickering when entering portals,
	# but theres still flickering most of the time so im not sure how much its helping
	if body.has_node("CanTeleport"):
		$Meshes/Clip.visible = true

func _on_ClipArea_body_exited(body):
	# If a body that can teleport exits the ClipArea area,
	# then make the inside meshes invisible again
	if body.has_node("CanTeleport"):
		$Meshes/Clip.visible = false
