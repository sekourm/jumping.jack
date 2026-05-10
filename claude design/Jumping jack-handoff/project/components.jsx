/* global React */
const { useMemo } = React;

// ===== Mascot cube =====
function Mascot({ size = 80, face = "smile", glow = true }) {
  const s = size;
  return (
    <svg width={s} height={s} viewBox="0 0 120 120" style={{ filter: glow ? 'drop-shadow(0 0 16px rgba(255,200,87,0.5)) drop-shadow(0 6px 12px rgba(0,0,0,0.4))' : 'drop-shadow(0 4px 8px rgba(0,0,0,0.4))' }}>
      <defs>
        <linearGradient id={`mg${face}${s}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#FFE198"/>
          <stop offset="0.55" stopColor="#FFC857"/>
          <stop offset="1" stopColor="#C8861A"/>
        </linearGradient>
        <linearGradient id={`mgs${face}${s}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="rgba(255,255,255,0.8)"/>
          <stop offset="0.5" stopColor="rgba(255,255,255,0)"/>
        </linearGradient>
      </defs>
      {/* body */}
      <rect x="14" y="14" width="92" height="92" rx="18" fill={`url(#mg${face}${s})`} stroke="#7A4A00" strokeWidth="5" strokeLinejoin="round"/>
      {/* top crown highlight */}
      <rect x="22" y="20" width="76" height="14" rx="8" fill={`url(#mgs${face}${s})`} opacity="0.7"/>
      {/* face */}
      {face === 'smile' && (
        <g>
          <ellipse cx="46" cy="60" rx="9" ry="11" fill="white"/>
          <ellipse cx="74" cy="60" rx="9" ry="11" fill="white"/>
          <circle cx="48" cy="62" r="4" fill="#1a1a1a"/>
          <circle cx="76" cy="62" r="4" fill="#1a1a1a"/>
          <path d="M 45 80 Q 60 92 75 80" stroke="#7A4A00" strokeWidth="4" strokeLinecap="round" fill="none"/>
        </g>
      )}
      {face === 'excited' && (
        <g>
          <ellipse cx="46" cy="58" rx="9" ry="11" fill="white"/>
          <ellipse cx="74" cy="58" rx="9" ry="11" fill="white"/>
          <circle cx="46" cy="58" r="5" fill="#1a1a1a"/>
          <circle cx="74" cy="58" r="5" fill="#1a1a1a"/>
          <ellipse cx="60" cy="84" rx="8" ry="9" fill="#7A4A00"/>
          <ellipse cx="60" cy="82" rx="5" ry="5" fill="#3a1f00"/>
        </g>
      )}
      {face === 'determined' && (
        <g>
          <rect x="38" y="56" width="16" height="6" rx="3" fill="#7A4A00"/>
          <rect x="66" y="56" width="16" height="6" rx="3" fill="#7A4A00"/>
          <rect x="44" y="80" width="32" height="6" rx="3" fill="#7A4A00"/>
        </g>
      )}
      {face === 'charge' && (
        <g>
          <path d="M 38 58 L 54 64" stroke="#7A4A00" strokeWidth="5" strokeLinecap="round"/>
          <path d="M 66 64 L 82 58" stroke="#7A4A00" strokeWidth="5" strokeLinecap="round"/>
          <rect x="44" y="80" width="32" height="8" rx="2" fill="white" stroke="#7A4A00" strokeWidth="3"/>
          <line x1="50" y1="80" x2="50" y2="88" stroke="#7A4A00" strokeWidth="2"/>
          <line x1="58" y1="80" x2="58" y2="88" stroke="#7A4A00" strokeWidth="2"/>
          <line x1="66" y1="80" x2="66" y2="88" stroke="#7A4A00" strokeWidth="2"/>
        </g>
      )}
      {face === 'dead' && (
        <g>
          <path d="M 40 56 L 52 68 M 52 56 L 40 68" stroke="#7A4A00" strokeWidth="4" strokeLinecap="round"/>
          <path d="M 68 56 L 80 68 M 80 56 L 68 68" stroke="#7A4A00" strokeWidth="4" strokeLinecap="round"/>
          <path d="M 45 84 Q 60 76 75 84" stroke="#7A4A00" strokeWidth="4" strokeLinecap="round" fill="none"/>
        </g>
      )}
    </svg>
  );
}

// ===== Cosmic background =====
function Cosmic({ stage = 'earth', children }) {
  const stars = useMemo(() => {
    const arr = [];
    const seed = stage.charCodeAt(0);
    for (let i = 0; i < 60; i++) {
      const x = ((seed * 9301 + i * 49297) % 233280) / 233280;
      const y = ((seed * 4773 + i * 31337) % 233280) / 233280;
      const sz = ((seed + i * 17) % 4) * 0.6 + 1;
      arr.push({ x: x * 100, y: y * 100, sz, d: (i % 5) * 0.4 });
    }
    return arr;
  }, [stage]);

  const blobs = {
    earth: [{c: 'rgba(124,192,255,0.35)', x: 80, y: 20, s: 220}, {c: 'rgba(80,40,180,0.25)', x: -10, y: 70, s: 280}],
    moon: [{c: 'rgba(220,220,240,0.18)', x: 70, y: 30, s: 200}],
    mars: [{c: 'rgba(255,138,92,0.32)', x: 80, y: 25, s: 240}, {c: 'rgba(180,60,30,0.28)', x: -10, y: 75, s: 260}],
    jupiter: [{c: 'rgba(255,200,140,0.3)', x: 70, y: 30, s: 220}, {c: 'rgba(180,120,40,0.25)', x: 10, y: 75, s: 240}],
    saturn: [{c: 'rgba(255,200,100,0.32)', x: 75, y: 25, s: 220}, {c: 'rgba(160,90,20,0.28)', x: 0, y: 75, s: 240}],
    nebula: [{c: 'rgba(177,75,255,0.42)', x: 75, y: 25, s: 240}, {c: 'rgba(255,100,200,0.28)', x: 0, y: 70, s: 260}],
    battle: [{c: 'rgba(177,75,255,0.4)', x: 50, y: 20, s: 280}, {c: 'rgba(120,40,200,0.3)', x: 10, y: 80, s: 240}],
    dark: [],
  };

  return (
    <div className={`cosmic ${stage}`} style={{ position: 'absolute', inset: 0 }}>
      {(blobs[stage] || []).map((b, i) => (
        <div key={i} className="nebula-blob" style={{
          left: `${b.x}%`, top: `${b.y}%`,
          width: b.s, height: b.s,
          background: b.c,
          transform: 'translate(-50%, -50%)',
        }}/>
      ))}
      {stars.map((s, i) => (
        <div key={i} className="star" style={{
          left: `${s.x}%`, top: `${s.y}%`,
          width: s.sz, height: s.sz,
          animation: `twinkle ${2 + s.d}s ease-in-out infinite`,
          animationDelay: `${s.d}s`,
        }}/>
      ))}
      {/* Saturn ring hint for saturn */}
      {stage === 'saturn' && (
        <svg style={{ position: 'absolute', right: -40, top: 80, opacity: 0.4 }} width="200" height="100" viewBox="0 0 200 100">
          <ellipse cx="100" cy="50" rx="90" ry="14" fill="none" stroke="#FFC857" strokeWidth="2"/>
          <ellipse cx="100" cy="50" rx="60" ry="9" fill="none" stroke="#FFE198" strokeWidth="1.5"/>
        </svg>
      )}
      {children}
    </div>
  );
}

// ===== Cloud platform =====
function Cloud({ kind = 'standard', cracked = false, w = 120 }) {
  const colors = {
    standard: { fill: '#FFFFFF', shadow: '#C8CDD6' },
    moving: { fill: '#FFB890', shadow: '#A35C3A' },
    bouncy: { fill: '#A8EDB6', shadow: '#3D8F4F' },
  };
  const c = colors[kind];
  return (
    <svg width={w} height={w * 0.42} viewBox="0 0 120 50" style={{ filter: 'drop-shadow(0 4px 6px rgba(0,0,0,0.4))' }}>
      <g>
        <ellipse cx="22" cy="28" rx="20" ry="18" fill={c.shadow}/>
        <ellipse cx="46" cy="22" rx="22" ry="20" fill={c.shadow}/>
        <ellipse cx="74" cy="22" rx="22" ry="20" fill={c.shadow}/>
        <ellipse cx="98" cy="28" rx="20" ry="18" fill={c.shadow}/>
        <ellipse cx="22" cy="24" rx="18" ry="16" fill={c.fill}/>
        <ellipse cx="46" cy="18" rx="20" ry="18" fill={c.fill}/>
        <ellipse cx="74" cy="18" rx="20" ry="18" fill={c.fill}/>
        <ellipse cx="98" cy="24" rx="18" ry="16" fill={c.fill}/>
        <ellipse cx="46" cy="12" rx="16" ry="6" fill="rgba(255,255,255,0.7)"/>
        <ellipse cx="74" cy="12" rx="16" ry="6" fill="rgba(255,255,255,0.7)"/>
      </g>
      {kind === 'bouncy' && (
        <g>
          <path d="M 50 4 L 56 -2 L 62 4" stroke="#3D8F4F" strokeWidth="2.5" fill="none" strokeLinecap="round"/>
          <path d="M 64 4 L 70 -2 L 76 4" stroke="#3D8F4F" strokeWidth="2.5" fill="none" strokeLinecap="round"/>
        </g>
      )}
      {cracked && (
        <g stroke="#1a1a1a" strokeWidth="1.5" fill="none" strokeLinecap="round" opacity="0.7">
          <path d="M 40 18 L 46 22 L 42 28 L 50 30"/>
          <path d="M 70 16 L 76 22 L 72 28"/>
        </g>
      )}
    </svg>
  );
}

// ===== Pickup gem =====
function Gem({ kind = 'star', size = 36 }) {
  const palette = {
    star:     { c: '#FFE198', d: '#C8861A', halo: 'rgba(255,255,255,0.5)' },
    crystal:  { c: '#7CC0FF', d: '#1c4a8a', halo: 'rgba(124,192,255,0.6)' },
    heart:    { c: '#FF8AC7', d: '#7a1f55', halo: 'rgba(255,138,199,0.55)' },
    vision:   { c: '#7AE091', d: '#1f6e2e', halo: 'rgba(122,224,145,0.55)' },
    teleport: { c: '#D896FF', d: '#5C1A8A', halo: 'rgba(216,150,255,0.6)' },
  };
  const p = palette[kind];
  const s = size;
  return (
    <svg width={s} height={s} viewBox="0 0 48 48" style={{ filter: `drop-shadow(0 0 12px ${p.halo})` }}>
      <defs>
        <linearGradient id={`gm${kind}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="white" stopOpacity="0.9"/>
          <stop offset="0.4" stopColor={p.c}/>
          <stop offset="1" stopColor={p.d}/>
        </linearGradient>
      </defs>
      {kind === 'star' && (
        <path d="M24 4 L29 18 L44 19 L32 28 L36 42 L24 33 L12 42 L16 28 L4 19 L19 18 Z"
              fill={`url(#gm${kind})`} stroke="#1a1a1a" strokeWidth="2" strokeLinejoin="round"/>
      )}
      {kind === 'crystal' && (
        <path d="M24 4 L40 20 L24 44 L8 20 Z" fill={`url(#gm${kind})`} stroke="#1a1a1a" strokeWidth="2" strokeLinejoin="round"/>
      )}
      {kind === 'heart' && (
        <path d="M24 42 C 4 28, 4 12, 16 12 C 20 12, 24 16, 24 20 C 24 16, 28 12, 32 12 C 44 12, 44 28, 24 42 Z"
              fill={`url(#gm${kind})`} stroke="#1a1a1a" strokeWidth="2" strokeLinejoin="round"/>
      )}
      {kind === 'vision' && (
        <g>
          <ellipse cx="24" cy="24" rx="18" ry="12" fill={`url(#gm${kind})`} stroke="#1a1a1a" strokeWidth="2"/>
          <circle cx="24" cy="24" r="6" fill="#1a1a1a"/>
          <circle cx="22" cy="22" r="2" fill="white"/>
        </g>
      )}
      {kind === 'teleport' && (
        <g>
          <circle cx="24" cy="24" r="18" fill={`url(#gm${kind})`} stroke="#1a1a1a" strokeWidth="2"/>
          <circle cx="24" cy="24" r="11" fill="none" stroke="#1a1a1a" strokeWidth="2"/>
          <circle cx="24" cy="24" r="5" fill="#1a1a1a"/>
        </g>
      )}
      {/* shine */}
      <ellipse cx="18" cy="14" rx="4" ry="2.5" fill="rgba(255,255,255,0.7)"/>
    </svg>
  );
}

// ===== Tiny icons =====
function Ico({ name, size = 18, color = 'currentColor' }) {
  const s = size;
  const stroke = { stroke: color, strokeWidth: 2.2, fill: 'none', strokeLinecap: 'round', strokeLinejoin: 'round' };
  const fill = { fill: color };
  switch (name) {
    case 'trophy':
      return <svg width={s} height={s} viewBox="0 0 24 24"><path d="M6 4h12v4a6 6 0 0 1-12 0V4z" {...fill}/><path d="M3 5h3v2a3 3 0 0 0 3 3M21 5h-3v2a3 3 0 0 1-3 3" {...stroke} fill="none"/><path d="M10 14h4v4h-4z" {...fill}/><path d="M8 20h8" {...stroke}/></svg>;
    case 'flame':
      return <svg width={s} height={s} viewBox="0 0 24 24"><path d="M12 3c1 4 5 5 5 10a5 5 0 0 1-10 0c0-2 1-3 2-4 0 2 1 3 2 3-1-3 0-6 1-9z" {...fill}/></svg>;
    case 'gear':
      return <svg width={s} height={s} viewBox="0 0 24 24"><circle cx="12" cy="12" r="3" {...stroke}/><path d="M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1" {...stroke}/></svg>;
    case 'play':
      return <svg width={s} height={s} viewBox="0 0 24 24"><path d="M7 4l13 8L7 20z" {...fill}/></svg>;
    case 'home':
      return <svg width={s} height={s} viewBox="0 0 24 24"><path d="M3 11l9-8 9 8v9a1 1 0 0 1-1 1h-5v-7h-6v7H4a1 1 0 0 1-1-1z" {...fill}/></svg>;
    case 'replay':
      return <svg width={s} height={s} viewBox="0 0 24 24"><path d="M3 12a9 9 0 1 1 3 6.7" {...stroke}/><path d="M3 6v6h6" {...stroke}/></svg>;
    case 'close':
      return <svg width={s} height={s} viewBox="0 0 24 24"><path d="M5 5l14 14M19 5L5 19" {...stroke}/></svg>;
    case 'arrow-left':
      return <svg width={s} height={s} viewBox="0 0 24 24"><path d="M14 6l-6 6 6 6" {...stroke}/></svg>;
    case 'eye':
      return <svg width={s} height={s} viewBox="0 0 24 24"><path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z" {...stroke}/><circle cx="12" cy="12" r="3" {...stroke}/></svg>;
    case 'check':
      return <svg width={s} height={s} viewBox="0 0 24 24"><path d="M5 13l4 4L19 7" {...stroke}/></svg>;
    case 'music':
      return <svg width={s} height={s} viewBox="0 0 24 24"><path d="M9 18V5l12-2v13" {...stroke}/><circle cx="6" cy="18" r="3" {...fill}/><circle cx="18" cy="16" r="3" {...fill}/></svg>;
    case 'sfx':
      return <svg width={s} height={s} viewBox="0 0 24 24"><path d="M3 12h2M7 8v8M11 5v14M15 8v8M19 11v2" {...stroke}/></svg>;
    case 'cap':
      return <svg width={s} height={s} viewBox="0 0 24 24"><path d="M2 9l10-4 10 4-10 4-10-4z" {...fill}/><path d="M6 11v5a6 3 0 0 0 12 0v-5" {...stroke}/></svg>;
    case 'globe':
      return <svg width={s} height={s} viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" {...stroke}/><path d="M3 12h18M12 3a14 14 0 0 1 0 18A14 14 0 0 1 12 3z" {...stroke}/></svg>;
    case 'finger':
      return <svg width={s} height={s} viewBox="0 0 24 24"><path d="M9 11V5a2 2 0 0 1 4 0v7l3-2a2 2 0 0 1 3 1.7v3.3a6 6 0 0 1-6 6h-2a4 4 0 0 1-4-3l-2-5a1.5 1.5 0 0 1 2.6-1.4L9 13" stroke={color} strokeWidth="2" fill="rgba(255,255,255,0.1)" strokeLinejoin="round"/></svg>;
    default: return null;
  }
}

Object.assign(window, { Mascot, Cosmic, Cloud, Gem, Ico });
