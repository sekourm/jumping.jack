/* global React, Mascot, Cosmic, Cloud, Gem, Ico */
const { useState: useState2 } = React;

// ============ TUTORIAL OVERLAY ============
function TutorialScreen({ stage, t, onNav }) {
  const [phase, setPhase] = useState2(0);
  const phases = [t.tut_hold, t.tut_aim, t.tut_release];
  return (
    <div className="screen-root">
      <Cosmic stage={stage}>
        {/* faint platforms behind */}
        <div style={{ position: 'absolute', left: '10%', top: '24%', opacity: 0.4 }}><Cloud w={100}/></div>
        <div style={{ position: 'absolute', left: '52%', top: '40%', opacity: 0.4 }}><Cloud w={100}/></div>
        <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.55)', backdropFilter: 'blur(4px)' }}/>
      </Cosmic>

      <div style={{ position: 'absolute', inset: 0, padding: '60px 22px 22px', display: 'flex', flexDirection: 'column', alignItems: 'center', zIndex: 10 }}>
        <div className="label" style={{ fontSize: 11, color: 'rgba(255,255,255,0.5)' }}>TUTORIEL</div>

        {/* phase tabs */}
        <div style={{ display: 'flex', gap: 6, marginTop: 14 }}>
          {phases.map((p, i) => (
            <div key={i} onClick={() => setPhase(i)} style={{ padding: '6px 12px', borderRadius: 999, background: i === phase ? 'rgba(255,200,87,0.18)' : 'rgba(255,255,255,0.06)', border: i === phase ? '1.5px solid #FFC857' : '1.5px solid rgba(255,255,255,0.1)', fontFamily: 'Bungee', fontSize: 9, letterSpacing: '0.1em', color: i === phase ? '#FFC857' : 'rgba(255,255,255,0.5)' }}>
              {String(i+1).padStart(2,'0')}
            </div>
          ))}
        </div>

        <div style={{ marginTop: 18, fontFamily: 'Bungee', fontSize: 22, letterSpacing: '0.06em', color: 'white', textAlign: 'center', textShadow: '0 2px 0 rgba(0,0,0,0.4)' }}>
          {phases[phase]}
        </div>

        {/* demo */}
        <div style={{ position: 'relative', marginTop: 32, width: 220, height: 240 }}>
          {/* platform */}
          <div style={{ position: 'absolute', bottom: 30, left: '50%', transform: 'translateX(-50%)' }}>
            <Cloud w={120}/>
          </div>
          {/* mascot */}
          <div style={{ position: 'absolute', bottom: 70, left: '50%', transform: 'translateX(-50%)' }}>
            <Mascot size={64} face={phase === 2 ? 'excited' : phase === 1 ? 'determined' : 'charge'}/>
          </div>
          {/* aim arc on phase 1 */}
          {phase === 1 && (
            <svg style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }} width="220" height="240" viewBox="0 0 220 240">
              <path d="M 110 130 Q 170 50, 200 80" stroke="#FFC857" strokeWidth="3" fill="none" strokeDasharray="4 6" strokeLinecap="round" opacity="0.8"/>
              <circle cx="200" cy="80" r="6" fill="#FFC857"/>
            </svg>
          )}
          {/* charge gauge */}
          {phase === 0 && (
            <div style={{ position: 'absolute', bottom: 6, left: '50%', transform: 'translateX(-50%)', width: 80, height: 6, borderRadius: 999, background: 'rgba(255,255,255,0.1)', border: '1px solid rgba(255,255,255,0.2)' }}>
              <div style={{ width: '70%', height: '100%', borderRadius: 999, background: 'linear-gradient(90deg,#FFE198,#FFC857,#FF5E5B)', boxShadow: '0 0 10px rgba(255,94,91,0.6)' }}/>
            </div>
          )}
          {/* finger */}
          <div style={{ position: 'absolute', bottom: 0, left: '50%', animation: 'finger-pulse 1.6s ease-in-out infinite' }}>
            <Ico name="finger" size={42} color="#FFC857"/>
          </div>
        </div>

        <div style={{ flex: 1 }}/>

        <label style={{ display: 'flex', alignItems: 'center', gap: 10, color: 'rgba(255,255,255,0.7)', fontFamily: 'Manrope', fontSize: 12, letterSpacing: '0.06em', marginBottom: 14 }}>
          <div style={{ width: 18, height: 18, borderRadius: 5, border: '2px solid rgba(255,255,255,0.4)' }}/>
          {t.dont_show}
        </label>
        <button className="fbtn primary" style={{ width: '100%' }} onClick={() => onNav('hud')}>
          <Ico name="check" size={18} color="#2a1700"/>
          <span>{t.ready}</span>
        </button>
      </div>
    </div>
  );
}

// ============ DEFEAT SOLO ============
function DefeatScreen({ t, onNav }) {
  return (
    <div className="screen-root">
      <Cosmic stage="dark">
        <div style={{ position: 'absolute', inset: 0, padding: '60px 22px 22px', display: 'flex', flexDirection: 'column' }}>
          <div style={{ textAlign: 'center', marginTop: 14 }}>
            <div className="logo-end gold">TERMINÉ</div>
          </div>

          <div style={{ marginTop: 18, textAlign: 'center' }}>
            <div className="ribbon" style={{ fontSize: 12 }}>★ NOUVEAU RECORD ★</div>
          </div>

          <div className="card gold" style={{ marginTop: 18, textAlign: 'center', padding: '20px 16px' }}>
            <div className="label" style={{ color: 'rgba(255,255,255,0.55)', fontSize: 10 }}>SCORE</div>
            <div className="dot-num" style={{ fontSize: 72, marginTop: 6 }}>5990</div>
            <div className="label" style={{ marginTop: 8, color: '#7AE091', fontSize: 10 }}>+ 378 VS RECORD</div>
          </div>

          <div className="card" style={{ marginTop: 14, display: 'flex', alignItems: 'center', gap: 12, padding: '14px 16px' }}>
            <div style={{ width: 36, height: 36, borderRadius: 10, background: 'rgba(255,200,87,0.18)', display: 'grid', placeItems: 'center' }}>
              <Ico name="trophy" size={18} color="#FFC857"/>
            </div>
            <div className="label" style={{ flex: 1, color: 'rgba(255,255,255,0.7)', fontSize: 11 }}>{t.best_score}</div>
            <div className="num" style={{ fontSize: 22, color: '#FFC857' }}>5612</div>
          </div>

          {/* pickups summary */}
          <div className="card" style={{ marginTop: 12, padding: 14 }}>
            <div className="label" style={{ fontSize: 10, color: 'rgba(255,255,255,0.5)', marginBottom: 10 }}>PICKUPS</div>
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              {['star','crystal','heart','vision','teleport'].map((g,i) => (
                <div key={i} style={{ textAlign: 'center' }}>
                  <Gem kind={g} size={28}/>
                  <div className="num" style={{ fontSize: 12, color: 'white', marginTop: 4 }}>{[5,2,1,3,0][i]}</div>
                </div>
              ))}
            </div>
          </div>

          <div style={{ flex: 1 }}/>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            <button className="fbtn primary" onClick={() => onNav('hud')}>
              <Ico name="replay" size={18} color="#2a1700"/>
              <span>{t.replay}</span>
            </button>
            <button className="fbtn cyan" onClick={() => onNav('home')}>
              <Ico name="home" size={18} color="#082040"/>
              <span>{t.menu}</span>
            </button>
          </div>
        </div>
      </Cosmic>
    </div>
  );
}

Object.assign(window, { TutorialScreen, DefeatScreen });
