-- CRT filter: the last step that puts the 320x180 canvas on the screen.
-- One still pass (nothing animates): a slight bulge, one dark scanline per
-- row of game pixels, a soft glow around bright pixels, darker corners and a
-- faint colour fringe towards the edges. Each part has its own strength,
-- 0..1, in a table: scanlines, glow, vignette, fringe, bulge.
--
-- The same pass also blends pixel edges very slightly, so pixels keep an even
-- size where the bulge or a fractional scale would make them uneven.

local Crt = {
  ok = false,     -- false when the shader could not be built: the game runs unfiltered
  -- What each part amounts to at full strength:
  K = 0.045,        -- bulge
  CORNER = 8,       -- radius of the tube's rounded corners, in game pixels (follows the bulge)
  SCAN = 0.6,       -- how dark a scanline is
  GLOW = 0.8,
  VIGNETTE = 0.45,  -- how dark the corners get
  FRINGE = 0.3,     -- colour drift at the corners, in game pixels
}

local CODE = [[
uniform vec2 size;      // canvas size in game pixels
uniform float scale;    // screen pixels per game pixel
uniform float bulge;
uniform float corner;
uniform float scan;
uniform float glow;
uniform float vignette;
uniform float fringe;

// A game pixel with crisp but blended edges. `p` is in game pixels; the
// canvas is sampled with linear filtering.
vec3 sharp(Image tex, vec2 p) {
  vec2 cell = floor(p);
  vec2 f = fract(p) - 0.5;
  vec2 inner = vec2(0.5 - 0.5 / scale);
  f = (f - clamp(f, -inner, inner)) * scale + 0.5;
  return Texel(tex, (cell + f) / size).rgb;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
  // Bulge: edges stay put at their middles, corners pull in. Keep in step
  // with Crt.warp below.
  vec2 c = uv * 2.0 - 1.0;
  vec2 d = c * (1.0 + bulge * c.yx * c.yx);
  vec2 p = (d * 0.5 + 0.5) * size;

  // Colour fringe: red and blue drift apart, growing towards the corners.
  vec2 drift = c * dot(c, c) * fringe;
  vec3 col = vec3(sharp(tex, p + drift).r, sharp(tex, p).g, sharp(tex, p - drift).b);

  // Glow: a small blur of the neighbourhood, kept only where it is bright.
  vec2 u = p / size;
  vec2 px = 1.0 / size;
  vec3 g = Texel(tex, u + px * vec2( 1.5,  1.5)).rgb
         + Texel(tex, u + px * vec2(-1.5,  1.5)).rgb
         + Texel(tex, u + px * vec2( 1.5, -1.5)).rgb
         + Texel(tex, u + px * vec2(-1.5, -1.5)).rgb
         + Texel(tex, u + px * vec2( 2.5,  0.0)).rgb
         + Texel(tex, u + px * vec2(-2.5,  0.0)).rgb
         + Texel(tex, u + px * vec2( 0.0,  2.5)).rgb
         + Texel(tex, u + px * vec2( 0.0, -2.5)).rgb;
  g *= 0.125;
  g *= smoothstep(0.12, 0.55, max(g.r, max(g.g, g.b)));
  col = 1.0 - (1.0 - col) * (1.0 - g * glow);

  // Scanlines: one dark stripe along the bottom of each row of game pixels,
  // weaker over bright colours.
  float row = abs(fract(p.y - 0.375) - 0.5) * 2.0;
  float dark = 1.0 - smoothstep(0.0, 0.5, row);
  float luma = dot(col, vec3(0.299, 0.587, 0.114));
  col *= 1.0 - scan * dark * (1.0 - 0.4 * luma);
  col *= 1.0 + scan * 0.2;

  // Darker corners.
  col *= 1.0 - vignette * smoothstep(0.5, 2.0, dot(c, c));

  // The tube's outline: black outside the picture, corners rounded off.
  vec2 hs = size * 0.5;
  float rad = corner + 0.001;
  vec2 q = abs(d) * hs - (hs - rad);
  float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
  col *= 1.0 - smoothstep(-0.5 / scale, 0.5 / scale, dist);

  return vec4(col, 1.0) * color;
}
]]

function Crt.load()
  local ok, shader = pcall(love.graphics.newShader, CODE)
  Crt.ok = ok
  if ok then
    Crt.shader = shader
  else
    print('CRT filter unavailable: ' .. tostring(shader))
  end
end

-- Where a point of the picture rectangle (u, v in 0..1) reads from the
-- canvas, also 0..1. The mouse goes through this so clicks land on what is
-- drawn under the cursor.
function Crt.warp(u, v, levels)
  local k = Crt.K * levels.bulge
  if k <= 0 then return u, v end
  local cx, cy = u * 2 - 1, v * 2 - 1
  return (cx * (1 + k * cy * cy) + 1) / 2, (cy * (1 + k * cx * cx) + 1) / 2
end

local function smoothstep(a, b, x)
  x = math.max(0, math.min(1, (x - a) / (b - a)))
  return x * x * (3 - 2 * x)
end

-- True when every part is at 0: the filter has nothing to draw.
function Crt.off(levels)
  for _, v in pairs(levels) do
    if v > 0 then return false end
  end
  return true
end

-- Draw `canvas` at (x, y), `s` screen pixels per game pixel. Scanlines need
-- about three screen pixels per row, so they fade out below 3x.
function Crt.draw(canvas, x, y, s, levels)
  local shader = Crt.shader
  shader:send('size', { canvas:getDimensions() })
  shader:send('scale', s)
  shader:send('bulge', Crt.K * levels.bulge)
  shader:send('corner', Crt.CORNER * levels.bulge)
  shader:send('scan', Crt.SCAN * levels.scanlines * smoothstep(2, 3, s))
  shader:send('glow', Crt.GLOW * levels.glow)
  shader:send('vignette', Crt.VIGNETTE * levels.vignette)
  shader:send('fringe', Crt.FRINGE * levels.fringe)
  canvas:setFilter('linear', 'linear')
  love.graphics.setShader(shader)
  love.graphics.draw(canvas, x, y, 0, s, s)
  love.graphics.setShader()
  canvas:setFilter('nearest', 'nearest')
end

return Crt
