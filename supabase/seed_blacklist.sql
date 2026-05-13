-- ============================================================
-- seed_blacklist.sql
-- Populates `br_name_blacklist` with the substring patterns used
-- by `set_player_name` to reject inappropriate / impersonating
-- pseudos. Patterns are stored lower-cased; the RPC lowercases
-- the candidate before the LIKE '%pattern%' match.
--
-- Coverage:
--   • English profanity, slurs, sexual / explicit, hate symbols,
--     self-harm prompts
--   • French profanity, slurs, common abbreviations (ntm, fdp,
--     vtff, etc.), sexual explicit
--   • Common l33t-speak variants of the worst slurs (n1gger, f4g,
--     sh1t, …) so the obvious bypass attempts get caught
--   • Reserved / impersonation (admin, staff, support, owner, …)
--   • Spam / scam vocabulary (onlyfans, viagra, casino, …)
--
-- Note on false positives — the match is plain substring without
-- word boundaries, so e.g. `nique` will reject "Unique" or
-- "Technique". This is an explicit trade-off: the wins (blocking
-- the offensive intent) outweigh the cost (the rare user has to
-- pick a different pseudo).
--
-- Idempotent: `ON CONFLICT DO NOTHING` makes re-running this file
-- a no-op against an already-seeded table. To add a pattern,
-- append a line and re-run — no need to wipe first.
-- ============================================================

INSERT INTO br_name_blacklist (pattern) VALUES
  -- =====================================================
  -- ENGLISH — profanity
  -- =====================================================
  ('fuck'), ('fucker'), ('fucking'), ('fucked'), ('fck'),
  ('mthrfck'), ('motherfuck'), ('motherfucker'), ('mthrfucker'),
  ('shit'), ('shitty'), ('shithead'), ('shitbag'), ('bullshit'),
  ('horseshit'), ('dumbshit'), ('dipshit'), ('shite'),
  ('bitch'), ('bitches'), ('bitchass'), ('sonofabitch'),
  ('cunt'), ('cuntface'),
  ('asshole'), ('arsehole'), ('asswipe'), ('asscrack'),
  ('dumbass'), ('jackass'), ('smartass'), ('asshat'), ('asshat'),
  ('bastard'), ('bastards'),
  ('damn'), ('goddamn'), ('goddam'),
  ('crap'), ('crappy'),
  ('piss'), ('pissed'), ('pissoff'), ('pissant'),
  ('twat'), ('wanker'), ('tosser'),
  ('douche'), ('douchebag'),
  ('dickhead'), ('dickface'), ('dickwad'), ('prick'),
  ('jerkoff'), ('jackoff'),
  ('skank'), ('scumbag'), ('scumlord'),
  ('moron'), ('imbecile'), ('cretin'),
  -- =====================================================
  -- ENGLISH — sexual / explicit
  -- =====================================================
  ('pussy'), ('cock'), ('dick'), ('penis'), ('vagina'),
  ('boobs'), ('tits'), ('titties'), ('nipples'),
  ('porn'), ('porno'), ('xxx'), ('nsfw'), ('hentai'),
  ('horny'), ('orgasm'), ('cumshot'), ('jizz'), ('cumdump'),
  ('blowjob'), ('handjob'), ('rimjob'), ('footjob'),
  ('dildo'), ('vibrator'), ('fleshlight'),
  ('masturb'), ('onanism'), ('bukkake'),
  ('milf'), ('dilf'), ('gilf'),
  ('nudes'), ('camgirl'), ('camboy'),
  ('escort'), ('hooker'),
  ('whore'), ('slut'), ('hoe'), ('thot'),
  -- =====================================================
  -- ENGLISH — slurs
  -- =====================================================
  ('nigger'), ('nigga'), ('niggr'), ('niglet'),
  ('faggot'), ('fagot'), ('faget'), ('faggit'),
  ('fag'),
  ('kike'), ('yid'),
  ('chink'), ('gook'), ('jap'),
  ('spic'), ('wetback'), ('beaner'),
  ('towelhead'), ('raghead'), ('sandnigger'), ('camelfucker'),
  ('tranny'), ('shemale'), ('hetook'),
  ('retard'), ('retarded'), ('autist'), ('mongoloid'),
  ('spastic'), ('cripple'),
  ('coon'),
  ('midget'),
  ('gypsy'), ('gypo'),
  ('pikey'),
  -- =====================================================
  -- ENGLISH — l33t variants of the worst slurs
  -- =====================================================
  ('n1gger'), ('n1gga'), ('niggur'), ('n1ggr'),
  ('f4ggot'), ('f4got'), ('phaggot'), ('phag'), ('ph4g'),
  ('k1ke'),
  ('ch1nk'),
  ('sh1t'), ('sh!t'),
  ('b1tch'), ('b!tch'),
  ('fvck'), ('fuk'), ('phuk'), ('phuck'),
  ('c0ck'),
  ('p3do'), ('p3edo'), ('pedo'), ('paedo'),
  -- =====================================================
  -- ENGLISH — hate, extremism, terrorism
  -- =====================================================
  ('hitler'), ('heilhitler'), ('seigheil'), ('sieghei'),
  ('nazi'), ('neonazi'),
  ('kkk'), ('whitepower'), ('blackpower'), ('skinhead'),
  ('1488'), ('14words'),
  ('isis'), ('daesh'), ('terrorist'), ('alqaeda'), ('alqaida'),
  ('jihad'), ('jihadi'),
  ('boko'),
  ('genocide'), ('holocaust'), ('holohoax'),
  -- =====================================================
  -- ENGLISH — sexual abuse / pedophilia
  -- =====================================================
  ('rape'), ('rapist'), ('molest'), ('molester'),
  ('pedophile'), ('pederast'),
  ('childporn'), ('cporn'), ('childmolest'),
  ('loli'), ('lolicon'), ('shota'), ('shotacon'),
  ('zoophil'), ('bestiality'),
  -- =====================================================
  -- ENGLISH — self-harm / suicide encouragement
  -- =====================================================
  ('kys'), ('kms'), ('killyourself'), ('killmyself'),
  ('suicide'), ('hangyourself'),
  ('cutters'), ('selfharm'),
  -- =====================================================
  -- FRENCH — profanité de base
  -- =====================================================
  ('connard'), ('connasse'), ('connards'), ('connasses'),
  ('encule'), ('enculé'), ('enculer'), ('enculée'),
  ('enculation'), ('enculeur'), ('enculeuse'),
  ('pute'), ('putain'), ('putes'), ('putain'), ('putasserie'),
  ('puta'), ('putita'),
  ('salope'), ('salopes'), ('salaud'), ('salopard'),
  ('grosvache'), ('grossepute'),
  ('chiotte'), ('chiottes'),
  ('chier'), ('chieur'), ('chieuse'), ('chiant'), ('chiante'),
  ('merde'), ('merdique'), ('merdeux'), ('merdier'), ('merdouille'),
  ('emmerde'), ('emmerdant'), ('emmerdeur'), ('emmerdement'),
  ('foutre'), ('foutu'), ('foutue'), ('foutrement'),
  ('bordel'), ('bordélique'), ('bordelique'),
  ('couille'), ('couilles'), ('couillon'), ('couillonne'),
  ('bite'), ('biter'), ('bitte'),
  ('chatte'),
  ('teub'), ('teubé'), ('teubeu'),
  ('zob'), ('zboub'),
  ('queutard'), ('queutarde'),
  ('cassos'), ('claqué'), ('claqu3'),
  ('bouffon'), ('bouffonne'), ('bouffons'),
  ('branleur'), ('branleuse'), ('branlette'), ('branler'),
  ('raclure'), ('charogne'), ('ordure'), ('crevure'),
  ('batard'), ('bâtard'), ('batards'), ('bâtards'),
  ('saloperie'), ('saletés'), ('saleté'),
  ('plouc'), ('clochard'),
  ('debilemental'), ('debile'), ('débile'),
  ('cretin'), ('crétin'),
  -- =====================================================
  -- FRENCH — slurs racistes / xénophobes
  -- =====================================================
  ('bougnoul'), ('bougnoule'), ('bougnouls'),
  ('negre'), ('nègre'), ('négro'), ('negro'), ('négros'),
  ('youpin'), ('youpine'),
  ('chinetoque'), ('chinetoc'),
  ('boche'),
  ('rital'),
  ('niakoue'), ('niakoué'),
  ('feuj'),
  ('kebla'),
  ('renoi'),
  ('crouille'),
  -- =====================================================
  -- FRENCH — slurs homophobes / transphobes
  -- =====================================================
  ('pédé'), ('pede'), ('pédés'), ('pedes'),
  ('pédale'), ('pedale'), ('pédales'), ('pedales'),
  ('tarlouze'), ('tafiole'), ('tantouze'),
  ('pétasse'), ('petasse'), ('pétasses'),
  ('grognasse'), ('grognasses'),
  ('travelo'),
  -- =====================================================
  -- FRENCH — abréviations / argot offensant
  -- =====================================================
  ('ntm'), ('ntmm'), ('ntmtg'),
  ('fdp'), ('filsdepute'), ('fildepute'),
  ('vtff'), ('vatefairefoutre'), ('vafaire'),
  ('ftgueule'), ('fermeta'),
  ('jenrien'),
  ('tdm'), ('vtm'),
  ('mortde'), ('mortauxgays'),
  ('niktamere'), ('nikta'), ('niktes'), ('niquer'),
  ('nique'), ('niquons'), ('niqua'),
  ('ducon'), ('petitcon'),
  ('grosbatard'),
  ('flicaille'),
  -- =====================================================
  -- FRENCH — sexuel explicite
  -- =====================================================
  ('fellation'), ('sodomie'), ('sodomis'),
  ('orgie'), ('orgies'),
  ('partouze'), ('partouz'),
  ('gangbang'),
  ('inceste'),
  -- =====================================================
  -- DRUGS — common drug names that don't fit a pseudo
  -- =====================================================
  ('cocaine'), ('cocaïne'), ('coke'),
  ('heroin'), ('héroïne'), ('heroine'), ('smack'),
  ('crystalmeth'), ('crackhead'),
  ('marijuana'),
  ('420blaze'),
  ('molly'), ('mdma'), ('ecstasy'), ('lsdtrip'),
  -- =====================================================
  -- RESERVED / IMPERSONATION
  -- =====================================================
  ('admin'), ('administrator'), ('administrat'),
  ('moderator'), ('moderateur'), ('modérateur'), ('modos'),
  ('support'), ('staff'), ('helpdesk'),
  ('jumpingjack'), ('jacksupport'), ('jackofficial'),
  ('system'), ('sysadmin'), ('sysop'),
  ('root'), ('superuser'),
  ('officiel'), ('official'),
  ('developer'), ('developpeur'), ('développeur'), ('dev_'),
  ('owner'), ('founder'), ('cofounder'),
  ('gamemaster'), ('gmaster'),
  ('verified'), ('vérifié'),
  -- =====================================================
  -- SPAM / SCAM
  -- =====================================================
  ('onlyfans'), ('xxxonly'),
  ('viagra'), ('cialis'),
  ('casino'), ('jackpot'), ('paripot'),
  ('telegramme'), ('whatsappme'),
  ('cryptopromo'), ('bitcoinfree'),
  ('freevbucks'), ('freegold')
ON CONFLICT (pattern) DO NOTHING;
