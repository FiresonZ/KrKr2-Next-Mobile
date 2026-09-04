//---------------------------------------------------------------------------
/*
        TJS2 Script Engine
        Copyright (C) 2000 W.Dee <dee@kikyou.info> and contributors

        See details of license at "license.txt"
*/
//---------------------------------------------------------------------------
// Script block caching
//---------------------------------------------------------------------------

#include "tjsCommHead.h"

#include "tjs.h"
#include "tjsScriptCache.h"
#include "tjsScriptBlock.h"
#include "tjsByteCodeLoader.h"
#include <atomic>

#define TJS_SCRIPT_CACHE_MAX 1024

static std::atomic<int64_t> sExecCacheHit{0};
static std::atomic<int64_t> sExecCacheMiss{0};
static std::atomic<int64_t> sExecNamed{0};
static std::atomic<int64_t> sEvalCacheHit{0};
static std::atomic<int64_t> sEvalCacheMiss{0};

extern "C" void TJS_GetScriptCacheStats(int64_t *exec_hit, int64_t *exec_miss,
                                         int64_t *exec_named,
                                         int64_t *eval_hit, int64_t *eval_miss) {
    if(exec_hit) *exec_hit = sExecCacheHit.load(std::memory_order_relaxed);
    if(exec_miss) *exec_miss = sExecCacheMiss.load(std::memory_order_relaxed);
    if(exec_named) *exec_named = sExecNamed.load(std::memory_order_relaxed);
    if(eval_hit) *eval_hit = sEvalCacheHit.load(std::memory_order_relaxed);
    if(eval_miss) *eval_miss = sEvalCacheMiss.load(std::memory_order_relaxed);
}

namespace TJS {
    //---------------------------------------------------------------------------
    // tTJSScriptCache - a class to cache script blocks
    //---------------------------------------------------------------------------
    tTJSScriptCache::tTJSScriptCache(tTJS *owner) :
        Cache(TJS_SCRIPT_CACHE_MAX) {
        Owner = owner;
    }

    //---------------------------------------------------------------------------
    tTJSScriptCache::~tTJSScriptCache() = default;

    //---------------------------------------------------------------------------
    void tTJSScriptCache::ExecScript(const tjs_char *script,
                                     tTJSVariant *result,
                                     iTJSDispatch2 *context,
                                     const tjs_char *name, tjs_int lineofs) {
        if(name) {
            sExecNamed.fetch_add(1, std::memory_order_relaxed);
            auto *blk = new tTJSScriptBlock(Owner);
            try {
                blk->SetName(name, lineofs);
                blk->SetText(result, script, context, false);
            } catch(...) {
                blk->Release();
                throw;
            }
            blk->Release();
            return;
        }

        tScriptCacheData data;
        data.Script = script;
        data.ExpressionMode = false;
        data.MustReturnResult = result != nullptr;

        tjs_uint32 hash = tScriptCacheHashFunc::Make(data);
        tScriptBlockHolder *holder = Cache.FindAndTouchWithHash(data, hash);
        if(holder) {
            sExecCacheHit.fetch_add(1, std::memory_order_relaxed);
            holder->GetObjectNoAddRef()->ExecuteTopLevelScript(result, context);
            return;
        }

        sExecCacheMiss.fetch_add(1, std::memory_order_relaxed);
        auto *blk = new tTJSScriptBlock(Owner);
        try {
            blk->SetText(result, script, context, false);
        } catch(...) {
            blk->Release();
            throw;
        }
        if(blk->IsReusable()) {
            tScriptBlockHolder newholder(blk);
            Cache.AddWithHash(data, hash, newholder);
        }
        blk->Release();
    }

    //---------------------------------------------------------------------------
    void tTJSScriptCache::ExecScript(const ttstr &script, tTJSVariant *result,
                                     iTJSDispatch2 *context, const ttstr *name,
                                     tjs_int lineofs) {
        if(name && !name->IsEmpty()) {
            sExecNamed.fetch_add(1, std::memory_order_relaxed);
            auto *blk = new tTJSScriptBlock(Owner);
            try {
                blk->SetName(name->c_str(), lineofs);
                blk->SetText(result, script.c_str(), context, false);
            } catch(...) {
                blk->Release();
                throw;
            }
            blk->Release();
            return;
        }

        tScriptCacheData data;
        data.Script = script;
        data.ExpressionMode = false;
        data.MustReturnResult = result != nullptr;

        tjs_uint32 hash = tScriptCacheHashFunc::Make(data);
        tScriptBlockHolder *holder = Cache.FindAndTouchWithHash(data, hash);
        if(holder) {
            sExecCacheHit.fetch_add(1, std::memory_order_relaxed);
            holder->GetObjectNoAddRef()->ExecuteTopLevelScript(result, context);
            return;
        }

        sExecCacheMiss.fetch_add(1, std::memory_order_relaxed);
        auto *blk = new tTJSScriptBlock(Owner);
        try {
            blk->SetText(result, script.c_str(), context, false);
        } catch(...) {
            blk->Release();
            throw;
        }
        if(blk->IsReusable()) {
            tScriptBlockHolder newholder(blk);
            Cache.AddWithHash(data, hash, newholder);
        }
        blk->Release();
    }

    //---------------------------------------------------------------------------
    void tTJSScriptCache::EvalExpression(const tjs_char *expression,
                                         tTJSVariant *result,
                                         iTJSDispatch2 *context,
                                         const tjs_char *name,
                                         tjs_int lineofs) {
        // currently this works only with anonymous script blocks.
        if(name) {
            auto *blk = new tTJSScriptBlock(Owner);
            blk->SetExpressionMode(true);

            try {
                blk->SetName(name, lineofs);
                blk->SetText(result, expression, context, true);
            } catch(...) {
                blk->Release();
                throw;
            }

            blk->Release();
            return;
        }

        // search through script block cache
        tScriptCacheData data;
        data.Script = expression;
        data.ExpressionMode = true;
        data.MustReturnResult = result != nullptr;

        tjs_uint32 hash = tScriptCacheHashFunc::Make(data);

        tScriptBlockHolder *holder = Cache.FindAndTouchWithHash(data, hash);

        if(holder) {
            sEvalCacheHit.fetch_add(1, std::memory_order_relaxed);
            holder->GetObjectNoAddRef()->ExecuteTopLevelScript(result, context);
            return;
        }

        sEvalCacheMiss.fetch_add(1, std::memory_order_relaxed);
        auto *blk = new tTJSScriptBlock(Owner);
        blk->SetExpressionMode(true);

        try {
            blk->SetText(result, expression, context, true);
        } catch(...) {
            blk->Release();
            throw;
        }

        // add to cache
        if(blk->IsReusable()) {
            tScriptBlockHolder newholder(blk);
            Cache.AddWithHash(data, hash, newholder);
        }

        blk->Release();
    }

    //---------------------------------------------------------------------------
    void tTJSScriptCache::EvalExpression(const ttstr &expression,
                                         tTJSVariant *result,
                                         iTJSDispatch2 *context,
                                         const ttstr *name, tjs_int lineofs) {
        // currently this works only with anonymous script blocks.
        if(name && !name->IsEmpty()) {
            auto *blk = new tTJSScriptBlock(Owner);
            blk->SetExpressionMode(true);

            try {
                blk->SetName(name->c_str(), lineofs);
                blk->SetText(result, expression.c_str(), context, true);
            } catch(...) {
                blk->Release();
                throw;
            }

            blk->Release();
            return;
        }

        // search through script block cache
        tScriptCacheData data;
        data.Script = expression;
        data.ExpressionMode = true;
        data.MustReturnResult = result != nullptr;

        tjs_uint32 hash = tScriptCacheHashFunc::Make(data);

        tScriptBlockHolder *holder = Cache.FindAndTouchWithHash(data, hash);

        if(holder) {
            sEvalCacheHit.fetch_add(1, std::memory_order_relaxed);
            holder->GetObjectNoAddRef()->ExecuteTopLevelScript(result, context);
            return;
        }

        sEvalCacheMiss.fetch_add(1, std::memory_order_relaxed);
        auto *blk = new tTJSScriptBlock(Owner);
        blk->SetExpressionMode(true);

        try {
            blk->SetText(result, expression.c_str(), context, true);
        } catch(...) {
            blk->Release();
            throw;
        }

        // add to cache
        if(blk->IsReusable()) {
            tScriptBlockHolder newholder(blk);
            Cache.AddWithHash(data, hash, newholder);
        }

        blk->Release();
    }

    //---------------------------------------------------------------------------
    // for Bytecode
    void tTJSScriptCache::LoadByteCode(const tjs_uint8 *buff, size_t len,
                                       tTJSVariant *result,
                                       iTJSDispatch2 *context,
                                       const tjs_char *name) {
        auto loader = std::make_unique<tTJSByteCodeLoader>();
        std::unique_ptr<tTJSScriptBlock, std::function<void(tTJSScriptBlock *)>>
            blk{ loader->ReadByteCode(Owner, name, buff, len),
                 [](auto *ptr) { ptr->Release(); } };
        if(blk != nullptr) {
            blk->ExecuteTopLevel(result, context);
            return;
        }
        TJS_eTJSScriptError(TJSByteCodeBroken, blk.get(), 0);
    }
    //---------------------------------------------------------------------------
    void tTJSScriptCache::Compact(tjs_int level) {
        if(level >= 3) {
            Cache.Clear();
        } else if(level >= 2) {
            tjs_int count = (tjs_int)Cache.GetCount();
            tjs_int toRemove = count / 2;
            if(toRemove > 0)
                Cache.ChopLast(toRemove);
        } else if(level >= 1) {
            tjs_int count = (tjs_int)Cache.GetCount();
            tjs_int toRemove = count / 8;
            if(toRemove > 0)
                Cache.ChopLast(toRemove);
        }
    }
    //---------------------------------------------------------------------------
} // namespace TJS
