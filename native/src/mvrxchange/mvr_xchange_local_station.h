#pragma once

#include "mvrxchange/mvr_xchange_types.h"

#include <atomic>
#include <functional>
#include <mutex>
#include <string>
#include <thread>

namespace peraviz::mvrxchange {

class MvrXchangeLocalStation {
public:
    using MessageCallback = std::function<void(const std::string &, const std::string &)>;

    MvrXchangeLocalStation();
    ~MvrXchangeLocalStation();

    bool start(const std::string &group, const std::string &bind_ip, const std::string &station_uuid, MessageCallback callback);
    void stop();
    bool is_running() const;
    uint16_t port() const;
    std::string service_name() const;
    std::string last_error() const;

private:
    void tcp_loop();
    void mdns_loop();
    void handle_tcp_client(int client_fd);
    void set_last_error(const std::string &message);

    mutable std::mutex mutex_;
    std::thread tcp_worker_;
    std::thread mdns_worker_;
    std::atomic<bool> running_{false};
    uint16_t port_ = 0;
    int server_fd_ = -1;
    std::string group_ = kDefaultGroupName;
    std::string bind_ip_;
    std::string station_uuid_;
    std::string station_name_ = "Peraviz";
    std::string service_name_;
    std::string last_error_;
    MessageCallback callback_;
};

} // namespace peraviz::mvrxchange
