#pragma once
#include "tjs.h"
#include "tjsNative.h"
#include "DrawDevice.h"
#include <dlfcn.h>
#include <unordered_map>

namespace DrawDeviceGLES {

using CreateKrkrGLESModuleObjectFn = tjs_error (*)(tTJSVariant *, tjs_int, tjs_int);
using ModuleName = std::basic_string<tjs_char>;
using ModuleStore = std::unordered_map<uintptr_t, std::unordered_map<ModuleName, tTJSVariant>>;

inline tjs_error TryCreateModuleViaKrkrGLES(tTJSVariant *result, tjs_int width,
                                            tjs_int height) {
    void *sym = dlsym(RTLD_DEFAULT, "TVPKrkrGLESCreateModuleObject");
    if(!sym) return TJS_E_MEMBERNOTFOUND;
    auto fn = reinterpret_cast<CreateKrkrGLESModuleObjectFn>(sym);
    return fn(result, width, height);
}

inline tjs_error ReturnTrueCb(tTJSVariant *result, tjs_int, tTJSVariant **,
                              iTJSDispatch2 *) {
    if(result) *result = true;
    return TJS_S_OK;
}

inline tjs_error ReturnFirstArgOrTrueCb(tTJSVariant *result, tjs_int numparams,
                                        tTJSVariant **param, iTJSDispatch2 *) {
    if(!result) return TJS_S_OK;
    if(numparams > 0 && param) {
        *result = *param[0];
    } else {
        *result = true;
    }
    return TJS_S_OK;
}

inline void SetObjectMethod(iTJSDispatch2 *obj, const tjs_char *name,
                            tTJSNativeClassMethodCallback cb) {
    if(!obj || !name || !cb) return;
    iTJSDispatch2 *method = TJSCreateNativeClassMethod(cb);
    if(!method) return;
    tTJSVariant v(method, method);
    obj->PropSet(TJS_MEMBERENSURE, name, nullptr, &v, obj);
    method->Release();
}

inline tjs_error CreateFallbackModuleObject(tTJSVariant *result, tjs_int width,
                                            tjs_int height) {
    iTJSDispatch2 *dict = TJSCreateCustomObject();
    if(!dict) return TJS_E_FAIL;

    tTJSVariant wv(width), hv(height);
    dict->PropSet(TJS_MEMBERENSURE, TJS_W("screenWidth"), nullptr, &wv, dict);
    dict->PropSet(TJS_MEMBERENSURE, TJS_W("screenHeight"), nullptr, &hv, dict);

    SetObjectMethod(dict, TJS_W("entryUpdateObject"), ReturnTrueCb);
    SetObjectMethod(dict, TJS_W("setScreenSize"), ReturnTrueCb);
    SetObjectMethod(dict, TJS_W("makeCurrent"), ReturnTrueCb);
    SetObjectMethod(dict, TJS_W("endScene"), ReturnTrueCb);
    SetObjectMethod(dict, TJS_W("finalize"), ReturnTrueCb);
    SetObjectMethod(dict, TJS_W("capture"), ReturnFirstArgOrTrueCb);
    SetObjectMethod(dict, TJS_W("captureScreen"), ReturnFirstArgOrTrueCb);
    SetObjectMethod(dict, TJS_W("glesCapture"), ReturnFirstArgOrTrueCb);
    SetObjectMethod(dict, TJS_W("glesCaptureScreen"), ReturnFirstArgOrTrueCb);
    SetObjectMethod(dict, TJS_W("copyLayer"), ReturnTrueCb);
    SetObjectMethod(dict, TJS_W("glesCopyLayer"), ReturnTrueCb);
    SetObjectMethod(dict, TJS_W("drawLayer"), ReturnTrueCb);
    SetObjectMethod(dict, TJS_W("drawAffine"), ReturnTrueCb);
    SetObjectMethod(dict, TJS_W("drawAffineGLES"), ReturnTrueCb);
    SetObjectMethod(dict, TJS_W("setMatrix"), ReturnTrueCb);

    if(result) *result = tTJSVariant(dict, dict);
    dict->Release();
    return TJS_S_OK;
}

inline ModuleStore &GetCachedModules() {
    static ModuleStore modules;
    return modules;
}

inline ModuleName NormalizeModuleName(tjs_int numparams, tTJSVariant **param) {
    if(numparams <= 0 || !param || !param[0] || param[0]->Type() == tvtVoid) {
        return TJS_W("live2d");
    }
    ttstr raw(*param[0]);
    ModuleName out(raw.c_str());
    for(auto &ch : out) {
        if(ch >= static_cast<tjs_char>('A') && ch <= static_cast<tjs_char>('Z')) {
            ch = static_cast<tjs_char>(ch + 32);
        }
    }
    if(out.empty()) out = TJS_W("live2d");
    return out;
}

inline void ClearCachedModulesForDevice(void *device) {
    if(!device) return;
    GetCachedModules().erase(reinterpret_cast<uintptr_t>(device));
}

inline void EnsureWindowGLESAdaptor(tTVPDrawDevice *device) {
    if(!device) return;
    iTVPWindow *window = device->GetWindowInterface();
    if(!window) return;
    iTJSDispatch2 *windowObj = window->GetWindowDispatch();
    if(!windowObj) return;

    tTJSVariant adaptor;
    windowObj->PropGet(0, TJS_W("glesAdaptor"), nullptr, &adaptor, windowObj);
}

template<typename DeviceT>
tjs_error GetModuleForDevice(DeviceT *device, tTJSVariant *result,
                             tjs_int numparams, tTJSVariant **param) {
    const ModuleName moduleName = NormalizeModuleName(numparams, param);
    if(moduleName == ModuleName(TJS_W("live2d"))) EnsureWindowGLESAdaptor(device);
    const uintptr_t key = reinterpret_cast<uintptr_t>(device);
    auto &cache = GetCachedModules();
    auto dit = cache.find(key);
    if(dit != cache.end()) {
        auto mit = dit->second.find(moduleName);
        if(mit != dit->second.end() && mit->second.Type() == tvtObject &&
           mit->second.AsObjectNoAddRef() != nullptr) {
            if(result) *result = mit->second;
            return TJS_S_OK;
        }
    }

    tjs_int w = 0, h = 0;
    device->GetSrcSize(w, h);
    tTJSVariant created;
    if(TJS_SUCCEEDED(TryCreateModuleViaKrkrGLES(&created, w, h))) {
        if(created.Type() == tvtObject && created.AsObjectNoAddRef() != nullptr)
            cache[key][moduleName] = created;
        if(result) *result = created;
        return TJS_S_OK;
    }
    if(TJS_SUCCEEDED(CreateFallbackModuleObject(&created, w, h))) {
        if(created.Type() == tvtObject && created.AsObjectNoAddRef() != nullptr)
            cache[key][moduleName] = created;
        if(result) *result = created;
        return TJS_S_OK;
    }
    if(result) result->Clear();
    return TJS_E_FAIL;
}

} // namespace DrawDeviceGLES
