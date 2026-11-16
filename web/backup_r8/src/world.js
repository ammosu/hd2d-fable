// 場景：黃昏逆光的運河小鎮。單位公尺，x 向右、y 向上、z 朝鏡頭。
import * as THREE from 'three';
import * as P from './ptex.js';

export const CAM_Z = 30, CAM_Y = 9, FPX = 670, LOW_W = 640, LOW_H = 360, HORIZON = 125;
// 深度 z 的平面上，每公尺佔幾個低解析像素（貼圖 1 texel = 1 像素的依據）
export const ppm = (z) => FPX / (CAM_Z - z);

export const WATER_Y = -0.7;
export const GROUND_SQ = 2.0; // 地面貼圖在螢幕上壓扁的倍數（石頭寬:高 = 2:1）
export const SUN_DIR = new THREE.Vector3(-0.22, 0.40, -0.84).normalize(); // 指向太陽
export const SUN_COL = new THREE.Color(1.0, 0.62, 0.30);
export const U = { time: { value: 0 } };

export async function buildWorld(opts = {}) {
  const scene = new THREE.Scene();
  const R = P.rng(1234);
  const rr = (a, b) => a + (b - a) * R();

  // ---------- 貼圖 ----------
  const loader = new THREE.TextureLoader();
  const meta = await (await fetch('/tex/meta.json')).json();
  const T = {};
  await Promise.all(Object.keys(meta).filter((n) => !n.endsWith('_cells')).map(async (n) => {
    const t = await loader.loadAsync(`/tex/${n}.png`);
    P.pix(t, (meta[n][0] === meta[n][1] && meta[n][0] >= 64) || n === 'street7' || n === 'quay7'); t.userData = { w: meta[n][0], h: meta[n][1] };
    if (n === 'sky7') t.wrapS = THREE.MirroredRepeatWrapping;
    T[n] = t;
  }));
  if (T.roof_red2) T.rooftile = T.roof_red2; if (T.roof_slate2) T.slate = T.roof_slate2;
  T.bark = P.barkTex(); T.lawn = P.lawnTex(); T.awning = P.awningTex(); T.awning2 = P.awningTex([52, 110, 116], [236, 226, 200]);
  T.leaf = P.leafAtlas(); T.plant = P.plantAtlas(); T.bird = P.birdTex(); T.bfly = P.butterflyTex(); T.leafbit = P.leafBit(); T.smoke = P.smokeTex();
  T.wood = P.flat([74, 50, 40]); T.iron = P.flat([34, 32, 44]); T.white = P.flat([255, 255, 255]);

  // ---------- 材質 ----------
  // 世界座標三向投影，密度依所在深度換算成 1 texel = 1 低解析像素
  const triCache = new Map();
  function tri(tex, { z = -3.5, tint = 0xffffff, mode = 0, emissive = 0x000000, scale = 1, ao = null } = {}) {
    const key = [tex.uuid, z.toFixed(2), tint, mode, emissive, scale, ao ? ao.join(',') : ''].join('|');
    if (triCache.has(key)) return triCache.get(key);
    const m = new THREE.MeshLambertMaterial({ map: tex, color: tint, emissive });
    const rep = ppm(z) / tex.userData.w / scale;
    m.onBeforeCompile = (sh) => {
      sh.uniforms.uRep = { value: rep };
      sh.uniforms.uG = { value: FPX * GROUND_SQ / tex.userData.w };
      sh.uniforms.uAO = { value: new THREE.Vector2(ao ? ao[0] : -999, ao ? ao[1] : 999) };
      sh.vertexShader = sh.vertexShader
        .replace('#include <common>', '#include <common>\nvarying vec3 vWPos; varying vec3 vWNrm;')
        .replace('#include <begin_vertex>', '#include <begin_vertex>\nvWPos = (modelMatrix * vec4(transformed, 1.0)).xyz; vWNrm = normalize(mat3(modelMatrix) * objectNormal);');
      sh.fragmentShader = sh.fragmentShader
        .replace('#include <common>', '#include <common>\nvarying vec3 vWPos; varying vec3 vWNrm; uniform float uRep, uG; uniform vec2 uAO;')
        .replace('#include <map_fragment>', `
          vec3 an = abs(vWNrm);
          // 水平面：z 方向改用「螢幕列」取樣，抵銷透視壓縮（不然地磚會被壓成橫條）
          vec2 guv = vec2(vWPos.x * uRep, uG * (${CAM_Y.toFixed(1)} - vWPos.y) / (${CAM_Z.toFixed(1)} - vWPos.z));
          vec2 tuv = ${mode === 1 ? 'vWPos.xy * uRep' : mode === 2 ? 'vWPos.zy * uRep' : '(an.y > 0.6 ? guv : (an.x > an.z ? vWPos.zy : vWPos.xy) * uRep)'};
          vec4 sampledDiffuseColor = texture2D(map, tuv);
          diffuseColor *= sampledDiffuseColor;
          if (an.y < 0.6) { // 牆腳與屋簷下的接觸暗化（分階）
            float df = vWPos.y - uAO.x, de = uAO.y - vWPos.y;
            float k = 1.0;
            if (df < 0.9) k = 0.86; if (df < 0.4) k = 0.7;
            if (de > 0.0 && de < 1.0) k = min(k, 0.8); if (de > 0.0 && de < 0.45) k = min(k, 0.6);
            diffuseColor.rgb *= k; }`);
    };
    m.customProgramCacheKey = () => 'tri' + mode;
    triCache.set(key, m);
    return m;
  }
  // 像素元件（窗、門、角色…）：發光只取暖黃色的玻璃部分
  const sprCache = new Map();
  function sprMat(tex, emis = 0, dark = 0) {
    const key = tex.uuid + '|' + emis + '|' + dark;
    if (sprCache.has(key)) return sprCache.get(key);
    const m = new THREE.MeshLambertMaterial({ map: tex, alphaTest: 0.5 });
    m.onBeforeCompile = (sh) => {
      sh.uniforms.uEmis = { value: emis }; sh.uniforms.uDark = { value: dark };
      sh.fragmentShader = sh.fragmentShader
        .replace('#include <common>', '#include <common>\nuniform float uEmis, uDark;')
        .replace('#include <map_fragment>', `#include <map_fragment>
          { vec3 c = sampledDiffuseColor.rgb; float glow = smoothstep(0.16, 0.42, min(c.r, c.g) - c.b);
            // 沒開燈的窗：玻璃改成映著天色的暗藍紫
            diffuseColor.rgb = mix(diffuseColor.rgb, vec3(0.22, 0.14, 0.13) + dot(c, vec3(0.333)) * vec3(0.30, 0.19, 0.12), glow * uDark);
            totalEmissiveRadiance += c * glow * (uEmis + 0.22 * uDark); }`);
    };
    m.customProgramCacheKey = () => 'spr';
    sprCache.set(key, m);
    return m;
  }
  const depthFor = (tex) => new THREE.MeshDepthMaterial({ depthPacking: THREE.RGBADepthPacking, map: tex, alphaTest: 0.5 });

  // ---------- 小工具 ----------
  function box(w, h, d, mat, x, y, z, { cast = true, recv = true, parent = scene } = {}) {
    const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
    m.position.set(x, y + h / 2, z); m.castShadow = cast; m.receiveShadow = recv; parent.add(m);
    return m;
  }
  // 元件：底部中心在 (x, y)，大小依深度 1:1
  function sprite(name, x, y, z, { emis = 0, cast = true, scale = 1, parent = scene, flip = false, dark = 0 } = {}) {
    const tex = T[name], k = scale / ppm(z);
    const w = tex.userData.w * k, h = tex.userData.h * k;
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), sprMat(tex, emis, dark));
    m.position.set(x, y + h / 2, z); if (flip) m.scale.x = -1;
    if (flip) m.material = m.material.clone(), m.material.side = THREE.DoubleSide, m.material.onBeforeCompile = sprMat(tex, emis).onBeforeCompile;
    m.castShadow = cast; m.receiveShadow = true;
    if (cast) m.customDepthMaterial = depthFor(tex);
    parent.add(m);
    return m;
  }

  // ---------- 燈光 ----------
  const sun = new THREE.DirectionalLight(SUN_COL, 11);
  sun.position.copy(SUN_DIR).multiplyScalar(70).add(new THREE.Vector3(0, 0, 2));
  sun.target.position.set(0, 0, 2);
  sun.castShadow = true;
  Object.assign(sun.shadow.camera, { left: -40, right: 40, top: 30, bottom: -24, near: 5, far: 150 });
  sun.shadow.mapSize.set(4096, 4096); sun.shadow.bias = -0.0006; sun.shadow.normalBias = 0.04;
  scene.add(sun, sun.target);
  const hemi = new THREE.HemisphereLight(new THREE.Color(0.50, 0.52, 0.95), new THREE.Color(0.85, 0.5, 0.35), 0.40);
  scene.add(hemi);
  // 來自前上方的天空補光（有陰影：屋簷、窗台、遮雨棚下會暗一階）
  const fill = new THREE.DirectionalLight(new THREE.Color(0.62, 0.60, 0.95), 0.14);
  fill.position.set(8, 46, 34); fill.target.position.set(0, 0, -4);
  fill.castShadow = true;
  Object.assign(fill.shadow.camera, { left: -34, right: 34, top: 26, bottom: -22, near: 5, far: 120 });
  fill.shadow.mapSize.set(2048, 2048); fill.shadow.bias = -0.001; fill.shadow.normalBias = 0.05;
  scene.add(fill, fill.target);
  // 立面的暖色受光：來自前方左上、低角度的霞光反彈（有陰影，屋簷與窗台下仍會暗一階）
  fill.color.set(1.0, 0.66, 0.42); fill.intensity = 1.7; fill.position.set(-26, 30, 40);
  sun.shadow.camera.updateProjectionMatrix(); fill.shadow.camera.updateProjectionMatrix();
  scene.traverse((o) => { if (o.isLight) o.layers.enableAll(); });
  if (opts.sunonly) { hemi.intensity = 0.05; fill.intensity = 0; }
  const lamps = [];
  function pointLight(x, y, z, col, inten, dist) {
    const l = new THREE.PointLight(col, inten, dist, 1.8); l.position.set(x, y, z); l.layers.enableAll(); scene.add(l); lamps.push({ l, base: inten, ph: R() * 10 });
    return l;
  }

  // ---------- 地面、堤岸 ----------
  const reflU = { tRefl: { value: null }, uTexMat: { value: new THREE.Matrix4() }, uReflOn: { value: 1 } };
  const streetMat = tri(T.cobble, { z: 0, tint: 0xc8bcc4 }).clone();
  streetMat.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, reflU, { uRep: { value: ppm(0) / 64 }, uG: { value: FPX * GROUND_SQ / 64 }, uTime: U.time, tStreet: { value: T.street7 } });
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vWPos;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvWPos = (modelMatrix * vec4(transformed, 1.0)).xyz;');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', `#include <common>
        varying vec3 vWPos; uniform float uRep, uG, uReflOn, uTime; uniform sampler2D tRefl, tStreet; uniform mat4 uTexMat;
        float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
        float vn(vec2 p){ vec2 i = floor(p), f = fract(p); f = f*f*(3.0-2.0*f);
          return mix(mix(h21(i), h21(i+vec2(1,0)), f.x), mix(h21(i+vec2(0,1)), h21(i+vec2(1,1)), f.x), f.y); }`)
      .replace('#include <map_fragment>', `
        float grow = (${CAM_Y.toFixed(1)} - vWPos.y) / (${CAM_Z.toFixed(1)} - vWPos.z);
        vec4 sampledDiffuseColor = texture2D(map, vec2(vWPos.x * uRep, uG * grow));
        // 堤岸到人行道之間用這條街專屬的長貼圖（768×44，1 texel = 1 像素，縱向 = 螢幕列）
        float srow = grow * ${FPX.toFixed(1)} - 186.7; float spud = 0.0;
        if (vWPos.z > -2.3) { vec4 st = texture2D(tStreet, vec2((vWPos.x * ${ppm(0).toFixed(4)} + 384.0) / 768.0, 1.0 - clamp(srow, 0.5, 43.5) / 44.0));
          sampledDiffuseColor = vec4(st.rgb * 2.0, 1.0); spud = st.a; }
        diffuseColor *= sampledDiffuseColor;`)
      .replace('#include <opaque_fragment>', `
        { // 水窪形狀也在「螢幕列」空間算，才不會被壓成長條
          float pud = step(0.5, spud); float edge = 0.0;
          vec4 rc = uTexMat * vec4(vWPos, 1.0); vec2 ruv = rc.xy / rc.w;
          ruv.x += pud * sin(vWPos.z * 11.0 + uTime * 1.3) * 0.0010;
          vec3 refl = texture2D(tRefl, ruv).rgb;
          vec3 streak = vec3(0.0);
          for (int i = 1; i <= 6; i++) { float w = 1.0 - float(i) / 7.0;
            streak += max(texture2D(tRefl, ruv + vec2(0.0, float(i) / 360.0)).rgb - 0.9, 0.0) * w; }
          refl = min(refl, vec3(0.32)) * vec3(1.0, 0.74, 0.60) + streak * 0.35;
          float lum = dot(sampledDiffuseColor.rgb, vec3(0.33));
          float wet = (0.16 + 0.26 * smoothstep(0.2, 0.5, lum)) * (1.0 - pud) + pud * 0.72;
          outgoingLight *= 1.0 - 0.5 * pud - 0.25 * edge;
          outgoingLight = mix(outgoingLight, outgoingLight * (1.0 - wet) + refl * wet, uReflOn);
        }
        #include <opaque_fragment>`);
  };
  streetMat.customProgramCacheKey = () => 'street';
  const street = new THREE.Mesh(new THREE.PlaneGeometry(160, 42), streetMat);
  street.rotation.x = -Math.PI / 2; street.position.set(0, 0, -17.4); street.receiveShadow = true; scene.add(street);
  // 人行道
  box(160, 0.14, 1.3, tri(T.stone, { z: -2.5, tint: 0xd8cfd0 }), 0, 0, -2.9);
  // 堤岸：壓頂石＋石牆
  box(160, 0.2, 0.55, tri(T.stone, { z: 3.4, tint: 0xe6dcd4 }), 0, 0, 3.35);
  box(160, 0.045, 0.02, new THREE.MeshBasicMaterial({ color: new THREE.Color(0.30, 0.17, 0.08) }), 0, 0.16, 3.635, { cast: false, recv: false }); // 堤岸上緣的暖色邊緣光
  {
    const qm = new THREE.MeshLambertMaterial({ map: T.quay7, color: 0xffffff, emissive: new THREE.Color(0.20, 0.15, 0.17) }); // 一點自發光當作水面的反彈光，石塊才讀得出來
    qm.onBeforeCompile = (sh) => {
      sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vWPos;').replace('#include <begin_vertex>', '#include <begin_vertex>\nvWPos = (modelMatrix * vec4(transformed, 1.0)).xyz;');
      sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying vec3 vWPos;')
        .replace('#include <map_fragment>', `vec4 sampledDiffuseColor = texture2D(map, vec2((vWPos.x * ${ppm(3.6).toFixed(4)} + 384.0) / 768.0, clamp((vWPos.y - ${(WATER_Y - 1 / ppm(3.6)).toFixed(4)}) * ${ppm(3.6).toFixed(4)}, 0.5, 21.5) / 22.0));
          diffuseColor *= sampledDiffuseColor; totalEmissiveRadiance *= sampledDiffuseColor.rgb * 3.0;`);
    };
    box(160, 2.6, 0.5, qm, 0, -2.6, 3.35);
  }
  // 欄杆
  const iron = tri(T.iron, { z: 3.4 });
  for (let x = -21.6; x <= 22; x += 2.4) {
    if (x > 4.4 && x < 8.2) continue;
    box(0.34, 0.5, 0.34, tri(T.stone, { z: 3.4, tint: 0xd8cfd0 }), x, 0.2, 3.36);
    box(0.42, 0.1, 0.42, tri(T.stone, { z: 3.4, tint: 0xf0e6e0 }), x, 0.7, 3.36);
  }
  // 小碼頭＋階梯
  const plankQ = tri(T.planks, { z: 4.2, tint: 0xc8b8a8 });
  box(3.4, 0.14, 1.5, plankQ, 6.3, WATER_Y + 0.22, 4.4);
  for (const x of [4.75, 7.85]) box(0.16, 1.5, 0.16, tri(T.wood, { z: 5 }), x, WATER_Y - 0.5, 5.05);
  for (let i = 0; i < 2; i++) box(1.1, 0.24, 0.3, tri(T.stone, { z: 3.8, tint: 0xd0c8c8 }), 6.3, -0.24 - i * 0.24, 3.75 + i * 0.3);

  // ---------- 水面 ----------
  const waterU = { tRefl: { value: null }, tVol: { value: null }, uTexMat: { value: new THREE.Matrix4() }, uReflOn: { value: 1 } };
  const waterMat = new THREE.MeshLambertMaterial({ color: new THREE.Color(0.10, 0.16, 0.20) });
  waterMat.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, waterU, { uTime: U.time });
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vWPos;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvWPos = (modelMatrix * vec4(transformed, 1.0)).xyz;');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', `#include <common>
        varying vec3 vWPos; uniform float uReflOn, uTime; uniform sampler2D tRefl, tVol; uniform mat4 uTexMat;
        float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }`)
      .replace('#include <opaque_fragment>', `
        { vec4 rc = uTexMat * vec4(vWPos, 1.0); vec2 ruv = rc.xy / rc.w;
          float near = smoothstep(3.6, 10.0, vWPos.z);
          // 平滑小波紋：約 1 個低解析像素，越靠近鏡頭越強；倒影要讀得出房屋形狀
          ruv.x += sin(vWPos.z * 5.2 + uTime * 1.5 + vWPos.x * 0.6) * 0.6 / 640.0;
          vec3 refl = min(texture2D(tRefl, ruv).rgb, vec3(1.2));
          // 亮處（窗、街燈、串燈）的倒影拉成垂直長條：只看亮度、顏色統一偏暖
          vec3 streak = vec3(0.0);
          for (int i = 1; i <= 22; i++) { float w = 1.0 - float(i) / 23.0;
            streak += vec3(max(dot(texture2D(tRefl, ruv + vec2(0.0, float(i) / 360.0)).rgb, vec3(0.333)) - 1.5, 0.0) * w);
            streak += vec3(max(dot(texture2D(tRefl, ruv - vec2(0.0, float(i) / 360.0)).rgb, vec3(0.333)) - 1.5, 0.0) * w * 0.3); }
          streak *= vec3(1.25, 0.80, 0.34);
          // 長條被橫向波紋切成一段一段
          float cut = step(0.35, fract(vWPos.z * 2.6 + sin(vWPos.x * 1.7 + uTime * 0.8) * 0.25 - uTime * 0.12));
          float sunlit = smoothstep(0.02, 0.2, reflectedLight.directDiffuse.r);
          vec3 deep = vec3(0.006, 0.011, 0.026);
          // 暗而乾淨的水：一般倒影只留一點，越靠近鏡頭越暗
          float fres = mix(0.16, 0.03, near);
          vec3 col = deep + refl * fres + streak * 0.6 * (0.7 + 0.3 * cut) * mix(1.0, 0.6, near);
          vec2 suv = gl_FragCoord.xy / vec2(640.0, 360.0);
          float wl = ${((180 + HORIZON + FPX * (WATER_Y - CAM_Y) / (CAM_Z - 3.6)) / 360).toFixed(4)};
          col += texture2D(tVol, vec2(suv.x, wl + (wl - suv.y) * 1.6)).rgb * 0.3 * fres;
          // 橫向細碎波光
          vec2 cell = vec2(floor(vWPos.x * 3.0 + uTime * 0.4), floor(vWPos.z * 7.0));
          float n = h21(cell + floor(uTime * 1.2 + h21(cell) * 4.0) * 0.37);
          col += step(0.985, n) * streak * 0.5;                    // 少量波光：只出現在燈柱倒影附近
          col += vec3(0.10, 0.055, 0.025) * step(vWPos.z, 3.70);     // 水線的暖色邊緣光
          col *= 0.3 + 0.7 * smoothstep(3.72, 4.15, vWPos.z) + step(vWPos.z, 3.70);
          outgoingLight = mix(deep * 3.0, col, uReflOn); }
        #include <opaque_fragment>`);
  };
  const water = new THREE.Mesh(new THREE.PlaneGeometry(200, 60), waterMat);
  water.rotation.x = -Math.PI / 2; water.position.set(0, WATER_Y, 33.5); water.receiveShadow = true; scene.add(water);

  // ---------- 葉叢／草花：instanced 像素小片 ----------
  const foliageMeshes = [];
  function foliagePatch(m) {
    m.onBeforeCompile = (sh) => {
      sh.uniforms.uTime = U.time;
      sh.vertexShader = sh.vertexShader
        .replace('#include <common>', '#include <common>\nattribute vec3 aNrm; attribute vec4 aUv; attribute vec3 aSway; uniform float uTime;')
        .replace('#include <uv_vertex>', '#include <uv_vertex>\n#ifdef USE_MAP\n vMapUv = uv * aUv.zw + aUv.xy;\n#endif')
        .replace('#include <beginnormal_vertex>', 'vec3 objectNormal = aNrm;')
        .replace('#include <begin_vertex>', `#include <begin_vertex>
          { vec3 ip = instanceMatrix[3].xyz;
            // 由左往右傳遞的陣風：整片樹冠、草叢一起波動，再疊一點各自的小抖動
            float gust = sin(ip.x * 0.3 - uTime * 1.5) * 0.65 + sin(ip.x * 0.11 - uTime * 0.6 + ip.z * 0.2) * 0.35;
            float sw = gust + sin(uTime * 3.1 + aSway.z) * 0.22;
            float sc = length(instanceMatrix[0].xyz);
            transformed.x += sw * (aSway.x + aSway.y * uv.y) / sc;
            transformed.y += sin(ip.x * 0.3 - uTime * 1.5 + 1.3) * aSway.x * 0.35 / sc; }`);
    };
    m.customProgramCacheKey = () => 'foliage' + m.type;
    return m;
  }
  // items: [{p:[x,y,z], n:[..], size(px), cell:[u,v,su,sv], col:Color, sway:[whole, top]}]
  function billboards(tex, items, { layer = 0, cast = true, pxScale = 1 } = {}) {
    const geo = new THREE.PlaneGeometry(1, 1);
    const n = items.length;
    const aN = new Float32Array(n * 3), aUv = new Float32Array(n * 4), aS = new Float32Array(n * 3);
    const mat = foliagePatch(new THREE.MeshLambertMaterial({ map: tex, alphaTest: 0.5, side: THREE.DoubleSide }));
    const mesh = new THREE.InstancedMesh(geo, mat, n);
    const M = new THREE.Matrix4();
    items.forEach((it, i) => {
      const k = pxScale / ppm(it.p[2]);
      M.makeScale(it.size[0] * k, it.size[1] * k, 1).setPosition(it.p[0], it.p[1], it.p[2]);
      mesh.setMatrixAt(i, M); mesh.setColorAt(i, it.col);
      aN.set(it.n, i * 3); aUv.set(it.cell, i * 4); aS.set([it.sway[0], it.sway[1], R() * 20], i * 3);
    });
    geo.setAttribute('aNrm', new THREE.InstancedBufferAttribute(aN, 3));
    geo.setAttribute('aUv', new THREE.InstancedBufferAttribute(aUv, 4));
    geo.setAttribute('aSway', new THREE.InstancedBufferAttribute(aS, 3));
    mesh.castShadow = cast; mesh.receiveShadow = true; mesh.frustumCulled = false;
    if (cast) mesh.customDepthMaterial = foliagePatch(depthFor(tex));
    mesh.layers.set(layer);
    scene.add(mesh); foliageMeshes.push(mesh);
    return mesh;
  }
  const AUTUMN = [0xd8612a, 0xe88a2c, 0xf2b53a, 0xc23e28, 0xe07030, 0xb8a03c, 0x8c9a3c].map((c) => new THREE.Color(c));
  const GOLD = [0xf0b838, 0xf6cf52, 0xe89a30, 0xd8c048, 0xb0a840].map((c) => new THREE.Color(c));
  const GREEN = [0x4c8a3c, 0x5fa044, 0x3c7438, 0x78b04c, 0x2f6238].map((c) => new THREE.Color(c));
  const DARKGREEN = [0x2c5a38, 0x356a3c, 0x244c34, 0x3f7a40].map((c) => new THREE.Color(c));
  const pick = (a) => a[(R() * a.length) | 0];
  // 橢球葉叢
  // 樹冠分亮／中／暗三階：頂部與背光邊緣亮（透光），朝鏡頭的內側暗
  const TONE = [0.50, 0.82, 1.25];
  function canopyItems(blobs, pal, { size = 16, sway = 0.12, sil = false, flat = false, gold = false } = {}) {
    const items = [];
    const base = (R() * pal.length) | 0;
    for (const b of blobs) {
      for (let i = 0; i < b.n; i++) {
        let v;
        do { v = [rr(-1, 1), rr(-1, 1), rr(-1, 1)]; } while (v[0] * v[0] + v[1] * v[1] + v[2] * v[2] > 1);
        const len = Math.hypot(...v) || 1, fr = 0.5 + 0.5 * R(), f = fr / len;
        const nrm = new THREE.Vector3(v[0] / len, v[1] / len, v[2] / len);
        const p = [b.c[0] + v[0] * f * b.r[0], b.c[1] + v[1] * f * b.r[1], b.c[2] + v[2] * f * b.r[2]];
        const lv = nrm.y * 0.75 - nrm.x * 0.22 - nrm.z * 0.25 + rr(-0.12, 0.12);
        const rim = fr > 0.84 && Math.abs(nrm.z) < 0.55 && lv > -0.25;
        const level = flat ? (lv > 0.25 ? 2 : 1) : (lv > 0.42 || rim) ? 2 : lv > -0.18 ? 1 : 0;
        // 亮階朝向太陽（沒被擋住才會被照亮）、其他背向太陽 → 逆光樹冠只剩邊緣透光
        const n2 = sil ? new THREE.Vector3(0.2, -0.5, 0.8) : nrm.clone().multiplyScalar(0.35).addScaledVector(SUN_DIR, level === 2 ? 1 : -0.35).normalize();
        const cell = (R() * 4) | 0;
        const col = pal[(base + (R() < 0.28 ? 1 : 0) + (level === 2 && R() < 0.5 ? 2 : 0)) % pal.length].clone().multiplyScalar(TONE[level]);
        if (gold && rim) col.set(0xffc850).multiplyScalar(1.5);
        if (sil) col.multiply(new THREE.Color(0.26, 0.15, 0.20));
        items.push({ p, n: [n2.x, n2.y, n2.z], size: [size, size], cell: [(cell % 2) * 0.5, (cell >> 1) * 0.5, 0.5, 0.5], col, sway: [sway * rr(0.7, 1.2), 0] });
      }
    }
    return items;
  }
  const barkM = (z) => tri(T.bark, { z });
  function tree(x, z, { h = 3.2, r = 0.32, blobs, pal = AUTUMN, n = 1, gold = false, cast = true } = {}) {
    const trunk = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.6, r, h, 6), barkM(z));
    trunk.position.set(x, h / 2, z); trunk.castShadow = true; trunk.receiveShadow = true; scene.add(trunk);
    const B = blobs.map((b) => ({ c: [x + b[0], h + b[1], z + b[2]], r: [b[3], b[4], b[5]], n: Math.round(b[6] * n) }));
    // 枝幹
    blobs.slice(1).forEach((b) => {
      const from = new THREE.Vector3(x, h * 0.86, z), to = new THREE.Vector3(x + b[0], h + b[1] - b[4] * 0.3, z + b[2]);
      const len = from.distanceTo(to);
      const br = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.22, r * 0.4, len, 5), barkM(z));
      br.position.copy(from).lerp(to, 0.5); br.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), to.clone().sub(from).normalize());
      br.castShadow = true; scene.add(br);
    });
    const its = canopyItems(B, pal, { gold });
    if (z < -10.5) its.forEach((i) => i.col.multiplyScalar(z < -20 ? 0.3 : 0.32)); // 後排的樹退成暗剪影
    billboards(T.leaf, its, { cast });
  }

  // ---------- 房屋 ----------
  const lightsOn = [];
  function house(o) {
    const { x0, x1, zf, d = 5.5, h, rh, wall, tint = 0xffffff, roof = 'eave', roofTex = T.rooftile, roofTint = 0xffffff } = o;
    const w = x1 - x0, cx = (x0 + x1) / 2, zc = zf - d / 2;
    const wm = tri(wall, { z: zf, tint, ao: [0, h] });
    box(w, h, d, wm, cx, 0, zc);
    // 基座
    box(w + 0.12, 0.55, d + 0.12, tri(T.stone, { z: zf, tint: 0xb4aab0 }), cx, 0, zc);
    if (o.ground) box(w + 0.06, o.ground.h, d + 0.06, tri(o.ground.tex, { z: zf, tint: o.ground.tint ?? 0xffffff, ao: [0, 999] }), cx, 0, zc);
    if (o.band !== false) box(w + 0.16, 0.14, d + 0.16, tri(T.wood, { z: zf, tint: o.bandTint ?? 0xffffff }), cx, (o.ground?.h ?? 2.95), zc);
    const rm = (mode) => tri(roofTex, { z: zf, tint: roofTint, mode });
    const edge = tri(T.wood, { z: zf, tint: 0x8a7468 });
    if (roof === 'eave') {
      // 屋脊沿 x：前後兩個斜面
      const run = d / 2 + 0.45, L = Math.hypot(run, rh * (run / (d / 2))), ang = Math.atan2(rh, d / 2);
      for (const s of [1, -1]) {
        const m = new THREE.Mesh(new THREE.BoxGeometry(w + 0.7, 0.16, L), rm(1));
        m.rotation.x = s * ang; m.position.set(cx, h + rh / 2 - (0.45 * rh / (d / 2)) / 2 + 0.06, zc + s * run / 2);
        m.castShadow = true; m.receiveShadow = true; scene.add(m);
      }
      box(w + 0.74, 0.16, 0.22, tri(T.white, { z: zf, tint: 0xe8c8a0 }), cx, h + rh + 0.02, zc);     // 屋脊（淺色，吃得到背光）
      box(w + 0.74, 0.12, 0.12, edge, cx, h - 0.45 * rh / (d / 2) + 0.02, zf + 0.46); // 檐口
      // 山牆（兩側三角）
      for (const sx of [x0, x1]) {
        const g = new THREE.BufferGeometry();
        g.setAttribute('position', new THREE.Float32BufferAttribute([sx, h, zf, sx, h, zf - d, sx, h + rh, zc], 3));
        g.setIndex(sx === x0 ? [0, 2, 1] : [0, 1, 2]); g.computeVertexNormals();
        const m = new THREE.Mesh(g, tri(wall, { z: zf, tint, mode: 2 })); m.material.side = THREE.DoubleSide; m.castShadow = true; scene.add(m);
      }
    } else {
      // 屋脊沿 z：正面看到三角山牆
      const run = w / 2 + 0.45, ang = Math.atan2(rh, w / 2), L = run / Math.cos(ang);
      for (const s of [1, -1]) {
        const m = new THREE.Mesh(new THREE.BoxGeometry(L, 0.16, d + 0.8), rm(2));
        m.rotation.z = -s * ang; m.position.set(cx + s * run / 2, h + rh / 2 - (0.45 * Math.tan(ang)) / 2 + 0.06, zc);
        m.castShadow = true; m.receiveShadow = true; scene.add(m);
        // 正面的封簷板
        const bm = new THREE.Mesh(new THREE.BoxGeometry(L, 0.26, 0.1), edge);
        bm.rotation.z = -s * ang; bm.position.set(cx + s * run / 2, h + rh / 2 - (0.45 * Math.tan(ang)) / 2 + 0.02, zf + 0.42);
        bm.castShadow = true; scene.add(bm);
      }
      const g = new THREE.BufferGeometry();
      const pos = [];
      for (const zz of [zf, zf - d]) pos.push(x0, h, zz, x1, h, zz, cx, h + rh, zz);
      g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
      g.setIndex([0, 1, 2, 3, 5, 4]); g.computeVertexNormals();
      const m = new THREE.Mesh(g, wm); m.castShadow = true; m.receiveShadow = true; scene.add(m);
    }
    // 半木構造的樑
    if (o.timber) {
      const tm = tri(T.wood, { z: zf, tint: o.timber === true ? 0xffffff : o.timber });
      const zb = zf + 0.05, y0 = o.ground?.h ?? 0.55;
      for (const y of o.timberRows ?? [h - 0.16]) box(w + 0.04, 0.2, 0.1, tm, cx, y, zb);
      for (const xx of o.timberCols ?? [0.1, w / 2, w - 0.1]) box(0.2, h - y0, 0.1, tm, x0 + xx, y0, zb);
      for (const [xa, ya, xb, yb] of o.braces ?? []) {
        const len = Math.hypot(xb - xa, yb - ya);
        const b = new THREE.Mesh(new THREE.BoxGeometry(len, 0.16, 0.08), tm);
        b.position.set(x0 + (xa + xb) / 2, (ya + yb) / 2, zb); b.rotation.z = Math.atan2(yb - ya, xb - xa); scene.add(b);
      }
    }
    // 窗與門
    for (const it of o.items ?? []) {
      const [name, x, y, emis = 0] = it;
      const s = sprite(name, x0 + x, y, zf + (name.startsWith('door') ? 0.07 : 0.09), { emis, cast: false, dark: emis <= 0 ? 1 : emis < 1 ? 0.55 : 0 });
      if (emis > 0) lightsOn.push({ mesh: s, x: x0 + x, y: y + 1, z: zf });
    }
    // 煙囪
    for (const [x, zz, ch] of o.chimneys ?? []) {
      box(0.7, ch, 0.7, tri(T.brick, { z: zf, tint: 0xd8c8c0 }), x0 + x, h + 0.4, zc + zz);
      box(0.86, 0.14, 0.86, tri(T.stone, { z: zf }), x0 + x, h + 0.4 + ch, zc + zz);
      if (o.smoke !== false) smokeSrc.push([x0 + x, h + 0.6 + ch, zc + zz]);
    }
    // 老虎窗：小山牆（三角牆面＋兩片斜屋頂＋深色封簷板），每個窗樣式不同
    (o.dormers ?? []).forEach((x, di) => {
      const dz = zf - 0.9, dy = h + 0.35, cxd = x0 + x, top = dy + 1.15;
      box(1.3, 1.15, 1.4, wm, cxd, dy, dz);
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.Float32BufferAttribute([cxd - 0.65, top, dz + 0.7, cxd + 0.65, top, dz + 0.7, cxd, top + 0.6, dz + 0.7], 3));
      g.setIndex([0, 1, 2]); g.computeVertexNormals();
      const tm = new THREE.Mesh(g, tri(wall, { z: zf, tint })); tm.castShadow = true; scene.add(tm);
      const ang = Math.atan2(0.6, 0.65), L = Math.hypot(0.85, 0.78);
      for (const sgn of [1, -1]) {
        const m = new THREE.Mesh(new THREE.BoxGeometry(L, 0.1, 1.7), rm(2));
        m.rotation.z = -sgn * ang; m.position.set(cxd + sgn * 0.42, top + 0.26, dz + 0.02); m.castShadow = true; scene.add(m);
        const bd = new THREE.Mesh(new THREE.BoxGeometry(L, 0.2, 0.08), edge);
        bd.rotation.z = -sgn * ang; bd.position.set(cxd + sgn * 0.42, top + 0.24, dz + 0.86); scene.add(bd);
      }
      const wn = (o.dormerWins ?? [])[di] ?? 'win_d', lit = wn === 'win_box';
      sprite(T[wn] ? wn : 'win_d', cxd, dy + 0.1, dz + 0.72, { emis: lit ? 1.6 : 0, cast: false, dark: lit ? 0 : 1 });
    });
    // 遮雨棚
    for (const [x, y, aw, tex = T.awning] of o.awnings ?? []) {
      const m = new THREE.Mesh(new THREE.BoxGeometry(aw, 0.06, 1.25), tri(tex, { z: zf + 0.6, mode: 1 }));
      m.rotation.x = 0.5; m.position.set(x0 + x, y, zf + 0.58); m.castShadow = true; m.receiveShadow = true; scene.add(m);
      box(aw, 0.22, 0.05, tri(tex, { z: zf + 1.1, mode: 1 }), x0 + x, y - 0.5, zf + 1.13);
    }
  }
  const smokeSrc = [];

  const Z1 = -3.5;
  // H1 奶油色灰泥、陶瓦
  house({ x0: -18.2, x1: -11.8, zf: Z1, d: 6, h: 5.7, rh: 2.6, wall: T.plaster, tint: 0xf4e6cf, roof: 'eave',
    items: [['door_a', 1.5, 0.14, 0], ['win_a', 4.3, 1.0, 2.4], ['win_b2', 1.7, 3.6, 0], ['win_b', 4.6, 3.6, 0]],
    chimneys: [[1.4, -0.8, 2.4]], dormers: [3.4] });
  // H2 半木構造、山牆朝前
  house({ x0: -11.6, x1: -6.2, zf: Z1 - 0.3, d: 4.6, h: 6.0, rh: 3.3, wall: T.plaster, tint: 0xf8f0e2, roof: 'gable', roofTex: T.slate,
    ground: { tex: T.brick, h: 3.0, tint: 0xe8d8d0 }, timber: true, timberRows: [3.0, 5.84], timberCols: [0.1, 2.7, 5.3],
    braces: [[0.2, 3.2, 1.3, 5.8], [5.2, 3.2, 4.1, 5.8], [2.7, 6.3, 1.2, 6.2], [2.7, 6.3, 4.2, 6.2], [2.7, 6.1, 2.7, 9.0]],
    items: [['door_b', 1.5, 0.14, 0.3], ['win_e', 4.0, 0.9, 0], ['win_a2', 1.45, 3.45, 0], ['win_a', 3.95, 3.45, 2.4], ['win_d', 2.7, 7.0, 0]] });
  // H3 麵包店：磚造一樓、鵝黃二樓、石板瓦＋老虎窗
  house({ x0: 0.6, x1: 7.8, zf: Z1, d: 5.6, h: 5.9, rh: 2.7, wall: T.plaster, tint: 0xf6dca4, roof: 'eave', roofTex: T.slate,
    ground: { tex: T.brick, h: 3.0 },
    items: [['win_c', 2.5, 0.75, 3.0], ['door_open', 5.6, 0.14, 3.2], ['win_b', 1.4, 3.75, 2.2], ['win_b2', 3.6, 3.75, 0], ['win_e', 5.8, 3.45, 0]],
    chimneys: [[5.9, -0.6, 2.2]], dormers: [1.9, 5.0], dormerWins: ['win_box', 'win_shut'], awnings: [[2.5, 3.2, 3.5]] });
  // H4 高窄的玫瑰色屋、山牆朝前
  house({ x0: 8.0, x1: 12.6, zf: Z1 - 0.2, d: 5.4, h: 7.5, rh: 2.9, wall: T.plaster, tint: 0xf0c4b4, roof: 'gable', roofTex: T.rooftile,
    ground: { tex: T.stone, h: 2.9, tint: 0xd8ccc8 }, timber: 0xffffff, timberRows: [2.9, 5.2, 7.36], timberCols: [0.1, 4.5],
    items: [['door_a', 1.35, 0.14, 0], ['win_e', 3.4, 0.9, 0], ['win_a3', 1.3, 3.15, 0], ['win_a', 3.35, 3.15, 2.4], ['win_b2', 2.3, 5.5, 0], ['win_d', 2.3, 8.1, 0]],
    chimneys: [[3.6, -1.2, 1.6]] });
  // H5 紅磚屋
  house({ x0: 15.0, x1: 22, zf: Z1, d: 6, h: 5.3, rh: 2.5, wall: T.brick, tint: 0xf0e0d8, roof: 'eave', roofTex: T.rooftile, roofTint: 0xe8d8d0,
    ground: { tex: T.stone, h: 0.9, tint: 0xc8c0c0 }, band: false,
    items: [['win_e', 1.3, 1.0, 0], ['door_a', 3.5, 0.14, 0], ['win_a2', 1.6, 3.0, 0.3], ['win_b', 4.4, 3.2, 0]], chimneys: [[2.0, 0.4, 2.0]], awnings: [] });

  // 後排（較簡單）
  const Z2 = -15;
  house({ x0: -27, x1: -19, zf: Z2, d: 6, h: 5.6, rh: 2.6, wall: T.plaster, tint: 0xe8d0b8, roof: 'eave', roofTex: T.slate, band: false, items: [['win_b', 2, 3.2, 0], ['win_b', 5.6, 3.2, 0]], chimneys: [[5, 0, 2]], smoke: false });
  house({ x0: -17.5, x1: -10.5, zf: Z2 - 1, d: 5, h: 4.6, rh: 2.4, wall: T.brick, tint: 0xe0d0c8, roof: 'eave', band: false, items: [['win_b', 2, 2.4, 0], ['win_b', 5, 2.4, 0.3]], smoke: false });
  house({ x0: -9.5, x1: -1.5, zf: Z2 - 1, d: 5, h: 4.3, rh: 2.1, wall: T.plaster, tint: 0xf2dcc0, roof: 'eave', band: false,
    items: [['win_a', 1.6, 0.8, 0], ['door_a', 4, 0.1, 0], ['win_a', 6.4, 0.8, 2.2]], chimneys: [[6.2, 0, 2]] });
  house({ x0: 9.5, x1: 17.5, zf: Z2, d: 6, h: 9.2, rh: 3, wall: T.plaster, tint: 0xe0c8c0, roof: 'eave', roofTex: T.slate, band: false, items: [['win_b', 2, 7.2, 1.4], ['win_b', 6, 7.2, 0]], chimneys: [[2, 0, 2.2]], smoke: false });
  house({ x0: 19, x1: 28, zf: Z2 - 1, d: 6, h: 8, rh: 3, wall: T.brick, tint: 0xd8c8c8, roof: 'eave', band: false, items: [['win_b', 2.4, 6, 0]], smoke: false });
  // 鐘樓
  {
    const tz = -19, tx = 4.6, sm = tri(T.stone, { z: tz + 2, tint: 0xd8cccc });
    box(4, 8.6, 4, sm, tx, 0, tz);
    box(4.5, 0.3, 4.5, tri(T.stone, { z: tz + 2, tint: 0xf0e4e0 }), tx, 8.6, tz);
    box(4.4, 0.25, 4.4, tri(T.stone, { z: tz + 2, tint: 0xf0e4e0 }), tx, 6.6, tz);
    const spire = new THREE.Mesh(new THREE.ConeGeometry(3.3, 4.2, 4), tri(T.slate, { z: tz + 2, mode: 1 }));
    spire.rotation.y = Math.PI / 4; spire.position.set(tx, 8.9 + 2.1, tz); spire.castShadow = true; scene.add(spire);
    sprite('win_d', tx, 7.2, tz + 2.06, { emis: 2.4, cast: false });
  }

  // ---------- 公園缺口 ----------
  const lawn = box(6.3, 0.1, 9.5, tri(T.lawn, { z: -5 }), -2.8, 0, -7.6);
  box(6.5, 0.3, 0.3, tri(T.stone, { z: -3.4, tint: 0xd8d0d0 }), -2.8, 0, -3.0); // 緣石
  box(6.3, 1.0, 0.4, tri(T.stone, { z: -12, tint: 0xb8b0b4 }), -2.8, 0, -12.2); // 後方矮牆
  // 大樹（光束的源頭）：codex 畫的葉團疊成樹冠，團與團之間留空隙讓光漏下來
  {
    const tx = -4.7, tz = -9.5;
    tree(tx, tz, { h: 4.6, r: 0.46, pal: AUTUMN, gold: true, blobs: [[0, 4.2, 0, 0.9, 0.7, 0.8, 10], [-3.0, 0.9, 0.2, 0.8, 0.6, 0.8, 8], [2.0, 0.2, 0.2, 0.8, 0.6, 0.8, 8], [2.2, 3.1, 0, 0.7, 0.5, 0.7, 6]] });
    const cl = [ // x, y, z 偏移, 大小倍數, 明暗
      [-3.1, 5.6, 0.0, 1.0, 0.95], [2.0, 4.9, 0.3, 1.0, 0.75], [-0.2, 9.0, -0.3, 1.0, 1.25], [2.3, 7.9, -0.1, 0.8, 1.05], [-2.3, 8.6, -0.5, 0.75, 1.3], [1.7, 6.5, 0.9, 0.55, 0.55],
    ].map(([dx, y, dz, k, tone]) => ({ p: [tx + dx, y, tz + dz], n: [0.15, 0.55, 0.8], size: [48 * k, 48 * k], cell: [0, 0, 1, 1], col: new THREE.Color(1, 1, 1).multiplyScalar(tone * 1.15), sway: [0.10, 0] }));
    billboards(T.clump, cl);
    for (const c of cl) { // 每個葉團都有枝幹接回樹幹，樹冠不再浮在空中
      const from = new THREE.Vector3(tx, 4.2, tz), to = new THREE.Vector3(c.p[0], c.p[1] - 0.2, c.p[2]);
      const br = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.2, from.distanceTo(to), 5), barkM(tz));
      br.position.copy(from).lerp(to, 0.5); br.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), to.clone().sub(from).normalize()); br.castShadow = true; scene.add(br); }
  }
  sprite('bench', -0.4, 0.1, -5.2);
  box(1.9, 0.05, 9.0, tri(T.cobble, { z: -5, tint: 0xd8c4a8 }), -2.0, 0.1, -7.7); // 往公園深處的小徑
  // 後方的樹
  tree(-13.5, -11.5, { h: 3.0, pal: GOLD, blobs: [[0, 2.0, 0, 2.2, 2.3, 1.8, 110], [1.2, 0.9, 0, 1.5, 1.3, 1.3, 50]] });
  tree(0.6, -17.5, { h: 3.6, pal: AUTUMN, cast: false, blobs: [[0, 2.0, 0, 2.3, 2.9, 1.6, 130], [-1.2, 0.4, 0, 1.3, 1.2, 1.2, 40]] }); // 擋住後排房子之間那塊天空
  tree(4.0, -13.2, { h: 2.6, pal: GREEN, blobs: [[0, 1.9, 0, 1.7, 2.6, 1.5, 100]] });
  tree(7.6, -12.4, { h: 3.0, pal: AUTUMN, blobs: [[0, 2.4, 0, 2.2, 2.6, 1.7, 120], [-1.3, 1.0, 0, 1.4, 1.2, 1.2, 40]] });
  tree(20, -11, { h: 3.0, pal: GOLD, blobs: [[0, 2.4, 0, 2.4, 2.6, 1.7, 110]] });
  tree(-21, -24, { h: 4, pal: AUTUMN, blobs: [[0, 3, 0, 2.4, 4.4, 2, 120]] });
  tree(-12.5, -25, { h: 4, pal: GOLD, blobs: [[0, 3, 0, 2.6, 4.2, 2, 120]] });
  tree(13, -26, { h: 4, pal: AUTUMN, blobs: [[0, 4, 0, 3.4, 4.2, 2, 150]] });
  tree(30, -22, { h: 4, pal: AUTUMN, blobs: [[0, 3, 0, 3, 3.6, 2, 120]] });
  // 堤邊的小樹（中前景）
  tree(-9.4, 2.3, { h: 2.5, r: 0.2, pal: GOLD, blobs: [[0, 1.5, 0, 1.6, 1.4, 1.2, 80], [0.9, 0.7, 0.2, 1.0, 0.9, 0.9, 30]] });
  box(1.5, 0.22, 1.5, tri(T.stone, { z: 2.3, tint: 0xd8d0d0 }), -9.4, 0, 2.3);
  // 右緣收邊：一棵立在樹穴裡、有樹幹的樹（在街道這一層，跟左邊那棵呼應）
  tree(12.55, 2.3, { h: 3.5, r: 0.24, pal: AUTUMN, blobs: [[0, 2.1, 0, 1.5, 1.6, 1.1, 95], [-0.9, 0.7, 0.2, 1.0, 0.9, 0.9, 34], [0.8, 3.3, 0, 1.0, 0.9, 0.9, 30]] });
  box(1.4, 0.22, 1.4, tri(T.stone, { z: 2.3, tint: 0xd8d0d0 }), 12.55, 0, 2.3);

  // 草與花
  {
    const items = [];
    // 10 種 codex 畫的草叢與花（圖集 plants7：5 種草、5 種花）
    const PN = meta.plants7_cells[0], PW = meta.plants7_cells[1], PH = meta.plants7_cells[2];
    const remap = (c) => (c <= 1 ? (R() * 5) | 0 : c === 6 ? (R() < 0.6 ? 1 : 3) : ({ 2: 9, 3: 6, 4: 8, 5: 5, 7: 7 })[c]);
    const plant = (x, y, z, cell, sway = 0.0) => { const c = remap(cell); if (cell <= 1 && R() < 0.3) return;
      if (Math.abs(x + 3.25) < 1.3 && z > -2.4 && z < 3.2) return; // 主角腳邊留空
      items.push({ p: [x, y + PH / 2 / ppm(z), z], n: [SUN_DIR.x * 0.6, 0.8, 0.3], size: [PW, PH], cell: [c / PN, 0, 1 / PN, 1], col: new THREE.Color(1, 1, 1).multiplyScalar(rr(0.85, 1.1)), sway: [0, 0.16 + sway] }); };
    // 公園草地
    for (let i = 0; i < 520; i++) {
      const x = rr(-5.9, 0.3), z = rr(-11.8, -3.3);
      if (Math.abs(x + 2.0) < 1.05) continue; // 小徑
      const c = R() < 0.74 ? (R() * 2) | 0 : [2, 3, 4, 5, 7][(R() * 5) | 0];
      plant(x, 0.1, z, c);
    }
    // 緣石前、牆腳的花叢
    for (let i = 0; i < 46; i++) plant(rr(-5.8, 0.2), 0.1, rr(-3.6, -3.25), [2, 3, 4, 5, 7, 0][(R() * 6) | 0]);
    for (const [a, b, z] of [[-18, -12, -3.38], [8.2, 12.4, -3.58], [15.2, 21, -3.38], [-11.4, -6.4, -3.68]]) for (let x = a; x < b; x += rr(0.25, 0.9)) if (R() < 0.5) plant(x, 0.14, z, [0, 1, 0, 3, 4, 2][(R() * 6) | 0]);
    // 堤邊樹穴
    for (let i = 0; i < 22; i++) plant(-9.4 + rr(-0.7, 0.7), 0.22, 2.3 + rr(-0.6, 0.7), [0, 1, 4, 5, 2][(R() * 5) | 0]);
    // 石縫雜草
    for (let i = 0; i < 26; i++) plant(rr(-18, 18), 0, R() < 0.5 ? rr(-2.2, -1.6) : rr(2.6, 3.05), (R() * 2) | 0);
    // 堤岸水邊蘆葦
    for (let i = 0; i < 60; i++) { const x = R() < 0.5 ? rr(-17, -10) : rr(9.5, 18); plant(x, WATER_Y, rr(3.7, 4.3), R() < 0.8 ? 6 : 0, 0.05); }
    // 碼頭邊花盆
    billboards(T.plants7, items, { cast: false });
  }
  // 牆上的常春藤
  {
    const B = [
      { c: [-17.6, 3.2, Z1 + 0.1], r: [1.5, 3.2, 0.12], n: 130 }, { c: [-16.4, 5.3, Z1 + 0.1], r: [2.2, 0.8, 0.12], n: 70 },
      { c: [12.5, 3.6, Z1 - 0.1], r: [0.5, 3.6, 0.12], n: 60 },
      { c: [-2.8, 0.9, -12.0], r: [3.2, 0.7, 0.2], n: 80 },
    ];
    const it = canopyItems(B, GREEN, { size: 16, sway: 0.03, flat: true });
    it.forEach((i) => { i.size = [12, 12]; });
    billboards(T.leaf, it, { cast: false });
    // 灌木
    const bush = canopyItems([
      { c: [-5.5, 0.7, -6.4], r: [0.6, 0.7, 0.9], n: 30 }, { c: [0.0, 0.6, -6.2], r: [0.5, 0.6, 0.7], n: 22 }, { c: [-4.6, 0.7, -10.6], r: [1.2, 0.8, 0.8], n: 36 }, { c: [-0.6, 0.8, -10.8], r: [1.0, 0.9, 0.8], n: 36 },
      { c: [14.4, 0.7, -5.6], r: [0.6, 0.7, 0.6], n: 24 },
    ], DARKGREEN, { size: 16, sway: 0.05 });
    bush.forEach((i) => { i.size = [12, 12]; });
    billboards(T.leaf, bush);
  }

  // ---------- 街燈、串燈、招牌、雜物 ----------
  const lampMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(3.4, 2.1, 0.8) });
  const glowObjs = [];
  const lampDim = new THREE.MeshBasicMaterial({ color: new THREE.Color(0.9, 0.6, 0.3) });
  function lamp(x, z, k = 1) {
    box(0.26, 0.5, 0.26, iron, x, 0.2, z); box(0.1, 3.3, 0.1, iron, x, 0.2, z);
    box(0.5, 0.07, 0.3, iron, x, 3.5, z);
    box(0.36, 0.08, 0.36, iron, x, 3.34, z, { cast: false });
    const g = box(0.26, 0.34, 0.26, k < 1 ? lampDim : lampMat, x, 2.98, z, { cast: false, recv: false }); glowObjs.push(g);
    box(0.4, 0.06, 0.4, iron, x, 2.92, z, { cast: false });
    pointLight(x, 3.0, z + 0.2, new THREE.Color(1.0, 0.56, 0.22), 15 * k, 12);
  }
  lamp(-6.4, 2.75); lamp(3.6, 2.75); lamp(-15.2, 2.75, 0.3);
  // 串燈：H2 屋角 → 樹 → H3 屋角
  {
    const pts = [[-6.2, 5.2, Z1 - 0.1], [0.6, 5.4, Z1 + 0.15]], pts2 = [[0.6, 5.4, Z1 + 0.15], [3.6, 3.56, 2.75]];
    const cols = [new THREE.Color(3.2, 1.9, 0.6), new THREE.Color(3.0, 0.9, 0.5), new THREE.Color(1.4, 2.4, 1.6), new THREE.Color(3.2, 2.4, 1.0)];
    const wire = tri(T.iron, { z: 0 });
    for (const [a, b] of [pts, pts2]) {
      const A = new THREE.Vector3(...a), B = new THREE.Vector3(...b), N = 14;
      let prev = A.clone();
      for (let i = 1; i <= N; i++) {
        const t = i / N, p = A.clone().lerp(B, t); p.y -= Math.sin(t * Math.PI) * 0.9;
        const seg = new THREE.Mesh(new THREE.BoxGeometry(0.035, prev.distanceTo(p), 0.035), wire);
        seg.position.copy(prev).lerp(p, 0.5); seg.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), p.clone().sub(prev).normalize()); scene.add(seg);
        if (opts.flags && i < N && a === pts[0]) { // 三角旗：在光束裡投下一條條影子
          const fl = new THREE.Mesh(new THREE.BoxGeometry(0.42, 0.62, 0.03), new THREE.MeshLambertMaterial({ color: [0xc8483c, 0xe8c070, 0x3c7c84, 0xe8e0d0][i % 4] }));
          fl.position.copy(prev).lerp(p, 0.5).y -= 0.45; fl.castShadow = true; scene.add(fl); }
        if (i < N) { const bm = new THREE.Mesh(new THREE.BoxGeometry(0.17, 0.2, 0.17), new THREE.MeshBasicMaterial({ color: cols[i % 4] })); bm.position.copy(p).y -= 0.12; scene.add(bm); glowObjs.push(bm); }
        prev = p;
      }
    }
  }
  sprite('sign', 0.6 - 0.78, 3.3, Z1 + 0.45, { flip: true });
  sprite('props', 7.2, 0.14, -2.75);
  const baker = sprite('baker', 5.2, 0.14, -2.5);
  // 牆面：剝落露磚（每棟不同）、垂掛的藤蔓；堤岸上緣的藤蔓
  const hang = (name, x, top, z) => { const m = sprite(name, x, top - T[name].userData.h / ppm(z), z, { cast: false });
    if (z > 3) m.material = new THREE.MeshLambertMaterial({ map: T[name], alphaTest: 0.5, emissive: new THREE.Color(0.5, 0.5, 0.36), emissiveMap: T[name] }); return m; };
  for (const [n, x, y, z] of [['patches_2', -13.1, 0.75, Z1], ['patches_0', -16.6, 2.5, Z1], ['patches_3', -7.5, 4.7, Z1 - 0.3], ['patches_1', 7.25, 3.4, Z1], ['patches_0', 9.1, 4.5, Z1 - 0.2], ['patches_3', 11.9, 6.2, Z1 - 0.2], ['patches_1', 15.6, 2.2, Z1], ['patches_2', -17.6, 4.3, Z1]])
    sprite(n, x, y, z + 0.04, { cast: false });
  for (const [n, x, top, z] of [['vines_3', -11.9, 5.6, Z1 + 0.06], ['vines_1', -6.45, 5.9, Z1 - 0.24], ['vines_2', 7.6, 5.8, Z1 + 0.06], ['vines_0', 12.4, 2.8, Z1 - 0.14]]) hang(n, x, top, z);
  for (const [n, x] of [['vines_3', -13.6], ['vines_0', -10.2], ['vines_2', -6.3], ['vines_1', -4.4], ['vines_0', -0.6], ['vines_3', 1.6], ['vines_1', 3.9], ['vines_2', 9.4], ['vines_0', 12.2], ['vines_3', 14.6]]) hang(n, x, 0.06, 3.63);
  // 生活道具
  for (const [n, x, y, z, cast] of [['props7_0', -12.3, 0.14, -2.7, 1], ['props7_1', -7.3, 0.14, -2.75, 1], ['props7_2', -6.55, 0.14, -3.2, 1], ['props7_3', 10.7, 1.0, Z1 - 0.14, 0], ['props7_4', 11.9, 0.14, -2.85, 1], ['props7_5', 1.05, 0.14, -2.8, 1], ['cart', 9.7, 0.0, -1.2, 1], ['props7_0', 16.3, 0.14, -2.7, 1]])
    if (T[n]) sprite(n, x, y, z, { cast: !!cast });
  pointLight(6.4, 1.3, Z1 + 1.4, new THREE.Color(1.0, 0.66, 0.30), 9, 5);  // 打開的店門在地上投出的光
  const fisher = sprite('fisher', 5.6, WATER_Y + 0.36, 4.85);
  pointLight(5.0, WATER_Y + 1.6, 6.2, new THREE.Color(1.0, 0.72, 0.45), 4, 4);
  sprite('cat', 3.0, 0.2, 3.1, { cast: true });
  pointLight(3.1, 1.9, Z1 + 1.3, new THREE.Color(1.0, 0.62, 0.26), 16, 9);   // 麵包店櫥窗
  pointLight(-10.0, 1.6, Z1 + 1.0, new THREE.Color(1.0, 0.62, 0.26), 1.5, 7);
  pointLight(-13.9, 2.0, Z1 + 1.0, new THREE.Color(1.0, 0.62, 0.26), 6, 7);
  pointLight(9.4, 4.2, Z1 + 0.9, new THREE.Color(1.0, 0.62, 0.26), 6, 7);
  // 船
  const boat = sprite('boat', 9.9, WATER_Y - 0.22, 4.9, { emis: 2.6 });
  pointLight(8.2, WATER_Y + 0.9, 5.6, new THREE.Color(1.0, 0.6, 0.25), 10, 7);

  // ---------- 角色 ----------
  const HX = -3.25, HZ = 0.9;
  // 主角腳下的光池：順著太陽方向打下來的窄聚光（即時燈光），落點就是光束的落點
  const POOL = new THREE.Vector3(HX + 0.25, 0, HZ + 0.25);
  { const sp = new THREE.SpotLight(new THREE.Color(1.0, 0.58, 0.24), 70, 0, 0.06, 0.55, 0);
    sp.position.copy(POOL).addScaledVector(SUN_DIR, 34); sp.target.position.copy(POOL); sp.layers.enableAll(); scene.add(sp, sp.target); }
  const hero = sprite('hero', HX, 0.0, HZ);
  { const hl = new THREE.PointLight(new THREE.Color(1.0, 0.70, 0.36), 7, 3.4, 1.6); hl.position.set(HX - 0.5, 1.8, HZ + 1.4); hl.layers.enableAll(); scene.add(hl); }
  { // 腳下的接觸陰影（橢圓）
    const sh = new THREE.Mesh(new THREE.CircleGeometry(0.5, 12), new THREE.MeshBasicMaterial({ color: 0x06040a, transparent: true, opacity: 0.85, depthWrite: false }));
    sh.rotation.x = -Math.PI / 2; sh.scale.set(0.95, 0.75, 1); sh.position.set(HX, 0.02, HZ + 0.15); scene.add(sh);
  }
  {
    const tex = T.hero, m = new THREE.MeshLambertMaterial({ map: tex, alphaTest: 0.5 });
    m.onBeforeCompile = (sh) => {
      sh.uniforms.uTexel = { value: new THREE.Vector2(1 / tex.userData.w, 1 / tex.userData.h) };
      sh.uniforms.uRim = { value: new THREE.Color(2.6, 1.5, 0.6) };
      sh.fragmentShader = sh.fragmentShader
        .replace('#include <map_pars_fragment>', '#include <map_pars_fragment>\nuniform vec2 uTexel; uniform vec3 uRim;\nfloat aAt(vec2 u){ return (u.x < 0.0 || u.y < 0.0 || u.x > 1.0 || u.y > 1.0) ? 0.0 : texture2D(map, u).a; }')
        .replace('#include <map_fragment>', `#include <map_fragment>
          { // 亮邊只出現在「左上鄰點是透明」的邊緣（朝太陽那一側），其餘外框維持深色
            float e = max(1.0 - aAt(vMapUv + vec2(-uTexel.x, 0.0)), (1.0 - aAt(vMapUv + vec2(0.0, uTexel.y))) * step(vMapUv.x, 0.42)) * step(0.12, vMapUv.y);
            totalEmissiveRadiance += uRim * e * 0.5 * (sampledDiffuseColor.rgb * 0.5 + 0.5) + sampledDiffuseColor.rgb * vec3(0.80, 0.72, 0.68); }`);
    };
    hero.material = m;
  }

  // ---------- 遠景 ----------
  const hills = [];
  for (const [layer, z, y] of [[2, -66, 3]]) {
    const t = P.hillTex(layer), k = 1 / ppm(z);
    const m = new THREE.Mesh(new THREE.PlaneGeometry(1024 * k, 128 * k), new THREE.MeshBasicMaterial({ map: t, alphaTest: 0.5, color: new THREE.Color(0.30, 0.16, 0.26) }));
    m.position.set(layer * 14 - 10, y + 64 * k, z); scene.add(m); hills.push(m);
  }
  // 天空
  // codex 畫的黃昏天空（一個藝術像素 = 1 個低解析像素；左右鏡射延伸），霞光最亮處對到缺口的樹後
  const skyMat = new THREE.ShaderMaterial({
    uniforms: { map: { value: T.sky7 }, uPpm: { value: ppm(-260) } },
    vertexShader: 'varying vec3 vW; void main(){ vW = (modelMatrix * vec4(position,1.0)).xyz; gl_Position = projectionMatrix * viewMatrix * vec4(vW,1.0); }',
    fragmentShader: `
      varying vec3 vW; uniform sampler2D map; uniform float uPpm;
      void main(){
        float col = 320.0 + vW.x * uPpm, row = ${(180 - HORIZON).toFixed(1)} - (vW.y - ${CAM_Y.toFixed(1)}) * uPpm;
        vec2 uv = vec2((floor(col) + 0.5 - 97.0) / 418.0, 1.0 - clamp(floor(row) + 0.5 + 118.0, 0.5, 234.5) / 235.0);
        vec3 c = texture2D(map, uv).rgb;
        float l = dot(c, vec3(0.3, 0.6, 0.1));
        float hot = smoothstep(0.20, 0.50, l);
        vec3 cool = mix(vec3(l), c, 0.55) * vec3(0.80, 0.86, 1.30);          // 雲與高空：降飽和、往紫藍
        vec3 warm = mix(c, vec3(1.0, 0.74, 0.36) * (l + 0.25), 0.55);         // 霞光：橘金
        vec3 o = mix(cool * 1.15, warm * 2.3, hot);
        float hz = smoothstep(-6.0, 62.0, row);                               // 越接近屋頂線越亮越金：一整片乾淨的霞光
        o = mix(o, vec3(2.7, 1.30, 0.44) * (0.72 + 0.5 * l), hz * 0.96);
        gl_FragColor = vec4(o, 1.0);
      }`,
  });
  const sky = new THREE.Mesh(new THREE.PlaneGeometry(900, 400), skyMat);
  sky.position.set(0, 110, -260); scene.add(sky);

  // 夕陽：缺口上方、樹冠後面一團集中的金色光（讓光束有來源，亮度夠高讓 bloom 起作用）
  {
    const g = new THREE.Mesh(new THREE.PlaneGeometry(22, 22), new THREE.ShaderMaterial({
      transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, uniforms: { uPx: { value: ppm(-30) } },
      vertexShader: 'varying vec2 vP; void main(){ vP = position.xy; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
      fragmentShader: `varying vec2 vP; uniform float uPx;
        float bayer(vec2 p){ ivec2 q = ivec2(mod(p, 4.0)); int i = q.x + q.y * 4; int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5); return (float(m[i]) + 0.5) / 16.0; }
        void main(){ vec2 c = floor(vP * uPx); vec2 q = (c + 0.5) / uPx; float d = length(q);
          float core = smoothstep(0.75, 0.45, d) * 4.0;                               // 小亮點（大半藏在葉團後）
          float h = exp(-d * 0.42) * 4.0;                                              // 指數衰減的光暈，量化成 4 階＋Bayer 抖色過渡
          float halo = floor(h + bayer(c)) / 4.0 * smoothstep(10.5, 7.0, d);
          // 樹冠下緣到屋頂之間再補一層低強度、3 階的暖金光暈，讓人看得出光從這裡來
          float d2 = length((q - vec2(0.3, -1.5)) * vec2(0.8, 1.0));
          float halo2 = floor(exp(-d2 * d2 * 0.07) * 3.0 + bayer(c)) / 3.0 * smoothstep(10.5, 7.0, d);
          float soft = exp(-d2 * d2 * 0.09) * smoothstep(10.5, 6.0, d);   // 霞光本身在天空貼圖裡，這裡只補一層不抖色的柔光
          gl_FragColor = vec4(vec3(1.5, 0.85, 0.4) * soft * 0.5 + vec3(1.0, 0.85, 0.5) * core * 0.6, 1.0); }`,
    }));
    g.position.set(-7.4, 8.5, -30); scene.add(g);
  }

  // ---------- 粒子：落葉、蝴蝶、鳥、煙 ----------
  const shadowU = { tShadow: { value: null }, uShadowMat: { value: new THREE.Matrix4() } };
  const partVert = (body) => `
    #include <packing>
    attribute vec4 aA; attribute vec4 aB; attribute vec3 aCol; uniform float uTime; varying vec2 vUv; varying vec3 vCol; varying float vK;
    uniform sampler2D tShadow; uniform mat4 uShadowMat;
    float sunLit(vec3 p){ vec4 sc = uShadowMat * vec4(p, 1.0); sc.xyz /= sc.w;
      if (sc.x < 0.0 || sc.x > 1.0 || sc.y < 0.0 || sc.y > 1.0 || sc.z > 1.0) return 1.0;
      return step(sc.z - 0.002, unpackRGBAToDepth(texture2D(tShadow, sc.xy))); }
    void main(){ vec3 c; vec2 sz; vec2 uvo = uv; float k = 0.0; vec3 col = aCol;
      ${body}
      vUv = uvo; vCol = col; vK = k;
      vec3 wp = c + vec3(position.xy * sz, 0.0);
      gl_Position = projectionMatrix * viewMatrix * vec4(wp, 1.0); }`;
  const partFrag = (body = '') => `float bayer(vec2 p){ ivec2 q = ivec2(mod(p, 4.0)); int i = q.x + q.y * 4; int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5); return (float(m[i]) + 0.5) / 16.0; }
    uniform sampler2D map; uniform vec3 uLight; varying vec2 vUv; varying vec3 vCol; varying float vK;
    void main(){ vec4 t = texture2D(map, vUv); ${body} if (t.a < 0.5) discard; gl_FragColor = vec4(t.rgb * vCol * uLight, 1.0); }`;
  function particles(n, tex, vert, frag, fill, light = [1, 1, 1], layer = 0) {
    const geo = new THREE.PlaneGeometry(1, 1);
    const A = new Float32Array(n * 4), B = new Float32Array(n * 4), C = new Float32Array(n * 3);
    for (let i = 0; i < n; i++) fill(i, A, B, C);
    geo.setAttribute('aA', new THREE.InstancedBufferAttribute(A, 4)); geo.setAttribute('aB', new THREE.InstancedBufferAttribute(B, 4)); geo.setAttribute('aCol', new THREE.InstancedBufferAttribute(C, 3));
    const mat = new THREE.ShaderMaterial({ uniforms: { uTime: U.time, map: { value: tex }, uLight: { value: new THREE.Vector3(...light) }, ...shadowU }, vertexShader: partVert(vert), fragmentShader: partFrag(frag), side: THREE.DoubleSide });
    const m = new THREE.InstancedMesh(geo, mat, n); m.frustumCulled = false; m.layers.set(layer); scene.add(m);
    return m;
  }
  // 落葉：aA = 起點 xyz + 相位, aB = (落下高度, 週期, 飄移, 大小px)
  const leafSrc = [[-4.7, 8.0, -9.0, 3.0, 9], [-9.4, 4.2, 2.3, 1.6, 4], [-4.5, 7.5, -1.5, 7.0, 2], [-13.5, 5.6, -11.5, 2, 2]];
  particles(170, T.leafbit, `
      float life = aB.y; float t = uTime / life + aA.w; k = fract(t); float id = floor(t);
      float gust = sin(uTime * 0.45 + aA.x * 0.12) * 0.5 + 0.5;
      c = aA.xyz + vec3(k * aB.z * (0.7 + gust * 0.6) + sin(k * 17.0 + aA.w * 40.0) * 0.5, -k * aB.x + sin(k * 31.0 + aA.w * 9.0) * 0.12, sin(k * 9.0 + aA.w * 20.0) * 0.6 + k * 1.5);
      float spin = uTime * 5.0 + aA.w * 60.0;
      sz = vec2(0.45 + 0.55 * cos(spin), 0.7 + 0.3 * sin(spin * 0.7)) * aB.w;
      col *= (0.8 + 0.4 * abs(cos(spin))) * mix(0.42, 2.0, sunLit(c));`, '',
    (i, A, B, C) => {
      const s = leafSrc[i < 70 ? 0 : i < 95 ? 1 : i < 160 ? 2 : 3];
      const x = s[0] + rr(-1, 1) * s[3], y = s[1] + rr(-1.2, 1.2), z = s[2] + rr(-1, 1) * s[3] * 0.6;
      const ground = z > 3.5 ? WATER_Y : 0.05;
      A.set([x, y, z, R()], i * 4); B.set([y - ground, rr(6, 10), rr(2.5, 6), 6 / ppm(z)], i * 4);
      const c = pick(AUTUMN); C.set([c.r, c.g, c.b], i * 3);
    }, [0.85, 0.75, 0.72]);
  // 地上與水面的落葉
  {
    const n = 120, geo = new THREE.PlaneGeometry(1, 1);
    const mesh = new THREE.InstancedMesh(geo, new THREE.MeshLambertMaterial({ map: T.leafbit, alphaTest: 0.5 }), n);
    const M = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler();
    for (let i = 0; i < n; i++) {
      let x, z, y = 0.03;
      const v = R();
      if (v < 0.5) { x = -3.0 + rr(-1, 1) * rr(0, 6); z = rr(-11, 3.1); if (z < -3.2 && x > -6 && x < 0.4) y = 0.13; else if (z < -2.3) y = 0.17; }
      else if (v < 0.7) { x = -9.4 + rr(-3, 4); z = rr(0.5, 3.1); }
      else { x = rr(-18, 18); z = rr(-2.2, 3.0); }
      const s = 5 / ppm(z);
      e.set(-Math.PI / 2, 0, R() * 6.28); q.setFromEuler(e);
      M.compose(new THREE.Vector3(x, y, z), q, new THREE.Vector3(s, s * 2.4, 1));
      mesh.setMatrixAt(i, M); mesh.setColorAt(i, pick(AUTUMN).clone().multiplyScalar(1.7));
    }
    mesh.receiveShadow = true; scene.add(mesh);
  }
  // 蝴蝶：aA = 中心 xyz + 相位, aB = (rx, ry, rz, 大小)
  const bflyCol = [[1.0, 0.95, 0.8], [1.0, 0.78, 0.15], [0.35, 0.65, 1.0], [1.0, 0.45, 0.6], [1.0, 0.55, 0.15]];
  particles(7, T.bfly, `
      float t = uTime * 0.55 + aA.w * 30.0;
      c = aA.xyz + vec3(sin(t * 1.0) * aB.x + sin(t * 2.7) * 0.35, sin(t * 1.7 + aA.w * 5.0) * aB.y + abs(sin(t * 6.0)) * 0.18, cos(t * 0.8) * aB.z);
      float fr = step(0.0, sin(uTime * 22.0 + aA.w * 50.0));
      uvo = vec2(uv.x * 0.5 + fr * 0.5, uv.y);
      sz = vec2(aB.w, aB.w * 7.0 / 9.0); col *= mix(0.6, 1.5, sunLit(c));`, '',
    (i, A, B, C) => {
      const spots = [[-3.2, 1.0, -3.6, 2.2, 0.5, 0.5], [-1.2, 1.2, -4.6, 1.5, 0.6, 0.8], [-4.6, 1.4, -5.2, 1.2, 0.7, 1.0], [-9.2, 1.1, 2.6, 1.0, 0.5, 0.4], [4.2, 1.3, -2.6, 1.4, 0.5, 0.3], [0.6, 1.5, 1.6, 1.6, 0.6, 0.8], [-13.6, 1.2, -2.9, 1.4, 0.4, 0.3]][i];
      A.set([spots[0], spots[1], spots[2], R()], i * 4); B.set([spots[3], spots[4], spots[5], 9 / ppm(spots[2])], i * 4); C.set(bflyCol[i % 5], i * 3);
    }, [1.0, 0.95, 0.9]);
  // 鳥群：aA = (x 偏移, y, z, 相位), aB = (速度, 跨度, 大小, 方向)
  particles(16, T.bird, `
      float span = aB.y; float x = mod(uTime * aB.x + aA.x, span) - span * 0.5;
      c = vec3(x * aB.w, aA.y + sin(uTime * 0.7 + aA.w * 6.0) * 0.8 + sin(x * 0.08) * 2.0, aA.z);
      float fr = step(0.0, sin(uTime * 7.0 + aA.w * 20.0));
      uvo = vec2((uv.x * aB.w * 0.5 + (aB.w < 0.0 ? 0.5 : 0.0)) + fr * 0.5, uv.y);
      sz = vec2(8.0, 6.0) * aB.z;`, '',
    (i, A, B, C) => {
      const flock = i < 9 ? 0 : i < 14 ? 1 : 2;
      const j = flock === 0 ? i : flock === 1 ? i - 9 : i - 14;
      const z = [-60, -34, -11][flock], base = [14.2, 13.0, 11.6][flock];
      const off = flock === 2 ? j * 3.2 + 30 : Math.abs(j - (flock ? 2 : 4)) * -1.8 + (flock ? 44 : 0);
      const yy = base + (flock === 2 ? j * 0.5 : (j - (flock ? 2 : 4)) * 0.7);
      A.set([off, yy, z, R()], i * 4); B.set([[3.6, 3.0, 2.6][flock], [112, 84, 60][flock], [1, 1, 2][flock] / ppm(z), flock === 1 ? -1 : 1], i * 4);
      C.set(flock === 2 ? [0.14, 0.08, 0.14] : [0.22, 0.14, 0.24], i * 3);
    });
  // 煙：少量小煙團，顏色跟著光走，用 4×4 Bayer 抖色淡出。aA = 煙囪口 xyz + 相位, aB = (週期, 上升, 飄移, 大小)
  if (opts.smoke) particles(smokeSrc.length * 5, T.white, `
      float t = uTime / aB.x + aA.w; k = fract(t);
      c = aA.xyz + vec3(k * aB.z + sin(k * 6.0 + aA.w * 70.0) * 0.25 * k, k * aB.y, 0.0);
      sz = vec2(aB.w * (0.6 + k * 0.7));
      col *= mix(0.55, 1.5, sunLit(c));`, `
      float d = length(vUv - 0.5) * 2.0;
      float a = (1.0 - vK) * 0.8 * smoothstep(1.0, 0.55, d) * step(d, 1.0);
      t.a = a > bayer(gl_FragCoord.xy) ? 1.0 : 0.0;`,
    (i, A, B, C) => {
      const sm = smokeSrc[(i / 5) | 0], j = i % 5;
      A.set([sm[0], sm[1], sm[2], j / 5 + R() * 0.05], i * 4); B.set([9, 3.2, 2.4, rr(7, 10) / ppm(sm[2])], i * 4);
      C.set([1, 1, 1], i * 3);
    }, [0.42, 0.36, 0.46]);
  // 光裡的浮塵
  particles(70, T.white, `
      float t = uTime * 0.12 + aA.w * 10.0;
      c = aA.xyz + vec3(sin(t * 1.3 + aA.w * 40.0) * 1.2 + t * 0.0, sin(t * 2.1 + aA.w * 17.0) * 0.7, cos(t * 0.9 + aA.w * 5.0) * 1.0);
      float tw = 0.5 + 0.5 * sin(uTime * 2.0 + aA.w * 90.0);
      sz = vec2(aB.w) * sunLit(c); col *= 0.6 + tw * 1.8;`, '',
    (i, A, B, C) => {
      const x = rr(-6, 6), y = rr(0.6, 6), z = rr(-3, 3);
      A.set([x, y, z, R()], i * 4); B.set([0, 0, 0, 1.01 / ppm(z)], i * 4); C.set([1.6, 1.1, 0.5], i * 3);
    });

  let fgBranch = null;
  // ---------- 近前景（獨立一層，先模糊再疊回去） ----------
  if (!opts.nofg) {
    const fz = 21, vt = CAM_Y + (180 - HORIZON) / FPX * (CAM_Z - fz), vb = CAM_Y + (-180 - HORIZON) / FPX * (CAM_Z - fz);
    // 單側一根垂下的楓枝（刻意設計的深色前景，只略微失焦）
    if (T.branch) {
      const k = 1 / ppm(fz), w = T.branch.userData.w * k, hh = T.branch.userData.h * k;
      const vl = -320 / FPX * (CAM_Z - fz);
      const m = new THREE.Mesh(new THREE.PlaneGeometry(w, hh), new THREE.MeshBasicMaterial({ map: T.branch, alphaTest: 0.5, color: new THREE.Color(0.40, 0.22, 0.24) }));
      m.position.set(vl + w / 2 - 0.15, vt - hh / 2 + 0.15, fz); m.layers.set(1); scene.add(m); fgBranch = m;
      // 前景路燈桿：銳利的深色剪影，從下緣一路切到屋頂高度，打破一條條橫帶
      const dk = new THREE.MeshBasicMaterial({ color: 0x0c070c }), px = -3.75, yb = vb - 0.3, top = vb + 3.55;
      const part = (w2, h2, x, y, mat = dk) => { const b = new THREE.Mesh(new THREE.BoxGeometry(w2, h2, 0.1), mat); b.position.set(x, y + h2 / 2, fz + 0.3); b.layers.set(1); scene.add(b); };
      part(0.11, top - yb, px, yb); part(0.24, 0.3, px, yb); part(0.19, 0.05, px, top - 0.75);
      part(0.36, 0.05, px, top); part(0.05, 0.36, px - 0.15, top + 0.05); part(0.05, 0.36, px + 0.15, top + 0.05); part(0.44, 0.06, px, top + 0.41); part(0.2, 0.08, px, top + 0.47);
      part(0.13, 0.2, px, top + 0.1, new THREE.MeshBasicMaterial({ color: new THREE.Color(1.5, 0.85, 0.3) }));
    }
  }

  // ---------- 每格更新 ----------
  function update(t) {
    U.time.value = t;
    for (const L of lamps) L.l.intensity = L.base * (0.94 + 0.06 * Math.sin(t * 9 + L.ph) * Math.sin(t * 3.3 + L.ph * 2));
    boat.position.y = WATER_Y - 0.22 + T.boat.userData.h / ppm(4.9) / 2 + Math.sin(t * 1.1) * 0.035;
    boat.rotation.z = Math.sin(t * 0.8) * 0.012;
    // 待機：呼吸（整張圖高 1 像素的伸縮，腳不動）、釣竿輕晃、前景枝條擺動
    for (const [m, period, ph] of [[hero, 2.6, 0], [baker, 3.1, 1.2]]) {
      const hgt = m.geometry.parameters.height, px = hgt / m.material.map.userData.h;
      const up = Math.sin(t * 6.283 / period + ph) > 0.25 ? 1 : 0;
      if (m.userData.y0 === undefined) m.userData.y0 = m.position.y;
      m.scale.y = 1 + up * px / hgt; m.position.y = m.userData.y0 + up * px / 2;
    }
    fisher.rotation.z = Math.round(Math.sin(t * 1.9) * 2) / 2 * 0.035 + (Math.sin(t * 0.6) > 0.9 ? 0.06 : 0);
    if (fgBranch) fgBranch.rotation.z = Math.round(Math.sin(t * 0.8) * 3) / 3 * 0.012;
  }

  return { scene, sun, fill, water, street, reflU, waterU, shadowU, update, hero, sky, POOL };
}
