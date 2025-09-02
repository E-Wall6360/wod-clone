extends Area2D

enum Team { PLAYER, ENEMY }

@export var team: Team = Team.PLAYER
var target_position = Vector2.ZERO
var move_speed = 50.0
var cluster_mates = []
var enemy_contacts = []

func _ready():
    target_position = global_position
    modulate = Color.BLUE if team == Team.PLAYER else Color.RED
    
    # Connect Area2D signals
    area_entered.connect(_on_area_entered)
    area_exited.connect(_on_area_exited)

func _on_area_entered(area):
    if area == self:
        return
        
    if area.team == team:
        # Friendly unit - add to cluster
        if area not in cluster_mates:
            cluster_mates.append(area)
    else:
        # Enemy unit - add to combat
        if area not in enemy_contacts:
            enemy_contacts.append(area)

func _on_area_exited(area):
    if area in cluster_mates:
        cluster_mates.erase(area)
    if area in enemy_contacts:
        enemy_contacts.erase(area)

func get_cluster_size():
    return cluster_mates.size() + 1  # Include self

func find_closest_frontline_point(frontline_points: Array) -> Vector2:
    if frontline_points.size() == 0:
        return Vector2.ZERO
    
    var closest_point = frontline_points[0]
    var closest_distance = global_position.distance_to(closest_point)
    
    for point in frontline_points:
        var distance = global_position.distance_to(point)
        if distance < closest_distance:
            closest_distance = distance
            closest_point = point
    
    return closest_point

func _process(_delta):
    # Handle combat if in contact with enemies
    if enemy_contacts.size() > 0:
        handle_combat(_delta)
        return
    
    # Move toward enemy city, but also be attracted to nearby enemies
    var main_scene = get_parent()
    var city_target = Vector2.ZERO
    
    if main_scene.has_method("get_enemy_city_position"):
        city_target = main_scene.get_enemy_city_position(team)
    
    if city_target == Vector2.ZERO:
        return
    
    # Find nearby enemies to be attracted to
    var nearest_enemy = find_nearest_enemy()
    var movement_direction = Vector2.ZERO
    
    if nearest_enemy and global_position.distance_to(nearest_enemy.global_position) < 150:
        # Blend city direction with enemy attraction
        var city_direction = (city_target - global_position).normalized()
        var enemy_direction = (nearest_enemy.global_position - global_position).normalized()
        movement_direction = (city_direction * 0.6 + enemy_direction * 0.4).normalized()
    else:
        # Just head to city if no nearby enemies
        movement_direction = (city_target - global_position).normalized()
    
    global_position += movement_direction * move_speed * _delta

func find_nearest_enemy():
    var main_scene = get_parent()
    var enemy_units = []
    
    # Get enemy units from main scene
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

func handle_combat(_delta):
    # Calculate net force from all enemy contacts
    var net_force = Vector2.ZERO
    var my_cluster_size = get_cluster_size()
    
    for enemy in enemy_contacts:
        var enemy_cluster_size = enemy.get_cluster_size()
        var force_direction = (global_position - enemy.global_position).normalized()
        
        # Force = difference in cluster sizes (positive means I'm stronger)
        var force_magnitude = my_cluster_size - enemy_cluster_size
        
        # If I'm stronger (positive force), push toward enemy
        # If I'm weaker (negative force), get pushed back
        if force_magnitude > 0:
            # I'm stronger - push toward the enemy
            net_force -= force_direction * force_magnitude
        else:
            # I'm weaker - get pushed back
            net_force += force_direction * abs(force_magnitude)
    
    # Apply the force
    global_position += net_force * move_speed * _delta * 0.1  # Scale down combat movement
