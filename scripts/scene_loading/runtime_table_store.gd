extends RefCounted
class_name RuntimeTableStore

var _loader = null
var _schemas: Dictionary = {}
var _rows_by_table: Dictionary = {}
var _rows_by_uuid: Dictionary = {}

func configure(loader) -> void:
	_loader = loader
	refresh()

func clear() -> void:
	_schemas.clear()
	_rows_by_table.clear()
	_rows_by_uuid.clear()

func refresh() -> void:
	clear()
	if _loader == null or not _loader.has_method("get_runtime_table_schema"):
		return
	for table_id in ["fixtures", "trusses", "scene_objects"]:
		var schema: Dictionary = _loader.get_runtime_table_schema(table_id)
		if schema.is_empty():
			continue
		_schemas[table_id] = schema
		var rows: Array = _loader.get_runtime_table_rows(table_id) if _loader.has_method("get_runtime_table_rows") else []
		_rows_by_table[table_id] = rows.duplicate(true)
		var uuid_lookup: Dictionary = {}
		for row_value in rows:
			if row_value is not Dictionary:
				continue
			var row: Dictionary = row_value
			var row_uuid: String = str(row.get("row_uuid", ""))
			if not row_uuid.is_empty():
				uuid_lookup[row_uuid] = row
		_rows_by_uuid[table_id] = uuid_lookup

func get_schema(table_id: String) -> Dictionary:
	return _schemas.get(table_id, {}).duplicate(true)

func get_rows(table_id: String) -> Array:
	return _rows_by_table.get(table_id, []).duplicate(true)

func get_row(table_id: String, row_uuid: String) -> Dictionary:
	var uuid_lookup: Dictionary = _rows_by_uuid.get(table_id, {})
	return uuid_lookup.get(row_uuid, {}).duplicate(true)

func get_cell(table_id: String, row_uuid: String, column_index: int) -> Variant:
	var row: Dictionary = get_row(table_id, row_uuid)
	var cells: Array = row.get("cells", [])
	if column_index < 0 or column_index >= cells.size():
		return null
	return cells[column_index]
