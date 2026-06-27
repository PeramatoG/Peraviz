#pragma once

#include "mvrxchange/mvr_xchange_types.h"

#include <atomic>
#include <mutex>
#include <queue>
#include <string>
#include <thread>
#include <unordered_map>

namespace peraviz::mvrxchange {

struct MvrXchangeCommitInfo {
    std::string service_name;
    std::string station_name;
    std::string file_uuid;
    std::string timestamp;
    std::string message;
    uint64_t seen_us = 0;
};

struct MvrXchangeEvent {
    std::string type;
    std::string service_name;
    std::string station_name;
    std::string file_uuid;
    std::string path;
    std::string message;
    uint64_t size_bytes = 0;
};

struct TransferStats {
    bool busy = false;
    uint64_t commit_count = 0;
    uint64_t event_count = 0;
};

class MvrXchangeTransferClient {
public:
    MvrXchangeTransferClient();
    ~MvrXchangeTransferClient();

    void set_stations(const std::vector<StationInfo> &stations);
    bool join_station(const std::string &service_name);
    bool request_latest_mvr(const std::string &service_name, const std::string &target_path);
    bool request_mvr(const std::string &service_name, const std::string &file_uuid, const std::string &target_path);
    std::vector<MvrXchangeCommitInfo> get_commits() const;
    std::vector<MvrXchangeEvent> poll_events();
    TransferStats get_stats() const;
    std::string get_last_error() const;
    void stop();

private:
    bool start_worker(const std::string &service_name, const std::string &file_uuid, const std::string &target_path, bool request_file);
    void worker_main(StationInfo station, std::string file_uuid, std::string target_path, bool request_file);
    void push_event(const MvrXchangeEvent &event);
    void set_last_error(const std::string &message);

    mutable std::mutex mutex_;
    std::thread worker_;
    std::atomic<bool> busy_{false};
    std::unordered_map<std::string, StationInfo> stations_;
    std::unordered_map<std::string, MvrXchangeCommitInfo> commits_;
    std::queue<MvrXchangeEvent> events_;
    std::string last_error_;
    uint64_t event_count_ = 0;
};

std::string build_line_message(const std::string &type, const std::string &file_uuid = std::string());
MvrXchangeCommitInfo parse_commit_message(const std::string &message, const StationInfo &station);
bool write_completed_mvr_file(const std::string &target_path, const std::string &payload, std::string &error);

} // namespace peraviz::mvrxchange
