extends Node2D

var player_units = []
var enemy_units = []
var frontline_points = []
var city_scene = preload("res://city.tscn")

func _ready():
    print("=== BEGIN COMBAT ===")
    spawn_cities()

    # Update unit lists every second
    var timer = Timer.new()
    timer.wait_time = 1.0
    timer.timeout.connect(update_unit_lists)
    timer.autostart = true
    add_child(timer)

func spawn_cities():
    var viewport_size = get_viewport().get_visible_rect().size
    var corner_radius = 100  # Smaller radius to keep cities on-screen
    var margin = 50  # Keep cities away from exact edges
    
    # Player city - bottom left corner
    var player_city = city_scene.instantiate()
    player_city.team = 0
    var player_pos = Vector2(
        randf_range(margin, corner_radius),
        randf_range(viewport_size.y - corner_radius, viewport_size.y - margin)
    )
    player_city.global_position = player_pos
    add_child(player_city)
    
    # Enemy city - top right corner  
    var enemy_city = city_scene.instantiate()
    enemy_city.team = 1
    var enemy_pos = Vector2(
        randf_range(viewport_size.x - corner_radius, viewport_size.x - margin),
        randf_range(margin, corner_radius)
    )
    enemy_city.global_position = enemy_pos
    add_child(enemy_city)

func update_unit_lists():
    player_units.clear()
    enemy_units.clear()
    
    for child in get_children():
        if "team" in child:
            if child.team == 0:
                player_units.append(child)
            elif child.team == 1:
                enemy_units.append(child)
    
    calculate_frontline()
    queue_redraw()
    print("Player units: ", player_units.size(), " Enemy units: ", enemy_units.size())

func calculate_frontline():
    frontline_points.clear()
    
    # Find the two cities first
    var player_city = null
    var enemy_city = null
    
    for child in get_children():
        if child.has_method("_spawn_unit"):  # This identifies cities
            if child.team == 0:
                player_city = child
            elif child.team == 1:
                enemy_city = child
    
    if not player_city or not enemy_city:
        return
    
    # Sample points across the map
    var viewport_size = get_viewport().get_visible_rect().size
    var sample_points_x = 20
    var sample_points_y = 15
    
    for x in range(sample_points_x):
        for y in range(sample_points_y):
            var test_point = Vector2(
                x * viewport_size.x / sample_points_x,
                y * viewport_size.y / sample_points_y
            )
            
            var dist_to_player_city = test_point.distance_to(player_city.global_position)
            var dist_to_enemy_city = test_point.distance_to(enemy_city.global_position)
            
            # If distances are roughly equal, this point is on the frontline
            if abs(dist_to_player_city - dist_to_enemy_city) < 30:
                frontline_points.append(test_point)
    
    print("Base-distance frontline points: ", frontline_points.size())

func _draw():
    # Draw frontline as a line
    if frontline_points.size() > 1:
        for i in range(frontline_points.size() - 1):
            draw_line(frontline_points[i], frontline_points[i + 1], Color.GRAY, 3.0)

func get_frontline_points():
    return frontline_points

func get_enemy_center(unit_team):
    if unit_team == 0:  # Player unit, target enemy center
        if enemy_units.size() > 0:
            var center = Vector2.ZERO
            for unit in enemy_units:
                center += unit.global_position
            return center / enemy_units.size()
    else:  # Enemy unit, target player center
        if player_units.size() > 0:
            var center = Vector2.ZERO
            for unit in player_units:
                center += unit.global_position
            return center / player_units.size()
    
    return Vector2.ZERO

func _input(event):
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_R:
            restart_game()

func restart_game():
    # Remove ALL children (including timer)
    for child in get_children():
        child.queue_free()
    
    # Clear everything
    player_units.clear()
    enemy_units.clear()
    frontline_points.clear()
    queue_redraw()
    
    await get_tree().process_frame
    
    # Recreate the timer
    var timer = Timer.new()
    timer.wait_time = 1.0
    timer.timeout.connect(update_unit_lists)
    timer.autostart = true
    add_child(timer)
    
    # Spawn new cities
    spawn_cities()
    print("Game restarted!")
