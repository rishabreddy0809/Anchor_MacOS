import { useEffect, useRef } from "react";

/**
 * AuroraSilk — full-bleed WebGL backdrop.
 * Domain-warped flowing silk in deep teal / cyan / indigo. Slow, cinematic,
 * pointer-reactive. One full-screen fragment shader, no dependencies.
 */

const VERT = `attribute vec2 a_pos; void main(){ gl_Position = vec4(a_pos,0.0,1.0); }`;

const FRAG = `
precision highp float;
uniform vec2 u_res; uniform float u_time; uniform vec2 u_mouse; uniform float u_intro;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1,311.7)))*43758.5453123); }
float noise(vec2 p){
  vec2 i=floor(p), f=fract(p); vec2 u=f*f*(3.0-2.0*f);
  return mix(mix(hash(i),hash(i+vec2(1,0)),u.x), mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),u.x),u.y);
}
float fbm(vec2 p){ float v=0.0,a=0.5; for(int i=0;i<6;i++){ v+=a*noise(p); p=p*2.02+11.0; a*=0.5; } return v; }

void main(){
  vec2 uv = (gl_FragCoord.xy - 0.5*u_res)/u_res.y;
  float t = u_time*0.06;
  vec2 p = uv*1.35 + u_mouse*0.05;

  // domain warping -> silk folds
  vec2 q = vec2(fbm(p + vec2(0.0, t)), fbm(p + vec2(5.2, -t*0.8)));
  vec2 r = vec2(fbm(p + 3.0*q + vec2(1.7 + t*1.2, 9.2)),
                fbm(p + 3.0*q + vec2(8.3, 2.8 - t*0.9)));
  float f = fbm(p + 3.2*r);

  // ridged highlight along the folds
  float fold = abs(sin((f + r.x*0.8) * 9.0 + t * 4.0));
  fold = pow(1.0 - fold, 3.2);

  vec3 deep  = vec3(0.020, 0.055, 0.085);
  vec3 mid   = vec3(0.020, 0.290, 0.400);
  vec3 hot   = vec3(0.180, 0.900, 1.000);
  vec3 violet= vec3(0.230, 0.190, 0.520);

  vec3 col = mix(deep, mid, smoothstep(0.25, 0.95, f));
  col = mix(col, violet, smoothstep(0.35, 0.9, r.y) * 0.5);
  col += hot * fold * smoothstep(0.2, 0.85, f) * 0.75;

  // drifting caustic sparkle
  float spark = pow(fbm(p*4.0 + vec2(t*3.0, -t*2.0)), 6.0);
  col += hot * spark * 0.35;

  // top-down light shaft
  col += vec3(0.05,0.35,0.5) * smoothstep(0.9,-0.2,uv.y) * 0.18;

  // vignette + grade
  float vig = smoothstep(1.35, 0.2, length(uv*vec2(0.65,1.0)));
  col *= 0.16 + 0.72*vig;
  col *= u_intro;
  col = col/(col+0.85);
  col = pow(col, vec3(0.9));
  col += (hash(gl_FragCoord.xy + u_time)-0.5)*0.012;
  gl_FragColor = vec4(col,1.0);
}
`;

function compile(gl: WebGLRenderingContext, type: number, src: string) {
  const s = gl.createShader(type)!;
  gl.shaderSource(s, src);
  gl.compileShader(s);
  if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
    console.error(gl.getShaderInfoLog(s));
    return null;
  }
  return s;
}

export function AuroraSilk() {
  const ref = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    const gl = canvas.getContext("webgl", {
      alpha: false,
      antialias: false,
    }) as WebGLRenderingContext | null;
    if (!gl) return;

    const vs = compile(gl, gl.VERTEX_SHADER, VERT);
    const fs = compile(gl, gl.FRAGMENT_SHADER, FRAG);
    if (!vs || !fs) return;
    const prog = gl.createProgram()!;
    gl.attachShader(prog, vs);
    gl.attachShader(prog, fs);
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
      console.error(gl.getProgramInfoLog(prog));
      return;
    }
    gl.useProgram(prog);

    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(prog, "a_pos");
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);

    const uRes = gl.getUniformLocation(prog, "u_res");
    const uTime = gl.getUniformLocation(prog, "u_time");
    const uMouse = gl.getUniformLocation(prog, "u_mouse");
    const uIntro = gl.getUniformLocation(prog, "u_intro");

    const dpr = Math.min(window.devicePixelRatio || 1, 1.6);
    const resize = () => {
      const w = canvas.clientWidth;
      const h = canvas.clientHeight;
      if (!w || !h) return;
      canvas.width = Math.floor(w * dpr);
      canvas.height = Math.floor(h * dpr);
      gl.viewport(0, 0, canvas.width, canvas.height);
      gl.uniform2f(uRes, canvas.width, canvas.height);
    };
    resize();
    const ro = new ResizeObserver(resize);
    ro.observe(canvas);

    const target = { x: 0, y: 0 };
    const cur = { x: 0, y: 0 };
    const onMove = (e: PointerEvent) => {
      target.x = (e.clientX / window.innerWidth) * 2 - 1;
      target.y = (e.clientY / window.innerHeight) * -2 + 1;
    };
    window.addEventListener("pointermove", onMove, { passive: true });

    let visible = true;
    const io = new IntersectionObserver((e) => {
      visible = e[0]?.isIntersecting ?? true;
    });
    io.observe(canvas);
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    let raf = 0;
    const start = performance.now();
    const loop = (now: number) => {
      raf = requestAnimationFrame(loop);
      if (!visible) return;
      const el = (now - start) / 1000;
      cur.x += (target.x - cur.x) * 0.035;
      cur.y += (target.y - cur.y) * 0.035;
      gl.uniform1f(uTime, reduced ? 20 : el);
      gl.uniform2f(uMouse, cur.x, cur.y);
      gl.uniform1f(uIntro, Math.min(1, el / 1.4));
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    };
    raf = requestAnimationFrame(loop);

    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      io.disconnect();
      window.removeEventListener("pointermove", onMove);
      gl.deleteProgram(prog);
      gl.deleteShader(vs);
      gl.deleteShader(fs);
      gl.deleteBuffer(buf);
    };
  }, []);

  return <canvas ref={ref} className="absolute inset-0 h-screen w-screen" aria-hidden="true" />;
}
