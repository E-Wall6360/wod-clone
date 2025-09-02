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

func _process(_delta):
    # Handle combat if in contact with enemies
    if enemy_contacts.size() > 0:
        handle_combat(_delta)
        return
    
    # Otherwise move toward enemy center
    var main_scene = get_parent()
    if main_scene.has_method("get_enemy_center"):
        var enemy_center = main_scene.get_enemy_center(team)
        if enemy_center != Vector2.ZERO:
            target_position = enemy_center
            if target_position.distance_to(global_position) > 10:
                var direction = (target_position - global_position).normalized()
                global_position += direction * move_speed * _delta

func handle_combat(_delta):
    # Calculate net force from all enemy contacts
    var net_force = Vector2.ZERO
    var my_cluster_size = get_cluster_size()
    
    for enemy in enemy_contacts:
        var enemy_cluster_size = enemy.get_cluster_size()
        var force_direction = (global_position - enemy.global_position).normalized()
        
        # Force = difference in cluster sizes
        var force_magnitude = my_cluster_size - enemy_cluster_size
        net_force += force_direction * force_magnitude
    
    # Apply the force
    global_position += net_force * move_speed * _delta * 0.1  # Scale down combat movement
