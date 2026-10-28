#pragma once

#include <string>

#include "scene_model.h"
#include "asset_cache.h"

namespace peraviz {

SceneModel load_mvr(const std::string &path, bool peraviz_debug_baseline = false,
                    bool peraviz_debug_coords = false, GdtfModelDetail model_detail = GdtfModelDetail::Default);

} // namespace peraviz
