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
const MIN_DISTANCE := 1.35
const MAX_DISTANCE := 4.0

var viewport: SubViewport
var camera: Camera3D
var globe: MeshInstance3D
var labels: Node3D
var globe_material: ShaderMaterial
var state_image: Image
var state_texture: ImageTexture

var id_image: Image
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


## assets: {id_image: Image, color_texture: Texture2D, index: Dictionary, world: Dictionary}
func setup(assets: Dictionary, world_graph) -> void:
	graph = world_graph
	id_image = assets.id_image
	place_ids = assets.index["ids"]
	centers = assets.index["centers"]
	for i in place_ids.size():
		place_index[place_ids[i]] = i + 1
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
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.09)
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
	globe_material.set_shader_parameter("id_tex", ImageTexture.create_from_image(id_image))
	globe_material.set_shader_parameter("id_size", Vector2(id_image.get_width(), id_image.get_height()))
	state_image = Image.create(STATE_WIDTH, 1, false, Image.FORMAT_RGBA8)
	state_texture = ImageTexture.create_from_image(state_image)
	globe_material.set_shader_parameter("state_tex", state_texture)
	globe = MeshInstance3D.new()
	globe.mesh = mesh
	globe.material_override = globe_material
	viewport.add_child(globe)

	labels = Node3D.new()
	globe.add_child(labels)
	_apply_view()


## Punctul de pe sfera locală pentru o latitudine și longitudine (în grade).
static func lat_lon_to_point(lat: float, lon: float) -> Vector3:
	var la := deg_to_rad(lat)
	var lo := deg_to_rad(lon)
	return Vector3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo))


## Ce loc e la o latitudine și longitudine. "" = teritoriu neutru.
func place_at(lat: float, lon: float) -> String:
	var w := id_image.get_width()
	var h := id_image.get_height()
	var x := posmod(int(floor((lon + 180.0) / 360.0 * w)), w)
	var y := clampi(int(floor((90.0 - lat) / 180.0 * h)), 0, h - 1)
	var c := id_image.get_pixel(x, y)
	var index := int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256
	if index == 0:
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
func show_session(session) -> void:
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
	colors[session.goal] = COLORS.start_goal
	colors[session.current()] = COLORS.current

	state_image.fill(Color(0, 0, 0, 0))
	for i in place_ids.size():
		var id: String = place_ids[i]
		var shown: String = id if graph.nodes.has(id) else parents.get(id, id)
		if colors.has(shown) and i + 1 < STATE_WIDTH:
			state_image.set_pixel(i + 1, 0, colors[shown])
	state_texture.update(state_image)

	for child in labels.get_children():
		child.queue_free()
	for id in session.path:
		if graph.is_water(id) or not centers.has(id):
			continue
		var label := Label3D.new()
		label.text = graph.name_of(id)
		label.font_size = 40
		label.pixel_size = 0.0012
		label.outline_size = 10
		label.modulate = Color.WHITE
		label.outline_modulate = Color(0, 0, 0, 0.8)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = lat_lon_to_point(centers[id][0], centers[id][1]) * 1.01
		labels.add_child(label)


func _apply_view() -> void:
	if globe == null:
		return
	globe.basis = Basis(Vector3.RIGHT, pitch) * Basis(Vector3.UP, yaw)
	camera.position = Vector3(0, 0, distance)


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
