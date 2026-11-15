#pragma once
#include "document/mvr_inversion.h"
#include <tinyxml2.h>
namespace peraviz::document {
// Read strict MVR Bool children; absence requests no inversion, without inventing a declaration.
inline Inversion read_inversion(const tinyxml2::XMLElement *fixture, const char *name) {
    Inversion result;
    for (auto child = fixture->FirstChildElement(); child; child = child->NextSiblingElement()) {
        if (std::string(child->Name()) != name)
            continue;
        if (result.present) {
            result.valid = false;
            result.diagnostic = std::string("Duplicate ") + name;
            continue;
        }
        result.present = true;
        std::string text;
        for (auto part = child->FirstChild(); part; part = part->NextSibling())
            if (auto content = part->ToText())
                text += content->Value();
        const auto begin = text.find_first_not_of(" \t\r\n"), end = text.find_last_not_of(" \t\r\n");
        text = begin == std::string::npos ? "" : text.substr(begin, end - begin + 1);
        if (child->FirstChildElement() || (text != "true" && text != "false")) {
            result.valid = false;
            result.diagnostic = std::string("Malformed ") + name + "; expected true or false";
        } else
            result.value = text == "true";
    }
    return result;
}
} // namespace peraviz::document
