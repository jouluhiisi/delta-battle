extends Node2D
class_name Character

enum Animations {
	IDLE, PREP_ATTACK, PREP_ACT, PREP_ITEM, PREP_SPARE, ATTACK, ACT, USE_ITEM, SPARE, DEFEND, FAINT, REVIVE
}

@export var title := ""
@export var weapon: Equippable
@export var armors: Array[Equippable]
@export var current_hp := 100
@export var max_hp := 1
@export var strength := 0:
	get():
		var equipped_strength := 0 if !weapon else weapon.attack
		for armor: Equippable in armors:
			equipped_strength += armor.attack
		return strength + equipped_strength
@export var defense := 0:
	get():
		var equipped_defense := 0 if !weapon else weapon.defense
		for armor: Equippable in armors:
			equipped_defense += armor.defense
		return defense + equipped_defense
@export var magic := 0:
	get():
		var equipped_magic := 0 if !weapon else weapon.magic
		for armor: Equippable in armors:
			equipped_magic += armor.magic
		return magic + equipped_magic
@export var uses_magic := false
@export_color_no_alpha var main_color := Color.WHITE
@export_color_no_alpha var icon_color := Color.GRAY
@export var icon: Texture2D = preload("res://ui/battle/char_menu/res/sample_char_icon.png")

@export_node_path("Sprite2D") var main_sprite
var sprite: Sprite2D
var mat: ShaderMaterial
var alive := true
var defending := false
var shake := 0.0

## The list of default spells the character can use. Only for characters with do_magic set to true.
@export var spells: Array[Spell] = []

signal health_changed(p_new_health: int)
signal act_finished
signal spell_finished
signal item_used
signal spare_finished
signal faint_finished

func _ready() -> void:
	if !main_sprite:
		return
	sprite = get_node(main_sprite)
	mat = ShaderMaterial.new()
	mat.shader = preload("res://characters/generic_character.gdshader")
	sprite.material = mat
	await get_tree().create_timer(randf_range(0.0, 0.6)).timeout
	do_animation(Animations.IDLE)

func swap_armor(p_id: int, p_armor: Equippable) -> void:
	if armors.size() < 2:
		armors.resize(2)
	armors[p_id] = p_armor

func shake_sprite(p_amount: float) -> void:
	shake = p_amount

func do_animation(_p_animation: Animations) -> Signal:
	return get_tree().create_timer(0.1).timeout

func _process(p_delta: float) -> void:
	if shake > 0.0:
		shake = lerpf(shake, 0.0, 1.0 - pow(0.1, p_delta))
		sprite.position = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
		if shake <= 0.1:
			shake = 0.0
			sprite.position = Vector2.ZERO

func get_acts(p_monster: Monster) -> Array[Act]:
	var acts: Array[Act] = []
	
	var check := preload("res://characters/acts/check/check.tres")
	acts.append(check)
	var monster_acts := p_monster.get_acts()
	acts.append_array(monster_acts)
	
	return acts

func get_spells() -> Array[Spell]:
	return spells if !spells.is_empty() else [Spell.new()]

func prep_attack() -> void:
	do_animation(Animations.PREP_ATTACK)

func prep_act() -> void:
	do_animation(Animations.PREP_ACT)

func prep_item() -> void:
	do_animation(Animations.PREP_ITEM)

func prep_spare() -> void:
	do_animation(Animations.PREP_SPARE)

func do_attack(p_monster: Monster, p_damage: int) -> void:
	if p_monster and !p_monster.dying:
		p_monster.take_damage(self, p_damage)
		p_monster.damage_or_die_animation()
		Sounds.play("snd_laz_c")
	await do_animation(Animations.ATTACK)
	do_animation(Animations.IDLE)

func use_item(p_character: Character, p_item: int) -> void:
	await do_animation(Animations.USE_ITEM)
	var item := Global.items[p_item]
	if item == null:
		Global.display_text.emit(title + " tried to use an item that was already used", true)
		await Global.text_finished
		item_used.emit()
		return
	match item.type:
		Item.TYPE.NONE:
			Global.display_text.emit("  * " + title + " used the " + item.name + ".", true)
			await Global.text_finished
			await get_tree().create_timer(0.01).timeout
			Global.display_text.emit("  * But nothing happened...", true)
		Item.TYPE.HEAL:
			p_character.heal(item.amount)
			Global.display_text.emit("  * " + title + " used the " + item.name + "!", true)
			Global.delete_item(p_item)
	await Global.text_finished
	do_animation(Animations.IDLE)
	item_used.emit()

func do_spare(p_monster: Monster) -> void:
	do_animation(Animations.SPARE)
	if p_monster == null:
		do_animation(Animations.IDLE)
		spare_finished.emit()
		return
	
	if p_monster.mercy_percent >= 1.0:
		p_monster.spare()
		await get_tree().create_timer(0.01).timeout
		Global.display_text.emit("  * " + title + " spared " + p_monster.title + "!", true)
		await Global.text_finished
		Sounds.play("snd_spare")
	else:
		await get_tree().create_timer(0.01).timeout
		Global.display_text.emit("  * " + title + " tried to spare " + p_monster.title + ", but couldn't...", true)
		await Global.text_finished
	do_animation(Animations.IDLE)
	spare_finished.emit()

func defend() -> void:
	defending = true
	do_animation(Animations.DEFEND)

func faint() -> void:
	alive = false
	await do_animation(Animations.FAINT)
	faint_finished.emit()

func revive() -> void:
	if current_hp < max_hp * 0.17:
		current_hp = ceili(max_hp * 0.17)
	alive = true
	do_animation(Animations.REVIVE)

func hurt(p_damage: int) -> void:
	shake_sprite(4.0)
	p_damage = int(maxi(1, p_damage - 3 * defense) * (1.0 if !defending else 2.0 / 3.0))
	current_hp -= p_damage
	health_changed.emit(current_hp)
	create_text(str(p_damage), Color.WHITE)
	Sounds.play("snd_hurt1")
	if current_hp <= 0:
		faint()

func heal(p_amount: int) -> void:
	current_hp += p_amount
	Sounds.play("snd_power")
	if !alive and current_hp >= 0:
		revive()
	if current_hp >= max_hp:
		current_hp = max_hp
		create_text("MAX", Global.GREEN)
	else:
		create_text(str(p_amount), icon_color)
	health_changed.emit(current_hp)

func do_act(p_monster: Monster, p_act: int) -> void:
	if p_monster == null:
		await do_animation(Animations.ACT)
		do_animation(Animations.IDLE)
		act_finished.emit()
		return
	
	var acts := get_acts(p_monster)
	acts[p_act].do_act(self, p_monster)

func do_spell(p_entity: Node2D, p_spell: Spell) -> void:
	if p_entity == null:
		await do_animation(Animations.ACT)
		do_animation(Animations.IDLE)
		act_finished.emit()
		return
	
	p_spell.do_spell(self, p_entity)

func set_selected(p_selected: bool) -> void:
	if !mat:
		return
	mat.set_shader_parameter("flash", float(p_selected))

func create_text(p_text: String, p_color: Color) -> void:
	var new_text := preload("res://ui/battle/floating_text/floating_text.tscn").instantiate()
	new_text.initialize(global_position, p_text, p_color)
	get_tree().current_scene.add_child(new_text)
