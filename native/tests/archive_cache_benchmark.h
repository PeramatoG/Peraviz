// Reports cold extraction and live-lease reuse separately, without CI timing gates.
int benchmark_archive_cache(int count) {
    if (count < 1 || count > 100000) return 1;
    peraviz::runtime_storage::TemporaryWorkspace workspace("archive-benchmark");
    const auto source = workspace.path() / "generated.mvr";
    {
        peraviz::archive::ZipArchive archive;
        if (!archive.open_create_or_modify(source)) return 1;
        for (int i = 0; i < count; ++i)
            if (!archive.write_file("models/" + std::to_string(i) + "/part.3ds", "geometry")) return 1;
        if (!archive.close()) return 1;
    }
    peraviz::runtime_storage::RuntimeDirectoryLease retained;
    for (int run = 0; run < 2; ++run) {
        const auto started = std::chrono::steady_clock::now();
        peraviz::ZipAssetCache cache(source.u8string());
        const auto opened = std::chrono::steady_clock::now();
        for (int i = 0; i < count; ++i)
            if (cache.ensure_mvr_model_extracted("models/" + std::to_string(i) + "/part.3ds").empty()) return 1;
        const auto extracted = std::chrono::steady_clock::now();
        for (int i = 0; i < 10000; ++i)
            if (cache.ensure_mvr_model_extracted("MODELS/0/PART.3DS").empty()) return 1;
        const auto finished = std::chrono::steady_clock::now();
        const auto ms = [](auto begin, auto end) {
            return std::chrono::duration<double, std::milli>(end - begin).count();
        };
        std::cout << "ARCHIVE_BENCHMARK entries=" << count << " cache=" << (run ? "leased-warm" : "extraction-cold")
            << " open_index_ms=" << ms(started, opened) << " extract_resolve_ms=" << ms(opened, extracted)
            << " repeated_lookups_ms=" << ms(extracted, finished) << '\n';
        retained = cache.cache_lease();
    }
    return 0;
}
