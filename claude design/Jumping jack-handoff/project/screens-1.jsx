/* global React, Mascot, Cosmic, Cloud, Gem, Ico */
const { useState } = React;

// ============ HOME ============
function HomeScreen({ stage, t, onNav }) {
  return (
    <div className="screen-root">
      <Cosmic stage={stage}>
        {/* Top chips */}
        <div style={{ position: 'absolute', top: 14, left: 14, display: 'flex', gap: 8, zIndex: 5 }}>
          <div className="chip">
            <div className="ico-wrap"><Ico name="trophy" size={16} color="#FFC857"/></div>
            <div className="meta"><span className="k">Score</span><span className="v">5612</span></div>
          </div>
          <div className="chip purple">
            <div className="ico-wrap"><Ico name="flame" size={16} color="#D896FF"/></div>
            <div className="meta"><span className="k">BR</span><span className="v">3</span></div>
          </div>
        </div>
        <div style={{ position: 'absolute', top: 14, right: 14, zIndex: 5 }}>
          <div className="icon-round-btn" onClick={() => onNav('settings')}><Ico name="gear" size={20} color="white"/></div>
        </div>

        {/* Logo + mascot */}
        <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', paddingTop: 20 }}>
          <div style={{ animation: 'float 3s ease-in-out infinite', marginBottom: 4 }}>
            <Mascot size={84} face="smile"/>
          </div>
          <div className="logo-jj" style={{ marginTop: 10, fontSize: 56, lineHeight: 0.95 }}>
            JUMPING<br/>JACK
          </div>
        </div>

        {/* Buttons */}
        <div style={{ position: 'absolute', bottom: 56, left: 22, right: 22, display: 'flex', flexDirection: 'column', gap: 16 }}>
          <button className="fbtn primary" onClick={() => onNav('hud')}>
            <Ico name="play" size={18} color="#2a1700"/>
            <span>{t.solo}</span>
          </button>
          <button className="fbtn epic" onClick={() => onNav('lobby')}>
            <Ico name="flame" size={18} color="white"/>
            <span>{t.battle}</span>
          </button>
        </div>
        <div style={{ position: 'absolute', bottom: 14, right: 14, fontSize: 10, color: 'rgba(255,255,255,0.3)', letterSpacing: '0.16em', fontWeight: 800 }}>v2.0</div>
      </Cosmic>
    </div>
  );
}

// ============ LOBBY BR ============
function LobbyScreen({ t, onNav }) {
  const slots = [
    { name: 'JACK_3600', tag: 'TOI', color: '#FFC857', online: true },
    { name: 'JACK_BOT_4421', tag: 'BOT', color: '#7CC0FF', online: true },
    { name: 'JACK_2841', tag: '', color: '#7AE091', online: true },
    { name: '...', tag: '', color: '#666', online: false },
    { name: '...', tag: '', color: '#666', online: false },
  ];
  return (
    <div className="screen-root">
      <Cosmic stage="battle">
        <div style={{ position: 'absolute', inset: 0, padding: '60px 20px 20px', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
          <div className="logo-br" style={{ fontSize: 36 }}>BATTLE ROYALE</div>
          <div className="label" style={{ marginTop: 22, color: '#D896FF', fontSize: 11 }}>{t.searching}</div>
          <div style={{ marginTop: 18, position: 'relative' }}>
            <div className="num" style={{ fontSize: 80, color: 'white', filter: 'drop-shadow(0 0 22px rgba(177,75,255,0.7))', lineHeight: 1 }}>8</div>
          </div>
          <div className="label" style={{ color: 'rgba(255,255,255,0.4)', fontSize: 10, marginTop: -4 }}>3 / 5</div>

          <div className="card purple" style={{ width: '100%', marginTop: 22, padding: 14 }}>
            {slots.map((s, i) => (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '11px 6px', borderBottom: i < 4 ? '1px solid rgba(255,255,255,0.05)' : 'none' }}>
                <div style={{ width: 12, height: 12, borderRadius: '50%', background: s.online ? s.color : 'rgba(255,255,255,0.18)', boxShadow: s.online ? `0 0 12px ${s.color}` : 'none' }}/>
                <div style={{ flex: 1, fontFamily: 'Bungee', fontSize: 14, color: s.online ? 'white' : 'rgba(255,255,255,0.3)', letterSpacing: '0.04em' }}>
                  {s.online ? s.name : t.waiting}
                </div>
                {s.tag && (
                  <div style={{
                    padding: '3px 10px', borderRadius: 6,
                    border: `1.5px solid ${s.tag === 'TOI' ? '#FFC857' : '#7CC0FF'}`,
                    color: s.tag === 'TOI' ? '#FFC857' : '#7CC0FF',
                    fontFamily: 'Bungee', fontSize: 10, letterSpacing: '0.1em',
                  }}>{s.tag}</div>
                )}
              </div>
            ))}
          </div>

          <div style={{ flex: 1 }}/>
          <button className="fbtn cyan" onClick={() => onNav('home')} style={{ width: '100%' }}>
            <Ico name="close" size={18} color="#082040"/>
            <span>{t.cancel}</span>
          </button>
        </div>
      </Cosmic>
    </div>
  );
}

// ============ HUD (game) ============
function HudScreen({ stage, t, brMode = false, spectator = false, onNav }) {
  const platforms = [
    { x: 6, y: 18, kind: 'standard', cracked: false },
    { x: 60, y: 30, kind: 'standard' },
    { x: 16, y: 46, kind: 'moving' },
    { x: 8, y: 62, kind: 'standard', cracked: true },
    { x: 58, y: 58, kind: 'bouncy' },
    { x: 26, y: 78, kind: 'standard' },
  ];
  return (
    <div className="screen-root">
      <Cosmic stage={stage}>
        {/* Score dot-matrix */}
        {!spectator && (
          <div style={{ position: 'absolute', top: 60, left: 0, right: 0, textAlign: 'center', zIndex: 4 }}>
            <div className="label" style={{ color: 'rgba(255,255,255,0.5)', fontSize: 10 }}>SCORE</div>
            <div className="dot-num" style={{ marginTop: 4 }}>490</div>
          </div>
        )}

        {/* Combo */}
        {!spectator && (
          <div style={{ position: 'absolute', top: 168, left: 0, right: 0, textAlign: 'center', zIndex: 4 }}>
            <div style={{ display: 'inline-flex', alignItems: 'center', gap: 6, fontFamily: 'Bungee', letterSpacing: '0.08em' }}>
              <span style={{ color: '#FFC857', fontSize: 22 }}>2</span>
              <span style={{ color: 'white', fontSize: 11, letterSpacing: '0.2em' }}>COMBO</span>
              <span style={{ color: '#FF5E5B', fontSize: 13 }}>×1.15</span>
            </div>
            <div style={{ width: 96, height: 4, margin: '6px auto 0', background: 'rgba(255,255,255,0.1)', borderRadius: 999 }}>
              <div style={{ width: '60%', height: '100%', background: 'linear-gradient(90deg, #FFE198, #FFC857)', borderRadius: 999, boxShadow: '0 0 10px rgba(255,200,87,0.7)' }}/>
            </div>
          </div>
        )}

        {/* BR leaderboard top right */}
        {brMode && !spectator && (
          <div style={{ position: 'absolute', top: 12, right: 12, zIndex: 4, width: 152 }}>
            <div className="card purple" style={{ padding: 8, fontSize: 10 }}>
              <div className="label" style={{ fontSize: 8, color: '#D896FF', marginBottom: 4 }}>VIVANTS · 4/5</div>
              {[
                { d: '#FFC857', n: 'JACK_3600', s: 490, me: true, dead: false },
                { d: '#7CC0FF', n: 'BOT_4421', s: 720, dead: false },
                { d: '#7AE091', n: 'JACK_2841', s: 380, dead: false },
                { d: '#B14BFF', n: 'BOT_8123', s: 210, dead: false },
                { d: '#FF5E5B', n: 'JACK_7755', s: 0, dead: true },
              ].map((r, i) => (
                <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '3px 0', opacity: r.dead ? 0.45 : 1 }}>
                  <div style={{ width: 7, height: 7, borderRadius: '50%', background: r.d }}/>
                  <div style={{ flex: 1, fontFamily: 'Bungee', fontSize: 9, color: r.me ? '#FFC857' : 'white', textDecoration: r.dead ? 'line-through' : 'none', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{r.n}</div>
                  <div className="num" style={{ fontSize: 10, color: 'white' }}>{r.s}</div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* spectator badge */}
        {spectator && (
          <div style={{ position: 'absolute', top: 60, left: 14, zIndex: 5, display: 'flex', alignItems: 'center', gap: 8, padding: '8px 12px', background: 'rgba(177,75,255,0.18)', border: '2px solid #B14BFF', borderRadius: 14, backdropFilter: 'blur(8px)' }}>
            <Ico name="eye" size={18} color="#D896FF"/>
            <div style={{ fontFamily: 'Bungee', fontSize: 12, color: 'white', letterSpacing: '0.06em' }}>SPECTATEUR · 3</div>
          </div>
        )}

        {/* Platforms */}
        {platforms.map((p, i) => (
          <div key={i} style={{ position: 'absolute', left: `${p.x}%`, top: `${p.y}%`, zIndex: 2 }}>
            <Cloud kind={p.kind} cracked={p.cracked} w={110}/>
          </div>
        ))}

        {/* Mascot */}
        {!spectator && (
          <div style={{ position: 'absolute', left: '36%', top: '54%', zIndex: 3, animation: 'float 1.2s ease-in-out infinite' }}>
            <Mascot size={56} face="excited"/>
          </div>
        )}

        {/* +score popup */}
        {!spectator && (
          <div style={{ position: 'absolute', right: '26%', top: '46%', zIndex: 3, fontFamily: 'Bungee', color: '#FFC857', fontSize: 22, textShadow: '0 0 16px rgba(255,200,87,0.8), 0 2px 0 #7A4A00' }}>+310</div>
        )}

        {/* Pickups */}
        <div style={{ position: 'absolute', left: '70%', top: '52%', animation: 'float 2s ease-in-out infinite' }}><Gem kind="star" size={28}/></div>
        <div style={{ position: 'absolute', left: '20%', top: '38%', animation: 'float 2.4s ease-in-out infinite' }}><Gem kind="crystal" size={26}/></div>

        {/* Spectator quit btn */}
        {spectator && (
          <div style={{ position: 'absolute', bottom: 24, left: '50%', transform: 'translateX(-50%)', zIndex: 5 }}>
            <button className="fbtn cyan" style={{ width: 220, height: 52, fontSize: 16 }} onClick={() => onNav('home')}>
              <Ico name="close" size={16} color="#082040"/>
              <span>{t.quit}</span>
            </button>
          </div>
        )}

        {/* tap to die */}
        {!spectator && (
          <div onClick={() => onNav(brMode ? 'br_end' : 'defeat')} style={{ position: 'absolute', inset: 0, zIndex: 1, cursor: 'pointer' }}/>
        )}
      </Cosmic>
    </div>
  );
}

Object.assign(window, { HomeScreen, LobbyScreen, HudScreen });
