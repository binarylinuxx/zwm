const std = @import("std");

// Cubic Bezier easing function
pub fn cubicBezier(t: f32, p0: f32, p1: f32, p2: f32, p3: f32) f32 {
    const u = 1.0 - t;
    const tt = t * t;
    const uu = u * u;
    const uuu = uu * u;
    const ttt = tt * t;

    return uuu * p0 + 3 * uu * t * p1 + 3 * u * tt * p2 + ttt * p3;
}

// Solve cubic bezier equation for t given x using Newton-Raphson method for better performance
pub fn solveCubicBezier(x: f32, p0x: f32, p1x: f32, p2x: f32, p3x: f32) f32 {
    // Start with a linear guess
    var t = x;
    
    // Newton-Raphson iterations for faster convergence
    for (0..8) |_| {  // Reduced iterations for better performance
        const x_t = cubicBezier(t, p0x, p1x, p2x, p3x);
        const dx_dt = cubicBezierDerivative(t, p0x, p1x, p2x, p3x);
        
        // Avoid division by zero
        if (@abs(dx_dt) < 0.0001) break;
        
        const diff = x_t - x;
        if (@abs(diff) < 0.001) break;
        
        t -= diff / dx_dt;
        // Clamp t to [0, 1] range
        t = @max(0.0, @min(1.0, t));
    }
    
    return t;
}

// Derivative of cubic bezier for Newton-Raphson method
pub fn cubicBezierDerivative(t: f32, p0: f32, p1: f32, p2: f32, p3: f32) f32 {
    const u = 1.0 - t;
    return 3.0 * (u * u * (p1 - p0) + 2 * u * t * (p2 - p1) + t * t * (p3 - p2));
}

// Get eased value using cubic bezier with standard ease-in-out curve
pub fn easeCubicBezier(t: f32, p0x: f32, p0y: f32, p1x: f32, p1y: f32, p2x: f32, p2y: f32, p3x: f32, p3y: f32) f32 {
    const x = cubicBezier(t, p0x, p1x, p2x, p3x);
    const t_val = solveCubicBezier(x, p0x, p1x, p2x, p3x);
    const y = cubicBezier(t_val, p0y, p1y, p2y, p3y);
    return y;
}

// Spring dynamics constants
pub const SpringParams = struct {
    frequency: f32 = 8.0,  // Angular frequency (controls speed)
    damping_ratio: f32 = 0.8,  // Damping ratio (1.0 = critically damped, < 1.0 = underdamped)
};

// Spring interpolation function
pub fn springInterpolate(t: f32, params: SpringParams) f32 {
    // Calculate damping coefficient and angular frequency
    const zeta = params.damping_ratio;
    const w0 = params.frequency;
    
    // Calculate damped frequency
    const wd = if (zeta < 1.0) w0 * @sqrt(1.0 - zeta * zeta) else 0.0;
    
    if (zeta > 1.0) {
        // Overdamped case
        const r1 = -zeta * w0 + @sqrt(zeta * zeta - 1.0) * w0;
        const r2 = -zeta * w0 - @sqrt(zeta * zeta - 1.0) * w0;
        const c1 = 1.0;  // Since we start at 0
        const c2 = (zeta * w0 - r1) / (r2 - r1);  // To satisfy initial conditions
        
        return 1.0 - (c1 * @exp(r1 * t) + c2 * @exp(r2 * t));
    } else if (zeta == 1.0) {
        // Critically damped case
        return 1.0 - (1.0 + w0 * t) * @exp(-w0 * t);
    } else {
        // Underdamped case (oscillating)
        const envelope = @exp(-zeta * w0 * t);
        const oscillation = @cos(wd * t) + (zeta * w0 / wd) * @sin(wd * t);
        return 1.0 - envelope * oscillation;
    }
}

pub const Layer = enum {
    background,
    bottom,
    app,
    top,
    overlay,
};