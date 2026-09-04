#ifndef __LayerExBase__
#define __LayerExBase__

#include "tjsNative.h"

class tTJSNI_Layer;

/**
 * Layer extension native instance — uses direct C++ calls for performance.
 */
class NI_LayerExBase : public tTJSNativeInstance {
public:
    tjs_int _width;
    tjs_int _height;
    tjs_int _pitch;
    unsigned char *_buffer;

public:
    static int classId;

    static NI_LayerExBase *getNative(iTJSDispatch2 *objthis,
                                     bool create = true);

    void reset(iTJSDispatch2 *layerobj);
    void redraw(iTJSDispatch2 *layerobj);

    NI_LayerExBase();
};

#endif
