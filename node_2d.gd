extends Node2D

var player_units = []
var enemy_units = []
var frontline_points = []
var city_scene = preload("res://city.tscn")

func _ready():
    print("=== BEGIN COMBAT ===")
    spawn_cities()

func spawn_cities():
    var viewport_size = get_viewport().get_visible_rect().size
    var corner_radius = 100
    var margin = 50
    
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

func _process(_delta):
    update_unit_lists()
    calculate_frontline()
    queue_redraw()

func update_unit_lists():
    player_units.clear()
    enemy_units.clear()
    
    for child in get_children():
        if "team" in child:
            if child.team == 0:
                player_units.append(child)
            elif child.team == 1:
                enemy_units.append(child)

func calculate_frontline():
    frontline_points.clear()
    
    # Find cities
    var player_city = null
    var enemy_city = null
    
    for child in get_children():
        if child.has_method("_spawn_unit"):
            if child.team == 0:
                player_city = child
            elif child.team == 1:
                enemy_city = child
    
    if not player_city or not enemy_city:
        return
    
    var viewport_size = get_viewport().get_visible_rect().size
    
    # For each row, find the frontline point
    for y in range(0, int(viewport_size.y), 15):
        var leftmost_x = viewport_size.x
        var rightmost_x = 0.0
        var valid_points = []
        
        # Scan horizontally to find balanced influence points
        for x in range(0, int(viewport_size.x), 10):
            var test_point = Vector2(x, y)
            
            # Base influence from cities
            var player_influence = 1.0 / max(1.0, test_point.distance_to(player_city.global_position))
            var enemy_influence = 1.0 / max(1.0, test_point.distance_to(enemy_city.global_position))
            
            # Add unit influence with distance falloff
            for unit in player_units:
                if unit.has_method("get_cluster_size"):
                    var dist = max(1.0, test_point.distance_to(unit.global_position))
                    # Strong influence only within 80 pixels, then rapid falloff
                    if dist < 80:
                        var cluster_bonus = unit.get_cluster_size() * 0.5
                        player_influence += (3.0 + cluster_bonus) / (dist * dist * 0.01)
            
            for unit in enemy_units:
                if unit.has_method("get_cluster_size"):
                    var dist = max(1.0, test_point.distance_to(unit.global_position))
                    if dist < 80:
                        var cluster_bonus = unit.get_cluster_size() * 0.5
                        enemy_influence += (3.0 + cluster_bonus) / (dist * dist * 0.01)
            
            # Check if balanced
            var total = player_influence + enemy_influence
            if total > 0:
                var balance = abs(player_influence - enemy_influence) / total
                if balance < 0.15:
                    valid_points.append(test_point)
                    leftmost_x = min(leftmost_x, x)
                    rightmost_x = max(rightmost_x, x)
        
        # Add midpoint of valid range for this row
        if valid_points.size() > 0:
            var midpoint_x = (leftmost_x + rightmost_x) / 2
            frontline_points.append(Vector2(midpoint_x, y))

func _draw():
    # Draw frontline as a connected line through the center of the influence balance
    if frontline_points.size() > 1:
        var sorted_points = sort_points_for_curve(frontline_points)
        
        # Draw connected line segments
        for i in range(sorted_points.size() - 1):
            draw_line(sorted_points[i], sorted_points[i + 1], Color.WHITE, 2.0)

func sort_points_for_curve(points: Array) -> Array:
    if points.size() <= 1:
        return points
    
    var sorted = []
    var remaining = points.duplicate()
    
    # Start with leftmost point
    var current = remaining[0]
    for point in remaining:
        if point.x < current.x:
            current = point
    
    sorted.append(current)
    remaining.erase(current)
    
    # Always connect to nearest remaining point
    while remaining.size() > 0:
        var nearest = remaining[0]
        var nearest_dist = current.distance_to(nearest)
        
        for point in remaining:
            var dist = current.distance_to(point)
            if dist < nearest_dist:
                nearest = point
                nearest_dist = dist
        
        sorted.append(nearest)
        remaining.erase(nearest)
        current = nearest
    
    return sorted

func get_frontline_points():
    return frontline_points

func get_enemy_city_position(unit_team):
    # Find the enemy city for this unit's team
    for child in get_children():
        if child.has_method("_spawn_unit"):
            if unit_team == 0 and child.team == 1:  # Player unit targeting enemy city
                return child.global_position
            elif unit_team == 1 and child.team == 0:  # Enemy unit targeting player city
                return child.global_position
    return Vector2.ZERO

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

func toggle_pause():
    get_tree().paused = !get_tree().paused
    print("Game paused!" if get_tree().paused else "Game resumed!")

func restart_game():
    # Remove ALL children
    for child in get_children():
        child.queue_free()
    
    # Clear everything
    player_units.clear()
    enemy_units.clear()
    frontline_points.clear()
    queue_redraw()
    
    await get_tree().process_frame
    
    # Spawn new cities
    spawn_cities()
    print("Game restarted!")
