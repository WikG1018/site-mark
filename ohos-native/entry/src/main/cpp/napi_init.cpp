#include <cstdlib>
#include <new>
#include <string>

#include "napi/native_api.h"

extern "C" char *sitemark_call_json(const char *input);
extern "C" void sitemark_string_free(char *value);

namespace {

struct NativeWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string input;
    std::string output;
};

void Execute(napi_env, void *data)
{
    auto *work = static_cast<NativeWork *>(data);
    char *response = sitemark_call_json(work->input.c_str());
    if (response == nullptr) {
        work->output = R"({"ok":false,"value":null,"error":"invalid_data:native allocation"})";
        return;
    }
    work->output.assign(response);
    sitemark_string_free(response);
}

void Complete(napi_env env, napi_status status, void *data)
{
    auto *work = static_cast<NativeWork *>(data);
    napi_value value = nullptr;
    if (status == napi_ok &&
        napi_create_string_utf8(env, work->output.c_str(), work->output.size(), &value) == napi_ok) {
        napi_resolve_deferred(env, work->deferred, value);
    } else {
        napi_create_string_utf8(env, "Native image work failed", NAPI_AUTO_LENGTH, &value);
        napi_reject_deferred(env, work->deferred, value);
    }
    napi_delete_async_work(env, work->work);
    delete work;
}

napi_value Call(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc != 1) {
        napi_throw_type_error(env, nullptr, "call expects one JSON string");
        return nullptr;
    }

    size_t inputLength = 0;
    if (napi_get_value_string_utf8(env, args[0], nullptr, 0, &inputLength) != napi_ok) {
        napi_throw_type_error(env, nullptr, "call expects a JSON string");
        return nullptr;
    }
    std::string input(inputLength + 1, '\0');
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, args[0], input.data(), inputLength + 1, &copied) != napi_ok) {
        napi_throw_error(env, nullptr, "could not read JSON request");
        return nullptr;
    }
    input.resize(copied);

    auto *work = new (std::nothrow) NativeWork();
    if (work == nullptr) {
        napi_throw_error(env, nullptr, "could not allocate native image work");
        return nullptr;
    }
    work->input = std::move(input);
    napi_value promise = nullptr;
    napi_value resourceName = nullptr;
    if (napi_create_promise(env, &work->deferred, &promise) != napi_ok ||
        napi_create_string_utf8(env, "SiteMarkImageCore", NAPI_AUTO_LENGTH, &resourceName) != napi_ok ||
        napi_create_async_work(env, nullptr, resourceName, Execute, Complete, work, &work->work) != napi_ok ||
        napi_queue_async_work(env, work->work) != napi_ok) {
        if (work->work != nullptr) {
            napi_delete_async_work(env, work->work);
        }
        delete work;
        napi_throw_error(env, nullptr, "could not schedule native image work");
        return nullptr;
    }
    return promise;
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor properties[] = {
        { "call", nullptr, Call, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    return exports;
}

} // namespace

static napi_module sitemarkModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "sitemark_native",
    .nm_priv = nullptr,
    .reserved = { nullptr }
};

extern "C" __attribute__((constructor)) void RegisterSiteMarkModule()
{
    napi_module_register(&sitemarkModule);
}
