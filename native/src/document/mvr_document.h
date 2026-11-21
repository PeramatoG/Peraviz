#pragma once
#include "document/mvr_inversion.h"
#include "runtime_storage.h"
#include <array>
#include <filesystem>
#include <map>
#include <vector>
namespace tinyxml2 {
class XMLElement;
}
namespace peraviz::document {
struct ElementSpan {
    size_t start = 0, content = 0, close = 0, end = 0;
    std::string name;
    int parent = -1;
    bool empty = false;
};
struct PatchEntry {
    int break_id = 0, universe = 0, address = 0, element = -1;
    bool explicit_break = false, dotted = false;
    std::string text;
    // Compare canonical state including original source spelling and optional presence.
    bool operator==(const PatchEntry &b) const {
        return break_id == b.break_id && universe == b.universe && address == b.address &&
               element == b.element && explicit_break == b.explicit_break && dotted == b.dotted &&
               text == b.text;
    }
};
using PatchState = std::vector<PatchEntry>;
struct XmlEdit {
    size_t start, length;
    std::string text;
};
struct Fixture {
    std::string uuid, reason;
    size_t element = 0;
    std::array<int, 2> fields{{-1, -1}};
    std::array<Inversion, 2> original, current, saved;
    int addresses_element = -1;
    std::string patch_reason;
    PatchState original_patch, current_patch, saved_patch;
};
struct Change {
    std::string uuid;
    int axis = 0;
    Inversion before, after;
    enum class Kind { Inversion, Patch } kind = Kind::Inversion;
    PatchState patch_before, patch_after;
    int patch_break = -1;
};
class MvrDocument {
  public:
    bool open(const std::filesystem::path &source);
    const Fixture *fixture(const std::string &uuid) const;
    bool prepare(const std::vector<std::string> &ids, int axis, bool value);
    bool prepare_history(bool redo);
    bool prepare_patch(const std::string &uuid, int break_id, int universe, int address,
                       const std::string &operation);
    // Identify the staged command without inspecting XML from the UI.
    bool pending_patch() const { return !pending_.empty() && pending_[0].kind == Change::Kind::Patch; }
    bool commit();
    void cancel();
    std::filesystem::path canonical_archive();
    bool export_mvr(const std::filesystem::path &destination);
    void mark_saved();
    // Read cached save-point state without scanning XML or fixtures from the UI.
    bool dirty() const { return dirty_; }
    // Read bounded command availability.
    bool can_undo() const { return cursor_ > 0; }
    // Read bounded redo availability.
    bool can_redo() const { return cursor_ < history_.size(); }
    // Borrow the current staged command until commit or cancellation.
    const std::vector<Change> &pending() const { return pending_; }
    // Read the last actionable operation diagnostic.
    const std::string &error() const { return error_; }
    std::string xml() const;
    // Check whether a supported canonical source is installed.
    bool ready() const { return !original_xml_.empty(); }
    // Borrow the protected imported source identity.
    const std::filesystem::path &original_path() const { return source_; }

  private:
    bool parse();
    void index_patch(Fixture &fixture, const tinyxml2::XMLElement *node);
    std::vector<XmlEdit> patch_edits(const Fixture &fixture, const PatchState &state) const;
    bool validate_pending();
    int64_t size_delta(const Change &change) const;
    bool fail(std::string message);
    runtime_storage::RuntimeDirectoryLease lease_;
    std::filesystem::path source_, snapshot_;
    std::string original_xml_, error_, archive_error_;
    std::vector<ElementSpan> spans_;
    std::map<std::string, Fixture> fixtures_;
    std::vector<std::vector<Change>> history_;
    std::vector<Change> pending_;
    size_t cursor_ = 0;
    int pending_kind_ = 0;
    bool dirty_ = false;
    bool archive_snapshot_valid_ = false;
    int64_t serialized_xml_size_ = 0;
    uint64_t revision_ = 0, cached_revision_ = ~uint64_t(0);
    std::filesystem::path cached_;
};
// Validate ZIP structure without extracting resource payloads; XML is bounded separately.
bool inspect_archive(const std::filesystem::path &path, std::string &xml, std::string &error,
                     bool *safe_zip = nullptr);
// Copy the ZIP on disk, replace only XML, verify resource streams and publish without overwriting.
bool write_archive(const std::filesystem::path &source, const std::filesystem::path &destination,
                   const std::string &xml, bool changed, std::string &error);
} // namespace peraviz::document
