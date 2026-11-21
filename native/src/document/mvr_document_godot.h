#pragma once
#include "document/mvr_document.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
namespace godot {
class PeravizMvrDocument : public RefCounted {
    GDCLASS(PeravizMvrDocument, RefCounted)
    peraviz::document::MvrDocument document_;

  protected:
    static void _bind_methods();

  public:
    bool open(const String &path);
    Dictionary fixture(const String &uuid) const;
    bool prepare(const PackedStringArray &ids, int axis, bool value);
    bool prepare_history(bool redo);
    bool prepare_patch(const String &uuid, int break_id, int universe, int address, const String &operation);
    bool pending_patch() const;
    Array pending_values() const;
    bool commit();
    void cancel();
    String canonical_path();
    bool export_mvr(const String &path);
    void mark_saved();
    Dictionary state() const;
};
} // namespace godot
