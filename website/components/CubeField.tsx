"use client";

import { useEffect, useRef, useState } from "react";

/**
 * WebGL hero: a field of ~20,000 cubes with a wave rolling through it, each
 * cube flipping end over end as the wave passes.
 *
 * All of the motion happens in the vertex shader. The CPU builds the instance
 * buffers once at startup and then does nothing per frame — no matrix
 * composition, no attribute uploads. That is what makes 20k independently
 * rotating cubes (roughly 700k vertices a frame) affordable; doing the same
 * with InstancedMesh.setMatrixAt would mean 20k matrix builds in JavaScript
 * every frame and would not hold 60fps.
 *
 * Custom lighting in the fragment shader rather than MeshStandardMaterial:
 * the rotation happens per-vertex, so the normals have to be rotated by the
 * same matrix, and hand-writing the shading is simpler than injecting that
 * into three's material chain.
 */

/* Grid is GRID x GRID cubes. 140 -> 19,600 instances. */
const GRID = 140;
const SPACING = 0.62;
const CUBE = 0.4;

const VERT_SRC = `
precision highp float;

attribute vec3 aOffset;
attribute float aPhase;

uniform float uTime;
uniform float uCube;

varying vec3 vNormal;
varying float vWave;
varying vec3 vWorld;

mat3 rotX(float a) {
  float c = cos(a), s = sin(a);
  return mat3(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

mat3 rotY(float a) {
  float c = cos(a), s = sin(a);
  return mat3(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

void main() {
  /* Two crossing waves — one radial from the centre, one travelling
     diagonally. A single wave reads as a mechanical ripple; crossing them
     makes the field feel alive. */
  float radial = length(aOffset.xz) * 0.30 - uTime * 1.45;
  float travel = (aOffset.x + aOffset.z) * 0.11 - uTime * 0.85;
  float w = sin(radial) * 0.65 + sin(travel + aPhase) * 0.45;

  /* The flip. Rotating on two axes at different rates keeps neighbouring
     cubes from ever landing in the same orientation. */
  float a = w * 1.75;
  mat3 R = rotY(a * 0.72) * rotX(a);

  vec3 local = R * (position * uCube);
  vNormal = normalize(R * normal);
  vWave = w;

  vec3 world = local + aOffset + vec3(0.0, w * 0.9, 0.0);
  vWorld = world;

  gl_Position = projectionMatrix * modelViewMatrix * vec4(world, 1.0);
}`;

const FRAG_SRC = `
precision highp float;

varying vec3 vNormal;
varying float vWave;
varying vec3 vWorld;

void main() {
  vec3 n = normalize(vNormal);

  vec3 keyDir = normalize(vec3(0.45, 0.85, 0.42));
  vec3 fillDir = normalize(vec3(-0.6, 0.25, 0.5));

  float key = max(dot(n, keyDir), 0.0);
  float fill = max(dot(n, fillDir), 0.0) * 0.4;

  /* Rim term picks out the silhouette of every cube, which is what stops
     20,000 of them reading as a single grey mass. */
  float rim = pow(1.0 - max(dot(n, vec3(0.0, 0.0, 1.0)), 0.0), 2.6);

  /* Colour rides the wave: crests take the accent blue, troughs stay pale. */
  vec3 pale = vec3(0.882, 0.906, 0.945);
  vec3 blue = vec3(0.184, 0.435, 0.894);
  vec3 base = mix(pale, blue, smoothstep(-0.9, 1.0, vWave));

  vec3 col = base * (0.34 + 0.82 * key + fill);
  col += vec3(0.42, 0.60, 1.0) * rim * 0.55;

  /* Distance haze so the far edge of the grid dissolves instead of ending
     on a hard line. */
  float haze = smoothstep(14.0, 46.0, length(vWorld.xz));
  col = mix(col, vec3(1.0), haze);

  gl_FragColor = vec4(col, 1.0 - haze * 0.15);
}`;

export default function CubeField() {
  const hostRef = useRef<HTMLDivElement>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;

    let disposed = false;
    let cleanup: (() => void) | undefined;

    (async () => {
      let THREE: typeof import("three");
      try {
        THREE = await import("three");
      } catch (error) {
        console.error("[CubeField] three.js failed to load:", error);
        return;
      }
      if (disposed) return;

      let renderer: import("three").WebGLRenderer;
      try {
        renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true });
      } catch (error) {
        console.error("[CubeField] WebGL unavailable:", error);
        return;
      }

      renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75));
      renderer.setSize(host.clientWidth, Math.max(host.clientHeight, 1), false);
      Object.assign(renderer.domElement.style, {
        width: "100%",
        height: "100%",
        display: "block",
      });
      host.appendChild(renderer.domElement);

      const scene = new THREE.Scene();
      const camera = new THREE.PerspectiveCamera(
        38,
        host.clientWidth / Math.max(host.clientHeight, 1),
        0.1,
        200,
      );
      camera.position.set(0, 7.5, 25);
      camera.lookAt(0, 0, -2);

      /* ---- instance buffers, built once ---- */
      const count = GRID * GRID;
      const offsets = new Float32Array(count * 3);
      const phases = new Float32Array(count);

      let i = 0;
      for (let gx = 0; gx < GRID; gx++) {
        for (let gz = 0; gz < GRID; gz++) {
          offsets[i * 3 + 0] = (gx - GRID / 2) * SPACING;
          offsets[i * 3 + 1] = 0;
          offsets[i * 3 + 2] = (gz - GRID / 2) * SPACING;
          phases[i] = Math.random() * Math.PI * 2;
          i++;
        }
      }

      const boxGeo = new THREE.BoxGeometry(1, 1, 1);
      const geometry = new THREE.InstancedBufferGeometry();
      geometry.index = boxGeo.index;
      geometry.attributes.position = boxGeo.attributes.position;
      geometry.attributes.normal = boxGeo.attributes.normal;
      geometry.setAttribute("aOffset", new THREE.InstancedBufferAttribute(offsets, 3));
      geometry.setAttribute("aPhase", new THREE.InstancedBufferAttribute(phases, 1));
      geometry.instanceCount = count;
      // The shader moves vertices far outside the base box, so the automatic
      // bounds are wrong and three would frustum-cull the whole field.
      geometry.boundingSphere = new THREE.Sphere(new THREE.Vector3(), GRID * SPACING);

      const material = new THREE.ShaderMaterial({
        vertexShader: VERT_SRC,
        fragmentShader: FRAG_SRC,
        uniforms: {
          uTime: { value: 0 },
          uCube: { value: CUBE },
        },
        transparent: true,
      });

      const field = new THREE.Mesh(geometry, material);
      /* Sits low so the top of the hero stays clear for the headline. At y=0
         the field fills the frame and the copy is unreadable over it. */
      field.position.y = -3.4;
      scene.add(field);

      const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      const started = performance.now();

      const draw = () => {
        const t = reduceMotion ? 0 : (performance.now() - started) / 1000;
        material.uniforms.uTime.value = t;

        // Slow drift so the composition never sits perfectly still.
        camera.position.x = Math.sin(t * 0.12) * 2.4;
        camera.position.y = 7.5 + Math.sin(t * 0.09) * 0.7;
        camera.lookAt(0, 0, -2);

        renderer.render(scene, camera);
      };

      let raf = 0;
      let running = false;

      const loop = () => {
        draw();
        if (running) raf = requestAnimationFrame(loop);
      };

      const play = () => {
        if (running || reduceMotion) return;
        running = true;
        raf = requestAnimationFrame(loop);
      };

      const pause = () => {
        running = false;
        cancelAnimationFrame(raf);
      };

      const resize = () => {
        const w = host.clientWidth;
        const h = Math.max(host.clientHeight, 1);
        camera.aspect = w / h;
        camera.updateProjectionMatrix();
        renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75));
        renderer.setSize(w, h, false);
      };

      draw();
      setReady(true);
      play();

      const ro = new ResizeObserver(() => {
        resize();
        if (!running) draw();
      });
      ro.observe(host);

      const onVisibility = () => (document.hidden ? pause() : play());
      document.addEventListener("visibilitychange", onVisibility);

      const onLost = (event: Event) => {
        event.preventDefault();
        pause();
        setReady(false);
      };
      renderer.domElement.addEventListener("webglcontextlost", onLost);

      cleanup = () => {
        pause();
        ro.disconnect();
        document.removeEventListener("visibilitychange", onVisibility);
        renderer.domElement.removeEventListener("webglcontextlost", onLost);
        geometry.dispose();
        boxGeo.dispose();
        material.dispose();
        renderer.dispose();
        renderer.domElement.remove();
      };
    })();

    return () => {
      disposed = true;
      cleanup?.();
    };
  }, []);

  return <div ref={hostRef} className="vanta-bg" data-ready={ready} aria-hidden="true" />;
}
