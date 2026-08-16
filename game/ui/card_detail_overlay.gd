class_name CardDetailOverlay
extends Control


signal closed


const SCREEN_MARGIN: float = 34.0
const MAX_IMAGE_SCREEN_RATIO: float = 0.90


var _backdrop: Button
var _image_holder: Control
var _card_image: TextureRect
var _current_texture: Texture2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 500

	set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	_build_ui()
	visible = false

	get_viewport().size_changed.connect(
		Callable(self, "_update_image_size")
	)


func _build_ui() -> void:
	# The backdrop is intentionally a Button: tapping anywhere outside the
	# image closes the overlay. The image itself sits above it and consumes
	# pointer input, so tapping the image does not close the overlay.
	_backdrop = Button.new()
	_backdrop.name = "Backdrop"
	_backdrop.text = ""
	_backdrop.focus_mode = Control.FOCUS_NONE
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)

	var backdrop_style := StyleBoxFlat.new()
	backdrop_style.bg_color = Color(0.0, 0.0, 0.0, 0.84)
	backdrop_style.border_width_left = 0
	backdrop_style.border_width_top = 0
	backdrop_style.border_width_right = 0
	backdrop_style.border_width_bottom = 0

	_backdrop.add_theme_stylebox_override(
		"normal",
		backdrop_style
	)
	_backdrop.add_theme_stylebox_override(
		"hover",
		backdrop_style
	)
	_backdrop.add_theme_stylebox_override(
		"pressed",
		backdrop_style
	)
	_backdrop.add_theme_stylebox_override(
		"focus",
		StyleBoxEmpty.new()
	)
	_backdrop.pressed.connect(
		Callable(self, "hide_overlay")
	)
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.name = "ImageCenter"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	add_child(center)

	_image_holder = Control.new()
	_image_holder.name = "ImageHolder"
	_image_holder.mouse_filter = Control.MOUSE_FILTER_STOP
	_image_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_image_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(_image_holder)

	_card_image = TextureRect.new()
	_card_image.name = "InfoImage"
	_card_image.mouse_filter = Control.MOUSE_FILTER_STOP
	_card_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card_image.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_image_holder.add_child(_card_image)


func show_card(
	card: CardInstance,
	_is_disabled: bool = false
) -> void:
	if card == null:
		return

	var definition: CardDefinition = card.definition

	if definition == null:
		return

	_current_texture = definition.info_image

	# Safe fallback while info images are still being assigned in .tres files.
	if _current_texture == null:
		_current_texture = definition.front_texture
		push_warning(
			"Card '%s' has no info_image assigned; using front_texture." % \
			str(definition.card_id)
		)

	if _current_texture == null:
		return

	_card_image.texture = _current_texture
	visible = true
	_update_image_size()

	modulate.a = 0.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(
		self,
		"modulate:a",
		1.0,
		0.10
	)


func hide_overlay() -> void:
	if not visible:
		return

	visible = false
	_current_texture = null
	_card_image.texture = null
	closed.emit()


func is_open() -> bool:
	return visible


func _update_image_size() -> void:
	if not is_instance_valid(_image_holder):
		return

	if _current_texture == null:
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	var available_size := Vector2(
		maxf(
			viewport_size.x - SCREEN_MARGIN * 2.0,
			1.0
		),
		maxf(
			viewport_size.y - SCREEN_MARGIN * 2.0,
			1.0
		)
	)

	available_size *= MAX_IMAGE_SCREEN_RATIO

	var texture_size: Vector2 = _current_texture.get_size()

	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return

	var scale_factor: float = minf(
		available_size.x / texture_size.x,
		available_size.y / texture_size.y
	)

	# Do not enlarge tiny source images beyond their native dimensions.
	scale_factor = minf(scale_factor, 1.0)

	_image_holder.custom_minimum_size = \
		texture_size * scale_factor


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_cancel"):
		hide_overlay()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		if (
			event.pressed
			and not event.echo
			and event.keycode == KEY_ESCAPE
		):
			hide_overlay()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_WM_GO_BACK_REQUEST
		and visible
	):
		hide_overlay()
