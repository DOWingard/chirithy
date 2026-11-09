// Lux trail
//
// When the cursor jumps, a streak of light follows it and a few star-shaped
// sparkles burst where it lands. Moving a single cell does nothing, so plain
// typing stays calm; the effect shows on line changes, prompt returns and
// jumps inside an editor.
//
// Everything is tinted with the cursor color, so it follows the theme.
//
// An animated shader keeps the focused terminal rendering every frame, which
// costs GPU time and battery. That is why this is opt-in.

// How long the effect lasts after the cursor moved, in seconds.
const float DURATION = 0.45;

// How far the cursor has to move before the effect shows, in cells.
const float MIN_JUMP = 1.5;
const float FULL_JUMP = 3.0;

const int SPARKLES = 5;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// A four-pointed sparkle of radius `r` centered on the origin. The shape is
// an astroid, which pinches toward the axes like a glint of light.
float sparkle(vec2 p, float r) {
    if (r <= 0.0) return 0.0;
    vec2 q = abs(p) / r;
    float d = pow(q.x, 0.55) + pow(q.y, 0.55);
    return 1.0 - smoothstep(0.75, 1.0, d);
}

// Center of a cursor rectangle. Its xy is the top-left corner in a space
// whose y axis points up, so the center is half a height below it.
vec2 center(vec4 cursor) {
    return cursor.xy + vec2(0.5, -0.5) * cursor.zw;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec4 base = texture(iChannel0, fragCoord / iResolution.xy);

    float age = iTime - iTimeCursorChange;
    if (iCursorVisible == 0 || age < 0.0 || age > DURATION) {
        fragColor = base;
        return;
    }

    // 1 right after the move, 0 when the effect ends.
    float life = 1.0 - age / DURATION;

    vec2 cur = center(iCurrentCursor);
    vec2 prev = center(iPreviousCursor);

    // The cursor height is the cell height for every cursor style, which
    // makes it a stable unit to size things with.
    float cell = max(iCurrentCursor.w, 1.0);

    vec2 path = cur - prev;
    float jump = length(path) / cell;
    float strength = smoothstep(MIN_JUMP, FULL_JUMP, jump);
    if (strength <= 0.0) {
        fragColor = base;
        return;
    }

    // Streak: a line from where the cursor was to where it is, brightest at
    // the cursor and thinning out as it ages.
    vec2 rel = fragCoord - prev;
    float along = clamp(dot(rel, path) / max(dot(path, path), 0.0001), 0.0, 1.0);
    float dist = length(rel - path * along);
    float streak = (1.0 - smoothstep(0.0, 0.22 * cell * life, dist)) * along * life;

    // Sparkles: thrown outward from the landing spot. The seed changes with
    // every move so that each burst looks different.
    float seed = floor(iTimeCursorChange * 97.0);
    float burst = 0.0;
    for (int i = 0; i < SPARKLES; i++) {
        float fi = float(i);
        float angle = 6.2831853 * hash(vec2(fi, seed));
        float reach = cell * (0.5 + 1.4 * (1.0 - life)) * (0.6 + 0.7 * hash(vec2(seed, fi + 3.0)));
        float size = cell * (0.38 + 0.3 * hash(vec2(fi + 11.0, seed))) * life;
        vec2 at = cur + reach * vec2(cos(angle), sin(angle));
        burst = max(burst, sparkle(fragCoord - at, size));
    }

    // Blend toward the cursor color instead of adding light, so the effect
    // is visible on light backgrounds as well as dark ones.
    vec3 glow = iCurrentCursorColor.rgb;
    float amount = clamp(0.55 * streak + 0.9 * burst * life, 0.0, 0.9) * strength;
    fragColor = vec4(mix(base.rgb, glow, amount), base.a);
}
