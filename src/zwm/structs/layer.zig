pub const Layer = enum {
    background,
    bottom,
    app,
    top,
    overlay,
    popups,  // Dedicated layer for all popups, above everything else
};