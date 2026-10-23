class_name LoadingTips
## Lines for the match loading screen: half lore, half how the game works.
## Keep the gameplay ones true to the rules (see Defs / the Codex).

const TIPS := [
	"Inhibitor shots EMP their target: its shields drop for 5 seconds and block nothing until they return.",
	"Strike while an enemy's shields flicker -- an EMP'd ship takes every hit straight to armor and hull.",
	"A world's minerals are finite. Mine its crust down to nothing and the planet implodes; pause mining from the world panel.",
	"Spice Extractors drain a planet's reserve: rich on barren worlds, scarce on lush ones.",
	"In a Blackout, mines, farms and extractors fall to a quarter of their output. Keep energy flowing.",
	"Scouts see deep into spice nebulae and through ion storms, and can drop a sensor beacon that watches a spot for 90 s.",
	"Tenders repair nearby ships once they are out of combat -- and only tenders restore armor.",
	"Carriers launch drones that hunt any enemy within 300. Needle point-defense answers by shooting incoming ordnance down.",
	"Spice nebulae and the zone around a star bathe ships in Radiation. Heatshields turn it into energy and a shared shield bubble.",
	"Touching Heatshield bubbles merge into one pooled shield that guards every friendly ship and world inside.",
	"Warp Gates carry fleets across the map. Guard yours: a captured gate is a door left open.",
	"Frontier Outposts push your reach toward the map's edge. Their guns share your weapon-range research.",
	"Harvesters ferry minerals home load by load. Research makes them faster, roomier, even armored.",
	"Gas Skimmers mine gas giants and nebulae -- wealth that other ships can't touch.",
	"Each ship class has its own shape: a corvette is always an A, a destroyer a Y. Marks show rank, not class.",
	"Prediction-aimed guns lead moving targets. Without it, fast corvettes slip through slow fire.",
	"Damage pierces shields first, then armor, then hull. Pick weapons for the layer you need to break.",
	"Mods change how a gun behaves: chain lightning, bursting shells, beams that pull their target in.",
	"Upkeep grows with every ship and building. Trim your empire before your energy runs dry.",
	"Colonies grow population, and population multiplies a world's output. Feed them and they will build your war.",
	"Starbases build your fleets and anchor your empire. Never leave one bare.",
	"Ion storms drift across their systems and hide what moves inside. Scouts see through them.",
	"Before the Matrix, the stars were silent. Now every sun sings with the hum of war-forges.",
	"The old charts call the edge of the map the Verge: where light thins and outposts keep the last watch.",
	"Legend says the first Aegis was a shield the size of a moon, raised by a single dying fleet.",
	"Pilots say a starbase silhouetted against its sun is the last thing a raider ever sees.",
]

static func random_tip() -> String:
	return TIPS[randi() % TIPS.size()]
