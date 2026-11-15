#pragma once
#include <string>
namespace peraviz::document {
struct Inversion {
    bool present = false, value = false, valid = true;
    std::string diagnostic;
    // Compare canonical semantics while retaining the distinction between absence and false.
    bool operator==(const Inversion &o) const {
        return present == o.present && value == o.value && valid == o.valid;
    }
};
} // namespace peraviz::document
