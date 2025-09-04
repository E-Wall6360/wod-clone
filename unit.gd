extends Area2D

enum Team { PLAYER, ENEMY }

@export var team: Team = Team.PLAYER
var target_position = Vector2.ZERO
const NORMAL_SPEED = 25.0
var move_speed = NORMAL_SPEED
var cluster_mates = []
var enemy_contacts = []

# Encirclement variables
var encircled = false
var encirclement_timer = 0.0
var ENCIRCLEMENT_DEATH_TIME = 3.0
var ENCIRCLEMENT_CHECK_RADIUS = 100.0

@onready var main_scene = get_parent()

func _ready():
    target_position = global_position
    modulate = Color.BLUE if team == Team.PLAYER else Color.RED
    
    area_entered.connect(_on_area_entered)
    area_exited.connect(_on_area_exited)

func _on_area_entered(area):
    if area == self:
        return
        
    if area.team == team:
        if area not in cluster_mates:
            cluster_mates.append(area)
    else:
        if area not in enemy_contacts:
            enemy_contacts.append(area)

func _on_area_exited(area):
    if area in cluster_mates:
        cluster_mates.erase(area)
    if area in enemy_contacts:
        enemy_contacts.erase(area)

func get_cluster_size():
    return cluster_mates.size() + 1

func get_nearby_units():
    var nearby = []
    for child in main_scene.get_children():
        if child != self and child.has_method("get_cluster_size"):
            var distance = global_position.distance_to(child.global_position)
            if distance < 25:
                nearby.append(child)
    return nearby

func check_encirclement():
    var home_city = get_home_city()
    if not home_city:
        encircled = false
        return
    
    var space_state = get_world_2d().direct_space_state
    var has_escape_route = false
    
    # Check path to home city
    var query = PhysicsRayQueryParameters2D.create(global_position, home_city.global_position)
    query.exclude = [self]
    query.collide_with_areas = true
    query.collide_with_bodies = false
    var result = space_state.intersect_ray(query)
    
    if not result or not ("team" in result.collider) or result.collider.team == team:
        has_escape_route = true
    
    # If no path to home, check paths to nearby friendlies
    if not has_escape_route:
        var nearby_friendlies = get_nearby_friendlies()
        for target in nearby_friendlies:
            query = PhysicsRayQueryParameters2D.create(global_position, target.global_position)
            query.exclude = [self]
            query.collide_with_areas = true
            query.collide_with_bodies = false
            result = space_state.intersect_ray(query)
            
            if not result or not ("team" in result.collider) or result.collider.team == team:
                has_escape_route = true
                break
    
    encircled = not has_escape_route

func get_home_city():
    for child in main_scene.get_children():
        if child.has_method("_spawn_unit") and child.team == team:
            return child
    return null

func get_nearby_friendlies():
    var friendlies = []
    for child in main_scene.get_children():
        if child != self and "team" in child and child.team == team:
            var distance = global_position.distance_to(child.global_position)
            if distance < ENCIRCLEMENT_CHECK_RADIUS:
                friendlies.append(child)
    return friendlies

func handle_encirclement_effects(delta):
    encirclement_timer += delta
    var original_color = Color.BLUE if team == Team.PLAYER else Color.RED
    modulate = original_color.lerp(Color.WHITE, 0.35)  # Mix 35% white with original color
    move_speed = move_speed * 0.5

func get_separation_force() -> Vector2:
    var separation = Vector2.ZERO
    var nearby = get_nearby_units()
    
    for unit in nearby:
        var distance = global_position.distance_to(unit.global_position)
        if distance > 0:
            var away = (global_position - unit.global_position).normalized()
            separation += away * (25 - distance) / distance
    
    return separation

func _process(_delta):
    check_encirclement()
    
    if encircled:
        handle_encirclement_effects(_delta)
        if encirclement_timer >= ENCIRCLEMENT_DEATH_TIME:
            queue_free()
            return
    else:
        encirclement_timer = 0.0
        modulate = Color.BLUE if team == Team.PLAYER else Color.RED
        move_speed = NORMAL_SPEED
    
    var viewport_size = get_viewport().get_visible_rect().size
    var margin = 50
    
    # Get terrain speed multiplier for current position
    var terrain_multiplier = main_scene.get_terrain_speed_multiplier(global_position)
    var actual_speed = move_speed * terrain_multiplier
    
    # Update contacts based on distance
    update_contacts()
    
    if enemy_contacts.size() > 0:
        handle_combat(_delta)
        return
    
    # Use terrain-aware pathfinding for movement
    var nearest_enemy = find_nearest_enemy()
    var enemy_city = main_scene.get_enemy_city_position(team)
    var target_pos = Vector2.ZERO
    
    if nearest_enemy and global_position.distance_to(nearest_enemy.global_position) < 150:
        target_pos = nearest_enemy.global_position
    elif enemy_city != Vector2.ZERO:
        target_pos = enemy_city
    else:
        return  # No target
    
    # Get the smart movement direction
    var movement_direction = get_best_movement_direction(target_pos)
    var separation = get_separation_force()
    var combined_force = movement_direction + separation
    
    var new_position = global_position + combined_force.normalized() * actual_speed * _delta
    new_position.x = clamp(new_position.x, margin, viewport_size.x - margin)
    new_position.y = clamp(new_position.y, margin, viewport_size.y - margin)
    
    global_position = new_position

func update_contacts():
    enemy_contacts.clear()
    cluster_mates.clear()
    
    var nearby = get_nearby_units()
    for unit in nearby:
        if unit.team == team:
            cluster_mates.append(unit)
        else:
            enemy_contacts.append(unit)

func find_nearest_enemy():
    var enemy_units = []
    
    for child in main_scene.get_children():
        if "team" in child and child.team != team and child.has_method("get_cluster_size"):
            enemy_units.append(child)
    
    if enemy_units.size() == 0:
        return null
    
    var nearest = enemy_units[0]
    var nearest_dist = global_position.distance_to(nearest.global_position)
    
    for enemy in enemy_units:
        var dist = global_position.distance_to(enemy.global_position)
        if dist < nearest_dist:
            nearest = enemy
            nearest_dist = dist
    
    return nearest

func get_best_movement_direction(target_pos: Vector2) -> Vector2:
    # If we're already on good terrain and close to target, just go direct
    var current_terrain_speed = main_scene.get_terrain_speed_multiplier(global_position)
    var distance_to_target = global_position.distance_to(target_pos)
    
    if current_terrain_speed >= 0.75 and distance_to_target < 100:
        return (target_pos - global_position).normalized()
    
    # Sample 8 directions around the unit
    var best_direction = Vector2.ZERO
    var best_score = -999.0
    var sample_distance = 50.0  # How far ahead to look
    
    for i in range(8):
        var angle = i * PI / 4.0  # 0, 45, 90, 135, 180, 225, 270, 315 degrees
        var test_direction = Vector2(cos(angle), sin(angle))
        var test_position = global_position + test_direction * sample_distance
        
        # Get terrain speed at test position
        var terrain_speed = main_scene.get_terrain_speed_multiplier(test_position)
        
        # Calculate progress toward target (dot product)
        var direct_to_target = (target_pos - global_position).normalized()
        var progress_factor = test_direction.dot(direct_to_target)
        
        # Score = terrain_quality * progress_toward_target
        # Terrain weight is higher so units really avoid bad terrain
        var score = terrain_speed * 2.0 + progress_factor * 1.0
        
        if score > best_score:
            best_score = score
            best_direction = test_direction
    
    # Fallback to direct path if no good options found
    if best_direction == Vector2.ZERO:
        return (target_pos - global_position).normalized()
    
    return best_direction

func handle_combat(_delta):
    var enemy_city = main_scene.get_enemy_city_position(team)
    if enemy_city == Vector2.ZERO:
        return
    
    # Get terrain speed multiplier for current position
    var terrain_multiplier = main_scene.get_terrain_speed_multiplier(global_position)
    var actual_speed = move_speed * terrain_multiplier
    
    var toward_target = (enemy_city - global_position).normalized()
    var my_cluster_size = get_cluster_size()
    var total_enemy_size = 0
    
    for enemy in enemy_contacts:
        total_enemy_size += enemy.get_cluster_size()
    
    var force_magnitude = my_cluster_size - total_enemy_size
    var net_force = toward_target * force_magnitude
    
    var separation = get_separation_force()
    var combined_force = net_force + separation
    
    var viewport_size = get_viewport().get_visible_rect().size
    var margin = 50
    var new_position = global_position + combined_force * actual_speed * _delta * 0.2
    new_position.x = clamp(new_position.x, margin, viewport_size.x - margin)
    new_position.y = clamp(new_position.y, margin, viewport_size.y - margin)
    
    global_position = new_position
