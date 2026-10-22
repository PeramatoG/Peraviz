
// Writes raw ZIP names so normalization is tested independently of the archive writer.
bool write_raw_resource_zip(const std::filesystem::path &path) {
    int error = 0;
    zip_t *archive = zip_open(path.u8string().c_str(), ZIP_CREATE | ZIP_TRUNCATE, &error);
    if (!archive) return false;
    for (const char *name : {u8"./nested\\modelo\u00f1\u6a21\u578b.3ds", "a/shared.3ds", "b/shared.3ds",
                             "a/other.glb", "a/Same.3ds", "a/same.3ds", "../escape.3ds",
                             "a/collision?.3ds", "a/collision*.3ds", u8"nested/fixture\u00f1.gdtf",
                             ".hidden.3ds"}) {
        auto *source = zip_source_buffer(archive, "geometry", 8, 0);
        if (!source || zip_file_add(archive, name, source, ZIP_FL_ENC_UTF_8) < 0) {
            if (source) zip_source_free(source);
            zip_discard(archive);
            return false;
        }
    }
    return zip_close(archive) == 0;
}

// Exercises Unicode ZIP identity, deterministic resolution, containment, sharing and cleanup.
int test_archive_resource_resolution(const std::filesystem::path &root) {
    const auto directory = root / std::filesystem::u8path(u8"recursos\u00f1\u6a21\u578b");
    std::filesystem::create_directories(directory);
    const auto source = directory / std::filesystem::u8path(u8"escena\u00f1.mvr");
    if (!write_raw_resource_zip(source)) return fail("Cannot create resource resolution archive");
    peraviz::archive::ZipArchive archive;
    if (!archive.open_read(source) || archive.read_text_file(u8"nested/modelo\u00f1\u6a21\u578b.3ds") != "geometry" ||
        archive.read_text_file(u8"NESTED/modelo\u00f1\u6a21\u578b.3ds") != "geometry" ||
        archive.file_exists("a/Same.3ds") || archive.file_exists("../escape.3ds") ||
        !archive.file_exists(".hidden.3ds")) return fail("ZIP normalized identity/raw entry remapping failed");
    archive.close();
    std::filesystem::path workspace;
    {
        peraviz::ZipAssetCache cache(source.u8string());
        workspace = cache.cache_dir();
        for (unsigned char ch : workspace.filename().u8string())
            if (ch >= 128) return fail("Content cache identifier contains non-ASCII bytes");
        auto model = cache.ensure_mvr_model_extracted(u8"nested/modelo\u00f1\u6a21\u578b.3ds");
        if (model.empty() || read_binary(std::filesystem::u8path(model)) != "geometry") return fail("Unicode model did not extract");
        if (cache.ensure_mvr_model_extracted(u8"NESTED/modelo\u00f1\u6a21\u578b.3ds") != model || cache.extracted_assets() != 1)
            return fail("Repeated case-compatible model did not share canonical path");
        if (!cache.ensure_mvr_model_extracted("shared.3ds").empty() || cache.last_error() != "ambiguous_resource_reference")
            return fail("Ambiguous model basename was accepted");
        if (cache.ensure_mvr_model_extracted("a/shared.3ds").empty()) return fail("Exact nested reference was not preferred");
        if (!cache.ensure_mvr_model_extracted("other.3ds").empty()) return fail("Explicit extension was substituted by an unrelated format");
        if (!cache.ensure_mvr_model_extracted("a/collision?.3ds").empty() || cache.last_error() != "ambiguous_extraction_path")
            return fail("Sanitized extraction aliases were accepted");
        if (cache.ensure_gdtf_spec_extracted(u8"fixture\u00f1").empty()) return fail("Nested GDTF basename lookup failed");
        const auto copy = directory / "ascii.mvr";
        std::filesystem::copy_file(source, copy);
        peraviz::ZipAssetCache shared(copy.u8string());
        if (shared.cache_dir() != workspace || shared.ensure_mvr_model_extracted(u8"nested/modelo\u00f1\u6a21\u578b.3ds") != model)
            return fail("Equivalent archive contents did not share cache leases");
        const auto distinct = directory / "different.mvr";
        { std::ofstream out(distinct, std::ios::binary); out << "different"; }
        peraviz::ZipAssetCache separate(distinct.u8string());
        if (separate.cache_dir() == workspace) return fail("Different archives shared a content cache");
    }
    if (std::filesystem::exists(workspace)) return fail("Resource cache survived its last owner");
    return 0;
}
