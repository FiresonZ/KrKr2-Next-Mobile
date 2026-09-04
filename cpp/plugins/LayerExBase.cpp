#include "LayerExBase.h"
#include "LayerImpl.h"
#include "MsgIntf.h"

int NI_LayerExBase::classId;

static tTJSNI_Layer *GetNativeLayer(iTJSDispatch2 *layerobj) {
    tTJSNI_Layer *ni = nullptr;
    tjs_error hr = layerobj->NativeInstanceSupport(
        TJS_NIS_GETINSTANCE, tTJSNC_Layer::ClassID,
        (iTJSNativeInstance **)&ni);
    if(TJS_FAILED(hr) || !ni)
        TVPThrowExceptionMessage(TJS_W("Not Layer"));
    return ni;
}

void NI_LayerExBase::reset(iTJSDispatch2 *layerobj) {
    tTJSNI_Layer *ni = GetNativeLayer(layerobj);
    _width  = (int)ni->GetWidth();
    _height = (int)ni->GetHeight();
    _buffer = (unsigned char *)ni->GetMainImagePixelBufferForWrite();
    _pitch  = (int)ni->GetMainImagePixelBufferPitch();
}

void NI_LayerExBase::redraw(iTJSDispatch2 *layerobj) {
    tTJSNI_Layer *ni = GetNativeLayer(layerobj);
    tTVPRect rc(0, 0, (tjs_int)ni->GetWidth(), (tjs_int)ni->GetHeight());
    ni->Update(rc);
}

NI_LayerExBase *NI_LayerExBase::getNative(iTJSDispatch2 *objthis, bool create) {
    NI_LayerExBase *_this = nullptr;
    if(TJS_FAILED(objthis->NativeInstanceSupport(
           TJS_NIS_GETINSTANCE, classId, (iTJSNativeInstance **)&_this)) &&
       create) {
        _this = new NI_LayerExBase();
        if(TJS_FAILED(objthis->NativeInstanceSupport(
               TJS_NIS_REGISTER, classId, (iTJSNativeInstance **)&_this))) {
            delete _this;
            _this = nullptr;
        }
    }
    return _this;
}

NI_LayerExBase::NI_LayerExBase() {
    _width = 0;
    _height = 0;
    _pitch = 0;
    _buffer = nullptr;
}
