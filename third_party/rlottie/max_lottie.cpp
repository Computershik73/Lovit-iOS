/* Обёртка над rlottie — см. max_lottie.h. */

#include "max_lottie.h"

#include <string>
#include <memory>

#include "rlottie.h"

namespace {

struct MaxLottie {
    std::unique_ptr<rlottie::Animation> animation;
};

}  // namespace

extern "C" {

void *max_lottie_open(const char *json, const char *key)
{
    if (json == nullptr) return nullptr;

    std::unique_ptr<rlottie::Animation> made =
        rlottie::Animation::loadFromData(std::string(json),
                                         key == nullptr ? std::string() : std::string(key));

    if (!made) return nullptr;

    MaxLottie *handle = new MaxLottie();
    handle->animation = std::move(made);

    return handle;
}

int max_lottie_frames(void *handle)
{
    MaxLottie *own = static_cast<MaxLottie *>(handle);
    if (own == nullptr) return 0;

    return static_cast<int>(own->animation->totalFrame());
}

double max_lottie_rate(void *handle)
{
    MaxLottie *own = static_cast<MaxLottie *>(handle);
    if (own == nullptr) return 0.0;

    return own->animation->frameRate();
}

void max_lottie_render(void *handle, int frame, uint32_t *buffer,
                       int width, int height, int stride)
{
    MaxLottie *own = static_cast<MaxLottie *>(handle);
    if (own == nullptr || buffer == nullptr || width <= 0 || height <= 0) return;

    rlottie::Surface surface(buffer,
                             static_cast<size_t>(width),
                             static_cast<size_t>(height),
                             static_cast<size_t>(stride));

    own->animation->renderSync(static_cast<size_t>(frame), surface);
}

void max_lottie_close(void *handle)
{
    delete static_cast<MaxLottie *>(handle);
}

}  // extern "C"
