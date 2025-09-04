extends Node2D

var player_units = []
var enemy_units = []
var frontline_points = []
var original_frontline_points = []
var city_scene = preload("res://city.tscn")

# Terrain system - now in chunks, not pixels
var terrain_data = []
var terrain_texture: ImageTexture
var terrain_sprite: Sprite2D
var terrain_chunks = Vector2i(80, 60)  # number of chunks
var chunk_size = 10

# City positions (set before terrain generation)
var player_city_pos: Vector2
var enemy_city_pos: Vector2

enum TerrainType {
    WATER = -3,
    SAND = -2,
    MUD = -1,
    PLAINS = 0,
    BUSH = 1,
    ROCKY = 2,
    SNOW = 3
}

const terrain_speeds = {
    TerrainType.WATER: 0.0,
    TerrainType.SAND: 0.25,
    TerrainType.MUD: 0.75,
    TerrainType.PLAINS: 1.0,
    TerrainType.BUSH: 0.75,
    TerrainType.ROCKY: 0.25,
    TerrainType.SNOW: 0.0
}

const terrain_colors = {
    TerrainType.WATER: Color.DODGER_BLUE,
    TerrainType.SAND: Color.SANDY_BROWN,
    TerrainType.MUD: Color.SADDLE_BROWN,
    TerrainType.PLAINS: Color.SEA_GREEN,
    TerrainType.BUSH: Color.DARK_GREEN,
    TerrainType.ROCKY: Color.SLATE_GRAY,
    TerrainType.SNOW: Color.WHITE
}

func _ready():
    print("=== BEGIN COMBAT ===")
    pre_place_cities()
    generate_terrain()
    render_terrain()
    spawn_cities()
    create_static_frontline()

func pre_place_cities():
    var viewport_size = get_viewport().get_visible_rect().size
    print("viewport size is", viewport_size.x, " x ", viewport_size.y)
    var margin = 50
    var segment_width = viewport_size.x / 4
    
    player_city_pos = Vector2(
        randf_range(margin, segment_width - margin),
        randf_range(margin, viewport_size.y - margin)
    )
    
    enemy_city_pos = Vector2(
        randf_range(3 * segment_width + margin, viewport_size.x - margin),
        randf_range(margin, viewport_size.y - margin)
    )
    
    print("Cities pre-placed at: Player=", player_city_pos, " Enemy=", enemy_city_pos)

func world_pos_to_chunk(world_pos: Vector2) -> Vector2i:
    var viewport_size = get_viewport().get_visible_rect().size
    var chunk_x = int((world_pos.x / viewport_size.x) * terrain_chunks.x)
    var chunk_y = int((world_pos.y / viewport_size.y) * terrain_chunks.y)
    return Vector2i(clamp(chunk_x, 0, terrain_chunks.x - 1), clamp(chunk_y, 0, terrain_chunks.y - 1))

func is_near_city(chunk_x: int, chunk_y: int) -> bool:
    var player_chunk = world_pos_to_chunk(player_city_pos)
    var enemy_chunk = world_pos_to_chunk(enemy_city_pos)
    
    var distance_to_player = abs(chunk_x - player_chunk.x) + abs(chunk_y - player_chunk.y)
    var distance_to_enemy = abs(chunk_x - enemy_chunk.x) + abs(chunk_y - enemy_chunk.y)
    
    return distance_to_player <= 6 or distance_to_enemy <= 6

func generate_terrain():
    # Initialize
    terrain_data = []
    for y in range(terrain_chunks.y):
        terrain_data.append([])
        for x in range(terrain_chunks.x):
            terrain_data[y].append(TerrainType.PLAINS)
    
    var noise = FastNoiseLite.new()
    noise.seed = randi()
    noise.frequency = 0.06  # Lower = larger features
    
    for y in range(terrain_chunks.y):
        for x in range(terrain_chunks.x):
            if is_near_city(x, y):
                terrain_data[y][x] = TerrainType.PLAINS
                continue
            
            var noise_value = noise.get_noise_2d(x, y)
            # Convert -1 to +1 noise into -3 to +3 terrain height
            var height = int(round(noise_value * 4.0))
            terrain_data[y][x] = clamp(height, TerrainType.WATER, TerrainType.SNOW)
    
    print("Terrain generation complete")

func render_terrain():
    print("Rendering terrain...")
    var pixel_width = terrain_chunks.x * chunk_size
    var pixel_height = terrain_chunks.y * chunk_size
    var image = Image.create(pixel_width, pixel_height, false, Image.FORMAT_RGB8)
    
    for chunk_y in range(terrain_chunks.y):
        for chunk_x in range(terrain_chunks.x):
            var terrain_type = terrain_data[chunk_y][chunk_x]
            var color = terrain_colors[terrain_type]
            
            for pixel_y in range(chunk_size):
                for pixel_x in range(chunk_size):
                    var img_x = chunk_x * chunk_size + pixel_x
                    var img_y = chunk_y * chunk_size + pixel_y
                    image.set_pixel(img_x, img_y, color)
    
    terrain_texture = ImageTexture.new()
    terrain_texture.set_image(image)
    
    terrain_sprite = Sprite2D.new()
    terrain_sprite.texture = terrain_texture
    terrain_sprite.centered = false
    terrain_sprite.position = Vector2.ZERO
    
    var viewport_size = get_viewport().get_visible_rect().size
    var scale_x = viewport_size.x / float(pixel_width)
    var scale_y = viewport_size.y / float(pixel_height)
    terrain_sprite.scale = Vector2(scale_x, scale_y)
    
    var terrain_layer = CanvasLayer.new()
    terrain_layer.layer = -1
    terrain_layer.add_child(terrain_sprite)
    add_child(terrain_layer)
    
    print("Terrain rendered")

func get_terrain_at_position(world_pos: Vector2) -> int:
    var chunk_pos = world_pos_to_chunk(world_pos)
    return terrain_data[chunk_pos.y][chunk_pos.x]

# Replace the simple get_terrain_speed_multiplier function in node_2d.gd with this:

func get_terrain_speed_multiplier(world_pos: Vector2) -> float:
    # Sample the 4 corners of a 20x20 unit (since units are 20x20)
    var unit_size = 20.0
    var half_size = unit_size / 2.0
    
    var corners = [
        world_pos + Vector2(-half_size, -half_size),  # Top-left
        world_pos + Vector2(half_size, -half_size),   # Top-right  
        world_pos + Vector2(-half_size, half_size),   # Bottom-left
        world_pos + Vector2(half_size, half_size)     # Bottom-right
    ]
    
    var min_speed = 1.0  # Start with maximum speed
    
    for corner in corners:
        var terrain_type = get_terrain_at_position(corner)
        var speed_mult = terrain_speeds[terrain_type]
        min_speed = min(min_speed, speed_mult)
        
        # Early exit if we hit impassable terrain
        if speed_mult == 0.0:
            return 0.0
    
    return min_speed

func spawn_cities():
    var player_city = city_scene.instantiate()
    player_city.team = 0
    player_city.global_position = player_city_pos
    add_child(player_city)
    
    var enemy_city = city_scene.instantiate()
    enemy_city.team = 1
    enemy_city.global_position = enemy_city_pos
    add_child(enemy_city)

func create_static_frontline():
    var player_city = get_city(0)
    var enemy_city = get_city(1)
    
    if not player_city or not enemy_city:
        return
    
    var city_line = enemy_city.global_position - player_city.global_position
    var midpoint = (player_city.global_position + enemy_city.global_position) / 2
    var perpendicular = Vector2(-city_line.y, city_line.x).normalized()
    
    frontline_points.clear()
    original_frontline_points.clear()
    var viewport_size = get_viewport().get_visible_rect().size
    var start_point = midpoint + perpendicular * viewport_size.y
    var end_point = midpoint - perpendicular * viewport_size.y
    
    for i in range(100):
        var t = float(i) / 99.0
        var point = start_point.lerp(end_point, t)
        frontline_points.append(point)
        original_frontline_points.append(point)

func get_city(team):
    for child in get_children():
        if child.has_method("_spawn_unit") and child.team == team:
            return child
    return null

func _process(_delta):
    update_unit_lists()
    update_frontline_from_units()
    queue_redraw()

func update_unit_lists():
    player_units.clear()
    enemy_units.clear()
    
    for child in get_children():
        if "team" in child and child.has_method("get_cluster_size"):
            if child.team == 0:
                player_units.append(child)
            elif child.team == 1:
                enemy_units.append(child)

func update_frontline_from_units():
    var player_city = get_city(0)
    var enemy_city = get_city(1)
    if not player_city or not enemy_city:
        return
    
    var all_units = player_units + enemy_units
    
    for unit in all_units:
        for i in range(frontline_points.size()):
            var distance = unit.global_position.distance_to(frontline_points[i])
            if distance < 20:
                var original_point = original_frontline_points[i]
                var unit_direction = determine_unit_advance_direction(unit, player_city, enemy_city)
                
                if unit_has_advanced_past_frontline(unit, original_point, unit_direction):
                    var push_distance = unit.global_position.distance_to(original_point)
                    frontline_points[i] = original_point + unit_direction * push_distance

func determine_unit_advance_direction(unit, player_city, enemy_city):
    if unit.team == 0:
        return (enemy_city.global_position - player_city.global_position).normalized()
    else:
        return (player_city.global_position - enemy_city.global_position).normalized()

func unit_has_advanced_past_frontline(unit, original_frontline_point, advance_direction):
    var to_unit = unit.global_position - original_frontline_point
    return to_unit.dot(advance_direction) > 0

func _draw():
    if frontline_points.size() > 1:
        var smoothed_points = []
        smoothed_points.append(frontline_points[0])
        
        for i in range(1, frontline_points.size() - 1):
            var prev = frontline_points[i - 1]
            var curr = frontline_points[i]
            var next = frontline_points[i + 1]
            smoothed_points.append((prev + curr + next) / 3.0)
        
        smoothed_points.append(frontline_points[-1])
        
        for i in range(smoothed_points.size() - 1):
            draw_line(smoothed_points[i], smoothed_points[i + 1], Color.WHITE, 2.0)

func get_frontline_points():
    return frontline_points

func get_enemy_city_position(unit_team):
    for child in get_children():
        if child.has_method("_spawn_unit"):
            if unit_team == 0 and child.team == 1:
                return child.global_position
            elif unit_team == 1 and child.team == 0:
                return child.global_position
    return Vector2.ZERO

func _input(event):
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_R:
            restart_game()

func restart_game():
    for child in get_children():
        child.queue_free()
    
    player_units.clear()
    enemy_units.clear()
    frontline_points.clear()
    original_frontline_points.clear()
    queue_redraw()
    
    await get_tree().process_frame
    
    pre_place_cities()
    generate_terrain()
    render_terrain()
    spawn_cities()
    create_static_frontline()
    print("Game restarted!")
