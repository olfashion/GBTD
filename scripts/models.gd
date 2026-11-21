extends RefCounted
## Original procedural art. Actors are baked by material into small meshes.

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}

static func material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var key := color.to_html(true) + str(unshaded)
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = mat
	return mat

static func primitive(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var mesh: Mesh
	match kind:
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			sphere.radial_segments = 12
			sphere.rings = 6
			mesh = sphere
		"cylinder", "cone":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.0 if kind == "cone" else 0.5
			cylinder.bottom_radius = 0.5
			cylinder.height = 1.0
			cylinder.radial_segments = 10
			mesh = cylinder
		_:
			var cube := BoxMesh.new()
			cube.size = Vector3.ONE
			mesh = cube
	_meshes[kind] = mesh
	return mesh

static func part(parent: Node3D, kind: String, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = primitive(kind)
	node.material_override = material(color)
	node.position = pos
	node.scale = size
	parent.add_child(node)
	return node

static func ball(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	return part(parent, "sphere", pos, size, color)

static func block(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	return part(parent, "box", pos, size, color)

static func rod(parent: Node3D, start: Vector3, finish: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var length := start.distance_to(finish)
	var node := part(parent, "cylinder", (start + finish) * 0.5, Vector3(radius * 2, length, radius * 2), color)
	var direction := (finish - start).normalized()
	if direction.length() > 0.001:
		node.quaternion = Quaternion(Vector3.UP, direction)
	return node

static func group(parent: Node3D, label: String, pos: Vector3 = Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	node.name = label
	node.position = pos
	parent.add_child(node)
	return node

static func bake(root: Node3D) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := _append_geometry(root, Transform3D.IDENTITY, surface)
	if count == 0:
		return
	for child in root.get_children():
		root.remove_child(child)
		child.free()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.88
	var merged := MeshInstance3D.new()
	merged.name = "Mesh"
	merged.mesh = surface.commit()
	merged.material_override = mat
	root.add_child(merged)

static func _append_geometry(root: Node3D, local: Transform3D, surface: SurfaceTool) -> int:
	var count := 0
	for child in root.get_children():
		if not child is Node3D:
			continue
		var transform: Transform3D = local * child.transform
		if child is MeshInstance3D and child.mesh != null:
			var mesh: Mesh = child.mesh
			var color := Color.WHITE
			if child.material_override is StandardMaterial3D:
				color = child.material_override.albedo_color
			# Keep authored colors unchanged in the Compatibility renderer. Its
			# sRGB render path does not use the Forward+/Mobile vertex-color flag.
			for surface_id in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(surface_id)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var normal_basis := transform.basis.inverse().transposed()
				var length := indices.size() if indices.size() > 0 else vertices.size()
				for index in length:
					var vertex_index := indices[index] if indices.size() > 0 else index
					surface.set_color(color)
					if normals.size() > vertex_index:
						surface.set_normal((normal_basis * normals[vertex_index]).normalized())
					surface.add_vertex(transform * vertices[vertex_index])
					count += 1
		count += _append_geometry(child, transform, surface)
	return count

static func dog(breed: String, level: int = 1) -> Node3D:
	var root := Node3D.new()
	root.name = "Dog"
	var visual := group(root, "Visual")
	var fur := Color("e6b65d")
	var ear := Color("c88a39")
	var muzzle := Color("f9d795")
	var collar := Color("49aebb")
	var body_size := Vector3(0.76, 0.79, 1.15)
	var body_height := 0.66
	var head_height := 1.08
	var head_z := 0.57
	var leg_height := 0.44
	if breed == "dachshund":
		fur = Color("8e4d2f")
		ear = Color("593422")
		muzzle = Color("cb8a4f")
		collar = Color("ed7762")
		body_size = Vector3(0.57, 0.57, 1.65)
		body_height = 0.45
		head_height = 0.76
		head_z = 0.86
		leg_height = 0.25
	elif breed == "bulldog":
		fur = Color("e7d6b4")
		ear = Color("b88058")
		muzzle = Color("faf1d8")
		collar = Color("a068b7")
		body_size = Vector3(1.0, 0.82, 1.07)
		body_height = 0.6
		head_height = 0.91
		head_z = 0.58
		leg_height = 0.38
	elif breed == "malinois":
		fur = Color("bf914f")
		ear = Color("302c29")
		muzzle = Color("352e28")
		collar = Color("5d6d57")
		body_size = Vector3(0.73, 0.88, 1.25)
		body_height = 0.83
		head_height = 1.28
		head_z = 0.63
		leg_height = 0.65
	var body := group(visual, "Body")
	ball(body, Vector3(0, body_height, 0), body_size, fur)
	ball(body, Vector3(0, body_height - 0.11, 0.25), body_size * Vector3(0.72, 0.8, 0.65), muzzle)
	var neck := part(body, "cylinder", Vector3(0, head_height - 0.22, head_z - 0.1), Vector3(0.62, 0.16, 0.62), collar)
	neck.rotation_degrees.x = 67
	ball(body, Vector3(0, head_height - 0.27, head_z + 0.18), Vector3(0.17, 0.19, 0.06), Color("ffd66f"))
	if breed == "malinois":
		block(body, Vector3(0, body_height + 0.15, -0.05), Vector3(0.81, 0.64, 0.96), Color("354542"))
		block(body, Vector3(0, body_height + 0.51, -0.18), Vector3(0.5, 0.07, 0.6), Color("485850"))
		for side in [-1, 1]:
			block(body, Vector3(side * 0.43, body_height + 0.13, -0.14), Vector3(0.09, 0.33, 0.45), Color("63725a"))
			block(body, Vector3(side * 0.45, body_height + 0.16, 0.22), Vector3(0.08, 0.11, 0.21), Color("dac89c"))
		block(body, Vector3(0, body_height + 0.56, -0.22), Vector3(0.33, 0.11, 0.09), Color("202d2c"))
	if level > 1:
		for i in mini(level - 1, 2):
			ball(body, Vector3(-0.19 + float(i) * 0.36, body_height + 0.43, 0.05), Vector3(0.2, 0.07, 0.23), Color("ffd86c"))
	bake(body)
	var head := group(visual, "Head", Vector3(0, head_height, head_z))
	var head_size := Vector3(0.78, 0.72, 0.72)
	if breed == "bulldog":
		head_size = Vector3(0.94, 0.74, 0.7)
	ball(head, Vector3.ZERO, head_size, fur)
	ball(head, Vector3(0, -0.16, 0.36), Vector3(0.54, 0.36, 0.5), muzzle)
	ball(head, Vector3(0, -0.08, 0.6), Vector3(0.24, 0.16, 0.13), Color("272c2c"))
	ball(head, Vector3(0, -0.29, 0.47), Vector3(0.16, 0.12, 0.18), Color("e88984"))
	for side in [-1, 1]:
		var sx := float(side)
		ball(head, Vector3(sx * 0.24, 0.04, 0.3), Vector3(0.2, 0.22, 0.12), Color("fff8de"))
		ball(head, Vector3(sx * 0.24, 0.04, 0.35), Vector3(0.1, 0.14, 0.08), Color("202d2d"))
		ball(head, Vector3(sx * 0.22, 0.08, 0.39), Vector3(0.035, 0.04, 0.025), Color.WHITE)
		if breed == "malinois":
			var pointed := part(head, "cone", Vector3(sx * 0.25, 0.51, -0.08), Vector3(0.31, 0.64, 0.33), ear)
			pointed.rotation_degrees.z = sx * -8
			part(head, "cone", Vector3(sx * 0.25, 0.49, 0.01), Vector3(0.16, 0.4, 0.12), Color("a17455"))
		elif breed == "bulldog":
			var small := ball(head, Vector3(sx * 0.42, 0.2, -0.04), Vector3(0.3, 0.25, 0.32), ear)
			small.rotation_degrees.z = sx * 30
		else:
			var floppy := ball(head, Vector3(sx * 0.39, -0.07, -0.05), Vector3(0.3, 0.65, 0.38), ear)
			floppy.rotation_degrees.z = sx * 13
	bake(head)
	var width := body_size.x * 0.34
	var length := body_size.z * 0.34
	for index in 4:
		var side := -1.0 if index % 2 == 0 else 1.0
		var forward := -1.0 if index < 2 else 1.0
		var leg := group(visual, "Leg%d" % index, Vector3(side * width, leg_height, forward * length))
		part(leg, "cylinder", Vector3(0, -leg_height * 0.4, 0), Vector3(0.23, leg_height, 0.23), fur)
		ball(leg, Vector3(0, -leg_height * 0.8, 0.06), Vector3(0.29, 0.2, 0.38), muzzle if breed != "malinois" else ear)
		bake(leg)
	var tail := group(visual, "Tail", Vector3(0, body_height + 0.09, -body_size.z * 0.45))
	rod(tail, Vector3.ZERO, Vector3(0, 0.25, -0.45), 0.13, fur)
	rod(tail, Vector3(0, 0.25, -0.45), Vector3(0, 0.46, -0.65), 0.1, muzzle)
	bake(tail)
	root.scale = Vector3.ONE * 0.82
	return root

static func enemy(kind: String) -> Node3D:
	var root := Node3D.new()
	var body := group(root, "Body")
	var legs_a := group(root, "LegsA")
	var legs_b := group(root, "LegsB")
	var red := Color("ae503a")
	var dark := Color("5b3433")
	var eyes := Color("f9efc8")
	if kind == "ant":
		ball(body, Vector3(0, 0.34, -0.3), Vector3(0.54, 0.49, 0.65), red)
		ball(body, Vector3(0, 0.36, 0.12), Vector3(0.33, 0.34, 0.36), dark)
		ball(body, Vector3(0, 0.42, 0.46), Vector3(0.53, 0.44, 0.48), red)
		for side in [-1.0, 1.0]:
			rod(body, Vector3(side * 0.14, 0.57, 0.59), Vector3(side * 0.3, 0.82, 0.73), 0.035, dark)
			ball(body, Vector3(side * 0.31, 0.83, 0.74), Vector3.ONE * 0.08, red)
			ball(body, Vector3(side * 0.18, 0.48, 0.66), Vector3(0.15, 0.17, 0.11), eyes)
			ball(body, Vector3(side * 0.18, 0.49, 0.71), Vector3(0.07, 0.1, 0.06), dark)
			for index in 3:
				var z := -0.22 + float(index) * 0.24
				var leg_group := legs_a if (index + int(side)) % 2 == 0 else legs_b
				rod(leg_group, Vector3(side * 0.12, 0.3, z), Vector3(side * 0.46, 0.23, z - 0.14), 0.043, dark)
				rod(leg_group, Vector3(side * 0.46, 0.23, z - 0.14), Vector3(side * 0.57, 0.05, z), 0.036, dark)
	elif kind == "beetle":
		ball(body, Vector3(0, 0.41, -0.05), Vector3(0.96, 0.68, 1.14), Color("466d73"))
		ball(body, Vector3(-0.22, 0.51, -0.07), Vector3(0.49, 0.57, 1.0), Color("6d9a8a"))
		ball(body, Vector3(0.22, 0.51, -0.07), Vector3(0.49, 0.57, 1.0), Color("79a88d"))
		rod(body, Vector3(0, 0.76, -0.49), Vector3(0, 0.76, 0.39), 0.025, Color("345259"))
		ball(body, Vector3(0, 0.36, 0.61), Vector3(0.65, 0.44, 0.5), Color("394e59"))
		for side in [-1.0, 1.0]:
			ball(body, Vector3(side * 0.2, 0.47, 0.79), Vector3(0.19, 0.2, 0.12), eyes)
			ball(body, Vector3(side * 0.2, 0.46, 0.85), Vector3(0.09, 0.12, 0.06), dark)
			for index in 3:
				var z := -0.35 + float(index) * 0.35
				var leg_group := legs_a if index % 2 == 0 else legs_b
				rod(leg_group, Vector3(side * 0.3, 0.3, z), Vector3(side * 0.73, 0.08, z - 0.15), 0.075, Color("394e59"))
	elif kind == "spider":
		var fur := Color("80614c")
		ball(body, Vector3(0, 0.42, -0.23), Vector3(0.8, 0.67, 0.91), fur)
		ball(body, Vector3(0, 0.38, 0.39), Vector3(0.61, 0.54, 0.58), Color("ad8a66"))
		for side in [-1.0, 1.0]:
			ball(body, Vector3(side * 0.16, 0.48, 0.63), Vector3(0.2, 0.24, 0.13), eyes)
			ball(body, Vector3(side * 0.16, 0.48, 0.69), Vector3(0.09, 0.13, 0.07), dark)
			for index in 4:
				var z := -0.44 + float(index) * 0.27
				var tip_z := z * 1.55
				var leg_group := legs_a if index % 2 == 0 else legs_b
				rod(leg_group, Vector3(side * 0.23, 0.43, z), Vector3(side * 0.73, 0.54, tip_z), 0.064, fur)
				rod(leg_group, Vector3(side * 0.73, 0.54, tip_z), Vector3(side * 0.95, 0.07, tip_z + 0.1), 0.053, dark)
	else:
		var shell := Color("c3884b") if kind == "scorpion" else Color("8f5872")
		var trim := Color("e9ad5a") if kind == "scorpion" else Color("c789a1")
		ball(body, Vector3(0, 0.36, 0), Vector3(0.8, 0.51, 1.1), shell)
		for index in 4:
			ball(body, Vector3(0, 0.42, -0.38 + float(index) * 0.22), Vector3(0.84, 0.38, 0.25), trim)
		var tail_positions := [Vector3(0, 0.37, -0.54), Vector3(0, 0.6, -0.86), Vector3(0, 0.95, -1.0), Vector3(0, 1.27, -0.85), Vector3(0, 1.46, -0.52), Vector3(0, 1.38, -0.19)]
		for index in tail_positions.size() - 1:
			rod(body, tail_positions[index], tail_positions[index + 1], 0.12, shell)
			ball(body, tail_positions[index], Vector3.ONE * 0.26, trim)
		part(body, "cone", Vector3(0, 1.27, -0.08), Vector3(0.2, 0.4, 0.2), Color("553b49")).rotation_degrees.x = 155
		for side in [-1.0, 1.0]:
			rod(body, Vector3(side * 0.28, 0.38, 0.45), Vector3(side * 0.66, 0.38, 0.84), 0.1, shell)
			ball(body, Vector3(side * 0.68, 0.4, 0.96), Vector3(0.42, 0.3, 0.51), trim)
			ball(body, Vector3(side * 0.2, 0.53, 0.53), Vector3(0.18, 0.19, 0.15), eyes)
			ball(body, Vector3(side * 0.2, 0.54, 0.61), Vector3(0.09, 0.12, 0.06), dark)
			for index in 4:
				var z := -0.4 + float(index) * 0.24
				var leg_group := legs_a if index % 2 == 0 else legs_b
				rod(leg_group, Vector3(side * 0.26, 0.3, z), Vector3(side * 0.79, 0.08, z - 0.19), 0.065, shell)
	if kind == "scorpion_boss":
		root.scale = Vector3.ONE * 1.45
	else:
		root.scale = Vector3.ONE * 0.78
	bake(body)
	bake(legs_a)
	bake(legs_b)
	return root

static func oak(height: float = 3.5) -> Node3D:
	var root := Node3D.new()
	var wood := Color("79654a")
	rod(root, Vector3.ZERO, Vector3(0.16, height * 0.7, 0), 0.22, wood)
	rod(root, Vector3(0.08, height * 0.37, 0), Vector3(-0.8, height * 0.78, 0.1), 0.14, wood)
	rod(root, Vector3(0.12, height * 0.46, 0), Vector3(0.8, height * 0.73, -0.18), 0.14, wood)
	var crowns := [Vector3(-0.8, height * 0.77, 0), Vector3(0.76, height * 0.76, -0.1), Vector3(0, height * 0.94, 0.1), Vector3(0, height * 0.77, 0.7)]
	var colors := [Color("527c4e"), Color("719a52"), Color("87a85a"), Color("64914e")]
	for index in crowns.size():
		ball(root, crowns[index], Vector3(height * 0.72, height * 0.49, height * 0.63), colors[index])
	bake(root)
	return root

static func cactus(size: float = 1.0) -> Node3D:
	var root := Node3D.new()
	ball(root, Vector3(0, 0.48, 0), Vector3(0.65, 0.98, 0.24), Color("508d6a"))
	var left := ball(root, Vector3(-0.39, 0.84, 0), Vector3(0.56, 0.73, 0.23), Color("6ca477"))
	left.rotation.z = 0.4
	var right := ball(root, Vector3(0.38, 1.12, 0.02), Vector3(0.52, 0.74, 0.22), Color("81b47e"))
	right.rotation.z = -0.36
	for index in 7:
		var x := sin(float(index) * 2.8) * 0.19
		ball(root, Vector3(x, 0.28 + float(index) * 0.085, 0.125), Vector3.ONE * 0.035, Color("dfdec2"))
	ball(root, Vector3(0.48, 1.48, 0.01), Vector3(0.2, 0.15, 0.17), Color("df6685"))
	ball(root, Vector3(-0.5, 1.13, 0.01), Vector3(0.18, 0.13, 0.16), Color("f5a35c"))
	bake(root)
	root.scale = Vector3.ONE * size
	return root

static func rock(size: Vector3, color: Color = Color("d7cda8")) -> Node3D:
	var root := Node3D.new()
	var stone := ball(root, Vector3(0, size.y * 0.32, 0), size, color)
	stone.rotation = Vector3(0.09, 0.3, 0.16)
	bake(root)
	return root

static func flowers(seed_value: int = 1, blue: bool = true) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for index in 5:
		var x := rng.randf_range(-0.35, 0.35)
		var z := rng.randf_range(-0.3, 0.3)
		var h := rng.randf_range(0.35, 0.6)
		rod(root, Vector3(x, 0, z), Vector3(x, h, z), 0.018, Color("598351"))
		ball(root, Vector3(x + 0.06, h * 0.4, z), Vector3(0.2, 0.06, 0.1), Color("64944c"))
		if blue:
			ball(root, Vector3(x, h, z), Vector3(0.14, 0.31, 0.14), Color("7287bd"))
			ball(root, Vector3(x, h + 0.17, z), Vector3(0.11, 0.1, 0.11), Color("eee9d5"))
		else:
			ball(root, Vector3(x, h, z), Vector3(0.23, 0.1, 0.23), Color("f2cc66"))
			ball(root, Vector3(x, h + 0.04, z), Vector3.ONE * 0.1, Color("b47a47"))
	bake(root)
	return root

static func doghouse() -> Node3D:
	var root := Node3D.new()
	block(root, Vector3(0, 0.64, 0), Vector3(2.05, 1.28, 1.85), Color("dc9864"))
	for z in [-0.7, -0.35, 0.0, 0.35, 0.7]:
		block(root, Vector3(-1.04, 0.66, z), Vector3(0.04, 1.22, 0.025), Color("bf784d"))
	block(root, Vector3(0, 0.59, 0.94), Vector3(0.89, 1.05, 0.04), Color("4e5142"))
	ball(root, Vector3(0, 1.02, 0.95), Vector3(0.89, 0.66, 0.05), Color("4e5142"))
	for side in [-1.0, 1.0]:
		var roof := block(root, Vector3(side * 0.58, 1.53, 0), Vector3(1.47, 0.18, 2.2), Color("488888"))
		roof.rotation.z = side * -0.48
		block(root, Vector3(side * 0.57, 0.65, 1.0), Vector3(0.12, 1.3, 0.12), Color("f1d9a5"))
	block(root, Vector3(0, 0.07, 1.18), Vector3(1.27, 0.14, 0.67), Color("f0d5a0"))
	block(root, Vector3(0, 1.44, 1.05), Vector3(0.73, 0.28, 0.1), Color("f3d99f"))
	for side in [-1.0, 1.0]:
		ball(root, Vector3(side * 0.21, 1.44, 1.12), Vector3(0.15, 0.15, 0.07), Color("b17d4f"))
	block(root, Vector3(0, 1.44, 1.12), Vector3(0.43, 0.08, 0.07), Color("b17d4f"))
	bake(root)
	return root

static func annulus(radius: float, thickness: float, color: Color, segments: int = 80) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in segments:
		var a := float(index) / float(segments) * TAU
		var b := float(index + 1) / float(segments) * TAU
		var p1 := Vector3(cos(a) * radius, 0, sin(a) * radius)
		var p2 := Vector3(cos(b) * radius, 0, sin(b) * radius)
		var p3 := Vector3(cos(a) * (radius - thickness), 0, sin(a) * (radius - thickness))
		var p4 := Vector3(cos(b) * (radius - thickness), 0, sin(b) * (radius - thickness))
		for p in [p1, p3, p2, p2, p3, p4]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(p)
	var node := MeshInstance3D.new()
	node.mesh = surface.commit()
	node.material_override = material(color, true)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

static func plinth(width: float, depth: float, bottom: float, top: float, color: Color, side_color: Color) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline: Array[Vector2] = []
	var corner := 1.1
	for index in 4:
		var center := Vector2((width * 0.5 - corner) * (1 if index == 0 or index == 3 else -1), (depth * 0.5 - corner) * (1 if index < 2 else -1))
		for step in 9:
			var angle := float(index) * PI * 0.5 + float(step) / 8.0 * PI * 0.5
			outline.append(center + Vector2(cos(angle), sin(angle)) * corner)
	for index in outline.size():
		var p := outline[index]
		var q := outline[(index + 1) % outline.size()]
		var top_p := Vector3(p.x, top, p.y)
		var top_q := Vector3(q.x, top, q.y)
		var bottom_p := Vector3(p.x, bottom, p.y)
		var bottom_q := Vector3(q.x, bottom, q.y)
		for vertex in [Vector3(0, top, 0), top_q, top_p]:
			surface.set_color(color)
			surface.set_normal(Vector3.UP)
			surface.add_vertex(vertex)
		var normal := Vector3((p + q).x, 0, (p + q).y).normalized()
		for vertex in [top_p, top_q, bottom_p, bottom_p, top_q, bottom_q]:
			surface.set_color(side_color)
			surface.set_normal(normal)
			surface.add_vertex(vertex)
	var node := MeshInstance3D.new()
	node.mesh = surface.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = mat
	return node
