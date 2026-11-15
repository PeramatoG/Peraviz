#include "archive/zip_archive.h"
#include "document/mvr_document.h"
#include <cstring>
#include <fstream>
#include <iostream>
using peraviz::document::MvrDocument;
namespace {
// Report source-preservation failures without changing the existing test infrastructure.
bool check(bool value, const char *message) {
    if (!value)
        std::cerr << message << '\n';
    return value;
}
// Read binary test outputs for exact archive comparisons.
std::string bytes(const std::filesystem::path &p) {
    std::ifstream in(p, std::ios::binary);
    return {std::istreambuf_iterator<char>(in), {}};
}
// Generate public synthetic MVRs with unknown XML, namespace extensions and large repeated resources.
bool archive(const std::filesystem::path &p, const std::string &body, const std::string &extra = {}) {
    peraviz::archive::ZipArchive zip;
    if (!zip.open_create_or_modify(p))
        return false;
    const std::string xml =
        "<?xml version='1.0' encoding='UTF-8'?><GeneralSceneDescription verMajor='1' verMinor='6' "
        "xmlns:x='urn:vendor' x:extra='untouched'><UserData><Data provider='Other'><x:Thing>&amp; "
        "preserved</x:Thing></Data></UserData><Scene><Layers><Layer uuid='layer'><ChildList><GroupObject "
        "uuid='group' name='Éclairage'><Matrix>{1,0,0}{0,1,0}{0,0,1}{1,2,3}</Matrix><ChildList>" +
        body + "</ChildList></GroupObject></ChildList></Layer></Layers></Scene></GeneralSceneDescription>";
    return zip.write_file("GeneralSceneDescription.xml", xml) &&
           zip.write_file("géométrie.bin", std::string(3 * 1024 * 1024, 'Z')) &&
           zip.write_file("type.gdtf", "immutable GDTF") &&
           (extra.empty() || zip.write_file(extra, "unsafe")) && zip.close();
}
const std::string a = "11111111-1111-4111-8111-111111111111", b = "22222222-2222-4222-8222-222222222222";
// Create a canonical fixture while preserving ordered numbered breaks and vendor-owned fields.
std::string fixture(const std::string &id, const std::string &fields = {}) {
    return "<Fixture uuid='" + id +
           "' name='光 &amp; Amber' "
           "x:data='keep'><GDTFSpec>type.gdtf</GDTFSpec><GDTFMode>Mode</GDTFMode><Addresses><Address "
           "break='2'>513</Address><Address "
           "break='0'>7</Address></Addresses><x:Unknown><![CDATA[<exact>]]></x:Unknown>" +
           fields + "</Fixture>";
}
} // namespace
// Exercise exact no-op bytes, field-local edits, atomic commands, history and safe exports.
int main() {
    peraviz::runtime_storage::TemporaryWorkspace workspace("document-test");
    const auto root = workspace.path();
    auto source = root / "source.mvr";
    if (!archive(source,
                 fixture(a) +
                     fixture(b, "<DMXInvertPan>false</DMXInvertPan><DMXInvertTilt>true</DMXInvertTilt>")))
        return 1;
    MvrDocument doc;
    if (!check(doc.open(source), doc.error().c_str()))
        return 1;
    auto initial = doc.xml();
    const auto original_bytes = bytes(source);
    {
        std::ofstream external(source, std::ios::binary | std::ios::trunc);
        external << "changed by another application";
    }
    if (!check(doc.export_mvr(root / "snapshot.mvr") && bytes(root / "snapshot.mvr") == original_bytes,
               "Immutable snapshot survives external source changes"))
        return 1;
    {
        std::ofstream restore(source, std::ios::binary | std::ios::trunc);
        restore << original_bytes;
    }

    if (!check(!doc.fixture(a)->current[0].present && !doc.fixture(a)->current[0].value,
               "Absent inversion remains distinct from explicit false"))
        return 1;
    if (!check(doc.export_mvr(root / "noop.mvr") && bytes(source) == bytes(root / "noop.mvr"),
               "No-op archive must be byte-identical"))
        return 1;
    if (!check(!doc.prepare({a, "synthetic"}, 0, true) && doc.xml() == initial && !doc.dirty(),
               "Invalid multi-edit is atomic"))
        return 1;
    if (!check(doc.prepare({a, b}, 0, true) && doc.commit() && doc.dirty(),
               "Multi-fixture command commits atomically"))
        return 1;
    auto expected = initial;
    auto at = expected.find("<DMXInvertPan>false</DMXInvertPan>");
    expected.replace(at, strlen("<DMXInvertPan>false</DMXInvertPan>"), "<DMXInvertPan>true</DMXInvertPan>");
    at = expected.find("</Fixture>");
    expected.insert(at, "<DMXInvertPan>true</DMXInvertPan>");
    if (!check(doc.xml() == expected, "Only intended XML field ranges may change"))
        return 1;
    if (!check(doc.export_mvr(root / "edited.mvr"), doc.error().c_str()))
        return 1;
    auto canonical = doc.canonical_archive();
    if (!check(bytes(canonical) == bytes(root / "edited.mvr"),
               "All callers consume the same canonical archive bytes"))
        return 1;
    MvrDocument reopened;
    if (!check(reopened.open(root / "edited.mvr") && reopened.fixture(a)->current[0].value,
               "Edited MVR reopens"))
        return 1;
    doc.mark_saved();
    if (!check(!doc.dirty() && doc.prepare_history(false) && doc.commit() && doc.xml() == initial &&
                   doc.dirty(),
               "Undo restores absence and exact source XML after a save point"))
        return 1;
    if (!check(doc.prepare_history(true) && doc.commit() && !doc.dirty(), "Redo restores saved semantics"))
        return 1;
    if (!check(!doc.export_mvr(source) && !doc.export_mvr(root / "edited.mvr") &&
                   bytes(source) == bytes(root / "noop.mvr"),
               "Source and existing outputs cannot be overwritten"))
        return 1;
    if (!check(!doc.export_mvr(root / "missing" / "bad.mvr") && doc.fixture(a)->current[0].value,
               "Failed write preserves editing state"))
        return 1;
    int number = 0;
    for (const auto &bad :
         {std::string("<DMXInvertPan>1</DMXInvertPan>"),
          std::string("<DMXInvertTilt>true</DMXInvertTilt><DMXInvertTilt>false</DMXInvertTilt>"),
          std::string("<DMXInvertPan><!--vendor-->true</DMXInvertPan>")}) {
        auto p = root / ("invalid-" + std::to_string(number++) + ".mvr");
        archive(p, fixture(a, bad));
        MvrDocument invalid;
        if (!check(invalid.open(p) && !invalid.prepare({a}, 0, true),
                   "Malformed, duplicate or marked-up declarations reject editing"))
            return 1;
    }
    auto duplicate = root / "duplicate.mvr";
    archive(duplicate, fixture(a) + fixture(a));
    MvrDocument ambiguous;
    if (!check(ambiguous.open(duplicate) && !ambiguous.prepare({a}, 1, true),
               "Duplicate UUIDs never match by assumption"))
        return 1;
    auto unsafe = root / "unsafe.mvr";
    archive(unsafe, fixture(a), "../escape");
    MvrDocument traversal;
    if (!check(!traversal.open(unsafe) && !traversal.export_mvr(root / "unsafe-out.mvr"),
               "Unsafe ZIP paths block mutation and export"))
        return 1;
    auto nested = root / "nested.mvr";
    auto parent = fixture(a);
    parent.insert(parent.find("</Fixture>"), "<ChildList>" + fixture(b) + "</ChildList>");
    archive(nested, parent);
    MvrDocument nested_doc;
    if (!check(nested_doc.open(nested) && nested_doc.prepare({a, b}, 1, true) && nested_doc.commit() &&
                   nested_doc.export_mvr(root / "nested-edited.mvr"),
               "Nested fixtures preserve parent-child identities under multi-edit"))
        return 1;
    int invalid_case = 0;
    for (const auto &body : {fixture("generated/fixture"), fixture(a, "<x:Other>&undeclared;</x:Other>"),
                             fixture(a, std::string(1, char(0xff)))}) {
        auto path = root / ("unsafe-xml-" + std::to_string(number++) + ".mvr");
        archive(path, body);
        MvrDocument invalid;
        const bool loaded = invalid.open(path);
        if (!check(invalid_case++ == 0 ? loaded && !invalid.prepare({"generated/fixture"}, 0, true) : !loaded,
                   "Invalid encoding, entities and synthetic identities cannot be edited"))
            return 1;
    }
    auto alias = root / "alias.mvr";
    archive(alias, fixture(a), "GENERALSCENEDESCRIPTION.XML");
    MvrDocument alias_doc;
    if (!check(!alias_doc.open(alias), "Case-aliased archive paths are rejected conservatively"))
        return 1;
    if (!check(!doc.export_mvr({}), "Empty output path reports a failure without exceptions"))
        return 1;
    auto legacy = root / "legacy.mvr";
    {
        peraviz::archive::ZipArchive zip;
        zip.open_create_or_modify(legacy);
        zip.write_file("GeneralSceneDescription.xml",
                       "<GeneralSceneDescription><Scene><Layers/></Scene></GeneralSceneDescription>");
        zip.close();
    }
    MvrDocument opaque;
    if (!check(!opaque.open(legacy) && !opaque.ready() && !opaque.canonical_archive().empty() &&
                   bytes(opaque.canonical_archive()) == bytes(legacy) &&
                   !opaque.export_mvr(root / "legacy-export.mvr"),
               "Legacy opaque PVZ copies preserve bytes without granting unsafe canonical editing/export"))
        return 1;
    auto bounded = root / "bounded.mvr";
    auto large_xml = initial;
    constexpr size_t xml_bound = 32 * 1024 * 1024;
    large_xml.insert(large_xml.find("<Scene>"),
                     "<!--" + std::string(xml_bound - 1 - large_xml.size() - 7, 'p') + "-->");
    {
        peraviz::archive::ZipArchive zip;
        if (!zip.open_create_or_modify(bounded) ||
            !zip.write_file("GeneralSceneDescription.xml", large_xml) || !zip.close())
            return 1;
    }
    MvrDocument bounded_doc;
    if (!check(bounded_doc.open(bounded) && !bounded_doc.prepare({a}, 0, true) &&
                   bounded_doc.pending().empty() && !bounded_doc.dirty() && !bounded_doc.can_undo(),
               "Oversized edits fail before a runtime transaction or history change"))
        return 1;
    auto oversized = root / "oversized.mvr";
    {
        peraviz::archive::ZipArchive zip;
        if (!zip.open_create_or_modify(oversized) ||
            !zip.write_file("GeneralSceneDescription.xml", large_xml + "  ") || !zip.close())
            return 1;
    }
    MvrDocument oversized_doc;
    if (!check(!oversized_doc.open(oversized) && bytes(oversized_doc.canonical_archive()) == bytes(oversized),
               "XML exceeding the editing bound remains an exact opaque PVZ source"))
        return 1;
    std::cout << "MVR document preservation tests passed\n";
}
