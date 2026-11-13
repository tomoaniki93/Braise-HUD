# Braise - le HUD qui respire

Un halo de combat animé pour **WoW : Forever** (interface 16001). Autonome : aucune dépendance, fonctionne seul ou à côté de TomoModForever.

## Ce que ça fait

- **Halo** : deux arcs fins autour du personnage (vie à gauche, ressource à droite) et deux anneaux qui tournent en sens inverse.
- **Cible** : deux arcs extérieurs, vie à gauche et ressource à droite (couleur de classe ou de réaction, nom au-dessus du halo). Ils glissent en place à la prise de cible ; l'arc de ressource disparaît pour les cibles qui n'en ont pas.
- **Incantations** : ton sort referme le cercle par le bas, celui de la cible est un second arc juste dessous, avec le nom du sort ; flash à la réussite, rouge à l'interruption.
- **Menace** : en groupe ou avec un familier, une jauge en haut du halo passe du vert au rouge quand tu montes sur la liste de menace de la cible ; option « Je suis tank » pour la lire dans l'autre sens.
- **Points de combo** : des pastilles en arc sous le personnage, qui éclatent à chaque point et pulsent quand la rangée est pleine.
- **Buffs manquants** : hors combat, des icônes rondes en haut de l'anneau pour les buffs de classe et enchantements d'arme absents (affichage seul, non cliquable).
- **Clic sur les arcs** : clic gauche pour cibler, clic droit pour le menu de l'unité, survol pour l'infobulle - sur tes arcs, ceux de la cible et son nom.
- **Cadres d'unité** : deux options pour masquer le cadre du joueur et celui de la cible (Blizzard et TomoModForever).
- **Cible de la cible** : son nom et un filet de vie au-dessus du nom de la cible ; passe à « TOI » dans la couleur de combat quand la cible se tourne vers toi.
- **Familier** : deux arcs plus fins à l'intérieur des tiens, vie à gauche et ressource à droite ; ils s'ouvrent à l'invocation et sont cliquables comme les autres.
- **Hors combat** : le halo s'estompe et respire, quelques braises dorées montent lentement. Il se réveille tout seul si tu cibles un ennemi ou s'il te manque de la vie.
- **Entrée en combat** : onde de choc, deux lames, les arcs claquent en place, les braises s'emballent, les bords de l'écran chauffent.
- **Vie basse** : les bords de l'écran battent en rouge, l'arc de vie rougeoie.
- **Sortie de combat** : onde qui se referme, puis une carte de récap (durée, XP gagnée, combats restants avant le niveau).
- **Montée de niveau** : rayons, double onde, grand chiffre, fontaine de braises.
- **4 thèmes** : Braise, Givre, Sève et Classe. Le thème Classe donne à chaque classe sa palette (repos, combat) pour les anneaux, l'arc d'incantation, les ondes et les braises. Quel que soit le thème, les braises peuvent bouger à la façon de la classe (étincelles du guerrier, feuilles du druide, statique du chaman...).

## Installation

Copier le dossier `Braise` dans `Interface\AddOns\` du client Forever.

## Commandes

| Commande | Effet |
|---|---|
| `/braise` | ouvrir les réglages |
| `/braise test` | jouer un combat de démonstration |
| `/braise level` | jouer l'animation de niveau |
| `/braise move` | mode déplacement : une poignée par élément, plus une au centre pour tout le HUD |
| `/braise reset` | réglages par défaut |

## Fichiers

- `Core.lua` - réglages, thèmes, moteur de tweens, état de combat, suivi d'XP
- `Fx.lua` - braises, bords d'écran, ondes, montée de niveau
- `Halo.lua` - arcs du joueur et de la cible, anneaux, chrono, carte de récap, déplacement
- `Signs.lua` - arcs d'incantation, points de combo, buffs manquants
- `Options.lua` - panneau de réglages
- `Media/` - textures (générées pour l'addon) et police Poppins (OFL)
