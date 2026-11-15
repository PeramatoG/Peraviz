#include "document/mvr_document.h"
#include "document/mvr_inversion_xml.h"
#include <algorithm>
#include <cctype>
#include <functional>
#include <set>
#include <string_view>
namespace peraviz::document {
namespace {
// Accept XML 1.0 characters, including valid supplementary Unicode codepoints.
bool xml_character(uint32_t c) {
    return c == 9 || c == 10 || c == 13 || (c >= 32 && c <= 0xd7ff) || (c >= 0xe000 && c <= 0xfffd) ||
           (c >= 0x10000 && c <= 0x10ffff);
}
// Reject invalid/overlong UTF-8 rather than letting a permissive parser reinterpret source bytes.
bool utf8_xml(std::string_view text) {
    for (size_t i = 0; i < text.size();) {
        uint32_t c = uint8_t(text[i++]);
        int tails = 0;
        uint32_t minimum = 0;
        if (c >= 0xc2 && c <= 0xdf) {
            c &= 31;
            tails = 1;
            minimum = 0x80;
        } else if (c >= 0xe0 && c <= 0xef) {
            c &= 15;
            tails = 2;
            minimum = 0x800;
        } else if (c >= 0xf0 && c <= 0xf4) {
            c &= 7;
            tails = 3;
            minimum = 0x10000;
        } else if (c >= 128)
            return false;
        for (int j = 0; j < tails; ++j) {
            if (i == text.size() || (uint8_t(text[i]) & 0xc0) != 0x80)
                return false;
            c = (c << 6) | (uint8_t(text[i++]) & 63);
        }
        if (c < minimum || !xml_character(c))
            return false;
    }
    return true;
}
// Validate entity spelling outside comments/CDATA without expanding or normalizing the source.
bool entities(std::string_view text) {
    for (size_t i = 0; (i = text.find('&', i)) != std::string_view::npos; ++i) {
        const auto end = text.find(';', i + 1);
        if (end == std::string_view::npos || end - i > 32)
            return false;
        auto name = text.substr(i + 1, end - i - 1);
        if (name == "amp" || name == "lt" || name == "gt" || name == "quot" || name == "apos") {
            i = end;
            continue;
        }
        if (name.empty() || name.front() != '#')
            return false;
        size_t digit = 1;
        uint32_t value = 0, base = 10;
        if (digit < name.size() && name[digit] == 'x') {
            base = 16;
            ++digit;
        }
        if (digit == name.size())
            return false;
        for (; digit < name.size(); ++digit) {
            char c = name[digit];
            int v = c >= '0' && c <= '9'   ? c - '0'
                    : c >= 'a' && c <= 'f' ? c - 'a' + 10
                    : c >= 'A' && c <= 'F' ? c - 'A' + 10
                                           : -1;
            if (v < 0 || uint32_t(v) >= base || value > 0x10ffff / base)
                return false;
            value = value * base + uint32_t(v);
        }
        if (!xml_character(value))
            return false;
        i = end;
    }
    return true;
}
// Canonical UUID comparison is case-insensitive; source spelling is never rewritten.
std::string key(std::string text) {
    for (auto &c : text)
        c = char(std::tolower(static_cast<unsigned char>(c)));
    return text;
}
// Reject missing, synthetic and nil identifiers rather than matching display names.
bool canonical(const std::string &id) {
    if (id.size() != 36)
        return false;
    bool nonzero = false;
    for (size_t i = 0; i < id.size(); ++i) {
        if (i == 8 || i == 13 || i == 18 || i == 23) {
            if (id[i] != '-')
                return false;
        } else {
            if (!std::isxdigit(static_cast<unsigned char>(id[i])))
                return false;
            nonzero |= id[i] != '0';
        }
    }
    return nonzero;
}
} // namespace
// Retain an immutable disk snapshot and bounded source XML; no binary resources are materialized.
bool MvrDocument::open(const std::filesystem::path &source) {
    revision_ = 0;
    cached_revision_ = ~uint64_t(0);
    cached_.clear();
    dirty_ = false;
    archive_snapshot_valid_ = false;
    fixtures_.clear();
    spans_.clear();
    history_.clear();
    pending_.clear();
    cursor_ = 0;
    pending_kind_ = 0;
    original_xml_.clear();
    error_.clear();
    archive_error_.clear();
    std::error_code path_error;
    source_ = std::filesystem::absolute(source, path_error);
    if (path_error || source.empty())
        return fail("Choose a readable MVR source filename");
    lease_ = runtime_storage::create_session_cache_directory("mvr-document");
    if (!lease_.valid())
        return fail("Cannot create scene-owned document workspace");
    snapshot_ = lease_.path() / "original.mvr";
    std::error_code ec;
    if (!std::filesystem::copy_file(source_, snapshot_, std::filesystem::copy_options::none, ec))
        return fail("Cannot snapshot source MVR: " + ec.message());
    if (!inspect_archive(snapshot_, original_xml_, error_, &archive_snapshot_valid_)) {
        archive_error_ = error_;
        original_xml_.clear();
        return false;
    }
    archive_snapshot_valid_ = true;
    if (!parse()) {
        archive_error_ = error_;
        original_xml_.clear();
        return false;
    }
    serialized_xml_size_ = int64_t(original_xml_.size());
    return true;
}
// Keep the first actionable operation diagnostic available to the caller.
bool MvrDocument::fail(std::string message) {
    error_ = std::move(message);
    return false;
}
// Index lexical element ranges once and cross-check their preorder against a real XML parser.
bool MvrDocument::parse() {
    if (!utf8_xml(original_xml_))
        return fail("Invalid UTF-8 or XML characters; document cannot be edited safely");
    tinyxml2::XMLDocument dom;
    if (dom.Parse(original_xml_.data(), original_xml_.size()) != tinyxml2::XML_SUCCESS)
        return fail("Malformed scene XML");
    auto root = dom.RootElement();
    if (!root || std::string(root->Name()) != "GeneralSceneDescription" || root->Attribute("xmlns"))
        return fail("Editing requires unprefixed canonical MVR XML without a default namespace");
    if (root->IntAttribute("verMajor") != 1 || !root->Attribute("verMinor") ||
        root->IntAttribute("verMinor") < 0 || root->IntAttribute("verMinor") > 6)
        return fail("Unsupported MVR version for canonical editing (supported: 1.0–1.6)");
    auto scene = root->FirstChildElement("Scene");
    auto layers = scene ? scene->FirstChildElement("Layers") : nullptr;
    if (!scene || scene->NextSiblingElement("Scene") || !layers || layers->NextSiblingElement("Layers"))
        return fail("Editing requires one canonical Scene and Layers collection");
    auto declaration = dom.FirstChild() ? dom.FirstChild()->ToDeclaration() : nullptr;
    if (declaration) {
        std::string d = key(declaration->Value());
        auto enc = d.find("encoding");
        if (enc != std::string::npos && d.find("utf-8", enc) == std::string::npos)
            return fail("Editing requires UTF-8 XML");
    }
    std::vector<int> stack;
    size_t scanned = 0;
    for (size_t pos = 0; (pos = original_xml_.find('<', pos)) != std::string::npos;) {
        const size_t start = pos;
        if (!entities(std::string_view(original_xml_).substr(scanned, start - scanned)))
            return fail("Unsupported or malformed XML entity");
        if (original_xml_.compare(pos, 4, "<!--") == 0 || original_xml_.compare(pos, 9, "<![CDATA[") == 0 ||
            original_xml_.compare(pos, 2, "<?") == 0) {
            const std::string terminator = original_xml_.compare(pos, 4, "<!--") == 0        ? "-->"
                                           : original_xml_.compare(pos, 9, "<![CDATA[") == 0 ? "]]>"
                                                                                             : "?>";
            auto end = original_xml_.find(terminator, pos);
            if (end == std::string::npos)
                return fail("Unterminated XML token");
            pos = end + terminator.size();
            scanned = pos;
            continue;
        }
        if (original_xml_.compare(pos, 2, "<!") == 0)
            return fail("Unsupported XML declaration");
        char quote = 0;
        size_t end = pos + 1;
        for (; end < original_xml_.size(); ++end) {
            char c = original_xml_[end];
            if (quote) {
                if (c == quote)
                    quote = 0;
            } else if (c == '\'' || c == '"')
                quote = c;
            else if (c == '>')
                break;
        }
        if (end == original_xml_.size())
            return fail("Unterminated XML tag");
        if (!entities(std::string_view(original_xml_).substr(start, end - start + 1)))
            return fail("Unsupported XML attribute entity");
        bool closing = original_xml_[pos + 1] == '/';
        size_t begin = pos + (closing ? 2 : 1), name_end = begin;
        while (name_end < end && !std::isspace(static_cast<unsigned char>(original_xml_[name_end])) &&
               original_xml_[name_end] != '/' && original_xml_[name_end] != '>')
            ++name_end;
        const auto name = original_xml_.substr(begin, name_end - begin);
        if (closing) {
            if (stack.empty() || spans_[stack.back()].name != name)
                return fail("XML range validation failed");
            auto &span = spans_[stack.back()];
            span.close = start;
            span.end = end + 1;
            stack.pop_back();
        } else {
            ElementSpan span;
            span.start = start;
            span.content = end + 1;
            span.name = name;
            span.parent = stack.empty() ? -1 : stack.back();
            span.empty = original_xml_[end - 1] == '/';
            if (span.empty)
                span.close = start, span.end = end + 1;
            spans_.push_back(span);
            if (!span.empty)
                stack.push_back(int(spans_.size() - 1));
            if (stack.size() > 256 || spans_.size() > 500000)
                return fail("XML editing complexity bound exceeded");
        }
        pos = end + 1;
        scanned = pos;
    }
    if (!entities(std::string_view(original_xml_).substr(scanned)))
        return fail("Unsupported XML trailing entity");
    if (!stack.empty())
        return fail("Unclosed XML element");
    std::vector<const tinyxml2::XMLElement *> elements;
    std::function<void(const tinyxml2::XMLElement *)> visit = [&](auto node) {
        elements.push_back(node);
        for (auto c = node->FirstChildElement(); c; c = c->NextSiblingElement())
            visit(c);
    };
    visit(root);
    if (elements.size() != spans_.size())
        return fail("XML lexical/DOM identity mismatch");
    std::map<std::string, int> counts;
    for (size_t i = 0; i < elements.size(); ++i) {
        if (spans_[i].name != elements[i]->Name())
            return fail("XML lexical/DOM order mismatch");
        if (auto id = elements[i]->Attribute("uuid"))
            ++counts[key(id)];
    }
    for (size_t i = 0; i < elements.size(); ++i) {
        auto node = elements[i];
        if (std::string(node->Name()) != "Fixture")
            continue;
        Fixture f;
        f.element = i;
        f.uuid = node->Attribute("uuid") ? node->Attribute("uuid") : "";
        bool canonical_scene = false, canonical_layers = false;
        bool foreign_namespace = node->Attribute("xmlns") && std::string(node->Attribute("xmlns")) != "";
        for (int parent = spans_[i].parent; parent >= 0; parent = spans_[parent].parent) {
            canonical_scene |= elements[parent] == scene;
            canonical_layers |= elements[parent] == layers;
            if (auto ns = elements[parent]->Attribute("xmlns"))
                foreign_namespace |= std::string(ns) != "";
        }
        if (!canonical_scene || !canonical_layers)
            continue; // Definitions/extension objects are not canonical scene fixtures.
        if (foreign_namespace)
            f.reason = "Fixture inherits a foreign default namespace; canonical mutation is unsafe";
        else if (!canonical(f.uuid))
            f.reason = "Fixture has missing, synthetic or invalid canonical UUID";
        else if (counts[key(f.uuid)] != 1)
            f.reason = "Fixture UUID is duplicated or ambiguous in the source document";
        else if (spans_[i].empty)
            f.reason = "Self-closing Fixture nodes are not editable in this phase";
        for (int axis = 0; axis < 2; ++axis) {
            const char *name = axis ? "DMXInvertTilt" : "DMXInvertPan";
            f.original[axis] = f.current[axis] = f.saved[axis] = read_inversion(node, name);
            if (!f.original[axis].valid)
                f.reason = f.original[axis].diagnostic;
            for (size_t j = i + 1; j < spans_.size() && spans_[j].start < spans_[i].end; ++j)
                if (spans_[j].parent == int(i) && spans_[j].name == name) {
                    f.fields[axis] = int(j);
                    const auto &field = spans_[j];
                    if (field.empty ||
                        original_xml_.substr(field.content, field.close - field.content).find('<') !=
                            std::string::npos)
                        f.reason = "Inversion field contains unsupported markup; preserving it requires a "
                                   "different editor";
                }
        }
        fixtures_[key(f.uuid)] = std::move(f);
    }
    return true;
}
// Resolve only canonical indexed identities, never names or generated paths.
const Fixture *MvrDocument::fixture(const std::string &uuid) const {
    auto i = fixtures_.find(key(uuid));
    return i == fixtures_.end() ? nullptr : &i->second;
}
// Compute byte-size changes from indexed field ranges without copying or reparsing XML.
int64_t MvrDocument::size_delta(const Change &change) const {
    const auto &f = fixtures_.at(key(change.uuid));
    const auto delta = [&](const Inversion &state) -> int64_t {
        if (state == f.original[change.axis])
            return 0;
        const int64_t text = state.value ? 4 : 5;
        if (f.fields[change.axis] >= 0) {
            const auto &span = spans_[f.fields[change.axis]];
            return text - int64_t(span.close - span.content);
        }
        return state.present
                   ? text +
                         int64_t(std::string(change.axis ? "DMXInvertTilt" : "DMXInvertPan").size() * 2 + 5)
                   : 0;
    };
    return delta(change.after) - delta(change.before);
}

// Validate the entire selection and stage one bounded atomic property command.
bool MvrDocument::prepare(const std::vector<std::string> &ids, int axis, bool value) {
    cancel();
    error_.clear();
    if (!ready())
        return fail(archive_error_.empty() ? "No editable MVR document" : archive_error_);
    if (axis < 0 || axis > 1 || ids.empty() || ids.size() > 100000)
        return fail("Invalid inversion command selection");
    std::set<std::string> seen;
    for (const auto &id : ids) {
        auto f = fixture(id);
        if (!f || !f->reason.empty()) {
            cancel();
            return fail(f ? f->reason : "Selection does not identify a canonical source Fixture: " + id);
        }
        if (!seen.insert(key(id)).second)
            continue;
        Inversion next;
        next.present = true;
        next.value = value;
        // A request for the existing effective value is a semantic no-op, preserving absence.
        if (f->current[axis].value != value)
            pending_.push_back({f->uuid, axis, f->current[axis], next});
    }
    size_t retained = pending_.size();
    for (size_t i = 0; i < cursor_; ++i)
        retained += history_[i].size();
    if (retained > 200000) {
        cancel();
        return fail("Undo change bound reached; save/reopen before more edits");
    }
    if (cursor_ >= 4096) {
        cancel();
        return fail("Undo command bound reached; save/reopen before more edits");
    }
    int64_t projected = serialized_xml_size_;
    for (const auto &change : pending_)
        projected += size_delta(change);
    if (projected > 32 * 1024 * 1024) {
        cancel();
        return fail("The edit would exceed the 32 MiB XML bound; reduce the selection or document size");
    }
    pending_kind_ = 1;
    return true;
}
// Stage Undo or Redo without publishing any document/runtime state yet.
bool MvrDocument::prepare_history(bool redo) {
    cancel();
    error_.clear();
    if (redo ? !can_redo() : !can_undo())
        return fail("No document command available");
    pending_ = history_[redo ? cursor_ : cursor_ - 1];
    if (!redo)
        for (auto &change : pending_)
            std::swap(change.before, change.after);
    pending_kind_ = redo ? 3 : 2;
    return true;
}
// Publish an already validated command after its native runtime transaction succeeds.
bool MvrDocument::commit() {
    if (!pending_kind_)
        return fail("No staged document command");
    if (pending_.empty()) {
        cancel();
        return true;
    }
    if (pending_kind_ == 1) {
        history_.resize(cursor_);
        history_.push_back(pending_);
        ++cursor_;
    } else if (pending_kind_ == 2)
        --cursor_;
    else
        ++cursor_;
    for (const auto &change : pending_)
        fixtures_.at(key(change.uuid)).current[change.axis] = change.after;
    for (const auto &change : pending_)
        serialized_xml_size_ += size_delta(change);
    ++revision_;
    dirty_ = false;
    for (const auto &[id, f] : fixtures_)
        dirty_ |= f.current != f.saved;
    cancel();
    return true;
}
// Abandon a staged command without modifying history, XML or canonical values.
void MvrDocument::cancel() {
    pending_.clear();
    pending_kind_ = 0;
}
// Record a successful PVZ save point; the original snapshot remains available for exact Undo.
void MvrDocument::mark_saved() {
    for (auto &[id, f] : fixtures_)
        f.saved = f.current;
    dirty_ = false;
}
// Splice only supported field text or new children; all other source bytes remain untouched.
std::string MvrDocument::xml() const {
    struct Patch {
        size_t start, length;
        std::string text;
    };
    std::vector<Patch> patches;
    for (const auto &[id, f] : fixtures_) {
        std::string insert;
        for (int axis = 0; axis < 2; ++axis) {
            if (f.current[axis] == f.original[axis])
                continue;
            const char *name = axis ? "DMXInvertTilt" : "DMXInvertPan";
            const std::string value = f.current[axis].value ? "true" : "false";
            if (f.fields[axis] >= 0) {
                auto &field = spans_[f.fields[axis]];
                patches.push_back({field.content, field.close - field.content, value});
            } else if (f.current[axis].present)
                insert += "<" + std::string(name) + ">" + value + "</" + name + ">";
        }
        if (!insert.empty())
            patches.push_back({spans_[f.element].close, 0, insert});
    }
    std::sort(patches.begin(), patches.end(), [](const auto &a, const auto &b) { return a.start > b.start; });
    std::string result = original_xml_;
    for (const auto &patch : patches)
        result.replace(patch.start, patch.length, patch.text);
    return result;
}
// Materialize one canonical archive per revision, shared by PVZ persistence and standalone export.
std::filesystem::path MvrDocument::canonical_archive() {
    error_.clear();
    if (!ready()) {
        error_ = archive_error_.empty() ? "No source document" : archive_error_;
        // Preserve the old opaque PVZ copy path, without authorizing edits or canonical MVR export.
        return archive_snapshot_valid_ ? snapshot_ : std::filesystem::path{};
    }
    if (cached_revision_ == revision_)
        return cached_;
    auto edited = xml();
    if (edited == original_xml_) {
        if (!cached_.empty() && cached_ != snapshot_) {
            std::error_code ec;
            std::filesystem::remove(cached_, ec);
        }
        cached_ = snapshot_;
        cached_revision_ = revision_;
        return cached_;
    }
    auto candidate = lease_.path() / ("canonical-" + std::to_string(revision_) + ".mvr");
    if (!write_archive(snapshot_, candidate, edited, true, error_))
        return {};
    if (!cached_.empty() && cached_ != snapshot_) {
        std::error_code ec;
        std::filesystem::remove(cached_, ec);
    }
    cached_ = candidate;
    cached_revision_ = revision_;
    return cached_;
}
// Copy the authoritative serialization; export and PVZ can never diverge into separate XML writers.
bool MvrDocument::export_mvr(const std::filesystem::path &destination) {
    error_.clear();
    if (!ready())
        return fail(archive_error_.empty() ? "No supported canonical MVR document" : archive_error_);
    const auto source = canonical_archive();
    if (source.empty())
        return false;
    std::error_code ec;
    const auto dest = std::filesystem::absolute(destination, ec);
    if (ec || destination.empty())
        return fail("Choose a valid new export filename");
    if (dest == source_ ||
        (std::filesystem::exists(dest, ec) && std::filesystem::equivalent(dest, source_, ec)))
        return fail("Export cannot overwrite the imported MVR; choose a new filename");
    return write_archive(source, dest, xml(), false, error_);
}
} // namespace peraviz::document
