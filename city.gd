extends Node2D

enum Team { PLAYER, ENEMY }

@export var team: Team = Team.PLAYER
@export var spawn_interval: float = 3.0  # seconds between spawns
@export var max_units: int = 10  # stop spawning after this many units

var unit_scene = preload("res://unit.tscn")  # Make sure this path matches your unit scene
var spawn_timer: Timer
var units_spawned: int = 0

func _ready():
    # Cities are always yellow regardless of team
    $ColorRect.color = Color.YELLOW
    
    # Create spawn timer
    spawn_timer = Timer.new()
    spawn_timer.wait_time = spawn_interval
    spawn_timer.timeout.connect(_spawn_unit)
    spawn_timer.autostart = true
    add_child(spawn_timer)

func _spawn_unit():
    if units_spawned >= max_units:
        return
        
    var new_unit = unit_scene.instantiate()
    new_unit.team = team
    
    # Get the actual viewport size
    var viewport_size = get_viewport().get_visible_rect().size
    var map_bounds = Rect2(Vector2.ZERO, viewport_size)
    
    var spawn_position = global_position
    var attempts = 0
    
    # Try up to 10 times to find a valid spawn position
    while attempts < 10:
        var offset = Vector2(randf_range(-100, 100), randf_range(-100, 100))
        var test_position = global_position + offset
        
        # Check if position is within viewport bounds
        if map_bounds.has_point(test_position):
            spawn_position = test_position
            break
        attempts += 1
    
    new_unit.global_position = spawn_position
    get_parent().add_child(new_unit)
    
    units_spawned += 1
