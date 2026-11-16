// HD-2D 管線：低解析（640×360）HDR 場景 → 體積光 → 全解析移軸景深 → 前景散景 → bloom → 調色
import * as THREE from 'three';
import { buildWorld, CAM_Z, CAM_Y, FPX, LOW_W, LOW_H, HORIZON, SUN_DIR, SUN_COL, U, WATER_Y } from './world.js';

const Q = new URLSearchParams(location.search);
const FULL_W = 1920, FULL_H = 1080;
const canvas = document.getElementById('c');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'high-performance' });
renderer.setPixelRatio(1); renderer.setSize(FULL_W, FULL_H, false);
renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFShadowMap; renderer.shadowMap.autoUpdate = false;
renderer.autoClear = true;
{
  const gl = renderer.getContext(), e = gl.getExtension('WEBGL_debug_renderer_info');
  window.__gpu = e ? gl.getParameter(e.UNMASKED_RENDERER_WEBGL) : 'unknown';
}

// 移軸鏡頭：鏡頭水平看出去，再把成像往下平移（所有正對鏡頭的平面縮放一致 → 像素 1:1）
const camera = new THREE.PerspectiveCamera(2 * Math.atan(LOW_H / 2 / FPX) * 180 / Math.PI, LOW_W / LOW_H, 2, 600);
camera.position.set(0, CAM_Y, CAM_Z); camera.lookAt(0, CAM_Y, 0);
camera.setViewOffset(LOW_W, LOW_H, 0, HORIZON, LOW_W, LOW_H);
camera.updateMatrixWorld(); camera.updateProjectionMatrix();

const world = await buildWorld({ nofg: Q.has('nofg'), sunonly: Q.has('sunonly') });
const { scene } = world;

// ---------- render targets ----------
const rt = (w, h, { depth = false, filter = THREE.NearestFilter, type = THREE.HalfFloatType } = {}) => {
  const t = new THREE.WebGLRenderTarget(w, h, { type, minFilter: filter, magFilter: filter, depthBuffer: depth });
  if (depth) { t.depthTexture = new THREE.DepthTexture(w, h); t.depthTexture.type = THREE.UnsignedIntType; t.depthTexture.minFilter = t.depthTexture.magFilter = THREE.NearestFilter; }
  return t;
};
const LIN = THREE.LinearFilter;
const lowRT = rt(LOW_W, LOW_H, { depth: true });
const reflWater = rt(LOW_W, LOW_H, { depth: true }), reflStreet = rt(LOW_W, LOW_H, { depth: true });
const volA = rt(LOW_W, LOW_H, { filter: LIN }), volB = rt(LOW_W, LOW_H, { filter: LIN });
const compLow = rt(LOW_W, LOW_H);
const fgRT = rt(LOW_W, LOW_H, { depth: true, filter: LIN }), fgA = rt(LOW_W, LOW_H, { filter: LIN }), fgB = rt(LOW_W, LOW_H, { filter: LIN });
const dofRT = rt(FULL_W, FULL_H, { filter: LIN });
const bloomRT = []; for (let i = 0, w = FULL_W / 2, h = FULL_H / 2; i < 6; i++, w = Math.max(2, w >> 1), h = Math.max(2, h >> 1)) bloomRT.push(rt(w, h, { filter: LIN }));

// ---------- 全螢幕 pass ----------
const fsScene = new THREE.Scene(), fsCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
const fsMesh = new THREE.Mesh(new THREE.PlaneGeometry(2, 2)); fsMesh.frustumCulled = false; fsScene.add(fsMesh);
const VS = 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }';
const mk = (uniforms, fs) => new THREE.ShaderMaterial({ uniforms, vertexShader: VS, fragmentShader: fs, depthTest: false, depthWrite: false });
function pass(mat, target) { fsMesh.material = mat; renderer.setRenderTarget(target); renderer.render(fsScene, fsCam); }

// 體積光：沿視線步進，查太陽的陰影貼圖
const volMat = mk({
  tDepth: { value: lowRT.depthTexture }, tShadow: { value: null }, uShadowMat: { value: new THREE.Matrix4() },
  uInvProj: { value: new THREE.Matrix4() }, uCamWorld: { value: new THREE.Matrix4() }, uCamPos: { value: new THREE.Vector3() },
  uPool: { value: world.POOL }, uSunDir: { value: SUN_DIR }, uSunCol: { value: new THREE.Vector3(SUN_COL.r, SUN_COL.g, SUN_COL.b) }, uTime: U.time, uOn: { value: 1 },
}, `
  #include <packing>
  varying vec2 vUv; uniform sampler2D tDepth, tShadow; uniform mat4 uShadowMat, uInvProj, uCamWorld; uniform vec3 uCamPos, uSunDir, uSunCol, uPool; uniform float uTime, uOn;
  float h31(vec3 p){ p = fract(p * vec3(0.1031, 0.1030, 0.0973)); p += dot(p, p.yxz + 33.33); return fract((p.x + p.y) * p.z); }
  float vn3(vec3 p){ vec3 i = floor(p), f = fract(p); f = f*f*(3.0-2.0*f);
    return mix(mix(mix(h31(i), h31(i+vec3(1,0,0)), f.x), mix(h31(i+vec3(0,1,0)), h31(i+vec3(1,1,0)), f.x), f.y),
               mix(mix(h31(i+vec3(0,0,1)), h31(i+vec3(1,0,1)), f.x), mix(h31(i+vec3(0,1,1)), h31(i+vec3(1,1,1)), f.x), f.y), f.z); }
  float lit(vec3 p){
    vec4 sc = uShadowMat * vec4(p, 1.0); sc.xyz /= sc.w;
    if (sc.x < 0.0 || sc.x > 1.0 || sc.y < 0.0 || sc.y > 1.0 || sc.z > 1.0) return 1.0;
    return step(sc.z - 0.0015, unpackRGBAToDepth(texture2D(tShadow, sc.xy)));
  }
  void main(){
    float d = texture2D(tDepth, vUv).x;
    vec4 v = uInvProj * vec4(vUv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0); v /= v.w;
    vec3 wp = (uCamWorld * v).xyz;
    vec3 ray = wp - uCamPos; float dist = min(length(ray), 150.0); dist = min(dist, 80.0); ray = normalize(ray);
    const int N = 56;
    float dith = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
    float ds = dist / float(N);
    float cosT = dot(ray, uSunDir);
    float g = 0.62; float phase = (1.0 - g*g) / pow(1.0 + g*g - 2.0*g*cosT, 1.5) * 0.25 + 0.35;
    vec3 acc = vec3(0.0); float T = 1.0;
    for (int i = 0; i < N; i++) {
      vec3 p = uCamPos + ray * (float(i) + dith) * ds;
      // 均勻的貼地薄霧（高度衰減＋流動雜訊）；亮不亮完全由陰影貼圖決定，沒有環境散射 → 只有光束裡看得到霧
      // 立面前方的霧只到 2 樓高（再高就是整片受光的空氣）；缺口裡（z < -3.5）才一路延伸到樹冠
      float cap = mix(smoothstep(14.0, 3.0, p.y), smoothstep(4.6, 2.6, p.y), smoothstep(-4.6, -3.0, p.z));
      float hgt = exp(-max(p.y, 0.0) * 0.12) * cap;
      float n = vn3(p * vec3(0.16, 0.30, 0.16) + vec3(uTime * 0.10, -uTime * 0.02, uTime * 0.04));
      float n2 = vn3(p * 0.55 + vec3(-uTime * 0.16, 0.0, uTime * 0.08));
      // 沿光線方向拉長的條紋：把位置投影到垂直於太陽方向的平面再取雜訊
      vec3 q = p - uSunDir * dot(p, uSunDir);
      float st = vn3(q * 0.9 + vec3(uTime * 0.05, 0.0, 0.0)) * 0.65 + vn3(q * 2.1 + 7.0) * 0.35;
      float zf = smoothstep(2.0, -0.5, p.z) * smoothstep(-10.0, -6.5, p.z);
      float sig = 0.0075 * hgt * (0.45 + 0.8 * n * n + 0.3 * n2) * (0.30 + 1.4 * smoothstep(0.25, 0.75, st)) * zf;
      float l = lit(p);
      // 打在主角身上的那一道光：沿太陽方向、以光池為落點的圓錐，樹冠高度以上淡出
      float dax = length(cross(p - uPool, uSunDir));
      float cone = smoothstep(2.1, 0.3, dax) * smoothstep(11.0, 6.5, p.y);
      l = max(l * 0.22, cone); sig *= 0.55 + 1.6 * cone;   // 霧幾乎只在那一道光裡發亮
      vec3 Li = vec3(1.0, 0.56, 0.17) * 17.0 * phase * l;
      float a = 1.0 - exp(-sig * ds);
      acc += T * a * Li; T *= 1.0 - a;
    }
    gl_FragColor = vec4(acc * uOn, mix(1.0, T, uOn));
  }`);
const blurMat = mk({ tex: { value: null }, uDir: { value: new THREE.Vector2() } }, `
  varying vec2 vUv; uniform sampler2D tex; uniform vec2 uDir;
  void main(){ vec4 s = texture2D(tex, vUv) * 0.227027;
    s += (texture2D(tex, vUv + uDir * 1.3846) + texture2D(tex, vUv - uDir * 1.3846)) * 0.316216;
    s += (texture2D(tex, vUv + uDir * 3.2308) + texture2D(tex, vUv - uDir * 3.2308)) * 0.070270;
    gl_FragColor = s; }`);
const compMat = mk({ tColor: { value: lowRT.texture }, tVol: { value: volA.texture } }, `
  varying vec2 vUv; uniform sampler2D tColor, tVol;
  void main(){ vec4 c = texture2D(tColor, vUv), v = texture2D(tVol, vUv); gl_FragColor = vec4(c.rgb * v.a + v.rgb, 1.0); }`);
// 景深（Gustafsson 單趟 scatter-as-gather），CoC 由深度與畫面上下緣（移軸）決定
const dofMat = mk({
  tColor: { value: compLow.texture }, tDepth: { value: lowRT.depthTexture }, uNF: { value: new THREE.Vector2(camera.near, camera.far) },
  uPx: { value: new THREE.Vector2(1 / FULL_W, 1 / FULL_H) }, uFocus: { value: CAM_Z - 0.9 }, uOn: { value: 1 },
}, `
  varying vec2 vUv; uniform sampler2D tColor, tDepth; uniform vec2 uNF, uPx; uniform float uFocus, uOn;
  float viewZ(vec2 uv){ float d = texture2D(tDepth, uv).x; return (uNF.x * uNF.y) / (uNF.y - d * (uNF.y - uNF.x)); }
  float coc(vec2 uv){
    float z = viewZ(uv);
    float c = max(abs(1.0 / uFocus - 1.0 / z) - 0.0088, 0.0) * 560.0;
    c = z < uFocus ? c * 1.5 : min(c * 2.2, 9.0) * (z > 200.0 ? 0.35 : 1.0);
    // 移軸：畫面最下緣額外加一點
    c += smoothstep(0.15, 0.0, uv.y) * 2.0 + smoothstep(0.90, 1.0, uv.y) * 1.5;
    return min(c, 14.0) * uOn;
  }
  void main(){
    float cs = coc(vUv); float cz = viewZ(vUv);
    vec3 col = texture2D(tColor, vUv).rgb; float tot = 1.0;
    float rad = 0.9; float ang = 0.0;
    for (int i = 0; i < 90; i++) {
      if (rad > 14.0) break;
      ang += 2.39996323;
      vec2 tc = vUv + vec2(cos(ang), sin(ang)) * uPx * rad;
      float sz = viewZ(tc); float ss = coc(tc);
      if (sz > cz) ss = clamp(ss, 0.0, cs * 2.0);
      float m = smoothstep(rad - 0.5, rad + 0.5, ss);
      col += mix(col / tot, texture2D(tColor, tc).rgb, m); tot += 1.0;
      rad += 0.9 / rad;
    }
    gl_FragColor = vec4(col / tot, 1.0);
  }`);
// bloom
const preMat = mk({ tex: { value: dofRT.texture }, tFg: { value: fgA.texture } }, `
  varying vec2 vUv; uniform sampler2D tex, tFg;
  void main(){ vec4 f = texture2D(tFg, vUv); vec3 c = texture2D(tex, vUv).rgb * (1.0 - f.a) + f.rgb;
    float l = max(c.r, max(c.g, c.b)); if (!(l >= 0.0 && l < 500.0)) { c = vec3(0.0); l = 0.0; } gl_FragColor = vec4(c * smoothstep(1.0, 2.6, l), 1.0); }`);
const downMat = mk({ tex: { value: null }, uPx: { value: new THREE.Vector2() } }, `
  varying vec2 vUv; uniform sampler2D tex; uniform vec2 uPx;
  void main(){ vec4 s = texture2D(tex, vUv) * 4.0;
    s += texture2D(tex, vUv + uPx * vec2(-1, -1)) + texture2D(tex, vUv + uPx * vec2(1, -1)) + texture2D(tex, vUv + uPx * vec2(-1, 1)) + texture2D(tex, vUv + uPx * vec2(1, 1));
    gl_FragColor = s / 8.0; }`);
const upMat = mk({ tex: { value: null }, uPx: { value: new THREE.Vector2() } }, `
  varying vec2 vUv; uniform sampler2D tex; uniform vec2 uPx;
  void main(){ vec4 s = texture2D(tex, vUv + uPx * vec2(-1, 0)) + texture2D(tex, vUv + uPx * vec2(1, 0)) + texture2D(tex, vUv + uPx * vec2(0, -1)) + texture2D(tex, vUv + uPx * vec2(0, 1));
    s += (texture2D(tex, vUv + uPx * vec2(-1, -1)) + texture2D(tex, vUv + uPx * vec2(1, -1)) + texture2D(tex, vUv + uPx * vec2(-1, 1)) + texture2D(tex, vUv + uPx * vec2(1, 1))) * 0.5;
    gl_FragColor = vec4(s.rgb / 6.0, 1.0); }`);
upMat.blending = THREE.AdditiveBlending; upMat.transparent = true;
// 最終合成
const finalMat = mk({ tex: { value: dofRT.texture }, tFg: { value: fgA.texture }, tBloom: { value: bloomRT[0].texture }, uTime: U.time, uBloom: { value: Q.has('nobloom') ? 0 : 1 }, uRaw: { value: Q.has('raw') ? 1 : 0 } }, `
  varying vec2 vUv; uniform sampler2D tex, tFg, tBloom; uniform float uTime, uBloom, uRaw;
  const float BLACK = 0.0005;
  vec3 aces(vec3 x){ return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0); }
  float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
  vec3 scene(vec2 uv){ vec4 f = texture2D(tFg, uv); return texture2D(tex, uv).rgb * (1.0 - f.a) + f.rgb; }
  void main(){
    vec2 c = vUv - 0.5; float r2 = dot(c, c);
    vec3 col = scene(vUv);
    col += texture2D(tBloom, vUv).rgb * 0.15 * uBloom;
    if (uRaw < 0.5) {
      col *= 0.92;
      col = aces(col * 0.86);
      // 調色：暗部偏藍紫、亮部偏暖，稍微提飽和
      float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
      col = mix(vec3(l), col, 1.14);
      col *= mix(vec3(1.0), vec3(1.05, 1.0, 0.93), smoothstep(0.4, 1.0, l));
      col = pow(max(col, 0.0), vec3(1.10));
      float vig = 1.0 - smoothstep(0.18, 0.78, r2 * 1.45); col *= mix(0.74, 1.0, vig);
      col = max(col - BLACK, 0.0) / (1.0 - BLACK);   // 壓回黑位（色相不變）
    } else { col = aces(col * 0.8); }
    gl_FragColor = vec4(pow(clamp(col, 0.0, 1.0), vec3(1.0 / 2.2)), 1.0);
  }`);

const dbgMat = mk({ tex: { value: null } }, `varying vec2 vUv; uniform sampler2D tex; void main(){ vec4 c = texture2D(tex, vUv); gl_FragColor = vec4(pow(clamp(c.rgb / (1.0 + c.rgb), 0.0, 1.0), vec3(1.0 / 2.2)), 1.0); }`);
// ---------- 平面反射（數學同 three 的 Reflector） ----------
const vcam = new THREE.PerspectiveCamera();
const _n = new THREE.Vector3(0, 1, 0), _rp = new THREE.Vector3(), _cp = new THREE.Vector3(), _view = new THREE.Vector3(), _rot = new THREE.Matrix4(), _look = new THREE.Vector3(), _tgt = new THREE.Vector3(), _plane = new THREE.Plane(), _clip = new THREE.Vector4(), _q = new THREE.Vector4();
function renderReflection(y, target, texMat, hide) {
  _rp.set(0, y, 0); _cp.setFromMatrixPosition(camera.matrixWorld);
  _rot.extractRotation(camera.matrixWorld);
  _view.subVectors(_rp, _cp).reflect(_n).negate().add(_rp);
  _look.set(0, 0, -1).applyMatrix4(_rot).add(_cp);
  _tgt.subVectors(_rp, _look).reflect(_n).negate().add(_rp);
  vcam.position.copy(_view); vcam.up.set(0, 1, 0).applyMatrix4(_rot).reflect(_n); vcam.lookAt(_tgt);
  vcam.far = camera.far; vcam.updateMatrixWorld(); vcam.projectionMatrix.copy(camera.projectionMatrix);
  texMat.set(0.5, 0, 0, 0.5, 0, 0.5, 0, 0.5, 0, 0, 0.5, 0.5, 0, 0, 0, 1).multiply(vcam.projectionMatrix).multiply(vcam.matrixWorldInverse);
  _plane.setFromNormalAndCoplanarPoint(_n, _rp).applyMatrix4(vcam.matrixWorldInverse);
  _clip.set(_plane.normal.x, _plane.normal.y, _plane.normal.z, _plane.constant);
  const pm = vcam.projectionMatrix, e = pm.elements;
  _q.x = (Math.sign(_clip.x) + e[8]) / e[0]; _q.y = (Math.sign(_clip.y) + e[9]) / e[5]; _q.z = -1; _q.w = (1 + e[10]) / e[14];
  _clip.multiplyScalar(2 / _clip.dot(_q));
  e[2] = _clip.x; e[6] = _clip.y; e[10] = _clip.z + 1 - 0.003; e[14] = _clip.w;
  vcam.projectionMatrixInverse.copy(pm).invert();
  hide.forEach((o) => { o.visible = false; });
  renderer.setRenderTarget(target); renderer.render(scene, vcam);
  hide.forEach((o) => { o.visible = true; });
}

// ---------- 主迴圈 ----------
const NOVOL = Q.has('novol'), NOREFL = Q.has('noreflect'), NODOF = Q.has('nodof');
volMat.uniforms.uOn.value = NOVOL ? 0 : 1; dofMat.uniforms.uOn.value = NODOF ? 0 : 1;
world.waterU.uReflOn.value = NOREFL ? 0 : 1;
const black = new THREE.Color(0, 0, 0);
let fps = 0, last = performance.now(), frames = 0, acc = 0;
const t0 = performance.now(), fixedT = Q.has('t') ? parseFloat(Q.get('t')) : null;

function frame() {
  const now = performance.now();
  const t = fixedT ?? (now - t0) / 1000 + 20;
  world.update(t);
  renderer.shadowMap.needsUpdate = true;
  renderer.setClearColor(black, 1);

  // 反射
  world.reflU.uReflOn.value = 0;
  if (!NOREFL) {
    renderReflection(WATER_Y, reflWater, world.waterU.uTexMat.value, [world.water]);
    renderReflection(0.0, reflStreet, world.reflU.uTexMat.value, [world.water, world.street]);
    world.reflU.uReflOn.value = 1;
  }
  world.waterU.tRefl.value = reflWater.texture; world.reflU.tRefl.value = reflStreet.texture;
  world.waterU.tVol.value = NOVOL ? null : volA.texture;

  // 主場景（低解析）
  camera.layers.set(0);
  renderer.setRenderTarget(lowRT); renderer.render(scene, camera);

  // 體積光
  const sm = world.sun.shadow;
  if (sm.map) {
    volMat.uniforms.tShadow.value = sm.map.texture; volMat.uniforms.uShadowMat.value.copy(sm.matrix);
    world.shadowU.tShadow.value = sm.map.texture; world.shadowU.uShadowMat.value.copy(sm.matrix);
    volMat.uniforms.uInvProj.value.copy(camera.projectionMatrixInverse); volMat.uniforms.uCamWorld.value.copy(camera.matrixWorld);
    volMat.uniforms.uCamPos.value.copy(camera.position);
    pass(volMat, volA);
    for (let i = 0; i < 1; i++) {
      blurMat.uniforms.tex.value = volA.texture; blurMat.uniforms.uDir.value.set(1 / LOW_W, 0); pass(blurMat, volB);
      blurMat.uniforms.tex.value = volB.texture; blurMat.uniforms.uDir.value.set(0, 1 / LOW_H); pass(blurMat, volA);
    }
  }
  pass(compMat, compLow);

  // 近前景層 → 模糊
  renderer.setClearColor(black, 0);
  camera.layers.set(1);
  renderer.setRenderTarget(fgRT); renderer.render(scene, camera);
  camera.layers.set(0);
  let src = fgRT;
  for (let i = 0; i < 0; i++) { // 前景楓枝保持銳利的剪影，不再糊成色塊
    blurMat.uniforms.tex.value = src.texture; blurMat.uniforms.uDir.value.set(1.6 / LOW_W, 0); pass(blurMat, fgB);
    blurMat.uniforms.tex.value = fgB.texture; blurMat.uniforms.uDir.value.set(0, 1.6 / LOW_H); pass(blurMat, fgA);
    src = fgA;
  }
  preMat.uniforms.tFg.value = finalMat.uniforms.tFg.value = src.texture;
  renderer.setClearColor(black, 1);

  // 景深
  pass(dofMat, dofRT);
  // bloom
  pass(preMat, bloomRT[0]);
  for (let i = 1; i < bloomRT.length; i++) { downMat.uniforms.tex.value = bloomRT[i - 1].texture; downMat.uniforms.uPx.value.set(1 / bloomRT[i - 1].width, 1 / bloomRT[i - 1].height); pass(downMat, bloomRT[i]); }
  renderer.autoClear = false;
  for (let i = bloomRT.length - 1; i > 0; i--) { upMat.uniforms.tex.value = bloomRT[i].texture; upMat.uniforms.uPx.value.set(1 / bloomRT[i].width, 1 / bloomRT[i].height); pass(upMat, bloomRT[i - 1]); }
  renderer.autoClear = true;
  if (Q.has('view')) { dbgMat.uniforms.tex.value = ({ low: lowRT, vol: volA, comp: compLow, rw: reflWater, rs: reflStreet, fg: fgRT, dof: dofRT, bloom: bloomRT[0], sm: world.sun.shadow.map })[Q.get('view')].texture; pass(dbgMat, null); }
  else pass(finalMat, null);

  frames++; acc += now - last; last = now;
  if (acc > 1000) { fps = frames * 1000 / acc; frames = 0; acc = 0; window.__fps = fps; }
  window.__frames = (window.__frames || 0) + 1;
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
