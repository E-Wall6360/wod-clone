extends Area2D

enum Team { PLAYER, ENEMY }

@export var team: Team = Team.PLAYER
var target_position = Vector2.ZERO
var move_speed = 50.0
var cluster_mates = []
var enemy_contacts = []

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
    var viewport_size = get_viewport().get_visible_rect().size
    var margin = 50
    
    # Update contacts based on distance
    update_contacts()
    
    if enemy_contacts.size() > 0:
        var enemy_city = main_scene.get_enemy_city_position(team)
        var dist_to_edge = min(global_position.x, global_position.y, 
                              viewport_size.x - global_position.x, 
                              viewport_size.y - global_position.y)
        var dist_to_city = global_position.distance_to(enemy_city) if enemy_city != Vector2.ZERO else INF
        
        if dist_to_edge < dist_to_city:
            var movement_direction = (enemy_city - global_position).normalized()
            var separation = get_separation_force()
            var combined_force = movement_direction + separation * 2.0
            var new_position = global_position + combined_force.normalized() * move_speed * _delta
            new_position.x = clamp(new_position.x, margin, viewport_size.x - margin)
            new_position.y = clamp(new_position.y, margin, viewport_size.y - margin)
            global_position = new_position
            return
        else:
            handle_combat(_delta)
            return
    
    var nearest_enemy = find_nearest_enemy()
    var enemy_city = main_scene.get_enemy_city_position(team)
    var movement_direction = Vector2.ZERO
    
    if nearest_enemy and global_position.distance_to(nearest_enemy.global_position) < 150:
        movement_direction = (nearest_enemy.global_position - global_position).normalized()
    elif enemy_city != Vector2.ZERO:
        movement_direction = (enemy_city - global_position).normalized()
    
    var separation = get_separation_force()
    var combined_force = movement_direction + separation
    var new_position = global_position + combined_force.normalized() * move_speed * _delta
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

func handle_combat(_delta):
    var enemy_city = main_scene.get_enemy_city_position(team)
    if enemy_city == Vector2.ZERO:
        return
    
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
    var new_position = global_position + combined_force * move_speed * _delta * 0.2
    new_position.x = clamp(new_position.x, margin, viewport_size.x - margin)
    new_position.y = clamp(new_position.y, margin, viewport_size.y - margin)
    
    global_position = new_position
