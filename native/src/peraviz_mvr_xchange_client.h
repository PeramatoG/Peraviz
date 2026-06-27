#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include "mvrxchange/mvr_xchange_discovery.h"
#include "mvrxchange/mvr_xchange_transfer.h"

#include <memory>

namespace godot {

class PeravizMvrXchangeClient : public RefCounted {
    GDCLASS(PeravizMvrXchangeClient, RefCounted)

protected:
    static void _bind_methods();

public:
    PeravizMvrXchangeClient();
    ~PeravizMvrXchangeClient() override;

    bool start(const String &group = "Default", const String &bind_ip = "");
    void stop();
    bool is_running() const;
    String get_last_error() const;
    Array get_stations() const;
    Array get_commits() const;
    bool join_station(const String &service_name);
    bool request_latest_mvr(const String &service_name, const String &target_path);
    bool request_mvr(const String &service_name, const String &file_uuid, const String &target_path);
    Array poll_events();
    Dictionary get_stats() const;

private:
    static uint64_t now_microseconds();

    std::unique_ptr<peraviz::mvrxchange::MvrXchangeDiscovery> discovery_;
    mutable std::unique_ptr<peraviz::mvrxchange::MvrXchangeTransferClient> transfer_;
};

} // namespace godot
