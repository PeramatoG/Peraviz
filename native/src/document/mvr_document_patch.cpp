#include "dmx/addressing_fields.h"
#include "document/mvr_document.h"
#include <algorithm>
#include <cctype>
#include <set>
namespace peraviz::document {
namespace {
// Normalize UUID lookup without changing source spelling.
std::string identity(std::string id) {
    std::transform(id.begin(), id.end(), id.begin(), [](unsigned char c) { return char(std::tolower(c)); });
    return id;
}
// Generate only a newly authored entry, never rewrite existing entry attributes.
std::string entry_xml(const PatchEntry &entry) {
    return "<Address break=\"" + std::to_string(entry.break_id) + "\">" + entry.text + "</Address>";
}
} // namespace
// Index canonical ordered assignments once, preserving raw text and optional attribute absence.
void MvrDocument::index_patch(Fixture &f, const tinyxml2::XMLElement *node) {
    const auto *addresses = node->FirstChildElement("Addresses");
    if (!addresses) {
        for (const auto *a = node->FirstAttribute(); a; a = a->Next()) {
            const auto name = identity(a->Name());
            if (name == "universe" || name == "address" || name == "dmxuniverse" || name == "dmxaddress" ||
                name == "absoluteaddress" || name == "absdmxaddress")
                f.patch_reason = "Legacy scalar patch attributes are not canonical Addresses";
        }
        for (auto child = node->FirstChildElement(); child; child = child->NextSiblingElement()) {
            const auto name = identity(child->Name());
            if (name == "universe" || name == "address" || name == "dmxuniverse" || name == "dmxaddress" ||
                name == "absoluteaddress" || name == "absdmxaddress" || name == "dmxabsoluteaddress")
                f.patch_reason = "Legacy scalar patch children are not canonical Addresses";
        }
        return;
    }
    if (addresses->NextSiblingElement("Addresses")) {
        f.patch_reason = "Duplicate Addresses containers";
        return;
    }
    for (size_t i = f.element + 1; i < spans_.size() && spans_[i].start < spans_[f.element].end; ++i)
        if (spans_[i].parent == int(f.element) && spans_[i].name == "Addresses") {
            f.addresses_element = int(i);
            break;
        }
    if (addresses->Attribute("xmlns") && std::string(addresses->Attribute("xmlns")) != "") {
        f.patch_reason = "Addresses uses an unsupported default namespace";
        return;
    }
    std::set<int> seen;
    PatchState parsed;
    size_t position = size_t(f.addresses_element + 1);
    for (auto entry = addresses->FirstChildElement("Address"); entry;
         entry = entry->NextSiblingElement("Address")) {
        PatchEntry value;
        for (; position < spans_.size(); ++position)
            if (spans_[position].parent == f.addresses_element && spans_[position].name == "Address") {
                value.element = int(position++);
                break;
            }
        const char *b = entry->Attribute("break");
        value.explicit_break = b != nullptr;
        if ((b && !dmx::patch_number(b, value.break_id)) || !seen.insert(value.break_id).second ||
            entry->Attribute("Break") || entry->Attribute("xmlns") || value.element < 0) {
            f.patch_reason = "Invalid, duplicate or noncanonical MVR break identifier";
            return;
        }
        for (auto a = entry->FirstAttribute(); a; a = a->Next()) {
            auto name = identity(a->Name());
            if (name == "address" || name == "universe" || name == "absoluteaddress" ||
                name == "dmxaddress") {
                f.patch_reason = "Contradictory Address attribute representation";
                return;
            }
        }
        const auto &span = spans_[value.element];
        if (span.empty) {
            f.patch_reason = "Self-closing Address has no canonical value";
            return;
        }
        value.text = original_xml_.substr(span.content, span.close - span.content);
        if (span.empty || value.text.find('<') != std::string::npos ||
            value.text.find('&') != std::string::npos) {
            f.patch_reason = "Address contains unsupported markup or entity spelling";
            return;
        }
        const auto text = dmx::trim_ascii(value.text);
        const auto dot = text.find('.');
        value.dotted = dot != std::string::npos;
        bool valid = false;
        if (value.dotted)
            valid = dmx::patch_number(text.substr(0, dot), value.universe, 1) &&
                    dmx::patch_number(text.substr(dot + 1), value.address, 1) && value.address <= 512;
        else {
            int absolute = 0;
            valid = dmx::patch_number(text, absolute, 1);
            if (valid) {
                value.universe = 1 + (absolute - 1) / 512;
                value.address = 1 + (absolute - 1) % 512;
            }
        }
        if (!valid) {
            f.patch_reason = "Malformed canonical Address value for break " + std::to_string(value.break_id);
            return;
        }
        if (value.text.size() > 256 || parsed.size() >= 4096) {
            f.patch_reason = "Patch editing bound exceeded (256 text bytes / 4096 entries)";
            return;
        }
        parsed.push_back(std::move(value));
    }
    f.original_patch = std::move(parsed);
    f.current_patch = f.saved_patch = f.original_patch;
}
// Produce disjoint edits against immutable source ranges, keeping Network and extensions byte-identical.
std::vector<XmlEdit> MvrDocument::patch_edits(const Fixture &f, const PatchState &state) const {
    std::vector<XmlEdit> edits;
    if (state == f.original_patch)
        return edits;
    for (const auto &original : f.original_patch) {
        const auto current = std::find_if(state.begin(), state.end(),
                                          [&](const auto &v) { return v.element == original.element; });
        const auto &span = spans_[original.element];
        if (current == state.end())
            edits.push_back({span.start, span.end - span.start, {}});
        else if (current->text != original.text)
            edits.push_back({span.content, span.close - span.content, current->text});
    }
    std::string added;
    for (const auto &entry : state)
        if (entry.element < 0)
            added += entry_xml(entry);
    if (!added.empty()) {
        if (f.addresses_element < 0)
            edits.push_back({spans_[f.element].close, 0, "<Addresses>" + added + "</Addresses>"});
        else {
            const auto &span = spans_[f.addresses_element];
            if (!span.empty)
                edits.push_back({span.close, 0, added});
            else {
                auto opening = original_xml_.substr(span.start, span.end - span.start);
                opening.erase(opening.rfind('/'), 1);
                edits.push_back({span.start, span.end - span.start, opening + added + "</Addresses>"});
            }
        }
    }
    return edits;
}
// Stage one explicit set/insert/remove command; runtime validation precedes document publication.
bool MvrDocument::prepare_patch(const std::string &uuid, int break_id, int universe, int address,
                                const std::string &operation) {
    cancel();
    error_.clear();
    const auto *f = fixture(uuid);
    const std::string context = "Fixture " + uuid + " break " + std::to_string(break_id) + ": ";
    if (!ready() || !f || !f->reason.empty() || !f->patch_reason.empty())
        return fail(context + (f ? (!f->reason.empty() ? f->reason : f->patch_reason)
                                 : "Canonical source identity unavailable"));
    if (break_id < 0 || (operation != "set" && operation != "insert" && operation != "remove"))
        return fail(context + "Invalid patch operation or break identifier");
    if (operation != "remove" && (universe < 1 || universe > 32768 || address < 1 || address > 512))
        return fail(
            context +
            "Universe must be 1–32768 and address 1–512; runtime offset limits are validated separately");
    auto next = f->current_patch;
    auto entry =
        std::find_if(next.begin(), next.end(), [&](const auto &v) { return v.break_id == break_id; });
    if ((operation == "insert") != (entry == next.end()))
        return fail(context +
                    (entry == next.end() ? "No authored assignment exists" : "Break is already assigned"));
    if (operation == "remove")
        next.erase(entry);
    else {
        if (entry == next.end()) {
            PatchEntry created;
            created.break_id = break_id;
            created.explicit_break = true;
            created.dotted = true;
            next.push_back(created);
            entry = next.end() - 1;
        }
        if (entry->universe != universe || entry->address != address) {
            entry->universe = universe;
            entry->address = address;
            entry->text = entry->dotted ? std::to_string(universe) + "." + std::to_string(address)
                                        : std::to_string((int64_t(universe) - 1) * 512 + address);
        }
    }
    if (next != f->current_patch) {
        Change change;
        change.uuid = f->uuid;
        change.kind = Change::Kind::Patch;
        change.patch_break = break_id;
        change.patch_before = f->current_patch;
        change.patch_after = std::move(next);
        pending_.push_back(std::move(change));
    }
    return validate_pending();
}
} // namespace peraviz::document
