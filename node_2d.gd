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
    TerrainType.WATER: Color.DARK_BLUE,
    TerrainType.SAND: Color.YELLOW,
    TerrainType.MUD: Color(0.6, 0.4, 0.2),
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
    print("Generating spiral-based terrain...")
    # Initialize all as plains (0)
    terrain_data = []
    for y in range(terrain_chunks.y):
        terrain_data.append([])
        for x in range(terrain_chunks.x):
            terrain_data[y].append(TerrainType.PLAINS)
    
    # Create 64 seeds including 2 cities
    var seeds = plant_seeds()
    
    for seed in seeds:
        expand_spiral(seed.x, seed.y, seed.radius)
    
    print("Terrain generation complete")

func plant_seeds() -> Array:
    var seeds = []
    var city_chunks = [world_pos_to_chunk(player_city_pos), world_pos_to_chunk(enemy_city_pos)]
    
    # City seeds
    for city_chunk in city_chunks:
        seeds.append({"x": city_chunk.x, "y": city_chunk.y, "radius": 8})
    
    # Extreme terrain seeds
    for i in range(15):
        var x = randi() % terrain_chunks.x
        var y = randi() % terrain_chunks.y
        if not is_near_city(x, y):
            var extreme_values = [TerrainType.WATER, TerrainType.SAND, TerrainType.ROCKY, TerrainType.SNOW]
            var value = extreme_values[randi() % extreme_values.size()]
            
            # Plant 5x5 seed
            for dy in range(-2, 3):
                for dx in range(-2, 3):
                    var nx = x + dx
                    var ny = y + dy
                    if nx >= 0 and nx < terrain_chunks.x and ny >= 0 and ny < terrain_chunks.y:
                        terrain_data[ny][nx] = value
            
            seeds.append({"x": x, "y": y, "radius": randi_range(8, 20)})
    
    return seeds

func expand_spiral(start_x: int, start_y: int, max_radius: int):
    terrain_data[start_y][start_x] = TerrainType.PLAINS  # Set seed point
    
    for radius in range(1, max_radius + 1):
        var circumference = max(8, radius * 6)

        for i in range(circumference):
            var angle = (float(i) / circumference) * 2 * PI
            var x = start_x + int(radius * cos(angle))
            var y = start_y + int(radius * sin(angle))
            
            if x < 0 or x >= terrain_chunks.x or y < 0 or y >= terrain_chunks.y:
                continue
            
            # Cities never change terrain
            if is_near_city(x, y):
                continue
            
            var current_value = terrain_data[y][x]
            
            # Calculate weighted average of 3x3 neighborhood
            var change_prob = 0.8
            var neighbor_sum = 0
            var neighbor_count = 0
            for dy in range(-1, 2):
                for dx in range(-1, 2):
                    var nx = x + dx
                    var ny = y + dy
                    if nx >= 0 and nx < terrain_chunks.x and ny >= 0 and ny < terrain_chunks.y:
                        neighbor_sum += terrain_data[ny][nx]
                        neighbor_count += 1
            
            var neighborhood_avg = float(neighbor_sum) / neighbor_count
            
            # New value based on neighborhood tendency
            var new_value = current_value
            if randf() < 0.3:
                # Bias toward neighborhood average
                if neighborhood_avg > current_value:
                    new_value = clamp(current_value + 1, TerrainType.WATER, TerrainType.SNOW)
                elif neighborhood_avg < current_value:
                    new_value = clamp(current_value - 1, TerrainType.WATER, TerrainType.SNOW)
                else:
                    var variation = randi() % 3 - 1
                    new_value = clamp(current_value + variation, TerrainType.WATER, TerrainType.SNOW)
            
            terrain_data[y][x] = new_value

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

func get_terrain_speed_multiplier(world_pos: Vector2) -> float:
    var terrain_type = get_terrain_at_position(world_pos)
    return terrain_speeds[terrain_type]

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
