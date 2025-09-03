extends Node2D

var player_units = []
var enemy_units = []
var frontline_points = []
var original_frontline_points = []
var city_scene = preload("res://city.tscn")

func _ready():
    print("=== BEGIN COMBAT ===")
    spawn_cities()
    create_static_frontline()

func spawn_cities():
    var viewport_size = get_viewport().get_visible_rect().size
    var margin = 50
    var segment_width = viewport_size.x / 4
    
    var player_city = city_scene.instantiate()
    player_city.team = 0
    var player_pos = Vector2(
        randf_range(margin, segment_width - margin),
        randf_range(margin, viewport_size.y - margin)
    )
    player_city.global_position = player_pos
    add_child(player_city)
    
    var enemy_city = city_scene.instantiate()
    enemy_city.team = 1
    var enemy_pos = Vector2(
        randf_range(3 * segment_width + margin, viewport_size.x - margin),
        randf_range(margin, viewport_size.y - margin)
    )
    enemy_city.global_position = enemy_pos
    add_child(enemy_city)

func create_static_frontline():
    var viewport_size = get_viewport().get_visible_rect().size
    var player_city = get_city(0)
    var enemy_city = get_city(1)
    
    if not player_city or not enemy_city:
        return
    
    var city_line = enemy_city.global_position - player_city.global_position
    var midpoint = (player_city.global_position + enemy_city.global_position) / 2
    var perpendicular = Vector2(-city_line.y, city_line.x).normalized()
    
    frontline_points.clear()
    original_frontline_points.clear()
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
        for i in range(frontline_points.size() - 1):
            draw_line(frontline_points[i], frontline_points[i + 1], Color.WHITE, 2.0)

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
    
    spawn_cities()
    create_static_frontline()
    print("Game restarted!")
