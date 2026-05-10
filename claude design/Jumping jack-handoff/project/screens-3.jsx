/* global React, Mascot, Cosmic, Cloud, Gem, Ico */

// ============ BR END ============
function BrEndScreen({ won, t, onNav }) {
  const ranking = [
    { rank: 1, name: 'JACK_3600', score: 5990, dead: false, me: won, color: '#FFD24A' },
    { rank: 2, name: 'BOT_4421', score: 4720, dead: true, me: !won, color: '#C0C8D2' },
    { rank: 3, name: 'JACK_2841', score: 3380, dead: true, color: '#C18A4F' },
    { rank: 4, name: 'BOT_8123', score: 2210, dead: true, color: '#7E889A' },
    { rank: 5, name: 'JACK_7755', score: 1090, dead: true, color: '#7E889A' },
  ];
  return (
    <div className="screen-root">
      <Cosmic stage={won ? 'nebula' : 'dark'}>
        <div style={{ position: 'absolute', inset: 0, padding: '50px 20px 22px', display: 'flex', flexDirection: 'column' }}>
          <div style={{ textAlign: 'center' }}>
            <div className={`logo-end ${won ? 'gold' : 'purple'}`} style={{ fontSize: won ? 52 : 48 }}>
              {won ? 'VICTOIRE !' : 'TERMINÉ'}
            </div>
          </div>

          {/* Winner portrait */}
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 14, marginTop: 16 }}>
            <div style={{ position: 'relative', filter: 'drop-shadow(0 0 24px rgba(255,200,87,0.5))' }}>
              <Mascot size={92} face={won ? 'excited' : 'smile'}/>
              <div style={{ position: 'absolute', top: -10, right: -10, width: 28, height: 28, borderRadius: '50%', background: 'linear-gradient(180deg,#FFE198,#C8861A)', border: '2px solid #7A4A00', display: 'grid', placeItems: 'center', fontFamily: 'Bungee', fontSize: 13, color: '#2a1700' }}>1</div>
            </div>
            <div>
              <div className="label" style={{ color: 'rgba(255,255,255,0.5)', fontSize: 9 }}>{t.winner}</div>
              <div style={{ fontFamily: 'Bungee', fontSize: 20, color: 'white', letterSpacing: '0.04em' }}>{ranking[0].name}</div>
              <div className="num" style={{ fontSize: 26, color: '#FFC857', marginTop: 2 }}>{ranking[0].score}</div>
            </div>
          </div>

          {/* Ranking */}
          <div className="card" style={{ marginTop: 16, padding: 12 }}>
            <div className="label" style={{ fontSize: 10, color: 'rgba(255,255,255,0.5)', marginBottom: 8 }}>{t.classement}</div>
            {ranking.map((r) => (
              <div key={r.rank} className={`lb-row ${r.me ? 'me' : ''} ${r.dead ? 'dead' : ''}`}>
                <div style={{ width: 22, height: 22, borderRadius: 6, background: r.rank <= 3 ? r.color : 'rgba(255,255,255,0.1)', display: 'grid', placeItems: 'center', fontFamily: 'Bungee', fontSize: 11, color: r.rank <= 3 ? '#1a1a1a' : 'rgba(255,255,255,0.6)' }}>{r.rank}</div>
                <div className="name" style={{ flex: 1, fontFamily: 'Bungee', fontSize: 12, color: 'white', letterSpacing: '0.04em' }}>{r.name}</div>
                {r.me && <div style={{ padding: '2px 8px', borderRadius: 5, border: '1.5px solid #FFC857', color: '#FFC857', fontFamily: 'Bungee', fontSize: 9 }}>TOI</div>}
                <div className="num" style={{ fontSize: 14, color: 'white' }}>{r.score}</div>
              </div>
            ))}
          </div>

          <div style={{ flex: 1 }}/>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            <button className="fbtn epic" onClick={() => onNav('lobby')}>
              <Ico name="flame" size={16} color="white"/>
              <span>{t.new_game}</span>
            </button>
            <button className="fbtn cyan" onClick={() => onNav('home')}>
              <Ico name="home" size={16} color="#082040"/>
              <span>{t.menu}</span>
            </button>
          </div>
        </div>
      </Cosmic>
    </div>
  );
}

// ============ SETTINGS ============
function SettingsScreen({ tutorial, setTutorial, lang, setLang, vol, setVol, sfx, setSfx, t, onNav }) {
  return (
    <div className="screen-root">
      <Cosmic stage="earth">
        <div style={{ position: 'absolute', inset: 0, padding: '50px 20px 22px', overflowY: 'auto' }}>
          <div className="icon-round-btn" onClick={() => onNav('home')}>
            <Ico name="arrow-left" size={20} color="white"/>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 22 }}>
            <div style={{ width: 4, height: 16, background: '#FFC857', borderRadius: 2 }}/>
            <div className="label" style={{ fontSize: 12, color: 'white' }}>AUDIO</div>
          </div>

          {/* music */}
          <div className="card" style={{ marginTop: 12, padding: 14, display: 'flex', alignItems: 'center', gap: 14 }}>
            <div style={{ width: 44, height: 44, borderRadius: 12, background: 'rgba(255,200,87,0.12)', border: '1.5px solid #FFC857', display: 'grid', placeItems: 'center' }}>
              <Ico name="music" size={20} color="#FFC857"/>
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
                <div className="label" style={{ fontSize: 11, color: 'white' }}>{t.music}</div>
                <div style={{ padding: '3px 10px', borderRadius: 999, border: '1.5px solid #FFC857', fontFamily: 'Bungee', fontSize: 10, color: '#FFC857' }}>{vol}%</div>
              </div>
              <div className="slider-track" onClick={(e) => {
                const r = e.currentTarget.getBoundingClientRect();
                setVol(Math.round(((e.clientX - r.left) / r.width) * 100));
              }}>
                <div className="slider-fill" style={{ width: `${vol}%` }}/>
                <div className="slider-thumb" style={{ left: `${vol}%` }}/>
              </div>
            </div>
          </div>

          {/* sfx */}
          <div className="card" style={{ marginTop: 10, padding: 14, display: 'flex', alignItems: 'center', gap: 14 }}>
            <div style={{ width: 44, height: 44, borderRadius: 12, background: 'rgba(255,200,87,0.12)', border: '1.5px solid #FFC857', display: 'grid', placeItems: 'center' }}>
              <Ico name="sfx" size={20} color="#FFC857"/>
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
                <div className="label" style={{ fontSize: 11, color: 'white' }}>{t.sfx}</div>
                <div style={{ padding: '3px 10px', borderRadius: 999, border: '1.5px solid #FFC857', fontFamily: 'Bungee', fontSize: 10, color: '#FFC857' }}>{sfx}%</div>
              </div>
              <div className="slider-track" onClick={(e) => {
                const r = e.currentTarget.getBoundingClientRect();
                setSfx(Math.round(((e.clientX - r.left) / r.width) * 100));
              }}>
                <div className="slider-fill" style={{ width: `${sfx}%` }}/>
                <div className="slider-thumb" style={{ left: `${sfx}%` }}/>
              </div>
            </div>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 22 }}>
            <div style={{ width: 4, height: 16, background: '#FFC857', borderRadius: 2 }}/>
            <div className="label" style={{ fontSize: 12, color: 'white' }}>JEU</div>
          </div>

          <div className="card" style={{ marginTop: 12, padding: 14, display: 'flex', alignItems: 'center', gap: 14 }}>
            <div style={{ width: 44, height: 44, borderRadius: 12, background: 'rgba(255,200,87,0.12)', border: '1.5px solid #FFC857', display: 'grid', placeItems: 'center' }}>
              <Ico name="cap" size={20} color="#FFC857"/>
            </div>
            <div style={{ flex: 1 }}>
              <div className="label" style={{ fontSize: 11, color: 'white', marginBottom: 4 }}>{t.tutorial}</div>
              <div style={{ fontSize: 11, color: 'rgba(255,255,255,0.5)' }}>{t.tutorial_desc}</div>
            </div>
            <div className={`tgl ${tutorial ? 'on' : ''}`} onClick={() => setTutorial(!tutorial)}>
              <div className="tgl-knob"/>
            </div>
          </div>

          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 22 }}>
            <div style={{ width: 4, height: 16, background: '#FFC857', borderRadius: 2 }}/>
            <div className="label" style={{ fontSize: 12, color: 'white' }}>{t.lang_label}</div>
          </div>

          <div className="card" style={{ marginTop: 12, padding: 14, display: 'flex', alignItems: 'center', gap: 14 }}>
            <div style={{ width: 44, height: 44, borderRadius: 12, background: 'rgba(255,200,87,0.12)', border: '1.5px solid #FFC857', display: 'grid', placeItems: 'center' }}>
              <Ico name="globe" size={20} color="#FFC857"/>
            </div>
            <div style={{ display: 'flex', gap: 10, flex: 1 }}>
              {['fr', 'en'].map((l) => {
                const active = lang === l;
                return (
                  <div key={l} onClick={() => setLang(l)} style={{ position: 'relative', cursor: 'pointer' }}>
                    <Flag code={l} active={active}/>
                    <div style={{ marginTop: 4, textAlign: 'center', fontFamily: 'Bungee', fontSize: 9, letterSpacing: '0.1em', color: active ? '#FFC857' : 'rgba(255,255,255,0.4)' }}>{l.toUpperCase()}</div>
                    {active && (
                      <div style={{ position: 'absolute', top: -6, right: -6, width: 18, height: 18, borderRadius: '50%', background: '#FFC857', border: '2px solid #7A4A00', display: 'grid', placeItems: 'center' }}>
                        <Ico name="check" size={12} color="#2a1700"/>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </div>

          <div style={{ height: 40 }}/>
        </div>
      </Cosmic>
    </div>
  );
}

function Flag({ code, active }) {
  const ring = active ? '#FFC857' : 'rgba(255,255,255,0.18)';
  if (code === 'fr') {
    return (
      <svg width="48" height="32" viewBox="0 0 48 32" style={{ borderRadius: 6, filter: active ? 'drop-shadow(0 0 8px rgba(255,200,87,0.5))' : 'none' }}>
        <rect x="1" y="1" width="46" height="30" rx="4" fill="#0055A4"/>
        <rect x="16" y="1" width="16" height="30" fill="white"/>
        <rect x="32" y="1" width="15" height="30" rx="0" fill="#EF4135"/>
        <rect x="32" y="1" width="15" height="30" fill="#EF4135"/>
        <path d="M 1 5 Q 1 1 5 1 H 43 Q 47 1 47 5 V 27 Q 47 31 43 31 H 5 Q 1 31 1 27 Z" fill="none" stroke={ring} strokeWidth="2"/>
      </svg>
    );
  }
  return (
    <svg width="48" height="32" viewBox="0 0 48 32" style={{ borderRadius: 6, filter: active ? 'drop-shadow(0 0 8px rgba(255,200,87,0.5))' : 'none' }}>
      <rect x="1" y="1" width="46" height="30" rx="4" fill="#012169"/>
      <path d="M1 1 L47 31 M47 1 L1 31" stroke="white" strokeWidth="4"/>
      <path d="M1 1 L47 31 M47 1 L1 31" stroke="#C8102E" strokeWidth="2"/>
      <path d="M24 1 V31 M1 16 H47" stroke="white" strokeWidth="6"/>
      <path d="M24 1 V31 M1 16 H47" stroke="#C8102E" strokeWidth="3"/>
      <rect x="1" y="1" width="46" height="30" rx="4" fill="none" stroke={ring} strokeWidth="2"/>
    </svg>
  );
}

Object.assign(window, { BrEndScreen, SettingsScreen });
