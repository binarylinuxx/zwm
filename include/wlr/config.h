#ifndef WLR_CONFIG_H
#define WLR_CONFIG_H

/**
 * Whether the DRM backend is compile-time enabled. Equivalent to the
 * pkg-config "have_drm_backend" variable.
 *
 * Required for <wlr/backend/drm.h>.
 */
#define WLR_HAS_DRM_BACKEND 1
/**
 * Whether the libinput backend is compile-time enabled. Equivalent to the
 * pkg-config "have_libinput_backend" vartiable.
 *
 * Required for <wlr/backend/libinput.h>.
 */
#define WLR_HAS_LIBINPUT_BACKEND 1
/**
 * Whether the X11 backend is compile-time enabled. Equivalent to the
 * pkg-config "have_x11_backend" variable.
 *
 * Required for <wlr/backend/x11.h>.
 */
#define WLR_HAS_X11_BACKEND 1

/**
 * Whether the GLES2 renderer is compile-time enabled. Equivalent to the
 * pkg-config "have_gles2_renderer" variable.
 *
 * Required for <wlr/render/gles2.h>.
 */
#define WLR_HAS_GLES2_RENDERER 1
/**
 * Whether the Vulkan renderer is compile-time enabled. Equivalent to the
 * pkg-config "have_vulkan_renderer" variable.
 *
 * Required for <wlr/render/vulkan.h>.
 */
#define WLR_HAS_VULKAN_RENDERER 1

/**
 * Whether the GBM allocator is compile-time enabled. Equivalent to the
 * pkg-config "have_gbm_allocator" variable.
 */
#define WLR_HAS_GBM_ALLOCATOR 1
/**
 * Whether the udmabuf allocator is compile-time enabled. Equivalent to the
 * pkg-config "have_udmabuf_allocator" variable.
 */
#define WLR_HAS_UDMABUF_ALLOCATOR 1

/**
 * Whether Xwayland support is compile-time enabled. Equivalent to the
 * pkg-config "have_xwayland" variable.
 *
 * Required for <wlr/xwayland/…>.
 */
#define WLR_HAS_XWAYLAND 1

/**
 * Whether session support is compile-time enabled. Equivalent to the
 * pkg-config "have_session" variable.
 *
 * Required for <wlr/backend/session.h>.
 */
#define WLR_HAS_SESSION 1

/**
 * Whether traditional color management support is compile-time enabled.
 * Equivalent to the pkg-config "have_color_management" variable.
 *
 * Required for ICC profile support in <wlr/render/color.h>.
 */
#define WLR_HAS_COLOR_MANAGEMENT 1

#endif
