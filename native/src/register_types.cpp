#include "register_types.h"

#include "hello_world.h"
#include "peraviz_loader.h"
#include "gobo_vectorizer.h"

#ifdef PERAVIZ_ENABLE_MVR_XCHANGE
#include "peraviz_mvr_xchange_client.h"
#endif

#ifdef PERAVIZ_ENABLE_DMX
#include "peraviz_dmx_receiver.h"
#include "runtime/peraviz_visual_runtime_godot.h"
#endif

// Registers module classes when the Peraviz module is initialized.
void initialize_peraviz_module(godot::ModuleInitializationLevel p_level) {
    if (p_level != godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    godot::ClassDB::register_class<godot::HelloWorld>();
    godot::ClassDB::register_class<godot::PeravizLoader>();
    godot::ClassDB::register_class<godot::PeravizGoboVectorizer>();
#ifdef PERAVIZ_ENABLE_DMX
    godot::ClassDB::register_class<godot::PeravizDmxReceiver>();
    godot::ClassDB::register_class<godot::PeravizVisualRuntime>();
#endif
#ifdef PERAVIZ_ENABLE_MVR_XCHANGE
    godot::ClassDB::register_class<godot::PeravizMvrXchangeClient>();
#endif
}

// Cleans up module state when the Peraviz module is unloaded.
void uninitialize_peraviz_module(godot::ModuleInitializationLevel p_level) {
    if (p_level != godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
}
