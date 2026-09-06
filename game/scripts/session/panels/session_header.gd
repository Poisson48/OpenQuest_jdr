extends PanelContainer
class_name SessionHeaderPanel

## Bandeau de session : où l'on est, qui on est, depuis combien de temps.
## Structure dans `scenes/session/panels/session_header.tscn`.

signal leave_pressed
signal docks_toggled(shown: bool)
signal preview_toggled(active: bool)

@onready var _btn_leave: Button = %BtnLeave
@onready var _title: Label = %LblTitle
@onready var _progress: Label = %LblProgress
@onready var _role_badge: Label = %LblRole
@onready var _btn_docks: Button = %BtnDocks
@onready var _btn_preview: Button = %BtnPreview
@onready var _timer: Label = %LblTimer
@onready var _net_dot: Label = %LblNetDot
@onready var _net_label: Label = %LblNet

func _ready() -> void:
	_btn_leave.pressed.connect(func(): leave_pressed.emit())
	_btn_docks.toggled.connect(func(on: bool): docks_toggled.emit(on))
	_btn_preview.toggled.connect(func(on: bool): preview_toggled.emit(on))

func set_header(header: Dictionary) -> void:
	_title.text = str(header.get("title", "Session"))
	var progress := str(header.get("progress", ""))
	_progress.text = progress
	_progress.tooltip_text = progress
	_progress.visible = not progress.is_empty()

func set_role(role: SessionRoleView) -> void:
	_role_badge.text = role.label
	var tint := ThemeColors.ACCENT if role.kind == SessionRoleView.KIND_GM else ThemeColors.SUCCESS
	if role.completed:
		tint = ThemeColors.TEXT_MUTED
	_role_badge.add_theme_color_override("font_color", tint)
	var gm_view := role.kind == SessionRoleView.KIND_GM
	_btn_docks.visible = gm_view
	_btn_preview.visible = gm_view

func set_net(net: Dictionary) -> void:
	var online := bool(net.get("online", false))
	_net_label.text = str(net.get("text", ""))
	_net_dot.add_theme_color_override(
		"font_color", ThemeColors.SUCCESS if online else ThemeColors.TEXT_MUTED
	)

func set_elapsed(seconds: int) -> void:
	_timer.text = "%02d:%02d" % [seconds / 60, seconds % 60]

func set_preview_active(active: bool) -> void:
	_btn_preview.set_pressed_no_signal(active)

func set_docks_shown(shown: bool) -> void:
	_btn_docks.set_pressed_no_signal(shown)
