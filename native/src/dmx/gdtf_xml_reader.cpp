#include "dmx/gdtf_xml_reader.h"

#include "archive/zip_archive.h"

#include <algorithm>
#include <cctype>
#include <filesystem>

namespace peraviz::dmx {

// Converts an ASCII string to lowercase for case-insensitive matching.
std::string lower_ascii(std::string text) {
// Applies lowercase conversion to each character in the string.
    std::transform(text.begin(), text.end(), text.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return text;
}

// Trims ASCII whitespace from both ends of a string.
std::string trim_ascii(std::string text) {
    const auto is_space = [](unsigned char c) { return std::isspace(c) != 0; };
    text.erase(text.begin(), std::find_if(text.begin(), text.end(), [&](unsigned char c) { return !is_space(c); }));
    text.erase(std::find_if(text.rbegin(), text.rend(), [&](unsigned char c) { return !is_space(c); }).base(), text.end());
    return text;
}

// Reads and returns the GDTF description XML from an archive.
std::string read_gdtf_description_xml(const std::string &gdtf_path) {
    peraviz::archive::ZipArchive archive;
    if (!archive.open_read(std::filesystem::u8path(gdtf_path))) {
        return {};
    }

    const auto files = archive.list_files();
    auto exact = std::find(files.begin(), files.end(), "description.xml");
    if (exact != files.end()) return archive.read_text_file(*exact);

    // Match the geometry builder's root precedence and unique nested compatibility fallback.
    std::string folded_root, nested;
    bool duplicate_root = false, duplicate_nested = false;
    for (const auto &entry : archive.ambiguous_files()) {
        const auto folded = lower_ascii(entry);
        duplicate_root |= folded == "description.xml";
        duplicate_nested |= folded.size() > 16 && folded.compare(folded.size() - 16, 16, "/description.xml") == 0;
    }
    for (const auto &entry : files) {
        const auto folded = lower_ascii(entry);
        if (folded == "description.xml") {
            duplicate_root |= !folded_root.empty();
            folded_root = entry;
        } else if (folded.size() > 16 && folded.compare(folded.size() - 16, 16, "/description.xml") == 0) {
            duplicate_nested |= !nested.empty();
            nested = entry;
        }
    }
    if (duplicate_root) return {};
    if (!folded_root.empty()) return archive.read_text_file(folded_root);
    return duplicate_nested || nested.empty() ? std::string{} : archive.read_text_file(nested);
}

// Collects all descendant XML elements with a case-insensitive name match.
std::vector<tinyxml2::XMLElement *> collect_elements_by_name(tinyxml2::XMLElement *root,
                                                             const std::string &name_lower) {
    std::vector<tinyxml2::XMLElement *> result;
    std::vector<tinyxml2::XMLElement *> stack;
    if (root) {
        stack.push_back(root);
    }

    while (!stack.empty()) {
        tinyxml2::XMLElement *node = stack.back();
        stack.pop_back();

        if (lower_ascii(node->Name()) == name_lower) {
            result.push_back(node);
        }

        for (tinyxml2::XMLElement *child = node->FirstChildElement(); child;
             child = child->NextSiblingElement()) {
            stack.push_back(child);
        }
    }
    return result;
}

// Collects direct child XML elements with a case-insensitive name match.
std::vector<tinyxml2::XMLElement *> collect_direct_children_by_name(tinyxml2::XMLElement *root,
                                                                    const std::string &name_lower) {
    std::vector<tinyxml2::XMLElement *> result;
    if (!root) {
        return result;
    }
    for (tinyxml2::XMLElement *child = root->FirstChildElement(); child;
         child = child->NextSiblingElement()) {
        if (lower_ascii(child->Name()) == name_lower) {
            result.push_back(child);
        }
    }
    return result;
}

// Reads one of two case variants of an XML attribute and trims it.
std::string read_attr_ci(tinyxml2::XMLElement *node,
                         const char *name_a,
                         const char *name_b) {
    if (!node) {
        return {};
    }
    const char *value = node->Attribute(name_a);
    if (!value) {
        value = node->Attribute(name_b);
    }
    return value ? trim_ascii(value) : std::string();
}

} // namespace peraviz::dmx
