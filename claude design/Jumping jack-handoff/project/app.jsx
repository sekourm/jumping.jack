/* global React, ReactDOM, HomeScreen, LobbyScreen, HudScreen, TutorialScreen, DefeatScreen, BrEndScreen, SettingsScreen, useTweaks, TweaksPanel, TweakSection, TweakRadio, TweakSelect, TweakToggle, Mascot, Ico */
const { useState, useEffect } = React;

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "screen": "home",
  "stage": "earth",
  "brMode": false,
  "spectator": false,
  "won": true,
  "lang": "fr"
}/*EDITMODE-END*/;

const I18N = {
  fr: {
    solo: 'MODE SOLO', battle: 'BATTLE ROYALE',
    searching: 'RECHERCHE DE JOUEURS', waiting: 'EN ATTENTE…', cancel: 'ANNULER',
    quit: 'QUITTER',
    tut_hold: 'MAINTIENS', tut_aim: 'VISE', tut_release: 'RELÂCHE',
    dont_show: 'Ne plus afficher', ready: 'JE SUIS PRÊT',
    best_score: 'MON MEILLEUR SCORE', replay: 'REJOUER', menu: 'MENU',
    winner: 'GAGNANT', classement: 'CLASSEMENT', new_game: 'NOUVELLE PARTIE',
    music: 'MUSIQUE', sfx: 'EFFETS', tutorial: 'TUTORIEL', tutorial_desc: 'Afficher au début de chaque partie',
    lang_label: 'LANGUE',
  },
  en: {
    solo: 'SOLO MODE', battle: 'BATTLE ROYALE',
    searching: 'SEARCHING PLAYERS', waiting: 'WAITING…', cancel: 'CANCEL',
    quit: 'QUIT',
    tut_hold: 'HOLD', tut_aim: 'AIM', tut_release: 'RELEASE',
    dont_show: "Don't show again", ready: "I'M READY",
    best_score: 'MY BEST SCORE', replay: 'REPLAY', menu: 'MENU',
    winner: 'WINNER', classement: 'RANKING', new_game: 'NEW GAME',
    music: 'MUSIC', sfx: 'EFFECTS', tutorial: 'TUTORIAL', tutorial_desc: 'Show at the start of each game',
    lang_label: 'LANGUAGE',
  },
};

const SCREENS = [
  { id: 'home', name: 'Home' },
  { id: 'lobby', name: 'Lobby' },
  { id: 'hud', name: 'HUD' },
  { id: 'tutorial', name: 'Tuto' },
  { id: 'defeat', name: 'Solo End' },
  { id: 'br_end', name: 'BR End' },
  { id: 'settings', name: 'Settings' },
];

function PhoneFrame({ children, scale = 1 }) {
  return (
    <div className="phone-scaler" style={{
      position: 'relative',
      width: 400, height: 820,
      transform: `scale(${scale})`,
      transformOrigin: 'top left',
      borderRadius: 56,
      background: 'linear-gradient(180deg, #1a1a1f 0%, #0a0a0d 100%)',
      padding: 12,
      boxShadow: '0 0 0 2px #2a2a30, 0 24px 60px rgba(0,0,0,0.6), 0 0 80px rgba(255,200,87,0.05)',
    }}>
      <div style={{
        position: 'absolute', top: 18, left: '50%', transform: 'translateX(-50%)',
        width: 110, height: 30, borderRadius: 999, background: 'black', zIndex: 100,
      }}/>
      <div style={{
        position: 'relative',
        width: '100%', height: '100%',
        borderRadius: 44,
        overflow: 'hidden',
        background: '#000',
      }}>
        {children}
      </div>
    </div>
  );
}

function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const [vol, setVol] = useState(60);
  const [sfx, setSfx] = useState(70);
  const [tutorial, setTutorial] = useState(true);
  const [localScreen, setLocalScreen] = useState(null);
  const [editMode, setEditMode] = useState(false);
  const [scale, setScale] = useState(1);

  useEffect(() => {
    const recalc = () => {
      const padX = 40;
      const padY = 140;
      const sx = (window.innerWidth - padX) / 400;
      const sy = (window.innerHeight - padY) / 820;
      setScale(Math.min(1, sx, sy));
    };
    recalc();
    window.addEventListener('resize', recalc);
    return () => window.removeEventListener('resize', recalc);
  }, []);

  useEffect(() => {
    const onMsg = (e) => {
      if (e.data?.type === '__activate_edit_mode') setEditMode(true);
      if (e.data?.type === '__deactivate_edit_mode') setEditMode(false);
    };
    window.addEventListener('message', onMsg);
    window.parent.postMessage({ type: '__edit_mode_available' }, '*');
    return () => window.removeEventListener('message', onMsg);
  }, []);

  const screen = localScreen || t.screen;
  const setScreen = (s) => setLocalScreen(s);
  const txt = I18N[t.lang] || I18N.fr;

  const onNav = (s) => setLocalScreen(s);

  let content = null;
  switch (screen) {
    case 'home': content = <HomeScreen stage={t.stage} t={txt} onNav={onNav}/>; break;
    case 'lobby': content = <LobbyScreen t={txt} onNav={onNav}/>; break;
    case 'hud': content = <HudScreen stage={t.stage} t={txt} brMode={t.brMode} spectator={t.spectator} onNav={onNav}/>; break;
    case 'tutorial': content = <TutorialScreen stage={t.stage} t={txt} onNav={onNav}/>; break;
    case 'defeat': content = <DefeatScreen t={txt} onNav={onNav}/>; break;
    case 'br_end': content = <BrEndScreen won={t.won} t={txt} onNav={onNav}/>; break;
    case 'settings': content = <SettingsScreen tutorial={tutorial} setTutorial={setTutorial} lang={t.lang} setLang={(l) => setTweak('lang', l)} vol={vol} setVol={setVol} sfx={sfx} setSfx={setSfx} t={txt} onNav={onNav}/>; break;
    default: content = <HomeScreen stage={t.stage} t={txt} onNav={onNav}/>;
  }

  return (
    <div className="stage">
      <div style={{ width: 400 * scale, height: 820 * scale, marginBottom: scale < 1 ? 16 : 0 }}>
        <PhoneFrame scale={scale}>{content}</PhoneFrame>
      </div>

      {/* Screen switcher floating below phone */}
      <div style={{ position: 'relative', display: 'flex', gap: 4, padding: 6, borderRadius: 999, background: 'rgba(20,22,30,0.85)', border: '1px solid rgba(255,255,255,0.08)', backdropFilter: 'blur(10px)', zIndex: 200, flexWrap: 'nowrap' }}>
        {SCREENS.map(s => (
          <button key={s.id} onClick={() => setScreen(s.id)} style={{
            padding: '7px 10px',
            borderRadius: 999,
            border: 'none',
            background: screen === s.id ? 'linear-gradient(180deg,#FFE198,#FFC857)' : 'transparent',
            color: screen === s.id ? '#2a1700' : 'rgba(255,255,255,0.6)',
            fontFamily: 'Manrope', fontWeight: 800, fontSize: 10, letterSpacing: '0.06em',
            cursor: 'pointer',
            textTransform: 'uppercase',
            whiteSpace: 'nowrap',
          }}>
            {s.name}
          </button>
        ))}
      </div>

      {editMode && (
        <TweaksPanel title="Tweaks">
          <TweakSection label="Vue">
            <TweakSelect label="Écran" value={t.screen} options={SCREENS.map(s => ({ label: s.name, value: s.id }))} onChange={(v) => { setTweak('screen', v); setLocalScreen(null); }}/>
            <TweakSelect label="Ambiance" value={t.stage} options={[
              { label: 'Terre', value: 'earth' },
              { label: 'Lune', value: 'moon' },
              { label: 'Mars', value: 'mars' },
              { label: 'Jupiter', value: 'jupiter' },
              { label: 'Saturne', value: 'saturn' },
              { label: 'Nébuleuse', value: 'nebula' },
            ]} onChange={(v) => setTweak('stage', v)}/>
            <TweakRadio label="Langue" value={t.lang} options={[{label:'FR',value:'fr'},{label:'EN',value:'en'}]} onChange={(v) => setTweak('lang', v)}/>
          </TweakSection>
          <TweakSection label="HUD">
            <TweakToggle label="Mode BR (leaderboard)" value={t.brMode} onChange={(v) => setTweak('brMode', v)}/>
            <TweakToggle label="Spectateur" value={t.spectator} onChange={(v) => setTweak('spectator', v)}/>
          </TweakSection>
          <TweakSection label="Fin BR">
            <TweakRadio label="Résultat" value={t.won ? 'win' : 'lose'} options={[{label:'Victoire',value:'win'},{label:'Défaite',value:'lose'}]} onChange={(v) => setTweak('won', v === 'win')}/>
          </TweakSection>
        </TweaksPanel>
      )}
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
