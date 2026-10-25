#include "runtime/native_worker_pool.h"
#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <exception>
#include <mutex>
#include <thread>
#include <vector>
#include <fstream>
#include <string>
#if defined(__linux__)
#include <sched.h>
#endif
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <time.h>
#endif

namespace peraviz::runtime {
namespace {
// Reads monotonic wall time for coarse batch observations, never once per scalar.
uint64_t wall_ns() { return uint64_t(std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count()); }
// Measures actual current-thread CPU time separately from overlapping worker wall intervals.
uint64_t cpu_ns() {
#ifdef _WIN32
    FILETIME created,exited,kernel,user;
    if (!GetThreadTimes(GetCurrentThread(),&created,&exited,&kernel,&user)) return 0;
    ULARGE_INTEGER k,u; k.LowPart=kernel.dwLowDateTime; k.HighPart=kernel.dwHighDateTime;
    u.LowPart=user.dwLowDateTime; u.HighPart=user.dwHighDateTime;
    return (k.QuadPart+u.QuadPart)*100ULL;
#elif defined(CLOCK_THREAD_CPUTIME_ID)
    timespec value{};
    return clock_gettime(CLOCK_THREAD_CPUTIME_ID,&value)==0?uint64_t(value.tv_sec)*1000000000ULL+uint64_t(value.tv_nsec):0;
#else
    return 0;
#endif
}
}
struct NativeWorkerPool::Impl {
    struct WorkerResult { uint64_t cpu=0,wall=0; std::exception_ptr failure; };
    std::vector<std::thread> threads;
    std::vector<WorkerResult> results;
    std::mutex mutex;
    std::condition_variable work,done;
    bool stopping=false,force=false,sample=false;
    uint64_t epoch=0,dispatches=0;
    size_t count=0,participants=0,completed=0;
    Function function=nullptr;
    void *context=nullptr;
    double item_ns=300.0,dispatch_ns=30000.0;
    mutable uint64_t decisions=0;
    // Runs one reusable worker with an exclusive coarse range and catches callback failures.
    void worker(size_t index) {
        uint64_t observed=0;
        for (;;) {
            std::unique_lock<std::mutex> lock(mutex);
            work.wait(lock,[&] { return stopping || epoch!=observed; });
            if (stopping) return;
            observed=epoch;
            const auto fn=function; auto *ctx=context; const size_t n=count,used=participants;
            const bool measured=sample;
            lock.unlock();
            auto &result=results[index]; result={};
            if (index<used) {
                const auto start=measured?wall_ns():0, cpu=measured?cpu_ns():0;
                try { fn(ctx,n*index/used,n*(index+1)/used); } catch (...) { result.failure=std::current_exception(); }
                if (measured) { result.wall=wall_ns()-start; const auto end=cpu_ns(); result.cpu=end>=cpu?end-cpu:0; }
            }
            lock.lock();
            if (++completed==threads.size()) done.notify_one();
        }
    }
};
// Reserves main/render/coordinator capacity and caps parallel calculation at four workers.
uint32_t NativeWorkerPool::recommended_workers() {
    auto available=std::thread::hardware_concurrency();
#if defined(__linux__)
    cpu_set_t affinity;
    if (sched_getaffinity(0,sizeof(affinity),&affinity)==0) available=std::min(available,unsigned(CPU_COUNT(&affinity)));
    std::ifstream quota("/sys/fs/cgroup/cpu.max"); std::string limit; uint64_t period=0;
    if (quota>>limit>>period && limit!="max" && period) {
        try { available=std::min(available,unsigned(std::max<uint64_t>(1,std::stoull(limit)/period))); } catch (...) { }
    }
#endif
#if defined(_WIN32)
    DWORD_PTR process_mask=0,system_mask=0;
    if (GetProcessAffinityMask(GetCurrentProcess(),&process_mask,&system_mask)) {
        unsigned allowed=0; for (;process_mask;process_mask>>=1) allowed+=unsigned(process_mask&1);
        if (allowed) available=std::min(available,allowed);
    }
#endif
    return available>4?std::min(4U,available-3):0;
}
// Creates threads once for this scene-owned native executor.
NativeWorkerPool::NativeWorkerPool(uint32_t workers,bool force):impl_(std::make_unique<Impl>()) {
    impl_->force=force;
    const auto count=std::min(4U,workers?workers:recommended_workers());
    impl_->results.resize(count);
    try { for (uint32_t i=0;i<count;++i) impl_->threads.emplace_back([this,i] { impl_->worker(i); }); }
    catch (...) {
        { std::lock_guard<std::mutex> lock(impl_->mutex); impl_->stopping=true; }
        impl_->work.notify_all(); for (auto &thread:impl_->threads) thread.join(); throw;
    }
}
// Retires idle native workers only at lifecycle boundaries after coordinator work has stopped.
NativeWorkerPool::~NativeWorkerPool() {
    { std::lock_guard<std::mutex> lock(impl_->mutex); impl_->stopping=true; }
    impl_->work.notify_all(); for (auto &thread:impl_->threads) thread.join();
}
// Exposes explicit diagnostic forcing independently from the normal adaptive policy.
bool NativeWorkerPool::forced() const { return impl_->force; }
// Keeps small batches serial and backs off when observed dispatch cost exceeds useful work.
bool NativeWorkerPool::worthwhile(size_t count,size_t minimum) const {
    const auto &p=*impl_;
    if (p.threads.size()<2 || count<2) return false;
    if (p.force) return true;
    return count>=minimum && (++p.decisions%32==0 ||
        double(count)*p.item_ns*(1.0-1.0/double(p.threads.size()))>p.dispatch_ns*2.0);
}
// Executes pure ranges; only the native coordinator waits for completion and commits their results.
NativeBatchMetrics NativeWorkerPool::run(size_t count,size_t minimum,Function function,void *context,bool trace) {
    auto &p=*impl_; NativeBatchMetrics metrics;
    ++p.dispatches;
    const bool sample=trace || p.dispatches%16==1;
    const auto start=sample?wall_ns():0;
    if (!worthwhile(count,minimum)) {
        function(context,0,count);
        if (sample && count) p.item_ns=p.item_ns*0.75+double(wall_ns()-start)/double(count)*0.25;
        return metrics;
    }
    {
        std::unique_lock<std::mutex> lock(p.mutex);
        p.count=count; p.participants=std::min<size_t>(p.threads.size(),p.force?count:std::max<size_t>(2,count/std::max<size_t>(1,minimum)));
        p.function=function; p.context=context; p.sample=sample; p.completed=0; ++p.epoch;
        p.work.notify_all(); p.done.wait(lock,[&] { return p.completed==p.threads.size(); });
    }
    metrics.parallel=true; metrics.tasks=p.participants; metrics.workers_used=uint32_t(p.participants);
    uint64_t longest=0;
    for (size_t i=0;i<p.participants;++i) {
        metrics.worker_cpu_ns+=p.results[i].cpu; longest=std::max(longest,p.results[i].wall);
        metrics.failures+=p.results[i].failure!=nullptr;
    }
    if (sample) {
        metrics.wall_ns=wall_ns()-start;
        metrics.coordination_ns=metrics.wall_ns>longest?metrics.wall_ns-longest:0;
        metrics.cpu_clock_supported=metrics.worker_cpu_ns>0;
        if (count && metrics.worker_cpu_ns) p.item_ns=p.item_ns*0.75+double(metrics.worker_cpu_ns)/double(count)*0.25;
        p.dispatch_ns=p.dispatch_ns*0.75+double(metrics.coordination_ns)*0.25;
    }
    // All workers have joined the barrier, so a serial retry can safely replace every result slot.
    if (metrics.failures) {
        function(context,0,count);
        if (sample) { metrics.wall_ns=wall_ns()-start; metrics.coordination_ns=metrics.wall_ns>longest?metrics.wall_ns-longest:0; }
    }
    return metrics;
}
// Reports retained native execution capacity, not an assertion of optimal worker count.
uint32_t NativeWorkerPool::worker_count() const { return uint32_t(impl_->threads.size()); }
} // namespace peraviz::runtime
