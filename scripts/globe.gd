extends SubViewportContainer
## Globul 3D: se rotește cu degetul sau mouse-ul, zoom cu rotița sau două degete.
## O atingere scurtă pe o țară sau o mare emite place_tapped(id).
## Pe glob nu apar nume, doar pentru țările prin care ai trecut deja.

signal place_tapped(id: String)

const STATE_WIDTH := 512
const COLORS := {
	"current": Color(0.15, 0.45, 1.0, 0.9),
	"start_goal": Color(0.62, 0.22, 0.88, 0.85),
	"required": Color(1.0, 0.85, 0.1, 0.85),
	"visited": Color(0.2, 0.75, 0.3, 0.8),
	"mistake": Color(1.0, 0.5, 0.0, 0.85),
	"forbidden": Color(0.9, 0.1, 0.1, 0.85),
	"off_map": Color(0.85, 0.1, 0.1, 0.45),
}
const MAX_LABEL_PIXEL := 0.0012
const FERRY_COLOR := Color(1.0, 0.82, 0.3)
const STRAIT_COLOR := Color(0.55, 0.9, 1.0)
const WORLD_BOUNDS := [-180.0, -90.0, 180.0, 90.0]
const MIN_DISTANCE := 1.35
const MAX_DISTANCE := 4.0
const UiTheme := preload("res://scripts/ui_theme.gd")

var viewport: SubViewport
var camera: Camera3D
var globe: MeshInstance3D
var labels: Node3D
var globe_material: ShaderMaterial
var state_image: Image
var state_texture: ImageTexture

var id_image: Image
var bounds := WORLD_BOUNDS          # lon_min, lat_min, lon_max, lat_max ale hărții de identificare active
var _world := {}                    # harta lumii, ca să revenim la ea după harta SUA
var place_ids: Array = []        # index - 1 -> id
var place_index := {}            # id -> index
var centers := {}                # id -> [lat, lon]
var parents := {}                # mare detaliată -> marea mare
var graph

var yaw := 0.0
var pitch := 0.0
var distance := 2.6
var _tween: Tween
var _press_pos := Vector2.ZERO
var _dragged := false
var _touches := {}
var _labels_key := ""
var ferry_lines: MeshInstance3D
var _boxes := {}  # țară -> {lat, lon, width, height}, mărimea ei în jurul punctului de etichetă


## assets: {id_image: Image, id_texture: Texture2D, color_texture: Texture2D, index: Dictionary, world: Dictionary}
func setup(assets: Dictionary, world_graph) -> void:
	graph = world_graph
	_use_index(assets.id_image, assets.index, WORLD_BOUNDS)
	_world = {"id_image": assets.id_image, "index": assets.index}
	for node in assets.world["nodes"]:
		if node.has("parent"):
			parents[node["id"]] = node["parent"]

	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)

	var env := Environment.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	camera = Camera3D.new()
	camera.fov = 40
	viewport.add_child(camera)

	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 128
	mesh.rings = 64
	globe_material = ShaderMaterial.new()
	globe_material.shader = preload("res://shaders/globe.gdshader")
	globe_material.set_shader_parameter("color_tex", assets.color_texture)
	globe_material.set_shader_parameter("id_tex", assets.id_texture)
	globe_material.set_shader_parameter("id_size", Vector2(id_image.get_width(), id_image.get_height()))
	state_image = Image.create(STATE_WIDTH, 1, false, Image.FORMAT_RGBA8)
	state_texture = ImageTexture.create_from_image(state_image)
	globe_material.set_shader_parameter("state_tex", state_texture)
	globe = MeshInstance3D.new()
	globe.mesh = mesh
	globe.material_override = globe_material
	viewport.add_child(globe)

	var halo := MeshInstance3D.new()
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = 1.07
	halo_mesh.height = 2.14
	halo_mesh.radial_segments = 64
	halo_mesh.rings = 32
	halo.mesh = halo_mesh
	var halo_material := ShaderMaterial.new()
	halo_material.shader = preload("res://shaders/atmosphere.gdshader")
	halo.material_override = halo_material
	viewport.add_child(halo)

	labels = Node3D.new()
	globe.add_child(labels)
	# Globul se redesenează doar când se schimbă ceva (rotire, zoom, mutare), nu la fiecare cadru.
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	resized.connect(_request_draw)
	_apply_view()


func _use_index(image: Image, index: Dictionary, area: Array) -> void:
	id_image = image
	bounds = area
	place_ids = index["ids"]
	centers = index["centers"]
	place_index.clear()
	for i in place_ids.size():
		place_index[place_ids[i]] = i + 1
	_boxes.clear()
	_labels_key = ""


## Harta unei regiuni (SUA) peste globul lumii: în regiune locurile vin din harta ei, mai detaliată;
## în rest se vede globul lumii, cu uscatul mai întunecat (nu e în joc). region = {} revine la lume.
func set_region(region: Dictionary) -> void:
	var on := not region.is_empty()
	globe_material.set_shader_parameter("use_region", on)
	if on:
		_use_index(region.id_image, region.index, region.index["bounds"])
		globe_material.set_shader_parameter("region_color_tex", region.color_texture)
		globe_material.set_shader_parameter("region_id_tex", region.id_texture)
		var b: Array = region.index["bounds"]
		globe_material.set_shader_parameter("region_bounds", Vector4(b[0], b[1], b[2], b[3]))
		globe_material.set_shader_parameter("region_size", Vector2(id_image.get_width(), id_image.get_height()))
	else:
		_use_index(_world.id_image, _world.index, WORLD_BOUNDS)
	for child in labels.get_children():
		child.queue_free()
	# SUA se vede mai de aproape; lumea, de mai departe.
	distance = 1.85 if on else 2.6
	_apply_view()


func _px(lat: float, lon: float) -> Vector2i:
	var w := id_image.get_width()
	var h := id_image.get_height()
	var x := int(floor((lon - bounds[0]) / (bounds[2] - bounds[0]) * w))
	var y := int(floor((bounds[3] - lat) / (bounds[3] - bounds[1]) * h))
	return Vector2i(posmod(x, w) if bounds == WORLD_BOUNDS else clampi(x, 0, w - 1), clampi(y, 0, h - 1))


## Legături peste mare între țări (bacuri sau strâmtori): linii întrerupte pe glob, cu un punct la capete.
func set_links(list: Array, color: Color) -> void:
	if ferry_lines == null:
		ferry_lines = MeshInstance3D.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ferry_lines.material_override = material
		globe.add_child(ferry_lines)
	ferry_lines.material_override.albedo_color = color
	var mesh := ImmediateMesh.new()
	ferry_lines.mesh = mesh
	if list.is_empty():
		_request_draw()
		return
	for ferry in list:
		var a := lat_lon_to_point(ferry["pa"][0], ferry["pa"][1])
		var b := lat_lon_to_point(ferry["pb"][0], ferry["pb"][1])
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		var steps := 24
		# Linie întreruptă: un segment da, unul nu; arcul se ridică puțin deasupra mării.
		for i in steps:
			if i % 2 == 1:
				continue
			for k in [i, i + 1]:
				var f := float(k) / steps
				var lift := 1.004 + 0.02 * sin(PI * f) * a.distance_to(b)
				mesh.surface_add_vertex(a.slerp(b, f).normalized() * lift)
		mesh.surface_end()
		for port in [a, b]:
			mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			_add_dot(mesh, port)
			mesh.surface_end()
	_request_draw()


## Un romb mic, tangent la glob, la port.
func _add_dot(mesh: ImmediateMesh, at: Vector3) -> void:
	var n := at.normalized()
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized() * 0.006
	var v := n.cross(u).normalized() * 0.006
	var c := n * 1.005
	for quad in [[c + u, c + v, c - u], [c - u, c - v, c + u]]:
		for p in quad:
			mesh.surface_add_vertex(p)


func _request_draw() -> void:
	if viewport:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		queue_redraw()


## Punctul de pe sfera locală pentru o latitudine și longitudine (în grade).
static func lat_lon_to_point(lat: float, lon: float) -> Vector3:
	var la := deg_to_rad(lat)
	var lo := deg_to_rad(lon)
	return Vector3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo))


## Ce loc e la o latitudine și longitudine. "" = teritoriu neutru.
func place_at(lat: float, lon: float) -> String:
	var at := _px(lat, lon)
	var index := _index_at(at.x, at.y)
	if index == 0 or index > place_ids.size():
		return ""
	var id: String = place_ids[index - 1]
	if graph and not graph.nodes.has(id):
		id = parents.get(id, id)
	return id


## Rotește globul ca locul să fie în fața camerei.
func focus(id: String, animate := true) -> void:
	if not centers.has(id):
		return
	var target_yaw := -deg_to_rad(centers[id][1])
	var target_pitch := deg_to_rad(centers[id][0])
	target_yaw = yaw + wrapf(target_yaw - yaw, -PI, PI)
	if _tween:
		_tween.kill()
	if not animate or not is_inside_tree():
		yaw = target_yaw
		pitch = target_pitch
		_apply_view()
		return
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(func(v: Vector2):
		yaw = v.x
		pitch = v.y
		_apply_view(), Vector2(yaw, pitch), Vector2(target_yaw, target_pitch), 0.6)


## Colorează locurile după starea partidei și pune numele țărilor vizitate.
## fog: granițele apar doar la locurile implicate; hide_goal: destinația nu se colorează.
func show_session(session, fog := false, hide_goal := false) -> void:
	var colors := {}
	for id in graph.nodes:
		if session.continent != "" and not graph.is_allowed(id, session.continent):
			colors[id] = COLORS.off_map
	for id in session.forbidden:
		colors[id] = COLORS.forbidden
	for id in session.mistake_places:
		colors[id] = COLORS.mistake
	for id in session.path:
		colors[id] = COLORS.visited
		if graph.is_water(id):
			colors[id] = Color(COLORS.visited, 0.35)  # oceanele mari ar acoperi tot globul
	for id in session.missing_required():
		colors[id] = COLORS.required
	colors[session.start] = COLORS.start_goal
	if not hide_goal:
		colors[session.goal] = COLORS.start_goal
	colors[session.current()] = COLORS.current

	state_image.fill(Color(0, 0, 0, 0))
	for i in place_ids.size():
		var id: String = place_ids[i]
		var shown: String = id if graph.nodes.has(id) else parents.get(id, id)
		if colors.has(shown) and i + 1 < STATE_WIDTH:
			state_image.set_pixel(i + 1, 0, colors[shown])
	state_texture.update(state_image)
	globe_material.set_shader_parameter("fog", fog)
	_request_draw()

	# Etichetele se refac doar când se schimbă traseul sau limba.
	var key := "%s|%s" % [graph.lang, ",".join(session.path)]
	if key == _labels_key:
		return
	_labels_key = key
	for child in labels.get_children():
		child.queue_free()
	for id in session.path:
		if graph.is_water(id) or not centers.has(id):
			continue
		var label := Label3D.new()
		label.text = graph.name_of(id)
		label.font = UiTheme.bold()
		label.font_size = 40
		label.outline_size = 10
		# Numele încape în țară: mărimea textului urmează lățimea și înălțimea țării.
		var box := _country_box(id)
		var text_size: Vector2 = label.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 40) \
			+ Vector2(20, 10)
		label.pixel_size = minf(MAX_LABEL_PIXEL, minf(0.9 * box.width / text_size.x, 0.85 * box.height / text_size.y))
		label.modulate = Color.WHITE
		label.outline_modulate = Color(0, 0, 0, 0.8)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true  # altfel globul taie din litere; ascundem noi etichetele din spate
		label.position = lat_lon_to_point(box.lat, box.lon) * 1.01
		labels.add_child(label)
	_update_label_visibility()


## Cât de lată și de înaltă e țara (în unități pe glob) pe rândul și coloana punctului de etichetă,
## plus mijlocul rândului, unde stă numele.
func _country_box(id: String) -> Dictionary:
	if _boxes.has(id):
		return _boxes[id]
	var w := id_image.get_width()
	var h := id_image.get_height()
	var lat: float = centers[id][0]
	var lon: float = centers[id][1]
	var at := _px(lat, lon)
	var x := at.x
	var y := at.y
	var wanted: int = place_index.get(id, -1)
	var left := 0
	var right := 0
	if _index_at(x, y) == wanted:
		while left < w / 4 and _index_at(posmod(x - left - 1, w), y) == wanted:
			left += 1
		while right < w / 4 and _index_at(posmod(x + right + 1, w), y) == wanted:
			right += 1
	var mid_x := posmod(x + (right - left) / 2, w)
	var up := 0
	var down := 0
	if _index_at(mid_x, y) == wanted:
		while y - up - 1 >= 0 and up < h / 4 and _index_at(mid_x, y - up - 1) == wanted:
			up += 1
		while y + down + 1 < h and down < h / 4 and _index_at(mid_x, y + down + 1) == wanted:
			down += 1
	var deg_x: float = (bounds[2] - bounds[0]) / w
	var deg_y: float = (bounds[3] - bounds[1]) / h
	var box := {
		"lat": lat + (up - down) * 0.5 * deg_y,
		"lon": bounds[0] + (mid_x + 0.5) * deg_x,
		"width": deg_to_rad((left + right + 1) * deg_x) * cos(deg_to_rad(lat)),
		"height": deg_to_rad((up + down + 1) * deg_y),
	}
	_boxes[id] = box
	return box


func _index_at(x: int, y: int) -> int:
	var c := id_image.get_pixel(x, y)
	return int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256


## Etichetele de pe partea din spate a globului nu se văd.
func _update_label_visibility() -> void:
	if labels == null:
		return
	for label in labels.get_children():
		var world_pos: Vector3 = globe.basis * label.position
		label.visible = world_pos.z > 0.15


func _apply_view() -> void:
	if globe == null:
		return
	globe.basis = Basis(Vector3.RIGHT, pitch) * Basis(Vector3.UP, yaw)
	camera.position = Vector3(0, 0, distance)
	_update_label_visibility()
	_request_draw()


func _zoom(factor: float) -> void:
	distance = clampf(distance * factor, MIN_DISTANCE, MAX_DISTANCE)
	_apply_view()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
	elif event is InputEventScreenDrag and _touches.size() == 2:
		var other: Vector2 = _touches[1 - event.index] if _touches.has(1 - event.index) else event.position
		var before: float = _touches[event.index].distance_to(other)
		_touches[event.index] = event.position
		var after: float = event.position.distance_to(other)
		if before > 1.0 and after > 1.0:
			_zoom(before / after)
		_dragged = true
		accept_event()
		return
	elif event is InputEventMagnifyGesture:
		_zoom(1.0 / event.factor)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom(0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom(1.1)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press_pos = event.position
				_dragged = false
			elif not _dragged and _touches.size() <= 1:
				_tap(event.position)
		accept_event()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if _touches.size() >= 2:
			return
		if event.position.distance_to(_press_pos) > 8.0:
			_dragged = true
		if _dragged:
			if _tween:
				_tween.kill()
			var speed := 0.005 * distance / 2.6
			yaw += event.relative.x * speed
			pitch = clampf(pitch + event.relative.y * speed, -1.4, 1.4)
			_apply_view()
		accept_event()


func _tap(pos: Vector2) -> void:
	var scale_factor := Vector2(viewport.size) / size if size.x > 0 and size.y > 0 else Vector2.ONE
	var p := pos * scale_factor
	var origin := camera.project_ray_origin(p)
	var dir := camera.project_ray_normal(p)
	var b := origin.dot(dir)
	var c := origin.dot(origin) - 1.0
	var disc := b * b - c
	if disc < 0.0:
		return
	var hit := origin + dir * (-b - sqrt(disc))
	var local := (globe.global_transform.basis.inverse() * hit).normalized()
	var id := place_at(rad_to_deg(asin(local.y)), rad_to_deg(atan2(local.x, local.z)))
	if id != "":
		place_tapped.emit(id)
