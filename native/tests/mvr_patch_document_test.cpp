#include "archive/zip_archive.h"
#include "document/mvr_document.h"
#include <fstream>
#include <iostream>
using namespace peraviz::document;
namespace {
const std::string id = "11111111-1111-4111-8111-111111111111";
// Fail visibly without weakening preservation assertions.
bool check(bool value, const char *message) {
    if (!value)
        std::cerr << message << '\n';
    return value;
}
// Read exact archive bytes independently of the document snapshot.
std::string bytes(const std::filesystem::path &path) {
    std::ifstream in(path, std::ios::binary);
    return {std::istreambuf_iterator<char>(in), {}};
}
// Generate a deterministic canonical document with unrelated hierarchy and extensions.
bool source(const std::filesystem::path &path, const std::string &patch) {
    peraviz::archive::ZipArchive zip;
    const std::string xml = "<?xml version='1.0' encoding='UTF-8'?><GeneralSceneDescription verMajor='1' "
                            "verMinor='6' xmlns:x='urn:other'><Scene><Layers><Layer "
                            "uuid='layer'><ChildList><GroupObject uuid='group'><ChildList><Fixture uuid='" +
                            id + "' name='Étage 光'><Matrix>unchanged matrix</Matrix>" + patch +
                            "<x:Unknown data='keep'/></Fixture><Truss "
                            "uuid='truss'><x:Geometry/></Truss></ChildList></GroupObject></ChildList></"
                            "Layer></Layers></Scene></GeneralSceneDescription>";
    return zip.open_create_or_modify(path) && zip.write_file("GeneralSceneDescription.xml", xml) &&
           zip.write_file("geometry-é.bin", "identical binary bytes") && zip.close();
}
} // namespace
// Cover ordered authored patch commands, original spelling, mixed history and safe rejection.
int main() {
    peraviz::runtime_storage::TemporaryWorkspace workspace("patch-document");
    const auto root = workspace.path();
    int n = 0;
    for (const auto &text : {std::string("<Address x:tag='keep'> \n 513 \t</Address>"),
                             std::string("<Address break='0' x:tag='keep'>2.1</Address>")}) {
        const auto path = root / (std::to_string(n++) + ".mvr");
        if (!source(path, "<Addresses><Network geometry='NetworkInOut_1'>192.0.2.1</Network>" + text +
                              "<x:Other/><Address break='7'>4.201</Address></Addresses>"))
            return 1;
        MvrDocument doc;
        if (!check(doc.open(path), "Canonical patch source opens"))
            return 1;
        const auto initial = doc.xml();
        auto f = doc.fixture(id);
        if (!check(f->current_patch.size() == 2 && f->current_patch[0].universe == 2 &&
                       f->current_patch[0].address == 1 && f->current_patch[1].break_id == 7,
                   "Read ordered absolute/dotted and noncontiguous breaks"))
            return 1;
        if (!check(doc.export_mvr(root / (std::to_string(n) + "-noop.mvr")) &&
                       bytes(path) == bytes(root / (std::to_string(n) + "-noop.mvr")),
                   "No-op patch export is byte-identical"))
            return 1;
        if (!check(doc.prepare({id}, 0, true) && doc.commit() && doc.prepare_patch(id, 0, 3, 101, "set") &&
                       doc.commit() && doc.prepare_patch(id, 7, 5, 201, "set") && doc.commit(),
                   "Inversion and primary/secondary patch share one staged history"))
            return 1;
        if (!check(doc.xml().find("<Network geometry='NetworkInOut_1'>192.0.2.1</Network>") !=
                           std::string::npos &&
                       doc.xml().find("x:tag='keep'") != std::string::npos,
                   "Network and unknown attributes survive patch edits"))
            return 1;
        for (int i = 0; i < 3; ++i)
            if (!check(doc.prepare_history(false) && doc.commit(), "Undo mixed commands"))
                return 1;
        if (!check(doc.xml() == initial && !doc.dirty(),
                   "Undo recovers exact whitespace/text and omitted optional attributes"))
            return 1;
        for (int i = 0; i < 3; ++i)
            if (!check(doc.prepare_history(true) && doc.commit(), "Redo mixed commands"))
                return 1;
        if (!check(doc.fixture(id)->current_patch[0].universe == 3 &&
                       doc.fixture(id)->current_patch[1].universe == 5 && doc.fixture(id)->current[0].value,
                   "Redo restores canonical states"))
            return 1;
        if (!check(doc.prepare_patch(id, 11, 6, 301, "insert") && doc.commit() &&
                       doc.prepare_patch(id, 7, 0, 0, "remove") && doc.commit(),
                   "Explicit insertion and removal preserve ordered existing break identities"))
            return 1;
        if (!check(doc.fixture(id)->current_patch[0].break_id == 0 &&
                       doc.fixture(id)->current_patch[1].break_id == 11,
                   "Noncontiguous breaks do not become universe offsets"))
            return 1;
        if (!check(doc.prepare_history(false) && doc.commit() && doc.prepare_history(false) && doc.commit(),
                   "Undo remove and insert restores exact previous assignments"))
            return 1;
        const auto before = doc.xml();
        if (!check(!doc.prepare_patch(id, 0, 1, 513, "set") && !doc.prepare_patch(id, 0, 0, 1, "set") &&
                       !doc.prepare_patch(id, 0, 32769, 1, "set") &&
                       !doc.prepare_patch(id, 0, 1, 1, "insert") && !doc.prepare_patch(id, 99, 1, 1, "set") &&
                       doc.xml() == before,
                   "Invalid slots/universes and ambiguous operations fail atomically"))
            return 1;
        const auto exported = root / (std::to_string(n) + "-edited.mvr");
        MvrDocument reopened;
        if (!check(doc.export_mvr(exported) && reopened.open(exported) && reopened.xml() == before,
                   "Canonical edited archive reopens with patch and inversion"))
            return 1;
    }
    for (const auto &container : {std::string(), std::string("<Addresses/>"),
                                  std::string("<Addresses><Network>192.0.2.2</Network></Addresses>")}) {
        auto path = root / ("unpatched" + std::to_string(n++) + ".mvr");
        source(path, container);
        MvrDocument doc;
        if (!check(doc.open(path) && doc.fixture(id)->current_patch.empty() &&
                       doc.prepare_patch(id, 4, 2, 201, "insert") && doc.commit(),
                   "Unpatched canonical documents support explicit validated document insertion"))
            return 1;
        if (!check(doc.prepare_history(false) && doc.commit() &&
                       doc.export_mvr(root / ("unpatched-noop" + std::to_string(n) + ".mvr")) &&
                       doc.xml().find("<Address break=") == std::string::npos,
                   "Undo insertion restores original container absence/self-closing semantics"))
            return 1;
    }
    for (const auto &body :
         {"<Addresses><Address>1</Address><Address break='0'>2</Address></Addresses>",
          "<Addresses><Address break='-1'>1</Address></Addresses>",
          "<Addresses><Address>1.513</Address></Addresses>",
          "<Addresses><Address>1</Address><Address>invalid</Address></Addresses>", "<Addresses/><Addresses/>",
          "<Addresses><Address><![CDATA[1]]></Address></Addresses>"}) {
        auto path = root / ("unsafe" + std::to_string(n++) + ".mvr");
        source(path, body);
        MvrDocument doc;
        if (!check(doc.open(path) && !doc.prepare_patch(id, 0, 2, 1, "set"),
                   "Malformed/ambiguous patch metadata rejects mutation"))
            return 1;
        auto before = doc.xml();
        if (!check(doc.prepare({id}, 1, true) && doc.commit() && doc.xml().find(body) != std::string::npos,
                   "Unrelated inversion never drops malformed original patch data"))
            return 1;
    }
    std::cout << "Canonical patch document tests passed\n";
}
